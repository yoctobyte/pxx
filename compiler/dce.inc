{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Reachability-gated dead-code elimination ==============================

  `writeln('hello')` emitted 113 routines and 58 KB of code, of which the
  program can reach a handful: a `uses` pulls in a whole unit body, so every
  program pays for the float writer, the variant engine, the dynamic-array
  runtime and the record RTTI helpers whether or not it ever mentions a real, a
  variant, a dynamic array or a record. This pass drops the bodies nothing can
  reach.

  WHY IT IS A POST-PASS AND NOT LAZY EMISSION. The compiler emits a routine's
  code the moment it parses it -- `Procs[i].BodyAddr := CodeLen` sits at the
  prologue -- so at the point where you would want to decide "skip this body"
  nothing yet knows who calls it. The alternative (buffer every unit body's
  tokens and compile on demand, the way generics are instantiated) means
  replaying parser state per routine, per frontend. Compacting afterwards is one
  language-agnostic pass over tables that already exist.

  WHAT MAKES IT SAFE. Moving a body invalidates every PC-relative reference that
  crosses the gap, and a stale rel32 does not crash -- it calls into the middle
  of whatever slid up into the hole. So the pass runs only when every such
  reference is enumerable, and the compiler was changed to make them so:

    * EmitCallProc records EVERY internal direct call in CallFix, not just the
      forward ones it used to (RecordInternalCall). That table is BOTH the call
      graph this pass walks and the set of call sites it re-patches.
    * IREmitCodeCall and the program entry's jump record a CodeRef -- the
      references that name a code OFFSET rather than a proc (the ~50 runtime
      stubs). RecordCodeRef, in emit.inc.
    * Everything else that is PC-relative is INTRA-body (IR labels, loop and
      goto fixups, exception landing pads, inline-asm locals). A body moves as a
      unit, so those distances are preserved untouched.
    * @proc addresses (ProcAddrFix) and VMT/RTTI method slots (MethodFixups) are
      absolute and resolved from BodyAddr at write time, so they follow the move
      for free -- and both are ROOTS, because an address that is taken can be
      called from anywhere.

  A range that holds a CodeRef TARGET is never dropped, whoever emitted it. That
  one rule is what keeps this honest against a stub kind nobody remembered to
  list: an unreferenced stub costs its bytes, a wrongly dropped one costs a
  jump into hyperspace.

  The pass REFUSES rather than guesses. Two bodies sharing a start address (the
  C frontend aliases one), a body that never recorded its end, an output mode
  whose writer carries its own code-offset tables (-c, --shared), a target whose
  references are not rel32: all of them turn the pass off and, under
  --dce-report, say why.

  feature-emission-size-dce }

function DceBodyEnd(slot: Integer): Integer;
{ Code[] offset just past the body in DceOrder[slot] -- or its START when the
  body never recorded an end, which reads as "zero bytes I am sure about" and
  makes everything after it look like the always-live gap. Conservative on
  purpose: an unknown extent must not be guessed at. }
var p: Integer;
begin
  p := DceOrder[slot];
  Result := ProcBodyEnd[p];
  if (Result <= Procs[p].BodyAddr) or (Result > DceLimit[slot]) then
    Result := Procs[p].BodyAddr;
end;

function DceOwnerOf(pos: Integer): Integer;
{ The proc whose body holds code offset `pos`, or -1 when `pos` is in none of
  them -- the entry stub, the runtime stubs, the main body. -1 means ALWAYS
  LIVE: a call from there is a root, because that code is never dropped. }
var lo, hi, mid, slot: Integer;
begin
  Result := -1;
  slot := -1;
  lo := 0; hi := DceOrderCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if Procs[DceOrder[mid]].BodyAddr <= pos then
      begin slot := mid; lo := mid + 1; end
    else
      hi := mid - 1;
  end;
  if slot < 0 then Exit;
  if pos < DceBodyEnd(slot) then Result := DceOrder[slot];
end;

procedure DceMark(p: Integer);
begin
  if (p < 0) or (p >= ProcCount) then Exit;
  if DceLive[p] then Exit;
  DceLive[p] := True;
  DceWork[DceWorkCount] := p;
  Inc(DceWorkCount);
end;

function DceAddStubTarget(t: Integer): Boolean;
{ Dedup into DceStubTgt. False = table full, which turns the pass off. }
var i: Integer;
begin
  Result := True;
  i := 0;
  while i < DceStubCount do
  begin
    if DceStubTgt[i] = t then Exit;
    Inc(i);
  end;
  if DceStubCount >= MAX_DCE_STUBS then begin Result := False; Exit; end;
  DceStubTgt[DceStubCount] := t;
  Inc(DceStubCount);
end;

function DceRangeHoldsStub(a, b: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  i := 0;
  while i < DceStubCount do
  begin
    if (DceStubTgt[i] >= a) and (DceStubTgt[i] < b) then begin Result := True; Exit; end;
    Inc(i);
  end;
end;

function DceNewOff(pos: Integer): Integer;
{ Where `pos` lands after the removed ranges are squeezed out. Ranges are
  ascending and disjoint, so this is a subtraction, not a search. }
var i, drop: Integer;
begin
  drop := 0;
  i := 0;
  while (i < DceRemCount) and (DceRemStart[i] < pos) do
  begin
    if pos >= DceRemEnd[i] then drop := drop + (DceRemEnd[i] - DceRemStart[i])
    else drop := drop + (pos - DceRemStart[i]);   { inside a removed range: clamps }
    Inc(i);
  end;
  Result := pos - drop;
end;

function DceIsRemoved(pos: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  i := 0;
  while i < DceRemCount do
  begin
    if (pos >= DceRemStart[i]) and (pos < DceRemEnd[i]) then begin Result := True; Exit; end;
    Inc(i);
  end;
end;

function DceCollectBodies(var why: AnsiString): Boolean;
{ Fill DceOrder (bodied procs, sorted by BodyAddr) and DceLimit (the next body's
  start). False = refuse, with `why` set. }
var i, j, g, t, n: Integer;
begin
  Result := False;
  DceOrderCount := 0;
  i := 0;
  while i < ProcCount do
  begin
    if Procs[i].BodyAddr >= 0 then
    begin
      DceOrder[DceOrderCount] := i;
      Inc(DceOrderCount);
    end;
    Inc(i);
  end;
  n := DceOrderCount;
  { Shell sort by BodyAddr: ProcCount is thousands, and an insertion sort over
    the compiler's own 3038 routines is 4.6M comparisons for no reason. }
  g := 1;
  while g < n div 3 do g := g * 3 + 1;
  while g >= 1 do
  begin
    i := g;
    while i < n do
    begin
      t := DceOrder[i];
      j := i;
      while (j >= g) and (Procs[DceOrder[j - g]].BodyAddr > Procs[t].BodyAddr) do
      begin
        DceOrder[j] := DceOrder[j - g];
        j := j - g;
      end;
      DceOrder[j] := t;
      Inc(i);
    end;
    g := g div 3;
  end;
  { Two routines at one address is the C frontend's bound-method alias. It is
    not hard to support -- both would have to die together -- but supporting it
    blind is how a pass like this gets its first silent miscompile. }
  i := 1;
  while i < n do
  begin
    if Procs[DceOrder[i]].BodyAddr = Procs[DceOrder[i - 1]].BodyAddr then
    begin
      why := 'two routines share one body address (' +
             Procs[DceOrder[i - 1]].Name + ' / ' + Procs[DceOrder[i]].Name + ')';
      Exit;
    end;
    Inc(i);
  end;
  i := 0;
  while i < n do
  begin
    if i + 1 < n then DceLimit[i] := Procs[DceOrder[i + 1]].BodyAddr
    else DceLimit[i] := CodeLen;
    Inc(i);
  end;
  Result := True;
end;

procedure DceReportLine(const s: AnsiString);
begin
  if DceReport then writeln(StdErr, 'dce: ', s);
end;

procedure DceRun;
var i, j, p, owner, a, b, slot, liveN, deadN, liveB, deadB, gotB: Integer;
    why: AnsiString; src, dst: Integer;
begin
  if not DceEnabled then Exit;
  why := '';
  { The reference shapes this pass knows how to re-patch are x86-64's rel32
    call/jmp. Every other target keeps its bodies. }
  if TargetArch <> TARGET_X86_64 then why := 'target is not x86-64'
  else if EmitObjMode or EmitSharedMode then why := '-c / --shared carry their own code-offset relocations'
  else if DebugInfo then why := '-g line/frame tables carry code offsets'
  else if not IsPascalFrontend then
    why := 'only the Pascal frontend is wired up so far'
  else if AsmEntryOff <> 0 then why := 'the .asm frontend overrides the entry point';
  if why <> '' then begin DceReportLine('off: ' + why); Exit; end;

  if not DceCollectBodies(why) then begin DceReportLine('off: ' + why); Exit; end;

  { Every code offset something reaches without naming a proc. }
  DceStubCount := 0;
  i := 0;
  while i < CodeRefCount do
  begin
    if not DceAddStubTarget(CodeRefTarget[i]) then
    begin
      DceReportLine('off: more than MAX_DCE_STUBS distinct stub targets');
      Exit;
    end;
    Inc(i);
  end;

  { The two graph tables are sized to THIS image's call sites, not to a cap --
    they are the only place the pass allocates anything big. }
  SetLength(DceCallOwner, CallFixCount + 1);
  SetLength(DceEdgeTo, CallFixCount + 1);

  { --- roots ------------------------------------------------------------- }
  i := 0;
  while i < ProcCount do begin DceLive[i] := False; Inc(i); end;
  DceWorkCount := 0;
  { an address in a VMT / RTTI / interface table can be called from anywhere }
  i := 0;
  while i < MethodFixCount do begin DceMark(MethodFixups[i].ProcIdx); Inc(i); end;
  { @proc: same argument }
  i := 0;
  while i < ProcAddrFixCount do begin DceMark(ProcAddrFix[i].ProcIdx); Inc(i); end;
  i := 0;
  while i < IramCallFixCount do begin DceMark(IramCallFix[i].ProcIdx); Inc(i); end;
  i := 0;
  while i < InitProcCount do begin DceMark(InitProcs[i]); Inc(i); end;
  i := 0;
  while i < FiniProcCount do begin DceMark(FiniProcs[i]); Inc(i); end;
  DceMark(FiniRunnerProc);
  { a call from code that is never dropped -- the entry stub, the runtime stubs,
    the main body -- is a root by definition }
  i := 0;
  while i < CallFixCount do
  begin
    owner := DceOwnerOf(CallFix[i].CodePos);
    DceCallOwner[i] := owner;
    if owner < 0 then DceMark(CallFix[i].ProcIdx);
    Inc(i);
  end;

  { --- edges: counting-sort CallFix by owning proc ------------------------ }
  i := 0;
  while i <= ProcCount do begin DceEdgeHead[i] := 0; Inc(i); end;
  i := 0;
  while i < CallFixCount do
  begin
    if DceCallOwner[i] >= 0 then
      DceEdgeHead[DceCallOwner[i]] := DceEdgeHead[DceCallOwner[i]] + 1;
    Inc(i);
  end;
  a := 0;
  i := 0;
  while i <= ProcCount do
  begin
    b := DceEdgeHead[i];
    DceEdgeHead[i] := a;
    a := a + b;
    Inc(i);
  end;
  i := 0;
  while i < CallFixCount do
  begin
    owner := DceCallOwner[i];
    if owner >= 0 then
    begin
      DceEdgeTo[DceEdgeHead[owner]] := CallFix[i].ProcIdx;
      DceEdgeHead[owner] := DceEdgeHead[owner] + 1;
    end;
    Inc(i);
  end;
  { DceEdgeHead[p] now points PAST p's edges, i.e. it is p's end and
    DceEdgeHead[p-1] is its start -- the standard counting-sort shift, read
    backwards instead of shifting the array. }

  { --- reachability ------------------------------------------------------- }
  while DceWorkCount > 0 do
  begin
    Dec(DceWorkCount);
    p := DceWork[DceWorkCount];
    if p = 0 then a := 0 else a := DceEdgeHead[p - 1];
    b := DceEdgeHead[p];
    i := a;
    while i < b do begin DceMark(DceEdgeTo[i]); Inc(i); end;
  end;

  { --- removable ranges --------------------------------------------------- }
  DceRemCount := 0;
  liveN := 0; deadN := 0; liveB := 0; deadB := 0; gotB := 0;
  slot := 0;
  while slot < DceOrderCount do
  begin
    p := DceOrder[slot];
    a := Procs[p].BodyAddr;
    b := DceBodyEnd(slot);
    if b > a then
    begin
      if DceLive[p] then begin Inc(liveN); liveB := liveB + (b - a); end
      else
      begin
        Inc(deadN); deadB := deadB + (b - a);
        if DceRangeHoldsStub(a, b) then
          DceReportLine('kept (holds a stub target): ' + Procs[p].Name)
        else
        begin
          DceRemStart[DceRemCount] := a;
          DceRemEnd[DceRemCount] := b;
          Inc(DceRemCount);
          gotB := gotB + (b - a);
        end;
      end;
    end;
    Inc(slot);
  end;

  if DceReport then
  begin
    writeln(StdErr, 'dce: bodies ', DceOrderCount, '  live ', liveN, ' (', liveB,
            'B)  dead ', deadN, ' (', deadB, 'B)  dropping ', DceRemCount, ' (', gotB, 'B)');
    writeln(StdErr, 'dce: code ', CodeLen, 'B -> ', CodeLen - gotB, 'B');
  end;
  if DceRemCount = 0 then Exit;

  { --- drop the bytes ----------------------------------------------------- }
  dst := DceRemStart[0];
  i := 0;
  while i < DceRemCount do
  begin
    src := DceRemEnd[i];
    if i + 1 < DceRemCount then b := DceRemStart[i + 1] else b := CodeLen;
    while src < b do
    begin
      Code[dst] := Code[src];
      Inc(dst); Inc(src);
    end;
    Inc(i);
  end;

  { --- everything that names a code offset -------------------------------- }
  i := 0;
  while i < DceOrderCount do
  begin
    p := DceOrder[i];
    if DceIsRemoved(Procs[p].BodyAddr) then
    begin
      { -1 is "no body": if reachability was wrong and something still calls it,
        ApplyCallFixups says so by name instead of jumping into the hole. }
      Procs[p].BodyAddr := -1;
      ProcBodyEnd[p] := -1;
    end
    else
    begin
      ProcBodyEnd[p] := DceNewOff(ProcBodyEnd[p]);
      Procs[p].BodyAddr := DceNewOff(Procs[p].BodyAddr);
    end;
    Inc(i);
  end;

  j := 0;
  i := 0;
  while i < FixCount do
  begin
    if not DceIsRemoved(Fixups[i].CodePos) then
    begin
      Fixups[j].CodePos := DceNewOff(Fixups[i].CodePos);
      Fixups[j].DataOff := Fixups[i].DataOff;
      Inc(j);
    end;
    Inc(i);
  end;
  FixCount := j;

  j := 0;
  i := 0;
  while i < GlobFixCount do
  begin
    if not DceIsRemoved(GlobFix[i].CodePos) then
    begin
      GlobFix[j].CodePos := DceNewOff(GlobFix[i].CodePos);
      GlobFix[j].BSSoff := GlobFix[i].BSSoff;
      Inc(j);
    end;
    Inc(i);
  end;
  GlobFixCount := j;

  j := 0;
  i := 0;
  while i < CallFixCount do
  begin
    if not DceIsRemoved(CallFix[i].CodePos) then
    begin
      CallFix[j].CodePos := DceNewOff(CallFix[i].CodePos);
      CallFix[j].ProcIdx := CallFix[i].ProcIdx;
      Inc(j);
    end;
    Inc(i);
  end;
  CallFixCount := j;

  j := 0;
  i := 0;
  while i < ProcAddrFixCount do
  begin
    if not DceIsRemoved(ProcAddrFix[i].CodePos) then
    begin
      ProcAddrFix[j].CodePos := DceNewOff(ProcAddrFix[i].CodePos);
      ProcAddrFix[j].ProcIdx := ProcAddrFix[i].ProcIdx;
      Inc(j);
    end;
    Inc(i);
  end;
  ProcAddrFixCount := j;

  j := 0;
  i := 0;
  while i < DynCallCount do
  begin
    if not DceIsRemoved(DynCallCodePos[i]) then
    begin
      DynCallCodePos[j] := DceNewOff(DynCallCodePos[i]);
      DynCallExtIdx[j] := DynCallExtIdx[i];
      Inc(j);
    end;
    Inc(i);
  end;
  DynCallCount := j;

  j := 0;
  i := 0;
  while i < CodeRefCount do
  begin
    if not DceIsRemoved(CodeRefPos[i]) then
    begin
      CodeRefPos[j] := DceNewOff(CodeRefPos[i]);
      CodeRefTarget[j] := DceNewOff(CodeRefTarget[i]);
      Inc(j);
    end;
    Inc(i);
  end;
  CodeRefCount := j;

  DbgMainBodyStart := DceNewOff(DbgMainBodyStart);
  DbgMainBodyEnd := DceNewOff(DbgMainBodyEnd);
  CodeLen := CodeLen - gotB;

  { --- and re-patch what moved ------------------------------------------- }
  ApplyCallFixups;
  i := 0;
  while i < CodeRefCount do
  begin
    Patch32(CodeRefPos[i], CodeRefTarget[i] - (CodeRefPos[i] + 4));
    Inc(i);
  end;
end;
