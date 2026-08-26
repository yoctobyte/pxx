---
summary: "pxx accepts only the declaration form `specialize Max<Integer> as MaxInt;` — FPC's inline `specialize Max<Integer>(a, b)` in an expression or statement is rejected with 'undefined variable'"
type: compat
track: P
prio: 60
---

# Inline `specialize F<T>(...)` for generic ROUTINES

- **Type:** compat (tag: compat-pascal) — Track P (Pascal frontend)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, generics batch.

## What differs

pxx requires a generic **routine** to be specialized in a *declaration*, then
called by the new name (`test/test_generic_func.pas`):

```pascal
specialize Max<Integer> as MaxIntF;
...
writeln(MaxIntF(3, 7));
```

FPC (`-Mobjfpc`) also allows the specialization **inline at the call site**:

```pascal
writeln(specialize MaxOf<Integer>(3, 9));      { expression position }
specialize Swp<Integer>(x, y);                 { statement position  }
```

pxx rejects both with `error: undefined variable`.

Generic **classes** and **records** are unaffected — `specialize TBox<Integer>`
as a type, two independent specializations of one template, generic records with
value-copy semantics and generic methods all match FPC exactly (verified: seven
cases in the same batch pass). This is specifically the routine call form.

## Why it is worth having

The declaration form needs a name for every (routine, type) pair, so a unit that
uses `Max` on three types carries three otherwise-pointless identifiers. Inline
specialization is what FPC code in the wild writes, so this blocks compiling
real objfpc source that uses generic helper routines — the `compat` case the tag
exists for.

## Probe cases

`gen-func-int`, `gen-func-string`, `gen-swap-var` in `tools/fpc_diff_probe.sh`,
tagged `known`. Untag when this closes.

Note `gen-swap-var` names its local `tmp`, not `t`: FPC rejects a local whose
name matches the type parameter `T` case-insensitively ("Duplicate identifier").
That is FPC being right, not a divergence — it cost one no-oracle SKIP to find.

## Gate

The three probe cases match FPC; `make test` + self-host fixedpoint.
