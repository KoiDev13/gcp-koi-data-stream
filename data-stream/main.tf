# Define the provider and required providers

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.32.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

data "google_project" "project" {}

# Define network and subnetwork: vpc_network, vpc_subnetwork
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_firewall" "vpc_network_firewall" {
  name                    = "firewall"
  network                 = google_compute_network.vpc_network.name
  source_service_accounts = ["${google_service_account.data_pipeline_access.email}"]
  allow {
    protocol = "tcp"
    ports    = ["12345", "12346"]
  }
}

resource "google_service_account" "data_pipeline_access" {
  project      = var.project_id
  account_id   = "retailpipeline-hyp"
  display_name = "Retail app data pipeline access"
}

# Set permissions for the service account
resource "google_project_iam_member" "dataflow_admin_role" {
  project = var.project_id
  role    = "roles/dataflow.admin"
  member  = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_worker_role" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_bigquery_role" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_pub_sub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_pub_sub_viewer" {
  project = var.project_id
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

data "google_compute_default_service_account" "default" {}

resource "google_project_iam_member" "gce_pub_sub_admin" {
  project = var.project_id
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# Enabling APIs: compute, run, dataflow, pubsub

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataflow" {
  service            = "dataflow.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

# Common resources: proxy, dataset, topic

# Cloud run proxy
# To make a Cloud run publicly accessible, we need to create a proxy
resource "google_cloud_run_service" "pubsub_proxy_hyp" {
  name     = "hyp-run-service-pubsub-proxy"
  location = var.gcp_region
  template {
    spec {
      containers {
        image = "gcr.io/${var.project_id}/pubsub-proxy"
      }
      service_account_name = "data_pipeline_access@${var.project_id}.iam.gserviceaccount.com"
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location    = google_cloud_run_service.pubsub_proxy_hyp.location
  project     = google_cloud_run_service.pubsub_proxy_hyp.project
  service     = google_cloud_run_service.pubsub_proxy_hyp.name
  policy_data = data.google_iam_policy.noauth.policy_data
}

output "cloud_run_proxy_url" {
  value = google_cloud_run_service.pubsub_proxy_hyp.status[0].url
}

# BigQuery dataset

resource "google_bigquery_dataset" "bq_dataset" {
  dataset_id    = "ecommerce_sink"
  friendly_name = "ecommerce_sink"
  description   = "Destination dataset for all pipeline options"
  location      = var.gcp_region

  delete_contents_on_destroy = true

  labels = {
    env = "default"
  }
}

# Pubsub topic
resource "google_pubsub_topic" "ps_topic" {
  name = 
}