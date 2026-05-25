terraform {
  backend "s3" {
    bucket = "project-bedrock-tfstate-3152"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}