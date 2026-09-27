#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
# Throwaway certificates for the QEMU TLS rows, into directory $1:
#   ca.pem         a test CA
#   srv.pem/.key   a server certificate that CA signed, for the names the rows
#                  use: 10.0.2.2.nip.io (the chip's view of the host, through
#                  slirp's DNS) and 127.0.0.1.nip.io (the desktop's), and the
#                  two addresses themselves
#   wrong-ca.pem   a second CA that signed nothing here -- the control a
#                  CERT_REQUIRED client must REFUSE, or verification is not
#                  being done at all
# P-256 keys: an RSA-2048 handshake is several times slower on an emulated chip.
set -euo pipefail
D="${1:?usage: mkcerts.sh <dir>}"
mkdir -p "$D"
cd "$D"
EC="-newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes"
openssl req -x509 $EC -keyout ca.key -out ca.pem -days 7 -subj /CN=pxx-qemu-test-ca 2>/dev/null
openssl req $EC -keyout srv.key -out srv.csr -subj /CN=10.0.2.2.nip.io 2>/dev/null
printf 'subjectAltName=DNS:10.0.2.2.nip.io,DNS:127.0.0.1.nip.io,IP:10.0.2.2,IP:127.0.0.1\n' > srv.ext
openssl x509 -req -in srv.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out srv.pem -days 7 \
  -extfile srv.ext 2>/dev/null
openssl req -x509 $EC -keyout wrong-ca.key -out wrong-ca.pem -days 7 -subj /CN=pxx-qemu-wrong-ca 2>/dev/null
echo "mkcerts: $D"
