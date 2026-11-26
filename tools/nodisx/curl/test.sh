#!/bin/sh
# test.sh: build curl + mbedTLS with onsite.sh (pxx only) and compare it with
# the gcc build record.sh left in $NODISX_WORK/curl-ref, against a local
# server (testserver.py: plain HTTP, and HTTPS with an EC and an RSA
# certificate from a throwaway CA made here):
#   1. curl -V (version, protocols, features)
#   2. file://, HTTP GET/HEAD, ranges, chunked, redirects, POST/PUT uploads
#      (a 3 MB random file: the bytes must come back identical), headers,
#      cookies, basic auth, status codes, -w write-out, connection reuse
#   3. HTTPS over TLS 1.2 and 1.3, EC and RSA: a verified fetch with the test
#      CA, the refusals (the compiled-in bundle path and the Mozilla bundle,
#      neither of which holds the test CA; a wrong host name), -k, an upload
#   4. the Mozilla CA bundle: curl loads it (a broken bundle is exit 77, an
#      unknown CA exit 60), and every certificate in it parses (mbedTLS's own
#      x509 parser, via curl's --cacert)
#   5. mbedTLS's own self-test (programs/test/selftest.c: AES, GCM, CCM, SHA,
#      HMAC-DRBG, CTR-DRBG, RSA, ECP, ECJPAKE, x509, ...), built by pxx from
#      the same units, its output compared with the gcc build's
# NODISX_NET=1 also fetches https://curl.se/ with the installed bundle.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/curl/test.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$T/../../../compiler/pascal26}
REF=$W/curl-ref
R=$W/recipe/curl
[ -x "$REF/curl/src/curl" ] && [ -f "$R/units" ] || { echo "test: run record.sh first" >&2; exit 1; }
O=$(mktemp -d -p "$W" curl-test.XXXXXX)
DL=$W/dl PXX=$PXX JOBS=${JOBS:-4} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root" > "$O/onsite.log" 2>&1 \
  || { tail -5 "$O/onsite.log" >&2; echo "test: FAIL (on-site build)" >&2; exit 1; }
G=$REF/curl/src/curl
P=$O/work/curl
fail=0

# compare NAME CMD... : run CMD with $C (the curl under test) set to the gcc
# build, then to the pxx one; the outputs (exit status included) must match
compare() {
  name=$1; shift
  g=$(C=$G; rc=0; eval "$*" 2>&1 || rc=$?; echo "rc=$rc")
  p=$(C=$P; rc=0; eval "$*" 2>&1 || rc=$?; echo "rc=$rc")
  # elapsed times in curl's messages ("after 1 ms") are not a difference
  g=$(printf '%s\n' "$g" | sed 's/after [0-9]* ms/after N ms/g')
  p=$(printf '%s\n' "$p" | sed 's/after [0-9]* ms/after N ms/g')
  if [ "$g" = "$p" ]; then
    echo "same    $name ($(printf '%s\n' "$g" | tail -1))"
  else
    echo "DIFFERS $name"
    printf '%s\n' "$g" > "$O/$name.gcc"
    printf '%s\n' "$p" > "$O/$name.pxx"
    diff "$O/$name.gcc" "$O/$name.pxx" | head -10
    fail=1
  fi
}
# expect NAME RC CMD... : as compare, and the exit status must be RC
expect() {
  name=$1; want=$2; shift 2
  compare "$name" "$@"
  got=$(C=$P; rc=0; eval "$*" > /dev/null 2>&1 || rc=$?; echo $rc)
  [ "$got" = "$want" ] || { echo "WRONG   $name: exit $got, expected $want"; fail=1; }
}

# --- payloads, the test CA and the server ---
D=$O/files
mkdir -p "$D" "$O/ca"
head -c 3145728 /dev/urandom > "$D/big.bin"
printf 'small file, one line\n' > "$D/small.txt"
head -c 100000 /dev/urandom > "$D/mid.bin"
A=$O/ca
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 \
  -subj /CN=nodisx-test-ca -keyout "$A/ca.key" -out "$A/ca.crt" > /dev/null 2>&1
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\n' > "$A/ext"
for k in ec rsa; do
  if [ $k = ec ]; then kopt="-newkey ec -pkeyopt ec_paramgen_curve:P-256"; else kopt="-newkey rsa:2048"; fi
  # shellcheck disable=SC2086
  openssl req $kopt -nodes -subj /CN=localhost -keyout "$A/$k.key" -out "$A/$k.csr" > /dev/null 2>&1
  openssl x509 -req -in "$A/$k.csr" -CA "$A/ca.crt" -CAkey "$A/ca.key" -CAcreateserial \
    -days 2 -extfile "$A/ext" -out "$A/$k.crt" > /dev/null 2>&1
done
python3 -I "$T/testserver.py" "$D" "$O/ports" "$A" 2> "$O/server.log" &
spid=$!
trap 'kill $spid 2> /dev/null || :' EXIT
i=0
while [ ! -f "$O/ports" ]; do i=$((i + 1)); [ $i -lt 100 ] || { echo "test: server did not start" >&2; exit 1; }; sleep 0.1; done
port() { awk -v k="$1" '$1 == k { print $2 }' "$O/ports"; }
H=http://127.0.0.1:$(port http)
E=https://localhost:$(port https-ec)
S=https://localhost:$(port https-rsa)
CA=$A/ca.crt
B=$R/cacert.pem
sum() { sha256sum | cut -c1-16; }

# --- 1. version ---
compare version '"$C" -V'

# --- 2. file and HTTP ---
compare file-get '"$C" -sS "file://$D/big.bin" | sum'
compare file-missing '"$C" -sS "file://$D/nothere"'
compare http-get '"$C" -sS "$H/f/big.bin" | sum'
compare http-get-to-file '"$C" -sS -o "$O/dl.tmp" "$H/f/big.bin" && cmp "$O/dl.tmp" "$D/big.bin" && echo identical'
compare http-head '"$C" -sS -I "$H/f/mid.bin" | grep -i -e "^HTTP" -e "^content-length" | tr -d "\r"'
compare http-range '"$C" -sS -r 1000-1999 "$H/f/big.bin" | sum'
compare http-chunked '"$C" -sS "$H/chunked/big.bin" | sum'
compare http-redirect '"$C" -sS -L -w "%{http_code} %{num_redirects} %{url_effective}\n" "$H/redir/4" | sed "s|$H|H|"'
compare http-redirect-max '"$C" -sS -L --max-redirs 2 "$H/redir/5"'
compare http-post '"$C" -sS --data-binary "@$D/big.bin" "$H/echo"'
compare http-post-form '"$C" -sS -d a=1 -d "b=two words" "$H/echo"'
compare http-put '"$C" -sS -T "$D/mid.bin" "$H/echo"'
compare http-put-chunked '"$C" -sS -H "Transfer-Encoding: chunked" -T "$D/mid.bin" "$H/echo"'
compare http-mime '"$C" -sS -F "f=@$D/small.txt" -F x=y "$H/echo" | cut -d" " -f1'
compare http-headers '"$C" -sS -H "X-Test: hello" -b "k=v" -u user:pass -r 5-9 "$H/hdr"'
compare http-cookies '"$C" -sS -c "$O/jar.tmp" "$H/setcookie" > /dev/null && "$C" -sS -b "$O/jar.tmp" "$H/hdr" | grep Cookie'
compare http-404 '"$C" -sS -w "%{http_code}\n" "$H/code/404"'
expect http-fail 22 '"$C" -sS -f "$H/code/500"'
compare http-reuse '"$C" -sS -w "%{num_connects}\n" "$H/f/small.txt" "$H/f/small.txt" "$H/f/small.txt"'
compare http-parallel '"$C" -sS -Z -o "$O/p1.tmp" "$H/f/mid.bin" -o "$O/p2.tmp" "$H/f/big.bin" -o "$O/p3.tmp" "$H/f/small.txt" && cat "$O/p1.tmp" "$O/p2.tmp" "$O/p3.tmp" | sum'
expect http-refused 7 '"$C" -sS "http://127.0.0.1:1/"'

# --- 3. HTTPS ---
for k in ec rsa; do
  if [ $k = ec ]; then U=$E; else U=$S; fi
  for v in 1.2 1.3; do
    compare "https-$k-tls$v" '"$C" -sS --cacert "$CA" --tlsv$v --tls-max $v "$U/f/big.bin" | sum'
  done
  compare "https-$k-info" '"$C" -sS --cacert "$CA" -o /dev/null -w "%{http_code} %{ssl_verify_result} %{scheme}\n" "$U/f/small.txt"'
  compare "https-$k-upload" '"$C" -sS --cacert "$CA" --data-binary "@$D/big.bin" "$U/echo"'
  expect "https-$k-default-bundle" 60 'env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR "$C" -sS "$U/f/small.txt"'
  expect "https-$k-bundle-lacks-ca" 60 '"$C" -sS --cacert "$B" "$U/f/small.txt"'
  expect "https-$k-wrong-name" 60 '"$C" -sS --cacert "$CA" --resolve "wrong.example:$(echo "$U" | sed "s|.*:||"):127.0.0.1" "https://wrong.example:$(echo "$U" | sed "s|.*:||")/f/small.txt"'
  compare "https-$k-insecure" '"$C" -sS -k "$U/f/small.txt"'
done
compare https-reuse '"$C" -sS --cacert "$CA" -w "%{num_connects}\n" "$E/f/small.txt" "$E/f/small.txt"'

# --- 4. the Mozilla bundle ---
n=$(grep -c 'BEGIN CERTIFICATE' "$B")
expect bundle-loads 60 '"$C" -sS --cacert "$B" "$E/f/small.txt"'
printf 'not a certificate\n' > "$O/broken.pem"
expect bundle-broken 77 '"$C" -sS --cacert "$O/broken.pem" "$E/f/small.txt"'
# every certificate on its own: each must load (60: parsed, did not match)
mkdir -p "$O/one"
awk -v d="$O/one" '/BEGIN CERTIFICATE/ { n++ } n { print > (d "/" n ".pem") }' "$B"
bad=0
for f in "$O/one"/*.pem; do
  rc=0; "$P" -sS --cacert "$f" "$E/f/small.txt" > /dev/null 2>&1 || rc=$?
  [ "$rc" = 60 ] || { echo "WRONG   bundle certificate $(basename "$f"): exit $rc"; bad=1; }
done
[ $bad = 0 ] && echo "same    bundle: all $n certificates load" || fail=1
if [ "${NODISX_NET:-}" = 1 ]; then
  expect net-curl-se 0 '"$C" -sS --cacert "$B" -o /dev/null -w "%{http_code}\n" https://curl.se/'
fi

# --- 5. mbedTLS self-test, pxx and gcc ---
M=$O/work/src/mbedtls
objs=
for u in $(awk '$1 ~ /^mbedtls\/library\// { print $1 }' "$R/units"); do
  o=$O/work/obj/$(echo "$u" | tr / _)
  if [ ! -f "$o" ]; then
    line=$(grep -m1 "^$u " "$R/units")
    # shellcheck disable=SC2086
    ( set -- $line; dir=$2; src=$3; shift 3; cd "$O/work/src/$dir"
      eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime --threadsafe $* \"\$src\" \"\$o\"" > "$o.log" 2>&1 ) \
      || { echo "test: FAIL compiling $u: $(grep -m1 error "$o.log")" >&2; exit 1; }
  fi
  objs="$objs $o"
done
( cd "$M/programs/test" && "$PXX" --emit-obj --function-sections --shared-runtime --threadsafe \
    -I../../include -I../../library -D_FILE_OFFSET_BITS=64 selftest.c "$O/selftest.o" ) > "$O/selftest.log" 2>&1 \
  || { tail -3 "$O/selftest.log" >&2; echo "test: FAIL (selftest.c)" >&2; exit 1; }
# shellcheck disable=SC2086
"$PXX" --link --threadsafe -o "$O/selftest" "$O/selftest.o" $objs > "$O/selftest-link.log" 2>&1 \
  || { tail -5 "$O/selftest-link.log" >&2; echo "test: FAIL (selftest link)" >&2; exit 1; }
( cd "$REF/mbedtls/programs/test" && gcc -O2 -I../../include -I../../library -D_FILE_OFFSET_BITS=64 \
    selftest.c -o "$O/selftest-gcc" "$REF/mbedtls/library/libmbedx509.a" "$REF/mbedtls/library/libmbedcrypto.a" -lpthread )
g=$(rc=0; "$O/selftest-gcc" 2>&1 || rc=$?; echo "rc=$rc")
p=$(rc=0; "$O/selftest" 2>&1 || rc=$?; echo "rc=$rc")
if [ "$g" = "$p" ] && printf '%s\n' "$p" | grep -q 'Executed .* test suites' && [ "$(printf '%s\n' "$p" | tail -1)" = rc=0 ]; then
  echo "same    mbedtls selftest ($(printf '%s\n' "$p" | grep -c passed) passed lines, rc=0)"
else
  echo "DIFFERS mbedtls selftest"
  printf '%s\n' "$g" > "$O/selftest.gcc"; printf '%s\n' "$p" > "$O/selftest.pxx"
  diff "$O/selftest.gcc" "$O/selftest.pxx" | head -10; printf '%s\n' "$p" | tail -3
  fail=1
fi

size "$P" 2> /dev/null || :
if [ $fail = 0 ]; then echo "curl recipe: PASS"; else echo "curl recipe: FAIL (see $O)"; exit 1; fi
