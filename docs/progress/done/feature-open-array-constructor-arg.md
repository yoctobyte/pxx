# feature: array constructor `[...]` as an open-array argument

- **Type:** feature (Track A — parser / call lowering)
- **Status:** done
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

## Resolution (2026-06-23)

New AN_ARRAY_CTOR node (defs.inc), the plain-element mirror of AN_VARREC_ARRAY.
At a call where the param is an `array of T` with a scalar/string element
(ParamIsOpenArrayScalar), a `[...]` argument is parsed by ParseArrayCtorAST into
AN_ARRAY_CTOR tagged with the element type (so overload matching binds it to the
open-array param, whose TypeKind is the element type). Lowering (ir.inc) builds a
heap dyn-array temp: alloc + nil-init + SetLength(N) + per-element store via the
normal element-assign path (coercion + managed-string ARC), yielding the
data-pointer handle. Wired into both the expression-level (parser ~4243) and
statement-level (~7494) call-arg loops; AN_ARRAY_CTOR also bypasses the by-ref
"must be a variable" check (it IS the open-array temp) and passes through
IRLowerCallArg.

f([1,2,3])=6, f([10,20,30,40])=100, g(['a','b'])=2 (string elems), h([])=0 (empty)
— byte-identical to FPC. Self-host byte-identical; array-of-const/open-array test
suite green. Closes feature-open-array-constructor-arg.
