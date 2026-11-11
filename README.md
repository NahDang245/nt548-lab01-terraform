# NT548 – Lab 01: Quản lý và triển khai hạ tầng AWS bằng Terraform và CloudFormation

Hạ tầng gồm: VPC `10.x.0.0/16`, Public Subnet (Internet Gateway), Private Subnet (NAT Gateway),
2 Route Table, 2 EC2 (Public bastion và Private), Security Groups.
Cùng một kiến trúc được triển khai bằng **Terraform (module)** và **CloudFormation (nested stack)**.

```
Internet ── IGW ── Public Subnet 10.x.1.0/24 ── Public EC2 (SSH chỉ từ IP của bạn)
                      │  NAT Gateway (EIP)
                      ▼
               Private Subnet 10.x.2.0/24 ── Private EC2 (SSH chỉ từ Public SG, ra Internet qua NAT)
Public RT : 0.0.0.0/0 → IGW        Private RT : 0.0.0.0/0 → NAT
```

## Cấu trúc thư mục

```
├── main.tf, variables.tf, outputs.tf, providers.tf   # Terraform (root)
├── modules/
│   ├── vpc/              # VPC, Subnets, IGW, Default SG (khóa hết rule)
│   ├── nat_gateway/      # Elastic IP + NAT Gateway
│   ├── route_tables/     # Public/Private Route Table + association
│   ├── security_groups/  # Public EC2 SG, Private EC2 SG
│   └── ec2/              # Key pair + Public/Private EC2 (IMDSv2, EBS mã hóa)
├── cloudformation/
│   └── templates/        # main.yaml (root) → vpc.yaml, security-groups.yaml, ec2.yaml
└── tests/
    ├── test_infra.sh     # test case cho Terraform
    └── test_cfn.sh       # test case cho CloudFormation
```

## Yêu cầu

Terraform >= 1.5, AWS CLI v2 (đã `aws configure`, region `ap-southeast-1`), Git, Git Bash (chạy test trên Windows).
IAM user cần: `AmazonEC2FullAccess` (Terraform) và thêm `AWSCloudFormationFullAccess`, `AmazonS3FullAccess`,
`IAMFullAccess`, `AmazonSSMReadOnlyAccess` (CloudFormation).

> **Chi phí:** NAT Gateway tính phí theo giờ, public IPv4 tính phí theo giờ. Xóa tài nguyên ngay sau khi kiểm tra xong.

## 1. Terraform

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\nt548-lab01"
copy terraform.tfvars.example terraform.tfvars    # sửa allowed_ssh_cidr = "<IP public của bạn>/32"
terraform init
terraform validate
terraform plan
terraform apply
bash tests/test_infra.sh
```

Kiểm tra thủ công (Git Bash hoặc PowerShell có OpenSSH):

```bash
ssh-add ~/.ssh/nt548-lab01
ssh -A ec2-user@$(terraform output -raw public_instance_ip)   # vào Public EC2
ssh ec2-user@<private_instance_ip>                           # từ Public sang Private
curl -s https://checkip.amazonaws.com                         # trên Private: phải ra IP của NAT Gateway
```

Dọn dẹp: `terraform destroy`

## 2. CloudFormation

Root stack tải 3 nested template từ S3 nên cần tạo bucket và upload trước.

```powershell
aws ec2 import-key-pair --key-name nt548-lab01-cfn-key --public-key-material fileb://$env:USERPROFILE/.ssh/nt548-lab01.pub --region ap-southeast-1

$BUCKET = "nt548-lab01-cfn-<ACCOUNT_ID>"
aws s3 mb s3://$BUCKET --region ap-southeast-1
aws s3 cp cloudformation/templates s3://$BUCKET/lab01/templates/ --recursive --region ap-southeast-1

aws cloudformation deploy --stack-name nt548-lab01-cfn --template-file cloudformation/templates/main.yaml `
  --capabilities CAPABILITY_IAM --region ap-southeast-1 --parameter-overrides `
  TemplatesBucketName=$BUCKET TemplatesKeyPrefix=lab01/ EnvironmentName=nt548-lab01-cfn `
  VpcCidr=10.10.0.0/16 PublicSubnetCidr=10.10.1.0/24 PrivateSubnetCidr=10.10.2.0/24 `
  AllowedSSHCidr=<IP>/32 KeyName=nt548-lab01-cfn-key InstanceType=t3.micro

bash tests/test_cfn.sh
```

Kiểm tra thủ công tương tự mục Terraform, dùng IP trong Outputs của stack
(`aws cloudformation describe-stacks --stack-name nt548-lab01-cfn --query "Stacks[0].Outputs"`).

Dọn dẹp:

```powershell
aws cloudformation delete-stack --stack-name nt548-lab01-cfn --region ap-southeast-1
aws cloudformation wait stack-delete-complete --stack-name nt548-lab01-cfn --region ap-southeast-1
aws s3 rb s3://$BUCKET --force
aws ec2 delete-key-pair --key-name nt548-lab01-cfn-key --region ap-southeast-1
```

## Test cases

| Nhóm | Nội dung kiểm tra |
|---|---|
| TC1 VPC | VPC available, 2 subnet thuộc VPC, Default SG |
| TC2 IGW | IGW attach vào VPC |
| TC3 Route Tables | Public RT → IGW, Private RT → NAT, association đúng subnet |
| TC4 NAT | NAT available, nằm ở Public Subnet |
| TC5 Security Groups | Public SG chỉ SSH từ IP chỉ định, Private SG chỉ SSH từ Public SG |
| TC6 EC2 | 2 instance running, Public có IP public, Private không có, đúng subnet |
| TC7 Kết nối | Cổng 22 của Public EC2 mở từ máy người dùng |
