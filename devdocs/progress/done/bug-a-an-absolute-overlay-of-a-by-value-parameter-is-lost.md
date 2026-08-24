---
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
summary: "`procedure P(v: Integer); var b: array[0..3] of Byte absolute v;` compiles, runs, and writes SOMEWHERE ELSE: v is unchanged. A by-value parameter's slot lives in the parameter space, so copying its Offset onto a local-kind symbol aliases a LOCAL slot at the same number. Silent wrong value, present on `pinned`, and the naive fix (copy the target's Kind too, which is what fixed the by-REF case) segfaults."
---

# An `absolute` overlay of a by-VALUE parameter writes to the wrong slot

Found 2026-08-24 by varying the shape while fixing
[[bug-a-absolute-cannot-overlay-an-untyped-var-parameter]] — the by-ref case was
a loud refusal, this one is the silent sibling.

## Measured

```pascal
procedure ByValue(v: Integer; var outv: Integer);
var b: array[0..3] of Byte absolute v;
begin b[0] := 5; outv := v; end;

procedure ByValueScalar(v: Integer; var outv: Integer);
var w: Byte absolute v;
begin w := 5; outv := v; end;

var i, j: Integer;
begin
  i := $01020304; ByValue(i, j);       WriteLn('arr    ', j);
  i := $01020304; ByValueScalar(i, j); WriteLn('scalar ', j);
end.
```

| | arr | scalar |
| --- | --- | --- |
| fpc 3.2.2 | `16909061` | `16909061` |
| pxx HEAD | `16909060` | `16909060` |
| pxx `pinned` | `16909060` | `16909060` |

The write to the overlay is simply lost. Both the array and the scalar spelling,
so it is the overlay's storage that is wrong, not one lowering.

## Why

`absolute` gives the new symbol the target's storage by copying its `Offset`:

```pascal
Syms[idx].Offset := Syms[absTarget].Offset;
```

An offset is meaningless without the space it is measured in, and the
declaration code already knows that for one pair — it refuses a local
overlaying a global with *"a local cannot overlay a global"*, on exactly this
reasoning. A by-VALUE parameter is a third space: its slot is in the parameter
area, while the freshly-allocated overlay symbol is `skLocal`. Same number,
different frame region.

## The obvious fix segfaults — measured, not assumed

The by-ref case above was fixed by copying the target's addressing mode as well
as its offset (`Kind` and `IsRef`), which makes the alias faithful for every
access path at once. Doing the same for a by-value target — `Syms[idx].Kind :=
Syms[absTarget].Kind` with `IsRef` False — **segfaults at runtime** on both the
array and the scalar spelling. So `skParam` addressing is not simply "the same
space with a different sign" for a non-ref parameter, and whatever the extra
ingredient is has to be found before this can be written.

Start by printing what the two symbols actually record —
`PXXDBG=a.symptr:<name>` is the existing topic for a pointer decl and the
nearest thing; a symbol-layout dump may be worth adding beside it, since this
ticket and its sibling both turned on "what does the symbol table actually say"
(`devdocs/dev/debugging-playbook.md`).

## Why it is a real bug and not a corner

It is the one arm of `absolute` that is neither correct nor refused. The other
three are settled: a local/global overlay works, a by-ref parameter works as of
today, a dynamic array is refused by name, and a local-over-global is refused by
name. This one compiles and lies.

## Gate

Track A's, plus the program above matching fpc 3.2.2 on x86-64 and one cross
target, and the by-value row added back to
`test/test_absolute_over_a_var_parameter.pas`, which deliberately omits it today
so the wrong answer is not frozen into a test.

## Fixed 2026-08-24 (claude-A) — it was never the addressing, it was the OPTIMIZER

This ticket's "Why" section is wrong, and how it was wrong is the finding.

It says a by-value parameter's slot lives in "a third space… the parameter area,
while the freshly-allocated overlay symbol is `skLocal`". It does not. `AllocVar`
and `AllocParam` both do `FrameSize := AlignTo(FrameSize + sz, align);
Offset := -FrameSize` — **one counter, one space** — so the plain `Offset` copy
already aliases a by-value parameter faithfully, and always did.

The one measurement the ticket never took says so in a line:

| | -O0 | -O1 | -O2 | -O3 |
| --- | --- | --- | --- | --- |
| `byval-arr` / `byval-scalar` | correct | correct | **wrong** | **wrong** |

Correct at -O0 is not something an addressing-space bug does. And the
disassembly of the -O2 body named the cause outright:

```
mov  %edi,-0x4(%rbp)        ; v spilled
mov  %r14,-0x20(%rbp)       ; save caller's r14
movslq -0x4(%rbp),%rax
mov  %rax,%r14              ; <-- v is now RESIDENT in r14
mov  $0x5,%eax
mov  %al,-0x4(%rbp)         ; the overlay writes the SLOT
mov  %r14,%rax              ; <-- and the read comes from the REGISTER
```

## Root cause: the one alias in the language that takes no address

Register residency is allowed to cache a symbol in a register exactly when
nothing else can write its slot, and the question it asks is *"is this symbol's
address taken in this body"* — an `IR_LEA` / `IR_SLOTADDR` scan. An `absolute`
overlay is two symbol indices over one slot and **emits no address-of at all**,
so the scan is structurally unable to see it.

Six independent copies of that scan were live, and every one of them answered
"clean":

| site | what it gates |
| --- | --- |
| `RegcallAssignResidency` | -O2 param residency (r14/r15) |
| `UnifiedResidencyAssign` | -O3 loop residency (r12-r15 + xmm8-13) |
| `UnifiedResidencyAssignA64` | the aarch64 twin |
| `ArgSymAddrClean` | -O3 argument-evaluation deferral |
| `ProcBodyScan` | per-proc addr-taken-param summary |
| `--measure-regcall` | the opportunity probe |

Two is a smell and three is a design flaw
(`devdocs/dev/root-cause-over-microfix.md`); six is why a one-concept miss was a
six-site miss. So the fix is not a guard added to the pass that happened to be
measured — it is **one predicate, `SymSlotEscapes`, in `ir.inc`**, asking the
whole question ("can this slot be reached other than through this symbol
index?"), with all six call sites reduced to calling it. The `absolute` half is
recorded by `SymAbsAliased`, set on **both** sides of the overlay at declaration
(either index is equally a residency candidate) and cleared at every `Alloc*`,
since `SymRollbackTo` recycles slots.

### And a seventh site, which residency alone would not have found

Varying the shape from a `procedure` to a `function` kept it broken after the
residency fix, and the caller's disassembly showed why: the body had been
**inlined**, with `v` at one global and `w` at another four bytes away. Inline
retention *replaces storage* — params and locals become placeholders the
expansion re-materialises as one fresh slot per symbol — so two symbols sharing
a slot in the callee become two slots in the caller and the alias is simply
gone. `TryRetainInlineBody` now refuses to retain any body with an
`absolute`-aliased symbol in scope. Refused wholesale rather than per-shape,
because the overlay is invisible in the AST (it is a fact about the symbol
table, not about any node), so each shape validator would otherwise re-learn it.

## Measured after

`test/test_absolute_alias_survives_residency.pas` — 7 rows over the shapes each
guard covers: a by-value param written through a scalar and an array overlay, an
overlay written on one branch only, a local overlay read hot in a loop (-O3
picks locals, not just params), the reverse direction (the OVERLAY hot and the
TARGET written, which is why the flag is on both sides), and a by-value param
whose overlay is written between two calls.

Identical to fpc 3.2.2 at **-O0, -O1, -O2 and -O3** natively, and at -O0/-O2/-O3
under qemu on i386, arm32 and riscv32. aarch64 matches at -O0 and -O2; aarch64
`-O3` could not be measured because **the compiler segfaults there on an empty
program**, on `pinned` as much as HEAD — found by this cross-check and filed as
[[bug-a-aarch64-o3-segfaults-the-compiler-on-an-empty-program]] (prio 60).

The by-value rows are back in `test/test_absolute_over_a_var_parameter.pas`,
which had deliberately omitted them so the wrong answer would not be frozen.

The property the new test asserts is deliberately **not** a value — the other
test asserts values. It is that the answer does not DEPEND on the optimisation
level, so the same source is compiled three times and the three outputs must
agree. That is the invariant an aliasing bug breaks, and a single-`-O` test
cannot see it.

### Correction recorded rather than quietly dropped

The sibling ticket's fix comment said copying `skParam` onto the overlay
"segfaults, so skParam addressing is evidently not simply the same space". The
segfault is real and the inference was not: the two Kinds differ in **prologue
spill**, not in address space, which is why the by-value arm needs no Kind copy
at all. Both comments are now corrected in place.

## Gate

`make compiler/pascal26` fixedpoint converged in one round; `tools/gate.sh
quick` GREEN; two `test-core` cases (the extended `absolute` test and the new
three-`-O` residency test).

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
