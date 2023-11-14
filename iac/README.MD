# IAC folder  

terraform workspace new gcp-env-dev  
terraform workspace select gcp-env-dev  
terraform init  
terraform plan -var-file gcp-env-dev.tfvars  
terraform apply -var-file gcp-env-dev.tfvars  
