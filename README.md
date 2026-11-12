# NT548 – Lab 01: Quản lý và triển khai hạ tầng AWS bằng Terraform và CloudFormation

Hạ tầng gồm: VPC, Public Subnet (Internet Gateway), Private Subnet (NAT Gateway), 2 Route Table,
2 EC2 (Public bastion và Private), Security Groups. Cùng một kiến trúc được triển khai bằng
**Terraform (module)** và **CloudFormation (nested stack)**.

```
Internet ── IGW ── Public Subnet  ── Public EC2  (SSH chỉ từ IP chỉ định)
                      │ NAT Gateway (Elastic IP)
                      ▼
               Private Subnet ── Private EC2 (SSH chỉ từ Public SG, ra Internet qua NAT)

Public RT : 0.0.0.0/0 → IGW          Private RT : 0.0.0.0/0 → NAT
```

| | Terraform | CloudFormation |
|---|---|---|
| VPC | 10.0.0.0/16 | 10.10.0.0/16 |
| Public / Private Subnet | 10.0.1.0/24 / 10.0.2.0/24 | 10.10.1.0/24 / 10.10.2.0/24 |
| Region | ap-southeast-1 | ap-southeast-1 |

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

- Terraform >= 1.5, AWS CLI v2 (đã `aws configure`, region `ap-southeast-1`), Git, Git Bash (chạy test trên Windows).
- IAM user: `AmazonEC2FullAccess` (Terraform); thêm `AWSCloudFormationFullAccess`, `AmazonS3FullAccess`, `IAMFullAccess`, `AmazonSSMReadOnlyAccess` (CloudFormation).

> **Chi phí:** NAT Gateway và địa chỉ public IPv4 tính phí theo giờ. Xóa tài nguyên ngay sau khi kiểm tra xong.

## Lưu ý quan trọng về IP SSH

Security Group của Public EC2 chỉ cho SSH từ **một IP cụ thể**. IP này phải là IP mà **EC2 thật sự thấy** khi bạn SSH.
Ở một số mạng (nhiều IP ra Internet, CGNAT), IP đó có thể **khác** IP mà `ifconfig.me` trả về.

Cách xác định (mở tạm cổng 22, đọc IP nguồn, đóng lại ngay):

```powershell
aws ec2 authorize-security-group-ingress --group-id <public_sg_id> --protocol tcp --port 22 --cidr 0.0.0.0/0
ssh -i $KEY ec2-user@<public_ip> 'echo SSH_CLIENT=$SSH_CLIENT'    # lấy IP đầu tiên sau SSH_CLIENT=
aws ec2 revoke-security-group-ingress --group-id <public_sg_id> --protocol tcp --port 22 --cidr 0.0.0.0/0
```

## 1. Terraform

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\nt548-lab01"
copy terraform.tfvars.example terraform.tfvars    # sửa allowed_ssh_cidr = "<IP>/32"
terraform init
terraform validate
terraform plan
terraform apply
& "C:\Program Files\Git\bin\bash.exe" tests/test_infra.sh
```

Kiểm tra thủ công (PowerShell):

```powershell
$KEY  = "$env:USERPROFILE\.ssh\nt548-lab01"
$KEYF = ($env:USERPROFILE -replace '\\','/') + "/.ssh/nt548-lab01"
$PUB  = terraform output -raw public_instance_ip
$PRIV = terraform output -raw private_instance_ip

# 1. SSH vào Public EC2 từ máy bạn
ssh -i $KEY ec2-user@$PUB "hostname; curl -s https://checkip.amazonaws.com"

# 2. Từ Public EC2 nhảy sang Private EC2, và Private EC2 ra Internet qua NAT
#    (IP in ra phải trùng Elastic IP của NAT Gateway)
ssh -i $KEY -o "ProxyCommand=ssh -i $KEYF -W %h:%p ec2-user@$PUB" ec2-user@$PRIV "hostname; curl -s -m 10 https://checkip.amazonaws.com"

# 3. SSH thẳng vào Private EC2 phải thất bại (Connection timed out)
ssh -i $KEY -o ConnectTimeout=8 ec2-user@$PRIV "hostname"
```

Dọn dẹp: `terraform destroy`

## 2. CloudFormation

Root stack tải 3 nested template từ S3 nên cần tạo bucket và upload trước.

```powershell
aws ec2 import-key-pair --key-name nt548-lab01-cfn-key --public-key-material fileb://$env:USERPROFILE/.ssh/nt548-lab01.pub --region ap-southeast-1

$BUCKET = "nt548-lab01-cfn-<ACCOUNT_ID>"
$SSHIP  = "<IP SSH>"
aws s3 mb s3://$BUCKET --region ap-southeast-1
aws s3 cp cloudformation/templates s3://$BUCKET/lab01/templates/ --recursive --region ap-southeast-1

aws cloudformation deploy --stack-name nt548-lab01-cfn --template-file cloudformation/templates/main.yaml `
  --capabilities CAPABILITY_IAM --region ap-southeast-1 --parameter-overrides `
  "TemplatesBucketName=$BUCKET" "TemplatesKeyPrefix=lab01/" "EnvironmentName=nt548-lab01-cfn" `
  "VpcCidr=10.10.0.0/16" "PublicSubnetCidr=10.10.1.0/24" "PrivateSubnetCidr=10.10.2.0/24" `
  "AllowedSSHCidr=$SSHIP/32" "KeyName=nt548-lab01-cfn-key" "InstanceType=t3.micro"

aws cloudformation describe-stacks --stack-name nt548-lab01-cfn --region ap-southeast-1 --query "Stacks[0].Outputs" --output table
& "C:\Program Files\Git\bin\bash.exe" tests/test_cfn.sh
```

Kiểm tra thủ công giống mục Terraform, dùng `PublicInstancePublicIp` và `PrivateInstancePrivateIp` trong Outputs của stack.

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
| TC0 Stack (CloudFormation) | Root stack hoàn tất, có 3 nested stack |
| TC1 VPC | VPC available, 2 subnet thuộc VPC, Default SG |
| TC2 IGW | IGW attach vào VPC |
| TC3 Route Tables | Public RT → IGW, Private RT → NAT, association đúng subnet |
| TC4 NAT | NAT available, nằm ở Public Subnet |
| TC5 Security Groups | Public SG chỉ SSH từ IP chỉ định, Private SG chỉ SSH từ Public SG |
| TC6 EC2 | 2 instance running, Public có IP public, Private không có, đúng subnet, IMDSv2 |
| TC7 Kết nối | Cổng 22 của Public EC2 mở từ máy người dùng |

## Ghi chú thiết kế

- **Default Security Group:** Terraform quản lý và xóa hết rule. CloudFormation không xóa được rule mặc định, nên template chỉ xuất ID ra Outputs.
- **Private EC2** không có IP public, chỉ truy cập qua Public EC2 (bastion) và ra Internet qua NAT Gateway.
- **Bảo mật EC2:** bật IMDSv2, mã hóa ổ đĩa EBS, bật detailed monitoring.
