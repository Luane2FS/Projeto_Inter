# Relatório Técnico: Arquitetura em Nuvem para Aplicação SaaS Multitenant

**Projeto Integrador: Residência em TIC 20 / Capacita Computação em Nuvem**  
**Alunos:** Luane F. e Lucas F.  
**Orientadores / Professores:** Allberson Dantas e Homero  
**Repositório Oficial:** [https://github.com/Luane2FS/Projeto_Inter](https://github.com/Luane2FS/Projeto_Inter)  

---

## Resumo Executivo

Este relatório apresenta o projeto arquitetural, a conteinerização e a estratégia de implantação em nuvem de uma aplicação **SaaS (Software as a Service) Multitenant** desenvolvida em Node.js (Express 5) e MongoDB 8. A infraestrutura de hospedagem foi automatizada via **Terraform (Infraestrutura como Código - IaC)** sobre a plataforma **Amazon Web Services (AWS)**, utilizando contêineres **Docker** e **Docker Compose** para isolamento de serviços, portabilidade e persistência em blocos EBS.

O documento descreve a fundamentação teórica para a escolha do modelo de serviço, detalha a topologia de rede virtual (VPC, sub-redes e grupos de segurança), mapeia a Matriz de Responsabilidade Compartilhada e analisa os desafios e estratégias para garantir escalabilidade, elasticidade e alta disponibilidade em ambientes de produção.

---

## 1. Planejamento da Arquitetura e Modelos de Serviço em Nuvem

### 1.1. Justificativa da Escolha do Modelo de Serviço

A computação em nuvem estrutura-se em diferentes modelos de serviço (IaaS, PaaS, SaaS e XaaS), variando conforme o nível de controle e abstração delegado ao provedor de nuvem:

| Modelo | Nível de Controle | Responsabilidade da Equipe | Aderência ao Projeto |
| :--- | :--- | :--- | :--- |
| **SaaS** | Consumo direto | Nenhuma sobre a infraestrutura da nuvem | É o **produto entregue** aos clientes finais (tenants), mas não o modelo de infraestrutura utilizado para hospedagem. |
| **PaaS** | Plataforma gerenciada | Gerenciamento apenas de código e dados | Reduz o controle sobre a topologia de rede e os custos em cenários com banco de dados próprio acoplado. |
| **IaaS + CaaS** *(Adotado)* | Controle total de SO e rede com contêineres | Configuração de VPC, firewall, sistema operacional e orquestração de contêineres | **Modelo escolhido**: Permite automação completa via Terraform, isolamento estrito de portas e cumprimento dos requisitos da disciplina. |

A solução foi estruturada no modelo **IaaS (Infrastructure as a Service)** na AWS, complementada por **CaaS (Containers as a Service)** localmente na máquina virtual:
1. **Infraestrutura IaaS (AWS)**: Uma Virtual Private Cloud (VPC) com sub-rede pública, Internet Gateway, tabela de rotas e firewall virtual (Security Group) provisiona o ambiente isolado onde opera uma máquina virtual EC2 `t3.micro` (Amazon Linux 2).
2. **Camada CaaS (Docker & Docker Compose)**: Dentro da EC2, o Docker isola o processo da API e do MongoDB em uma rede bridge privada interna, eliminando a dependência do sistema operacional hospedeiro e garantindo empacotamento imutável.
3. **Produto SaaS**: Para os usuários externos e empresas contratantes, a solução é oferecida como um software sob demanda multitenant com controle de cotas (`freemium` e `premium`), isolamento lógico de dados e autenticação baseada em tokens JWT.

---

## 2. Componentes Arquiteturais e Topologia de Nuvem

### 2.1. Diagrama de Arquitetura

```
+---------------------------------------------------------------------------------------+
|                                    AWS CLOUD (us-east-1)                              |
|                                                                                       |
|   +-------------------------------------------------------------------------------+   |
|   |                       VPC: 10.0.0.0/16 (enable_dns_hostnames = true)          |   |
|   |                                                                               |   |
|   |   +-----------------------------------+   +-------------------------------+   |   |
|   |   |     Internet Gateway (IGW)        |   |   Tabela de Rotas Pública     |   |   |
|   |   |   Conexão bidirecional Internet   |<--|   0.0.0.0/0 -> Target: IGW    |   |   |
|   |   +-----------------------------------+   +-------------------------------+   |   |
|   |                                                           |                   |   |
|   |   +-------------------------------------------------------v-------------------+   |
|   |   | Sub-rede Pública: 10.0.1.0/24 (us-east-1a, Auto-assign Public IP)          |   |
|   |   |                                                                           |   |
|   |   |   +-------------------------------------------------------------------+   |   |
|   |   |   | Security Group (Firewall Virtual)                                 |   |   |
|   |   |   | - Entrada SSH (Porta 22): Restrito exclusivamente ao IP do Admin  |   |   |
|   |   |   | - Entrada API (Porta 3000): Aberto publicamente para Clientes/API |   |   |
|   |   |   | - Saída (Egress): Irrestrita (0.0.0.0/0) para pacotes e contêineres|   |   |
|   |   |   +-------------------------------------------------------------------+   |   |
|   |   |                                           |                               |   |
|   |   |   +---------------------------------------v---------------------------+   |   |
|   |   |   | Instância EC2: t3.micro (Amazon Linux 2 x86_64)                   |   |   |
|   |   |   | Key Pair: RSA 2048 (gerado via Terraform tls_private_key)         |   |   |
|   |   |   | Provisionamento: user_data.sh.tftpl (Docker + Compose + Git Clone)|   |   |
|   |   |   |                                                                   |   |
|   |   |   |   +-----------------------------------------------------------+   |   |
|   |   |   |   | Docker Engine / Docker Compose                            |   |   |
|   |   |   |   |                                                           |   |   |
|   |   |   |   |   Rede Bridge Privada: saas-internal-network              |   |   |
|   |   |   |   |                                                           |   |   |
|   |   |   |   |   [ Contêiner: saas-api ] <=======> [ Contêiner: mongodb ]|   |   |
|   |   |   |   |   Node.js 22 Alpine (Porta 3000)    MongoDB 8.0 (127.0.0.1)  |   |   |
|   |   |   |   +-----------------------------------------------------------+   |   |
|   |   |   |                                                 |                 |   |   |
|   |   |   |   +---------------------------------------------v-------------+   |   |
|   |   |   |   | Volume EBS Persistente: /data/db (Volume saas-mongo-data) |   |   |
|   |   |   |   +-----------------------------------------------------------+   |   |
|   |   |   +-------------------------------------------------------------------+   |   |
|   |   +---------------------------------------------------------------------------+   |
|   +-------------------------------------------------------------------------------+   |
+---------------------------------------------------------------------------------------+
```

### 2.2. Detalhamento dos Componentes

1. **VPC e Roteamento**: Bloco CIDR `10.0.0.0/16` segmentado com sub-rede pública `10.0.1.0/24`. O tráfego de saída é governado por uma tabela de rotas associada diretamente ao Internet Gateway.
2. **Firewall e Segurança em Profundidade**:
   - A porta SSH (22) é restrita exclusivamente ao endereço IPv4 do administrador através da variável `admin_ssh_ip` com máscara `/32` (bloqueando tentativas de força bruta da internet).
   - A porta 3000 expõe a API RESTful de forma pública para chamadas do Postman ou clientes HTTP.
   - A porta do MongoDB (`27017`) **não é exposta externamente**, comunicando-se exclusivamente com a API através da rede bridge interna do Docker (`saas-internal-network`).
3. **Persistência de Dados**: O banco MongoDB utiliza um volume Docker nomeado (`saas-mongo-data`) mapeado no disco virtual EBS da EC2 (`/data/db`), garantindo que atualizações da aplicação ou reinicializações de contêiner não causem perda dos dados cadastrais dos locatários.

---

## 3. Matriz de Responsabilidade Compartilhada

A segurança e a operação na nuvem seguem o **Modelo de Responsabilidade Compartilhada da AWS**:

```
+-----------------------------------------------------------------------------+
|                     RESPONSABILIDADE DO CLIENTE / EQUIPE                    |
+-----------------------------------------------------------------------------+
| - Dados da aplicação, senhas criptografadas (bcrypt) e tokens JWT           |
| - Controle de acesso por papéis (RBAC admin vs member) e isolamento lógico  |
| - Configuração de firewall virtual (Security Groups e regras de porta)      |
| - Sistema Operacional convidado (Amazon Linux 2), patches e atualizações    |
| - Configuração dos contêineres Docker, Dockerfile e dependências Node.js    |
| - Gestão de segredos de ambiente (.env) e chave privada SSH (.pem)          |
+-----------------------------------------------------------------------------+
|                     RESPONSABILIDADE DA AWS (PROVEDOR)                      |
+-----------------------------------------------------------------------------+
| - Segurança física dos Data Centers (controles biométricos, energia, clima) |
| - Hardware dos servidores e armazenamento físico (discos EBS)               |
| - Virtualização (hipervisor Nitro / Xen) e infraestrutura de rede global   |
| - Disponibilidade da região us-east-1 e zonas de disponibilidade            |
+-----------------------------------------------------------------------------+
```

---

## 4. Conceitos Fundamentais Aplicados: Escalabilidade e Elasticidade

### 4.1. Escalabilidade Vertical vs. Escalabilidade Horizontal

- **Cenário Atual (Vertical)**: A infraestrutura inicial adotou a instância `t3.micro` (2 vCPUs, 1 GB RAM) elegível ao plano gratuito da AWS na região `us-east-1`. Para aumento de demanda em curto prazo, a escalabilidade vertical é obtida alterando a variável `instance_type` no Terraform para tipos superiores (ex: `t3.small` ou `t3.medium`).
- **Cenário de Produção (Horizontal)**: Para ambientes de grande porte, a arquitetura deve evoluir para múltiplas instâncias EC2 em sub-redes privadas distribuídas em diferentes Zonas de Disponibilidade (Multi-AZ), coordenadas por um **Auto Scaling Group (ASG)**.

### 4.2. Elasticidade e Automação

A elasticidade refere-se à capacidade do sistema de provisionar e desprovisionar recursos computacionais de forma automática acompanhando as variações de carga:
- No modelo de microsserviços em nuvem, o script [`user_data.sh.tftpl`](../terraform/scripts/user_data.sh.tftpl) garante elasticidade ao automatizar 100% da inicialização: qualquer nova instância criada pelo Terraform ou por um grupo de auto scaling baixa o código do GitHub, configura o ambiente Docker e inicia a API de forma autônoma sem intervenção humana.

### 4.3. Evolução Arquitetural Corporativa

Enquanto o protótipo acadêmico concentra-se em uma única instância EC2 para respeitar o teto do Free Tier, a transição para um ambiente corporativo de missão crítica contempla:
1. **Application Load Balancer (ALB)**: Ponto único de entrada em sub-rede pública com terminação TLS/HTTPS (porta 443) via certificado **AWS Certificate Manager (ACM)**.
2. **Instâncias em Sub-redes Privadas**: As máquinas da aplicação rodam sem IP público, acessando a internet apenas via **NAT Gateway** para atualizações.
3. **Banco de Dados Gerenciado**: Migração do MongoDB conteinerizado para o **Amazon DocumentDB** ou **MongoDB Atlas**, usufruindo de replicação nativa, backups contínuos e alta disponibilidade gerenciada pelo provedor.
4. **Gerenciamento Seguro de Segredos**: Substituição do arquivo local `.env` pelo **AWS Secrets Manager** ou **Systems Manager Parameter Store**, com rotação automática de chaves e criptografia KMS.

---

## 5. Conclusão

O projeto cumpriu integralmente os objetivos propostos nas Unidades 01, 04 e 05 do programa de capacitação:
1. Uma **aplicação SaaS multitenant robusta**, com modelos relacionais de plano, isolamento lógico e controle de taxas de requisição.
2. **Conteinerização eficiente via Docker Multi-Stage**, garantindo imagens enxutas e seguras em ambiente de produção.
3. **Provisionamento 100% reproduzível via Terraform**, criando a infraestrutura de rede e computação na AWS sem necessidade de cliques manuais no console.
4. **Alinhamento conceitual estrito**, fundamentando a entrega nos modelos de serviço IaaS, CaaS e SaaS, na matriz de responsabilidade compartilhada e nas boas práticas de segurança em nuvem.
