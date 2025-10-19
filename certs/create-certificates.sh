#!/bin/bash

# create CA key
openssl genrsa -out ca.key 4096

# create CA certificate
openssl req -x509 -new -nodes \
    -days 3650 \
    -key ca.key \
    -out ca.crt \
    -subj "/C=DE/ST=Berlin/O=MyCompany/OU=IT/CN=MyCA"

# create server key
openssl genrsa -out server.key 2048

# create ssl request config
cat > san.cnf << EOF
[req]
distinguished_name=req_dn
req_ext=req_ext
prompt=no

[req_dn]
C=DE
ST=Berlin
O=MyCompany
OU=IT
CN=ldap.example.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ldap.example.local
DNS.2 = localhost
IP.1  = 127.0.0.1
EOF

# create request
openssl req -new -key server.key -out server.csr -config san.cnf

# sign request
openssl x509 -req \
    -in server.csr \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial -out server.crt \
    -days 3600 \
    -sha256

