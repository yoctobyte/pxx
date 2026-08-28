#!/bin/sh
# crtl declaration census — every function crtl DECLARES must also be DEFINED.
#
# The recurring failure this gates is quiet by construction: a header declares a
# function, nothing in lib/crtl/src defines it, and a C program that calls it
# links against the system libc on the dev box and cannot run anywhere else.
# It has bitten four times (inttypes' strtoimax/strtoumax, an 18-function batch,
# a 10-function batch, environ) and each time it was found by a hand-run probe
# somebody had to remember to run.
#
# The name list is GENERATED from the headers on every run, never checked in: a
# frozen list of ~358 names is a claim about the search that produced it, and it
# goes stale exactly where the next declared-but-unimplemented function appears.
#
# Usage: sh test/crtl_declaration_census.sh <pxx> <tmpdir>
set -e
PXX=${1:?usage: crtl_declaration_census.sh <pxx> <tmpdir>}
TMP=${2:?usage: crtl_declaration_census.sh <pxx> <tmpdir>}
INC=lib/crtl/include
SRC=$TMP/crtl_census.c
BIN=$TMP/crtl_census
LOG=$TMP/crtl_census.log

{
  for h in $INC/*.h $INC/sys/*.h; do printf '#include <%s>\n' "${h#$INC/}"; done
  echo 'void *volatile __census_sink;'
  echo 'int main(void){'
  # Strip comments, keep one declaration per line, extract the declared name.
  # LC_ALL=C on the sort is load-bearing: under a UTF-8 locale `sort -u`
  # collates `_longjmp` and `longjmp` as EQUAL (collation ignores punctuation)
  # and silently drops one of two distinct C identifiers.
  awk '
    { line=$0
      while (1) {
        if (inc) { p=index(line,"*/"); if (!p) { line=""; break }
                   line=substr(line,p+2); inc=0; continue }
        p=index(line,"/*"); q=index(line,"//")
        if (q && (!p || q<p)) { line=substr(line,1,q-1); break }
        if (!p) break
        line=substr(line,1,p-1) " " substr(line,p+2); inc=1
        rest=substr($0,p+2); r=index(rest,"*/")
        if (r) { line=substr($0,1,p-1) " " substr(rest,r+2); inc=0; break }
      }
      print line }' $INC/*.h $INC/sys/*.h \
  | sed -e 's/[ \t][ \t]*/ /g' \
  | grep ';[ ]*$' \
  | grep -v '^ *#' | grep -v '^ *typedef' | grep -v '^ *extern *"C"' \
  | sed -n 's/^[A-Za-z_][A-Za-z0-9_ \*]* \**\([a-z_][a-z0-9_]*\) *(.*/\1/p' \
  | LC_ALL=C sort -u \
  | while read n; do printf '  __census_sink = (void*)&%s;\n' "$n"; done
  echo '  return 0;'
  echo '}'
} > $SRC

# A generator that silently produced an empty list would pass every check below,
# so assert the search itself found something before trusting its all-clear.
n=$(grep -c '__census_sink = ' $SRC)
test "$n" -ge 300 || { echo "FAIL: census found only $n declarations — the generator is broken, not the library"; exit 1; }

$PXX --threadsafe -I$INC -I$INC/sys -Ilib/crtl/src $SRC $BIN > $LOG 2>&1 || {
  echo "FAIL: census TU did not compile"; cat $LOG; exit 1; }

if grep -q 'does not define' $LOG; then
  echo "FAIL: crtl declares functions it does not define:"
  grep -o 'crtl does not define [a-z_0-9]*' $LOG | awk '{print "  " $NF}' | sort -u
  exit 1
fi

if command -v readelf >/dev/null 2>&1; then
  d=$(readelf -d $BIN 2>/dev/null | grep -c NEEDED || true)
  test "$d" = "0" || { echo "FAIL: census binary has $d DT_NEEDED — a declaration bound to the system libc"; exit 1; }
fi

$BIN || { echo "FAIL: census binary did not run"; exit 1; }
echo "  lib-test: crtl declaration census — $n declared, all defined, no libc imports"
