---
summary: "Supports(obj, IFoo) works but FPC's three-argument Supports(obj, IFoo, out Ref) — the form that both tests AND retrieves the interface — is a parse error"
type: compat
track: P
prio: 45
owner: opus5-frank1
---

# `Supports(obj, IFoo, Ref)` — the three-argument form

- **Type:** compat (tag: compat-pascal) — Track P (Pascal frontend)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, interfaces batch.

## What differs

pxx implements the two-argument form as an intrinsic
(`parser.inc:11647`, *"`Supports(obj, IFoo): Boolean` — the function form of
`obj is IFoo`"*). FPC/Delphi also have the three-argument form, which tests and
**assigns the reference in one step**:

```pascal
var a: IA; b: IB;
...
if Supports(a, IB, b) then b.Num;     { pxx: error: unexpected token }
writeln(Supports(a, IA));             { pxx: OK }
```

pxx stops at the comma after the interface type.

## Why it matters

The three-argument form is the idiomatic query — it is the reason `Supports`
exists rather than just `is`. Without it, code must write `if Supports(a, IB)
then b := a as IB`, which performs the lookup twice and is exactly the pattern
`Supports` was introduced to replace. Real Delphi/FPC source uses the
three-argument spelling almost exclusively.

The rest of the interface surface matches FPC: interface declaration with a
GUID, a class implementing one or two interfaces, `as` casting between them,
interfaces as parameters and as function results, and `TInterfacedObject`
lifetime — five probe cases, all passing.

## Probe case

`iface-supports` in `tools/fpc_diff_probe.sh`, tagged `known`. It also covers
the two-argument form, so untagging it verifies both.

## Gate

`iface-supports` matches FPC (`FALSE|TRUE`); `make test` + self-host fixedpoint.

## Outcome — 2026-08-27

**Already implemented; the ticket was stale.** `feature-a-supports-three-argument-form`
built it into `ParseFactorCore`'s `Supports` arm and did not close this one.
Verified rather than assumed, and the probe untagged, which is the part that was
actually missing.

### Measured

```pascal
r := Supports(a, IB, b);      { TC implements IA and IB }
```

| row | pxx | fpc 3.2.2 |
| --- | --- | --- |
| three-arg, hit — result + the reference | `TRUE 8` | `TRUE 8` |
| three-arg, miss — the `out` param is nilled | `FALSE TRUE` | `FALSE TRUE` |
| two-arg, hit | `TRUE` | `TRUE` |
| two-arg, miss | `FALSE` | `FALSE` |

The nilling row is the one worth having checked: FPC's `Supports` takes the
reference as `out`, and an `out` parameter is nilled on entry, so a FAILED query
must leave the destination nil rather than untouched. pxx lowers the three-arg
form to `__pxxGetInterface(obj, @guid, @Intf)` — FPC's own definition spelled
out — and gets the same answer.

`tools/fpc_diff_probe.sh`'s `iface-supports` row is **untagged** now: it prints
`FALSE|TRUE` on both compilers, which is the gate this ticket named. Full probe
run after untagging: **0 new divergences**, 12 known/filed, 1 by design.

### One divergence, not filed

`Supports(a, IA, a)` — the same variable as source AND destination — answers
`got IA` under pxx and `no IA` under FPC. FPC's `out` nils the parameter on
entry, which for an aliased call destroys the very interface being queried, so
FPC's answer is an artefact of its own calling convention rather than a rule
anyone relies on. Not filed: no real code queries an interface into the variable
it is querying from, and matching it would mean nilling a destination pxx has no
other reason to nil.

### Gate

`tools/fpc_diff_probe.sh` clean (`iface-supports` untagged, 0 new) ·
`tools/gate.sh quick` GREEN · pascal-conformance 346/0/170/34 · c-conformance
220/0 · fgl 7/7. No compiler change, so the self-host binary is untouched.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
