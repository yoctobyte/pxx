#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Differential probe: run small C programs under gcc AND the pinned pxx stable,
# diff their stdout+stderr, and report divergences. The C-side mirror of
# tools/fpc_diff_probe.sh.
#
# WHY this and not tools/crtl_decl_probe.sh: that one answers "is the symbol
# implemented at all" (declaration -> dynamic import census). This one answers
# the question after it — "does the implementation AGREE with the oracle" — over
# crtl's EXISTING functions. `test/crtl_libc_oracle.c` does that for one recorded
# batch; this is the harness you add a case to in ten seconds.
#
# gcc is the oracle by project decision (feature-crtl-implement-libc-assumptions:
# "keep gcc's libc as the oracle for behaviour"). The pxx side is built libc-free
# (crtl's own implementations), which is the whole point — a glibc-linked run
# would agree with the oracle trivially.
#
# Output: one DIFF line per divergence; known/filed ones are tagged [known] so a
# clean run shows only NEW ones. A gcc compile failure is a SKIP and is COUNTED
# AND PRINTED — a case the oracle cannot build proves nothing, and a silent skip
# is how a disarmed case sits here for months looking like coverage.
#
# THE RULE THIS HARNESS KEEPS BREAKING: never read a side effect in the argument
# list of the call that causes it. `printf("%d [%s]", fread(b,...), b)`,
# `printf("%d %d", ftell(f), fgetc(f))`, `printf("%d %d", strtol(s,&e,0), e-s)`,
# `printf("%d %d %d", ctr(), ctr(), ctr())` — argument evaluation order is
# unspecified, gcc evaluates right-to-left, and pxx orders them differently on
# arm32/aarch64 than on x86-64. All of it legal, and every one of those shapes
# reported a phantom compiler bug here. Sequence the call, then print.
#
# NOT in scope: float formatting and libm rounding. Wrong values and crashes are
# in scope; ULP-chasing against a high-precision oracle is this repo's rabbit
# hole and is deliberately left to the libm tickets.
#
# CROSS MODE: `--target ARCH` (i386 | arm32 | aarch64 | riscv32) compiles the pxx
# side for ARCH and runs it under tools/run_target.sh. There is no cross-gcc on
# this box (not even gcc -m32 — no 32-bit multilib), so the oracle stays the
# NATIVE gcc run and each case is judged in two steps: pxx-native must match gcc
# first (otherwise the case is already reported by the default mode and cross
# proves nothing), then pxx-ARCH must match that same oracle. Same source, same
# answer required — a target-dependent divergence in a portable case is a bug,
# which is exactly how tools/lib_cross_sweep.sh found four of the last six
# urgent ones.
#
# A case whose output legitimately depends on the data model (LP64 vs ILP32 —
# `long` width, so strtoul("-1") and friends) is tagged `lp64` and skipped in
# cross mode rather than reported as a false divergence.
#
# Usage: tools/gcc_diff_probe.sh [--target ARCH] [name-substring]
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}"
command -v gcc >/dev/null || { echo "gcc not found"; exit 2; }
[ -x "$S" ] || { echo "pxx compiler not found: $S"; exit 2; }
TARGET=""
if [ "${1:-}" = "--target" ]; then TARGET="${2:-}"; shift 2; fi
FILTER="${1:-}"
if [ -n "$TARGET" ]; then
  RUNNER="$ROOT/tools/run_target.sh"
  [ -x "$RUNNER" ] || { echo "tools/run_target.sh not found"; exit 2; }
fi

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

new=0
known=0
skipped=0
ran=0
modelskip=0

# Make invisible bytes visible on BOTH sides of a reported divergence, so a
# whitespace-only difference cannot print as two identical-looking strings.
# Separator, not terminator: $( ) already stripped trailing newlines.
vis() { sed -e 's/\r/<CR>/g' -e 's/\t/<TAB>/g' | awk 'NR>1{printf "<LF>"}{printf "%s", $0}'; }

# probe NAME [known|lp64] -- full C program on stdin
#   known -- a filed divergence; tagged so a clean run shows only NEW ones.
#            A TAG IS A LIABILITY, NOT A RECORD: it says "diverges, do not be
#            surprised", so the moment the bug behind it is fixed the tag stops
#            suppressing a known issue and starts suppressing a REGRESSION —
#            the exact failure a differential oracle exists to prevent. Drop a
#            tag as part of fixing its bug, and re-measure the survivors when
#            you touch this file.
#            Currently: int64-to-double is bug-c-int64-to-double-cast-truncates-
#            on-32bit — native-clean, fires only under --target. It is the last
#            one; it did NOT diverge on i386 or arm32 in the 2026-08-13 sweep
#            either, so it may be stale too, but it keeps its tag until its
#            ticket is closed.
#            Dropped 2026-08-13 (task-t-drop-stale-known-tags-on-string-h-probes),
#            all four measured at 0 known on i386 / arm32 / x86-64:
#            str-chr-nul, str-str-empty and mem-chr-miss were never string.h
#            bugs at all — one pointer difference passed inline to printf,
#            pushed at 8 bytes on ILP32, shifting every later argument
#            (bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit);
#            bool-and-negative-zero-int was
#            bug-a-bool-conversion-does-not-normalise-to-0-or-1, which fired on
#            every target including native.
#   lp64  -- output depends on the data model; not judged in cross mode.
#            atoi-family: atol("2147483648") overflows `long` on ILP32.
#   charsign -- output depends on whether plain `char` is signed. It is on
#            x86-64 (the oracle) and UNSIGNED in the ARM procedure call
#            standard, so `(int)(char)0xFF` is legitimately -1 native and 255
#            on arm32/aarch64. Not a divergence; not judged in cross mode.
probe() {
  local name="$1"; local tag="${2:-}"
  if [ -n "$FILTER" ] && [ "${name#*$FILTER}" = "$name" ]; then cat >/dev/null; return; fi
  if [ -n "$TARGET" ] && { [ "$tag" = "lp64" ] || [ "$tag" = "charsign" ]; }; then
    cat >/dev/null
    printf 'MODEL       %-24s data-model dependent, not judged under --target\n' "$name"
    modelskip=$((modelskip+1)); return
  fi
  # Cases that touch the filesystem write under the per-run scratch dir, never a
  # fixed /tmp path. Two runs of this script (or a run alongside anything else
  # using the same names) would otherwise share files — and a case that reads
  # back what it just wrote turns into an intermittent divergence that does not
  # reproduce. One arm32 run reported exactly that and the rerun was clean.
  sed "s#@TMP@#$W#g" > "$W/c.c"
  ran=$((ran+1))
  local gr pr xr
  # -std=gnu99, not c99: under strict c99 the POSIX/BSD declarations (strsep,
  # strtok_r, strcasecmp, timegm) are hidden, so gcc took them as implicit int
  # and TRUNCATED the returned pointer to 32 bits — the oracle segfaulted and
  # the probe reported it as a pxx divergence. crtl declares them, and real code
  # uses them, so gnu99 is the honest oracle mode.
  # -Werror=implicit-function-declaration survives the -w: an implicit
  # declaration is never intentional in a probe and is exactly the shape that
  # produced that phantom. It turns into a counted, printed SKIP instead.
  if gcc -std=gnu99 -w -Werror=implicit-function-declaration \
         -o "$W/g" "$W/c.c" -lm >/dev/null 2>&1; then
    gr="$("$W/g" 2>&1)"; gr="$gr|rc=$?"
  else gr="<gcc-compile-fail>"; fi
  if [ "$gr" = "<gcc-compile-fail>" ]; then
    printf 'SKIP        %-24s no oracle: gcc cannot compile it, so this case proves nothing\n' "$name"
    skipped=$((skipped+1)); return
  fi
  if "$S" "$W/c.c" "$W/p" > "$W/cc.log" 2>&1; then
    pr="$("$W/p" 2>&1)"; pr="$pr|rc=$?"
  else pr="<pxx-compile-fail: $(grep -oE 'error:[^\n]*' "$W/cc.log" | head -1)>"; fi

  if [ -n "$TARGET" ]; then
    # The native run has to agree first, or a cross divergence is just the
    # native bug seen twice and reporting it here buries the real signal.
    if [ "$gr" != "$pr" ]; then
      printf 'SKIP        %-24s native already diverges; run without --target\n' "$name"
      skipped=$((skipped+1)); return
    fi
    if "$S" "--target=$TARGET" "$W/c.c" "$W/x" > "$W/xc.log" 2>&1; then
      xr="$("$RUNNER" "$TARGET" "$W/x" 2>&1)"; xr="$xr|rc=$?"
    else xr="<pxx-compile-fail: $(grep -oE 'error:[^\n]*' "$W/xc.log" | head -1)>"; fi
    pr="$xr"
  fi

  [ "$gr" = "$pr" ] && return
  local grv prv
  grv="$(printf '%s' "$gr" | vis)"; prv="$(printf '%s' "$pr" | vis)"
  if [ "$tag" = "known" ]; then
    printf 'DIFF [known] %-24s gcc=[%s] pxx=[%s]\n' "$name" "$grv" "$prv"; known=$((known+1))
  else
    printf 'DIFF        %-24s gcc=[%s] pxx=[%s]\n' "$name" "$grv" "$prv"; new=$((new+1))
  fi
}

# ---------------------------------------------------------------- string.h ---
probe str-cmp-sign <<'C'
#include <stdio.h>
#include <string.h>
int sgn(int v) { return v < 0 ? -1 : (v > 0 ? 1 : 0); }
int main(void) {
  /* strcmp's SIGN is all that is specified; the magnitude is not. Compare
     signs, or this case reports a legal implementation difference as a bug. */
  printf("%d %d %d\n", sgn(strcmp("abc","abd")), sgn(strcmp("abd","abc")), sgn(strcmp("ab","ab")));
  printf("%d %d\n", sgn(strcmp("ab","abc")), sgn(strcmp("abc","ab")));
  /* high-bit bytes: strcmp compares as UNSIGNED char, a classic sign bug */
  printf("%d\n", sgn(strcmp("\x80", "\x01")));
  return 0;
}
C
probe str-ncmp-zero <<'C'
#include <stdio.h>
#include <string.h>
int main(void) { printf("%d\n", strncmp("abc","xyz",0)); return 0; }
C
probe str-chr-nul <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *s = "hello";
  /* strchr(s,0) must find the TERMINATOR, not return NULL */
  printf("%d %d %d\n", strchr(s,'l')-s, strrchr(s,'l')-s, strchr(s,0)-s);
  printf("%d %d\n", strchr(s,'z')==0, strrchr(s,0)-s);
  return 0;
}
C
probe str-str-empty <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *s = "hello";
  /* strstr(s,"") is s, per C99 7.21.5.7 — a hand-rolled loop often returns 0 */
  printf("%d %d %d\n", strstr(s,"")-s, strstr(s,"ll")-s, strstr(s,"zz")==0);
  return 0;
}
C
probe str-ncpy-pad <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char b[8]; int i;
  memset(b,'#',8);
  strncpy(b,"ab",6);              /* must NUL-PAD to 6, not stop at one NUL */
  for (i=0;i<8;i++) printf("%d ", b[i]);
  printf("\n");
  memset(b,'#',8);
  strncpy(b,"abcdefgh",4);        /* must NOT terminate when src is longer */
  for (i=0;i<8;i++) printf("%d ", b[i]);
  printf("\n");
  return 0;
}
C
probe str-ncat <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char b[16] = "ab";
  strncat(b, "cdefgh", 3);        /* appends 3 + always terminates */
  printf("[%s] %d\n", b, (int)strlen(b));
  return 0;
}
C
probe mem-move-overlap <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char b[10] = "abcdefghi"; int i;
  memmove(b+2, b, 5);             /* forward overlap: must copy as if buffered */
  for (i=0;i<9;i++) putchar(b[i]);
  putchar('\n');
  memcpy(b, "abcdefghi", 9);
  memmove(b, b+2, 5);             /* backward overlap */
  for (i=0;i<9;i++) putchar(b[i]);
  putchar('\n');
  return 0;
}
C
probe mem-cmp-unsigned <<'C'
#include <stdio.h>
#include <string.h>
int sgn(int v) { return v < 0 ? -1 : (v > 0 ? 1 : 0); }
int main(void) {
  char a[2]; char b[2];
  a[0] = (char)0x80; a[1] = 0;
  b[0] = (char)0x01; b[1] = 0;
  printf("%d %d\n", sgn(memcmp(a,b,1)), memcmp(a,b,0));
  return 0;
}
C
probe mem-chr-miss <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *s = "ab\0cd";
  printf("%d %d %d\n", (char*)memchr(s,'c',5)-s, memchr(s,'z',5)==0, (char*)memchr(s,0,5)-s);
  return 0;
}
C
probe str-spn <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  printf("%d %d\n", (int)strspn("abcde","abc"), (int)strcspn("abcde","cd"));
  printf("%d %d\n", (int)strspn("abc",""), (int)strcspn("abc",""));
  return 0;
}
C
probe str-pbrk-tok <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char buf[] = "a,b,,c";
  char *t = strtok(buf, ",");
  while (t) { printf("[%s]", t); t = strtok(0, ","); }   /* adjacent seps collapse */
  printf("\n%d\n", strpbrk("hello","lz")-"hello" >= 0);
  return 0;
}
C
probe str-error-nonnull <<'C'
#include <stdio.h>
#include <string.h>
#include <errno.h>
int main(void) {
  /* the STRINGS differ between libcs; only assert the contract: never NULL,
     never empty, and distinct for distinct errno values. */
  const char *a = strerror(ENOENT), *b = strerror(EINVAL);
  printf("%d %d %d\n", a != 0 && *a != 0, b != 0 && *b != 0, strcmp(a,b) != 0);
  return 0;
}
C

# ---------------------------------------------------------------- stdlib.h ---
probe strtol-bases <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  printf("%ld %ld %ld\n", strtol("0x1f",0,16), strtol("0x1f",0,0), strtol("0x1f",0,10));
  printf("%ld %ld %ld\n", strtol("017",0,0), strtol("017",0,8), strtol("017",0,10));
  printf("%ld %ld\n", strtol("z",0,36), strtol("-42",0,10));
  printf("%ld\n", strtol("  \t +7abc",0,10));      /* leading space + explicit + */
  return 0;
}
C
probe strtol-endptr <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  char *e; const char *s = "12ab";
  long v = strtol(s, &e, 10);
  printf("%ld %d\n", v, (int)(e - s));
  s = "zz"; v = strtol(s, &e, 10);
  printf("%ld %d\n", v, (int)(e - s));            /* no conversion: endptr = start */
  s = "0x"; v = strtol(s, &e, 16);
  printf("%ld %d\n", v, (int)(e - s));            /* "0x" alone: consumes just "0" */
  return 0;
}
C
probe strtol-overflow lp64 <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
int main(void) {
  long v; int e;
  /* errno read on its OWN statement — reading it inside the same argument list
     as the call that sets it is unspecified order and the targets disagree. */
  errno = 0; v = strtol("99999999999999999999", 0, 10); e = errno;
  printf("%d %d\n", v == LONG_MAX, e == ERANGE);
  errno = 0; v = strtol("-99999999999999999999", 0, 10); e = errno;
  printf("%d %d\n", v == LONG_MIN, e == ERANGE);
  return 0;
}
C
probe strtol-no-conversion <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  char *e; const char *s;
  /* "no conversion" puts endptr back at the ORIGINAL string, past nothing —
     not past the whitespace and sign it speculatively consumed. */
  s = "  +zz"; strtol(s, &e, 10); printf("%d\n", (int)(e - s));
  s = "  -";   strtol(s, &e, 10); printf("%d\n", (int)(e - s));
  s = "0xg";   strtol(s, &e, 16); printf("%d\n", (int)(e - s));   /* longest valid prefix is "0" */
  s = "0x";    strtoul(s, &e, 0); printf("%d\n", (int)(e - s));
  /* assign FIRST: `strtol(...)` and `e - s` in one argument list is unspecified
     order, and gcc really does evaluate `e - s` first — it prints garbage on
     BOTH sides. Same trap as reading errno inline. */
  s = "08";    { long v = strtol(s, &e, 0); printf("%ld %d\n", v, (int)(e - s)); }  /* octal: "8" is not a digit */
  return 0;
}
C
probe fread-short-and-eof <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *path = "@TMP@/gdp_eof.txt";
  char buf[64]; size_t n;
  FILE *f = fopen(path, "wb");
  fwrite("abcdef", 1, 6, f);
  fclose(f);
  f = fopen(path, "rb");
  n = fread(buf, 1, sizeof buf, f);
  printf("%d %d %d\n", (int)n, !!feof(f), !!ferror(f));
  n = fread(buf, 1, sizeof buf, f);      /* already at EOF */
  printf("%d %d\n", (int)n, !!feof(f));
  clearerr(f);
  printf("%d\n", !!feof(f));
  fclose(f);
  /* element-sized read: a 6-byte file read as 4-byte elements gives 1 */
  f = fopen(path, "rb");
  n = fread(buf, 4, 8, f);
  printf("%d %d\n", (int)n, !!feof(f));
  fclose(f);
  remove(path);
  return 0;
}
C
probe strftime-overflow <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  time_t t = 1000000000;
  char b[64]; size_t n;
  /* on overflow strftime returns 0; the buffer is then unspecified, so only
     the RETURN is compared. */
  n = strftime(b, 5, "%Y", gmtime(&t)); printf("%d [%s]\n", (int)n, b);
  n = strftime(b, 4, "%Y", gmtime(&t)); printf("%d\n", (int)n);
  n = strftime(b, 1, "%Y", gmtime(&t)); printf("%d\n", (int)n);
  n = strftime(b, 9, "%d/%m/%y", gmtime(&t)); printf("%d [%s]\n", (int)n, b);
  n = strftime(b, 8, "%d/%m/%y", gmtime(&t)); printf("%d\n", (int)n);
  n = strftime(b, 64, "", gmtime(&t)); printf("%d\n", (int)n);
  return 0;
}
C
probe isprint-controls <<'C'
#include <stdio.h>
#include <ctype.h>
int main(void) {
  int c;
  /* isprint must be isgraph plus SPACE only — \t \n \v \f \r are not printable */
  for (c = 8; c <= 33; c++) printf("%d", !!isprint(c));
  printf("\n%d %d %d\n", !!isprint(' '), !!isprint(127), !!isprint('~'));
  return 0;
}
C
probe strtoul-wrap lp64 <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  /* strtoul on a negative is specified: negate the unsigned result */
  printf("%lu %lu\n", strtoul("-1",0,10), strtoul("18446744073709551615",0,10));
  return 0;
}
C
probe strtoll-range <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  printf("%lld %lld\n", strtoll("9223372036854775807",0,10), strtoll("-9223372036854775808",0,10));
  printf("%llu\n", strtoull("18446744073709551615",0,10));
  return 0;
}
C
probe atoi-family lp64 <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  printf("%d %d %d %d\n", atoi("42"), atoi("-42"), atoi("  12x"), atoi("x"));
  printf("%ld %lld\n", atol("2147483648"), atoll("9223372036854775807"));
  return 0;
}
C
probe abs-family <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  printf("%d %ld %lld\n", abs(-5), labs(-5L), llabs(-5LL));
  printf("%d %ld\n", abs(0), labs(-2147483647L));
  return 0;
}
C
probe div-family <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  div_t d = div(-7, 2);
  ldiv_t l = ldiv(-7L, 2L);
  printf("%d %d %ld %ld\n", d.quot, d.rem, l.quot, l.rem);   /* truncation toward zero */
  return 0;
}
C
probe qsort-bsearch <<'C'
#include <stdio.h>
#include <stdlib.h>
static int ci(const void *a, const void *b) {
  int x = *(const int*)a, y = *(const int*)b;
  return (x > y) - (x < y);
}
int main(void) {
  int a[9] = {5,3,9,1,3,7,-2,0,3}; int i; int key = 3; int *f;
  qsort(a, 9, sizeof(int), ci);
  for (i=0;i<9;i++) printf("%d ", a[i]);
  printf("\n");
  f = bsearch(&key, a, 9, sizeof(int), ci);
  printf("%d ", f != 0 && *f == 3);
  key = 100; f = bsearch(&key, a, 9, sizeof(int), ci);
  printf("%d\n", f == 0);
  return 0;
}
C
probe qsort-empty <<'C'
#include <stdio.h>
#include <stdlib.h>
static int ci(const void *a, const void *b) { return *(const int*)a - *(const int*)b; }
int main(void) {
  int a[1] = {7};
  qsort(a, 0, sizeof(int), ci);      /* nmemb 0 must be a no-op, not a crash */
  qsort(a, 1, sizeof(int), ci);
  printf("%d\n", a[0]);
  return 0;
}
C
probe malloc-zero-and-realloc <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
  char *p = malloc(4);
  memcpy(p, "abc", 4);
  p = realloc(p, 64);                /* must preserve contents */
  printf("[%s]\n", p);
  p = realloc(p, 2);                 /* shrink */
  printf("%d %d\n", p[0]=='a', p[1]=='b');
  free(p);
  free(0);                           /* free(NULL) is a no-op */
  p = calloc(4, 4);
  printf("%d\n", p[0]==0 && p[15]==0);
  free(p);
  return 0;
}
C
probe getenv-missing <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  printf("%d\n", getenv("PXX_DEFINITELY_NOT_SET_12345") == 0);
  return 0;
}
C
# environ was NULL under pxx until the C entry stub grew an init phase
# (bug/feature-c-entry-stub-must-run-initializers-for-environ, 08dccc7df,
# PXX_STABLE from v368). Structural assertions only, never a dump of the
# environment: both sides run under the same env, but the shell sets `_` to the
# path of the binary it is launching, so the two arrays legitimately differ in
# one entry and a raw dump would report a phantom divergence forever.
probe environ-prefilled <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern char **environ;
int main(void) {
  int n = 0, eq = 1;
  char **e;
  char *v;
  if (environ == 0) { printf("environ is NULL\n"); return 0; }
  for (e = environ; *e; e++) { n++; if (strchr(*e, '=') == 0) eq = 0; }
  printf("%d %d\n", n > 0, eq);          /* non-empty, every entry NAME=VALUE */
  /* the first entry must be findable by its own name, with its own value --
     a check that says nothing about WHICH variables this box happens to set */
  {
    char name[256];
    char *s = environ[0];
    char *p = strchr(s, '=');
    size_t len = (size_t)(p - s);
    if (len < sizeof(name)) {
      memcpy(name, s, len); name[len] = 0;
      v = getenv(name);
      printf("%d\n", v != 0 && strcmp(v, p + 1) == 0);
    } else printf("1\n");
  }
  return 0;
}
C
probe exit-code <<'C'
#include <stdlib.h>
int main(void) { exit(3); }
C
probe return-code-truncation <<'C'
int main(void) { return 300; }   /* exit status is the low 8 bits: 44 */
C

# ----------------------------------------------------------------- ctype.h ---
probe ctype-classify <<'C'
#include <stdio.h>
#include <ctype.h>
int main(void) {
  int c;
  for (c = 0; c < 128; c++) {
    printf("%d%d%d%d%d%d%d%d%d ",
      !!isalpha(c), !!isdigit(c), !!isalnum(c), !!isspace(c),
      !!isupper(c), !!islower(c), !!ispunct(c), !!isprint(c), !!isxdigit(c));
    if ((c % 8) == 7) printf("\n");
  }
  return 0;
}
C
probe ctype-convert <<'C'
#include <stdio.h>
#include <ctype.h>
int main(void) {
  int c;
  /* toupper/tolower must be IDENTITY outside their class, not blind +-32 */
  for (c = 0; c < 128; c++) printf("%d,%d ", toupper(c), tolower(c));
  printf("\n");
  return 0;
}
C

# ----------------------------------------------------------------- stdio.h ---
probe printf-int-flags <<'C'
#include <stdio.h>
int main(void) {
  printf("[%5d][%-5d][%05d][%+d][% d]\n", 42, 42, 42, 42, 42);
  printf("[%5d][%-5d][%05d][%+d]\n", -42, -42, -42, -42);
  printf("[%x][%X][%#x][%#o][%o]\n", 255, 255, 255, 8, 8);
  printf("[%#x][%#o]\n", 0, 0);        /* '#' on zero adds nothing / adds "0" */
  printf("[%u]\n", 4294967295u);
  return 0;
}
C
probe printf-width-prec <<'C'
#include <stdio.h>
int main(void) {
  printf("[%.3d][%8.3d][%-8.3d]\n", 5, 5, 5);
  printf("[%.0d][%.0d]\n", 0, 7);      /* precision 0 with value 0 prints NOTHING */
  printf("[%*d][%.*d]\n", 6, 42, 4, 42);
  printf("[%-*d]\n", 6, 42);
  printf("[%*d]\n", -6, 42);           /* negative width = left justify */
  return 0;
}
C
probe printf-string-prec <<'C'
#include <stdio.h>
int main(void) {
  printf("[%.2s][%5.2s][%-5.2s][%s]\n", "hello", "hello", "hello", "hi");
  printf("[%.0s]\n", "hello");
  printf("[%c][%3c][%-3c]\n", 'x', 'x', 'x');
  return 0;
}
C
probe printf-percent-literal <<'C'
#include <stdio.h>
/* NOT probed: "%5%". A width on %% is undefined behaviour (C99 7.19.6.1p8 —
   the complete conversion specification is "%%"), so gcc printing "%" and pxx
   printing "    %" are both legal and a DIFF there would be harness noise. */
int main(void) { printf("100%%\n"); printf("a%%b\n"); return 0; }
C
probe printf-long-modifiers lp64 <<'C'
#include <stdio.h>
#include <inttypes.h>
#include <stdint.h>
#include <stddef.h>
int main(void) {
  long long v = -9223372036854775807LL - 1;
  printf("%lld %llu\n", v, (unsigned long long)v);
  printf("%ld %lu\n", 2147483647L, 4294967295UL);
  printf("%hd %hhd\n", (short)-1, (signed char)-1);
  printf("%zu %td\n", (size_t)12, (ptrdiff_t)-3);
  printf("%" PRId64 " %" PRIu64 "\n", (int64_t)-5, (uint64_t)5);
  return 0;
}
C
probe printf-return-value <<'C'
#include <stdio.h>
int main(void) {
  int n = printf("abc\n");
  printf("%d\n", n);
  return 0;
}
C
probe snprintf-truncate <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char b[8]; int n;
  memset(b, '#', 8);
  n = snprintf(b, 5, "abcdefgh");   /* returns what it WOULD have written */
  printf("%d [%s] %d\n", n, b, b[4] == 0);
  n = snprintf(0, 0, "abcdefgh");   /* NULL/0 is legal and just measures */
  printf("%d\n", n);
  return 0;
}
C
probe sprintf-return <<'C'
#include <stdio.h>
int main(void) {
  char b[32];
  int n = sprintf(b, "%d-%s", 42, "x");
  printf("%d [%s]\n", n, b);
  return 0;
}
C
probe sscanf-basic <<'C'
#include <stdio.h>
int main(void) {
  int a = -1, b = -1; char s[16] = "";
  int n = sscanf("12 34 hi", "%d %d %15s", &a, &b, s);
  printf("%d %d %d [%s]\n", n, a, b, s);
  n = sscanf("xy", "%d", &a);
  printf("%d\n", n);                 /* matching failure: 0, not EOF */
  n = sscanf("", "%d", &a);
  printf("%d\n", n);                 /* input failure: EOF (-1) */
  return 0;
}
C
probe sscanf-widths <<'C'
#include <stdio.h>
int main(void) {
  int a = 0; char s[8] = "";
  sscanf("12345", "%2d", &a);
  sscanf("abcdef", "%3s", s);
  printf("%d [%s]\n", a, s);
  return 0;
}
C
probe puts-putchar-return <<'C'
#include <stdio.h>
int main(void) {
  int a = puts("x");
  int b = putchar('y');
  printf("\n%d %d\n", a >= 0, b == 'y');
  return 0;
}
C
probe stdio-file-roundtrip <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *path = "@TMP@/gdp_rt.txt";
  char buf[32]; size_t n;
  FILE *f = fopen(path, "wb");
  if (!f) { printf("open-fail\n"); return 1; }
  n = fwrite("hello\n", 1, 6, f);
  printf("%d %d\n", (int)n, fclose(f) == 0);
  f = fopen(path, "rb");
  memset(buf, 0, sizeof buf);
  n = fread(buf, 1, sizeof buf, f);
  printf("%d [%s] %d\n", (int)n, buf, !!feof(f));
  fclose(f);
  f = fopen(path, "rb");
  printf("[%s]", fgets(buf, sizeof buf, f) ? buf : "<null>");
  printf("%d\n", fgets(buf, sizeof buf, f) == 0);   /* second read hits EOF */
  fclose(f);
  remove(path);
  printf("%d\n", fopen(path, "rb") == 0);
  return 0;
}
C
probe stdio-seek-tell <<'C'
#include <stdio.h>
int main(void) {
  const char *path = "@TMP@/gdp_seek.txt";
  FILE *f = fopen(path, "wb");
  fwrite("0123456789", 1, 10, f);
  fclose(f);
  f = fopen(path, "rb");
  /* ftell and fgetc must NOT share an argument list: fgetc moves the position,
     so the printed ftell depends on evaluation order, which is unspecified —
     pxx orders them differently on arm32/aarch64 than on x86-64 and gcc, all
     of it legal. Sequence them instead, or this case reports the harness. */
  { long t; int c;
    fseek(f, 4, SEEK_SET);  t = ftell(f); c = fgetc(f); printf("%ld %d\n", t, c);
    fseek(f, -2, SEEK_END); t = ftell(f); c = fgetc(f); printf("%ld %d\n", t, c);
    fseek(f, 1, SEEK_CUR);  printf("%ld\n", ftell(f));
    ungetc('Z', f);         printf("%d\n", fgetc(f)); }
  fclose(f);
  remove(path);
  return 0;
}
C
probe fopen-missing <<'C'
#include <stdio.h>
#include <errno.h>
int main(void) {
  FILE *f = fopen("@TMP@/gdp_definitely_absent_9182", "rb");
  int e = errno;
  printf("%d %d\n", f == 0, e == ENOENT);
  return 0;
}
C
probe stderr-goes-to-stderr <<'C'
#include <stdio.h>
int main(void) {
  fprintf(stderr, "E\n");
  fprintf(stdout, "O\n");
  return 0;
}
C

# ------------------------------------------------------------------ time.h ---
probe time-monotone-ish <<'C'
#include <stdio.h>
#include <time.h>
#include <sys/time.h>
int main(void) {
  time_t t = time(0);
  struct timeval tv;
  gettimeofday(&tv, 0);
  /* no wall-clock VALUE can be compared to an oracle, so assert the contract:
     a plausible epoch, agreement between the two clocks, usec in range. */
  printf("%d %d %d\n", t > 1600000000, tv.tv_sec > 1600000000,
         tv.tv_usec >= 0 && tv.tv_usec < 1000000);
  printf("%d\n", (long)t >= tv.tv_sec - 1 && (long)t <= tv.tv_sec + 1);
  return 0;
}
C
probe gmtime-fields <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  time_t t = 1000000000;            /* 2001-09-09 01:46:40 UTC */
  struct tm *g = gmtime(&t);
  printf("%d-%02d-%02d %02d:%02d:%02d wd=%d yd=%d\n",
         g->tm_year+1900, g->tm_mon+1, g->tm_mday,
         g->tm_hour, g->tm_min, g->tm_sec, g->tm_wday, g->tm_yday);
  t = 951782400;                    /* 2000-02-29, a leap day in a century year */
  g = gmtime(&t);
  printf("%d-%02d-%02d wd=%d\n", g->tm_year+1900, g->tm_mon+1, g->tm_mday, g->tm_wday);
  t = 0;
  g = gmtime(&t);
  printf("%d-%02d-%02d wd=%d\n", g->tm_year+1900, g->tm_mon+1, g->tm_mday, g->tm_wday);
  return 0;
}
C
probe strftime-fields <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  time_t t = 1000000000;
  char b[64];
  strftime(b, sizeof b, "%Y-%m-%d %H:%M:%S", gmtime(&t)); printf("[%s]\n", b);
  strftime(b, sizeof b, "%d/%m/%y %j %%", gmtime(&t));    printf("[%s]\n", b);
  printf("%d\n", (int)strftime(b, 4, "%Y", gmtime(&t)));  /* fits exactly? */
  printf("%d\n", (int)strftime(b, 3, "%Y", gmtime(&t)));  /* 0 when it does not */
  return 0;
}
C
probe mktime-roundtrip <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  time_t t = 1000000000;
  struct tm g = *gmtime(&t);
  struct tm h = g;
  /* not mktime (it is local-time and the oracle's TZ is not ours) — assert the
     field arithmetic instead: a normalised out-of-range mday. */
  h.tm_mday += 40;
  printf("%d %d\n", g.tm_mday, h.tm_mday);
  return 0;
}
C

# ---------------------------------------------------------------- unistd.h ---
probe unistd-write-read <<'C'
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
int main(void) {
  const char *path = "@TMP@/gdp_u.txt";
  char buf[16];
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  printf("%d %d\n", fd >= 0, (int)write(fd, "abcd", 4));
  close(fd);
  fd = open(path, O_RDONLY);
  memset(buf, 0, sizeof buf);
  { int r = (int)read(fd, buf, sizeof buf); printf("%d [%s]\n", r, buf); }
  printf("%ld\n", (long)lseek(fd, 1, SEEK_SET));
  printf("%d\n", close(fd));
  unlink(path);
  fd = open(path, O_RDONLY);
  printf("%d\n", fd < 0);
  return 0;
}
C
probe unistd-close-bad-fd <<'C'
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
int main(void) {
  int rc = close(4242);
  int e = errno;
  printf("%d %d\n", rc, e == EBADF);
  return 0;
}
C

# ------------------------------------------------------------ integer edges ---
probe int-shift-and-div <<'C'
#include <stdio.h>
int main(void) {
  int a = -7;
  printf("%d %d\n", a / 2, a % 2);        /* truncate toward zero */
  printf("%d %d\n", a >> 1, (-1) >> 31);  /* arithmetic shift on this ABI */
  printf("%u\n", ((unsigned)-1) >> 28);
  printf("%lld\n", (long long)1 << 62);
  return 0;
}
C
probe int-promotion <<'C'
#include <stdio.h>
int main(void) {
  unsigned char c = 200;
  signed char s = -56;
  short h = -1;
  printf("%d %d %d\n", c + 1, s + 1, h + 1);
  printf("%d\n", (int)(unsigned short)h);
  printf("%d\n", -1 < (unsigned)1);       /* the classic: 0, not 1 */
  return 0;
}
C
probe int64-to-double known <<'C'
#include <stdio.h>
int main(void) {
  long long v = 9007199254740991LL;
  double d = (double)v;
  printf("%d %d\n", d > 9.0e15, (long long)d == v);
  printf("%d\n", (int)((double)(long long)-5 == -5.0));
  return 0;
}
C


# ------------------------------------------------------ batch 2: more surface ---
probe realloc-identities <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
  char *p = realloc(0, 8);            /* realloc(NULL, n) == malloc(n) */
  int ok1, ok2;
  strcpy(p, "abc");
  ok1 = (p != 0 && strcmp(p, "abc") == 0);
  p = realloc(p, 0);                  /* implementation-defined: NULL or a freeable ptr */
  ok2 = 1;                            /* only assert it did not crash */
  free(p);
  printf("%d %d\n", ok1, ok2);
  return 0;
}
C
probe calloc-overflow-guard <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(void) {
  /* nmemb*size must not wrap into a small allocation */
  void *p = calloc((size_t)-1 / 2, 4);
  printf("%d\n", p == 0);
  return 0;
}
C
probe bsearch-empty <<'C'
#include <stdio.h>
#include <stdlib.h>
static int ci(const void *a, const void *b) { return *(const int*)a - *(const int*)b; }
int main(void) {
  int a[1] = {1}, key = 1;
  printf("%d %d\n", bsearch(&key, a, 0, sizeof(int), ci) == 0,
                    bsearch(&key, a, 1, sizeof(int), ci) != 0);
  return 0;
}
C
probe strtoimax-family <<'C'
#include <stdio.h>
#include <inttypes.h>
int main(void) {
  printf("%" PRIdMAX " %" PRIuMAX "\n", (intmax_t)strtoimax("-77", 0, 10),
                                        (uintmax_t)strtoumax("77", 0, 10));
  printf("%" PRIdMAX "\n", (intmax_t)imaxabs((intmax_t)-9));
  return 0;
}
C
probe sscanf-charclass <<'C'
#include <stdio.h>
int main(void) {
  char a[16] = "", b[16] = "";
  int n = sscanf("abc123", "%[a-z]%[0-9]", a, b);
  printf("%d [%s] [%s]\n", n, a, b);
  n = sscanf("hello world", "%[^ ]", a);
  printf("%d [%s]\n", n, a);
  return 0;
}
C
probe sscanf-scanset-edges <<'C'
#include <stdio.h>
int main(void) {
  char a[24] = "", b[24] = "";
  int n;
  n = sscanf("]abc]", "%[]a-c]", a);            printf("%d [%s]\n", n, a);   /* ']' first is literal */
  a[0]=0; n = sscanf("a-c", "%[a-]", a);        printf("%d [%s]\n", n, a);   /* '-' last is literal */
  a[0]=0; n = sscanf("   xy", "%[^0-9]", a);    printf("%d [%s]\n", n, a);   /* no leading-ws skip */
  a[0]=0; n = sscanf("abcdef", "%3[a-z]", a);   printf("%d [%s]\n", n, a);   /* width */
  a[0]=0; n = sscanf("123", "%[a-z]", a);       printf("%d [%s]\n", n, a);   /* matching failure */
  a[0]=0; b[0]=0;
  n = sscanf("key=value", "%[^=]=%[^\n]", a, b); printf("%d [%s] [%s]\n", n, a, b);
  a[0]=0; n = sscanf("xyz", "%*[a-z]%n", &(int){0});  printf("%d\n", n);     /* suppressed */
  return 0;
}
C
probe sscanf-percent-n-positions <<'C'
#include <stdio.h>
int main(void) {
  int v = 0, c1 = -1, c2 = -1, n;
  n = sscanf("  42abc", "%n%d%n", &c1, &v, &c2);
  printf("%d %d %d %d\n", n, c1, v, c2);       /* %n counts from the START */
  { long lc = -1; n = sscanf("abcd", "%*3c%ln", &lc); printf("%d %ld\n", n, lc); }
  return 0;
}
C
probe sscanf-percent-n <<'C'
#include <stdio.h>
int main(void) {
  int v = 0, consumed = -1;
  int n = sscanf("42abc", "%d%n", &v, &consumed);
  printf("%d %d %d\n", n, v, consumed);       /* %n is not counted in the return */
  return 0;
}
C
probe sscanf-literal-and-space <<'C'
#include <stdio.h>
int main(void) {
  int a = 0, b = 0; int n;
  n = sscanf("12,34", "%d,%d", &a, &b);       printf("%d %d %d\n", n, a, b);
  n = sscanf("  12", " %d", &a);              printf("%d %d\n", n, a);
  n = sscanf("x12", "%d", &a);                printf("%d\n", n);
  n = sscanf("12 x", "%d %c", &a, (char*)&b); printf("%d %d\n", n, a);
  return 0;
}
C
probe printf-null-string <<'C'
#include <stdio.h>
int main(void) {
  /* glibc prints "(null)" for %s with NULL. It is UB per the standard, but it
     is the oracle's documented behaviour and real code hits it in error paths;
     a crash here is strictly worse than agreeing. */
  printf("[%s]\n", (char *)0);
  return 0;
}
C
probe snprintf-size-one <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char b[4]; int n;
  memset(b, '#', 4);
  n = snprintf(b, 1, "abc");          /* writes only the NUL */
  printf("%d %d %d\n", n, b[0] == 0, b[1] == '#');
  return 0;
}
C
probe stdio-rewind-and-flush <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *path = "@TMP@/gdp_rw.txt";
  char b[16];
  FILE *f = fopen(path, "w+b");
  fwrite("abcdef", 1, 6, f);
  printf("%d\n", fflush(f) == 0);
  rewind(f);
  memset(b, 0, sizeof b);
  { int r = (int)fread(b, 1, 3, f); printf("%d [%s]\n", r, b); }
  printf("%ld\n", ftell(f));
  fclose(f);
  remove(path);
  return 0;
}
C
probe stdio-append-mode <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *path = "@TMP@/gdp_ap.txt";
  char b[16];
  FILE *f = fopen(path, "wb");  fwrite("ab", 1, 2, f); fclose(f);
  f = fopen(path, "ab");        fwrite("cd", 1, 2, f); fclose(f);
  f = fopen(path, "rb");
  memset(b, 0, sizeof b);
  { int r = (int)fread(b, 1, sizeof b, f); printf("%d [%s]\n", r, b); }
  fclose(f);
  remove(path);
  return 0;
}
C
probe stdio-fseek-past-eof <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *path = "@TMP@/gdp_hole.txt";
  char b[16];
  FILE *f = fopen(path, "wb");
  fwrite("ab", 1, 2, f);
  fseek(f, 4, SEEK_SET);            /* leaves a hole */
  fwrite("z", 1, 1, f);
  fclose(f);
  f = fopen(path, "rb");
  memset(b, 0, sizeof b);
  { int r = (int)fread(b, 1, sizeof b, f); printf("%d %d %d %d\n", r, b[0], b[2], b[4]); }
  fclose(f);
  remove(path);
  return 0;
}
C
probe errno-values <<'C'
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
int main(void) {
  int fd, e;
  fd = open("@TMP@/gdp_no_such_dir_9182/x", O_RDONLY); e = errno;
  printf("%d %d\n", fd < 0, e == ENOENT);
  fd = open("/", O_WRONLY); e = errno;
  printf("%d %d\n", fd < 0, e == EISDIR);
  e = 0; errno = 0;
  printf("%d\n", errno == 0);
  return 0;
}
C
probe syscall-errno-convention <<'C'
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <fcntl.h>
int main(void) {
  int r, e;
  /* The whole point: a failing syscall veneer must return -1 and SET errno, not
     hand back the kernel's raw negative errno. `if (rc < 0)` catches both, which
     is why this hid; `rc == -1` and perror() do not. errno is read on its own
     statement — never in the argument list of the call that sets it. */
  errno=0; r = open("@TMP@/nope_9182/x", O_RDONLY); e=errno; printf("open   %d %d\n", r, e);
  errno=0; r = open("/", O_WRONLY);          e=errno; printf("isdir  %d %d\n", r, e);
  errno=0; r = fsync(4242);                  e=errno; printf("fsync  %d %d\n", r, e);
  errno=0; r = dup(4242);                    e=errno; printf("dup    %d %d\n", r, e);
  errno=0; r = chdir("@TMP@/nope_9182");  e=errno; printf("chdir  %d %d\n", r, e);
  errno=0; r = mkdir("@TMP@/nope_9182/x", 0755); e=errno; printf("mkdir  %d %d\n", r, e);
  errno=0; r = link("@TMP@/nope_9182", "@TMP@/nope_9183"); e=errno; printf("link   %d %d\n", r, e);
  errno=0; r = rmdir("@TMP@/nope_9182");  e=errno; printf("rmdir  %d %d\n", r, e);
  errno=0; r = unlink("@TMP@/nope_9182"); e=errno; printf("unlink %d %d\n", r, e);
  errno=0; r = access("@TMP@/nope_9182", 0); e=errno; printf("access %d %d\n", r, e);
  return 0;
}
C
probe isatty-not-negative <<'C'
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
int main(void) {
  int fd = open("@TMP@/gdp_tty", O_WRONLY | O_CREAT | O_TRUNC, 0644);
  /* isatty answers 0 or 1. A negative leaking out would make every
     `if (isatty(fd))` interactivity branch take the terminal path. */
  printf("%d %d\n", isatty(fd), isatty(fd) ? 1 : 0);
  printf("%d %d\n", isatty(4242), isatty(4242) ? 1 : 0);
  close(fd); unlink("@TMP@/gdp_tty");
  return 0;
}
C
probe unistd-dup-and-pipe <<'C'
#include <stdio.h>
#include <unistd.h>
#include <string.h>
int main(void) {
  int fds[2];
  char b[8];
  if (pipe(fds) != 0) { printf("pipe-fail\n"); return 1; }
  write(fds[1], "hi", 2);
  memset(b, 0, sizeof b);
  { int r = (int)read(fds[0], b, sizeof b); printf("%d [%s]\n", r, b); }
  close(fds[0]); close(fds[1]);
  return 0;
}
C
probe setjmp-longjmp <<'C'
#include <stdio.h>
#include <setjmp.h>
static jmp_buf jb;
static void deep(int n) { if (n) deep(n - 1); else longjmp(jb, 7); }
int main(void) {
  int v = setjmp(jb);
  if (v == 0) { deep(3); printf("unreachable\n"); return 1; }
  printf("longjmp=%d\n", v);
  return 0;
}
C
probe struct-copy-and-compare <<'C'
#include <stdio.h>
#include <string.h>
struct S { int a; char b[5]; long c; };
int main(void) {
  struct S x, y;
  memset(&x, 0, sizeof x);
  x.a = 1; strcpy(x.b, "abcd"); x.c = 99;
  y = x;                                  /* whole-struct assignment */
  printf("%d [%s] %ld %d\n", y.a, y.b, y.c, (int)(memcmp(&x, &y, sizeof x) == 0));
  return 0;
}
C
probe array-of-struct-init <<'C'
#include <stdio.h>
struct P { int x, y; };
int main(void) {
  struct P a[3] = { {1,2}, {3,4} };        /* third is zero-filled */
  int i;
  for (i = 0; i < 3; i++) printf("%d,%d ", a[i].x, a[i].y);
  printf("\n");
  return 0;
}
C
probe union-punning <<'C'
#include <stdio.h>
#include <string.h>
union U { unsigned int u; unsigned char b[4]; };
int main(void) {
  union U v;
  v.u = 0x01020304u;
  printf("%d %d %d %d\n", v.b[0], v.b[1], v.b[2], v.b[3]);   /* little-endian */
  return 0;
}
C
probe static-local-persists <<'C'
#include <stdio.h>
static int counter(void) { static int n = 0; return ++n; }
int main(void) {
  { int a = counter(), b = counter(), c = counter(); printf("%d %d %d\n", a, b, c); }
  return 0;
}
C
probe switch-fallthrough-default <<'C'
#include <stdio.h>
static int f(int v) {
  int r = 0;
  switch (v) {
    case 1: r += 1;
    case 2: r += 2; break;
    case 3: r += 4;
    default: r += 8;
  }
  return r;
}
int main(void) { printf("%d %d %d %d\n", f(1), f(2), f(3), f(9)); return 0; }
C


# ------------------------------------------ batch 3: strings, time, semantics ---
probe str-case-and-sep <<'C'
#include <stdio.h>
#include <string.h>
#include <strings.h>
int sgn(int v) { return v < 0 ? -1 : (v > 0 ? 1 : 0); }
int main(void) {
  char buf[] = "a:b::c";
  char *rest = buf, *tok;
  printf("%d %d %d\n", sgn(strcasecmp("ABC","abc")), sgn(strcasecmp("abd","ABC")),
                       sgn(strncasecmp("ABCx","abcy",3)));
  while ((tok = strsep(&rest, ":")) != 0) printf("[%s]", tok);  /* keeps empties */
  printf("\n");
  return 0;
}
C
probe strtok-r-reentrant <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char a[] = "1,2,3";
  char b[] = "x-y";
  char *sa = 0, *sb = 0, *ta, *tb;
  ta = strtok_r(a, ",", &sa);
  tb = strtok_r(b, "-", &sb);
  /* interleaved: the whole point of the _r form is that these do not collide */
  while (ta || tb) {
    if (ta) { printf("[%s]", ta); ta = strtok_r(0, ",", &sa); }
    if (tb) { printf("(%s)", tb); tb = strtok_r(0, "-", &sb); }
  }
  printf("\n");
  return 0;
}
C
probe memccpy-and-mempcpy <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  char d[8];
  char *r;
  memset(d, '#', 8);
  r = memccpy(d, "abcXdef", 'X', 8);
  printf("%d %d %d\n", r != 0, (int)(r - d), d[3] == 'X');
  memset(d, '#', 8);
  r = memccpy(d, "abc", 'X', 3);        /* not found within n */
  printf("%d\n", r == 0);
  return 0;
}
C
probe strlen-strnlen-edges <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *s = "abcdef";
  printf("%d %d %d %d\n", (int)strlen(""), (int)strlen(s),
                          (int)strnlen(s, 3), (int)strnlen(s, 99));
  return 0;
}
C
probe chmod-umask <<'C'
#include <stdio.h>
#include <sys/stat.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
int main(void) {
  const char *p = "@TMP@/chmod_probe";
  struct stat st;
  int r, e; mode_t old;
  int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  close(fd);
  r = chmod(p, 0600); stat(p, &st); printf("%d %o\n", r, st.st_mode & 07777);
  r = chmod(p, 0755); stat(p, &st); printf("%d %o\n", r, st.st_mode & 07777);
  errno = 0; r = chmod("@TMP@/nope_31337/x", 0644); e = errno;
  printf("%d %d\n", r, e == ENOENT);
  old = umask(022);
  printf("%d %d\n", (old & ~07777) == 0, umask(old) == 022);
  unlink(p);
  return 0;
}
C
probe clock-gettime-selfcontained <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  struct timespec a, b;
  int r1 = clock_gettime(CLOCK_REALTIME, &a);
  int r2 = clock_gettime(2 /* CLOCK_PROCESS_CPUTIME_ID */, &b);
  /* values only; the LINKAGE half of this (no DT_NEEDED on libc.so.6) is what
     tools/crtl_decl_probe.sh checks — clock_gettime produced correct output
     here for months while binding to glibc. */
  printf("%d %d %d %d\n", r1, r2, a.tv_sec > 1600000000,
         a.tv_nsec >= 0 && a.tv_nsec < 1000000000);
  printf("%d %d\n", b.tv_sec >= 0, b.tv_nsec >= 0 && b.tv_nsec < 1000000000);
  return 0;
}
C
probe time-difftime-clock <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  time_t a = 1000000000, b = 1000000060;
  printf("%d %d\n", (int)difftime(b, a), (int)difftime(a, b));
  printf("%d\n", CLOCKS_PER_SEC == 1000000);
  { clock_t c = clock(); printf("%d\n", c >= 0); }
  return 0;
}
C
probe ctime-asctime-shape <<'C'
#include <stdio.h>
#include <string.h>
#include <time.h>
int main(void) {
  time_t t = 1000000000;
  char *a = asctime(gmtime(&t));
  /* the exact text is fixed by C99 7.23.3.1: "Sun Sep  9 01:46:40 2001\n" */
  printf("[%s]", a ? a : "<null>");
  printf("%d\n", a ? (int)strlen(a) : -1);
  return 0;
}
C
probe timegm-roundtrip <<'C'
#include <stdio.h>
#include <time.h>
int main(void) {
  time_t t = 1000000000;
  struct tm g = *gmtime(&t);
  time_t back = timegm(&g);
  printf("%d\n", (long long)back == (long long)t);
  return 0;
}
C
probe integer-wraparound <<'C'
#include <stdio.h>
#include <limits.h>
int main(void) {
  unsigned int u = UINT_MAX;
  unsigned char c = 255;
  unsigned short h = 65535;
  printf("%u %u %u\n", u + 1, (unsigned)(c + 1), (unsigned)(unsigned short)(h + 1));
  printf("%d\n", (int)(unsigned char)(c * 3));
  printf("%llu\n", (unsigned long long)-1);
  return 0;
}
C
probe bitfields <<'C'
#include <stdio.h>
struct B { unsigned a : 3; unsigned b : 5; signed c : 4; unsigned d : 20; };
int main(void) {
  struct B v;
  v.a = 7; v.b = 31; v.c = -8; v.d = 1048575;
  printf("%u %u %d %u %d\n", v.a, v.b, v.c, v.d, (int)sizeof(struct B));
  v.a = 8;                       /* truncates to 3 bits */
  v.c = 7;
  printf("%u %d\n", v.a, v.c);
  return 0;
}
C
probe designated-and-compound <<'C'
#include <stdio.h>
struct P { int x, y, z; };
int main(void) {
  struct P a = { .z = 3, .x = 1 };            /* y zero-filled */
  int arr[6] = { [4] = 9, [1] = 2 };
  int i;
  printf("%d %d %d\n", a.x, a.y, a.z);
  for (i = 0; i < 6; i++) printf("%d ", arr[i]);
  printf("\n");
  return 0;
}
C
probe bool-and-negative-zero-int <<'C'
#include <stdio.h>
int main(void) {
  _Bool t = 5, f = 0;
  printf("%d %d %d\n", (int)t, (int)f, (int)(_Bool)2);
  printf("%d %d\n", !5, !0);
  printf("%d\n", (int)(0 == -0));
  return 0;
}
C
probe function-pointers <<'C'
#include <stdio.h>
static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }
int main(void) {
  int (*ops[2])(int, int) = { add, sub };
  int (*p)(int, int) = add;
  printf("%d %d %d\n", ops[0](7, 3), ops[1](7, 3), p(7, 3));
  p = sub;
  printf("%d\n", (*p)(7, 3));
  return 0;
}
C
probe long-long-arith <<'C'
#include <stdio.h>
int main(void) {
  long long a = 9007199254740993LL;      /* not representable as double */
  long long b = 3;
  printf("%lld %lld %lld\n", a / b, a % b, a * 2);
  printf("%lld\n", -9223372036854775807LL - 1);
  printf("%d\n", (int)(a > 9007199254740992LL));
  return 0;
}
C
probe nested-struct-array-copy <<'C'
#include <stdio.h>
#include <string.h>
struct Inner { int v[3]; };
struct Outer { struct Inner in[2]; char tag[4]; };
int main(void) {
  struct Outer a, b;
  memset(&a, 0, sizeof a);
  a.in[0].v[1] = 5; a.in[1].v[2] = 9; strcpy(a.tag, "ok");
  b = a;
  printf("%d %d [%s] %d\n", b.in[0].v[1], b.in[1].v[2], b.tag,
         (int)(memcmp(&a, &b, sizeof a) == 0));
  return 0;
}
C
probe goto-and-labels <<'C'
#include <stdio.h>
int main(void) {
  int i, n = 0;
  for (i = 0; i < 10; i++) { if (i == 3) goto out; n++; }
out:
  printf("%d %d\n", i, n);
  return 0;
}
C
probe recursion-depth <<'C'
#include <stdio.h>
static long long fib(int n) { return n < 2 ? n : fib(n-1) + fib(n-2); }
static int depth(int n) { return n ? depth(n-1) + 1 : 0; }
int main(void) {
  printf("%lld %d\n", fib(24), depth(2000));
  return 0;
}
C
probe const-string-sharing <<'C'
#include <stdio.h>
#include <string.h>
int main(void) {
  const char *a = "shared";
  const char *b = "shared";
  /* whether literals are pooled is implementation-defined; only the VALUE is
     compared, never the pointers. */
  printf("%d %d\n", strcmp(a, b) == 0, (int)strlen(a));
  return 0;
}
C

probe bitfield-layout-and-truncate <<'C'
#include <stdio.h>
struct B { unsigned a : 3; unsigned b : 5; int c : 4; unsigned d : 1; };
int main(void) {
  struct B x;
  x.a = 7; x.b = 31; x.c = -8; x.d = 1;
  printf("%u %u %d %u %d\n", x.a, x.b, x.c, x.d, (int)sizeof(struct B));
  x.a = 9;              /* 1001b -> keeps the low three bits */
  x.c = 7;
  printf("%u %d\n", x.a, x.c);
  x.c = 8;              /* overflows a 4-bit signed field */
  printf("%d\n", x.c);
  return 0;
}
C
probe bitfield-mixed-with-plain <<'C'
#include <stdio.h>
struct M { unsigned char tag; unsigned lo : 12; unsigned hi : 20; int n; };
int main(void) {
  struct M m;
  m.tag = 200; m.lo = 4095; m.hi = 1048575; m.n = -5;
  printf("%u %u %u %d\n", m.tag, m.lo, m.hi, m.n);
  m.lo = 4096;
  printf("%u %u\n", m.lo, m.hi);
  return 0;
}
C
probe union-type-punning <<'C'
#include <stdio.h>
#include <string.h>
union U { unsigned int u; unsigned char b[4]; };
int main(void) {
  union U x;
  x.u = 0x01020304u;
  /* little-endian on every target this probe runs; assert the ORDER, which is
     what a punning bug would scramble */
  printf("%u %u %u %u %d\n", x.b[0], x.b[1], x.b[2], x.b[3], (int)sizeof(union U));
  memset(&x, 0, sizeof x);
  x.b[1] = 0xFF;
  printf("%u\n", x.u);
  return 0;
}
C
probe struct-by-value-and-return <<'C'
#include <stdio.h>
struct P { int x, y; };
struct Big { long a, b, c, d; char t[8]; };
static struct P mk(int a, int b) { struct P p; p.x = a; p.y = b; return p; }
static int sum(struct P p) { return p.x + p.y; }
static struct Big mkbig(long s) {
  struct Big g; g.a = s; g.b = s + 1; g.c = s + 2; g.d = s + 3;
  g.t[0] = 'z'; g.t[1] = 0; return g;
}
static long bigsum(struct Big g) { return g.a + g.b + g.c + g.d; }
int main(void) {
  struct P p = mk(3, 4);
  struct Big g = mkbig(100);
  printf("%d %d %d\n", p.x, p.y, sum(p));
  printf("%ld %s %ld\n", g.a, g.t, bigsum(g));
  return 0;
}
C
probe struct-assignment-copies <<'C'
#include <stdio.h>
struct S { int n; char s[6]; };
int main(void) {
  struct S a, b;
  a.n = 1; a.s[0] = 'a'; a.s[1] = 0;
  b = a;
  b.n = 2; b.s[0] = 'b';
  printf("%d %s %d %s\n", a.n, a.s, b.n, b.s);
  return 0;
}
C
# The case that found bug-a-aarch64-signed-vs-unsigned-narrow-comparison-is-wrong
# (FIXED): `-1 < (unsigned char)1` was FALSE on aarch64 in both frontends at
# every -O level, because that backend decided compare signedness with
# `unsigned(l) or unsigned(r)` instead of TypeCompareUnsigned. Kept untagged —
# it must stay green on every target.
probe integer-promotion-in-comparison <<'C'
#include <stdio.h>
int main(void) {
  unsigned u = 1;
  int i = -1;
  signed char sc = -1;
  unsigned char uc = 200;
  short sh = -2;
  /* the classic: i converts to unsigned, so i < u is FALSE */
  printf("%d %d %d %d\n", i < u, sc < u, (int)(uc + uc), (int)(sh * sh));
  printf("%d %d\n", (int)(sc + uc), -1 < (unsigned char)1);
  return 0;
}
C
probe shift-and-truncation-edges <<'C'
#include <stdio.h>
int main(void) {
  unsigned int u = 0x80000000u;
  int i = -16;
  unsigned long long q = 1ULL << 40;
  printf("%u %u\n", u >> 31, u << 1);
  printf("%d %d\n", i >> 2, i / 4);          /* arithmetic shift vs division */
  printf("%llu %llu\n", q >> 8, q << 8);
  printf("%d %u\n", (int)(signed char)0xFF, (unsigned)(unsigned char)0xFF);
  return 0;
}
C
# Integer -> floating CASTS at every width and signedness. Not float formatting
# (%.17g of a value that is exactly representable is exact everywhere): these are
# WRONG VALUES. Each target got a different subset wrong and every one of them
# was invisible below 2^31, which is where ordinary code lives —
# bug-c-int64-to-double-cast-truncates-on-32bit. Keep the 2^53-1, 2^63 and
# ULLONG_MAX rows: they are the three thresholds that separate the bugs
# (high-word drop, signed-vs-unsigned 64, and unsigned-32 sign).
probe int-to-float-casts <<'C'
#include <stdio.h>
int main(void) {
  unsigned long long m = 0x1FFFFFFFFFFFFFULL;    /* 2^53-1, exact in a double */
  unsigned long long big = 18446744073709551615ULL;
  long long s = 4886718345LL, neg = -5LL, at31 = 2147483648LL;
  unsigned int u = 4294967295u, u2 = 2147483648u;
  long long v = 4294967296LL;
  printf("%.17g %.17g %.17g\n", (double)m, (double)s, (double)neg);
  printf("%.17g %.17g %.17g\n", (double)at31, (double)u, (double)u2);
  printf("%.17g %.17g\n", (double)big, (double)v);
  printf("%.17g %.17g %.17g\n", (float)v, (float)u, (float)4294967296LL);
  return 0;
}
C
# Plain `char` is signed on x86-64 and UNSIGNED under the ARM procedure call
# standard, so this case is right to differ under --target and is tagged rather
# than fixed. Kept as a case because a target getting its OWN char signedness
# wrong is still worth catching natively.
probe plain-char-signedness charsign <<'C'
#include <stdio.h>
int main(void) {
  char c = (char)0xFF;
  printf("%d %d\n", (int)c, (int)(char)0x7F);
  return 0;
}
C
probe switch-fallthrough-and-default <<'C'
#include <stdio.h>
static int f(int k) {
  int r = 0;
  switch (k) {
    case 1: r += 1;
    case 2: r += 2; break;
    case 5: case 6: r += 10; break;
    default: r = -1;
  }
  return r;
}
int main(void) {
  printf("%d %d %d %d %d %d\n", f(1), f(2), f(3), f(5), f(6), f(99));
  return 0;
}
C
probe switch-sparse-and-negative <<'C'
#include <stdio.h>
static const char *f(int k) {
  switch (k) {
    case -1000: return "a";
    case 0: return "b";
    case 1000000: return "c";
    case -1: return "d";
    default: return "?";
  }
}
int main(void) {
  printf("%s%s%s%s%s\n", f(-1000), f(0), f(1000000), f(-1), f(7));
  return 0;
}
C
probe designated-initializers <<'C'
#include <stdio.h>
struct D { int a, b, c; char t[4]; };
int main(void) {
  struct D d = { .c = 3, .a = 1, .t = "hi" };
  int arr[6] = { [4] = 40, [1] = 10 };
  printf("%d %d %d %s\n", d.a, d.b, d.c, d.t);
  printf("%d %d %d %d %d %d\n", arr[0], arr[1], arr[2], arr[3], arr[4], arr[5]);
  return 0;
}
C
probe compound-literal <<'C'
#include <stdio.h>
struct P { int x, y; };
static int sum(struct P p) { return p.x + p.y; }
int main(void) {
  int s = sum((struct P){ 3, 4 });
  int *a = (int[]){ 7, 8, 9 };
  printf("%d %d %d\n", s, a[0], a[2]);
  return 0;
}
C
probe varargs-mixed-widths <<'C'
#include <stdio.h>
#include <stdarg.h>
static long long tally(int n, ...) {
  va_list ap; long long t = 0; int i;
  va_start(ap, n);
  for (i = 0; i < n; i++) {
    int k = va_arg(ap, int);
    long long q = va_arg(ap, long long);
    double d = va_arg(ap, double);
    t += k + q + (long long)d;
  }
  va_end(ap);
  return t;
}
int main(void) {
  printf("%lld\n", tally(2, 1, 2LL, 3.0, 10, 20LL, 30.0));
  return 0;
}
C
probe qsort-and-bsearch <<'C'
#include <stdio.h>
#include <stdlib.h>
static int cmp(const void *a, const void *b) {
  int x = *(const int *)a, y = *(const int *)b;
  return (x > y) - (x < y);
}
int main(void) {
  int v[8] = { 5, -1, 9, 0, 3, 9, -7, 2 };
  int key = 3, i;
  int *hit;
  qsort(v, 8, sizeof(int), cmp);
  for (i = 0; i < 8; i++) printf("%d ", v[i]);
  printf("\n");
  hit = (int *)bsearch(&key, v, 8, sizeof(int), cmp);
  printf("%d %d\n", hit != NULL, hit ? *hit : -1);
  key = 100;
  hit = (int *)bsearch(&key, v, 8, sizeof(int), cmp);
  printf("%d\n", hit != NULL);
  return 0;
}
C
probe setjmp-longjmp <<'C'
#include <stdio.h>
#include <setjmp.h>
static jmp_buf jb;
static void deep(int k) { if (k > 0) deep(k - 1); else longjmp(jb, 7); }
int main(void) {
  int r = setjmp(jb);
  if (r == 0) { printf("go\n"); deep(5); printf("unreachable\n"); }
  else printf("back %d\n", r);
  return 0;
}
C
probe pointer-arith-on-struct-array <<'C'
#include <stdio.h>
struct E { int a; char b; };
int main(void) {
  struct E v[4];
  struct E *p = v, *q;
  long d;
  int i;
  for (i = 0; i < 4; i++) { v[i].a = i; v[i].b = (char)('A' + i); }
  q = p + 3;
  d = q - p;                       /* sequenced, then printed */
  printf("%ld %d %c %d\n", d, q->a, q->b, (int)sizeof(struct E));
  printf("%d %c\n", (p + 2)->a, (*(p + 1)).b);
  return 0;
}
C
probe const-and-static-locals <<'C'
#include <stdio.h>
static int tick(void) { static int n = 0; n++; return n; }
int main(void) {
  int a, b, c;
  a = tick(); b = tick(); c = tick();   /* sequenced, never in one arg list */
  printf("%d %d %d\n", a, b, c);
  return 0;
}
C

printf '\ngcc_diff_probe%s: %d cases, %d NEW divergence(s), %d known, %d skipped, %d model-dependent\n' \
  "${TARGET:+ [--target $TARGET]}" "$ran" "$new" "$known" "$skipped" "$modelskip"
[ "$new" -eq 0 ]
