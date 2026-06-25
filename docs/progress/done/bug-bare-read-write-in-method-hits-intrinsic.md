# Bare `Read`/`Write` inside a method resolves to the console intrinsic, not the method

- **Type:** bug (name resolution) — minor, clean workaround
- **Status:** backlog (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** Classes / TStream ([[feature-own-net-http-lib]]) — `TStream.CopyFrom`
  / `ReadBuffer` / `WriteBuffer`.

## Symptom

Declaring `Read`/`Write` methods now works (fixed v54). But calling them
*unqualified* from inside another method of the same class resolves to the
**console `Read`/`Write` intrinsic**, not `Self.Read`/`Self.Write`:

```pascal
function TStream.CopyFrom(Source: TStream; Count: Int64): Int64;
...
  Write(buf[0], got);     { goes to the CONSOLE — prints buf[0], got — not Self.Write }
```
Observed: a `TMemoryStream.CopyFrom` printed `110` to stdout (buf[0]=1, got=10)
and wrote nothing to the stream.

## Workaround in use

`lib/rtl/classes.pas` qualifies the self-calls: `Self.Write(...)` /
`Self.Read(...)` in `CopyFrom`/`ReadBuffer`/`WriteBuffer`. Correct and clear.

## Fix

When the enclosing class has a `Read`/`Write` method, an unqualified
`Read(...)`/`Write(...)` call in a method body should bind to the method (as FPC
does), not the console/file intrinsic. The intrinsic remains for code with no
such method in scope.

## Done when

- Unqualified `Read`/`Write` inside a method with those members calls the member.
- Regression test under `make test`. (Low priority — `Self.` works.)

## Resolution (2026-06-25)

Fixed for the **statement** case (the TStream.CopyFrom symptom). In
`ParseStatementAST`, the `tkwriteln/tkwrite/tkReadln/tkRead` branch now, before
falling to the console-intrinsic dispatch, checks: inside a method
(`CurProc>=0`, `CurSelfClass` is a class), the next token is `(`, and
`FindUMeth(CurSelfClass, CurTok.SVal) >= 0` → builds an implicit-`Self` method
call (AN_CALL / AN_VIRTUAL_CALL), mirroring the tkIdent implicit-Self dispatch.
The `(` guard keeps a bare console `Write`/`Writeln` on the intrinsic path; the
own-name-result assignment is still rejected above
(bug-virtual-keyword-name-result). `FindUMeth` walks the parent chain, so an
inherited Read/Write member binds too. Front-end only — self-host byte-identical
(the compiler defines no class with a Read/Write member). New regression
`test/test_method_read_write_unqualified.pas` in `make test`. Committed in
777730d.

**Residual (not this fix):**
- *Expression* context (`x := Read` / `v := Write(n)`): the intrinsic keyword
  token is not accepted as a value in `ParseFactor`, so it errors `expected
  expression` rather than misdispatching. A separate ParseFactor branch (same
  shape) would be needed if a Read/Write *function* member must be callable
  unqualified in an expression.
- `Move` (below): a different mechanism — `Move` is a builtin proc on the
  tkIdent path, not a keyword token — and its repro needs adventure's fuller
  context. Left open as a data point.

## Related data point — `Move` (2026-06-25, Track B)

The same family bit `examples/adventure` once F1 (textfile) cleared: a
`TGame.Move(d: TDirection)` method called unqualified from `TGame.Run`
(engine.pas:1038, `Move(d)`) binds to the memory `Move(src,dst,count)` intrinsic →
`error: no overload of Move matches these arguments`. So this is not specific to
`Read`/`Write` — any intrinsic-named method (`Move`, …) called unqualified is at
risk. NB: a reduced repro (bare method `Move(Integer)`/`Move(enum)` from another
method, program or unit) does **not** reproduce — it needs engine's fuller
context, so the trigger is narrower than "any same-named method". Sidestep:
`Self.Move(d)`.
