---
prio: 60
---

# TObject-typed parameter is 32-bit-truncated in methods, unmatched in plain routines

- **Type:** bug (codegen + overload matching — class model) — **Track A**
- **Status:** done
- **Opened:** 2026-07-12, found wiring the Eliah component tab bar (the
  identity search over `Sender` never matched).

## Symptom 1 — method param truncated (silent wrong value)

```pascal
type
  TObj = class
    procedure H(Sender: TObject);
  end;
var target: TObj;
procedure TObj.H(Sender: TObject);
begin
  writeln(Pointer(Sender) = Pointer(target));   { FALSE }
  writeln(Int64(Pointer(Sender)));               { lower 32 bits only }
end;
begin
  target := TObj.Create;
  target.H(target);
end.
```

`Sender` arrives as the LOW 32 BITS of the passed object pointer (e.g.
`0x2B40F808` from `0x70612B40F808`). A concrete-class parameter
(`Sender: TObj`), a `Pointer` parameter, and a plain-function class parameter
are all correct — only `TObject`-typed parameters truncate, so the load/store
width for the builtin TObject type is wrong somewhere in the value-param path.

This is silent wrong behavior: every PCL event handler is declared
`(Sender: TObject)` per LCL convention, and any handler that *uses* Sender's
value (identity compare, cast, field access) reads through a truncated
pointer — worked "by luck" so far because existing handlers only use Self.
Eliah's tab bar now carries a workaround (`Sender: TButton` + comment).

## Symptom 2 — plain routine rejects the call

```pascal
procedure P(o: TObject);
begin end;
...
P(target);   { TObj instance }
```

```
Mismatch in MatchProcCall: name = P, nArgs = 1
  arg[0] = 6
```

The overload matcher does not accept a class instance for a `TObject`
parameter in a plain routine (methods accept it — then truncate). Also note
the raw matcher dump is not a normal file:line diagnostic.

## Acceptance

- `TObject` params behave exactly like any class-typed param: full 64-bit
  value in methods AND plain routines; any class instance converts implicitly.
- Eliah's `OnPaletteButton` workaround can revert to `Sender: TObject`.
- Compile-run test covers: method + plain fn, identity compare, `is`/cast use.
- Self-host byte-identical.

## Log
- 2026-07-12 — resolved, commit HEAD.
