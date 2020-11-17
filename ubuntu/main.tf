
provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_pool" "rk8s-pool" {
  name = "rk8s-pool"
  type = "dir"
  path = var.libvirt_disk_path
}

resource "libvirt_volume" "ubuntu-qcow2" {
  name = "ubuntu-qcow2"
  pool = libvirt_pool.rk8s-pool.name
  source = var.ubuntu_20_img_url
  format = "qcow2"
}


data "template_file" "user_data" {
  template = file("${path.module}/config/cloud_init.yml")
}

data "template_file" "network_config" {
  template = file("${path.module}/config/network_config.yml")
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name           = "commoninit.iso"
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
  pool           = libvirt_pool.rk8s-pool.name
}

# resource "libvirt_network" "kube_network" {
#   name = "k8snet"
#   mode = "bridge"
#   bridge = "br0"
#   # addresses = ["10.0.3.0/24", "2001:db8:ca2:2::1/64"]
#   dns {
#     enabled = true
#     local_only = true
    
#     # (Optional) one or more DNS forwarder entries.  One or both of
#     # "address" and "domain" must be specified.  The format is:
#     # forwarders {
#     #     address = "my address"
#     #     domain = "my domain"
#     #  } 
#     # 

#     # (Optional) one or more DNS host entries.  Both of
#     # "ip" and "hostname" must be specified.  The format is:
#     # hosts  {
#     #     hostname = "my_hostname"
#     #     ip = "my.ip.address.1"
#     #   }
#     # hosts {
#     #     hostname = "my_hostname"
#     #     ip = "my.ip.address.2"
#     #   }
#     # 

#     # (Optional) one or more static routes.
#     # "cidr" and "gateway" must be specified. The format is:
#     # routes {
#     #     cidr = "10.17.0.0/16"
#     #     gateway = "10.18.0.2"
#     #   }
#   }
# }

resource "libvirt_volume" "rk8s-lb-volume" {
  count = var.num_rk8s_lbs

  name = "rk8s-lb-volume-${count.index}"
  pool = libvirt_pool.rk8s-pool.name
  base_volume_id = libvirt_volume.ubuntu-qcow2.id
  size = 8 * 1024 * 1024 * 1024 # 8GiB
}

resource "libvirt_domain" "domain-rk8s-lb" {

  count = var.num_rk8s_lbs

  name   = "${var.vm_hostname}-lb-${count.index}"
  memory = "4090"
  vcpu   = 16

  cloudinit = libvirt_cloudinit_disk.commoninit.id
  qemu_agent = true
  
  cpu = {
    mode            = "host-passthrough"
    check           = "partial"
  }

  network_interface {
    wait_for_lease = true
    bridge = "br0"
    hostname       = "${var.vm_hostname}-lb-${count.index}"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.rk8s-lb-volume[count.index].id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete configuration...'",
      "cloud-init status --long --wait",
    ]
    connection {
      type                = "ssh"
      user                = var.ssh_username
      host                = self.network_interface[0].addresses[0]
      private_key         = file(var.ssh_private_key)
      timeout             = "2m"
    }
  }

}

resource "libvirt_volume" "rk8s-node-volume" {

  count = var.num_rk8s_nodes

  name = "rk8s-node-volume-${count.index}"
  pool = libvirt_pool.rk8s-pool.name
  base_volume_id = libvirt_volume.ubuntu-qcow2.id
  size = 16 * 1024 * 1024 * 1024 # 16GiB
}

resource "libvirt_domain" "domain-rk8s-node" {

  count = var.num_rk8s_nodes

  name   = "${var.vm_hostname}-node-${count.index}"
  memory = "4090"
  vcpu   = 16

  cloudinit = libvirt_cloudinit_disk.commoninit.id
  
  cpu = {
    mode            = "host-passthrough"
    check           = "partial"
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
    hostname       = "${var.vm_hostname}-node-${count.index}"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.rk8s-node-volume[count.index].id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete configuration...'",
      "cloud-init status --long --wait",
    ]
    connection {
      type                = "ssh"
      user                = var.ssh_username
      host                = self.network_interface[0].addresses[0]
      private_key         = file(var.ssh_private_key)
      timeout             = "2m"
    }
  }

}

resource "local_file" "rk8s-node-inventory" {
  content = templatefile("templates/rk8s_inventory.ini.j2",
  {
    group_name = "rancher_2_kubernetes_nodes"
    node_names = libvirt_domain.domain-rk8s-node.*.name,
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
  })
  filename = "ansible/rk8s_node_inventory.ini"
}




resource "local_file" "rk8s-lb-inventory" {
  content = templatefile("templates/rk8s_inventory.ini.j2",
  {
    group_name = "rancher_2_kubernetes_load_balancers"
    node_names = libvirt_domain.domain-rk8s-lb.*.name,
    node_ips = libvirt_domain.domain-rk8s-lb.*.network_interface.0.addresses.0
  })
  filename = "ansible/rk8s_lb_inventory.ini"
}

resource "local_file" "rk8s-inventory" {
  content = templatefile("templates/rk8s_inventory.yml.j2",
  {
    lb_ips = libvirt_domain.domain-rk8s-lb.*.network_interface.0.addresses.0
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
    
    num_rk8s_lbs = var.num_rk8s_lbs

    num_rk8s_master_nodes = var.num_rk8s_master_nodes

    num_rk8s_etcd_nodes = var.num_rk8s_etcd_nodes
    etcd_node_offset = var.etcd_node_offset
    
    num_rk8s_controlplane_nodes = var.num_rk8s_controlplane_nodes
    controlplane_node_offset = var.controlplane_node_offset
    
    num_rk8s_worker_nodes = var.num_rk8s_worker_nodes
    worker_node_offset = var.worker_node_offset
  })
  filename = "ansible/rk8s_inventory.yml"
}

resource "local_file" "rancher_cluster" {
  content = templatefile("templates/rancher_cluster.yml.j2",
  {
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
    num_rk8s_lbs = var.num_rk8s_lbs
    
    num_rk8s_rancher_nodes = var.num_rk8s_rancher_nodes

    ssh_key = var.ssh_private_key
  })
  filename = "rancher/rancher_cluster.yml"
}
