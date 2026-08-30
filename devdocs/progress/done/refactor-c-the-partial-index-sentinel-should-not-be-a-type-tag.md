---
track: C
prio: 40
type: refactor
blocked-by: []
summary: "cparser's partial-index builder marks 'this add is raw bytes, do not scale' by RETAGGING its base ASTTk to tyInt64 — a type tag used as a flag. tyInt64 is also the honest element tag of a `long long` array, and that collision cost a real bug."
status: done
owner: frankC
---

# The partial-index sentinel should not be a type tag

- **Track C** (C frontend).
- Filed 2026-08-20 out of
  [[bug-c-pointer-difference-on-a-long-long-element-type]], where the collision
  produced a silent wrong stride.

## What it is

`ParseCPostfixTail`'s partial-index arm (`m[1]` on `int m[3][4]`) builds a raw
byte add and marks the base so nothing scales it a second time:

```pascal
ASTTk[baseFld] := Ord(tyInt64);   { "raw 64-bit add, no pointer-stride scale" }
```

That is a **flag written into the type field**. tyInt64 is also the perfectly
honest element tag of `long long a[8]`, so a reader cannot tell "I am a
deliberately unscaled byte base" from "I am a signed 64-bit array".

## What it cost

`IRNodePointerBase` read the tag the sentinel way and bailed on tyInt64
outright. A signed 64-bit array was therefore never a pointer base: `a + 1`
stepped one byte, `q - p` answered 0, and `unsigned long long` — a different
tag — was correct. A sign bit decided a stride, silently.

The fix in place disambiguates by asking whether the node's DECLARATION explains
the tag (a fixed-extent, single-dimension array whose element type really is
tyInt64 carries it honestly). That is correct and it is a second reading of an
overloaded field, which is the thing worth removing.

## Sketch

Carry the "already byte-scaled" fact somewhere that means only that:

- an `ASTSLen`-style stamp, which the AN_BINOP arm of `IRPointerStride` already
  uses for exactly this family (`bug-c-a-multidim-array-decays-with-the-element-stride`
  — this ticket cited it as `bug-c-a-decayed-array-row-steps-one-byte`, a slug
  that does not exist; the same dangling citation was in `ir.inc` and is fixed), or
- a dedicated AST node kind for a decayed row, which would also give
  `CNodePointeeTk` something to key on instead of its walk-left-to-the-ident
  heuristic.

Then `IRNodePointerBase` loses its special case and `CNodePointeeTk` loses one
too. Two readers simplify, which is the measure worth using.

## Not urgent

The current disambiguation is tested from both sides — `carr2d_decay_stride.c`
pins the sentinel reading and the pointer-difference test pins the honest one —
so this is a clarity/robustness refactor, not an open defect.

## Gate

C tests green + self-host byte-identical; both tests above still pass, and the
tyInt64 special case in `IRNodePointerBase` is gone rather than moved.

## Ownership: this needs the Track A slot, not just Track C — 2026-08-29 (frankC)

Checked before claiming, dispatched to frankC and handed back. Same fork and
same answer as [[refactor-c-string-literal-decay-belongs-at-the-producer]], so
recording it here too rather than making the next agent derive it a third time.

The file map:

| symbol | file | lane |
| --- | --- | --- |
| `ParseCPostfixTail` (writes the sentinel) | `compiler/cparser.inc:3696` | C |
| `CNodePointeeTk` (reads it) | `compiler/cparser.inc:2051` | C |
| `IRNodePointerBase` (reads it) | `compiler/ir.inc:2348` | **A** |
| `IRPointerStride` (reads the stamp) | `compiler/ir.inc:2390` | **A** |

**The gate line requires the A file by construction:** *"the tyInt64 special
case in `IRNodePointerBase` is gone rather than moved."* That special case IS
the refactor — the `cparser` half only changes how the fact is written down.

**Neither sketch option escapes it.** The `ASTSLen`-style stamp is read by
`IRPointerStride`'s AN_BINOP arm in `ir.inc`, so `IRNodePointerBase` has to be
re-keyed onto it there. The dedicated-AST-node option is *worse* for Track C,
not better: CLAUDE.md names a new AST node as a Track A ticket you file, not
code you write.

**Do not land the cparser half alone.** It would write the sentinel twice — the
type tag AND the new marker — with A's reader still keyed on the tag, which is
strictly worse than today's single overloaded field.

`track:` stays `C`: it is a C-frontend defect and belongs in C's queue for
visibility. But whoever takes it must hold Track A or confirm no one else is in
`ir.inc`. Nothing was started and no code was touched.

Instance five of
[[refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed]],
and the sharpest one: this ticket was dispatched *specifically* because it
looked disjoint from A's files, and it collided anyway. Five of the seven ready
Track C tickets now need A's ground, because the ~40 `CProgramMode` sites in
`ir.inc` have no `cir.inc` to live in.

## DONE — 2026-08-29 (frankC), and it was not a clarity refactor

Took the `ASTSLen`-stamp option, not the dedicated-AST-node one. The stamp
already existed and `IRPointerStride` already read it; the sentinel was a
second, lossy copy of the same fact.

**What changed**

| file | change | lane |
| --- | --- | --- |
| `cparser.inc` | the three builders stop retagging their base `ASTTk := Ord(tyInt64)` | C |
| `cir.inc` | new `CNodeIsDecayedRow` — the one reader of the marker | C |
| `ir.inc` | `IRNodePointerBase`'s tyInt64 block **deleted**; `IRPointerStride`'s AN_BINOP arm and the three pointer-arith arms consult the predicate | A (granted) |

There are **three** builders, not the two the ticket describes: the array
partial index, the struct-field partial index, and the no-op deref of a
pointer-to-array (`CDerefDecayStride`'s arm). All three retagged; all three now
stamp only.

The gate line's requirement — *"the tyInt64 special case in `IRNodePointerBase`
is gone rather than moved"* — is met literally: that function is now four lines
and asks the declaration and nothing else.

`CNodePointeeTk` is untouched. The ticket expected it to lose a special case
too, but it never read the sentinel — its AN_BINOP arm walks left to the ident.
(It has its own gap, filed below.)

## It closed two live silent wrong values

The ticket called this "a clarity/robustness refactor, not an open defect,"
because both readings were pinned by tests. Both readings were pinned; the
shapes the whitelist did not reach were not. Measured against gcc:

| expression | gcc | pxx before |
| --- | --- | --- |
| `(char*)(m+1) - (char*)m`, `long long m[3][4]` | 32 | **1** |
| `*(s.v+3)`, `long long v[8]` as a struct FIELD | 3 | **0** |

Same root as `bug-c-pointer-difference-on-a-long-long-element-type`: the patch
for that one whitelisted the single shape that carries tyInt64 honestly — a
fixed-extent, **1-D**, **AN_IDENT** array — so a 2-D one and a FIELD one were
never pointer bases at all. `unsigned long long` (a different tag) was right
throughout, which is the same tell as the original: a sign bit deciding a
stride. Regression: `test/cll_array_pointer_base.c`.

*The lesson worth keeping is about the ticket, not the code: "both readings are
tested, so this is cosmetic" was measured on the two shapes someone had already
thought of. The overloaded field was still costing wrong answers the whole
time.*

## Gate

- `make compiler/pascal26` — `converged after 1 round(s)`.
- Named C differential, pre/post, sha256 of each binary: **42 of 43
  byte-identical, zero output changes**. The one that moved is
  `carr2d_decay_stride` — the test this ticket names as pinning the sentinel
  reading — and it moved 88 bytes SMALLER with identical output. Isolated to
  five no-op-deref expressions, 11 bytes each: the old code let the
  pointer-arith arm fire on `(m+1) + 0` and emitted a multiply of a literal
  zero by the stride. Dead code, now not emitted.
- A 219-test pre/post differential over every C test whose name touches
  pointers, arrays, strings, structs, casts, initialisers or varargs.
- gcc oracle for every expression whose behaviour legitimately changed.

**Two measurement corrections on myself, both the same error.** I first
"confirmed" the machine code was identical from an `objdump -d` diff — pxx
emits section-less ELF, so objdump produced three lines of header and I diffed
two empty files. I then "confirmed" it again from a `--dump-ir` diff, and
`--dump-ir` changes codegen: both sides came out at the pre-refactor size. Two
clean, agreeing runs of two methods that each measured nothing. What answered
it was the compiler's own `code=` line at a fixed output path.

## Filed from here

- [[bug-c-a-multidim-array-field-decays-with-the-element-stride]] **[prio 75]**
  — found writing the regression test, then widened by probing the pattern
  instead of the instance. Four readers of a decayed array each split
  AN_IDENT / AN_FIELD, and the FIELD arm is unfinished in all four:
  `(char*)(s.m+1)-(char*)s.m` on `int m[3][4]` answers 4 for gcc's 16; `*a.s[1]`
  on a `char s[2][8]` field loads four bytes; and `**a.s`, `*(*(a.m+1)+2)`,
  `strcmp(*(a.s+1),"cd")` and two more **segfault**. Every array-spelled twin
  is correct and already has a passing assertion in `carr2d_decay_stride.c`.

  Worth stating plainly, because it is the reusable part: the first probe
  returned one wrong number, and probing the *pattern* rather than the instance
  turned it into five crashes on ordinary C. Three field-arm defects had already
  been found and fixed on this same day, each as a one-off. Nobody had asked
  what the shape was.

## Log
- 2026-08-30 — resolved, commit 72de20420.
