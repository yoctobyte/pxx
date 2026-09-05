---
track: A
prio: 45
type: bug
blocked-by: []
status: working
found-by: frankwasm (while reducing bug-a-a-nilpy-generator-fails-on-wasm32)
summary: "A `generator; stackless;` routine with a VARIANT PARAMETER SEGFAULTS on native x86-64 (not zero iterations -- that was an inference from absent output; measured rc=139) and gives one wrong iteration on wasm32. ROOT CAUSE FOUND 2026-09-06: three parties disagree on what a Variant parameter is. The callee frame slot holds a one-word POINTER (a Variant value-param is passed by reference), the instance reserves 2 slots (correct for a value), and the caller stores 8 bytes via SlSet after an implicit Variant->Int64 conversion. `Syms[i].IsRef` is FALSE for a Variant value-param, so AssignStacklessSlots routes it to the tyVariant arm instead of the correct by-ref arm directly above, and SlUnblob then writes 16 bytes into that 8-byte pointer slot -- overrunning the ADJACENT frame slot. When the Variant is the FIRST parameter the neighbour is the hidden `self`, which is zeroed, so the step function does SlGet(nil, 0). That is the crash. When it is not first, the neighbour is another parameter, which is silently clobbered to 0. ONE mechanism, all rows."
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

### That hypothesis is now DEAD too — the layout is identical as well

I wrote above that `SizeOf(Pointer)` was the only thing left, and guessed the
`{tag, payload}` pair might place its members differently at the same total
width. **Measured, and it does not.** Writing `v := 33` and dumping all 16
bytes:

```
native  bytes: 1 0 0 0 0 0 0 0  33 0 0 0 0 0 0 0
wasm32  bytes: 1 0 0 0 0 0 0 0  33 0 0 0 0 0 0 0
```

Byte-for-byte identical: an 8-byte tag at offset 0, an 8-byte payload at offset
8, on both targets. So **the first 8 bytes that `SlSet` writes are the TAG on
both**, and the payload at slot offset +8 is never written on either.

That is a sixth negative result and it is worth stating as one: the
native/wasm32 asymmetry is not size, not slot offset, not `instsize`, not
zero-fill, and not member placement. Every compile-time quantity I can find is
the same on the two targets.

**What it leaves, and I am labelling the inference as an inference.** frankS
measured that `SlSet(g, 64, v)` with a Variant writes **33** — the payload, via
a Variant->Int64 conversion — rather than the tag. Combined with the layout
above, that puts the payload value 33 into the TAG word and leaves the real
payload word zero, i.e. the restored Variant is `{tag = 33, payload = 0}` with
33 as a nonsense type code. One corruption, and two runtimes are then free to
react to an invalid tag differently — one bailing out of the iteration, one
yielding 0. **I have not verified that either runtime does that**; it is the
cheapest remaining explanation for a divergence with no compile-time difference
behind it, and it predicts that the two symptoms are the same defect seen twice
rather than a third thing.

The falsifiable version, for whoever picks this up: dump the instance's 16 bytes
at the slot offset on both targets after the store. If they are equal, the
divergence is entirely in the Variant runtime's handling of a bad tag and there
is nothing target-specific in the generator machinery at all.

### Scope

Only the headline one-parameter repro was probed on wasm32. frankS's
multi-parameter cases were not re-run there, and the open mechanism (earlier
integer stores lost when a Variant is anywhere in the argument list) was not
investigated on wasm32 at all.

## 2026-09-06 (frankS) — ROOT CAUSE. It is a frame-slot OVERRUN, and the ticket's core claim was wrong

**The headline claim in this ticket — mine and the original — was an inference
from absent output, and it is false.** "Native produces no output at all, so the
step function reports has-next False on its very first call" describes a state
machine declining to start. It does not. **The program SEGFAULTS**: `rc=139`,
confirmed with markers (`[BEFORE|]`, never reaches `AFTER`). My own "zero
iterations" phrasing in the sections above inherits the error; read them with
that correction. A crash has a location, which is why this was the cheap case
the moment anyone checked an exit code instead of stdout.

### The mechanism, end to end

`gdb` on the headline repro (`function Gen(c: Variant): Integer; generator;
stackless; begin yield 9; end;`):

```
SIGSEGV at 0x427b2f, inside SlGet (0x427ae5..0x427b50)
  rdi = 0   (g)      rsi = 0   (off)
  rax = g + off = 0 ; mov (%rax),%rax     <-- NULL deref
```

`SlGet(nil, 0)` is the read of the **state** field. So the instance pointer is
NULL — but `SlNew` is fine and its result IS stored:

```
SlNew called, instSize=64   -> returned 0x7fffe7e00008, stored to global 0x437038
Gen entered:  self(rdi) = 0x7fffe7e00008        <-- correct
after SlUnblob: self@-0x8 = (nil)               <-- destroyed by the restore
                varlocal@-0x10 = 7
```

The step function's prologue:

```
sub    $0x20,%rsp
mov    %rdi,-0x8(%rbp)        ; self
mov    %rsi,-0x10(%rbp)       ; c  -- ONE WORD
lea    -0x10(%rbp),%rax       ; dst = &c
mov    $0x10,%eax             ; 16 bytes
call   SlUnblob(self, 48, &c, 16)
mov    -0x8(%rbp),%rax        ; reload self -> now 0
call   SlGet                  ; SlGet(nil, 0)  -> SIGSEGV
```

`-0x10 + 16 = -0x0`. **The 16-byte restore runs over `-0x8(%rbp)`, which is
`self`.** The word it writes there is the Variant's payload half — never
written by the caller's 8-byte `SlSet`, so it is 0. The generator zeroes its
own instance pointer and then dereferences it.

### Three parties, three different ideas of what a Variant parameter is

| party | what it thinks `c: Variant` is | measured |
| --- | --- | --- |
| caller (`ParseForInGeneratorAST`) | an Int64 value — `SlSet` 8 bytes after an implicit Variant→Int64 conversion | slot word = `7` |
| instance (`AssignStacklessSlots`) | a 16-byte value — `Inc(CurGenSlotNext, 2)` | `instSize=64`, 2 slots |
| callee frame | a one-word **pointer** — the real ABI | `mov %rsi,-0x10(%rbp)`, 8 bytes |

Three mechanisms for one concept. Per `root-cause-over-microfix.md` that is the
design-flaw count, not the smell count.

**The callee is the one that is right.** A Variant VALUE parameter is passed by
reference — measured on a plain non-generator function, which spills exactly one
word and calls through it:

```
function F(c: Variant): Integer;
  sub $0x10,%rsp ; mov %rdi,-0x8(%rbp) ; mov -0x8(%rbp),%rax ; mov %rax,%rdi ; call 0x41eb23
```

So the 8-byte frame slot is CORRECT. What is wrong is that the generator
treats that pointer slot as though it held the 16-byte value.

### Why it never reaches the arm that already handles this

`AssignStacklessSlots` has the right arm, and it sits directly ABOVE the one
that fires:

```pascal
if Syms[i].IsRef then          { by-ref param: the slot persists the caller ADDRESS
begin                            (one pointer word); save/restore go through AN_SLOTADDR }
  SymGenSlot[i] := CurGenSlotNext; Inc(CurGenSlotNext); Continue;
end;
...
if tk = tyVariant then         { 16-byte {tag,payload}: two slots, SlBlob/SlUnblob }
```

`PXXDBG=a.slslot` on the repro:

```
a.slslot assign: sym=c kind=2 tk=22 slot=0 off=48
```

`kind=2` is `skParam`, `tk=22` is `tyVariant` — and it took the **Variant** arm.
**`Syms[c].IsRef` is False for a Variant value-parameter that the ABI
nevertheless passes by reference.** This is frankB's missing-copy shape exactly:
the correct handling exists, is adjacent, and is simply never reached. The bug
is an ABSENT classification, not a divergent one.

### One mechanism explains every row, and it predicted a new one

Adjacency decides the symptom. Frame slots go downward in declaration order:
`self@-0x8`, first param `@-0x10`, second `@-0x18`. A 16-byte write into a
one-word slot always lands on the slot ABOVE it.

| shape | neighbour clobbered | predicted | measured |
| --- | --- | --- | --- |
| `c: Variant` | `self` | crash | `rc=139` |
| `c: Variant; a: Integer` | `self` | crash | `rc=139` |
| `a: Integer; c: Variant` (body yields 9) | `a`, unread | works | `got=9` |
| `a: Integer` | — | works | `got=9` |

The first three were already in this ticket as a table with no explanation. The
fourth row below is the one the mechanism PREDICTED before it was run — Variant
second, and a body that READS the clobbered parameter:

```pascal
function Gen(a: Integer; c: Variant): Integer; generator; stackless;
begin yield a; end;
...  for x in Gen(9, 7) do writeln('got=', x);
```

Predicted `got=0` (a clobbered by the payload half), not `got=9`, and no crash.
**Measured `got=0`, `rc=0`.** That is the positive control for this diagnosis:
a row whose right answer differs from both the working value and the crash.

This also retires my own open mechanism. "Non-Variant parameters read 0" is not
a second defect and not a store that failed to take effect — it is the
neighbour being overwritten by the Variant's restore.

### What this says about the native/wasm32 split

frankwasm has now measured that every compile-time quantity is identical on the
two targets — slot offsets, `instsize`, `sizeof(Variant)`, zero-fill, and
`{tag, payload}` member placement (six negative results). That is consistent
with this cause and it explains why: **the defect is not in any compile-time
quantity, it is an out-of-bounds WRITE into a stack frame**, and what a stray
16-byte store lands on is a property of the target's frame layout, not of the
generator machinery. Native puts `self` in the way and dies; wasm32 does not
have that adjacency in a linear overwritable frame, survives, and yields the
garbage 0. **Two symptoms, one out-of-bounds write, no third thing** — which is
where frankwasm's inference was pointing, reached from the other end.

### A Variant LOCAL is fine, and the contrast is the proof

```
LOCAL:      lea -0x20(%rbp),%rdi ; mov $0x10,%rcx ; rep stos   <- 16 bytes reserved at -0x20
PARAMETER:  mov %rsi,-0x10(%rbp)                               <- 8 bytes, adjacent to self
```

The step function sizes a Variant LOCAL by its type and a Variant PARAMETER by
the ABI word. Only the parameter path is wrong, which is exactly what this
ticket's original boundary-finding said without knowing why.

### The fix is NOT to route it to the by-ref arm

Tempting and wrong: that arm persists the caller's ADDRESS, and a generator
outlives the `for-in` statement's argument temp. Persisting a pointer to a dead
temp trades a reproducible crash for a use-after-free.

The generator must OWN the Variant by value, which means all three parties
above have to agree on that one answer:
- caller stores the 16 bytes (`SlBlob`), not an Int64 conversion of them;
- the step function needs a real 16-byte frame home for the parameter, and
  every read of `c` must go through it rather than through the incoming pointer.

The machinery for exactly this already exists and is what NilPy uses — cell
promotion (`SymCellPtr`), whose own comment in this procedure says it is "how a
Nil Python generator persists a variant across a yield without this pass having
to understand variant ARC". A Pascal stackless generator does not cell-promote
its Variant parameters. That is the next thing to try, and it is a
normalise-don't-special-case fix rather than a fourth mechanism.

### Not verified

- That cell promotion is the right vehicle. It is a strong candidate because it
  already solves this problem for another frontend; I have not made it fire for
  a Pascal parameter.
- The wasm32 half of the "no adjacency" explanation. I am reasoning about why a
  stray write is survivable there; I did not read a wasm32 frame.
