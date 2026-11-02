# ==============================================================================
# provider.tf - Provedores do Terraform para AWS, Criptografia e Arquivos Locais
# Projeto Integrador: Capacita Computação em Nuvem
# ==============================================================================

terraform {
  # Versão mínima recomendada do Terraform CLI
  required_version = ">= 1.5.0"

  required_providers {
    # Provedor oficial da AWS para gerenciamento de recursos de nuvem
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    # Provedor TLS para geração automatizada do par de chaves SSH RSA
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Provedor Local para gravação segura do arquivo de chave privada (.pem) no disco
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Configuração do provedor AWS
provider "aws" {
  region = var.aws_region

  # Tags padrão aplicadas automaticamente a todos os recursos criados por este projeto
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Course      = "Capacita-Computacao-em-Nuvem"
    }
  }
}
