#!/bin/bash 

set -euo pipefail 

create_vpc(){

        #Variables
        local existing_vpc_id

        #Check if a VPC with the specified CIDR already exists.
        echo "Checking for existing VPC with CIDR ${CIDR}...."

        #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-vpcs.html
        existing_vpc_id=$(aws ec2 describe-vpcs \
        --region "$REGION" \
        --filters "Name=cidr,Values=${CIDR}" \
                "Name=tag:Name,Values=${VPC_NAME}" \
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
        echo "===================================================================================================="
}

#====================================================================================================#

create_subnet(){

        #Arguments
        local subnet_cidr="$1"
        local subnet_name="$2"
        local az="$3"

        #Variables
        local existing_subnet_id

        #Check if a Subnet with the specified CIDR already exists.
        echo "Checking for existing Subnet with CIDR ${subnet_cidr}...."
        
        #https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-subnets.html
        existing_subnet_id=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters \
                "Name=vpc-id,Values=${vpc_id}" \
                "Name=cidr-block,Values=${subnet_cidr}" \
        --query 'Subnets[0].SubnetId' \
        --output text)

        if [[ "$existing_subnet_id" != "None" && -n "$existing_subnet_id" ]]; then
                echo "Subnet with CIDR ${subnet_cidr} already exists. Subnet ID: ${existing_subnet_id}"
                subnet_id="$existing_subnet_id"
                return 0
        fi

        #Create the Subnet
        echo "Creating Subnet ${subnet_name} with CIDR ${subnet_cidr} in VPC ${VPC_NAME}"
        
        #https://docs.aws.amazon.com/cli/latest/reference/ec2/create-subnet.html
        subnet_id=$(aws ec2 create-subnet \
        --vpc-id "$vpc_id" \
        --cidr-block "$subnet_cidr" \
        --availability-zone "$az" \
        --tag-specifications \
            "ResourceType=subnet,Tags=[{Key=Name,Value=$subnet_name}]" \
        --query 'Subnet.SubnetId' \
        --output text \
        --region "$REGION")

        if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]; then
                echo "ERROR: Failed to create subnet."
                return 1
        fi

        echo "Subnet Created Successfully!"
        echo "Subnet ID: $subnet_id"
        echo "Subnet Name: $subnet_name"
        echo "Subnet CIDR: $subnet_cidr"
        echo "Availability Zone: $az"
        echo "===================================================================================================="

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
        echo "===================================================================================================="


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
        echo "===================================================================================================="

}

#====================================================================================================#
create_route_table(){

        #Arguments
        ROUTE_TABLE_NAME="$1"

        # Variables
        local existing_route_table_id

        # Check whether the route table already exists in this VPC
        echo "Checking for existing route table ${ROUTE_TABLE_NAME}..."

        existing_route_table_id=$(aws ec2 describe-route-tables \
                --region "$REGION" \
                --filters \
                "Name=vpc-id,Values=${vpc_id}" \
                "Name=tag:Name,Values=${ROUTE_TABLE_NAME}" \
                --query 'RouteTables[0].RouteTableId' \
                --output text)

        if [[ "$existing_route_table_id" != "None" && -n "$existing_route_table_id" ]]; then
                echo "Route table already exists: ${existing_route_table_id}"
                route_table_id="$existing_route_table_id"
                return 0
        fi

        # Create the route table
        echo "Creating route table ${ROUTE_TABLE_NAME}..."

        route_table_id=$(aws ec2 create-route-table \
                --vpc-id "$vpc_id" \
                --tag-specifications \
                "ResourceType=route-table,Tags=[{Key=Name,Value=${ROUTE_TABLE_NAME}}]" \
                --query 'RouteTable.RouteTableId' \
                --output text \
                --region "$REGION")       

        if [[ -z "$route_table_id" || "$route_table_id" == "None" ]]; then
                echo "ERROR: Failed to create route table."
                return 1
        fi

        echo "Route table created successfully!"
        echo "Route table name: ${ROUTE_TABLE_NAME}"
        echo "Route table ID: ${route_table_id}"
        echo "===================================================================================================="

}

#====================================================================================================#

create_igw_route(){
        
        # Variables
        local existing_route_target

        echo "Checking for existing Route..."

        # Check whether 0.0.0.0/0 already exists
        existing_route_target=$(aws ec2 describe-route-tables \
                --route-table-ids "$route_table_id" \
                --region "$REGION" \
                --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" \
                --output text)


        # If the route already points to our IGW, nothing to do
        if [[ "$existing_route_target" == "$igw_id" ]]; then
                echo "Route already points to IGW: $igw_id"
                return 0
        fi

        # Do not overwrite an existing default route to another target
        if [[ -n "$existing_route_target" && "$existing_route_target" != "None" ]]; then
                echo "ERROR: A route already exists with target: $existing_route_target"
                return 1
        fi

        # Create the default route
        echo "Creating Route to Internet Gateway..."

        aws ec2 create-route \
                --route-table-id "$route_table_id" \
                --destination-cidr-block "0.0.0.0/0" \
                --gateway-id "$igw_id" \
                --region "$REGION"

        echo "Route created successfully!"
        echo "===================================================================================================="

}

associate_route_table(){
        #Arguments
        local fun_subnet_id="$1"
        local fun_route_table_id="$2"
        # Variables
        local existing_route_table_id

        echo "Checking existing route table association for subnet ${fun_subnet_id}..."

        # Find the route table currently associated with this subnet
        existing_route_table_id=$(aws ec2 describe-route-tables \
                --region "$REGION" \
                --filters "Name=association.subnet-id,Values=${fun_subnet_id}" \
                --query 'RouteTables[0].RouteTableId' \
                --output text)

      
        # If already associated with the intended route table, do nothing
        if [[ "$existing_route_table_id" == "$fun_route_table_id" ]]; then
                echo "Subnet is already associated with route table ${fun_route_table_id}"
                return 0
        fi

        # If associated with another explicit route table, don't silently change it
        if [[ -n "$existing_route_table_id" && "$existing_route_table_id" != "None" ]]; then
                echo "ERROR: Subnet is already associated with another route table: ${existing_route_table_id}"
                return 1
        fi

        # Associate subnet with the public route table
        echo "Associating subnet ${fun_subnet_id} with route table ${fun_route_table_id}..."

        aws ec2 associate-route-table \
                --subnet-id "$fun_subnet_id" \
                --route-table-id "$fun_route_table_id" \
                --region "$REGION"

        echo "Subnet associated with route table successfully!"
        echo "===================================================================================================="

}

#--------------------------Global Variables---------------------------

PUBLIC_SUBNET_IDS=()
PRIVATE_SUBNET_IDS=()

public_route_table_id=""
private_route_table_id=""


#--------------------------Functions Call---------------------------

create_vpc

for i in "${!PUBLIC_SUBNET_CIDRS[@]}"; do
        create_subnet \
                "${PUBLIC_SUBNET_CIDRS[$i]}" \
                "${PUBLIC_SUBNET_NAMES[$i]}" \
                "${PUBLIC_SUBNET_AZS[$i]}"

        PUBLIC_SUBNET_IDS+=("$subnet_id")    
done

for i in "${!PRIVATE_SUBNET_CIDRS[@]}"; do
        create_subnet \
                "${PRIVATE_SUBNET_CIDRS[$i]}" \
                "${PRIVATE_SUBNET_NAMES[$i]}" \
                "${PRIVATE_SUBNET_AZS[$i]}"
        
        PRIVATE_SUBNET_IDS+=("$subnet_id")
done

create_IGW
attach_igw_to_vpc


for i in "${!ROUTE_TABLE_NAMES[@]}"; do

    create_route_table "${ROUTE_TABLE_NAMES[$i]}"

    if [[ "${ROUTE_TABLE_NAMES[$i],,}" == *public* ]]; then

        public_route_table_id="$route_table_id"
        create_igw_route

    elif [[ "${ROUTE_TABLE_NAMES[$i],,}" == *private* ]]; then

        private_route_table_id="$route_table_id"

    fi

done


for subnet_id in "${PUBLIC_SUBNET_IDS[@]}"; do
    associate_route_table "$subnet_id" "$public_route_table_id"
done

for subnet_id in "${PRIVATE_SUBNET_IDS[@]}"; do
    associate_route_table "$subnet_id" "$private_route_table_id"
done    