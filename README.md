# Projeto_Inter — Aplicação SaaS Multitenant & Infraestrutura AWS

Repositório oficial do Projeto Integrador do curso **Capacita — Computação em Nuvem**.

Este projeto integra o desenvolvimento de uma **API RESTful SaaS Multitenant** (Node.js + Express 5 + MongoDB), o empacotamento com **Docker e Docker Compose** e o provisionamento automatizado de infraestrutura na nuvem **AWS utilizando Terraform (IaaS)**.

---

## Sumário
- [Arquitetura Geral](#arquitetura-geral)
- [Estrutura do Repositório](#estrutura-do-repositório)
- [Requisitos](#requisitos)
- [Execução Local com Docker](#execução-local-com-docker)
- [Execução Manual / Desenvolvimento](#execução-manual--desenvolvimento-sem-docker)
- [Infraestrutura AWS com Terraform](#infraestrutura-aws-com-terraform)
- [Validação e Testes Automatizados](#validação-e-testes-automatizados)
- [Coleção Postman](#coleção-postman)
- [Relatório Técnico e Evidências](#relatório-técnico-e-evidências)
- [Integração Contínua (CI/CD)](#integração-contínua-cicd)
- [Execução no GitHub Codespaces](#execução-no-github-codespaces--dev-containers)
- [Principais Endpoints](#principais-endpoints)

---

## Arquitetura Geral

A solução adota uma estratégia em camadas para entrega de nuvem:

1. **Infraestrutura como Serviço (IaaS)**: Provisionamento automatizado via **Terraform** na AWS:
   - **Rede Virtual**: VPC dedicada (`10.0.0.0/16`), Sub-rede pública (`10.0.1.0/24`) na Zona de Disponibilidade `us-east-1a`, Internet Gateway e Tabela de Rotas com saída pública.
   - **Segurança de Borda**: Security Group aplicando o **princípio do menor privilégio** (`api_ingress_cidr`), restringindo acessos administrativos (SSH - porta 22) e da API (porta 3000) ao IP do operador por padrão. O protótipo acadêmico opera em protocolo HTTP, com as portas 443 e 80 pré-alocadas no Security Group para futura evolução com Application Load Balancer (ALB) e terminação TLS.
   - **Computação**: Instância EC2 **`t3.micro`** (2 vCPUs, 1 GB RAM com Amazon Linux 2023 - AL2023). A elegibilidade e a duração do [AWS Free Tier para EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) variam conforme o plano e a data de abertura da conta (regras legadas de 12 meses / 750h mensais para contas anteriores a 15/07/2025; oferta baseada em créditos por até 6 meses ou até o esgotamento dos créditos para contas novas). O modo `cpu_credits = "standard"` evita cobranças por créditos de CPU excedentes, mas não garante ausência total de custos em todos os recursos (ex.: IPv4 público, EBS ou consumo além dos créditos/franquias).
   - **Armazenamento Desacoplado**: Volume EBS independente de 10 GB (`gp3`, criptografado) com montagem automática fail-fast e permissões restritas `0700` (UID 999). Preserva dados entre reinicializações e substituições da instância EC2, exigindo snapshots periódicos (AWS Backup/DLM) para proteção definitiva contra desastres.
   - **Automação de Inicialização (Bootstrapping)**: Script `user_data.sh.tftpl` que instala Docker via `dnf`, monta o disco EBS persistente com validação estrita, gera credenciais fortes com permissão restrita `0600` para o `.env` e sobe os serviços sem intervenção manual.

2. **Conteinerização sobre IaaS**: **Docker e Docker Compose** executando os serviços sobre uma **topologia de redes em duas camadas**:
   - `saas-frontend-network` (bridge pública): comunica a porta de entrada da API (`saas-api`) com o host.
   - `saas-backend-network` (bridge com `internal: true`): conecta a API ao banco de dados (`saas-mongodb`), **sem gateway para a internet** e sem nenhuma porta exposta no host da EC2, isolando completamente o banco.
   - Volume Docker `saas-mongo-data` apontando diretamente para o ponto de montagem do volume EBS desacoplado (`/mnt/mongo-data`).

3. **Software como Serviço (SaaS)**: Aplicação multitenant desenvolvida em Node.js 22 e Express 5:
   - Modelos de planos `freemium` (até 3 usuários) e `premium` (usuários ilimitados).
   - Autenticação stateless via tokens JWT (`HS256`).
   - Controle de acesso baseado em papéis (**RBAC**: `admin` vs `member`).
   - Isolamento lógico estrito de dados por `tenantId` em todas as coleções.
   - Rate limiting distribuído (armazenado no MongoDB com fallback em memória) com suporte a cabeçalhos padrão IETF.
   - Probes de observabilidade (`/health`, `/health/live`, `/health/ready`).

---

## Estrutura do Repositório

```text
Projeto_Inter/
├── .devcontainer/                  # Ambiente de desenvolvimento em contêiner (Codespaces)
│   ├── devcontainer.json           # Configuração de extensões e ferramentas do VS Code
│   ├── docker-compose.yml          # Setup local de Node.js 22 + MongoDB 8 Replica Set
│   └── setup.js                    # Script de bootstrap do Codespace
├── .github/
│   ├── docker-compose.standalone.yml # MongoDB standalone para testes de contingência
│   └── workflows/
│       └── ci.yml                  # Pipeline CI: validação de Terraform e testes da API
├── docs/                           # Documentação e entregáveis do projeto
│   ├── relatorio-tecnico.md        # Relatório técnico completo de arquitetura e infraestrutura
│   ├── relatorio-iac-terraform.md  # Relatório específico (IaC com Terraform na AWS)
│   ├── OPERATIONS.md               # Procedimentos operacionais, backup e observabilidade
│   └── evidencias/                 # Logs reais de execução na nuvem AWS
│       ├── terraform_init.txt      # Inicialização dos provedores Terraform
│       ├── terraform_apply.txt     # Plano de execução e saída do provisionamento da EC2 t3.micro
│       ├── validacao_ssh.txt       # Sessão SSH comprovando AL2023, EBS e Docker
│       └── testes_api_ec2.txt      # Execução da suíte E2E (45/45) contra o IP público
├── postman/                        # Coleção Postman oficial da API
│   ├── README.md                   # Instruções de importação e variáveis de ambiente
│   └── SaaS-App.postman_collection.json # Coleção Postman v2.1
├── saas-app/                       # Código-fonte da aplicação SaaS
│   ├── controllers/                # Controladores HTTP (auth, tenants, users, plans)
│   ├── middleware/                 # Middlewares (auth JWT, RBAC, tenantContext, rateLimiter)
│   ├── models/                     # Modelos de dados e validações (Mongoose)
│   ├── routes/                     # Definições de rotas da API
│   ├── services/                   # Regras de negócio e transações ACID
│   ├── scripts/                    # Scripts utilitários (setup-env.js)
│   ├── Dockerfile                  # Empacotamento multi-stage seguro (Node 22 Alpine)
│   └── server.js                   # Ponto de entrada da aplicação Express
├── terraform/                      # Infraestrutura como Código (IaC) na AWS
│   ├── main.tf                     # Definição de VPC, Subnet, SG, EBS e EC2 (AL2023)
│   ├── variables.tf                # Variáveis parametrizadas (instance_type: t3.micro)
│   ├── outputs.tf                  # Saídas de infraestrutura (IPs, URLs de health e SSH)
│   ├── terraform.tfvars.example    # Modelo de variáveis (copie para terraform.tfvars)
│   └── scripts/
│       └── user_data.sh.tftpl      # Script de inicialização automatizada da instância
├── test-scripts/                   # Suíte de testes de ponta a ponta (E2E)
│   ├── run-all.js                  # Orquestrador consolidado de testes
│   ├── test-smoke.js               # Smoke test de rotas públicas e headers de segurança
│   ├── test-onboarding.js          # Fluxo de criação de tenant e registrationToken
│   ├── test-rbac.js                # Validação de permissões admin vs member
│   ├── test-isolation.js           # Garantia de isolamento cross-tenant
│   ├── test-concurrency.js         # Concorrência atômica sob limite de vagas
│   └── test-rate-limit.js          # Validação de Rate Limiting e HTTP 429
├── docker-compose.yml              # Orquestração da API e MongoDB em 2 redes
└── README.md                       # Documentação principal do projeto
```

---

## Requisitos

- **Git**
- **Node.js** `>= 20.19.0` e **npm**
- **Docker** e **Docker Compose**
- **Terraform** `>= 1.5.0`
- **AWS CLI v2** configurada (`aws configure`) com permissões para EC2, VPC e EBS

---

## Execução Local com Docker

1. Gere o segredo JWT no arquivo `saas-app/.env`:

```bash
cd saas-app
npm run setup:env
cd ..
```

2. Inicie os contêineres da aplicação e banco com o Compose:

```bash
docker compose --env-file saas-app/.env up -d --build
```

3. Verifique o status dos serviços e os healthchecks:

```bash
docker compose --env-file saas-app/.env ps

# Health check consolidado (status e dependências):
curl http://localhost:3000/health

# Liveness probe (processo HTTP ativo):
curl http://localhost:3000/health/live

# Readiness probe (conectividade MongoDB):
curl http://localhost:3000/health/ready
```

4. Para encerrar os serviços locais:

```bash
docker compose --env-file saas-app/.env down
```

---

## Execução Manual / Desenvolvimento (sem Docker)

1. Instale as dependências dentro da pasta `saas-app`:

```bash
cd saas-app
npm install
```

2. Configure o arquivo `saas-app/.env`:

```bash
npm run setup:env
```

3. Inicie o servidor:

```bash
npm start
```

---

## Infraestrutura AWS com Terraform

O diretório `terraform/` contém a automação completa da infraestrutura na nuvem AWS.

### Parâmetros Configuráveis (`terraform/variables.tf`)

* `aws_region`: Região da AWS (padrão: `us-east-1`).
* `instance_type`: Tipo de instância EC2 (padrão: **`t3.micro`** com 2 vCPUs e 1 GB RAM em substituição à `t2.micro`; a elegibilidade ao Free Tier varia conforme o plano e a data de criação da conta na AWS, e `cpu_credits = "standard"` limita cobranças por *burst* de CPU excedente sem isentar todos os recursos de custo).
* `ami_id`: AMI específica (padrão vazio: resolve automaticamente a AMI oficial mais recente do **Amazon Linux 2023**, adotado em substituição ao Amazon Linux 2 devido ao fim de suporte/EOL do AL2).
* `mongo_data_volume_size`: Tamanho em GB do volume EBS independente (padrão: `10` GB).
* `api_ingress_cidr`: CIDR permitido para acessar a API em HTTP (padrão restrito ao IP do operador `/32` para proteção do tráfego).

> **Nota sobre `terraform.tfvars`:** Por boas práticas de segurança (evitando expor o IP público `/32` do operador no controle de versão), `*.tfvars` consta no `.gitignore` e o repositório versiona o modelo [`terraform/terraform.tfvars.example`](terraform/terraform.tfvars.example).

### Passo a Passo de Provisionamento

1. Acesse o diretório do Terraform e configure seu arquivo `terraform.tfvars`:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edite admin_ssh_ip em terraform.tfvars com seu IPv4 público (ex.: "$(curl -4 -s ifconfig.me)/32")
```

2. Inicialize o Terraform para baixar os providers (`aws`, `tls`, `local`):

```bash
terraform init
```

3. Valide o plano de execução e os recursos a serem criados:

```bash
terraform plan
```

4. Aplique o provisionamento na nuvem AWS:

```bash
terraform apply -auto-approve
```

Ao final da execução, o Terraform exibirá os outputs com o endereço IP público da EC2, URLs de healthcheck e o comando de conexão SSH:

```text
Outputs:
api_endpoint           = "http://<IP_PUBLICO_EC2>:3000"
api_healthcheck_url    = "http://<IP_PUBLICO_EC2>:3000/health"
api_ingress_cidr       = "<SEU_IP_ADMIN>/32"
ec2_instance_id        = "<ID_DA_INSTANCIA_EC2>"
ec2_public_dns         = "<DNS_PUBLICO_EC2>"
ec2_public_ip          = "<IP_PUBLICO_EC2>"
mongo_data_volume_id   = "<ID_DO_VOLUME_EBS>"
ssh_connection_command = "ssh -i ./projeto-inter-capacita-key.pem ec2-user@<IP_PUBLICO_EC2>"
```

5. **Acesso Remoto via SSH**:
O par de chaves RSA 2048 é gerado dinamicamente e salvo localmente com permissão `0600`. Conecte-se à instância:

- **Se estiver dentro do diretório `terraform/`**:
  ```bash
  ssh -i projeto-inter-capacita-key.pem ec2-user@<IP_PUBLICO_EC2>
  ```
- **Se estiver no diretório raiz do projeto**:
  ```bash
  ssh -i terraform/projeto-inter-capacita-key.pem ec2-user@<IP_PUBLICO_EC2>
  ```

6. **Desprovisionamento (Limpeza de Recursos)**:
Após finalizar os testes e a avaliação, destrua toda a infraestrutura para evitar custos:

```bash
terraform destroy -auto-approve
```

---

## Validação e Testes Automatizados

O projeto conta com suíte de testes unitários e testes de ponta a ponta (E2E) que realizam chamadas HTTP reais:

```bash
# Executa testes unitários da aplicação:
cd saas-app
npm test

# Executa a suíte completa de 45 testes E2E:
node ../test-scripts/run-all.js
```

### Scripts de Teste Especializados (`test-scripts/`)

- **`test-smoke.js`**: Verifica rotas públicas, integridade do banco e headers de segurança nativos (`securityHeaders.js`).
- **`test-onboarding.js`**: Testa o fluxo de criação de tenant, ciclo de vida do `registrationToken` e bloqueio de planos pagos sem faturamento.
- **`test-rbac.js`**: Testa controle de acesso baseado em papéis (`admin` vs `member`), proteção contra autoexclusão do último admin e revogação imediata de token.
- **`test-isolation.js`**: Valida a impossibilidade de acesso cruzado a dados e usuários entre diferentes tenants.
- **`test-concurrency.js`**: Simula requisições simultâneas concorrentes para validar a consistência atômica de vagas no plano.
- **`test-rate-limit.js`**: Dispara requisições em rajada para validar proteção contra força bruta e resposta `HTTP 429 Too Many Requests`.

---

## Coleção Postman

A coleção oficial do Postman está versionada no diretório [`postman/`](postman/):

* **[`postman/SaaS-App.postman_collection.json`](postman/SaaS-App.postman_collection.json)**: Contém todas as requisições configuradas com parâmetros, corpos de exemplo e scripts de teste de resposta.
* **[`postman/README.md`](postman/README.md)**: Guia passo a passo de importação, variáveis de ambiente (`baseUrl`, `token`, `memberToken`, `tenantId`) e fluxos de teste.

---

## Relatório Técnico e Evidências

Toda a documentação técnica exigida pelo curso está consolidada na pasta `docs/`:

* **[Relatório Específico da Atividade IaC com Terraform (`docs/relatorio-iac-terraform.md`)](docs/relatorio-iac-terraform.md)**:
  - Relatório enxuto (1 a 2 páginas) detalhando a estrutura de arquivos (`.tf` / `.tfvars`), os recursos AWS provisionados e a validação de conectividade SSH.

* **[Relatório Técnico de Arquitetura e Infraestrutura (`docs/relatorio-tecnico.md`)](docs/relatorio-tecnico.md)**:
  - Análise dos modelos de serviço em nuvem (**SaaS hospedado em IaaS com Docker Compose**).
  - Diagrama de arquitetura em nuvem (VPC, AL2023 `t3.micro`, volume EBS independente, rede interna Docker).
  - Modelo de responsabilidade compartilhada para resiliência (*AWS vs. Cliente*).
  - Diferenciação entre **Bootstrapping** (`user_data`) e **Elasticidade** (Auto Scaling Group e métricas).
  - Dimensionamento, estimativa de custos e evolução para produção (ALB, HTTPS/TLS, MongoDB Atlas).

* **Evidências de Execução na AWS (`docs/evidencias/`)**:
  - [`terraform_init.txt`](docs/evidencias/terraform_init.txt): Sucesso na inicialização e download dos provedores.
  - [`terraform_apply.txt`](docs/evidencias/terraform_apply.txt): Geração do plano formal (`Plan: 12 to add`) e execução do `apply` com criação dos 12 recursos (instância EC2, rede e volume EBS).
  - [`validacao_ssh.txt`](docs/evidencias/validacao_ssh.txt): Comprovação de acesso SSH, kernel AL2023, montagem de `/mnt/mongo-data`, `.env` restrito e contêineres ativos.
  - [`testes_api_ec2.txt`](docs/evidencias/testes_api_ec2.txt): 45 de 45 passos aprovados executados diretamente contra a API pública na AWS.

---

## Integração Contínua (CI/CD)

O pipeline do GitHub Actions em [`.github/workflows/ci.yml`](.github/workflows/ci.yml) executa duas esteiras automáticas a cada push ou pull request:

1. **`terraform`**: Executa `terraform fmt -check` para garantir padronização de código e `terraform validate` para validar a sintaxe e integridade dos manifestos HCL.
2. **`test`**: Sobe um ambiente de contêiner com MongoDB em Replica Set, instala dependências e executa os testes unitários, de integração e os scripts E2E da API.

---

## Execução no GitHub Codespaces / Dev Containers

O repositório inclui suporte pronto para desenvolvimento em nuvem via `.devcontainer/`:

1. No GitHub, clique em **Code → Codespaces → Create codespace on main**.
2. O ambiente inicializa automaticamente com **Node.js 22** e **MongoDB 8.0** configurado como Replica Set `rs0` para testes locais com transações ACID.
3. No terminal do Codespace:

```bash
cd saas-app
npm test
npm start
```

---

## Principais Endpoints

| Método | Rota | Autenticação | Papel | Descrição |
| :--- | :--- | :---: | :---: | :--- |
| `GET` | `/health` | Pública | — | Status consolidado da API e integridade das dependências |
| `GET` | `/health/live` | Pública | — | Liveness probe: confirma que o processo da API está ativo |
| `GET` | `/health/ready` | Pública | — | Readiness probe: confirma que a API consegue consultar o MongoDB |
| `GET` | `/plans` | Pública | — | Lista os planos disponíveis cadastrados no MongoDB |
| `GET` | `/plans/:name` | Pública | — | Consulta detalhes de um plano específico |
| `POST` | `/tenants` | Pública (Rate Limited) | — | Cadastra tenant em plano gratuito e retorna token para o primeiro cadastro |
| `POST` | `/auth/register` | Pública (Rate Limited) | — | Registra o 1º usuário (`admin`) usando `tenantId` e `registrationToken` |
| `POST` | `/auth/login` | Pública (Rate Limited) | — | Autentica usuário ativo; aceita `tenantId` para distinguir contas |
| `GET` | `/tenants` | Bearer JWT | `admin`/`member` | Retorna o tenant do usuário autenticado |
| `GET` | `/tenants/:id` | Bearer JWT | `admin`/`member` | Consulta dados do próprio tenant |
| `PUT` / `PATCH` | `/tenants/:id` | Bearer JWT | `admin` | Atualiza dados do próprio tenant |
| `DELETE` | `/tenants/:id` | Bearer JWT | `admin` | Remove o tenant e todos os seus usuários |
| `GET` | `/tenants/:id/users` | Bearer JWT | `admin`/`member` | Lista usuários do próprio tenant (`?page=1&limit=50`) |
| `GET` | `/users` | Bearer JWT | `admin`/`member` | Lista usuários do próprio tenant (`?page=1&limit=50`) |
| `POST` | `/users` | Bearer JWT | `admin` | Cria novo usuário no tenant respeitando o limite atômico do plano |
| `GET` | `/users/:id` | Bearer JWT | `admin`/`member` | Consulta usuário do próprio tenant |
| `PUT` / `PATCH` | `/users/:id` | Bearer JWT | `admin` ou próprio usuário | Atualiza dados cadastrais/senha (alteração de `role` restrita a `admin`) |
| `DELETE` | `/users/:id` | Bearer JWT | `admin` | Remove usuário do tenant (bloqueia autoexclusão e remoção do único `admin`) |
