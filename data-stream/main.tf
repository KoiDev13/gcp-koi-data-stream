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
  region  = var.gcp_region
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
  member = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_worker_role" {
  project = var.project_id
  role = "roles/dataflow.worker"
  member = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_bigquery_role" {
  project = var.project_id
  role = "roles/bigquery.dataEditor"
  member = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_pub_sub_subscriber" {
  project = var.project_id
  role = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_pub_sub_viewer" {
  project = var.project_id
  role = "roles/pubsub.viewer"
  member = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

resource "google_project_iam_member" "dataflow_storage_object_admin" {
  project = var.project_id
  role = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.data_pipeline_access.email}"
}

data "google_compute_default_service_account" "default" {}

resource "google_project_iam_member" "gce_pub_sub_admin" {
  project = var.project_id
  role = "roles/pubsub.admin"
  member = "serviceAccount:${data.google_compute_default_service_account.default.email}"
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

# Cloud Run Proxy
resource "google_cloud_run_service" "pubsub_proxy_hyp" {
  name     = "hyp-run-service-pubsub-proxy"
  location = var.gcp_region
  template {
    spec {
      containers {
        image = "gcr.io/${var.project_id}/pubsub-proxy"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [ google_project_service.run ]
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

# BigQuery Dataset
resource "google_bigquery_dataset" "bq_dataset" {
  dataset_id                  = "ecommerce_sink"
  friendly_name               = "ecommerce sink"
  description                 = "Destination dataset for all pipeline options"
  location                    = var.gcp_region

  delete_contents_on_destroy = true

  labels = {
    env = "default"
  }
}

# Pub/Sub Topic
resource "google_pubsub_topic" "ps_topic" {
  name = "hyp-pubsub-topic"

  labels = {
    created = "terraform"
  }

  depends_on = [google_project_service.pubsub]
}

# Pipeline 1: Cloud Run Proxy -> Pub/Sub -> BigQuery
resource "google_bigquery_table" "bq_table_bqdirect" {
  dataset_id = google_bigquery_dataset.bq_dataset.dataset_id
  table_id   = "pubsub_direct"
  deletion_protection = false

  labels = {
    env = "default"
  }

  schema = <<EOF
[
  {
    "name": "data",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "The data"
  }
]
EOF
}

resource "google_project_iam_member" "viewer" {
  project = var.project_id
  role   = "roles/bigquery.metadataViewer"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "editor" {
  project = var.project_id
  role   = "roles/bigquery.dataEditor"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "sub_bqdirect" {
  name  = "hyp_subscription_bq_direct"
  topic = google_pubsub_topic.ps_topic.name

  bigquery_config {
    table = "${google_bigquery_table.bq_table_bqdirect.project}:${google_bigquery_table.bq_table_bqdirect.dataset_id}.${google_bigquery_table.bq_table_bqdirect.table_id}"
  }

  depends_on = [google_project_iam_member.viewer, google_project_iam_member.editor]

  labels = {
    created = "terraform"
  }
  retain_acked_messages      = false

  ack_deadline_seconds = 20

  retry_policy {
    minimum_backoff = "10s"
  }

  enable_message_ordering    = false
}