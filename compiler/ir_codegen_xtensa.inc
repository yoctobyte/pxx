{ SPDX-License-Identifier: MPL-2.0 }
{ ===== IR -> Xtensa LX6/LX7 (Call0 ABI) machine code (cross target) ===== }
{ Register use: a2 = primary value, a3 = secondary, a4 = branch helper,
  a8/a9 = address/scratch temps, a15 = frame pointer, a1 = sp, a0 = ra. }

procedure XtensaAlignCode4;
{ Pad with 3-byte NOPs until CodeLen is 4-aligned (terminates in <= 3 steps). }
begin
  while (CodeLen mod 4) <> 0 do
    xtensa_nop;
end;

procedure XtensaEmitLitHeader;
{ Emit a jump over a 4-aligned 32-bit literal slot. The caller must emit
  exactly 4 literal bytes next, then `xtensa_l32r(rd, $FFFF)`: L32R offsets
  are one-extended (always negative), so the literal sits right before the
  4-aligned L32R and imm16 = -1 word. }
var jPos, litPos: Integer;
begin
  jPos := CodeLen;
  litPos := ((jPos + 3 + 3) div 4) * 4;
  xtensa_j((litPos + 4) - jPos);
  while CodeLen < litPos do
    EmitB(0);
end;

procedure EmitLoadConstXtensa(rd: Integer; v: Int32);
begin
  if (v >= -2048) and (v <= 2047) then
    xtensa_movi(rd, v)
  else
  begin
    XtensaEmitLitHeader;
    EmitI32(v);
    xtensa_l32r(rd, $FFFF);
  end;
end;

procedure EmitLoadDataRefXtensa(rd: Integer; dataOff: Integer);
begin
  XtensaEmitLitHeader;
  EmitDataRef(dataOff);
  xtensa_l32r(rd, $FFFF);
end;

procedure EmitLoadGlobAddrXtensa(rd: Integer; bssOff: Integer);
begin
  XtensaEmitLitHeader;
  EmitGlobRef(bssOff);
  xtensa_l32r(rd, $FFFF);
end;

function XtRegName(r: Integer): AnsiString;
{ 'a<n>' for the text assembler, so a register CHOSEN by ABI can still be
  spelled into an EmitAsmXtensa block. }
begin
  XtRegName := 'a' + AIntToStr(r);
end;

function XtensaMarshalReg4: Integer;
{ The FOURTH register of the string-helper marshalling quad (lenA, srcA, then
  two more that differ per helper).

  a7 ON CALL0, a3 UNDER WINDOWED, AND THE DIFFERENCE IS A BUG THAT TOOK FIVE
  ROUNDS TO FIND. The quad was chosen as a4-a7 because the Xtensa windowed ABI
  says a2-a7 survive a call8 -- which is TRUE OF THE ABI and false of this
  compiler, because EmitFrameAddrXtensa below puts the WINDOWED FRAME POINTER
  in a7. So every managed-string concat and compare overwrote the frame pointer
  and every subsequent local reference (`addi aN, a7, -off`) read from garbage.

  Measured 2026-08-31 on `r := Copy(s,2,3)` under qemu-xtensa: A07=00000001 --
  literally the `movi a7, 1` this arm emits for a Char operand's length -- and
  the fault is the very next frame-relative load, `addi a2, a7, -32; l32i a2,
  a2, 0` at 0xFFFFFFE1. SIGBUS.

  The fault is FAR from the cause and looks nothing like it: rounds 1-5 of the
  ticket killed misaligned word copy, `sp`-movement volume, call depth, the
  prologue's plain-addi ABI violation, and frame size -- all shape properties,
  all matched by a program that passes. This is a CONTENT property (which
  register holds what), which is the class the ticket had concluded it needed.
  bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength

  a3 is free here on both ABIs: the operands have already been pushed to
  expression slots, IREmitNodeXtensa leaves its value in a2, and the quad is
  consumed into a10-a13 (windowed) or a2-a5 (Call0) before anything else runs.
  Returning a7 on Call0 keeps that arm byte-identical. }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    XtensaMarshalReg4 := reg_xtensa_a3
  else
    XtensaMarshalReg4 := reg_xtensa_a7;
end;

procedure EmitFrameAddrXtensa(rd: Integer; off: Integer);
var fp: Integer;
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    fp := reg_xtensa_a7
  else
    fp := reg_xtensa_a15;
  if (off >= -128) and (off <= 127) then
    xtensa_addi(rd, fp, off)
  else
  begin
    EmitLoadConstXtensa(rd, off);
    xtensa_add(rd, fp, rd);
  end;
end;

procedure EmitSizedLoadXtensa(rd, rs: Integer; sz: Integer; sgn: Boolean);
{ rd must not be a9 (used as sign-extension scratch). }
begin
  if sz = 1 then
  begin
    xtensa_l8ui(rd, rs, 0);
    if sgn then
    begin
      { No signed 8-bit load: rd := (rd xor 128) - 128. }
      xtensa_movi(reg_xtensa_a9, 128);
      xtensa_xor(rd, rd, reg_xtensa_a9);
      xtensa_sub(rd, rd, reg_xtensa_a9);
    end;
  end
  else if sz = 2 then
  begin
    if sgn then xtensa_l16si(rd, rs, 0) else xtensa_l16ui(rd, rs, 0);
  end
  else
    xtensa_l32i(rd, rs, 0);
end;

procedure EmitSizedStoreXtensa(rt, rs: Integer; sz: Integer);
begin
  if sz = 1 then
    xtensa_s8i(rt, rs, 0)
  else if sz = 2 then
    xtensa_s16i(rt, rs, 0)
  else
    xtensa_s32i(rt, rs, 0);
end;

procedure EmitLoadVarXtensa(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitLoadGlobAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    EmitSizedLoadXtensa(reg_xtensa_a2, reg_xtensa_a8, sz, sgn);
  end
  else
  begin
    EmitFrameAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);
    EmitSizedLoadXtensa(reg_xtensa_a2, reg_xtensa_a8, sz, sgn);
  end;
end;

procedure EmitStoreVarXtensa(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitLoadGlobAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    EmitSizedStoreXtensa(reg_xtensa_a2, reg_xtensa_a8, sz);
  end
  else
  begin
    EmitFrameAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);
    EmitSizedStoreXtensa(reg_xtensa_a2, reg_xtensa_a8, sz);
  end;
end;

procedure XtensaPushA2;
{ Spill a2 to the next expression-stack slot. Windowed: sp is constant, so the
  slot is sp-relative at the running XtSpillDepth offset (never move sp, or the
  window spill area at [sp-16] desyncs). Call0: classic moving-sp push. }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    if XtSpillDepth + 4 > XT_OUTARG_REGION + XT_EXPR_REGION then
      Error('target xtensa: expression/argument stack exceeds reserved frame');
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
    Inc(XtSpillDepth, 4);
    if XtSpillDepth > XtSpillMax then XtSpillMax := XtSpillDepth;
  end
  else
  begin
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -4);
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);
  end;
end;

function XtensaSlotOff(argBase, idx, nLive: Integer): Integer;
{ Byte offset FROM SP of expression-stack slot `idx` (0 = first pushed of the
  group), given `nLive` slots pushed above argBase and still live.

  THE TWO ABIS INDEX THE EXPRESSION STACK IN OPPOSITE DIRECTIONS, and that is
  the whole reason this is a function. Windowed keeps sp fixed -- moving it
  desyncs the window spill area at [sp-16] -- so slot idx sits at a RISING
  offset from argBase. Call0 moves sp on every push, so the MOST RECENTLY
  pushed slot is at sp+0 and slot idx sits (nLive-1-idx) words above it.

  Written by hand, the windowed spelling `argBase + 4*idx` is correct on
  windowed and SILENTLY WRONG on Call0 -- it reads a neighbouring live slot
  rather than faulting, so the wrong value is always a plausible one. That is
  how ansistring `=` came to return a heap handle on the DEFAULT ABI (nonzero,
  so `if a = b` was simply always true), and how `PXXStrSetLen` got its two
  arguments the wrong way round. Call0 also never maintains XtSpillDepth, so
  `argBase` is a stale counter there, not an offset.
  bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    XtensaSlotOff := argBase + 4 * idx
  else
    XtensaSlotOff := 4 * (nLive - 1 - idx);
end;

procedure XtensaDropSlots(argBase, nLive: Integer);
{ Release nLive expression-stack slots. Windowed rewinds the offset counter;
  Call0 must actually MOVE SP BACK, which the hand-written `XtSpillDepth :=
  argBase` did not do -- that assignment is a no-op on Call0, so every managed
  string compare leaked 12 bytes of stack and every concat 12 more. }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    XtSpillDepth := argBase
  else if nLive > 0 then
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4 * nLive);
end;

function XtensaArgRegN(n: Integer): Integer;
{ The register holding outgoing argument `n` of a helper call, for the ABI in
  force. Call0 passes arg0..arg5 in a2..a7; windowed `call8` rotates the window
  so the callee sees them as a2.., which means the CALLER writes a10..a15.

  A function rather than two spellings at each site: every hand-written arm in
  this backend that needed more than one argument wrote the windowed pair by
  hand, and the Call0 half is the one that is silently wrong when it is missed —
  a wrong-but-plausible register, never a fault. Same argument as XtensaSlotOff
  one screen up. }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    XtensaArgRegN := reg_xtensa_a10 + n
  else
    XtensaArgRegN := reg_xtensa_a2 + n;
end;

procedure XtensaPopA3;
{ Pop the top expression-stack slot into a3 (windowed: sp constant). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    Dec(XtSpillDepth, 4);
    xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth);
  end
  else
  begin
    xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 0);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
  end;
end;

procedure XtensaPopA2;
{ Pop the top expression-stack slot into a2 (windowed: sp constant). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    Dec(XtSpillDepth, 4);
    xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
  end
  else
  begin
    xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
  end;
end;

procedure XtensaPush64;
{ Spill the 64-bit value in a2:a3 (lo at the lower address) to two expr-stack
  slots, same discipline as XtensaPushA2 (windowed: constant sp + XtSpillDepth;
  Call0: moving sp). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    if XtSpillDepth + 8 > XT_OUTARG_REGION + XT_EXPR_REGION then
      Error('target xtensa: expression/argument stack exceeds reserved frame');
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
    xtensa_s32i(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth + 4);
    Inc(XtSpillDepth, 8);
    if XtSpillDepth > XtSpillMax then XtSpillMax := XtSpillDepth;
  end
  else
  begin
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -8);
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);
    xtensa_s32i(reg_xtensa_a3, reg_xtensa_sp, 4);
  end;
end;

procedure XtensaPop64ToA4A5;
{ Pop the top 64-bit expr-stack slot into a4:a5 (lo:hi). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    Dec(XtSpillDepth, 8);
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, XtSpillDepth);
    xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, XtSpillDepth + 4);
  end
  else
  begin
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, 0);
    xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, 4);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 8);
  end;
end;

procedure XtensaPadTo64Xtensa(procIdx: Integer; var nArgs: Integer);
{ The xtensa C ABI starts a 64-bit argument at an EVEN word index — measured
  from the IDF's own xtensa-esp32s3-elf-gcc, which compiles
  `f(void *p, long long v)` to p in a10 and v in a12:a13, SKIPPING a11 (call0:
  a2 and a4:a5, skipping a3). The padding word's value is irrelevant; only its
  slot matters.

  This rule is now UNCONDITIONAL — it used to apply to EXTERNAL callees only,
  with pxx's own routines keeping a packed no-padding layout. That asymmetry is
  what made a pxx routine called FROM C read its 64-bit parameter one register
  early: gcc placed it at a4:a5, the pxx callee spill read a3:a4
  (bug-a-pxx-callee-uses-internal-abi-for-64bit-params-called-from-c). A calling
  convention is the TARGET's by definition — a `cdecl`/`stdcall` marker in this
  dialect is decoration — so xtensa uses the xtensa C ABI for everyone, and pxx
  and gcc cannot disagree. Internal calls stay correct because the callee spill
  in pasparser_*.inc applies the identical rule; the two must be changed together. }
begin
  if (nArgs and 1) = 1 then
  begin
    XtensaPushA2;
    Inc(nArgs);
  end;
end;

procedure XtensaLoadArgRegsWindowed(argBase, nArgs: Integer);
{ Windowed: hand nArgs argument words, spilled at sp+argBase.., to the callee.
  Words 0..5 travel in a10..a15; word k >= 6 is copied down to the outgoing
  area at sp+(k-6)*4, which the callee reads back through its own frame pointer
  (biased by its `entry` size). That is the layout xtensa gcc emits, so calls
  in and out of ESP-IDF agree. a8 is scratch: an indirect/virtual site only
  loads the callee address into it afterwards. }
var k: Integer;
begin
  if nArgs > XT_MAX_ARG_WORDS then
    Error('target xtensa windowed: more than 22 argument words not supported ' +
          '(XT_OUTARG_REGION is 16 overflow words)');
  for k := 6 to nArgs - 1 do
  begin
    xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, argBase + k * 4);
    xtensa_s32i(reg_xtensa_a8, reg_xtensa_sp, (k - 6) * 4);
  end;
  for k := 0 to nArgs - 1 do
    if k < 6 then
      xtensa_l32i(reg_xtensa_a10 + k, reg_xtensa_sp, argBase + k * 4);
end;

procedure XtensaOrderOverflowArgsCall0(nArgs: Integer);
{ Call0: the words were pushed arg0-deepest, so word k sits at (nArgs-1-k)*4
  and the overflow words 6.. occupy the LOWEST nArgs-6 slots in DESCENDING
  order. The callee reads word 6 at sp+0 ascending (gcc layout), so reverse
  that low block in place. The six register words above it stay allocated
  across the call — 24 bytes — which is why an overflowing Call0 site frees its
  block AFTER the call instead of before. Scratch is a8/a10; a9 is left alone
  because the `interrupt;` prologue does not save it. }
var lo, hi: Integer;
begin
  lo := 0;
  hi := nArgs - 7;
  while lo < hi do
  begin
    xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, lo * 4);
    xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, hi * 4);
    xtensa_s32i(reg_xtensa_a10, reg_xtensa_sp, lo * 4);
    xtensa_s32i(reg_xtensa_a8, reg_xtensa_sp, hi * 4);
    Inc(lo);
    Dec(hi);
  end;
end;

procedure XtensaLoadArgRegsCall0(nArgs: Integer);
{ Call0: words 0..5 into a2..a7; the rest are already sitting in the outgoing
  area at sp+0.. thanks to XtensaOrderOverflowArgsCall0. }
var k: Integer;
begin
  XtensaOrderOverflowArgsCall0(nArgs);
  for k := 0 to nArgs - 1 do
    if k < 6 then
      xtensa_l32i(reg_xtensa_a2 + k, reg_xtensa_sp, (nArgs - 1 - k) * 4);
end;

procedure EmitSlotAddrXtensa(rd, si: Integer);
{ rd = address of the variable's storage slot (global abs / frame-relative). }
begin
  if Syms[si].Kind = skGlobal then
    EmitLoadGlobAddrXtensa(rd, Syms[si].Offset)
  else
    EmitFrameAddrXtensa(rd, Syms[si].Offset);
end;

procedure EmitHeapAllocLockedXtensa;
{ a2 = requested payload bytes -> a2 = payload pointer. Delegates to the Pascal
  PXXAlloc(size, align=8). No threadsafe lock (x86-64-only). }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);   { arg0 = size }
    xtensa_movi(reg_xtensa_a11, 8);              { arg1 = align }
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { result }
  end
  else
  begin
    xtensa_movi(reg_xtensa_a3, 8);               { a2 = size already; arg1 = align }
    EmitCallProc(procIdx);                            { result in a2 }
  end;
end;

procedure EmitHeapFreeLockedXtensa;
{ a2 = payload pointer -> PXXFree(p). nil ignored inside. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
  EmitCallProc(procIdx);
end;

procedure EmitStrFromLitXtensa;
{ a2 = len, a3 = src -> a2 = new managed-string handle (PXXStrFromLit). }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXStrFromLit');
  if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);   { arg0 = len }
    xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);   { arg1 = src }
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { handle }
  end
  else
    EmitCallProc(procIdx);                            { a2=len, a3=src; result a2 }
end;

procedure EmitStrRefCallXtensa(const name: AnsiString);
{ a2 = handle -> call proc(handle). a2 is NOT preserved (DecRef path). }
var procIdx: Integer;
begin
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: string refcount helper not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
  EmitCallProc(procIdx);
end;

procedure EmitXtensaSoftDivCall(const name: AnsiString);
{ a2 = dividend (arg0), a3 = divisor (arg1) -> call helper -> result in a2.
  LX6 software div/mod path (--xtensa-cpu=lx6). }
var procIdx: Integer;
begin
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: xtensa soft-divide helper not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
    xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
  end
  else
    EmitCallProc(procIdx);   { a2, a3 already hold arg0, arg1; result in a2 }
end;

procedure IREmitNodeXtensa(node: Integer); forward;

procedure EmitAnsiStringFromNodeXtensa(valNode: Integer);
{ Materialise a MANAGED string handle in a2 from a value that is NOT one — a
  char, or a frozen inline buffer. Needed at a call ARGUMENT: handing a
  `string[N]` straight to a `const s: string` parameter passed the raw BUFFER
  address as if it were a heap handle, and the callee then read the 8 bytes
  BEFORE the buffer as its length. Mirrors riscv32's b345 port. }
begin
  if IntToTypeKind(IRTk[valNode]) = tyChar then
  begin
    IREmitNodeXtensa(valNode);                  { a2 = char code }
    XtensaPushA2;                               { spill char to the frame }
    if XtensaABI = XTENSA_ABI_WINDOWED then
      xtensa_addi(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth - 4)
    else
      xtensa_addi(reg_xtensa_a3, reg_xtensa_sp, 0);
    EmitLoadConstXtensa(reg_xtensa_a2, 1);      { len 1 }
    EmitStrFromLitXtensa;                       { a2 = handle }
    if XtensaABI = XTENSA_ABI_WINDOWED then Dec(XtSpillDepth, 4)
    else xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
  end
  else
  begin
    IREmitNodeXtensa(valNode);                  { a2 = frozen buffer }
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_a2, 0);  { len = [buf] }
    xtensa_addi(reg_xtensa_a3, reg_xtensa_a2, 8);  { src = buf+8 }
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);
    EmitStrFromLitXtensa;                       { a2 = handle }
  end;
end;

procedure EmitFrozenCopyXtensa(srcTk: TTypeKind; cap: Integer);
{ THE FROZEN COPY ITSELF, destination given as an ADDRESS: a5 = the evaluated
  source, a4 = the destination inline buffer, `cap` = its capacity. Writes
  [len:8][chars] with the length clamped (truncating `string[N]` semantics).
  Mirrors riscv32's b345 port: three source shapes — a char ordinal, a MANAGED
  handle (length at [h-8], chars at h, nil = empty), or another frozen/literal
  buffer (length at [b], chars at b+8).

  Split out of EmitFrozenStoreXtensa (which had it inline against a SYMBOL SLOT)
  so IR_STORE_MEM can reach it: a `string[N]` RECORD FIELD is reached through an
  address expression, not a slot index, and that path had no frozen store at all
  — the generic sized store dropped the source ADDRESS into the field.
  bug-a-xtensa-cannot-read-a-managed-string-out-of-a-record-field-or-array-element }
begin
  if cap <= 0 then cap := DEFAULT_STR_CAP;

  if srcTk = tyChar then
  begin
    xtensa_movi(reg_xtensa_a8, 1);
    xtensa_s32i(reg_xtensa_a8, reg_xtensa_a4, 0);   { len = 1 }
    xtensa_movi(reg_xtensa_a8, 0);
    xtensa_s32i(reg_xtensa_a8, reg_xtensa_a4, 4);   { high half of the length }
    xtensa_s8i(reg_xtensa_a5, reg_xtensa_a4, 8);    { the char }
    Exit;
  end;

  if srcTk = tyAnsiString then
    { nil handle -> empty, else len := [src-8] and chars start AT src. }
    EmitAsmXtensa(['movi a6, 0', 'movi a8, 0', 'beq a5, a8, .fs',
                   'addi a8, a5, -8', 'l32i a6, a8, 0', '.fs:'])
  else
  begin
    xtensa_l32i(reg_xtensa_a6, reg_xtensa_a5, 0);   { frozen/literal: len = [src] }
    xtensa_addi(reg_xtensa_a5, reg_xtensa_a5, 8);   { chars = src+8 }
  end;

  { Truncating `string[N]` assignment: clamp the length to the slot capacity
    before publishing/copying — without this the copy overruns the buffer
    (bug-pascal-shortstring-no-truncation-buffer-overrun). }
  xtensa_movi(reg_xtensa_a8, cap);
  EmitAsmXtensa(['bge a8, a6, .tk', 'mov a6, a8', '.tk:']);

  xtensa_s32i(reg_xtensa_a6, reg_xtensa_a4, 0);     { publish the length }
  xtensa_movi(reg_xtensa_a8, 0);
  xtensa_s32i(reg_xtensa_a8, reg_xtensa_a4, 4);
  xtensa_addi(reg_xtensa_a4, reg_xtensa_a4, 8);     { dst chars }
  { byte-copy loop: a4=dst, a5=src, a6=cnt, a8 scratch }
  EmitAsmXtensa(['.fc:', 'movi a8, 0', 'beq a6, a8, .fd',
                 'l8ui a8, a5, 0', 's8i a8, a4, 0',
                 'addi a5, a5, 1', 'addi a4, a4, 1', 'addi a6, a6, -1',
                 'j .fc', '.fd:']);
end;

procedure EmitFrozenStoreXtensa(si, valNode: Integer);
{ `f := 'hello'` where f is a `string[N]` SYMBOL. Xtensa had no frozen store at
  all, so the buffer was never written and every later read saw length 0
  (bug-frozen-string-unsupported-riscv32-xtensa). Now just the slot-addressed
  front end of EmitFrozenCopyXtensa. }
begin
  IREmitNodeXtensa(valNode);                    { a2 = source }
  xtensa_mov(reg_xtensa_a5, reg_xtensa_a2);     { a5 = src }
  EmitSlotAddrXtensa(reg_xtensa_a4, si);        { a4 = dst buffer }
  EmitFrozenCopyXtensa(IntToTypeKind(IRTk[valNode]), SymStrCap[si]);
end;

procedure EmitStrHandleForStoreXtensa(valNode: Integer);
{ Materialise in a2 the MANAGED HANDLE to publish into an ansistring
  destination, carrying the +1 reference that destination is about to own.
  Four source shapes, and only the LAST of them is already a handle:

    IR_CONST_STR  a literal      -> PXXStrFromLit(len, rodata chars)
    tyChar        a character    -> PXXStrFromLit(1, &spilled char)
    frozen        a string[N]    -> PXXStrFromLit([buf], buf+8)
    otherwise     a handle       -> IncRef, unless the value is a FRESH result
                                    (a concat or a function return) which
                                    already carries its own +1.

  Lifted out of IR_STORE_SYM so IR_STORE_MEM can use the same four rows. It had
  them inline and IR_STORE_MEM had NONE of them: a store through an address just
  wrote the raw source word into the slot, so `r.f := 'lit'` put the address of
  the rodata literal into a managed field. `r.f := s` and `r.f := s + 'x'`
  happened to be right — the raw word IS a handle in those two shapes — which is
  exactly what hid it.
  bug-a-xtensa-cannot-read-a-managed-string-out-of-a-record-field-or-array-element }
var sVal: AnsiString; j: Integer;
begin
  if IRKind[valNode] = IR_CONST_STR then
  begin
    sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
    j := InternStr(sVal);
    EmitLoadConstXtensa(reg_xtensa_a2, Strs[j].Len);          { len }
    EmitLoadDataRefXtensa(reg_xtensa_a3, Strs[j].Offset + 8); { src }
    EmitStrFromLitXtensa;                                     { a2 = handle }
  end
  else if IntToTypeKind(IRTk[valNode]) = tyChar then
  begin
    IREmitNodeXtensa(valNode);                  { a2 = char code }
    XtensaPushA2;                               { spill char to the frame }
    { a3 = address of the spilled char slot. }
    if XtensaABI = XTENSA_ABI_WINDOWED then
      xtensa_addi(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth - 4)
    else
      xtensa_addi(reg_xtensa_a3, reg_xtensa_sp, 0);
    EmitLoadConstXtensa(reg_xtensa_a2, 1);      { len 1 }
    EmitStrFromLitXtensa;                       { a2 = handle }
    { drop the char slot }
    if XtensaABI = XTENSA_ABI_WINDOWED then Dec(XtSpillDepth, 4)
    else xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
  end
  else if TypeIsFrozenString(IntToTypeKind(IRTk[valNode])) then
  begin
    IREmitNodeXtensa(valNode);                  { a2 = inline buffer addr }
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_a2, 0); { len = [buf] }
    xtensa_addi(reg_xtensa_a3, reg_xtensa_a2, 8); { src = buf+8 }
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);     { len }
    EmitStrFromLitXtensa;
  end
  else
  begin
    IREmitNodeXtensa(valNode);                  { a2 = source handle }
    if not (((IRKind[valNode] = IR_BINOP) and (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
            ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
    begin
      XtensaPushA2;                             { save handle }
      EmitStrRefCallXtensa('PXXStrIncRef');
      XtensaPopA2;                              { restore handle }
    end;
  end;
end;

{ ===== 64-bit (Int64/UInt64) value model: a2:a3 = lo:hi register pair =====
  True 8-byte values live in a2(low):a3(high) in flight, are loaded/stored as two
  words, and have their own arithmetic/shift/compare sequences. Xtensa has no
  condition flags (like riscv/arm), so carries/borrows are computed via the
  unsigned branches bgeu/bltu. Mirrors the riscv32 a0:a1 / arm32 r0:r1 models. A
  32-bit source widens into a3 (sign/zero-ext). Scratch: a4:a5 = popped left
  operand, a6/a8..a14 = temporaries (a7 is the windowed frame pointer, a15 the
  Call0 frame pointer — both avoided). The MSB of a word is extracted with `srl`
  after presetting SAR=31 (no EXTUI needed). }

function Is64BitXtensa(tk: TTypeKind): Boolean;
begin
  { Double occupies an a2:a3 pair / 8-byte slot, same shape as Int64 — the
    value-model paths (const/load/store) treat it as 64-bit. Float arithmetic is
    dispatched separately (IsFloatXtensa, checked first). }
  Result := (tk = tyInt64) or (tk = tyUInt64) or (tk = tyDouble);
end;

function IsFloatXtensa(tk: TTypeKind): Boolean;
begin
  Result := (tk = tySingle) or (tk = tyDouble);
end;

procedure EmitLoadConst64Xtensa(v: Int64);
begin
  EmitLoadConstXtensa(reg_xtensa_a2, Integer(v and $FFFFFFFF));
  EmitLoadConstXtensa(reg_xtensa_a3, Integer((v shr 32) and $FFFFFFFF));
end;

procedure EmitSlotAddr64Xtensa(rd, idx: Integer);
{ rd = address of an 8-byte slot (global abs / frame-relative; ref forwarded). }
begin
  if Syms[idx].Kind = skGlobal then
    EmitLoadGlobAddrXtensa(rd, Syms[idx].Offset)
  else
  begin
    EmitFrameAddrXtensa(rd, Syms[idx].Offset);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      xtensa_l32i(rd, rd, 0);
  end;
end;

procedure EmitLoadVar64Xtensa(idx: Integer);
begin
  EmitSlotAddr64Xtensa(reg_xtensa_a8, idx);
  xtensa_l32i(reg_xtensa_a2, reg_xtensa_a8, 0);   { lo }
  xtensa_l32i(reg_xtensa_a3, reg_xtensa_a8, 4);   { hi }
end;

procedure EmitStoreVar64Xtensa(idx: Integer);
begin
  EmitSlotAddr64Xtensa(reg_xtensa_a8, idx);       { value in a2:a3; addr in a8 }
  xtensa_s32i(reg_xtensa_a2, reg_xtensa_a8, 0);   { lo }
  xtensa_s32i(reg_xtensa_a3, reg_xtensa_a8, 4);   { hi }
end;

procedure EmitNode64Xtensa(node: Integer);
{ Emit node; guarantee its full 64-bit value sits in a2:a3, widening a 32-bit
  source (sign-extend signed, zero-extend unsigned) into a3. }
var ntk: TTypeKind;
begin
  IREmitNodeXtensa(node);
  ntk := IntToTypeKind(IRTk[node]);
  if not Is64BitXtensa(ntk) then
  begin
    if TypeSigned(ntk) then
      { a3 := (a2 < 0) ? -1 : 0 }
      EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .pos', 'movi a3, -1', '.pos:'])
    else
      xtensa_movi(reg_xtensa_a3, 0);
  end;
end;

procedure EmitUDivMod64Xtensa(wantMod: Boolean);
{ Unsigned 64-bit divide. Pre: dividend in a4:a5 (lo:hi), divisor in a2:a3.
  Restoring binary long division, 64 iterations MSB-first: the dividend (a4:a5)
  doubles as the quotient register, the remainder builds in a6:a8. SAR is preset
  to 31 so `srl` extracts a word's MSB. Post: result (quotient, or remainder when
  wantMod) in a2:a3. Clobbers a4,a5,a6,a8,a9,a10,a11,a12. }
begin
  EmitAsmXtensa([
    'movi a10, 31',
    'ssr a10',              { SAR = 31, so `srl x, y` = y >> 31 = MSB(y) }
    'movi a6, 0',           { R.lo }
    'movi a8, 0',           { R.hi }
    'movi a9, 64',          { count }
    'movi a11, 0',          { zero (loop test) }
    '.loop:',
    { shift {R.hi:R.lo:NQ.hi:NQ.lo} left by 1, MSB first }
    'srl a10, a4',          { NQ.lo top bit }
    'add a4, a4, a4',       { NQ.lo <<= 1 }
    'srl a12, a5',          { NQ.hi top bit }
    'add a5, a5, a5',       { NQ.hi <<= 1 }
    'or a5, a5, a10',       { NQ.hi |= old NQ.lo top }
    'srl a10, a6',          { R.lo top bit }
    'add a6, a6, a6',       { R.lo <<= 1 }
    'or a6, a6, a12',       { R.lo |= old NQ.hi top }
    'add a8, a8, a8',       { R.hi <<= 1 }
    'or a8, a8, a10',       { R.hi |= old R.lo top }
    { if R (a8:a6) >= divisor (a3:a2) unsigned: subtract, set quotient bit }
    'bltu a8, a3, .nosub',  { R.hi < D.hi }
    'bne a8, a3, .sub',     { R.hi > D.hi }
    'bltu a6, a2, .nosub',  { R.hi == D.hi and R.lo < D.lo }
    '.sub:',
    'movi a12, 0',
    'bgeu a6, a2, .nb',     { borrow }
    'movi a12, 1',
    '.nb:',
    'sub a6, a6, a2',       { R.lo -= D.lo }
    'sub a8, a8, a3',       { R.hi -= D.hi }
    'sub a8, a8, a12',      { R.hi -= borrow }
    'movi a12, 1',
    'or a4, a4, a12',       { quotient bit }
    '.nosub:',
    'addi a9, a9, -1',
    'bne a9, a11, .loop'
  ]);
  if wantMod then
  begin
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a6);
    xtensa_mov(reg_xtensa_a3, reg_xtensa_a8);
  end
  else
  begin
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);
    xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);
  end;
end;

procedure EmitIDivMod64Xtensa(wantMod: Boolean);
{ Signed 64-bit divide/mod. Truncated: quotient sign = dividend xor divisor,
  remainder takes the dividend's sign. Operands (divisor a2:a3, dividend a4:a5)
  are made non-negative in place, the unsigned core runs, then the sign is
  applied. Flags live in a14 (the unsigned core does not touch a14). }
begin
  EmitAsmXtensa([
    'movi a14, 0',          { flags: bit0 negate-quotient, bit1 negate-remainder }
    { divisor sign (a3 = D.hi) }
    'movi a13, 0',
    'bge a3, a13, .dpos',
    'movi a12, 0',          { negate divisor a2:a3 }
    'beq a2, a13, .db0',
    'movi a12, 1',          { borrow if lo <> 0 }
    '.db0:',
    'sub a2, a13, a2',
    'sub a3, a13, a3',
    'sub a3, a3, a12',
    'movi a12, 1',
    'xor a14, a14, a12',
    '.dpos:',
    { dividend sign (a5 = N.hi) }
    'movi a13, 0',
    'bge a5, a13, .npos',
    'movi a12, 0',          { negate dividend a4:a5 }
    'beq a4, a13, .nb0',
    'movi a12, 1',
    '.nb0:',
    'sub a4, a13, a4',
    'sub a5, a13, a5',
    'sub a5, a5, a12',
    'movi a12, 1',
    'xor a14, a14, a12',
    'movi a12, 2',
    'or a14, a14, a12',
    '.npos:'
  ]);
  EmitUDivMod64Xtensa(wantMod);   { result in a2:a3; a14 preserved }
  if wantMod then
    EmitAsmXtensa(['movi a12, 2', 'and a12, a14, a12'])
  else
    EmitAsmXtensa(['movi a12, 1', 'and a12, a14, a12']);
  EmitAsmXtensa([
    'movi a13, 0',
    'beq a12, a13, .done',
    'movi a12, 0',          { negate result a2:a3 (a13 = 0) }
    'beq a2, a13, .rb0',
    'movi a12, 1',
    '.rb0:',
    'sub a2, a13, a2',
    'sub a3, a13, a3',
    'sub a3, a3, a12',
    '.done:'
  ]);
end;

procedure EmitBinop64Xtensa(left, right, op: Integer; signedOp: Boolean);
{ (left OP right) as a 64-bit op. left spilled to the expr stack, right -> a2:a3,
  left popped into a4:a5. Arithmetic/bit ops leave a2:a3; comparisons leave 0/1
  in a2. }
var hbr: AnsiString;
begin
  EmitNode64Xtensa(left);
  XtensaPush64;
  EmitNode64Xtensa(right);             { right -> a2:a3 }
  XtensaPop64ToA4A5;                    { a4:a5 = left.lo:hi }
  { now a4:a5 = left, a2:a3 = right }

  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    { dividend in a4:a5, divisor in a2:a3 }
    if signedOp then EmitIDivMod64Xtensa(op = Ord(tkMod))
    else EmitUDivMod64Xtensa(op = Ord(tkMod));
  end
  else if op = Ord(tkPlus) then
    EmitAsmXtensa([
      'add a8, a4, a2',     { lo = left.lo + right.lo }
      'movi a9, 0',
      'bgeu a8, a4, .nc',   { carry if lo <u left.lo }
      'movi a9, 1',
      '.nc:',
      'add a3, a5, a3',     { hi = left.hi + right.hi }
      'add a3, a3, a9',     { hi += carry }
      'mov a2, a8' ])
  else if op = Ord(tkMinus) then
    EmitAsmXtensa([
      'movi a9, 0',
      'bgeu a4, a2, .nb',   { borrow if left.lo <u right.lo }
      'movi a9, 1',
      '.nb:',
      'sub a8, a4, a2',     { lo }
      'sub a3, a5, a3',     { hi = left.hi - right.hi }
      'sub a3, a3, a9',     { hi -= borrow }
      'mov a2, a8' ])
  else if op = Ord(tkStar) then
  begin
    { low 64 of (a5:a4) * (a3:a2) }
    EmitAsmXtensa(['mull a8, a4, a2']);          { lo = low(Llo*Rlo) }
    if XtensaSoftMulHigh then
      { high(Llo*Rlo) without MUL32HIGH. Split both operands at 16 and
        recombine, carrying through the mid products; every intermediate fits
        in 32 bits unsigned (worst case (2^16-1)^2 + (2^16-1) < 2^32), so no
        step can overflow and no step needs a second word.

        No EXTUI encoder is needed: SAR is set to 16 ONCE and every `srl`
        below reads it, which is this file's own idiom — see the 64-bit header
        note above ("the MSB of a word is extracted with `srl` after presetting
        SAR=31"). The mask comes from `movi -1` + that same shift because
        movi's imm12 is too narrow to hold $FFFF.

        Scratch is a9..a13 only: a2..a5 and a8 are live across this, and a7/a15
        are the windowed and Call0 frame pointers. }
      EmitAsmXtensa([
        'movi a12, 16', 'ssr a12',                 { SAR := 16, for every srl below }
        'movi a13, -1', 'srl a13, a13',            { a13 = $0000FFFF }
        'and a10, a4, a13',                        { xl }
        'and a11, a2, a13',                        { yl }
        'mull a9, a10, a11', 'srl a9, a9',         { c0   = high16(xl*yl) }
        'srl a12, a2',                             { yh }
        'mull a10, a10, a12', 'add a9, a9, a10',   { mid  = xl*yh + c0 }
        'srl a10, a4',                             { xh }
        'mull a11, a10, a11',                      { xh*yl }
        'and a13, a9, a13', 'add a11, a11, a13',   { mid2 = xh*yl + low16(mid) }
        'srl a11, a11', 'srl a9, a9', 'add a9, a9, a11',
        'mull a10, a10, a12', 'add a9, a9, a10'])  { += xh*yh -> a9 = high(Llo*Rlo) }
    else
      EmitAsmXtensa(['muluh a9, a4, a2']);         { high(Llo*Rlo) }
    EmitAsmXtensa([
      'mull a10, a4, a3',   { low(Llo*Rhi) }
      'mull a11, a5, a2',   { low(Lhi*Rlo) }
      'add a9, a9, a10',
      'add a3, a9, a11',
      'mov a2, a8' ]);
  end
  else if op = Ord(tkAnd) then
    EmitAsmXtensa(['and a2, a4, a2', 'and a3, a5, a3'])
  else if op = Ord(tkOr) then
    EmitAsmXtensa(['or a2, a4, a2', 'or a3, a5, a3'])
  else if op = Ord(tkXor) then
    EmitAsmXtensa(['xor a2, a4, a2', 'xor a3, a5, a3'])
  else if op = Ord(tkShl) then
    { count = a2 (& 63); value = a4:a5 -> a2:a3 }
    EmitAsmXtensa([
      'movi a8, 63',
      'and a8, a2, a8',     { n }
      'movi a9, 32',
      'bgeu a8, a9, .big',
      'movi a10, 0',
      'beq a8, a10, .zero',
      'movi a12, 32',
      'sub a12, a12, a8',   { 32 - n }
      'ssl a8',             { SAR for << n }
      'sll a10, a4',        { lo << n  (final lo) }
      'sll a11, a5',        { hi << n }
      'ssr a12',            { SAR = 32-n }
      'srl a4, a4',         { lo >> (32-n) }
      'or a3, a11, a4',     { final hi }
      'mov a2, a10',        { final lo }
      'j .end',
      '.big:',
      'sub a8, a8, a9',     { n - 32 }
      'ssl a8',
      'sll a3, a4',         { hi = lo << (n-32) }
      'movi a2, 0',
      'j .end',
      '.zero:',
      'mov a2, a4',
      'mov a3, a5',
      '.end:' ])
  else if op = Ord(tkIdent) then   { 'shr' parses as ident; logical on Int64/UInt64 }
    EmitAsmXtensa([
      'movi a8, 63',
      'and a8, a2, a8',     { n }
      'movi a9, 32',
      'bgeu a8, a9, .big',
      'movi a10, 0',
      'beq a8, a10, .zero',
      'movi a12, 32',
      'sub a12, a12, a8',   { 32 - n }
      'ssr a8',             { SAR = n }
      'srl a10, a4',        { lo >> n }
      'srl a3, a5',         { hi >> n  (final hi) }
      'ssl a12',            { SAR for << (32-n) }
      'sll a11, a5',        { hi << (32-n) }
      'or a2, a10, a11',    { final lo }
      'j .end',
      '.big:',
      'sub a8, a8, a9',     { n - 32 }
      'ssr a8',
      'srl a2, a5',         { lo = hi >> (n-32) }
      'movi a3, 0',
      'j .end',
      '.zero:',
      'mov a2, a4',
      'mov a3, a5',
      '.end:' ])
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    EmitAsmXtensa([
      'movi a8, 0',
      'bne a4, a2, .ne',    { lo differ -> not equal }
      'bne a5, a3, .ne',    { hi differ -> not equal }
      'movi a8, 1',
      '.ne:',
      'mov a2, a8' ]);
    if op = Ord(tkNeq) then
      EmitAsmXtensa(['movi a8, 1', 'xor a2, a2, a8']);
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkGe)) then
  begin
    { a2 = (left < right): hi compare (signed/unsigned) then unsigned lo tiebreak }
    if signedOp then hbr := 'blt' else hbr := 'bltu';
    EmitAsmXtensa([
      'movi a8, 1',
      hbr + ' a5, a3, .lt',  { left.hi < right.hi }
      'bne a5, a3, .lz',     { hi differ but not < -> 0 }
      'bltu a4, a2, .lt',    { hi equal, lo unsigned < }
      '.lz:',
      'movi a8, 0',
      '.lt:',
      'mov a2, a8' ]);
    if op = Ord(tkGe) then
      EmitAsmXtensa(['movi a8, 1', 'xor a2, a2, a8']);   { ge = not lt }
  end
  else if (op = Ord(tkGt)) or (op = Ord(tkLe)) then
  begin
    { a2 = (left > right) = (right < left) }
    if signedOp then hbr := 'blt' else hbr := 'bltu';
    EmitAsmXtensa([
      'movi a8, 1',
      hbr + ' a3, a5, .gt',  { right.hi < left.hi }
      'bne a3, a5, .gz',
      'bltu a2, a4, .gt',    { hi equal, right.lo unsigned < left.lo }
      '.gz:',
      'movi a8, 0',
      '.gt:',
      'mov a2, a8' ]);
    if op = Ord(tkLe) then
      EmitAsmXtensa(['movi a8, 1', 'xor a2, a2, a8']);   { le = not gt }
  end
  else
    Error('target xtensa: 64-bit binop operator not yet supported');
end;

procedure EmitFloatUnaryCallXtensa(const nm: AnsiString; srcDouble, dstDouble: Boolean);
{ Argument already in a2 (single/int) or a2:a3 (double). Call the kernel and
  leave its result in a2 (single/int) or a2:a3 (double). ABI-aware. }
var procIdx: Integer;
begin
  procIdx := FindProc(nm);
  if procIdx < 0 then Error(SoftFloatMissing(nm));
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
    if srcDouble then xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
    if dstDouble then xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
  end
  else
    EmitCallProc(procIdx);   { Call0: args already a2(:a3); result a2(:a3) }
end;

procedure EmitFloatConvXtensa(srcTk, dstTk: TTypeKind);
{ Repack value (a2 / a2:a3) from one float width to the other, in place. }
begin
  if srcTk = dstTk then Exit;
  if (srcTk = tySingle) and (dstTk = tyDouble) then
    EmitFloatUnaryCallXtensa('__pxx_s2d', False, True)
  else if (srcTk = tyDouble) and (dstTk = tySingle) then
    EmitFloatUnaryCallXtensa('__pxx_d2s', True, False)
  else
    Error('target xtensa: unsupported float-to-float conversion');
end;

procedure EmitFloatOperandXtensa(node: Integer; wantTk: TTypeKind);
{ Emit node and coerce its value to wantTk (a float kind) in a2 / a2:a3. }
var ntk: TTypeKind;
begin
  ntk := IntToTypeKind(IRTk[node]);
  if IsFloatXtensa(ntk) then
  begin
    if ntk = tyDouble then EmitNode64Xtensa(node) else IREmitNodeXtensa(node);
    EmitFloatConvXtensa(ntk, wantTk);
  end
  else
  begin
    if (ntk = tyInt64) or (ntk = tyUInt64) then
    begin
      { 64-bit int -> float. Was refused outright, which made `d := q` with
        q: Int64 a compile error on the one target that could not say why —
        and it is reached by ordinary code, not just an explicit cast: it is
        what every `{$ifndef PXX_ESP}` body in builtinheap hits first once the
        IDF profile stops pretending xtensa is bare metal.
        EmitNode64Xtensa gives the pair in a2:a3 and the kernels take it there,
        so this is the riscv32 arm with xtensa's register names.
        bug-a-xtensa-cannot-lower-an-int64-to-float-conversion }
      EmitNode64Xtensa(node);          { a2:a3 = 64-bit int }
      if ntk = tyUInt64 then EmitFloatUnaryCallXtensa('__pxx_ul2d', True, True)
      else EmitFloatUnaryCallXtensa('__pxx_l2d', True, True);
      EmitFloatConvXtensa(tyDouble, wantTk);
      Exit;
    end;
    if (ntk = tyUInt32) or (ntk = tyNativeUInt) then
    begin
      { UNSIGNED 32-bit: __pxx_i2s/i2d read a2 as SIGNED, so a Cardinal >= 2^31
        converted NEGATIVE — `(double)4294967295u` answered -1. Zero-extend into
        the 64-bit pair and reuse the proven unsigned kernel rather than adding
        a u2d. a3 is cleared AFTER the node emits, because emitting it may
        clobber a3.

        The sibling of the arm above and found with it: riscv32 fixed exactly
        this in bug-c-int64-to-double-cast-truncates-on-32bit and xtensa was
        never given the same treatment, so it was silently wrong here while
        merely refusing above. Silent beats loud to the wrong answer, which is
        why it goes in the same change. }
      IREmitNodeXtensa(node);          { a2 = value }
      xtensa_movi(reg_xtensa_a3, 0);   { a3 = 0 (zero-extend) }
      EmitFloatUnaryCallXtensa('__pxx_ul2d', True, True);
      EmitFloatConvXtensa(tyDouble, wantTk);
      Exit;
    end;
    IREmitNodeXtensa(node);            { a2 = 32-bit int }
    if wantTk = tySingle then EmitFloatUnaryCallXtensa('__pxx_i2s', False, False)
    else EmitFloatUnaryCallXtensa('__pxx_i2d', False, True);
  end;
end;

procedure EmitFloatCmpMapXtensa(op: Integer);
{ Map a soft-float compare code in a2 (-1/0/1, or 2 for NaN/unordered) to a
  Boolean 0/1 in a2. NaN-correct: only Eq/Neq/Lt/Le/Gt/Ge as defined for IEEE
  (unordered makes every relation false except <>). Uses a8/a9/a10 scratch. }
begin
  if op = Ord(tkEq) then
    EmitAsmXtensa(['movi a9, 0', 'movi a8, 0', 'bne a2, a9, .e', 'movi a8, 1', '.e:', 'mov a2, a8'])
  else if op = Ord(tkNeq) then
    EmitAsmXtensa(['movi a9, 0', 'movi a8, 1', 'bne a2, a9, .e', 'movi a8, 0', '.e:', 'mov a2, a8'])
  else if op = Ord(tkLt) then
    EmitAsmXtensa(['movi a9, 0', 'movi a8, 1', 'blt a2, a9, .e', 'movi a8, 0', '.e:', 'mov a2, a8'])
  else if op = Ord(tkLe) then
    EmitAsmXtensa(['movi a10, 1', 'movi a8, 1', 'blt a2, a10, .e', 'movi a8, 0', '.e:', 'mov a2, a8'])
  else if op = Ord(tkGt) then
    EmitAsmXtensa(['movi a10, 1', 'movi a8, 0', 'bne a2, a10, .e', 'movi a8, 1', '.e:', 'mov a2, a8'])
  else if op = Ord(tkGe) then
    EmitAsmXtensa(['movi a9, 0', 'movi a10, 2', 'movi a8, 0', 'blt a2, a9, .e', 'bge a2, a10, .e', 'movi a8, 1', '.e:', 'mov a2, a8'])
  else
    Error('target xtensa: unsupported float comparison');
end;

procedure EmitFloatBinopXtensa(node: Integer);
{ Float arithmetic + comparison via the soft-float kernels (both widths soft;
  HW single FPU is a follow-up). Arithmetic result lands in a2 / a2:a3; a
  comparison lands as a Boolean 0/1 in a2. }
var left, right, op, procIdx, argBase, nArgs, i: Integer; ltk, rtk, opTk: TTypeKind;
    isDouble, isCmp: Boolean; nm: AnsiString;
begin
  left := IRA[node]; right := IRB[node]; op := IRC[node];
  ltk := IntToTypeKind(IRTk[left]); rtk := IntToTypeKind(IRTk[right]);
  { ...and the RESULT type decides when the operands do not: an ordinal/ordinal
    `/` assigned to a Double is computed at double depth, because that is the
    depth the program asked for (user, 2026-08-11,
    decide-esp-single-depth-division-into-a-declared-double). Comparisons are
    unaffected — their result is tyBoolean, so the operand rule still decides. }
  isDouble := (ltk = tyDouble) or (rtk = tyDouble) or
             (IntToTypeKind(IRTk[node]) = tyDouble);
  if isDouble then opTk := tyDouble else opTk := tySingle;
  isCmp := (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
           (op = Ord(tkGt)) or (op = Ord(tkLe)) or (op = Ord(tkGe));

  { Hardware single FPU path (--xtensa-fpu, ESP32/-S3): single +,-,* via
    add.s/sub.s/mul.s. Single / and comparisons stay soft (no HW single divide /
    no FP-compare-to-AR path wired). Double normally stays soft, BUT under
    {$FASTDOUBLES ON} Double +,-,* also takes this path (operands coerced to
    single via d2s, the result repacked to double via s2d) — lossy single
    precision, traded for speed. }
  if XtensaHasFpu and ((op = Ord(tkPlus)) or (op = Ord(tkMinus)) or (op = Ord(tkStar))) and
     ((not isDouble) or XtensaFastDoubles) then
  begin
    EmitFloatOperandXtensa(left, tySingle);      { double operand -> single (d2s) }
    XtensaPushA2;
    EmitFloatOperandXtensa(right, tySingle);      { a2 = right bits }
    XtensaPopA3;                                   { a3 = left bits }
    xtensa_wfr(0, reg_xtensa_a3);                  { f0 = left }
    xtensa_wfr(1, reg_xtensa_a2);                  { f1 = right }
    if op = Ord(tkPlus) then xtensa_add_s(0, 0, 1)
    else if op = Ord(tkMinus) then xtensa_sub_s(0, 0, 1)
    else xtensa_mul_s(0, 0, 1);
    xtensa_rfr(reg_xtensa_a2, 0);                  { a2 = single result }
    if isDouble then EmitFloatConvXtensa(tySingle, tyDouble);  { s2d -> a2:a3 }
    Exit;
  end;

  argBase := XtSpillDepth;
  EmitFloatOperandXtensa(left, opTk);
  XtensaPushA2;
  if isDouble then begin xtensa_mov(reg_xtensa_a2, reg_xtensa_a3); XtensaPushA2; end;
  EmitFloatOperandXtensa(right, opTk);
  XtensaPushA2;
  if isDouble then begin xtensa_mov(reg_xtensa_a2, reg_xtensa_a3); XtensaPushA2; end;
  if isDouble then nArgs := 4 else nArgs := 2;

  { Load outgoing argument registers (mirrors the generic IR_CALL marshalling). }
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    for i := 0 to nArgs - 1 do
      xtensa_l32i(reg_xtensa_a10 + i, reg_xtensa_sp, argBase + i * 4);
    XtSpillDepth := argBase;
  end
  else
  begin
    for i := 0 to nArgs - 1 do
      xtensa_l32i(reg_xtensa_a2 + i, reg_xtensa_sp, (nArgs - 1 - i) * 4);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
  end;

  if isDouble then nm := '__pxx_d' else nm := '__pxx_s';
  if op = Ord(tkPlus) then nm := nm + 'add'
  else if op = Ord(tkMinus) then nm := nm + 'sub'
  else if op = Ord(tkStar) then nm := nm + 'mul'
  else if op = Ord(tkSlash) then nm := nm + 'div'
  else if isCmp then nm := nm + 'cmp'
  else begin Error('target xtensa: unsupported float operator'); Exit; end;

  procIdx := FindProc(nm);
  if procIdx < 0 then Error(SoftFloatMissing(nm));
  EmitCallProc(procIdx);
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
    if isDouble and not isCmp then xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
  end;

  if isCmp then EmitFloatCmpMapXtensa(op);
end;

{ ---- Variant support (bug-a-xtensa-codegen-has-no-variant-support) ---------
  xtensa was the LAST backend with no IR_VAR_STORE / IR_VAR_BOX / IR_VAR_BINOP
  arm, so `var v: Variant; v := 1;` did not compile at all here.

  Modelled on the riscv32 arms (bug-a-riscv32-codegen-has-no-variant-support,
  2026-08-27) — the 32-bit peer with the same 16-byte layout: tag at +0, a zero
  word at +4, an 8-byte payload at +8.

  THREE things do not carry over from that template, all xtensa-only:

  - riscv32 preserves a register across a helper call by moving sp. That is
    wrong here: under the WINDOWED ABI sp must stay put, or the window spill
    area at [sp-16] desyncs (see XtensaPushA2). Every save below therefore goes
    through XtensaPush*/XtensaPop*, which are already correct on BOTH ABIs.
  - xtensa has no shift-right-arithmetic-IMMEDIATE, so sign-extending a 4-byte
    payload into the high word uses the branch idiom EmitNode64Xtensa already
    uses for the identical question, not an srai.
  - the write dispatch the riscv32 fix also needed has NO counterpart here.
    xtensa's IR_WRITE is `{ Bare-metal: write/writeln does nothing. }`, so there
    is no PXXWriteVariant call site to add: `writeln(v)` compiles and emits
    nothing, exactly as `writeln` of any other type does on this backend. }

function XtensaHelperProc(const name: AnsiString): Integer;
{ FindProc + the "not found" Error, which every helper call site below wants
  and which is worth exactly one copy. }
begin
  Result := FindProc(name);
  if Result < 0 then Error('compiler error: ' + name + ' not found');
end;

procedure EmitXtensaHelperCall(procIdx, nArgs: Integer);
{ Call a runtime helper whose arguments are ALREADY in a2..a(1+nArgs) -- the
  Call0 argument registers, in order. Under the windowed ABI they must be
  copied up to a10.., which is what call8 rotates into the callee's a2..,
  and the result comes back in a10.

  One routine rather than the dance open-coded at each write case below: they
  are all the same decision, and repeating it ten times is how one of them ends
  up windowed-wrong (devdocs/dev/normalise-dont-special-case.md). }
var k: Integer;
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    for k := 0 to nArgs - 1 do
      xtensa_mov(reg_xtensa_a10 + k, reg_xtensa_a2 + k);
  EmitCallProc(procIdx);
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
end;

procedure EmitVarHelperCallXtensa(const name: AnsiString);
{ a2 = variant slot address (the helper's only argument), and a2 still holds it
  on return — every caller below keeps using the slot afterwards.

  The argument/return ABI dance is EmitStrRefCallXtensa's, reused rather than
  re-spelled so the two cannot drift; the preserve is layered on top. FindProc
  is checked here as well so a missing VARIANT helper names itself — the shared
  path's message says "string refcount helper", which would be a lie here. }
var procIdx: Integer;
begin
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: variant helper ' + name + ' not found');
  XtensaPushA2;
  EmitStrRefCallXtensa(name);
  XtensaPopA2;
end;

procedure EmitVariantPayloadXtensa(valNode: Integer; tk: TTypeKind);
{ Emit the payload for a boxing store and leave it pushed as 8 bytes, lo word
  first. Always 8 wide even for a 4-byte payload, so the fill's shape does not
  depend on the payload size and the expression stack stays 8-aligned. }
begin
  if (tk = tyString) or (tk = tyAnsiString) then
  begin
    if tk = tyString then
      EmitAnsiStringFromNodeXtensa(valNode)      { a2 = new handle (owned) }
    else
    begin
      IREmitNodeXtensa(valNode);                 { a2 = handle }
      { A CALL result / concat BINOP is already OWNED (+1) — retaining again
        leaks one handle per boxed call result. Same test as every other
        backend's; bug-a-runtime-variant-heap-grows-unbounded. }
      if not (((IRKind[valNode] = IR_BINOP) and
               (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
              ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
      begin
        XtensaPushA2;                            { save handle }
        EmitStrRefCallXtensa('PXXStrIncRef');
        XtensaPopA2;                             { restore handle }
      end;
    end;
    xtensa_movi(reg_xtensa_a3, 0);               { high word of a handle payload }
    XtensaPush64;
  end
  else if TypeIsFloat(tk) then
  begin
    { VT_DOUBLE's payload is 8 bytes of IEEE-754 DOUBLE bits whatever the source
      width, and the ESP parts have no usable double FPU — EmitFloatOperandXtensa
      is the one routine that both widens a Single and materialises an integer
      source, and it leaves the bits in a2:a3. }
    EmitFloatOperandXtensa(valNode, tyDouble);
    XtensaPush64;
  end
  else if Is64BitXtensa(tk) then
  begin
    { An Int64 payload must reach the slot WHOLE: EmitNode64Xtensa guarantees
      the full value in a2:a3, widening a narrow source in place. The 32-bit
      twins got this wrong once —
      bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32. }
    EmitNode64Xtensa(valNode);
    XtensaPush64;
  end
  else
  begin
    IREmitNodeXtensa(valNode);                   { a2 = scalar }
    xtensa_movi(reg_xtensa_a3, 0);               { defined, but the fill recomputes it }
    XtensaPush64;
  end;
end;

procedure EmitVariantFillXtensa(tag: Integer; payloadTk: TTypeKind);
{ a2 = variant slot address, payload pushed by EmitVariantPayloadXtensa.
  Clears the old value, stores tag + payload, pops, leaves the slot addr in a2.

  The HIGH word is chosen from the payload's TYPE, not from the tag: a 4-byte
  signed payload sign-extends and an unsigned one zero-fills, because
  tyNativeInt maps to VT_INT64 and a negative NativeInt zero-filled reads as a
  huge unsigned. See EmitVariantFillArm32 for the incident. }
begin
  EmitVarHelperCallXtensa('PXXVarClear');        { a2 preserved across the call }
  EmitLoadConstXtensa(reg_xtensa_a8, tag);
  xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 0);
  xtensa_movi(reg_xtensa_a8, 0);
  xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 4);
  XtensaPop64ToA4A5;                             { a4:a5 = payload lo:hi }
  xtensa_s32i(reg_xtensa_a4, reg_xtensa_a2, 8);
  if TypeIsFloat(payloadTk) or Is64BitXtensa(payloadTk) then
    xtensa_s32i(reg_xtensa_a5, reg_xtensa_a2, 12)
  else
  begin
    if TypeSigned(payloadTk) then
      { a5 := (a4 < 0) ? -1 : 0 — no srai on this ISA, same shape as
        EmitNode64Xtensa's widening. }
      EmitAsmXtensa(['movi a5, 0', 'bge a4, a5, .vpos', 'movi a5, -1', '.vpos:'])
    else
      xtensa_movi(reg_xtensa_a5, 0);
    xtensa_s32i(reg_xtensa_a5, reg_xtensa_a2, 12);
  end;
end;

procedure EmitLoadVariantAddrXtensa(node: Integer);
{ a2 = address of a variant slot for a value-position variant node. }
begin
  if IRKind[node] = IR_LOAD_SYM then
    EmitSlotAddrXtensa(reg_xtensa_a2, IRA[node])
  else if IRKind[node] = IR_LOAD_MEM then
    IREmitNodeXtensa(IRA[node])
  else
    IREmitNodeXtensa(node);
end;

procedure EmitSysBuiltinXtensa(node, sysNr, nArgs, nZeroTail: Integer; atFdCwd: Boolean);
{ The SysOpen/SysRead/SysWrite/SysClose/SysFchmod family: evaluate the builtin's
  arguments and issue one raw syscall.

  This is ONE routine rather than five hand-written sequences because the five
  differ only in a number and an argument count. arm32 open-codes all five (its
  `svc` blocks run ~90 lines) and that is the shape this file deliberately does
  not copy: the register map below is the part that is easy to get wrong, and
  five copies of it is five chances (devdocs/dev/normalise-dont-special-case.md).

  The map is NOT "argument registers in order" -- it is the IR_SYSCALL arm's map,
  read from arch/xtensa/kernel/entry.S rather than guessed:

    nr -> a2,  arg0 -> a6, arg1 -> a3, arg2 -> a4, arg3 -> a5, arg4 -> a8,
    arg5 -> a9,  result -> a2

  Args travel via XtensaPushA2/XtensaPopA2 for the same reason IR_SYSCALL does:
  it is the one spelling correct under BOTH ABIs (windowed keeps sp fixed and
  walks XtSpillDepth, Call0 moves sp), so popping in reverse avoids open-coding
  two offset schemes.

  `atFdCwd` prepends AT_FDCWD and `nZeroTail` appends zero words, which is how
  SysOpen reaches openat(2). See the SysOpen arm for why it is openat and not
  open on this target. }
var argNode, i, total: Integer;
begin
  total := 0;
  if atFdCwd then
  begin
    EmitLoadConstXtensa(reg_xtensa_a2, -100);        { AT_FDCWD }
    XtensaPushA2; Inc(total);
  end;
  argNode := IRB[node];
  i := 0;
  while (argNode <> -1) and (i < nArgs) do
  begin
    IREmitNodeXtensa(IRA[argNode]);
    XtensaPushA2; Inc(total); Inc(i);
    argNode := IRB[argNode];
  end;
  if i < nArgs then
    Error('target xtensa: a syscall builtin was reached with fewer arguments '
          + 'than its arity -- the parser should have rejected this call');
  for i := 1 to nZeroTail do
  begin
    EmitLoadConstXtensa(reg_xtensa_a2, 0);
    XtensaPushA2; Inc(total);
  end;
  if total > 6 then
    Error('target xtensa: a syscall builtin needs more than six argument words');
  { Reverse: the last pushed is the highest-numbered argument. Nothing maps to
    a2, so the running pop register is never also a target. }
  for i := total - 1 downto 0 do
  begin
    XtensaPopA2;
    case i of
      0: xtensa_mov(reg_xtensa_a6, reg_xtensa_a2);
      1: xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
      2: xtensa_mov(reg_xtensa_a4, reg_xtensa_a2);
      3: xtensa_mov(reg_xtensa_a5, reg_xtensa_a2);
      4: xtensa_mov(reg_xtensa_a8, reg_xtensa_a2);
      5: xtensa_mov(reg_xtensa_a9, reg_xtensa_a2);
    end;
  end;
  EmitLoadConstXtensa(reg_xtensa_a2, sysNr);
  xtensa_syscall;
end;

procedure IREmitNodeXtensa(node: Integer);
var
  left, right, op, si, procIdx, nArgs, i, lo, elemSize, sz, argNode, argBase, valNode, j: Integer;
  itemNode, hi: Integer;   { `x in [consts]` — SPECIAL_IN's item walk }
  isOrd: Boolean;   { managed-string compare: ordered (PXXStrCmp3) vs equality }
  r4: Integer;      { the string-marshalling quad's FOURTH register -- a7 on
                      Call0, a3 under windowed, because a7 is the windowed
                      frame pointer. See XtensaMarshalReg4. }
  argFree: Integer;   { Call0: bytes of argument block to pop AFTER the call
                        (0 = the block was already freed before it) }
  scFrac, scExp: Integer;   { scientific-write format, from SciFormatFor }
  tk: TTypeKind;
  sgn, savedLVW: Boolean;
  sVal: AnsiString;
begin
  case IRKind[node] of
    IR_CONST_INT:
      { The riscv32 case, on the target that matters most: a float constant's
        IVal is the DOUBLE bit pattern whatever its tk says (defs.inc,
        AN_FLOAT_LIT), so a tySingle const must be NARROWED, not truncated --
        Low32 of a double pattern is the low mantissa half. Measured before the
        fix, `const S1: Single = 0.5` read back as bits 0 (want 1056964608) and
        `-1.5` as 0 (want -1077936128): EVERY Single constant on xtensa was
        zero, in pure Pascal, silently.

        Same shape and same fix as ir_codegen_riscv32.inc, for the same reason:
        both are soft-float ILP32 and carry a single as its own 32 bits in the
        first argument register. x86-64/aarch64 carry a single as double bits
        and never needed it; arm32 loads the whole pattern into d0 and converts
        on the way out; i386 goes through the shared MovRaxImm, which is a full
        64-bit immediate. Three backends spell this path three ways and exactly
        two of them truncated.
        bug-c-the-f-suffix-on-a-float-literal-is-ignored }
      if IntToTypeKind(IRTk[node]) = tySingle then
        EmitLoadConstXtensa(reg_xtensa_a2, DoubleBitsToSingleBits(IRIVal[node]))
      else if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
        EmitLoadConst64Xtensa(IRIVal[node])
      else
        EmitLoadConstXtensa(reg_xtensa_a2, Low32(IRIVal[node]));

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefXtensa(reg_xtensa_a2, Strs[si].Offset);
      end;

    IR_CONST_DATA:
      { Absolute data address (sentinel-resolvable), see the x86-64 case. }
      EmitLoadDataRefXtensa(reg_xtensa_a2, Integer(IRIVal[node]));

    IR_VMTADDR:
      { a2 = address of class ci's VMT (the identity stored at [instance+0]).
        Offsets are final at codegen, so the data-ref is direct. }
      EmitLoadDataRefXtensa(reg_xtensa_a2, UClsVMTOffset[IRA[node]]);

    IR_LOAD_SYM:
      { A VARIANT in value position yields its slot ADDRESS, not a load: the
        slot is 16 bytes and every consumer (PXXVarBinOp, a variant-to-variant
        store) takes a pointer. Same rule as riscv32/arm32/i386.
        bug-a-xtensa-codegen-has-no-variant-support }
      if Syms[IRA[node]].TypeKind = tyVariant then
        EmitSlotAddrXtensa(reg_xtensa_a2, IRA[node])
      else if Is64BitXtensa(Syms[IRA[node]].TypeKind) or
              ((Syms[IRA[node]].TypeKind = tyRecord) and not Syms[IRA[node]].IsArray and
               (RecSize(SymTR[IRA[node]].RecId) > 4) and
               (RecSize(SymTR[IRA[node]].RecId) <= 8)) then
        { A 5-8 byte record VALUE needs BOTH words. EmitLoadVar64Xtensa is
          type-agnostic (a raw 8-byte load, already by-ref aware), so it serves a
          record exactly as it serves an Int64. Without this the record fell to
          the 1-word EmitLoadVarXtensa below and silently dropped its high 4
          bytes — one of three spots, all counting 4 bytes where the type is 8.
          arm32 had the identical trio (bug-arm32-record-byvalue-over-4-bytes-abi-gap). }
        EmitLoadVar64Xtensa(IRA[node])
      else
        EmitLoadVarXtensa(IRA[node]);

    IR_STORE_SYM:
      begin
        si := IRA[node];
        if Syms[si].IsArray and (Syms[si].ArrLen = -1) then
        begin
          { Whole DYNAMIC-array assignment (`b := a`). Xtensa was the last
            backend without this arm, so the store fell through to the scalar
            path and published the wrong one of IR_LEA's read/write results;
            `Length(b)` then dereferenced garbage and SEGFAULTED. Same gap
            arm32 and riscv32 each had
            (bug-a-arm32-dynamic-array-assignment-has-no-store-arm).

            It was invisible here rather than absent: test_dynarray_whole_assign
            is the program that asserts it, and it did not COMPILE for xtensa
            until IR_SETLEN_DYN landed in this same commit. A missing op hides
            every bug in the programs it stops from compiling.

            Retain the new handle, publish it, release the old one — element
            aware via the symbol's layout descriptor. Must precede the
            tyAnsiString arm: for `array of string` the symbol's TypeKind names
            the ELEMENT and would wrongly claim the array. }
          IREmitNodeXtensa(IRB[node]);                { a2 = new data pointer }
          { Move semantics: a fresh user-function result already carries the +1
            for this owner; intrinsics (IRA < 0) keep the conservative retain. }
          if not ((IRKind[IRB[node]] = IR_CALL) and (IRA[IRB[node]] >= 0)) then
          begin
            procIdx := FindProc('PXXDynArrayIncRef');
            if procIdx < 0 then Error('compiler error: PXXDynArrayIncRef not found');
            XtensaPushA2;
            if XtensaABI = XTENSA_ABI_WINDOWED then
              xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
            EmitCallProc(procIdx);
            XtensaPopA2;                              { a2 = new handle again }
          end;
          argBase := XtSpillDepth;
          XtensaPushA2;                               { slot 0 = new handle }
          EmitSlotAddrXtensa(reg_xtensa_a5, si);
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            xtensa_l32i(reg_xtensa_a5, reg_xtensa_a5, 0);   { a5 = &caller_slot }
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a5, 0);     { a2 = old handle }
          xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 1));
          xtensa_s32i(reg_xtensa_a3, reg_xtensa_a5, 0);     { publish new }
          EmitLoadDataRefXtensa(reg_xtensa_a3, GetOrAllocSymRTTI(si));
          procIdx := FindProc('PXXDynArrayRelease');
          if procIdx < 0 then Error('compiler error: PXXDynArrayRelease not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
          end;
          EmitCallProc(procIdx);                      { release(old, desc) }
          XtensaPopA2;                                { a2 = new handle (value) }
          Exit;
        end;
        if TypeIsFrozenString(Syms[si].TypeKind) and not Syms[si].IsArray then
        begin
          { `f := 'hello'` where f is string[N]: xtensa had NO frozen store, so
            the buffer was never written and every later read saw length 0. }
          EmitFrozenStoreXtensa(si, IRB[node]);
          Exit;
        end;
        if Syms[si].TypeKind = tyAnsiString then
        begin
          { Managed-string assignment: build the new handle in a2, then publish
            into the slot (DecRef old). Mirrors i386/riscv32. }
          EmitStrHandleForStoreXtensa(IRB[node]);
          { Publish: save new, DecRef the old handle in the slot, then store new.
            The slot address can't be held in a8 across the windowed DecRef call
            (call8 rotates a8-a15 out), so recompute it before the store. }
          XtensaPushA2;                                 { save new handle }
          { a2 = old handle from the slot }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitFrameAddrXtensa(reg_xtensa_a2, Syms[si].Offset);
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { caller slot addr }
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { old handle }
          end
          else
          begin
            EmitSlotAddrXtensa(reg_xtensa_a2, si);
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { old handle }
          end;
          EmitStrRefCallXtensa('PXXStrDecRef');            { DecRef(old) }
          XtensaPopA2;                                     { a2 = new handle }
          { recompute slot addr into a8 (no calls follow) and store }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitFrameAddrXtensa(reg_xtensa_a8, Syms[si].Offset);
            xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);  { caller slot addr }
          end
          else
            EmitSlotAddrXtensa(reg_xtensa_a8, si);          { slot addr }
          xtensa_s32i(reg_xtensa_a2, reg_xtensa_a8, 0);     { slot := new }
          Exit;
        end;
        { Float destination: coerce the RHS to the slot's float width before the
          store. Must precede the Is64Bit branch (a Double slot is Is64Bit but a
          non-double RHS needs conversion, not a raw 64-bit move). }
        if IsFloatXtensa(Syms[IRA[node]].TypeKind) then
        begin
          EmitFloatOperandXtensa(IRB[node], Syms[IRA[node]].TypeKind);
          if Syms[IRA[node]].TypeKind = tyDouble then
            EmitStoreVar64Xtensa(IRA[node])
          else
            EmitStoreVarXtensa(IRA[node]);
          Exit;
        end;
        if Is64BitXtensa(Syms[IRA[node]].TypeKind) then
        begin
          EmitNode64Xtensa(IRB[node]);
          EmitStoreVar64Xtensa(IRA[node]);
        end
        else
        begin
          IREmitNodeXtensa(IRB[node]);
          EmitStoreVarXtensa(IRA[node]);
        end;
      end;

    IR_LEA:
      begin
        si := IRA[node];
        if Syms[si].Kind = skGlobal then
          EmitLoadGlobAddrXtensa(reg_xtensa_a2, Syms[si].Offset)
        else
          EmitFrameAddrXtensa(reg_xtensa_a2, Syms[si].Offset);
        { Slot holds a heap data pointer (handle) that must be loaded in a
          read/index position: a local dynamic array, or an open-array value
          param (the caller passed the handle). SetLength keeps the slot address.
          (No COW / by-ref open arrays yet.) }
        if (Syms[si].IsArray and (Syms[si].ArrLen = -1)) or
           ((Syms[si].Kind = skParam) and Syms[si].IsArray and not Syms[si].IsRef) then
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0)
        { Scalar managed string: read position loads the handle; write position
          keeps the slot address for the store to publish a new handle. }
        else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray and
                not InLValueWrite and
                not ((Syms[si].Kind = skParam) and Syms[si].IsRef) then
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0)
        { Scalar var/out param: the slot holds the forwarded caller address, so its
          lvalue address is [slot], not &slot. Without this deref, forwarding a
          `var` param into another routine's `var` param (or `@op`) yields the
          local slot and the inner write never reaches the caller
          (feature-riscv32-var-param-forwarding, same defect on xtensa). The 64-bit
          slot-addr emitter + load/store paths already deref; this aligns IR_LEA's
          scalar path. Arrays/strings keep their handling above. }
        else if (Syms[si].Kind = skParam) and Syms[si].IsRef and
                not Syms[si].IsArray and (Syms[si].TypeKind <> tyAnsiString) then
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0)
        { THE SHARED CATCH-ALL: a param whose slot holds the ADDRESS of the
          value rather than the value — by-ref anything, a by-ref fixed array,
          a frozen-string param, a by-value Variant (the slot points at the
          caller's 16-byte temp, bug-pascal-byvalue-variant-param).

          `ABIParamSlotHoldsValueAddr` lives in abi.inc precisely so the six
          backends answer this identically, and it was used by x86-64, i386,
          aarch64, arm32 and riscv32 — FIVE of six. Xtensa open-coded only the
          by-value-Variant row of it, so a by-ref ANSISTRING param was left one
          deref short: `Length(var s)` returned a live heap address rendered as
          a decimal number (`varlen=545267744` against the oracle's `5`), and
          `s[1]` indexed through the parameter slot itself.

          The open-coded row is deleted rather than kept beside the call: the
          predicate subsumes it (tyVariant is one of its clauses), and a
          hand-written copy of one row of a shared predicate is exactly what
          makes the missing rows invisible. }
        else if ABIParamSlotHoldsValueAddr(si) then
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
      end;

    IR_SLOTADDR:
      EmitSlotAddrXtensa(reg_xtensa_a2, IRA[node]);   { always the slot address }

    IR_FIELD:
      begin
        IREmitNodeXtensa(IRA[node]);
        if Integer(IRIVal[node]) <> 0 then
        begin
          EmitLoadConstXtensa(reg_xtensa_a3, Integer(IRIVal[node]));
          xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end;
      end;

    IR_INDEX:
      begin
        left := IRA[node];
        right := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);

        IREmitNodeXtensa(left);               { base: handle (read) / slot addr (write) }
        { Managed-string index. THREE base shapes reach here and xtensa handled
          only the write half of one of them:

            a SCALAR managed string   (IR_LEA)  — read: IR_LEA already loaded
              the handle, nothing to do; write: the slot address, needs COW.
            a BY-REF managed param    (IR_LEA, skParam+IsRef) — IR_LEA stops at
              the caller's SLOT ADDRESS (ABIParamSlotHoldsValueAddr supplies
              that deref), so a READ index is still one deref short of the
              handle: `d[1]` on a `var d: AnsiString` read the wrong byte
              (32 where the oracle says 65) while Length(d) and WriteLn(d) were
              both correct — which is what made it look like an index bug rather
              than a base bug.
            a FIELD or ELEMENT        (IR_FIELD / IR_INDEX, stride 1 or 2) —
              `r.f[1]`, `a[i][1]`. The base is the field's SLOT ADDRESS. Read
              gave the wrong byte; WRITE was worse: neither the COW call nor the
              deref ran, so the character store landed in the HANDLE SLOT
              itself and the string read back EMPTY.

          riscv32 has all three (bug-a-riscv32-setlength-on-string-array-element-
          loses-length); arm32 has all three; xtensa had the first one's write
          arm alone. Ported verbatim rather than re-derived. }
        if ((IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString) and
            not Syms[IRA[left]].IsArray) or
           (((IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX)) and
            (IRTk[left] = Ord(tyAnsiString)) and ((elemSize = 1) or (elemSize = 2))) then
        begin
          if InLValueWrite then
          begin
            { clone-if-shared: PXXStrUnique takes the SLOT ADDRESS and returns a
              writable handle, so it serves the scalar and the field/element
              base identically. }
            procIdx := FindProc('PXXStrUnique');
            if procIdx < 0 then Error('compiler error: PXXStrUnique not found');
            if XtensaABI = XTENSA_ABI_WINDOWED then
            begin
              xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
              EmitCallProc(procIdx);
              xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { a2 = unique handle }
            end
            else
              EmitCallProc(procIdx);                       { a2 = unique handle }
          end
          else if (IRKind[left] = IR_LEA) and (Syms[IRA[left]].Kind = skParam) and
                  Syms[IRA[left]].IsRef then
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0)   { &handle -> handle }
          else if (IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX) then
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { slot -> handle }
        end;
        XtensaPushA2;

        { The INDEX expression is a READ even when the whole IR_INDEX is a write
          target (`b[Length(b)] := c`): left set, IR_LEA(b) inside the index
          kept the slot address and Length read garbage — the store landed
          wild. Same reset x86-64 has always done (b355). }
        savedLVW := InLValueWrite;
        InLValueWrite := False;
        IREmitNodeXtensa(right);
        InLValueWrite := savedLVW;
        if lo <> 0 then
        begin
          EmitLoadConstXtensa(reg_xtensa_a3, lo);
          xtensa_sub(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end;

        if (elemSize = 2) or (elemSize = 4) or (elemSize = 8) then
        begin
          xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a2);
          if elemSize >= 4 then
            xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a2);
          if elemSize = 8 then
            xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a2);
        end
        else if elemSize <> 1 then
        begin
          EmitLoadConstXtensa(reg_xtensa_a3, elemSize);
          xtensa_mull(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end;

        XtensaPopA3;
        xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
      end;

    IR_LOAD_MEM:
      begin
        IREmitNodeXtensa(IRA[node]);
        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if (sz = 8) and Is64BitXtensa(tk) then
        begin
          { 64-bit load through memory (Int64/Double field/element): two words
            into a2:a3. Was a single l32i — the HIGH word stayed whatever a3
            last held (typically the index computation's base address), so a
            64-bit `<> 0` test on a null low word took the dereference branch
            and double-faulted (esp32s3 bare-boot total UART silence). Twin of
            the riscv32 IR_LOAD_MEM fix. Hi first: a2 still holds the address. }
          xtensa_l32i(reg_xtensa_a3, reg_xtensa_a2, 4);
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
        end
        else if tk = tyRecord then
        begin
          { A record VALUE loaded through memory only ever means a <=8-byte
            by-value record: IRLowerCallArg wraps a record-RETURNING call (or
            operator result) in IR_LOAD_MEM, and anything over 8 bytes travels
            by pointer. Load both words -- riscv32 carries this identical arm
            with the identical comment, and xtensa was the last backend without
            it (bug-riscv32-byval-record-param-one-word is the same defect one
            target over).

            This is the arm that made `inner(mk)` -- a record-returning function
            called directly as a by-value argument -- print `7 0` on Call0 and
            `7 6` (a stale register) on windowed, while every OTHER shape of the
            same bug was already fixed: a named variable, a 4-byte record, a
            5-byte record, two records in a row, the 5th and 6th parameter
            positions, and forwarding a record parameter onward all passed. The
            producer node is what differs -- the arg reaching the call-arg loop
            is IR_LOAD_MEM, not IR_LOAD_SYM -- which is why widening IR_LOAD_SYM
            did not cover it and why only varying the SHAPE of the repro found
            it (devdocs/dev/root-cause-over-microfix.md). Hi first: a2 still
            holds the address. }
          xtensa_l32i(reg_xtensa_a3, reg_xtensa_a2, 4);
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
        end
        else
          EmitSizedLoadXtensa(reg_xtensa_a2, reg_xtensa_a2, sz, sgn);
      end;

    IR_STORE_DYN:
      begin
        { ARC-correct whole dyn-array store into a slot ADDRESS (record/class
          field or nested sub-array). Ported from riscv32, which ported it from
          x86-64; xtensa was the last backend still taking the bare IR_STORE_MEM
          handle share here, which does not retain.

          That is not a missing optimisation, it is a use-after-free waiting for
          a second owner to go away:

              var m: array of array of Integer; r: array of Integer;
              SetLength(r, 3); r[0] := 7;
              SetLength(m, 2);
              m[0] := r;              { shares r's block WITHOUT retaining }
              SetLength(m, 3, 5);     { releases row 0 -> frees r's block }

          It is also the arm that gates the dyn-array row of xtensa's scope-exit
          release (EmitManagedLocalCleanupForTarget in ir_codegen.inc): releasing
          a local is only safe once EVERY store that publishes a handle retains.
          bug-a-xtensa-scope-exit-releases-one-of-seven-managed-kinds

          Retain the new handle (unless it is a fresh user-function result
          already carrying the +1), publish it into the slot, then element-aware
          release the old one through the node-derived descriptor. }
        IREmitNodeXtensa(IRB[node]);              { a2 = new handle }
        if not ((IRKind[IRB[node]] = IR_CALL) and (IRA[IRB[node]] >= 0)) then
        begin
          procIdx := FindProc('PXXDynArrayIncRef');
          if procIdx < 0 then Error('compiler error: PXXDynArrayIncRef not found');
          XtensaPushA2;
          if XtensaABI = XTENSA_ABI_WINDOWED then
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
          EmitCallProc(procIdx);
          XtensaPopA2;                            { a2 = new handle again }
        end;
        argBase := XtSpillDepth;
        XtensaPushA2;                             { slot 0 = new handle }
        IREmitNodeXtensa(IRA[node]);              { a2 = slot address }
        xtensa_mov(reg_xtensa_a5, reg_xtensa_a2);         { a5 = slot }
        xtensa_l32i(reg_xtensa_a2, reg_xtensa_a5, 0);     { a2 = old handle }
        xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 1));
        xtensa_s32i(reg_xtensa_a3, reg_xtensa_a5, 0);     { publish new }
        EmitLoadDataRefXtensa(reg_xtensa_a3, GetOrAllocNodeDynDesc(node));
        procIdx := FindProc('PXXDynArrayRelease');
        if procIdx < 0 then Error('compiler error: PXXDynArrayRelease not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
          xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
        end;
        EmitCallProc(procIdx);                    { release(old, desc) — nil-safe }
        XtensaPopA2;                              { a2 = new handle (the value) }
      end;

    IR_STORE_MEM:
      begin
        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        { THE TYPED STORES. IR_STORE_SYM has dispatched on the destination TYPE
          since managed strings landed; IR_STORE_MEM — the same store reached
          through an ADDRESS (a record field, an array element, a deref) — had
          none of it and fell straight through to a raw sized store. So the
          three type classes that need more than a word copy were all silently
          wrong through an aggregate, and each failed differently:

            r.f := 'lit'   (managed)  the rodata ADDRESS landed in the field;
                                      Length read [addr-8] = 1936482630
            r.g := 'lit'   (frozen)   the source address landed in the buffer
                                      where [len][chars] belongs
            r.d := i       (float)    the integer bits landed in a Double field
                                      — SIGBUS on the next read

          Every other backend has all three. riscv32 has them adjacent in this
          same node, which is how all three were found by one probe.
          bug-a-xtensa-cannot-read-a-managed-string-out-of-a-record-field-or-array-element }
        if tk = tyAnsiString then
        begin
          { Managed store through an address: build the new handle (with its +1),
            publish it into the slot, then DecRef whatever was there.
            Publish-before-DecRef, so `r.f := r.f` cannot free the live value. }
          EmitStrHandleForStoreXtensa(IRB[node]);
          XtensaPushA2;                              { new handle }
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeXtensa(IRA[node]);               { a2 = slot address }
          InLValueWrite := savedLVW;
          XtensaPopA3;                               { a3 = new handle }
          xtensa_l32i(reg_xtensa_a4, reg_xtensa_a2, 0);   { a4 = old handle }
          xtensa_s32i(reg_xtensa_a3, reg_xtensa_a2, 0);   { [slot] := new }
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);       { a2 = old }
          EmitStrRefCallXtensa('PXXStrDecRef');
          Exit;
        end;
        if tk = tyString then
        begin
          { Frozen `string[N]` store through an address: copy [len][chars] with
            the length clamped to the destination capacity, which the IR carries
            as the node's ival. Same core as the slot-addressed store. }
          IREmitNodeXtensa(IRB[node]);               { a2 = source }
          XtensaPushA2;
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeXtensa(IRA[node]);               { a2 = dest buffer }
          InLValueWrite := savedLVW;
          xtensa_mov(reg_xtensa_a4, reg_xtensa_a2);  { a4 = dst }
          XtensaPopA3;
          xtensa_mov(reg_xtensa_a5, reg_xtensa_a3);  { a5 = src }
          EmitFrozenCopyXtensa(IntToTypeKind(IRTk[IRB[node]]), Integer(IRIVal[node]));
          Exit;
        end;
        if IsFloatXtensa(tk) then
        begin
          { Coerce the RHS to the destination's float width before storing. Must
            precede the Is64Bit branch: a Double destination IS 64-bit, but an
            integer RHS needs int->double conversion, not a raw bit copy. }
          EmitFloatOperandXtensa(IRB[node], tk);
          if tk = tyDouble then
          begin
            XtensaPush64;
            savedLVW := InLValueWrite;
            InLValueWrite := True;
            IREmitNodeXtensa(IRA[node]);             { a2 = dest addr }
            InLValueWrite := savedLVW;
            XtensaPop64ToA4A5;                       { a4:a5 = lo:hi }
            xtensa_s32i(reg_xtensa_a4, reg_xtensa_a2, 0);
            xtensa_s32i(reg_xtensa_a5, reg_xtensa_a2, 4);
          end
          else
          begin
            XtensaPushA2;
            savedLVW := InLValueWrite;
            InLValueWrite := True;
            IREmitNodeXtensa(IRA[node]);             { a2 = dest addr }
            InLValueWrite := savedLVW;
            XtensaPopA3;
            xtensa_s32i(reg_xtensa_a3, reg_xtensa_a2, 0);
          end;
          Exit;
        end;
        if (sz = 8) and Is64BitXtensa(tk) then
        begin
          { 64-bit store through memory: spill both value words across the
            address evaluation, then store the pair. Was single-word — the
            high word of an Int64/Double field/element store was dropped.
            Twin of the riscv32 IR_STORE_MEM fix. }
          EmitNode64Xtensa(IRB[node]);              { a2:a3 = value }
          XtensaPush64;
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeXtensa(IRA[node]);              { a2 = dest addr }
          InLValueWrite := savedLVW;
          XtensaPop64ToA4A5;                        { a4:a5 = value lo:hi }
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_a2, 0);
          xtensa_s32i(reg_xtensa_a5, reg_xtensa_a2, 4);
        end
        else
        begin
          IREmitNodeXtensa(IRB[node]);
          XtensaPushA2;
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeXtensa(IRA[node]);
          InLValueWrite := savedLVW;
          XtensaPopA3;
          EmitSizedStoreXtensa(reg_xtensa_a3, reg_xtensa_a2, sz);
        end;
      end;

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];

        if (IntToTypeKind(IRTk[node]) = tyAnsiString) and (op = Ord(tkPlus)) then
        begin
          { Managed-string concat -> PXXStrConcat(lenA, srcA, srcB, lenB). Operand
            len/src into a4=lenA,a5=srcA,a6=srcB,a7=lenB (a2-a7 survive call8). }
          r4 := XtensaMarshalReg4;
          argBase := XtSpillDepth;
          IREmitNodeXtensa(left);  XtensaPushA2;       { lhs @ argBase }
          IREmitNodeXtensa(right); XtensaPushA2;       { rhs @ argBase+4 }
          { rhs -> srcB(a6)/lenB(a7) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
          if IntToTypeKind(IRTk[right]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a6, reg_xtensa_a8);
            EmitAsmXtensa(['movi ' + XtRegName(r4) + ', 0', 'movi a9, 0',
                           'beq a8, a9, .cb', 'addi a9, a8, -8',
                           'l32i ' + XtRegName(r4) + ', a9, 0', '.cb:']);
          end
          else if TypeIsFrozenString(IntToTypeKind(IRTk[right])) then
          begin
            xtensa_l32i(r4, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a6, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a6, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
            EmitLoadConstXtensa(r4, 1);
          end;
          { lhs -> srcA(a5)/lenA(a4) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
          if IntToTypeKind(IRTk[left]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a8);
            EmitAsmXtensa(['movi a4, 0', 'movi a9, 0', 'beq a8, a9, .ca',
                           'addi a9, a8, -8', 'l32i a4, a9, 0', '.ca:']);
          end
          else if TypeIsFrozenString(IntToTypeKind(IRTk[left])) then
          begin
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a5, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a5, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
            EmitLoadConstXtensa(reg_xtensa_a4, 1);
          end;
          procIdx := FindProc('PXXStrConcat');
          if procIdx < 0 then Error('compiler error: PXXStrConcat not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a4);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a5);
            xtensa_mov(reg_xtensa_a12, reg_xtensa_a6);
            xtensa_mov(reg_xtensa_a13, r4);
            EmitCallProc(procIdx);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          end
          else
          begin
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);   { a2=lenA }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);   { a3=srcA }
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);   { a4=srcB }
            xtensa_mov(reg_xtensa_a5, r4);              { a5=lenB }
            EmitCallProc(procIdx);                           { result a2 }
          end;
          { release fresh tyAnsiString BINOP operand temporaries }
          XtensaPushA2;                                 { slot 2 = result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 3));
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 3));
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 2, 3));   { result }
          XtensaDropSlots(argBase, 3);
          Exit;
        end;

        if (((op = Ord(tkEq)) or (op = Ord(tkNeq)) or
             (op = Ord(tkLt)) or (op = Ord(tkLe)) or
             (op = Ord(tkGt)) or (op = Ord(tkGe))) and
            ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString) or
             TypeIsFrozenString(IntToTypeKind(IRTk[left])) or TypeIsFrozenString(IntToTypeKind(IRTk[right])))) then
        begin
          { Managed-string compare. ONE arm for both equality and ordering,
            differing only in callee and result tail -- not two arms, because
            the ordered form was MISSING here and the whole bug is that a
            second path is the one nobody visits. `<` fell through to the
            integer compare below and compared the two heap HANDLES, so
            'zzz' < 'aaa' answered by allocation order. PXXStrCmp3's own header
            said "the FOUR cross backends had no ordered-string arm at all";
            there were five, and that miscount is why xtensa was never visited.
            The count is now gone from that header rather than corrected.

            Operand decompose (mirrors concat): handle -> len [h-8] (0 if nil)
            + src h; frozen tyString -> len [buf] + src buf+8; char -> len 1 +
            src &slot. Builds a4=lenA, a5=srcA, a6=lenB, a7=srcB (a2-a7 survive
            call8).

            ONE guard for all six operators, and the two-guard version it
            replaces is the bug this arm was written to fix, committed a second
            time inside the fix. The ordered guard accepted a FROZEN string on
            either side; the equality guard did not, above a comment asserting
            "frozen equality already works". It does not. Both sides frozen —
            `b: string[4]` against a literal — fell through to the INTEGER
            compare below and compared the two buffer ADDRESSES, so `b =
            'BBBB'` was false while `b` printed BBBB and Length(b) was 4.

            The false claim is not carelessness, it is a measurement that
            passes for the wrong reason: `'BBBB' = 'BBBB'` really does answer
            true, because two identical literals INTERN TO ONE ADDRESS, so
            address equality and string equality agree. Check frozen equality
            with two literals and it works; check it with a variable and it
            never did. Measured both ways here before this was written.

            riscv32 already carried the fix, with the same root cause in its own
            comment: "Was gated on tyAnsiString only, so frozen = frozen (e.g.
            ParamStr(1) = '--selftest') compared ADDRESSES." Sixth backend
            skipped while its siblings were visited, again — the same shape as
            PXXStrCmp3's own miscount three lines above, which is what makes
            merging the two guards, rather than adding the missing terms beside
            them, the actual fix. Char-vs-string reaches this through the
            tyAnsiString on the other side.

            Slot offsets go through XtensaSlotOff: the hand-written
            `argBase + k` spelling is windowed-only and read a neighbouring
            live slot on Call0, which is why `=` returned a heap handle on the
            default ABI. }
          isOrd := (op = Ord(tkLt)) or (op = Ord(tkLe)) or
                   (op = Ord(tkGt)) or (op = Ord(tkGe));
          r4 := XtensaMarshalReg4;
          argBase := XtSpillDepth;
          IREmitNodeXtensa(left);  XtensaPushA2;       { slot 0 = lhs }
          IREmitNodeXtensa(right); XtensaPushA2;       { slot 1 = rhs }
          { rhs -> lenB(a6)/srcB(a7) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
          if IntToTypeKind(IRTk[right]) = tyAnsiString then
          begin
            xtensa_mov(r4, reg_xtensa_a8);
            EmitAsmXtensa(['movi a6, 0', 'movi a9, 0', 'beq a8, a9, .cb',
                           'addi a9, a8, -8', 'l32i a6, a9, 0', '.cb:']);
          end
          else if TypeIsFrozenString(IntToTypeKind(IRTk[right])) then
          begin
            xtensa_l32i(reg_xtensa_a6, reg_xtensa_a8, 0);
            xtensa_addi(r4, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(r4, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
            EmitLoadConstXtensa(reg_xtensa_a6, 1);
          end;
          { lhs -> lenA(a4)/srcA(a5) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
          if IntToTypeKind(IRTk[left]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a8);
            EmitAsmXtensa(['movi a4, 0', 'movi a9, 0', 'beq a8, a9, .ca',
                           'addi a9, a8, -8', 'l32i a4, a9, 0', '.ca:']);
          end
          else if TypeIsFrozenString(IntToTypeKind(IRTk[left])) then
          begin
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a5, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a5, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
            EmitLoadConstXtensa(reg_xtensa_a4, 1);
          end;
          if isOrd then procIdx := FindProc('PXXStrCmp3')
          else procIdx := FindProc('PXXStrEq');
          if procIdx < 0 then
          begin
            if isOrd then Error('compiler error: PXXStrCmp3 not found')
            else Error('compiler error: PXXStrEq not found');
          end;
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a4);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a5);
            xtensa_mov(reg_xtensa_a12, reg_xtensa_a6);
            xtensa_mov(reg_xtensa_a13, r4);
            EmitCallProc(procIdx);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          end
          else
          begin
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);   { a2=lenA }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);   { a3=srcA }
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);   { a4=lenB }
            xtensa_mov(reg_xtensa_a5, r4);              { a5=srcB }
            EmitCallProc(procIdx);                           { result a2 }
          end;
          { release fresh tyAnsiString BINOP operand temporaries }
          XtensaPushA2;                                 { slot 2 = result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 3));
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 3));
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 2, 3));  { result }
          XtensaDropSlots(argBase, 3);
          if op = Ord(tkNeq) then
          begin
            xtensa_movi(reg_xtensa_a8, 1);
            xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
          end
          else if isOrd then
          begin
            { PXXStrCmp3 -> -1/0/1; map to 0/1 against zero in a3, the same
              branch idiom the integer compare tail below uses. }
            xtensa_movi(reg_xtensa_a3, 0);
            if op = Ord(tkLt) then
              EmitAsmXtensa(['movi a4, 1','blt a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
            else if op = Ord(tkGt) then
              EmitAsmXtensa(['movi a4, 1','blt a3, a2, .done','movi a4, 0','.done:','mov a2, a4'])
            else if op = Ord(tkLe) then
              EmitAsmXtensa(['movi a4, 1','bge a3, a2, .done','movi a4, 0','.done:','mov a2, a4'])
            else
              EmitAsmXtensa(['movi a4, 1','bge a2, a3, .done','movi a4, 0','.done:','mov a2, a4']);
          end;
          Exit;
        end;

        { Float arithmetic/compare via the soft-float kernels. MUST precede the
          64-bit check — Double is Is64Bit (a2:a3 storage shape) but its
          arithmetic is soft-float, not integer. Key off the operands. }
        { IRValueKind on the OPERANDS, not IRTk: an IR_LEA/IR_FIELD/IR_INDEX
          operand is an ADDRESS whose IRTk names the type AT it, so `@V[0]`
          over an array of Double reported tyDouble and sent a pure address
          computation in here -- arriving with `and`, which no soft-float
          kernel implements. See IRValueKind in ir.inc for the measurement. }
        if IsFloatXtensa(IntToTypeKind(IRTk[node])) or
           IsFloatXtensa(IRValueKind(left)) or
           IsFloatXtensa(IRValueKind(right)) then
        begin
          EmitFloatBinopXtensa(node);
          Exit;
        end;

        { 64-bit (Int64/UInt64) ops use the dedicated a2:a3 path. A comparison
          carries a Boolean result tk, so key off the operands too. }
        if Is64BitXtensa(IntToTypeKind(IRTk[node])) or
           Is64BitXtensa(IntToTypeKind(IRTk[left])) or
           Is64BitXtensa(IntToTypeKind(IRTk[right])) then
        begin
          EmitBinop64Xtensa(left, right, op,
            not ((IntToTypeKind(IRTk[left]) = tyUInt64) or (IntToTypeKind(IRTk[right]) = tyUInt64)));
          Exit;
        end;

        if (op = Ord(tkPlus)) and TypeIsFrozenString(IntToTypeKind(IRTk[node])) then
          Error('target xtensa: frozen tyString concat unsupported; only literal+literal folds (combine nested string literals)');

        IREmitNodeXtensa(left);
        XtensaPushA2;
        IREmitNodeXtensa(right);
        xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
        { pop the saved left operand into a2 }
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          Dec(XtSpillDepth, 4);
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
        end
        else
        begin
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);
          xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
        end;
        { a2 = left, a3 = right }

        if op = Ord(tkPlus) then xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkMinus) then xtensa_sub(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkStar) then xtensa_mull(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkDiv) then
        begin
          if XtensaSoftDivide then EmitXtensaSoftDivCall('__pxx_divsi3')
          else xtensa_quos(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end
        else if op = Ord(tkMod) then
        begin
          if XtensaSoftDivide then EmitXtensaSoftDivCall('__pxx_modsi3')
          else xtensa_rems(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end
        else if op = Ord(tkShl) then
        begin
          { a2 := a2 << a3 : SAR from a3, then SLL takes the value in s=a2. }
          xtensa_ssl(reg_xtensa_a3);
          xtensa_sll(reg_xtensa_a2, reg_xtensa_a2);
        end
        else if op = Ord(tkIdent) then
        begin
          { 'shr' parses as an identifier operator (logical right shift, like the
            riscv path): SAR from a3, then SRL takes the value in t=a2. }
          xtensa_ssr(reg_xtensa_a3);
          xtensa_srl(reg_xtensa_a2, reg_xtensa_a2);
        end
        else if op = Ord(tkShr) then
        begin
          { C signed >> (bug-c-signed-arith-shift-right): arithmetic right
            shift, same shape as the logical case but SRA instead of SRL. }
          xtensa_ssr(reg_xtensa_a3);
          xtensa_sra(reg_xtensa_a2, reg_xtensa_a2);
        end
        else if op = Ord(tkAnd) then xtensa_and(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkOr) then xtensa_or(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkXor) then xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        { Comparison: a2 := (a2 rel a3) ? 1 : 0. = and <> subtract then branch on
          zero; the ordered forms branch on the operands. The conditional branch
          skips the `movi a4, 0` to the `.done` label. }
        else if op = Ord(tkEq) then
          EmitAsmXtensa(['sub a2, a2, a3','movi a3, 0','movi a4, 1','beq a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkNeq) then
          EmitAsmXtensa(['sub a2, a2, a3','movi a3, 0','movi a4, 1','bne a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkLt) then
          EmitAsmXtensa(['movi a4, 1','blt a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkGt) then
          EmitAsmXtensa(['movi a4, 1','blt a3, a2, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkLe) then
          EmitAsmXtensa(['movi a4, 1','bge a3, a2, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkGe) then
          EmitAsmXtensa(['movi a4, 1','bge a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkIn) then
        begin
          { Set membership: a2 = element, a3 = set address. Branch on the range
            check rather than riscv32's branch-free mask, because xtensa has no
            sltiu and no zero register — the mask costs more instructions here
            than the branch does. Same semantics: an element outside 0..255
            yields 0 and never dereferences past the 32-byte set, and `bgeu`
            catches a negative element as a huge unsigned in one compare, as
            riscv32's `sltiu` does.

            THE ONLY BINARY OPERATOR XTENSA WAS MISSING, and the six `class of`
            / RTTI programs need it because lib/rtl/typinfo.pas uses `in` —
            which means anything that so much as USES typinfo failed to compile
            for this target, one layer under the rtti_reg arm above. }
          EmitAsmXtensa(['movi a5, 0',
                         'movi a4, 256',
                         'bgeu a2, a4, .done',
                         'movi a6, 3',
                         'ssr a6',
                         'srl a4, a2',          { a4 = elem >> 3 = byte index }
                         'add a4, a3, a4',
                         'l8ui a4, a4, 0',      { a4 = the set byte }
                         'movi a6, 7',
                         'and a6, a2, a6',      { a6 = bit index }
                         'ssr a6',
                         'srl a4, a4',
                         'movi a6, 1',
                         'and a5, a4, a6',
                         '.done:',
                         'mov a2, a5']);
        end
        else
        begin
          { The message used to read "(div/mod/shifts pending)" and name no
            operator. Both halves cost real time: div, mod and every shift have
            been implemented for a while, so the parenthesis sends you to the
            wrong place, and without the operator the only way to learn WHICH
            one is missing is to edit this line and self-compile — which is
            exactly what it cost to find tkIn above. Mirrors riscv32's spelling.

            A diagnostic that names a cause it no longer has is worse than one
            that names none: the first sends you somewhere, and it is wrong. }
          ErrorIdent := 'op ' + MangleSuffix(op);
          Error('target xtensa: unsupported binary operator');
        end;
      end;

    IR_CALL:
      begin
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New / class instantiation. For a class: alloc, store the
            VMT pointer at offset 0, run the ctor, return Self in a2 (mirrors
            the riscv32 shape at xtensa conventions, windowed + Call0). }
          j := IRC[node];                       { class idx (or < base) }
          argNode := IRB[node];                 { size arg }
          IREmitNodeXtensa(IRA[argNode]);       { size -> a2 }
          EmitHeapAllocLockedXtensa;            { a2 = payload pointer }
          if j < REC_UCLASS_BASE then
            Exit;                               { plain GetMem }
          EmitLoadDataRefXtensa(reg_xtensa_a3, UClsVMTOffset[j - REC_UCLASS_BASE]);
          xtensa_s32i(reg_xtensa_a3, reg_xtensa_a2, 0);   { [Self] = VMT }
          j := IRResolveCtorProc(node, j);      { overload-resolved ctor PROC }
          if j < 0 then
            Exit;                               { no ctor: instance in a2 }
          argBase := XtSpillDepth;
          XtensaPushA2;                         { Self = word 0 (call0: deepest) }
          nArgs := 1;
          argNode := IRB[node];                 { size arg }
          argNode := IRB[argNode];              { first explicit ctor arg }
          while argNode <> -1 do
          begin
            IREmitNodeXtensa(IRA[argNode]);
            XtensaPushA2;
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            XtensaLoadArgRegsWindowed(argBase, nArgs);
            EmitCallProc(j);
            { Self survives in its sp-relative slot (sp is constant). }
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase);
            XtSpillDepth := argBase;
          end
          else
          begin
            { Call0: word i sits at (nArgs-1-i)*4, Self deepest. Keep the block
              across the call so Self can be reloaded, then drop it — which is
              also what the >6-word overflow area needs. (The reversal only
              touches the low nArgs-6 slots, so Self's slot is untouched.) }
            XtensaLoadArgRegsCall0(nArgs);
            EmitCallProc(j);
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, (nArgs - 1) * 4);  { Self }
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
          end;
          Exit;
        end;
        if procIdx = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];                 { pointer arg }
          IREmitNodeXtensa(IRA[argNode]);       { p -> a2 }
          EmitHeapFreeLockedXtensa;
          Exit;
        end;
        if procIdx = -102 then
        begin
          { SetLength(arr, n) -> PXXDynSetLen(slotAddr, n, desc). SetLength on a
            managed AnsiString -> PXXStrSetLen(slotAddr, n). }
          argNode := IRB[node];                 { arg1 = array/string lvalue }
          valNode := IRB[argNode];              { arg2 = new length }
          left := IRA[argNode];
          if (IRKind[left] = IR_LOAD_SYM) and
             (Syms[IRA[left]].TypeKind = tyAnsiString) then
          begin
            si := IRA[left];
            argBase := XtSpillDepth;
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              EmitFrameAddrXtensa(reg_xtensa_a2, Syms[si].Offset);
              xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0); { caller slot addr }
            end
            else
              EmitSlotAddrXtensa(reg_xtensa_a2, si);        { slot address }
            XtensaPushA2;                                    { slot @ argBase }
            IREmitNodeXtensa(IRA[valNode]);                  { a2 = n }
            XtensaPushA2;                                    { n @ argBase+4 }
            procIdx := FindProc('PXXStrSetLen');
            if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
            if XtensaABI = XTENSA_ABI_WINDOWED then
            begin
              xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
              xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
              XtensaDropSlots(argBase, 2);
            end
            else
            begin
              xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
              xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
              XtensaDropSlots(argBase, 2);
            end;
            EmitCallProc(procIdx);
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target xtensa: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target xtensa: SetLength only supports dynamic arrays yet');
          argBase := XtSpillDepth;
          EmitSlotAddrXtensa(reg_xtensa_a2, si); { a2 = slot address (not the handle) }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            { var-array param: the frame slot holds the CALLER's slot address,
              so one more deref gets the slot PXXDynSetLen must write back
              through. This was an outright refusal
              ("SetLength on a var-array parameter not yet supported"), which is
              the honest failure mode — but riscv32 has carried the two-line
              answer for a while and there was nothing to invent. }
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
          XtensaPushA2;
          IREmitNodeXtensa(IRA[valNode]);       { a2 = n }
          XtensaPushA2;
          EmitLoadDataRefXtensa(reg_xtensa_a2, GetOrAllocSymRTTI(si)); { a2 = desc }
          XtensaPushA2;
          procIdx := FindProc('PXXDynSetLen');
          if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
          { The one site that already had the Call0 direction right, by hand
            (sp+8/4/0 and a real sp restore). Routed through the helper anyway:
            it emits the identical offsets, and leaving one correct hand-written
            copy beside three broken ones is what made the broken spelling look
            like the house style. }
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 3));
            xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 3));
            xtensa_l32i(reg_xtensa_a12, reg_xtensa_sp, XtensaSlotOff(argBase, 2, 3));
          end
          else
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 3));
            xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 3));
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, XtensaSlotOff(argBase, 2, 3));
          end;
          XtensaDropSlots(argBase, 3);
          EmitCallProc(procIdx);
          Exit;
        end;
        if procIdx = -Ord(tkLength) then
        begin
          argNode := IRB[node];
          valNode := IRA[argNode];
          { A FROZEN inline string keeps its length in the buffer's own prefix
            ([buf+0]), not in a heap header at [handle-8]. Reading it the
            managed way gave whatever sat 8 bytes before the buffer — in
            practice 0, so Length(f) was always 0. The frozen operand does not
            arrive tagged: `f` lowers to an IR_LEA of its symbol (the buffer
            ADDRESS), `pf^` to a bare pointer load whose value IS the buffer.
            Same structural predicate as aarch64/riscv32 (b345). }
          if (IntToTypeKind(IRTk[valNode]) = tyString) or
             ((IRKind[valNode] = IR_LEA) and
              TypeIsFrozenString(Syms[IRA[valNode]].TypeKind) and
              not Syms[IRA[valNode]].IsArray) or
             (((IRKind[valNode] = IR_LOAD_SYM) or (IRKind[valNode] = IR_LOAD_MEM)) and
              (IntToTypeKind(IRTk[valNode]) = tyPointer)) then
          begin
            IREmitNodeXtensa(valNode);          { a2 = frozen buffer addr }
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
            Exit;
          end;
          { Length(arr) / Length(managed): a2 = handle; count at [handle-8],
            nil handle -> 0. (l32i has no negative offset, so addi first.) }
          IREmitNodeXtensa(IRA[argNode]);       { a2 = handle (or 0) }
          { A record/class FIELD, an array ELEMENT, or a BY-REF managed string
            param yields the SLOT ADDRESS, not the handle — deref once first,
            else the count is read from [slotaddr-8].

            This step existed on riscv32 and aarch64 and was MISSING here, so
            `Length(var s)` returned the handle itself: `varlen=545267744`, a
            live heap address rendered as a decimal number, against the oracle's
            `varlen=5`. Not a crash and not a zero — a plausible large integer,
            which is the expensive shape. Found by the first differential sweep
            hosted xtensa has ever had (test_cross_var_string_param), whose own
            header documents the identical bug being fixed on arm32.

            Third instance this week of one backend being skipped while its
            siblings were visited (cf. PXXStrCmp3's "four cross backends", and
            HeapMmap's seven arms with no CPU_XTENSA). }
          if (IRKind[valNode] = IR_INDEX) or (IRKind[valNode] = IR_FIELD) or
             ((IRKind[valNode] = IR_LEA) and (Syms[IRA[valNode]].Kind = skParam) and
              Syms[IRA[valNode]].IsRef and (Syms[IRA[valNode]].TypeKind = tyAnsiString) and
              not Syms[IRA[valNode]].IsArray) then
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
          EmitAsmXtensa(['movi a4, 0', 'beq a2, a4, .lzero',
                         'addi a2, a2, -8', 'l32i a2, a2, 0', '.lzero:']);
          Exit;
        end;
        if procIdx = -100 then
        begin
          { LoadFile(path, dst): read the whole file named by `path` into the
            managed-string `dst` through the portable PXXStrLoadFile helper,
            then publish the new handle and release dst's old one. Managed dst
            only. Same shape as arm32/i386/aarch64 -- the FILE I/O is entirely
            in the helper, so what a backend owns here is the refcount dance
            and nothing else, which is why this is a call and not a syscall. }
          argNode := IRB[node];
          left := IRA[argNode];            { arg1 = path }
          valNode := IRB[argNode];
          right := IRA[valNode];           { arg2 = dst }
          if not ((IRKind[right] = IR_LOAD_SYM) and
                  (Syms[IRA[right]].TypeKind = tyAnsiString)) then
            Error('target xtensa: LoadFile expects a managed-string destination');
          si := IRA[right];
          IREmitNodeXtensa(left);          { a2 = path handle (nul-terminated) }
          EmitXtensaHelperCall(XtensaHelperProc('PXXStrLoadFile'), 1);
          XtensaPushA2;                    { save the new handle (refcount 1) }
          EmitLoadVarXtensa(si);           { a2 = dst's OLD handle }
          EmitStrRefCallXtensa('PXXStrDecRef');
          XtensaPopA2;                     { a2 = the new handle }
          EmitStoreVarXtensa(si);
          Exit;
        end;
        if procIdx < 0 then
        begin
          { Type-pun passthroughs: Ord/Chr/Integer()/LongWord() are identity on
            the value already in a2 (char/int share the register model). }
          if (procIdx = -Ord(tkOrd)) or (procIdx = -Ord(tkChr)) or
             (procIdx = -Ord(tkInteger_T)) or (procIdx = -Ord(tkLongWord_T)) or
             (procIdx = -Ord(tkChar_T)) or (procIdx = -Ord(tkBoolean_T)) or
             (procIdx = -Ord(tkString_T)) then
          begin
            argNode := IRB[node];
            IREmitNodeXtensa(IRA[argNode]);
            Exit;
          end;
          if (procIdx = -203) or (procIdx = -204) then
          begin
            { Trunc (-203, toward zero) / Round (-204, nearest-even) -> Int64, via
              the soft-float d2i[_rne]/s2i[_rne] kernels (32-bit result, sign-
              extended to the a2:a3 pair). }
            argNode := IRB[node];
            tk := IntToTypeKind(IRTk[IRA[argNode]]);
            if tk = tyDouble then
            begin
              EmitNode64Xtensa(IRA[argNode]);     { a2:a3 = double bits }
              if procIdx = -204 then EmitFloatUnaryCallXtensa('__pxx_d2i_rne', True, False)
              else EmitFloatUnaryCallXtensa('__pxx_d2i', True, False);
            end
            else if tk = tySingle then
            begin
              IREmitNodeXtensa(IRA[argNode]);     { a2 = single bits }
              if procIdx = -204 then EmitFloatUnaryCallXtensa('__pxx_s2i_rne', False, False)
              else EmitFloatUnaryCallXtensa('__pxx_s2i', False, False);
            end
            else
              IREmitNodeXtensa(IRA[argNode]);      { Trunc/Round of an integer is identity }
            { sign-extend a2 -> a3 for the Int64 result pair }
            EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .p', 'movi a3, -1', '.p:']);
            Exit;
          end;
          if (procIdx = -205) or (procIdx = -206) then
          begin
            { Frac (-205) / Int (-206) -> float (node tk tyDouble). Promote the
              arg to double, then call the fractional / integer-part kernel. }
            argNode := IRB[node];
            EmitFloatOperandXtensa(IRA[argNode], tyDouble);    { a2:a3 = double }
            if procIdx = -205 then EmitFloatUnaryCallXtensa('__pxx_dfrac', True, True)
            else EmitFloatUnaryCallXtensa('__pxx_dint', True, True);
            Exit;
          end;
          if procIdx = -210 then
          begin
            { bare `Eof` (stdin) -> PXXStdinEof: Boolean (portable builtin,
              shares the peek byte with PXXReadLine). Hosted only. }
            procIdx := FindProc('PXXStdinEof');
            if procIdx < 0 then Error('compiler error: PXXStdinEof not found');
            EmitCallProc(procIdx);
            Exit;
          end;
          if procIdx = -SPECIAL_IN then
          begin
            { `x in [items]` where EVERY item is constant. This is the SECOND
              shape `in` arrives in and it is the one I missed: a set literal
              with any runtime element routes through ParseSetLiteralAST and
              becomes an ordinary AN_BINOP tkIn (the arm added earlier tonight),
              while an all-constant literal never becomes a set at all — the
              parser emits an AN_CALL with -SPECIAL_IN and the backend compares
              inline. Two shapes for one construct is exactly what
              devdocs/dev/normalise-dont-special-case.md says to grep for before
              closing the first arm, and the parser's own comment records that
              these two paths had already diverged once (`writeln(e in [a,b])`
              printed 1 instead of TRUE, because only the binop arm was typed
              tyBoolean).

              ir_codegen.inc, aarch64, arm32 and i386 carry this; riscv32 and
              xtensa did not. Modelled on arm32, which is the closest 32-bit
              arm — but arm32 accumulates with conditional execution (`moveq
              r4, #1`), which xtensa does not have, so every test becomes a
              branch over a `movi`, the same way the tkIn arm had to become a
              branch for want of `sltiu`.

              Constants go through EmitLoadConstXtensa, never a bare `movi`:
              xtensa_movi masks to 12 bits with no range check, so a set element
              above 2047 would silently encode as something else. The literal-
              pool fallback is why each item is its own EmitAsmXtensa block —
              EmitLoadConstXtensa can emit a jump over a literal, and labels are
              scoped per block, so nothing branches across one.

              Registers avoid a7 (the frame pointer under the windowed ABI) and
              a15 (the frame pointer under Call0): a3 holds the test value, a4
              the accumulator, a5 the item constant, a6 a per-range temp. }
            argNode := IRB[node];             { arg1 = the test value (IR_ARG) }
            IREmitNodeXtensa(IRA[argNode]);   { a2 = test value }
            EmitAsmXtensa(['mov a3, a2', 'movi a4, 0']);
            argNode := IRB[argNode];          { first set item }
            while argNode <> -1 do
            begin
              itemNode := IRA[argNode];
              if IRKind[itemNode] = IR_BLOCK then
              begin
                { [lo..hi]: a6 := 1, cleared by either bound that fails. }
                lo := Integer(IRIVal[IRA[itemNode]]);
                hi := Integer(IRIVal[IRB[itemNode]]);
                EmitAsmXtensa(['movi a6, 1']);
                EmitLoadConstXtensa(reg_xtensa_a5, lo);
                EmitAsmXtensa(['bge a3, a5, .ok', 'movi a6, 0', '.ok:']);
                EmitLoadConstXtensa(reg_xtensa_a5, hi);
                EmitAsmXtensa(['bge a5, a3, .ok', 'movi a6, 0', '.ok:']);
                EmitAsmXtensa(['or a4, a4, a6']);
              end
              else
              begin
                if IRKind[itemNode] <> IR_CONST_INT then
                  Error('target xtensa: `in [..]` reached the constant-only path '
                        + 'with a non-constant element; a runtime element must '
                        + 'lower to a set binop (ParseSetMembershipAST)');
                lo := Integer(IRIVal[itemNode]);
                EmitLoadConstXtensa(reg_xtensa_a5, lo);
                EmitAsmXtensa(['bne a3, a5, .skip', 'movi a4, 1', '.skip:']);
              end;
              argNode := IRB[argNode];
            end;
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);
            Exit;
          end;
          if procIdx = -Ord(tkArgCount) then
          begin
            { ParamCount = argc - 1. The initial sp -- saved by the entry stub
              in EmitProgramEntryForTarget, which is the half of this that had
              to land in the same change -- points at argc.

              Under --platform=esp there is no argc and BSS_INITIAL_RSP is a
              zeroed BSS word, so the generic path would load [0] and answer -1:
              a plausible wrong value where the truth is simply that an ESP
              image has no command line. 0 is the honest answer and is what a
              caller can act on. }
            if TargetPlatform = PLATFORM_ESP then
            begin
              EmitLoadConstXtensa(reg_xtensa_a2, 0);
              Exit;
            end;
            EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_INITIAL_RSP);
            xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);   { a8 = initial sp }
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a8, 0);   { a2 = argc }
            xtensa_addi(reg_xtensa_a2, reg_xtensa_a2, -1);
            Exit;
          end;
          if procIdx = -Ord(tkArgStr) then
          begin
            { ArgStr(index, strVar) -- the 2-arg statement form; a ParamStr(i)
              EXPRESSION desugars to this with a hidden frozen temp, which is
              why ParamCount alone does not make test_arm32_arg_runtime green
              and both arms are in this change. Mirrors riscv32.

              Refused rather than faked under --platform=esp: there is no argv
              to index, and unlike SysGetRandom nothing in the portable RTL
              calls ArgStr (checked, not assumed), so an ESP program reaching
              here asked for it directly and an empty string would be a lie it
              cannot detect. That is the opposite call from IR_SYSCALL's -ENOSYS
              and for the stated reason: that arm exists to let STATICALLY
              UNREACHABLE library calls compile away. }
            if TargetPlatform = PLATFORM_ESP then
              Error('target xtensa: ArgStr/ParamStr needs a command line, which '
                    + 'an ESP image has not; ParamCount answers 0 there');
            argNode := IRB[node];
            if argNode = -1 then Error('target xtensa: ArgStr expects an index');
            IREmitNodeXtensa(IRA[argNode]);            { a2 = index }
            argNode := IRB[argNode];
            if argNode = -1 then
              Error('target xtensa: ArgStr expects a destination string');
            valNode := IRA[argNode];
            { BOUND THE INDEX AGAINST argc, which this used to skip entirely:
              the index was scaled and added to the argv base with no compare,
              so ParamStr(3) with no arguments read past argv's NULL terminator
              into envp and returned 62 characters of an ENVIRONMENT string --
              or segfaulted where that slot was unmapped. `bgeu` is unsigned, so
              it rejects a negative index in the same instruction, exactly as
              x86-64's `jb` does. Out of range yields NIL, and PXXCStrToFrozen
              turns nil into '' for free.
              bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets }
            EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_INITIAL_RSP);
            EmitAsmXtensa(['l32i a8, a8, 0',            { initial sp }
                           'l32i a9, a8, 0',            { argc }
                           'bgeu a2, a9, .oor',         { unsigned: catches < 0 too }
                           'add a2, a2, a2', 'add a2, a2, a2',  { index*4, no shift-imm }
                           'addi a8, a8, 4',            { argv base }
                           'add a2, a8, a2',
                           'l32i a2, a2, 0',            { argv[index] }
                           'j .done',
                           '.oor:', 'movi a2, 0',
                           '.done:']);
            if (IRKind[valNode] = IR_LOAD_SYM) and
               (Syms[IRA[valNode]].TypeKind = tyAnsiString) then
            begin
              { managed dest: strlen, PXXStrFromLit(len, src), publish. }
              xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);    { a3 = src }
              { `beq a3, a6, .done` first: a nil src must not enter the loop,
                whose first l8ui would fault. }
              EmitAsmXtensa(['movi a4, 0', 'movi a6, 0',
                             'beq a3, a6, .done',
                             '.lp:', 'add a5, a3, a4', 'l8ui a5, a5, 0',
                             'beq a5, a6, .done', 'addi a4, a4, 1', 'j .lp',
                             '.done:']);
              xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);    { a2 = len, a3 = src }
              EmitStrFromLitXtensa;                        { a2 = handle }
              xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);    { a3 = handle }
              EmitSlotAddrXtensa(reg_xtensa_a2, IRA[valNode]);
              EmitXtensaHelperCall(XtensaHelperProc('PXXStrPublish'), 2);
            end
            else
            begin
              { frozen dest: buffer address then byte copy. Emitting the dest
                lvalue may clobber a2..a7, so park src on the expression stack
                -- XtensaPush/Pop, the one spelling correct under both ABIs. }
              XtensaPushA2;
              IREmitNodeXtensa(valNode);                   { a2 = dest buffer }
              xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
              XtensaPopA2;                                 { a2 = src }
              xtensa_mov(reg_xtensa_a4, reg_xtensa_a2);
              xtensa_mov(reg_xtensa_a2, reg_xtensa_a3);    { a2 = dest }
              xtensa_mov(reg_xtensa_a3, reg_xtensa_a4);    { a3 = src }
              EmitXtensaHelperCall(XtensaHelperProc('PXXCStrToFrozen'), 2);
            end;
            Exit;
          end;
          { The SysOpen/SysRead/SysWrite/SysClose/SysFchmod family. Numbers are
            xtensa's OWN table (arch/xtensa/include/uapi/asm/unistd.h), which is
            neither x86-64's nor asm-generic's: read=12, write=13, close=9,
            fchmod=52, openat=288. Getting these from the wrong table is not a
            compile error anywhere -- it is a different syscall at runtime.

            SysOpen lowers to openat(AT_FDCWD, path, flags, 0) and NOT to open,
            even though xtensa does still carry a legacy open (8), because
            riscv32 -- landed in the same pass -- is asm-generic and has NO open
            at all. One shape across both backends beats two, and openat is what
            the C library issues on every target here anyway. mode is 0 because
            the public builtin takes no mode argument; the family's own test
            creates with mode 0 and then chmods via SysFchmod, which is exactly
            why SysFchmod is in the family.

            Under --platform=esp there is no kernel. This mirrors the IR_SYSCALL
            arm in this file rather than inventing a second convention: emit the
            arguments (they are arbitrary expressions and may have side effects),
            discard them, and answer -ENOSYS = -38 = PAL_ERR_UNSUPPORTED. Its
            reasoning applies unchanged -- refusing at RUNTIME keeps genuinely
            reachable misuse detectable while letting statically-unreachable
            calls compile away, where a codegen Error takes whole portable units
            out of the target. NOTE this arm is structural, not measured: the
            hosted arms below are verified against the x86-64 oracle under
            qemu-xtensa, the ESP arm is not executed by anything in my loop. }
          if (procIdx = -Ord(tkSysOpen)) or (procIdx = -Ord(tkSysRead)) or
             (procIdx = -Ord(tkSyswrite)) or (procIdx = -Ord(tkSysClose)) or
             (procIdx = -Ord(tkSysFchmod)) then
          begin
            if TargetPlatform = PLATFORM_ESP then
            begin
              argNode := IRB[node];
              while argNode <> -1 do
              begin
                IREmitNodeXtensa(IRA[argNode]);
                argNode := IRB[argNode];
              end;
              EmitLoadConstXtensa(reg_xtensa_a2, -38);
              Exit;
            end;
            if procIdx = -Ord(tkSysOpen) then
              EmitSysBuiltinXtensa(node, 288, 2, 1, True)    { openat(AT_FDCWD,path,flags,0) }
            else if procIdx = -Ord(tkSysRead) then
              EmitSysBuiltinXtensa(node, 12, 3, 0, False)    { read(fd,buf,count) }
            else if procIdx = -Ord(tkSyswrite) then
              EmitSysBuiltinXtensa(node, 13, 3, 0, False)    { write(fd,buf,count) }
            else if procIdx = -Ord(tkSysClose) then
              EmitSysBuiltinXtensa(node, 9, 1, 0, False)     { close(fd) }
            else
              EmitSysBuiltinXtensa(node, 52, 2, 0, False);   { fchmod(fd,mode) }
            Exit;
          end;
          { Names the builtin. The message used to read "builtin calls not
            supported in bare-metal stage 1" and identify nothing — and it is
            reached under --platform=posix, where there is no bare-metal stage
            at all, so the words send the reader to a profile question that is
            not the problem. Second instance tonight of the same defect class as
            the binop message; the rule is the same: a diagnostic that cannot
            name its own subject makes the reader guess, and the guess is
            usually the message's own stale hint. }
          ErrorIdent := 'builtin ' + AIntToStr(procIdx);
          Error('target xtensa: this builtin has no arm in the xtensa backend');
        end;

        { Word-based argument passing (matches the callee spill in pasparser_*.inc):
          each scalar arg is one word, a by-value Int64/UInt64 is two (lo then
          hi). nArgs counts WORDS; word k loads into the k-th arg register
          (Call0 a2+k / windowed a10+k). }
        { Aggregate (record) result: the caller's hidden destination pointer.
          Call0 pushes it first (deepest) and loads it into a8 just before the
          call — it is NOT an argument word there. Windowed has no register that
          survives the call8 rotation, so it travels as the implicit FIRST
          argument word instead (callee a2), which is also what xtensa gcc does
          for a >16-byte struct return; every real argument shifts up one word
          and the callee's param-copy loop starts at word 1. }
        if (procIdx >= 0) and (not ProcExternal[procIdx]) and
           ABIRetViaHiddenDestProc(procIdx) and (XtensaABI = XTENSA_ABI_CALL0) then
        begin
          IREmitNodeXtensa(IRC[node]);     { a2 = hidden dest addr }
          XtensaPushA2;
        end;
        argNode := IRB[node];
        nArgs := 0;     { word count }
        i := 0;         { argument index }
        argBase := XtSpillDepth;   { windowed: base offset of this call's arg block }
        if (procIdx >= 0) and (not ProcExternal[procIdx]) and
           ABIRetViaHiddenDestProc(procIdx) and (XtensaABI = XTENSA_ABI_WINDOWED) then
        begin
          IREmitNodeXtensa(IRC[node]);     { a2 = hidden dest addr }
          XtensaPushA2;                    { word 0 }
          nArgs := 1;
        end;
        while argNode <> -1 do
        begin
          if (procIdx >= 0) and
             (i < Procs[procIdx].ParamCount) and
             IsFloatXtensa(Procs[procIdx].Params[i].TypeKind) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            { Float param: coerce to the param's float width, push one word
              (single) or two words lo:hi (double). EXTERNAL callees included —
              excluding them handed a C function's `double` a single word. }
            if (Procs[procIdx].Params[i].TypeKind = tyDouble) then
              XtensaPadTo64Xtensa(procIdx, nArgs);
            EmitFloatOperandXtensa(IRA[argNode], Procs[procIdx].Params[i].TypeKind);
            XtensaPushA2;                           { lo / single }
            if Procs[procIdx].Params[i].TypeKind = tyDouble then
            begin
              xtensa_mov(reg_xtensa_a2, reg_xtensa_a3);
              XtensaPushA2;                          { hi }
              Inc(nArgs, 2);
            end
            else
              Inc(nArgs, 1);
          end
          else if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i < Procs[procIdx].ParamCount) and
             (Procs[procIdx].Params[i].TypeKind = tySet) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            { Set by-value param: the arg VALUE is the 32-byte set's ADDRESS, so
              push all 8 words inline (mirrors i386 and riscv32) and let the
              callee spill rebuild the set in its own 32-byte param slot. One
              address word leaves the callee reading its own uninitialised slot
              as set bytes.

              Xtensa had no arm at all, so `CountIn(s)` counted members of the
              stack: an EMPTY set answered 1 where the oracle said 0, and a
              literal `[]` answered 2. Identical to the riscv32 defect that made
              chess perft count 164 instead of 20
              (bug-riscv32-chess-perft-runtime-corruption) — the test that
              catches it, test_cross_set_param, was written FOR that incident
              and could not run here until IR_SET_COPY landed minutes ago. }
            IREmitNodeXtensa(IRA[argNode]);        { a2 = set address }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
            for j := 0 to 7 do
            begin
              xtensa_l32i(reg_xtensa_a2, reg_xtensa_a3, j * 4);
              XtensaPushA2;
            end;
            Inc(nArgs, 8);
          end
          else if (procIdx >= 0) and
             (i < Procs[procIdx].ParamCount) and (i < MAX_PROC_PARAMS) and
             (Procs[procIdx].Params[i].TypeKind = tyRecord) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) and
             (RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]) > 4) and
             (RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]) <= 8) then
          begin
            { By-value record over 4 bytes (up to 8): push BOTH words, exactly
              as the Int64 arm below does. IREmitNodeXtensa now yields a2:a3 for
              a 5-8 byte record value (IR_LOAD_SYM widened above to match);
              without this arm the record fell to the generic 1-word case and
              lost its high word on every plain-value record argument.

              The three symptoms in test_arm32_record_byval_wide are one bug
              seen at three distances from the frame pointer, which is why
              nothing but a full-word fix works: a LONE record arg printed
              `1 0` (high word simply absent), a record BETWEEN scalars printed
              `1 1` (the missing word read back the neighbouring slot), and a
              record after four scalars printed `1 134730429` — a live address
              rendered as a decimal number. Same escalation arm32 recorded:
              data loss becomes corruption becomes a leaked pointer as the slot
              that gets read moves further from the one that was written. }
            { The even-word pad is the SAME call the Int64 arm below makes, and
              it is required for the same reason: the callee spill in
              EmitParamSpillsForTarget runs one shared 64-bit branch for Int64,
              Double AND this record, so it skips an odd word here too. Omitting
              it was measured, not assumed -- `mixedMiddle(1, p, 2)` printed
              `1 2 2 1` for `1 1 2 2`: the caller had packed the record at words
              1-2 while the callee read words 2-3 and took word 4 for `y`. Both
              sides apply the rule or neither does. }
            XtensaPadTo64Xtensa(procIdx, nArgs);
            IREmitNodeXtensa(IRA[argNode]);        { a2=lo, a3=hi }
            XtensaPushA2;                           { lo, word nArgs }
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a3);
            XtensaPushA2;                           { hi, word nArgs+1 }
            Inc(nArgs, 2);
          end
          else if (procIdx >= 0) and
             (i < Procs[procIdx].ParamCount) and
             ((Procs[procIdx].Params[i].TypeKind = tyInt64) or
              (Procs[procIdx].Params[i].TypeKind = tyUInt64)) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            { EXTERNAL callees included — excluding them gave a C function's
              64-bit parameter only its LOW word, the high one being whatever
              the previous call left in that register
              (bug-esp-timer-callback-never-dispatched). }
            XtensaPadTo64Xtensa(procIdx, nArgs);
            EmitNode64Xtensa(IRA[argNode]);        { a2=lo, a3=hi }
            XtensaPushA2;                           { lo, word nArgs }
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a3);
            XtensaPushA2;                           { hi, word nArgs+1 }
            Inc(nArgs, 2);
          end
          else
          begin
            { A frozen buffer (or a char) handed to a MANAGED string parameter
              has to be materialised into a real heap handle first — otherwise
              the callee takes the buffer address for a handle and reads its
              "length" from the 8 bytes before it. Args already converted by
              IRLowerCallArg are tagged tyAnsiString, so they do not match here
              and cannot double-convert. Mirrors riscv32/aarch64 (b345). }
            if (procIdx >= 0) and (i < Procs[procIdx].ParamCount) and
               (Procs[procIdx].Params[i].TypeKind = tyAnsiString) and
               (not Procs[procIdx].Params[i].IsRef) and
               ((IntToTypeKind(IRTk[argNode]) = tyChar) or
                TypeIsFrozenString(IntToTypeKind(IRTk[argNode]))) then
              EmitAnsiStringFromNodeXtensa(IRA[argNode])
            else
              IREmitNodeXtensa(IRA[argNode]);
            { External C call: skip the 8-byte length prefix of a Pascal string
              literal so the callee sees a const char* (as on x86-64/riscv32). }
            if ProcExternal[procIdx] and TypeIsFrozenString(IntToTypeKind(IRTk[argNode])) then
              xtensa_addi(reg_xtensa_a2, reg_xtensa_a2, 8);
            XtensaPushA2;
            Inc(nArgs, 1);
          end;
          Inc(i);
          argNode := IRB[argNode];
        end;

        { Load the outgoing argument registers. Windowed keeps sp constant, so
          the args sit at sp-relative offsets wid..wid+(n-1)*4 (arg0 lowest);
          pop them off the expression stack by resetting XtSpillDepth. Call0
          uses the moving-sp slots (arg0 deepest) and frees them with addi.
          Beyond 6 words both ABIs place the overflow in the outgoing stack
          area the callee reads (see the two helpers). }
        argFree := 0;
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          XtensaLoadArgRegsWindowed(argBase, nArgs);
          XtSpillDepth := argBase;
        end
        else
        begin
          XtensaLoadArgRegsCall0(nArgs);
          if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             ABIRetViaHiddenDestProc(procIdx) then
          begin
            xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, nArgs * 4);   { hidden dest (deepest) }
            argFree := (nArgs + 1) * 4;
          end
          else if nArgs > 0 then
            argFree := nArgs * 4;
          { With no overflow the block is dead the moment the registers are
            loaded, so free it before the call (unchanged codegen). With
            overflow the low words ARE the callee's incoming arguments and the
            block must survive until it returns. }
          if nArgs <= 6 then
          begin
            if argFree > 0 then
              xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, argFree);
            argFree := 0;
          end;
        end;

        EmitCallProc(procIdx);
        if argFree > 0 then
          xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, argFree);
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          { 64-bit result returns in the callee's a2:a3, the caller's a10:a11. }
          if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
        end;
      end;

    IR_WRITE, IR_WRITELN:
      begin
        if TargetPlatform = PLATFORM_ESP then
        begin
          { Bare-metal / IDF: write/writeln does nothing (UART output is
            explicit MMIO in user code, see test_esp_bare.pas). }
        end
        else if IRKind[node] = IR_WRITELN then
          EmitXtensaHelperCall(XtensaHelperProc('PXXWriteNL'), 0)
        else
        begin
          { HOSTED: route every write argument through the portable
            buffer-based builtin helpers (PXXWrite*W in builtinheap.pas), the
            same way riscv32's hosted arm does -- no inline write codegen.
            feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle }
          valNode := IRA[node];
          j := IRB[node];                    { field width, 0 = none }
          if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            si := InternStr(sVal);
            if (j > 0) and (j > Strs[si].Len) then
            begin
              EmitLoadConstXtensa(reg_xtensa_a2, j - Strs[si].Len);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWritePad'), 1);
            end;
            if Strs[si].Len > 0 then
            begin
              { write(1, data+8, len) -- inline syscall, no helper needed.
                13 is __NR_write in XTENSA'S table (measured under
                qemu-xtensa); riscv32's arm uses 64, from the generic table.
                a2 = nr, a6 = arg0, a3 = arg1, a4 = arg2 -- NOT a2..a7 in
                order; see the IR_SYSCALL arm for the whole map. }
              EmitLoadDataRefXtensa(reg_xtensa_a3, Strs[si].Offset + 8);
              EmitLoadConstXtensa(reg_xtensa_a4, Strs[si].Len);
              xtensa_movi(reg_xtensa_a6, 1);              { fd 1 }
              xtensa_movi(reg_xtensa_a2, 13);             { __NR_write }
              xtensa_syscall;
            end;
          end
          else
          begin
            tk := IntToTypeKind(IRTk[node]);
            if IRC[node] = -3 then
            begin
              { write(PChar): NUL-terminated C string }
              IREmitNodeXtensa(valNode);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteCStr'), 1);
            end
            else if tk = tyVariant then
            begin
              { The runtime picks the format from the slot's tag, so a variant
                write is one call with the slot ADDRESS -- no width form.
                This is the call site bug-a-xtensa-codegen-has-no-variant-support
                recorded as having no counterpart on xtensa; the hosted profile
                is what gives it one. }
              EmitLoadVariantAddrXtensa(valNode);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteVariant'), 1);
            end
            else if TypeIsFloat(tk) then
            begin
              { a2:a3 = double bits; the portable float writers take their
                stack ADDRESS. Windowed keeps sp fixed, so the slot is at
                sp+XtSpillDepth-8 after the push; Call0 moved sp onto it. }
              EmitFloatOperandXtensa(valNode, tyDouble);
              XtensaPush64;
              if XtensaABI = XTENSA_ABI_WINDOWED then
                xtensa_addi(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth - 8)
              else
                xtensa_mov(reg_xtensa_a2, reg_xtensa_sp);
              i := IRC[node];                          { decimals }
              if i >= 0 then
              begin
                EmitLoadConstXtensa(reg_xtensa_a3, i);
                EmitLoadConstXtensa(reg_xtensa_a4, j);  { field width }
                EmitXtensaHelperCall(XtensaHelperProc('PXXWriteFloatFixed'), 3);
              end
              else if i = -2 then
                EmitXtensaHelperCall(XtensaHelperProc('PXXWriteFloatNat'), 1)
              else
              begin
                SciFormatFor(j, Ord(tk), scFrac, scExp);
                EmitLoadConstXtensa(reg_xtensa_a3, scFrac);
                EmitLoadConstXtensa(reg_xtensa_a4, scExp);
                EmitXtensaHelperCall(XtensaHelperProc('PXXWriteFloatSci'), 3);
              end;
              XtensaPop64ToA4A5;                       { discard: frees the slot }
            end
            else if tk = tyChar then
            begin
              IREmitNodeXtensa(valNode);
              EmitLoadConstXtensa(reg_xtensa_a3, j);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteCharW'), 2);
            end
            else if tk = tyBoolean then
            begin
              IREmitNodeXtensa(valNode);
              EmitLoadConstXtensa(reg_xtensa_a3, j);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteBoolW'), 2);
            end
            else if tk = tyAnsiString then
            begin
              IREmitNodeXtensa(valNode);               { a2 = handle }
              EmitLoadConstXtensa(reg_xtensa_a3, j);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteStrMW'), 2);
            end
            else if TypeIsFrozenString(tk) then
            begin
              IREmitNodeXtensa(valNode);               { a2 = buffer addr }
              EmitLoadConstXtensa(reg_xtensa_a3, j);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteFrozenW'), 2);
            end
            else if Is64BitXtensa(tk) or TypeIsOrdinal(tk) or (tk = tyUnknown) then
            begin
              { PXXWriteDecW(v: Int64; uns, wid) -- v in a2:a3, so uns/wid land
                in a4/a5 and the call takes four argument words. }
              if Is64BitXtensa(tk) then
                EmitNode64Xtensa(valNode)              { a2:a3 = value }
              else
              begin
                IREmitNodeXtensa(valNode);
                if (tk <> tyUnknown) and not TypeSigned(tk) then
                  xtensa_movi(reg_xtensa_a3, 0)        { zero-extend }
                else
                  { no srai on this ISA -- the EmitNode64Xtensa idiom }
                  EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .wpos', 'movi a3, -1', '.wpos:']);
              end;
              if (tk <> tyUnknown) and not TypeSigned(tk) then
                xtensa_movi(reg_xtensa_a4, 1)
              else
                xtensa_movi(reg_xtensa_a4, 0);
              EmitLoadConstXtensa(reg_xtensa_a5, j);
              EmitXtensaHelperCall(XtensaHelperProc('PXXWriteDecW'), 4);
            end
            else
              Error('target xtensa: write of this type not supported (hosted)');
          end;
        end;
      end;

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
        begin
          { Halt(n) must EXIT WITH n. This arm emitted EmitExit(0)
            unconditionally, with a comment claiming "bare-metal: park in a
            self-loop" -- true for ESP bare, and simply wrong for hosted xtensa
            Linux, which is the same arch. The argument was evaluated nowhere
            and discarded, so `Halt(5)` returned 0 while every other target and
            FPC returned 5. Character for character the riscv32 bug
            (bug-a-halt-n-exits-zero-on-hosted-riscv32) -- including the
            misleading comment, which is the tell that this is a COPY of the
            pre-fix riscv32 arm rather than an independent oversight.

            It was invisible for a different reason than the rest of tonight's
            finds: test_halt_exit_code is IN the test-xtensa target and PASSES,
            because that row compared stdout only. riscv32's row appends
            `echo "exit=$?"`; xtensa's did not. A green differential row that
            does not assert the thing the program exists to assert.
            bug-a-halt-n-exits-zero-on-hosted-xtensa }
          if (IRA[node] <> -1) and (TargetPlatform <> PLATFORM_ESP) then
          begin
            IREmitNodeXtensa(IRA[node]);         { a2 = the exit code }
            EmitExitReg;
          end
          else
            EmitExit(0);                         { no argument, or ESP bare: park }
        end
        else if CurProc >= 0 then
          EmitProcEpilog(Procs[CurProc].RetSymIdx) { early Exit: jump out via epilogue }
        else
          EmitExit(0);
      end;

    IR_DEFAULT_MEM:
      begin
        { Zero IRIVal bytes at dest. ESP has no managed records yet, so skip the
          PXXRecordRelease path the hosted targets take for managed fields. }
        IREmitNodeXtensa(IRA[node]);             { a2 = dest }
        procIdx := FindProc('PXXMemZero');
        if procIdx < 0 then Error('compiler error: PXXMemZero not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);        { arg0 = dest }
          EmitLoadConstXtensa(reg_xtensa_a11, Integer(IRIVal[node])); { arg1 = count }
        end
        else
          EmitLoadConstXtensa(reg_xtensa_a3, Integer(IRIVal[node])); { a2=dest; arg1=count }
        EmitCallProc(procIdx);
      end;

    IR_COPY_REC:
      begin
        { Whole-record copy: PXXMemMove(dest, src, count). ESP has no managed
          record fields yet, so the plain byte move is correct (no per-field ARC). }
        IREmitNodeXtensa(IRB[node]);             { a2 = src }
        XtensaPushA2;
        IREmitNodeXtensa(IRA[node]);             { a2 = dest }
        XtensaPopA3;                              { a3 = src }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);                   { arg0 = dest }
          xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);                   { arg1 = src }
          EmitLoadConstXtensa(reg_xtensa_a12, Integer(IRIVal[node]));  { arg2 = count }
        end
        else
          EmitLoadConstXtensa(reg_xtensa_a4, Integer(IRIVal[node]));   { a2=dest, a3=src, a4=count }
        EmitCallProc(procIdx);
      end;

    IR_READLINE:
      begin
        procIdx := FindProc('PXXReadLine');
        if procIdx < 0 then Error('compiler error: PXXReadLine not found');
        EmitCallProc(procIdx);
      end;

    IR_READ_DISCARD:
      begin
        procIdx := FindProc('PXXReadDiscard');
        if procIdx < 0 then Error('compiler error: PXXReadDiscard not found');
        EmitCallProc(procIdx);
      end;

    IR_READ_VAR:
      begin
        { Parse one read/readln target from the shared line buffer via the
          portable builtin helpers. A managed string wants its SLOT address —
          force lvalue-write mode (mirrors every other backend). Ported from
          riscv32; the three read ops together were the last node-dispatch gap
          keeping `readln` off this target. }
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyAnsiString then
        begin
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeXtensa(IRA[node]);           { a2 = slot address }
          InLValueWrite := savedLVW;
          procIdx := FindProc('PXXReadVarStrM');
          if procIdx < 0 then Error('compiler error: PXXReadVarStrM not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
            xtensa_mov(XtensaArgRegN(0), reg_xtensa_a2);
          EmitCallProc(procIdx);
        end
        else if tk = tyChar then
        begin
          IREmitNodeXtensa(IRA[node]);           { a2 = target address }
          procIdx := FindProc('PXXReadVarChar');
          if procIdx < 0 then Error('compiler error: PXXReadVarChar not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
            xtensa_mov(XtensaArgRegN(0), reg_xtensa_a2);
          EmitCallProc(procIdx);
        end
        else if TypeIsOrdinal(tk) then
        begin
          IREmitNodeXtensa(IRA[node]);           { a2 = target address }
          procIdx := FindProc('PXXReadVarInt');
          if procIdx < 0 then Error('compiler error: PXXReadVarInt not found');
          { arg1 = the target's width. Load it AFTER moving arg0 into place,
            never before: windowed's arg0 is a10 and Call0's is a2, and on
            Call0 a2 already holds the address — so a write to arg1 that
            happened first would still be fine, but the move is what makes the
            two ABIs read identically at this site. }
          if XtensaABI = XTENSA_ABI_WINDOWED then
            xtensa_mov(XtensaArgRegN(0), reg_xtensa_a2);
          EmitLoadConstXtensa(XtensaArgRegN(1), TypeSize(tk));
          EmitCallProc(procIdx);
        end
        else
          Error('target xtensa: read/readln target type not supported');
      end;

    IR_CLASSREF:
      { A metaclass value: a2 = the address of class ci's RTTI blob, through the
        per-class sentinel data-ref the other backends use (patched after
        EmitRTTI). One line, and without it `class of` and every classref
        program stopped at

            unsupported node in IR codegen: unknown

        -- `unknown`, not `classref`, because IROpName has no entry for this op.
        Seven of the 75 declared IR ops have no name there, so a missing arm for
        any of them names nothing at all. Filed as
        bug-a-iropname-has-no-entry-for-seven-ir-ops-so-a-missing-arm-reports-unknown. }
      EmitLoadDataRefXtensa(reg_xtensa_a2, -(CLASSREF_DATAREF_BASE + IRA[node]));

    IR_SET_LIT:
      { a2 = the 32-byte set blob's address. }
      EmitLoadDataRefXtensa(reg_xtensa_a2, Integer(IRIVal[node]));

    IR_SET_COPY:
      begin
        { Copy the 32-byte set from src (IRB) to dest (IRA), 8 words. }
        IREmitNodeXtensa(IRB[node]);              { a2 = source addr }
        XtensaPushA2;
        IREmitNodeXtensa(IRA[node]);              { a2 = dest addr }
        XtensaPopA3;                              { a3 = src }
        for i := 0 to 7 do
        begin
          xtensa_l32i(reg_xtensa_a4, reg_xtensa_a3, i * 4);
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_a2, i * 4);
        end;
      end;

    IR_SET_BINOP:
      begin
        { Set +/-/*/>< over 8 words into the BSS scratch (IRIVal). }
        IREmitNodeXtensa(IRA[node]);              { a2 = lhs addr }
        XtensaPushA2;
        IREmitNodeXtensa(IRB[node]);              { a2 = rhs addr }
        xtensa_mov(reg_xtensa_a3, reg_xtensa_a2); { a3 = rhs }
        XtensaPopA2;                              { a2 = lhs }
        EmitLoadGlobAddrXtensa(reg_xtensa_a4, Integer(IRIVal[node]));  { a4 = scratch }
        { `-` is `and not`, and xtensa has no xori — hoist the -1 mask out of
          the loop rather than materialising it eight times. }
        if IntToTokenKind(IRC[node]) = tkMinus then
          xtensa_movi(reg_xtensa_a8, -1);
        for i := 0 to 7 do
        begin
          xtensa_l32i(reg_xtensa_a5, reg_xtensa_a2, i * 4);
          xtensa_l32i(reg_xtensa_a6, reg_xtensa_a3, i * 4);
          if IntToTokenKind(IRC[node]) = tkPlus then
            xtensa_or(reg_xtensa_a5, reg_xtensa_a5, reg_xtensa_a6)
          else if IntToTokenKind(IRC[node]) = tkStar then
            xtensa_and(reg_xtensa_a5, reg_xtensa_a5, reg_xtensa_a6)
          else if IntToTokenKind(IRC[node]) = tkMinus then
          begin
            xtensa_xor(reg_xtensa_a6, reg_xtensa_a6, reg_xtensa_a8);   { not rhs }
            xtensa_and(reg_xtensa_a5, reg_xtensa_a5, reg_xtensa_a6);
          end
          else if IntToTokenKind(IRC[node]) = tkSymDiff then
            xtensa_xor(reg_xtensa_a5, reg_xtensa_a5, reg_xtensa_a6);   { `><` }
          xtensa_s32i(reg_xtensa_a5, reg_xtensa_a4, i * 4);
        end;
        xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);  { result addr }
      end;

    IR_SET_CMP:
      begin
        { Compare two 32-byte sets. a8 = accumulated differences, a9 =
          subset-direction violations (mirrors riscv32 and aarch64, 8 words).
          The final 0/1 materialisation uses the branch idiom the comparison
          arms above use, because xtensa has neither sltiu nor a zero register. }
        IREmitNodeXtensa(IRA[node]);              { a2 = lhs addr }
        XtensaPushA2;
        IREmitNodeXtensa(IRB[node]);              { a2 = rhs addr }
        xtensa_mov(reg_xtensa_a3, reg_xtensa_a2); { a3 = rhs }
        XtensaPopA2;                              { a2 = lhs }
        xtensa_movi(reg_xtensa_a8, 0);            { differences }
        xtensa_movi(reg_xtensa_a9, 0);            { violations }
        if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) or
           (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          xtensa_movi(reg_xtensa_a11, -1);        { the `not` mask, hoisted }
        for i := 0 to 7 do
        begin
          xtensa_l32i(reg_xtensa_a4, reg_xtensa_a2, i * 4);   { lhs word }
          xtensa_l32i(reg_xtensa_a5, reg_xtensa_a3, i * 4);   { rhs word }
          xtensa_xor(reg_xtensa_a6, reg_xtensa_a4, reg_xtensa_a5);
          xtensa_or(reg_xtensa_a8, reg_xtensa_a8, reg_xtensa_a6);
          if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) then
          begin
            xtensa_xor(reg_xtensa_a6, reg_xtensa_a5, reg_xtensa_a11);  { not rhs }
            xtensa_and(reg_xtensa_a6, reg_xtensa_a4, reg_xtensa_a6);   { lhs and not rhs }
            xtensa_or(reg_xtensa_a9, reg_xtensa_a9, reg_xtensa_a6);
          end
          else if (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          begin
            xtensa_xor(reg_xtensa_a6, reg_xtensa_a4, reg_xtensa_a11);  { not lhs }
            xtensa_and(reg_xtensa_a6, reg_xtensa_a5, reg_xtensa_a6);   { rhs and not lhs }
            xtensa_or(reg_xtensa_a9, reg_xtensa_a9, reg_xtensa_a6);
          end;
        end;
        if IRC[node] = Ord(tkEq) then
          EmitAsmXtensa(['movi a4, 1','movi a6, 0','beq a8, a6, .done',
                         'movi a4, 0','.done:','mov a2, a4'])
        else if IRC[node] = Ord(tkNeq) then
          EmitAsmXtensa(['movi a4, 1','movi a6, 0','bne a8, a6, .done',
                         'movi a4, 0','.done:','mov a2, a4'])
        else if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkGe)) then
          EmitAsmXtensa(['movi a4, 1','movi a6, 0','beq a9, a6, .done',
                         'movi a4, 0','.done:','mov a2, a4'])
        else
        begin
          { tkLt / tkGt: proper = subset AND unequal. Two single-label blocks
            rather than one block with two branches to the same label — labels
            are scoped per EmitAsmXtensa call, and one shape per block is the
            shape every other arm in this file already uses. }
          EmitAsmXtensa(['movi a4, 1','movi a6, 0','beq a9, a6, .done',
                         'movi a4, 0','.done:']);
          EmitAsmXtensa(['movi a5, 1','movi a6, 0','bne a8, a6, .done',
                         'movi a5, 0','.done:']);
          xtensa_and(reg_xtensa_a2, reg_xtensa_a4, reg_xtensa_a5);
        end;
      end;

    IR_RTTI_REG:
      { a2 = the RTTI-registry address, through the -100 data-ref sentinel the
        linker fills in. One line, and it is the entire reason six `class of` /
        RTTI / LFM programs would not compile for xtensa — including
        lib/rtl/typinfo.pas itself, so anything that so much as USES typinfo
        failed here. Mirrors aarch64; x86-64 emits the same sentinel by hand.

        RISCV32 HAS THE SAME GAP and is not fixed here — it is not my lane's
        file. Filed as bug-a-rtti-reg-and-resources-are-missing-on-riscv32.
        Found by the sibling rule: this arm was ported from aarch64 rather than
        riscv32 precisely because riscv32 turned out not to have one, which is
        only visible if you check the arm you are copying FROM exists.
        devdocs/dev/normalise-dont-special-case }
      EmitLoadDataRefXtensa(reg_xtensa_a2, -100);

    IR_RESOURCES:
      { a2 = the resource-table address (-101 sentinel). Same arm, same gap,
        same two backends missing it. }
      EmitLoadDataRefXtensa(reg_xtensa_a2, -101);

    IR_SETLEN_DYN:
      begin
        { Nested / record-or-class-field SetLength via the portable
          PXXDynSetLen(slotAddr, n, desc). IRA = slot-address node, IRB =
          length; descriptor from the node metadata. Ported from riscv32; was an
          "unsupported node" error on xtensa, the single largest cause in the 66
          programs that would not compile for this target.

          A plain dyn-array SYMBOL target has to bypass IR_LEA, which
          dereferences a dynamic array's slot in every position — that would
          hand PXXDynSetLen the CURRENT handle instead of the slot address, and
          for a fresh (nil) array the helper's `arrSlot = nil` early exit makes
          `SetLength(a, 2)` silently do nothing.
          bug-a-riscv32-nested-dynamic-array-element-write-segfaults }
        savedLVW := InLValueWrite;
        InLValueWrite := True;
        if (IRKind[IRA[node]] = IR_LEA) and Syms[IRA[IRA[node]]].IsArray and
           (Syms[IRA[IRA[node]]].ArrLen = -1) then
        begin
          si := IRA[IRA[node]];
          EmitSlotAddrXtensa(reg_xtensa_a2, si);
          { var-array param: the frame slot holds the CALLER's slot address }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
        end
        else
          IREmitNodeXtensa(IRA[node]);            { a2 = slot addr }
        InLValueWrite := savedLVW;
        argBase := XtSpillDepth;
        XtensaPushA2;                             { slot 0 = slotAddr }
        IREmitNodeXtensa(IRB[node]);              { a2 = n }
        XtensaPushA2;                             { slot 1 = n }
        EmitLoadDataRefXtensa(reg_xtensa_a2, GetOrAllocNodeDynDesc(node));
        XtensaPushA2;                             { slot 2 = desc }
        procIdx := FindProc('PXXDynSetLen');
        if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
        xtensa_l32i(XtensaArgRegN(0), reg_xtensa_sp, XtensaSlotOff(argBase, 0, 3));
        xtensa_l32i(XtensaArgRegN(1), reg_xtensa_sp, XtensaSlotOff(argBase, 1, 3));
        xtensa_l32i(XtensaArgRegN(2), reg_xtensa_sp, XtensaSlotOff(argBase, 2, 3));
        XtensaDropSlots(argBase, 3);
        EmitCallProc(procIdx);
      end;

    IR_DYNUNIQUE:
      begin
        { Load this level's data pointer. IRA = slot-address node, so one deref,
          in read AND write mode alike — a dynamic array is an FPC reference type
          at every depth, so there is no nested copy-on-write. Full note in
          ir_codegen.inc's IR_DYNUNIQUE
          (bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing).
          Ported from riscv32; was an "unsupported node" error on xtensa. }
        IREmitNodeXtensa(IRA[node]);              { a2 = slot addr }
        xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);   { a2 = data pointer }
      end;

    IR_COPY_REC_MANAGED:
      begin
        { ARC record copy: retain src's managed fields, release dest's, then
          move the bytes. Ported from riscv32; was an "unsupported node" error
          on xtensa, which is what blocks any record with a managed field from
          being copied by value on this target. }
        argBase := XtSpillDepth;
        IREmitNodeXtensa(IRB[node]);              { a2 = src }
        XtensaPushA2;                             { slot 0 = src }
        IREmitNodeXtensa(IRA[node]);              { a2 = dest }
        XtensaPushA2;                             { slot 1 = dest }
        { COM interface members: their own pass, source retained before the
          destination is released so `a := a` nets zero (see the x86-64 arm).
          Absent on the ESP profile, where FindProc simply answers -1.
          bug-a-a-record-copy-does-not-retain-an-interface-field }
        if RecordHasComIntfFields(IRC[node]) then
        begin
          procIdx := FindProc('PXXRecordRetainIntf');
          if procIdx >= 0 then
          begin
            xtensa_l32i(XtensaArgRegN(0), reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
            EmitLoadDataRefXtensa(XtensaArgRegN(1),
              -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
            EmitCallProc(procIdx);
          end;
          procIdx := FindProc('PXXRecordReleaseIntf');
          if procIdx >= 0 then
          begin
            xtensa_l32i(XtensaArgRegN(0), reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
            EmitLoadDataRefXtensa(XtensaArgRegN(1),
              -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
            EmitCallProc(procIdx);
          end;
        end;
        procIdx := FindProc('PXXRecordRetain');
        if procIdx < 0 then Error('compiler error: PXXRecordRetain not found');
        xtensa_l32i(XtensaArgRegN(0), reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
        EmitLoadDataRefXtensa(XtensaArgRegN(1),
          -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(procIdx);
        procIdx := FindProc('PXXRecordRelease');
        if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
        xtensa_l32i(XtensaArgRegN(0), reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
        EmitLoadDataRefXtensa(XtensaArgRegN(1),
          -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(procIdx);
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        xtensa_l32i(XtensaArgRegN(0), reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
        xtensa_l32i(XtensaArgRegN(1), reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
        EmitLoadConstXtensa(XtensaArgRegN(2), Integer(IRIVal[node]));
        XtensaDropSlots(argBase, 2);
        EmitCallProc(procIdx);
      end;

    IR_NEG:
      if IsFloatXtensa(IntToTypeKind(IRTk[node])) then
      begin
        { Float negate = flip the IEEE sign bit (bit 63 of a Double = bit 31 of
          the hi word a3; bit 31 of a Single in a2), NOT an integer negate. Must
          precede the Is64Bit branch (Double is Is64Bit). }
        if IntToTypeKind(IRTk[node]) = tyDouble then
        begin
          EmitNode64Xtensa(IRA[node]);           { a2:a3 = double bits }
          EmitLoadConstXtensa(reg_xtensa_a8, Integer($80000000));
          xtensa_xor(reg_xtensa_a3, reg_xtensa_a3, reg_xtensa_a8);
        end
        else
        begin
          IREmitNodeXtensa(IRA[node]);           { a2 = single bits }
          EmitLoadConstXtensa(reg_xtensa_a8, Integer($80000000));
          xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
        end;
      end
      else if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
      begin
        EmitNode64Xtensa(IRA[node]);             { value -> a2:a3 }
        { negate: lo = 0-lo (borrow if lo<>0), hi = 0-hi-borrow }
        EmitAsmXtensa([
          'movi a8, 0',
          'movi a9, 0',
          'beq a2, a8, .nb',
          'movi a9, 1',
          '.nb:',
          'sub a2, a8, a2',
          'sub a3, a8, a3',
          'sub a3, a3, a9' ]);
      end
      else
      begin
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, 0);
        xtensa_sub(reg_xtensa_a2, reg_xtensa_a8, reg_xtensa_a2);
      end;

    IR_NOT:
      if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
      begin
        EmitNode64Xtensa(IRA[node]);             { value -> a2:a3 }
        EmitAsmXtensa(['movi a8, -1', 'xor a2, a2, a8', 'xor a3, a3, a8']);
      end
      else if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
              (IntToTypeKind(IRTk[node]) <> tyBoolean) then
      begin
        { 32-bit integer/ordinal: bitwise complement (mirror i386/aarch64), not a
          boolean flip. }
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, -1);
        xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
      end
      else
      begin
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, 1);
        xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          slot-address node, IRB = new length. Address-based, so a record/var-
          param field needs no symbol reconstruction. Spill both args, then load
          into the ABI arg registers. }
        argBase := XtSpillDepth;
        IREmitNodeXtensa(IRA[node]);          { a2 = slot address }
        XtensaPushA2;                         { slot @ argBase }
        IREmitNodeXtensa(IRB[node]);          { a2 = n }
        XtensaPushA2;                         { n @ argBase+4 }
        procIdx := FindProc('PXXStrSetLen');
        if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
          xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
          XtensaDropSlots(argBase, 2);
        end
        else
        begin
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtensaSlotOff(argBase, 0, 2));
          xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtensaSlotOff(argBase, 1, 2));
          XtensaDropSlots(argBase, 2);
        end;
        EmitCallProc(procIdx);
      end;

    IR_SYSCALL:
      begin
        { A raw Linux syscall cannot be serviced on ANY xtensa configuration.
          Two arms, chosen by PROFILE -- exactly the dual-role shape riscv32
          already has. Under --platform=esp (bare or IDF/FreeRTOS) there is no
          kernel, so the op cannot succeed and answers -ENOSYS. Under a hosted
          posix profile there IS one (qemu-xtensa user mode), and the op is a
          real trap.

          The ESP arm came first (cf72dd641) and was written when xtensa had no
          hosted role at all; the header then said no xtensa spelling of this op
          could ever succeed. Adding the hosted profile falsified that, which is
          why it is a profile test now and not an architecture fact.

          So answer the way a kernel answers a syscall number it does not
          implement: -ENOSYS. That is PAL_ERR_UNSUPPORTED (-38, lib/rtl/
          platform.pas: "Linux ENOSYS, used as the portable 'not here'"), the
          same value the ESP PAL returns from its 33 refused entry points -- so
          this follows the PAL's precedent rather than inventing a convention,
          and -38 is independently the right answer because it IS the errno for
          "no such syscall".

          Erroring at codegen instead took a whole portable unit out of the
          target over a call that is statically unreachable there (lib/rtl/
          random.pas guards its tier 2 on SysGetRandom returning -1, so the
          call is dead on xtensa). Refusing at RUNTIME keeps genuinely
          reachable misuse detectable while letting unreachable calls compile
          away.

          This is NOT the IR_FRAME precedent (defs.inc:816), where xtensa Errors
          at lowering rather than lie with a plausible-looking pointer: there is
          no honest frame pointer to hand back on a windowed-register machine,
          whereas -ENOSYS is the honest answer here.

          The args are emitted and their values discarded -- they are arbitrary
          expressions and may have side effects.

          bug-a-xtensa-refuses-to-lower-an-unreachable-syscall }
        if TargetPlatform = PLATFORM_ESP then
        begin
          { ESP profile: no kernel under it, so answer -ENOSYS. Args are still
            emitted -- they are arbitrary expressions and may have side effects
            -- and their values discarded. }
          argNode := IRA[node];
          while argNode <> -1 do
          begin
            IREmitNodeXtensa(IRA[argNode]);
            argNode := IRB[argNode];
          end;
          if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
            EmitLoadConst64Xtensa(-38)
          else
            EmitLoadConstXtensa(reg_xtensa_a2, -38);
        end
        else
        begin
          { HOSTED (qemu-xtensa user mode): a real Linux syscall.

            The register map is NOT "the argument registers in order", and this
            is the one detail worth reading arch/xtensa/kernel/entry.S for
            rather than guessing:

              nr -> a2,  arg0 -> a6, arg1 -> a3, arg2 -> a4,
                         arg3 -> a5, arg4 -> a8, arg5 -> a9,   result -> a2

            a6 leading, then a3..a5, then a8/a9. Guessing a2..a7 in order puts
            arg0 in a3 and every syscall takes the wrong first argument -- which
            for write(2) is the fd, so it would look like it nearly worked.

            Args reach the registers via the expression stack rather than being
            loaded at computed offsets: XtensaPushA2/XtensaPopA2 are the one
            spelling correct under BOTH ABIs (windowed keeps sp fixed and walks
            XtSpillDepth; Call0 moves sp), so popping in reverse avoids
            open-coding two different offset schemes. }
          argNode := IRA[node]; nArgs := 0;
          while argNode <> -1 do
          begin
            IREmitNodeXtensa(IRA[argNode]);
            XtensaPushA2;
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          { Popped in reverse: last pushed is the highest-numbered argument.
            Nothing maps to a2, so the running pop register is never a target. }
          for i := nArgs - 2 downto 0 do
          begin
            XtensaPopA2;
            case i of
              0: xtensa_mov(reg_xtensa_a6, reg_xtensa_a2);
              1: xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
              2: xtensa_mov(reg_xtensa_a4, reg_xtensa_a2);
              3: xtensa_mov(reg_xtensa_a5, reg_xtensa_a2);
              4: xtensa_mov(reg_xtensa_a8, reg_xtensa_a2);
              5: xtensa_mov(reg_xtensa_a9, reg_xtensa_a2);
            end;
          end;
          XtensaPopA2;                                 { a2 = syscall number }
          xtensa_syscall;
          { the intrinsic is typed Int64 (a2:a3) -- sign-extend the 32-bit
            result, the same shape EmitNode64Xtensa uses. }
          EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .scp', 'movi a3, -1', '.scp:']);
        end;
      end;

    IR_ATOMIC:
      begin
        { Atomic read-modify-write on addr^, answering the OLD value.

          S32C1I is the whole ISA here: it stores only if the word still equals
          SCOMPARE1, and hands back the word it FOUND. So ADD and XCHG retry
          until what they read is what they replaced, and CAS is a single
          attempt by definition — a miss is a legal outcome, not a retry.

          Two things make this work that are not in the sequence:

          - ATOMCTL. Its reset value is 0, which means "raise an exception" for
            every memory class, so the first S32C1I traps into the ROM vector
            loop with no output at all. The bare entry now programs it (0x2A,
            internal operation for all three classes) beside CPENABLE — see
            pasparser_*.inc. This is what made the instruction look unimplemented:
            an assembler-built two-instruction .S faults identically, and one
            `wsr.atomctl` makes both run.
          - The branch offset. `xtensa_bne(s, t, off)` measures off from the
            BRANCH itself (EncodeXtensaBranch subtracts the 4 the ISA adds), so
            a retry over four 3-byte instructions is -12; -15 walks back into
            the pop sequence and spins forever.

          bug-s-xtensa-atomics-s32c1i-faults-on-esp32s3 }
        if (IRIVal[node] = ATOMIC_XCHG64) or (IRIVal[node] = ATOMIC_CAS64) or
           (IRIVal[node] = ATOMIC_ADD64) then
          Error('target xtensa: __pxxatomic_*64 not supported (32-bit target)');
        if not SocHasAtomicISA(TargetSoc) then
          Error('target xtensa: this SoC has no atomic ISA');
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeXtensa(IRA[argNode]);
          XtensaPushA2;
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        xtensa_memw;
        if IRIVal[node] = ATOMIC_CAS then
        begin
          XtensaPopA3; xtensa_mov(reg_xtensa_a4, reg_xtensa_a3);   { newval }
          XtensaPopA3; xtensa_mov(reg_xtensa_a6, reg_xtensa_a3);   { expected }
          XtensaPopA3; xtensa_mov(reg_xtensa_a5, reg_xtensa_a3);   { addr }
          xtensa_wsr_scompare1(reg_xtensa_a6);
          xtensa_s32c1i(reg_xtensa_a4, reg_xtensa_a5, 0);
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);                { the word found }
        end
        else
        begin
          XtensaPopA3; xtensa_mov(reg_xtensa_a6, reg_xtensa_a3);   { val / delta }
          XtensaPopA3; xtensa_mov(reg_xtensa_a5, reg_xtensa_a3);   { addr }
          { retry: }
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a5, 0);            { old }
          xtensa_wsr_scompare1(reg_xtensa_a2);
          if IRIVal[node] = ATOMIC_ADD then
            xtensa_add(reg_xtensa_a4, reg_xtensa_a2, reg_xtensa_a6)
          else
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);
          xtensa_s32c1i(reg_xtensa_a4, reg_xtensa_a5, 0);
          xtensa_bne(reg_xtensa_a4, reg_xtensa_a2, -12);           { lost the race }
        end;
        xtensa_memw;
        { the intrinsic is typed Int64 (a2:a3) — sign-extend the 32-bit old
          value into the high word, the same way Trunc/Round do }
        EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .p', 'movi a3, -1', '.p:']);
      end;

    IR_ASM:
      begin
        { Inline asm block: replay the parse-time-captured text lines
          (AsmParseBodyTextXtensa, asmenc.inc) through the xtensa text engine.
          Emitting here, at final code positions, makes label fixups, the L32R
          literal pool and @glob/@data relocations natively correct — no
          AsmBytes-offset rebase like the x86-64 path needs. Labels are scoped
          to the block. }
        AsmXtensaBlockBegin;
        for i := IRA[node] to IRA[node] + IRB[node] - 1 do
          AsmXtensaProcessInlineLine(i);
        AsmXtensaBlockResolve;
      end;

    IR_SET_SIGNAL:
      begin
        { SetSignalHandler(sig, handler): a2 = sig, a3 = handler -> the sethook
          stub (stores the hook slot, falls through into the installer).
          riscv32's arm is the model; the register pair is xtensa's.

          THE GUARD IS NOT DECORATION. Reaching here with no runtime emitted
          would call SigSetHookAddr, which is 0 -- a jump to offset 0 of .text,
          i.e. the program entry, from inside user code. That is a hang or a
          re-entered program, not a diagnostic, and it is reachable two ways:
          the WINDOWED ABI (EmitSignalRuntimeXtensa is Call0-only) and any ESP
          platform build. Both are exactly what TargetHasSignalRuntime answers. }
        if NoSignals then
          Error('SetSignalHandler requires the signal runtime (built without it: --no-signals)');
        if not TargetHasSignalRuntime then
          Error('SetSignalHandler needs a signal runtime, which this build has none of'
                + ' (xtensa installs one only on --platform=posix with the Call0 ABI)');
        IREmitNodeXtensa(IRB[node]);                 { a2 = handler address }
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -16);
        xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);
        IREmitNodeXtensa(IRA[node]);                 { a2 = signal number }
        xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 0);   { a3 = handler }
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 16);
        EmitXtensaCallToCode(SigSetHookAddr);
      end;

    IR_PROCADDR:
      begin
        { @proc -> a2 = the routine's absolute code address, via an inline
          L32R literal patched to entry+BodyAddr by the ELF writer (same
          fixup as riscv32's auipc+literal shape). }
        if ProcExternal[IRA[node]] then
          Error('@ on external routine not supported; wrap it in a local routine');
        XtensaEmitLitHeader;
        if ProcAddrFixCount >= MAX_CALLFIX then Error('proc addr fixup overflow');
        ProcAddrFix[ProcAddrFixCount].CodePos := CodeLen;
        ProcAddrFix[ProcAddrFixCount].ProcIdx := IRA[node];
        Inc(ProcAddrFixCount);
        EmitI32(0);                       { literal: absolute proc addr (patched) }
        xtensa_l32r(reg_xtensa_a2, $FFFF);
      end;

    IR_CALL_IND:
      begin
        if IRCallDest[node] >= 0 then
          Error('target xtensa: aggregate/frozen-string result via an indirect call is not yet supported (feature-cross-virtual-indirect-hidden-dest)');
        { Indirect call through a proc-typed value (e.g. the PXXDivZeroHook
          runtime hook). v1 mirrors arm32: scalar word args only (no by-value
          Int64/float marshalling through a proc pointer yet). Spill the callee
          first, then the arg words, load the ABI arg registers from the slots,
          load the callee into a8, and callx8/callx0 through it. }
        argBase := XtSpillDepth;
        IREmitNodeXtensa(IRA[node]);          { a2 = callee address }
        XtensaPushA2;                         { callee @ argBase (call0: deepest) }
        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeXtensa(IRA[argNode]);
          XtensaPushA2;
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          XtensaLoadArgRegsWindowed(argBase + 4, nArgs);
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, argBase);      { callee }
          XtSpillDepth := argBase;
          xtensa_callx8(reg_xtensa_a8);
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
        end
        else
        begin
          { Call0: moving-sp pushes — arg i sits at (nArgs-1-i)*4, the callee
            deepest at nArgs*4. Overflow words stay allocated across the call
            (they are the callee's incoming stack args) and are freed after. }
          XtensaLoadArgRegsCall0(nArgs);
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, nArgs * 4);    { callee }
          if nArgs > 6 then
          begin
            xtensa_callx0(reg_xtensa_a8);
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, (nArgs + 1) * 4);
          end
          else
          begin
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, (nArgs + 1) * 4);
            xtensa_callx0(reg_xtensa_a8);
          end;
        end;
      end;

    IR_VIRTUAL_CALL:
      begin
        if IRCallDest[node] >= 0 then
          Error('target xtensa: aggregate/frozen-string result via a virtual call is not yet supported (feature-cross-virtual-indirect-hidden-dest)');
        { VMT dispatch. IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=slot.
          Word-push args (Self = word 0, deepest on Call0), load the arg
          registers, read the VMT pointer from [Self], call through
          [VMT + slot*8] (8-byte data slots, address in the low word — mirrors
          riscv32/arm32). }
        argBase := XtSpillDepth;
        argNode := IRA[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeXtensa(IRA[argNode]);
          XtensaPushA2;
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          XtensaLoadArgRegsWindowed(argBase, nArgs);
          XtSpillDepth := argBase;
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a10, 0);              { VMT ptr from [Self] }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, Integer(IRIVal[node]) * 8);
          xtensa_callx8(reg_xtensa_a8);
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
        end
        else
        begin
          XtensaLoadArgRegsCall0(nArgs);
          if nArgs <= 6 then
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a2, 0);               { VMT ptr from [Self] }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, Integer(IRIVal[node]) * 8);
          xtensa_callx0(reg_xtensa_a8);
          { Overflow words are the callee's incoming stack args: free after. }
          if nArgs > 6 then
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
        end;
      end;

    IR_VAR_STORE:
      begin
        { IRA = dest addr, IRB = value/src addr, IRC = source TTypeKind ord. }
        tk := IntToTypeKind(IRC[node]);
        if tk = tyVariant then
        begin
          { ARC-correct 16-byte variant-to-variant copy: retain the source
            BEFORE clearing the destination, so `v := v` cannot free what it is
            about to read. }
          EmitLoadVariantAddrXtensa(IRB[node]);          { a2 = src addr }
          EmitVarHelperCallXtensa('PXXVarRetain');
          XtensaPushA2;                                  { save src }
          IREmitNodeXtensa(IRA[node]);                   { a2 = dest addr }
          { ReleasePayload, not Clear: Clear zeroes the 16 slot bytes, and when
            src and dest alias that wipes what the copy below is about to read —
            `v := v` came back Empty.
            bug-a-a-variant-assigned-to-itself-becomes-empty }
          EmitVarHelperCallXtensa('PXXVarReleasePayload');
          { src is popped AFTER the call, not held in a register across it:
            Call0 treats a3 as caller-saved and the windowed call rotates
            a8-a15 out, so nothing but the expression stack survives. }
          XtensaPopA3;                                   { a3 = src }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a3, 0);  xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 0);
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a3, 4);  xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 4);
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a3, 8);  xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 8);
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_a3, 12); xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 12);
        end
        else
        begin
          j := VariantTagForTk(tk, 'Variant :=');
          { A CODE ADDRESS overrides the type-kind answer — defs.inc's
            VT_CALLABLE_TAG; the x86-64 arm carries the full note. }
          if IRSrcIsCallable(IRB[node]) then j := VT_CALLABLE_TAG;
          EmitVariantPayloadXtensa(IRB[node], tk);
          IREmitNodeXtensa(IRA[node]);                   { a2 = dest addr }
          EmitVariantFillXtensa(j, tk);
        end;
      end;

    IR_VAR_BOX:
      begin
        { Box a scalar into a temp variant (IRA = temp addr); addr -> a2. }
        tk := IntToTypeKind(IRC[node]);
        j := VariantTagForTk(tk, 'Variant operand');
        if IRSrcIsCallable(IRB[node]) then j := VT_CALLABLE_TAG;
        EmitVariantPayloadXtensa(IRB[node], tk);
        IREmitNodeXtensa(IRA[node]);                     { a2 = temp addr }
        EmitVariantFillXtensa(j, tk);                    { leaves addr in a2 }
      end;

    IR_VAR_BINOP:
      begin
        { PXXVarBinOp(dest, left, right, opTk, isCompare) — five words. Built in
          a2-a6 (the Call0 argument registers, in order) and copied up to
          a10-a14 for the windowed ABI, which is what call8 rotates into the
          callee's a2-a7. Five is inside both ABIs' register-argument range, so
          nothing spills to the outgoing-argument area. }
        sgn := IntToTypeKind(IRTk[node]) = tyBoolean;
        IREmitNodeXtensa(IRA[node]);                     { a2 = left addr }
        XtensaPushA2;
        IREmitNodeXtensa(IRB[node]);                     { a2 = right addr }
        xtensa_mov(reg_xtensa_a4, reg_xtensa_a2);        { a4 = right }
        XtensaPopA3;                                     { a3 = left }
        if sgn then
          xtensa_movi(reg_xtensa_a2, 0)                  { compare: dest unused }
        else
          EmitLoadGlobAddrXtensa(reg_xtensa_a2, Integer(IRIVal[node]));  { dest temp }
        EmitLoadConstXtensa(reg_xtensa_a5, IRC[node]);   { a5 = opTk }
        if sgn then xtensa_movi(reg_xtensa_a6, 1)
        else xtensa_movi(reg_xtensa_a6, 0);              { a6 = isCompare }
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
          xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
          xtensa_mov(reg_xtensa_a12, reg_xtensa_a4);
          xtensa_mov(reg_xtensa_a13, reg_xtensa_a5);
          xtensa_mov(reg_xtensa_a14, reg_xtensa_a6);
        end;
        { PASCAL selects PXXVarBinOpPas — the raw dispatch with FPC's string
          rule in front of it. NilPy keeps the raw one: Python's rules for these
          pairs differ in every case ('5' * 3 is '555'). Choosing WHICH helper
          to call is how the language reaches a shared runtime that cannot see
          PyProgramMode. Falls back to the raw one when no builtin unit is
          loaded, rather than failing to compile.
          bug-a-pxxvarbinop-carries-the-same-string-arithmetic-defect-as-x86-64-did }
        if PyProgramMode then
          procIdx := FindProc('PXXVarBinOp')
        else
        begin
          procIdx := FindProc('PXXVarBinOpPas');
          if procIdx < 0 then procIdx := FindProc('PXXVarBinOp');
        end;
        if procIdx < 0 then Error('compiler error: PXXVarBinOp not found');
        EmitCallProc(procIdx);
        if XtensaABI = XTENSA_ABI_WINDOWED then
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);     { result }
      end;

    else
      Error('target xtensa: unsupported node in IR codegen: ' + IROpName(IRKind[node]));
  end;
end;

procedure EmitSignalRuntimeXtensa;
{ Libc-free signal support, hosted xtensa Linux, Call0 only (feature-signal-handlers;
  x86-64 = b336, aarch64 = b370, riscv32 = the model this is ported from).

  EVERY NUMBER AND EVERY ABI FACT BELOW WAS MEASURED under qemu-xtensa, because
  none of them are in the tree and xtensa carries its OWN syscall table -- write
  is 13, not the generic 64. Recalling them would have compiled, linked, run, and
  done something else. See addenda 4-6 of
  ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired.

    rt_sigaction  226   pinned by a WORKING install, not by an errno signature
    sigaltstack   224   installed a real altstack and read it back
    kill          123   the only candidate accepting a non-positive pid
    getpid        120   see the caveat at its use -- one of three, indistinguishable here

  Contract, measured, and it is riscv32's rather than i386/arm32's:

  - **No SA_RESTORER.** struct sigaction is { handler(0), flags(4), mask(8,12) },
    16 bytes on ILP32, sigsetsize 8. The kernel supplies the return path itself.
  - **Returning from the handler works.** `ret` out of a Call0 handler unwinds.
    (The first probe of this said otherwise and was confounded: SIGSEGV is blocked
    inside its own handler, so a re-fault force-kills whether the return path works
    or not. With SA_NODEFER: three entries, exit 0.)
  - **The kernel enters a plain Call0 proc.** xtensa userland is conventionally
    windowed and setup_frame is written for it, so this was the risk that decided
    whether this ticket was a session or a campaign. It holds.
  - Handler entry: a2 = sig, a3 = siginfo_t*, a4 = ucontext_t*, a0 = return address.
  - Syscall map (NOT "argument registers in order" -- see the IR_SYSCALL arm):
    nr -> a2, arg0 -> a6, arg1 -> a3, arg2 -> a4, arg3 -> a5, result -> a2.

  WINDOWED IS DELIBERATELY EXCLUDED and the caller gates it: a windowed unwind
  needs the register windows spilled first, which is the same reason
  TargetHasProcCleanupFrame is Call0-only. Call0 is the DEFAULT ABI
  (compiler.pas:862), so this serves the default path, not a corner.

  Two layout constraints, both enforced by the encoders rather than by care:

  1. Conditional branches encode an EIGHT-BIT displacement (-128..127,
     XtensaRelCheck). Every short branch below is paired with a long `j` where the
     span could grow. If a future edit pushes one past the range the encoder
     RAISES -- it does not truncate, since
     bug-a-xtensa-pc-relative-encoders-silently-truncate-an-out-of-range-offset.
  2. Each EmitLoadGlobAddrXtensa injects ~12 bytes of literal header INTO those
     spans. Adding one inside a branch span is how the range gets exceeded.

  The sig is parked in the FRAME rather than a callee-saved register across the
  hook call: a12-a15 are callee-saved by convention, but the hook is arbitrary
  compiled Pascal and the frame slot costs one load to be independent of it. }
var
  jmpOver, dispatchAt, bNoSi, jSt, bLo, bHi, bHook, jDfl, jDflOut, outAt,
  c0At, padTo, delta: Integer;
begin
  jmpOver := CodeLen; xtensa_j(0);            { skip the blob; patched at the end }

  { ---------------- dispatch ---------------- }
  XtensaAlignCode4;
  SigDispatchAddr := CodeLen;
  dispatchAt := CodeLen;

  { THE KERNEL ENTERS A SIGNAL HANDLER WITH THE CALL4 CONVENTION, NOT CALL0, and
    it does so whatever ABI the handler was compiled with -- setup_frame is
    written for windowed userland and there is no flag that turns it off. This
    stub's first version assumed a plain Call0 entry (a0 = return address,
    a2/a3/a4 = sig/siginfo/ucontext) and it was WRONG on every one of the four:

      MEASURED at handler entry under qemu-xtensa (`qemu-xtensa -d cpu`, the
      register dump at the fault, whose a4/a6/a7 the stub had not yet touched):

        a0 = 00000000    NOT a return address -- `ret` jumped to 0
        a4 = 60801000    return address, with the CALL4 WINDOW-INCREMENT BITS
                         in the top two: ra = a4 and $3FFFFFFF = 20801000, the
                         kernel's rt_sigreturn trampoline
        a6 = 0000000f    the signal (SIGTERM), where a2 was assumed
        a7 = 080ab600    siginfo*, where a3 was assumed (and a3 was 0, so the
                         defensive nil check silently took the no-siginfo arm)
        a8 =             ucontext*, where a4 was assumed

    Every one of those reads a plausible wrong value rather than faulting at the
    mistake: sig 0 fell out of the 1..64 bounds check, siginfo nil zeroed
    si_code/si_addr, and the only visible symptom was a SIGSEGV one instruction
    after the stub was already finished. The dead-code note this runtime landed
    with said its Call0-entry claim was "the risk that decided whether this
    ticket was a session or a campaign"; it was measured with a hand-written
    probe rather than through this stub, and it did not hold.

    Masking a4 with $3FFFFFFF discards the two window bits the kernel packed in
    (`areg[4] = (ra & 0x3fffffff) | 0x40000000`), which is exactly what RETW
    reconstructs from the PC. It loses ra's own top two bits -- correct for a
    hosted Linux image, where text, vdso and stack all live in the low 1 GiB. }
  xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -16);
  EmitLoadConstXtensa(reg_xtensa_a10, $3FFFFFFF);
  xtensa_and(reg_xtensa_a10, reg_xtensa_a4, reg_xtensa_a10);
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_sp, 0);     { kernel return address }
  xtensa_s32i(reg_xtensa_a6, reg_xtensa_sp, 8);      { sig, in the frame }
  xtensa_mov(reg_xtensa_a3, reg_xtensa_a7);          { siginfo*, in a3 from here }
  xtensa_mov(reg_xtensa_a11, reg_xtensa_a8);         { ucontext*, before a8 becomes
                                                       EmitLoadGlobAddr's scratch }

  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_CTX);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 0);     { ucontext* for __pxxSigContext }

  { siginfo_t is { si_signo(0), si_errno(4), si_code(8), union }. The union is
    pointer-aligned, so on ILP32 the preamble is NOT padded and si_addr sits at
    12 -- riscv32's offsets, not the 64-bit targets'. a3 nil is defensive. }
  xtensa_movi(reg_xtensa_a10, 0);
  bNoSi := CodeLen; xtensa_beq(reg_xtensa_a3, reg_xtensa_a10, 0);
  xtensa_l32i(reg_xtensa_a10, reg_xtensa_a3, 8);     { si_code }
  xtensa_l32i(reg_xtensa_a11, reg_xtensa_a3, 12);    { si_addr }
  jSt := CodeLen; xtensa_j(0);
  { .nosi -- a10 is already 0 from the compare }
  Patch24(bNoSi, EncodeXtensaBranch(1, reg_xtensa_a3, reg_xtensa_a10, CodeLen - bNoSi));
  xtensa_movi(reg_xtensa_a11, 0);
  { .st }
  Patch24(jSt, EncodeXtensaJ(CodeLen - jSt));
  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_CODE);
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 0);
  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_ADDR);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 0);

  { bounds 1 <= sig <= 64, as two SIGNED compares: xtensa has no bgeu/bltu
    encoder in-tree and adding one is a shared-file change this lane does not
    hold. Signed is exact here because sig arrives from the kernel. }
  xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 8);
  xtensa_movi(reg_xtensa_a11, 1);
  bLo := CodeLen; xtensa_blt(reg_xtensa_a2, reg_xtensa_a11, 0);
  xtensa_movi(reg_xtensa_a11, 65);
  bHi := CodeLen; xtensa_bge(reg_xtensa_a2, reg_xtensa_a11, 0);

  { hook = BSS_SIG_HOOKS[(sig-1)*8]. The table is 64 * 8 on every target; the
    stride is 8 even on ILP32, and only the low word is a pointer here.
    *8 as three adds: no constant-shift encoder in-tree, same reason as above. }
  xtensa_addi(reg_xtensa_a10, reg_xtensa_a2, -1);
  xtensa_add(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a10);
  xtensa_add(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a10);
  xtensa_add(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a10);
  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_HOOKS);
  xtensa_add(reg_xtensa_a8, reg_xtensa_a8, reg_xtensa_a10);
  xtensa_l32i(reg_xtensa_a10, reg_xtensa_a8, 0);
  xtensa_movi(reg_xtensa_a11, 0);
  bHook := CodeLen; xtensa_bne(reg_xtensa_a10, reg_xtensa_a11, 0);   { -> .call }
  jDfl := CodeLen; xtensa_j(0);                { no hook -> .dfl, long hop }
  { .call }
  Patch24(bHook, EncodeXtensaBranch(9, reg_xtensa_a10, reg_xtensa_a11, CodeLen - bHook));
  xtensa_callx0(reg_xtensa_a10);               { the Pascal hook; returning resumes }

  { .out -- shared epilogue }
  outAt := CodeLen;
  Patch24(bLo, EncodeXtensaBranch(2,  reg_xtensa_a2, reg_xtensa_a11, outAt - bLo));
  Patch24(bHi, EncodeXtensaBranch(10, reg_xtensa_a2, reg_xtensa_a11, outAt - bHi));
  xtensa_l32i(reg_xtensa_a0, reg_xtensa_sp, 0);
  xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 16);
  xtensa_ret;                                  { -> kernel return path }

  { .dfl: no hook -- revert to SIG_DFL and re-raise, so an unhandled signal still
    terminates with proper killed-by-signal status. Returning instead would be
    wrong for SIGINT/SIGTERM, which are exactly what the default install covers:
    the fault is not re-executed, so the signal would simply be lost. }
  Patch24(jDfl, EncodeXtensaJ(CodeLen - jDfl));
  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_SCRATCH);
  xtensa_movi(reg_xtensa_a10, 0);
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 0);    { handler = SIG_DFL }
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 4);    { flags }
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 8);    { mask lo -- NO restorer slot }
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 12);   { mask hi }
  xtensa_l32i(reg_xtensa_a6, reg_xtensa_sp, 8);     { arg0 = sig }
  xtensa_mov(reg_xtensa_a3, reg_xtensa_a8);         { arg1 = act }
  xtensa_movi(reg_xtensa_a4, 0);                    { arg2 = oldact }
  xtensa_movi(reg_xtensa_a5, 8);                    { arg3 = sigsetsize }
  xtensa_movi(reg_xtensa_a2, 226);                  { rt_sigaction }
  xtensa_syscall;
  { getpid. MEASURED ONLY TO A SET: 120, 126 and 127 all answer the process's own
    id and are indistinguishable in a single-threaded process by construction
    (getpid / gettid / most likely set_tid_address). All three feed kill the right
    number, so this is operationally settled; what is NOT settled is which name
    belongs on this line. Do not "correct" it to a confident name without a
    threaded measurement. 150 is getppid -- it matched a pid oracle exactly and
    the oracle was the parent process. }
  xtensa_movi(reg_xtensa_a2, 120);
  xtensa_syscall;                                   { a2 = pid }
  xtensa_mov(reg_xtensa_a6, reg_xtensa_a2);         { arg0 = pid }
  xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 8);     { arg1 = sig }
  xtensa_movi(reg_xtensa_a2, 123);                  { kill }
  xtensa_syscall;
  jDflOut := CodeLen; xtensa_j(0);
  Patch24(jDflOut, EncodeXtensaJ(outAt - jDflOut));

  { ---------------- sethook (a2 = sig, a3 = handler) ---------------- }
  XtensaAlignCode4;                            { CALL0 targets must be 4-aligned }
  SigSetHookAddr := CodeLen;
  xtensa_addi(reg_xtensa_a10, reg_xtensa_a2, -1);
  xtensa_movi(reg_xtensa_a11, 63);
  xtensa_and(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a11);   { keep in-table }
  xtensa_add(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a10);
  xtensa_add(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a10);
  xtensa_add(reg_xtensa_a10, reg_xtensa_a10, reg_xtensa_a10);
  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_HOOKS);
  xtensa_add(reg_xtensa_a8, reg_xtensa_a8, reg_xtensa_a10);
  xtensa_s32i(reg_xtensa_a3, reg_xtensa_a8, 0);
  { falls through into install. The alignment pad below is 3-byte NOPs, which
    EXECUTE harmlessly -- that is why the fallthrough is safe here and why this
    does not need riscv32's explicit jump. }

  { ---------------- install (a2 = sig) ---------------- }
  XtensaAlignCode4;
  SigInstallAddr := CodeLen;
  xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -16);
  xtensa_s32i(reg_xtensa_a0, reg_xtensa_sp, 0);   { our OWN return address: the
                                                    call0 below clobbers a0 }
  xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 8);   { sig }

  { sigaltstack(2) FIRST, then SA_ONSTACK in the flags -- neither works alone.
    Without both, a stack-overflow SIGSEGV is unhandleable: the fault happens
    BECAUSE there is no stack left, so the kernel cannot push a signal frame onto
    the faulting stack and kills outright
    (bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack).
    stack_t on ILP32 is { ss_sp(0), ss_flags(4), ss_size(8) } -- riscv32's
    offsets; defs.inc's 0/8/16 describes the 64-bit shape. }
  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_ALTSS);
  EmitLoadGlobAddrXtensa(reg_xtensa_a10, BSS_SIG_ALTSTK);
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 0);
  xtensa_movi(reg_xtensa_a11, 0);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 4);
  EmitLoadConstXtensa(reg_xtensa_a11, SIG_ALTSTACK_SIZE);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 8);
  xtensa_mov(reg_xtensa_a6, reg_xtensa_a8);       { arg0 = new }
  xtensa_movi(reg_xtensa_a3, 0);                  { arg1 = old = nil }
  xtensa_movi(reg_xtensa_a2, 224);                { sigaltstack }
  xtensa_syscall;

  { a10 := absolute address of the dispatch stub.

    THE ONE PIECE WITH NO IN-TREE MODEL -- xtensa has no auipc, aarch64's adr and
    x86-64's call/pop do not transfer, EmitGlobRef/EmitDataRef relocate DATA
    addresses, and ProcAddrFix is keyed by PROC INDEX while this is a raw code
    offset inside the runtime blob. Addendum 6 of the ruling.

    CALL0 sets a0 to the address of the instruction AFTER it (PC+3) and jumps to
    a 4-ALIGNED target, so the two differ by the pad and the delta must be taken
    from PC+3 -- not from where control resumes. Getting that backwards installs a
    handler pointing mid-instruction: a fault at delivery time, far from the
    cause, on the one path a signal actually arrives on. }
  c0At := CodeLen;
  padTo := ((c0At + 3 + 3) div 4) * 4;
  xtensa_call0(padTo - c0At);
  while CodeLen < padTo do EmitB(0);              { jumped over, never executed }
  delta := dispatchAt - (c0At + 3);               { a0 = c0At + 3 }
  EmitLoadConstXtensa(reg_xtensa_a10, delta);     { addi's imm is only -128..127 }
  xtensa_add(reg_xtensa_a10, reg_xtensa_a0, reg_xtensa_a10);

  EmitLoadGlobAddrXtensa(reg_xtensa_a8, BSS_SIG_SCRATCH);
  xtensa_s32i(reg_xtensa_a10, reg_xtensa_a8, 0);  { handler = dispatch }
  { SA_RESTART|SA_ONSTACK|SA_SIGINFO. SA_SIGINFO ($04) is what makes the kernel
    pass siginfo_t*/ucontext_t* in a3/a4 -- without it the fault CAUSE is
    unknowable, si_code being its only carrier. No SA_RESTORER to flip alongside,
    measured: the install works without one. }
  EmitLoadConstXtensa(reg_xtensa_a11, $18000004);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 4);
  xtensa_movi(reg_xtensa_a11, 0);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 8);
  xtensa_s32i(reg_xtensa_a11, reg_xtensa_a8, 12);
  xtensa_l32i(reg_xtensa_a6, reg_xtensa_sp, 8);   { arg0 = sig }
  xtensa_mov(reg_xtensa_a3, reg_xtensa_a8);       { arg1 = act }
  xtensa_movi(reg_xtensa_a4, 0);                  { arg2 = oldact }
  xtensa_movi(reg_xtensa_a5, 8);                  { arg3 = sigsetsize }
  xtensa_movi(reg_xtensa_a2, 226);                { rt_sigaction }
  xtensa_syscall;
  xtensa_l32i(reg_xtensa_a0, reg_xtensa_sp, 0);
  xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 16);
  xtensa_ret;

  Patch24(jmpOver, EncodeXtensaJ(CodeLen - jmpOver));
end;

procedure IREmitLeaveExceptionFramesXtensa(count: Integer);
{ Pop `count` exception frames: restore the saved prev EXC_TOP from each
  frame head and free the 32-byte frame (Call0 moving sp). }
var i: Integer;
begin
  for i := 1 to count do
  begin
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, 0);   { prev EXC_TOP }
    EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_TOP);
    xtensa_s32i(reg_xtensa_a4, reg_xtensa_a3, 0);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, EXC_FRAME_SIZE_XT);
  end;
end;

{ --- one place that decides how a body jumps to its own label ---------------
  Five sites used to spell out `if the label is known then xtensa_j(delta) else
  record a fixup and reserve three bytes`, and four of them then had to know how
  many bytes that came to, because a conditional branch skips OVER it. A backward
  jump can now widen to ~20 bytes (EmitXtensaJumpToCode), so the size is no longer
  a constant and open-coding it five times would be five chances to leave a skip
  distance behind.

  So the skip branch is emitted with a placeholder and PATCHED once the jump has
  been emitted and CodeLen says how long it actually was -- which is exact, and
  does not require anyone to predict the long form's two alignment pads.
  bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi (the wall behind) }
procedure EmitXtensaJumpToLabel(lblId: Integer; var fixCount: Integer);
begin
  if LabelPositions[lblId] <> -1 then
  begin
    EmitXtensaJumpToCode(LabelPositions[lblId]);
    Exit;
  end;
  { Forward: the slot is sized before the label exists, so its width is a GUESS.
    XtWideLabel carries the guess in from the previous attempt -- three bytes
    the first time round, the long form once a J has been seen not to reach.
    Either way the fixup loop below patches it and never has to widen anything
    in place, which is the thing that cannot be done. }
  if fixCount >= MAX_IR then Error('label fixup overflow');
  LabelFixupTarget[fixCount] := lblId;
  if XtWideLabel[lblId] then
    EmitXtensaLongJumpSlot(LabelFixupPos[fixCount], LabelFixupAnchor[fixCount])
  else
  begin
    LabelFixupPos[fixCount] := CodeLen;
    LabelFixupAnchor[fixCount] := -1;
    xtensa_j(4);
  end;
  Inc(fixCount);
end;

procedure XtensaPatchSkipOver(pos, r, s, t: Integer);
{ Rewrite the branch at `pos` to skip everything emitted since. r is the branch
  flavour's own field: 9 = BNE, 1 = BEQ, matching xtensa_bne/xtensa_beq. }
begin
  Patch24(pos, EncodeXtensaBranch(r, s, t, CodeLen - pos));
end;

procedure IREmitMachineCodeXtensa;
{ RELAXATION. A forward jump reserves its slot before the label exists, so the
  width is a guess; when the guess is wrong the slot CANNOT be widened in place,
  because everything after it would move. So the body is emitted AGAIN, with the
  labels that overflowed marked wide. Two passes settle it in every case that
  can occur -- the long form reaches +-2 GB, so the only thing a third pass
  could fix is a jump pushed out of range BY the widening, which the loop
  handles anyway.

  This costs nothing on any body that fits: the retry fires only when a J was
  measured not to reach, i.e. only in a body over 128 KiB of code, which is
  generated or machine-expanded source. `hello` and the compiler's own ordinary
  procedures emit exactly the bytes they did before.

  RE-EMITTING IS ONLY SAFE BECAUSE OF WHAT THE BODY APPENDS TO, and that was
  enumerated rather than assumed. Every table an Xtensa body writes -- CodeRef,
  Fixups, GlobFix, CallFix, DynCall, IramCallFix -- is a pure `T[Count] := x;
  Inc(Count)` append, so restoring the count makes the second pass overwrite the
  first's entries in place. RegisterExternal is idempotent (it looks the proc up
  in ExternalProc and returns the existing index), the Xtensa emitter never
  touches the data section at all, and LibcSyscallCallCount is x86-64 only.
  Anything added to this backend that appends to a NEW table must be saved here
  too, or the discarded pass leaves relocations pointing into overwritten code. }
var i, lblId, pos, f, procIdx, skipPos: Integer;
    LabelFixupCount: Integer;
    saveCodeLen, saveCodeRef, saveFix, saveGlobFix: Integer;
    saveCallFix, saveDynCall, saveIramFix: Integer;
    saveSpillDepth, saveSpillMax, attempt: Integer;
    needRetry: Boolean;
begin
  saveCodeLen := CodeLen;
  saveCodeRef := CodeRefCount;
  saveFix := FixCount;
  saveGlobFix := GlobFixCount;
  saveCallFix := CallFixCount;
  saveDynCall := DynCallCount;
  saveIramFix := IramCallFixCount;
  saveSpillDepth := XtSpillDepth;
  saveSpillMax := XtSpillMax;
  for i := 0 to IRLabelCount - 1 do
    XtWideLabel[i] := False;
  attempt := 0;

  repeat
  Inc(attempt);
  CodeLen := saveCodeLen;
  CodeRefCount := saveCodeRef;
  FixCount := saveFix;
  GlobFixCount := saveGlobFix;
  CallFixCount := saveCallFix;
  DynCallCount := saveDynCall;
  IramCallFixCount := saveIramFix;
  XtSpillDepth := saveSpillDepth;
  XtSpillMax := saveSpillMax;

  { Nil-init hidden owning locals synthesised during IR lowering (see the
    riscv32/x86-64 walkers) — the epilogue's scope-exit DecRef would otherwise
    release stale stack bytes when the temp's own path never ran. }
  if CurProc >= 0 then
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if SymIsHiddenArgTemp[i] and (Syms[i].Kind = skLocal) then
      begin
        if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
           (RecSize(SymTR[i].RecId) > TARGET_PTR_SIZE) then
        begin
          EmitSlotAddrXtensa(reg_xtensa_a2, i);
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
            EmitLoadConstXtensa(reg_xtensa_a11, RecSize(SymTR[i].RecId));
          end
          else
            EmitLoadConstXtensa(reg_xtensa_a3, RecSize(SymTR[i].RecId));
          EmitCallProc(procIdx);
        end
        else
        begin
          EmitSlotAddrXtensa(reg_xtensa_a8, i);
          xtensa_movi(reg_xtensa_a9, 0);
          xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, 0);
        end;
      end;
  { Clear only this body's labels ([0, IRLabelCount) — see IREmitMachineCode). }
  for i := 0 to IRLabelCount - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_LABEL:
        begin
          lblId := Integer(IRIVal[i]);
          if (lblId >= 0) and (lblId < MAX_IR) then
            LabelPositions[lblId] := CodeLen;
        end;

      IR_JUMP:
        EmitXtensaJumpToLabel(IRA[i], LabelFixupCount);

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeXtensa(IRB[i]);
          { Conditional branch range is only +-127 bytes, so branch over an
            18-bit J: if cond <> 0 skip the J, else J label. }
          xtensa_movi(reg_xtensa_a4, 0);
          skipPos := CodeLen;
          xtensa_bne(reg_xtensa_a2, reg_xtensa_a4, 6);      { patched below }
          EmitXtensaJumpToLabel(lblId, LabelFixupCount);
          XtensaPatchSkipOver(skipPos, 9, reg_xtensa_a2, reg_xtensa_a4);
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeXtensa(i);
        end;

      IR_CALL_IND:
        begin
          if IRStmtRoot[i] then
            IREmitNodeXtensa(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeXtensa(i);

      { try/except (feature-esp-bare-exceptions), Call0 only: the windowed
        ABI would need the register windows spilled before a longjmp-style sp
        rewind, which bare-metal has no handlers for. Mirrors riscv32. }
      IR_EXC_ENTER:
        begin
          if XtensaABI = XTENSA_ABI_WINDOWED then
            Error('target xtensa: try/except requires the Call0 ABI (windowed needs register-window spills before unwind)');
          { try: push a 32-byte frame ([0]=prev EXC_TOP, jmpbuf at +8), chain
            it, setjmp; a raise longjmps back here with a2=1 -> jump to the
            handler label (beq-skip + j, so the handler can be far). }
          lblId := IRA[i];
          xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -EXC_FRAME_SIZE_XT);
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_TOP);
          xtensa_l32i(reg_xtensa_a4, reg_xtensa_a3, 0);
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_sp, 0);
          xtensa_s32i(reg_xtensa_sp, reg_xtensa_a3, 0);
          xtensa_addi(reg_xtensa_a2, reg_xtensa_sp, EXC_JMP_OFFSET_XT);
          EmitXtensaCallToCode(ExcSetJmpAddr);
          xtensa_movi(reg_xtensa_a4, 0);
          skipPos := CodeLen;
          xtensa_beq(reg_xtensa_a2, reg_xtensa_a4, 6);   { 0 = normal: skip }
          EmitXtensaJumpToLabel(lblId, LabelFixupCount);
          XtensaPatchSkipOver(skipPos, 1, reg_xtensa_a2, reg_xtensa_a4);
        end;

      IR_EXC_LEAVE:
        IREmitLeaveExceptionFramesXtensa(IRA[i]);

      IR_RAISE:
        begin
          if XtensaABI = XTENSA_ABI_WINDOWED then
            Error('target xtensa: try/except requires the Call0 ABI (windowed needs register-window spills before unwind)');
          if IRA[i] <> -1 then
          begin
            IREmitNodeXtensa(IRA[i]);                    { a2 = exception object }
            EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_OBJ);
            xtensa_s32i(reg_xtensa_a2, reg_xtensa_a3, 0);
            EmitLoadConstXtensa(reg_xtensa_a2, Integer(IRIVal[i]));   { class idx }
            EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_CLS);
            xtensa_s32i(reg_xtensa_a2, reg_xtensa_a3, 0);
          end;
          EmitXtensaCallToCode(ExcRaiseAddr);
        end;

      IR_EXC_STORE:
        begin
          { `on E: EFoo do`: store the raised object into E's slot. }
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, IRExcStoreSlot(i));
          xtensa_l32i(reg_xtensa_a4, reg_xtensa_a3, 0);
          EmitSlotAddrXtensa(reg_xtensa_a8, IRA[i]);
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_a8, 0);
        end;

      IR_EXC_MATCH:
        begin
          { jump to the label when the raised class <> this clause's class }
          lblId := IRA[i];
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_CLS);
          xtensa_l32i(reg_xtensa_a3, reg_xtensa_a3, 0);
          EmitLoadConstXtensa(reg_xtensa_a4, Integer(IRIVal[i]));
          skipPos := CodeLen;
          xtensa_beq(reg_xtensa_a3, reg_xtensa_a4, 6);   { equal: skip the jump }
          EmitXtensaJumpToLabel(lblId, LabelFixupCount);
          XtensaPatchSkipOver(skipPos, 1, reg_xtensa_a3, reg_xtensa_a4);
        end;

      IR_EXC_MATCH_HIT:
        begin
          { jump to the label when the raised class = this clause's class }
          lblId := IRA[i];
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_CLS);
          xtensa_l32i(reg_xtensa_a3, reg_xtensa_a3, 0);
          EmitLoadConstXtensa(reg_xtensa_a4, Integer(IRIVal[i]));
          skipPos := CodeLen;
          xtensa_bne(reg_xtensa_a3, reg_xtensa_a4, 6);   { not equal: skip it }
          EmitXtensaJumpToLabel(lblId, LabelFixupCount);
          XtensaPatchSkipOver(skipPos, 9, reg_xtensa_a3, reg_xtensa_a4);
        end;

      IR_EXC_CLEAR:
        begin
          xtensa_movi(reg_xtensa_a4, 0);
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_OBJ);
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_a3, 0);
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_CLS);
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_a3, 0);
          EmitLoadGlobAddrXtensa(reg_xtensa_a3, BSS_EXC_ADDR);
          xtensa_s32i(reg_xtensa_a4, reg_xtensa_a3, 0);
        end;

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK, IR_CONST_DATA,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SLOTADDR, IR_FIELD, IR_INDEX: ;
      { IR_ATOMIC is a value node consumed by its parent store, like
        IR_SYSCALL. Emitting it at statement level TOO runs the
        read-modify-write twice — riscv32 and arm32 both paid for this one. }
      IR_ATOMIC: ;

      else
        IREmitNodeXtensa(i);
    end;
  end;

  { Did every three-byte guess hold? A slot that did not reach is not an error
    any more -- it is the input to the next pass. }
  needRetry := False;
  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    if LabelPositions[lblId] = -1 then
      Error('Unresolved forward jump in Xtensa IR codegen');
    if (LabelFixupAnchor[f] = -1) and
       not XtensaJReaches(LabelFixupPos[f], LabelPositions[lblId]) then
    begin
      XtWideLabel[lblId] := True;
      needRetry := True;
    end;
  end;
  if needRetry and (attempt >= XT_MAX_RELAX_PASSES) then
    Error('target xtensa: forward-jump relaxation did not settle in ' +
          AIntToStr(XT_MAX_RELAX_PASSES) + ' passes. A forward jump still '
          + 'cannot reach its label with the long form reserved, which should '
          + 'not be possible -- the long form reaches +-2 GB');
  until not needRetry;

  { CurProc is -1 for the program's MAIN body, which is exactly the body a
    generated far-forward-jump repro puts everything in -- so a `CurProc >= 0`
    guard here would have made this instrument unable to fire in the one case it
    exists to report, and it would have printed nothing and read as "it did not
    fire". Caught by asking it about a program that provably relaxes.
    The one instrument that answers "did the relaxation fire, and how wide did
    it end up" without counting instructions in the artifact -- a mnemonic count
    off a disassembly is NOT an enumeration here, because this backend embeds
    4-byte literals in .text and objdump resyncs across them. Measured: for the
    same program a byte-pattern count and an objdump mnemonic count disagreed,
    and each was right for one ABI. `PXXDBG=a.xtrelax:*` asks the emitter --
    note the `:*`, without which PxxDbgWants reads the topic as empty and this
    can never print, which is not distinguishable from "it did not fire". }
  if (attempt > 1) and
     PxxDbgWants('a.xtrelax', XtRelaxBodyName) then
  begin
    pos := 0;
    for f := 0 to LabelFixupCount - 1 do
      if LabelFixupAnchor[f] <> -1 then Inc(pos);
    writeln('a.xtrelax: ', XtRelaxBodyName, ': ', AIntToStr(attempt),
            ' passes, ', AIntToStr(pos), ' of ', AIntToStr(LabelFixupCount),
            ' forward jumps widened, body ', AIntToStr(CodeLen - saveCodeLen),
            ' bytes');
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    if LabelFixupAnchor[f] = -1 then
      Patch24(pos, EncodeXtensaJ(LabelPositions[lblId] - pos))
    else
      Patch32(pos, LabelPositions[lblId] - LabelFixupAnchor[f]);
  end;
end;
