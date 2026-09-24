---
slug: bug-c-a-struct-tag-is-not-scoped-to-its-block
track: C
type: bug
prio: 50
status: open
owner: ""
created: 2026-09-24
found-by: frank (frankb-8e, running the shard the range attribution said was already green)
blocked-by: []
summary: "MECHANISM: a C struct/union TAG is registered globally rather than in the scope that declares it, so an inner `struct T {...}` does not SHADOW an outer `struct T` -- it collides with it, and every member reference in the inner scope is resolved against the OUTER type. Standard C scopes a tag to its enclosing block (C11 6.2.1p7); gcc compiles all rows below. TWO OBSERVABLE CLASSES FROM ONE CAUSE, and the second is silent: where the inner type's member NAME is absent from the outer type the access is REFUSED (`no member named 'y' in this struct/union`), and where the name is PRESENT it resolves at the OUTER type's offset -- so a member that happens to line up gives a plausible right answer and one that does not gives a plausible wrong one. `sizeof(struct T)` inside the inner scope answers the OUTER type's size with no diagnostic at all (4 against gcc's 8). THIS IS NOT A REGRESSION AND MUST NOT BE FILED AS ONE: it is what reddened test-c-conformance#shard4/6 on x86-64 and on all four cross targets, but the refusal arrived from the member-refusal fix that correctly replaced a silent offset-0 read, and the corpus test it reddens (00053.c) was PASSING FOR THE WRONG REASON -- both its structs have a single member at offset 0, so the mis-resolved `s2.y` read `s1.x`'s slot and `s1.x - s2.y` came out 0. A correct fix unmasked an older bug; the five red rows are ONE cause, identical on every target because a frontend refusal is target-independent. THE CONDITION THAT SPRINGS IT is any tag reused in a nested scope -- a block-local struct in a function that also has a file-scope tag of the same name, which is ordinary in C where short tags like T, node, entry or pair recur. Reuse with an IDENTICAL member set is invisible, which is why this survived: the shapes that work and the shapes that break differ only in whether the two definitions agree. WHAT WOULD RETIRE IT: 00053.c passing unskipped on x86-64 and all four cross targets, plus the three-row control -- the same-tag-same-member row still answering 1 2 (it works today and must keep working), `sizeof` in the inner scope answering the INNER size, and `struct E { };` still answering 0 and NOT being refused, which is a legal GNU extension and the row most likely to be left out. RELATED: the silent `sizeof` half is a second independent instance of the size path having no error channel -- see [[bug-c-an-undeclared-struct-type-compiles-and-reads-garbage]], where RecSize (symtab.inc:3374) returns a number for every input and 0 is simultaneously correct for an empty struct and wrong for a dropped layout. Two unrelated causes now reach a wrong size silently, which makes the missing error channel the shared defect rather than either cause."
---

# A C struct tag is not scoped to its block

Measured 2026-09-24 at tree `0070fda846`, compiler
`4d148c23cc723afe` (pin v419's binary; `git log ... -- compiler/ lib/` empty
between the two, so the instrument is current for this tree).

## How it was found, which matters because two of us had predicted the opposite

`test-c-conformance#shard4/6` went NEW-RED on x86-64 and on all four cross
targets. Two seats independently attributed it to a range and recorded *"very
likely green at HEAD, explicitly NOT CONFIRMED"* — the reasoning was that the
refusal of valid C introduced at `134d68dfe3` was corrected six minutes later by
`690d3859ff`, which is an ancestor of HEAD. Both of us said out loud that it
would only harden into a verdict if someone ran a shard.

**Someone ran a shard. It is still red, and the range attribution was wrong.**

```
tools/run_c_conformance.sh ./compiler/pascal26 <suite> --shard 4/6
  35 pass, 1 fail, 0 skip (of 36)
  FAILURES: 00053.c(compile)
```

Identical on `--target i386`. The failing diagnostic is the member-refusal
wording, so the refusal *is* from that work — and the refusal is **correct**.
What is wrong is older than both commits.

## The corpus test, and why it used to pass

`00053.c`, in full:

```c
int main()
{
	struct T { int x; } s1;
	s1.x = 1;
	{
		struct T { int y; } s2;
		s2.y = 1;
		if (s1.x - s2.y != 0)
			return 1;
	}
	return 0;
}
```

Two distinct types sharing a tag in nested scopes. pxx resolves `s2.y` against
the **outer** `struct T`, which has no `y`.

**Before the member-refusal fix this test passed, and it passed for the wrong
reason.** Each struct has exactly one member, so both sit at offset 0; the
mis-resolved `s2.y` read `s1.x`'s slot, `1 - 1` came out `0`, and the program
returned 0 as the oracle expects. The test could not distinguish correct tag
scoping from no tag scoping at all, because the only arrangement it exercises is
the one where the wrong answer and the right answer coincide — this tree's own
expected-value collision, sitting in an upstream conformance suite.

## The boundary, measured, one binary

| construct | pxx | gcc |
| --- | --- | --- |
| inner tag redefined, **same** member name | `1 2` | `1 2` |
| inner tag redefined, **different** member name | **REFUSED** | `1 2` |
| inner tag, member at a **different offset** | **REFUSED** | `1 2 3` |
| `sizeof(struct T)` in the inner scope (outer 4, inner 8) | **4**, no diagnostic | **8** |
| file-scope tag, inner redefinition | **REFUSED** | `5` |

Row 1 is the positive control and it is the one that makes this class survive:
**reuse with an identical member set is invisible.** The shapes that work and the
shapes that break differ only in whether the two definitions agree, which is why
neither the corpus nor any local test caught it.

Row 4 is the silent one and it is the worse half — no diagnostic, a plausible
number, and it is not fixed by anything that only guards member access.

## Two classes from one cause

- **Member name absent from the outer type → REFUSED.** Loud, and only loud
  since the member-refusal fix. Before it, this was a read at offset 0.
- **Member name present in the outer type → resolved at the OUTER offset.**
  Silent. Right answer when the layouts happen to agree, wrong when they do not.
- **`sizeof` → the outer type's size.** Silent, always, and unguarded.

## Relationship to the size-path finding

Row 4 is a **second, independent cause** reaching a wrong size with no
diagnostic. The first is in
[[bug-c-an-undeclared-struct-type-compiles-and-reads-garbage]]: `RecSize`
(`symtab.inc:3374`) returns a number for every input and has no way to say
"unknown", exactly as its neighbour `RecHasField`'s header says of
`RecFieldOffset`. Two unrelated causes now arrive at the same silent wrong size,
which argues the missing error channel is the shared defect rather than either
cause — and a guard for it cannot read an absolute size, because 0 is
simultaneously correct for `struct E { };`, wrong for a dropped layout, and
something gcc refuses for an undefined tag.

## Fixing it

Not attempted here, and the reason is coordination rather than difficulty: this
is the C lane's scoping model, the lane owner has deliberately stopped after one
self-inflicted regression in this same code path tonight, and a tag scope stack
is a structural change rather than a patch. The machinery to distinguish the
states already exists — `UClsBodySeen`, `UClsLayoutDropped` and
`CRecMissingFieldKind` — so what is needed is a scope level on tag registration
and lookup, not a new distinction.

**The census is the part that needs doing properly.** Tag lookup runs for every
struct in every C program, so a change here has the same false-positive exposure
the member-refusal fix measured before landing (17,043 resolving accesses across
zlib and `lib/crtl/src`, zero failing). Use that population, not busybox or
sqlite — neither parses per-file in this tree, and a sweep of busybox answered
0-of-0 without saying so.

**Three controls, and the third is the one most likely to be omitted:**

1. the same-tag-same-member row keeps answering `1 2` — it works today;
2. `sizeof` in the inner scope answers the **inner** size;
3. `struct E { };` still answers **0** and is **not** refused — a legal GNU
   extension, and the row a size-path guard eats first.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]

## 2026-09-24 (frankS) — the SITE, measured: the inner body is swallowed by the REDEFINITION GUARD, which exists to prevent a documented SIGSEGV

Confirming the report independently, and adding the mechanism one level down —
**the inner definition is not merely mis-resolved, its body is never parsed at
all.**

`compiler/cparser.inc`, the bare `struct Tag { ... };` path:

```pascal
if hasTag and UClsIsRecord[ci] and (UClsFCount[ci] > 0) then
  { REDEFINITION of an already-laid-out tag ... Keep the first definition;
    skip the duplicate body. }
  SkipBraceBlock
```

`FindOrForwardCTag` returns the OUTER tag's record, that record already has
fields, so the guard fires and the inner body is discarded.

**The discriminator, which is what makes this the site rather than a plausible
story: the guard only fires when the outer tag ALREADY HAS FIELDS.** So a
forward-declared outer tag should let the inner definition lay out normally.
Predicted 4 and 8; measured 4 and 8:

| outer declaration | inner `sizeof(struct T)` | gcc |
| --- | --- | --- |
| `struct T { int x; };` (1 field — guard fires) | **4** | 8 |
| `struct T;` (forward, 0 fields — guard does not fire) | **8** | 8 |

### The warning, and it is the reason this is worth a section

**That guard is correct and must keep working.** Its own comment records why it
exists: re-running `ParseCStructInto` on a populated record re-lays its field
base and misfiles a following struct's members into the old range, **producing a
self-referential record that hangs `RecordHasManagedFields` (SIGSEGV)**. It was
added for a real case — a host header leaking in and redefining a crtl-defined
struct, e.g. `struct in_addr` from both crtl and a host `netinet` include.

So the two cases are **indistinguishable at that site today**: an illegal
same-scope redefinition (where keeping the first definition is right) and a
legal inner-scope shadow (where a second record must be created). A fix that
weakens the guard to let the inner body parse will reintroduce the crash the
guard was written for. **The tag scope stack is what separates them** — with
scoping, the inner definition is a different tag entry and never reaches the
redefinition test at all, which is why the structural fix is also the safe one
and a local patch here is not.

**Add to the controls: a same-scope duplicate definition of a tag that already
has fields must still take the guard** (keep the first definition, no crash, no
second record). That row is the guard's own positive control and is not in the
three listed above.
