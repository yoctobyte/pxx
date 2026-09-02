---
slug: feature-a-a-stackful-generator-is-x86-64-only-so-examples-chess-cannot-target-anything-else
track: A
prio: 45
type: feature
status: done
found: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "A plain `generator;` uses the STACKFUL lowering, which needs CoSwitch (x86-64 asm) and refuses on every other target. examples/chess/chess.pas uses one for move generation, so chess builds for x86-64 alone — the only program in examples/ that fails on ALL five cross targets. MEASURED: the accepted alternative, `generator; stackless;` with `uses slgen`, works and gives identical answers on all six targets, so the refusal is NOT load-bearing here. The open question is whether chess's generator can be expressed stacklessly, which is a capability question, not a porting one."
---

# A stackful generator is x86-64-only, so `examples/chess` cannot target anything else

From the cross-backend `examples/` sweep (2026-09-02) — the only program that
failed on **all five** cross targets, and identically:

```
chess | i386:BUILD arm32:BUILD riscv32:BUILD aarch64:BUILD xtensa:BUILD
        generator: only the x86-64 target is supported for the stackful backend
        (use `stackless` for other targets)
```

`pasparser_proc.inc:2550`. `chess.pas:472` declares
`function GenMoves(const pos: TPosition): TMove; generator;` — no `stackless`,
so it takes the stackful lowering, whose body runs on a heap coroutine stack
swapped by `CoSwitch`, which is x86-64 assembly.

## The alternative spelling was checked, and it works

Because a refusal can be the only thing keeping a program correct, the accepted
spelling was run before filing rather than assumed:

```pascal
uses slgen;
function CountUp(n: Integer): Integer; generator; stackless;
var i: Integer;
begin for i := 1 to n do yield i; end;
```

| target | result |
| --- | --- |
| x86-64, i386, arm32, aarch64, riscv32, xtensa | `sum=15 sum2=60` — **identical on all six** |

So the stackless backend genuinely runs everywhere and agrees with x86-64. This
is unlike the `parallel for` case (`4c94d248d`), where both compiling spellings
were broken and only the refusal was safe.

(It needs `uses slgen` in scope, and says so clearly when it is missing.)

## So what is actually open

**Not** "port CoSwitch to five architectures" as a first move. The question is
whether chess's generator NEEDS the stackful capability:

- **stackful** can suspend from inside nested calls, because it owns a stack.
- **stackless** is a state-machine transform of the generator body, so a `yield`
  reachable only through a helper call is not expressible.

`GenMoves` should be read for whether it yields from nested helpers. If it does
not, chess becomes cross-target by adding two words and this is a Track B/E
change to the example. If it does, the choice is between restructuring chess and
implementing a stackful backend elsewhere — and that is a real decision, worth
Track U rather than a guess.

**Do not "fix" this by rewriting chess without checking that**, and do not read
the passing table above as evidence that chess specifically will work: it is
evidence about a generator that yields from its own body.

## Gate

`examples/chess/chess.pas` builds and plays identically on at least one cross
target. Whatever lands must state which of the two capability answers it took.

## Bound

HEAD `eabd599ee`, compiler `58620a6d3662`. Six-target stackless table measured;
chess itself was NOT converted or run on a cross target.

## Resolved 2026-09-02 (frankC, Track A) — the capability answer is STACKLESS SUFFICES

The ticket demanded that whatever lands say which of the two capability answers
it took. **Stackless suffices, and it was measured, not assumed.**

The question was whether `GenMoves` yields from a nested helper — stackful owns a
stack and can suspend from inside a call; stackless is a state-machine transform
of the body, so a `yield` reachable only through a helper is not expressible.
Counted over the whole file: **all 24 `yield`s are lexically inside `GenMoves`'
own body**, and the only other match in the file is the section comment
`{ ===== Move generation as a generator (yield + for-in) ===== }` sitting under
`UnmakeMove`. `MkMove(...)` is a call, but it produces the yielded VALUE and does
not itself yield, which is the distinction that decides this.

So the change is two words plus `uses slgen`, and it is a change to the EXAMPLE,
not to the compiler. No backend was ported and `CoSwitch` was not touched.

### Equivalence, on the strongest available check

x86-64 output is **byte-identical** before and after, including
`bestmove e2e4  score 10  nodes 40793`. The node count is a function of every
move the generator produces over a full search, so an equivalent-looking
generator that dropped or reordered a move would not land on the same number.

Then all five cross targets against that same oracle:

| target | result |
| --- | --- |
| i386, arm32, aarch64, riscv32 | **MATCH** |
| xtensa | **MATCH**, with `--xtensa-long-calls` |

The xtensa caveat is not about this change. Without the flag the image is large
enough that a forward `call` to `__pxx_run_finalizers` cannot reach its body
(CALL0/CALL8 reach ±512 KiB, and a forward site is sized before the body
exists). The diagnostic says exactly that and names the flag — a good one; it
cost no diagnosis at all.

### The refusal stays, and should

`pasparser_proc.inc:2550` still refuses a STACKFUL generator on non-x86-64, and
that is correct: the lowering really does need `CoSwitch`, which really is
x86-64 assembly. What changed is that chess no longer asks for it. This was the
non-load-bearing half of the refusal pair frankA's *"a refusal is a hypothesis
about the language, and it can be load-bearing"* split for me today — the other
half, i386's by-value record parameter, IS protective and must not be deleted
before the copy exists.

### Gate

The ticket asked for "at least one cross target". Added to `test-i386`:
`examples/chess/chess.pas` built for i386 and run under `--selftest`, asserting
`ALL OK`. `--selftest` rather than the interactive default because it is
deterministic and it exercises the generator, which is the thing that changed.

**The existing `lib-test` row was checked rather than assumed.** It builds chess
with `$(PXX_STABLE)` — the v399 pin — and I had just changed the source it
compiles. The pin builds the stackless spelling and its `--selftest` still prints
`ALL OK`, so that row stays green. The new row lives in the cross section
instead because lib-test runs on x86-64, the one target that never had the
problem.

### What this closes

`umbrella-cross-target-codegen-is-correct` now has ONE blocker left,
`feature-a-i386-refuses-a-by-value-record-parameter-...`. Every program in
`examples/` that the 2026-09-02 sweep could run now builds and matches the
x86-64 oracle on all five cross targets, except fm and raytracer on i386, which
that last blocker covers.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 995b1daef.
