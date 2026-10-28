module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
}

module "nat_gateway" {
  source = "./modules/nat_gateway"

  project_name     = var.project_name
  public_subnet_id = module.vpc.public_subnet_id

  depends_on = [module.vpc]
}

module "route_tables" {
  source = "./modules/route_tables"

  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  igw_id            = module.vpc.igw_id
  nat_gateway_id    = module.nat_gateway.nat_gateway_id
  public_subnet_id  = module.vpc.public_subnet_id
  private_subnet_id = module.vpc.private_subnet_id
}

module "security_groups" {
  source = "./modules/security_groups"

  project_name     = var.project_name
  vpc_id           = module.vpc.vpc_id
  allowed_ssh_cidr = var.allowed_ssh_cidr
}

module "ec2" {
  source = "./modules/ec2"

  project_name      = var.project_name
  instance_type     = var.instance_type
  public_key_path   = var.public_key_path
  public_subnet_id  = module.vpc.public_subnet_id
  private_subnet_id = module.vpc.private_subnet_id
  public_sg_id      = module.security_groups.public_sg_id
  private_sg_id     = module.security_groups.private_sg_id
}
