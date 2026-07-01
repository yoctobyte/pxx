# Array-constructor statement-arg fails differently when a preceding param has a dynarray field

- **Type:** bug (parser / call lowering — correctness) — Track A
- **Status:** done — already fixed as a side effect of
  [[bug-open-array-ctor-statement-call]]'s fix; re-verified 2026-07-01, see Log
- **Severity:** low — workaround is trivial (bind the literal to a named
  const first), but the error message is actively misleading.
- **Opened:** 2026-06-30 (found while building lib/asmcore, Track B)
- **Relation:** same general family as
  [[bug-open-array-ctor-statement-call]] (inline `[...]` as an open-array arg
  fails when the call is a statement, not an expression) — **not the same
  bug**: that one's symptom is `by-reference argument must be a variable ()`;
  this one is `too many array constant elements ()`, a different code path
  entirely (the typed-const-array parser, confirmed via
  `compiler/parser.inc:9700`, not the by-ref check).

## Symptom

```pascal
type TBuf = record Bytes: array of Byte; Len: Integer; end;
procedure Check(const name: AnsiString; const buf: TBuf; const a: array of Byte);
begin
  writeln(name, ' ', Length(a));
end;
var b: TBuf;
begin
  Check('hi', b, [1,2,3,4,5]);   { error: too many array constant elements () }
end.
```

Plain reduced shapes (string+record param, no dynarray field; or string+
simple-var param) call fine as a *statement* with the inline `[...]` literal
— they instead hit `by-reference argument must be a variable ()`, i.e. they
hit the already-known bug. This specific shape — a `const` record parameter
**whose type has a dynamic-array field** sitting before the open-array
parameter — produces a *different* error message instead. Root cause not
isolated beyond this; flagging the distinguishing factor (preceding
dynarray-bearing record param) for whoever picks this up.

## Isolation attempts (2026-06-30)

| Call shape | Error |
| --- | --- |
| `f([4,5]);` (procedure, no other params) | `by-reference argument must be a variable ()` |
| `Check('hi', rv, [1,2,3]);` where `rv: TRec` (`TRec = record x: Integer end`, no dynarray) | `by-reference argument must be a variable ()` |
| `Check('hi', b, [1,2,3,4,5]);` where `b: TBuf` (`TBuf` has an `array of Byte` field) | **`too many array constant elements ()`** |

## Workaround

Bind the literal to a local typed const array first, then pass the named
const instead of the inline `[...]`:

```pascal
const expect: array[0..4] of Byte = (1,2,3,4,5);
...
Check('hi', b, expect);   { compiles fine }
```

## Acceptance

- `Check('hi', b, [1,2,3,4,5]);` (shape above) compiles and runs correctly.
- Whatever the fix turns out to be, confirm it doesn't regress
  [[bug-open-array-ctor-statement-call]]'s fix (if that lands first or
  together) — these may turn out to share a root cause once someone digs in,
  despite the different error messages observed here.
- Regression test added alongside whichever ticket's fix lands.

## Log
- 2026-06-30 — Opened (Track B, found while building lib/asmcore — see
  [[feature-asmcore-encoder-library]]).
- 2026-07-01 — Re-tested against current binary (pin v135): the exact repro
  above, and the other two isolation-table shapes (`f([4,5])` alone, and a
  non-dynarray record param before the open-array literal), all now compile
  and run correctly, matching real FPC output exactly. `bug-open-array-ctor-
  statement-call`'s fix evidently covered this shape too even though it
  wasn't specifically tested there. Added the dynarray-field-record-param
  case to `test/test_open_array_ctor_stmt.pas` (already wired into
  `make test`) rather than a new file, so this shape stays covered going
  forward. No code change needed — closing as already-fixed.
