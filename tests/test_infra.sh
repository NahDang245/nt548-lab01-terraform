#!/usr/bin/env bash
# Test cases kiem tra ha tang sau khi `terraform apply`
# Chay tu thu muc goc: bash tests/test_infra.sh
set -u
PASS=0; FAIL=0

out() { terraform output -raw "$1"; }
check() { # check "mo ta" "gia tri thuc te" "gia tri mong doi"
  if [[ "$2" == "$3" ]]; then echo "  [PASS] $1"; PASS=$((PASS+1))
  else echo "  [FAIL] $1 (thuc te: '$2', mong doi: '$3')"; FAIL=$((FAIL+1)); fi
}

VPC=$(out vpc_id); PUB_SN=$(out public_subnet_id); PRI_SN=$(out private_subnet_id)
IGW=$(out igw_id); NAT=$(out nat_gateway_id)
PUB_RT=$(out public_route_table_id); PRI_RT=$(out private_route_table_id)
PUB_SG=$(out public_sg_id); PRI_SG=$(out private_sg_id); DEF_SG=$(out default_sg_id)
PUB_EC2=$(out public_instance_id); PRI_EC2=$(out private_instance_id)
PUB_IP=$(out public_instance_ip)
MY_CIDR=$(grep allowed_ssh_cidr terraform.tfvars | cut -d'"' -f2)

echo "== TC1: VPC =="
check "VPC o trang thai available" "$(aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[0].State' --output text)" "available"
check "Public subnet thuoc VPC" "$(aws ec2 describe-subnets --subnet-ids $PUB_SN --query 'Subnets[0].VpcId' --output text)" "$VPC"
check "Private subnet thuoc VPC" "$(aws ec2 describe-subnets --subnet-ids $PRI_SN --query 'Subnets[0].VpcId' --output text)" "$VPC"
check "Default SG khong co inbound rule" "$(aws ec2 describe-security-groups --group-ids $DEF_SG --query 'length(SecurityGroups[0].IpPermissions)' --output text)" "0"

echo "== TC2: Internet Gateway =="
check "IGW attach vao VPC" "$(aws ec2 describe-internet-gateways --internet-gateway-ids $IGW --query 'InternetGateways[0].Attachments[0].VpcId' --output text)" "$VPC"

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
check "Public EC2 running" "$(aws ec2 describe-instances --instance-ids $PUB_EC2 --query 'Reservations[0].Instances[0].State.Name' --output text)" "running"
check "Private EC2 running" "$(aws ec2 describe-instances --instance-ids $PRI_EC2 --query 'Reservations[0].Instances[0].State.Name' --output text)" "running"
check "Public EC2 co public IP" "$([[ -n "$PUB_IP" ]] && echo yes || echo no)" "yes"
check "Private EC2 KHONG co public IP" "$(aws ec2 describe-instances --instance-ids $PRI_EC2 --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)" "None"
check "Public EC2 trong public subnet" "$(aws ec2 describe-instances --instance-ids $PUB_EC2 --query 'Reservations[0].Instances[0].SubnetId' --output text)" "$PUB_SN"
check "Private EC2 trong private subnet" "$(aws ec2 describe-instances --instance-ids $PRI_EC2 --query 'Reservations[0].Instances[0].SubnetId' --output text)" "$PRI_SN"

echo "== TC7: Ket noi (SSH port) =="
if command -v nc >/dev/null; then
  check "Public EC2 mo port 22 tu may ban" "$(nc -z -w5 $PUB_IP 22 && echo open || echo closed)" "open"
fi
echo "  (Test SSH Public->Private va Private->Internet lam thu cong, xem README)"

echo; echo "KET QUA: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
