{ By-VALUE Variant parameters (bug-pascal-byvalue-variant-param).

  A Variant is 16 bytes, so its parameter slot is pointer-sized and holds the
  ADDRESS of the value — for `const`/`var` the caller's own variant, for a
  plain by-value param a hidden caller-side COPY. Before the fix the callee
  read the slot as if it were the value: `show(2)` printed garbage and a
  variant variable printed its tag. The copy is what makes writes inside the
  callee invisible to the caller, which is the whole point of by-value. }
program test_variant_byvalue_param;

procedure ByVal(v: Variant);
begin
  writeln('byval: ', v);
  v := 'clobbered';              { must NOT reach the caller }
  writeln('after write: ', v);
end;

procedure ByConst(const v: Variant);
begin
  writeln('const: ', v);
end;

procedure ByRef(var v: Variant);
begin
  v := 'written';                { must reach the caller }
end;

{ several variant params in one call, mixed with an ordinary scalar }
procedure Three(a: Variant; b: Variant; n: Integer);
begin
  writeln('three: ', a, ' ', b, ' ', n);
end;

function RoundTrip(v: Variant): Variant;
begin
  Result := v;
end;

var x: Variant;
begin
  { a literal boxes into a hidden variant temp }
  ByVal(2);
  ByConst(2);

  x := 42;      ByVal(x);  ByConst(x);
  x := 'hi';    ByVal(x);  ByConst(x);
  writeln('caller intact: ', x);

  ByRef(x);
  writeln('after byref: ', x);

  x := 1;
  Three(x, 'str', 7);
  Three(5, 'lit', 8);

  x := 'rt';
  writeln('roundtrip: ', RoundTrip(x));

  x := 3.5;
  ByVal(x);
  writeln('float intact: ', x);
end.
