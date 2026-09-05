---
track: A
prio: 45
type: bug
blocked-by: []
status: working
found-by: frankwasm (while reducing bug-a-a-nilpy-generator-fails-on-wasm32)
summary: "A `generator; stackless;` routine that declares a VARIANT PARAMETER produces ZERO iterations on native x86-64 and ONE iteration with a garbage value (0) on wasm32. Six-line Pascal repro, no NilPy involved. It does NOT depend on the body reading the parameter -- a body that yields a constant fails identically -- so it is the parameter's SLOT, not its use. A Variant LOCAL is fine, an Integer parameter is fine, a Variant return is fine; only a Variant PARAMETER. Pre-existing on the pinned compiler. This is an ALL-TARGETS bug found on the native oracle, not a wasm32 one."
owner: frankS
---

# A Variant parameter makes a stackless generator produce nothing

```pascal
program p; uses slgen;
function Gen(n: Variant): Variant; generator; stackless;
begin yield n; end;
var x: Variant;
begin for x in Gen(7) do writeln('got=', x); end.
```

| | expected | native x86-64 | wasm32 |
| --- | --- | --- | --- |
| `yield n` | `got=7` | **(no output)** | `got=0` |
| `yield 9` (param unread) | `got=9` | **(no output)** | `got=0` |

**Native produces no output at all** — `for x in Gen(7)` runs zero times, so the
step function reports has-next False on its very first call. wasm32 runs the
body once and yields a value that is neither 7 nor 9.

## What was varied, and where the boundary is

Each row is the same program with one thing changed. All four controls PASS on
both targets, which is what makes the boundary a parameter's TYPE rather than
generators, Variants, or wasm32:

| shape | native | wasm32 |
| --- | --- | --- |
| `Gen(n: Variant): Variant` | **(nothing)** | **got=0** |
| `Gen(n: Variant): Variant`, body yields a constant | **(nothing)** | **got=0** |
| `Gen: Variant` with a Variant LOCAL | got=7 | got=7 |
| `Gen(n: Integer): Variant` | got=7 | got=7 |
| `Gen(n: Integer): Integer` | got=7 | got=7 |
| `Gen: Variant` yielding a literal | got=7 | got=7 |

`writeln` of a Variant is not the problem: it prints `got=7` from an ordinary
Variant outside a generator.

**The body does not have to read the parameter.** That is the load-bearing row:
a generator whose body yields a constant and never mentions `n` fails exactly
the same way, so this is about the parameter's slot region existing, not about
any read or write of it.

## Suspected site

`AssignStacklessSlots` (`compiler/pasparser_stmt.inc:~2440`) gives `tyVariant` a
TWO-word slot region and checkpoints it by blob copy:

```pascal
    if tk = tyVariant then
    begin
      SymGenSlot[i] := CurGenSlotNext;
      Inc(CurGenSlotNext, 2);
      Continue;
    end;
```

The arm makes no distinction between `skParam` and `skLocal`, and a Variant
LOCAL works — so the difference is in what happens to a PARAMETER's two-word
region at instance creation, where the caller's argument must be copied in,
rather than in the save/restore the local exercises.

Worth checking against the arm directly below it, which has this exact family's
scar tissue: `TypeIsPromoInt` used to fall through to the one-word arm and drop
the tag, and the write-up notes the promotable-int contract is *"a {tag,
payload} struct, not a machine word, so anything that must handle it asks for it
by name — an unhandled site errors instead of miscompiling"*. A multi-word
parameter is the same shape of question asked at instance-creation time.

## Why it is filed separately from the NilPy one

`bug-a-a-nilpy-generator-fails-on-wasm32-while-three-other-targets-agree` has a
similar-looking symptom (a generator parameter reads as absent on wasm32) but a
DIFFERENT signature: NilPy generators with parameters run **correctly on
native** and fail only on wasm32, whereas this fails on native first. They may
share the slot machinery; they are not the same measurement and should not be
merged on resemblance.

## Not verified

Only x86-64 native and wasm32 were measured. i386/arm32/aarch64/riscv32 are
unknown — if the mechanism is the two-word region, the 32-bit targets are the
interesting ones, because that is where the promotable-int twin of this bug
diverged.

---

## 2026-09-06 (frankS) — TWO defects found, one mechanism still open; probe added

Reproduced on native x86-64 at `64f260c3618d`. Added `PXXDBG=a.slslot`, which
prints the slot layout from **both ends of the one rule that has two spellings**
— what `AssignStacklessSlots` decided, and what the for-in desugar actually
stores to.

### Defect 1 — the caller addresses slots by ARGUMENT INDEX, the generator by SLOT INDEX

`ParseForInGeneratorAST` (`pasparser_stmt.inc:~515`) stores argument `k` at
`SL_OFF_SLOTS + 8*(k-1)`, and its own comment states the assumption:
`SlSet(__g, SLOTS+8k, ak) for each provided arg`. The generator's save and
restore (`SLSaveLocals` / `SLRestoreLocals`) use `SL_OFF_SLOTS + 8*SymGenSlot[i]`.

**Those agree only while every parameter is one word.** A Variant takes two, so
any parameter AFTER a Variant is addressed by the caller one slot low:

```
Gen(a: Variant; b: Integer)   a -> slots 0,1 (48,56)   b -> slot 2 (64)
caller writes                 a0 -> 48 (ok)            a1 -> 56  = a's HIGH WORD
```

`b` is never written and reads 0; `a` is corrupted in its second word. That is
`w_vi` / `probe3`, and it is the **no output at all** column of the table above.

This is the missing-copy shape again: one rule, two spellings, and the two
disagree only in a case nothing in the tree exercised.

### Defect 2 — a Variant parameter is stored as ONE machine word

`GenSlSetStmt2` emits `SlSet(g, off, val)`, and `SlSet(g: Pointer; off, val:
Int64)` writes exactly 8 bytes. A Variant is a 16-byte {tag, payload} pair, so
half of it is never written; `SlNew` zeroes the instance, so the other half stays
0. The code comment above `PyGenArgNeedsCell` states the assumption outright —
*"stored into its persistent instance slot by the for-in desugar, as ONE machine
word"* — and handles the NilPy variant case with a heap cell while the **Pascal
by-value Variant case has no arm at all**.

`SLSaveLocals`/`SLRestoreLocals` already do this correctly with
`SlBlob`/`SlUnblob` and an explicit 16. Only the caller does not.

### What is measured, and what is NOT

Measured and solid:

- Native reproduction; **only Variant**. A `record` parameter and an
  `AnsiString` parameter both leave the other parameters intact (`prec`, `pstr`
  print `11 22`), so this is not "any multi-word parameter".
- The generator's own restore is **correct** — `PXXDBG=a.ir:Gen` shows `a` read
  from 48 and `b` from 56, identically in the working and broken programs.
- For the case where the Variant is LAST, `PXXDBG=a.slslot` shows
  `storeoff == realoff` for every argument, so Defect 1 is **not** what breaks
  that case.
- `SlSet(g, 64, v)` with a Variant `v` works standalone — writes 33, leaves
  slots 0 and 1 intact. **Negative result: this is not a simple ABI mismatch**,
  and nobody should re-derive that theory.
- The failure is value-independent (`c` = 0, 1 or 33 all corrupt identically),
  so it is structural at compile time rather than a malformed-tag runtime effect.

**NOT explained, and this is the open question.** With the Variant LAST
(`Gen(a: Integer; b: Integer; c: Variant)`), the offsets are right and the
restore is right, yet `a` and `b` both read **0** — so the caller's stores to 48
and 56 are not taking effect when a Variant argument is present anywhere in the
list. Defect 2 alone should corrupt only `c`. Something about building the
argument sequence with a Variant in it is losing the earlier stores, and I did
not find it. The next reader should start there and not at the offsets, which
are proven correct in that case.

### Where to look next

`ParseForInGeneratorAST`'s `assignG` chain, the `argHoist` splice in particular.
Note the Variant-variable form (`pv`) fails identically to the literal form, so a
conversion temp is **not** the trigger.

Fixing Defect 2 needs a `SlBlob` of the argument's address with `TypeSlotSize`
bytes at `SL_OFF_SLOTS + 8*SymGenSlot[param]`, which fixes Defect 1 in the same
edit — the two share one repair. Do not fix Defect 1 alone: it would move the
Variant to the right offset and still write half of it.

### Not verified

Still only x86-64 native and wasm32. The ticket's own note that 32-bit targets
are the interesting ones stands, and Defect 1 makes that sharper — `8*(k-1)`
is a hardcoded 8 on every target, while `TypeSlotSize` is not.

---

## 2026-09-06 (frankS, later) — the two symptoms are NOT the two defects, and both occur on native

A tempting mapping is going around: *native's zero iterations is Defect 1, wasm32's
`got=0` is Defect 2.* **It does not hold, and acting on it would misroute the fix.**

**Both symptoms occur on native, from one binary.** All four programs below yield
the CONSTANT 9, so the parameter list is the only variable and nothing depends on
reading a parameter:

| parameters | native result |
| --- | --- |
| `c: Variant` | **no iterations** |
| `c: Variant; a: Integer` | **no iterations** |
| `a: Integer; c: Variant` | `got=9` — correct |
| `a: Integer` | `got=9` — correct |

**Zero iterations happens exactly when the FIRST parameter is a Variant.** It is
not about targets and not about how many parameters there are.

Separately, and independently: with a Variant anywhere in the list, the OTHER
parameters read 0 while iteration still works — `Gen(a: Integer; c: Variant)`
yielding the constant prints `9`, and the same signature yielding `a` prints `0`.

**And Defect 1 does not apply to this ticket's own headline repro.** For
`Gen(n: Variant): Variant`, `PXXDBG=a.slslot` prints
`arg1: storeoff=48 ... realoff=48` — the two spellings AGREE, because a single
leading parameter is at argument index 0 and slot index 0 whichever way you
compute it. Defect 1 needs a parameter AFTER a Variant to diverge. So the
headline repro is Defect 2 plus the open mechanism, and **fixing Defect 1 would
not change it at all.**

That matters for anyone reading the wasm32/native asymmetry as diagnostic: the
asymmetry is real and worth explaining, but it is a THIRD thing, not a view of
the two defects. Same source, same parameter list, two targets, two symptoms —
while native alone already produces both symptoms from different parameter lists.

**Sharpest statement of the open mechanism**, replacing the looser one above:
*with a Variant anywhere in the parameter list, the caller's slot stores for the
NON-Variant parameters do not take effect* — the offsets are provably correct
and the restore provably reads them, so the stores are the remaining suspect.
And when the Variant is FIRST, the generator additionally reports has-next False
on its first call, which no wrong parameter value should be able to cause.

---

## 2026-09-06 (frankwasm) — the wasm32 half, and a correction

frankS worked native; I filed the row and had the wasm32 side, so this is the
other end of the same measurement. Compiler `d1f75a3c0531`.

### `a.slslot` on wasm32 is IDENTICAL to native for the headline repro

Same program as this ticket's first block, one Variant parameter:

```
native   assign: sym=n kind=2 tk=22 slot=0 off=48
         caller: proc=Gen nargs=1 instsize=80 paramcount=2
           arg1: storeoff=48 symgenslot=0 realoff=48 tk=22

wasm32   assign: sym=n kind=2 tk=22 slot=0 off=48
         caller: proc=Gen nargs=1 instsize=80 paramcount=2
           arg1: storeoff=48 symgenslot=0 realoff=48 tk=22
```

Byte-for-byte the same layout, same `instsize`, and `storeoff == realoff` on
both. So **Defect 1 does not fire in this ticket's headline repro at all** — a
single parameter makes argument index 1 and slot index 0 coincide, exactly as
Defect 1's own rule predicts. This extends frankS's "Variant LAST" negative
result to the ONE-PARAMETER case, and it means the program this ticket is named
after is explained by Defect 2 and/or the open mechanism, never by Defect 1.

### On the symptom-to-defect mapping — reached independently, twice

frankS's section directly above and this probe were run separately and agree:
`storeoff == realoff` for the headline repro, so **neither symptom is Defect 1**.
frankS's version is the stronger one and is the one to cite — a parameter-list
table on ONE target beats my two-target argument, because it shows both symptoms
coming out of a single binary.

Worth recording how the wrong mapping arose, since it was built on a number of
mine: I measured two OUTPUTS on two targets and never measured which defect
produced either. There were two defects and two symptoms, and the arities
matching did the rest. An asymmetry sitting next to a real measurement acquires
that measurement's credibility.

### And it is not Variant WIDTH either

The obvious explanation for "8 bytes written of a 16-byte pair behaves
differently per target" is that the pair is not 16 bytes everywhere. Measured:

```
native  sizeof(Variant)=16  sizeof(Pointer)=8
wasm32  sizeof(Variant)=16  sizeof(Pointer)=4
```

**Same 16 on both.** So: same total width, same slot offset, same 8-byte
`SlSet`, and `SlNew` zeroes the instance on both — yet native runs the body
ZERO times and wasm32 runs it once yielding 0. Whatever separates them is not
size, not offset and not the zero-fill.

### The one place I would look next, stated as a hypothesis and NOT measured

`SizeOf(Pointer)` is the only thing left that differs. If the `{tag, payload}`
pair places its members differently at the same total width — a tag and a
pointer-sized payload plus padding on a 32-bit target, against two 8-byte
members on a 64-bit one — then the FIRST 8 bytes that `SlSet` does write cover
different parts of the value on the two targets, which would produce exactly
this "half-works on one, not at all on the other" split from one defect rather
than two. **I did not measure the field offsets and this may be wrong.** It is a
place to point a probe, not a finding.

### Scope

Only the headline one-parameter repro was probed on wasm32. frankS's
multi-parameter cases were not re-run there, and the open mechanism (earlier
integer stores lost when a Variant is anywhere in the argument list) was not
investigated on wasm32 at all.
