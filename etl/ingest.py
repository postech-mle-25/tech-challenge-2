import os
import time
import logging
from datetime import datetime
from dotenv import load_dotenv
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.chrome.service import Service
from io import StringIO, BytesIO
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import boto3

# Carregar variáveis de ambiente
load_dotenv()

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(funcName)s:%(lineno)d - %(message)s",
    handlers=[logging.StreamHandler()]
)

def webscraping_b3_csv():
    """
    Faz webscraping do site da B3 para baixar dados do IBOVESPA
    Retorna o caminho do arquivo baixado
    """
    logging.info("Iniciando Chrome WebDriver...")
    
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    
    logging.info("Navegando para o site da B3...")
    
    temp_download_path = os.path.join(os.getcwd(), "temp_downloads")
    os.makedirs(temp_download_path, exist_ok=True)
    
    prefs = {
        "download.default_directory": temp_download_path,
        "download.prompt_for_download": False,
        "download.directory_upgrade": True,
        "safebrowsing.enabled": True
    }
    chrome_options.add_experimental_option("prefs", prefs)
    
    try:
        # Usar ChromeDriverManager para gerenciar o driver automaticamente
        service = Service(ChromeDriverManager().install())
        driver = webdriver.Chrome(service=service, options=chrome_options)
        
        url = "https://sistemaswebb3-listados.b3.com.br/indexPage/day/IBOV?language=pt-br"
        driver.get(url)
        
        logging.info("Aguardando carregamento da página...")
        time.sleep(10)
        
        # Encontrar o link de download
        download_links = driver.find_elements(By.XPATH, "//a[contains(text(), 'Download')]")
        
        if not download_links:
            logging.error("Link de download não encontrado na página")
            return None
            
        logging.info("Link de download encontrado, iniciando download...")
        
        # Verificar arquivos antes do download
        files_before = set(os.listdir(temp_download_path)) if os.path.exists(temp_download_path) else set()
        
        # Clicar no link de download
        driver.execute_script("arguments[0].click();", download_links[0])
        
        # Aguardar download completar
        timeout = 60
        start_time = time.time()
        downloaded_file = None
        
        while time.time() - start_time < timeout:
            files_after = set(os.listdir(temp_download_path))
            new_files = files_after - files_before
            
            # Filtrar arquivos temporários
            complete_files = [f for f in new_files if not f.endswith((".crdownload", ".tmp", ".part"))]
            
            if complete_files:
                downloaded_file = complete_files[0]
                file_path = os.path.join(temp_download_path, downloaded_file)
                
                # Verificar se o arquivo existe e tem conteúdo
                if os.path.exists(file_path) and os.path.getsize(file_path) > 0:
                    logging.info(f"Download concluído: {downloaded_file}")
                    break
                    
            time.sleep(2)
        
        if not downloaded_file:
            logging.error("Timeout: arquivo não foi baixado completamente")
            return None
            
        return os.path.join(temp_download_path, downloaded_file)
        
    except Exception as e:
        logging.error(f"Erro durante webscraping: {e}")
        return None
    finally:
        if 'driver' in locals():
            driver.quit()

def processar_csv_para_parquet(csv_path):
    """
    Processa arquivo CSV e converte para formato Parquet em memória
    Retorna buffer com dados Parquet
    """
    if not os.path.exists(csv_path):
        logging.error(f"Arquivo CSV não encontrado: {csv_path}")
        return None
        
    logging.info(f"Processando arquivo CSV: {csv_path}")
    
    # Tentar diferentes encodings
    encodings = ['utf-8', 'latin-1', 'cp1252', 'iso-8859-1']
    csv_content = None
    
    for encoding in encodings:
        try:
            with open(csv_path, 'r', encoding=encoding) as file:
                csv_content = file.read()
            logging.info(f"Arquivo lido com encoding: {encoding}")
            break
        except UnicodeDecodeError:
            logging.warning(f"Falha ao ler com encoding {encoding}")
            continue
    
    if csv_content is None:
        logging.error("Não foi possível ler o arquivo com nenhum encoding testado")
        return None
    
    try:
        # Processar CSV com pandas
        df = pd.read_csv(StringIO(csv_content), sep=';', engine='python', skiprows=1)
        logging.info(f"DataFrame criado com {len(df)} linhas e {len(df.columns)} colunas")
        
        # Converter para Arrow Table
        table = pa.Table.from_pandas(df, preserve_index=False)
        
        # Criar buffer Parquet em memória
        parquet_buffer = BytesIO()
        pq.write_table(table, parquet_buffer)
        
        logging.info("Conversão para Parquet concluída")
        return parquet_buffer
        
    except Exception as e:
        logging.error(f"Erro ao processar CSV: {e}")
        return None

def upload_s3_parquet(parquet_buffer):
    """
    Faz upload do buffer Parquet para o S3
    """
    bucket_name = os.getenv('S3_BUCKET_NAME', 'fiap-2025-tech02-b3-glue')
    
    try:
        s3 = boto3.client('s3')
        
        # Gerar chave com particionamento por data
        data = datetime.now()
        particao = data.strftime('%Y%m%d')
        parquet_key = f"raw/dt_particao={particao}/IBOV_{data.strftime('%Y-%m-%d')}.parquet"
        
        # Upload para S3
        s3.put_object(
            Bucket=bucket_name,
            Key=parquet_key,
            Body=parquet_buffer.getvalue(),
            ContentType='application/octet-stream'
        )
        
        logging.info(f"Upload concluído: s3://{bucket_name}/{parquet_key}")
        return True
        
    except Exception as e:
        logging.error(f"Erro no upload S3: {e}")
        return False

def limpar_arquivos_temporarios():
    """
    Remove arquivos temporários de download
    """
    temp_path = os.path.join(os.getcwd(), "temp_downloads")
    
    if os.path.exists(temp_path):
        try:
            for arquivo in os.listdir(temp_path):
                arquivo_path = os.path.join(temp_path, arquivo)
                if os.path.isfile(arquivo_path):
                    os.remove(arquivo_path)
                    logging.info(f"Arquivo temporário removido: {arquivo}")
            
            os.rmdir(temp_path)
            logging.info("Diretório temporário removido")
            
        except Exception as e:
            logging.warning(f"Erro ao limpar arquivos temporários: {e}")

def main():
    """
    Função principal do pipeline ETL
    """
    logging.info("Executando processo ETL completo da B3 para S3 (processamento em memória)...")
    
    try:
        # 1. Webscraping e download
        csv_path = webscraping_b3_csv()
        if not csv_path:
            logging.error("Falha no webscraping")
            return False
        
        # 2. Processamento em memória
        parquet_buffer = processar_csv_para_parquet(csv_path)
        if not parquet_buffer:
            logging.error("Falha no processamento do CSV")
            return False
        
        # 3. Upload para S3
        success = upload_s3_parquet(parquet_buffer)
        if not success:
            logging.error("Falha no upload para S3")
            return False
        
        logging.info("✅ Pipeline ETL concluído com sucesso!")
        return True
        
    except Exception as e:
        logging.error(f"Erro no pipeline ETL: {e}")
        return False
    
    finally:
        # 4. Limpeza
        limpar_arquivos_temporarios()

if __name__ == "__main__":
    success = main()
    print("✅ Pipeline ETL concluído com sucesso!" if success else "❌ Pipeline ETL falhou. Verifique os logs.")
