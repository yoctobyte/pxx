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

  So: rank the candidates by whether their Current type matches the loop
  variable, and give the TIE to the operator. `getenum` is the tie -- a class
  whose own GetEnumerator and whose operator both yield Integer -- and fpc takes
  the operator there, which is the half pxx had backwards.

  BOTH SPELLINGS OF THE STRING CONTAINER, deliberately: a bare variable and an
  expression. They must move together or one spelling stays wrong, and they do
  here for a reason worth knowing -- BuildForInStringValueLoop materialises the
  expression into a hidden string symbol and re-enters ParseForInVarAST, so the
  SYMBOL arm decides both. The expression arm further down never sees it.

  NOT IN THIS FIXTURE, and measured rather than assumed: `for i in st` with an
  Integer loop variable over a set still answers the builtin here where fpc runs
  the operator. That is not the ranking rule -- it is the symbol arm's operator
  LOOKUP missing for a set container, which is a separate defect with its own
  landing. Its expression twin (`st + [4]`) already answers the operator, so the
  two spellings currently disagree; pinning either here would pin half a bug.

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
  s1, s2: AnsiString; ss: TShort; st: TSet; c: TCol;
begin
  s1 := 'ab'; s2 := 'c'; ss := 'de'; st := [1, 2]; c := TCol.Create;

  Write('str-char      '); for ch in s1      do Write(ch, ' '); WriteLn;
  Write('str-char-expr '); for ch in s1 + s2 do Write(ch, ' '); WriteLn;
  Write('short-char    '); for ch in ss      do Write(ch, ' '); WriteLn;
  Write('str-int       '); for i  in s1      do Write(i, ' ');  WriteLn;
  Write('set-elem      '); for e  in st      do Write(e, ' ');  WriteLn;
  Write('getenum-tie   '); for i  in c       do Write(i, ' ');  WriteLn;
end.
