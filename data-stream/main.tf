# Define the provider and required providers

terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.32.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

data "google_project" "project" {}

# Define network and subnetwork: vpc_network, vpc_subnetwork
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
  
}

resource "google_compute_firewall" "vpc_network_firewall" {
  name    = "firewall"
  network = google_compute_network.vpc_network.name
  source_service_accounts = ["${google_service_account.data_pipeline_access.email}"]
  allow {
    protocol = "tcp"
    ports    = ["12345", "12346"]
  }
}

resource "google_service_account" "data_pipeline_access" {
  project = var.project_id
  account_id = "retailpipeline-hyp"
  display_name = "Retail app data pipeline access"
}

# Set permissions for the service account
resource "google_project_iam_member" "dataflow_admin_role" {
  project = var.project_id
  role = "roles/dataflow.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# Enabling APIs: compute, run, dataflow, pubsub

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  service = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataflow" {
  service = "dataflow.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  service = "pubsub.googleapis.com"
  disable_on_destroy = false
}

# Common resources: proxy, dataset, topic

# Cloud run Proxy

# Bigquery Dataset

# Pub/Sub Topic