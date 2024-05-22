terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = var.regiao_aws
}

resource "aws_launch_template" "maquina" {
  image_id      = "ami-0cf2b4e024cdb6960"
  instance_type = var.instancia
  key_name = var.chave
  tags = {
    Name = "Terraform Ansible Python"
  }
  security_group_names = [ var.grupoDeSeguranca ]
  user_data = var.producao ? filebase64("${path.module}/../env/DEV/ansible.sh") : ""
}

resource "aws_key_pair" "chaveSSH" {
  key_name = var.chave
  public_key = file("${path.module}/../env/DEV/${var.chave}.pub")
}

resource "aws_autoscaling_group" "grupo" {
  availability_zones = [ "${var.regiao_aws}a", "${var.regiao_aws}b" ]
  name = var.nomeGrupo
  max_size = var.maximo
  min_size = var.minimo
  target_group_arns = [ aws_lb_target_group.alvoLoadBalancer.arn ]
  launch_template {
    id = aws_launch_template.maquina.id
    version = "$Latest"
  }
}

resource "aws_default_subnet" "subnet_1" {
  availability_zone = "${var.regiao_aws}a"
}

resource "aws_default_subnet" "subnet_2" {
  availability_zone = "${var.regiao_aws}b"
}

resource "aws_lb" "loadBalancer" {
  internal = false
  subnets = [ aws_default_subnet.subnet_1.id, aws_default_subnet.subnet_2.id ]
}

resource "aws_default_vpc" "vpc" {
}

resource "aws_lb_target_group" "alvoLoadBalancer" {
  name = "alvoLoadBalancer"
  port = "8000"
  protocol = "HTTP"
  vpc_id = aws_default_vpc.vpc.id
}

resource "aws_lb_listener" "entradaLoadBalancer" {
  load_balancer_arn = aws_lb.loadBalancer.arn
  port = "8000"
  protocol = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.alvoLoadBalancer.arn
  }
}

resource "aws_autoscaling_policy" "escala-Producao" {
  depends_on = [aws_autoscaling_group.grupo]

  name = "terraform-escala"
  autoscaling_group_name = aws_autoscaling_group.grupo.name
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}