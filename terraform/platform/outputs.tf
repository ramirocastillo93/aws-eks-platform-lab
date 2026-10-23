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
