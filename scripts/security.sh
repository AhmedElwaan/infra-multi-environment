#!/bin/bash 

set -euo pipefail 

create_security_group(){
    #Variables
    local sg_name="$1"
    local sg_description="$2"
    local existing_sg_id

    #Check if the security group already exists

    echo "Checking if security group '$sg_name' already exists in VPC '$vpc_id'..."

    #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-security-groups.html
    existing_sg_id=$(aws ec2 describe-security-groups \
        --filters \
            "Name=vpc-id,Values=${vpc_id}" \
            "Name=group-name,Values=${sg_name}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region "$REGION")

    if [[ "$existing_sg_id" != "None" && -n "$existing_sg_id" ]]; then
        echo "Security group already exists: $existing_sg_id"
        sg_id="$existing_sg_id"
        return 0
    fi

    echo "Creating security group '$sg_name' in VPC '$vpc_id'..."

    #https://docs.aws.amazon.com/cli/latest/reference/ec2/create-security-group.html
    sg_id=$(aws ec2 create-security-group \
        --group-name "$sg_name" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${sg_name}}]" \
        --description "$sg_description" \
        --vpc-id "$vpc_id" \
        --query 'GroupId' \
        --output text \
        --region "$REGION")

    if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
            echo "Failed to create security group."
            return 1
    fi    

    echo "Created security group successfully"
    echo "Security Group ID: $sg_id"
    echo "Security Group Name: $sg_name"
    echo "Security Group Description: $sg_description"
    echo "VPC ID: $vpc_id"
}

create_security_group "test-sg" "testing"