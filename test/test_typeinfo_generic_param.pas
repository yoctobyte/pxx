program test_typeinfo_generic_param;
{ TypeInfo(T) where T is a GENERIC PARAMETER, resolved at specialization time —
  the case feature-typeinfo-all-types was actually opened for (generics.defaults
  picks a comparer per TypeInfo(T)).

  It needs no separate path, and this test is here to PROVE that rather than
  assume it: pxx generics substitute the type parameter's token TEXTUALLY before
  the parser reaches the body, so `TypeInfo(T)` inside a specialized TBox<Byte>
  is already `TypeInfo(Byte)` by then and takes the ordinary path. The Byte row
  is the one that would catch a regression there, since `byte` and `integer`
  share a token kind and answering "Integer" for both is exactly how this path
  was broken before.

  TSub proves the substitution reaches the NAMED-type tables too, not just the
  builtin spellings — a specialization over a subrange must still report `TSub`.

  Diffed against FPC 3.2.2. The one divergence is deliberate and escalated: we
  say `Integer` where FPC says `LongInt`, because pxx has tyInteger and tyInt32
  as separate kinds where FPC's Integer IS LongInt —
  decide-typeinfo-scalar-name-spelling (Track U).

  Note the body parks TypeInfo(T) in a VARIABLE rather than writing
  `PTypeInfo(TypeInfo(T))^.NamePtr^` inline. That is not style: the inline
  typecast spelling drops the final deref and prints the raw pointer —
  bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped. Restore the
  inline form here once that is fixed; it is a second assertion for free. }
uses typinfo;
type
  TSub = 1..10;
  generic TBox<T> = class
    procedure Show;
  end;
  TBoxInt  = specialize TBox<Integer>;
  TBoxByte = specialize TBox<Byte>;
  TBoxStr  = specialize TBox<string>;
  TBoxSub  = specialize TBox<TSub>;
procedure TBox.Show;
var p: PTypeInfo;
begin
  p := TypeInfo(T);
  Writeln(p^.NamePtr^, ' ', p^.Kind);
end;
var a: TBoxInt; b: TBoxByte; c: TBoxStr; d: TBoxSub;
begin
  a := TBoxInt.Create;  a.Show;
  b := TBoxByte.Create; b.Show;
  c := TBoxStr.Create;  c.Show;
  d := TBoxSub.Create;  d.Show;
end.
