---
track: P
prio: 15
type: idea
summary: "DESIGN SUGGESTION, deliberately parked. Let Pascal calls write `f(name := value)`, reusing the keyword binder NilPy already has. Rejected for now on the grounds that no existing Pascal code can ever use it — the only consumers would be pxx-authored wrappers of Python-shaped APIs, and those can simply BE Python"
---

# Named parameters in the Pascal dialect — parked design suggestion

- **Type:** idea (dialect extension) — **Track P**, would touch Track A ground
- **Raised:** 2026-08-10, out of
  [[bug-b-tkhtmlview-uses-named-arguments-pascal-does-not-have]] — a library
  file written as though Pascal had keyword arguments, because the API it wraps
  (Tk) is keyword-shaped throughout.
- **Status: PARKED by the repo owner, deliberately.** Recorded so the reasoning
  is not re-derived, not as queued work.

## The suggestion

Accept `P(name := value)` in a Pascal call, binding by parameter name.

## Why it is cheaper than it sounds

**No name mangling is involved** — that framing is wrong, and worth correcting
because it makes the idea look harder than it is. pxx already HAS keyword
arguments; Pascal not having them is the anomaly *within this compiler*:

- `PyBindKwArgs(mpi, argsHead, lastArg, nArgs)` binds keyword arguments to
  parameters by name;
- `PyPromoteOverloadByKwAt` picks the overload a keyword names.

Both operate on the **shared `Procs[]` table** (`Procs[mpi].Params[k].Name`),
not on anything NilPy-specific. So this is mostly wiring the Pascal call path
into an existing binder.

## Compatibility, measured

`P(a := 1, 2)` is a **syntax error in both today**:

```
pxx : error: expected comma or close parenthesis
FPC : Syntax error, ")" expected but ":=" found
```

- **FPC source → pxx: provably safe.** No valid FPC program contains the
  construct, so none can change meaning. The extension claims syntax that is
  currently an error rather than reinterpreting anything that works.
- **pxx source using it → FPC: will not compile.** Unavoidable for any
  extension.
- **The bite in this repo:** `compiler/**` must stay FPC-compilable (the seed),
  so the compiler's own source could never use it. Already enforced
  mechanically by the FPC seed canary. `lib/**` and user code are unconstrained.

The dialect policy would permit it by default: it is case 2 of the two-part
rule (FPC *rejects* it; pxx would give well-defined deterministic semantics →
lax by default, parity rejection behind `--strict-fpc`).

Spelling note: `:=` rather than `=`, because `=` is comparison in a Pascal
expression and `f(a = 1)` is genuinely ambiguous with a boolean argument. If
FPC ever adds the feature it might pick Ada's `=>`; accepting both would
reconcile.

## Why it is PARKED — the argument that decided it (user, 2026-08-10)

1. it has to be designed well;
2. it has unintended side effects;
3. **it is not standard Pascal, so no existing Pascal code will ever use it.**

(3) is the decisive one, and it defeats the case originally made for it. The
argument *for* the feature was that it removes the pressure that produced the
bad file — but the only code that would ever write `f(name := value)` is
pxx-authored wrappers of Python-shaped APIs, and **those can simply be written
in Python**. The feature's entire constituency evaporates, and with it the
"fixes the cause" claim.

Reinforcing it: Pascal has its own GUI RTL that works entirely differently, so
the typical consumer of a Tk-shaped API is Python code, not Pascal code.

## What was done instead

[[feature-b-tkhtmlview-in-nilpy]] — rewrite the offending library in NilPy,
where keyword arguments already exist and the library's own consumers already
live.

## If this is ever revisited

The trigger to watch for is a *Pascal-side* consumer that genuinely wants
keyword arguments — i.e. someone writing Pascal, not a wrapper. Absent that,
(3) still holds and this should stay parked.
