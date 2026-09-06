---
track: A
prio: 30
type: bug
blocked-by: []
summary: "MEASURED 2026-09-06. A record with `class operator Initialize`/`Finalize` returned BY VALUE from a function runs NEITHER operator for the function's own Result variable: fpc Initializes it on entry and Finalizes the caller-side temp when the statement ends, pxx does neither. So a managed record's invariant does not hold for the one value a factory function produces, which is the ordinary way such a record is constructed -- `function NewFoo: TFoo` returns something Initialize never saw, and any handle it owns is never released. PRE-EXISTING AND NOT THE AddRef WORK: verified against the PINNED compiler on the same program with the AddRef operator removed (the pin refuses that declaration), and the pin omits the identical two lines. Distinct from the by-value PARAMETER event, which is now correct in both argument shapes. It is the whole reason test_mgmt_operators_addref_nonlvalue_arg.expected is not fpc's output byte for byte -- the two missing lines are exactly this defect, named there, and that fixture MUST go red when this is fixed."
status: backlog
owner: unassigned
---

# A managed record function result runs neither Initialize nor Finalize

## Repro

```pascal
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    id: Integer; pad1, pad2, pad3: Int64;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
class operator TFoo.Initialize(var a: TFoo); begin a.id := 0; WriteLn('  Init'); end;
class operator TFoo.Finalize(var a: TFoo);   begin WriteLn('  Fin    id=', a.id); end;

function Make: TFoo; begin Make.id := 7; end;
procedure TakeConst(const f: TFoo); begin WriteLn('  callee(const) id=', f.id); end;

begin
  TakeConst(Make);
end.
```

| | fpc 3.2.2 | pxx at `188316478939` | pinned |
| --- | --- | --- | --- |
| `Init` on entry to `Make` | yes | **no** | **no** |
| `callee(const) id=` | 7 | 7 | 7 |
| `Fin id=7` at end of statement | yes | **no** | **no** |

The pin agreeing with HEAD is the control that dates this: it predates the
Copy/AddRef work entirely.

## Why it matters — it is the constructor case

A record carrying `Initialize`/`Finalize` is carrying an invariant: a handle, a
buffer, a refcount. The idiomatic way to hand one out is a factory function, and
that is precisely the path where neither operator runs. The value the caller
receives was never Initialized, so its invariant is whatever the stack held; and
the temp holding it is never Finalized, so anything it owns leaks. Both halves
are silent.

This is not the `const`/`var` parameter rule (fpc runs no operator there either,
and pxx now agrees). It is the RESULT variable's own lifetime, which fpc treats
like any other managed local.

## Where to look

`WrapManagementOpsRange` (`compiler/pasparser_proc.inc` ~631) walks
`isTarget` = `skLocal`/`skGlobal` only. A function's Result is neither of those
in this compiler's symbol kinds — the same structural reason the by-value
PARAMETER copy had no lifecycle at all until 2026-09-06, and it is worth
checking whether one predicate can own both populations rather than growing a
third (`devdocs/dev/normalise-dont-special-case.md`).

The caller-side half is separate: the temp that receives the result needs the
same end-of-statement finalize queue the by-value argument temp now uses
(`IRFlushPostCallIntf`, `PostCallIntfSym`/`PostCallIntfRec`).

**Check before fixing:** the by-value argument path must not finalize the same
storage twice. `TakeVal(Make)` currently prints one `Fin id=107` under both
compilers; if the result temp gains a finalize and the argument copy keeps its
own, that row must still print exactly one.

## Not taken

Found while closing the AddRef half of
`feature-pascal-management-operators-copy-and-addref`, as the residual that kept
one fixture from being byte-identical to fpc. Parked rather than folded in: it is
a different mechanism (result lifetime, not parameter lifetime) and it needs the
double-finalize question above answered before it is safe.
