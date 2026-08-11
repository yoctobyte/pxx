---
summary: "On i386 every C program's `main` reads garbage argc and a bogus argv: the entry stub pushes cdecl order (argc lowest) but a CProgramMode callee reads leftmost-first, so argc receives the argv POINTER. Pascal's ParamCount on i386 is fine — this is the C stub only."
type: bug
track: A
prio: 55
found-by: claude-B
status: done
owner: claude-A
---

# i386: the C entry stub hands `main` argc and argv in the wrong slots

- **Type:** bug (silent wrong value) — Track A (ABI / entry stub,
  `compiler/cparser.inc:8421`, TARGET_I386 arm of the C entry stub)
- **Opened:** 2026-08-10
- **Found by:** Track B, cross-checking crtl's new `atexit`
  ([[feature-b-crtl-last-seven-unimplemented-declarations]]) on all five targets.
  Every argv-selected sub-mode of the test silently ran the *default* branch on
  i386 and passed nothing — arm32, aarch64 and riscv32 were all correct.

## Repro

```c
#include <stdio.h>
int main(int argc, char **argv) {
  int i; printf("argc=%d\n", argc);
  for (i = 0; i < argc; i++) printf("[%s]\n", argv[i]);
  return 0;
}
```

```
$ pinned --target=i386 argv.c argv_i386 && tools/run_target.sh i386 ./argv_i386 hello world
argc=-4958108                 <- a STACK ADDRESS read as an int; the loop then runs 0 times

$ pinned --target=aarch64 ... && tools/run_target.sh aarch64 ./argv_a64 hello world
argc=3
[/…/argv_a64]
[hello]
[world]
```

**Not a regression from the v256 pin.** Checked against the previous pinned
binary (`ca4dac8d0`, before the entry stub gained its finalizer call) — same
garbage, so the finalizer change is exonerated and this is long-standing.

**Pascal on i386 is fine:** the same argv through `ParamCount`/`ParamStr` prints
`count=2` and all three strings. The Pascal entry path does not go through this
stub, which is why nothing caught it.

## Mechanism (measured, not inferred)

The stub pushes **cdecl order** — argv first, then argc, leaving argc at the
lowest address (`cparser.inc:8421`):

```
lea ecx, [eax+4]   ; argv
push ecx           ; arg2
push [eax]         ; arg1 = argc
call main
```

But `ir_codegen386.inc:3140` states the internal convention outright: *"The
internal convention pushes leftmost-first"*, and the reversal that would make a
call cdecl-shaped is explicitly **disabled inside a C program**:

```pascal
vaFwd := (procIdx >= 0) and (ProcVariadic[procIdx] or (ProcCdecl[procIdx] and not CProgramMode));
```

So `main`, compiled in CProgramMode, reads arg0 from the *higher* slot — which
holds argv. That is exactly what the observed value is: `argc=-4958108` is
`0xFFB4…`, a stack address, not a count.

## Fix

Swap the two pushes in the TARGET_I386 arm so the stub matches the convention
the callee actually uses (leftmost-first: push argc, then argv). Worth a look at
the other four arms while there — arm32/aarch64/riscv32 are verified correct by
the test above, x86-64 too, so i386 is the odd one out.

## Gate

`tools/gcc_diff_probe.sh --target i386` with an argv case, plus
`test/crtl_atexit.c`'s `e`/`x`/`n` sub-modes (they select on `argv[1]`, so they
are an argv assertion on every target and currently all collapse to the default
branch on i386 — a passing i386 run of those three is the proof).

## Log
- 2026-08-11 — resolved, commit b58b3904e.
