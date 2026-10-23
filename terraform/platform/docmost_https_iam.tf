locals {
  docmost_https_ci_users = {
    plan  = "aws-eks-platform-lab-terraform-plan"
    apply = "aws-eks-platform-lab-terraform-apply"
  }
  docmost_https_zone_arn = "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${aws_route53_zone.docmost_checkr.zone_id}"
  docmost_https_acm_arn  = "arn:${data.aws_partition.current.partition}:acm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:certificate/*"
}

data "aws_iam_policy_document" "docmost_https_read" {
  statement {
    sid       = "ReadDocmostCertificate"
    actions   = ["acm:DescribeCertificate", "acm:ListTagsForCertificate"]
    resources = [local.docmost_https_acm_arn]
  }

  statement {
    sid = "DiscoverDocmostLoadBalancer"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeTags"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ReadDocmostDnsRecords"
    actions   = ["route53:ListResourceRecordSets"]
    resources = [local.docmost_https_zone_arn]
  }
}

resource "aws_iam_policy" "docmost_https_read" {
  name        = "aws-eks-platform-lab-terraform-docmost-https-read"
  description = "Read the Docmost HTTPS certificate and discover its tagged load balancer during Terraform planning."
  policy      = data.aws_iam_policy_document.docmost_https_read.json
}

resource "aws_iam_user_policy_attachment" "docmost_https_read" {
  for_each   = local.docmost_https_ci_users
  user       = each.value
  policy_arn = aws_iam_policy.docmost_https_read.arn
}

data "aws_iam_policy_document" "docmost_https_apply" {
  statement {
    sid = "ManageDocmostCertificate"
    actions = [
      "acm:AddTagsToCertificate",
      "acm:DeleteCertificate",
      "acm:RemoveTagsFromCertificate"
    ]
    resources = [local.docmost_https_acm_arn]
  }

  statement {
    sid       = "RequestDocmostCertificate"
    actions   = ["acm:RequestCertificate"]
    resources = ["*"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "acm:DomainNames"
      values   = [local.docmost_hostname]
    }

    condition {
      test     = "Null"
      variable = "acm:DomainNames"
      values   = ["false"]
    }

    condition {
      test     = "StringEquals"
      variable = "acm:ValidationMethod"
      values   = ["DNS"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "ManageDocmostDnsRecords"
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
    resources = [local.docmost_https_zone_arn]
  }

  statement {
    sid       = "ReadDocmostDnsChangeStatus"
    actions   = ["route53:GetChange"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }
}

resource "aws_iam_policy" "docmost_https_apply" {
  name        = "aws-eks-platform-lab-terraform-docmost-https-apply"
  description = "Manage the Docmost HTTPS ACM certificate and records in its dedicated Route 53 hosted zone."
  policy      = data.aws_iam_policy_document.docmost_https_apply.json
}

resource "aws_iam_user_policy_attachment" "docmost_https_apply" {
  user       = local.docmost_https_ci_users.apply
  policy_arn = aws_iam_policy.docmost_https_apply.arn
}
