#!/bin/sh
openssl s_client -showcerts -connect registry.alhena:5000</dev/null 2>/dev/null|openssl x509 -outform PEM >ca.crt
mkdir -p /etc/docker/certs.d/registry.alhena
cp ca.crt /etc/docker/certs.d/registry.alhena/ca.crt
cat ca.crt | sudo tee -a /etc/ssl/certs/ca-certificates.crt
systemctl restart docker 
