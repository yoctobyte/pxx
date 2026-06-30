# Unqualified property access inside a method body fails

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Track:** A (compiler — name resolution)
- **Found / Opened:** 2026-06-30, while adding TThread.Terminated (multithreading M3)

## Symptom

Inside a method, a bare (unqualified) reference to one of the class's own
**properties** fails with `undefined variable (<name>)`. Bare **field** access in
the same position works, and `Self.<property>` works — only the unqualified
property read/write is unresolved.

```pascal
type TC = class
  private FX: Boolean;
  public property Done: Boolean read FX;
  procedure Go;
end;
procedure TC.Go;
begin
  if FX        then ... ;   { ok — bare field }
  if Self.Done then ... ;   { ok — qualified property }
  if Done      then ... ;   { ERROR: undefined variable (Done) }
end;
```

This breaks idiomatic FPC code, most visibly `while not Terminated do` in a
`TThread.Execute` override (worked around with `Self.Terminated` in
lib/rtl/palthreadobj.pas + test/test_tthread_terminate.pas).

## Root cause (located)

`compiler/parser.inc` ~1169–1184: unqualified identifier resolution in a method,
when not a local/global, does `FindUField(selfClassCi, name)` and synthesises an
implicit-Self `AN_FIELD`. There is **no parallel `FindUProp` fallback**, so a name
that is a property (not a field) falls through to "undefined variable".

## Fix sketch

After the `FindUField` miss in that block (and the WITH-stack block at ~1135),
also try `FindUProp(selfClassCi, name)` (symtab.inc:417). On a hit, synthesise the
same access the working `Self.<prop>` postfix path produces — i.e. an implicit-Self
base node + the property's read accessor (field-backed: read field; method-backed:
call read method). Must cover read (factor context) and write (assignment LHS), and
not regress indexed/default properties. Gate: self-host byte-identical + a focused
test (bare read, bare write, method-backed read, field-backed read).

## Impact

Quality-of-life / FPC compatibility for all classes, not threading-specific.
Workaround (`Self.`) is available everywhere, so not urgent — but it is a real
papercut for ported FPC code.
