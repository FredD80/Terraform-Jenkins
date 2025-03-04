terraform {
  backend "s3" {
    bucket = "terraform-project54321"
    key    = "terraform-project54321/backend/pywebsite.tf"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "local" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "website-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.101.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false


  tags = {
    Terraform   = "true"
    Environment = "dev"
    name        = "website-vpc"
  }
}

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/*-24.04-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

}

output "ami_id" {
  value = data.aws_ami.ubuntu_2404.id
}

module "ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                        = "website-Server"
  instance_type               = "t3.micro"
  ami                         = data.aws_ami.ubuntu_2404.id
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  iam_instance_profile        = "Managed-EC2"
  key_name                    = "FD_CLI_Keypair"
  vpc_security_group_ids      = [module.security_group.security_group_id]

  root_block_device = [
        
        {
    device_name           = "/dev/xvda" # Or /dev/sda1, etc. - Check your AMI documentation
    volume_type           = "gp3"       # or gp2, io1, io2, st1, sc1
    volume_size           = 32          # Size in GiB
    encrypted             = true        # Recommended
    delete_on_termination = true        # Recommended (so volume is deleted when instance is terminated)
    
      }
  ]
    user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
              sudo apt-get update -y
              sudo apt-get install -y docker-ce docker-ce-cli containerd.io
              sudo usermod -aG docker ubuntu
	      sudo usermod -aG docker ssm-user
              newgrp docker 
              sudo docker run -d --name flaskapp -p 8100:8100 fredd1/flaskapp 

              EOF

  tags = {
    Terraform   = "true"
    Environment = "dev"
    name        = "website-server"
  }
}

output "ec2_instance_public_ip" {
  value = module.ec2_instance.public_ip
}

output "ec2_instance_private_ip" {
  value = module.ec2_instance.private_ip
}

output "ec2_instance_public_dns" {
  value = module.ec2_instance.public_dns
}

output "ec2_instance_instance_id" {
  value = module.ec2_instance.id
}

module "security_group" {
  source      = "terraform-aws-modules/security-group/aws"
  name        = "front-sg"
  description = "Security group for website server"
  vpc_id      = module.vpc.vpc_id


  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["all-icmp", "https-443-tcp", "http-80-tcp"]
  ingress_with_cidr_blocks = [

    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "SSH"
      cidr_blocks = "${local.validated_ip}/32"
    },
   
    { 
      from_port  = 8080
      to_port    = 8080
      protocol   = "tcp"
      decription = "app port"
      cidr_blocks = "0.0.0.0/0"
    }

 
  ] 

  egress_rules = ["all-all"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
    name        = "front-sg"
  }

}
output "security_group_id" {
  value = module.security_group.security_group_id
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

locals {
  # Remove whitespace and newlines from the response
  current_ip = chomp(data.http.my_ip.response_body)

  # Validate the IP format using regex
  validated_ip = can(
    regex(
      "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$",
      local.current_ip
    )
  ) ? local.current_ip : null
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  default     = "latest"
}
