---
type: refactor
track: A
prio: 45
status: open
summary: A Nil-Python string literal lowers to an IR const_str tagged tyString,
  which matches neither IRLowerCallArg's frozen->managed arm (scoped to the
  PASCAL node AN_STR_LIT) nor any backend's literal fast path — so five
  per-backend frozen-arg arms are load-bearing and cannot be deleted.
---

# NilPy const_str bypasses both the literal fast path and the call-arg funnel

Nothing is wrong today. This is the reason ten duplicated backend arms have to
stay, which is what makes it worth a ticket.

## The shape

```python
x = "a" * 3        # NilPy: reaches a backend frozen-arg arm
y = "ab"; x = y * 3   # does not
```

```
3: const_str a=7049 b=43 tk=4     <- NilPy literal, tagged tyString (FROZEN)
4: arg      a=3               tk=4
5: call     a=-44 b=4
```

The same two calls in Pascal (`P('literal'); P(s);`) reach neither arm: the
literal takes `EmitStaticLitHandle`, the variable takes `IRLowerCallArg`.

`IRLowerCallArg`'s frozen->managed arm excludes `ASTKind[argAST] = AN_STR_LIT`
deliberately, because routing a literal through a heap temp is a pessimisation.
That exclusion names a PASCAL AST node. A NilPy literal never becomes one, so it
falls through to whichever backend arm is next — and those arms convert it
correctly, which is why NilPy is green.

## What that costs

Five arms are PROVEN live by a canary build (2026-09-03, tip 8cd3d6eb4): each
was replaced by an `Error` carrying a per-site id and the non-Pascal corpus was
swept.

| arm | fires | population |
| --- | --- | --- |
| `x86-64/direct` | 61 | 30 distinct `.npy` sources |
| `x86-64/ordered-predicate` | 60 | same, `-O3` only |
| `i386/direct` | 120 | same |
| `arm32/direct` | 120 | same |
| `aarch64/direct` | 120 | same |
| `riscv32/direct` | 0 | **of 1932 compiles — vacuous** |
| `xtensa/direct` | 0 | **of 0 compiles — entirely vacuous** |
| `x86-64/ordered`, `/ctor`, `/method-indirect` | 0 | 5092 compiles |

riscv32 and xtensa are silent because NilPy cannot build for them at all
(`bug-a-nilpy-on-cross-targets-four-remaining-walls`): xtensa answers `a heap
arena needs mmap, which bare metal has not`. Their silence is not evidence.
Given i386/arm32/aarch64 all fire 120 times on the same sources, expect both to
become live the moment that ticket clears.

Deleting the arms is measurable damage, not a theoretical risk: with all ten
removed the self-host fixedpoint still held and `gate.sh quick` went RED —
`test/quick_canary_nilpy.npy` fell from `total ok 36 / 36` to `ok 23` and
segfaulted.

## The fix

Normalise the frontends, not the backends: give a NilPy constant string the same
treatment a Pascal `AN_STR_LIT` gets, so the literal fast path claims it and
`IRLowerCallArg` remains the single funnel for everything else. C, Rust and Zig
fired nothing in this sweep, but they were not shown to PRODUCE this shape
either — check what each frontend emits for a constant string before assuming
Pascal and NilPy are the only two answers.

## One asymmetry noticed and NOT constructed

`aarch64`, `riscv32` and `xtensa` guard their arm with
`(not Procs[procIdx].Params[nArgs].IsRef)`; `i386` and `arm32` do not. If a
`var AnsiString` parameter can receive a frozen argument, those two would
convert where the other three pass the slot through. **I did not build that
case** — the guards may be unreachable on both. Construct it before treating
this paragraph as a defect.
