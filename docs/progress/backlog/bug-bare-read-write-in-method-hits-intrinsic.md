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
