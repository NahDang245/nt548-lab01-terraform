# NT548 - Lab 01: Terraform quan ly ha tang AWS

## Kien truc
VPC (10.0.0.0/16) gom Public Subnet (IGW) + Private Subnet (NAT Gateway), 2 Route Tables, 2 EC2 (public/private), Security Groups.

## Cau truc
- `modules/vpc` : VPC, Subnets, IGW, Default SG
- `modules/nat_gateway` : EIP + NAT Gateway
- `modules/route_tables` : Public/Private Route Table + association
- `modules/security_groups` : Public EC2 SG, Private EC2 SG
- `modules/ec2` : Key pair + Public/Private EC2
- `tests/test_infra.sh` : test cases kiem tra sau khi deploy

## Yeu cau
Terraform >= 1.5, AWS CLI da `aws configure`, SSH key pair.

## Cach chay
```bash
ssh-keygen -t ed25519 -f ~/.ssh/nt548-lab01 -N ""
cp terraform.tfvars.example terraform.tfvars   # sua allowed_ssh_cidr = "<IP>/32"
terraform init
terraform fmt -recursive && terraform validate
terraform plan
terraform apply
bash tests/test_infra.sh
```

## Kiem tra thu cong
```bash
ssh-add ~/.ssh/nt548-lab01
ssh -A ec2-user@$(terraform output -raw public_instance_ip)
# Tren Public EC2:
ssh ec2-user@<private_instance_ip>
# Tren Private EC2:
curl -I https://example.com     # ra Internet qua NAT
```

## Don dep
```bash
terraform destroy
```
