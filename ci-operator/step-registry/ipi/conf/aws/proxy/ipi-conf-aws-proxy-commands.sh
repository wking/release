#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

function generate_proxy_certs() {

  ROOTCA=${SHARED_DIR}
  INTERMEDIATE=${ROOTCA}/INTERMEDIATE

  mkdir ${ROOTCA}
  pushd ${ROOTCA}
  mkdir certs crl newcerts private
  chmod 700 private
  touch index.txt
  echo 1000 > serial

  cat > ${ROOTCA}/openssl.cnf << EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
# Directory and file locations.
dir               = ${ROOTCA}
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
# The root key and root certificate.
private_key       = \$dir/private/ca.key.pem
certificate       = \$dir/certs/ca.cert.pem
# For certificate revocation lists.
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl.pem
crl_extensions    = crl_ext
copy_extensions   = copy
default_crl_days  = 30
# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose
[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ req ]
default_bits        = 2048
distinguished_name  = ca_dn
string_mask         = utf8only
# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256
# Extension to add when the -x509 option is used.
x509_extensions     = v3_ca
prompt              = no
[ ca_dn ]
0.domainComponent       = "io"
1.domainComponent       = "openshift"
organizationName        = "OpenShift Origin"
organizationalUnitName  = "Proxy CI Signing CA"
commonName              = "Proxy CI Signing CA"
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[ crl_ext ]
authorityKeyIdentifier=keyid:always
[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

  # create root key
  uuidgen | sha256sum | cut -b -32 > capassfile

  openssl genrsa -aes256 -out private/ca.key.pem -passout file:capassfile 4096 2>/dev/null
  chmod 400 private/ca.key.pem

  # create root certificate

  openssl req -config openssl.cnf \
    -key private/ca.key.pem \
    -passin file:capassfile \
    -new -x509 -days 7300 -sha256 -extensions v3_ca \
    -out certs/ca.cert.pem 2>/dev/null

  chmod 444 certs/ca.cert.pem

  mkdir ${INTERMEDIATE}
  pushd ${INTERMEDIATE}

  mkdir certs crl csr newcerts private
  chmod 700 private
  touch index.txt
  echo 1000 > serial

  echo 1000 > ${INTERMEDIATE}/crlnumber

  cat > ${INTERMEDIATE}/openssl.cnf << EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
# Directory and file locations.
dir               = ${INTERMEDIATE}
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
# The root key and root certificate.
private_key       = \$dir/private/intermediate.key.pem
certificate       = \$dir/certs/intermediate.cert.pem
# For certificate revocation lists.
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/intermediate.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose
[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
prompt              = no
string_mask         = utf8only
# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256
# Extension to add when the -x509 option is used.
x509_extensions     = v3_ca
req_extensions      = req_ext
[ req_distinguished_name ]
0.domainComponent       = "io"
1.domainComponent       = "openshift"
organizationName        = "OpenShift Origin"
organizationalUnitName  = "CI Proxy"
commonName              = "CI Proxy"
[ req_ext ]
subjectAltName          = "DNS.1:*.compute-1.amazonaws.com"
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[ crl_ext ]
authorityKeyIdentifier=keyid:always
[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

  popd
  uuidgen | sha256sum | cut -b -32 > intpassfile

  openssl genrsa -aes256 \
    -out ${INTERMEDIATE}/private/intermediate.key.pem \
    -passout file:intpassfile 4096 2>/dev/null

  chmod 400 ${INTERMEDIATE}/private/intermediate.key.pem

  openssl req -config ${INTERMEDIATE}/openssl.cnf -new -sha256 \
    -key ${INTERMEDIATE}/private/intermediate.key.pem \
    -passin file:intpassfile \
    -out ${INTERMEDIATE}/csr/intermediate.csr.pem 2>/dev/null

  openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
    -days 3650 -notext -md sha256 \
    -batch \
    -in ${INTERMEDIATE}/csr/intermediate.csr.pem \
    -passin file:capassfile \
    -out ${INTERMEDIATE}/certs/intermediate.cert.pem 2>/dev/null

  chmod 444 ${INTERMEDIATE}/certs/intermediate.cert.pem

  openssl verify -CAfile certs/ca.cert.pem \
    ${INTERMEDIATE}/certs/intermediate.cert.pem

  cat ${INTERMEDIATE}/certs/intermediate.cert.pem \
    certs/ca.cert.pem > ${INTERMEDIATE}/certs/ca-chain.cert.pem

  chmod 444 ${INTERMEDIATE}/certs/ca-chain.cert.pem
  popd
}


cluster_name=${NAMESPACE}-${JOB_NAME_HASH}

CONFIG="${SHARED_DIR}/install-config.yaml"
CERTS="${SHARED_DIR}/INTERMEDIATE/certs"

PASSWORD="$(uuidgen | sha256sum | cut -b -32)"

cat >> "${CERTS}/password" << EOF
${PASSWORD}
EOF

PROXY_DNS="squid.${cluster_name}.origin-ci-int-aws.dev.rhcloud.com"

PROXY_URL="http://${cluster_name}:${PASSWORD}@${PROXY_DNS}:3128/"
TLS_PROXY_URL="https://${cluster_name}:${PASSWORD}@${PROXY_DNS}:3130/"

cat >> "${CONFIG}" << EOF
proxy:
  httpsProxy: ${PROXY_URL}
  httpProxy: ${PROXY_URL}
additionalTrustBundle: |
$(cat ${CERTS}/ca-chain.cert.pem | awk '{print "  "$0}')
EOF
