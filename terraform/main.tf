#ref https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
# define a new vpc 
resource "aws_vpc" "main_vpc" {
  #cidr_block           = "10.10.0.0/16"
  cidr_block           = var.vpc_cidr # set via makefile
  enable_dns_hostnames = true // false by default for non-default vpc. needed for interface endpoints with private dns. ref # https://docs.aws.amazon.com/vpc/latest/privatelink/interface-endpoints.html#enable-private-dns-names

  tags = {
    Name = "${var.service_name}-main-vpc"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id = aws_vpc.main_vpc.id
  #cidr_block = "10.10.2.0/24"
  cidr_block = var.private_subnet_cidr # set via makefile
  tags       = { Name = "${var.service_name}-ps" }
}


resource "aws_security_group" "lambda_sg" {
  name   = "${var.service_name}-lambda-sg"
  vpc_id = aws_vpc.main_vpc.id
  # tightened to limit to only lambda ENI outboud connection to vpc interface endpoint for ec2 api and cloudwatch logs. SGs are stateful
  egress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    # allow out for lambda ENI https
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ref https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html
resource "aws_security_group" "vpc_endpoint_sg" {
  name   = "${var.service_name}-vpc_endpoint-sg"
  vpc_id = aws_vpc.main_vpc.id
  # allow inbound connection from lambda sg 
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
  }
}

# ec2 api endpoint for lambda to call to.
resource "aws_vpc_endpoint" "ec2_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.ec2"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true // allows calls from boto3 to resolve to vpc endpoint . ref # https://docs.aws.amazon.com/vpc/latest/privatelink/privatelink-access-aws-services.html#interface-endpoint-private-dns

  tags = { Name = "${var.service_name}-vpc_endpoint-ec2" }
}

# cloudwatch endpoint for lambda logging without NAT
resource "aws_vpc_endpoint" "cw_logs_endpoint" {
  vpc_id              = aws_vpc.main_vpc.id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.logs"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true

  tags = { Name = "${var.service_name}-vpc_endpoint-cw_logs" }
}


# for sanity check with aws-whoami
data "aws_caller_identity" "current" {}
