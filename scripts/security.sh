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
            echo "ERROR: Invalid port range: $port_range" >&2
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

#====================================================================================================#

create_nacl() {

    # Arguments
    local nacl_name="$1"

    # Variables
    local existing_nacl_id

    echo "Checking if Network ACL '$nacl_name' already exists in VPC '$vpc_id'..."

    # Check if the NACL already exists in this VPC
    existing_nacl_id=$(aws ec2 describe-network-acls \
        --filters \
            "Name=vpc-id,Values=${vpc_id}" \
            "Name=tag:Name,Values=${nacl_name}" \
        --query 'NetworkAcls[0].NetworkAclId' \
        --output text \
        --region "$REGION")

    # Reuse the existing NACL if found
    if [[ "$existing_nacl_id" != "None" && -n "$existing_nacl_id" ]]; then
        echo "Network ACL '$nacl_name' already exists: $existing_nacl_id"
        nacl_id="$existing_nacl_id"
        return 0
    fi

    # Create a new NACL
    echo "Creating Network ACL '$nacl_name'..."

    if ! nacl_id=$(aws ec2 create-network-acl \
        --vpc-id "$vpc_id" \
        --query 'NetworkAcl.NetworkAclId' \
        --output text \
        --region "$REGION"); then

        echo "ERROR: Failed to create Network ACL '$nacl_name'" >&2
        return 1
    fi

    if [[ -z "$nacl_id" || "$nacl_id" == "None" ]]; then
        echo "ERROR: AWS returned an invalid NACL ID" >&2
        return 1
    fi

    aws ec2 create-tags \
    --resources "$nacl_id" \
    --tags "Key=Name,Value=${nacl_name}" \
    --region "$REGION"

    echo "Network ACL created successfully: $nacl_id"
}

#====================================================================================================#

add_nacl_rule() {

    # Arguments
    local type="$1"
    local rule_number="$2"
    local protocol="$3"
    local port_range="$4"
    local cidr="$5"
    local action="$6"

    # Variables
    local from_port
    local to_port

    # Parse a single port or a range
    if [[ "$port_range" == *-* ]]; then
        
        from_port="${port_range%-*}"
        to_port="${port_range#*-}"
        
        # Reject malformed ranges containing multiple hyphens.
        if [[ "$to_port" == *-* ]]; then
            echo "ERROR: Invalid port range: $port_range" >&2
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

    # Validate direction
    if [[ "$type" != "ingress" && "$type" != "egress" ]]; then
        echo "ERROR: Type must be ingress or egress" >&2
        return 1
    fi

    echo "Adding $type rule $rule_number to NACL '$nacl_id'..."

    # Create NACL rule
    if ! aws ec2 create-network-acl-entry \
        --network-acl-id "$nacl_id" \
        "--$type" \
        --rule-number "$rule_number" \
        --protocol "$protocol" \
        --port-range "From=${from_port},To=${to_port}" \
        --cidr-block "$cidr" \
        --rule-action "$action" \
        --region "$REGION"; then

        echo "ERROR: Failed to add $type rule $rule_number" >&2
        return 1
    fi

    echo "$type rule $rule_number added successfully."
}

#====================================================================================================#

associate_nacl_with_subnet() {

    # Arguments
    local nacl_id="$1"
    local subnet_id="$2"

    # Variables
    local current_nacl_id

    echo "Checking NACL association for subnet '$subnet_id'..."

    # Find the NACL currently associated with this subnet
    if ! current_nacl_id=$(aws ec2 describe-network-acls \
        --filters "Name=association.subnet-id,Values=${subnet_id}" \
        --query 'NetworkAcls[0].NetworkAclId' \
        --output text \
        --region "$REGION"); then

        echo "ERROR: Failed to check the subnet's NACL association" >&2
        return 1
    fi

    # Skip if the desired NACL is already associated
    if [[ "$current_nacl_id" == "$nacl_id" ]]; then
        echo "Subnet '$subnet_id' is already associated with NACL '$nacl_id'."
        return 0
    fi

    # Associate the subnet with the requested NACL
    echo "Associating subnet '$subnet_id' with NACL '$nacl_id'..."

    if ! aws ec2 associate-network-acl \
        --network-acl-id "$nacl_id" \
        --subnet-id "$subnet_id" \
        --region "$REGION"; then

        echo "ERROR: Failed to associate NACL '$nacl_id' with subnet '$subnet_id'" >&2
        return 1
    fi

    echo "Subnet '$subnet_id' associated successfully with NACL '$nacl_id'."
}

#--------------------------Functions Call---------------------------

for i in "${!SECURITY_GROUP_NAMES[@]}"; do
    create_security_group "${SECURITY_GROUP_NAMES[$i]}" \
    "${SECURITY_GROUP_DESCRIPTIONS[$i]}"
done

for sg_name in "${SECURITY_GROUP_NAMES[@]}"; do
    add_security_group_rule "ingress" \
        "${SG_INBOUND_PROTOCOL[$sg_name]}" \
        "${SG_INBOUND_PORTS[$sg_name]}" \
        "${SG_INBOUND_CIDR[$sg_name]}" \
        "${SG_INBOUND_DESCRIPTION[$sg_name]}"
    add_security_group_rule "egress" "${SG_OUTBOUND_PROTOCOL[$sg_name]}" \
        "${SG_OUTBOUND_PORTS[$sg_name]}" \
        "${SG_OUTBOUND_CIDR[$sg_name]}" \
        "${SG_OUTBOUND_DESCRIPTION[$sg_name]}"
done


for nacl_name in "${NACL_NAMES[@]}"; do

    create_nacl "$nacl_name"

    add_nacl_rule \
        "ingress" \
        "${NACL_INBOUND_RULE_NUMBERS[$nacl_name]}" \
        "${NACL_INBOUND_PROTOCOL[$nacl_name]}" \
        "${NACL_INBOUND_PORTS[$nacl_name]}" \
        "${NACL_INBOUND_CIDR[$nacl_name]}" \
        "${NACL_INBOUND_ACTION[$nacl_name]}"

    add_nacl_rule \
        "egress" \
        "${NACL_OUTBOUND_RULE_NUMBERS[$nacl_name]}" \
        "${NACL_OUTBOUND_PROTOCOL[$nacl_name]}" \
        "${NACL_OUTBOUND_PORTS[$nacl_name]}" \
        "${NACL_OUTBOUND_CIDR[$nacl_name]}" \
        "${NACL_OUTBOUND_ACTION[$nacl_name]}"

    if [[ "$nacl_name" == *Public* ]]; then

        for subnet_id in "${PUBLIC_SUBNET_IDS[@]}"; do
            associate_nacl_with_subnet "$nacl_id" "$subnet_id"
        done

    elif [[ "$nacl_name" == *Private* ]]; then

        for subnet_id in "${PRIVATE_SUBNET_IDS[@]}"; do
            associate_nacl_with_subnet "$nacl_id" "$subnet_id"
        done

    else
        echo "Unknown NACL type: $nacl_name" >&2
        return 1
    fi

done