terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.5.0"
    }
  }
}

variable "project_id" {
  type = string
  default = "swift-height-337210"
}


provider "google-beta" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}


resource "google_service_account" "default" {
  account_id   = "service-account-id"
  display_name = "Service Account"
  project      = var.project_id
}

resource "google_compute_network" "gke" {
  project                         = var.project_id
  auto_create_subnetworks         = false
  delete_default_routes_on_create = false
  description                     = "Compute Network for GKE nodes"
  name                            = "${terraform.workspace}-gke"
  routing_mode                    = "GLOBAL"
}

resource "google_compute_subnetwork" "gke" {
  name          = "prod-gke-subnetwork"
  ip_cidr_range = "10.255.0.0/16"
  network       = google_compute_network.gke.id

  secondary_ip_range {
    range_name    = local.cluster_secondary_range_name
    ip_cidr_range = "10.0.0.0/12"
  }

  secondary_ip_range {
    range_name    = local.services_secondary_range_name
    ip_cidr_range = "10.64.0.0/12"
  }
}

locals {
  cluster_secondary_range_name  = "cluster-secondary-range"
  services_secondary_range_name = "services-secondary-range"
}

resource "google_container_cluster" "primary" {
  name = "my-gke-cluster"
  #location = "us-central1"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = google_compute_network.gke.self_link
  subnetwork               = google_compute_subnetwork.gke.self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = local.cluster_secondary_range_name
    services_secondary_range_name = local.services_secondary_range_name
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name = "preemptible-pool"
  #location   = "us-central1"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-medium"

    service_account = google_service_account.default.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    taint {
      key    = "cloud.google.com/gke-preemptible"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }


}

resource "google_container_node_pool" "primary_non_preemptible_nodes" {
  name = "non-preemptible-pool"
  #location   = "us-central1"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = false
    machine_type = "e2-medium"

    service_account = google_service_account.default.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
