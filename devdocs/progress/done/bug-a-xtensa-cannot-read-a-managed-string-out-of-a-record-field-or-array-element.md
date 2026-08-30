---
track: A+S
type: bug
prio: 45
status: done
found: 2026-08-30
found-by: frankS
---

# Reading an AnsiString out of a record field or array element is broken on xtensa

Storing a managed string into an aggregate and reading it back gives garbage.
riscv32 and x86-64 are both correct; this is xtensa-only.

## Repro

`--target=xtensa --platform=posix --xtensa-soft-mulhigh`, Call0, qemu-xtensa.

```pascal
program t; type R = record f: AnsiString; end;
var r: R; begin r.f := 'ABCDE'; WriteLn(r.f); end.
{ x86-64: ABCDE    riscv32: ABCDE    xtensa: <empty line> }

program t; var a: array[0..2] of AnsiString;
begin a[1] := 'ABCDE'; WriteLn(a[1]); end.
{ x86-64: ABCDE    riscv32: ABCDE    xtensa: <empty line> }

program t; type R = record f: AnsiString; end;
var r: R; begin r.f := 'ABCDE'; WriteLn(Length(r.f)); end.
{ x86-64: 5        riscv32: 5        xtensa: 1936482630 }
```

## It is NOT a `Length` bug, and that is the useful part

The obvious reading of the third case is that `Length` mishandles a field
operand — it is the one that looks like the arm-specific defects fixed in
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]. It is
not. Copying the field to a plain local first:

```pascal
r.f := 'ABCDE'; x := r.f; WriteLn(Length(x));   { xtensa: 1936482630 }
```

is wrong the same way, and `WriteLn(r.f)` — no `Length` anywhere — prints
nothing. **The value read out of the aggregate is already wrong before anything
is done with it.** Suspect the field/element load or store of a `tyAnsiString`,
not the consumers.

`1936482630` is `$736F5F46`, bytes `46 5F 6F 73` = `"F_os"` — a pointer into
rodata or a fragment of one, not a heap handle and not a length. Whatever the
load produces, it is not the handle that was stored.

## Where to start

`IR_FIELD` on xtensa is `IREmitNodeXtensa(base)` plus a constant add — it yields
an ADDRESS and never derefs, which matches riscv32. So the divergence is more
likely in the managed store (`store_mem` of a tyAnsiString through a field
address, including whether it retains) or in the load position that follows it.
Compare against riscv32's `IR_STORE_MEM`/`IR_LOAD_MEM` handling for
`tyAnsiString` rather than against its `IR_FIELD`, which is the same.

## Scope

Blocks at least `test_cross_managed_aggregate_locals` and
`test_cross_openarray_string` in
[[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]], and is a
plausible cause for the two interface tests there (an interface's fields are the
same shape). Filed separately from that ticket because it has a single crisp
repro and they do not.

## Bound

Object-level plus observable output, hosted profile, Call0, at `3bc9a9303267`,
compared directly against riscv32 and x86-64 built from the same source.
Windowed not checked — it faults earlier for unrelated reasons
([[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]]).

---

## ROOT CAUSE — the store, and it was three stores, not one. frankS, 2026-08-30

The ticket's own guess was right and understated. Measured first, by reading the
field's raw slot and then `[handle-8]`:

| target | slot | `[slot-8]` |
| --- | --- | --- |
| x86-64 | nonnil | 5 |
| riscv32 | nonnil | 5 |
| **xtensa** | nonnil | **1936482630** |

So the slot held a **raw literal buffer address, not a managed handle** — the
store is wrong, not the load, and no amount of work on `Length` or `IR_FIELD`
would have found it.

`IR_STORE_SYM` has dispatched on the destination TYPE since managed strings
landed. **`IR_STORE_MEM` — the same store reached through an ADDRESS, which is
how every record field, array element and deref is written — had no type
dispatch at all** on xtensa: a 64-bit branch and then a raw sized word store.
Three type classes need more than a word copy and all three were silently wrong
through an aggregate:

| | shape | what actually landed in the destination |
| --- | --- | --- |
| managed | `r.f := 'lit'` | the rodata ADDRESS; `Length` read `[addr-8]` |
| frozen | `r.g := 'lit'` | the source address, where `[len][chars]` belongs |
| float | `r.d := i` | the integer bits, in a `Double` field |

Every other backend has all three; riscv32 has them adjacent in this same node,
which is how one probe found all three.

### Why it survived: the working spellings are the common ones

`r.f := s` and `r.f := s + 'x'` were always **right**, because in those two
shapes the raw source word already IS a handle. Only a literal, a char or a
frozen source exposes it. This is the third instance tonight of the same
sentence — see [[why-xtensa-was-the-holdout]] — and the one before it,
`ABIParamSlotHoldsValueAddr`, had exactly this structure too.

### The float row was measured, not inferred

It was added on riscv32's evidence, and the probe that suggested it faulted
somewhere else entirely: **`WriteLn` of a `Double` SIGBUSes on xtensa for a
plain local**, no aggregate involved — a separate defect that masked this one.
Measured instead by reading the field's raw bits back as an `Int64`, and
confirmed load-bearing by **ablation**: branch off, `r.d := i` leaves `hi=0
lo=7`; branch on, `hi=1075576832 lo=0` = `$401C0000_00000000` = 7.0, matching
both oracles. That `WriteLn(Double)` fault is filed separately.

### Fixed by sharing, not copying

Two helpers lifted out so both stores use one body:
`EmitStrHandleForStoreXtensa` (the four handle-producing source shapes, was
inline in `IR_STORE_SYM`) and `EmitFrozenCopyXtensa` (the frozen `[len][chars]`
copy against a destination ADDRESS — it was inline against a symbol *slot*,
which is precisely why the address-reached path had nothing to call).

### Bound

Hosted profile, Call0, `--xtensa-soft-mulhigh`, binary `915121e5d0e9`, against
the x86-64 and riscv32 oracles built from the same source. The 9-case store
matrix went 9/9 wrong-or-crashing to 9/9 identical. The 142-source differential
went **57 match / 19 differ → 63 / 13**, cfail set unchanged at 66, **zero
regressions**; newly green: `test_cross_dynarray`,
`test_cross_managed_aggregate_locals`, `test_cross_openarray_string`,
`test_cross_stack_params`, `test_interfaces_multi_secondary`,
`test_u64_to_double`. Both interface tests the Scope section predicted are
among them.

Windowed: the managed stores now work there too; the frozen one still faults,
and that fault is **pre-existing and not from this change** — a plain
`var f: string[16]; f := 'FROZEN'` symbol store, no aggregate anywhere, SIGBUSes
under windowed on code this commit does not touch
([[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]]).

---

## THE THIRD CLUSTER — indexing, and it did NOT fall out of the store fix

Worth recording because it looked like it should. With the stores fixed,
`WriteLn(r.f)` and `Length(r.f)` are correct and `r.f[1]` is still wrong.

Indexing a managed string needs the HANDLE, and three base shapes arrive at
`IR_INDEX` with three different things in the register. Xtensa had the write
half of one of them:

| base | read | write |
| --- | --- | --- |
| scalar (`IR_LEA`) | `IR_LEA` already loaded the handle — ok | slot addr → `PXXStrUnique` — ok |
| **by-ref param** (`IR_LEA`, skParam+IsRef) | **the CALLER'S SLOT ADDRESS — one deref short** | ok |
| **field / element** (`IR_FIELD`/`IR_INDEX`, 1-byte stride) | **the field's slot address — one deref short** | **neither COW nor deref ran; the character store landed in the HANDLE SLOT** |

Measured, Call0, against both oracles:

| | xtensa before | oracle |
| --- | --- | --- |
| `d[1]`, `var d: AnsiString` | 32 | 65 |
| `r.f[1]` | 32 | 65 |
| `a[0][1]` | 72 | 80 |
| `r.f[2] := 'z'; WriteLn(r.f)` | `[]` | `[AzCDE]` |
| `a[0][2] := 'z'; WriteLn(a[0])` | `[]` | `[PzRST]` |

All five now identical to both oracles, **on Call0 and on windowed**.

**What made the by-ref row hard to see:** `Length(d)` and `WriteLn(d)` on the
same parameter were both CORRECT. Only the index was wrong, so the signature
read as "the index operator is broken" when the base was.
`test_cross_var_string_param` carried exactly this — it was the last line of
that test still diverging after the ABI-predicate fix, and it is now green.

riscv32 and arm32 both have all three rows
([[bug-a-riscv32-setlength-on-string-array-element-loses-length]]). Ported
verbatim rather than re-derived: **this is the same missing-row shape three
times in one night** — the ABI predicate, `IR_STORE_MEM`, `IR_INDEX` — and
re-deriving it a fourth time is how the fourth row goes missing.

### Bound and close

Binary `4c878d2df324`, hosted Call0 `--xtensa-soft-mulhigh`, plus the windowed
re-run of the index matrix. The 142-source differential: **63 → 64 match, 13 →
12 differ**, cfail unchanged at 66, zero regressions; `test-xtensa` regenerated
from the measured list and now runs 64 programs.

The ticket's subject — reading a managed string out of an aggregate — is fixed
for stores, reads and indexing, on both ABIs. Resolved. What remains is
elsewhere: `Write` of a real SIGBUSes
([[bug-a-xtensa-write-of-any-real-sigbuses-while-str-of-the-same-value-works]],
filed tonight from the probe that misled the float branch), and the 12 residual
divergences stay on
[[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]].

## Log
- 2026-08-30 — resolved, commit b69b4424c.
