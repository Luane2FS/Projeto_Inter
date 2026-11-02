# ==============================================================================
# variables.tf - Definição de Variáveis Parametrizadas
# Projeto Integrador: Capacita Computação em Nuvem
# ==============================================================================

variable "aws_region" {
  description = "Região da AWS onde a infraestrutura será provisionada (ex: us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome base do projeto para prefixo e tags de identificação dos recursos"
  type        = string
  default     = "projeto-inter-capacita"
}

variable "environment" {
  description = "Identificador do ambiente de implantação (ex: dev, test, prod)"
  type        = string
  default     = "prod"
}

# ------------------------------------------------------------------------------
# Parâmetros de Rede (VPC e Sub-rede)
# ------------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Bloco de endereçamento CIDR da VPC (exigência do projeto: 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bloco CIDR da sub-rede pública (exigência do projeto: 10.0.1.0/24)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Zona de Disponibilidade (AZ) para alocação da sub-rede pública"
  type        = string
  default     = "us-east-1a"
}

# ------------------------------------------------------------------------------
# Parâmetros Computacionais (EC2 e Chaves SSH)
# ------------------------------------------------------------------------------

variable "instance_type" {
  description = "Tipo da instância EC2 (Free Tier: t3.micro em us-east-1)"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "ID específico da AMI Amazon Linux 2 (opcional conforme slide 6; se vazio, busca automaticamente a AMI mais recente)"
  type        = string
  default     = ""
}

variable "admin_ssh_ip" {
  description = "Endereço IPv4 válido do administrador com máscara /32 para restringir acesso SSH (obtido via: curl -4 ifconfig.me)"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_ssh_ip)) && endswith(var.admin_ssh_ip, "/32")
    error_message = "Por segurança, 'admin_ssh_ip' deve ser um IPv4 válido com máscara /32 (ex: 187.78.167.114/32)."
  }
}

variable "create_ssh_key" {
  description = "Se true, o Terraform gera automaticamente um novo par de chaves RSA 2048 e salva o arquivo .pem localmente"
  type        = bool
  default     = true
}

variable "existing_key_name" {
  description = "Nome de um Key Pair já existente no console da AWS (usado se create_ssh_key for false)"
  type        = string
  default     = ""
}

# ------------------------------------------------------------------------------
# Parâmetros da Aplicação e Deploy
# ------------------------------------------------------------------------------

variable "github_repo_url" {
  description = "URL do repositório Git para clonagem da aplicação no provisionamento automatizado"
  type        = string
  default     = "https://github.com/Luane2FS/Projeto_Inter.git"
}

variable "app_port" {
  description = "Porta HTTP em que a API SaaS responde"
  type        = number
  default     = 3000
}
