---
track: O
prio: 55
type: feature
blocked-by: []
status: unfinished
owner: frank-optimize
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "Container subscript is NilPy's worst primitive against CPython by a wide margin: b[2] costs 234 ns against CPython's 12 (19x) and d['k'] 495 against 30 (16x), while pxx BEATS CPython at isinstance (0.39x), len (0.14x), exec (0.92x) and a zero-argument call (0.10x). Subscript is the largest single gap and the one with an obvious mechanism; it is also on the per-token path of every interpreter-shaped NilPy program."
---

# NilPy container subscript is 15-19x slower than CPython

## Measured

Marginal cost of one added statement in a NilPy `while` loop, 300k iterations,
x86-64, compiler `0604b414089f`, binary `883476f0abaf`, box load 2.05 flat
across the whole run. Baseline subtracted; both halves run back to back in one
process each.

| operation | pxx | CPython 3.14.4 | ratio |
| --- | ---: | ---: | ---: |
| `b[2]` list subscript, constant index | **234 ns** | 12 ns | **19.2x** |
| `b[k]` list subscript, variable index | 229 ns | 24 ns | 9.4x |
| `d['k']` dict subscript | **495 ns** | 30 ns | **16.5x** |
| `d.get('k')` | 504 ns | 46 ns | 11.1x |
| `f.body[f.ip]` (2 attrs + subscript) | 492 ns | 33 ns | 15.0x |
| `s.append` + `s.pop` | 654 ns | 76 ns | 8.6x |
| `tok.word` attribute read | 57 ns | 10 ns | 5.5x |
| `isinstance(t, (int, float))` | 62 ns | 158 ns | **0.39x** |
| `isinstance(t, int)` | 47 ns | 64 ns | 0.73x |
| `len(b)` | 3 ns | 24 ns | **0.14x** |
| call, no args and no locals | 3.5 ns | 37 ns | **0.10x** |
| `exec(src, g, ns)` + call | 68.8 µs | 74.9 µs | 0.92x |

Reproduce: `$SCRATCH/uf/hot.npy`, `disp.npy`, `call.npy` (self-contained, no
uforth, no RTL flags).

**Read the bottom half of that table before starting.** NilPy is not uniformly
slower than CPython — it wins at `isinstance`, `len`, `exec` and a bare call,
some of them by 3-10x. Subscript is not "one more thing that is slow"; it is an
outlier against the language's own baseline, which is what makes it worth a
ticket rather than a shrug.

## Why it matters beyond a micro-benchmark

Every interpreter-shaped NilPy program subscripts per token. In `uforth.py`,
`run_forth_word`'s inner loop does `frame.body[frame.ip]` once per token, and
`lookup_word` does two dict subscripts per word. A gdb-sampled profile of
pxx-compiled uforth (593 samples, five ANS word sets) put **96% of samples in
the RTL and 67% in the first 130 KB of `.text`** — the string, header and heap
core. The allocator entry alone was 12.3%, the free path 7.6%.

That profile is also the reason this ticket is scoped to subscript and not sold
as "the fix for uforth": see
`bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython`, where three
other plausible causes were each eliminated by building the change and measuring
that it did nothing. **Do not assume this one is different — measure uforth
before and after, and expect less than the ratio suggests.**

## Where to look

Unmeasured, in likely order:

1. **The path a subscript takes per element.** 234 ns for a four-element list of
   small ints is ~800 cycles; that is not a bounds check and a load. Candidates:
   a variant tag dispatch per access, a managed retain/release on the element, a
   generic `pylist_at` that boxes, or a managed temp for the result (see
   `bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-finalized`,
   which is the same family and may be the whole answer here too).
2. **Constant vs variable index are the same cost** (234 vs 229), so nothing is
   specialising on a literal index today — a cheap win if the generic path
   stays.
3. **Dict is 2x list** (495 vs 234), consistent with hashing a short string per
   access; `d.get` costs the same as `d[...]`, so the method-call form is not
   the problem.

Per Track O's rule this lands behind `-O3` if it is a pass, and promotes to `-O2`
per-pass after the full gate. If it turns out to be an RTL shape fix rather than
a pass — which the profile suggests — the `-O3` staging does not apply and the
gate is the ordinary one.

## Gate

`make compiler/pascal26` (fixedpoint) + `gate.sh quick`; `test-nilpy` is Track
T's to sweep. A correctness risk exists if element retain/release is what gets
removed, so the heap-flatness repros from the managed-string leak tickets are
the right regression probe, not just wall-clock.

---

## 2026-08-30 frank-optimize — one allocation removed, −41%. Still open.

### The mechanism, measured

Container subscript **heap-allocated per access**, and cost tracked the count
at ~190 ns per allocation. Counted with a gdb breakpoint on the allocator
entry, differenced between an n=1000 and an n=3000 run of the same loop so
startup allocations cancel:

| statement | before | after | CPython |
| --- | ---: | ---: | ---: |
| `x = 7` (control — stays flat in n) | 0 | 0 | 0 |
| `x = o.f` attribute | 0 | 0 | 0 |
| `x = b[2]` list | **1** | **0** | 0 |
| `x = s[0]` list of str | 1 | 0 | 0 |
| `st.append(1)` | 1 | 0 | 0 |
| `x = d['k']` dict | 2 | 1 | 0 |

The site was `PyVarSlotSet` (pylib.pas), which every variant slot copy goes
through:

```pascal
var s: AnsiString;
begin
  if dst = src then Exit;
  s := '';                       { every call, including the integer path }
```

Under NilPy that is a real 25-byte block, not a cleared pointer, because
`PXX_NILPY_STR` makes a zero-length string a real block on purpose
(`decide-nilpy-none-str-representation`, so `"" is None` stops answering True).
That is why the same line is free in Pascal and costs an allocation here — and
it is why a Pascal-only reading of the source would have missed it.

Fixed by splitting the managed half into `PyVarSlotSetStr`, the same shape as
`promocore.pas:796` and `0c3ad8a10`. **Third instance of that rule today.**

### Measured, both binaries back to back in the same second (box load 4.7)

| | before | after | |
| --- | ---: | ---: | ---: |
| `b[2]` | 254 ns | **149 ns** | −41% |
| `b[k]` | 237 ns | 147 ns | −38% |
| `f.body[f.ip]` | 478 ns | 364 ns | −24% |
| `s.append`+`pop` | 687 ns | 460 ns | −33% |
| `vm.push`+`pop` | 768 ns | 587 ns | −24% |
| `d['k']` | 501 ns | 492 ns | −2% |
| `isinstance` | 48 ns | 48 ns | — (untouched) |

Marginal cost with the loop baseline subtracted. Correctness: five uforth ANS
word sets match CPython byte for byte; a targeted aliasing/refcount stress
(self-assignment of a managed slot, managed↔unmanaged transitions, tuple swap
of nested lists, a string outliving its container) matches; `gate.sh quick`
GREEN; self-host fixedpoint `965236b0f5ab`.

### Why dict only moved 2%, and why that half is NOT this ticket's

The dict's remaining allocation is **not** in `TPyDict.fetch` (which is already
clean, and uses the same `PyVarSlotInit` the list does). It is the **literal key
being re-materialised on the heap per lookup** — `d["k"]` allocates, `d[kk]`
with the key hoisted into a local does not, and `x = "k"` alone allocates with
no dict involved.

That is `PXXStrFromLit`, and it is **already fixed behind `-O3`** by the
`PXX_FLAG_STATIC` pass that landed earlier the same day (see the parent
ticket's "FOLLOW-UP 1 LANDED" section). Measured just now: marginal cost of
`x = "k"` is **80.3 ns at -O2 and 0.0 ns at -O3**. So the dict gap closes when
that pass promotes to `-O2`, and nothing should be done about it here.

I rediscovered it from a disassembly before finding it in the parent ticket.
Recorded so the next reader does not spend the same hour.

### Still open — this is why the ticket is not resolved

`b[2]` is 149 ns against CPython's 3 ns marginal. Removing the allocation took
41%; the rest is not allocation. What is left, unmeasured and in no order:

- **Per-call managed-slot init/finalize.** `o.m(1)` costs ~390 ns with **zero**
  allocations, so this is a second driver entirely. A call with no arguments and
  no locals costs 3.5 ns (10x faster than CPython); each argument or local adds
  50-130 ns. This is the same family as
  `bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-finalized`.
- **The RTL's one-line accessors are not inlined.** Sampling the subscript loop
  showed several routines that spill and reload their argument eight times to
  perform a single `mov (%rax),%rax`, each behind a full stack frame and a call.
  `-O3` already recovers 30-40% of subscript cost over `-O2`, which suggests
  some of this is an inlining-tier question rather than a missing pass.
- **`rep movsb` / `rep stosb` for 16-byte variant copies and clears**, where two
  `mov`s would do. Small, general, and independent of the above.

### Do not repeat

The allocation counter used here is worth keeping: `objdump` to find the
allocator entry, a gdb breakpoint on it, and a difference between two n so
startup cancels. It answers "how many allocations does this construct do",
which is what the parent ticket's "Still open" section says three sessions
reached for callgrind to learn (callgrind is not installed here, and
`perf_event_paranoid` is 4).

**Watch the failure mode it has:** if the binary fails to build or the entry
address is not found, a naive script reports **0 allocations**, which reads
exactly like a fix. It did that to me twice — once from a filename with a space
in it, once from a locator that silently found nothing — and both times the
false reading was "0", the answer I was hoping for. Make the script print
`NOBIN`/`NOADDR` rather than defaulting to zero.
