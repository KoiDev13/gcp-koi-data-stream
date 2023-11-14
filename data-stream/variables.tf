variable "project_id" {
  description = "Project where datasets and tables are created"
}

variable "delete_contents_on_destroy" {
  description = "If set to true, the dataset, tables and all the data will be deleted when the resource is destroyed. Otherwise, destroying the resource will fail if tables or datasets contain data."
  type        = bool
  default     = null
}

variable "force_destroy" {
  description = "When deleting a bucket, this boolean option will delete all contained objects. If false, Terraform will fail to delete buckets which contain objects."
  type        = bool
  default     = true
}

variable "gcp_region" {
  description = "GCP region to deploy resources in."
  type        = string
  default     = "us-central1"
}
