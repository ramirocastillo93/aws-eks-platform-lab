locals {
  name = "aws-eks-platform-lab"

  # Stable CIDRs make the network diagram and future service placement explicit.
  subnet_cidrs = {
    public = {
      az_a = "10.0.0.0/24"
      az_b = "10.0.1.0/24"
    }
    private = {
      az_a = "10.0.10.0/24"
      az_b = "10.0.11.0/24"
    }
  }
  subnet_number = {
    az_a = 1
    az_b = 2
  }
}

# Reads AZ to later create subnets
data "aws_availability_zones" "available" {
  state = "available"
}

# Creates the ONLY VPC for this lab
resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = local.name
    Project   = local.name
    ManagedBy = "Terraform"
  }
}

# Internet Gateway for apps in public subnet
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = local.name
    Project = local.name
  }
}

# A single NAT gateway keeps this lab's private nodes able to reach AWS APIs
# and container registries without assigning public addresses. It is a
# deliberate cost/availability trade-off for a short-lived learning cluster.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "${local.name}-nat"
    Project = local.name
  }
}

resource "aws_nat_gateway" "lab" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["az_a"].id

  tags = {
    Name    = "${local.name}-nat"
    Project = local.name
  }

  depends_on = [aws_internet_gateway.lab]
}

# Public subnets (like loadbalancers)
resource "aws_subnet" "public" {
  for_each                = local.subnet_cidrs.public
  vpc_id                  = aws_vpc.lab.id
  availability_zone       = data.aws_availability_zones.available.names[local.subnet_number[each.key] - 1]
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name    = "${local.name}-public-${local.subnet_number[each.key]}"
    Project = local.name
    Tier    = "public"
  }
}

# Private subnets for internal usage
resource "aws_subnet" "private" {
  for_each                = local.subnet_cidrs.private
  vpc_id                  = aws_vpc.lab.id
  availability_zone       = data.aws_availability_zones.available.names[local.subnet_number[each.key] - 1]
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name    = "${local.name}-private-${local.subnet_number[each.key]}"
    Project = local.name
    Tier    = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "${local.name}-public"
    Project = local.name
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.lab.id

  tags = {
    Name    = "${local.name}-private-${local.subnet_number[each.key]}"
    Project = local.name
  }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route" "private_default" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.lab.id
}

moved {
  from = aws_subnet.public[0]
  to   = aws_subnet.public["az_a"]
}

moved {
  from = aws_subnet.public[1]
  to   = aws_subnet.public["az_b"]
}

moved {
  from = aws_subnet.private[0]
  to   = aws_subnet.private["az_a"]
}

moved {
  from = aws_subnet.private[1]
  to   = aws_subnet.private["az_b"]
}

moved {
  from = aws_route_table_association.public[0]
  to   = aws_route_table_association.public["az_a"]
}

moved {
  from = aws_route_table_association.public[1]
  to   = aws_route_table_association.public["az_b"]
}

moved {
  from = aws_route_table.private[0]
  to   = aws_route_table.private["az_a"]
}

moved {
  from = aws_route_table.private[1]
  to   = aws_route_table.private["az_b"]
}

moved {
  from = aws_route_table_association.private[0]
  to   = aws_route_table_association.private["az_a"]
}

moved {
  from = aws_route_table_association.private[1]
  to   = aws_route_table_association.private["az_b"]
}
