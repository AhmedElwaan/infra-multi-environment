#!/bin/bash 

set -euo pipefail 

create_security_group(){
    
    #Arguments
    local sg_name="$1"
    local sg_description="$2"

    #Variables
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

#====================================================================================================#



add_security_group_rule(){
    
    #Arguments
    local type="$1"
    local protocol="$2"
    local port_range="$3"
    local cidr="$4"
    local description="$5"

    #Variables
    local output
    local from_port
    local to_port

    # Parse a single port or a range
    if [[ "$port_range" == *-* ]]; then
        
        from_port="${port_range%-*}"
        to_port="${port_range#*-}"
        
        # Reject malformed ranges containing multiple hyphens.
        if [[ "$to_port" == *-* ]]; then
            echo "ERROR: Invalid port range: $port_spec" >&2
            return 1
        fi
    else
        from_port="$port_range"
        to_port="$port_range"
    fi
    
    
    # Ensure both values contain only decimal digits.
    if [[ ! "$from_port" =~ ^[0-9]+$ || ! "$to_port" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Ports must be integers." >&2
        return 1
    fi

    # Ensure both ports are within the valid range.
    if (( from_port < 0 || from_port > 65535 || to_port < 0 || to_port > 65535 )); then
        echo "ERROR: Ports must be between 0 and 65535." >&2
        return 1
    fi

    # Ensure the starting port does not exceed the ending port.
    if (( from_port > to_port )); then
        echo "ERROR: Starting port must not exceed ending port." >&2
        return 1
    fi

    
    if [[ "$type" == "egress" ]]; then
        
        # Authorize the specified inbound traffic and attach a description to the rule.
        if output=$(aws ec2 authorize-security-group-egress \
            --group-id "$sg_id" \
            --ip-permissions \
            "IpProtocol=${protocol},FromPort=${from_port},ToPort=${to_port},IpRanges=[{CidrIp=${cidr},Description='${description}'}]" \
            --region "$REGION" \
            2>&1); then

            echo "Outbound rule added: ${protocol}/${port_range} to ${cidr}"

            # Treat an existing identical rule as an idempotent outcome.
        elif [[ "$output" == *"InvalidPermission.Duplicate"* ]]; then
            echo "Outbound rule already exists: ${protocol}/${port_range} to ${cidr}"

        # Report unexpected AWS CLI errors and return a failure status.
        else
            echo "ERROR: Failed to add outbound rule: $output" >&2
            return 1
        fi
        return 0

    elif [[ "$type" == "ingress" ]]; then
        
        # Authorize the specified inbound traffic and attach a description to the rule.
        if output=$(aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --ip-permissions \
            "IpProtocol=${protocol},FromPort=${from_port},ToPort=${to_port},IpRanges=[{CidrIp=${cidr},Description='${description}'}]" \
            --region "$REGION" \
            2>&1); then

            echo "Inbound rule added: ${protocol}/${port_range} from ${cidr}"

        # Treat an existing identical rule as an idempotent outcome.
        elif [[ "$output" == *"InvalidPermission.Duplicate"* ]]; then
            echo "Inbound rule already exists: ${protocol}/${port_range} from ${cidr}"

        # Report unexpected AWS CLI errors and return a failure status.
        else
            echo "ERROR: Failed to add inbound rule: $output" >&2
            return 1
        fi
        
        return 0

    else
        echo "ERROR: Invalid rule type: $type. Must be 'ingress' or 'egress'." >&2
        return 1
    fi

}


