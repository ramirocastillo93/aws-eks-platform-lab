locals {
  state_key = "platform/terraform.tfstate"
  state_arn = "${aws_s3_bucket.state.arn}/${local.state_key}"
  lock_arn  = "${local.state_arn}.tflock"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  tags = {
    Project   = "aws-eks-platform-lab"
    ManagedBy = "Terraform"
    Purpose   = "Terraform state"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_user" "plan" {
  name = "aws-eks-platform-lab-terraform-plan"
}

resource "aws_iam_user" "apply" {
  name = "aws-eks-platform-lab-terraform-apply"
}

data "aws_iam_policy_document" "read_data_services" {
  statement {
    sid = "ReadDataServices"
    actions = [
      "rds:Describe*", "rds:ListTagsForResource",
      "elasticache:Describe*", "elasticache:List*"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ReadDataServiceLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ReadDataServiceLogGroupTags"
    actions   = ["logs:ListTagsForResource"]
    resources = ["arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/elasticache/aws-eks-platform-lab-docmost"]
  }

  statement {
    sid       = "ReadEksOptimizedAmiVersion"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}::parameter/aws/service/eks/optimized-ami/*"]
  }
}

resource "aws_iam_policy" "read_data_services" {
  name        = "aws-eks-platform-lab-terraform-read-data-services"
  description = "Read existing data services and EKS AMI metadata during Terraform planning."
  policy      = data.aws_iam_policy_document.read_data_services.json
}

resource "aws_iam_user_policy_attachment" "plan_read_data_services" {
  user       = aws_iam_user.plan.name
  policy_arn = aws_iam_policy.read_data_services.arn
}

resource "aws_iam_user_policy_attachment" "apply_read_data_services" {
  user       = aws_iam_user.apply.name
  policy_arn = aws_iam_policy.read_data_services.arn
}

data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "ReadStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = [local.state_arn]
  }

  statement {
    sid       = "LockState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.lock_arn]
  }

  statement {
    sid       = "ReadNetwork"
    actions   = ["ec2:Describe*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ReadEks"
    actions   = ["eks:Describe*", "eks:List*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ReadIamRolesAndPolicies"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid = "ReadRoute53HostedZone"
    actions = [
      "route53:GetHostedZone",
      "route53:ListTagsForResource"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  }
}

data "aws_iam_policy_document" "apply" {
  source_policy_documents = [data.aws_iam_policy_document.plan.json]

  statement {
    sid       = "WriteState"
    actions   = ["s3:PutObject"]
    resources = [local.state_arn]
  }

  statement {
    sid = "ManageLabNetwork"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:AllocateAddress", "ec2:ReleaseAddress",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:CreateTags", "ec2:DeleteTags"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "CreateRoute53HostedZone"
    actions   = ["route53:CreateHostedZone"]
    resources = ["*"]
  }

  statement {
    sid = "ManageRoute53HostedZone"
    actions = [
      "route53:DeleteHostedZone",
      "route53:ChangeTagsForResource"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid       = "WaitForRoute53Change"
    actions   = ["route53:GetChange"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }
}

data "aws_iam_policy_document" "apply_eks" {
  statement {
    sid       = "CreateEksServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateLabEksCluster"
    actions   = ["eks:CreateCluster"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["aws-eks-platform-lab"]
    }
  }

  statement {
    sid = "ManageLabEksResources"
    actions = [
      "eks:DeleteCluster", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion",
      "eks:CreateNodegroup", "eks:DeleteNodegroup", "eks:UpdateNodegroupConfig",
      "eks:CreateAddon", "eks:DeleteAddon", "eks:UpdateAddon",
      "eks:CreatePodIdentityAssociation", "eks:DeletePodIdentityAssociation",
      "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:UpdateAccessEntry",
      "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy",
      "eks:TagResource", "eks:UntagResource"
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/aws-eks-platform-lab-eks",
      "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:nodegroup/aws-eks-platform-lab-eks/*/*",
      "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:addon/aws-eks-platform-lab-eks/*/*",
      "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:access-entry/aws-eks-platform-lab-eks/*",
      "arn:${data.aws_partition.current.partition}:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:podidentityassociation/aws-eks-platform-lab-eks/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["aws-eks-platform-lab"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ManageLabEksRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-eks-platform-lab-eks-*"]
  }

  statement {
    sid = "ManageLabLoadBalancerControllerPolicy"
    actions = [
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:TagPolicy", "iam:UntagPolicy"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/aws-eks-platform-lab-eks-aws-load-balancer-controller"]
  }

  statement {
    sid     = "CreateDataServiceLinkedRoles"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/elasticache.amazonaws.com/AWSServiceRoleForElastiCache*"
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["rds.amazonaws.com", "elasticache.amazonaws.com"]
    }
  }

  statement {
    sid       = "ConfigureElastiCacheServiceLinkedRole"
    actions   = ["iam:PutRolePolicy"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/elasticache.amazonaws.com/AWSServiceRoleForElastiCache*"]
  }

  statement {
    sid = "ManageDataServiceSecurityGroups"
    actions = [
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ManageLabRds"
    actions = [
      "rds:CreateDBInstance", "rds:ModifyDBInstance", "rds:DeleteDBInstance",
      "rds:CreateDBSubnetGroup", "rds:ModifyDBSubnetGroup", "rds:DeleteDBSubnetGroup",
      "rds:AddTagsToResource", "rds:RemoveTagsFromResource"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ManageLabElastiCache"
    actions = [
      "elasticache:CreateReplicationGroup", "elasticache:ModifyReplicationGroup", "elasticache:DeleteReplicationGroup",
      "elasticache:CreateCacheSubnetGroup", "elasticache:ModifyCacheSubnetGroup", "elasticache:DeleteCacheSubnetGroup",
      "elasticache:AddTagsToResource", "elasticache:RemoveTagsFromResource"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "PassLabEksRolesToEksAndEc2"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-eks-platform-lab-eks-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "ec2.amazonaws.com", "pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_user_policy" "plan" {
  name   = "terraform-plan-network"
  user   = aws_iam_user.plan.name
  policy = data.aws_iam_policy_document.plan.json
}

resource "aws_iam_user_policy" "apply" {
  name   = "terraform-apply-network"
  user   = aws_iam_user.apply.name
  policy = data.aws_iam_policy_document.apply.json
}

resource "aws_iam_policy" "apply_eks" {
  name        = "aws-eks-platform-lab-terraform-apply-eks"
  description = "EKS and service role permissions for the platform Terraform apply identity."
  policy      = data.aws_iam_policy_document.apply_eks.json
}

resource "aws_iam_user_policy_attachment" "apply_eks" {
  user       = aws_iam_user.apply.name
  policy_arn = aws_iam_policy.apply_eks.arn
}
