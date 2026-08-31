---
track: O
prio: 55
type: feature
blocked-by: []
status: unfinished
owner: 
found: 2026-08-30
found-by: frank-optimize, profiling bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython
summary: "Container subscript is NilPy's worst primitive against CPython. RE-MEASURED 2026-08-31 on a quiet box: b[2] is now 117 ns vs 11 (10.6x, was 234 vs 12 = 19.2x) and d['k'] 262 vs 25 (10.6x, was 16.5x) -- the absolute cost roughly HALVED, and the -O3 reserve this ticket recorded as 30-40% is now 3-7% because the static-literal pass promoted to -O2 exactly as predicted. All FOUR previously-named drivers are now resolved, so a ~10x gap remains with no cause. New suspect, named categorically and then CORRECTED the same night: a subscript costs 11 out-of-line calls, 8 into retain/release/release-and-clear -- three genuinely DIFFERENT operations (confirmed by which refcount helpers each calls), not duplicates, so do not merge them. What is real is that each re-derives the value's type tag with six compares, so the tag is classified ~8x per subscript for a value whose type never changes. Benchmark committed as bench/nilpy_primitives.npy. Next step is confirm-then-decide, not a fix."
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

## The three open candidates are now all measured — 2026-08-30, later the same day

The section below listed three unmeasured candidates "in no order". All three
have since been measured, and **none of them is work for this ticket**:

| candidate | verdict |
| --- | --- |
| per-call managed-slot init/finalize (`o.m(1)` at ~390 ns, zero allocations) | **Was a codegen bug, and it is fixed** — frankA's `d27b4a28a`. The cause was neither the zeroing nor the branch: `AN_SEQ` called `IRFlushPostCallIntf` once per statement, so a temp created inside an `if` had its finalize emitted into the **merge block** and ran on every call. The isolated repro went 47x -> ~1.8x. |
| RTL accessors not inlined / the `-O3` tier recovering 30-40% | **Named:** `EmitStaticLitHandle` (`ir_codegen.inc:3480`), the static string-literal pass. Promoting that one gate to `-O2` is 20% of `-O3`'s 28% on the compiler's own workload. It is a tier/promotion decision, not subscript work — `decide-the-o3-tier-is-34-percent-faster-and-nothing-gates-it` [U]. **This is also the dict half of this very ticket**: `d['k']`'s remaining allocation is the literal key, which that pass removes. |
| 16-byte `rep stosb` clears for variant slots | **~4%, under the noise floor.** Every NilPy Variant local is zeroed 3-4x in one prologue by three passes that do not know about each other, invariant across `-O0..-O3`; removing one is unmeasurable at box load 6.5. Recorded under the managed-temps ticket, deliberately not filed separately. `991fa5c15` fixed the managed-record half. |

**So the honest state of this ticket is: it is waiting on a re-measurement, not
an investigation.** `b[2]` was 149 ns after my fix, against CPython's 3 ns
marginal. Two of the three drivers above have since been fixed or named, and
neither has been re-measured against subscript because the box has been at load
6-14 all evening and a 41%-scale A/B needs better than that. **Whoever picks it
up should re-measure first and re-scope second** — the remaining gap may be
much smaller than the 149 ns this ticket records, and re-deriving a plan against
a stale number is the failure this ticket's own notes warn about.

### Originally still open — superseded by the table above

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

## 2026-08-31 (frank-optimize) — the re-measurement this ticket was parked for. Headline halved; all four named drivers are gone; ONE new suspect

Parked waiting for a quiet box. Box at load ~4.4, compiler `3c31befa1704`.
**Re-measured first and re-scoped second**, in that order, per the instruction
above.

### The numbers, min-of-5 each side, both run back to back on this box

| operation | pxx then | **pxx now** | ratio then | **ratio now** |
| --- | ---: | ---: | ---: | ---: |
| `b[2]` list, const index | 234 ns | **117.2** | 19.2x | **10.6x** |
| `b[k]` list, var index | 229 ns | **117.3** | 9.4x | 11.4x |
| `d['AAA']` dict | 495 ns | **261.7** | 16.5x | **10.6x** |
| `d.get('AAA')` | 504 ns | **263.4** | 11.1x | 6.6x |
| `f.body[f.ip]` | 492 ns | **310.4** | 15.0x | 13.9x |
| `s.append`+`pop` | 654 ns | **397.9** | 8.6x | 6.1x |
| `isinstance(t,(int,float))` | 62 ns | 54.1 | 0.39x | 0.39x |

**pxx's absolute cost roughly halved on the whole subscript family.** `d['AAA']`
495 → 262 is the static-literal promotion landing exactly where this ticket
predicted it would.

**Read the ratios with care, and this is why the benchmark is now committed.**
`b[k]`'s ratio got *worse* (9.4x → 11.4x) while pxx got *twice as fast*, because
CPython's own number moved 24 → 10.3 ns between the two runs. **A ratio moves
with both sides**, so only the paired same-box run is comparable, and the "then"
column is a different box-day. The absolute pxx column is the one that travels.

### The `-O3` reserve is GONE, and that is a confirmed prediction, not a loss

This ticket recorded *"`-O3` already recovers 30-40% of subscript cost over
`-O2`, which suggests an inlining-tier question"*. Measured now, min-of-3:

| | `-O2` | `-O3` | gain |
| --- | ---: | ---: | ---: |
| `b[2]` | 116.6 | 108.4 | **7.0%** |
| `d['AAA']` | 260.6 | 244.6 | **6.1%** |
| `f.body[f.ip]` | 315.0 | 302.6 | 3.9% |

**3-7%, not 30-40%.** The thing `-O3` was holding was `EmitStaticLitHandle`,
which is now at `-O2` — so the tier gap closed by promotion, exactly as this
ticket said it would. **Inlining tier is no longer a lever here.**

### So all four previously-named drivers are resolved, and the gap is ~10x with no cause

Allocation (fixed), managed-temp init (`d27b4a28a`), the static-literal pass
(promoted), the `-O3` tier gap (closed). `b[2]` is still **117 ns against
CPython's 11**. **A ticket whose every suspect has been cleared is not a solved
ticket** — it is an open question with no owner for the residual, which is the
state that reads as finished.

### The new suspect, named categorically — 11 calls per subscript, 8 into tag dispatch

Zero-variance method, no profiler: compile the loop **with** and **without**
`x = b[2]` and diff the emitted binaries. Adding the statement costs **+57
instructions and +11 static call sites**. pxx emits a minimal ELF with no symbol
table, so the targets are bare addresses; six gain calls:

| target | added | what the code is |
| --- | ---: | --- |
| `0x4004c5` | +4 | tag dispatch, 21 instructions |
| `0x400529` | +2 | tag dispatch, 19 instructions |
| `0x40057e` | +2 | tag dispatch, 19 instructions |
| `0x40870e` | +1 | global-guard prologue |
| `0x40acbe` | +1 | small accessor, full frame |
| `0x452736` | +1 | `lea; xor; mov $0x10,%rcx` — the 16-byte variant clear |

**The three tag dispatchers share an identical 18-instruction preamble** and
diverge only in the tail (21 vs 19 instructions; the long one writes a tag back).
Each re-tests the value's type tag with **six compare-and-branch pairs** before
doing anything. **8 of the 11 added calls are into these three.**

So the shape of the remaining cost is: **a list subscript re-derives the type tag
from scratch, out of line, eight times.** That is one concept served by three
near-identical mechanisms, which `root-cause-over-microfix.md` calls a design
flaw rather than a smell — but they are **not** literal duplicates, and anyone
acting on this should confirm the tails are genuinely specialisations before
proposing to merge them.

### What I did NOT do

Not attempted the fix. Removing repeated out-of-line tag dispatch is type
inference or an inline cache, not a peephole, and it is a fresh investigation
rather than the re-scope this ticket asked for. **Next step for whoever takes
it: confirm the three tails are specialisations of one routine, then decide
between merging them and not calling them at all.**

`bench/nilpy_primitives.npy` is **committed** now, with the paired-run
instructions in its header — this ticket's numbers were unreproducible four days
later because the benchmark lived in a scratchpad.

## Parked 2026-08-31

re-measurement and re-scope done; the fix is a fresh investigation (out-of-line tag dispatch), not this ticket's remaining work

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

### CORRECTION to the section above, by me, same night — the three are NOT duplicates and must not be merged

The section above called the three tag dispatchers *"one concept served by three
near-identical mechanisms, which `root-cause-over-microfix.md` calls a design
flaw"*, hedged with *"confirm the tails are genuinely specialisations before
proposing to merge them."* **I ran that confirm step. The answer is no, and the
design-flaw reading is withdrawn.**

Neither of the two shorter routines calls the longer one, and each calls a
**different** pair of helpers. Disassembling those helpers settles what they are:

| helper | first instructions | what it is |
| --- | --- | --- |
| `0x40036a` | `test rax,rax; je; incq -0x10(%rax)` | string **retain** |
| `0x400378` | `test rax,rax; je; decq -0x10(%rax); jne; sub $0x18` | string **release** + free path |
| `0x4003aa` | `push rax,rcx,rdx,rsi,rdi,r8…` | object **retain** (saves all registers) |
| `0x4003cd` | same prologue | object **release** |

So the family is:

| routine | calls | therefore |
| --- | --- | --- |
| `0x40057e` | str retain + obj retain | **RETAIN** |
| `0x400529` | str release + obj release | **RELEASE** |
| `0x4004c5` | str release + obj release, **then writes the tag back** | **RELEASE-AND-CLEAR** (`PyVarSlotClear`: `dst^.VType := 0; dst^.Payload := 0`) |

**Three genuinely different operations that happen to share a prologue.** That
prologue is `PyVarSlotManaged` + `PyVarSlotIsObj` (`pylib.pas:5334,5345`)
inlined into each — the same *classification*, not the same *routine*. Merging
them would be wrong.

**What survives, and it is the real finding:** a subscript makes **11 out-of-line
calls, 8 of them into retain/release/clear, and every one of those re-derives
the value's type tag from scratch** with six compare-and-branch pairs. The tag
is classified ~8 times per subscript for a value whose type never changes across
those 8 operations.

**So the lever is not merging routines. It is one of three, in increasing order
of ambition:** inline the classification so the *call* disappears; classify once
per statement and pass the result to the slot ops; or know the type statically
and emit no dispatch at all. Which of those is right is a real design question
and is **not** settled by this measurement — it is the next investigation, and
it now starts from a correct picture instead of my wrong one.

**Recorded rather than quietly edited**, because the wrong version was published
in the section immediately above and someone could have acted on it: "merge the
three duplicates" would have been a refactor toward a bug.

## Parked 2026-08-31

confirm step done and it refuted my own suspect framing; next is a design choice between inlining the tag classification, hoisting it per statement, or eliminating it statically

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.
