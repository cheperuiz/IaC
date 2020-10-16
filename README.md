## Assuming you have these prerequisites:

- KVM/QEMU installed and correctly configured
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
