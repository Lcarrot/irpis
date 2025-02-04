terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

variable "token" {
    type = string 
}

variable "cloud_id" {
    type = string 
}

variable "folder_id" {
    type = string 
}

variable "region" {
  type = string
  default = "ru-central1-a"
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.region
}

variable "user" {
  type = string
  default = "ipiris"
}

variable "network_name" {
  type = string
  default = "task4-network"
}
variable "subnet_name" {
  type = string
  default = "task4-subnetwork"
}
variable "vm_name" {
  type = string
  default = "task4-vm"
}

resource "yandex_vpc_network" "network" {
  name = var.network_name
}

resource "yandex_vpc_subnet" "subnet" {
  name           = var.subnet_name
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["192.168.0.0/24"]
}

resource "tls_private_key" "ssh_key" {
  algorithm = "ED25519"
}

resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "~/.ssh/${var.vm_name}/${var.vm_name}-key"
}

resource "yandex_compute_instance" "vm" {
  name        = var.vm_name
  platform_id = "standard-v3"
  zone        = var.region

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = "fd82odtq5h79jo7ffss3"
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    user-data = user-data = "#cloud-config\nusers:\n  - name: ${var.user}\n    groups: sudo\n    shell: /bin/bash\n    sudo: 'ALL=(ALL) NOPASSWD:ALL'\n    ssh_authorized_keys:\n      -  ${tls_private_key.ssh_key.public_key_openssh}"
  }
}

resource "null_resource" "docker run" {
  depends_on = [yandex_compute_instance.vm]

  provisioner "remote-exec" {
    inline = [
      "sudo apt install docker.io",
      "sudo usermod -aG docker ${var.ipiris}",
      "newgrp docker",
      "docker pull jmix/jmix-bookstore",
      "sudo docker run -d -p 80:8080 --name new-bookstore-app jmix/jmix-bookstore"
    ]

    connection {
      type        = "ssh"
      user        = var.vm_name
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = yandex_compute_instance.vm.network_interface.0.nat_ip_address
    }
  }
}

output "connection_info" {
  value = "ssh -i ~/.ssh/${var.vm_name}/${var.vm_name}-key ${var.ipiris}@${yandex_compute_instance.vm.network_interface.0.nat_ip_address}"
}

output "app_url" {
  value = "http://${yandex_compute_instance.vm.network_interface.0.nat_ip_address}"
}
