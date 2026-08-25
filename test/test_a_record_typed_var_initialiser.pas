program test_a_record_typed_var_initialiser;
{ `var R: TRec = (n: 7; s: 'seven')` was refused with *"parenthesised
  initializer requires an array variable"* — a diagnostic that names its own
  gap. The var path had learned parenthesised initialisers for ARRAYS only; the
  record arm was never wired up beside it, while the identical CONST declaration
  had worked for as long as records have.

  FPC treats a var initialiser as a writable typed const, so this was a routing
  gap and not new machinery. Fixing it turned up that the record-field loop had
  been hand-written THREE times — the scalar const arm, the array-of-record
  const arm, and (absent) the var arm. Three mechanisms for one concept is what
  root-cause-over-microfix.md calls a design flaw rather than a smell, so they
  are one routine now (ParseRecordInitializerInto) with the element index as a
  parameter, and the var side is two calls to it rather than a fourth copy.

  The CONST rows are here for that reason: the fix rewrote the path they take,
  so they are as much at risk as the rows it adds.

  KNOWN LIMITATION, inherited from the local typed-const channel and unchanged
  here: a LOCAL record initialiser with a STRING field is refused
  ("record constant with string fields must be global") because a local init
  slot has no ValAux and its FLen is already spoken for by the field-name span.
  It is loud, so the local row below uses an all-ordinal record.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}{$H+}

type
  TP    = record x, y: Integer; end;
  TRec  = record n: Integer; s: AnsiString; end;
  TArr  = array[0..1] of TRec;
  TPArr = array[0..2] of TP;

var
  { the shape the ticket is about }
  R: TRec = (n: 7; s: 'seven');
  { …and its array form, which reached "not a constant" once the scalar one
    parsed: the element's `(` was read as another DIMENSION }
  A: TArr  = ((n: 1; s: 'a'), (n: 2; s: 'b'));
  P: TPArr = ((x: 1; y: 2), (x: 3; y: 4), (x: 5; y: 6));
  { a record var with NO initialiser must still be zeroed }
  Z: TRec;

const
  { the const spellings, which already worked and now take the shared routine }
  CR: TRec  = (n: 70; s: 'const');
  CA: TArr  = ((n: 10; s: 'ca'), (n: 20; s: 'cb'));

procedure Loc;
var
  L: TP = (x: 9; y: 8);
  LC: TP = (x: 1; y: 1);
begin
  WriteLn('local   : ', L.x, ' ', L.y, ' ', LC.x + LC.y);
end;

begin
  WriteLn('varrec  : ', R.n, ' ', R.s);
  WriteLn('vararr  : ', A[0].n, ' ', A[0].s, ' ', A[1].n, ' ', A[1].s);
  WriteLn('varords : ', P[0].x, ' ', P[0].y, ' ', P[1].x, ' ', P[1].y, ' ', P[2].x, ' ', P[2].y);
  WriteLn('zeroed  : ', Z.n, ' [', Z.s, ']');
  WriteLn('constrec: ', CR.n, ' ', CR.s);
  WriteLn('constarr: ', CA[0].n, ' ', CA[0].s, ' ', CA[1].n, ' ', CA[1].s);
  Loc;
  { an initialised var is WRITABLE — that is the whole difference from a const }
  R.n := 99; R.s := 'written';
  A[1].n := 42;
  WriteLn('written : ', R.n, ' ', R.s, ' ', A[1].n);
end.
