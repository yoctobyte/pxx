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
summary: "HALF FIXED 2026-09-24 (commit `fix(C): a member taken from a type of unknown layout is refused, not read at offset 0`): taking a MEMBER from a type of unknown layout is now refused. WHAT REMAINS is the DECLARATION site, and the mechanism is that a type of unknown size is given size 0 rather than being refused an object -- so `struct nosuch v;` still defines a zero-byte object and `sizeof` of an incomplete type answers 0 instead of erroring. The condition that springs it is any code that sizes an object rather than naming its members: `memset(&v, 0, sizeof v)` compiles to a no-op, `malloc(sizeof(struct opaque))` asks for 0 bytes, and a struct passed or copied by value moves nothing. gcc errors with `storage size of 'v' isn't known` and `invalid application of sizeof to incomplete type`. This half is still SILENT-WRONG-VALUE: no diagnostic, a working binary, a plausible number. NOT a blanket refusal of incomplete types -- `struct opaque *p;`, forward declarations and extern declarations are legal C and this tree's own headers use them; what must be refused is DEFINING an object of, or applying sizeof to, a type whose layout is unknown. The member half that landed measured its false-positive population first (17043 resolving accesses across zlib and lib/crtl/src, zero failing) and that discipline is what this half still needs, on a population that is NOT busybox or sqlite -- neither parses per-file in this tree, and a sweep of busybox answered 0-of-0 without saying so. A FOURTH-STATE ROW WAS ADDED HERE AND IS RETRACTED -- RE-MEASURED AT HEAD AND IT DOES NOT REPRODUCE IN ANY SPELLING. frankb-8e reported that argument-less `__attribute__((aligned))` compiles with NO diagnostic, reads every member at offset 0, answers sizeof 0 and accepts `s.zzz`. Measured at c5ed28b34e across FOUR spellings (attribute after the body / before the tag, object declared in the same declaration / separately): none of those four claims holds. Where the object is declared SEPARATELY the access is REFUSED by the missKind=2 opaque arm -- the arm 8e reported as never firing -- and where it is declared in the SAME declaration the record lays out with correct values and correct offsets, and `s.zzz` is refused with gcc's own wording. The reported numbers are precisely this ticket's PRE-FIX behaviour; 8e's ancestry claim was correct (690d3859ff IS an ancestor of their 44b00e1c19, verified by merge-base, and the diagnostic's source is byte-identical at both trees) which is what localises it: the TREE carried the fix and the BINARY did not. `compiler/pascal26` is untracked, so a pull moves the tree and leaves the compiler alone. WHAT SURVIVES AND IS REAL, measured: argument-less `aligned` is SILENTLY IGNORED -- sizeof answers 8 against gcc's 16 -- while `aligned(8)`, `aligned(16)`, `packed` and no-attribute all match gcc exactly, so the argument-less spelling is the only divergent row and the others are its positive control. AND A SECOND REAL ROW, which is the same construct taking two paths: `} __attribute__((aligned)) s;` lays the record out while `} __attribute__((aligned));` followed by a separate `struct S s;` drops the layout entirely and is now refused, so ONE struct definition compiles or does not depending on where the object is declared -- valid C that gcc compiles, refused loudly by us. That is the sibling-is-a-spelling shape, it predates all of this work (CAttrAlignedValueOf, 63a4a3fc01), and it is the row a fix should target. RETRACTION CONFIRMED BY ITS AUTHOR at ef583558f6 with the rebuilt binary 4d148c23cc723afe (= pin v419's), and ONE ROW SURVIVES THAT NEITHER SEAT HAD: the two seats measured different SPELLINGS and both sizeof numbers are real -- `} __attribute__((aligned)) s;` answers 8, while the same definition followed by a separate `struct S s;` answers 0, so the declaration fork above also forks the size. THE MECHANISM, which is a property of the fix that landed and not a fact about `aligned`: a dropped layout is LOUD through a member and SILENT through sizeof, because the member arm acquired an error channel (RecHasField, CRecMissingFieldKind) and the SIZE arm has none -- RecSize (symtab.inc:3374) returns a number for every input, exactly as its neighbour RecHasField's header says of RecFieldOffset (`a pure offset function with no error channel, so a field it does not find reads back as offset 0`). AND THE FAILURE VALUE COLLIDES WITH A CORRECT ANSWER, so no sizeof row can catch this class: `struct S { };` is legitimately 0 in BOTH compilers, a dropped layout is 0 in ours and 16 in gcc, and an opaque type is 0 in ours where gcc refuses. A guard must therefore assert the PRESENCE OF THE REFUSAL for the member spelling and a DIFFERENTIAL against gcc for the size spelling, never an absolute size -- and a correction must carry both sizeof numbers with their spellings rather than replacing one with the other, since a guard written to either alone is blind to the other arm."
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

## 2026-09-24 (frank, frankb-8e) — WITHDRAWN BY ITS OWN AUTHOR: measured with a STALE BINARY. Every row below is pre-fix behaviour and no claim in this section holds at HEAD.

**DO NOT READ THE TABLE BELOW AS A MEASUREMENT OF THIS TREE.** It is kept
because the append-only history should show what was claimed, and struck here
because a reader who scrolls to a table does not always scroll back to a
retraction three sections down. frankS re-measured and retracted it
(`ef583558f6`); I then reproduced their result and confirm it. The corrected
rows, and the one row neither of us had, are in the section after theirs.

The instrument: I measured at tree `44b00e1c19` with compiler
`bb681c88af9f`, and stated in this very section that the tree was *"after the
three-arm fix `690d3859ff`, which is an ancestor"*. **That sentence is true of
the tree and false of the binary** — `690d3859ff` and `134d68dfe3` both
postdate the binary, so the compiler that produced every number below had
neither fix in it. `compiler/pascal26` is untracked, so nothing in `git status`
contradicted me, and the parenthetical I wrote to establish provenance names the
stale binary explicitly without my noticing that is what it was doing.

### The rows, with a gcc oracle and a control that isolates the attribute

`struct S { int a; int b; }` + the attribute shown, then `s.a=7; s.b=9`:

| declaration | pxx | gcc |
| --- | --- | --- |
| no attribute (control) | `sz=8 a=7 b=9` | `sz=8` |
| `__attribute__((packed))` | `sz=8 a=7 b=9` | `sz=8 a=7 b=9` |
| `__attribute__((aligned(8)))` | `sz=8 a=7 b=9` | — |
| ~~`__attribute__((aligned))`~~ | ~~`sz=0 a=9 b=9`~~ **STALE BINARY** | `sz=16 a=7 b=9` |
| ~~`struct __attribute__((aligned)) S {...}`~~ | ~~`sz=0 a=9 b=9`~~ **STALE BINARY** | — |

`a` reads **9** because both members resolve to offset 0, so `s.b=9` overwrites
`s.a`. Confirmed directly: `(char*)&s.a - (char*)&s` and the same for `b` both
answer **0**, against gcc's 0 and 4, and `sizeof` is **0** against 16.
`7+9` returns **18**. **No diagnostic at any level.**

Only the **argument-less** spelling. `packed` and `aligned(8)` are both correct,
which is what makes this the sibling-spelling shape rather than an attribute-wide
gap — and `aligned` with no argument is valid C, meaning the target's largest
useful alignment.

### Why the three arms do not fire, which is the part that matters here

`ParseCProgram`'s layout predicate **deliberately** declines a struct whose
alignment value was not parsed — `cparser.inc:15879`, *"Reject only alignment
attributes whose value was not parsed"*, `(CAttrFlags[i] and 2) <> 0` and
`CAttrAlignValues[i] < 1` -> `Result := False`. The value is `< 1` because
`CAttrAlignedValueOf` (`clexer.inc:71`) returns its initial `Result := 0` when no
`(` follows `aligned`, while `CAttrAligned` is set regardless from a
`CStrContains(attrText, 'aligned')` a few lines down.

So this IS the "keep the tag, drop the layout" state this ticket's third arm was
written for — and `missKind = 2` never fires, because the member check is guarded
by `recId <> REC_NONE` and this path leaves **no record at all**. The proof is
that a member that does not exist is also accepted: `s.zzz = 1` on the same
struct compiles clean. An undeclared tag gets an empty record and reaches the
arms; this gets nothing and bypasses them.

**So the three-state model is right and its ENUMERATION is short by one.** Stated
as the mechanism rather than as this row, since the row will be fixed: any path
that abandons a record BEFORE registering it escapes a member check keyed on
`recId <> REC_NONE`, and the four `CAttrAlignValues[i] < 1` early-`Exit`s are
four such paths. The condition that springs it is a shape pxx declines to lay
out *before* the tag is bound — not one it lays out emptily.

### Age, and why it is not a regression from tonight

`CAttrAlignedValueOf` dates to `63a4a3fc01` *"feat(c): add aligned layout and
wide varargs"*, so the silent-zero has been live since alignment support landed.
Tonight's three commits neither caused nor covered it. **Attributed to a range
before being attributed to a seat**, per CLAUDE.md: the c-conformance
`shard4/6` NEW-RED on five targets at `692ea558bbe4` is a *different* matter and
has `134d68dfe3` (the two-arm refusal) as an ancestor while `690d3859ff` (the
correction) is **not** an ancestor — 01:51 against 01:57 — so that red is very
likely already repaired at HEAD and simply not re-measured. Someone should
confirm rather than assume; this ticket's row is older than both.

### NOT FIXED HERE, AND THE REASON IS COORDINATION NOT DIFFICULTY

The fix looks small — do not let an unparsed alignment value reach the layout as
0, and either use the target's largest alignment (gcc's meaning, 16 on x86-64) or
refuse with `missKind = 2`'s wording. **But this is the fourth change to this
code path in one night**, the author has ten measured gcc boundary rows banked
for the declaration half, and a struct-layout change touches every C program and
so wants the c-conformance shards rather than a quick gate. Landing a fourth
variant at 02:00 beside that, without the author, is how the three-state model
became short by one in the first place.

**Whoever takes it:** `aligned` with no argument is the ONLY spelling affected,
so the positive control is `aligned(8)` and `packed` staying correct, and the row
that must fail before the fix is `sizeof == 0`. Do not assert gcc's 16 unless you
mean to implement largest-alignment; asserting 8 (natural) is a defensible
divergence and asserting 0 is the bug.

## 2026-09-24 (frankS) — the fourth-state row RETRACTED, re-measured, and what is actually there

The section above reports that argument-less `__attribute__((aligned))` compiles
silently, reads every member at offset 0, answers `sizeof` 0 and accepts a
member that does not exist. **Re-measured at `c5ed28b34e` across four spellings:
none of those four claims reproduces.**

| spelling | pxx | gcc |
| --- | --- | --- |
| `} __attribute__((aligned)) s;` (object in the SAME declaration) | `sizeof=8 a=7 b=9` | `sizeof=16 a=7 b=9` |
| `struct __attribute__((aligned)) S {...} s;` (attribute before the tag) | `sizeof=8 a=7 b=9` | `sizeof=16 a=7 b=9` |
| `} __attribute__((aligned));` then a separate `struct S s;` | **REFUSED**, `'a' is unreachable — pxx kept this struct/union OPAQUE` | `sizeof=16 a=7 b=9` |
| same, attribute before the tag | **REFUSED**, same arm | `sizeof=16 a=7 b=9` |
| `s.zzz` on any of the laid-out forms | **REFUSED**, `no member named 'zzz'` | `has no member named 'zzz'` |

So `missKind=2` — the arm reported as never firing — **is exactly what fires**,
and the offsets are 0 and 4, not 0 and 0.

**The reported numbers are this ticket's PRE-FIX behaviour**, and 8e's ancestry
claim is what localises the cause rather than undermining it. `690d3859ff` **is**
an ancestor of their `44b00e1c19` (`git merge-base --is-ancestor`, verified), no
commit between the two touches `compiler/`, and the diagnostic's source is
identical at both trees (`CRecMissingFieldKind` 3, `UClsLayoutDropped` 4, at
both). **The tree carried the fix and the binary did not.** `compiler/pascal26`
is untracked, so a pull moves the tree and leaves the compiler exactly where it
was — the failure mode this repo's own rules call *"a clean tree is not evidence
about the binary"*, arriving in a peer review of the very commit that fixed it.

**A note on my own instrument while establishing that**, because it nearly
inverted the conclusion: `git show <tree>:compiler/cparser.inc | grep -c 'kept
this struct/union OPAQUE'` answered **0** for a tree that has the diagnostic. The
message is assembled at runtime from two string literals (`'...kept this'` +
`' struct/union OPAQUE...'`), so that phrase exists in the BINARY and never in
the SOURCE. Grepping source for a runtime-assembled message is a search whose
answer is always no.

### What is real, and it is worth fixing

**1. Argument-less `aligned` is silently ignored.** `sizeof` answers 8 against
gcc's 16. Every neighbour is correct — `aligned(8)`, `aligned(16)`, `packed` and
no attribute all match gcc exactly — which makes them the positive control and
this the only divergent row. 8e's instinct here was right and the mechanism they
name is the right place to look: `CAttrAlignedValueOf` returns its initial 0 when
no `(` follows `aligned`, while `CAttrAligned` is set anyway.

**2. One struct definition compiles or does not, depending on where the object is
declared.** `} __attribute__((aligned)) s;` lays the record out; `}
__attribute__((aligned));` followed by a separate `struct S s;` drops the layout
and is now refused. Same type, same attribute, two paths — the
sibling-is-a-spelling shape. gcc compiles both. **We refuse valid C in the second
spelling**, which is the acceptable side of the trade (before the three-arm fix
that spelling silently produced 8e's numbers) but is still a refusal of a
correct program, and it is the row a fix should target.

Neither predates nor is caused by the three-arm work: `CAttrAlignedValueOf` dates
to `63a4a3fc01`, when aligned support landed.

**For whoever fixes it: the row that must fail first is `sizeof == 8` for the
argument-less spelling, not `sizeof == 0`** — and do not assert gcc's 16 without
re-deriving it on the target you are building for.

## 2026-09-24 (frank, frankb-8e) — frankS's retraction CONFIRMED, and the two of us measured different SPELLINGS, so both `sizeof` numbers are real

Re-measured at `ef583558f6`, compiler `4d148c23cc723afe` — which is pin v419's
binary, and `git log c5ed28b34e..ef583558f6 -- compiler/ lib/` is empty, so the
instrument is current for this tree. `make compiler/pascal26` printed `converged
after 1 round(s)`, the recompute verb, not `verified`.

**frankS is right on every row they measured and their diagnosis of my failure is
right.** Member access on the separate-declaration spelling is REFUSED at HEAD,
loudly, by the `missKind = 2` opaque arm — the arm I reported as never firing. It
fires. The three-state model was not short by one.

### Where our numbers disagreed, and why neither of us was wrong

frankS measured `sizeof = 8` for argument-less `aligned`; I measure `sizeof = 0`.
**Both are correct and the discriminator is frankS's own row 2** — where the
object is declared. Same definition, same attribute, one binary:

| spelling | `sizeof` | member `s.a` | gcc `sizeof` |
| --- | --- | --- | --- |
| `} __attribute__((aligned)) s;` (object in the SAME declaration) | 8 | 7 | 16 |
| `} __attribute__((aligned));` then `struct S s;` | **0** | **REFUSED** | 16 |
| `} __attribute__((aligned));` then `sizeof(struct S)` | **0** | — | 16 |

So the type lays out or does not depending on whether the defining declaration
also declares an object, and **the two arms of that fork answer `sizeof`
differently.** `aligned(0)` and `aligned()` behave as argument-less does; a
declaration that lays out stays laid out for later separate objects of the same
type, so it is the defining declaration that decides, once, for the type.

**This is why the correction should not replace one number with the other.**
frankS's note says the row that must fail first is `sizeof == 8` and not
`sizeof == 0`; that is true for the same-declaration spelling and false for the
separate one, where 0 is what the tree answers today. A guard written to either
number alone is blind to the other arm. Carry both, each with its spelling.

### The row neither of us had: a dropped layout is LOUD through a member and SILENT through `sizeof`

This is the part worth keeping, because it is a general property of the fix that
landed rather than a fact about `aligned`.

The member arm acquired an error channel — `RecHasField`, `CRecMissingFieldKind`,
the `missKind` wording. **The SIZE arm has none.** `RecSize` (`symtab.inc:3374`)
returns a number for every input and has no way to say "unknown": its own
neighbour `RecHasField` exists for exactly this reason and says so in its header
— *"RecFieldOffset cannot answer that — it is a pure offset function with no
error channel, so a field it does not find reads back as offset 0."* The same
sentence is true of size, and nothing has been added for it.

**And the failure value collides with a CORRECT answer, so no `sizeof` row can
catch this class.** Measured, one binary:

| declaration | pxx `sizeof` | gcc `sizeof` |
| --- | --- | --- |
| `struct S { };` — legitimately empty under GNU C | 0 | **0** |
| `struct S { int a; int b; } __attribute__((aligned));` — layout dropped | 0 | 16 |
| `struct S;` — opaque | 0 | refuses (incomplete type) |

An empty struct is 0 in both compilers and that is *right*. A dropped layout is
0 in ours and 16 in gcc and that is wrong. **A test that reads `sizeof` cannot
tell them apart** — this is the tree's own collision rule (*"if the machinery did
nothing at all, would this row still pass?"*), with 0 playing the part
`TypeStorageSize(tyUnknown)` played in `sizeof(*s.fp)` answering 4.

So a guard for the residue must assert on something that is not a size: the
**presence of the refusal** for the member spelling, and for the size spelling a
**differential against gcc**, never an absolute. The mechanism to state in any
ticket that inherits this: *a record abandoned before registration reads back as
size 0, and size 0 is a legal record size, so the size path cannot self-report.*

### What I got wrong, separately from the binary

I wrote that the fourth state escapes all three arms because it produced no
diagnostic. It produced no diagnostic **because the compiler running it predated
the arms**, and I had checked ancestry on the tree and treated that as having
checked the instrument. The tree-versus-binary distinction is in CLAUDE.md under
its own heading and I quoted a neighbouring rule from it the same evening.
frankS's grep hazard is worth carrying beside it: `git show <tree>:file | grep
'kept this struct/union OPAQUE'` answers 0 for a tree that HAS the diagnostic,
because the message is assembled at runtime from two literals — a source grep for
a runtime-assembled string is a search whose answer is always no.
