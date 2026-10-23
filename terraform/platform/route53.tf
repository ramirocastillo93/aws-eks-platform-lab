resource "aws_route53_zone" "docmost_checkr" {
  name = "docmost-checkr.nakamalabs.io"

  tags = {
    Name      = "docmost-checkr.nakamalabs.io"
    Project   = local.name
    ManagedBy = "Terraform"
  }
}
