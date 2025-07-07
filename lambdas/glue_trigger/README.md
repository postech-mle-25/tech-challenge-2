## glue_trigger

### Lambda config

- Linguagem: Python 3.13
- Role: LabRole
- Variáveis de Ambiente:
  - "JOB_NAME": {nome do job do glue}
- Triggers:
  - S3 (Source): Quando um novo arquivo é adicionado na pasta desejada, o lambda é ativado
    - Configurar bucket, Event types (s3:ObjectCreated:*) e prefix (pasta dos arquivos que acionam o lambda)
- Opcional: Configurar memória e timeout nas configurações gerais