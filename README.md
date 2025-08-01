# Tech Challenge 2 - Pipeline de Dados B3
## Objetivo
O objetivo deste projeto é criar um pipeline completo de dados para ingestão, processamento e análise de dados do IBOVESPA (Índice Bovespa) da B3 (Brasil, Bolsa, Balcão), utilizando tecnologias modernas de nuvem AWS.
## Arquitetura
Este projeto implementa uma arquitetura serverless na AWS para processamento automatizado de dados financeiros da B3, seguindo as melhores práticas de Data Engineering com foco em:

- **Ingestão automatizada** de dados da B3
- **Processamento em lote** usando AWS Glue
- **Armazenamento escalável** no Amazon S3
- **Orquestração serverless** com AWS Lambda
- **Infraestrutura como código** com Terraform

### Componentes da Arquitetura

#### 1. ETL (Extract, Transform, Load)
**Localização**: `tech-challenge-2/etl/`

- **ingest.py**: Script principal de ingestão que utiliza Selenium para fazer web scraping da página da B3, baixa dados do IBOVESPA em formato CSV, converte para Parquet e armazena no S3 na pasta `raw/`
- **lambda_function.py**: Função Lambda que é disparada quando novos arquivos são carregados no S3, iniciando automaticamente o job do AWS Glue para processamento.
- **b3-visual-etl.py**: Script do AWS Glue (gerenciado via Terraform) que processa dados da pasta raw/, aplica transformações (filtro, renomeação de colunas, cálculo de data, agregação) e salva na pasta `refined/` com particionamento por dt_particao e codigo.
- **b3-visual-etl.json.tmpl**: Template para configuração visual do Glue (opcional, gerado via Terraform para referência).
- **visualize.py**: Script opcional para gerar um gráfico de barras a partir dos resultados do Athena.

#### 2. Infraestrutura (Infrastructure as Code)
**Localização**: `tech-challenge-2/infra/`

- **main.tf**: Definição da infraestrutura AWS usando Terraform, incluindo:
  - Bucket S3 para armazenamento de dados brutos e refinados.
  - Função Lambda para orquestração.
  - Job Glue para processamento.
  - Banco de dados no Glue Catalog para catalogação.
  - IAM roles e policies necessárias.
  - Upload automático do código Lambda, Glue script e JSON de configuração.


- **variables.tf**: Variáveis de configuração, incluindo o ID da conta AWS (account_id) centralizado.
- **b3-visual-etl.json.tmpl**: Template para gerar a configuração visual do Glue com o ID da conta AWS.

### Fluxo de Dados

1. **Ingestão**: O script `ingest.py`acessa a página da B3, baixa os dados do IBOVESPA e os armazena em formato Parquet no S3 (s3://fiap-2025-tech02-b3-glue-<account_id>/raw/dt_particao=YYYYMMDD/).
2. **Trigger**: A adição de novos arquivos na pasta `raw/` do S3 dispara automaticamente a função Lambda.
3. **Processamento**: A Lambda inicia um job do AWS Glue que:
   - Lê os dados da pasta raw/.
   - Filtra tipos válidos (ON, PN, PNA, PNB, UNT).
   - Renomeia colunas (Código → codigo, Ação → acao).
   - Limpa Qtde. Teórica (remove pontos, converte para bigint).
   - Calcula diferença de datas (dias_desde_pregao).
   - Realiza agregação (contagem distinta de ações por tipo).
   - Salva dados refinados na pasta refined/ com particionamento por dt_particao e codigo.
   - Cataloga a tabela no Glue Catalog (b3_database.b3_refined).


4. **Armazenamento e Consulta**: 
- Dados refinados ficam disponíveis em s3://fiap-2025-tech02-b3-glue-<account_id>/refined/ e são queryáveis no Athena.
- Visualização (Opcional): Resultados podem ser consultados no Athena e visualizados como gráficos usando visualize.py.

### Tecnologias Utilizadas

- **AWS S3**: Armazenamento de dados (Data Lake).
- **AWS Glue**: Processamento serverless de dados.
- **AWS Lambda**: Orquestração e triggers.
AWS Athena: Consultas SQL nos dados catalogados.
- **Terraform**: Infrastructure as Code (IaC)
- **Python**: Linguagem principal
- **Selenium**: Web scraping
- **Pandas**: Manipulação de dados
- **PyArrow**: Conversão para formato Parquet
- **Boto3**: SDK da AWS para Python
- **Matplotlib**: Visualização de dados (opcional).


### Vantagens da Arquitetura

- **Serverless**: Sem necessidade de gerenciar servidores
- **Escalável**: Processa dados de qualquer volume automaticamente
- **Custo-efetivo**: Paga apenas pelo que usar
- **Resiliente**: Componentes gerenciados pela AWS
- **Observável**: Logs integrados ao CloudWatch

## Pré-requisitos

### Ferramentas Necessárias
- **Python 3.9+**
- **Terraform 1.0+**
- **AWS CLI** configurado com credenciais válidas
- **Google Chrome** (para web scraping)
- **ChromeDriver** compatível com a versão do Chrome

### Credenciais AWS
Configure suas credenciais AWS usando uma das opções:
#### Opção 1: AWS CLI

```bash
aws configure
```

#### Opção 2: Variáveis de ambiente

```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

## Configuração Centralizada de Conta AWS
O ID da conta AWS (ex.: 119268833495) está centralizado em infra/variables.tf na variável account_id. Para alterar a conta em todo o projeto:

- Edite o default de **account_id** em `infra/variables.tf`.
- Execute `terraform apply` para propagar as alterações nos recursos AWS (bucket, ARNs, scripts).
- Exporte a variável de ambiente para ingest.py:
```
export AWS_ACCOUNT_ID=$(cd infra && terraform output -raw account_id)
```

## Instalando o Ambiente

#### Opção 1: Via pip + requirements
- Crie um arquivo requirements.txt com:

```
python-dotenv==1.0.1
selenium==4.23.1
webdriver-manager==4.0.2
pandas==2.2.2
pyarrow==17.0.0
boto3==1.35.5
matplotlib==3.9.2
```

- Instala as dependências Python listadas em requirements.txt
```
pip install -r requirements.txt
```
#### Opção 2: Via conda

- Crie o ambiente a partir do arquivo environment.yml:

```bash
conda env create -f environment.yml
conda activate tc1
```

## Configuração e Deploy

### 1. Deploy da Infraestrutura

```bash
# Navegar para o diretório de infraestrutura
cd infra/

# Inicializa o Terraform, baixando os provedores necessários
terraform init

# Visualiza o plano de execução para verificar os recursos que serão criados ou alterados
terraform plan

# Aplica a configuração Terraform, criando ou atualizando os recursos AWS
terraform apply

### 2. Configuração das Variáveis
As principais variáveis estão em `infra/variables.tf`:

- `aws_region`: Região AWS (padrão: us-east-1)
- `account_id`: ID da conta AWS (padrão: 119268833495)
- `bucket_name_prefix`: Prefixo do bucket S3 (padrão: fiap-2025-tech02-b3-glue)
- `environment`: Ambiente (padrão: Academy)

# Exporta o ID da conta AWS do Terraform para uso no ingest.py
export AWS_ACCOUNT_ID=$(cd ../infra && terraform output -raw account_id)
```

## Executando o Pipeline

### Execução Manual da Ingestão

```bash
# Navega para o diretório ETL onde estão os scripts Python
cd etl/

# Executa o script de ingestão que faz web scraping da B3 e salva dados em S3 raw
python ingest.py
```

### Monitoramento

```bash
# Baixa o arquivo Parquet bruto do S3 para verificar localmente
aws s3 cp s3://fiap-2025-tech02-b3-glue-${AWS_ACCOUNT_ID}/raw/dt_particao=YYYYMMDD/IBOV_YYYY-MM-DD.parquet ./IBOV.parquet --region us-east-1
# Lê o arquivo Parquet e exibe os valores únicos da coluna 'Tipo' para verificar a integridade dos dados
python -c "import pandas as pd; df = pd.read_parquet('IBOV.parquet'); print(df['Tipo'].unique())"

# Inicia manualmente o job Glue (opcional, já que o Lambda dispara automaticamente)
aws glue start-job-run --job-name b3-visual-etl --region us-east-1

# Verifica o status de um job Glue específico, substituindo <ID_DO_JOB> pelo ID retornado pelo comando start-job-run
aws glue get-job-run --job-name b3-visual-etl --run-id <ID_DO_JOB> --region us-east-1
# Filtra eventos de log do grupo de logs do Glue para verificar erros ou detalhes da execução nas últimas 1 hora
aws logs filter-log-events --log-group-name /aws-glue/jobs/output --region us-east-1 --start-time $(date -u -d "-1 hour" +%s)000

# Lista os arquivos na pasta refined do S3 para verificar se os dados processados foram gerados
aws s3 ls s3://fiap-2025-tech02-b3-glue-${AWS_ACCOUNT_ID}/refined/ --region us-east-1
# Filtra eventos de log do grupo de logs do Lambda para verificar detalhes da execução nas últimas 1 hora
aws logs filter-log-events --log-group-name /aws/lambda/b3-glue-trigger --region us-east-1 --start-time $(date -u -d "-1 hour" +%s)000
```

### Visualização (Opcional)


1. Execute a consulta no Athena Query Editor para gerar dados para visualização:
```sql
SELECT Tipo, COUNT(DISTINCT codigo) as num_acoes
FROM b3_database.b3_refined
WHERE dt_particao='20250731' #YYYYMMDD
GROUP BY Tipo;
```


2. Exporte o resultado como CSV (ex.: `b3_visualization.csv`) e salve em `etl/`.
Gere o gráfico com `visualize.py`:
```bash
# Gera um gráfico de barras a partir dos resultados do Athena
python visualize.py
```


## Estrutura do Projeto

```
tech-challenge-2/
├── etl/                    # Scripts de ETL
│   ├── ingest.py          # Script principal de ingestão B3
│   ├── lambda_function.py # Trigger Lambda para Glue
│   ├── visualize.py       # Script para visualização local dos dados (opcional)
├── infra/                 # Infraestrutura como código
│   ├── main.tf           # Recursos Terraform
│   ├── variables.tf      # Variáveis de configuração
│   ├── b3-visual-etl.json.tmpl # Template para configuração Glue
├── downloads/            # Arquivos baixados localmente
├── requirements.txt      # Dependências Python
├── environment.yml       # Ambiente conda
├── architecture.png      # Diagrama da arquitetura
├── b3_visualization.png  # Gráfico gerado (opcional)
├── tech_challenge.mp4    # Vídeo de explicação do projeto
└── README.md            # Este arquivo
```

## Dados Processados

### Estrutura no S3

```
s3://fiap-2025-tech02-b3-glue-<account_id>/
├── raw/                           # Dados brutos
│   └── dt_particao=20250731/
│       └── IBOV_2025-07-31.parquet
├── refined/                      # Dados processados
│   └── dt_particao=20250731/
│       └── codigo=ALOS3/
│       └── codigo=ABEV3/
│       └── ...
├── temp/                         # Dados temporários (agregações)
│   └── agg/
└── scripts/                      # Scripts do Glue e Lambda
    ├── b3-visual-etl.py
    ├── b3-visual-etl.json
    └── glue_trigger.zip
```

### Formato dos Dados

- **Formato**: Apache Parquet (otimizado para analytics)
- **Particionamento**: Por data (raw/) e por data/código da ação (refined/)
- **Compressão**: Snappy (padrão do Parquet)
- **Schema**:
`Raw`: Código, Ação, Tipo, Qtde. Teórica, Part. (%)
`Refined`: acao, Tipo, qtde_teorica, Part. (%), dias_desde_pregao, dt_particao, codigo



## Troubleshooting

### Problemas Comuns

#### 1. Erro de Credenciais AWS
```
Error: operation error STS: GetCallerIdentity, https response error StatusCode: 403
```
**Solução**: Verifique se as credenciais AWS estão configuradas corretamente.

#### 2. ChromeDriver não encontrado
```
WebDriverException: 'chromedriver' executable needs to be in PATH
```
**Solução**: Instale o ChromeDriver e adicione ao PATH, ou use o ChromeDriver Manager:
```bash
pip install webdriver-manager
```

#### 3. Timeout no download da B3
```
Timeout: o arquivo não foi baixado completamente
```
**Solução**: Verifique a conexão com a internet e tente novamente. O site da B3 pode estar instável.

#### 4. Erro de permissões IAM
```
User is not authorized to perform: iam:CreateRole
```
**Solução**: Use uma role existente como `LabRole` ou solicite permissões administrativas.

#### 5. Erro de Bucket Name Inválido
```
Invalid bucket name "fiap-2025-tech02-b3-glue-{AWS_ACCOUNT_ID}"
```

**Solução**: Certifique-se de exportar AWS_ACCOUNT_ID antes de executar ingest.py:
```
export AWS_ACCOUNT_ID=$(cd infra && terraform output -raw account_id)
```

#### 6. Arquivo ingest.py não encontrado
```
python: can't open file '/.../infra/ingest.py': [Errno 2] No such file or directory
```

**Solução**: Execute python ingest.py a partir do diretório etl/:
```
cd etl/
python ingest.py
```

## Limpeza dos Recursos

Para evitar custos desnecessários, sempre destrua os recursos quando não precisar mais:

```bash
cd infra/
terraform destroy
```
