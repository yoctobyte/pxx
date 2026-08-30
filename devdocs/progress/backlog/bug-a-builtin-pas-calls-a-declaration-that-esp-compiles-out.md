---
track: A
prio: 50
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "`builtin.pas:1702` calls `PxxSciDigits17` unconditionally, but its forward declaration in `builtinheap.pas` sits inside `{$ifndef PXX_ESP}` (407-441) while its BODY at :5148 is unguarded. So on a bare ESP target the body compiles and nothing can reach it, and `builtin.pas` fails with `undefined variable (PxxSciDigits17)`. This is why `builtin.pas` does not compile on bare xtensa or bare riscv32 at all -- and why 22 arms of `needsBuiltin` carry `(not TargetIsEspClass)` to route around it."
---

# `builtin.pas` does not compile on bare ESP: a one-sided `{$ifndef PXX_ESP}`

- **Type:** bug (Track A — compiler-shipped source that does not compile for two
  supported targets). Tagged **S** by consequence, not by file.
- **Found:** 2026-08-30. frankB hit the symptom from `lib/rtl/random.pas`;
  frankS's falsifier isolated it to the `builtin` unit itself; the coordinator
  read the guard.

## The measurement (frankS, at HEAD)

`needsBuiltin` does exactly one thing — `ParseUsesUnitAmbient('builtin')`
(`pasparser_prog.inc:1340`). So "is the ESP guard a structural constraint or a
copied habit?" reduces to one question: **can the `builtin` unit be pulled on
bare ESP at all?**

| target | empty program | `uses builtin;` |
| --- | --- | --- |
| bare xtensa | ok | **FAILS** — `undefined variable (PxxSciDigits17)` *inside `compiler/builtin/builtin.pas`* |
| bare riscv32 | ok | **FAILS** — same error, same file |
| hosted xtensa | ok | **ok** |

The empty-program control rules out general bare-profile breakage. It is the
unit.

## The mechanism — one arm guarded, its sibling not

```
compiler/builtin/builtinheap.pas:407   {$ifndef PXX_ESP}
compiler/builtin/builtinheap.pas:440     procedure PxxSciDigits17(...);   <- DECLARATION, guarded
compiler/builtin/builtinheap.pas:441   {$endif}
compiler/builtin/builtinheap.pas:5148  procedure PxxSciDigits17(...);     <- BODY, NOT guarded
compiler/builtin/builtin.pas:1702        PxxSciDigits17(v, scaled, e);    <- CALL, NOT guarded
```

**The guard removes the declaration and leaves both the body and the caller
standing.** On ESP the body is compiled and unreachable, and the one caller
cannot see it. That is textbook
[[devdocs/dev/normalise-dont-special-case]] — a construct reachable through two
shapes where only one grew the guard, and the ungrown one is the broken one.

The guard is also protecting nothing: whatever `{$ifndef PXX_ESP}` was meant to
keep off ESP, it is not keeping the *code* off ESP, since the body compiles
there.

## Why this is not Track F

The symbol formats floats. **The mechanism is a one-sided conditional-compilation
guard and the float content is incidental** — rank the mechanism, never the
datatype. A compiler-shipped unit that does not compile is an ordinary Track A
bug at ordinary priority.

## What it explains, and what fixing it might delete

`(not TargetIsEspClass)` appears on **22 arms** of `needsBuiltin`. `util.inc`'s
own header for `TargetIsEspClass` says it guards *"may I pull this RTL unit"* and
that being wrong *"silently drags an uncompilable unit into a bare-metal
build."* So those 22 arms are a **real constraint honestly documented** — but the
constraint they route around is this single one-sided guard.

**So this is plausibly a root cause with 22 consequences**, and the
tickets-closed-per-change measure says fix it here rather than adding a
23rd workaround. Confirm that before believing it: `PxxSciDigits17` may not be
the only unresolved symbol on that path, only the first one the parser reaches.
**Re-run `uses builtin;` on bare xtensa after fixing this one and see whether a
second name appears.** If a queue of them appears, this is one of N and the
guards stay.

## Downstream

- [[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]] (A+S,
  p45) is the arm that blocks `lib/rtl/random.pas`. Its chosen fix — a False stub
  that reaches a bare target **without** the builtin pull — remains correct
  regardless of what happens here, because it must work whether or not the pull
  is ever repaired.
- [[feature-random-library]] (B, p45) is blocked behind that one.
