# Relatório de Atividade Prática: Provisionamento de Infraestrutura na AWS com Terraform (IaC)

**Curso:** Residência em TIC 20 — Capacita Computação em Nuvem  
**Atividade:** Projeto IaC com Terraform na AWS  
**Autora:** Luane Ferreira da Silva

---

## 1. Objetivo e Contexto

Esta atividade tem como objetivo automatizar o provisionamento de um ambiente de nuvem na **Amazon Web Services (AWS)** utilizando **Infraestrutura como Código (IaC)** por meio do **Terraform**. A abordagem declarativa elimina configurações manuais no painel da nuvem, assegurando padronização, auditabilidade e rápida replicação ou destruição do ambiente.

---

## 2. Organização do Projeto Terraform

O código-fonte da infraestrutura está localizado no diretório [`terraform/`](../terraform/) e segue a estrutura modular exigida pela especificação:

| Arquivo | Responsabilidade |
| :--- | :--- |
| [`provider.tf`](../terraform/provider.tf) | Define a versão mínima do Terraform (`>= 1.5.0`), os provedores oficiais (`hashicorp/aws`, `hashicorp/tls`, `hashicorp/local`) e as tags globais padrão. |
| [`variables.tf`](../terraform/variables.tf) | Declara variáveis parametrizadas com validações de CIDR (`vpc_cidr`, `public_subnet_cidr`, `admin_ssh_ip`, `instance_type`, `app_port`). |
| [`terraform.tfvars.example`](../terraform/terraform.tfvars.example) | Modelo de preenchimento das variáveis de ambiente (copiado para `terraform.tfvars` localmente com o IP `/32` do operador obtido via `curl -4 ifconfig.me`). |
| [`main.tf`](../terraform/main.tf) | Declara os 12 recursos de rede, segurança, chaves criptográficas, armazenamento EBS e computação EC2 comentados bloco a bloco. |
| [`outputs.tf`](../terraform/outputs.tf) | Expõe ao final do `apply` os IDs criados (VPC, Subnet, SG, EC2, EBS), o IP/DNS público, as URLs de *healthcheck* e o comando pronto de conexão SSH. |
| [`scripts/user_data.sh.tftpl`](../terraform/scripts/user_data.sh.tftpl) | Script de *bootstrapping* executado na inicialização da instância para instalar Docker, montar o volume EBS em `/mnt/mongo-data` e subir a aplicação. |

---

## 3. Recursos Provisionados e Decisões Técnicas

Todos os recursos solicitados na especificação foram provisionados na região `us-east-1`:

1. **Rede Virtual (`aws_vpc.main`)**: VPC dedicada com bloco CIDR `10.0.0.0/16`, suporte a DNS e *hostnames* públicos habilitados.
2. **Sub-rede Pública (`aws_subnet.public`)**: Sub-rede com CIDR `10.0.1.0/24` na zona `us-east-1a`, configurada com `map_public_ip_on_launch = true` para atribuição automática de IPv4 público.
3. **Conectividade à Internet (`aws_internet_gateway.gw`, `aws_route_table.public_rt`, `aws_route_table_association.public_assoc`)**: Internet Gateway anexado à VPC e tabela de rotas direcionando o tráfego `0.0.0.0/0` para o IGW, vinculada explicitamente à sub-rede pública.
4. **Firewall Virtual (`aws_security_group.app_sg`)**: Regra de entrada SSH (porta `22/tcp`) e da aplicação (porta `3000/tcp`) restritas exclusivamente ao bloco `/32` do IP público do aluno (`var.admin_ssh_ip`), aplicando o princípio do menor privilégio. Saída (`egress`) liberada (`0.0.0.0/0`) para download de pacotes e imagens.
5. **Par de Chaves SSH (`tls_private_key.ssh_key`, `aws_key_pair.generated_key`, `local_sensitive_file.private_key_pem`)**: Geração automatizada de chave RSA 2048 bits e gravação local do arquivo `.pem` com permissão restrita `0600`.
6. **Instância EC2 (`aws_instance.app_server`) e Armazenamento EBS (`aws_ebs_volume.mongo_data`)**:
   - **Adaptação Técnica Documentada (SO, Instância e Ressalvas de Custos/Free Tier)**: Em substituição à `t2.micro` e ao *Amazon Linux 2* (cujo suporte padrão encerrou na AWS), adotou-se a instância **`t3.micro`** e a imagem oficial mais recente do **Amazon Linux 2023 (AL2023)** obtida dinamicamente via `data "aws_ami"`. Conforme a [documentação oficial da AWS para EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html), a elegibilidade e o período do *AWS Free Tier* variam segundo o plano e a data de abertura da conta: contas criadas antes de 15 de julho de 2025 seguem as regras legadas de 12 meses (até 750 horas/mês), enquanto contas abertas a partir dessa data operam no modelo baseado em créditos (por até 6 meses no plano gratuito ou até os créditos se esgotarem). O parâmetro `cpu_credits = "standard"` evita cobranças extras por créditos de *burst* de CPU excedentes (padrão `unlimited` na família T3), mas não isenta todos os recursos de tarifação (como IPv4 público, armazenamento EBS, tráfego de rede ou consumo além da franquia/créditos).
   - **Persistência**: Volume EBS `gp3` criptografado de 10 GB anexado via `aws_volume_attachment` para preservar os dados do banco independentemente do ciclo de vida da instância EC2.

---

## 4. Ciclo de Execução e Validação Operacional

O fluxo completo de provisionamento e validação seguiu os passos abaixo, com os respectivos registros na pasta [`docs/evidencias/`](evidencias/):

1. **Descoberta do IP Público e Inicialização ([`terraform_init.txt`](evidencias/terraform_init.txt))**: Obtenção do IPv4 público via `curl -4 ifconfig.me` para configurar `admin_ssh_ip` no `terraform.tfvars` e inicialização dos provedores AWS, TLS e Local (`terraform init`).
2. **Plano de Execução e Provisionamento na Nuvem ([`terraform_apply.txt`](evidencias/terraform_apply.txt))**: Geração do plano declarativo dos 12 recursos (`Plan: 12 to add, 0 to change, 0 to destroy`) e criação efetiva na AWS (`12 added`), seguida de ajuste *in-place* (`1 changed`) do bloco CIDR administrativo no Security Group, mantendo a infraestrutura ativa para inspeção e testes e emitindo os `Outputs` (IDs, IP público e comando SSH).
3. **Validação de Acesso Remoto SSH ([`validacao_ssh.txt`](evidencias/validacao_ssh.txt))**: Conexão autenticada via chave privada RSA 2048 (`ssh -i ./terraform/projeto-inter-capacita-key.pem ec2-user@<IP_PUBLICO>`), comprovando a versão do sistema operacional Amazon Linux 2023 (`cat /etc/os-release`), `uptime`, montagem e permissão `0700` do volume EBS (`/mnt/mongo-data`), permissão restrita `0600` do arquivo `.env` (`ls -la` e `stat`) e contêineres saudáveis (`docker ps` e `/health`).
4. **Testes Ponta a Ponta e Procedimento de Encerramento ([`testes_api_ec2.txt`](evidencias/testes_api_ec2.txt))**: Execução aprovada dos 45 testes automatizados (`45/45`) contra o endpoint público da EC2 ativa. Concluídas as validações e capturas, o encerramento do ciclo de vida prevê a execução de `terraform destroy -auto-approve` para remover os recursos provisionados e interromper cobranças recorrentes.
