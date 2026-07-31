---
track: U
prio: 60
type: decide
---

# Decide: what should NilPy do when an operator gets operand types Python rejects?

CPython raises `TypeError` for `3 - "ab"`, `2.5 * "ab"`, `3 < [1, 2]`. NilPy
currently does pointer arithmetic on the handle and returns a plausible wrong
number, hangs, or segfaults, depending on the operator
([[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]],
[[bug-nilpy-float-times-string-hangs]],
[[bug-nilpy-int-equals-string-segfaults]]). The individual crashes and hangs
are plain bugs and are filed as such. What needs a decision is the POLICY the
fixes should implement, because it applies to every operator and every builtin,
not just the ones the sweep happened to reach.

## The fork

1. **Static rejection only.** Compile-time error when both operand types are
   statically known and the pair is meaningless. No runtime cost; catches the
   literal and annotated cases; silent on anything variant-typed.
2. **Dynamic raise.** The variant arithmetic helpers raise a catchable NilPy
   exception when the tags do not admit the operator. Complete; costs a tag
   check on the dynamic path (those helpers already switch on the tag, so it is
   close to free where it matters). Needs the exception to be a real NilPy
   exception, not a Pascal runtime trap — the same requirement as
   [[bug-nilpy-runtime-raised-errors-bypass-try-except]].
3. **Define it away.** Give the operators a total semantics (None as 0,
   handle-as-number, etc.) and document the divergence. Rejected as written:
   a result derived from a heap address is not a semantics, it is a different
   answer on every run.

## Recommendation

1 and 2 together. 1 is small and immediately valuable; 2 closes the dynamic
hole and shares the machinery division-by-zero needs anyway. That also settles
the wider question — NilPy gets real `TypeError`-shaped runtime errors — which
is why this is a decision and not just a bug fix.

## Why it is a Track U item

It sets NilPy's stance on type errors in general (builtins, indexing, attribute
access, not just arithmetic), and it trades strictness against the deliberately
lax dialect posture. That is a direction call, not something to infer from the
code.

## DECIDED 2026-07-30 (user) — 1 AND 2, and 2 is cheaper than this ticket assumed

**Both.** Static rejection where the types are provable, dynamic raise for the rest.

Reasoning for 1 (user's): pxx compiles Python, C and Pascal into one IR. In a
COMPILED setting, waiting for a run-time error when the type is provably T is
silly — the code is simply wrong and the compiler can say so. Accepted
divergence: `if False: 3 - "ab"` compiles under CPython and will not under pxx.
Default-on; add an escape hatch only if it turns out to bite real code.

### 2 does NOT need an exception story built — it already works

This ticket said dynamic raise "needs the exception to be a real NilPy exception,
not a Pascal runtime trap". Measured today; that premise is wrong:

```
try: int("abc")   except ValueError:        -> caught      (matches CPython)
try: 1 // 0       except ZeroDivisionError: -> caught      (matches CPython)
try: 2.5 * "ab"   except TypeError:         -> NOT caught, exit 219
```

The mechanism is in place and correct. `pystr_to_int` does
`raise ValueError.Create(...)` and NilPy catches it. The hole is that
`PyTypeError` (pylib.pas) was written as `writeln` + `Halt(219)` instead of
`raise` — 14 call sites go through it, plus ~8 loose `Halt(1)` sites in the same
unit. Nobody converted them when the ValueError one was converted. So 2 is
"finish converting the diagnostics", not "design a story".

### The embedded concern is already answered — do NOT add a switch

Raised in discussion: exceptions cost on ESP32/xtensa, Pascal deliberately makes
exception support opt-in (same reasoning as ansistring), so maybe halting is
right for some targets. Measured, and no switch is needed:

- The exception runtime is DEMAND-DRIVEN, not flagged: `EnableExceptionRuntime`
  fires when the program's own source uses `try`/`raise`
  (`pyHasExceptions` for NilPy). A `raise` sitting inside pylib does not turn it
  on — a hello-world `.npy` and one calling `int("5")` both come out ~2.3 KB
  SMALLER than the same program with a `try` block.
- A raise in a program that never enabled the runtime degrades cleanly:
  `Unhandled exception: ValueError: invalid literal for int() ...`, exit 1.

So `raise` STRICTLY DOMINATES `Halt`: identical behaviour when nobody is
catching, but with the class name, and catchable when someone is. There is no
size or overhead argument for keeping the halts, and no per-target policy to
gate.

### Work order

1. `PyTypeError` -> `raise TypeError.Create(...)`; audit its 14 call sites and the
   `Halt(1)` neighbours for any that run where a raise cannot unwind (a callback
   frame, an ARC finalizer). Closes
   [[bug-nilpy-pytypeerror-halts-instead-of-raising]] and unblocks
   [[bug-nilpy-runtime-raised-errors-bypass-try-except]].
2. The operator arms: `-`, `*`, `/`, `//`, `%`, `<`, `<=`, `>`, `>=` reach the
   type dispatch that `+` and `and`/`or` already use
   ([[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]).
3. Static rejection where both operand types are statically known.

Gate for each: `make test-nilpy` + self-host byte-identical, plus the sweep's
operator x operand-type table diffed against CPython.

## Log
- 2026-07-30 — resolved, commit user-decision.

## Refinement 2026-07-30 (user): option 1 WARNS, it does not abort

Static rejection is a WARNING by default, not a compile error. Settled after
noting that option 1 is the one place where pxx would be STRICTER than its
reference implementation — normally strictness here means matching FPC or
CPython, never exceeding them.

Why warn and not error:

- `if False: <buggy code>` is legal CPython and compiles. So is anything behind
  a version, platform or `if TYPE_CHECKING:` guard that never runs on this
  target. Aborting on a provably-wrong expression inside one is defensible in
  theory and infuriating in practice when it is a vendored library.
- The check only sees a SUBSET anyway. In NilPy nearly every value is a variant,
  so "both operand types statically known" is roughly literals and annotated
  locals. It catches less than it sounds like — which also means erroring buys
  less than it costs.
- Cost asymmetry: an abort that is wrong stops a real file compiling and someone
  has to hunt for why; a warning that is wrong is a grep-able line.

Deliberately NOT the answer: `-Werror`. It exists (`compiler.pas`, `WarnAsError`)
and promotes warnings to fatal, but it promotes ALL of them — too blunt to serve
as the opt-in for this one check. If a dedicated opt-in is ever wanted, the right
shape is a per-feature strict flag in the existing family (`--strict-case`,
`--strict-overload`), i.e. `--strict-types`. Not building it now: no evidence yet
that anyone wants it, and the warning is the whole value.

Status of that: a NOTE, not a task. Revisit only if the warning turns out to be
something people want promoted. Do not file a ticket for `--strict-types` on the
strength of this paragraph.

### Open, not decided: the other frontends

Raised and left open. For the PASCAL and C frontends the same static check has no
compat question — Pascal already errors on type mismatches and there is no lax
reference implementation to match. If the check lands in shared AST/IR ground it
may be worth defaulting to ERROR there and warning only on the NilPy path. Decide
that when the implementation makes the sharing concrete, not before.
