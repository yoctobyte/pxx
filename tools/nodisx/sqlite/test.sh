#!/bin/sh
# test.sh: build sqlite3 with onsite.sh (pxx) and with gcc from the same
# sources and flags, then run the SQL scripts in sql/ through both:
#   01-sql           tables, constraints, all join kinds, aggregates, views,
#                    triggers, upsert, RETURNING, STRICT, generated columns,
#                    query plans
#   02-functions     the built-in functions, affinity and casts, integer and
#                    real edge cases, printf formatting, dates, JSON/JSONB
#   03-cte-windows   recursive CTEs (Fibonacci to 92, a Mandelbrot), floating
#                    point summed 100,000 times, every window function
#   04-shell         the shell's output modes, .import, .dump, .sha3sum, ...
#   05-errors-txn    error messages, savepoints, rollback, WAL, VACUUM
#   06-bulk          200,000 rows, overflow pages, indexes, delete/update,
#                    VACUUM on a small cache
# Each runs in a fresh directory per build with relative file names. Output,
# exit status and the database file must be identical; then each build reads
# the other's 06 database (integrity_check and the same queries).
# If the download directory also holds pixix's pinned amalgamation zip, its
# sources are checked to be the tarball's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/sqlite/test.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$T/../../../compiler/pascal26}
R=$W/recipe/sqlite
[ -f "$R/sources.list" ] || { echo "test: run record.sh first" >&2; exit 1; }
O=$(mktemp -d -p "$W" sqlite-test.XXXXXX)
DL=$W/dl PXX=$PXX RECIPE=$R sh "$R/onsite.sh" "$O/work" "$O/root" > "$O/onsite.log" 2>&1 \
  || { tail -5 "$O/onsite.log" >&2; echo "test: FAIL (on-site build)" >&2; exit 1; }
S=$O/work/src
read -r flags < "$R/flags"
# The gcc reference uses -DLONGDOUBLE_TYPE=double: pxx's long double IS double
# (bug-c-long-double-is-8-bytes-in-pxx-and-16-in-gcc), so sqlite's start-up
# probe (hasHighPrecisionDouble) turns its long-double path off under pxx and
# it formats reals with double-double arithmetic, the path it takes wherever
# long double is double (MSVC, many ARM targets). Against an 80-bit gcc build
# the one visible difference is past 17 digits: printf('%!.20g', 0.1) is
# 0.1000000000000000055 under pxx (the exact digits) and 0.100000000000000005
# under x87.
# shellcheck disable=SC2086
( cd "$S" && gcc -O2 $flags -DLONGDOUBLE_TYPE=double -I. sqlite3.c shell.c -o "$O/sqlite3-gcc" -lm ) 2> "$O/gcc.log"
G=$O/sqlite3-gcc
P=$O/root/bin/sqlite3
fail=0

z=$W/dl/sqlite-amalgamation-3460000.zip
if [ -f "$z" ] && command -v unzip > /dev/null; then
  echo "712a7d09d2a22652fb06a49af516e051979a3984adb067da86760e60ed51a7f5  $z" | sha256sum -c --quiet - \
    || { echo "WRONG   pixix's amalgamation zip does not match its pin"; fail=1; }
  mkdir -p "$O/zip"; unzip -q "$z" -d "$O/zip"
  for f in sqlite3.c shell.c sqlite3.h sqlite3ext.h; do
    cmp -s "$S/$f" "$O/zip/sqlite-amalgamation-3460000/$f" || { echo "WRONG   $f differs from pixix's zip"; fail=1; }
  done
  [ $fail = 0 ] && echo "same    sources as pixix's pinned amalgamation zip"
fi

# a CSV for 04-shell's .import
awk 'BEGIN { print "a,b,c"; for (i = 1; i <= 500; i++) printf "%d,%d,\"v %d, x\"\n", i, i * i, i }' > "$O/data.csv"

for f in "$T"/sql/*.sql; do
  n=$(basename "$f" .sql)
  for c in gcc pxx; do
    d=$O/run/$c/$n
    mkdir -p "$d"
    cp "$O/data.csv" "$d/"
    if [ $c = gcc ]; then bin=$G; else bin=$P; fi
    ( cd "$d" && rc=0; "$bin" test.db < "$f" > out 2>&1 || rc=$?; echo "rc=$rc" >> out )
  done
  a=$O/run/gcc/$n; b=$O/run/pxx/$n
  if cmp -s "$a/out" "$b/out"; then
    echo "same    $n ($(wc -l < "$b/out") lines, $(tail -1 "$b/out"))"
  else
    echo "DIFFERS $n"; diff "$a/out" "$b/out" | head -12; fail=1
  fi
  for x in test.db out.txt; do
    [ -f "$a/$x" ] || continue
    if cmp -s "$a/$x" "$b/$x"; then echo "same    $n $x ($(wc -c < "$b/$x") bytes)"
    else echo "DIFFERS $n $x"; fail=1; fi
  done
done

# each build reads the other's bulk database
q='PRAGMA integrity_check; SELECT count(*), sum(k), sum(length(s)), printf("%.6f", sum(r)) FROM big; SELECT s FROM big WHERE k > 999990 ORDER BY s;'
g=$(echo "$q" | "$G" "$O/run/pxx/06-bulk/test.db" 2>&1)
p=$(echo "$q" | "$P" "$O/run/gcc/06-bulk/test.db" 2>&1)
if [ "$g" = "$p" ] && [ "$(printf '%s\n' "$p" | head -1)" = ok ]; then
  echo "same    cross-read: gcc reads pxx's database and pxx reads gcc's"
else
  echo "DIFFERS cross-read"; printf '%s\n---\n%s\n' "$g" "$p" | head -12; fail=1
fi

size "$P" 2> /dev/null || :
if [ $fail = 0 ]; then echo "sqlite recipe: PASS"; else echo "sqlite recipe: FAIL (see $O)"; exit 1; fi
