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
