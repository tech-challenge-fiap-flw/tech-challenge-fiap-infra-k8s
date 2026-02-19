output "cluster_endpoint" {
  description = "Endpoint para o plano de controle do EKS"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "ID do grupo de segurança do cluster"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "Região AWS"
  value       = "us-east-1"
}

output "cluster_name" {
  description = "Nome do Cluster Kubernetes"
  value       = module.eks.cluster_name
}

output "sqs_os_events_url" {
  description = "URL da fila SQS OS Events"
  value       = aws_sqs_queue.os_events.url
}

output "sqs_billing_events_url" {
  description = "URL da fila SQS Billing Events"
  value       = aws_sqs_queue.billing_events.url
}

output "sqs_execution_events_url" {
  description = "URL da fila SQS Execution Events"
  value       = aws_sqs_queue.execution_events.url
}