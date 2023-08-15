# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create a Virtual Private Cloud (VPC)
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "MyVPC"
  }
}

# Create Subnets
resource "aws_subnet" "public_subnet" {
  count = length(var.subnet_cidr)
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = var.subnet_cidr[count.index]

  tags = {
    Name = var.subnet_name[count.index]
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "MyInternetGateway"
  }
}

# Create a Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Associate Public Route Table with Subnets
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet[0].id
  route_table_id = aws_route_table.public_route_table.id
}

# Create Elastic IP and NAT Gateway for private instances
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "NATGateway"
  }
}

# Create a Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "PrivateRouteTable"
  }
}

# Associate Private Route Table with Subnets
resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.public_subnet[1].id
  route_table_id = aws_route_table.private_route_table.id
}

# Create a Security Group for Instances
resource "aws_security_group" "my_security_group" {
  name        = "MySecurityGroup"
  description = "Allow HTTP and SSH traffic"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming HTTPS connections"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming SSH connections"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming HTTP connections"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "MySecurityGroup"
  }
}

# Create Instances
data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "public_instance" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet[0].id
  vpc_security_group_ids      = [aws_security_group.my_security_group.id]
  source_dest_check           = false
  associate_public_ip_address = true
  user_data = file("Apache.sh")

  tags = {
    Name = "PublicInstance"
  }
}

resource "aws_instance" "private_instance" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_subnet[1].id
  vpc_security_group_ids      = [aws_security_group.my_security_group.id]
  source_dest_check           = false
  associate_public_ip_address = false
  user_data = file("Nginx.sh")

  tags = {
    Name = "PrivateInstance"
  }
}

# Define output variables
output "public_ip" {
  value = aws_instance.public_instance.public_ip
}

output "private_ip" {
  value = aws_instance.private_instance.private_ip
}

# Define variables
variable "subnet_cidr" {
  type = list(string)
}

variable "subnet_name" {
  type = list(string)
}

variable "instance_type" {
  description = "Type of EC2 instance"
  default     = "t2.micro"
}
