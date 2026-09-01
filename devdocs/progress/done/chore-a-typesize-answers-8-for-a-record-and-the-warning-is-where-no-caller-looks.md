---
track: A
prio: 45
type: chore
blocked-by: []
summary: "RESOLVED. TypeSize renamed to TypeSlotSize (371 sites) and the question it does not answer named: TypeStorageSize(tk, recId). The rename exposed two live misuses in rtti_emit.inc -- a record FIELD of type `array of TRec` emitted a dyn-array descriptor elSize of 8 for every unmanaged element type. ir_codegen.inc had fixed the same conditional in 1b9bf814c (2026-06-15) without grepping for the sibling. Latent, not observed: no reader of that slot for baseKind=0 could be constructed. The concept was written out by hand 20 times; 18 collapsed into the new helper, byte-identical output 7/7."
status: done
owner: ""
---

# `TypeSize` answers 8 for a record, and the warning is where no caller looks

## The confirmed instance

`compiler/symtab.inc:2817`:

```pascal
    5: Result := 8;  { tyRecord — caller must use RecSize() for full record size }
```

The Rust frontend sized a monomorphized generic's payload with `TypeSize`, so
`Option<T>`'s union was **8 bytes wide regardless of T**. Wrong since `Option`
was written, and it survived eleven rungs because the only record it ever held
was `Option<Square>` and `Square` is a one-field tuple struct — **exactly 8
bytes**. Measured against the shipped file, not argued:

- `Option<Big>`, `Big` = four `i64` → **SIGSEGV**
- `Result<Pos, i64>` → `Pos { file: 4, rank: 2 }` reads back as **`4 0`**

Fixed in Track R by an `RPayloadSize`/`RPayloadAlign` pair, both pinned in
`test_rust_result.rs`. **The `4 0` is the dangerous half** — the segfault
announces itself; a `rank` that landed outside the value and a `file` that did
not gives a plausibly-wrong table.

## What this ticket is NOT

**Not a list of 319 defects.** `grep -c 'TypeSize('` over `compiler/*.inc` gives
**319** call sites — 46 in `cparser.inc`, 42 in `pyparser.inc`, 23 in
`pasparser_expr.inc`, 8 in `rparser.inc`, 6/2/2 elsewhere. The overwhelming
majority are correct: `TypeSize` is right for every kind except `tyRecord`, and
most call sites cannot see a record at all.

A call is wrong only when **both** hold: the operand can be `tyRecord`, *and* the
result is used as a full storage size (allocation, copy width, field offset,
union width) rather than as a machine-word/pointer size.

Filing per-site tickets from a grep would reproduce the phantom-bug pattern
`chore-t-lint-fall-open-target-chains-without-the-false-positives` was filed to
avoid: a candidate list wearing a defect-shaped format, which the board cannot
later distinguish from findings. **Inspect before filing.**

## The actual defect is the placement of the warning

The comment is correct, precise, and **on the callee's return-value line**. A
caller writing `TypeSize(tk)` in `rparser.inc` never sees it. The one reader who
needs the warning is the one place it is not.

**Preferred fix, in order:**

1. **Make it unrepresentable.** Rename to `TypeSizeWord` / `TypeSizeScalar`, or
   have the record arm return a value that cannot be mistaken for a size, so the
   caller is forced to ask. A name is read at every call site; a comment is read
   at none.
2. Failing that, a lint that flags `TypeSize` applied to an operand whose kind
   can be `tyRecord` — the classification above is the spec, and the false
   positives are the hard part, so record the inspected/total ratio like
   pxx-a5's sweep did rather than emitting a raw candidate list.
3. Failing that, put the warning in `frontend_forwards.inc` beside the
   declaration, where a caller plausibly looks.

## Cross-frontend note

Track R found this in its own file and fixed it there. **Whether C, NilPy, Zig or
Pascal hold the same misuse is UNKNOWN and explicitly not asserted here** — the
sweep has not been done, and 319 unexamined sites is not evidence in either
direction. Each frontend owns its own call sites; a shared fix to `TypeSize`
itself is Track A's.

## Resolved — 2026-09-01, Track A (frankA)

Fix 1 of the ticket's own preference order ("Make it unrepresentable. Rename")
plus the thing the rename exposed while doing it.

### The rename

`TypeSize` → **`TypeSlotSize`** — 371 occurrences, 26 compiler files. The word
boundary excludes `CTypeSizeBytes` and `PSpoofInterfacedTypeSizeObject`, checked
before the edit. Vendored FPC sources under `library_candidates/` (a `TypeSize`
*parameter* in `typefile.inc`/`compproc.inc`) and the historic docs under
`devdocs/developer/historic/` were deliberately left alone.

The name now states the scope the comment used to state where nobody read it:
it is the **slot** size, the machine word a value is passed and held in.

### The question it does not answer now has a name

```pascal
function TypeStorageSize(tk: TTypeKind; recId: Integer): Integer;
```

Bytes one VALUE occupies in an array or aggregate — the stride. `RecSize(recId)`
for `tyRecord`, `TypeSlotSize(tk)` otherwise. `RecSize(REC_NONE)` is 8, so a
caller with no meaningful recId gets exactly the old answer and does not have to
know whether its recId is real.

### The ticket asked whether other frontends hold the same misuse. Two do.

The ticket says this is "UNKNOWN and explicitly not asserted here". It is now
known for one concept — dynamic-array element size — and the answer is that the
concept was written out by hand **20 times** across `ir.inc`, `cparser.inc`,
`ir_codegen.inc`, `pasparser_expr.inc`, `pasparser_decl.inc`, `rparser.inc` and
`rtti_emit.inc`, as:

```pascal
if tk = tyRecord then sz := RecSize(rec) else sz := TypeSlotSize(tk);
```

**Eighteen had the record arm. Two did not** — `rtti_emit.inc`, twice, ~120
lines apart, in the descriptor emitted for a record FIELD of type
`array of TRec`. Those two wrote `elSize = 8` for every unmanaged element type,
whatever its real size.

`ir_codegen.inc` got the missing arm in **1b9bf814c** (2026-06-15) with a comment
spelling out the consequence — element 1 overruns into adjacent heap. That commit
changed one file. The siblings in `rtti_emit.inc` were never grepped for and sat
wrong for 2.5 months. This is the case CLAUDE.md's *"fixed one arm of a double
case? grep for the sibling before closing"* is written about; the sibling was two
files away and the grep would have found it.

### How the two sites were found — the measurement, not the reading

Poison-and-diff. Replace the record arm of `TypeSlotSize` with a sentinel
(`12345`), rebuild, byte-diff emitted output against the clean compiler. Exactly
one 4-byte slot moves, which names the reachable site instead of arguing about
it. Then, before and after the fix, on identical sources:

| program | elSize slot |
| --- | --- |
| record field `array of TBig`, TBig = 4×Integer | `8` → **16** |
| record field `array of TBig`, TBig = 5×Integer | `8` → **20** |
| program with no record-field dyn array (control) | 0 bytes differ |

**The first probe was immune by coincidence** and nearly ended the search: a
2-Integer record is exactly 8 bytes, so the wrong constant was the right answer.
The bug only appears once the element is not pointer-sized.

### Reachability — stated as narrowly as it was checked

**I could not construct a consumer, and I am not claiming a user-visible fix.**
Every read of a Kind=2 descriptor's `+4` in `builtinheap.pas` was traced:

- the release paths read `baseRecDesc + 4` only under `baseKind = 3`, where it is
  the base record's own Kind=1 descriptor — a different field at the same offset;
- `PXXDynArrayUnique` does read `desc + 4`, but its only emitter,
  `EmitDynArrayUnique` (`ir_codegen.inc`), passes `GetOrAllocSymRTTI(symIdx)` —
  a **symbol** descriptor, whose elSize comes from a site that already had the arm;
- `SetLength`, record copy and copy-on-write on 16- and 20-byte elements match
  FPC 3.2.2 exactly, before and after.

So: a wrong value in a slot that today has no reader for `baseKind = 0`. Latent.
That it is unread is a fact about today's RTL, not about the value being right.

### Then the root cause, since 20 copies is the defect

The 18 correct copies are the reason the 2 wrong ones were invisible — nothing
compares them. Collapsed **18 of the 20** to `TypeStorageSize`; the two left are
mid-`else if` chains with a `FrozenStrSlotSize` arm interleaved, where the
collapse would drop an arm. (The first attempt did exactly that and produced
code that would not compile — caught by reading the diff, not by the build.)

Control for a pure refactor: emitted output must not move. **7 of 7 programs
byte-identical**, with a positive control confirming the comparison can fail
(two different programs compare unequal).

### What is still open

- The remaining 2 interleaved sites, and 8 more `else if`-chained ones that the
  collapse skipped by design. None of them is wrong today; they are the places
  where copy 21 would go wrong.
- The ticket's option 2 (a lint) is now unnecessary for this concept and remains
  open for others: `TypeSlotSize` still has ~350 call sites, and the argument
  that most are legitimate is unchanged.

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.
