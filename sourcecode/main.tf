terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

#IaC for airflow - EC2, Docker, Airfloe Docker image, ENV variables

resource "aws_security_group" "secgrp" {
  name_prefix = "secgrp-"

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"] # Replace with your IP to allow SSH access.
  }

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"] # Allows the world to access the Airflow server on port 8080.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_instance" "server" {
  instance_type          = "t2.large"
  ami                    = "ami-0c7217cdde317cfec"
  key_name               = "ec2keypair"
  subnet_id              = "subnet-0a2bb940e1e38bfc8"
  vpc_security_group_ids = [aws_security_group.secgrp.id]
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common vi pip
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
              sudo apt-get update
              sudo apt-get install -y docker-ce
              cd /home/ubuntu
              curl -LfO 'https://airflow.apache.org/docs/apache-airflow/2.8.1/docker-compose.yaml'
              mkdir -p ./dags ./logs ./plugins ./config
              echo -e "AIRFLOW_UID=$(id -u)" > .env
              sudo docker compose up airflow-init
              sudo docker compose up
              EOF
  root_block_device {
    volume_size = 15  # Volume size in GB
    #include memory increase
  }

  connection {
    type        = "ssh"
    user        = "ubuntu" 
    private_key = file("C:/Users/hamsa/Downloads/ec2keypair.pem") 
    host        = self.public_ip 
  }
  provisioner "file" {
    source      = "~/.aws/credentials"
    destination = "/tmp/aws_credentials"
  }
  provisioner "remote-exec" {
    inline = [
      "export AWS_SHARED_CREDENTIALS_FILE=/tmp/aws_credentials",
      "export AWS_DEFAULT_REGION=us-east-1",
      "export AWS_ACCESS_KEY_ID=$(awk -F' = ' '/aws_access_key_id/{print $2}' /tmp/aws_credentials)",
      "export AWS_SECRET_ACCESS_KEY=$(awk -F' = ' '/aws_secret_access_key/{print $2}' /tmp/aws_credentials)",
      "export AWS_SESSION_TOKEN=$(awk -F' = ' '/aws_session_token/{print $2}' /tmp/aws_credentials)"
    ]
  }
}

output "public_ip" {
  value = aws_instance.server.public_ip
}

output "private_ip" {
  value = aws_instance.server.private_ip
}

#Iac for S3 bucket
resource "aws_s3_bucket" "example1" {
  bucket = "dwdag"

  tags = {
    Name        = "dwdag"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "object1" {
  bucket = aws_s3_bucket.example1.id
  key    = "dags/"
}

# IaC for AWS Redshift
resource "aws_security_group" "database_security_group" {
  name        = "database security group"
  description = "enable redshift access on port 5439"
  vpc_id = "vpc-01c10389da9df7185"

  ingress {
    description      = "redshift access"
    from_port        = 5439
    to_port          = 5439
    protocol         = "tcp"
    security_groups  = [aws_security_group.secgrp.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = -1
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_redshift_cluster" "example1" {
  cluster_identifier         = "example-cluster"
  database_name              = "example_db"
  master_username            = "masteruser"
  master_password            = "MasterPassword123"  # Update with your desired password
  node_type                  = "dc2.large"         # Update with desired node type
  cluster_type               = "single-node"       # Update with desired cluster type
  publicly_accessible        = true                # Update based on your needs
  skip_final_snapshot        = true                # Update based on your needs
  
  # Security Group (Update with your own Security Group ID)
  vpc_security_group_ids = [aws_security_group.database_security_group.id]

  # IAM Roles (Update with your own IAM Role ARN)
  iam_roles = ["arn:aws:iam::905418162536:role/LabRole"]
}
