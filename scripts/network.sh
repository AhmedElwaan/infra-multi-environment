#!/bin/bash 

set -euo pipefail 

source "$(dirname "${BASH_SOURCE[0]}")/../config/dev.env"

create_vpc(){

        #Variables
        local existing_vpc_id

        #Check if a VPC with the specified CIDR already exists.
        echo "Checking for existing VPC with CIDR ${CIDR}...."

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-vpcs.html
        existing_vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=cidr,Values=${CIDR}" \
        --query 'Vpcs[0].VpcId' \
        --output text)

        if [[ "$existing_vpc_id" != "None" && -n "$existing_vpc_id" ]]; then
                echo "VPC with CIDR ${CIDR} already exists. VPC ID: ${existing_vpc_id}"
                vpc_id="$existing_vpc_id"
                return 0
                
        fi

        #Create the VPC
        
        echo "Creating VPC ${VPC_NAME} with CIDR ${CIDR}"

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc.html
        vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$CIDR" \
        --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query 'Vpc.VpcId' \
        --output text \
        --region "$REGION")

        if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
                echo "Failed to create VPC."
                return 1
        fi

        echo "VPC Created Successfully!"
        echo "VPC ID: $vpc_id"
        echo "VPC Name: $VPC_NAME"
        echo "CIDR: $CIDR"
        echo "Region: $REGION"
}

#====================================================================================================#

create_subnet(){

        #Check if a Subnet with the specified CIDR already exists.
        echo "Checking for existing Subnet with CIDR ${SUBNET_CIDR}...."
        
        local existing_subnet_id

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-subnets.html
        existing_subnet_id=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters \
                "Name=vpc-id,Values=${vpc_id}" \
                "Name=cidr-block,Values=${SUBNET_CIDR}" \
        --query 'Subnets[0].SubnetId' \
        --output text)

        if [[ "$existing_subnet_id" != "None" && -n "$existing_subnet_id" ]]; then
                echo "Subnet with CIDR ${SUBNET_CIDR} already exists. Subnet ID: ${existing_subnet_id}"
                subnet_id="$existing_subnet_id"
                return 0
        fi

        #Create the Subnet
        echo "Creating Subnet ${SUBNET_NAME} with CIDR ${SUBNET_CIDR} in VPC ${VPC_NAME}"
        
        #https://docs.aws.amazon.com/cli/latest/reference/ec2/create-subnet.html
        subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$SUBNET_CIDR" \
        --availability-zone "$AZ" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME}]" \
        --query 'Subnet.SubnetId' \
        --output text \
        --region "$REGION")

        if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]; then
                echo "ERROR: Failed to create subnet."
                return 1
        fi

        echo "Subnet Created Successfully!"
        echo "Subnet ID: $subnet_id"
        echo "Subnet Name: $SUBNET_NAME"
        echo "Subnet CIDR: $SUBNET_CIDR"
        echo "Availability Zone: $AZ"
}

#====================================================================================================#

create_IGW(){

        #Variables 
        local existing_igw_id

        #Check if an Internet Gateway already exists for the VPC
        echo "Checking for existing Internet Gateway for VPC ${VPC_NAME}...."
        
        #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-internet-gateways.html
        existing_igw_id=$(aws ec2 describe-internet-gateways \
        --region "$REGION" \
        --filters \
                "Name=attachment.vpc-id,Values=${vpc_id}" \
                "Name=tag:Name,Values=${IGW_NAME}" \
        --query 'InternetGateways[0].InternetGatewayId' \
        --output text)

        if [[ "$existing_igw_id" != "None" && -n "$existing_igw_id" ]]; then
                echo "Internet Gateway already exists for VPC ${VPC_NAME}. IGW ID: ${existing_igw_id}"
                igw_id="$existing_igw_id"
                return 0
        fi

        #Create the Internet Gateway
        echo "Creating Internet Gateway for VPC ${VPC_NAME}..."
        
        #https://docs.aws.amazon.com/cli/latest/reference/ec2/create-internet-gateway.html
        igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications \
            "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$IGW_NAME}]" \
        --query 'InternetGateway.InternetGatewayId' \
        --output text \
        --region "$REGION")

        if [[ -z "$igw_id" || "$igw_id" == "None" ]]; then
                echo "ERROR: Failed to create Internet Gateway."
                return 1
        fi

        echo "Internet Gateway Created Successfully!"
        echo "IGW NAME: $IGW_NAME"
        echo "IGW ID: $igw_id"

}

#====================================================================================================#


attach_igw_to_vpc(){

        #Attach the Internet Gateway to the VPC
        local attached_vpc_id

        echo "Checking IGW attachment status..."

        attached_vpc_id=$(aws ec2 describe-internet-gateways \
        --internet-gateway-ids "$igw_id" \
        --region "$REGION" \
        --query 'InternetGateways[0].Attachments[0].VpcId' \
        --output text)

         if [[ "$attached_vpc_id" == "$vpc_id" ]]; then
                echo "IGW is already attached to VPC ${vpc_id}."
                return 0
        fi

        if [[ "$attached_vpc_id" != "None" && -n "$attached_vpc_id" ]]; then
                echo "ERROR: IGW is attached to another VPC: ${attached_vpc_id}" >&2
                return 1
        fi

        echo "Attaching Internet Gateway ${igw_id} to VPC ${vpc_id}..."

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/attach-internet-gateway.html
        aws ec2 attach-internet-gateway \
        --internet-gateway-id "$igw_id" \
        --vpc-id "$vpc_id" \
        --region "$REGION"

        echo "Internet Gateway ${igw_id} attached to VPC ${vpc_id} successfully."
}

#====================================================================================================#
create_vpc
create_subnet
create_IGW
attach_igw_to_vpc
