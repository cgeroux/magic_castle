provider "google" {
  project     = "${var.project_name}"
  region      = "${var.zone}"
  version     = "~> 2.1.0"
}


resource "google_compute_instance" "mgmt01" {
  project = "${var.project_name}"
  zone = "${var.zone_region}"
  name = "mgmt01"
  machine_type = "${var.machine_type_mgmt}"
  tags         = ["mgmt01"]

  boot_disk {
    initialize_params {
      image = "${var.gcp_image}"
      size  = "${var.shared_storage_size}"
    }
  }

  network_interface {
    subnetwork = "default"
    access_config { }
  }

  metadata {
    sshKeys = "centos:${file(var.public_key_path)}"
    user-data = "${data.template_cloudinit_config.mgmt_config.rendered}"
    user-data-encoding = "base64"
  }

  metadata_startup_script = "${file("${path.module}/install_cloudinit.sh")}"
}

resource "google_compute_instance" "login01" {
  project = "${var.project_name}"
  zone = "${var.zone_region}"
  name = "login01"
  machine_type = "${var.machine_type_login}"
  tags         = ["login01"]

  boot_disk {
    initialize_params {
      image = "${var.gcp_image}"
    }
  }

  network_interface {
    subnetwork = "default"
    access_config { }
  }

  metadata {
    sshKeys = "centos:${file(var.public_key_path)}"
    user-data = "${data.template_cloudinit_config.login_config.rendered}"
    user-data-encoding = "base64"
  }

  metadata_startup_script = "${file("${path.module}/install_cloudinit.sh")}"
}

resource "google_compute_instance" "node" {
  count = "${var.nb_nodes}"
  project = "${var.project_name}"
  zone = "${var.zone_region}"
  name = "node${count.index + 1}"
  machine_type = "${var.machine_type_node}"
  scheduling {
    # Instances with guest accelerators do not support live migration.
    on_host_maintenance = "${var.gpu_per_node[1] ? "TERMINATE" : "MIGRATE"}"
  }
  guest_accelerator {
    type  = "${var.gpu_per_node[0]}"
    count = "${var.gpu_per_node[1]}"
  }
  tags         = ["node${count.index + 1}"]

  boot_disk {
    initialize_params {
      image = "${var.gcp_image}"
    }
  }

  network_interface {
    subnetwork = "default"
    access_config { }
  }

  metadata {
    sshKeys = "centos:${file(var.public_key_path)}"
    user-data = "${element(data.template_cloudinit_config.node_config.*.rendered, count.index)}"
    user-data-encoding = "base64"
  }

  metadata_startup_script = "${file("${path.module}/install_cloudinit.sh")}"
}

resource "google_compute_firewall" "default" {
  name    = "firewall"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags   = ["login01"]
}

locals {
  mgmt01_ip = "${google_compute_instance.mgmt01.network_interface.0.network_ip}"
  public_ip = "${google_compute_instance.login01.network_interface.0.access_config.0.nat_ip}"
  cidr = "10.128.0.0/9" # GCP default
}
