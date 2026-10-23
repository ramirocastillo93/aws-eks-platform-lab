data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_role" "eks_admin" {
  name = var.eks_admin_role_name
}

locals {
  eks_name = "${local.name}-eks"
  eks_node_group_subnets = {
    az_a = aws_subnet.private["az_a"].id
    az_b = aws_subnet.private["az_b"].id
  }
}

# Associate the VPC CNI with a dedicated Pod Identity role. Node roles retain
# CNI permissions for bootstrap because add-on readiness is not a dependency
# of managed node group creation in this module version.
resource "aws_iam_role" "vpc_cni" {
  name = "${local.eks_name}-vpc-cni"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnEquals    = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.eks_name}" }
      }
    }]
  })

  tags = { Project = local.name }
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Keep the Pod Identity association behind the CNI policy attachment without
# making every data source inside the EKS module wait until apply.
resource "terraform_data" "vpc_cni_role_ready" {
  input      = aws_iam_role.vpc_cni.arn
  depends_on = [aws_iam_role_policy_attachment.vpc_cni]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = local.eks_name
  kubernetes_version = "1.37"

  # Keep the same API-only authentication and admin access as the hand-written
  # cluster. The current public endpoint remains restricted to the operator IP.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  endpoint_private_access                  = true
  endpoint_public_access                   = true
  endpoint_public_access_cidrs             = var.eks_api_allowed_cidrs
  access_entries = {
    admin = {
      principal_arn = data.aws_iam_role.eks_admin.arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Do not create optional log groups or KMS keys as a side effect of adopting
  # the module. Those services can be added deliberately in a later change.
  enabled_log_types           = []
  create_cloudwatch_log_group = false
  create_kms_key              = false
  encryption_config           = null
  enable_irsa                 = false

  # Use the EKS-created primary security group, matching the previous layout.
  # This avoids additional security groups while retaining the cluster/node
  # connectivity managed by EKS.
  create_security_group      = false
  create_node_security_group = false

  vpc_id                   = aws_vpc.lab.id
  control_plane_subnet_ids = [for az in ["az_a", "az_b"] : aws_subnet.private[az].id]
  subnet_ids               = [for az in ["az_a", "az_b"] : aws_subnet.private[az].id]

  addons = {
    coredns = {
      resolve_conflicts_on_create = "OVERWRITE"
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {
      resolve_conflicts_on_create = "OVERWRITE"
    }
    vpc-cni = {
      before_compute = true
      pod_identity_association = [{
        role_arn        = terraform_data.vpc_cni_role_ready.output
        service_account = "aws-node"
      }]
      resolve_conflicts_on_create = "OVERWRITE"
    }
  }

  eks_managed_node_groups = {
    for az, subnet_id in local.eks_node_group_subnets : az => {
      name            = "${local.eks_name}-${az}"
      use_name_prefix = false
      subnet_ids      = [subnet_id]

      min_size     = 1
      max_size     = 1
      desired_size = 1

      capacity_type              = "ON_DEMAND"
      instance_types             = ["t3.small"]
      use_custom_launch_template = false
      disk_size                  = 20
      update_config = {
        max_unavailable = 1
      }

      iam_role_name            = "${local.eks_name}-${az}-nodes"
      iam_role_use_name_prefix = false
      # Keep CNI permissions on the node role as a bootstrap fallback: the
      # pinned module does not make before_compute add-ons a graph dependency
      # of node groups, so aws-node may start before Pod Identity is available.
      iam_role_attach_cni_policy = true
      create_security_group      = false
      iam_role_tags              = { Project = local.name }
    }
  }

  tags = {
    Project   = local.name
    ManagedBy = "Terraform"
  }

}
