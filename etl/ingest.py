import boto3
import os
import time
import logging
from datetime import datetime
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from io import StringIO, BytesIO
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)

def scrape_b3_ibov_to_s3_parquet():
    bucket_name = "fiap-2025-tech02-b3-glue"
    s3 = boto3.client("s3")
    
    data = datetime.now()
    particao = f"{data.strftime('%Y%m%d')}"
    parquet_key = f"raw/dt_particao={particao}/IBOV_{data.strftime('%Y-%m-%d')}.parquet"
    
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    
    temp_download_path = os.path.join(os.getcwd(), "temp_download")
    os.makedirs(temp_download_path, exist_ok=True)
    
    prefs = {
        "download.default_directory": temp_download_path,
        "download.prompt_for_download": False,
        "download.directory_upgrade": True
    }
    chrome_options.add_experimental_option("prefs", prefs)
    
    page_url = "https://sistemaswebb3-listados.b3.com.br/indexPage/day/IBOV?language=pt-br"
    
    try:
        driver = webdriver.Chrome(options=chrome_options)
        logging.info("Acessando página da B3...")
        driver.get(page_url)
        time.sleep(10)
        
        download_links = driver.find_elements(By.XPATH, "//a[contains(text(), 'Download')]")
        if not download_links:
            logging.warning("Link de download não encontrado.")
            return False
        
        logging.info("Link de download encontrado.")
        files_before = set(os.listdir(temp_download_path))
        driver.execute_script("arguments[0].click();", download_links[0])
        logging.info("Clique no link de download executado.")
        
        timeout = 60
        start_time = time.time()
        downloaded_file = None
        
        while time.time() - start_time < timeout:
            files_after = set(os.listdir(temp_download_path))
            new_files = files_after - files_before
            
            # Filtrar arquivos temporários e incompletos
            complete_files = [f for f in new_files if not f.endswith((".crdownload", ".tmp", ".part"))]
            
            if complete_files:
                downloaded_file = complete_files[0]
                file_path = os.path.join(temp_download_path, downloaded_file)
                
                # Verificar se o arquivo realmente existe e tem tamanho > 0
                if os.path.exists(file_path) and os.path.getsize(file_path) > 0:
                    logging.info(f"Arquivo baixado: {downloaded_file}")
                    break
                else:
                    logging.warning(f"Arquivo {downloaded_file} existe mas está vazio ou inacessível")
                    
            time.sleep(2)
        
        if not downloaded_file:
            logging.error("Timeout: o arquivo não foi baixado completamente.")
            logging.info(f"Arquivos encontrados no diretório: {os.listdir(temp_download_path)}")
            return False
        
        file_path = os.path.join(temp_download_path, downloaded_file)
        
        # Verificar se o arquivo ainda existe antes de processá-lo
        if not os.path.exists(file_path):
            logging.error(f"Arquivo {file_path} não encontrado após o download")
            return False
            
        logging.info(f"Processando arquivo: {file_path} (tamanho: {os.path.getsize(file_path)} bytes)")
        
        encodings = ['utf-8', 'latin-1', 'cp1252', 'iso-8859-1']
        csv_content = None
        
        for encoding in encodings:
            try:
                with open(file_path, 'r', encoding=encoding) as file:
                    csv_content = file.read()
                logging.info(f"Arquivo lido com sucesso usando codificação: {encoding}")
                break
            except UnicodeDecodeError:
                logging.warning(f"Falha ao ler com codificação {encoding}")
        
        if csv_content is None:
            logging.error("Não foi possível ler o arquivo com nenhuma codificação testada")
            return False
        
        df = pd.read_csv(StringIO(csv_content), sep=';', engine='python', skiprows=1)
        table = pa.Table.from_pandas(df, preserve_index=False)
        parquet_buffer = BytesIO()
        pq.write_table(table, parquet_buffer)
        
        s3.put_object(
            Bucket=bucket_name,
            Key=parquet_key,
            Body=parquet_buffer.getvalue(),
            ContentType='application/octet-stream'
        )
        
        logging.info(f"Arquivo Parquet enviado para s3://{bucket_name}/{parquet_key}")
        
        # Limpar arquivo baixado
        if os.path.exists(file_path):
            os.remove(file_path)
            logging.info(f"Arquivo temporário removido: {file_path}")
            
        # Remover diretório temporário se estiver vazio
        if os.path.exists(temp_download_path) and not os.listdir(temp_download_path):
            os.rmdir(temp_download_path)
            logging.info("Diretório temporário removido")
            
        return True
        
    except Exception as e:
        logging.error(f"Erro durante o processo: {e}")
        return False
    finally:
        if 'driver' in locals():
            driver.quit()
        
        # Limpeza robusta do diretório temporário
        if os.path.exists(temp_download_path):
            try:
                for file in os.listdir(temp_download_path):
                    file_path = os.path.join(temp_download_path, file)
                    if os.path.isfile(file_path):
                        os.remove(file_path)
                        logging.info(f"Arquivo removido na limpeza: {file}")
                os.rmdir(temp_download_path)
                logging.info("Diretório temporário removido na limpeza")
            except Exception as cleanup_error:
                logging.warning(f"Erro durante limpeza: {cleanup_error}")

if __name__ == "__main__":
    success = scrape_b3_ibov_to_s3_parquet()
    print("Processo concluído com sucesso!" if success else "Processo falhou. Verifique os logs.")
