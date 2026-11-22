provider "aws" {
  region = "ap-south-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# data "local_file" "yb-installation" {
#     filename = "${path.module}/yb/install.sh"
    
# }

# data "template_file" "yb-installation" {
#   template = "${file("${path.module}/yb/install.tpl")}"
#   vars = {
#     ALLOCATION_IP = "${aws_instance.}"
#   }
# }

resource "aws_vpc" "vpc-yb" {
  cidr_block = "10.0.0.0/16"
  tags = {
    name = "YB-VPC"
  }
}

variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
 
variable "private_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

locals {
  private_node = [for c in var.private_subnet_cidrs : cidrhost(c, 10)]
}


resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.vpc-yb.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  depends_on = [ aws_vpc.vpc-yb ]
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.vpc-yb.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  depends_on = [ aws_vpc.vpc-yb ]

}

resource "aws_internet_gateway" "yb-igw" {
  vpc_id = aws_vpc.vpc-yb.id
  depends_on = [ aws_vpc.vpc-yb ]
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat-gateway" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet[0].id
  tags          = { Name = "YB-NAT" }
  depends_on    = [
    aws_internet_gateway.yb-igw,
    aws_eip.nat,
    aws_subnet.public_subnet
    ]

}

resource "aws_route_table" "yb-public-route-table" {
  vpc_id = aws_vpc.vpc-yb.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.yb-igw.id
  }

  depends_on = [ aws_internet_gateway.yb-igw ]

}


resource "aws_route_table_association" "public_subnet_asso_yb" {
 count = length(var.public_subnet_cidrs)
 subnet_id      = aws_subnet.public_subnet[count.index].id
 route_table_id = aws_route_table.yb-public-route-table.id

 depends_on = [ aws_subnet.public_subnet ]
}


resource "aws_route_table" "yb-private-route-table" {
  vpc_id = aws_vpc.vpc-yb.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat-gateway.id
    
  }

}

resource "aws_lb" "yb-aws-alb" {
  name               = "yb-aws-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]
  security_groups    = [aws_security_group.alb-sg.id]
  depends_on         = [aws_internet_gateway.yb-igw]
}


resource "aws_route_table_association" "private_subnet_asso_yb" {
 count = length(var.private_subnet_cidrs)
 subnet_id      = aws_subnet.private_subnet[count.index].id
 route_table_id = aws_route_table.yb-private-route-table.id
}

resource "aws_security_group" "yb" {
  name = "yb-node"
  vpc_id = aws_vpc.vpc-yb.id

  ingress {
    protocol  = "-1"
    from_port = 0
    to_port   = 0
    self      = true
  }

  ingress {
    protocol        = "tcp"
    from_port       = 7000
    to_port         = 7000
    security_groups = [aws_security_group.alb-sg.id]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 9000
    to_port         = 9000
    security_groups = [aws_security_group.alb-sg.id]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.eic-sg.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self = true
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb-sg" {
  name = "alb-sg"
  vpc_id = aws_vpc.vpc-yb.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 9000
    to_port     = 9000
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "eic-sg" {
  name   = "eic-sg"
  vpc_id = aws_vpc.vpc-yb.id

  egress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [aws_vpc.vpc-yb.cidr_block]
  }
}

resource "aws_ec2_instance_connect_endpoint" "eic" {
  subnet_id          = aws_subnet.private_subnet[0].id
  security_group_ids = [aws_security_group.eic-sg.id]
  preserve_client_ip = false
}

resource "aws_lb_target_group" "yb-master" {
  name     = "yb-master"
  port     = 7000
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-yb.id

  health_check {
    path    = "/"
    matcher = "200-299"
  }
}

resource "aws_lb_target_group" "yb-tserver" {
  name     = "yb-tserver"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc-yb.id

  health_check {
    path    = "/"
    matcher = "200-299"
  }
}

resource "aws_lb_target_group_attachment" "yb-master" {
  count            = 3
  target_group_arn = aws_lb_target_group.yb-master.arn
  target_id        = aws_instance.yb-e2[count.index].id
  port             = 7000
  # depends_on = [ aws_instance.yb-e2 ]
}

resource "aws_lb_target_group_attachment" "yb-tserver" {
  count            = 3
  target_group_arn = aws_lb_target_group.yb-tserver.arn
  target_id        = aws_instance.yb-e2[count.index].id
  port             = 9000
  # depends_on = [ aws_instance.yb-e2 ]
}

resource "aws_lb_listener" "yb-master" {
  load_balancer_arn = aws_lb.yb-aws-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.yb-master.arn
  }
}

resource "aws_lb_listener" "yb-tserver" {
  load_balancer_arn = aws_lb.yb-aws-alb.arn
  port              = 9000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.yb-tserver.arn
  }
}


resource "aws_instance" "yb-e2" {
  ami = "ami-0f19324397f53458f"
  count = 3
  instance_type = "c7i-flex.large"
  vpc_security_group_ids = [ aws_security_group.yb.id ]
  subnet_id = aws_subnet.private_subnet[count.index].id
  private_ip = local.private_node[count.index]
  user_data = templatefile("${path.module}/yb/install.tpl",
  {
    MASTER_ADDRS = join(",", [for ip in local.private_node : "${ip}:7100"])
    NODE_IP      = local.private_node[count.index]
    AZ           = data.aws_availability_zones.available.names[count.index]
  }
  )

  depends_on = [
    aws_route_table_association.private_subnet_asso_yb,
    aws_nat_gateway.nat-gateway,
  ]

}

output "alb_dns_name" {
  value = aws_lb.yb-aws-alb.dns_name
}
