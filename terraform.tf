provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
}

variable "az_list" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"]
}

variable "vpc_cidr" {
  type = string
  default = "10.0.0.0/16"
}

variable "ec2_cidr" {
  type = string
  default = "10.0.0.0/24"
}

variable "container_cidr" {
  type = string
  default = "10.0.1.0/24"
}

data "aws_ecs_task_definition" "mysql" {
  task_definition = aws_ecs_task_definition.mysql.family
}

data "aws_ecs_task_definition" "app" {
  task_definition = aws_ecs_task_definition.app.family
}

data "aws_iam_policy_document" "ecs_instance_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_service_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

# resource "null_resource" "clone" {
#   provisioner "local-exec" {
#     command = "git clone https://github.com/UndercoverTourist/dev-ops-app"
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "rm -vrf ./dev-ops-app"
#   }
# }
resource "tls_private_key" "ssh_key" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "local_file" "ssh_private_key" {
  sensitive_content         = tls_private_key.ssh_key.private_key_pem
  filename        = "ssh_key"
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content           = tls_private_key.ssh_key.public_key_openssh
  filename          = "ssh_key.pub"
  file_permission    = "0600"
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "autogen_sshkey"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

resource "aws_vpc" "skill_assessment" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "UT Skill Assessment VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.skill_assessment.id

  tags = {
    Name        = "Skill Assessment IGW"
  }
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name        = "Skill Assessment NAT EIP"
  }

}
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.ec2[0].id

  tags = {
    Name        = "Skill Assessment NAT GW"
  }
}

resource "aws_default_route_table" "r" {
  default_route_table_id = aws_vpc.skill_assessment.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Default Route"
  }
}

resource "aws_route_table" "container" {
  vpc_id = aws_vpc.skill_assessment.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "Container Route"
  }
}

resource "aws_subnet" "ec2" {
  count = length(var.az_list)

  vpc_id = aws_vpc.skill_assessment.id
  cidr_block = cidrsubnet(
    var.ec2_cidr,
    ceil(log(length(var.az_list), 2)),
    count.index
  )

  availability_zone       = var.az_list[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name        = "EC2 subnet - ${var.az_list[count.index]}"
  }
}

resource "aws_subnet" "container" {
  count = length(var.az_list)

  vpc_id = aws_vpc.skill_assessment.id
  cidr_block = cidrsubnet(
    var.container_cidr,
    ceil(log(length(var.az_list), 2)),
    count.index
  )

  availability_zone       = var.az_list[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name        = "Container subnet - ${var.az_list[count.index]}"
  }
}

resource "aws_route_table_association" "container" {
  count = length(aws_subnet.container)

  subnet_id      = aws_subnet.container[count.index].id
  route_table_id = aws_route_table.container.id
}

resource "aws_security_group" "ecs" {
  name        = "ECS Security Group"
  description = "ECS Security Group"
  vpc_id      = aws_vpc.skill_assessment.id
}

resource "aws_security_group" "mysql" {
  name        = "MySQL Security Group"
  description = "MySQL Security Group"
  vpc_id      = aws_vpc.skill_assessment.id
}

resource "aws_security_group_rule" "ssh" {
  type            = "ingress"
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  cidr_blocks     = ["24.28.31.213/32", "24.242.67.212/32"]

  security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "self-ssh" {
  type      = "ingress"
  from_port = 22
  to_port   = 22
  protocol  = "tcp"

  security_group_id        = aws_security_group.ecs.id
  source_security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "ecs_app" {
  type            = "ingress"
  from_port       = 8000
  to_port         = 8000
  protocol        = "tcp"
  cidr_blocks     = ["0.0.0.0/0"]

  security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "all-egress" {
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]

  security_group_id = aws_security_group.ecs.id
}

resource "aws_security_group_rule" "mysql-ingress" {
  type      = "ingress"
  from_port = 3306
  to_port   = 3306
  protocol  = "tcp"

  security_group_id        = aws_security_group.mysql.id
  source_security_group_id = aws_security_group.ecs.id
}

resource "aws_ecr_repository" "skill_assessment" {
  name                 = "dev-ops-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_service_discovery_private_dns_namespace" "local" {
  name        = "ec2.internal"
  description = "foobar"
  vpc         = aws_vpc.skill_assessment.id
}

resource "aws_service_discovery_service" "mysql" {
  name = "mysql"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.local.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs_instance_role"
  path = "/"
  assume_role_policy = data.aws_iam_policy_document.ecs_instance_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_attachment" {
  role = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_logs_attachment" {
  role = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecr_attachment" {
  role = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm_attachment" {
  role = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs_instance_profile"
  path = "/"
  role = aws_iam_role.ecs_instance_role.id
}

resource "aws_iam_role" "ecs_service_role" {
  name = "ecs_service_role"
  path = "/"
  assume_role_policy = data.aws_iam_policy_document.ecs_service_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_service_role_attachment" {
  role = aws_iam_role.ecs_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_launch_configuration" "ecs_launch_configuration" {
  name = "ecs_launch_configuration"
  image_id = "ami-07a63940735aebd38"
  instance_type = "t3.small"
  iam_instance_profile = aws_iam_instance_profile.ecs_instance_profile.id
  associate_public_ip_address = true
  key_name = aws_key_pair.ssh_key.key_name

  security_groups = [aws_security_group.ecs.id]

  root_block_device {
    volume_type = "standard"
    volume_size = 100
    delete_on_termination = true
  }

  user_data = <<EOF
    #!/usr/bin/env bash
    echo ECS_CLUSTER=${aws_ecs_cluster.ut_skill_assessment.name} > /etc/ecs/ecs.config
    yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
EOF
}

resource "aws_autoscaling_group" "ecs_autoscaling_group" {
  name = "ecs_autoscaling_group"
  max_size = "1"
  min_size = "1"
  desired_capacity = "1"

  vpc_zone_identifier = aws_subnet.ec2.*.id
  launch_configuration = aws_launch_configuration.ecs_launch_configuration.name
  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = "Skill Assessment ECS"
    propagate_at_launch = true
  }

  depends_on = [aws_launch_configuration.ecs_launch_configuration]
}

resource "aws_ecs_cluster" "ut_skill_assessment" {
    capacity_providers = []
    name               = "skill_assessment"
    tags               = {}

    setting {
        name  = "containerInsights"
        value = "disabled"
    }
}

resource "aws_ecs_task_definition" "mysql" {
    container_definitions    = jsonencode(
      [
        {
          cpu              = 0
          environment      = [
            {
              name  = "MYSQL_ALLOW_EMPTY_PASSWORD"
              value = "yes"
            },
            {
              name  = "MYSQL_DATABASE"
              value = "app"
            },
          ]
          essential        = true
          image            = "mysql:5.7"
          logConfiguration = {
            logDriver = "awslogs"
            options   = {
              awslogs-group         = "/ecs/mysql"
              awslogs-region        = "us-east-1"
              awslogs-stream-prefix = "ecs"
              awslogs-create-group  = "true"
            }
          }
          mountPoints      = []
          name             = "mysql"
          volumesFrom      = []
         },
      ]
    )
    cpu                      = "128"
    family                   = "mysql"
    memory                   = "256"
    network_mode             = "awsvpc"
    requires_compatibilities = [
        "EC2",
    ]
    tags                     = {}
}

resource "aws_ecs_service" "mysql" {
  cluster                            = aws_ecs_cluster.ut_skill_assessment.id
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  enable_ecs_managed_tags            = false
  health_check_grace_period_seconds  = 0
  #iam_role                           = "aws-service-role"
  launch_type                        = "EC2"
  name                               = "mysql"
  #propagate_tags                     = "NONE"
  scheduling_strategy                = "REPLICA"
  tags                               = {}
  task_definition                    = "${aws_ecs_task_definition.mysql.family}:${max(aws_ecs_task_definition.mysql.revision, data.aws_ecs_task_definition.mysql.revision)}"

  deployment_controller {
      type = "ECS"
  }

  network_configuration {
      assign_public_ip = false
      security_groups  = [ aws_security_group.mysql.id ]
      subnets          = aws_subnet.container.*.id
  }

  ordered_placement_strategy {
      field = "attribute:ecs.availability-zone"
      type  = "spread"
  }
  ordered_placement_strategy {
      field = "instanceId"
      type  = "spread"
  }
  service_registries {
    registry_arn   = aws_service_discovery_service.mysql.arn
  }
}

resource "null_resource" "ecr_login" {
  provisioner "local-exec" {
    command = "$(aws ecr get-login --no-include-email --region us-east-1)"
  }
}

resource "null_resource" "build" {
  provisioner "local-exec" {
    command = "docker build -t dev-ops-app ."
  }
}

resource "null_resource" "tag" {
  provisioner "local-exec" {
    command = "docker tag dev-ops-app:latest ${aws_ecr_repository.skill_assessment.repository_url}:latest"
  }
  depends_on = [null_resource.build]
}

resource "null_resource" "push" {
  provisioner "local-exec" {
    command = "docker push ${aws_ecr_repository.skill_assessment.repository_url}:latest"
  }
  depends_on = [null_resource.tag]
}

resource "aws_ecs_task_definition" "app" {
    container_definitions    = jsonencode(
      [
        {
          cpu              = 0
          essential        = true
          image            = "${aws_ecr_repository.skill_assessment.repository_url}:latest"
          logConfiguration = {
            logDriver = "awslogs"
            options   = {
              awslogs-group         = "/ecs/app"
              awslogs-region        = "us-east-1"
              awslogs-stream-prefix = "ecs"
              awslogs-create-group  = "true"
            }
          }
          mountPoints      = []
          name             = "app"
          portMappings     = [
            {
              containerPort = 8000
              hostPort      = 8000
              protocol      = "tcp"
            },
          ]
          volumesFrom      = []
         },
      ]
    )
    cpu                      = "128"
    family                   = "app"
    memory                   = "256"
    network_mode             = "bridge"
    requires_compatibilities = [
        "EC2",
    ]
    tags                     = {}
    depends_on = [null_resource.push]
}

resource "aws_ecs_service" "app" {
  cluster                            = aws_ecs_cluster.ut_skill_assessment.id
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 1
  enable_ecs_managed_tags            = false
  health_check_grace_period_seconds  = 0
  #iam_role                           = "aws-service-role"
  launch_type                        = "EC2"
  name                               = "app"
  #propagate_tags                     = "NONE"
  scheduling_strategy                = "REPLICA"
  tags                               = {}
  task_definition                    = "${aws_ecs_task_definition.app.family}:${max(aws_ecs_task_definition.app.revision, data.aws_ecs_task_definition.app.revision)}"

  deployment_controller {
      type = "ECS"
  }

  #network_configuration {
  #    assign_public_ip = false
  #    security_groups  = [ aws_security_group.app.id ]
  #    subnets          = aws_subnet.container.*.id
  #}

  ordered_placement_strategy {
      field = "attribute:ecs.availability-zone"
      type  = "spread"
  }
  ordered_placement_strategy {
      field = "instanceId"
      type  = "spread"
  }
  depends_on = [aws_ecs_service.mysql, aws_ecs_task_definition.app]
}

# data "aws_instance" "ecs" {
#   count = aws_autoscaling_group.ecs_autoscaling_group.id ? 1 : 0
#   instance_tags = {
#     Name = "Skill Assessment ECS"
#   }
# }

#  output "url" {
#    value = "http://${data.aws_instance.ecs[0].public_ip}:8000"
#  }