# ==============================================================================
# main.tf - Provisionamento da Infraestrutura AWS com Terraform (IaaS)
# Projeto Integrador: Capacita Computação em Nuvem
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Virtual Private Cloud (VPC)
# Cria a rede virtual isolada na nuvem AWS conforme exigência do projeto (10.0.0.0/16)
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ------------------------------------------------------------------------------
# 2. Internet Gateway (IGW)
# Ponto de conexão que permite o tráfego de entrada e saída entre a VPC e a Internet
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ------------------------------------------------------------------------------
# 3. Sub-rede Pública
# Segmento de rede da VPC com CIDR 10.0.1.0/24 configurado para atribuir IP público
# automático às instâncias criadas dentro dele
# ------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# ------------------------------------------------------------------------------
# 4. Tabela de Rotas e Associação
# Direciona todo o tráfego destinado à internet pública (0.0.0.0/0) para o IGW
# ------------------------------------------------------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associação obrigatória entre a sub-rede pública e a tabela de rotas com saída para internet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------------------------------------------------------------
# 5. Security Group (Firewall Virtual com Regras de Entrada e Saída)
# - Porta 22 (SSH): Restrito exclusivamente ao IP do administrador
# - Porta da API (var.app_port): Restrita ao IP administrativo por padrão para
#   mitigar o risco de tráfego HTTP em texto claro durante avaliações/testes
# - Portas 80 e 443: Habilitadas para terminação TLS / proxy reverso seguro
# - Saída irrestrita (Egress 0.0.0.0/0) para download de pacotes e contêineres Docker
# ------------------------------------------------------------------------------
locals {
  effective_api_ingress_cidr = var.api_ingress_cidr != "" ? var.api_ingress_cidr : var.admin_ssh_ip
}

resource "aws_security_group" "app_sg" {
  name        = "${var.project_name}-sg"
  description = "Security Group com acesso SSH restrito ao IP do admin e porta da API liberada"
  vpc_id      = aws_vpc.main.id

  # Regra de Entrada: SSH (Porta 22) restrita ao IP administrativo
  ingress {
    description = "Acesso SSH restrito ao IP do administrador"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_ip]
  }

  # Regra de Entrada: API SaaS Multitenant (Porta configurável via var.app_port)
  # Restrita ao IP administrativo para proteger credenciais e tokens em trânsito HTTP
  ingress {
    description = "Acesso a API SaaS Express restrito para mitigacao de HTTP em texto claro"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [local.effective_api_ingress_cidr]
  }

  # Regra de Entrada: HTTPS (Porta 443) - Pre-configurada para evolucao futura de terminacao TLS via ALB/ACM
  ingress {
    description = "HTTPS pre-configurado para futura terminacao TLS via ALB (prototipo opera em HTTP restrito)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.effective_api_ingress_cidr]
  }

  # Regra de Entrada: HTTP (Porta 80) - Pre-configurada para futuro redirecionamento TLS via ALB
  ingress {
    description = "HTTP pre-configurado para futuro redirecionamento TLS (prototipo opera em HTTP restrito)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.effective_api_ingress_cidr]
  }

  # Regra de Saida: Acesso irrestrito a internet para instalacao de pacotes e imagens Docker
  egress {
    description = "Saida irrestrita para comunicacao com a Internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ------------------------------------------------------------------------------
# 6. Geração Automatizada de Chave SSH (RSA 2048) e Key Pair
# Gera dinamicamente o par de chaves criptográficas para garantir acesso seguro via SSH
# ------------------------------------------------------------------------------
resource "tls_private_key" "ssh_key" {
  count     = var.create_ssh_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "generated_key" {
  count      = var.create_ssh_key ? 1 : 0
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh_key[0].public_key_openssh
}

# Grava localmente o arquivo de chave privada com extensão .pem para uso com comando ssh
resource "local_sensitive_file" "private_key_pem" {
  count           = var.create_ssh_key ? 1 : 0
  content         = tls_private_key.ssh_key[0].private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0600"
}

# ------------------------------------------------------------------------------
# 7. Resolução da AMI Oficial Amazon Linux 2023 (AL2023)
# Migração oficial do Amazon Linux 2 (cujo suporte terminou na AWS) para AL2023
# ------------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# 8. Volume EBS Persistente Desacoplado para Dados do MongoDB
# Mantém os dados preservados independentemente do ciclo de vida da instância EC2
# ------------------------------------------------------------------------------
resource "aws_ebs_volume" "mongo_data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.mongo_data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-mongo-data-ebs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_volume_attachment" "mongo_data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.app_server.id
}

# ------------------------------------------------------------------------------
# 9. Instância EC2 (Computação Virtual na Nuvem)
# Máquina t3.micro elegível ao Free Tier com provisionamento automatizado de Docker
# ------------------------------------------------------------------------------
resource "aws_instance" "app_server" {
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023[0].id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = true
  key_name                    = var.create_ssh_key ? aws_key_pair.generated_key[0].key_name : var.existing_key_name

  # Modo de créditos de CPU definido como standard para prevenir custos adicionais no Free Tier
  credit_specification {
    cpu_credits = "standard"
  }

  # Armazenamento em bloco para o sistema operacional AL2023
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root-ebs"
    }
  }

  # Script de inicialização (user_data) executado no boot para instalar Docker, Compose e rodar a aplicação
  user_data = templatefile("${path.module}/scripts/user_data.sh.tftpl", {
    github_repo_url = var.github_repo_url
    app_port        = var.app_port
    project_name    = var.project_name
  })

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-ec2-server"
  }
}
