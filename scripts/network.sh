#!/bin/bash 

set -euo pipefail 

source "$(dirname "${BASH_SOURCE[0]}")/../config/dev.env"

create_vpc(){
        
        #Variables
        local existing_vpc_id
        local vpc_id 

        #Check if a VPC with the specified CIDR already exists.
        echo "Checking for existing VPC with CIDR ${CIDR}...."

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-vpcs.html
        existing_vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=cidr,Values=${CIDR}" \
        --query "Vpcs[0].VpcId" \
        --output text)

        if [[ "$existing_vpc_id" != "None" && -n "$existing_vpc_id" ]]; then
                echo "VPC with CIDR ${CIDR} already exists. VPC ID: ${existing_vpc_id}"
                return 0
        fi
        
        #Create the VPC
        echo "Creating VPC ${VPC_NAME} with CIDR ${CIDR}"

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc.html
        vpc_id=$(aws ec2 create-vpc \
        --cidr-block "$CIDR" \
        --tag-specifications \
            "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
        --query '[Vpc.VpcId]' \
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

create_vpc

