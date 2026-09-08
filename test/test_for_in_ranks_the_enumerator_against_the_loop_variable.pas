program test_for_in_ranks_the_enumerator_against_the_loop_variable;
{$mode objfpc}{$H+}
{ WHICH ENUMERATOR A for-in TAKES IS NOT A PROPERTY OF THE CONTAINER.

  The obvious rule -- "a built-in iteration meaning beats a user operator on the
  same type" -- is false, and it is false in a way no per-family table can
  express. The rows that settle it are the PAIRS below: the same container, the
  same operators in scope, and a different answer because the LOOP VARIABLE's
  type changed.

    for ch in s   (ch: Char)     -> builtin, the characters
    for i  in s   (i: Integer)   -> the OPERATOR
    for e  in st  (e: TElem)     -> builtin, the members
    for i  in st  (i: Integer)   -> the OPERATOR          [see the note below]

  So: THE OPERATOR RUNS ONLY WHEN ITS Current TYPE IS EXACTLY THE LOOP
  VARIABLE'S. A container that HAS a built-in meaning otherwise keeps it, and a
  genuine tie -- neither candidate matching -- goes to the BUILT-IN.

  `getenum` is not a counterexample and was once read as one: there BOTH
  candidates yield Integer and the loop variable IS Integer, so the operator
  wins by matching exactly rather than by winning a tie.

  THE width ROWS ARE WHAT RULE OUT A LADDER, and they are the reason this is
  spelled "exactly" and not "compatibly". One `set of 0..7`, one operator
  returning Integer, only the loop variable's type moving: byte, word and even
  INT64 keep the built-in, and only `longint` -- which IS Integer -- runs the
  operator. Nothing about width, bounds or signedness survives that; int64 is
  wider than the element and still loses. `longint` also earns its row twice
  over: Integer and LongInt are one FPC type carried here as two kinds
  (tyInteger / tyInt32), so a bare kind comparison discriminates on the
  SPELLING -- the closed
  bug-p-integer-and-longint-are-not-the-same-type-in-overload-matching,
  reproducing itself at a second exact-match site.

  BOTH SPELLINGS OF THE STRING CONTAINER, deliberately: a bare variable and an
  expression. They must move together or one spelling stays wrong, and they do
  here for a reason worth knowing -- BuildForInStringValueLoop materialises the
  expression into a hidden string symbol and re-enters ParseForInVarAST, so the
  SYMBOL arm decides both. The expression arm further down never sees it.

  BOTH SPELLINGS OF THE SET CONTAINER too, and that pair had to be chased: a
  set RETURNS EARLY out of the symbol arm into the membership scan, so it was
  the one container the ranking never reached, and `for i in st` answered the
  built-in while its expression twin `st + [4]` already answered the operator.
  The ranking therefore happens AT that early exit -- the last point a set can
  be ranked at all -- and the two spellings agree here by measurement.

  Oracle: fpc 3.2.2 -Mobjfpc.
  bug-p-for-in-over-a-string-prefers-a-user-operator-enumerator-and-fpc-prefers-the-builtin }
type
  TElem = 0..7;
  TSet  = set of TElem;
  TEnum = class
    stop: Boolean; F: Integer;
    function MoveNext: Boolean;
    property Current: Integer read F;
  end;
  TShort = string[8];
  TCol = class
    function GetEnumerator: TEnum;
  end;

function TEnum.MoveNext: Boolean; begin Result := not stop; stop := True; end;

function MkE(v: Integer): TEnum;
begin Result := TEnum.Create; Result.F := v; Result.stop := False; end;

{ One operator per container type, each returning a DISTINGUISHABLE constant, so
  the printed value says which candidate ran rather than merely that something
  did. A one-row table cannot tell a correct lookup from one that ignores its
  key. }
function TCol.GetEnumerator: TEnum;         begin Result := MkE(11); end;
operator enumerator(a: AnsiString): TEnum;  begin Result := MkE(99); end;
operator enumerator(a: TShort): TEnum;      begin Result := MkE(66); end;
operator enumerator(a: TSet): TEnum;        begin Result := MkE(88); end;
operator enumerator(a: TCol): TEnum;        begin Result := MkE(44); end;

var
  ch: Char; i: Integer; e: TElem;
  b: Byte; w: Word; q: Int64; l: LongInt;
  s1, s2: AnsiString; ss: TShort; st: TSet; c: TCol;
begin
  s1 := 'ab'; s2 := 'c'; ss := 'de'; st := [1, 2]; c := TCol.Create;

  Write('str-char      '); for ch in s1      do Write(ch, ' '); WriteLn;
  Write('str-char-expr '); for ch in s1 + s2 do Write(ch, ' '); WriteLn;
  Write('short-char    '); for ch in ss      do Write(ch, ' '); WriteLn;
  Write('str-int       '); for i  in s1      do Write(i, ' ');  WriteLn;
  Write('set-elem      '); for e  in st      do Write(e, ' ');  WriteLn;
  Write('set-int       '); for i  in st      do Write(i, ' ');  WriteLn;
  Write('set-int-expr  '); for i  in st + [4] do Write(i, ' ');  WriteLn;
  Write('set-byte      '); for b  in st      do Write(b, ' ');  WriteLn;
  Write('set-word      '); for w  in st      do Write(w, ' ');  WriteLn;
  Write('set-int64     '); for q  in st      do Write(q, ' ');  WriteLn;
  Write('set-longint   '); for l  in st      do Write(l, ' ');  WriteLn;
  Write('getenum-tie   '); for i  in c       do Write(i, ' ');  WriteLn;
end.
