{ Record constants whose value is itself an AGGREGATE — a record-typed field, an
  array-of-record field, and both at once — for a const and for a var, global
  and routine-local.

  All of these used to answer `not a constant`, pointing at the first field name
  INSIDE the inner parentheses: a pending init recorded its target as ONE field
  span, so there was nowhere to put the second. The parser said as much at the
  head of the routine — "Nested record/array fields are not handled yet" — and
  the array half of that sentence was implemented later (TGuid's D4) while the
  record half was not.

  The target is a PATH now, so the depth below is the data's rather than the
  emitter's; `deep` walks three levels to prove it is not an F2Off/F2Len pair
  with `a.b.c.d` still waiting for someone to add F3.

  Rows that are NOT about nesting and must not regress:
    guid  — TGuid's own shape, the array-valued field this arm was built for.
    lo    — an array-valued field with a NON-ZERO low bound. Elements used to be
            numbered from 0 regardless, so `array[1..3]` wrote one element
            BEFORE the field, silently over its neighbour. `g0` is that
            neighbour and is checked first.
    loc   — the routine-LOCAL spellings, which were refused BY NAME while the
            identical global compiled: once for the nesting, once more for a
            string field (the local table's field-name length and its string
            length were the same slot).

  bug-p-typed-constants-cannot-hold-a-pointer-a-nested-aggregate-or-storage }
program test_nested_record_constant;

type
  TPt   = record x, y: Integer; end;
  TMid  = record q: TPt; lbl: string; end;
  TDeep = record m: TMid; n: Integer; nm: PChar; end;
  TSub  = record x, y: Integer; end;
  TR    = record g0: Integer; a: array[1..3] of TSub; g1: Integer; end;
  TG    = record d1: LongWord; d4: array[0..7] of Byte; end;
  TOut  = record k: Integer; sub: TPt; end;
  TAOR  = array[0..1] of TOut;
  TNest = record p: TPt; tag: string; n: array[0..2] of Integer; end;

const
  DP: TDeep = (m: (q: (x: 11; y: 22); lbl: 'deep'); n: 3; nm: 'ptr');
  CN: TNest = (p: (x: 1; y: 2); tag: 'k'; n: (7, 8, 9));
  CR: TR    = (g0: 7; a: ((x: 1; y: 2), (x: 3; y: 4), (x: 5; y: 6)); g1: 8);
  GG: TG    = (d1: $11223344; d4: ($C0, 1, 2, 3, 4, 5, 6, $46));
  AO: TAOR  = ((k: 1; sub: (x: 10; y: 20)), (k: 2; sub: (x: 30; y: 40)));

var
  VR: TMid = (q: (x: 5; y: 6); lbl: 'gvar');

procedure Loc;
var
  LR: TMid = (q: (x: 1; y: 2); lbl: 'loc');
begin
  WriteLn('loc   : ', LR.q.x, ' ', LR.q.y, ' ', LR.lbl);
end;

begin
  WriteLn('deep  : ', DP.m.q.x, ' ', DP.m.q.y, ' ', DP.m.lbl, ' ', DP.n, ' ', DP.nm);
  WriteLn('nest  : ', CN.p.x, ' ', CN.p.y, ' ', CN.tag, ' ', CN.n[0], ' ', CN.n[2]);
  WriteLn('lo    : ', CR.g0, ' ', CR.a[1].x, ' ', CR.a[2].y, ' ', CR.a[3].y, ' ', CR.g1);
  WriteLn('guid  : ', GG.d1, ' ', GG.d4[0], ' ', GG.d4[7]);
  WriteLn('aor   : ', AO[0].k, ' ', AO[0].sub.x, ' ', AO[1].k, ' ', AO[1].sub.y);
  WriteLn('gvar  : ', VR.q.x, ' ', VR.q.y, ' ', VR.lbl);
  Loc;
end.
