# Define the provider and required providers

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
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
  depends_on = [google_project_service.run]
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

# Pub/Sub topic
resource "google_pubsub_topic" "ps_topic" {
  name = "hyp-pubsub-topic"

  labels = {
    created = "terraform"
  }

  depends_on = [google_project_service.pubsub]
}

# Pipeline 1: Cloud Run proxy -> Pubsub -> BigQuery

resource "google_bigquery_table" "bq_table_bqdirect" {
  dataset_id          = google_bigquery_dataset.bq_dataset.dataset_id
  table_id            = "pubsubdirect"
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
      "description": "JSON data from Pub/Sub"
    }
  ]
  EOF
}

resource "google_project_iam_member" "viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "sub_bqdirect" {
  name  = "hyp_subscription_bq_direct"
  topic = google_pubsub_topic.ps_topic.name

  bigquery_config {
    table = "${google_bigquery_table.bq_table_bqdirect.project}:${google_bigquery_table.bq_table_bqdirect.dataset_id}.${google_bigquery_table.bq_table_bqdirect.table_id}"
  }

  depends_on = [google_project_iam_member.viewer, google_project_iam_member.editor]

  labels                = { created = "terraform" }
  retain_acked_messages = false
  ack_deadline_seconds  = 20
  retry_policy {
    minimum_backoff = "10s"
  }
  enable_message_ordering = false
}

#Pipeline 2: Cloud Run proxy -> Pubsub -> Cloud Run -> BigQuery
resource "google_cloud_run_service" "hyp_run_service_data_processing" {
  name     = "hyp-run-service-data-processing"
  location = var.gcp_region

  template {
    spec {
      containers {
        image = "gcr.io/${var.project_id}/data-processing-service"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.run]

}

# Make cloud run service public  -> noauth
resource "google_cloud_run_service_iam_policy" "noauth_dp" {
  location    = google_cloud_run_service.hyp_run_service_data_processing.location
  project     = google_cloud_run_service.hyp_run_service_data_processing.project
  service     = google_cloud_run_service.hyp_run_service_data_processing.name
  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_pubsub_subscription" "hyp_sub_cloud_run" {
  name  = "hyp_subscription_cloud_run"
  topic = google_pubsub_topic.ps_topic.name
  labels = {
    created = "terraform"
  }


  push_config {
    push_endpoint = google_cloud_run_service.hyp_run_service_data_processing.status[0].url
    attributes = {
      x-goog-version = "v1"
    }
  }
  retain_acked_messages = false
  ack_deadline_seconds  = 20
  retry_policy {
    minimum_backoff = "10s"
  }
  enable_message_ordering = false
}

resource "google_bigquery_table" "bq_table_cloud_run" {
  dataset_id = google_bigquery_dataset.bq_dataset.dataset_id
  table_id = "cloud_run"
  deletion_protection = false

  time_partitioning {
    type = "DAY"
    field = "event_datetime"
  }
  labels = {
    env = "default"
  }
  
  # TODO: Make file path dynamic
  schema = file("./data-schema/ecommerce_events_bq_schema.json")
}

#Pipeline 3: Cloud Run proxy -> Pubsub -> Dataflow -> BigQuery

resource "google_pubsub_subscription" "hyp_sub_dataflow" {
  name  = "hyp_subscription_dataflow"
  topic = google_pubsub_topic.ps_topic.name

  labels = {
    created = "terraform"
  }

  retain_acked_messages = false

  ack_deadline_seconds = 20


  retry_policy {
    minimum_backoff = "10s"
  }

  enable_message_ordering = false
}

resource "google_dataflow_flex_template_job" "dataflow_stream" {
  provider                = google-beta
  name                    = "ecommerce-events-ps-to-bq-stream"
  container_spec_gcs_path = "gs://${var.project_id}-ecommerce-events/df_templates/dataflow_template.json"
  region                  = var.gcp_region
  project                 = var.project_id
  depends_on              = [google_project_service.compute, google_project_service.dataflow]
  parameters = {
    "on_delete"             = "cancel"
    "service_account_email" = "${google_service_account.data_pipeline_access.email}"
    "network"               = "${google_compute_network.vpc_network.name}"
    "max_workers"           = 1
    "temp_location"         = "gs://${var.project_id}-ecommerce-events/df_tmp_dir"
    "runner"                = "DataflowRunner"
  }
}

