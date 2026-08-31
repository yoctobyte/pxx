---
slug: bug-p-a-nested-class-method-called-from-inside-its-generic-outer-is-unresolved
track: P
prio: 60
type: bug
status: done
owner: frankwasm
blocked-by: []
summary: "FIXED. A class's own body is TWO ranges of source and they named a nested type's methods after two different spellings: the declaration used the type AS WRITTEN (always bare), the out-of-line implementation used the qualifier path it walked -- and AddClassLikeType registers a nested type QUALIFIED whenever the bare name is taken. Two procs, one with the callers and no body: `unresolved forward: TInner.GetIt`. A generic breaks the coincidence every time, because a specialization re-materialises the nested type against the template's own row. Both sides now read the class ROW (the record arm already did, which is what found the class arm). The ticket's `outer class not generic -> ok` row is WRONG and was the more expensive half: a method BODY had no class scope at all (ParsingClassBodyCi is declaration-only), so a plain non-generic outer called the DECOY's method -- FPC 7, we printed 1, silently. MethImplOwnerCi is that missing scope. test_nested_class_method_from_owner_body.pas matches FPC 3.2.2 byte for byte; gate.sh quick GREEN."
---

# A nested class's method, called from inside its GENERIC outer, is unresolved

## Repro (20 lines, FPC-verified)

```pascal
unit u; {$mode objfpc}
interface
type
  generic TOuter<T> = class
  public type
    TInner = class
      F: Integer;
      function GetIt: Integer;
    end;
    function Make: TInner;
    function Probe: Integer;
  end;
implementation
function TOuter.TInner.GetIt: Integer;
begin Result := 9; end;
function TOuter.Make: TInner;
begin Result := TInner.Create; end;
function TOuter.Probe: Integer;
begin Result := Make.GetIt; end;     { <-- the call site that breaks it }
end.
```

Driver: `type TO2 = specialize TOuter<Integer>; ... writeln(o.Probe)`.

```
pxx (414252435fb1)  pascal26:2: error: unresolved forward: TInner.GetIt
FPC 3.2.2           9
```

The reported position is useless again — `pascal26:2` with an `in:`/`near:` in
`compiler/builtin/builtinheap.pas`. Reduce from the SHAPE, not the coordinate.

## The boundary is the CALL SITE, not the declaration

Measured, same binary, each a separate unit:

| shape | result |
| --- | --- |
| nested method declared + implemented, **never called** | **ok** |
| nested method called from **outside** the generic class (`o.Make.M1` in the driver) | **ok** |
| nested method called from **inside** an outer method body (`Make.GetIt`) | **`unresolved forward`** |
| same call, outer class **not generic** | **ok** |

So the implementation IS parsed and registered — three functions on a nested
class resolve fine when the calls come from the driver. It is the call from
within the generic body, which goes through specialization, that fails to find
it. `function` vs `procedure` vs `constructor` makes no difference; all three
were tried and all three fail at that call site.

## Why it matters now

This is the shape at `generics.collections.pas:2129` —
`function TStack<T>.GetEnumerator: TEnumerator`, where `TEnumerator` is the
nested enumerator inherited from `TCustomList<T>` and used by the class's own
bodies. It is the wall revealed once rung 6b's `end`-imbalance is padded over;
see [[feature-pascal-corpus-expansion]]'s canonical table for the measurement
chain and the binary provenance.

**Not proven to be the same defect as the `end`-imbalance** that the truncation
bisect is chasing there — that one originates at or below line 1815 and this
site is at 2129. Two findings, one unit, and the relationship is open.

## FIXED — root cause, and it is two arms of one thing (frankwasm, 2026-08-31)

Measured with `--debug` on the ticket's own repro: **two proc rows**, one with
the callers and one with the body.

```
Proc 242: TInner.GetIt      at CodePos -1        <- the call bound here
Proc 245: TO2.TInner.GetIt  at CodePos 105665    <- the body is here
```

`AddClassLikeType` registers a nested type under its **qualified** name
(`TOuter.TInner`) whenever the bare one is already taken, and bare otherwise.
The two halves of the class then disagreed about which spelling names its
methods:

* the **declaration** in the class body composed `tname + '.' + mname` — the
  type **as written**, always bare;
* the out-of-line **implementation** composed the qualifier path it had just
  walked — `TO2` + `.` + `TInner` + `.` + `GetIt`.

They agree only by coincidence. A generic breaks the coincidence *every* time:
a specialization re-materialises the nested type against the template's own
already-registered row, so the row is qualified and the declaration is not.
**Both sides now read the class ROW's registered name**, so they cannot drift.
The **record** arm already did exactly this (`recNm := GetTokenStrFromRaw(
UClsNOff[ci], ...)`, `pasparser_decl.inc:3518`) — which is what identified the
class arm as the odd one out, and the nested-**interface** arm as the third.

### The row this ticket's table gets wrong, and it is the more expensive half

> | same call, outer class **not generic** | **ok** |

Not ok — **silently wrong**, which is why it read as ok. `ParsingClassBodyCi` is
set only while a class **declaration** is parsed, so a bare nested-type name in
an out-of-line **method body** had no class scope at all and fell through to the
flat unit table. With a decoy `TInner` declared first at unit level, plain
non-generic `TPlain.Probe` called the **decoy's** `GetIt`: FPC prints 7, we
printed 1. No generic anywhere. `MethImplOwnerCi` (`defs.inc`, saved/restored
across `ParseProcDecl` including its three early exits) is the missing half of
that scope, and it covers the impl **header** too — `function TOuter.Make:
TInner` is already outside the class body.

The ticket's row was measured honestly on a probe with no name collision, where
the row comes out bare and the two spellings happen to match. *The shape that
exonerates the non-generic case is the shape that cannot show the bug.*

### Evidence

`test/test_nested_class_method_from_owner_body.pas`, wired into `test-core`,
output byte-identical to FPC 3.2.2 on the same source:

```
decoy          1     <- the flat unit-level TInner
plain          7     <- non-generic: was 1
generic first  9     <- was `unresolved forward: TInner.GetIt`
generic second 9     <- second specialization of the same template
from outside   9     <- the call that always worked
```

`gate.sh quick` GREEN; self-host fixedpoint converges in 1 round.

### Not closed by this

The rung-6b `end`-imbalance in `generics.collections.pas` is a separate finding
and stays open on [[feature-pascal-corpus-expansion]]; this removes the 2129
wall, not that one. Whether `TStack<T>.GetEnumerator` now compiles is a
re-measurement that ticket owns — and it is still gated on its own `make pin`.

## Log
- 2026-08-31 — resolved, commit 2b99d6c19.
