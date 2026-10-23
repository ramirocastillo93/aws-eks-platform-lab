locals {
  docmost_hostname = "docmost-checkr.nakamalabs.io"
}

resource "aws_acm_certificate" "docmost" {
  domain_name       = local.docmost_hostname
  validation_method = "DNS"

  tags = {
    Name      = local.docmost_hostname
    Project   = local.name
    ManagedBy = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "docmost_certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.docmost.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.docmost_checkr.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "docmost" {
  certificate_arn = aws_acm_certificate.docmost.arn
  validation_record_fqdns = [
    for record in aws_route53_record.docmost_certificate_validation : record.fqdn
  ]
}

# The AWS Load Balancer Controller owns this ALB. Locate it by the stable
# Kubernetes stack tags so Terraform manages only the DNS alias and certificate.
data "aws_lb" "docmost" {
  tags = {
    "elbv2.k8s.aws/cluster" = local.eks_name
    "ingress.k8s.aws/stack" = "docmost/docmost"
  }
}

resource "aws_route53_record" "docmost" {
  zone_id = aws_route53_zone.docmost_checkr.zone_id
  name    = local.docmost_hostname
  type    = "A"

  alias {
    name                   = data.aws_lb.docmost.dns_name
    zone_id                = data.aws_lb.docmost.zone_id
    evaluate_target_health = true
  }
}
