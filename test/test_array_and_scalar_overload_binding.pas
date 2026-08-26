{ An array argument and a scalar argument must reach their own overload,
  whichever order the two are declared in.

  pxx presents an array's ELEMENT kind as its type kind, so `array of AnsiString`
  and plain `AnsiString` look identical to overload resolution, as do
  `array of Integer` and `Integer`. Resolution therefore took whichever was
  DECLARED FIRST, in both directions:

    P('hello') on P(array of AnsiString) declared first -> `arr 5`
    S(ia)      on S(v: Integer)          declared first -> `Sint 1440743456`
    T(fa)      on T(v: Integer)          declared first -> `Tint 4303792`

  Silent wrong dispatch and silent wrong values -- the last two are the
  dyn-array handle and the variable's address printed as integers. And because
  it flipped with declaration order, the same two overloads written the other
  way round were always right, which is what made this look like it was not
  happening (Q and the second half of each pair below).

  Both directions are pinned because they are separate facts with separate
  evidence: "this argument is certainly not an array" and "this argument is
  certainly an array" are not each other's negation when every uncertain shape
  has to stay matchable. Fixing one leaves the other silently wrong.

  Extends bug-a-an-integer-argument-binds-a-fixed-array-overload, which added
  the first half of the first direction. Every row measured against fpc 3.2.2
  (-Mobjfpc -O1). }
program test_array_and_scalar_overload_binding;
uses sysutils;
type
  TSA = array of AnsiString;
  TIA = array of Integer;
  TFA = array[0..2] of Integer;
var
  a: TSA; ia: TIA; fa: TFA; txt: AnsiString; sh: string[8];

{ --- a SCALAR argument must not bind the ARRAY overload --- }

{ array declared FIRST: the order that used to lose }
procedure P(const v: TSA); overload;
begin WriteLn('arr ', Length(v)); end;
procedure P(const v: AnsiString); overload;
begin WriteLn('str ', v); end;

{ ...and the other way round, which was always right }
procedure Q(const v: AnsiString); overload;
begin WriteLn('Qstr ', v); end;
procedure Q(const v: TSA); overload;
begin WriteLn('Qarr ', Length(v)); end;

{ an array of a DIFFERENT element kind was never confusable }
procedure R(const v: TIA); overload;
begin WriteLn('Rarr ', Length(v)); end;
procedure R(const v: AnsiString); overload;
begin WriteLn('Rstr ', v); end;

{ --- an ARRAY argument must not bind the SCALAR overload --- }

procedure S(v: Integer); overload;
begin WriteLn('Sint ', v); end;
procedure S(const v: TIA); overload;
begin WriteLn('Sarr ', Length(v)); end;

procedure T(v: Integer); overload;
begin WriteLn('Tint ', v); end;
procedure T(const v: TFA); overload;
begin WriteLn('Tfix ', v[0]); end;

procedure U(v: AnsiString); overload;
begin WriteLn('Ustr ', v); end;
procedure U(const v: TSA); overload;
begin WriteLn('Uarr ', Length(v)); end;

procedure Open(const v: array of AnsiString);
begin WriteLn('open ', Length(v)); end;

function Cat(const x: AnsiString): AnsiString;
begin Cat := x + '!'; end;

function MakeI: TIA;
begin SetLength(Result, 6); end;

begin
  SetLength(a, 3);
  SetLength(ia, 4);
  fa[0] := 11;

  { every shape of a scalar string argument }
  P('lit');
  txt := 'var'; P(txt);
  P(txt + 'x');        { a concatenation }
  P(Cat('c'));       { a string-returning call }
  sh := 'fz'; P(sh); { a frozen string }
  Q('lit');
  R('lit');

  { array arguments, against a scalar overload declared first }
  S(ia);
  S(MakeI);          { ...including an array-returning CALL }
  T(fa);
  U(a);

  { ...and the array argument still reaches the array overload where it always did }
  P(a);
  Q(a);
  R(ia);
  Open(a);

  { `array of const` is exempt -- it legitimately takes anything }
  WriteLn(Format('%s/%d', ['f', 7]));
end.
