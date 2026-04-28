packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  default = "ap-southeast-2"
}

source "amazon-ebs" "ubuntu" {
  region        = var.region
  instance_type = "t3.micro"
  source_ami    = "ami-0c33c6bd24cee108b"
  ssh_username  = "ubuntu"
  ami_name      = "my-custom-nginx-{{timestamp}}"
}

build {
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y nginx",
      "echo 'Hello from Packer AMI' | sudo tee /var/www/html/index.html"
    ]
  }
}