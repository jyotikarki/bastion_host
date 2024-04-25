provider "aws" {
  region = "us-west-2"
}

# Creating the VPC
resource "aws_vpc" "nginx-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
#enable_classiclink   = "false"
  instance_tenancy     = "default"
  tags = {
    Name = "nginx-vpc"
  }
}
# Creating a public subnet
resource "aws_subnet" "prod-subnet-public-1" {
  vpc_id                  = aws_vpc.nginx-vpc.id // Referencing the id of the VPC from abouve code block
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = "true" // Makes this a public subnet
  availability_zone       = "us-west-2a"
  tags = {
    name = "public-subnet"
  }
}

# Creating an Internet Gateway
resource "aws_internet_gateway" "prod-igw" {
  vpc_id = aws_vpc.nginx-vpc.id
}

# Create a custom route table for public subnets
resource "aws_route_table" "prod-public-crt" {
  vpc_id = aws_vpc.nginx-vpc.id
  route {
    cidr_block = "0.0.0.0/0"                      //associated subnet can reach everywhere
    gateway_id = aws_internet_gateway.prod-igw.id //CRT uses this IGW to reach internet
  }
  tags = {
    Name = "prod-public-crt"
  }
}
# Route table association for the public subnets
resource "aws_route_table_association" "prod-crta-public-subnet-1" {
  subnet_id      = aws_subnet.prod-subnet-public-1.id
  route_table_id = aws_route_table.prod-public-crt.id
}

#### ----------Private Subnet----------####
resource "aws_subnet" "private-subnet-1" {
  vpc_id                  = aws_vpc.nginx-vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = false
  tags = {
    Name = "private-subnet-1"
  }
}

#--------------------Elastic IP------------------##
resource "aws_eip" "ep1" {
  depends_on = [aws_internet_gateway.prod-igw]
  tags = {
    Name = "nginx_ep"
  }
}
#-----------------NAT Gateway-------------------##
resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.ep1.id
  subnet_id     = aws_subnet.prod-subnet-public-1.id
  tags = {
    Name = "nginx_nat"
  }
}

#------------Private Route Table----------------------##
resource "aws_route_table" "private-route" {
  vpc_id = aws_vpc.nginx-vpc.id
  route {
    cidr_block     = "0.0.0.0/0"            //associated subnet can reach everywhere
    nat_gateway_id = aws_nat_gateway.ngw.id //CRT uses this IGW to reach internet
  }
  tags = {
    Name = "priv-route"
  }
}


#--------------Private Route Table Association---------------------##
resource "aws_route_table_association" "rta-private-subnet-2" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private-route.id
}

#---------------------------------------##



# Security group
resource "aws_security_group" "ssh-allowed" {
  vpc_id = aws_vpc.nginx-vpc.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] // Ideally best to use your laptops IP. However if it is dynamic you will need to change this in the vpc every so often. 
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#------------------ SG2---------------------------------#
# Create Security Group for the Web Server
# terraform aws create security group
resource "aws_security_group" "webserver-security-group" {
  name        = "Web Server Security Group"
  description = "Enable HTTP/HTTPS access on Port 80/443 via ALB and SSH access on Port 22 via SSH SG"
  vpc_id      = aws_vpc.nginx-vpc.id
  ingress {
    description     = "SSH Access"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.ssh-allowed.id}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Web Server Security Group"
  }
}
##----------------------------------------------------------##

# Setting up the aws ssh key. You need to generate one and store it in the same directory
resource "aws_key_pair" "aws-key" {
  key_name   = "aws-key"
  public_key = file(var.PUBLIC_KEY_PATH)
}
# Setting up the EC2 instnace
# We are installing ubunto as the core OD
resource "aws_instance" "nginx_server" {
  ami           = "ami-08d70e59c07c61a3a"
  instance_type = "t2.micro"
  tags = {
    Name = "nginx_server"
  }
  # VPC
  subnet_id = aws_subnet.prod-subnet-public-1.id
  # Security Group
  vpc_security_group_ids = ["${aws_security_group.ssh-allowed.id}"]
  # the Public SSH key
  key_name = aws_key_pair.aws-key.id
  # nginx installation
  # storing the nginx.sh file in the EC2 instnace
  provisioner "file" {
    source      = "nginx.sh"
    destination = "/tmp/nginx.sh"
  }
  # Exicuting the nginx.sh file
  # Terraform does not reccomend this method becuase Terraform state file cannot track what the scrip is provissioning
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/nginx.sh",
      "sudo /tmp/nginx.sh"
    ]
  }
  # Setting up the ssh connection to install the nginx server
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file("${var.PRIVATE_KEY_PATH}")
  }
}


#-------------------------EC2----------------#
resource "aws_instance" "nginx_private" {
  ami           = "ami-08d70e59c07c61a3a"
  instance_type = "t2.micro"
  # VPC
  subnet_id = aws_subnet.private-subnet-1.id
  # Security Group
  vpc_security_group_ids = ["${aws_security_group.webserver-security-group.id}"]
  # the Public SSH key
  key_name                    = aws_key_pair.aws-key.id
  associate_public_ip_address = false
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    "Name" = "EC2-Private"
  }
}
