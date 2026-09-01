{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Emitter ===== }

procedure EnsureSpaces; forward;
procedure EmitLoadImmArm32(rd: Integer; v: Int32); forward;
procedure EmitLoadImmA64(rd: Integer; v: Int64); forward;
procedure EmitwriteSyscallArm32(dataOff, len: Integer); forward;
procedure xtensa_j(offset: Integer); forward;
procedure xtensa_movi(t, imm12: Integer); forward;
procedure xtensa_mov(dst, src: Integer); forward;
procedure xtensa_syscall; forward;
procedure XtensaEmitLitHeader; forward;

{ Kept out of EmitB so the hot inline path stays a compare and a store. The
  message names the limit because 'code overflow' alone cost a Track T bench
  investigation: it does not say whether the cap is close or wildly exceeded,
  and those want opposite fixes. }
procedure ErrorCodeOverflow;
begin
  { No IntToStr here: emit.inc is included long before sysutils-style helpers
    or the compiler's own AIntToStr are in scope, and MAX_CODE is a constant
    the reader can look up. The value was never the missing information. }
  Error('code overflow: emitted code exceeds MAX_CODE (see compiler/defs.inc). '
        + 'Raise it if this is growth rather than runaway emission; note that '
        + 'LOWER -O levels emit MORE code, so a build that fits at -O2 can '
        + 'still overflow at -O0.');
end;

{ Kept out of EmitB for the same reason ErrorCodeOverflow is: the hot path is a
  compare and a store, and it runs once per emitted BYTE.

  Code[] used to be a fixed 16 MB array -- the single biggest static buffer left
  in the compiler, reserved in full to compile `writeln('hello')`. Doubling from
  64 KB reaches the self-host's 8.8 MB in eight reallocations. MAX_CODE stays the
  hard cap so ErrorCodeOverflow still means what it says.

  The 16 bytes of slack past the capacity are for READERS, not writers: the -S
  disassembler decodes a ModRM/SIB/disp32 tail by reading Code[i+1..i+3] and can
  run a few bytes past the last instruction. Under a fixed 16 MB array that was
  harmless; with an exactly-sized buffer it would be a read off the end.
  feature-dynamic-compiler-tables }
procedure GrowCode;
var n: Integer;
begin
  if CodeLen >= MAX_CODE then ErrorCodeOverflow;
  if CodeCapacity = 0 then n := 65536 else n := CodeCapacity * 2;
  if n > MAX_CODE then n := MAX_CODE;
  SetLength(Code, n + 16);
  CodeCapacity := n;
end;

procedure EmitB(b: Byte); inline;
begin
  if CodeLen >= CodeCapacity then GrowCode;
  Code[CodeLen] := b; Inc(CodeLen);
end;

{ Record a code->code rel32 reference at the CURRENT emission point.

  Call it immediately before writing the 4-byte displacement, so CodeLen is the
  displacement's own offset -- the same convention CallFix uses.

  It exists because a finished rel32 is only correct while nothing moves, and
  dead-code elimination moves things. Every reference NOT recorded somewhere is
  a reference that silently rots the moment a body ahead of it is dropped, which
  is why the recording lives at the emission points rather than in a table
  someone has to remember to extend. feature-emission-size-dce }
procedure RecordCodeRefAt(pos, target: Integer);
var n: Integer;
begin
  if CodeRefCount >= CodeRefCapacity then
  begin
    if CodeRefCapacity = 0 then n := CODEREF_BASE else n := CodeRefCapacity * 2;
    SetLength(CodeRefPos, n); SetLength(CodeRefTarget, n);
    CodeRefCapacity := n;
  end;
  CodeRefPos[CodeRefCount] := pos;
  CodeRefTarget[CodeRefCount] := target;
  Inc(CodeRefCount);
end;

procedure RecordCodeRef(target: Integer);
begin
  RecordCodeRefAt(CodeLen, target);
end;

procedure AddDataPtrFix(dataPos, targetOff: Integer);
{ Record a data->data 8-byte pointer relocation: the slot at dataPos is patched
  at link time to (dataBase + targetOff). Used by RTTI and resource emission.
  Grows instead of capping — see the table's note in defs.inc. Lived in
  elfwriter.inc until 2026-08-25; it sits here now next to the other relocation
  recorders, and early enough that every frontend can reach it. }
var n: Integer;
begin
  if DataPtrFixCount >= DataPtrFixCapacity then
  begin
    if DataPtrFixCapacity = 0 then n := DATAPTRFIX_BASE else n := DataPtrFixCapacity * 2;
    SetLength(DataPtrFix, n);
    DataPtrFixCapacity := n;
  end;
  DataPtrFix[DataPtrFixCount].DataPos   := dataPos;
  DataPtrFix[DataPtrFixCount].TargetOff := targetOff;
  Inc(DataPtrFixCount);
end;

procedure AddMethodFix(dataPos, procIdx: Integer);
{ Record a code-address relocation into Data[]: the 8-byte slot at dataPos is
  patched to the entry address of Procs[procIdx]. Every VMT slot and every RTTI
  method entry goes through here.

  This is the ONE append point. There were nine, each a hand-written
  guard/store/store/Inc quartet -- and two of them (NilPy's VMT emitter) had no
  guard at all, so a class-dense NilPy program wrote past the end of the fixed
  array with nothing to say so. A single chokepoint is what makes that class of
  bug unstateable rather than merely unlikely. }
var n: Integer;
begin
  if MethodFixCount >= MethodFixCapacity then
  begin
    if MethodFixCapacity = 0 then n := METHFIX_BASE else n := MethodFixCapacity * 2;
    SetLength(MethodFixups, n);
    MethodFixCapacity := n;
  end;
  MethodFixups[MethodFixCount].DataPos := dataPos;
  MethodFixups[MethodFixCount].ProcIdx := procIdx;
  Inc(MethodFixCount);
end;

procedure EmitI32(v: Int64);
begin
  EmitB(Byte(v and $FF)); EmitB(Byte((v shr 8) and $FF));
  EmitB(Byte((v shr 16) and $FF)); EmitB(Byte((v shr 24) and $FF));
end;

procedure EmitI64(v: Int64);
begin
  EmitI32(v and $FFFFFFFF);
  { 32-bit backends mis-lower `v shr 32` for small Int64 values when this
    compiler self-hosts. Most emitted x86-64 immediates are small; avoid the
    shift there and keep the wide path for native/full-width cases. }
  if (v >= 0) and (v <= 2147483647) then
    EmitI32(0)
  else if (v < 0) and (v >= -2147483648) then
    EmitI32($FFFFFFFF)
  else
    EmitI32((v shr 32) and $FFFFFFFF);
end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos]   := Byte(v and $FF); Code[pos+1] := Byte((v shr 8) and $FF);
  Code[pos+2] := Byte((v shr 16) and $FF); Code[pos+3] := Byte((v shr 24) and $FF);
end;

procedure Patch24(pos: Integer; v: Integer);
begin
  Code[pos]   := Byte(v and $FF); Code[pos+1] := Byte((v shr 8) and $FF);
  Code[pos+2] := Byte((v shr 16) and $FF);
end;

{ Patch8(pos: Integer; v: Byte) lived here and is DELETED, not deprecated.

  Every one of its 21 call sites passed `CodeLen - (pos + 1)` -- a rel8 jump
  displacement -- and its `v: Byte` parameter truncated that Integer AT THE
  CALL, silently, with no warning from the compiler. It was the third and
  worst-disguised spelling of
  bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows, worst because
  it already looked like a checked helper: a fix aimed at the raw `Byte(...)`
  stores would have converted the other two spellings, left all 21 of these
  truncating, and reported the job done.

  The call sites are now PatchRel8 (rel8.inc), which refuses what it cannot
  encode. Nothing else ever called Patch8, so there is no byte-patching need
  left for it to serve -- and leaving an unused truncating helper in a file
  full of emitters is an invitation, not a convenience. `Code[pos] := v` is
  what to write if a raw byte store is ever genuinely wanted. }


{ -O1 pass 3 (constant-load size peephole): the historic form is always the
  10-byte `movabs rax, imm64` (48 B8 + 8 bytes). Under -O1 shrink the common
  small/zero constants — every consumer only cares that rax ends up holding v,
  and these encodings zero/sign-extend to the full register:
    v=0            -> `xor eax, eax`      (31 C0)          2 bytes
    0..2^32-1      -> `mov eax, imm32`    (B8 + 4)         5 bytes (zero-ext)
    -2^31..-1      -> `mov rax, imm32`    (48 C7 C0 + 4)   7 bytes (sign-ext)
  MovRaxImm is x86-64-only (48 B8 is REX.W movabs); the 32-bit/ARM/RISC-V
  backends never call it. Gated on OptLevel so -O0 stays byte-identical. }
procedure MovRaxImm(v: Int64);
begin
  if OptLevel >= 1 then
  begin
    if v = 0 then
      begin EmitB($31); EmitB($C0); Exit; end                                 { xor eax, eax }
    else if (v >= 0) and (v <= $FFFFFFFF) then
      begin EmitB($B8); EmitI32(v); Exit; end                                 { mov eax, imm32 (zero-extends) }
    else if (v >= -2147483648) and (v <= 2147483647) then
      begin EmitB($48); EmitB($C7); EmitB($C0); EmitI32(v); Exit; end;        { mov rax, imm32 (sign-extends) }
  end;
  EmitB($48); EmitB($B8); EmitI64(v);                                         { movabs rax, imm64 }
end;
procedure MovRbxImm(v: Int64); begin EmitB($48); EmitB($BB); EmitI64(v); end;
procedure MovRdiImm(v: Int64); begin EmitB($48); EmitB($BF); EmitI64(v); end;
procedure MovRsiImm(v: Int64); begin EmitB($48); EmitB($BE); EmitI64(v); end;
procedure MovRdxImm(v: Int64); begin EmitB($48); EmitB($BA); EmitI64(v); end;

{ The ONE place the x86-64 kernel-entry instruction is emitted, which is what
  lets --rtl-libc convert all 43 sites without touching a single caller: every
  caller has already set up the RAW convention (rax = nr, then rdi/rsi/rdx/r10/
  r8/r9), and the thunk converts from that. Emitting a 5-byte call rather than
  the ~140-byte body inline is not a size preference -- inlining it overflows
  rel8 jump patches that span a syscall, silently.
  feature-port-rtl-over-libc }
procedure EmitSyscall;
begin
  if RtlOverLibc and (TargetArch = TARGET_X86_64) then
  begin
    { REFUSED rather than emitted wrong: at -O3 EmitExternalIndirectCall wraps
      the call in FloatPoolSave/Restore, which address the float-resident pool
      at [rbp + FxSaveBase] -- and FxSaveBase is PER FUNCTION. In a shared
      out-of-line thunk rbp belongs to whichever caller jumped in, so those
      stores would land in that caller's frame at another function's offset and
      silently corrupt it. A loud refusal now beats a wrong value later; lifting
      it means saving the pool at the call site rather than in the thunk. }
    if OptLevel >= 3 then
      Error('--rtl-libc is not supported with -O3 yet: the shared syscall thunk '
            + 'cannot carry -O3''s per-function float-register pool (FxSaveBase '
            + 'is frame-relative). Build the libc-mode program at -O2 or lower.');
    if LibcSyscallCallCount >= MAX_CALLFIX then
      Error('too many --rtl-libc syscall sites');
    EmitB($E8);                                   { call rel32 -> thunk }
    LibcSyscallCallPos[LibcSyscallCallCount] := CodeLen;
    Inc(LibcSyscallCallCount);
    EmitI32(0);                                   { patched by EmitLibcSyscallThunk }
  end
  else begin EmitB($0F); EmitB($05); end;
end;

function PICRefsAreRipRelative: Boolean;
{ Will a global/data reference emitted right now become rip-relative? ONE
  predicate because two readers must agree: EmitGlobRef, which rewrites the
  operand, and the text assembler, which has to choose the `lea` form up front
  for `mov reg, @glob`. If they disagreed, the encoder would emit a lea and the
  writer would patch it absolute -- a wrong address with no diagnostic. }
begin
  Result := (TargetArch = TARGET_X86_64) and (not EncToAsmBuffer);
end;

{ Declaration order matters here and FPC is the only thing that checks it.
  TryI386PcRelStore calls GlobRefTrailingImm, so it has to come after it.
  PXX prescans headers and accepts either order; FPC is single-pass and does
  not, and gate.sh quick's FPC seed canary is the only gate that sees the
  difference -- `make compiler/pascal26` and --tier quick both passed with
  this function still below its caller. Measured 2026-09-01. }
function GlobRefTrailingImm(op, prev, modrm: Byte; var trail: Integer): Boolean;
{ How many instruction bytes follow the disp32 of an absolute memory operand?
  A rip-relative displacement is measured from the END of the instruction, so
  this is the correction the writers apply -- and getting it wrong does not
  crash: the access lands a few bytes off, in a NEIGHBOURING variable.

  MEASURED, and the measurement is the whole point. A census over five
  --emit-obj objects said ZERO sites have a trailing immediate, so the first
  version of this rewrite ignored the question. It was wrong for 13 of 191
  sites in a --threadsafe build: EmitReleaseHeapLock emits `mov dword [@glob],
  0` (C7 /0 with imm32), the release wrote four bytes past the lock word, the
  lock was never freed and every worker thread spun forever. The census was not
  false, it was VACUOUS -- none of the five programs used --threadsafe, so the
  population could not contain the shape. Re-measured by instrumenting the
  emitter itself, over a build that does: 8B/89/8D/63/87/FF/39 and the 0F pairs
  carry nothing, C7 carries four.

  Returns FALSE for an opcode not listed, and the caller then leaves the
  operand ABSOLUTE -- which is exactly what it did before any of this, so an
  unrecognised encoding loses position-independence and never correctness. That
  direction is deliberate: the alternative is guessing a width. }
begin
  trail := 0;
  Result := True;
  case op of
    { no immediate: mov r/m<->r, lea, movsxd, xchg, cmp, inc/dec/call/jmp/push,
      and the arithmetic r/m forms }
    $88, $89, $8A, $8B, $8D, $63, $87, $FF,
    $01, $03, $09, $0B, $21, $23, $29, $2B, $31, $33, $39, $3B, $85: trail := 0;
    $C7, $81, $69: trail := 4;   { imm32 forms: mov/grp1/imul }
    $C6, $83, $6B: trail := 1;   { imm8 forms }
  else
    { two-byte opcodes reached as 0F xx: cmpxchg, movzx, movsx, cmov, setcc --
      none of the ones this compiler emits carries an immediate. `prev` is only
      consulted here, AFTER the one-byte table has had its say, because $B1 is
      also a one-byte `mov cl, imm8`. }
    if prev = $0F then trail := 0 else Result := False;
  end;
  if modrm = 0 then ;   { reserved: F6/F7 need the reg field to decide, and are
                          deliberately not in the table above until measured }
end;

procedure EmitPicAnchorInto(reg: Integer);
{ Put a PC anchor -- an address in .text that this instruction's displacement can
  be measured from -- into reg. Callers must have established that reg is dead.

  TWO SOURCES, ONE MECHANISM. A body with a frame parked the anchor once in
  X386PicSlot at entry, so this is a 6-byte load from the frame. A FRAMELESS body
  has nowhere to park it, so the anchor is materialised inline instead: `call .L;
  .L: pop reg`, which is also 6 bytes and needs no ebp, no slot and no prologue.
  The instruction sequence that follows is identical either way.

  Without the second source the frameless body converts NOTHING, and measured on
  the pcrel subject that was every one of the 39 absolute .text relocations left
  after four families had landed -- not one of them an unhandled opcode.

  The inline form pays for itself: a `call` that is not matched by a `ret`
  unbalances the CPU's return-address predictor, so every return in that body
  mispredicts. That is why gcc emits a shared __x86.get_pc_thunk rather than
  inline call/pop in code it expects to be hot. It is confined here to bodies
  with no frame -- in this compiler's output that is the main body, which runs
  once -- and the framed path, which is all of the rest, keeps the cheap load.

  X386PicAnchor is UPDATED per site on the inline path, because the anchor is
  per site there. The framed path never touches it: its anchor is the body's. }
begin
  if X386PicSlot <> 0 then
  begin
    EmitB($8B);
    EmitB(Byte($80 or (reg shl 3) or $05));   { mod=10 reg rm=101 (ebp+disp32) }
    EmitI32(X386PicSlot);
  end
  else
  begin
    EmitB($E8); EmitI32(0);        { call .L  (displacement 0 = the next insn) }
    X386PicAnchor := CodeLen;      { .L is HERE: the address `call` pushed }
    EmitB(Byte($58 or reg));       { pop reg }
  end;
end;

function I386PicBaseUsable(reg: Integer): Boolean;
{ Whether reg can serve as the anchor base in a mod=10 ModRM.

  esp (4) cannot: rm=100 selects a SIB byte rather than a base register, so the
  encoding would mean something else entirely. ebp (5) could be encoded, but
  loading the anchor into it destroys the frame pointer the slot is addressed
  through -- and the slot is read again by every later reference in the body.
  Both refuse, and a refusing site keeps its absolute form. }
begin
  I386PicBaseUsable := (reg <> 4) and (reg <> 5);
end;

function I386PrefixBefore(pos: Integer): Boolean;
{ Is the byte at pos-1 a legacy instruction prefix?

  THIS IS THE GUARD THAT MAKES EVERY REWRITE IN THIS FILE SAFE, and it was
  missing for four families. A rewrite rewinds CodeLen past the opcode and its
  ModRM and emits new instructions in front of the original -- but a prefix the
  caller already emitted sits BEFORE the opcode, so it is not rewound, and it
  binds to whatever is emitted next instead.

  MEASURED, on `mov [glob], ax` (`66 89 05 <d32>`): the store wrapper produced
  `66` + `push ecx`, which the CPU reads as `push cx` -- TWO bytes pushed and
  four popped -- and the original store lost its `66` and wrote four bytes where
  it meant two. The body returned to address 0x1. The load family had the same
  latent defect for `66 8B 05` and had not been caught only because the pcrel
  subject's `short` reads come out as 0F B7/0F BF, which carry no prefix.

  It REFUSES rather than re-emitting the prefix in the right place, because
  scanning backwards for a prefix cannot be made sound: the preceding byte may
  be the last byte of the previous instruction and merely LOOK like one. False
  refusals cost position-independence on a handful of 16-bit accesses; a false
  acceptance costs a wrong-width memory access, which is silent. }
begin
  I386PrefixBefore := False;
  if pos < 1 then Exit;
  case Code[pos-1] of
    $66, $67, $F0, $F2, $F3,                { opsize, addrsize, lock, rep }
    $2E, $36, $3E, $26, $64, $65:           { segment overrides }
      I386PrefixBefore := True;
  end;
end;

function TryI386PcRelStore(var popReg: Integer): Boolean;
{ The store half of the i386 PC-relative conversion. A store must KEEP its
  source, so unlike a load it has no dead register to borrow and the anchor
  needs a scratch that is saved and restored:

      push scratch
      mov  scratch, [ebp+picslot]
      mov  [scratch+disp32], src      <- the caller's instruction, ModRM rebased
      pop  scratch                    <- emitted by the CALLER, after the disp32

  The pop is the caller's because the disp32 placeholder is emitted after this
  function returns; popReg carries the register out and -1 means no conversion.
  That is also why this only accepts instructions that END at the disp32:
  GlobRefTrailingImm says C7/81/69 carry four more bytes and C6/83/6B one, and a
  pop emitted before those would sit in the middle of an instruction. Those keep
  the absolute form. (C7 is `mov [glob], imm32` -- 8 sites on the pcrel subject
  and the shape that hung every worker thread once already, so it is refused
  here explicitly rather than by omission.)

  FF AND 8F ARE REFUSED SEPARATELY AND THAT IS NOT PEDANTRY. Both carry no
  trailing immediate, so the trail test alone lets them through, and both touch
  the stack: `FF /6` is `push m32`, which inside this wrapper would push the
  operand and then have the `pop` take that value straight back off instead of
  restoring the scratch -- a wrapper that destroys exactly the thing it exists
  to protect. `8F /0` is `pop m32` and is the mirror. Nothing else in the
  trail-0 set reads or writes esp, which is what makes the wrapper safe for the
  rest of it.

  The arithmetic r/m forms (01/03/09/0B/21/23/29/2B/31/33/39/3B/85/87) are
  accepted although the pcrel subject holds none: the rewrite is the same ModRM
  rebase for every one of them, and the sibling nobody exercised is this file's
  standing failure mode. 8A/8B/0F B6/B7/BE/BF never reach here -- TryI386PcRelLoad
  takes them first and gets them without a scratch. }
var modrm, sib, src, sc, trail: Integer;
    op, prev: Byte;
begin
  TryI386PcRelStore := False;
  popReg := -1;
  if TargetArch <> TARGET_I386 then Exit;
  if not EmitObjMode then Exit;
  if CodeLen < 2 then Exit;

  modrm := Code[CodeLen-1];

  { moffs stores: A2 (mov [moffs],al) and A3 (mov [moffs],eax). No ModRM, and
    the source is architecturally eax, so the scratch is simply not eax. }
  if ((modrm = $A2) or (modrm = $A3)) and not I386PrefixBefore(CodeLen-1) then
  begin
    Dec(CodeLen);
    EmitB($51);                          { push ecx }
    EmitPicAnchorInto(1);
    if modrm = $A2 then EmitB($88) else EmitB($89);
    EmitB($81);                          { mod=10 reg=eax rm=ecx }
    popReg := 1;
    TryI386PcRelStore := True;
    Exit;
  end;

  { The SIB form of the same thing: `mov [edx*8+glob], eax`. The scratch fills
    the SIB's empty base field, so it must differ from the source AND from the
    index register -- the load arm only had to avoid the index because its base
    and destination are the same register. }
  if (CodeLen >= 3) and ((modrm and $07) = $05) and
     ((Code[CodeLen-2] and $C7) = $04) then
  begin
    sib := modrm;
    modrm := Code[CodeLen-2];
    op := Code[CodeLen-3];
    if CodeLen >= 4 then prev := Code[CodeLen-4] else prev := 0;
    if I386PrefixBefore(CodeLen-3) then Exit;
    if (op = $FF) or (op = $8F) then Exit;
    if prev = $0F then Exit;
    if not GlobRefTrailingImm(op, prev, Byte(modrm), trail) then Exit;
    if trail <> 0 then Exit;
    src := (modrm shr 3) and 7;
    if src = 4 then Exit;                 { see the esp note below }
    sc := 0;
    while (sc = src) or (sc = ((sib shr 3) and 7)) do Inc(sc);
    if not I386PicBaseUsable(sc) then Exit;
    CodeLen := CodeLen - 3;               { opcode, ModRM, SIB }
    EmitB(Byte($50 or sc));
    EmitPicAnchorInto(sc);
    EmitB(op);
    EmitB(Byte($80 or (src shl 3) or $04));
    EmitB(Byte((sib and $F8) or sc));
    popReg := sc;
    TryI386PcRelStore := True;
    Exit;
  end;

  if (modrm and $C7) <> $05 then Exit;   { not absolute [disp32] }

  op := Code[CodeLen-2];
  if CodeLen >= 3 then prev := Code[CodeLen-3] else prev := 0;
  if I386PrefixBefore(CodeLen-2) then Exit;           { see I386PrefixBefore }
  if (op = $FF) or (op = $8F) then Exit;              { see the header }
  if prev = $0F then Exit;                            { load-only set; family 1 has these }
  if not GlobRefTrailingImm(op, prev, Byte(modrm), trail) then Exit;
  if trail <> 0 then Exit;

  src := (modrm shr 3) and 7;

  { THE SOURCE MAY NOT BE esp, AND THIS IS NOT A THEORETICAL CASE. The wrapper
    preserves the scratch, but `push` also MOVES esp -- so an instruction whose
    operand IS esp reads a value four bytes off and the wrapper is not
    transparent to it after all. The program's very first instruction is
    `mov [glob], esp`, saving the process entry stack pointer that argc and argv
    are found from; wrapped, it saved entry-esp-4 and the body returned to
    address 0x1. Measured, and it cost a full debug cycle to see, because the
    crash is at a `ret` in a different body from the defect.

    ebp as a source is fine -- the wrapper does not touch it. }
  if src = 4 then Exit;

  sc := 0;
  while (sc = src) do Inc(sc);            { first of eax/ecx/edx/ebx that is not the source }
  if not I386PicBaseUsable(sc) then Exit; { unreachable for sc in 0..3; kept as the assert }

  CodeLen := CodeLen - 2;                 { drop the opcode AND its ModRM }
  EmitB(Byte($50 or sc));                 { push sc }
  EmitPicAnchorInto(sc);
  EmitB(op);
  EmitB(Byte($80 or (src shl 3) or sc));  { mod=10 reg=src rm=sc }
  popReg := sc;
  TryI386PcRelStore := True;
end;

function TryI386PcRelLoad: Boolean;
{ Rewrite an absolute [disp32] LOAD, just emitted by the caller, into a load
  through this body's PC anchor, and report whether it did.

  Absolute is mod=00 rm=101. The anchor's VALUE lives in a frame slot, so the
  form becomes

      mov  dest, [ebp+picslot]      <- inserted
      mov  dest, [dest+disp32]      <- the caller's instruction, ModRM rewritten

  DEST IS ITS OWN BASE, and that is what makes this correct WITHOUT any liveness
  analysis: the instruction is a load INTO dest, so dest is dead at this point by
  construction. Nothing has to be preserved across anything, no sequence needs a
  push/pop wrapper, and no register is pinned. An earlier plan for this ticket
  pinned the anchor in esi and needed an audit of every sequence that clobbers
  it; this needs none.

  LOADS ONLY, AND ONLY THE LISTED OPCODES. A store (`89`/`88`/`C7`) must keep its
  source, a `cmp` (`39`) reads both operands, and the moffs forms (`A1`/`A2`/`A3`)
  have no ModRM to rewrite -- for all of those this returns False and the site
  stays absolute, which loses position-independence and never correctness. That
  is the same refusing posture GlobRefTrailingImm takes on this path.

  0F BE / 0F BF (movsx) are included alongside 0F B6 / 0F B7 (movzx) although the
  census did not observe them: the rewrite is identical for any `0F xx /r` load,
  and this file's own history is that the unobserved sibling is the one that stays
  broken. bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations }
var modrm, sib, opLen, dest, k: Integer;
    saved: array[0..3] of Byte;
begin
  TryI386PcRelLoad := False;
  if TargetArch <> TARGET_I386 then Exit;
  if not EmitObjMode then Exit;
  if CodeLen < 2 then Exit;

  modrm := Code[CodeLen-1];

  { SHAPES B AND C READ THE LAST BYTE AS AN OPCODE, AND A ModRM CAN LOOK EXACTLY
    LIKE ONE. $A0..$A3 as a ModRM is mod=10 reg=esp rm=eax..ebx, and $B8..$BF is
    mod=10 reg=edi -- so `mov [eax+disp32], esp` and `mov [eax+disp32], edi` are
    indistinguishable here from the moffs and B8+r forms. Today no caller reaches
    this with a mod=10 ModRM: absolute code has no base register, so callers emit
    either mod=00 rm=101 or the SIB form, and the only producers of mod=10 before
    a fixup are the whole-instruction helpers below -- each of which asserts that
    EmitGlobRef did NOT convert what it handed over. Keep those asserts; they are
    the only thing standing between this ambiguity and a silent miscompile, and
    one of them has already fired for real (EmitMovGlobEsp32).

    --- SHAPE B: the moffs LOADS, A0 (mov al,[moffs]) and A1 (mov eax,[moffs]).
    One opcode byte and NO ModRM at all, which is why the first version of this
    function could not see them: it keyed on a ModRM that is not there. The
    destination is architecturally eax, so it is the base, and the ModRM form
    they become is the ordinary one. A2/A3 are the STORES of the same family and
    are not here -- they must keep eax. --- }
  if ((modrm = $A0) or (modrm = $A1)) and not I386PrefixBefore(CodeLen-1) then
  begin
    Dec(CodeLen);
    EmitPicAnchorInto(0);                { eax }
    if modrm = $A0 then EmitB($8A) else EmitB($8B);
    EmitB($80);                          { mod=10 reg=eax rm=eax }
    TryI386PcRelLoad := True;
    Exit;
  end;

  { --- SHAPE C: B8+r, `mov reg, imm32` where the IMMEDIATE is the data address.
    Not a memory reference at all -- it is address-of -- so it becomes a `lea`
    rather than a `mov`: the anchor into reg, then `lea reg,[reg+disp32]`. Same
    dead-destination argument as the loads, since the instruction's whole effect
    is to define reg. This is the i386 twin of what EmitDataRef already does on
    x86-64, where `movabs r64, imm64` becomes `lea r64,[rip+disp32]`. --- }
  if (modrm >= $B8) and (modrm <= $BF) and not I386PrefixBefore(CodeLen-1) then
  begin
    dest := modrm - $B8;
    if not I386PicBaseUsable(dest) then Exit;
    Dec(CodeLen);
    EmitPicAnchorInto(dest);
    EmitB($8D);                          { lea }
    EmitB(Byte($80 or (dest shl 3) or dest));
    TryI386PcRelLoad := True;
    Exit;
  end;

  { --- SHAPE D: the SIB form, `mod=00 rm=100` with a SIB whose base field is
    101 (no base). `mov eax,[edx*8+disp32]` -- an indexed read of a global array,
    which is the one absolute shape that already HAS a SIB byte and so cannot
    simply have its ModRM rebased. It does not need to be: SIB already carries a
    base field, and filling it in with the anchor register is exactly what it is
    for. Scale and index are copied through untouched.

    The anchor register is the destination again, dead by the same argument, so
    the only new refusal is dest = index -- the load would then clobber its own
    index before using it. --- }
  { The byte at CodeLen-1 is the SIB here, not the ModRM -- reading it as the
    ModRM is why the first version of this arm never fired. }
  if (CodeLen >= 3) and ((modrm and $07) = $05) and
     ((Code[CodeLen-2] and $C7) = $04) then
  begin
    sib := modrm;
    modrm := Code[CodeLen-2];
    dest := (modrm shr 3) and 7;
    if not I386PicBaseUsable(dest) then Exit;
    if ((sib shr 3) and 7) = dest then Exit;   { dest is the index register }
    opLen := 0;
    if (Code[CodeLen-3] = $8B) or (Code[CodeLen-3] = $8A) then opLen := 3
    else if (CodeLen >= 4) and (Code[CodeLen-4] = $0F) and
            ((Code[CodeLen-3] = $B6) or (Code[CodeLen-3] = $B7) or
             (Code[CodeLen-3] = $BE) or (Code[CodeLen-3] = $BF)) then opLen := 4;
    if opLen = 0 then Exit;
    if I386PrefixBefore(CodeLen - opLen) then Exit;
    for k := 0 to opLen - 1 do saved[k] := Code[CodeLen - opLen + k];
    CodeLen := CodeLen - opLen;
    EmitPicAnchorInto(dest);
    for k := 0 to opLen - 3 do EmitB(saved[k]);
    EmitB(Byte($80 or (dest shl 3) or $04));      { mod=10 rm=100 (SIB) }
    EmitB(Byte((sib and $F8) or dest));           { same scale+index, base=dest }
    TryI386PcRelLoad := True;
    Exit;
  end;

  if (modrm and $C7) <> $05 then Exit;   { not absolute [disp32] }

  opLen := 0;
  if (Code[CodeLen-2] = $8B) or (Code[CodeLen-2] = $8A) then opLen := 2
  else if (CodeLen >= 3) and (Code[CodeLen-3] = $0F) and
          ((Code[CodeLen-2] = $B6) or (Code[CodeLen-2] = $B7) or
           (Code[CodeLen-2] = $BE) or (Code[CodeLen-2] = $BF)) then opLen := 3;
  if opLen = 0 then Exit;                { unlisted encoding: stay absolute }
  if I386PrefixBefore(CodeLen - opLen) then Exit;   { see I386PrefixBefore }

  dest := (modrm shr 3) and 7;
  if not I386PicBaseUsable(dest) then Exit;

  for k := 0 to opLen - 1 do saved[k] := Code[CodeLen - opLen + k];
  CodeLen := CodeLen - opLen;
  EmitPicAnchorInto(dest);

  { the caller's instruction, with ModRM mod=10 rm=dest }
  for k := 0 to opLen - 2 do EmitB(saved[k]);
  EmitB(Byte($80 or (dest shl 3) or dest));
  TryI386PcRelLoad := True;
end;

procedure DbgI386RelocShape(const site: AnsiString);
{ PXXDBG=a.i386reloc — print the bytes that PRECEDE a 32-bit absolute fixup on
  i386, one line per site, so the set of operand shapes needing conversion for
  bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations can be
  enumerated from the EMITTER rather than sampled from objects.

  Why this exists rather than an objdump census: an object census reports the
  shapes the compiled PROGRAMS happen to contain. Measured 2026-09-01, three
  honestly-taken censuses of the same compiler gave 19, 24 and 23 shapes, and
  `push imm32` read as ZERO in the newest of them while nine source sites still
  emit it (RTTI and dyn-array descriptors, which no test object reached). The
  emitter is the only population that cannot be short. }
const HEXD = '0123456789abcdef';
var k, lo: Integer;
begin
  if not PxxDbgEnabled('a.i386reloc') then Exit;
  if TargetArch <> TARGET_I386 then Exit;
  Write('PXXDBG a.i386reloc ', site, ' bytes=');
  lo := CodeLen - 8;
  if lo < 0 then lo := 0;
  for k := lo to CodeLen - 1 do
  begin
    { +1: a Pascal string literal is 1-based, so nibble 0 is HEXD[1]. Without
      it this printed out-of-bounds bytes that LOOKED like plausible hex. }
    Write(HEXD[((Code[k] shr 4) and $0F) + 1]);
    Write(HEXD[(Code[k] and $0F) + 1]);
    Write(' ');
  end;
  { slot=0 means this body has NO PC anchor -- it is the frameless main body,
    where the anchor cannot be parked because there is no ebp frame to park it
    in. Printed because without it a census reads a refusal as an unhandled
    OPCODE and sends you to write a conversion that already exists: measured, 39
    `mov reg,imm32` sites read as an unconverted family when B8+r had been
    converting for two commits and every one of the 39 was in that one body. }
  WriteLn(' at=', CodeLen, ' slot=', X386PicSlot);
end;

procedure EmitDataRef(dataOff: Integer);
{ Data-address placeholder; width follows the target's pointer size (writeELF
  patches 8 bytes, writeELF32 patches 4) -- EXCEPT for the x86-64 rip-relative
  form below, which is 4 bytes on a 64-bit target.

  The absolute form here is `movabs r64, imm64`: an address as a 64-bit
  IMMEDIATE, which no relocation can make position-independent. It has to
  become a different instruction, `lea r64, [rip+disp32]` -- REX.W 8D ModRM
  disp32, 7 bytes where movabs was 10. The register moves from the opcode's
  low three bits into ModRM.reg, so REX.B becomes REX.R.

  Same refusing shape as GlobRefTrailingImm: anything that is not exactly
  [REX.W][B8+r] keeps the absolute 8-byte form, which is what every target
  did before. }
var drRex, drOp, drReg: Byte;
    drPopReg: Integer;
begin
  if FixCount >= MAX_FIXUPS then Error('fixup overflow');
  FixupPCRel[FixCount] := False;
  FixupPicDelta[FixCount] := 0;
  if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
     (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) or
     (TargetArch = TARGET_WASM32) then
  begin
    drPopReg := -1;
    if TryI386PcRelLoad or TryI386PcRelStore(drPopReg) then
    begin
      FixupPCRel[FixCount] := True;
      FixupPicDelta[FixCount] := CodeLen - X386PicAnchor;
    end;
    { AFTER the rewrite, deliberately, so the census reads as "what is still
      absolute" rather than "what arrived". Printing it before cost a reading in
      which 58 converted `8a` sites counted as unconverted -- the object said 120
      R_386_PC32 and the census could account for 62. EmitGlobRef prints after
      its rewrite too, for the same reason. }
    DbgI386RelocShape('EmitDataRef');
    Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
    Inc(FixCount);
    EmitI32(0);
    { The store wrapper's `pop`, which has to land after the disp32 -- and the
      disp32 is emitted here, not in the function that opened the wrapper. }
    if drPopReg >= 0 then EmitB(Byte($58 or drPopReg));
    Exit;
  end;
  if PICRefsAreRipRelative and (CodeLen >= 2) then
  begin
    drRex := Code[CodeLen-2];
    drOp  := Code[CodeLen-1];
    if ((drRex and $F8) = $48) and (drOp >= $B8) and (drOp <= $BF) then
    begin
      drReg := Byte(drOp - $B8);
      { REX.B (bit 0) extended the opcode register; as ModRM.reg it is REX.R }
      Code[CodeLen-2] := Byte($48 or ((drRex and $01) shl 2));
      Code[CodeLen-1] := $8D;                        { lea }
      EmitB(Byte((drReg shl 3) or $05));             { mod=00 reg=r rm=101 }
      FixupPCRel[FixCount] := True;
      Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
      Inc(FixCount);
      EmitI32(0);
      Exit;
    end;
  end;
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  EmitI64(0);
end;

function SymOffIsData(off: Integer): Boolean;
{ Is this global symbol offset a .data offset rather than a BSS one? See
  DATA_SYM_BIAS. Ask this, never the raw comparison -- the ELF writers, the
  DWARF location emitter and any future consumer must agree on one decoding. }
begin
  Result := off >= DATA_SYM_BIAS;
end;

function SymOffDataPart(off: Integer): Integer;
{ The .data offset inside a biased symbol offset. }
begin
  Result := off - DATA_SYM_BIAS;
end;

procedure EmitGlobRef(bssOff: Integer);
{ Emit 4-byte placeholder for a BSS address -- absolute, or rip-relative on
  x86-64 where the operand shape allows it (see GlobRefTrailingImm). }
var gfN, trailN, gfPopReg: Integer;
begin
  gfPopReg := -1;
  { Grows instead of capping. The old fixed table was 2 MB of BSS sized for the
    --threadsafe self-host high-water mark, and the cap it enforced was hit by
    that build 121 entries in (bug-a-threadsafe-self-host-exceeds-max-globfix-by-121)
    -- a capacity limit that read as a mysterious failure in the last unit.
    feature-dynamic-compiler-tables }
  if GlobFixCount >= GlobFixCapacity then
  begin
    if GlobFixCapacity = 0 then gfN := 8192 else gfN := GlobFixCapacity * 2;
    SetLength(GlobFix, gfN);
    SetLength(GlobFixPCRel, gfN);
    SetLength(GlobFixTrail, gfN);
    SetLength(GlobFixPicDelta, gfN);
    GlobFixCapacity := gfN;
  end;
  GlobFixPCRel[GlobFixCount] := False;
  GlobFixTrail[GlobFixCount] := 0;
  GlobFixPicDelta[GlobFixCount] := 0;
  { x86-64: rewrite the absolute [disp32] memory operand just emitted into the
    rip-relative form, so .text carries R_X86_64_PC32 and an object can be
    linked into a PIE (feature-a-x86-64-object-output-is-position-dependent).

    Done HERE rather than at ~200 call sites because every one of them emits the
    ModRM (+SIB) immediately before calling us, so the bytes to rewrite are the
    ones at the end of the buffer. Absolute [disp32] is mod=00 rm=100 with
    SIB=$25 (no base, no index); rip-relative is mod=00 rm=101 and NO SIB byte,
    so the rewrite drops one byte.

    THAT CENSUS WAS EMPTY, AND THIS COMMENT USED TO STATE ITS RESULT AS FACT.
    It said: across 1271 relocation sites, none is indexed and none has an
    immediate trailing the displacement, so every addend here is -4. The
    instrument was sound and gcc-validated; the POPULATION could not contain
    what it was counting -- all five objects were built without --threadsafe,
    and the trailing-immediate shape lives almost entirely in lock code. The
    zero was not wrong, it was empty.

    What it cost, before the re-measure: EmitReleaseHeapLock emits
    `mov dword [@glob], 0` -- C7 /0, imm32 TRAILING the disp32 -- so measured
    from rip the release wrote four bytes PAST the lock word. The lock was
    never freed, every worker spun forever, test_multithreading hung at its
    first join, and test_mutex passed. No crash and no diagnostic.

    Re-measured over a population that CAN contain it (instrumenting the
    emitter, building --threadsafe): 13 of 191 converted sites are C7 and trail
    four bytes. So the addend is NOT uniformly -4, which is why GlobRefTrailingImm
    derives it from the opcode -- and returns False for anything unlisted, in
    which case the operand stays absolute. An unrecognised encoding loses
    position-independence, never correctness.

    Do not restore a "no site trails an immediate" claim from a census of
    objects built without --threadsafe.

    The `else` REFUSES. A fourth byte-shape must not be silently emitted as a
    displacement that is now relative to something else -- that is the shape of
    bug this repo pays most for.

    The address-as-immediate shapes (`mov r32, imm32` / `movabs r64, imm64`)
    used to be listed here as the unconverted remainder. They are converted
    now, but NOT by this function: an immediate needs a different INSTRUCTION,
    so EmitDataRef rewrites the `movabs` into `lea r64, [rip+disp32]` and
    asmtext.inc emits the lea directly for `mov reg, @glob`. Both then arrive
    here, or set FixupPCRel themselves, already in rip form -- which is what
    the second branch below is for. .text now carries no absolute relocation
    at all, and that is asserted in the Makefile's test-emit-obj rows. }
  if PICRefsAreRipRelative and (CodeLen >= 4) and
     (Code[CodeLen-1] = $25) and ((Code[CodeLen-2] and $C7) = $04) and
     GlobRefTrailingImm(Code[CodeLen-3], Code[CodeLen-4], Code[CodeLen-2], trailN) then
  begin
    Code[CodeLen-2] := Byte((Code[CodeLen-2] and $38) or $05);  { mod=00 rm=101 }
    Dec(CodeLen);                                               { drop the SIB }
    GlobFixPCRel[GlobFixCount] := True;
    GlobFixTrail[GlobFixCount] := trailN;
  end
  else if PICRefsAreRipRelative and (CodeLen >= 2) and
          (Code[CodeLen-2] = $8D) and ((Code[CodeLen-1] and $C7) = $05) then
    { The caller already emitted `lea r64, [rip+disp32]` and wants the
      displacement recorded, not rewritten. No collision with the branch above:
      that one requires BOTH a $25 SIB and a ModRM with rm=100, and $8D has
      rm=101. }
    GlobFixPCRel[GlobFixCount] := True
  else if TryI386PcRelLoad or TryI386PcRelStore(gfPopReg) then
  begin
    GlobFixPCRel[GlobFixCount] := True;
    GlobFixPicDelta[GlobFixCount] := CodeLen - X386PicAnchor;
  end;
  DbgI386RelocShape('EmitGlobRef');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount); EmitI32(0);
  { see EmitDataRef: the store wrapper's `pop` belongs after the disp32 }
  if gfPopReg >= 0 then EmitB(Byte($58 or gfPopReg));
end;

procedure EmitMovGlobEsp32(bssOff: Integer);
{ `mov [glob], esp` -- the program entry's very first instruction, saving the
  process entry stack pointer.

  TryI386PcRelStore refuses this shape and must keep refusing it: its wrapper
  `push`es, and an instruction whose operand IS esp cannot survive that. This
  emits it without a wrapper instead, which needs a base register that is free
  WITHOUT being saved -- and here there is one for a reason that holds only at
  this site. It is the entry sequence's first instruction: nothing of ours runs
  before it, and however the object is reached (Linux hands a fresh process
  zeroed registers; a gcc-built main reaches it through a thunk) eax is
  caller-saved under cdecl, so nothing live can be in it.

  The anchor's own `call` pushes and its `pop` takes back, so esp is exactly its
  entry value by the time the store reads it. That is the property the whole
  rewrite turns on, and it is why the anchor must come FIRST. }
var gfIdx: Integer;
begin
  if (TargetArch <> TARGET_I386) or (not EmitObjMode) then
  begin
    EmitB($89); EmitB($25); EmitGlobRef(bssOff);
    Exit;
  end;
  { THE ADDRESS IS COMPUTED FIRST AND STORED THROUGH SEPARATELY, and that is not
    style. The direct form `mov [eax+disp32], esp` encodes as 89 A0 <disp32> --
    and $A0 as a ModRM (mod=10, reg=esp, rm=eax) is byte-identical to $A0 as the
    moffs OPCODE `mov al,[moffs]`. EmitGlobRef sees only the last byte before the
    displacement it is about to emit, so it read this ModRM as a moffs opcode and
    rewrote the instruction. Caught by the assert below, which is why the assert
    is here. `lea` puts the fixup behind ModRM $80 instead, which collides with
    nothing, and the store that follows carries no relocation at all. }
  EmitPicAnchorInto(0);
  EmitB($8D); EmitB($80);           { lea eax, [eax+disp32] }
  gfIdx := GlobFixCount;
  EmitGlobRef(bssOff);
  if GlobFixPCRel[gfIdx] then
    Error('EmitMovGlobEsp32: EmitGlobRef converted a shape it was not meant to');
  GlobFixPCRel[gfIdx] := True;
  GlobFixPicDelta[gfIdx] := GlobFix[gfIdx].CodePos - X386PicAnchor;
  EmitB($89); EmitB($20);           { mov [eax], esp }
end;

procedure EmitMovGlobAx16(bssOff: Integer);
{ `mov word [glob], ax` -- the 16-bit store, `66 A3 <moffs>`.

  Refused by I386PrefixBefore for a sound reason (a byte before an opcode cannot
  be told from the last byte of the previous instruction by looking at it), and
  the answer is the same as for C7: stop guessing backwards and emit the whole
  instruction here, where the `66` is placed by this code and therefore lands in
  front of the store rather than in front of the inserted push.

  The rewritten form is the ModRM store, not the moffs one -- moffs has no base
  register to hang the anchor on. }
var gfIdx: Integer;
begin
  if (TargetArch <> TARGET_I386) or (not EmitObjMode) then
  begin
    EmitB($66); EmitB($A3); EmitGlobRef(bssOff);
    Exit;
  end;
  EmitB($51);                       { push ecx }
  EmitPicAnchorInto(1);
  EmitB($66); EmitB($89); EmitB($81);   { mov word [ecx+disp32], ax }
  gfIdx := GlobFixCount;
  EmitGlobRef(bssOff);
  if GlobFixPCRel[gfIdx] then
    Error('EmitMovGlobAx16: EmitGlobRef converted a shape it was not meant to');
  GlobFixPCRel[gfIdx] := True;
  GlobFixPicDelta[gfIdx] := GlobFix[gfIdx].CodePos - X386PicAnchor;
  EmitB($59);                       { pop ecx }
end;

procedure EmitMovGlobImm32(bssOff, imm: Integer);
{ `mov dword [glob], imm32` -- C7 /0, the one absolute shape TryI386PcRelStore
  cannot take.

  Its problem is placement, not encoding: the scratch wrapper's `pop` must land
  after the imm32, and the imm32 is emitted by the CALLER, after EmitGlobRef has
  already returned. So the fix is not a cleverer rewrite, it is to stop
  splitting the instruction across the caller and the emitter -- this emits the
  whole thing, imm32 included, and the pop has somewhere to go.

  There is no source register to avoid (the source is the immediate), so the
  scratch is simply eax.

  EmitGlobRef is still what records the fixup, so the growth, the capacity
  doubling and the bookkeeping all stay in one place; it sees a mod=10 ModRM,
  declines to convert it, and records an absolute entry that this retypes. The
  assert is not decoration: if a future family ever did convert this shape, the
  retype would be applied twice and the addend would be silently doubled. }
var gfIdx: Integer;
begin
  if (TargetArch <> TARGET_I386) or (not EmitObjMode) then
  begin
    EmitB($C7); EmitB($05); EmitGlobRef(bssOff); EmitI32(imm);
    Exit;
  end;
  EmitB($50);                       { push eax }
  EmitPicAnchorInto(0);
  EmitB($C7); EmitB($80);           { mov dword [eax+disp32], imm32 }
  gfIdx := GlobFixCount;
  EmitGlobRef(bssOff);
  if GlobFixPCRel[gfIdx] then
    Error('EmitMovGlobImm32: EmitGlobRef converted a shape it was not meant to');
  GlobFixPCRel[gfIdx] := True;
  GlobFixPicDelta[gfIdx] := GlobFix[gfIdx].CodePos - X386PicAnchor;
  EmitI32(imm);
  EmitB($58);                       { pop eax }
end;

procedure EmitwriteSyscallA64(dataOff, len: Integer);
begin
  EmitI32($D2800808);  { movz x8, #64 }
  EmitI32($D2800020);  { movz x0, #1 }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(dataOff);
  EmitI32($D2800002 + (len shl 5)); { movz x2, #len }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteSyscall(dataOff, len: Integer);
begin
  if TargetArch = TARGET_I386 then
  begin
    { i386 int 0x80 ABI: eax=4 (write), ebx=fd, ecx=buf, edx=len }
    EmitB($B8); EmitI32(4);
    EmitB($BB); EmitI32(CurWriteFd);
    EmitB($B9); EmitDataRef(dataOff);
    EmitB($BA); EmitI32(len);
    EmitB($CD); EmitB($80);
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    EmitwriteSyscallArm32(dataOff, len);
    Exit;
  end;
  if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
  begin
    { Bare-metal: hosted write syscall not supported. }
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitwriteSyscallA64(dataOff, len);
    Exit;
  end;
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd);
  EmitB($48); EmitB($BE); EmitDataRef(dataOff);
  MovRdxImm(len); EmitSyscall;
end;

procedure EmitMmapArena(len: Integer);
{ Emit an anonymous mmap of `len` bytes. On return the base address is in the
  target's first return register (rax / eax / r0 / x0 / a0).

  It used to take its length in rsi and Error only for xtensa and riscv32,
  which meant i386, arm32 and aarch64 fell through and were handed the x86-64
  encoding VERBATIM — an ELF with `Machine: ARM` whose entry point was
  `mov %rsp,0x82b5060; movabs $0x10000000,%rsi`. It refused two targets and
  lied to three. The length is now a parameter because every non-x86-64 ABI
  wants it in a different register, and hiding that in the caller is how the
  lie was possible in the first place.
  bug-a-nilpy-on-cross-targets-four-remaining-walls }
begin
  if TargetArch = TARGET_I386 then
  begin
    { mmap2(192): ebx=addr ecx=len edx=prot esi=flags edi=fd ebp=pgoffset.
      ebp is a callee-saved register the entry stub does not own -- save it. }
    EmitB($31); EmitB($DB);                { xor ebx, ebx        (addr = NULL) }
    EmitB($B9); EmitI32(len);              { mov ecx, len }
    EmitB($BA); EmitI32(3);                { mov edx, PROT_READ|PROT_WRITE }
    EmitB($BE); EmitI32($22);              { mov esi, MAP_PRIVATE|MAP_ANONYMOUS }
    EmitB($BF); EmitI32(-1);               { mov edi, -1         (fd) }
    EmitB($55);                            { push ebp }
    EmitB($31); EmitB($ED);                { xor ebp, ebp        (pgoffset = 0) }
    EmitB($B8); EmitI32(192);              { mov eax, __NR_mmap2 }
    EmitB($CD); EmitB($80);                { int 0x80            -> eax = base }
    EmitB($5D);                            { pop ebp }
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    { mmap2(192), EABI: r0=addr r1=len r2=prot r3=flags r4=fd r5=pgoffset. }
    EmitLoadImmArm32(0, 0);
    EmitLoadImmArm32(1, len);
    EmitLoadImmArm32(2, 3);
    EmitLoadImmArm32(3, $22);
    EmitI32($E3E04000);                    { mvn r4, #0          (fd = -1) }
    EmitLoadImmArm32(5, 0);
    EmitI32($E3A070C0);                    { mov r7, #192 }
    EmitI32($EF000000);                    { svc #0              -> r0 = base }
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    { mmap(222): x0=addr x1=len x2=prot x3=flags x4=fd x5=offset (BYTES). }
    EmitLoadImmA64(0, 0);
    EmitLoadImmA64(1, len);
    EmitLoadImmA64(2, 3);
    EmitLoadImmA64(3, $22);
    EmitI32($92800004);                    { movn x4, #0         (fd = -1) }
    EmitLoadImmA64(5, 0);
    EmitLoadImmA64(8, 222);
    EmitI32($D4000001);                    { svc #0              -> x0 = base }
    Exit;
  end;
  if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
    Error('mmap not supported on bare-metal target');
  MovRsiImm(len);                        { length }
  MovRdiImm(0);                          { addr = NULL }
  MovRdxImm(3);                          { PROT_READ | PROT_WRITE }
  EmitB($49); EmitB($BA); EmitI64($22);  { mov r10, MAP_PRIVATE|MAP_ANONYMOUS }
  EmitB($49); EmitB($B8); EmitI64(-1);   { mov r8, -1  (fd) }
  EmitB($49); EmitB($B9); EmitI64(0);    { mov r9, 0   (offset) }
  MovRaxImm(SYS_MMAP);
  EmitSyscall;
end;

procedure EmitExitA64(code: Int64);
begin
  EmitI32($D2800BC8);  { movz x8, #94 }
  EmitI32($D2800000 + (code shl 5)); { movz x0, #code }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitExitArm32(code: Integer);
begin
  EmitI32($E3A070F8);  { mov r7, #248  (sys_exit_group) }
  EmitLoadImmArm32(0, code);
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitExit(code: Int64);
{ exit_group, not exit: terminate every thread. A bare exit (60) only ends
  the calling thread, so a program that started worker threads (e.g. via
  gtk_init / GLib) would leave the process alive after main returns. For a
  single-threaded program the two are equivalent. }
begin
  if TargetArch = TARGET_XTENSA then
  begin
    if TargetPlatform = PLATFORM_ESP then
      { Bare metal / IDF: no kernel, so no exit syscall — park in a self-loop. }
      xtensa_j(0)
    else
    begin
      { Hosted linux (qemu-xtensa user mode): exit_group(119).

        119 IS exit_group and 118 is plain exit — VERIFIED, not read off the
        table: qemu-xtensa -strace names them, printing `exit(7)` for 118 and
        `exit_group(7)` for 119. That distinction is load-bearing here, not
        pedantic: this routine wants exit_group ON PURPOSE (see the header
        note and bug-b-concurrent-halt-from-several-threads-exits-0), because
        a plain exit ends only the CALLING thread, so Halt(216) from a worker
        left the process running and the status was silently lost as 0. A
        single-threaded probe cannot tell the two apart, and hosted xtensa has
        no threads yet (--threadsafe is x86-64/i386/aarch64/arm32 only), so
        -strace is what settled it.

        The numbering is XTENSA'S OWN unistd.h, not the generic table riscv32
        uses five lines below: there write is 64, here write is 13 (measured
        against qemu). Do not carry a number across these two arms.

        a2 = syscall number, arg0 = a6 -- NOT a2..a7 in order; see the
        IR_SYSCALL arm in ir_codegen_xtensa.inc for the full register map.
        movi's imm12 covers the 0..255 exit-code range.
        feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle }
      xtensa_movi(2, 119);                        { a2 = __NR_exit_group }
      xtensa_movi(6, Integer(code and $FF));      { a6 = arg0 = exit code }
      xtensa_syscall;
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    if EspBareBoot then
      { Bare-metal: no exit syscall — park in a self-loop. }
      EmitI32($0000006F) { jal zero, 0 }
    else
    begin
      { Hosted linux (qemu-user): exit_group(94). Raw encodings — rv32enc.inc
        is included after this file. imm12 covers the 0..255 exit-code range. }
      EmitI32($05E00893);                              { addi a7, x0, 94 }
      EmitI32($00000513 or ((code and $FF) shl 20));   { addi a0, x0, code }
      EmitI32($00000073);                              { ecall }
    end;
    Exit;
  end;
  if TargetArch = TARGET_I386 then
  begin
    { i386 int 0x80 ABI: eax=252 (exit_group), ebx=code }
    EmitB($B8); EmitI32(252);
    EmitB($BB); EmitI32(code);
    EmitB($CD); EmitB($80);
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    EmitExitArm32(code);
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitExitA64(code);
    Exit;
  end;
  MovRaxImm(SYS_EXIT_GROUP); MovRdiImm(code); EmitSyscall;
end;

procedure EmitExitReg;
{ EmitExit for a RUNTIME code — `Halt(n)` where n is an expression. The caller
  has already evaluated it into the target's natural result register (rax / eax /
  x0 / r0 / a0); this moves it into place if the ABI needs that and issues the
  same exit_group EmitExit issues, for the same reason: a bare exit ends only the
  CALLING THREAD, so in a threaded program the process status is decided by
  whichever thread exits last — and threads finishing normally exit 0. A fatal
  then reports SUCCESS at random.

  This routine exists because that rule was previously restated by hand in each
  backend's AN_HALT arm, six copies of one concept, and TWO of them drifted:
  x86-64 emitted SYS_EXIT (60) and arm32 `mov r7,#1`, both thread-exit, while
  i386/aarch64/riscv32 were right and three of those even named exit_group in a
  comment. The correct answer was sitting one line below the x86-64 bug, in the
  no-argument branch's call to EmitExit, whose comment above says exactly this.
  bug-b-concurrent-halt-from-several-threads-exits-0

  The riscv32 arm had already noticed the gap — "EmitExit's own encodings only
  cover a constant" — and hand-rolled around it rather than closing it. That note
  is what a missing abstraction looks like from inside the fifth copy.

  Kept deliberately adjacent to EmitExit and NOT merged into it: the constant
  form can materialise the code itself, this one must not touch the register the
  caller just filled. Two behaviours, one rule, and the rule is now written once. }
begin
  if TargetArch = TARGET_XTENSA then
  begin
    if TargetPlatform = PLATFORM_ESP then
      { Bare metal / IDF: no kernel, so no exit syscall and no status to report
        it with -- park in a self-loop. }
      xtensa_j(0)
    else
    begin
      { Hosted linux (qemu-xtensa user mode). This arm used to park
        UNCONDITIONALLY, treating xtensa as bare metal in a routine whose
        sibling EmitExit had already learnt the difference twenty lines up --
        the same shape as the riscv32 bug this whole routine was extracted to
        stop (bug-a-halt-n-exits-zero-on-hosted-riscv32), one target later.

        a2 holds the code (xtensa's natural result register). Move it to a6
        FIRST: the xtensa syscall map is nr->a2 and arg0->a6, so loading the
        number before the move would overwrite the code with 119.
        bug-a-halt-n-exits-zero-on-hosted-xtensa }
      xtensa_mov(6, 2);                              { a6 = arg0 = the code }
      xtensa_movi(2, 119);                           { a2 = __NR_exit_group }
      xtensa_syscall;
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    if EspBareBoot then
      EmitI32($0000006F)                             { jal zero, 0 — park }
    else
    begin
      { a0 already holds the code. Load a7 AFTER it, so computing the code
        cannot clobber the syscall number. }
      EmitI32($05E00893);                            { addi a7, x0, 94 }
      EmitI32($00000073);                            { ecall }
    end;
    Exit;
  end;
  if TargetArch = TARGET_I386 then
  begin
    EmitB($89); EmitB($C3);                          { mov ebx, eax }
    EmitB($B8); EmitI32(252);                        { mov eax, 252 (exit_group) }
    EmitB($CD); EmitB($80);                          { int 0x80 }
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    { r0 already holds the code. }
    EmitI32($E3A070F8);                              { mov r7, #248 (exit_group) }
    EmitI32($EF000000);                              { svc #0 }
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    { x0 already holds the code. }
    EmitI32($D2800BC8);                              { movz x8, #94 (exit_group) }
    EmitI32($D4000001);                              { svc #0 }
    Exit;
  end;
  EmitB($48); EmitB($89); EmitB($C7);                { mov rdi, rax }
  MovRaxImm(SYS_EXIT_GROUP);
  EmitSyscall;
end;

{ ===== String table ===== }

function InternKey(const s: AnsiString): Integer;
{ Intern a COMPILE-TIME key: an identity the compiler compares against itself
  and the compiled program never sees. Same contract as InternStr — equal text
  gives an equal index — minus the emission into Data[]. Use this, never
  InternStr, for anything derived from a resolved FILE PATH: those carry ExeDir
  (from ParamStr(0)), and a path in the emitted string pool makes the output
  depend on how the compiler was invoked. See KeyStrs in defs.inc. }
var i: Integer;
begin
  for i := 0 to KeyCount-1 do
    if KeyStrs[i] = s then begin Result := i; Exit; end;
  if KeyCount >= MAX_KEYS then Error('compile-time key table overflow');
  KeyStrs[KeyCount] := s;
  Result := KeyCount;
  Inc(KeyCount);
end;

{ One 8-byte little-endian word into Data[], from a value that fits in 32 bits.
  The high dword is written as four explicit zero bytes and never as `v shr 32`:
  the 32-bit self-hosts shift a 32-bit register there and would store garbage,
  which is the same trap the string-table length prefix below already dodges. }
procedure EmitDataWord32Zx(v: Int64);
var j: Integer;
begin
  for j := 0 to 3 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := Byte((v shr (j * 8)) and $FF);
    Inc(DataLen);
  end;
  for j := 0 to 3 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
end;

function InternStr(const s: AnsiString): Integer;
var i, j: Integer; len, orAll, meta: Int64; match: Boolean;
begin
  for i := 0 to StrCount-1 do
  begin
    if Strs[i].Len = Length(s) then
    begin
      match := True;
      for j := 1 to Length(s) do
        if Strs[i].Text[j] <> s[j] then match := False;
      if match then begin Result := i; Exit; end;
    end;
  end;
  if StrCount >= MAX_STRS then Error('string table overflow');
  Strs[StrCount].Text   := s;

  { ---- the static managed-string header, laid down BEFORE Offset is taken ----
    Three words go in front of the length prefix, so that the char data at
    Offset+8 is simultaneously a frozen inline string's payload (what every
    existing consumer of Offset already reads) and a fully formed managed
    handle: the runtime's [meta][rc][len] sit at handle-24, -16 and -8, and the
    length prefix this table has always written IS the -8 word. Nothing about
    the old layout moves, which is why no call site changes.

    Offset is recorded AFTER the header, still pointing at the length prefix.
    That keeps `Offset` meaning exactly what it meant, and puts the header at
    negative offsets nobody has to know about unless they want the handle.

    The word before the header is the allocator's size word, which
    PXXStrAllocSize reads for spare capacity. It is written as an explicit ZERO
    rather than left to be whatever the previous entry's padding holds: an
    in-place append needs PXX_FLAG_APPENDABLE as well as room, and a static
    block never carries it, so this word is unreachable today — but a garbage
    capacity that only a future flag change could reach is the kind of latent
    wrong value this runtime has already been bitten by, and eight bytes per
    literal is not worth arguing about.

    Alignment first: the header is read a word at a time, and the 32-bit
    targets fault on an unaligned word. The table already ended each entry
    8-aligned, so this loop is a no-op in practice — it is here so that the
    property is stated rather than inherited. }
  while (DataLen mod 8) <> 0 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  EmitDataWord32Zx(0);                       { allocator size word: no capacity }

  { The ASCII answer, computed here because the bytes are right here. The
    runtime pays a per-byte OR inside PXXStrFromLit for exactly this; a literal
    can have it for free and for good. Same encoding as PXXStrMeta: KNOWN is
    set either way, because this loop is authoritative. }
  orAll := 0;
  for j := 1 to Length(s) do orAll := orAll or Ord(s[j]);
  meta := MSTR_KIND_LEGACY or MSTR_FLAG_STATIC or MSTR_FLAG_ASCII_KNOWN;
  if (orAll and $80) = 0 then meta := meta or MSTR_FLAG_ASCII;
  EmitDataWord32Zx(meta);                    { handle - 24 }
  EmitDataWord32Zx(MSTR_STATIC_RC);          { handle - 16 }

  Strs[StrCount].Offset := DataLen;
  Strs[StrCount].Len    := Length(s);
  
  { Write 8-byte length prefix. String table lengths fit in 32 bits; write the
    high dword explicitly so 32-bit self-hosts do not rely on `len shr 32`. }
  len := Length(s);
  for j := 0 to 3 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := Byte((len shr (j * 8)) and $FF);
    Inc(DataLen);
  end;
  for j := 0 to 3 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  
  for j := 1 to Length(s) do
    begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := Ord(s[j]); Inc(DataLen); end;

  { Explicit NUL terminator after the chars so the char data at Offset+8 is a
    valid C string for PChar()/const char* interop. The alignment padding below
    used to supply this only incidentally (and not at all when the char count
    was already 8-aligned). }
  if DataLen >= MAX_DATA then Error('data overflow');
  Data[DataLen] := 0;
  Inc(DataLen);

  { Align to 8 bytes }
  while (DataLen mod 8) <> 0 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  
  Result := StrCount; Inc(StrCount);
end;

procedure EmitLoadImmA64(rd: Integer; v: Int64);
begin
  if (v >= 0) and (v <= 65535) then
    EmitI32($D2800000 + (v shl 5) + rd)
  else
  begin
    { Fallback to PC-relative load }
    if (rd >= 0) and (rd <= 30) then
      EmitI32($58000040 + rd)  { ldr x[rd], [pc+8] }
    else
      Error('target aarch64: unsupported constant destination register');
    EmitI32($14000003);  { b [pc+12] }
    EmitI64(v);
  end;
end;

procedure EmitwriteCharA64;
begin
  { Load BSS_INTBUF address into w1 }
  EmitI32($18000041);  { ldr w1, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF);
  { strb w0, [x1] }
  EmitI32($39000020);
  { Make syscall: write(1, x1, 1) }
  EmitI32($D2800808);  { movz x8, #64 }
  EmitI32($D2800020);  { movz x0, #1 }
  EmitI32($D2800022);  { movz x2, #1 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteIntA64;
var jnsOff, loopStart: Integer;
begin
  { Test if x0 is positive }
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ge positive }
  jnsOff := CodeLen;
  EmitI32($5400000A);
  
  { Negative: print minus, then negate }
  EmitI32($CB0003E0);  { neg x0, x0 }
  
  { Save x0 on stack because we need to preserve it during write syscall }
  EmitI32($F81F0FE0);  { str x0, [sp, #-16]! }
  EmitwriteSyscallA64(MINUS_OFFSET, 1);
  EmitI32($F84107E0);  { ldr x0, [sp], #16 }
  
  { Patch the b.ge positive jump }
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7ffff) shl 5);
  
  { EmitwriteUIntA64 logic starts here }
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  { udiv, NOT sdiv: x0 is the NON-NEGATIVE MAGNITUDE by now — the negative
    case already emitted the minus and ran `neg x0, x0` above. Signed division
    here was wrong for exactly one value: neg of Low(Int64) is Low(Int64)
    again (its magnitude does not fit a signed 64-bit register), so x0 stayed
    negative, every msub remainder came out negative, and `add x5, x5, #48`
    produced Ord('0') - d for all nineteen digits. WriteLn(Low(Int64)) printed
    -'..--).0-*(+,))+(0( on aarch64 and correctly everywhere else.

    Unsigned division is right for every OTHER value too, since the operand is
    a magnitude — which is why arm32's sibling loop has said `udiv` ("divides
    the non-negative magnitude") all along. aarch64 was the outlier.
    bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes }
  EmitI32($9AC20804);  { udiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);
  
  { Write syscall: write(1, x3, x1) }
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteUIntA64;
var loopStart: Integer;
begin
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($9AC20804);  { udiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);
  
  { Write syscall: write(1, x3, x1) }
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteIntWA64(width: Integer);
var jnsOff, loopStart, jleOff, jzOff: Integer;
begin
  { Test if x0 is positive }
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ge positive (forward jump) }
  jnsOff := CodeLen;
  EmitI32($5400000A);
  
  { Negative: print minus, then negate }
  EmitI32($CB0003E0);  { neg x0, x0 }
  EmitI32($D2800029);  { movz x9, #1 }
  jzOff := CodeLen;
  EmitI32($14000000);  { b positive }
  
  { Patch jnsOff }
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7ffff) shl 5);
  EmitI32($D2800009);  { movz x9, #0 }
  
  { Patch jzOff }
  Patch32(jzOff, $14000000 or (((CodeLen - jzOff) div 4) and $03ffffff));

  { Digit conversion starts here }
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  { udiv, NOT sdiv: x0 is the NON-NEGATIVE MAGNITUDE by now — the negative
    case already emitted the minus and ran `neg x0, x0` above. Signed division
    here was wrong for exactly one value: neg of Low(Int64) is Low(Int64)
    again (its magnitude does not fit a signed 64-bit register), so x0 stayed
    negative, every msub remainder came out negative, and `add x5, x5, #48`
    produced Ord('0') - d for all nineteen digits. WriteLn(Low(Int64)) printed
    -'..--).0-*(+,))+(0( on aarch64 and correctly everywhere else.

    Unsigned division is right for every OTHER value too, since the operand is
    a magnitude — which is why arm32's sibling loop has said `udiv` ("divides
    the non-negative magnitude") all along. aarch64 was the outlier.
    bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes }
  EmitI32($9AC20804);  { udiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);

  { Save digit start/count; compute padding = width - digits - sign }
  { stp x1, x3, [sp, #-32]! }
  EmitI32($A9BE0FE1);
  { str x9, [sp, #16] }
  EmitI32($F9000BE9);
  
  { Compute padding in x4: x4 = width - x1 - x9 }
  EmitLoadImmA64(4, width);
  EmitI32($CB010084);  { sub x4, x4, x1 }
  EmitI32($CB090084);  { sub x4, x4, x9 }
  EmitI32($F100009F);  { cmp x4, #0 }
  
  jleOff := CodeLen;
  EmitI32($5400000D);  { b.le no_pad }
  
  { Print padding: write(1, SpacesOffset, x4) }
  EnsureSpaces;
  EmitI32($AA0403E2);  { mov x2, x4 (len) }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(SpacesOffset);
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $5400000D or (((CodeLen - jleOff) div 4) and $7ffff) shl 5);
  
  { Restore x9 }
  { ldr x9, [sp, #16] }
  EmitI32($F9400BE9);
  EmitI32($F100053F);  { cmp x9, #1 }
  
  jzOff := CodeLen;
  EmitI32($54000001);  { b.ne no_sign }
  
  { Write minus sign: write(1, MINUS_OFFSET, 1) }
  EmitI32($D2800022);  { mov x2, #1 }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(MINUS_OFFSET);
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
  
  { Patch jzOff }
  Patch32(jzOff, $54000001 or (((CodeLen - jzOff) div 4) and $7ffff) shl 5);
  
  { Write digits: write(1, x3, x1) }
  { ldp x1, x3, [sp], #32 }
  EmitI32($A8C20FE1);
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteUIntWA64(width: Integer);
var loopStart, jleOff: Integer;
begin
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($9AC20804);  { udiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);

  { Save digit start/count; compute padding = width - digits }
  { stp x1, x3, [sp, #-32]! }
  EmitI32($A9BE0FE1);
  
  { Compute padding in x4: x4 = width - x1 }
  EmitLoadImmA64(4, width);
  EmitI32($CB010084);  { sub x4, x4, x1 }
  EmitI32($F100009F);  { cmp x4, #0 }
  
  jleOff := CodeLen;
  EmitI32($5400000D);  { b.le no_pad }
  
  { Print padding: write(1, SpacesOffset, x4) }
  EnsureSpaces;
  EmitI32($AA0403E2);  { mov x2, x4 (len) }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(SpacesOffset);
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $5400000D or (((CodeLen - jleOff) div 4) and $7ffff) shl 5);
  
  { Write digits: write(1, x3, x1) }
  { ldp x1, x3, [sp], #32 }
  EmitI32($A8C20FE1);
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitLoadImmArm32(rd: Integer; v: Int32);
begin
  if (v >= 0) and (v <= 255) then
    EmitI32($E3A00000 or (rd shl 12) or v)
  else
  begin
    EmitI32($E59F0000 or (rd shl 12));  { ldr rd, [pc] }
    EmitI32($EA000000);                 { b .+8 }
    EmitI32(v);                         { literal }
  end;
end;

procedure EmitwriteSyscallArm32(dataOff, len: Integer);
begin
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitDataRef(dataOff);
  EmitLoadImmArm32(2, len);
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteCharArm32;
begin
  { Load BSS_INTBUF address into r1 }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF);
  { strb r0, [r1] }
  EmitI32($E5C10000);
  { Make syscall: write(1, r1, 1) }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A02001);  { mov r2, #1 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteIntArm32;
var jnsOff, loopStart: Integer;
begin
  { Test if r0 is positive }
  EmitI32($E3500000);  { cmp r0, #0 }
  { bpl positive }
  jnsOff := CodeLen;
  EmitI32($5A000000);
  
  { Negative: print minus, then negate }
  EmitI32($E2600000);  { rsb r0, r0, #0 }
  
  { Save r0 on stack because we need to preserve it during write syscall }
  EmitI32($E92D0001);  { push {r0} }
  EmitwriteSyscallArm32(MINUS_OFFSET, 1);
  EmitI32($E8BD0001);  { pop {r0} }
  
  { Patch the bpl positive jump }
  Patch32(jnsOff, $5A000000 or ((((CodeLen - jnsOff) div 4) - 2) and $00ffffff));
  
  { EmitwriteUIntArm32 logic starts here }
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E734F210);  { udiv r4, r0, r2 (divides the non-negative magnitude) }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  
  { Write syscall: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteUIntArm32;
var loopStart: Integer;
begin
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E734F210);  { udiv r4, r0, r2 (unsigned write) }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  
  { Write syscall: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteIntWArm32(width: Integer);
var jnsOff, loopStart, jleOff, jzOff: Integer;
begin
  { Test if r0 is positive }
  EmitI32($E3500000);  { cmp r0, #0 }
  { bpl positive }
  jnsOff := CodeLen;
  EmitI32($5A000000);
  
  { Negative: print minus, then negate }
  EmitI32($E2600000);  { rsb r0, r0, #0 }
  EmitI32($E3A09001);  { mov r9, #1 }
  jzOff := CodeLen;
  EmitI32($EA000000);  { b positive }
  
  { Patch jnsOff }
  Patch32(jnsOff, $5A000000 or ((((CodeLen - jnsOff) div 4) - 2) and $00ffffff));
  EmitI32($E3A09000);  { mov r9, #0 }
  
  { Patch jzOff }
  Patch32(jzOff, $EA000000 or ((((CodeLen - jzOff) div 4) - 2) and $00ffffff));

  { Digit conversion starts here }
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E734F210);  { udiv r4, r0, r2 (divides the non-negative magnitude) }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));

  { Save digit start/count and sign flag on stack }
  EmitI32($E92D020A);  { push {r1, r3, r9} }
  
  { Compute padding in r4: r4 = width - r1 - r9 }
  EmitLoadImmArm32(4, width);
  EmitI32($E0444001);  { sub r4, r4, r1 }
  EmitI32($E0444009);  { sub r4, r4, r9 }
  EmitI32($E3540000);  { cmp r4, #0 }
  
  jleOff := CodeLen;
  EmitI32($DA000000);  { ble no_pad }
  
  { Print padding: write(1, SpacesOffset, r4) }
  EnsureSpaces;
  EmitI32($E1A02004);  { mov r2, r4 (len) }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitDataRef(SpacesOffset);
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $DA000000 or ((((CodeLen - jleOff) div 4) - 2) and $00ffffff));
  
  { Restore digit start/count and sign flag from stack }
  EmitI32($E8BD020A);  { pop {r1, r3, r9} }
  
  EmitI32($E3590001);  { cmp r9, #1 }
  jzOff := CodeLen;
  EmitI32($1A000000);  { bne no_sign }
  
  { Write minus sign: write(1, MINUS_OFFSET, 1) }
  { Save r1, r3 because write syscall clobbers them }
  EmitI32($E92D000A);  { push {r1, r3} }
  EmitwriteSyscallArm32(MINUS_OFFSET, 1);
  EmitI32($E8BD000A);  { pop {r1, r3} }
  
  { Patch jzOff }
  Patch32(jzOff, $1A000000 or ((((CodeLen - jzOff) div 4) - 2) and $00ffffff));
  
  { Write digits: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteUIntWArm32(width: Integer);
var loopStart, jleOff: Integer;
begin
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E734F210);  { udiv r4, r0, r2 (unsigned write) }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));

  { Save digit start/count on stack }
  EmitI32($E92D000A);  { push {r1, r3} }
  
  { Compute padding in r4: r4 = width - r1 }
  EmitLoadImmArm32(4, width);
  EmitI32($E0444001);  { sub r4, r4, r1 }
  EmitI32($E3540000);  { cmp r4, #0 }
  
  jleOff := CodeLen;
  EmitI32($DA000000);  { ble no_pad }
  
  { Print padding: write(1, SpacesOffset, r4) }
  EnsureSpaces;
  EmitI32($E1A02004);  { mov r2, r4 (len) }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitDataRef(SpacesOffset);
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $DA000000 or ((((CodeLen - jleOff) div 4) - 2) and $00ffffff));
  
  { Restore digit start/count from stack }
  EmitI32($E8BD000A);  { pop {r1, r3} }
  
  { Write digits: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

