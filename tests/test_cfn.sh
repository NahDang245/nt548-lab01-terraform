#!/usr/bin/env bash
# Test cases kiem tra ha tang CLOUDFORMATION sau khi deploy
# Chay tu thu muc goc project: bash tests/test_cfn.sh [ten-stack] [ten-moi-truong] [region]
set -u
STACK="${1:-nt548-lab01-cfn}"
ENV_NAME="${2:-nt548-lab01-cfn}"
REGION="${3:-ap-southeast-1}"
PASS=0; FAIL=0

# Loai bo ky tu \r cuoi dong (AWS CLI tren Windows / Git Bash)
aws() { command aws "$@" --region "$REGION" | tr -d '\r'; }
port_open() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null && echo open || echo closed; }
check() {
  if [[ "$2" == "$3" ]]; then echo "  [PASS] $1"; PASS=$((PASS+1))
  else echo "  [FAIL] $1 (thuc te: '$2', mong doi: '$3')"; FAIL=$((FAIL+1)); fi
}
out() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" --output text; }
param() { aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Parameters[?ParameterKey=='$1'].ParameterValue | [0]" --output text; }
instance() { aws ec2 describe-instances --filters "Name=tag:Name,Values=$ENV_NAME-$1-ec2" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].$2" --output text; }

VPC=$(out VpcId); PUB_SN=$(out PublicSubnetId); PRI_SN=$(out PrivateSubnetId)
NAT=$(out NatGatewayId); PUB_RT=$(out PublicRouteTableId); PRI_RT=$(out PrivateRouteTableId)
PUB_SG=$(out PublicSecurityGroupId); PRI_SG=$(out PrivateSecurityGroupId); DEF_SG=$(out DefaultSecurityGroupId)
PUB_IP=$(out PublicInstancePublicIp)
MY_CIDR=$(param AllowedSSHCidr)
IGW=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[0].InternetGatewayId' --output text)

echo "== TC0: Stack =="
ST=$(aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].StackStatus' --output text); check "Root stack hoan tat (CREATE_COMPLETE hoac UPDATE_COMPLETE)" "$([[ "$ST" == CREATE_COMPLETE || "$ST" == UPDATE_COMPLETE ]] && echo ok || echo "$ST")" "ok"
check "Co 3 nested stack" "$(aws cloudformation list-stack-resources --stack-name $STACK --query "length(StackResourceSummaries[?ResourceType=='AWS::CloudFormation::Stack'])" --output text)" "3"

echo "== TC1: VPC =="
check "VPC o trang thai available" "$(aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[0].State' --output text)" "available"
check "Public subnet thuoc VPC" "$(aws ec2 describe-subnets --subnet-ids $PUB_SN --query 'Subnets[0].VpcId' --output text)" "$VPC"
check "Private subnet thuoc VPC" "$(aws ec2 describe-subnets --subnet-ids $PRI_SN --query 'Subnets[0].VpcId' --output text)" "$VPC"
check "Default SG thuoc VPC" "$(aws ec2 describe-security-groups --group-ids $DEF_SG --query 'SecurityGroups[0].VpcId' --output text)" "$VPC"

echo "== TC2: Internet Gateway =="
check "Co IGW attach vao VPC" "$([[ "$IGW" == igw-* ]] && echo yes || echo no)" "yes"

echo "== TC3: Route Tables =="
check "Public RT: 0.0.0.0/0 -> IGW" "$(aws ec2 describe-route-tables --route-table-ids $PUB_RT --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId|[0]" --output text)" "$IGW"
check "Private RT: 0.0.0.0/0 -> NAT" "$(aws ec2 describe-route-tables --route-table-ids $PRI_RT --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId|[0]" --output text)" "$NAT"
check "Public RT gan voi public subnet" "$(aws ec2 describe-route-tables --route-table-ids $PUB_RT --query 'RouteTables[0].Associations[?Main==`false`].SubnetId|[0]' --output text)" "$PUB_SN"
check "Private RT gan voi private subnet" "$(aws ec2 describe-route-tables --route-table-ids $PRI_RT --query 'RouteTables[0].Associations[?Main==`false`].SubnetId|[0]' --output text)" "$PRI_SN"

echo "== TC4: NAT Gateway =="
check "NAT available" "$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT --query 'NatGateways[0].State' --output text)" "available"
check "NAT nam o public subnet" "$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT --query 'NatGateways[0].SubnetId' --output text)" "$PUB_SN"

echo "== TC5: Security Groups =="
check "Public SG chi cho SSH tu IP cua ban" "$(aws ec2 describe-security-groups --group-ids $PUB_SG --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[0].CidrIp|[0]' --output text)" "$MY_CIDR"
check "Public SG chi co 1 inbound rule" "$(aws ec2 describe-security-groups --group-ids $PUB_SG --query 'length(SecurityGroups[0].IpPermissions)' --output text)" "1"
check "Private SG: SSH chi tu Public SG" "$(aws ec2 describe-security-groups --group-ids $PRI_SG --query 'SecurityGroups[0].IpPermissions[0].UserIdGroupPairs[0].GroupId' --output text)" "$PUB_SG"
check "Private SG khong mo CIDR nao" "$(aws ec2 describe-security-groups --group-ids $PRI_SG --query 'length(SecurityGroups[0].IpPermissions[0].IpRanges)' --output text)" "0"

echo "== TC6: EC2 =="
check "Public EC2 running" "$(instance public State.Name)" "running"
check "Private EC2 running" "$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$ENV_NAME-private-ec2" --query 'Reservations[0].Instances[0].State.Name' --output text)" "running"
check "Public EC2 co public IP" "$([[ -n "$PUB_IP" && "$PUB_IP" != "None" ]] && echo yes || echo no)" "yes"
check "Private EC2 KHONG co public IP" "$(instance private PublicIpAddress)" "None"
check "Public EC2 trong public subnet" "$(instance public SubnetId)" "$PUB_SN"
check "Private EC2 trong private subnet" "$(instance private SubnetId)" "$PRI_SN"
check "EC2 bat IMDSv2" "$(instance public MetadataOptions.HttpTokens)" "required"

echo "== TC7: Ket noi =="
check "Public EC2 mo port 22 tu may ban" "$(port_open $PUB_IP 22)" "open"
echo "  (Test SSH Public->Private va Private->Internet lam thu cong, xem README)"

echo; echo "KET QUA: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
