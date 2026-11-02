# ==============================================================================
# outputs.tf - Valores de Saída do Provisionamento Terraform
# Projeto Integrador: Capacita Computação em Nuvem
# ==============================================================================

output "vpc_id" {
  description = "Identificador exclusivo da VPC criada na AWS"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "Identificador da sub-rede pública"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "Identificador do Security Group com regras de firewall"
  value       = aws_security_group.app_sg.id
}

output "ec2_instance_id" {
  description = "Identificador da instância EC2 provisionada"
  value       = aws_instance.app_server.id
}

output "ec2_public_ip" {
  description = "Endereço IPv4 público atribuído à instância EC2"
  value       = aws_instance.app_server.public_ip
}

output "ec2_public_dns" {
  description = "Nome de domínio público (DNS) atribuído à instância EC2"
  value       = aws_instance.app_server.public_dns
}

output "ssh_connection_command" {
  description = "Comando pronto para conexão remota via SSH utilizando a chave privada gerada"
  value       = var.create_ssh_key ? "ssh -i ./terraform/${var.project_name}-key.pem ec2-user@${aws_instance.app_server.public_ip}" : "ssh -i <sua-chave>.pem ec2-user@${aws_instance.app_server.public_ip}"
}

output "api_endpoint" {
  description = "URL base da API SaaS para testes no Postman ou no navegador"
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}"
}

output "api_healthcheck_url" {
  description = "URL consolidada de verificação de integridade (Health Check: status e dependências)"
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}/health"
}

output "api_liveness_url" {
  description = "URL de verificação de liveness (processo HTTP ativo)"
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}/health/live"
}

output "api_readiness_url" {
  description = "URL de verificação de readiness (conectividade com banco MongoDB ativa)"
  value       = "http://${aws_instance.app_server.public_ip}:${var.app_port}/health/ready"
}
