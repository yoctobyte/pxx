---
slug: bug-a-frozen-compare-feeds-inttotypekind-where-irstrtkof-is-required
track: A
prio: 75
type: bug
status: done
blocked-by: []
found: 2026-09-02
found-by: frankC
owner:
summary: "FIXED and VERIFIED. Under -dPXX_SHORTSTRING, comparing two frozen strings answered FALSE on x86-64 and arm32; frankb-a9 fixed both causes in 764dc3a30/64f230d12 exactly as this ticket prescribed -- EmitStrCmpReg gained a type kind (x86-64), and arm32's four callers moved from IntToTypeKind to IRStrTkOf. Re-measured independently at c8375f3e7 (compiler 4ba5c77aacc7): var=var, var=lit and lit=var all TRUE on x86-64, arm32, aarch64 AND riscv32. THE HOLD IS RELEASED. What survives is NOT a remnant of this -- the record-FIELD operand and the pointer-deref INDEX fail on opposite operand shapes and are separately ticketed."
---

# Frozen compare: `IntToTypeKind` where `IRStrTkOf` is required (arm32), and no kind at all (x86-64)

## HOLD RELEASED — 2026-09-02. The test it protected has been run.

The hold existed to preserve franks-ab's falsifiable prediction that the walker
fix would NOT repair comparison. **That prediction was tested and it held**: the
walker fix did not repair comparison; causes (2) and (3) did, separately. Nothing
is lost by closing this now.

## FIXED — verified independently, not taken from the fixing session

NOT DISPATCHABLE until the IRFrozenKindOfAddr walker fix lands (frankb-a9, sole
and named owner). This is a deliberate unowned state, decided 2026-09-02, not a
gap in the paperwork — and it looks exactly like a gap, which is why it is
written here rather than held in the coordinator's head. It was the ranked head
of `ready --track A` when this was added.

**The reason.** The walker model predicts that after the walker fix, comparison
stays red on exactly x86-64 and arm32 and goes green nowhere else. That
prediction is the only falsifiable check anyone has on whether the walker model
is right. Repair arm32's compare first and the prediction is unfalsifiable: a
green afterwards proves nothing and a red proves nothing, because both sides
moved. Walker lands, prediction confirms or fails, THEN this gets an owner.

**It is tempting precisely because it is cheap and well specified** — arm32 is
four identifiers, `IntToTypeKind(IRTk[left])` to `IRStrTkOf(left)`, with
`IRStrTkOf`'s own docstring prescribing that exact substitution. Small,
verifiable, and worth nothing tonight against losing the prediction. A session
that finishes early and goes looking will find this and see no reason not to
take it; the reason is the paragraph above.

**Population: RESOLVED 2026-09-02, and the summary above is stale on one row.**
This ticket's summary places riscv32 outside the population, refusing the flag
by design. That figure originated with frankb-a9 and **frankb-a9 has retracted
it**: riscv32 accepts the flag and passes all four modes plus all six comparison
shapes. The retraction is the origin correcting itself, not a third self-report,
so riscv32 is IN the population and its comparison is correct. frankh-15 had
reported the same from its own runs (`856810406`) and franks-ab the same for
xtensa (`fe8662e24`); those two were each reporting on a backend they had just
landed, so they agreed but could have failed the same way — they are one reading,
not two, and the retraction is what settles it.

The summary is left as its author wrote it rather than edited by a third party;
whoever next touches this ticket should fix that row in the same commit.

**Standing instruction regardless: whoever runs the prediction re-derives the
population from the tree at that moment**, rather than citing this paragraph,
the summary, or any commit. A partition whose membership is uncertain cannot
falsify anything, and every figure in this section has been wrong once.


## Repro — no pointer, no parameter, no literal

```pascal
type TS = string[8];          { capacity 8; 'hello' is 5, so a compare that
                                accidentally used the CAPACITY cannot pass
                                for the wrong reason }
var g1, g2: TS;
begin
  g1 := 'hello'; g2 := 'hello';
  WriteLn(Length(g1));        { 5 on every target, both configs }
  if g1 = g2 then ... else ...
end.
```

| config | x86-64 | arm32 | aarch64 |
| --- | --- | --- | --- |
| default | TRUE | TRUE | TRUE |
| `-dPXX_SHORTSTRING` | **FALSE** | **FALSE** | TRUE |

**The strings are INTACT when the compare fails** — printed value `[hello]`,
`Length` 5, `g1[1..5]` = `hello` on every row above. That is the control that
separates this from the store-side defect franks-ab found (`p^ := c` writing
the char at offset 8 under the flag): this repro contains no pointer store, so
a store bug cannot be what it is measuring.

## Population — CORRECTED 2026-09-02, and the correction is about TIME

When filed, riscv32 refused the flag outright: *"the byte-length-prefix codegen
exists for x86-64, aarch64 and arm32 only so far"*. That measurement was true
when taken. **riscv32 has since been converted**, and re-measured at HEAD it
accepts the flag and answers correctly (`g1 = g2` TRUE, `Length` 5, chars
intact). frankb-a9 retracted the figure as its own; the coordinator recorded it
in this body at `a6f81ffd2` and correctly did not edit another author's summary.

So the population grew under the ticket. **This is not a wrong measurement, it
is an expired one** — and it is the more dangerous kind, because nothing about
it ever becomes false-looking: the quoted diagnostic is still a real string the
compiler once printed. A population figure in a summary needs a date on it, or
it keeps answering about the tree it was measured on.

## The two causes, read from source rather than inferred

**arm32 — the normaliser is right and the CALLER feeds it the wrong kind.**
`EmitArm32StringParts` (`ir_codegen_arm32.inc:1299`) is width-aware and carries
this comment:

> *Callers must pass a kind resolved through `IRStrTkOf`/`IRFrozenKindOfAddr`,
> not `IntToTypeKind` of a node, or every frozen string looks 8 wide here.*

All four of its callers do the forbidden thing:

```
arm32   :2055 :2095 :2140 :2190   lhsTk := IntToTypeKind(IRTk[left]);   <- wrong
aarch64 :2349 :2390 :2438 :2487   lhsTk := IRStrTkOf(left);             <- right
```

`IRStrTkOf` (`ir.inc:15710`) exists precisely for this and says so:

> *This exists so the fix is ONE substitution rather than one per site: every
> `IntToTypeKind(IRTk[n])` that feeds a prefix width or a char offset becomes
> `IRStrTkOf(n)` and is correct on all seven backends.*

So the remedy was designed, named, documented and applied on aarch64, and
arm32's four sites never got the substitution. **The comment predicted the bug
and the callers below it violate it.**

**x86-64 — there is no kind to substitute.** x86-64 does not use `PXXStrEq` at
all (no `FindProc('PXXStrEq')` anywhere in `ir_codegen.inc`). Frozen string/string
equality inlines through `EmitStrCmpReg(eq: Boolean)` at `symtab.inc:7249`,
whose signature carries **no type kind**, and which hardcodes the word layout
four times:

```
add rsi, 8        { chars assumed at +8 }
add rdi, 8        { chars assumed at +8 }
mov rcx, [rcx]    { length read as a full 8-byte word }
cmp rcx, [rax]    { same }
```

The `tyString`/`tyChar` arms in `ir_codegen.inc` (~`:8990`-`:9030`) have the same
hardcoding (`mov rcx, [rax]`, `movzx rcx, byte [rax+8]`). So x86-64 needs the
signature to GAIN a kind, not a substitution at the call site — a different
edit from arm32's.

## Why it fails FALSE rather than loudly

A wrong prefix width yields a length in the billions; the length mismatch
short-circuits before any character is compared. It never crashes and never
prints garbage — it quietly answers no. aarch64's own compare-arm comment
records the same shape from before its fix: *"two frozen strings fell to the
integer path below and compared buffer addresses (always unequal)"*.

## Corrections to the working hypothesis this replaces

Three sessions converged on *"riscv32 and aarch64 have a named operand
normaliser and get it right; x86-64's shared path and arm32 lack that layer and
get it wrong."* **Measured against source, that is right for x86-64 and wrong
for arm32** — arm32 has the layer and calls it at the compare arm. The
agreement was three readings of one inference, not three independent readings.

Likewise *"a literal operand is correct, a variable operand is not"* is a
**wasm32** finding (frankwasm, at default, `WasmStrParts` operand selection) and
does **not** hold here: on x86-64 and arm32 under the flag the literal row
fails too (`g1 = 'hello'` BAD, `g1 = g2` BAD, `'hello' = g1` BAD). Different
backend, different config, different bug — see
[[bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length]]. They should
not be merged.

## Not fixed, deliberately

`ir_codegen.inc` and `symtab.inc` are frankb-a9's live surface and
`ir_codegen_arm32.inc` is adjacent to live conversion work. Two authors in the
operand decomposition would cost more than the bug.

## The residual question, which is bigger than these two arms

aarch64 `:2022-2027` and riscv32 `:503-507` carry the same warning on the
frozen→frozen assignment path; this is at least the **third** site of one
mechanism. The question is not "fix the compare arm" but **why a prefix width
is a per-site decision at all** — every site that reads a frozen prefix has to
remember to ask, and the ones that forget fail silently. See
[[refactor-a-the-const-cast-width-table-is-the-third-copy]] for the same shape.
