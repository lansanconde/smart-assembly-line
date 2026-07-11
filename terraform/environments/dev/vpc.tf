# VPC principal — réseau privé isolé du projet
# CIDR /16 intentionnellement large : un VPC ne se redimensionne pas après création
resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true  # Les ressources auront des noms DNS automatiques
  enable_dns_support   = true

  tags = { Name = "smart-assembly-vpc" }
}

# Subnet public — réservé au Load Balancer uniquement
# Les ressources ici reçoivent une IP publique
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = true

  tags = { Name = "smart-assembly-subnet-public" }
}

# Subnet privé — Lambda et API, jamais joignables depuis internet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "eu-west-3a"

  tags = { Name = "smart-assembly-subnet-private" }
}


# Internet Gateway — unique point de sortie vers internet
# Attachée au VPC, pas au subnet — c'est la route table qui décide qui l'utilise
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "smart-assembly-igw" }
}

# Route table du subnet public — tout trafic externe passe par l'IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "smart-assembly-rt-public" }
}

# Route table explicite pour le subnet privé
# Pas de route vers internet — trafic local VPC uniquement
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "smart-assembly-rt-private" }
}

# Association route table → subnet public
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}