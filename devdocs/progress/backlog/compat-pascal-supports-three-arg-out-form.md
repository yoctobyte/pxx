---
summary: "Supports(obj, IFoo) works but FPC's three-argument Supports(obj, IFoo, out Ref) — the form that both tests AND retrieves the interface — is a parse error"
type: compat
track: P
prio: 45
---

# `Supports(obj, IFoo, Ref)` — the three-argument form

- **Type:** compat (tag: compat-pascal) — Track P (Pascal frontend)
- **Status:** backlog
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
