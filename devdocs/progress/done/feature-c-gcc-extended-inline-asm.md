---
slug: feature-c-gcc-extended-inline-asm
title: "GCC extended inline asm: accept the compiler-barrier form, refuse the rest by name"
track: C
prio: 50
type: feature
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
commit: 7a62439f4
summary: "The C frontend did not recognise `asm` at all, so a bare `asm(\"\")` failed as `call to undeclared function: asm` and the operand sections died at the first ':'. busybox's barrier() is `asm volatile (\"\":::\"memory\")`, expanded by INIT_G()/INIT_S(), so three applets stopped on their function's first statement. Empty template -> compiles to nothing (correct); anything else refused by name rather than silently dropped."
---

# `asm volatile ("":::"memory")`

Found compiling busybox 1.37.0, with
[[bug-c-logical-not-is-not-folded-in-a-constant-expression]] and
[[bug-c-a-ternary-cannot-be-the-callee-of-a-call]].

## What was there: nothing

| written | before |
| --- | --- |
| `asm("")` | `error: call to undeclared function: asm` |
| `__asm__ volatile ("")` | `error: call to undeclared function: __asm__` |
| `asm volatile ("":::"memory")` | `Expected: ), but got: (Kind: 79)` — the first `:` |
| `asm volatile ("mov %0,%0" : "+r"(x))` | same |

`asm` was an ordinary identifier, so it parsed as a call.

busybox reaches it from `include/libbb.h`:

```c
#define barrier()             asm volatile ("":::"memory")
#define ASSIGN_CONST_PTR(pptr, v) do { *(void**)(pptr) = (void*)(v); barrier(); } while (0)
#define SET_PTR_TO_GLOBALS(x) ASSIGN_CONST_PTR(&ptr_to_globals, x)
```

`INIT_G()` / `INIT_S()` expand that, and applets call it as their function's
**first statement** — so `coreutils/test.c`, `editors/ed.c` and
`util-linux/acpid.c` each died immediately, at line 926, 1006 and 266.

## What landed, and the line it draws

An **empty template with no output operands** is a compiler barrier: it orders
the compiler, not the machine. pxx does not reorder across a statement
boundary, so compiling it to nothing is not an approximation — it is what the
construct means. That form is accepted, in every spelling:

```c
asm(""); asm volatile (""); __asm__ volatile (""); __asm ("");
asm volatile ("":::"memory");     asm volatile ("" ::: "memory");
asm volatile ("" : : : "memory"); asm volatile ("" "" ::: "memory");
```

**Everything else is refused, by name.** Parsing real instructions and dropping
them would silently miscompile precisely the code that cares most about what the
machine does — the *incomplete step reporting in the vocabulary of a complete
one* class this project treats as its most expensive:

```
error: C: inline asm with a non-empty template is not supported
       — the instructions would be silently dropped
error: C: inline asm with an output operand list is not supported
       — nothing would ever be written to it
```

The second exists because an empty template with an OUTPUT section still claims
to produce a value, which nothing wrote. `":::"` (clobbers only) carries no such
claim, which is why the section COUNT distinguishes them rather than the
template alone.

This is deliberately not an implementation of extended asm. Operand
constraints, `%0` substitution, register allocation and clobber honouring are a
real feature; this is the honest boundary in front of it, and the diagnostic
names which part is missing so a reader is not left inferring it from a parse
error.

## Measured

| | |
| --- | --- |
| `coreutils/test.c` | refused → **compiles** |
| `editors/ed.c` | refused → **compiles** |
| `util-linux/acpid.c` | refused → **compiles** |
| `run_c_conformance.sh` | 220 pass / 0 fail — baseline |
| `run_pascal_conformance.sh` | 346 pass / 0 fail — baseline |
| self-host | converged after 1 round |
| `gate.sh quick` | GREEN |

## busybox, cumulative for the three C fixes today

Restricted to the **286 files gcc actually compiles** in `libbb` + `coreutils` +
`editors` + `util-linux` — an earlier count of 307 included include-fragments
like `pw_encrypt_des.c` that the real build never compiles standalone, so it
inflated the failure list:

| | files compiling clean |
| --- | --- |
| session start | 174 |
| after the `!` / negative-bound fix | 176 |
| after the ternary callee | 176 (+ `stat.c`, − none) |
| after inline asm | **178** |

and the residue is now sharply separated:

| remaining failure | count |
| --- | --- |
| missing crtl function — a LIBRARY gap | 100 |
| real compiler gaps | **8** |

The eight, which are the whole remaining compiler work list:

| file | |
| --- | --- |
| `libbb/copy_file.c:351` | `expected C expression` |
| `editors/vi.c:791` | `expected C expression` |
| `util-linux/fdformat.c:82` | `expected C expression` |
| `util-linux/rtcwake.c:102` | `expected C expression` |
| `libbb/unicode.c:124` | `IR_UNSUPPORTED: AST node (kind 1)` |
| `util-linux/rev.c:51` | `IR_UNSUPPORTED: AST node (kind 1)` |
| `libbb/lineedit.c:367` | `stray token at top level: 'wchar_t'` |
| `editors/awk.c` | `#error … RAND_MAX` — a header value, not the compiler |

Four share `expected C expression` and two share `IR_UNSUPPORTED`, so this is
plausibly three or four distinct causes rather than eight. Do not assume it:
`test.c`/`ed.c`/`acpid.c` shared a symptom string with `copy_file.c` today and
turned out to be a different bug, which is why they were separated before being
fixed.

## Gate

`test/casm_barrier.c` (gcc -O0 oracle: every accepted spelling, plus a barrier
between two increments in a function and at top level) and
`test/casm_nonempty_template_fails.c` (must NOT compile), both wired into
`test-core`.
