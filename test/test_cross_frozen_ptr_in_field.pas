program test_cross_frozen_ptr_in_field;

{ A frozen string reached through a POINTER HELD IN A RECORD FIELD, compared
  against a literal. On wasm32 every such row answered FALSE while the same
  expression PRINTED the string correctly: WasmEmitLoadMem's frozen arm returned
  the address it was given instead of loading through it, so the compare was
  handed `@r.NamePtr` where it wanted `r.NamePtr` -- the pointer value read as
  the length, the bytes after it as the characters.

  THE ROWS THAT ALREADY WORKED ARE HALF THE TEST, and they are what a careless
  fix breaks. `q^` through a plain pointer VARIABLE was always correct and an
  "always take the address" change breaks it; a plain `string[N]` FIELD and a
  plain ARRAY ELEMENT were always correct and an "always load" change breaks
  them. All three are asserted here beside the three that were broken, so the
  file fails in both directions.

  The three broken shapes are the field, the field through a record POINTER,
  and the field of an ARRAY ELEMENT -- every route whose pointer comes out of a
  field. The boundary was the field, not the index and not the deref.

  CAP 256 IS DELIBERATE. It makes these `tyString`, the 8-byte-prefix layout
  that lib/rtl/typinfo.pas's TRttiStr uses on purpose, which is the shape whose
  failure made GetClass return nil on wasm32. The narrow layout -- string[N] for
  N <= 255, tyShortString -- is a DIFFERENT and still-open defect: it answers
  FALSE for these same three shapes on EVERY target, because the deref loses the
  shortstring kind. Asserting it here would assert a wrong value as expected;
  see bug-a-a-pointer-deref-loses-the-shortstring-kind-on-every-target. }

type
  S = string[256];
  P = ^S;
  TEnt = record NamePtr: P; s: S; end;

var
  n: S;
  r: TEnt;
  q: P;
  pr: ^TEnt;
  ents: array[0..1] of TEnt;
  arr: array[0..2] of S;
  ok: Boolean;

begin
  n := 'A';
  r.NamePtr := @n;
  r.s := 'A';
  q := r.NamePtr;
  pr := @r;
  ents[1].NamePtr := @n;
  arr[1] := 'A';

  { the three that always worked -- a fix must not break them }
  ok := (q^ = 'A') and (r.s = 'A') and (arr[1] = 'A');
  if not ok then WriteLn('  a control row failed: q^ ', q^ = 'A',
                         ' r.s ', r.s = 'A', ' arr ', arr[1] = 'A');

  { the three the pointer-in-a-field defect broke }
  ok := ok and (r.NamePtr^ = 'A') and (pr^.NamePtr^ = 'A')
           and (ents[1].NamePtr^ = 'A');

  { and the write path, which dereferenced correctly throughout and is what
    made the defect silent: the string PRINTED right and COMPARED wrong. }
  WriteLn('printed ', r.NamePtr^);
  if ok then WriteLn('FROZENPTRFIELD OK') else WriteLn('FROZENPTRFIELD FAIL');
end.
