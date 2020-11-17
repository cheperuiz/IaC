output "nodes" {
  value = libvirt_domain.domain-rk8s-node.*.name
}

output "nodes_ips" {
  value = libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0
}

output "nodes_inventory" {
  value = formatlist(
    "%s ansible_host=%s %s",
    libvirt_domain.domain-rk8s-node.*.name,
    libvirt_domain.domain-rk8s-node.*.network_interface.0.addresses.0,
    "ansible_python_interpreter=/usr/bin/python3"
  )
}

output "load-balancers" {
  value = libvirt_domain.domain-rk8s-lb.*.name
}

output "lb_ips" {
  value = [libvirt_domain.domain-rk8s-lb.*.network_interface.0.addresses.0,
          libvirt_domain.domain-rk8s-lb.*.network_interface.1.addresses.0]

}

output "lb_inventory" {
  value = formatlist(
    "%s ansible_host=%s %s",
    libvirt_domain.domain-rk8s-lb.*.name,
    libvirt_domain.domain-rk8s-lb.*.network_interface.0.addresses.0,
    "ansible_python_interpreter=/usr/bin/python3"
  )
}
