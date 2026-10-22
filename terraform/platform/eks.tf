data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_role" "eks_admin" {
  name = var.eks_admin_role_name
}

locals {
  eks_name      = "${local.name}-eks"
  eks_admin_arn = data.aws_iam_role.eks_admin.arn
  eks_node_groups = {
    az_a = aws_subnet.private["az_a"].id
    az_b = aws_subnet.private["az_b"].id
  }
}

resource "aws_iam_role" "eks_cluster" {
  name = "${local.eks_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = local.name }
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodes" {
  for_each = local.eks_node_groups
  name     = "${local.eks_name}-${each.key}-nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = local.name }
}

resource "aws_iam_role_policy_attachment" "eks_nodes_worker" {
  for_each   = aws_iam_role.eks_nodes
  role       = each.value.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_ecr" {
  for_each   = aws_iam_role.eks_nodes
  role       = each.value.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

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

resource "aws_eks_cluster" "lab" {
  name     = local.eks_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.36"

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = values(aws_subnet.private)[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_api_allowed_cidrs
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]

  tags = { Project = local.name }
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = local.eks_admin_arn
  type          = "STANDARD"

  tags = { Project = local.name }
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.lab.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope { type = "cluster" }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.lab.name
  addon_name   = "eks-pod-identity-agent"

  tags = { Project = local.name }

  depends_on = [aws_eks_node_group.lab]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.lab.name
  addon_name   = "vpc-cni"

  pod_identity_association {
    service_account = "aws-node"
    role_arn        = aws_iam_role.vpc_cni.arn
  }

  tags = { Project = local.name }

  depends_on = [
    aws_eks_node_group.lab,
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.vpc_cni,
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.lab.name
  addon_name   = "kube-proxy"

  tags = { Project = local.name }

  depends_on = [aws_eks_node_group.lab]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.lab.name
  addon_name   = "coredns"

  tags = { Project = local.name }

  # CoreDNS needs nodes to become healthy; nodes must not wait for CoreDNS.
  depends_on = [aws_eks_node_group.lab]
}

resource "aws_eks_node_group" "lab" {
  for_each        = local.eks_node_groups
  cluster_name    = aws_eks_cluster.lab.name
  node_group_name = "${local.eks_name}-${each.key}"
  node_role_arn   = aws_iam_role.eks_nodes[each.key].arn
  subnet_ids      = [each.value]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.small"]
  disk_size      = 20

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config { max_unavailable = 1 }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_worker,
    aws_iam_role_policy_attachment.eks_nodes_ecr,
  ]

  tags = { Project = local.name }
}
