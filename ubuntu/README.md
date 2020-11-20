# Rancher Managed Kubernetes Cluster (KVM + Terraform + Ansible + Kubernetes + RKE + Rancher 2)

Provision a resources to create and manage a self-hosted/on-prem Kubernetes cluster (Managed by Rancher).

[Rancher](https://rancher.com/docs/rancher/v2.x/en/overview/) is a container management platform built for organizations that deploy containers in production. Rancher makes it easy to run Kubernetes everywhere.

## Overview:

Adjust values on `varibles.tf` to suit your needs. With default configuration this is what you'll get:

1. Provision Cluster (KVM) Nodes for 2 Clusters:
   1. Rancher Server Cluster (1 or 3 nodes)
   2. User Cluster (N nodes on the internal (NAT) network, 1 load balancer with internal + bridge networking)
2. Generate Ansible inventory files:
   1. Rancher Nodes + User Cluster Nodes
   2. Load Balancer Nodes
3. Generate 2 separate Rancher config files:
   1. Rancher cluster
   2. User cluster
4. Generate NGINX reverse proxy / load balancer configuration file (Based on rancher docs). Running a proxy on your host is useful during the setup process.
   1. Edit this file as needed depending on what you want:
      1. To access the **rancher-ui**: Point to all nodes on your rancher cluster. Comment out the rest. (Recommended during setup)
      2. To access your user cluster: Point to `worker` nodes on your user cluster. Comment out the rest.

## How-to:

This is a step-by-step guide for the setup that worked for me (after several attempts to make it repeatible):

### Pre-Requisites

Make sure you have all the dependencies installed, including:

1. QEMU / KVM / Libvirt
2. Terraform
   1. Terraform provider for libvirt (https://github.com/dmacvicar/terraform-provider-libvirt)
3. Ansible
4. Kubernetes CLI (`kubectl`)
5. Helm (Package manager for Kubernetes).
6. Rancher Kubernetes Engine CLI (rke)

If you plan to use a load-balancer with an ip assigned by your local DHCP server (ie. LAN router):

1. Make sure you have a bridge setup on your host.
   Note: When using Libvirt/KVM to run your VMs, you MUST use an ethernet device (will not work over WiFi as per current libvirt docs)
2. Make sure you have defined this bridge in libvirt (ie. using `virsh`). A `host-bridge.xml` file is provided for this.

   If you don't know how to do any of this you can follow this blog post: https://levelup.gitconnected.com/how-to-setup-bridge-networking-with-kvm-on-ubuntu-20-04-9c560b3e3991

Install all ansible roles:

`ansible-galaxy install -r ansible/requirements.yml`

### Provision infrastructure:

As configured in this deployment all VMs are based on Ubuntu 20.04 and use cloud-init for initial configuration.
Make sure to explore all terraform files and adjust to your needs, you can use any other OS as long as you take the corresponding considerations.

Once configured, create all VMs simply run:

```
terraform init
terraform apply
```

Then install required packages on all VMs.

```
ansible-playbook -i ansible/rk8s_node_inventory.ini -i ansible/rk8s_lb_inventory.ini ansible/site.yml
```

### Create Rancher cluster

To create the rancher cluster:

```
cd rancher # Move to this directory because more files will be created by this tool
rke up --config=rancher_cluster.yml
```

### Set up your Reverse Proxy / Load Balancer

Make sure you have a reverse proxy on your host or a load balancer that points to the nodes that belong to the Rancher cluster.
You can edit the generated config and make sure it points **only** to the correct nodes provisioned by Terraform.
You can run an NGNIX docker container and use the provided config as follows (be sure to adjust the `path_to_your_project`):

```
docker run -d --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  -v {{ path_to_your_project }}/nginx/nginx.conf:/etc/nginx/nginx.conf \
  nginx:1.14
```

This will create a cluster on the nodes you assigned for running Rancher Server. (Make sure all nodes in `rancher_cluster.yml` have all 3 roles).
Additional

### Install Rancher Server

Make sure your `kubectl` is pointing to the right cluster, you have two options for this:

1. Set KUBECONFIG={{ your_project_path }}/rancher/kube_config_rancher_cluster.yml

or

2. Append `--kubeconfig={{ your_project_path }}/rancher/kube_config_rancher_cluster.yml` to every kubectl command you run.

Check Rancher 2 docs for updated instructions, at the moment of the creation of this project these are the steps I followed:
(If you don't know what these commands do, please read the documentation for Rancher 2 and the tools used.)
https://rancher.com/docs/rancher/v2.x/en/installation/install-rancher-on-k8s/

As detailed in the documentation, you have 3 options for SSL configuration:

1. Self-signed (not recommended). It's better if you use your own trusted CA and use that to generate your own certs and follow option `3`.
2. Automatic LetsEncrypt (Never worked for me, cert-manager pods crashed periodically)
3. Bring your own certs (This is the option that worked best on my case).

If like me, you will generate your certificates independently, make sure to:

1. Point a domain to your server.
2. Set up the correct configuration so requests on ports 80 and 443 arrive at the nodes that belong to your Rancher cluster.
3. Generate your certificates manually. I succeded using cert-bot with DNS as confirmation step.

Make sure to set the correct domain for your deployment:

```
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
kubectl create namespace cattle-system
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.my.org \
  --set ingress.tls.source=secret
```

This will install Rancher... It takes a while to be ready so make sure to monitor the deployment with:
`kubectl -n cattle-system rollout status deploy/rancher`

Finally, create a Kubernetes secret for your certificates detailed in:
https://rancher.com/docs/rancher/v2.x/en/installation/resources/encryption/tls-secrets/
(Rename your files accordingly.)

```
kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert=tls.crt \
  --key=tls.key
```

At this point you should be able to access the Rancher UI on your browser :)

**Important**
You should only run Rancher workloads on this cluster. Use the User Cluster (created below) to run your own workloads.

## Create your User Cluster

From the `rancher` directory, run the command below:

```
rke up --config=user_cluster.yml
```

This will generate the cluster state file as well as the `kubeconfig` to communicate with your cluster.

## Import your User cluster to your Rancher Server for monitoring and management.

On the UI, from the homepage (Global view) click on the `Add Cluster` button (Top right).
Name your cluster and click `Create`

**Important**
Before running the provided command in the UI make sure your `KUBECONFIG` is pointing to the correct cluster!

Run the provided command, it should look something like this:

`kubectl apply -f https://rancher.chepetronix.tech/v3/import/aVeryRandomAndLongHashStringThatLooksLikeBase64Here.yml`

Click `Done` and you will be back at the landing page (Global view) with a new entry.

If the `State` column of your user cluster never changes from "pending", it means that the cattle-cluster-agent is not working as expected.
I encountered two different problems here, both easy to fix:

1.  Your nodes in the User Cluster don't have a route to your rancher cluster (using the URL, ie. `rancher.my.org`).
    This can happen because that is a valid domain that can be resolved from outside your LAN. Again, you have several options here:
    a) Set up an internal DNS server and configure the corresponding entry there, make sure the dnsPolicy in the deployment is set to `Default`.
    b) Patch the deployment. This can be done in 2 ways, by editing the corresponding yaml file or by running the command below.
    I made it resolve to my load balancer.

        (Edit to match your environment)

```
kubectl -n cattle-system patch  deployments cattle-cluster-agent --patch '{
    "spec": {
        "template": {
            "spec": {
                "hostAliases": [
                    {
                      "hostnames":
                      [
                        "rancher.my.org"
                      ],
                      "ip": "YOU.NODE.IP.HERE"
                    }
                ]
            }
        }
    }
}'
```

Your cluster should transition from "Pending" --> "Waiting" --> "Active"

If for some reason this step didn't work for you, you can check the logs of that pod by running:

`kubectl -n cattle-system logs -l app=ranche`

Done! You can proceed to install any workload on your cluster.

If you want to add/remove nodes to your cluster, just edit the `rancher/user_cluster.yml` and add/remove the corresponding node.
Then run `rke up --config=user_cluster.yml --update-only` and your cluster will be reconfigured.
