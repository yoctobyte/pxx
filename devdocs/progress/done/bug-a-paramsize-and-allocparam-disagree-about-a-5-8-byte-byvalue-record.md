---
slug: bug-a-paramsize-and-allocparam-disagree-about-a-5-8-byte-byvalue-record
track: A
prio: 40
type: bug
found: 2026-08-30
owner: frankA
status: done
blocked-by: []
summary: "RESOLVED by splitting the misleading name into the two answers it was asked for: ParamSlotWordSize (the slot-LAYOUT question, one machine word for anything passed by address -- today's ParamSize, renamed at all 15 call sites) and ParamValueSize (how many bytes AllocParam actually reserved). AllocParam now CALLS ParamValueSize instead of restating its rule, so the two cannot diverge again -- the half a rename alone would not have closed. Measured on arm32: slotword=4 and valuesize=8 for the same 5-8 byte by-value record param, and both 8 on x86-64, so the disagreement is real and the coincidence is real. Emitted binaries byte-identical on x86-64/arm32/riscv32/aarch64. The measurement also found the INPUT half and it is filed: AllocParam sizes the slot from a record id that is REC_NONE for 41 of 52 record params in compiler.pas."
---

# ParamSize and AllocParam disagree about a 5-8 byte by-value record

Two functions in `symtab.inc` answer "how big is this parameter's slot" and give
different answers for the same parameter on a 32-bit target. `AllocParam` is the
one that is right; `ParamSize` is the one every backend reads.

```pascal
{ AllocParam — allocates the slot }
if (tk = tyRecord) and not isRef and not isArray and (RecSize(LastTypeRecId) <= 8) then
begin
  sz := RecSize(LastTypeRecId);              { 8 for an 8-byte record }
  if sz < TARGET_PTR_SIZE then sz := TARGET_PTR_SIZE;
end
else if ABIParamSlotIsPointer(tk, isRef, isArray) then
  sz := TARGET_PTR_SIZE
...

{ ParamSize — reports the slot's size }
function ParamSize(idx: Integer): Integer;
begin
  if ABIParamSlotIsPointer(Syms[idx].TypeKind, Syms[idx].IsRef, Syms[idx].IsArray) then
    Result := TARGET_PTR_SIZE                 { 4 on a 32-bit target }
  else
    Result := TypeSize(Syms[idx].TypeKind);
end;
```

`ABIParamSlotIsPointer` holds `tyRecord` **unconditionally**, so `ParamSize`
returns `TARGET_PTR_SIZE` for every record — while `AllocParam` has already
reserved the record's real width for the <=8-byte by-value case. On 64-bit they
agree by coincidence (`TARGET_PTR_SIZE` = 8 covers any `RecSize <= 8`); on
arm32 / riscv32 / xtensa / i386 they do not.

## Why this is worth a ticket and not just a note

**It is a trap that costs a build cycle and produces a plausible false comment.**
Measured, on 2026-08-30, while landing
`bug-a-a-by-value-wide-record-on-xtensa-renders-a-live-address`: the natural way
to widen xtensa's callee param spill is

```pascal
((Syms[idx].TypeKind = tyRecord) and (sz > 4) and (sz <= 8))
```

because `sz := ParamSize(idx)` is already in scope three lines above and reads
like the width. That guard **compiles, self-hosts, and can never be true**. The
symptom is a repro that comes back byte-identical, which reads as "my change did
nothing" and sends you back to re-read arms that were already correct. It also
invites a comment asserting that `sz` asks the real width — one was written, and
it was wrong.

arm32 and riscv32 both dodge it, in this same procedure
(`EmitParamSpillsForTarget`, `ir_codegen.inc`), by *not* using `sz` for records:
they spell it `RecSize(Syms[idx].RecName)` in the spill guard and
`RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + i])` in the word-count
pre-pass. xtensa now matches them. So all three live call sites are correct
today — **this ticket is about the next one**, and about a helper whose name
promises an answer it does not give.

## No known miscompile today

Checked, so the priority is honest rather than defensive: the `else` branches
that consume `sz` only distinguish 1 / 2 / other, and a record reaching them
gets a full-word store, which is right for a <=4-byte record and is the only
case that still reaches there. i386 refuses record parameters outright
(`target i386: only ordinal/pointer parameters supported yet`), so it cannot be
silently wrong. `cparser.inc` and `eparser.inc` also call `ParamSize`; those
were **not** audited and are the first thing to check if this is picked up.

## Options

1. **Make `ParamSize` ask `RecSize`** for the by-value <=8-byte record case, so
   it agrees with `AllocParam`. Correct in principle and makes the natural guard
   work — but `ParamSize` takes only a symbol index, `Syms[idx].RecName` is
   available, and any consumer currently *relying* on getting 4 would change
   behaviour. Needs the C-frontend call sites audited first.
2. **Rename it** to say what it answers (`ParamSlotWordSize`, or fold it into
   the `abi.inc` oracle beside `ABIParamSlotIsPointer` with a comment naming the
   record exception). Cheap, no behaviour change, kills the trap.
3. Leave it and document the exception at both definitions.

Recommendation: **2**, and only then 1 if an audit shows no consumer depends on
the pointer-sized answer. The defect here is a misleading name on a shared
helper, not a wrong number reaching the emitter.

## Provenance

Found by frankS under a bounded grant for `EmitParamSpillsForTarget`'s xtensa
arm. Filed rather than fixed: `symtab.inc` and `abi.inc` are Track A's and were
outside that grant. Sibling of `bug-a-param-pointer-rule-divergence`, which is
the same two functions disagreeing about `tyVariant` — that fix is cited in
`abi.inc` as the small-scale precedent for the whole oracle, so this is the
second instance of one pattern.

---

## Resolved 2026-09-01 (frankA, Track A)

**Option 2, and then the part option 2 alone would have left open.**

`ParamSize` -> `ParamSlotWordSize` at all 15 call sites (`cparser.inc` ×3,
`eparser.inc` ×1, `ir_codegen.inc` ×10, `pasparser_proc.inc` ×1). And
`ParamValueSize(idx)` beside it, which is the answer the trap was reaching for:
how many bytes `AllocParam` actually reserved.

A name a reader has to think about is worth little if the answer they wanted
has no name at all. That is why this is not just the rename the ticket asked
for.

**`AllocParam` now CALLS `ParamValueSize` rather than restating the rule.** The
two functions gave different answers because the rule was written twice; one
copy is the only fix that stops it happening again. The extraction is exact —
`TypeKind`, `IsArray`, `IsRef` and `RecName := LastTypeRecId` are all written
before the size block, so the symbol-based form reads the same inputs the
inline form did.

### The disagreement, measured

Scratch `WriteLn` in `AllocParam`, four by-value record params (4/6/8/16 bytes):

```
arm32   (TARGET_PTR_SIZE=4)   slotword=4  valuesize=8     <- they differ
x86-64  (TARGET_PTR_SIZE=8)   slotword=8  valuesize=8     <- they agree
```

and a `const` param on arm32 comes through `slotword=4 valuesize=4`, so the new
function distinguishes by-ref from by-value rather than answering the record's
width unconditionally. Without this the split would have been cosmetic; with it
the trap guard `(TypeKind = tyRecord) and (sz > 4) and (sz <= 8)` becomes
expressible — against `ParamValueSize`, and still impossible against
`ParamSlotWordSize`, whose name now says so.

### Control: no behaviour change

The probe (4-, 6-, 8- and 16-byte by-value record parameters, all four called
and summed) compiled with the compiler built from this tree with the change
stashed (`07291395282b`) and with it (`994bcc639fa0`):

```
x86_64   IDENTICAL       arm32    IDENTICAL
riscv32  IDENTICAL       aarch64  IDENTICAL
```

byte-for-byte, and the program prints `3 7 5 30` natively and under qemu on all
three cross targets. i386 refuses record parameters outright, as the ticket
said.

### Option 1 was NOT taken, and the audit it asked for is the reason

The ticket ranks option 1 (make the reported size ask `RecSize`) as a
follow-up "only then ... if an audit shows no consumer depends on the
pointer-sized answer". The 15 sites are audited by the rename itself — every
one of them now says which question it asks — and option 1 is no longer
attractive, because the measurement below shows the input to `RecSize` is the
part that is wrong.

### What the measurement found underneath

`AllocParam` sizes the slot from `RecSize(LastTypeRecId)`, and **`LastTypeRecId`
is REC_NONE for 41 of the 52 record parameters in `compiler.pas`**, where
`RecSize` answers its 8-byte fallback. So `RecSize(..) <= 8` — the test that
chooses between an inline record slot and a pointer slot — is a CONSTANT TRUE
for those 41, and the branch's comment describes a decision it is not making.
The other 11 carry real ids (sizes 16, 40, 56), so the population is not
degenerate.

Not a miscompile: every answer `ParamValueSize` can give once `RecName` is
resolved is `<= max(8, TARGET_PTR_SIZE)`, so the slot is over-allocated by up
to four bytes on a 32-bit target and never under-read. Filed as
[[bug-a-a-record-parameters-type-is-not-resolved-when-its-slot-is-sized]]
rather than fixed here — it changes FRAME LAYOUT, which is the widest blast
radius in the compiler and does not belong in a commit that renames a helper.

So the ticket's *"AllocParam is the one that is right"* holds, but **by the
clamp rather than by the test**, and that is worth knowing before anyone
implements option 1 by copying its condition.

### Not changed, deliberately

`EmitParamSpillsForTarget`'s arm32 / riscv32 / xtensa arms spell
`RecSize(Syms[idx].RecName)` longhand and could now say `ParamValueSize(idx)`.
They are correct today, the equivalence over the `(>4, <=8)` window is subtle
rather than obvious, and rewriting correct backend code for uniformity in the
same commit as a 15-site rename would have made the byte-identity control above
meaningless. Left as a note, not done.

### Gate

`make compiler/pascal26`: converged, `994bcc639fa0`. `tools/gate.sh quick`:
GREEN, FPC seed canary PASS (run with `compiler/` dirty).
