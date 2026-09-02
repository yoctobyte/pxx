---
slug: bug-a-frozen-compare-feeds-inttotypekind-where-irstrtkof-is-required
track: A
prio: 75
type: bug
status: open
blocked-by: []
found: 2026-09-02
found-by: frankC
owner:
summary: "Under -dPXX_SHORTSTRING, comparing two frozen strings is FALSE on x86-64 and arm32, correct on aarch64 (riscv32/xtensa/wasm32 not in the population -- riscv32 REFUSES the flag by design). TWO DIFFERENT CAUSES, not one: arm32 HAS the width-aware normaliser and DOES call it, but resolves the operand kind with IntToTypeKind(IRTk[n]) at four call sites -- exactly what that normaliser's own comment forbids -- while aarch64 uses IRStrTkOf at all four equivalents; x86-64 has no width-aware compare path at all, EmitStrCmpReg (symtab.inc:7249) takes no type kind and hardcodes add rsi,8 / add rdi,8 / 8-byte length loads. Diagnosis only, not fixed: ir_codegen.inc and symtab.inc are frankb-a9's live surface."
---

# Frozen compare: `IntToTypeKind` where `IRStrTkOf` is required (arm32), and no kind at all (x86-64)

## HELD — do not claim this yet. The fix destroys a test we are about to get free.

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

**Open discrepancy in the population, unresolved — do not treat either row as
settled.** This ticket's summary places riscv32, xtensa and wasm32 outside the
population (riscv32 refusing the flag by design). Two other sessions reported
the opposite from their own runs after their conversions landed: frankh-15 that
riscv32 comparison is correct (`856810406`), franks-ab that xtensa comparison is
correct (`fe8662e24`). Both may be true of different trees — the conversions
landed after this diagnosis — which would make it the snapshot rule rather than
a contradiction. It matters because the prediction above is stated over a
partition, and a partition whose membership is uncertain cannot falsify
anything. Whoever runs the prediction must re-derive the population from the
tree at that moment rather than citing this paragraph, this summary, or either
of those commits.


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

## Population

riscv32 **refuses the flag by design** — `-dPXX_SHORTSTRING: the byte-length-prefix
codegen exists for x86-64, aarch64 and arm32 only so far`. So the population is
three converted backends, of which **two are wrong and one is right** — not
"four backends, two wrong".

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
