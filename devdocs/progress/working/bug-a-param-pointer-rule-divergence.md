---
track: A
prio: 40
type: bug
---

# "Param slot holds a pointer" is written 8 times; 3 copies disagree

Measured 2026-07-19. **LATENT, not active** — read the verification section
before treating this as a live bug.

| site | IsRef | IsArray | frozen str | tySet | tyVariant |
| --- | --- | --- | --- | --- | --- |
| x86-64 `ir_codegen.inc:2616` | y | y | y | y | y |
| aarch64 `:1410` | y | y | y | y | y |
| arm32 `:130` | y | y | y | y | y |
| i386 `:1639` | y | y | y | **n** | y |
| riscv32 `:1166` | y | y | y | **n** | y |
| `ParamSize` `symtab.inc:2231` | y | y | tyString only | **n** | **n** |
| `AllocParam` `symtab.inc:2322` | y | y | tyString only | **n** | y |

`ParamSize` and `AllocParam` are meant to encode ONE rule and already
contradict each other on `tyVariant`.

## Verification — a prediction that FAILED

From the table I predicted a `set` param would misbehave on i386/riscv32 and
work on x86-64. Tested on all five hosted targets: **all agree**
(`has a` / `no z`). Sets reach params via `IR_LEA` on a materialised temp
(`ir.inc:3563`), not the param-slot path, so the disagreement never fires for
that shape.

So this is not a live miscompile. It is an unmaintainable rule: nobody can say
which of the 8 copies is authoritative, no test would catch a fourth drifting,
and adding `tyVariant` this session required editing six of them by hand.

Resolved properly by [[feature-a-abi-oracle]] rather than by patching the three
outliers — patching them just re-creates the same trap with 8 agreeing copies.
If the oracle is deferred, at minimum reconcile `ParamSize` with `AllocParam`,
since those two disagreeing is indefensible on its own.
