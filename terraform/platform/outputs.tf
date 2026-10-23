output "vpc_id" {
  description = "VPC for the lab's future services."
  value       = aws_vpc.lab.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per Availability Zone."
  value       = [for key in ["az_a", "az_b"] : aws_subnet.public[key].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per Availability Zone."
  value       = [for key in ["az_a", "az_b"] : aws_subnet.private[key].id]
}

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "eks_node_group_names" {
  description = "Managed node groups, each pinned to one private subnet/AZ."
  value       = { for az in ["az_a", "az_b"] : az => "${local.name}-eks-${az}" }
}

output "load_balancer_controller_role_arn" {
  description = "Pod Identity role for the AWS Load Balancer Controller."
  value       = aws_iam_role.load_balancer_controller.arn
}

output "docmost_checkr_hosted_zone_id" {
  description = "Route 53 public hosted zone ID for docmost-checkr.nakamalabs.io."
  value       = aws_route53_zone.docmost_checkr.zone_id
}

output "docmost_checkr_name_servers" {
  description = "Name servers to delegate docmost-checkr.nakamalabs.io to Route 53."
  value       = aws_route53_zone.docmost_checkr.name_servers
}

output "docmost_hostname" {
  description = "HTTPS hostname routed to the Docmost ALB."
  value       = local.docmost_hostname
}

output "docmost_certificate_arn" {
  description = "Validated ACM certificate ARN for the Docmost ALB HTTPS listener."
  value       = aws_acm_certificate_validation.docmost.certificate_arn
}

output "docmost_cognito_user_pool_arn" {
  description = "Cognito user pool ARN for the Docmost Ingress authentication action."
  value       = aws_cognito_user_pool.docmost_access.arn
}

output "docmost_cognito_client_id" {
  description = "Cognito app client ID for the Docmost Ingress authentication action."
  value       = aws_cognito_user_pool_client.docmost_access.id
}

output "docmost_cognito_domain_prefix" {
  description = "Cognito domain prefix for the Docmost Ingress authentication action."
  value       = aws_cognito_user_pool_domain.docmost_access.domain
}
