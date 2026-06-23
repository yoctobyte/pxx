#!/usr/bin/env bash
# Differential probe: run small Pascal programs under the pinned pxx stable AND
# FPC, diff their stdout, and report divergences. A cheap way to surface
# FPC-parity bugs (this harness found bug-writeln-boolean-format,
# bug-writeln-real-format, bug-length-rejects-non-variable).
#
# Output: one DIFF line per divergence. Known/filed divergences are tagged
# [known] so a clean run shows only NEW ones. A pxx compile failure on code FPC
# accepts is itself a divergence (often a missing intrinsic or an "expects a
# variable" gap) and is reported.
#
# Usage: tools/fpc_diff_probe.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}"
command -v fpc >/dev/null || { echo "fpc not found"; exit 2; }

new=0
known=0

# probe NAME [known] -- full program on stdin
probe() {
  local name="$1"; local tag=""
  if [ "${2:-}" = "known" ]; then tag="known"; fi
  { echo 'program fdp;'; cat; } > /tmp/fdp.pas   # pxx requires a program header; FPC tolerates either
  local fr pr
  if fpc -Mobjfpc -vw -o/tmp/fdp_f /tmp/fdp.pas >/dev/null 2>&1; then
    fr="$(/tmp/fdp_f 2>&1)"
  else fr="<fpc-compile-fail>"; fi
  if "$S" /tmp/fdp.pas /tmp/fdp_p >/tmp/fdp_c.log 2>&1; then
    pr="$(/tmp/fdp_p 2>&1)"
  else pr="<pxx-compile-fail: $(grep -oE 'error[^(]*' /tmp/fdp_c.log | head -1)>"; fi
  if [ "$fr" = "$pr" ]; then return; fi
  # skip cases where FPC itself can't compile (probe is then meaningless)
  [ "$fr" = "<fpc-compile-fail>" ] && return
  if [ "$tag" = "known" ]; then
    printf 'DIFF [known] %-22s fpc=[%s] pxx=[%s]\n' "$name" "$fr" "$pr"; known=$((known+1))
  else
    printf 'DIFF        %-22s fpc=[%s] pxx=[%s]\n' "$name" "$fr" "$pr"; new=$((new+1))
  fi
}

# ---- arithmetic ----
probe int-negdiv   <<'P'
begin writeln((-7) div 2, '|', (-7) mod 2); end.
P
probe int-shr      <<'P'
begin writeln(1 shl 10, '|', 1024 shr 3); end.
P
probe neg-mod      <<'P'
begin writeln(7 mod (-3), '|', (-7) mod (-3)); end.
P
probe div-large    <<'P'
var a, b: int64; begin a := 1000000; b := 1000000; writeln(a * b); end.
P
probe word-wrap    <<'P'
var w: word; begin w := 65535; w := w + 1; writeln(w); end.
P

# ---- ordinals / chars ----
probe char-ord     <<'P'
begin writeln(ord('A'), '|', chr(66)); end.
P
probe inc-dec      <<'P'
var i: integer; begin i := 5; inc(i, 3); dec(i); writeln(i); end.
P

# ---- strings ----
probe str-copy     <<'P'
var s: string; begin s := 'abcdef'; writeln(copy(s, 2, 3)); end.
P
probe str-cmp      <<'P'
begin if 'abc' < 'abd' then writeln('lt') else writeln('ge'); end.
P
probe str-concat   <<'P'
var s: string; begin s := 'a'; s := s + 'b' + 'c'; writeln(s); end.
P
probe str-len-var  <<'P'
var s: string; begin s := 'hello'; writeln(length(s)); end.
P

# ---- sets ----
probe set-in       <<'P'
begin if 3 in [1, 3, 5] then writeln('y') else writeln('n'); end.
P
probe char-set     <<'P'
var c: char; begin c := 'm'; if c in ['a'..'z'] then writeln('low') else writeln('hi'); end.
P

# ---- formatting ----
probe real-fixed   <<'P'
begin writeln(1.5:0:2, '|', (-2.25):0:3); end.
P
probe trunc-round  <<'P'
begin writeln(trunc(3.7), '|', round(2.5), '|', round(3.5)); end.
P

# ---- correctness guards (value semantics; must keep matching FPC) ----
probe rec-copy <<'P'
type tr = record x: integer; end; var a, b: tr; begin a.x := 5; b := a; b.x := 9; writeln(a.x, '|', b.x); end.
P
probe arr-copy <<'P'
type ta = array[0..2] of integer; var a, b: ta; begin a[0] := 5; b := a; b[0] := 9; writeln(a[0], '|', b[0]); end.
P
probe copy-overrun <<'P'
var s: string; begin s := 'abc'; writeln('[' + copy(s, 2, 100) + ']'); end.
P
probe copy-past-end <<'P'
var s: string; begin s := 'abc'; writeln('[' + copy(s, 5, 2) + ']'); end.
P
probe int-div-neg <<'P'
begin writeln((-10) div 3, '|', 10 div (-3)); end.
P
probe mod-signs <<'P'
begin writeln(17 mod 5, '|', (-17) mod 5, '|', 17 mod (-5)); end.
P
probe round-half-neg <<'P'
begin writeln(trunc(-3.7), '|', round(-2.5)); end.
P
probe array-zero-init <<'P'
var a: array[0..3] of integer; begin writeln(a[0], a[1], a[2], a[3]); end.
P
probe concat-loop <<'P'
var s: string; i: integer; begin s := ''; for i := 1 to 5 do s := s + 'x'; writeln(s, '|', length(s)); end.
P

# ---- known/filed divergences (kept as regression markers) ----
probe bool-write known <<'P'
begin writeln(1 > 0, '|', 2 < 1); end.
P
probe real-default known <<'P'
begin writeln(3.14159); end.
P
probe length-literal known <<'P'
begin writeln(length('hello')); end.
P
probe nested-proc known <<'P'
procedure outer; procedure inner; begin writeln('in'); end; begin inner; end;
begin outer; end.
P
probe nested-fn known <<'P'
function f(n: integer): integer; function g(m: integer): integer; begin g := m * 2; end;
begin f := g(n) + 1; end;
begin writeln(f(5)); end.
P
probe low-array known <<'P'
var a: array[5..9] of integer; begin writeln(low(a)); end.
P
probe high-nonzero-array known <<'P'
var a: array[5..9] of integer; begin writeln(high(a)); end.
P
probe builtin-case known <<'P'
var s: string; begin s := 'hi'; writeln(LENGTH(s)); end.
P
probe overload-by-type known <<'P'
function f(a: integer): string; begin f := 'INT'; end;
function f(a: string): string; begin f := 'STR'; end;
begin writeln(f(1), '|', f('x')); end.
P
probe variant-record known <<'P'
type tr = record case boolean of true: (i: integer); false: (c: char); end;
var r: tr; begin r.i := 65; writeln(ord(r.c)); end.
P
probe default-param known <<'P'
function f(a: integer; b: integer = 10): integer; begin f := a + b; end;
begin writeln(f(5), '|', f(5, 1)); end.
P
probe binary-literal known <<'P'
begin writeln(%1010); end.
P
probe as-inline-call known <<'P'
type ta = class end; tb = class(ta) procedure m; end;
procedure tb.m; begin writeln('M'); end;
var o: ta; begin o := tb.create; (o as tb).m; end.
P
probe subrange-type known <<'P'
type tr = 1..10; var x: tr; begin x := 5; writeln(x); end.
P

echo "---"
echo "new divergences: $new   known/filed: $known"
[ "$new" -eq 0 ] && exit 0 || exit 1
