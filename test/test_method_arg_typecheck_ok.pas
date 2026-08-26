{ The positive half of the single-candidate argument gate: the shapes it must
  keep ACCEPTING.

  The obvious gate — refuse whenever TypesCompatible says no — is unsound on
  this path, and only measuring showed it. Four classes of legal call were
  refused, each because the speculative overload probe lacks a side channel the
  free-call path has. Every one of them is a row below.
  bug-p-a-single-candidate-method-call-does-not-check-its-argument-types

  Oracled against fpc 3.2.2. }
{$mode objfpc}
program margok;

uses Variants;   { FPC: boxing into a Variant is RTE 217 without it }
type
  TCmp = function(a, b: Pointer): Integer;

  TC = class
    { an open array parameter: its TypeKind is the ELEMENT kind, so ranking an
      argument against it is meaningless — this is CreateFmt's shape, which the
      first cut refused across seven conformance programs }
    procedure Fmt(const msg: AnsiString; const args: array of const);
    { nil binds any reference-shaped parameter — SetOnKeyPtrCompare(nil), which
      took the whole fgl rung to 0/7 }
    procedure SetCmp(f: TCmp);
    { a routine as a procedural value, which the probe types as neither a
      pointer nor the procedural type — fgl's inherited Sort(ItemPtrCompare).
      Spelled `@ByPtr`: the BARE name in this position is a separate
      pre-existing gap (`undefined variable (ByPtr)`, identical on the
      pinned compiler) and is not what this file is about. }
    procedure Sort(f: TCmp);
    { an untyped var takes anything by definition }
    procedure Raw(var x);
    { a Variant accepts every kind }
    procedure Any(v: Variant);
    { and the ordinary compatible conversions must still pass }
    procedure Str(const s: AnsiString);
    procedure Num(n: Int64);
  end;

procedure TC.Fmt(const msg: AnsiString; const args: array of const);
begin WriteLn('fmt ', msg, ' ', Length(args)); end;
procedure TC.SetCmp(f: TCmp); begin WriteLn('setcmp ', f = nil); end;
procedure TC.Sort(f: TCmp); begin WriteLn('sort ', f = nil); end;
procedure TC.Raw(var x); begin WriteLn('raw'); end;
{ prints no value: WriteLn of a bare Variant is RTE 217 under FPC without
  the variants unit, and what is under test is that the CALL is accepted }
procedure TC.Any(v: Variant); begin WriteLn('any'); end;
procedure TC.Str(const s: AnsiString); begin WriteLn('str ', s); end;
procedure TC.Num(n: Int64); begin WriteLn('num ', n); end;

function ByPtr(a, b: Pointer): Integer;
begin
  if a = b then ByPtr := 0 else ByPtr := 1;
end;

var
  c: TC;
  i: Integer;
  ch: Char;
  s: AnsiString;
begin
  c := TC.Create;
  i := 7;
  ch := 'z';
  s := 'hi';

  c.Fmt('%s', [s]);        { open array of const }
  c.Fmt('%d', [i, s]);     { ...of a different length }
  c.SetCmp(nil);           { nil into a procedural parameter }
  c.Sort(@ByPtr);          { a routine as a procedural value }
  c.Raw(i);                { untyped var }
  c.Raw(s);                { ...whatever the argument is }
  c.Any(i);                { Variant takes an ordinal }
  c.Any(s);                { ...and a string }
  c.Str(ch);               { Char -> AnsiString, a legal conversion }
  c.Str('lit');            { a frozen literal -> managed AnsiString }
  c.Num(i);                { Integer -> Int64 widening }
end.
