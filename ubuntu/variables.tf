variable "libvirt_disk_path" {
  description = "path for libvirt pool"
  default     = "/opt/kvm/rk8s-pool"
}

variable "ubuntu_20_img_url" {
  description = "ubuntu 20.04 image"
  default = "https://cloud-images.ubuntu.com/releases/focal/release-20201014/ubuntu-20.04-server-cloudimg-amd64.img"
}

variable "vm_hostname" {
  description = "vm hostname"
  default     = "rk8s"
}

variable "ssh_username" {
  description = "the ssh user to use"
  default     = "ubuntu"
}

variable "ssh_private_key" {
  description = "the private key to use"
  default     = "~/.ssh/terraform"
}


variable "num_rk8s_nodes" {
  description = "the number of nodes to be provisioned"
  default = 0
}

variable "num_rk8s_lbs" {
  description = "the number of load balancers to be provisioned"
  default = 1
}

variable "num_rk8s_rancher_nodes"{
  description = "the number of nodes to run all roles for HA Rancher 2"
  default = 0
}

variable "num_rk8s_master_nodes"{
  description = "the number of nodes to run both etcd and controlplane"
  default = 0
}

variable "num_rk8s_etcd_nodes" {
  description = "the number of rk8s nodes to be assigned for etcd"
  default = 0
}

variable "etcd_node_offset" {
  description = "index of the first etcd node"
  default = 0
}

variable "num_rk8s_controlplane_nodes" {
  description = "the number of rk8s nodes to be assigned for controlplane"
  default = 0
}

variable "controlplane_node_offset" {
  description = "index of the first controlplane node"
  default = 0
}

variable "num_rk8s_worker_nodes" {
  description = "the number of rk8s nodes to be assigned as workers"
  default = 0
}

variable "worker_node_offset" {
  description = "index of the first worker node"
  default = 0
}
