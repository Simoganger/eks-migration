terraform {
  backend "s3" {
    bucket         = "eks-migration-tfstate"
    key            = "cluster2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eks-migration-tfstate-lock"
    encrypt        = true
  }
}
