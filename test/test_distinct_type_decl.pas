program test_distinct_type_decl;
{ `T = type Base` -- the standard Pascal strong-typedef spelling. pxx reported
  `unknown type: type` and stopped the file, so a construct common in FPC RTL
  headers and Delphi-lineage code could not be compiled at all.
  compat-pascal-distinct-type-declaration

  The keyword is consumed ahead of the whole type-binding chain, so EVERY
  right-hand shape has to keep taking the arm it would have taken without it --
  which is what the seven declarations below are for, one per arm.

  THE CONTROL IS NOT HERE, and that is deliberate. `type helper for T` is the
  OTHER meaning of tkType in exactly this position, so the guard is written by
  NAME rather than as "skip a tkType here"; swallow the keyword and every helper
  stops resolving. FPC 3.2.2 has no `type helper` at all (only `record`/`class
  helper`), so a control row for it cannot live in an FPC-oracled file --
  test_type_helper_property, test_type_helper_typename_receiver and
  test_class_helper_for_a_class are that control and are already wired.

  NOT asserted here, on purpose: the declared type is not yet DISTINCT for
  overload resolution. FPC binds `P(b)` and `P(x)` to different bodies; pxx
  warns `duplicate definition ... with the same parameter types` and binds both
  to one, exactly as it already does for a plain `= byte` alias.
  bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct }
{$MODE OBJFPC}
type
  TRec = record a, b: Integer; end;
  TMyB   = type byte;                          { a builtin scalar }
  TMyB2  = type TMyB;                          { ...through another distinct type }
  PB     = type PByte;                         { a pointer alias }
  TArr   = type array[0..3] of Char;           { an array type }
  TStr   = type string;                        { a managed string }
  TMyR   = type TRec;                          { a record }
  TFn    = type function(x: Integer): Integer; { a procedural type }

function Dbl(x: Integer): Integer; begin Dbl := x * 2; end;

var m: TMyB; m2: TMyB2; p: PB; a: TArr; st: TStr; r: TMyR; f: TFn;
    b: byte; c: cardinal;
begin
  { the ticket's own repro: a cast through the distinct name truncates }
  c := $12345678; m := 5;
  WriteLn(m, ' ', TMyB(c));                    { 5 120 }

  m2 := 100; b := 9; p := @b;
  a := 'abcd'; st := 'hi'; r.a := 3; r.b := 4; f := @Dbl;
  WriteLn(m2, ' ', p^, ' ', a, ' ', st, ' ', r.a + r.b, ' ', f(21));
  WriteLn(SizeOf(TMyB), ' ', SizeOf(TArr), ' ', SizeOf(TMyR));
end.
