program test_for_in_operator_enumerator_on_an_alias_and_an_expression;
{$mode objfpc}
{ `operator enumerator` was reachable only when the container was a bare
  VARIABLE whose type was spelled with a builtin name. Two independent walls,
  both measured against fpc 3.2.2 on 2026-09-07:

    - a NAMED SCALAR ALIAS could not be an operand type at all -- the operator
      DECLARATION was refused with `TInt is not a supported operand type`,
      before any use site existed;
    - a container that was an EXPRESSION rather than a symbol never reached the
      operator table, because the arm that consults it takes a Sym index.

  Row 5 is the one that is not about this fix: `v + 1` needs the operator
  declared on Int64, because integer arithmetic evaluates at Int64 here. That is
  the declared architecture (CLAUDE.md, the native evaluation type), so the row
  asserts the WORKING spelling and exists to record which spelling that is. }
type
  TEnum = class
    stop: Boolean;
    F: Integer;
    function MoveNext: Boolean;
    property Current: Integer read F;
  end;
  TInt   = Integer;          { a PLAIN alias }
  TTwice = type Integer;     { a DISTINCT alias -- same row shape, `type` keyword }

function TEnum.MoveNext: Boolean;
begin
  Result := not stop;
  stop := True;
end;

operator enumerator(a: TInt): TEnum;
begin
  Result := TEnum.Create; Result.F := a; Result.stop := False;
end;

{ A SECOND operand type, so the table is not answering from a single row --
  a one-row table cannot tell a correct lookup from a lookup that ignores its
  key, which is the whole point of having two. }
operator enumerator(a: Int64): TEnum;
begin
  Result := TEnum.Create; Result.F := Integer(a) + 1000; Result.stop := False;
end;

var
  i: Integer;
  vi: TInt;
  vt: TTwice;
  vv: Integer;
begin
  vi := 7;
  for i in vi do WriteLn('alias ', i);              { alias operand, var container }

  vt := 5;
  for i in vt do WriteLn('distinct ', i);           { a DISTINCT alias reaches the same row }

  vv := 9;
  for i in vv do WriteLn('builtin ', i);            { the spelling that always worked }

  for i in Int64(4) do WriteLn('cast ', i);         { container is a CAST expression }

  vv := 9;
  for i in vv + 1 do WriteLn('expr ', i);           { container is an arithmetic expression }

  { THE CONTAINER'S FIRST TOKEN NO LONGER HAS TO BE tkIdent. These three were
    refused before the dispatch decided anything, by a gate reading the LEXER:
    `Int64` arrives as tkIdent and `Integer` as its own token kind, so the two
    spellings of one cast got opposite answers for a reason invisible in the
    source. `cast` above is the row that always worked and is the control -- it
    and `castint` must now agree, and they differ only in a token kind.
    bug-p-a-for-in-container-must-start-with-an-identifier-token }
  for i in Integer(4) do WriteLn('castint ', i);    { the SAME cast, spelled with a non-ident token }
  for i in 4 do WriteLn('lit ', i);                 { a bare integer literal }
  for i in (vv) do WriteLn('paren ', i);            { one pair of parentheses is the whole difference }
end.
