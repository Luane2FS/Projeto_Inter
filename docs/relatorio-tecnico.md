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
1. **Infraestrutura IaaS (AWS)**: Uma Virtual Private Cloud (VPC) com sub-rede pública, Internet Gateway, tabela de rotas e firewall virtual (Security Group) provisiona o ambiente isolado onde opera uma máquina virtual EC2 `t3.micro` executando **Amazon Linux 2023 (AL2023)**, substituindo o legado Amazon Linux 2 (cujo suporte oficial encerrou em 2026).
2. **Camada CaaS (Docker & Docker Compose)**: Dentro da EC2, o Docker isola o processo da API e do MongoDB em uma rede bridge privada interna, eliminando a dependência do sistema operacional hospedeiro e garantindo empacotamento imutável.
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
|   |   |   |   | Docker Engine / Docker Compose                                    |   |   |
|   |   |   |   |                                                                   |   |   |
|   |   |   |   |   Rede Bridge Privada: saas-internal-network                      |   |   |
|   |   |   |   |                                                                   |   |   |
|   |   |   |   |   [ Contêiner: saas-api ] <=======> [ Contêiner: mongodb ]        |   |   |
|   |   |   |   |   Node.js 22 Alpine (Porta 3000)    MongoDB 8.0 (127.0.0.1)          |   |   |
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
   - Para evitar a exposição de credenciais (senhas e tokens JWT) a ataques de interceptação (*man-in-the-middle*) em redes públicas, o Security Group **não** deixa a porta HTTP aberta globalmente (`0.0.0.0/0`).
   - A variável `api_ingress_cidr` restringe por padrão o acesso da API e do SSH exclusivamente ao endereço IPv4 do administrador/avaliador (`var.admin_ssh_ip`), aplicando o princípio do menor privilégio.
   - Foram abertas regras para as portas 80 e 443, preparando a infraestrutura para terminação TLS.
3. **Persistência de Dados com EBS Desacoplado**:
   - Em vez de gravar dados do banco no disco raiz volátil da EC2, provisionou-se um **volume EBS independente** (`aws_ebs_volume.mongo_data`, 10 GB gp3 criptografado) anexado via `aws_volume_attachment`.
   - O script `user_data` detecta o volume secundário, formata-o com `ext4` na primeira inicialização, monta-o em `/mnt/mongo-data` e o vincula ao volume do Docker (`saas-mongo-data`).
   - **Garantia de sobrevivência**: Caso a instância EC2 seja recriada ou substituída (ex: atualização de `user_data`), o volume EBS desacoplado permanece intacto na AWS e é montado pela nova instância preservando 100% dos dados dos locatários.

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
| - Sistema Operacional convidado (Amazon Linux 2023 - AL2023), patches e dnf |
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
5. **Políticas de Backup e Retenção Automatizadas**: Implementação de ciclo de vida para o volume EBS desacoplado via **AWS Data Lifecycle Manager (DLM)** ou **AWS Backup**, realizando snapshots agendados automáticos (ex: diários com retenção de 30 dias) para recuperação de desastres (RPO/RTO).

---

## 5. Conclusão

O projeto cumpriu integralmente os objetivos propostos nas Unidades 01, 04 e 05 do programa de capacitação:
1. Uma **aplicação SaaS multitenant robusta**, com modelos relacionais de plano, isolamento lógico e controle de taxas de requisição.
2. **Conteinerização eficiente via Docker Multi-Stage**, garantindo imagens enxutas e seguras em ambiente de produção.
3. **Provisionamento 100% reproduzível via Terraform**, criando a infraestrutura de rede e computação na AWS sem necessidade de cliques manuais no console.
4. **Alinhamento conceitual estrito**, fundamentando a entrega nos modelos de serviço IaaS, CaaS e SaaS, na matriz de responsabilidade compartilhada e nas boas práticas de segurança em nuvem.
