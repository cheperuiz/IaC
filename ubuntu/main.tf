
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


data "template_file" "lb_data" {
  template = file("${path.module}/config/loadbalancer/cloud_init.yml")
}

data "template_file" "lb_network_config" {
  template = file("${path.module}/config/loadbalancer/network_config.yml")
}

resource "libvirt_cloudinit_disk" "lbinit" {
  name           = "lbinit.iso"
  user_data      = data.template_file.lb_data.rendered
  network_config = data.template_file.lb_network_config.rendered
  pool           = libvirt_pool.rk8s-pool.name
}

data "template_file" "node_data" {
  template = file("${path.module}/config/node/cloud_init.yml")
}

data "template_file" "node_network_config" {
  template = file("${path.module}/config/node/network_config.yml")
}
resource "libvirt_cloudinit_disk" "nodeinit" {
  name           = "nodeinit.iso"
  user_data      = data.template_file.node_data.rendered
  network_config = data.template_file.node_network_config.rendered
  pool           = libvirt_pool.rk8s-pool.name
}

resource "libvirt_volume" "rk8s-lb-volume" {
  count = var.num_rk8s_lbs

  name = "rk8s-lb-volume-${count.index}"
  pool = libvirt_pool.rk8s-pool.name
  base_volume_id = libvirt_volume.ubuntu-qcow2.id
  size = 16 * 1024 * 1024 * 1024 # 16GiB
}

resource "libvirt_domain" "domain-rk8s-lb" {

  count = var.num_rk8s_lbs

  name   = "${var.vm_hostname}-lb-${count.index}"
  memory = "4096"
  vcpu   = 4
  autostart = true

  cloudinit = libvirt_cloudinit_disk.lbinit.id
  qemu_agent = true
  
  cpu = {
    mode            = "host-passthrough"
    check           = "partial"
  }

  network_interface {
    wait_for_lease = false
    bridge = "br0"
    hostname       = "${var.vm_hostname}-lb-${count.index}"
    mac = var.mac[count.index]
  }

  network_interface {
    network_name   = "default" # libvirt_network.rk8s_internal_net.name
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
  size = 40 * 1024 * 1024 * 1024 # 40GiB
}

resource "libvirt_domain" "domain-rk8s-node" {

  count = var.num_rk8s_nodes

  name   = "${var.vm_hostname}-node-${count.index}"
  memory = "4096"
  vcpu   = 4
  autostart = true

  cloudinit = libvirt_cloudinit_disk.nodeinit.id
  qemu_agent = false
  
  cpu = {
    mode            = "host-passthrough"
    check           = "partial"
  }

  network_interface {
    network_name   = "default" # libvirt_network.rk8s_internal_net.name
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
  file_permission = "644"
}

resource "local_file" "rk8s-lb-inventory" {
  content = templatefile("templates/rk8s_inventory.ini.j2",
  {
    group_name = "rancher_2_kubernetes_load_balancers"
    node_names = libvirt_domain.domain-rk8s-lb.*.name,
    node_ips = libvirt_domain.domain-rk8s-lb.*.network_interface.0.addresses.0
  })
  filename = "ansible/rk8s_lb_inventory.ini"
  file_permission = "644"
}

resource "local_file" "rk8s-inventory" {
  content = templatefile("templates/rk8s_inventory.yml.j2",
  {
    lb_ips = libvirt_domain.domain-rk8s-lb.*.network_interface.0.addresses.0
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
    
    num_rk8s_lbs = var.num_rk8s_lbs

    num_rk8s_master_nodes = var.num_rk8s_master_nodes
    master_node_offset = var.num_rk8s_rancher_nodes

    num_rk8s_etcd_nodes = var.num_rk8s_etcd_nodes
    etcd_node_offset = var.num_rk8s_rancher_nodes + var.num_rk8s_master_nodes
    
    num_rk8s_controlplane_nodes = var.num_rk8s_controlplane_nodes
    controlplane_node_offset = var.num_rk8s_rancher_nodes + var.num_rk8s_master_nodes + var.num_rk8s_etcd_nodes
    
    num_rk8s_worker_nodes = var.num_rk8s_worker_nodes
    worker_node_offset =  var.num_rk8s_rancher_nodes + var.num_rk8s_master_nodes + var.num_rk8s_etcd_nodes + var.num_rk8s_controlplane_nodes
  })

  filename = "ansible/rk8s_inventory.yml"
  file_permission = "644"
}

resource "local_file" "rancher_cluster" {
  content = templatefile("templates/rancher_cluster.yml.j2",
  {
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
    
    num_rk8s_rancher_nodes = var.num_rk8s_rancher_nodes

    ssh_key = var.ssh_private_key
  })
  filename = "rancher/rancher_cluster.yml"
  file_permission = "644"
}

resource "local_file" "user_cluster" {
  content = templatefile("templates/user_cluster.yml.j2",
  {
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
    
    num_rk8s_master_nodes = var.num_rk8s_master_nodes
    master_node_offset = var.num_rk8s_rancher_nodes

    num_rk8s_etcd_nodes = var.num_rk8s_etcd_nodes
    etcd_node_offset = var.num_rk8s_rancher_nodes + var.num_rk8s_master_nodes
    
    num_rk8s_controlplane_nodes = var.num_rk8s_controlplane_nodes
    controlplane_node_offset = var.num_rk8s_rancher_nodes + var.num_rk8s_master_nodes + var.num_rk8s_etcd_nodes
    
    num_rk8s_worker_nodes = var.num_rk8s_worker_nodes - 3
    worker_node_offset =  var.num_rk8s_rancher_nodes + var.num_rk8s_master_nodes + var.num_rk8s_etcd_nodes + var.num_rk8s_controlplane_nodes

    lb_ip = libvirt_domain.domain-rk8s-lb[0].network_interface.1.addresses.0
 
    ssh_key = var.ssh_private_key
  })

  filename = "rancher/user_cluster.yml"
  file_permission = "644"
}

resource "local_file" "ticketai_cluster" {
  content = templatefile("templates/ticketai_cluster.yml.j2",
  {
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
    
    num_rk8s_nodes = 3
    worker_node_offset = var.num_rk8s_nodes - 3

    ssh_key = var.ssh_private_key
  })

  filename = "rancher/ticketai_cluster.yml"
  file_permission = "644"
}

resource "local_file" "nginx_conf" {
  content = templatefile("templates/nginx.conf.j2",
  {
    node_ips = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
  })
  filename = "nginx/nginx.conf"
  file_permission = "644"
}
