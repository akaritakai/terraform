terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.2.0"
    }
	random = {
	  source = "hashicorp/random"
	  version = "3.0.1"
	}
  }
  required_version = ">= 1.1.6"
  cloud {
    organization = "akaritakai"
	workspaces {
	  name = "github-terraform"
	}
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_pet" "sg" {}

resource "aws_instance" "web" {
  ami = "ami-01b996646377b6619"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web-sg.id]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p 8080 &
              EOF
}

resource "aws_security_group" "web-sg" {
  name = "${random_pet.sg.id}-sg"
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "web-address" {
  value = "${aws_instance.web.public_dns}:8080"
}