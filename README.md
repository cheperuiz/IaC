## Assuming you have these prerequisites:

- KVM/QEMU installed and correctly configured
- Download and build (`go build`) [Terraform Provider for libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)
  - place the binary in `~/.local/share/terraform/plugins/registry.terraform.io/dmacvicar/libvirt/0.6.2/linux_amd64`
- For more info check this post: https://github.com/dmacvicar/terraform-provider-libvirt/issues/747#issuecomment-678575669
- Terraform >= 0.13
- Ansible installed
- an ssh identity in ~/.ssh/terraform

## Try:

- Copy your ssh public key to the corresponding place in `./ubuntu/config/cloud_init.yml`
- Run:

```
cd ubuntu
terraform init
terraform plan
terraform apply --auto-aprove
```

## Based on:

https://blog.ruanbekker.com/blog/2020/10/08/using-the-libvirt-provisioner-with-terraform-for-kvm/
