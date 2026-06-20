# SetLength rejects dynamic-array function result

- **Type:** bug (compiler / codegen)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-20
- **Relation:** surfaced while building `lib/rtl/png.pas`; blocks idiomatic
  dynamic-array-returning library code.

## Problem

`SetLength(Result, n)` inside a function returning a dynamic array fails during
IR codegen:

```
pascal26:175: error: SetLength expects a string variable in IR codegen ()
```

The source shape is normal Pascal and should work for dynamic arrays just as it
does for a named local dynamic-array variable.

## Reproduction

```pascal
program repro;

type
  TByteArray = array of Byte;

function MakeBytes(n: Integer): TByteArray;
begin
  SetLength(Result, n);
  if n > 0 then Result[0] := 42;
end;

begin
  writeln(MakeBytes(1)[0]);
end.
```

The PNG library hits the same shape in:

```pascal
function BuildRawRGBA(const img: TImage): TByteArray;
begin
  SetLength(Result, img.Height * (1 + img.Width * 4));
  ...
end;
```

## Expected

The compiler should treat the function result lvalue as a dynamic-array
variable for `SetLength`, retain/release it correctly, and allow indexed writes
to the resized result.

## Actual

The compiler rejects the call as if only string result variables are accepted by
the `SetLength` lowering path.

## Notes

Do not work around this in library code by introducing a temporary local solely
to satisfy the compiler. The library should remain idiomatic and the compiler
should learn this lvalue shape.

## Log

- 2026-06-20 — opened from Track B PNG library work. Reproduces with pinned
  stable when compiling `test/lib_png.pas`.
