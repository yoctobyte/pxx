---
slug: feature-a-a-stackful-generator-is-x86-64-only-so-examples-chess-cannot-target-anything-else
track: A
prio: 45
type: feature
status: open
found: 2026-09-02
found-by: frankC
owner: ""
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
