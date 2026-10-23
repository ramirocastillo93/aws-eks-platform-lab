output "docmost_postgres_address" {
  description = "Private PostgreSQL hostname for Docmost configuration."
  value       = module.docmost_postgres.db_instance_address
}

output "docmost_postgres_port" {
  description = "PostgreSQL port for Docmost configuration."
  value       = module.docmost_postgres.db_instance_port
}

output "docmost_postgres_master_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed PostgreSQL master credentials."
  value       = module.docmost_postgres.db_instance_master_user_secret_arn
}

output "docmost_valkey_primary_endpoint" {
  description = "Private Valkey endpoint for Docmost configuration."
  value       = module.docmost_valkey.replication_group_primary_endpoint_address
}

output "docmost_valkey_port" {
  description = "Valkey port for Docmost configuration."
  value       = module.docmost_valkey.replication_group_port
}
