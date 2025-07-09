# Tech Challenge 2 - Pipeline de Dados B3

## Objetivo
O objetivo deste projeto é criar um pipeline completo de dados para ingestão, processamento e análise de dados do **IBOVESPA (Índice Bovespa)** da B3 (Brasil, Bolsa, Balcão), utilizando tecnologias modernas de nuvem AWS.

## Arquitetura

Este projeto implementa uma arquitetura serverless na AWS para processamento automatizado de dados financeiros da B3, seguindo as melhores práticas de Data Engineering com foco em:

- **Ingestão automatizada** de dados da B3
- **Processamento em lote** usando AWS Glue
- **Armazenamento escalável** no Amazon S3
- **Orquestração serverless** com AWS Lambda
- **Infraestrutura como código** com Terraform

### Componentes da Arquitetura

#### 1. ETL (Extract, Transform, Load)
**Localização**: `tech-challenge-1/etl/`

- **ingest.py**: Script principal de ingestão que utiliza Selenium para fazer web scraping da página da B3, baixa dados do IBOVESPA em formato CSV, converte para Parquet e armazena no S3 na pasta `raw/`
- **lambda_function.py**: Função Lambda que é disparada quando novos arquivos são carregados no S3, iniciando automaticamente o job do AWS Glue para processamento
- **glue_job.py**: Script do AWS Glue responsável pelo processamento e transformação dos dados, movendo-os da pasta `raw/` para `processed/` com particionamento por ano/mês

#### 2. Infraestrutura (Infrastructure as Code)
**Localização**: `tech-challenge-1/infra/`

- **main.tf**: Definição da infraestrutura AWS usando Terraform, incluindo:
  - Bucket S3 para armazenamento de dados
  - Jobs do AWS Glue para processamento
  - Funções Lambda para orquestração
  - IAM roles e policies necessárias
- **variables.tf**: Variáveis de configuração da infraestrutura

### Fluxo de Dados

1. **Ingestão**: O script `ingest.py` acessa a página da B3, baixa os dados do IBOVESPA e os armazena em formato Parquet no S3 (`s3://bucket/raw/dt_particao=YYYYMMDD/`)

2. **Trigger**: A adição de novos arquivos na pasta `raw/` do S3 dispara automaticamente a função Lambda

3. **Processamento**: A Lambda inicia um job do AWS Glue que:
   - Lê os dados da pasta `raw/`
   - Aplica transformações e limpeza
   - Adiciona metadados (timestamp de processamento, qualidade dos dados)
   - Salva os dados processados na pasta `processed/` com particionamento

4. **Armazenamento**: Dados finais ficam disponíveis em `s3://bucket/processed/` organizados por ano/mês para consultas eficientes

### Tecnologias Utilizadas

- **AWS S3**: Armazenamento de dados (Data Lake)
- **AWS Glue**: Processamento serverless de dados
- **AWS Lambda**: Orquestração e triggers
- **Terraform**: Infrastructure as Code (IaC)
- **Python**: Linguagem principal
- **Selenium**: Web scraping
- **Pandas**: Manipulação de dados
- **PyArrow**: Conversão para formato Parquet
- **Boto3**: SDK da AWS para Python

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

```bash
# Opção 1: AWS CLI
aws configure

# Opção 2: Variáveis de ambiente
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

## Instalando o Ambiente

### Opção 1: Via pip + requirements

```bash
pip install -r requirements.txt
```

### Opção 2: Via conda

Crie o ambiente a partir do arquivo environment.yml:

```bash
conda env create -f environment.yml
conda activate tc1
```

## Configuração e Deploy

### 1. Deploy da Infraestrutura

```bash
# Navegar para o diretório de infraestrutura
cd infra/

# Inicializar Terraform
terraform init

# Visualizar o plano de execução
terraform plan

# Aplicar a infraestrutura
terraform apply
```

### 2. Configuração das Variáveis

As principais variáveis podem ser configuradas em `infra/variables.tf`:

- `aws_region`: Região AWS (padrão: us-east-1)
- `project_name`: Nome do projeto (padrão: fiap-2025-tech02)
- `bucket_name`: Nome do bucket S3 (padrão: b3-glue)
- `environment`: Ambiente (padrão: Academy)

## Executando o Pipeline

### Execução Manual da Ingestão

```bash
# Navegar para o diretório ETL
cd etl/

# Executar o script de ingestão
python ingest.py
```

### Monitoramento

- **CloudWatch Logs**: Visualize logs das execuções Lambda e Glue
- **S3 Console**: Monitore os arquivos nas pastas `raw/` e `processed/`
- **Glue Console**: Acompanhe a execução dos jobs de processamento

## Estrutura do Projeto

```
tech-challenge-2/
├── etl/                    # Scripts de ETL
│   ├── ingest.py          # Script principal de ingestão B3
│   ├── lambda_function.py # Trigger Lambda para Glue
│   └── glue_job.py       # Job de processamento Glue
├── infra/                 # Infraestrutura como código
│   ├── main.tf           # Recursos Terraform
│   └── variables.tf      # Variáveis de configuração
├── downloads/            # Arquivos baixados localmente
├── requirements.txt      # Dependências Python
├── environment.yml       # Ambiente conda
└── README.md            # Este arquivo
```

## Dados Processados

### Estrutura no S3

```
s3://fiap-2025-tech02-b3-glue/
├── raw/                           # Dados brutos
│   └── dt_particao=20250707/
│       └── IBOV_2025-07-07.parquet
├── processed/                     # Dados processados
│   └── year=2025/month=07/
│       └── data_files.parquet
└── scripts/                       # Scripts do Glue
    └── glue_job.py
```

### Formato dos Dados

- **Formato**: Apache Parquet (otimizado para analytics)
- **Particionamento**: Por data (raw) e ano/mês (processed)
- **Compressão**: Snappy (padrão do Parquet)
- **Schema**: Preservado do formato original da B3




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

## Limpeza dos Recursos

Para evitar custos desnecessários, sempre destrua os recursos quando não precisar mais:

```bash
cd infra/
terraform destroy
```
