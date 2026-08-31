---
track: A
prio: 45
type: chore
blocked-by: []
summary: "TypeSize(tyRecord) returns 8, and the warning that a caller must use RecSize() for the full size lives on the return-value line INSIDE symtab.inc, where no caller reads it. One confirmed misuse cost a SIGSEGV and a silently-wrong value in the Rust frontend. There are 319 TypeSize call sites across compiler/**; most are legitimate. This is a classification problem, not a defect list — do not file 319 tickets."
status: backlog
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
