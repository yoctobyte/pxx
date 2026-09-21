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
      resolved from BodyAddr at write time, and both are ROOTS, because an
      address that is taken can be called from anywhere.

      "FOLLOW THE MOVE FOR FREE" IS TRUE ONLY WHERE THE REFERENCE IS ABSOLUTE,
      and this line said it unconditionally until 2026-09-21. It is false for
      the 32-bit REL OBJECT path: SHT_REL has no addend field, so i386 writes
      @proc as R_386_PC32 against the .TEXT SECTION symbol and the proc's own
      offset lives in the IN-PLACE ADDEND, as `BodyAddr + PicDelta`. BodyAddr
      is remapped below, PicDelta is read from a PARALLEL ARRAY, and the
      compaction loop dropped that array -- so the site inherited another
      entry's delta and the addend named a point 0x20D past the real body. The
      objects linked cleanly and the program died before main.

      The sentence was not merely wrong, it was load-bearing: it is the reason
      this table reads as needing no attention. Anything resolved from BodyAddr
      through a parallel array is NOT free, and the parallel arrays are the
      thing to check.

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
{ DceWhyNow/DceViaNow are read HERE rather than passed, because this is called
  from a dozen root loops and the reachability walk, and widening the signature
  would touch every one of them for a field only --dce-why reads. The pair is
  set once per loop; the FIRST mark wins, which is what makes the record a
  chain rather than a last-writer. }
begin
  if (p < 0) or (p >= ProcCount) then Exit;
  if DceLive[p] then Exit;
  DceLive[p] := True;
  DceWhy[p] := DceWhyNow;
  DceVia[p] := DceViaNow;
  DceWork[DceWorkCount] := p;
  Inc(DceWorkCount);
end;

function DceWhyName(code: Integer): AnsiString;
begin
  case code of
    DCE_WHY_VMT:      DceWhyName := 'vmt/rtti slot';
    DCE_WHY_PROCADDR: DceWhyName := '@proc taken in unowned code';
    DCE_WHY_IRAM:     DceWhyName := 'iram call fixup';
    DCE_WHY_VECTOR:   DceWhyName := 'interrupt; -- entered by hardware';
    DCE_WHY_INIT:     DceWhyName := 'unit initialization';
    DCE_WHY_ENTRY:    DceWhyName := 'entry stub call';
    DCE_WHY_FINI:     DceWhyName := 'unit finalization';
    DCE_WHY_FINIRUN:  DceWhyName := 'finalizer runner';
    DCE_WHY_EXPORT:   DceWhyName := 'exported (--emit-obj)';
    DCE_WHY_STUB:     DceWhyName := 'holds a stub target';
    DCE_WHY_FREECODE: DceWhyName := 'called from unowned code';
    DCE_WHY_CALL:     DceWhyName := 'called by';
    DCE_WHY_PAEDGE:   DceWhyName := '@proc taken in a live body';
  else DceWhyName := 'unset';
  end;
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

function DceCodeAlign: Integer;
{ The alignment a code offset must keep for this target's branch encodings to
  stay valid when DCE slides everything after a hole downwards. 1 means "no
  constraint", which is the x86 family; 4 is every fixed-width ISA here, and on
  xtensa it is load-bearing rather than free -- see the rounding in DceRun. }
begin
  if (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386) then
    Result := 1
  else
    Result := 4;
end;

procedure DceReportLine(const s: AnsiString);
begin
  if DceReport then writeln(StdErr, 'dce: ', s);
end;

procedure DceWhyChain(p: Integer; var line: AnsiString);
{ p's first root and the hops back to it: `PyHostCall <- CallBuiltin <- ... <-
  [@proc taken]`. Bounded at 8 hops because a chain is for reading, and a
  cycle here would be a bug in the mark order rather than in the program. }
var hops, v: Integer; sep: AnsiString;
begin
  line := '';
  hops := 0;
  v := p;
  { `<- X` is "X calls it"; `<- @X` is "X takes its address". Two different
    claims, and the second is the weaker one -- an address taken is not a call
    made -- so the chain has to spell which hop is which or it reads as a call
    graph it is not. }
  while (hops < 8) and (v >= 0) and (DceVia[v] >= 0)
        and ((DceWhy[v] = DCE_WHY_CALL) or (DceWhy[v] = DCE_WHY_PAEDGE)) do
  begin
    if DceWhy[v] = DCE_WHY_PAEDGE then sep := ' <- @' else sep := ' <- ';
    v := DceVia[v];
    line := line + sep + Procs[v].Name;
    Inc(hops);
  end;
  if (v >= 0) and (DceVia[v] >= 0)
     and ((DceWhy[v] = DCE_WHY_CALL) or (DceWhy[v] = DCE_WHY_PAEDGE)) then
    line := line + ' <- ...'
  else if v >= 0 then
    line := line + ' <- [' + DceWhyName(DceWhy[v]) + ']';
end;

procedure DceReportWhy(liveB: Integer);
{ WHAT THIS ANSWERS AND WHAT IT DOES NOT. It answers "what kept this body in
  the image", which had no instrument at all -- `--dce-report` says which
  bodies DIED. It does NOT answer "can the program reach this", and the two
  are different questions: a root is a conservative claim (an address in a
  table can be called from anywhere), so a body can be LIVE here and
  unreachable in every run. Anything quoting this report has to keep those
  words apart, or it will read as having decided a question it cannot see.

  The reason recorded is the FIRST that reached a body. A body reachable four
  ways shows one, and which one is a property of the mark order. }
var i, slot, sz, big, bigIdx, shown: Integer;
    perWhy: array[0..12] of Integer;
    perWhyN: array[0..12] of Integer;
    seen: array of Boolean;
    chain: AnsiString;
begin
  for i := 0 to 12 do begin perWhy[i] := 0; perWhyN[i] := 0; end;
  SetLength(seen, ProcCount);
  for i := 0 to ProcCount - 1 do seen[i] := False;
  slot := 0;
  while slot < DceOrderCount do
  begin
    i := DceOrder[slot];
    sz := DceBodyEnd(slot) - Procs[i].BodyAddr;
    if DceLive[i] and (sz > 0) and (DceWhy[i] >= 0) and (DceWhy[i] <= 12) then
    begin
      perWhy[DceWhy[i]] := perWhy[DceWhy[i]] + sz;
      perWhyN[DceWhy[i]] := perWhyN[DceWhy[i]] + 1;
    end;
    Inc(slot);
  end;
  writeln(StdErr, 'dce-why: live bytes by FIRST reason (live is not reachable;',
          ' a root is a conservative claim)');
  for i := 0 to 12 do
    if perWhyN[i] > 0 then
      writeln(StdErr, 'dce-why:   ', perWhy[i], 'B  ', perWhyN[i], ' bodies  ',
              DceWhyName(i));
  writeln(StdErr, 'dce-why: total live ', liveB, 'B');
  { --dce-why=<substr>: every live body whose name matches, with its chain.
    Substring and case-insensitive, because a method reads as `TDerived.Tag`
    here and nobody remembers which. }
  if DceWhyFilter <> '' then
  begin
    slot := 0;
    while slot < DceOrderCount do
    begin
      i := DceOrder[slot];
      sz := DceBodyEnd(slot) - Procs[i].BodyAddr;
      if Pos(LowerCase(DceWhyFilter), LowerCase(Procs[i].Name)) > 0 then
      begin
        if DceLive[i] then
        begin
          DceWhyChain(i, chain);
          writeln(StdErr, 'dce-why:   [match] ', sz, 'B  ', Procs[i].Name, chain);
        end
        else
          { A matched name that is DEAD is the answer to a different question
            and it must not look like silence: a filter printing nothing reads
            as "no such body", which is what an inlined or renamed routine
            looks like too. }
          writeln(StdErr, 'dce-why:   [match] ', sz, 'B  ', Procs[i].Name, ' <- DROPPED');
      end;
      Inc(slot);
    end;
  end;
  { WHO TAKES EACH @proc ADDRESS. An @proc is an UNCONDITIONAL root -- the
    argument is that an address in a table can be called from anywhere -- and
    the owner of the taking SITE is what says whether that argument applies
    here or whether the address is only ever taken by code this same pass is
    about to delete. That is a question the pass can answer and the report
    could not, so it prints it: `[unowned]` means an entry stub or the main
    body, a name means a body, and a name that is itself DROPPED is an @proc
    root installed by dead code. }
  for i := 0 to ProcAddrFixCount - 1 do
  begin
    slot := DceOwnerOf(ProcAddrFix[i].CodePos);
    if slot < 0 then
      writeln(StdErr, 'dce-why:   @proc ', Procs[ProcAddrFix[i].ProcIdx].Name,
              ' taken in [unowned code]')
    else if DceLive[slot] then
      writeln(StdErr, 'dce-why:   @proc ', Procs[ProcAddrFix[i].ProcIdx].Name,
              ' taken in ', Procs[slot].Name)
    else
      writeln(StdErr, 'dce-why:   @proc ', Procs[ProcAddrFix[i].ProcIdx].Name,
              ' taken in ', Procs[slot].Name, ' [DROPPED]');
  end;
  { WHERE THE STUB TARGETS LAND, because `holds a stub target` is the one root
    kind that is about ADDRESSES rather than about a table, and it is the one
    that dominates a NilPy image. A target inside a body pins that body and
    everything it calls; a target between bodies pins nothing. }
  shown := 0;
  for i := 0 to DceStubCount - 1 do
  begin
    slot := DceOwnerOf(DceStubTgt[i]);
    if slot >= 0 then
    begin
      if shown < 12 then
        writeln(StdErr, 'dce-why:   stub target ', DceStubTgt[i], ' is INSIDE ',
                Procs[slot].Name, ' (+', DceStubTgt[i] - Procs[slot].BodyAddr, ')');
      Inc(shown);
    end;
  end;
  writeln(StdErr, 'dce-why: stub targets ', DceStubCount, ', of which ', shown,
          ' land inside a body (each pins that body and its callees)');
  { The 20 biggest live bodies, each with its chain back to a root. Selection
    is an O(n*20) scan rather than a sort: n is thousands and this runs once,
    behind a flag, and a sort here would need another array the size of
    DceOrder. }
  shown := 0;
  while shown < 20 do
  begin
    big := 0; bigIdx := -1;
    slot := 0;
    while slot < DceOrderCount do
    begin
      i := DceOrder[slot];
      sz := DceBodyEnd(slot) - Procs[i].BodyAddr;
      if DceLive[i] and not seen[i] and (sz > big) then
      begin big := sz; bigIdx := i; end;
      Inc(slot);
    end;
    if bigIdx < 0 then Break;
    seen[bigIdx] := True;
    DceWhyChain(bigIdx, chain);
    writeln(StdErr, 'dce-why:   ', big, 'B  ', Procs[bigIdx].Name, chain);
    Inc(shown);
  end;
end;

procedure DceReachReport;
{ --dce-reach-from=<name>: the bodies reachable from one named body by DIRECT
  calls, walked FORWARD. Called once the edge list is built and before the
  reachability walk; it only READS DceEdgeHead/DceEdgeTo, so it does not
  disturb the pass.

  WHY THIS EXISTS RATHER THAN --dce-why. Every other query here runs BACKWARD:
  from a live body up DceVia to the root that kept it. That answers "why is
  this in the image" and cannot answer "what can this one call". The ISR
  restriction needs the second question, and the first one gives a confidently
  useless answer to it -- `--dce-why=PXXAlloc` reports the allocator live for
  `x = 1`, because PXXStrLoadFile is called from unowned code and is a root.
  Measured 2026-09-21 across six programs and both frontends: identical chain
  every time, naming nothing from the subject.

  IT PRINTS A SET AND REFUSES TO PRINT A VERDICT. CallFix holds internal DIRECT
  calls; an indirect call is not an edge here, because DCE handles those by
  making the site a conservative ROOT -- correct for keeping bodies, silent for
  a forward walk. So "PXXAlloc is not in this set" means NO DIRECT PATH, and
  anything that upgrades that to "cannot allocate" has to establish separately
  that the body makes no indirect call. Printing a reachable SET rather than
  yes/no is what keeps that in front of the reader.

  A NAME THAT DOES NOT RESOLVE IS A LOUD REFUSAL, NOT AN EMPTY SET. An empty
  set is exactly what "reaches nothing, therefore safe" looks like, so a typo
  would read as the strongest possible pass. That is this tree's own
  collision-with-the-default class, and here the default is the answer the
  caller most wants to hear.

  MEASURED LIMIT, 2026-09-21, AND IT IS WHY THIS IS NOT YET A SAFETY GUARD.
  A body that provably allocates can report ZERO reachable bodies. Hosted
  x86-64, -O0, a three-line program:

      function Leaf(x: Integer): Integer;
      begin g := g + 'x'; Leaf := x + 1; end;     { g is a global AnsiString }

      --dce-reach-from=Leaf   ->  0 bodies
      --dce-why=PXXStrAppend  ->  PXXStrAppend <- [called from unowned code]

  The concat's call site is attributed to NO proc body, so it is a root rather
  than an edge out of Leaf, and the forward walk from Leaf is empty. Mid->Leaf
  in the same program IS found, so the walk itself is sound -- verified against
  a -O0/-O2 pair where -O2 legitimately removes the edge by inlining.

  SO THE POLARITY IS CURRENTLY WRONG FOR THE ISR QUESTION: the allocating body
  is the one that reads clean. Do not build a refusal on this until the
  unowned-site question is settled -- it is the third instrument in one day to
  answer honestly about a different thing, and the second on this exact
  question.

  SETTLED SAME DAY, AND THE ZERO-WIDTH-BODY CANDIDATE IS REFUTED. Give Leaf a
  real call beside the concat and the walk finds it:

      function Leaf(x: Integer): Integer;
      begin g := g + 'x'; Leaf := Pure(x) + 1; end;

      --dce-reach-from=Leaf   ->  1 body: Pure

  So Leaf owns a range and ProcBodyEnd IS recorded. What is missing is one HOP:

      Leaf  --CodeRef-->  stub (unowned region)  --CallFix-->  PXXStrAppend

  The concat lowers to a runtime stub reached by a CodeRef, which names a code
  OFFSET and not a proc, so it is not an edge in this graph at all; the stub's
  own call to PXXStrAppend IS a CallFix entry, but its site is in unowned code
  and therefore a ROOT. Both halves of the path exist and the join does not.

  CLOSED, in the over-approximating direction, by modelling unowned code as ONE
  node (see the block in the body). Not one node per stub: DceStubTgt holds
  entry offsets and no extents, and inventing extents would be a guess inside a
  reachability answer. Merging them can produce a false YES and never a false
  NO, which is the direction a safety question wants, and those rows are
  printed as [via unowned code] so a reader can see which half of an answer is
  the approximation.

  MEASURED, frankb-8e's five-body table, reproduced here with the build
  asserted (its first run printed four clean zeros that were four BUILD
  FAILURES -- this failure mode renders as the answer you are looking for):

      body          before          after
      PlainOnly     1    no         1    no      <- must NOT move, and does not
      UsesNew       8    YES        8    YES
      UsesSetLen   25    YES       25    YES
      UsesCopy      2    no        53    YES     <- was wrong
      UsesConcat    1    no        53    YES     <- was wrong

  THE SHAPE 8e FOUND AND THE REASON IT IS NOT A GENERAL PROPERTY: object
  creation and dynamic-array growth already recorded their edges; STRING
  operations did not. So this was never "synthesised helper calls are
  invisible" -- it was one lowering path whose call sites belong to no body.
  PlainOnly staying at 1 is what shows the merge did not collapse into
  everything-reaches-everything; it is the control that makes the other four
  rows worth reading. }
var root, p, q, a, b, i, n, seen, viaN, addrN, unresN: Integer;
    vis: array of Boolean;
    viaStub: array of Boolean;   { reached only THROUGH unowned code }
    viaAddr: array of Boolean;   { reached only because a body took its ADDRESS }
    hasStubEdge: array of Boolean;
    unowned: array of Integer;
    work: array of Integer;
    wc, unownedN: Integer;
    pulledStub, pulledAddr: Boolean;
begin
  if DceReachFrom = '' then Exit;
  root := FindProc(DceReachFrom);
  if (root < 0) or (root >= ProcCount) then
  begin
    WriteLn(StdErr, 'dce-reach: NO BODY NAMED ', DceReachFrom,
                    ' -- refusing rather than printing an empty set,');
    WriteLn(StdErr, 'dce-reach: because an empty set reads as "reaches nothing, therefore safe".');
    Exit;
  end;
  SetLength(vis, ProcCount + 1);
  SetLength(viaStub, ProcCount + 1);
  SetLength(viaAddr, ProcCount + 1);
  SetLength(hasStubEdge, ProcCount + 1);
  SetLength(work, ProcCount + 1);
  SetLength(unowned, CallFixCount + 1);
  i := 0;
  while i <= ProcCount do
  begin
    vis[i] := False; viaStub[i] := False; viaAddr[i] := False;
    hasStubEdge[i] := False; Inc(i);
  end;

  { THE UNOWNED-CODE NODE. A CodeRef names a code OFFSET, not a proc, so a call
    into a runtime stub is not an edge in this graph -- and the stub's own calls
    ARE CallFix entries whose sites belong to no body, so they are roots. Both
    halves of the path exist and the join does not, which is why a body doing
    `g := g + 'x'` reached nothing at all.

    Modelled as ONE node rather than one per stub, because DceStubTgt holds
    entry offsets and no extents, and inventing extents would be a guess inside
    a reachability answer. Merging them OVER-approximates: a body that calls any
    stub appears to reach everything any stub calls, so THE MERGE can produce a
    false YES and never a false NO, and the rows it adds are marked so a reader
    can see which part of an answer is the approximation.

    THAT SOUNDNESS IS THE MERGE'S, NOT THE TOOL'S, AND THE DIFFERENCE IS THE
    WHOLE POINT (frankb-8e, 2026-09-21). Collapsing unowned code to one node can
    only ADD reachability, so it cannot manufacture a NO relative to the
    previous behaviour. A reader hears "never a false NO" as a property of the
    ANSWER. It is not one. The tool still returns a clean, confident NO for a
    body that installs an allocating routine in a dispatch slot, because the
    root `@Foo` creates is GLOBAL and is not an edge out of the body that
    created it -- so a forward walk from that very body walks clean. Measured,
    hosted, -O0, with the build asserted:

        function Allocs(x: Integer): Integer;
        begin g := g + 'x'; Allocs := x + 1; end;
        function TakesAddr(x: Integer): Integer;
        begin hook := @Allocs; TakesAddr := x + 1; end;   { calls nothing }

        --dce-reach-from=TakesAddr  ->  0 bodies, PXXAlloc: no    <- FALSE NO
        --dce-reach-from=Allocs     ->            PXXAlloc: YES   <- control

    THE @proc HALF OF THAT IS NOW CLOSED, and the same probe is its control:

        --dce-reach-from=TakesAddr  before:  0 bodies, PXXAlloc no
                                    after:  37 bodies, PXXAlloc YES
                                            Allocs  [via @proc taken]

    A body that takes an address gets an edge to what it took the address of,
    because a pointer's value has to come from somewhere and this is the
    conservative reading of "this body can cause that to run". The five-body
    table is unchanged by it -- PlainOnly still 1/no -- which is what says the
    new edge fires on the address and not on everything.

    STILL OPEN, AND A NO IS STILL NOT A SAFETY CLAIM: a body reached through a
    VMT/RTTI dispatch slot. MethodFixups has no owning body -- a vtable slot is
    DATA, written at image-write time -- so there is no site to attribute and
    no edge to add here. That is a different shape from @proc and it is not
    closed by this. frankb-8e has a live instance: a Python method body sitting
    in a Pascal vtable slot, entered by a virtual call from Pascal, with no edge
    anywhere expressing the crossing
    (bug-nilpy-a-python-override-of-a-virtual-pascal-method-segfaults-...). }
  unownedN := 0;
  i := 0;
  while i < CallFixCount do
  begin
    if (DceCallOwner[i] < 0) and (CallFix[i].ProcIdx >= 0)
       and (CallFix[i].ProcIdx < ProcCount) then
    begin
      unowned[unownedN] := CallFix[i].ProcIdx;
      Inc(unownedN);
    end;
    Inc(i);
  end;
  i := 0;
  while i < CodeRefCount do
  begin
    q := DceOwnerOf(CodeRefPos[i]);
    if (q >= 0) and (q < ProcCount) then hasStubEdge[q] := True;
    Inc(i);
  end;
  wc := 0;
  vis[root] := True;
  work[wc] := root; Inc(wc);
  seen := 0;
  WriteLn(StdErr, 'dce-reach: which bodies can ', DceReachFrom,
                  ' (proc ', root, ') reach by DIRECT calls?');
  WriteLn(StdErr, 'dce-reach:   an indirect call is NOT an edge here, so absence is',
                  ' "no direct path", not "cannot reach"');
  pulledStub := False;
  pulledAddr := False;
  while wc > 0 do
  begin
    Dec(wc);
    p := work[wc];
    if p = 0 then a := 0 else a := DceEdgeHead[p - 1];
    b := DceEdgeHead[p];
    i := a;
    while i < b do
    begin
      q := DceEdgeTo[i];
      if (q >= 0) and (q < ProcCount) and not vis[q] then
      begin
        vis[q] := True;
        viaStub[q] := viaStub[p];
        viaAddr[q] := viaAddr[p];
        work[wc] := q; Inc(wc);
      end;
      Inc(i);
    end;
    { ...and a body that TAKES AN ADDRESS may reach what it took the address
      of. The root @Foo creates is GLOBAL and is not an edge out of the body
      that created it, so without this a body doing `hook := @Allocs;` and
      nothing else walks clean and returns a confident NO -- measured, and it
      is the false-NO channel frankb-8e named. A pointer's value has to come
      from somewhere, so treating the taking site as an edge is the
      conservative reading of "this body can cause that to run". }
    i := 0;
    while i < ProcAddrFixCount do
    begin
      if DceProcAddrOwner[i] = p then
      begin
        q := ProcAddrFix[i].ProcIdx;
        if (q >= 0) and (q < ProcCount) and not vis[q] then
        begin
          pulledAddr := True;
          vis[q] := True;
          viaAddr[q] := True;
          work[wc] := q; Inc(wc);
        end;
      end;
      Inc(i);
    end;
    { ...and if this body calls into unowned code at all, it may reach whatever
      unowned code calls. Marked, because it is the approximate half. }
    if hasStubEdge[p] then
    begin
      pulledStub := True;
      i := 0;
      while i < unownedN do
      begin
        q := unowned[i];
        if not vis[q] then
        begin
          vis[q] := True;
          viaStub[q] := True;
          work[wc] := q; Inc(wc);
        end;
        Inc(i);
      end;
    end;
  end;
  n := 0; viaN := 0; addrN := 0;
  i := 0;
  while i < ProcCount do
  begin
    if vis[i] and (i <> root) then
    begin
      Inc(n);
      if viaAddr[i] then
      begin
        Inc(addrN);
        WriteLn(StdErr, 'dce-reach:   ', Procs[i].Name, '   [via @proc taken]');
      end
      else if viaStub[i] then
      begin
        Inc(viaN);
        WriteLn(StdErr, 'dce-reach:   ', Procs[i].Name, '   [via unowned code]');
      end
      else
        WriteLn(StdErr, 'dce-reach:   ', Procs[i].Name);
    end;
    Inc(i);
  end;
  seen := n;
  { Each category named separately. An earlier version folded the @proc rows
    into the unowned-code count and printed "N only via unowned code" for a set
    that contained neither -- a summary line contradicting the rows above it,
    which is the caption-ahead-of-the-data shape this tree keeps paying for. }
  WriteLn(StdErr, 'dce-reach: ', seen, ' bodies reachable from ', DceReachFrom,
                  ' (', seen - viaN - addrN, ' by direct calls, ', viaN,
                  ' via unowned code, ', addrN, ' via @proc taken)');
  if pulledStub then
    WriteLn(StdErr, 'dce-reach:   NOTE the [via unowned code] rows are an',
                    ' OVER-approximation: all stubs are one node');
  if pulledAddr then
    WriteLn(StdErr, 'dce-reach:   NOTE a body here TAKES AN ADDRESS; the',
                    ' [via @proc taken] rows are what that may reach');

  { --- unresolved calls: the reason a NO may not be a safety claim --------- }
  { A body containing IR_VIRTUAL_CALL or IR_CALL_IND calls something this
    compiler cannot name. A vtable slot is DATA written at image-write time, so
    unlike @proc there is no site to attribute and no edge to add -- the walk
    cannot be completed, only declared incomplete. Reported per body, because
    "which body" is what a caller needs in order to fix it.

    The validity flag is checked FIRST and on its own line. Without it this
    block would print "0 bodies make an unresolved call" in any build where the
    scan was never armed, which is the most reassuring possible way to say
    nothing was measured. }
  if not ProcBodyUnresolvedValid then
    WriteLn(StdErr, 'dce-reach: unresolved-call scan NOT ARMED -- this says',
                    ' NOTHING about virtual or indirect calls')
  else
  begin
    unresN := 0;
    i := 0;
    while i < ProcCount do
    begin
      if (vis[i] or (i = root)) and (i < Length(ProcBodyUnresolvedCall))
         and ProcBodyUnresolvedCall[i] then
      begin
        Inc(unresN);
        WriteLn(StdErr, 'dce-reach:   UNRESOLVED CALL in ', Procs[i].Name,
                        ' -- virtual or through a value');
      end;
      Inc(i);
    end;
    if unresN = 0 then
      WriteLn(StdErr, 'dce-reach: no unresolved calls in this set')
    else
      WriteLn(StdErr, 'dce-reach: ', unresN, ' bodies in this set make an',
                      ' UNRESOLVED call -- the walk is incomplete and a NO',
                      ' here is not a safety claim');
  end;
end;

procedure DceRun;
var i, j, p, owner, a, b, slot, liveN, deadN, liveB, deadB, gotB: Integer;
    why: AnsiString; src, dst: Integer; progressed: Boolean;
begin
  if not DceEnabled then Exit;
  why := '';
  { WHICH REFERENCE SHAPES PatchCodeRefSlot AND ApplyCallFixups CAN RE-AIM.
    This used to read "x86-64's rel32 call/jmp", which was the truth about the
    ONE line below the CodeRef loop, not about the pass; see PatchCodeRefSlot
    (ir_codegen.inc) for the 2026-09-18 measurement that separated them.

    A target qualifies when two things hold, and both are about the EMITTER, not
    about this file: every code->code reference it emits is recorded (CallFix for
    a call to a proc, CodeRef for a call or jump to a fixed code offset), and the
    slot each one sits in can be re-encoded in place. Reach is not a third
    condition -- DCE only REMOVES bytes, so |target - site| never grows and a
    branch form that encoded before still encodes after.

    XTENSA IS NO LONGER REFUSED AND THIS COMMENT SAID IT WAS until 2026-09-19 --
    stale prose sitting three lines above a refusal list that does not contain
    it, which is the shape that gets believed because the code below is correct
    and nobody re-reads the paragraph. What it describes is real and was DONE:
    the slot needs both a delta ANCHOR and a per-site FORM (call0 vs call8,
    chosen by the callee's own return instruction), and both columns exist now.
    wasm32 is the only architecture this gate turns away.
    See bug-a-dce-refuses-every-target-except-x86-64 for what remains. }
  if TargetArch = TARGET_WASM32 then
    why := 'wasm32 references functions by INDEX, not by displacement'
  { --shared only. `-c` used to be refused beside it on the premise that an
    object "carries its own code-offset relocations"; it does, and every table
    those relocations are built from -- Fixups, GlobFix, CallFix, ProcAddrFix,
    DynCall, CodeRef and Procs[].BodyAddr -- is one this pass already compacts
    and re-patches below, because an ET_EXEC image reads the same tables. The
    half that was genuinely missing was not a relocation at all: it was the ROOT
    SET. An executable is rooted at its entry point, and an object's callers are
    outside it, so rooting an object the same way drops its entire reason to
    exist. That root now exists (see the export loop below), so the refusal has
    nothing left to refuse. --shared keeps it: its exported surface goes through
    a .dynsym and a GOT this pass has never been read against, and turning both
    on from one measurement would leave the failing one unidentified. }
  else if EmitSharedMode then why := '--shared: .dynsym/GOT surface is unmeasured against this pass'
  else if DebugInfo then why := '-g line/frame tables carry code offsets'
  else if (not IsPascalFrontend) and (not IsCFrontend) and
          (not IsNilPyFrontend) then
    why := 'only the Pascal, C and NilPy frontends are wired up so far'
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
  { THE INIT/FINI THUNKS ARE CODE NO PROC OWNS, and under --emit-obj they are
    the object's entry points -- the loader calls them through .init_array /
    .fini_array. They are NOT a clean tail: measured on test_emit_obj, the init
    thunk sits at 0x1aae4 and __pxx_run_finalizers' body at 0x1ab28, so both
    thunks fall INSIDE the removable range of whatever proc precedes them.
    Registering them as stub targets is the existing mechanism for exactly this
    -- a range that holds one is kept whole -- and it is why the thunks survive
    a pass that has no edge pointing at them.

    The fini thunk's own call to the finalizer runner needs no edge either:
    FiniRunnerProc is already an explicit root above. Reaching it through
    DceOwnerOf would attribute it to the proc whose range it happens to land in,
    which is a different proc on every program. }
  if InitThunkOff >= 0 then
    if not DceAddStubTarget(InitThunkOff) then
    begin DceReportLine('off: no stub slot for the init thunk'); Exit; end;
  if FiniThunkOff >= 0 then
    if not DceAddStubTarget(FiniThunkOff) then
    begin DceReportLine('off: no stub slot for the fini thunk'); Exit; end;

  { The two graph tables are sized to THIS image's call sites, not to a cap --
    they are the only place the pass allocates anything big. }
  SetLength(DceCallOwner, CallFixCount + 1);
  SetLength(DceEdgeTo, CallFixCount + 1);

  { --- roots ------------------------------------------------------------- }
  i := 0;
  while i < ProcCount do
  begin
    DceLive[i] := False; DceWhy[i] := DCE_WHY_UNSET; DceVia[i] := -1;
    Inc(i);
  end;
  DceWorkCount := 0;
  DceViaNow := -1;   { every loop below installs a ROOT; only the walk sets a via }
  { an address in a VMT / RTTI / interface table can be called from anywhere }
  DceWhyNow := DCE_WHY_VMT;
  i := 0;
  while i < MethodFixCount do begin DceMark(MethodFixups[i].ProcIdx); Inc(i); end;
  { @proc: the same argument, BUT ONLY WHERE THE TAKING SITE IS NOT IN A BODY.
    "an address in a table can be called from anywhere" is true of an address
    that is actually WRITTEN somewhere; an `@proc` sitting in a body this same
    pass is about to delete writes nothing, because the code that would store
    it never runs. Rooting on it unconditionally is a claim about the SOURCE
    when the pass has the answer about the IMAGE.
    Measured 2026-09-20 on examples/esp32/nilpy-c3: the ONE site taking
    @PyBodyTramp is inside EvalPyStmts, which DCE itself drops -- and that
    single root was holding the whole runtime eval() tree live in a program
    that never calls eval.
    So an @proc inside a body is an EDGE (owner -> target), resolved in the
    fixpoint below; only an @proc in code no body owns is a root here.
    SOUNDNESS, and it rests on one thing: a body kept because something jumps
    INTO it is marked live above, so its `@proc` sites have a live owner and
    still root their targets. Without that loop this would leave a retained
    body holding the address of a removed one. }
  SetLength(DceProcAddrOwner, ProcAddrFixCount + 1);
  DceWhyNow := DCE_WHY_PROCADDR;
  i := 0;
  while i < ProcAddrFixCount do
  begin
    owner := DceOwnerOf(ProcAddrFix[i].CodePos);
    DceProcAddrOwner[i] := owner;
    if owner < 0 then DceMark(ProcAddrFix[i].ProcIdx);
    Inc(i);
  end;
  DceWhyNow := DCE_WHY_IRAM;
  i := 0;
  while i < IramCallFixCount do begin DceMark(IramCallFix[i].ProcIdx); Inc(i); end;
  { An `interrupt;` body is a ROOT: hardware enters it through a vector table
    and no call edge or @proc leads to it. Until the compiler emitted that
    table a program had to write `@MyIsr` itself to install one, so every such
    body was reachable as DCE_WHY_PROCADDR and this root was never needed --
    the gap existed and was masked by the very awkwardness the table removes.
    The first program that simply declared one and took a trap would otherwise
    have had its handler deleted and its vector pointed at the hole. }
  DceWhyNow := DCE_WHY_VECTOR;
  i := 0;
  while i < ProcCount do
  begin
    if (i < Length(ProcIsInterrupt)) and ProcIsInterrupt[i] then DceMark(i);
    Inc(i);
  end;
  DceWhyNow := DCE_WHY_INIT;
  i := 0;
  while i < InitProcCount do begin DceMark(InitProcs[i]); Inc(i); end;
  { an entry stub's hand-patched call -- the C frontend's `main`, and its
    pre-main initializer shell. See RecordEntryRoot for why a CallFix edge
    cannot exist for these. }
  DceWhyNow := DCE_WHY_ENTRY;
  i := 0;
  while i < EntryRootCount do begin DceMark(EntryRootProc[i]); Inc(i); end;
  DceWhyNow := DCE_WHY_FINI;
  i := 0;
  while i < FiniProcCount do begin DceMark(FiniProcs[i]); Inc(i); end;
  DceWhyNow := DCE_WHY_FINIRUN;
  DceMark(FiniRunnerProc);
  { AN OBJECT'S CALLERS ARE NOT IN THE OBJECT. Everything this object exports is
    reachable by definition -- that is what exporting means -- and no edge inside
    the image says so. Without this loop the pass is correct and useless: it
    would root an --emit-obj object at its initialisers and drop every cdecl
    routine the object was built to provide.

    ObjProcIsExported is the object writer's own predicate, deliberately, so the
    root set and the GLOBAL symbol block cannot disagree about who is visible.
    They must not: a proc dropped here gets BodyAddr := -1, ObjProcIsDefined
    reads that, and the symbol quietly stops being emitted -- a link that fails
    on `undefined reference` if you are lucky and resolves to another object's
    copy if you are not. }
  if EmitObjMode then
  begin
    DceWhyNow := DCE_WHY_EXPORT;
    i := 0;
    while i < ProcCount do
    begin
      if ObjProcIsDefined(i) and ObjProcIsExported(i) then DceMark(i);
      Inc(i);
    end;
  end;
  { A BODY THAT HOLDS A STUB TARGET IS A ROOT, NOT MERELY A BODY THAT SURVIVES.
    The range loop below already refuses to drop one -- something jumps into
    the middle of it, so its bytes have to stay -- and until 2026-09-19 that
    was the whole rule. It is half of one: code that stays in the image and
    can be entered is code that RUNS, so the calls it makes are live edges. A
    body kept that way but never marked kept its call sites through the
    compaction (they are not inside a removed range) while their callees were
    dropped for want of an edge, and ApplyCallFixups said `unresolved forward:
    PyUserObjGetattrTry` -- pylib's two `hasattr` helpers, both kept for a stub
    target, both calling a body nothing else reaches.

    Marking it here rather than keeping it there is what closes the gap,
    because a decision taken AFTER the fixpoint cannot feed the fixpoint. The
    keep branch below stays as a second line: it is unreachable for anything
    this loop marks, and it is what would catch a stub target this loop's
    range arithmetic did not see.

    NOT riscv32's bug, though riscv32 IDF is where it was found: nothing in
    either half is target-specific. What differs per target is only WHICH
    bodies end up kept-but-dead, so the same program builds on x86-64 and
    xtensa and refuses here.
    bug-a-dce-drops-a-called-body-on-the-riscv32-idf-profile }
  DceWhyNow := DCE_WHY_STUB;
  slot := 0;
  while slot < DceOrderCount do
  begin
    p := DceOrder[slot];
    a := Procs[p].BodyAddr;
    b := DceBodyEnd(slot);
    if (b > a) and DceRangeHoldsStub(a, b) then DceMark(p);
    Inc(slot);
  end;

  { a call from code that is never dropped -- the entry stub, the runtime stubs,
    the main body -- is a root by definition }
  DceWhyNow := DCE_WHY_FREECODE;
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

  DceReachReport;

  { --- reachability ------------------------------------------------------- }
  { Two edge kinds, so two nested loops: the call walk drains its worklist,
    then the @proc sweep asks whether any address-taking site has BECOME owned
    by a live body, and anything it marks feeds the walk again. It terminates
    because both only ever mark, never unmark, and there are finitely many
    bodies. In practice it is two or three sweeps. }
  repeat
    DceWhyNow := DCE_WHY_CALL;
    while DceWorkCount > 0 do
    begin
      Dec(DceWorkCount);
      p := DceWork[DceWorkCount];
      if p = 0 then a := 0 else a := DceEdgeHead[p - 1];
      b := DceEdgeHead[p];
      i := a;
      DceViaNow := p;   { whoever this walk reaches was reached BY p }
      while i < b do begin DceMark(DceEdgeTo[i]); Inc(i); end;
    end;
    progressed := False;
    DceWhyNow := DCE_WHY_PAEDGE;
    i := 0;
    while i < ProcAddrFixCount do
    begin
      owner := DceProcAddrOwner[i];
      if (owner >= 0) and DceLive[owner] and not DceLive[ProcAddrFix[i].ProcIdx] then
      begin
        DceViaNow := owner;
        DceMark(ProcAddrFix[i].ProcIdx);
        progressed := True;
      end;
      Inc(i);
    end;
  until not progressed;

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
          { KEEP THE REMOVED SPAN A MULTIPLE OF THE TARGET'S CODE ALIGNMENT.
            Everything after a hole slides down by exactly its size, so a hole
            whose size is not a multiple of 4 re-aligns every later body -- and
            xtensa's CALL0/CALL8 encode a WORD offset and require a 4-aligned
            TARGET. Measured 2026-09-18, the first xtensa --dce build: `target
            2462 is not 4-aligned`, from the encoder's own assert, on `hello`.

            This has never bitten the other targets and could not have: x86-64
            and i386 have no alignment requirement at all, and on riscv32,
            arm32 and aarch64 every instruction is 4 bytes, so a body's extent
            is already a multiple of 4 and the rounding below is a no-op. Xtensa
            is the one ISA here with 2- and 3-byte instructions, so it is the
            one where a body's SIZE is an arbitrary number.

            The cost is up to 3 dead bytes left behind per dropped body, which
            is the honest price of not moving what follows. Rounding the END
            down rather than the START up because `a` is the body's first byte
            and is already correctly aligned; only the tail is negotiable. }
          if DceCodeAlign > 1 then
            b := a + ((b - a) div DceCodeAlign) * DceCodeAlign;
          if b > a then
          begin
            DceRemStart[DceRemCount] := a;
            DceRemEnd[DceRemCount] := b;
            Inc(DceRemCount);
            gotB := gotB + (b - a);
          end;
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
    if DceWhyReport then DceReportWhy(liveB);
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
      { The PARALLEL arrays move too. They are parallel BY INDEX, so compacting
        the record without them hands every surviving site the flags of whoever
        used to sit at its new index -- see the block comment above GlobFix. }
      FixupPCRel[j] := FixupPCRel[i];
      FixupPicDelta[j] := FixupPicDelta[i];
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
      { CARRY THE PARALLEL ARRAYS. GlobFixPCRel/Trail/PicDelta are parallel to
        GlobFix BY INDEX -- deliberately outside TGlobFix, because TFixup and
        TGlobFix are bootstrap records whose size the compiler asserts about
        itself. Compacting the record alone leaves site j wearing the flags of
        whatever entry used to occupy index j.

        What that cost, measured 2026-09-01 on a five-line program with no
        threads: EmitReleaseHeapLock emits `mov dword [@glob], 0` -- C7 /0 with
        an imm32 TRAILING the disp32, so its Trail is 4 and the rip correction
        must be -(4+4). Inheriting a Trail of 0 makes the correction -4 and the
        release stores four bytes PAST the lock word. 11 acquires, 6 releases:
        every one of the five sites DCE moved wrote to lock+4, the lock was
        never cleared, and the program spun forever in the acquire loop with a
        single thread alive. No crash and no diagnostic.

        That is the SAME failure EmitGlobRef's header already describes at
        length, from the day the addend was assumed to be uniformly -4. The
        emitter derives it per opcode now and is right; this pass threw the
        answer away afterwards. Anything added parallel to these tables has to
        be added here too. }
      GlobFixPCRel[j] := GlobFixPCRel[i];
      GlobFixTrail[j] := GlobFixTrail[i];
      GlobFixPicDelta[j] := GlobFixPicDelta[i];
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
      { the snapshot is a CODE OFFSET, so it moves with the code exactly like
        the site does. -1 (a genuine forward reference) stays -1 —
        ApplyCallFixups resolves those through the already-remapped proc row. }
      if CallFixTarget[i] < 0 then
        CallFixTarget[j] := -1
      else
        CallFixTarget[j] := DceNewOff(CallFixTarget[i]);
      { CallFixAnchor IS PARALLEL TO CallFix BY INDEX, and this loop used to
        drop it -- the same shape as the GlobFix/GlobFixPCRel bug that
        test_dce_threadsafe_heaplock.pas exists for, in the table next door.
        Every site that moved would have worn the anchor of whoever previously
        sat at its new index.

        It is a CODE OFFSET, so it moves with the code exactly like the site
        does; -1 means "not a reserved long call" and stays -1. INERT TODAY and
        fixed anyway: xtensa is the only target that sets an anchor and dce.inc
        still refuses xtensa, so nothing can reach this yet. It is fixed now
        rather than as part of that arm because a latent parallel-array drop is
        invisible until the day it is not, and whoever lifts the xtensa gate
        should not have to find this underneath the work they came to do. }
      if CallFixAnchor[i] < 0 then
        CallFixAnchor[j] := -1
      else
        CallFixAnchor[j] := DceNewOff(CallFixAnchor[i]);
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
      { CARRY THE PARALLEL ARRAYS -- the GlobFix loop above says why, and this
        loop is the third and fourth instance of the same omission rather than
        a new one. ProcAddrPCRel/ProcAddrPicDelta are parallel to ProcAddrFix
        BY INDEX (defs.inc), so compacting the record alone leaves site j
        wearing the flags of whatever entry used to occupy index j.

        What that cost, measured 2026-09-21: `--dce --emit-obj --target=i386`
        on the two-object callback-table pair. i386 emits @proc as a
        PC-relative R_386_PC32 against the .TEXT SECTION symbol, so the proc's
        own offset lives in the IN-PLACE ADDEND, written here as
        `BodyAddr + PicDelta`. With the wrong PicDelta the addend named a point
        0x20D past the real body: `fp_t Handler = dbl;` initialised Handler to
        mid-function, and the first call through it jumped one byte past a
        `pop %ecx`, leaving ecx=0 and storing through a null base. The objects
        LINKED CLEANLY and the program died before printing anything.

        x86-64 could not see it: RELA names the proc's OWN symbol with addend
        0, so the value is layout-independent and no in-place addend exists to
        go stale. The exe path could not see it either -- it resolves from
        BodyAddr at write time, which this pass does remap. Only the 32-bit
        REL object path reads these two arrays. }
      ProcAddrPCRel[j] := ProcAddrPCRel[i];
      ProcAddrPicDelta[j] := ProcAddrPicDelta[i];
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
      { SAME OMISSION AS ProcAddrFix BELOW, found by grepping for the sibling
        rather than by a failing test -- defs.inc states outright that
        ProcAddrPCRel/PicDelta carry "the same meaning as
        DynCallPCRel/DynCallPicDelta", and both loops dropped both arrays while
        the Fixups and GlobFix loops beside them carry theirs.

        NOT REPRODUCED: the @proc twin has a fixture and this one does not. It
        is fixed here because the tables are parallel by index by construction
        and the omission is the defect whether or not a program reaches it
        today -- the reachable shape is a 32-bit REL object whose DCE pass drops
        an entry BEFORE a surviving PC-relative extern call, which is the same
        arrangement that made the @proc case fire. Left unasserted rather than
        claimed as covered. }
      DynCallPCRel[j] := DynCallPCRel[i];
      DynCallPicDelta[j] := DynCallPicDelta[i];
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
      CodeRefLink[j] := CodeRefLink[i];
      { A CODE OFFSET, so it moves with the code exactly like the site does.
        The two negative states are forms, not offsets, and stay as they are. }
      if CodeRefAnchor[i] < 0 then
        CodeRefAnchor[j] := CodeRefAnchor[i]
      else
        CodeRefAnchor[j] := DceNewOff(CodeRefAnchor[i]);
      Inc(j);
    end;
    Inc(i);
  end;
  CodeRefCount := j;

  DbgMainBodyStart := DceNewOff(DbgMainBodyStart);
  DbgMainBodyEnd := DceNewOff(DbgMainBodyEnd);
  { The object/so writers state these as `.text + <offset>` in .rela.init_array
    and .rela.fini_array, and as DT_INIT / DT_FINI. They are raw code offsets
    held outside every fixup table, which is what "-c / --shared carry their own
    code-offset relocations" was pointing at. Kept alive as stub targets above,
    so DceNewOff always has a real answer for them. }
  if InitThunkOff >= 0 then InitThunkOff := DceNewOff(InitThunkOff);
  if FiniThunkOff >= 0 then FiniThunkOff := DceNewOff(FiniThunkOff);
  CodeLen := CodeLen - gotB;

  { --- and re-patch what moved ------------------------------------------- }
  ApplyCallFixups;
  i := 0;
  while i < CodeRefCount do
  begin
    { PER-TARGET, and this line was the whole of `target is not x86-64`. It read
      `Patch32(CodeRefPos[i], CodeRefTarget[i] - (CodeRefPos[i] + 4))` -- a raw
      rel32 -- while the slot on every other target is an encoded branch WORD.
      PatchCodeRefSlot (ir_codegen.inc) is the arm set PatchProgramEntryJump has
      always had for the same slot; see its header for the riscv32 measurement
      that found this, and for why xtensa is still refused above. }
    PatchCodeRefSlot(CodeRefPos[i], CodeRefTarget[i], CodeRefLink[i],
                     CodeRefAnchor[i]);
    Inc(i);
  end;
end;
