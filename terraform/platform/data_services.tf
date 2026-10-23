# These security groups grant the application nodes access to the data layer.
# The EKS module's primary cluster security group is attached to managed node
# groups for control-plane/data-plane communication. This is node-level access,
# not pod-specific isolation.
module "docmost_postgres_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-docmost-postgres"
  description = "PostgreSQL access from the EKS managed nodes"
  vpc_id      = aws_vpc.lab.id

  # Exclusive rules remove the AWS-created default allow-all egress rule.
  # Database responses use the stateful ingress connection.
  egress_rules = {}

  ingress_rules = {
    eks_nodes = {
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.eks.cluster_primary_security_group_id
      description                  = "PostgreSQL from EKS managed nodes"
    }
  }

  tags = {
    Project   = local.name
    ManagedBy = "Terraform"
  }
}

module "docmost_valkey_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-docmost-valkey"
  description = "Valkey access from the EKS managed nodes"
  vpc_id      = aws_vpc.lab.id

  # Exclusive rules remove the AWS-created default allow-all egress rule.
  # Cache responses use the stateful ingress connection.
  egress_rules = {}

  ingress_rules = {
    eks_nodes = {
      from_port                    = 6379
      to_port                      = 6379
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.eks.cluster_primary_security_group_id
      description                  = "Valkey from EKS managed nodes"
    }
  }

  tags = {
    Project   = local.name
    ManagedBy = "Terraform"
  }
}

module "docmost_postgres" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.2"

  identifier = "${local.name}-docmost"

  engine                = "postgres"
  engine_version        = "16.15"
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  storage_type          = "gp3"
  max_allocated_storage = 0

  db_name  = "docmost"
  username = "docmost_admin"
  port     = 5432

  # Let RDS generate and maintain the master password in Secrets Manager.
  # The secret ARN is exposed as an output for later application wiring.
  manage_master_user_password = true

  create_db_subnet_group = true
  subnet_ids             = [for az in ["az_a", "az_b"] : aws_subnet.private[az].id]
  vpc_security_group_ids = [module.docmost_postgres_security_group.id]

  publicly_accessible     = false
  multi_az                = false
  storage_encrypted       = true
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  apply_immediately       = true

  # RDS PostgreSQL 15+ defaults rds.force_ssl to 1; the pinned 16.15 engine
  # therefore rejects non-TLS client connections without a custom group.
  create_db_parameter_group = false
  create_db_option_group    = false

  tags = {
    Project   = local.name
    ManagedBy = "Terraform"
    Service   = "Docmost"
  }
}

module "docmost_valkey" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.11.1"

  replication_group_id = "${local.name}-docmost"
  description          = "Docmost Valkey cache for the learning lab"

  engine         = "valkey"
  engine_version = "7.2"
  node_type      = "cache.t4g.micro"

  # A single node limits lab cost. It has no replica or automatic failover.
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false
  cluster_mode_enabled       = false

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.docmost_valkey_auth_token
  auth_token_update_strategy = "ROTATE"

  create_security_group    = false
  security_group_ids       = [module.docmost_valkey_security_group.id]
  create_subnet_group      = true
  subnet_group_name        = "${local.name}-docmost"
  subnet_group_description = "Private subnets for Docmost Valkey"
  subnet_ids               = [for az in ["az_a", "az_b"] : aws_subnet.private[az].id]
  vpc_id                   = aws_vpc.lab.id

  apply_immediately          = true
  auto_minor_version_upgrade = true
  snapshot_retention_limit   = 0

  tags = {
    Project   = local.name
    ManagedBy = "Terraform"
    Service   = "Docmost"
  }
}
