{ A by-value RECORD parameter, through a DIRECT, a VIRTUAL and an INDIRECT call,
  on the internal (Pascal) convention.

  i386 refused this until 2026-09-02, and the refusal was CORRECT rather than a
  missing feature: `ir_codegen.inc` supported a by-value record for cdecl only,
  because Pascal passes a record of 8 bytes or less by value (IsRef stays False)
  while the internal i386 CALLER still pushed its ADDRESS. Lifting the check
  alone would have made the callee read bytes where the caller pushed a pointer
  -- silently, on every small record. The work was the caller half; the check
  went last.
  feature-a-i386-refuses-a-by-value-record-parameter-on-the-internal-convention-so-lib-rtl-image-does-not-build

  WHY THE THREE CALL SHAPES ARE ALL HERE. i386 marshals arguments in three
  separate ladders -- the direct IR_CALL's hand-rolled one, IR_VIRTUAL_CALL's
  and IR_CALL_IND's, the last two via Arg32Class. The by-value SET case had
  already been added to one of them and not the others, and that is exactly how
  it was found: `pS(1, [eA,eC,eD], 9)` through a proc-var pushed a single
  address word and answered 838829819 instead of 139. A record arm added to one
  ladder is the same bug waiting.

  WHY THE SIZES. The convention switches at 8 bytes -- above that the frontend
  marks the parameter by-reference, so R4 and R8 exercise the by-value push and
  R12/R16 exercise the by-ref path they fall back to. Both must be right, and
  which one a given size takes is the compiler's business, not this test's: it
  asserts the VALUES, so either decision is fine as long as the two halves agree.

  WHY EACH RECORD IS FOLLOWED BY AN INT. A record occupying the wrong number of
  argument slots shifts every parameter after it, and the shift is silent if
  nothing comes after. `tail` is that witness in every row.

  x86-64 is the oracle; the point of the file is that the five cross targets
  agree with it. }
program test_byvalue_record_param_every_call_shape;

type
  TR4  = record a: Integer; end;
  TR8  = record a, b: Integer; end;
  TR12 = record a, b, c: Integer; end;
  TR16 = record a, b, c, d: Integer; end;

  TTaker = class
    function Take4(lead: Integer; r: TR4; tail: Integer): Integer; virtual;
    function Take8(lead: Integer; r: TR8; tail: Integer): Integer; virtual;
    function Take12(lead: Integer; r: TR12; tail: Integer): Integer; virtual;
    function Take16(lead: Integer; r: TR16; tail: Integer): Integer; virtual;
  end;

  TShifted = class(TTaker)
    function Take8(lead: Integer; r: TR8; tail: Integer): Integer; override;
  end;

  TFn4  = function(lead: Integer; r: TR4; tail: Integer): Integer;
  TFn8  = function(lead: Integer; r: TR8; tail: Integer): Integer;
  TFn12 = function(lead: Integer; r: TR12; tail: Integer): Integer;
  TFn16 = function(lead: Integer; r: TR16; tail: Integer): Integer;

var
  fail: Integer;

procedure Check(got, want: Integer; const what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fail := fail + 1;
  end;
end;

{ ---- free functions: the DIRECT and INDIRECT rows ---- }
function F4(lead: Integer; r: TR4; tail: Integer): Integer;
begin F4 := lead * 1000 + r.a * 10 + tail; end;

function F8(lead: Integer; r: TR8; tail: Integer): Integer;
begin F8 := lead * 1000 + (r.a + r.b) * 10 + tail; end;

function F12(lead: Integer; r: TR12; tail: Integer): Integer;
begin F12 := lead * 1000 + (r.a + r.b + r.c) * 10 + tail; end;

function F16(lead: Integer; r: TR16; tail: Integer): Integer;
begin F16 := lead * 1000 + (r.a + r.b + r.c + r.d) * 10 + tail; end;

{ A by-value record must be a COPY: writing through it cannot reach the caller.
  This is the half a pointer-passing caller gets wrong in the other direction --
  it would compile and give the right READ while silently aliasing. }
function Mutate(r: TR8): Integer;
begin
  r.a := 999;
  r.b := 999;
  Mutate := r.a + r.b;
end;

{ ---- methods: the VIRTUAL rows ---- }
function TTaker.Take4(lead: Integer; r: TR4; tail: Integer): Integer;
begin Take4 := lead * 1000 + r.a * 10 + tail; end;

function TTaker.Take8(lead: Integer; r: TR8; tail: Integer): Integer;
begin Take8 := lead * 1000 + (r.a + r.b) * 10 + tail; end;

function TTaker.Take12(lead: Integer; r: TR12; tail: Integer): Integer;
begin Take12 := lead * 1000 + (r.a + r.b + r.c) * 10 + tail; end;

function TTaker.Take16(lead: Integer; r: TR16; tail: Integer): Integer;
begin Take16 := lead * 1000 + (r.a + r.b + r.c + r.d) * 10 + tail; end;

function TShifted.Take8(lead: Integer; r: TR8; tail: Integer): Integer;
begin Take8 := lead * 1000 + (r.a + r.b) * 100 + tail; end;

{ CONTROL: `const` makes the same record by-REFERENCE, which every backend has
  always handled. A run where these fail too is a broken build rather than this
  bug. }
function C8(lead: Integer; const r: TR8; tail: Integer): Integer;
begin C8 := lead * 1000 + (r.a + r.b) * 10 + tail; end;

var
  { pf4, not f4. Pascal is CASE-INSENSITIVE, so a variable `f4` and the function
    `F4` are ONE identifier -- FPC rejects that outright ("Duplicate identifier
    F"), and pxx accepts it and resolves the call to the uninitialised variable,
    which dies as `Runtime error 216 (nil reference)` a long way from the
    declaration. Cost a real detour here; the `p` prefix is not decoration. }
  r4: TR4; r8: TR8; r12: TR12; r16: TR16;
  t: TTaker; sh: TShifted;
  pf4: TFn4; pf8: TFn8; pf12: TFn12; pf16: TFn16;
begin
  fail := 0;
  r4.a := 1;
  r8.a := 1;  r8.b := 2;
  r12.a := 1; r12.b := 2; r12.c := 3;
  r16.a := 1; r16.b := 2; r16.c := 3; r16.d := 4;

  { DIRECT }
  Check(F4(7, r4, 5),   7015, 'direct, 4-byte record');
  Check(F8(7, r8, 5),   7035, 'direct, 8-byte record');
  Check(F12(7, r12, 5), 7065, 'direct, 12-byte record');
  Check(F16(7, r16, 5), 7105, 'direct, 16-byte record');

  { VIRTUAL, base }
  t := TTaker.Create;
  Check(t.Take4(7, r4, 5),   7015, 'virtual, 4-byte record');
  Check(t.Take8(7, r8, 5),   7035, 'virtual, 8-byte record');
  Check(t.Take12(7, r12, 5), 7065, 'virtual, 12-byte record');
  Check(t.Take16(7, r16, 5), 7105, 'virtual, 16-byte record');

  { VIRTUAL, reaching the override through a base-typed variable — the row that
    actually needs the VMT rather than a static bind. }
  sh := TShifted.Create;
  t := sh;
  Check(t.Take8(7, r8, 5), 7305, 'virtual, 8-byte record, reaches the override');

  { INDIRECT }
  pf4 := @F4;   Check(pf4(7, r4, 5),   7015, 'indirect, 4-byte record');
  pf8 := @F8;   Check(pf8(7, r8, 5),   7035, 'indirect, 8-byte record');
  pf12 := @F12; Check(pf12(7, r12, 5), 7065, 'indirect, 12-byte record');
  pf16 := @F16; Check(pf16(7, r16, 5), 7105, 'indirect, 16-byte record');

  { BY VALUE MEANS A COPY }
  Check(Mutate(r8), 1998, 'callee sees its own copy');
  Check(r8.a, 1, 'caller''s record survives the callee writing to it (a)');
  Check(r8.b, 2, 'caller''s record survives the callee writing to it (b)');

  { CONTROL: by-reference, which always worked }
  Check(C8(7, r8, 5), 7035, 'CONTROL: const (by-ref) record');

  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('BYVALRECPARAM OK') else WriteLn('BYVALRECPARAM FAILED');
end.
