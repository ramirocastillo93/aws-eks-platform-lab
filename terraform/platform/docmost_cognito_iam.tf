data "aws_iam_policy_document" "docmost_cognito_read" {
  statement {
    sid = "ReadDocmostUserPool"
    actions = [
      "cognito-idp:DescribeUserPool",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:GetUserPoolMfaConfig",
      "cognito-idp:ListTagsForResource",
    ]
    resources = [aws_cognito_user_pool.docmost_access.arn]
  }

  statement {
    sid       = "ReadDocmostCognitoDomain"
    actions   = ["cognito-idp:DescribeUserPoolDomain"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_policy" "docmost_cognito_read" {
  name        = "aws-eks-platform-lab-terraform-docmost-cognito-read"
  description = "Read the imported Docmost Cognito pool, app client, and domain during Terraform planning."
  policy      = data.aws_iam_policy_document.docmost_cognito_read.json
}

resource "aws_iam_user_policy_attachment" "docmost_cognito_read" {
  for_each   = local.docmost_https_ci_users
  user       = each.value
  policy_arn = aws_iam_policy.docmost_cognito_read.arn
}

data "aws_iam_policy_document" "docmost_cognito_apply" {
  statement {
    sid = "UpdateDocmostUserPoolAndClient"
    actions = [
      "cognito-idp:UpdateUserPool",
      "cognito-idp:UpdateUserPoolClient",
    ]
    resources = [aws_cognito_user_pool.docmost_access.arn]
  }

  statement {
    sid       = "UpdateDocmostCognitoDomain"
    actions   = ["cognito-idp:UpdateUserPoolDomain"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_policy" "docmost_cognito_apply" {
  name        = "aws-eks-platform-lab-terraform-docmost-cognito-apply"
  description = "Reconcile the imported Docmost Cognito configuration without granting deletion."
  policy      = data.aws_iam_policy_document.docmost_cognito_apply.json
}

resource "aws_iam_user_policy_attachment" "docmost_cognito_apply" {
  user       = local.docmost_https_ci_users.apply
  policy_arn = aws_iam_policy.docmost_cognito_apply.arn
}
