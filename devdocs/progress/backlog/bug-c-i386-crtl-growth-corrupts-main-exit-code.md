---
summary: "i386: adding ANY code to lib/crtl corrupts an unrelated program's exit code — output stays right, main's implicit return 0 becomes garbage"
type: bug
track: C
prio: 65
---

# On i386, growing crtl breaks `main`'s exit code in programs that never call the new code

- **Type:** bug (C backend / 32-bit codegen or link — **Track C**)
- **Opened:** 2026-07-31 by Track B, after Track T's cross matrix caught a
  regression my native gate could not see.

## Symptom

`library_candidates/c-testsuite/tests/single-exec/00211.c`:

```c
extern int printf(const char *format, ...);
#define n 0xe
int main() { printf("n+1 = %d\n", n+1); }     /* implicit return 0 */
```

Compiled `--target=i386` and run under `tools/run_target.sh`:

```
n+1 = 15      <- output CORRECT
rc=60         <- should be 0
```

The program prints the right thing and then exits with garbage. `00206.c` and
`00212.c` do the same.

## What changes it — and this is the alarming part

Nothing in the test. **Adding unrelated functions to `lib/crtl`.** Bisected
across four Track B commits, with `lib/crtl` checked out at each and only the
exit code observed:

| lib/crtl at | 00211 exit |
| --- | --- |
| `4d9bf3f8a` (before) | 0 |
| `2df158465` (+39 errno defines) | 0 |
| `aa3f561a7` (+`strnlen`) | 0 |
| `780506d85` (+`div`/`ldiv`/`lldiv`/`llabs`) | **92** |
| `ea07b041c` (sscanf widths, `%#o`, `%.0d`) | **140** |

`00211.c` calls **none** of those functions. And reverting `stdlib.c` alone did
not fix it — the `stdio.c` change breaks it independently. Two unrelated
additions each trigger it, and the failing value varies with what was added,
which is the signature of a size- or layout-sensitive fault rather than a bug in
any one function.

Plausible directions, none confirmed: the entry stub reading main's return from
the wrong place once crtl crosses some size; a relocation or offset that
overflows on 32-bit; `lldiv`'s 64-bit division helper or its 16-byte
struct-by-value return perturbing the module. Worth checking the i386 `_start`
-> `main` -> `exit` path first, since output is fine and only the return value
is wrong.

## Why it went unnoticed until Track T

`tools/gate.sh lib` is x86-64 only. The whole point of "confirm native, offload
the matrix" is this case, and it worked — the cross matrix caught it, my native
gate could not have. Worth remembering when a Track B change touches
`lib/crtl`: that code is compiled for **every** target.

## Current state

Master is restored — `lib/crtl` and `test/crtl_libc_oracle.c` are back at
`aa3f561a7`, keeping the i386-clean errno.h and `strnlen`. 00206/00211/00212/
00213 exit 0 again.

**Reverted and wanted back once this is fixed** (both were verified correct
against gcc on x86-64, and are in git at the SHAs above):

- `div` / `ldiv` / `lldiv` / `llabs` + the `div_t` family — C89/C99, absent
  entirely.
- The `sscanf` field-width fix. That one matters: `%15s` — the safe spelling —
  silently abandoned the whole scan and left the destination untouched. Also
  `%*d` suppression, `%hd`/`%hhd` writing the right width, `%#o`, and `%.0d`.

## Gate

C tests green + self-host byte-identical, plus `test-c-conformance-i386` and
`-riscv32` green with the reverted crtl work restored — the restoration is the
regression test.
