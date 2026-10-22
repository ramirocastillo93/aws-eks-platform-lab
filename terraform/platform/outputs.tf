output "vpc_id" {
  description = "VPC for the lab's future services."
  value       = aws_vpc.lab.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per Availability Zone."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per Availability Zone."
  value       = aws_subnet.private[*].id
}
