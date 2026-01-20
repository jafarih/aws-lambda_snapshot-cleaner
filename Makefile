# set shell
SHELL := /bin/zsh

# vars
AWS_PROFILE ?= YOUR-AWS-PROFILE-NAME
AWS_REGION ?= us-west-2
SERVICE_NAME ?= AWS-LAMBDA_SNAPSHOT-CLEANER
VPC_CIDR ?= 10.10.0.0/16
PRIVATE_SUBNET_CIDR ?= 10.10.2.0/24
TERRAFORM_DIR ?= terraform
# retention period is in hours.
RETENTION_PERIOD ?= 8760
LAMBDA_SCHEDULE_FREQUENCY ?= rate(1 day)


##### for testing #####
#LAMBDA_SCHEDULE_FREQUENCY ?= rate(5 minutes)
# retention period is in hours.
#RETENTION_PERIOD ?= 1
######################

#set env vars to used by aws cli and terraform 
export AWS_SDK_LOAD_CONFIG=1 # better compatibility for advanced profiles. ref -> registry.terraform.io/providers/hashicorp/aws/2.36.0/docs
export AWS_PROFILE
export AWS_REGION

### for debugging terraform ### 
#export TF_LOG=DEBUG # enable for debugging only. levels are --> TRACE, DEBUG, INFO, WARN, ERROR

export TF_VAR_region := $(AWS_REGION)
export TF_VAR_vpc_cidr := $(VPC_CIDR)
export TF_VAR_private_subnet_cidr := $(PRIVATE_SUBNET_CIDR)
export TF_VAR_service_name := $(SERVICE_NAME)
export TF_VAR_retention_period := $(RETENTION_PERIOD)
export TF_VAR_lambda_schedule_frequency := $(LAMBDA_SCHEDULE_FREQUENCY)


# autocomplete
.PHONY: help clean show-vars aws-whoami check-vars init plan apply destroy remove-state

help:
	@echo "#################################"
	@echo "  $(SERVICE_NAME)"
	@echo -e "#################################\n"
	@echo "Usage:"
	@echo " make help: show this screen"
	@echo " make aws-whoami: verify which AWS profile is being used"
	@echo " make clean: remove .terraform dir"
	@echo " make show-vars: show current variables"
	@echo " make check-vars: sanity check. give a chance to back out"
	@echo " make init: clean. initialize terraform (keeps terraform state)"
	@echo " make remove-state: remove terraform state"
	@echo " make plan: dry run terraform plan ( it will update lambda.zip file)"
	@echo " make apply: deploy terraform changes and create/update resources"
	@echo " make destroy: destroy all previosuly created resources"

clean:
	@rm -rf $(TERRAFORM_DIR)/.terraform

# remove terraform state
remove-state:
	@printf 'WARNING: this will remove terraform state, proceed? [yes/no] '; read -r ans; [ "$$ans" = "yes" ] || { echo "Aborted"; exit 1; }
	@rm -f $(TERRAFORM_DIR)/terraform.tfstate $(TERRAFORM_DIR)/terraform.tfstate.backup


show-vars:
	@echo -e "SERVICE:\t\t$(SERVICE_NAME)"
	@echo -e "AWSREGION:\t\t$(AWS_REGION)"
	@echo -e "AWS PROFILE:\t\t$(AWS_PROFILE)"
	@echo -e "VPC CIDR:\t\t$(VPC_CIDR)"
	@echo -e "PRIVATE SUBNET:\t\t$(PRIVATE_SUBNET_CIDR)"
	@echo -e "RETENTION PERIOD:\t$(RETENTION_PERIOD)"
	@echo -e "LAMBDA FREQ:\t\t$(LAMBDA_SCHEDULE_FREQUENCY)"


# verify what profile is being used
aws-whoami: show-vars
	@echo -n "PROFILE ARN:\t\t"
	@aws sts get-caller-identity --profile $(AWS_PROFILE) --region $(AWS_REGION) --query 'Arn' --output text --no-cli-pager

# sanity check, exit on missing key env vars
check-vars: show-vars aws-whoami
# give a chance to back out
	@printf 'ARE THESE PARAMETERS CORRECT? [yes/no] '; read -r ans; [ "$$ans" = "yes" ] || { echo "Aborted"; exit 1; }


#### 
# initialize terraform but keep state file
init: check-vars
	terraform -chdir=$(TERRAFORM_DIR) init

# dry run
plan: check-vars init
	terraform -chdir=$(TERRAFORM_DIR) plan

# deploy changes
apply: check-vars init
	terraform -chdir=$(TERRAFORM_DIR) apply

# destroy resources
destroy: check-vars init
	terraform -chdir=$(TERRAFORM_DIR) destroy