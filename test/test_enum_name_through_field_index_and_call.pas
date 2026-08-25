program test_enum_name_through_field_index_and_call;
{ The other half of test_writeln_of_an_enum_prints_its_name: an enum reached
  through anything OTHER than a plain variable still printed the ORDINAL, so the
  same enum printed two different ways in one program.

  Enum identity is not carried by the TYPE (a pxx enum is tyInteger at codegen),
  so every shape that can name one has to be asked separately. This file asserts
  one line per shape:

    a[i] / b[i] / d[i] / dd[i][j]   SymElemEnumId — an ARRAY symbol's TypeKind IS
                                    its element kind, so the element's identity
                                    needs its own slot; SymEnumId on an array
                                    would make `WriteLn(a)` claim to be an enum
    r.f / c.fk / n.inner.k          UFldEnumId — the field twin of SymEnumId
    r.g[i] / c.ka[i]                the same slot, holding the ELEMENT's enum
    F                               ProcRetEnumId — a call node has no symbol and
                                    no field, so the callee's row is the only
                                    place the result's identity survives
    p (var and value)               SymEnumId on the param symbol
    K                               SymEnumId on a typed const
    Succ/Pred, TE(i)                ASTEnumId, stamped where the parser derives it

  Ord() answering the number is asserted alongside, because the fix must not turn
  an ordinal context into a name.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  TE  = (One, Two, Three);
  TAE = array[0..1] of TE;
  TDE = array of TE;
  TR  = record
          f: TE;
          g: array[0..1] of TE;
          inner: record k: TE; end;
        end;
  TC = class
    fk: TE;
    ka: array[0..1] of TE;
    function Get: TE;
  end;

var
  e: TE; a: array[0..1] of TE; b: TAE; d: TDE; dd: array of array of TE;
  r: TR; c: TC; i: Integer;

const
  K: TE = Two;

function TC.Get: TE;
begin
  Result := Three;
end;

function Mk: TE;
begin
  Mk := Three;
end;

function MkAlias: TDE;
begin
  SetLength(MkAlias, 1);
  MkAlias[0] := One;
end;

procedure ByVar(var v: TE);
begin
  WriteLn('byvar  : ', v);
end;

procedure ByVal(v: TE);
begin
  WriteLn('byval  : ', v);
end;

procedure ByArr(const v: TAE);
begin
  WriteLn('byarr  : ', v[0], ' ', v[1]);
end;

begin
  e := Three;         WriteLn('var    : ', e);

  a[0] := Two; a[1] := One;
  WriteLn('arr    : ', a[0], ' ', a[1]);

  b[0] := Three; b[1] := Two;
  WriteLn('alias  : ', b[0], ' ', b[1]);

  SetLength(d, 2); d[0] := One; d[1] := Three;
  WriteLn('dyn    : ', d[0], ' ', d[1]);

  SetLength(dd, 1); SetLength(dd[0], 2); dd[0][0] := Two; dd[0][1] := Three;
  WriteLn('dyn2   : ', dd[0][0], ' ', dd[0][1]);

  r.f := One; r.g[0] := Two; r.g[1] := Three; r.inner.k := Two;
  WriteLn('field  : ', r.f);
  WriteLn('fldarr : ', r.g[0], ' ', r.g[1]);
  WriteLn('nested : ', r.inner.k);

  c := TC.Create;
  c.fk := Three; c.ka[0] := One; c.ka[1] := Two;
  WriteLn('clsfld : ', c.fk);
  WriteLn('clsarr : ', c.ka[0], ' ', c.ka[1]);
  WriteLn('method : ', c.Get);
  c.Free;

  WriteLn('const  : ', K);
  WriteLn('call   : ', Mk);
  { `MkAlias[0]` — indexing an array-returning call directly is refused today
    (compat-pascal-index-a-function-call-result), so the array-alias RESULT is
    asserted through a variable instead. The point being asserted is that the
    call's result does NOT claim its element's enum identity. }
  d := MkAlias;
  WriteLn('callarr: ', d[0]);

  e := Two; ByVar(e); ByVal(e); ByArr(a);

  WriteLn('succ   : ', Succ(One), ' ', Pred(Three));
  e := One;
  WriteLn('succvar: ', Succ(e), ' ', Succ(Succ(e)));

  i := 2;
  WriteLn('cast   : ', TE(i), ' ', TE(0));

  { the ordinal contexts must stay numeric }
  WriteLn('ord    : ', Ord(a[0]), ' ', Ord(r.f), ' ', Ord(Mk), ' ', Ord(K));
  for e := One to Three do Write(e, ' ');
  WriteLn;
  WriteLn('width  : [', a[0]:8, '][', r.f:8, ']');
end.
