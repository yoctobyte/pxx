---
track: A
prio: 30
type: bug
blocked-by: []
summary: "MEASURED 2026-09-06. A record with `class operator Initialize`/`Finalize` returned BY VALUE from a function runs NEITHER operator for the function's own Result variable: fpc Initializes it on entry and Finalizes the caller-side temp when the statement ends, pxx does neither. So a managed record's invariant does not hold for the one value a factory function produces, which is the ordinary way such a record is constructed -- `function NewFoo: TFoo` returns something Initialize never saw, and any handle it owns is never released. PRE-EXISTING AND NOT THE AddRef WORK: verified against the PINNED compiler on the same program with the AddRef operator removed (the pin refuses that declaration), and the pin omits the identical two lines. Distinct from the by-value PARAMETER event, which is now correct in both argument shapes. It is the whole reason test_mgmt_operators_addref_nonlvalue_arg.expected is not fpc's output byte for byte -- the two missing lines are exactly this defect, named there, and that fixture MUST go red when this is fixed."
status: done
owner: claude-dupwt
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


# Fixed 2026-11-19 (claude-dupwt)

Three parts, each measured against fpc 3.2.2.

1. **The caller's temp** (`CollectManagedResultTemps`, pasparser_proc.inc). Before
   the declaring routine is wrapped, a call whose record result has
   Initialize/Finalize (own or in a field) and is NOT the right side of an
   assignment gets a named local of the result type. The existing local wrap
   then Initializes it at entry and Finalizes it at exit (Exit and exceptions
   included). IR lowering hands it to IRAppendCall as the hidden destination
   (`IRForcedRetTmp`). One temp per record type, reused from statement to
   statement as fpc does. A temp is free again only once the statement that last
   used it has been walked, so `Pair(MakeCnt(3), MakeCnt(4))` keeps two temps,
   and a value an enclosing statement still holds is not shared with the
   statements inside it.
2. **The callee starts from the destination** (CompileAST, ir_codegen.inc). fpc's
   Result aliases the caller's slot. pxx's Result is a local copied out at return,
   so it now also copies the destination IN at entry (raw IR_COPY_REC).
3. **`x := F` seeds the scratch from x** (IRAppendCall prefill). fpc passes x
   itself, so `Result.id` reads x's old value. pxx returns into a scratch and then
   copies, so the scratch is pre-copied from x. This is done for a plain-name
   destination only, since re-reading it must have no side effect.

Parts 2 and 3 skip records with ARC-managed fields (strings, interfaces): a raw
duplicate of a reference would be released twice. Those keep their fresh local.

Remaining divergences, both fpc temp-allocation details and both documented in
the test: fpc Finalizes a DISCARDED call's temp twice (at the end of the
statement and at exit, after one Initialize), where pxx does it once. And fpc
reuses one temp for two calls inside a single statement, where pxx keeps two.

Tests: test_a_managed_record_function_result_lifecycle (row mgmt_result_lifecycle26)
covers an argument, an assignment, a discard, a loop, a string-field record, a
containing record, a method result, an exception mid-loop, two results in one
expression and the main body. Output is identical on x86-64, i386, aarch64,
arm32 and riscv32, and at -O2. test_mgmt_operators_addref_nonlvalue_arg is now
byte-identical to fpc: its header asked for the two lines to be added when this
landed. test_mgmt_operators lost its `Mk` divergence. All 11 tests that declare
these operators and have an .expected pass.
