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
| **IaaS com Docker Compose** *(Adotado)* | Controle total de SO e rede com contêineres | Configuração de VPC, firewall, sistema operacional e execução de contêineres | **Modelo escolhido**: Hospedagem IaaS autogerenciada na AWS, utilizando Docker Compose para isolamento e portabilidade da aplicação e do banco de dados. |

A solução foi estruturada como um **produto SaaS hospedado sobre infraestrutura IaaS (Infrastructure as a Service)** na AWS, utilizando **Docker e Docker Compose** para a conteinerização local:
1. **Infraestrutura IaaS (AWS)**: Uma Virtual Private Cloud (VPC) com sub-rede pública, Internet Gateway, tabela de rotas, volume EBS desacoplado e firewall virtual (Security Group) provisiona o ambiente básico de rede, computação e armazenamento onde opera uma máquina virtual EC2 `t3.micro` executando **Amazon Linux 2023 (AL2023)**.
2. **Conteinerização sobre IaaS (Docker & Docker Compose)**: O Docker Compose em uma EC2 autogerenciada não se caracteriza como uma plataforma gerenciada CaaS (como AWS ECS ou EKS, que delegam o plano de controle e a orquestração ao provedor). Trata-se de uma abordagem de conteinerização sobre IaaS, provendo imutabilidade de ambiente e isolamento em redes virtuais controladas.
3. **Produto SaaS**: Para os usuários externos e empresas contratantes, a solução é oferecida como um software sob demanda multitenant com controle de cotas (`freemium` e `premium`), isolamento lógico de dados e autenticação baseada em tokens JWT.

---

## 2. Componentes Arquiteturais e Topologia de Nuvem

### 2.1. Diagrama de Arquitetura

```
+-----------------------------------------------------------------------------------------------+
|                                     AWS CLOUD (us-east-1)                                     |
|                                                                                               |
|   +---------------------------------------------------------------------------------------+   |
|   |                       VPC: 10.0.0.0/16 (enable_dns_hostnames = true)                  |   |
|   |                                                                                       |   |
|   |   +-----------------------------------+   +---------------------------------------+   |   |
|   |   |     Internet Gateway (IGW)        |   |        Tabela de Rotas Pública        |   |   |
|   |   |   Conexão bidirecional Internet   |<--|        0.0.0.0/0 -> Target: IGW       |   |   |
|   |   +-----------------------------------+   +---------------------------------------+   |   |
|   |                                                           |                           |   |
|   |   +-------------------------------------------------------v---------------------------+   |
|   |   | Sub-rede Pública: 10.0.1.0/24 (us-east-1a, Auto-assign Public IP)                  |   |
|   |   |                                                                                   |   |
|   |   |   +---------------------------------------------------------------------------+   |   |
|   |   |   | Security Group (Firewall Virtual com Regras de Menor Privilégio)          |   |   |
|   |   |   | - Entrada SSH (Porta 22): Restrito exclusivamente ao IP do Admin (/32)    |   |   |
|   |   |   | - Entrada API (Porta 3000): Restrita ao IP Admin para evitar HTTP aberto   |   |   |
|   |   |   | - Entrada HTTPS (Porta 443) e HTTP (Porta 80): Habilitadas para TLS       |   |   |
|   |   |   | - Saída (Egress): Irrestrita (0.0.0.0/0) para pacotes e contêineres       |   |   |
|   |   |   +---------------------------------------------------------------------------+   |   |
|   |   |                                           |                                       |   |
|   |   |   +---------------------------------------v-----------------------------------+   |   |
|   |   |   | Instância EC2: t3.micro (Amazon Linux 2023 - AL2023 x86_64)               |   |   |
|   |   |   | Key Pair: RSA 2048 (gerado via Terraform tls_private_key)                 |   |   |
|   |   |   | Disco Raiz SO: 20 GB gp3 (delete_on_termination = true)                   |   |   |
|   |   |   | Provisionamento: user_data.sh.tftpl (dnf + Docker + Compose + Auto-Mount) |   |   |
|   |   |   |                                                                           |   |
|   |   |   |   +-------------------------------------------------------------------+   |   |
|   |   |   |   | Docker Engine / Docker Compose (Conteinerização sobre IaaS)       |   |   |
|   |   |   |   |                                                                   |   |   |
|   |   |   |   |   Rede Frontend (Bridge): saas-frontend-network                   |   |   |
|   |   |   |   |   [ Contêiner: saas-api ] (Node.js 22 Alpine - Porta 3000)        |   |   |
|   |   |   |   |          |                                                        |   |   |
|   |   |   |   |   Rede Backend (internal: true): saas-internal-backend-network    |   |   |
|   |   |   |   |   [ Contêiner: saas-mongodb ] (MongoDB 8.0 - Sem saída Internet)  |   |   |
|   |   |   |   +-------------------------------------------------------------------+   |   |
|   |   |   |                                                 |                         |   |   |
|   |   |   +-------------------------------------------------|-------------------------+   |   |
|   |   |                                                     |                             |   |
|   |   |   +-------------------------------------------------v-------------------------+   |   |
|   |   |   | Volume EBS Persistente Desacoplado: 10 GB gp3 (/mnt/mongo-data)          |   |   |
|   |   |   | Recurso: aws_ebs_volume.mongo_data + aws_volume_attachment                |   |   |
|   |   |   | CICLO DE VIDA INDEPENDENTE: Preserva dados se a EC2 for substituída       |   |   |
|   |   |   +---------------------------------------------------------------------------+   |   |
|   |   +-----------------------------------------------------------------------------------+   |
|   +---------------------------------------------------------------------------------------+   |
+-----------------------------------------------------------------------------------------------+
```

### 2.2. Detalhamento dos Componentes e Decisões de Segurança

1. **Migração para Amazon Linux 2023 (AL2023)**: O projeto migrou do Amazon Linux 2 (AL2) — cujo suporte oficial da AWS foi descontinuado em 2026 — para o **Amazon Linux 2023**, garantindo kernel 6.1+, gerenciamento moderno de pacotes com `dnf` e suporte a longo prazo da AWS.
2. **Mitigação de Tráfego HTTP em Texto Claro e Proteção de Credenciais**:
   - O protótipo acadêmico atual opera via protocolo **HTTP** na porta configurada (`var.app_port`). As portas 80 e 443 foram pré-configuradas no Security Group para preparar a infraestrutura para terminação TLS futura via Application Load Balancer (ALB) e certificados gerenciados pelo AWS Certificate Manager (ACM).
   - Para mitigar o risco de interceptação de credenciais e tokens em trânsito HTTP durante testes e avaliações, a variável `api_ingress_cidr` restringe por padrão o acesso da API e do SSH exclusivamente ao endereço IPv4 do operador (`var.admin_ssh_ip`), aplicando o princípio do menor privilégio e eliminando a exposição pública indiscriminada (`0.0.0.0/0`).
3. **Persistência de Dados com EBS Desacoplado e Princípio do Menor Privilégio**:
   - Em vez de gravar dados do banco no disco raiz volátil da EC2, provisionou-se um **volume EBS independente** (`aws_ebs_volume.mongo_data`, 10 GB gp3 criptografado) anexado via `aws_volume_attachment`.
   - O script `user_data` detecta o volume secundário, formata-o com `ext4` na primeira inicialização, monta-o em `/mnt/mongo-data`, restringe as permissões a `0700` com posse exclusiva do usuário do MongoDB (`chown -R 999:999`) e o vincula ao volume do Docker (`saas-mongo-data`).
   - **Fail-Fast de Inicialização**: O script aborta a inicialização com código de erro fatal (`exit 1`) caso o volume EBS não seja detectado no tempo limite, impedindo terminantemente que o banco seja inicializado no disco raiz efêmero da VM.
   - **Persistência vs. Backup**: O volume EBS independente garante que os dados dos locatários sobrevivam à reinicialização ou substituição da máquina virtual EC2. Contudo, **um volume EBS isolado não constitui por si só uma política de backup**, pois permanece vulnerável a falhas na Zona de Disponibilidade e é removido caso a infraestrutura seja destruída (`terraform destroy` com `final_snapshot = false`). Para resiliência corporativa, são necessários snapshots programados via AWS Backup/DLM ou replicação em banco de dados gerenciado.
4. **Isolamento de Rede em Duas Camadas no Docker Compose**:
   - Em vez de uma bridge única genérica, o `docker-compose.yml` estrutura a comunicação em duas redes independentes: `saas-frontend-network` (para recepção de tráfego na API) e `saas-backend-network` declarada com `internal: true`.
   - O contêiner do MongoDB conecta-se **exclusivamente** à rede `internal: true` sem mapear portas para a internet, eliminando qualquer rota padrão de gateway externo e assegurando isolamento estrito da camada de dados.

---

## 3. Matriz de Responsabilidade Compartilhada

A segurança, a operação e a resiliência na nuvem seguem o **Modelo de Responsabilidade Compartilhada da AWS**:

```
+-----------------------------------------------------------------------------------------+
|                          RESPONSABILIDADE DO CLIENTE / EQUIPE                           |
+-----------------------------------------------------------------------------------------+
| - Dados da aplicação, senhas criptografadas (bcrypt) e tokens JWT                       |
| - Controle de acesso por papéis (RBAC admin vs member) e isolamento lógico              |
| - Configuração de firewall virtual (Security Groups e regras de porta restritas)        |
| - Sistema Operacional convidado (Amazon Linux 2023 - AL2023), patches e dnf             |
| - Configuração dos contêineres Docker, Dockerfile e dependências Node.js                |
| - Gestão de segredos de ambiente (.env com chmod 600) e chave privada SSH (.pem)       |
| - Resiliência e Alta Disponibilidade da aplicação (decisão mono-AZ vs multi-AZ,         |
|   políticas de failover, backups e arquitetura de recuperação de desastres)             |
+-----------------------------------------------------------------------------------------+
|                           RESPONSABILIDADE DA AWS (PROVEDOR)                            |
+-----------------------------------------------------------------------------------------+
| - Segurança física dos Data Centers (controles biométricos, energia, climatização)     |
| - Hardware dos servidores e armazenamento físico (discos EBS)                           |
| - Virtualização (hipervisor Nitro) e infraestrutura de rede física global               |
| - Disponibilidade da infraestrutura física subjacente das Zonas e Regiões da AWS       |
+-----------------------------------------------------------------------------------------+
```

> [!NOTE]
> Conforme o whitepaper de *Shared Responsibility Model for Resiliency* da AWS, o provedor assegura a disponibilidade física dos componentes de infraestrutura, mas a resiliência da aplicação depende das decisões de arquitetura do cliente (como a distribuição de réplicas em múltiplas AZs e estratégias de contingência). A topologia atual, por operar em Zona de Disponibilidade única visando o Free Tier, concentra o risco operacional na resiliência da zona escolhida (`us-east-1a`).

---

## 4. Conceitos Fundamentais Aplicados: Escalabilidade e Elasticidade

### 4.1. Escalabilidade Vertical vs. Escalabilidade Horizontal

- **Cenário Atual (Vertical)**: A infraestrutura inicial adotou a instância `t3.micro` (2 vCPUs, 1 GB RAM). A elegibilidade ao AWS Free Tier (750 horas/mês) aplica-se a contas nos primeiros 12 meses de cadastro. Como as instâncias da família T3 operam por padrão no modo *unlimited* (o que pode acarretar custos adicionais caso o consumo de CPU supere a linha de base), a configuração do Terraform fixou explicitamente o modo de créditos como `standard` (`credit_specification { cpu_credits = "standard" }`). Para aumento de demanda em curto prazo, a escalabilidade vertical é obtida alterando a variável `instance_type` no Terraform para tipos superiores (ex: `t3.small` ou `t3.medium`), acarretando downtime planejado momentâneo para redimensionamento da máquina virtual.
- **Cenário de Produção (Horizontal)**: Para ambientes de grande porte, a arquitetura deve evoluir para múltiplas instâncias EC2 em sub-redes privadas distribuídas em diferentes Zonas de Disponibilidade (Multi-AZ), coordenadas por um **Auto Scaling Group (ASG)** e balanceadas por um Application Load Balancer.

### 4.2. Automação de Inicialização (Bootstrapping) vs. Elasticidade

É essencial diferenciar conceitualmente a **automação de inicialização** da **elasticidade**:
- **Automação de Inicialização (Bootstrapping)**: O script [`user_data.sh.tftpl`](../terraform/scripts/user_data.sh.tftpl) provê o bootstrapping completo e autônomo da máquina EC2 no momento da inicialização (instalação de pacotes via `dnf`, montagem automática do volume EBS independente, permissões restritas `0600` no `.env` e inicialização do Docker Compose). Essa automação elimina intervenções manuais na configuração da VM e serve como alicerce técnico obrigatório para provisionamentos escaláveis.
- **Elasticidade Real (Requisito Teórico de IaaS)**: Conforme o material de IaaS, a elasticidade é definida estritamente como a capacidade do sistema de expandir e contrair capacidade computacional de forma **automática e dinâmica em resposta às flutuações de demanda em tempo de execução**. Como a arquitetura acadêmica atual opera em uma **única instância EC2 em uma única AZ**, sem Auto Scaling Group nem políticas de ajuste orientadas por métricas do CloudWatch, a solução **não é elástica**. O dimensionamento atual é estático/manual, servindo o bootstrapping como pré-requisito para habilitar elasticidade em uma futura fase com ASG.

### 4.3. Evolução Arquitetural Corporativa

Enquanto o protótipo acadêmico concentra-se em uma única instância EC2 para respeitar o teto do Free Tier, a transição para um ambiente corporativo de missão crítica contempla:
1. **Application Load Balancer (ALB)**: Ponto único de entrada em sub-rede pública com terminação TLS/HTTPS (porta 443) via certificado **AWS Certificate Manager (ACM)**.
2. **Instâncias em Sub-redes Privadas**: As máquinas da aplicação rodam sem IP público, acessando a internet apenas via **NAT Gateway** para atualizações.
3. **Banco de Dados Gerenciado**: Migração do MongoDB conteinerizado para o **Amazon DocumentDB** ou **MongoDB Atlas**, usufruindo de replicação nativa, backups contínuos e alta disponibilidade gerenciada pelo provedor.
4. **Gerenciamento Seguro de Segredos**: Substituição do arquivo local `.env` pelo **AWS Secrets Manager** ou **Systems Manager Parameter Store**, com rotação automática de chaves e criptografia KMS.
5. **Políticas de Backup e Retenção Automatizadas**: Implementação de ciclo de vida para o volume EBS desacoplado via **AWS Data Lifecycle Manager (DLM)** ou **AWS Backup**, realizando snapshots agendados automáticos (ex: diários com retenção de 30 dias) para recuperação de desastres (RPO/RTO).

---

## 5. Conclusão

O projeto cumpriu integralmente os objetivos propostos nas Unidades 01, 04 e 05 do programa de capacitação:
1. Uma **aplicação SaaS multitenant robusta**, com modelos relacionais de plano, isolamento lógico e controle de taxas de requisição.
2. **Conteinerização eficiente via Docker Multi-Stage**, garantindo imagens enxutas e seguras em ambiente de produção.
3. **Provisionamento 100% reproduzível via Terraform**, criando a infraestrutura de rede e computação na AWS sem necessidade de cliques manuais no console.
4. **Alinhamento conceitual estrito**, fundamentando a entrega no modelo de serviço **SaaS hospedado em IaaS com conteinerização Docker Compose**, na matriz de responsabilidade compartilhada e nas boas práticas de segurança em nuvem.
