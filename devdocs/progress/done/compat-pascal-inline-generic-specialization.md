---
summary: "pxx accepts only the declaration form `specialize Max<Integer> as MaxInt;` — FPC's inline `specialize Max<Integer>(a, b)` in an expression or statement is rejected with 'undefined variable'"
type: compat
track: P
prio: 60
owner: opus5-frank1
---

# Inline `specialize F<T>(...)` for generic ROUTINES

- **Type:** compat (tag: compat-pascal) — Track P (Pascal frontend)
- **Status:** done
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

## Outcome (2026-08-27)

Implemented. All three probe cases now match FPC and are untagged;
`test/test_inline_generic_specialization.pas` carries them plus a second
concrete type per template, the two spellings mixed in one program, and the
specialized call nested in ordinary arithmetic.

**The inline spelling is rewritten INTO the declaration one**, not given a
dispatch path of its own. `SpecializeInlineGenericFuncUses` (pasparser_generic)
runs at the end of `ParseGenericFunc`, so it sees the rest of the unit with the
template just registered, and does two things:

- collapses every `specialize F<C>(` group left in the token stream to the
  single identifier `F_C` — which is exactly the name the declaration form
  auto-generates when no `as` clause is given;
- emits one declaration-form specialization per DISTINCT `C`, right there,
  where a hand-written `specialize F<C> as F_C;` would have sat.

Downstream, nothing knows a generic was involved: the call site, the overload
rules and every diagnostic see an ordinary routine. That is why the change is
~90 lines and touches no call-site code.

The `(` in the pattern is load-bearing — it is what separates a CALL from the
declaration form (`... > as Name;`), which keeps its own path, and from a plain
`a < b` comparison sitting beside the word.

**Deliberately not built:** an inline specialization *inside another generic
template's body*. The template's tokens are buffered before this scan runs, so a
recursive inline use is not rewritten. It needs the scan to run over
TemplateTokens at splice time, which is a different (and much wider) change than
the one this ticket asked for.

Gate: quick GREEN, self-host fixedpoint byte-identical. Pascal conformance,
C conformance and the fgl corpus unchanged. fpc_diff_probe: 0 new divergences,
known 8 -> 5.

## Log
- 2026-08-27 — resolved, commit e1e5e863e.
