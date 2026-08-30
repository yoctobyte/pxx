{ The other half of test_assign_lvalue_shapes_fail.pas: everything the lvalue
  type check must NOT start refusing.

  The check now types an element, a field and a deref instead of silently
  standing down on them, so the surface it can wrongly REJECT grew by exactly
  the surface it can now correctly refuse. A fix that turns a false accept into
  a false reject is a regression that looks like progress, and the only way to
  see it is to compile working code and RUN it — "accepted" and "correct" are
  different claims, so this program prints.

  The rows that are here because they nearly broke, not because they are
  interesting:

  - An INTERFACE is spelled tyRecord (a 16-byte fat pointer {IMT, instance}),
    so the record rule would refuse `ptr := rr.I`, which fpc accepts. Measured,
    not assumed: PXXDBG=a.ast prints the AN_FIELD for `rr.I` as tk=5 and the
    Pointer destination as tk=17, which is the record-XOR-record pair firing.
    The AN_IDENT arm carries the same bail for the same reason.
  - A Char is a legal SOURCE for a string and never a legal sink, in every
    lvalue shape, not just an identifier.
  - tyString and tyAnsiString are assignable to each other in this dialect on
    purpose; a destination-kind table treating them as distinct would reject
    working code.
  - An ARRAY-typed field (`cc.Buf[2]`) and a nested element (`rs[0].N`) reach
    the check through two node kinds at once.

  Verified against fpc 3.2.2: same source, identical stdout.
  bug-p-a-string-assigned-to-a-record-ARRAY-ELEMENT-is-not-type-checked }
program test_assign_lvalue_shapes_ok;
{$mode objfpc}{$H+}{$interfaces corba}
type
  IFoo   = interface procedure Go; end;
  TFoo   = class(TInterfacedObject, IFoo) procedure Go; end;
  TRec   = record S: AnsiString; N: Integer; end;
  PRec   = ^TRec;
  TPStr  = ^AnsiString;
  PIntf  = record I: IFoo; end;
  TRecs  = array of TRec;
  TFix   = array[0..1] of TRec;
  TIArr  = array of IFoo;
  TCls   = class Next: TCls; Buf: array[0..3] of Integer; Nm: AnsiString; end;
  PCls   = ^TCls;
  TSetR  = record S: set of 0..7; end;
procedure TFoo.Go; begin end;
var
  rs: TRecs; fx: TFix; r, r2: TRec; o: PIntf; ia: TIArr;
  cc, c2, c3: TCls; pc: PCls; p: PRec; psx: TPStr; sr: TSetR;
  ifv: IFoo; ptr: Pointer; s: AnsiString; sh: ShortString; ch: Char; i: Integer;
begin
  SetLength(rs, 2); SetLength(ia, 2);
  cc := TCls.Create; c2 := TCls.Create; c3 := TCls.Create; pc := @c3;
  New(p); New(psx);
  { record into record, through every shape }
  r.S := 'a'; r.N := 1;
  rs[0] := r;  fx[1] := r;  r2 := rs[0];  p^ := fx[1];  o.I := nil;
  { a Char is a legal source for a string sink in every shape }
  ch := 'z';
  rs[1].S := ch;  cc.Nm := ch;  psx^ := ch;
  { the two string kinds are interchangeable here on purpose }
  sh := 'sh';  cc.Nm := sh;  rs[1].S := sh;  s := cc.Nm;
  { interface spelled tyRecord: none of these may be refused }
  ifv := o.I;  ptr := o.I;  ptr := ia[0];  ia[1] := ifv;  o.I := ifv;
  { class-typed field and deref }
  cc.Next := nil;  cc.Next := c2;  pc^ := c2;  pc^.Next := cc;
  { pc aliases c3, deliberately NOT cc: a deref store that reseats the very
    variable the later rows read would hide them behind an empty object. }
  { an ARRAY-typed field, and a field OF an element }
  cc.Buf[2] := 7;  i := cc.Buf[2];  rs[0].N := 9;  i := i + rs[0].N;
  { a set inside a record }
  sr.S := [1, 3];  sr.S := sr.S + [5];
  WriteLn('lvok ', i, ' ', r2.S, ' ', rs[1].S, ' ', cc.Nm, ' ', psx^, ' ',
          p^.N, ' ', (5 in sr.S), ' ', pc^.Next.Buf[2]);
end.
