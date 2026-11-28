#!/bin/sh
# test.sh: build git with onsite.sh (pxx only) and compare it with the gcc
# build record.sh left in $NODISX_WORK/git-ref. scenario.sh runs each
# section once with each git, and what they print (object ids included,
# exit status last) must be the same:
#   history     commits, log, show, diff, trees
#   branches    branch, merge, tag, describe, rebase, cherry-pick
#   worktree    status, stash, add/restore, grep, blame, ls-files, mv/rm
#   objects     a 3 MB file and a one-line change to it: loose objects, gc
#               --aggressive (zlib, deltas), verify-pack, fsck --strict,
#               archive (tar, zip), bundle
#   sha256      a repository with SHA-256 object ids
#   clone-file  clone (full, shallow, bare) and push over file://
#   clone-http  clone, fetch and ls-remote over dumb HTTP, then HTTPS (EC
#               and RSA certificates from a throwaway CA, TLS through
#               libcurl and mbedTLS), served by ../curl/testserver.py
# and an https clone with the wrong CA must fail, in both, the same way.
# Each git finds git-remote-https through GIT_EXEC_PATH and the templates
# through GIT_TEMPLATE_DIR: the pxx build as onsite.sh installed it, the gcc
# build from its tree.
# NODISX_NET=1 also clones https://github.com/octocat/Hello-World with the
# curl recipe's Mozilla bundle.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/git/test.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$T/../../../compiler/pascal26}
REF=$W/git-ref
R=$W/recipe/git
[ -x "$REF/git/git" ] && [ -f "$R/units" ] || { echo "test: run record.sh first" >&2; exit 1; }
O=$(mktemp -d -p "$W" git-test.XXXXXX)
DL=$W/dl PXX=$PXX JOBS=${JOBS:-4} RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root" > "$O/onsite.log" 2>&1 \
  || { tail -5 "$O/onsite.log" >&2; echo "test: FAIL (on-site build)" >&2; exit 1; }
# the gcc build, laid out as an exec path and a template directory
mkdir -p "$O/gcc/bin" "$O/gcc/exec"
cp "$REF/git/git" "$O/gcc/bin/git"; cp "$REF/git/git" "$O/gcc/exec/git"
for n in git-remote-http git-remote-https; do cp "$REF/git/git-remote-http" "$O/gcc/exec/$n"; done
GT=$REF/git/templates/blt
PT=$O/root/share/git-core/templates
fail=0

# run SIDE SECTION [VAR=VALUE...]: scenario.sh with that side's git
run() {
  side=$1; sec=$2; shift 2
  d=$O/run-$side-$sec; rm -rf "$d"; mkdir -p "$d"
  if [ "$side" = gcc ]; then b=$O/gcc/bin x=$O/gcc/exec t=$GT; else b=$O/root/bin x=$O/root/libexec/git-core t=$PT; fi
  rc=0
  env "$@" PATH="$b:$PATH" GIT_EXEC_PATH="$x" GIT_TEMPLATE_DIR="$t" sh "$T/scenario.sh" "$d" "$sec" > "$d.out" 2>&1 || rc=$?
  # the run directory's path is the only thing allowed to differ
  sed "s|$d|DIR|g" "$d.out"; echo "rc=$rc"
}
compare() {
  name=$1; sec=$2; shift 2
  g=$(run gcc "$sec" "$@"); p=$(run pxx "$sec" "$@")
  if [ "$g" = "$p" ]; then
    echo "same    $name ($(printf '%s\n' "$g" | wc -l) lines, $(printf '%s\n' "$g" | tail -1))"
  else
    echo "DIFFERS $name"
    printf '%s\n' "$g" > "$O/$name.gcc"; printf '%s\n' "$p" > "$O/$name.pxx"
    diff "$O/$name.gcc" "$O/$name.pxx" | head -12
    fail=1
  fi
  case $name in *-wrong-ca) ;; *) printf '%s\n' "$p" | tail -1 | grep -q '^rc=0$' || { echo "WRONG   $name: $(printf '%s\n' "$p" | tail -1)"; fail=1; } ;; esac
}

g=$("$REF/git/git" --version); p=$("$O/root/bin/git" --version)
if [ "$g" = "$p" ]; then echo "same    version ($p)"; else echo "DIFFERS version: $g / $p"; fail=1; fi
for s in history branches worktree objects sha256 clone-file; do compare "$s" "$s"; done

# --- dumb HTTP and HTTPS: a bare repository with update-server-info ---
D=$O/files; A=$O/ca
mkdir -p "$D" "$A"
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
# the served repository: the clone-file section's source, made by gcc's git
cp -R "$O/run-gcc-clone-file/src" "$O/src"
GIT_CONFIG_NOSYSTEM=1 HOME=$O GIT_TEMPLATE_DIR=$GT "$REF/git/git" clone -q --bare "$O/src" "$D/repo.git"
GIT_CONFIG_NOSYSTEM=1 HOME=$O "$REF/git/git" -C "$D/repo.git" update-server-info
python3 -I "$T/../curl/testserver.py" "$D" "$O/ports" "$A" 2> "$O/server.log" &
spid=$!
trap 'kill $spid 2> /dev/null || :' EXIT
i=0
while [ ! -f "$O/ports" ]; do i=$((i + 1)); [ $i -lt 100 ] || { echo "test: server did not start" >&2; exit 1; }; sleep 0.1; done
port() { awk -v k="$1" '$1 == k { print $2 }' "$O/ports"; }
compare http clone-http URL="http://127.0.0.1:$(port http)/tree/repo.git"
compare https-ec clone-http URL="https://localhost:$(port https-ec)/tree/repo.git" GIT_SSL_CAINFO="$A/ca.crt"
compare https-rsa clone-http URL="https://localhost:$(port https-rsa)/tree/repo.git" GIT_SSL_CAINFO="$A/ca.crt"
compare https-wrong-ca clone-http URL="https://localhost:$(port https-ec)/tree/repo.git" GIT_SSL_CAINFO="$W/recipe/curl/cacert.pem"
printf '%s\n' "$(run pxx clone-http URL="https://localhost:$(port https-ec)/tree/repo.git" GIT_SSL_CAINFO="$W/recipe/curl/cacert.pem")" \
  | grep -q 'SSL\|certificate' || { echo "WRONG   https-wrong-ca: the pxx git did not refuse the certificate"; fail=1; }

if [ "${NODISX_NET:-0}" = 1 ]; then
  d=$O/net; mkdir -p "$d"
  if GIT_CONFIG_NOSYSTEM=1 HOME=$d GIT_EXEC_PATH=$O/root/libexec/git-core GIT_SSL_CAINFO=$W/recipe/curl/cacert.pem \
       "$O/root/bin/git" clone -q --depth 1 https://github.com/octocat/Hello-World "$d/hw" 2> "$d.err" \
     && [ -f "$d/hw/README" ]; then
    echo "same    net-github (cloned with the Mozilla bundle)"
  else
    echo "DIFFERS net-github: $(head -2 "$d.err")"; fail=1
  fi
fi

size "$O/work/git" "$O/work/git-remote-http" 2>/dev/null || :
if [ "$fail" = 0 ]; then echo "git recipe: PASS"; else echo "git recipe: FAIL (outputs in $O)"; exit 1; fi
