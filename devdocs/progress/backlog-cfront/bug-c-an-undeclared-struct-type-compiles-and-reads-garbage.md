---
slug: bug-c-an-undeclared-struct-type-compiles-and-reads-garbage
track: C
type: bug
prio: 45
status: backlog
owner: ""
created: 2026-09-24
found-by: frankS (fixing bug-b-terminalsize-answers-enotty-on-xtensa)
blocked-by: []
summary: "HALF FIXED 2026-09-24 (commit `fix(C): a member taken from a type of unknown layout is refused, not read at offset 0`): taking a MEMBER from a type of unknown layout is now refused. WHAT REMAINS is the DECLARATION site, and the mechanism is that a type of unknown size is given size 0 rather than being refused an object -- so `struct nosuch v;` still defines a zero-byte object and `sizeof` of an incomplete type answers 0 instead of erroring. The condition that springs it is any code that sizes an object rather than naming its members: `memset(&v, 0, sizeof v)` compiles to a no-op, `malloc(sizeof(struct opaque))` asks for 0 bytes, and a struct passed or copied by value moves nothing. gcc errors with `storage size of 'v' isn't known` and `invalid application of sizeof to incomplete type`. This half is still SILENT-WRONG-VALUE: no diagnostic, a working binary, a plausible number. NOT a blanket refusal of incomplete types -- `struct opaque *p;`, forward declarations and extern declarations are legal C and this tree's own headers use them; what must be refused is DEFINING an object of, or applying sizeof to, a type whose layout is unknown. The member half that landed measured its false-positive population first (17043 resolving accesses across zlib and lib/crtl/src, zero failing) and that discipline is what this half still needs, on a population that is NOT busybox or sqlite -- neither parses per-file in this tree, and a sweep of busybox answered 0-of-0 without saying so."
---

# An undeclared struct type compiles and reads garbage

## Reproducer

```c
#include <stdio.h>
int main(void) {
  struct nosuchtype v;
  v.field = 3;
  printf("%d\n", v.field);
  return 0;
}
```

- **gcc:** `error: storage size of 'v' isn't known`
- **pxx:** `ok: ... [code=61881B ...]` — compiles, links, runs.

Measured 2026-09-24 at HEAD on x86-64.

## How it surfaced, which is the part worth keeping

`lib/crtl/include/sys/ioctl.h` declared `TIOCGWINSZ` but not `struct winsize`,
while glibc's provides both. So the canonical spelling —

```c
#include <sys/ioctl.h>
struct winsize ws;
ioctl(1, TIOCGWINSZ, &ws);
printf("cols=%d rows=%d\n", ws.ws_col, ws.ws_row);
```

— compiled, the ioctl **succeeded** (`rc=0`), and it printed
`cols=8650792 rows=8650792`. `8650792` is `0x00840028`: `0x0084` is 132 and
`0x0028` is 40, the correct geometry, read as one 32-bit field instead of two
16-bit ones.

**Every signal the caller had said it worked.** The syscall returned 0, the
kernel really did fill the struct, and the only thing wrong was a member access
against a type of unknown layout.

**It also mimicked an unrelated bug.** This appeared while the xtensa
`TIOCGWINSZ` constant was being fixed, and the garbage showed up on **x86-64 and
xtensa alike** — which reads as "the new constant is wrong on both targets". A
control struct of two `unsigned short`s answers `132, 40` correctly, and that
asymmetry is what separated the incomplete type from the ioctl.

## Scope of the fix

**Not** a blanket refusal of incomplete types. `struct opaque *p;`, forward
declarations and pointers to undefined tags are legal C and used widely,
including in this tree's own headers. What must be diagnosed is:

- **defining an object** of a type whose size is unknown (`struct T v;`), and
- **taking a member** from such a type (`v.field`, `p->field`).

Both have an exact gcc wording to match if a differing diagnostic is not wanted.

## What is already done

`struct winsize` is now declared in `<sys/ioctl.h>` as well as `<termios.h>`,
guarded by `__struct_winsize_defined` so either include order works
(`bug-b-terminalsize-answers-enotty-on-xtensa-and-the-probe-cannot-say-why`).
That closes the instance. It does not close the class, and the class is
silent-wrong-value.

## 2026-09-24 — the member half landed; the declaration half did not

**What was wrong about this ticket's own framing, found by measuring rather than
by reading:** it assumed `struct nosuchtype v;` leaves the base at `REC_NONE`.
It does not. The C frontend **allocates an empty record for the unseen tag**, so
`recId` is valid, every member lookup misses, and the whole struct reads at
offset 0. An undeclared tag and a typo'd member on a fully known struct are
therefore **the same code path**, and one check covers both — the
normalise-don't-special-case answer rather than two arms.

The root mechanism is narrower and worse than "an undeclared type compiles":
`RecFieldOffset` is a pure offset function with **no error channel**, so a field
it cannot find reads back as offset **0**, and 0 is a real address in every
record. Hence the clobber:

```c
struct real { int a; int b; };
struct real v; v.a = 11; v.b = 22; v.typo = 99;
printf("a=%d b=%d\n", v.a, v.b);      /* pxx: a=99 b=22   gcc: refuses */
```

`RecHasField` (new, `compiler/symtab.inc`, deliberately mirroring
`RecFieldOffset`'s two arms so they cannot disagree) is the missing error
channel.

### The population, recorded with its denominator

| corpus | files | accesses resolving | failing | REC_NONE |
| --- | --- | --- | --- | --- |
| zlib + lib/crtl/src, **summed** | 48 | 17,043 | 0 | 0 |

**The split between the two corpora is deliberately not given: it was never
measured.** The sweep totalled the two together, and the instrument that
produced it — a temporary `PXXPROBE fieldok` counter at the member-access site —
is not in the tree, so the split is not recoverable by re-running. Anyone who
wants it re-adds the counter; nobody should quote a per-corpus number from here.

Measured at `36d63c8e0`. After the change, **0 of those 48 files** are newly
refused.

**Two corpora are NOT in that table and the reason is the finding.** A first
sweep of busybox's 685 TUs answered "0 bad" — and every file had died in
`libbb.h` before reaching a function body, so the 0 was **0-of-0**. Only
counting the RESOLVED accesses alongside the failing ones made that visible.
busybox needs `busybox_diff.sh` to regenerate `include/autoconf.h` per run
(`ENABLE_FEATURE_VERBOSE` is absent from the one checked in), and sqlite dies at
`__BEGIN_DECLS` before any body. Neither parses per-file in this tree.

`REC_NONE` is left alone on purpose: it measured zero here too, but
`ResolveNodeRec` failing on valid code is a documented recurring gap in
`cparser.inc` itself, and 48 files is not the population that would settle it.

### What is still open

**Defining an object of an incomplete type, and `sizeof` of one.** Both are
still silent, and both still produce a plausible wrong number:

```c
struct nosuch v;                 /* gcc: storage size of 'v' isn't known */
sizeof(v)                        /* pxx: 0    gcc: invalid application of sizeof */
```

The consequence is not academic — `memset(&v, 0, sizeof v)` compiles to a
no-op, `malloc(sizeof(struct opaque))` asks for 0 bytes, and a by-value copy
moves nothing.

This needs the same treatment the member half got, in this order: find the
sizing site, then **measure the false-positive population before arming
anything**. The legal shapes it must not touch are already pinned by
`test/c_incomplete_type_legal_shapes.c` — pointers to incomplete types, `extern`
declarations of them, forward-then-defined tags, self-referential nodes — and
that file is the place to add a row for any new legal shape found.
