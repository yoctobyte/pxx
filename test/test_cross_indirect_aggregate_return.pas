program test_cross_indirect_aggregate_return;
{ A function returning a RECORD, called three ways: directly, through a
  procedural variable, and virtually.

  All three use the caller-owned hidden destination -- the caller allocates the
  result and the callee fills it -- and the three differ only in where the
  callee's identity comes from. That is exactly why a direct-call-only test
  proves so little here: the convention is shared, the plumbing is not, and on
  wasm32 the direct arm worked while both indirect arms refused to compile at
  all (`the hidden-destination ABI is not chosen for this target yet`) until
  2026-09-04.

  THE OVERRIDE ROW IS THE ONE THAT CAN FAIL. `virt der` goes through a TDeriv
  in a TBase variable and its numbers are a different SHAPE from the base's
  (k*10+n against k+n), so a wrong VMT slot, a wrong signature or a destination
  threaded to the wrong call still produces a plausible five-integer row -- and
  it produces the BASE's row, which the line above already shows. Two rows that
  differ only in value would not separate those; two rows that differ in shape
  do.

  Every field of the record is read back, not just the first: a hidden
  destination handed over half-formed, or a result copied at the wrong width,
  leaves the later fields wrong while `r.a` still reads correctly.

  Compared against the x86-64 build of this same source. }
type
  TR = record a, b, c, d, e: Integer; end;
  TMakeR = function(k: Integer): TR;

  TBase = class
    function Make(k: Integer): TR; virtual;
  end;
  TDeriv = class(TBase)
    function Make(k: Integer): TR; override;
  end;

function TBase.Make(k: Integer): TR;
begin
  Make.a := k; Make.b := k + 1; Make.c := k + 2; Make.d := k + 3; Make.e := k + 4;
end;

function TDeriv.Make(k: Integer): TR;
begin
  Make.a := k * 10; Make.b := k * 10 + 1; Make.c := k * 10 + 2;
  Make.d := k * 10 + 3; Make.e := k * 10 + 4;
end;

function Plain(k: Integer): TR;
begin
  Plain.a := k; Plain.b := k * 2; Plain.c := k * 3; Plain.d := k * 4; Plain.e := k * 5;
end;

procedure Show(const tag: ShortString; const r: TR);
begin
  writeln(tag, ' ', r.a, ' ', r.b, ' ', r.c, ' ', r.d, ' ', r.e);
end;

var
  fp: TMakeR; r: TR; b: TBase; d: TDeriv;
begin
  r := Plain(3);        Show('direct   ', r);
  fp := @Plain;
  r := fp(4);           Show('procvar  ', r);

  b := TBase.Create;
  d := TDeriv.Create;
  r := b.Make(5);       Show('virt base', r);
  b := d;
  r := b.Make(6);       Show('virt der ', r);

  { The result consumed WITHOUT a named destination of its own: a field of a
    temporary. A different consumer from the assignment above, and the one that
    reads the hidden destination straight back rather than copying out of it.

    `fp(7).c` was NOT here for a day, and its absence was a finding: the
    procedural-variable spelling was rejected with `expected ')' before '.'`
    while the direct and virtual spellings on the same line worked.
    bug-p-member-access-on-a-procedural-variable-call-result-is-rejected, closed
    2026-09-04, and the row is now in -- which makes this line the guard for
    all THREE call kinds rather than two of them.

    `fp(7).c` is 21 (7*3) and NOT 7: the field must be read at its own offset,
    not at offset 0. That distinction is the whole point of picking `.c` here --
    the signature row carried no return-record id, so the field resolved against
    REC_NONE and landed at offset 0, and a `.a` row would have printed the right
    answer for the wrong reason and passed. }
  writeln('field    ', Plain(8).e, ' ', b.Make(9).a, ' ', fp(7).c);
  writeln('done');
end.
