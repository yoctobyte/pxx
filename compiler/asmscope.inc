{ SPDX-License-Identifier: MPL-2.0 }
{ asmscope.inc -- scope labels shared by EmitAsmX64 (asmtext.inc) and EmitAsm386
  (asmtext_386.inc). Needs Code, CodeLen, Patch32, CheckRel8 (rel8.inc), Error and
  AsmTextCharAt; split out so the i386 harness can include it without the x64
  encoder. }

{ ---- scope labels ------------------------------------------------------------

  A `.name` label belongs to the one EmitAsmX64 call that writes it. That is
  enough for a self-contained blob and not for the shape most raw-byte codegen
  has: a jump in one call, then Pascal that decides what comes next (an
  EmitCallProc, a MovRaxImm, an `if`), then the target in a later call. Raw code
  spelled that with a `p := CodeLen; EmitI32(0)` placeholder and a Patch32 at
  the target -- the bookkeeping that the text assembler exists to delete.

  So a label WITHOUT the leading dot is a SCOPE label: it lives from
  AsmScopeBegin to the matching AsmScopeEnd, across any number of calls and any
  Pascal in between, and AsmScopeEnd resolves every jump to it (an undefined
  one is a compile error there, as is defining a name twice in one scope).
  Scopes nest: a helper that opens its own scope sees only its own labels, so
  it cannot collide with -- or jump into -- its caller's. With no scope open a
  dotless name behaves exactly as it always did, local to its call. }
const
  ASM_SCOPE_MAX_LABELS = 256;
  ASM_SCOPE_MAX_DEPTH = 8;
var
  AsmSLblName: array[0..ASM_SCOPE_MAX_LABELS - 1] of AnsiString;
  AsmSLblPos:  array[0..ASM_SCOPE_MAX_LABELS - 1] of Integer;
  AsmSLblCount: Integer;
  AsmSFwName:  array[0..ASM_SCOPE_MAX_LABELS - 1] of AnsiString;
  AsmSFwPatch: array[0..ASM_SCOPE_MAX_LABELS - 1] of Integer;
  AsmSFwShort: array[0..ASM_SCOPE_MAX_LABELS - 1] of Boolean;
  AsmSFwCount: Integer;
  AsmScopeLblBase: array[0..ASM_SCOPE_MAX_DEPTH - 1] of Integer;
  AsmScopeFwBase:  array[0..ASM_SCOPE_MAX_DEPTH - 1] of Integer;
  AsmScopeDepth: Integer;

procedure AsmScopeBegin;
begin
  if AsmScopeDepth >= ASM_SCOPE_MAX_DEPTH then Error('asm: scopes nested too deep');
  AsmScopeLblBase[AsmScopeDepth] := AsmSLblCount;
  AsmScopeFwBase[AsmScopeDepth] := AsmSFwCount;
  Inc(AsmScopeDepth);
end;

{ Fill one forward jump: rel32 at `patch`, or for a `short` jump the rel8 byte
  there. Both are measured from the end of the displacement field. }
procedure AsmPatchFw(patch, target: Integer; isShort: Boolean);
var d: Integer;
begin
  if isShort then
  begin
    d := target - (patch + 1);
    CheckRel8(d, 'asm short forward jump');
    Code[patch] := Byte(d);
  end
  else
    Patch32(patch, target - (patch + 4));
end;

function AsmScopeFind(const nm: AnsiString; var pos: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  for k := AsmScopeLblBase[AsmScopeDepth - 1] to AsmSLblCount - 1 do
    if AsmSLblName[k] = nm then
    begin
      pos := AsmSLblPos[k];
      Result := True;
      Exit;
    end;
end;

procedure AsmScopeEnd;
var k, pos: Integer;
begin
  if AsmScopeDepth <= 0 then Error('asm: AsmScopeEnd without AsmScopeBegin');
  for k := AsmScopeFwBase[AsmScopeDepth - 1] to AsmSFwCount - 1 do
  begin
    pos := 0;
    if not AsmScopeFind(AsmSFwName[k], pos) then
      Error('asm: jump to undefined scope label ' + AsmSFwName[k]);
    AsmPatchFw(AsmSFwPatch[k], pos, AsmSFwShort[k]);
  end;
  Dec(AsmScopeDepth);
  AsmSLblCount := AsmScopeLblBase[AsmScopeDepth];
  AsmSFwCount := AsmScopeFwBase[AsmScopeDepth];
end;

{ Is `nm` a scope label here? Dotless, and a scope is open. }
function AsmIsScopeLabel(const nm: AnsiString): Boolean;
begin
  { AsmTextCharAt, not nm[1]: PXX evaluates `and` in full, and indexing an
    empty AnsiString reads through nil (see the landmine note in the ticket) }
  Result := (AsmScopeDepth > 0) and (Length(nm) > 0) and (AsmTextCharAt(nm, 1) <> '.');
end;

