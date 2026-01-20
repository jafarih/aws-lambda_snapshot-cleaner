# centralizing most vars to Makefile. keeping place holders here
variable "region" {
  description = "aws region default to oregon. no default added to avoid silent failures. use Makefile to define it"
  type        = string
}

variable "service_name" {
  description = "service or project name.should be used as prefix for most associated components. no default added to avoid silent failures. use Makefile to define it"
  type        = string
}

# set via makefile
variable "vpc_cidr" {
  description = "must be ipv4, cidr for the VPC to create. supply via the Make file"
  type        = string
  # ensure it is is a valid cidr
  validation {
    error_message = "not a valid cidr for vpc_cidr (needs to be ipv4)"
    condition     = can(cidrnetmask(var.vpc_cidr))
  }
}

# set via makefile
variable "private_subnet_cidr" {
  description = "must be ipv4, cidr for the VPC to create. supply via the Make file"
  type        = string
  # ensure it is is a valid cidr
  validation {
    error_message = "not a valid cidr for private subnet (needs to be ipv4)"
    condition     = can(cidrnetmask(var.private_subnet_cidr))
  }
}


# for validation 
variable "retention_period" {
  description = "how many hours should the snapshot be retained for. requirement is 1yr = 8760 hrs. default added to avoid early deletion. use Makefile to define the correct hours"
  type        = number
  default     = 8760 // 1 yr , 1 month = 730, 1 week = 168
}

# eventbridge scheduler schedule. ref # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule
variable "lambda_schedule_frequency" {
  description = "how often should the lambda function get triggered. default added to ensure it will run at least daily. use Makefile to define the correct schedule."
  type        = string
  default     = "rate(1 day)" // added default to make sure it will at least run once a day.
}
