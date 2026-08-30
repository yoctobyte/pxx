---
track: A
prio: 50
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "`builtin.pas` will not compile on a bare ESP target (xtensa or riscv32, identical): it calls two names — `PXXVarBinOp` (:1148) and `PxxSciDigits17` (:1702) — from UNGUARDED code, while their declarations sit inside `{$ifndef PXX_ESP}` (`builtinheap.pas:407-441`). MEASURED 2026-08-30: exactly those two, of the 17 declarations that block removes; the other 15 have no caller in `builtin.pas` and are cleanly excluded, so the guard is 15/17 correct and this is a two-callsite leak, NOT a root cause behind the 22 `(not TargetIsEspClass)` arms. The ticket's own disproof check fired — see DISPROOF RUN."
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

---

## DISPROOF RUN (frankS, 2026-08-30, at HEAD `3bb4dce4b`) — the check above was run, and it fires

The ticket names its own disproof condition:

> *"`PxxSciDigits17` may not be the only unresolved symbol on that path, only the
> first one the parser reaches. Re-run `uses builtin;` on bare xtensa and see
> whether a second name appears. If a queue of them appears, this is one of N and
> the guards stay."*

**A second name appears — and `PxxSciDigits17` is not even the first.** No fix was
needed to see it; the full error list was already there behind a `head`:

```
$ ./stable_linux_amd64/default/pinned --target=xtensa --platform=esp \
      --esp-profile=bare -Fulib/rtl ub.pas
pascal26:1148: error: undefined variable (PXXVarBinOp)
  in: ./stable_linux_amd64/default/builtin/builtin.pas
pascal26:1702: error: undefined variable (PxxSciDigits17)
  in: ./stable_linux_amd64/default/builtin/builtin.pas
```

Identical, name for name and line for line, on bare riscv32. **N = 2**, and it is
ISA-independent — a profile property, not an xtensa one.

**2 is the true total, not a truncation.** `defs.inc:189` caps reporting at
`MAX_REPORTED_ERRORS = 20`; we saw two. Nothing is hidden behind the cap.

### The guard is NOT "protecting nothing" — it is 15/17 correct

The block at `builtinheap.pas:407-441` removes **17** declarations on ESP. Grepping
each of the 17 for a call site in `builtin.pas`:

| names in the block | call sites in `builtin.pas` |
| --- | --- |
| `PXXVarBinOp` | 1 — line 1148 |
| `PxxSciDigits17` | 1 — line 1702 |
| the other **15** (`PXXStrLoadFile`, `PXXRecordRetain/Release`, `…Intf`, `…Initialize/Finalize`, `PXXDynArrayRelease/Unique`, `PXXVarNot`, `PXXVarStrAppend`, `PXXVarClear`, `PXXVarReleasePayload`, `PXXVarRetain`, `PXXWriteVariant`) | **0** |

Two independent measurements agree exactly: the compiler's own error list and the
static call-site grep both return the same two names. So the guard is doing its
job for 15 of 17 declarations, and **two callers leaked out of it**. That is a
two-line omission, not a design fault in the guard.

### The asymmetry is CALLER-side, and "BODY, NOT guarded" is unconfirmed

`builtin.pas` has exactly three `{$ifndef PXX_ESP}` regions — 62-85, 436-438,
1409-1469. **Neither call site (1148, 1702) is inside any of them.** The callers
are unguarded, full stop; that half of the mechanism section is confirmed.

The *body* half is not. A directive trace puts `builtinheap.pas:5148` inside
`{$ifndef PXX_ESP}` at :4407 — i.e. the body would be guarded after all — but that
trace is unreliable on this file, because the header comment at lines 12-17
contains directive *text* (`{$ifdef CPU_XTENSA}`, `{$ifndef PXX_ESP}`) inside a
`{ }` comment and any naive scanner counts it. What the compiler actually reports
is **declaration-visibility errors only**: no duplicate-body and no unreachable-body
diagnostic appears on either bare target. Treat "the body compiles and is
unreachable" as unproven until someone reads it with the real lexer.

### Consequence for the fix

By the ticket's own stated rule, **this is one of N and the guards stay.** It is
not a root cause with 22 consequences: it is two unguarded call sites. Fixing it
is still worth doing — a compiler-shipped unit that will not compile for two
supported targets is a Track A bug at ordinary priority — but it should be
scoped and ranked as *"guard two callers"*, not as *"delete the 22-arm
workaround"*. Anyone hoping to retire `(not TargetIsEspClass)` on the back of
this should re-derive that from scratch.

**[[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]]'s
option (3) is unaffected** and remains correct for the reason already given: a
False stub must reach a bare target whether or not the pull is ever repaired.

### Trap for whoever takes this — you will be editing a file the compiler is not reading

The error text cites `./stable_linux_amd64/default/builtin/builtin.pas`, **not**
`compiler/builtin/builtin.pas`. The pinned compiler resolves its builtin unit from
its own stable tree. The two trees are byte-identical right now (`diff -rq
compiler/builtin stable_linux_amd64/default/builtin` is clean), so the line
numbers above are interchangeable — but **a fix applied to `compiler/builtin/`
alone will not change this measurement until a pin**, and re-running the
falsifier with `pinned` will show the identical two errors. That reads exactly
like "the fix didn't work".
