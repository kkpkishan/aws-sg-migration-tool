#!/bin/bash

echo "Enter source region:"
read source_region

echo "Enter source Security Group ID:"
read source_sg_id

# Export the specific security group's rules
sg=$(aws ec2 describe-security-groups --group-ids $source_sg_id --region $source_region)
sg_name=$(echo $sg | jq -r '.SecurityGroups[0].GroupName')
sg_description=$(echo $sg | jq -r '.SecurityGroups[0].Description')
sg_tags=$(echo $sg | jq '.SecurityGroups[0].Tags')

echo "Security Group to export: $sg_name ($source_sg_id)"
echo "Description: $sg_description"

# Display Ingress Rules
echo "Ingress Rules:"
echo $sg | jq '.SecurityGroups[0].IpPermissions'

# Display Egress Rules, excluding the default rule
echo "Egress Rules (excluding default -1, 0.0.0.0/0):"
echo $sg | jq '[.SecurityGroups[0].IpPermissionsEgress[] | select(.IpProtocol != "-1" or (.IpRanges[]? | .CidrIp != "0.0.0.0/0"))]'

# Ask for validation
echo "Review the above rules. Do you want to proceed with importing these rules to the destination region? (yes/no)"
read validation_response

if [ "$validation_response" != "yes" ]; then
    echo "Import cancelled."
    exit 1
fi

echo "Enter destination region:"
read dest_region

echo "Enter destination VPC ID:"
read dest_vpc_id

# Proceed with import
# Create security group in destination region with adjusted VPC ID
new_sg_name="${sg_name}-copy"
new_sg=$(aws ec2 create-security-group --group-name "$new_sg_name" --description "$sg_description" --vpc-id $dest_vpc_id --region $dest_region)
new_sg_id=$(echo $new_sg | jq -r '.GroupId')
echo "Created new Security Group $new_sg_id in $dest_region."

# Apply tags from source security group to the new security group
if [ "$sg_tags" != "null" ] && [ "$sg_tags" != "[]" ]; then
    aws ec2 create-tags --resources $new_sg_id --tags "$sg_tags" --region $dest_region
    echo "Tags copied to $new_sg_id."
fi

# Copy ingress rules
ingress_rules=$(echo $sg | jq '.SecurityGroups[0].IpPermissions' | jq -c)
if [ "$ingress_rules" != "null" ] && [ "$ingress_rules" != "[]" ]; then
    aws ec2 authorize-security-group-ingress --group-id $new_sg_id --ip-permissions "$ingress_rules" --region $dest_region
    echo "Ingress rules copied to $new_sg_id."
fi

echo "Import completed."
