---
summary: "pxx rejects FPC's `class helper for T` at parse time — `TFooHelper = class helper for TFoo` is `error: unexpected token`"
type: compat
track: P
prio: 58
---

# `class helper for` is not parsed

- **Type:** compat (Pascal frontend parity) — Track P
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh`, class-helper case batch. The three
  cases are tagged `[known]` there and will start reporting the moment the
  syntax parses, so the semantics below are already under test.

## Repro

```pascal
program h;
type
  TBox = class
    Value: Integer;
  end;
  TBoxHelper = class helper for TBox
    function Doubled: Integer;
  end;
function TBoxHelper.Doubled: Integer; begin Result := Value * 2; end;
var b: TBox;
begin
  b := TBox.Create; b.Value := 21; writeln(b.Doubled); b.Free;
end.
```

FPC (`-Mobjfpc`) prints `42`. pxx: `error: unexpected token`.

## The semantics, if it is implemented

The probe pins the two that are easy to get wrong:

- **A helper method shadows an inherited *virtual* method non-virtually.** With
  `TBase.Name` virtual returning `'base'` and `TBaseHelper.Name` returning
  `'helper'`, FPC prints `helper` for **both** `o.Name` and `TBase(o).Name` —
  the helper wins at every static type that sees it, and the virtual dispatch
  never runs.
- **An unqualified name inside a helper method binds to the extended type's
  members.** `TThingHelper.Tag2` calling bare `Tag` reaches `TThing.Tag`.

Only one helper is active for a given type at a point in the source (the
last one in scope wins); the probe deliberately does not test that yet.

## Scope note

Related but distinct, and not covered here: `type helper for Integer` (record /
type helpers), which FPC gates behind `{$modeswitch typehelpers}`. Worth a
separate ticket — the parse work overlaps, the binding rules do not.

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical). Note the Track P
catch — the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, so
this must not be edited concurrently with Track A.

## Outcome (2026-08-27)

Implemented. `class helper for <class>` parses, and all three probe cases now
match FPC 3.2.2 byte for byte; the rows are untagged in `fpc_diff_probe.sh` and
`test/test_class_helper_for_a_class.pas` carries them plus the ancestor-chain
cases FPC exercises but the probe did not.

It reused the existing helper machinery rather than growing a second one. A
class helper is the same `UClsHelperTk`/`UClsHelperRec`-marked row that
`record helper for` and `type helper for` already produce — the marker is
`Ord(tyClass)` and the target's rec id — so `FindHelperForType` answers it
unchanged. Four things had to fork on the target being a CLASS:

1. **Self is by value.** A class instance is already a pointer; by-ref would
   hand the method the address OF the reference. Both the decl side
   (`ParseRecordMethod`) and the impl side (`ParseProcOrFunc`) key that off the
   target kind, so the two agree — the b321 lesson.
2. **Self's `RecName` is the EXTENDED class**, not the helper row. Without it
   `Self.Value` searched a row with no fields. The wiring now prefers
   `UClsHelperRec` whenever the target has a rec at all, which is also right
   for a `record helper for <record>`.
3. **`ClassHelperRecFor`** (symtab) answers the QUALIFIED direction: the rec a
   `b.M` lookup should actually run against. It walks the ancestor chain and
   interleaves — at each class, that class's helper before that class's own
   members. That single walk is what makes FPC's two surprising answers
   coexist: a helper shadows a virtual method non-virtually (`b.Name` =
   helper), yet a descendant's own override still wins (`d.Name` = derived).
4. **`SelfMemberCi`** (symtab) answers the UNQUALIFIED direction: the ci a bare
   name inside the current method body searches — the helper when it declares
   the name, the extended class otherwise. The two functions are the same rule
   read from opposite ends.

`CurSelfClass` inside a class-helper method now points at the EXTENDED class,
which is what `Self` there really is (fields, offsets and all); only the name
lookup has the helper in front of it, via `SelfMemberCi`.

**Deliberately not built:** helper *inheritance*. `class helper(TAncestor) for T`
parses and the ancestor is accepted and dropped. It only matters once two
helpers are in scope for one type at once, which is the case the ticket
itself declined to test.

Two smaller refusals fell out of it, both pinned by the FPC testsuite's
tdefault13 (which used to "pass" only because the parse died earlier):
`Default(<helper type>)` is refused (a helper names methods, not storage — it
has no zero value), and `Default(T);` standing alone as a STATEMENT is refused
rather than silently skipped by ParseStatementAST's catch-all, which was
swallowing every diagnostic the Default() expression arm raises.

Gate: quick GREEN, self-host fixedpoint byte-identical. Pascal conformance,
C conformance and the fgl corpus unchanged. `fpc_diff_probe`: 0 new
divergences, known count 11 -> 8.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
