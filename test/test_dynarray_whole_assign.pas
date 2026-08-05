program test_dynarray_whole_assign;
{ Regression: `b := a` on a DYNAMIC array must produce a usable array — correct
  Length, readable elements, and no crash — for plain and managed element types,
  as a local, as a global, and through a function.

  arm32 and riscv32 had no dynamic-array arm in IR_STORE_SYM at all, so the
  store fell through to the scalar path and published the wrong one of IR_LEA's
  read/write results; `Length(b)` then dereferenced garbage and segfaulted.
  That killed lib_zlib and, through it, lib_png.
  bug-a-arm32-dynamic-array-assignment-has-no-store-arm.

  NOTE: this deliberately does NOT assert aliasing (`a[0] := x` being visible
  through `b`). Dynamic arrays are reference types in FPC, but x86-64 currently
  copy-on-writes them, which is a separate pre-existing divergence tracked by
  bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing. Asserting it here
  would tie this regression to that one. }
type TByteArray = array of Byte;
var
  gData: TByteArray;

function Peek(i: Integer): Integer;
begin Peek := gData[i]; end;

procedure LocalToLocal;
var a, b: array of Byte;
begin
  SetLength(a, 8); a[3] := 42; a[7] := 7;
  b := a;
  writeln(Length(b), ' ', b[3], ' ', b[7]);
end;

procedure ManagedElems;
var s, t: array of string;
begin
  SetLength(s, 3);
  s[0] := 'p'; s[1] := 'q'; s[2] := 'r';
  SetLength(t, 1); t[0] := 'old';   { destination already holds a handle }
  t := s;
  writeln(Length(t), ' ', t[0], t[1], t[2]);
  t := t;                            { self-assign must not destroy it }
  writeln(Length(t), ' ', t[0], t[1], t[2]);
end;

var s: TByteArray;
begin
  LocalToLocal;
  ManagedElems;
  SetLength(s, 8); s[3] := 42;
  gData := s;                        { global := local }
  writeln(Length(gData), ' ', gData[3], ' ', Peek(3));
  writeln('OK');
end.
