---
track: A
prio: 40
type: bug
blocked-by: []
status: backlog
summary: "DIAGNOSED 2026-09-06, not fixed, no compiler change held -- and the REPRO IN THIS TICKET POINTS AT THE WRONG FEATURE. It is not the `while` loop and not the yield: a NilPy generator that READS A PARAMETER yields None on wasm32, with no control flow needed -- `def g(n): yield n` / `for x in g(7)` gives 7 native, None wasm32. Declaring a parameter and never reading it is FINE; multiple yields, and a loop in a generator that takes no parameter, are both fine. `def g(n): i = n + 1; yield i` yields 1, i.e. the parameter reads as ZERO. The discriminator that says where NOT to look: a PASCAL `generator; stackless;` with an Integer parameter, the same program shape, WORKS on wasm32 -- so the slgen transform, the one-word slot path and the $pc dispatch are all fine, and what differs is how a NilPy parameter is REPRESENTED. bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate is NOT this bug: adding that guard fixed nothing and REGRESSED two passing rows (tested, then reverted). Pre-existing on pinned. Full shape battery and next steps in the diagnosis section at the bottom."
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
