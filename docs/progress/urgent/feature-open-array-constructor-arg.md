# feature: array constructor `[...]` as an open-array argument

- **Type:** feature (Track A — parser / call lowering)
- **Status:** urgent (blocks Platonic Eliah IDE — RunCapture/array-of-string calls)
- **Found:** 2026-06-23, building the Eliah IDE (runner.RunCapture call)
- **Severity:** medium (common FPC idiom; forces a temp array variable per call)

## Gap

An inline array constructor passed to an `array of T` parameter is rejected:

```pascal
function f(const a: array of integer): integer; begin f := length(a); end;
begin writeln(f([1, 2, 3])); end.        { fpc: 3   pxx: error: no overload of f matches }

function g(const a: array of string): integer; begin g := length(a); end;
begin writeln(g(['a', 'b'])); end.        { fpc: 2   pxx: error: no overload of g matches }
```

Both the integer and string element cases fail, so it is the constructor-as-arg
path, not element type.

## Control (works)

The array-variable form is accepted:

```pascal
var v: array of string;
begin setlength(v, 2); v[0] := 'a'; v[1] := 'b'; writeln(g(v)); end.   { 2 }
```

## Expected

Accept `f([e1, e2, ...])` for an `array of T` parameter (FPC builds a temporary
open array). Also the `[]` empty-array case.

## Track B impact

Callers must pre-build a `SetLength`'d temp array (done in the IDE's compile/run
calls). Distinct from `bug-const-open-array-managed-elem-length` (a runtime
length defect) — this is the constructor not being accepted as an argument at all.

## Repro

`function f(const a: array of integer): integer; ... f([1,2,3])`.
