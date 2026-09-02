program test_char_array_field_is_a_string;

uses sysutils;

{ A static `array[..] of Char` IS a string in both directions -- and that was
  true only when it was spelled as a plain VARIABLE. Reached through a record
  FIELD or a pointer DEREF, ASTCharArrayCap answered -1, the conversion never
  fired, and the store fell through to the scalar type check:

    r.szDescription := 'Synsock';   error: cannot assign ShortString to Char
    a := 'Synsock';                 ok

  One oracle, one shape, five of six lvalues refused. Two lines of synapse's
  ssfpc.inc (`with WSData do` over szDescription/szSystemStatus, both
  `array[0..N] of Char`) took out all three lib_synapse jobs plus the TLS
  loopback. bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string

  What is asserted here is FPC's rule, not "it compiles": the store writes
  Min(Length(s), cap) characters and then ZERO-FILLS the rest, so a shorter
  string does not leave stale bytes behind, and the read stops at the first #0
  within cap. The padding is the half a compile-only test would miss -- the
  bug's own symptom in the plain-variable shape was five stale bytes. }

type
  TInner = record d: array[0..7] of Char; end;
  TRec = packed record
    a: array[0..7] of Char;
    tail: LongInt;              { the store must not run past `a` into this }
    inner: TInner;
  end;
  TArr8 = array[0..7] of Char;
  PArr8 = ^TArr8;

var
  r: TRec;
  ra: array[0..1] of TRec;
  buf: TArr8;
  p: PArr8;
  s: string;
  fails: Integer;

procedure Check(const what: string; got, want: string);
begin
  if got = want then
    WriteLn(what, '=ok')
  else
  begin
    WriteLn(what, '=FAIL got[', got, '] want[', want, ']');
    Inc(fails);
  end;
end;

function Dump(const a: TArr8): string;
{ Every byte, so a ZERO FILL is distinguishable from a stale one. }
var i: Integer;
begin
  Result := '';
  for i := 0 to 7 do
    if a[i] = #0 then Result := Result + '.'
    else Result := Result + a[i];
end;

function DumpF(rec: TRec): string;
begin
  DumpF := Dump(rec.a);
end;

begin
  fails := 0;

  { 1. the shape that always worked -- the control. Without it a green run
       would not distinguish "the fix works" from "nothing runs". }
  buf := 'abc';
  Check('var', Dump(buf), 'abc.....');

  { 2. a record FIELD, the synapse shape. }
  r.tail := 12345;
  r.a := 'abc';
  Check('field', DumpF(r), 'abc.....');
  Check('field-neighbour', IntToStr(r.tail), '12345');

  { 3. the zero fill, which is the half that is not about compiling: a LONGER
       value first, then a shorter one over it. FPC leaves 'ab' + six zeros,
       not 'abcdefgh' with two bytes patched. }
  r.a := 'abcdefgh';
  Check('field-full', DumpF(r), 'abcdefgh');
  r.a := 'ab';
  Check('field-refill', DumpF(r), 'ab......');

  { 4. TRUNCATION at cap -- no write past the eighth element. }
  r.a := 'abcdefghXYZ';
  Check('field-truncate', DumpF(r), 'abcdefgh');
  Check('field-truncate-neighbour', IntToStr(r.tail), '12345');

  { 5. a NESTED field, and a field of a record ARRAY ELEMENT. }
  r.inner.d := 'zz';
  Check('nested-field', Dump(r.inner.d), 'zz......');
  ra[1].a := 'q';
  Check('elem-field', Dump(ra[1].a), 'q.......');

  { 6. through a POINTER DEREF. }
  p := @buf;
  p^ := 'de';
  Check('deref', Dump(buf), 'de......');

  { 7. the READ direction, same three shapes -- one oracle drives both, so a
       fix that only reached the store would show up here. The read stops at
       the first #0 within cap. }
  r.a := 'abc';
  s := r.a;
  Check('read-field', s, 'abc');
  s := r.inner.d;
  Check('read-nested', s, 'zz');
  p^ := 'de';
  s := p^;
  Check('read-deref', s, 'de');

  { 8. a non-literal source, which takes a different arm than the literal. }
  s := 'wx';
  r.a := s;
  Check('field-from-var', DumpF(r), 'wx......');

  if fails = 0 then WriteLn('CHARARRFIELD OK')
  else begin WriteLn('CHARARRFIELD FAILED ', fails); Halt(1); end;
end.
