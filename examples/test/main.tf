# Retriving Account ID
data "aws_caller_identity" "current" {}



module "vpc" {
  source  = "shamimice03/vpc/aws"
  version = "1.2.1"

  create                    = true
  vpc_name                  = "aws-ref-vpc"
  cidr                      = "10.5.0.0/16"
  azs                       = ["ap-northeast-3a", "ap-northeast-3b"]
  public_subnet_cidr        = ["10.5.0.0/20", "10.5.16.0/20"]
  intra_subnet_cidr         = ["10.5.32.0/20", "10.5.48.0/20"]
  db_subnet_cidr            = ["10.5.64.0/20", "10.5.80.0/20"]
  enable_dns_hostnames      = true
  enable_dns_support        = true
  enable_single_nat_gateway = false

  tags = merge(
    { "VPC_name" = "External-VPC" },
  )
}

locals {
  vpc_id = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_id
  intra_subnet_id = module.vpc.intra_subnet_id
  db_subnet_id = module.vpc.db_subnet_id
}

module "aws_ref" {
  source = "../../"

  depends_on = [ module.vpc ]

  project_name = "aws-ref-architecture"
  general_tags = {
    "Project_name" = "aws-ref-architecture"
    "Team"         = "platform-team"
    "Env"          = "dev"
  }

  ### VPC
  create_vpc = false

  # Existing vpc id
  vpc_id     = local.vpc_id
  #vpc_id     = module.vpc.vpc_id

  ### Security Groups
  create_alb_sg = true
  alb_sg_name   = "aws-ref-alb-sg"

  create_ec2_sg = true
  ec2_sg_name   = "aws-ref-ec2-sg"

  create_efs_sg = true
  efs_sg_name   = "aws-ref-efs-sg"

  create_rds_sg = true
  rds_sg_name   = "aws-ref-rds-sg"

  create_ssh_sg = true
  ssh_sg_name   = "aws-ref-ssh-sg"
  ssh_ingress_cidr = [ "0.0.0.0/0" ]

  ### Primary Database
  create_primary_database = true # database won't be created
  db_identifier                       = "aws-ref-db"
  create_db_subnet_group              = true
  db_subnet_group_name                = "aws-ref-db-subnet"
  db_subnets                          = local.db_subnet_id
  db_name                             = "userlist"
  db_master_username                  = "admin"
  multi_az                            = false
  master_db_availability_zone         = "ap-northeast-3a"
  engine                              = "mysql"
  engine_version                      = "8.0"
  instance_class                      = "db.t3.micro"
  storage_type                        = "gp2"
  allocated_storage                   = "20"
  max_allocated_storage               = "20"
  db_security_groups                  = [] # This will be populated by module.rds_sg.security_group_id
  publicly_accessible                 = false
  database_port                       = 3306
  backup_retention_period             = 7
  backup_window                       = "03:00-05:00"
  maintenance_window                  = "Sat:05:00-Sat:07:00"
  deletion_protection                 = false
  iam_database_authentication_enabled = false
  enabled_cloudwatch_logs_exports     = ["audit", "error"]
  apply_immediately                   = true
  delete_automated_backups            = true
  skip_final_snapshot                 = true

  ### Replica Database
  create_replica_database = true
  replica_db_identifier                       = "aws-ref-db-replica"
  replica_multi_az                            = false
  replica_db_availability_zone                = "ap-northeast-3b"
  replica_engine                              = "mysql"
  replica_engine_version                      = "8.0"
  replica_instance_class                      = "db.t3.micro"
  replica_storage_type                        = "gp2"
  replica_max_allocated_storage               = "20"
  replica_publicly_accessible                 = false
  replica_database_port                       = 3306
  replica_backup_retention_period             = 7
  replica_backup_window                       = "03:00-05:00"
  replica_maintenance_window                  = "Sat:05:00-Sat:07:00"
  replica_deletion_protection                 = false
  replica_iam_database_authentication_enabled = false
  replica_enabled_cloudwatch_logs_exports     = ["audit", "error"]
  replica_apply_immediately                   = true
  replica_delete_automated_backups            = true
  replica_skip_final_snapshot                 = true

  ### Elastic File System
  efs_create = true
  efs_name                            = "aws-ref-efs"
  efs_mount_target_subnet_ids         = local.intra_subnet_id # This will be populated by module.vpc.intra_subnet_id
  efs_mount_target_security_group_ids = [] # This will be populated by module.efs_sg.security_group_id
  efs_throughput_mode                 = "bursting"
  efs_performance_mode                = "generalPurpose"
  efs_transition_to_ia                = "AFTER_30_DAYS"

  ### Parameters
  create_primary_db_parameters = false
  create_replica_db_parameters = false
  create_efs_parameters        = false

  ### Launch Template
  create_launch_template                 = true
  launch_template_image_id               = "ami-06a5510b6aff4e358" 
  launch_template_instance_type          = "t3.micro"
  launch_template_key_name               = "ec2-access"  # must be existed
  launch_template_sg_ids                 = [] # This will be populated by [module.ec2_sg.security_group_id, module.ssh_sg.security_group_id]
  launch_template_update_default_version = true
  launch_template_name_prefix            = "aws-ref"
  launch_template_device_name            = "/dev/xvda"
  launch_template_volume_size            = 20
  launch_template_volume_type            = "gp2"
  launch_template_delete_on_termination  = true
  launch_template_enable_monitoring      = false
  launch_template_userdata_file_path     = "examples/on-existing-vpc/init.sh"
  launch_template_resource_type          = "instance"


  ### ACM - Route53
  create_certificates = true
  acm_domain_names = [
    "fun.kubecloud.net",
    "www.fun.kubecloud.net",
  ]
  acm_hosted_zone_name       = "kubecloud.net"
  acm_validation_method      = "DNS"
  acm_private_zone           = false
  acm_allow_record_overwrite = true
  acm_ttl                    = 60

  ### ALB
  create_lb                       = true
  alb_name_prefix                 = "awsref"
  load_balancer_type              = "application"
  alb_subnets                     = local.public_subnet_id # This will be populated by module.vpc.public_subnet_id,
  alb_security_groups             = [] # This will be populated by module.alb_sg.security_group_id
  alb_target_group_name_prefix    = "ref-tg"
  alb_acm_certificate_domain_name = "fun.kubecloud.net"

  ### ALB - Route5
  create_alb_route53_record = true
  # if record name and zone name not given. It will featch it from `ACM-Route53 Module`
  alb_route53_record_names = [
    "fun.kubecloud.net",
    "www.fun.kubecloud.net",
  ]
  alb_route53_zone_name              = "kubecloud.net"
  alb_route53_record_type            = "A"
  alb_route53_private_zone           = false
  alb_route53_evaluate_target_health = true
  alb_route53_allow_record_overwrite = true

  ### Custom Policy
  create_custom_policy          = true
  custom_iam_policy_name_prefix = "ListAllS3Buckets"
  custom_iam_policy_path        = "/"
  custom_iam_policy_description = "List all s3 buckets"
  custom_iam_policy_json        = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "s3:ListAllMyBuckets",
        "Resource": "*"
      }
    ]
}
EOF

  ### IAM Instance Profile
  create_instance_profile                = true
  instance_profile_role_name             = "aws-ref-instance-role"
  instance_profile_instance_profile_name = "aws-ref-instance-role"
  instance_profile_role_path = "/"
  instance_profile_managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientFullAccess",
    "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy",
  ]
  instance_profile_custom_policy_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AllowFromJapan",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AllowFromJapanAndGlobalServices",
  ]

  ### Auto Scaling
  asg_create                    = true
  asg_name                      = "aws-ref-asg"
  asg_vpc_zone_identifier       = local.public_subnet_id # This will be populated by module.vpc.public_subnet_id
  asg_desired_capacity          = 2
  asg_min_size                  = 2
  asg_max_size                  = 4
  asg_wait_for_capacity_timeout = "10m"
  asg_health_check_type         = "ELB"
  asg_health_check_grace_period = 300
  asg_enable_monitoring         = true

}
