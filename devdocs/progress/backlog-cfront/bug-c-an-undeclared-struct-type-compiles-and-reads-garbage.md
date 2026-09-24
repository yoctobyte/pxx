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

## 2026-09-24, later — a THIRD state, and a correction that was worse than the bug

The section above says an undeclared tag and a typo'd member reach one
not-found path. That is true and it is **incomplete**, and the missing part
shipped as a regression for one commit.

**There are three ways a record can lack the member being asked for, and
`RecSize` and the field count cannot tell any of them apart:**

| state | how it arises | who is wrong |
| --- | --- | --- |
| no body ever seen | `struct nosuchtype v;` — forward record minted for the tag | the source: definition missing |
| body seen, **layout dropped** | `SkipBraceBlock` — "keep the tag, drop the layout" | **us**: pxx declined to lay it out |
| body laid out, genuinely empty | `struct E { };`, a GNU extension gcc accepts | the source: the member name |

The middle row is the one that bit. `struct S { int a; int b; }
__attribute__((aligned));` is **valid C that gcc compiles**, `CStructBodyIsSimple`
returns False for an alignment attribute with no parsed value, and the record
reaches the field tables with zero fields — indistinguishable from an undefined
tag. The two-arm check duly refused `v.a` with *"the struct/union has no
definition in scope"*, which is false; the definition is on the line above.

**THE FIRST CORRECTION WAS WORSE THAN THE BUG, and this is the part to keep.**
The obvious repair is to suppress the diagnostic where the layout is unknown —
we cannot know a member is missing from a struct we never laid out. That
compiles the program, and it **prints `9 9` where gcc prints `7 9`**: with the
layout dropped every member resolves to offset 0, and `sizeof` answers 0 against
gcc's 16. It trades a loud wrong MESSAGE for a silent wrong VALUE — this
ticket's own bug, reintroduced by the guard written to prevent a regression. It
was caught only by building the binary and **running** it rather than stopping
at "it compiles again".

**All three states refuse.** Two flags carry the distinction (`UClsBodySeen`,
set in `ParseCStructInto`, the one place a body is laid out; `UClsLayoutDropped`,
set at the `SkipBraceBlock` arm) and `CRecMissingFieldKind` reads them, so each
arm says something true: the member NAME is wrong, the DEFINITION is missing, or
the layout is ours to explain.

**The false-positive census could not have caught this.** 48 files of zlib and
`lib/crtl/src` contain no struct with an unparsed alignment attribute, so the
sweep was **silent about the case rather than clearing it** — an honest
measurement over a population that cannot contain the subject. The number was
re-taken after the third arm existed (still 0 of 48) instead of being carried
forward.

## 2026-09-24 — the gcc boundary for the declaration half, measured

Banked because it is the expensive part to re-derive, and because the first
design I had in hand would have been **wrong in the refusing direction** on two
of these rows. Every row measured against `gcc -std=gnu99` and against pxx at
the tree carrying the member fix.

| shape | gcc | pxx | note |
| --- | --- | --- | --- |
| `struct S v;` in a function body | **error** `storage size of 'v' isn't known` | accepts | the target |
| ...with `struct S { int x; };` later at file scope | **error** | accepts | **block scope needs the type complete AT THE DECLARATION**, so a parse-time check matches gcc exactly |
| `static struct S v;` in a body | **error** | accepts | same arm; `CLocalStaticDecl` still routes through the same allocator |
| `extern struct S v;` in a body | accepts | accepts | **must not be refused** — declares, defines nothing |
| `struct S *p;` in a body | accepts | accepts | must not be refused — the opaque-handle idiom |
| `struct S v;` at FILE scope | **error** | accepts | but see the row below — this one is NOT a parse-time check |
| `struct S v;` at file scope, `struct S {...}` later | **accepts** | accepts | **a tentative definition only needs its size by END OF TRANSLATION UNIT** |
| `struct S a[3];` in a body | **error** `array type has incomplete element type` | accepts | separate message, separate site |
| `int f(struct S v)` by value | **error** `parameter 1 ('v') has incomplete type` | accepts | separate message, separate site |
| `int f(struct S *p)` | accepts | accepts | must not be refused |

**The two rows that kill the obvious design.** A parse-time refusal at the
declaration site is correct for BLOCK scope and **wrong for FILE scope** — row 7
is legal C that gcc compiles, and refusing it would break a tentative definition,
which is an ordinary spelling. So the file-scope half needs a deferred
end-of-translation-unit check over objects still incomplete, not a check where
the declaration is parsed. Those are two different pieces of work and only the
block-scope one is cheap.

**What makes the block-scope half tractable now and not before:** it needs to
tell "never defined" from "defined, layout dropped" and from "defined empty",
which is exactly what `UClsBodySeen` / `UClsLayoutDropped` and
`CRecMissingFieldKind` were added for. Refuse only on kind 1 (no body ever
seen); the other two are definitions and must be left alone.

**Three call sites, not one.** `if declTk = tyRecord then LastTypeRecId :=
scalarRec;` appears three times in `cparser.inc` (the plain local-declaration
path and two others), so a block-scope object of record type can reach
allocation by more than one route. Hooking one of them is the shape of bug this
tree calls "the sibling is a spelling" — find all three, or put the check in the
shared allocator where every route passes.

**Do not skip the census a second time.** The member half's false-positive
population (48 files, zlib + `lib/crtl/src`) contained no alignment-attribute
struct and was therefore silent about the state that produced a regression. A
declaration-site census must deliberately include: a tentative definition
completed later, a block-scope `extern`, a pointer-to-incomplete, and a struct
whose body pxx drops.
