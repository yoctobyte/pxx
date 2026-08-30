---
track: O
prio: 55
type: feature
blocked-by: []
status: working
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
