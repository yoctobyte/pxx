program test_rel8_guard;
{ The rel8 range check must REFUSE what it cannot encode — proved, not asserted.

  bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows

  This harness mocks the byte sink and then {$include}s the REAL shipped
  compiler/rel8.inc, the way test_asm_emit_*.pas include the real encoders. It
  exists because a guard nobody has watched fire is the failure mode this repo
  keeps meeting: bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-
  cannot-fire is an invariant whose declared check matched nothing on any tree,
  forever, and reported clean. A range check that is never exercised is the same
  object with a different spelling.

  So the assertions here are two-sided on purpose. Proving the guard REJECTS 181
  is worth little on its own — a check that rejects everything would pass that.
  Every boundary is therefore pinned from both directions: +127 accepted and
  +128 refused, -128 accepted and -129 refused. A whitelist can fail in two
  directions and only one of them looks like a bug.

  181 is not an arbitrary out-of-range number. It is the measured one: growing
  EmitSyscall put a `jns` 181 bytes from its target, `Byte(181)` was stored and
  decoded as -75, and the program faulted at a mid-instruction address. 181-256
  = -75 exactly. That case is asserted by value below.

  WHY rel8.inc IS ITS OWN FILE: this harness needs five mocks. Including
  emit.inc, where these routines used to live, would need about thirty — and
  test_asm_emit_rv32.pas rotted three times on exactly that, most recently the
  morning of 2026-08-30 when the encoder grew an AIntToStr call its mock
  environment did not have. }

uses SysUtils;

const
  MAX_CODE = 65536;

var
  { --- mocked byte sink --- }
  Code: array[0..MAX_CODE-1] of Byte;
  CodeLen: Integer = 0;
  { --- mocked diagnostic: RECORDS instead of halting, so the test can assert
        that a refusal happened and then keep running --- }
  ErrCount: Integer = 0;
  LastErr: AnsiString = '';

procedure EmitB(b: Byte);
begin
  Code[CodeLen] := b;
  Inc(CodeLen);
end;

procedure Error(const msg: AnsiString);
begin
  Inc(ErrCount);
  LastErr := msg;
end;

function AIntToStr(n: Integer): AnsiString;
begin
  Result := IntToStr(n);
end;

{$include ../compiler/rel8.inc}

var
  failures: Integer = 0;
  checks: Integer = 0;

{ Drive PatchRel8 with a chosen forward span: place the placeholder, advance
  CodeLen to put the target `span` bytes ahead, then patch. }
procedure ExpectForward(span: Integer; wantRefused: Boolean; const nm: AnsiString);
var patchPos, before: Integer;
begin
  Inc(checks);
  CodeLen := 0;
  patchPos := CodeLen;
  EmitB(0);                       { the placeholder byte }
  CodeLen := patchPos + 1 + span; { target is `span` bytes past the placeholder }
  before := ErrCount;
  PatchRel8(patchPos);
  if wantRefused and (ErrCount = before) then
  begin
    writeln('NOT REFUSED: ', nm, ' span=', span);
    Inc(failures);
  end
  else if (not wantRefused) and (ErrCount <> before) then
  begin
    writeln('WRONGLY REFUSED: ', nm, ' span=', span, ' -> ', LastErr);
    Inc(failures);
  end;
end;

{ Drive EmitRel8 with a chosen backward span. }
procedure ExpectBack(span: Integer; wantRefused: Boolean; const nm: AnsiString);
var target, before: Integer;
begin
  Inc(checks);
  CodeLen := 40000;
  target := CodeLen + 1 + span;   { span is the displacement the CPU will see }
  before := ErrCount;
  EmitRel8(target);
  if wantRefused and (ErrCount = before) then
  begin
    writeln('NOT REFUSED: ', nm, ' span=', span);
    Inc(failures);
  end
  else if (not wantRefused) and (ErrCount <> before) then
  begin
    writeln('WRONGLY REFUSED: ', nm, ' span=', span, ' -> ', LastErr);
    Inc(failures);
  end;
end;

var stored: Integer;
begin
  { THE MEASURED CASE. 181 is what actually shipped a backwards jump. }
  ExpectForward(181, True, 'the measured jns span');

  { Both sides of both boundaries — a check that refused everything would pass
    the refusal half alone, so the acceptances are the half that gives it
    meaning. }
  ExpectForward(127, False, 'largest encodable forward');
  ExpectForward(128, True,  'one past the forward limit');
  ExpectForward(0,   False, 'zero span');
  ExpectForward(1,   False, 'minimal forward');

  ExpectBack(-128, False, 'largest encodable back edge');
  ExpectBack(-129, True,  'one past the back-edge limit');
  ExpectBack(-1,   False, 'minimal back edge');
  ExpectBack(127,  False, 'forward via EmitRel8');
  ExpectBack(128,  True,  'one past the limit via EmitRel8');

  { An IN-RANGE displacement must store exactly what the old raw expression
    stored — the conversion is only safe if the accepted path is unchanged. }
  Inc(checks);
  CodeLen := 0;
  EmitB(0);
  CodeLen := 1 + 100;
  PatchRel8(0);
  stored := Code[0];
  if stored <> 100 then
  begin
    writeln('WRONG BYTE for span 100: ', stored);
    Inc(failures);
  end;

  { And the negative one, where two's complement is what the field wants: -5
    must land as $FB, not be rejected as "negative". }
  Inc(checks);
  CodeLen := 40000;
  EmitRel8(CodeLen + 1 - 5);
  stored := Code[40000];
  if stored <> 251 then
  begin
    writeln('WRONG BYTE for back edge -5: ', stored, ' (want 251 = $FB)');
    Inc(failures);
  end;

  { The arithmetic that made this bug invisible: 181 truncated and read back as
    a signed byte is -75. Asserted so the ticket's central number is executable
    rather than prose. }
  Inc(checks);
  if Integer(Shortint(Byte(181))) <> -75 then
  begin
    writeln('the 181 -> -75 arithmetic does not hold on this host');
    Inc(failures);
  end;

  if failures = 0 then
    writeln('REL8-GUARD OK checks=', checks)
  else
    writeln('REL8-GUARD FAILURES=', failures);
end.
