# YugabyteDB AWS Terraform

Terraform configuration to deploy a YugabyteDB cluster on AWS.

## Overview

This project provisions a 3-node YugabyteDB cluster across multiple availability zones in AWS with:

- VPC with public and private subnets
- Application Load Balancer for master (7000) and tserver (9000) UI access
- NAT Gateway for outbound internet access from private subnets
- EC2 Instance Connect endpoint for secure SSH access

## Prerequisites

- Terraform installed
- AWS credentials configured
- AWS region: `ap-south-1` (default)

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Access

After deployment, access the YugabyteDB UI at:
- Master UI: `http://<alb_dns_name>`
- TServer UI: `http://<alb_dns_name>:9000`

The ALB DNS name will be displayed in the Terraform output.
