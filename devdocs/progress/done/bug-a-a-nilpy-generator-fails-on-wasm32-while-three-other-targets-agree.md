---
track: A
prio: 40
type: bug
blocked-by: []
status: done
summary: "FIXED 2026-09-06. Root cause was NOT in the generator machinery, the slgen transform or NilPy at all: a Variant stored THROUGH A POINTER did not reach the pointee on wasm32. A cell-promoted generator parameter gets a 16-byte pycell_new cell and the caller seeds it with `cell^ := arg` -- exactly that shape -- so the cell stayed pristine (tag 0) and every such parameter read None. WasmVariantAddr dispatched on IRKind = IR_LOAD_SYM alone, which is two questions in one opcode: a VARIANT symbol's address is its slot, a POINTER symbol's address is the slot's VALUE. Fixed by testing the symbol type. Both repros in this ticket now agree with native. Regression test test/wasm/check_variantptr.sh, wired into check_all.sh, with the pre-fix compiler as the positive control."
---

# A NilPy generator fails on wasm32 while three other targets agree

```python
def g(n):
    i = 0
    while i < n:
        yield i
        i = i + 1
s = 0
for x in g(4):
    s = s + x
print(s)
```

native / i386 / arm32 / aarch64: `6`, rc=0.
wasm32: `Unhandled exception`, rc=1, `exit with invalid exit status outside of
[0..126)`, backtrace at wasm function 1751. The BUILD exits 0 and prints `ok:`.

Not the double-write bug
([[bug-a-wasm32-emits-a-separate-function-per-compileast-call-so-a-proc-built-in-two-calls-loses-a-body]]):
the rewrite counter prints nothing for this source, and it is proven working on
the same binary — it fires on `procedure Fill(out s: string)` and on
`test/test_managed_var_param.pas`.

## Correction — this ticket was filed with three rows that were already fixed

As first filed it claimed a default argument, two defaults and a user-written
`__init__` also trapped on wasm32 (rc=134), and was ranked 55 on the strength of
"ordinary NilPy is unusable there". **All three pass at 6f86e8f48**, printing the
same values as every other target. Only the generator survives, so the ticket is
retitled and re-ranked to 40.

**How the error was made, because it is the reusable part.** The traps were
measured at b0275ecc1 and were real then. Between that and filing I pulled to
6f86e8f48 and rebuilt — and re-ran the six shapes only to read the REWRITE
COUNTER, never to re-read whether they still failed. So a stale run outcome
travelled beside a fresh instrument reading, in the same table, and the stale
half looked as current as the fresh one. The fix that landed in between is
somewhere in 34179225a..6f86e8f48, which contains two wasm32 commits
(`8fb2668c0`, `9b67b266d`); NOT bisected, so this names a range and not a cause.

Caught by franka-29, who could not reproduce a single failing row from the
descriptions and said so instead of assuming its own minimisation was at fault.

The causal story the first filing gave — that these shapes call one of the two
bodies emitted as `unreachable` (`PyBindHostKwArgs`,
`PyBoundFnCallvnMaskBody`) — was INFERENCE from the census line and was never
traced. Those two bodies are present in PASSING builds too, so their presence
was never the discriminator. Whether the generator reaches one of them is open
and is the first thing to check here.

---

## DIAGNOSIS 2026-09-06 (frankwasm) — it is the PARAMETER, not the loop

Parked with the diagnosis banked; no fix. Compiler `f2f11cd439e7`, and every
row below reproduces on `stable_pinned` too, so none of it is recent.

**The repro in this ticket points at the wrong feature, and that cost me an
hour.** Its generator has a `while` loop, so the obvious reduction is "loops in
generators", and a six-shape battery appeared to confirm it — including
`m_yield_after_loop`, whose loop sits *before* the only yield and which still
fails. I wrote down "any loop inside a generator body breaks it on wasm32".

**That was wrong, and the row that broke it has no control flow at all:**

```python
def g(n):
    yield n
for x in g(7):
    print(x)
```

native `7`, wasm32 `None`. Every failing shape I had took a bound parameter and
every passing one did not; I had varied two things and read the correlation off
the one I was looking at.

### The boundary, stated as the shape that fails

**A NilPy generator that READS a parameter yields `None` on wasm32.**

| shape | native | wasm32 |
| --- | --- | --- |
| `def g(n): yield n` | 7 | **None** |
| `def g(a, b): yield a; yield b` | 4, 9 | **None** |
| `def g(s): yield s` (string param) | hi | **None** |
| `def g(n): yield 7` — param declared, NEVER READ | 7 | 7 |
| `def g(): yield 7` | 7 | 7 |
| `def g(): yield 1; yield 2; yield 3` | 1,2,3 | 1,2,3 |
| `def g(): i=0; while i<3: i=i+1; yield i` (loop, no param) | 3 | 3 |

So: resumption across yields is fine, multiple yields are fine, and **a loop in
a generator is fine when nothing is parameterised**. `def g(n): i = n + 1;
yield i` yields `1` on wasm32 — i.e. `0 + 1` — which is the same fact with the
value visible: the parameter reads as zero.

### The discriminator that says where NOT to look

**A Pascal `generator; stackless;` with an Integer parameter WORKS on wasm32:**

```pascal
function Gen(n: Integer): Integer; generator; stackless;
var i: Integer;
begin i := 0; while i < n do begin yield i; i := i + 1; end; end;
```

`sum=6` on both native and wasm32 — the exact program shape this ticket's NilPy
repro has. So the shared slgen state-machine transform, the one-word slot path,
the `$pc` dispatch and wasm32's unstructured-CFG lowering are all fine. What
differs is how a NilPy parameter is REPRESENTED.

### Ruled out, by experiment rather than by reading

`bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate` looks
like the same bug and is not. `WasmEmitManagedLocals` genuinely does not consult
`SymSkipScopeExitRelease` (zero occurrences), and its own comment in
`ir_codegen.inc:13757` says that path is UNCHECKED — so it reads like a
confirmed cause. I added the guard, exactly as the other six arms have it:

```pascal
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if (not SymSkipScopeExitRelease(i)) and
         (Syms[i].Kind = skLocal) and not Syms[i].IsRef and (i <> retSym) then
```

**It made things worse.** No failing row was fixed, and two PASSING rows
regressed: `def g(): yield 1; yield 2` went from `1,2` to `1`. Reverted. That
is data about the model, not a partial fix — whatever the release loop is doing
for a generator on wasm32, the no-parameter cases currently DEPEND on it, so
that ticket cannot be closed by adding the guard alone and the two tickets
should not be merged on resemblance.

### Where to look next

`AssignStacklessSlots` (`compiler/pasparser_stmt.inc:~2410`) decides a symbol's
slot region per type, and its two multi-word arms are the candidates, since the
Pascal Integer parameter that works takes the one-word arm:

  - `tyVariant` → two words, blob copy;
  - `TypeIsPromoInt` → `(TypeSlotSize(tk) + 7) div 8` words, and **that size is
    target-dependent** (8 bytes as tyPromoInt32 on a 32-bit target, 16 as
    tyPromoInt64 on a 64-bit one).

The target-dependence is suggestive and is NOT on its own an explanation:
i386 and arm32 are also 32-bit and this ticket records them passing. So a plain
"32-bit assumption" story is already contradicted by the ticket's own data, and
whatever is wrong is wasm32-specific on top of the representation.

Also worth reading first: `if SymCellPtr[i] >= 0 then Continue;` at the top of
that loop skips cell-promoted names entirely. If a NilPy parameter is
cell-promoted, its slot is the cell POINTER rather than the value, and that is a
different object to get wrong. **Unmeasured** — I did not check whether NilPy
parameters are cell-promoted, and it should be the first thing checked rather
than assumed, because it would explain the Pascal/NilPy split directly.

### Related, filed separately rather than merged

`bug-a-a-stackless-generator-with-a-variant-parameter-yields-nothing-on-native-and-a-wrong-value-on-wasm32`
— found while reducing this. A Pascal `Gen(n: Variant)` generator produces zero
iterations **on native**, so it is an all-targets bug with a six-line Pascal
repro. It resembles this one and has a different signature (this one is correct
on native), which is exactly why it is its own ticket.

---

## 2026-09-06 (frankwasm, later) — narrowed to ONE step, with the probe

Re-measured at `0f6b627d7` (frankS's Variant-parameter fix), compiler
`c8dc944237a5`. **Still broken, unchanged**, and that is informative rather
than disappointing: it separates this row from the Variant one for good.

| repro | native | wasm32 |
| --- | --- | --- |
| `def g(n): yield n` | 7 | **None** |
| `def g(n): i=0; while i<n: yield i; i=i+1` | 6 | **Unhandled exception** |
| `def g(n): for i in range(n): yield i` | 6 | **0** |
| `def g(s): yield s` | hi | **None** |

frankS predicted this: NilPy Variant params are already `IsRef`, so they take
the by-ref arm and never reach the new predicate. Confirmed by measurement, not
taken on trust.

### The parameter has NO instance slot at all

`PXXDBG=a.slslot` on `def g(n): yield n`:

```
caller: proc=g nargs=1 instsize=72 paramcount=2
  arg1: storeoff=48 paramsym=… symgenslot=-1 realoff=40 tk=22
```

**`symgenslot=-1`, and there are no `assign:` lines whatsoever** —
`AssignStacklessSlots` gives this generator no persistent slots, because the
parameter is CELL-PROMOTED and the loop's `if SymCellPtr[i] >= 0 then Continue;`
skips it by design (*"its storage is the heap cell, and every read and write
already spells itself `cell^`"*).

So the for-in desugar stores the cell pointer at `SL_OFF_SLOTS + 8*(k-1)` = 48
by ARGUMENT INDEX, into a slot nothing reads. `realoff=40` is the probe
computing `48 + 8*(-1)`, i.e. an address BELOW `SL_OFF_SLOTS` — the instrument
reporting a nonsense offset honestly rather than a plausible wrong one.

**That table is byte-identical on native and wasm32**, and native works. Third
time in this neighbourhood that every compile-time quantity agrees while the
behaviour diverges, so the slot machinery is exonerated here the same way it
was for the Variant bug.

### The step that is actually missing

```python
def g(n):
    n = 5
    yield n
```

**`5` on BOTH targets.** So the cell storage, the resume, the yield and the
whole state machine are fine on wasm32 once the cell holds a value. What is
missing is only the **initialisation of the cell from the ARGUMENT** —
`GenMakeVariantArgCell`'s `pycell_new` followed by `cell^ := arg`, or the
delivery of that pointer to where the body's `cell^` reads it.

That is the one step to instrument next, and it is a runtime question on
wasm32, not a layout one. Everything either side of it is measured working.

### What this retires

The earlier section's "look at `AssignStacklessSlots`'s multi-word arms" is
**wrong** and should not be followed: this parameter never reaches any of those
arms. The `SymCellPtr` line it flagged as *"unmeasured, and it should be the
first thing checked"* was the right instinct, and the answer is yes — it is
cell-promoted, and that is why it has no slot.


## RESOLVED 2026-09-06 — the cause was a pointer store, not a generator

The narrowing that got there, each row measured on both targets:

| shape | native | wasm32 (before) |
| --- | --- | --- |
| `def g(n): yield n` | 9 | **None** |
| `def g(n): yield 1; yield n` | 1 9 | 1 **None** |
| `def g(n): yield n; n = 5; yield n; n = n+1; yield n` | 9 5 6 | **None** 5 6 |
| `def g(n): n = 5; yield n; yield n` | 5 5 | 5 5 |
| `def g(a,b): a = 7; yield 0; b = 8; yield a; yield b` | 0 7 8 | 0 7 8 |
| `def g(a,b): a = 7; yield 0; yield b` | 0 2 | 0 **None** |

Row 3 is the one that carries the weight: the initial read is empty, then a
write lands and SURVIVES two further yields including a read-modify-write. So
the cell, the resume, the yield and the state machine were all correct on
wasm32 and only the INITIALISATION of the cell from the argument was missing.

Row 5 kills the null-pointer reading: two parameters do not alias, so each cell
is distinct and valid, and every value there crosses a yield so no fold can
explain it. Row 6 is the sharpest — within ONE generator, one cell is correct
and the other empty, differing only by whether the body ever wrote to it. A
never-written cell reading `None` rather than aliasing means a FRESH cell, and
`pycell_new` zeroes `VType`, which is exactly what `None` is.

**The IR was structurally identical on both targets** (caller and callee both
diffed; every difference was symbol/proc renumbering), which is what moved the
search into the wasm backend.

Root cause and fix: `WasmVariantAddr` in `compiler/ir_codegen_wasm32.inc`
dispatched on `IRKind = IR_LOAD_SYM` alone. That opcode covers a load of a
VARIANT symbol, whose address is its slot, and a load of a POINTER symbol,
whose address is the slot's VALUE; it answered the first for both. Measured
bytes for `pv^ := 42` into a variant holding 0:

```
native  1 0 0 0 0 0 0 0 | 42 0 0 0 0 0 0 0    tag=1, payload=42
wasm32 42 0 0 0 0 0 0 0 |  0 0 0 0 0 0 0 0    tag=42, payload=0
```

Minimal repro, no NilPy and no generator: `p: ^Variant; New(p); p^ := 42;`
answers 42 native and 0 on wasm32.

**Two earlier hypotheses in this ticket are now positively retired, not merely
unconfirmed.** The `while` loop was never involved. And
`bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate`
is confirmed a separate defect — adding that guard fixed nothing here and
regressed two passing rows.

**What the diagnosis got wrong, recorded because the shape recurs:** this
ticket's earlier `storeoff=48 / realoff=40` reading was a true measurement of
`a.slslot` and a false lead. `realoff=40` is the probe computing `48 + 8*(-1)`
for a symbol with `symgenslot=-1`, i.e. a nonsense address reported honestly.
It looked like a caller/callee offset disagreement and there was none: the
generator prologue reads offset 48, the caller writes offset 48, and the IR
agrees on both targets.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
