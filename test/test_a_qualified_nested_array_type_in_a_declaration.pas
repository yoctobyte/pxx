program test_a_qualified_nested_array_type_in_a_declaration;
{$mode objfpc}{$H+}
{ `var a: TOwn.TPArr;` -- a nested ARRAY type reached through its owner's name.

  ParseDeclTypeDesc probes FindArrayType(CurTok.SVal) BEFORE handing the tokens
  to ParseTypeKind, and for the qualified spelling CurTok is the OWNER. The
  probe missed, the descriptor fell through, and the declaration was accepted as
  a scalar -- no diagnostic at the declaration, and `this value cannot be
  indexed` at the first `[`.

  The rows are split by which path fills the descriptor, because they did NOT
  all fail: the record FIELD arm (ParseRecordFields) and the enum/set arms
  (ParseTypeKind, which strips for itself) were right through the same qualifier
  the whole time. Those are the controls -- they must stay green either way, and
  they are what says the strip belongs in this routine and not in the lookup.

  Sizes are asserted as RELATIONS, never as byte counts, so the rows carry no
  target-specific constant and a wrong element type still shows.
  Oracle: fpc 3.2.2.
  bug-p-a-nested-array-type-is-refused-in-a-qualified-declaration }
type
  TOwn = class
  type
    TPArr = array[0..3] of LongInt;
    TPRec = record a, b: LongInt; end;
    TDyn  = array of LongInt;
    TE    = (eA, eB, eC);
    TSet  = set of TE;
  class var
    cv: TOwn.TPArr;
  end;
  THolder = record f: TOwn.TPArr; end;
  TTopArr = array[0..3] of LongInt;

  { The guard's own positive control. Two owners each declare a nested CLASS of
    ONE name, so the qualifier picks which type is meant rather than merely
    disambiguating the parse -- and ParseTypeKindInner's copy of the strip is
    what rewrites the name to the right row. Stripping ahead of it for a CLASS
    member consumes the qualifier that arm reads, and `bw.w` then resolves
    against whichever `TIn` registered first: `no such member`, silently for a
    reader who only sees two classes with the same shape.
    EatQualifiedArrayTypePrefix declines here because FindNestedType answers a
    row, which is exactly the case where the two copies do NOT agree. }
  TOwnerA = class type TIn = class x: LongInt; end; end;
  TOwnerB = class type TIn = class w, v: LongInt; end; end;

var
  g: TOwn.TPArr;              { global var section }
  h: THolder;                 { record field -- control, already worked }
  u: TTopArr;                 { unqualified -- control }
  dd: array of TOwn.TDyn;     { dyn array whose ELEMENT is a qualified dyn alias }
  fd: array[0..1] of TOwn.TDyn;
  kf: array[0..1] of TOwn.TPArr;
  qf: array of TOwn.TPArr;
  e: TOwn.TE;                 { enum -- control }
  s: TOwn.TSet;               { set -- control }
  b: TOwn.TDyn;               { for the var parameter }
  ba: TOwnerA.TIn;
  bb: TOwnerB.TIn;            { must NOT bind to TOwnerA's TIn }

procedure TakeFix(const v: TOwn.TPArr);          { value parameter }
begin WriteLn('param-fix ', v[2], ' ', SizeOf(v) div SizeOf(LongInt)); end;

procedure TakeDyn(var v: TOwn.TDyn);             { var parameter }
begin SetLength(v, 3); v[1] := 31; WriteLn('param-dyn ', v[1], ' ', Length(v)); end;

{ OPEN array whose ELEMENT is a qualified row. Called with a LITERAL, not with
  a static-outer array: passing `array[0..1] of TRow` to an open-array param is
  a residual the row-model work parked deliberately (Length answers 0 there for
  the UNQUALIFIED spelling too -- measured, both spellings agree, so it is not
  this defect). The literal is the path that model does cover, and it is what
  says the qualified element reaches exactly what the plain one reaches. }
procedure TakeOpen(const rows: array of TOwn.TPArr);
begin WriteLn('param-open ', rows[1][2], ' ', Length(rows)); end;

function MakeFix: TOwn.TPArr;                    { fixed-array result }
begin Result[2] := 41; end;

function MakeDyn: TOwn.TDyn;                     { dyn-array result }
begin SetLength(Result, 3); Result[1] := 42; end;

procedure Local;
var L: TOwn.TPArr;            { routine-local var section }
begin
  L[2] := 5;
  WriteLn('local ', L[2], ' ', SizeOf(L) div SizeOf(LongInt));
end;

begin
  g[0] := 42; g[2] := 43;
  h.f[1] := 8;
  u[3] := 3;
  TOwn.cv[3] := 9;
  SetLength(dd, 2); SetLength(dd[1], 3); dd[1][2] := 7;
  SetLength(fd[0], 4); fd[0][3] := 11;
  kf[1][2] := 13; kf[0][2] := 12;
  SetLength(qf, 2); qf[1][2] := 15;
  e := eB; s := [eA, eC];
  Local;
  WriteLn('global ', g[0], ' ', g[2], ' ', SizeOf(g) div SizeOf(LongInt));
  WriteLn('field ', h.f[1], ' ', SizeOf(h) div SizeOf(LongInt));
  WriteLn('plain ', u[3], ' ', SizeOf(u) div SizeOf(LongInt));
  WriteLn('classvar ', TOwn.cv[3]);
  WriteLn('dyn-of-dyn ', dd[1][2], ' ', Length(dd), ' ', Length(dd[1]));
  WriteLn('fix-of-dyn ', fd[0][3], ' ', Length(fd[0]));
  WriteLn('fix-of-fix ', kf[1][2], ' ', SizeOf(kf) div SizeOf(g));
  WriteLn('dyn-of-fix ', qf[1][2], ' ', Length(qf));
  WriteLn('enum ', Ord(e), ' ', eC in s);
  ba := TOwnerA.TIn.Create; ba.x := 61;
  bb := TOwnerB.TIn.Create; bb.w := 62; bb.v := 63;
  WriteLn('sibling-class ', ba.x, ' ', bb.w, ' ', bb.v);
  TakeFix(g);
  TakeDyn(b);
  TakeOpen([kf[0], kf[1]]);
  WriteLn('ret-fix ', MakeFix[2]);
  WriteLn('ret-dyn ', MakeDyn[1], ' ', Length(MakeDyn));
end.
