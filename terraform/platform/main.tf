locals {
  name = "aws-eks-platform-lab"

  # Stable CIDRs make the network diagram and future service placement explicit.
  subnet_cidrs = {
    public  = ["10.0.0.0/24", "10.0.1.0/24"]
    private = ["10.0.10.0/24", "10.0.11.0/24"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

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

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = local.name
    Project = local.name
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.lab.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = local.subnet_cidrs.public[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name    = "${local.name}-public-${count.index + 1}"
    Project = local.name
    Tier    = "public"
  }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.lab.id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = local.subnet_cidrs.private[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name    = "${local.name}-private-${count.index + 1}"
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
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.lab.id

  tags = {
    Name    = "${local.name}-private-${count.index + 1}"
    Project = local.name
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
