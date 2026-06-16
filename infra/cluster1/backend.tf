terraform {
  backend "s3" {
    bucket         = "eks-migration-tfstate"
    key            = "cluster1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eks-migration-tfstate-lock"
    encrypt        = true
  }
}
