{ ---- GNU / AT&T inline-asm template reader, x86-64 ------------------------

  A GNU inline-asm template is TEXT in AT&T syntax. asmenc.inc's x86-64 engine
  is Intel syntax and reads TOKENS from the Pascal lexer, so the two share no
  surface at all: `movq 1*8(%0), %3` against `mov rdx, [rax+8]`. That gap is the
  whole of this file. It is NOT a second assembler -- every instruction it
  reads is handed to AsmDispatch, the one encoder, with the same AsmOp* globals
  AsmParseOperand fills. A construct reachable through two shapes gets
  normalised here rather than growing a second encoding path, because the
  second path is the one that stays broken.

  Note the asymmetry that makes this file necessary for x86-64 and not for the
  other five targets: i386, aarch64, arm32, xtensa and riscv32 go through
  AsmParseBodyText*, which emits TEXT LINES for a per-target engine to read at
  codegen, so a template could in principle be handed to them nearly as
  written. x86-64 encodes into AsmBytes at parse time and never sees text.

  WHAT IS DELIBERATELY NOT HERE. Labels and branches: a template that jumps
  needs a target, and pxx resolves asm labels within one asm statement, so a
  local label is buildable but nothing asks for one yet. Symbols: an operand
  naming a C global. `%N` operand substitution is refused HERE and implemented
  by the caller's binding table -- this file only reports that a placeholder
  was seen, so the operand work can land separately from the syntax work.

  feature-c-gnu-inline-asm-with-a-non-empty-template }

const
  { How a `%N` in the template resolves. The caller binds each operand to a
    fixed register BEFORE encoding -- see the pinning note in
    feature-c-gnu-inline-asm-with-a-non-empty-template -- so substitution never
    has to happen as text and never has to wait for codegen. }
  ATTBIND_NONE = 0;
  ATTBIND_REG  = 1;   { %N is a register: `"r"`, `"rm"`, `"a"` and friends }
  ATTBIND_MEM  = 2;   { %N is the FRAME SLOT at AttBindOff[n]: `"m"` }
  ATTBIND_IMM  = 3;   { %N is the constant AttBindImm[n]: `"i"`, `"n"` }
  ATTBIND_MEMREG = 4; { %N is `(reg)`, reg holding the object's address: an `"m"` dereference }
  ATT_MAX_LABELS = 64;

var
  AttSrc     : AnsiString;   { the template being read }
  AttPos     : Integer;      { 1-based cursor into AttSrc }
  AttExtended: Boolean;      { extended asm: `%%` is an escaped `%`, `%N` an operand }
  AttMaxOpnd : Integer;      { highest %N seen, or -1 -- the caller checks it }
  AttBindKind: array[0..MAX_CASM_OPERANDS-1] of Integer;
  AttBindReg : array[0..MAX_CASM_OPERANDS-1] of Integer;
  AttBindSize: array[0..MAX_CASM_OPERANDS-1] of Integer;  { bytes; 0 = let the suffix say }
  { ATTBIND_MEM only: the operand's frame offset, i.e. the disp of [rbp+disp32].
    It is a SEPARATE lane from AttBindReg on purpose -- parking an offset in a
    field named Reg is how a value gets read as the thing its name promises. }
  AttBindOff : array[0..MAX_CASM_OPERANDS-1] of Integer;
  AttBindImm : array[0..MAX_CASM_OPERANDS-1] of Int64;
  { `[name] "c"(expr)` -- the name a template spells as %[name]. }
  AttBindName: array[0..MAX_CASM_OPERANDS-1] of AnsiString;
  AttBindCount: Integer;
  { Numeric local labels (`1:`, referenced as `1b` / `1f`), per template.
    Ordinals, not byte offsets, decide b and f: a label written just before
    an instruction shares that instruction's start offset, and gas reads
    `1b` there as the label, `1f` as the NEXT definition. }
  AttInstrOrd : Integer;
  AttLblCount : Integer;
  AttLblNum, AttLblOrd, AttLblPos : array[0..ATT_MAX_LABELS-1] of Integer;
  AttFixCount : Integer;
  AttFixPos, AttFixEnd, AttFixNum, AttFixOrd : array[0..ATT_MAX_LABELS-1] of Integer;
  AttFixFwd : array[0..ATT_MAX_LABELS-1] of Boolean;
  AttPendLblNum : Integer;     { label of the AOP_RIPLBL operand being encoded }
  AttPendLblFwd : Boolean;
  { The GNU as frontend (gasfront.inc) reads instructions through this same
    reader, with three liberties an inline-asm template never needs: a bare
    absolute address, a memory operand with no base, and -- under `.code32` --
    32-bit address registers. Off for every inline-asm statement. }
  AttGasMode   : Boolean;
  AttGasCode32 : Boolean;

{ Clear every binding. Called on its own for an operand-free template, so a
  stale binding from an earlier statement can never satisfy a `%N`. }
procedure AttResetBindings;
var i: Integer;
begin
  for i := 0 to MAX_CASM_OPERANDS - 1 do
  begin
    AttBindKind[i] := ATTBIND_NONE;
    AttBindReg[i] := 0;
    AttBindSize[i] := 0;
    AttBindOff[i] := 0;
    AttBindImm[i] := 0;
    AttBindName[i] := '';
  end;
  AttBindCount := 0;
end;

procedure AttBindOperand(n, kind, reg, size, off: Integer);
begin
  AttBindKind[n] := kind;
  AttBindReg[n] := reg;
  AttBindSize[n] := size;
  AttBindOff[n] := off;
  if n >= AttBindCount then AttBindCount := n + 1;
end;

procedure AttBindImmOperand(n: Integer; v: Int64);
begin
  AttBindOperand(n, ATTBIND_IMM, 0, 0, 0);
  AttBindImm[n] := v;
end;

procedure AttNameOperand(n: Integer; const nm: AnsiString);
begin
  AttBindName[n] := nm;
end;

{ ---- the i386 sink: the same parse, rendered as TEXT ----------------------

  x86-64 encodes an inline-asm block into AsmBytes at PARSE time and an AN_ASM
  node's Left/Right name that byte span. Every other target captures TEXT LINES
  that its own engine assembles at CODEGEN, and there the same two fields name a
  line span. The convention is per-target and there is exactly one of it per
  target, which is the property worth keeping.

  So an i386 GNU template is read by the SAME AT&T parser -- one syntax reader,
  not two -- and only the last step changes: instead of handing the parsed
  AsmOp* slots to AsmDispatch, this renders them as the Intel line
  AsmParseBodyText386 would have captured, and asmtext_386.inc assembles it.
  Giving i386's IR_ASM a second, byte-span form was the alternative; it is less
  code and it puts two mechanisms behind one concept on one target, which is the
  smell normalise-dont-special-case.md is about.

  WHAT THIS DELIBERATELY DOES NOT DO is encode i386 bytes here. It would work --
  the forms these templates use are byte-identical in both modes, measured with
  gas -- and it would mean this file quietly assembling for a target whose
  assembler is somewhere else. The one engine per target stays the one engine.

  Mnemonics are whitelisted rather than passed through. asmtext_386.inc reports
  an unknown mnemonic at CODEGEN, which is a long way from the template that
  wrote it; the list below fails at parse time with the offending word. It is
  the same "a narrower feature with an honest refusal" rule the constraint
  classes follow. }

var
  AttSinkText: Boolean;   { render Intel lines for asmtext_386 instead of bytes }

function AttRegName386(num, size: Integer): AnsiString;
begin
  Result := '';
  if size = 4 then
  begin
    if num = 0 then Result := 'eax' else if num = 1 then Result := 'ecx'
    else if num = 2 then Result := 'edx' else if num = 3 then Result := 'ebx'
    else if num = 4 then Result := 'esp' else if num = 5 then Result := 'ebp'
    else if num = 6 then Result := 'esi' else if num = 7 then Result := 'edi';
  end
  else if size = 2 then
  begin
    if num = 0 then Result := 'ax' else if num = 1 then Result := 'cx'
    else if num = 2 then Result := 'dx' else if num = 3 then Result := 'bx'
    else if num = 4 then Result := 'sp' else if num = 5 then Result := 'bp'
    else if num = 6 then Result := 'si' else if num = 7 then Result := 'di';
  end
  else if size = 1 then
  begin
    { Only the four low-byte names exist without a REX prefix; 4..7 at this
      width are ah/ch/dh/bh, which name a DIFFERENT part of the register and
      are not what an operand pinned to esi could ever have meant. }
    if num = 0 then Result := 'al' else if num = 1 then Result := 'cl'
    else if num = 2 then Result := 'dl' else if num = 3 then Result := 'bl'
    else
      Error('C: inline asm on i386 has no low-byte name for register '
            + AIntToStr(num) + ' — only al, cl, dl and bl exist');
  end
  else
    Error('C: inline asm on i386 has no ' + AIntToStr(size * 8)
          + '-bit register — a 64-bit operand needs a 64-bit target');
  if Result = '' then
    Error('C: inline asm on i386 has no register number ' + AIntToStr(num));
end;

function AttSizeKw386(size: Integer): AnsiString;
begin
  if size = 1 then Result := 'byte'
  else if size = 2 then Result := 'word'
  else if size = 4 then Result := 'dword'
  else
  begin
    Error('C: inline asm on i386 cannot address ' + AIntToStr(size)
          + ' bytes of memory in one instruction');
    Result := '';
  end;
end;

{ A signed displacement, written so AsmTextOperand's split-on-first-+/- reads
  it back as the same number. }
function AttDisp386(d: Int64): AnsiString;
begin
  if d < 0 then Result := '-' + AsmEncIntToStr(-d)
  else Result := '+' + AsmEncIntToStr(d);
end;

function AttRender386(slot: Integer): AnsiString;
begin
  Result := '';
  if AsmOpKind[slot] = AOP_REG then
    Result := AttRegName386(AsmOpReg[slot], AsmOpSize[slot])
  else if AsmOpKind[slot] = AOP_IMM then
    Result := AsmEncIntToStr(AsmOpVal[slot])
  else if AsmOpKind[slot] = AOP_MEM then
    { A frame slot. The size keyword is always written: the i386 engine refuses
      a memory ALU or `mul` operand whose width nothing else fixes, and a
      keyword next to a register that already fixes it is harmless. }
    Result := AttSizeKw386(AsmOpSize[slot]) + ' [ebp'
              + AttDisp386(AsmOpVal[slot]) + ']'
  else if AsmOpKind[slot] = AOP_MEMR then
  begin
    if AsmOpIndex[slot] >= 0 then
      Error('C: inline asm on i386 cannot write [base+index*scale]'
            + ' — the i386 text engine has no SIB form');
    Result := AttSizeKw386(AsmOpSize[slot]) + ' ['
              + AttRegName386(AsmOpReg[slot], 4)
              + AttDisp386(AsmOpVal[slot]) + ']';
  end
  else
    Error('C: inline asm on i386 has an operand form the text sink'
          + ' cannot write');
end;

{ The mnemonics asmtext_386.inc actually assembles. Kept here rather than
  exported from there because this is a statement about what THIS path may
  emit, and a wider list would only move the failure to codegen. }
function AttKnows386(const mn: AnsiString): Boolean;
begin
  Result := CaseEqual(mn,'mov') or CaseEqual(mn,'lea')
    or CaseEqual(mn,'add') or CaseEqual(mn,'adc') or CaseEqual(mn,'sub')
    or CaseEqual(mn,'sbb') or CaseEqual(mn,'and') or CaseEqual(mn,'or')
    or CaseEqual(mn,'xor') or CaseEqual(mn,'cmp') or CaseEqual(mn,'test')
    or CaseEqual(mn,'mul') or CaseEqual(mn,'imul') or CaseEqual(mn,'div')
    or CaseEqual(mn,'idiv') or CaseEqual(mn,'neg') or CaseEqual(mn,'not')
    or CaseEqual(mn,'inc') or CaseEqual(mn,'dec')
    or CaseEqual(mn,'shl') or CaseEqual(mn,'sal') or CaseEqual(mn,'shr')
    or CaseEqual(mn,'sar') or CaseEqual(mn,'rol') or CaseEqual(mn,'ror')
    or CaseEqual(mn,'push') or CaseEqual(mn,'pop')
    or CaseEqual(mn,'movzx') or CaseEqual(mn,'movsx')
    or CaseEqual(mn,'nop') or CaseEqual(mn,'cdq') or CaseEqual(mn,'leave')
    or CaseEqual(mn,'ret') or CaseEqual(mn,'cpuid')
    or CaseEqual(mn,'lfence') or CaseEqual(mn,'mfence') or CaseEqual(mn,'sfence');
end;

{ The one seam. Either the x86-64 byte encoder or the i386 text sink; the parse
  above this point is identical for both. }
function AttEmitInstr(const mn: AnsiString; nops: Integer): Boolean;
var line: AnsiString;
begin
  if not AttSinkText then
  begin
    Result := AsmDispatch(mn, nops);
    Exit;
  end;
  if not AttKnows386(mn) then begin Result := False; Exit; end;
  if nops > 2 then
    Error('C: inline asm on i386 cannot write the three-operand form of ' + mn);
  line := mn;
  if nops >= 1 then line := line + ' ' + AttRender386(0);
  if nops >= 2 then line := line + ',' + AttRender386(1);
  AsmAddInlineLine(line, 0, 0);
  Result := True;
end;

{ The span an AN_ASM node carries is whatever its TARGET's convention says --
  AsmBytes on x86-64, InlineAsmLine everywhere else. Reading the wrong counter
  here would not error; it would name a real span of the wrong thing. }
procedure AttBeginBlock(var startOff: Integer);
begin
  if AttSinkText then startOff := InlineAsmLineCount
  else startOff := AsmBytesCount;
end;

procedure AttEndBlock(startOff: Integer; var len: Integer);
begin
  if AttSinkText then len := InlineAsmLineCount - startOff
  else len := AsmBytesCount - startOff;
end;

{ ---- character-level scanning ---- }

function AttAtEnd: Boolean;
begin
  Result := AttPos > Length(AttSrc);
end;

function AttPeek: Char;
begin
  if AttAtEnd then Result := Chr(0) else Result := AttSrc[AttPos];
end;

function AttPeek2: Char;
begin
  if AttPos + 1 > Length(AttSrc) then Result := Chr(0)
  else Result := AttSrc[AttPos + 1];
end;

function AttIsHSpace(c: Char): Boolean;
begin
  Result := (c = ' ') or (c = Chr(9)) or (c = Chr(13));
end;

function AttIsDigit(c: Char): Boolean;
begin
  Result := (c >= '0') and (c <= '9');
end;

function AttIsAlpha(c: Char): Boolean;
begin
  Result := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))
            or (c = '_') or (c = '.');
end;

{ Horizontal whitespace and comments, never a newline: a newline separates
  instructions and the line loop has to see it. GNU as treats `#` as a comment
  to end of line on x86; `/* */` and `//` are accepted too because a template
  is C text and people write C comments in it. }
procedure AttSkipSpace;
begin
  while not AttAtEnd do
  begin
    if AttIsHSpace(AttPeek) then Inc(AttPos)
    else if AttPeek = '#' then
      while (not AttAtEnd) and (AttPeek <> Chr(10)) do Inc(AttPos)
    else if (AttPeek = '/') and (AttPeek2 = '/') then
      while (not AttAtEnd) and (AttPeek <> Chr(10)) do Inc(AttPos)
    else if (AttPeek = '/') and (AttPeek2 = '*') then
    begin
      Inc(AttPos, 2);
      while (not AttAtEnd) and not ((AttPeek = '*') and (AttPeek2 = '/')) do Inc(AttPos);
      if AttAtEnd then Error('C: inline asm template has an unterminated /* comment');
      Inc(AttPos, 2);
    end
    else Exit;
  end;
end;

{ True at an instruction separator: end of template, a newline, or `;`, which
  GNU as accepts as a statement separator on x86. }
function AttAtSeparator: Boolean;
begin
  Result := AttAtEnd or (AttPeek = Chr(10)) or (AttPeek = ';');
end;

procedure AttSkipSeparators;
begin
  while (not AttAtEnd) and (AttAtSeparator or AttIsHSpace(AttPeek)) do
  begin
    if AttIsHSpace(AttPeek) then AttSkipSpace else Inc(AttPos);
  end;
end;

function AttReadWord: AnsiString;
begin
  Result := '';
  while (not AttAtEnd) and (AttIsAlpha(AttPeek) or AttIsDigit(AttPeek)) do
  begin
    Result := Result + AttPeek;
    Inc(AttPos);
  end;
end;

{ ---- the constant expressions a displacement may be written as -------------

  `1*8(%0)` and `2*4(%0)` are how tls_sp_c32.c writes every limb offset, so
  folding `*` is not optional. GNU as folds the full C precedence set here;
  this handles + - * / and parenthesised subexpressions, which is everything a
  displacement is ever written with, and refuses the rest by name rather than
  guessing a precedence. }

function AttParseAddExpr: Int64; forward;

function AttParseNumber: Int64;
var v: Int64; d: Integer; sawDigit: Boolean;
begin
  v := 0;
  sawDigit := False;
  if (AttPeek = '0') and ((AttPeek2 = 'x') or (AttPeek2 = 'X')) then
  begin
    Inc(AttPos, 2);
    while not AttAtEnd do
    begin
      d := -1;
      if AttIsDigit(AttPeek) then d := Ord(AttPeek) - Ord('0')
      else if (AttPeek >= 'a') and (AttPeek <= 'f') then d := Ord(AttPeek) - Ord('a') + 10
      else if (AttPeek >= 'A') and (AttPeek <= 'F') then d := Ord(AttPeek) - Ord('A') + 10;
      if d < 0 then Break;
      v := v * 16 + d;
      sawDigit := True;
      Inc(AttPos);
    end;
    if not sawDigit then Error('C: inline asm template has a 0x with no digits after it');
    Result := v;
    Exit;
  end;
  while (not AttAtEnd) and AttIsDigit(AttPeek) do
  begin
    v := v * 10 + (Ord(AttPeek) - Ord('0'));
    sawDigit := True;
    Inc(AttPos);
  end;
  if not sawDigit then Error('C: inline asm template expected a number');
  Result := v;
end;

function AttParsePrimary: Int64;
begin
  AttSkipSpace;
  if AttPeek = '(' then
  begin
    Inc(AttPos);
    Result := AttParseAddExpr;
    AttSkipSpace;
    if AttPeek <> ')' then Error('C: inline asm template expected ) in a displacement');
    Inc(AttPos);
    Exit;
  end;
  { The empty parens are load-bearing, not style: a BARE own name in this
    dialect reads Result rather than recursing, so `-AttParsePrimary` would
    negate an uninitialised Result and silently fold every `-8(%rbp)` to
    garbage. The compiler warns about it, and the warning is the whole reason
    this is written out. }
  if AttPeek = '-' then begin Inc(AttPos); Result := -AttParsePrimary(); Exit; end;
  if AttPeek = '+' then begin Inc(AttPos); Result := AttParsePrimary(); Exit; end;
  Result := AttParseNumber;
end;

function AttParseMulExpr: Int64;
var v, rhs: Int64; op: Char;
begin
  v := AttParsePrimary;
  AttSkipSpace;
  while (AttPeek = '*') or (AttPeek = '/') do
  begin
    op := AttPeek;
    Inc(AttPos);
    rhs := AttParsePrimary;
    if op = '*' then v := v * rhs
    else
    begin
      if rhs = 0 then Error('C: inline asm template divides by zero in a displacement');
      v := v div rhs;
    end;
    AttSkipSpace;
  end;
  Result := v;
end;

function AttParseAddExpr: Int64;
var v: Int64; op: Char;
begin
  v := AttParseMulExpr;
  AttSkipSpace;
  while (AttPeek = '+') or (AttPeek = '-') do
  begin
    op := AttPeek;
    Inc(AttPos);
    if op = '+' then v := v + AttParseMulExpr else v := v - AttParseMulExpr;
    AttSkipSpace;
  end;
  Result := v;
end;

{ ---- operands -------------------------------------------------------------

  `%` is the interesting character and it means three different things:

    %rax   a register           (basic asm, or after a `%%` escape)
    %%rax  a register           (extended asm -- `%%` IS the escape)
    %0     operand 0            (extended asm only)

  gcc's rule is that `%` is only special when the statement HAS operand
  sections. A basic `asm("movq %rax, %rbx")` -- no colons anywhere -- passes
  its template through untouched, which is why `%%` there would be an error
  rather than an escape. AttExtended carries that distinction rather than
  guessing from what the text looks like. }

{ Read a register reference, cursor sitting on its leading `%`. ONE place
  decides how many `%` a register wears, so the memory-operand path and the
  top-level operand path cannot drift apart on it: extended asm requires the
  `%%` escape, basic asm forbids it. Being lenient about that would mean
  reading `%b0` -- an operand with a size modifier -- as a register named b0. }
{ es cs ss ds fs gs, numbered as ModRM.reg names them in 8C/8E; -1 if none. }
function AttSegRegNum(const nm: AnsiString): Integer;
begin
  Result := -1;
  if (Length(nm) <> 2) or (AsmRegLower(nm[2]) <> 's') then Exit;
  case AsmRegLower(nm[1]) of
    'e': Result := 0;
    'c': Result := 1;
    's': Result := 2;
    'd': Result := 3;
    'f': Result := 4;
    'g': Result := 5;
  end;
end;

{ cr0 cr2 cr3 cr4 cr8 -- the control registers that exist in long mode. }
function AttCtlRegNum(const nm: AnsiString): Integer;
begin
  Result := -1;
  if (Length(nm) <> 3) or (AsmRegLower(nm[1]) <> 'c') or (AsmRegLower(nm[2]) <> 'r') then Exit;
  case nm[3] of
    '0': Result := 0;
    '2': Result := 2;
    '3': Result := 3;
    '4': Result := 4;
    '8': Result := 8;
  end;
end;

procedure AttParseRegisterRef(slot: Integer);
var nm: AnsiString; num, size: Integer;
begin
  if AttPeek <> '%' then Error('C: inline asm template expected a register');
  Inc(AttPos);
  if AttExtended then
  begin
    if AttPeek <> '%' then
      Error('C: inline asm template needs %% before a register name in an'
            + ' extended asm statement (one % introduces an operand)');
    Inc(AttPos);
  end;
  nm := AttReadWord;
  if nm = '' then Error('C: inline asm template expected a register name after %');
  num := AttSegRegNum(nm);
  if num >= 0 then
  begin
    AsmOpKind[slot] := AOP_SREG; AsmOpReg[slot] := num; AsmOpSize[slot] := 2;
    Exit;
  end;
  num := AttCtlRegNum(nm);
  if num >= 0 then
  begin
    AsmOpKind[slot] := AOP_CREG; AsmOpReg[slot] := num; AsmOpSize[slot] := 8;
    Exit;
  end;
  if not AsmRegNum(nm, num, size) then
    Error('C: inline asm template has an unknown register: ' + nm);
  AsmOpKind[slot] := AOP_REG;
  AsmOpReg[slot] := num;
  AsmOpSize[slot] := size;
end;

function AttReadOperandNumber: Integer; forward;

{ Inside ( ), a register may be written directly or named by an operand:
  `1*8(%0)` is how tls_sp_c32.c reaches every limb, and %0 there is an `"r"`
  operand holding a pointer. Both spellings land in the same slot as a plain
  register, so the memory parser below does not need to know which it got. }
procedure AttParseBaseOrOperand(slot: Integer);
var n: Integer;
begin
  if AttExtended and (AttPeek = '%') and AttIsDigit(AttPeek2) then
  begin
    Inc(AttPos);
    n := AttReadOperandNumber;
    if AttBindKind[n] <> ATTBIND_REG then
      Error('C: inline asm template uses the memory operand %' + AIntToStr(n)
            + ' as an address register');
    AsmOpKind[slot] := AOP_REG;
    AsmOpReg[slot] := AttBindReg[n];
    AsmOpSize[slot] := AttBindSize[n];
    Exit;
  end;
  AttParseRegisterRef(slot);
end;

{ A memory operand: [disp] ( base [, index [, scale]] ). AT&T also writes a
  bare `disp` for an absolute address and `sym(%rip)` for a symbol; neither is
  read here, and both refuse by name below rather than encoding something
  plausible. }
procedure AttParseMemory(slot: Integer; disp: Int64; sawDisp: Boolean);
var num, size, idxNum, idxSize, addrSize: Integer; scale: Int64;
begin
  { AttPos is on '(' }
  Inc(AttPos);
  AttSkipSpace;
  { An address register is as wide as an address: 8 on x86-64, 4 on i386 --
    and 4 under the GNU as frontend's `.code32`, where the register's NUMBER
    encodes exactly as the 64-bit one with no 0x67 prefix. }
  addrSize := TARGET_PTR_SIZE;
  if AttGasMode then
    if AttGasCode32 then addrSize := 4 else addrSize := 8;
  if AttGasMode and (AttPeek = ',') then
  begin
    num := -1;               { `disp(,%idx,s)`: no base }
    size := addrSize;
  end
  else
  begin
    AttParseBaseOrOperand(slot);
    num := AsmOpReg[slot];
    size := AsmOpSize[slot];
  end;
  { An address register is as wide as an address. That is 8 on x86-64 and 4 on
    i386, and it is not a matter of taste: `(%eax)` in 64-bit mode is a
    different, address-size-prefixed encoding, and `(%rax)` does not exist in
    32-bit mode at all. }
  if size <> addrSize then
    Error('C: inline asm template needs a ' + AIntToStr(addrSize * 8)
          + '-bit base register inside ( )');
  idxNum := -1; scale := 1;
  AttSkipSpace;
  if AttPeek = ',' then
  begin
    Inc(AttPos);
    AttSkipSpace;
    AttParseBaseOrOperand(slot);
    idxNum := AsmOpReg[slot];
    idxSize := AsmOpSize[slot];
    if AttGasMode and (idxSize <> addrSize) then
      Error('asm: needs a ' + AIntToStr(addrSize * 8) + '-bit index register inside ( )');
    if (not AttGasMode) and (idxSize <> 8) then
      Error('C: inline asm template needs a 64-bit index register inside ( )');
    AttSkipSpace;
    if AttPeek = ',' then
    begin
      Inc(AttPos);
      AttSkipSpace;
      scale := AttParseAddExpr;
      if (scale <> 1) and (scale <> 2) and (scale <> 4) and (scale <> 8) then
        Error('C: inline asm template memory scale must be 1, 2, 4 or 8');
      AttSkipSpace;
    end;
  end;
  if AttPeek <> ')' then Error('C: inline asm template expected ) to close a memory operand');
  Inc(AttPos);
  AsmOpKind[slot] := AOP_MEMR;
  AsmOpReg[slot] := num;
  AsmOpIndex[slot] := idxNum;
  AsmOpScale[slot] := Integer(scale);
  if sawDisp then AsmOpVal[slot] := disp else AsmOpVal[slot] := 0;
  AsmOpSize[slot] := 0;   { the mnemonic's suffix supplies it }
end;

{ Read the digits of a `%N` and check that the caller actually bound operand
  N. An unbound one is the difference between substituting a register and
  substituting whatever happened to be in the table, so it refuses rather than
  defaulting. }
function AttReadOperandNumber: Integer;
var n: Integer;
begin
  n := 0;
  while (not AttAtEnd) and AttIsDigit(AttPeek) do
  begin
    n := n * 10 + (Ord(AttPeek) - Ord('0'));
    Inc(AttPos);
    if n >= MAX_CASM_OPERANDS then Break;
  end;
  if n > AttMaxOpnd then AttMaxOpnd := n;
  if AttBindCount = 0 then
    Error('C: inline asm template uses %' + AIntToStr(n)
          + ' but the statement declares no operands');
  if (n >= AttBindCount) or (AttBindKind[n] = ATTBIND_NONE) then
    Error('C: inline asm template uses %' + AIntToStr(n)
          + ', which is not one of its ' + AIntToStr(AttBindCount) + ' operands');
  Result := n;
end;

{ `%[name]` -> the operand's number. The cursor is on the '['. }
function AttReadNamedOperand: Integer;
var nm: AnsiString; i: Integer;
begin
  Inc(AttPos);
  nm := '';
  while (not AttAtEnd) and (AttPeek <> ']') do
  begin
    nm := nm + AttPeek;
    Inc(AttPos);
  end;
  if AttAtEnd then Error('C: inline asm template has an unclosed %[' + nm);
  Inc(AttPos);
  Result := -1;
  for i := 0 to AttBindCount - 1 do
    if (AttBindName[i] <> '') and (AttBindName[i] = nm) then Result := i;
  if Result < 0 then
    Error('C: inline asm template uses %[' + nm + '], which names no operand');
  if Result > AttMaxOpnd then AttMaxOpnd := Result;
end;

{ Is the text at the cursor a numeric label reference, `<digits>f` or
  `<digits>b`, followed by '('? Only the shape is checked; nothing moves. }
function AttAtLabelRef: Boolean;
var p: Integer;
begin
  Result := False;
  p := AttPos;
  if (p > Length(AttSrc)) or not AttIsDigit(AttSrc[p]) then Exit;
  while (p <= Length(AttSrc)) and AttIsDigit(AttSrc[p]) do Inc(p);
  if (p > Length(AttSrc)) or not ((AttSrc[p] = 'f') or (AttSrc[p] = 'b')) then Exit;
  Inc(p);
  while (p <= Length(AttSrc)) and AttIsHSpace(AttSrc[p]) do Inc(p);
  Result := (p <= Length(AttSrc)) and (AttSrc[p] = '(');
end;

{ `1f(%rip)` / `1b(%rip)`: the address of a numeric local label in this same
  template. Only rip may be the base: a label is a code address, and rip-
  relative is how 64-bit code names one without a relocation. }
procedure AttParseLabelRef(slot: Integer);
var n: Integer; nm: AnsiString;
begin
  if AttSinkText then
    Error('C: inline asm template references a local label, which the i386'
          + ' path does not support');
  n := 0;
  while AttIsDigit(AttPeek) do
  begin
    n := n * 10 + (Ord(AttPeek) - Ord('0'));
    Inc(AttPos);
  end;
  AttPendLblFwd := AttPeek = 'f';
  AttPendLblNum := n;
  Inc(AttPos);
  AttSkipSpace;
  Inc(AttPos);                                   { '(' }
  AttSkipSpace;
  if AttPeek <> '%' then Error('C: inline asm template expected %rip after a label');
  Inc(AttPos);
  if AttExtended then
  begin
    if AttPeek <> '%' then
      Error('C: inline asm template needs %% before rip in an extended asm statement');
    Inc(AttPos);
  end;
  nm := AttReadWord;
  if not CaseEqual(nm, 'rip') then
    Error('C: inline asm template can only address a local label as label(%rip)');
  AttSkipSpace;
  if AttPeek <> ')' then Error('C: inline asm template expected ) after %rip');
  Inc(AttPos);
  AsmOpKind[slot] := AOP_RIPLBL;
  AsmOpVal[slot] := 0;
  AsmOpSize[slot] := 0;
end;

{ Bind template slot `slot` to operand n, whatever kind it was bound as. }
procedure AttUseOperand(slot, n: Integer);
begin
  if AttBindKind[n] = ATTBIND_REG then
  begin
    AsmOpKind[slot] := AOP_REG;
    AsmOpReg[slot] := AttBindReg[n];
    AsmOpSize[slot] := AttBindSize[n];
  end
  else if AttBindKind[n] = ATTBIND_IMM then
  begin
    { gcc prints an "i" operand as `$value` in AT&T, so %0 IS the immediate }
    AsmOpKind[slot] := AOP_IMM;
    AsmOpVal[slot] := AttBindImm[n];
  end
  else if AttBindKind[n] = ATTBIND_MEMREG then
  begin
    AsmOpKind[slot] := AOP_MEMR;
    AsmOpReg[slot] := AttBindReg[n];
    AsmOpIndex[slot] := -1;
    AsmOpScale[slot] := 1;
    AsmOpVal[slot] := 0;
    AsmOpSize[slot] := AttBindSize[n];
  end
  else
  begin
    AsmOpKind[slot] := AOP_MEM;
    AsmOpReg[slot] := 0;
    AsmOpIndex[slot] := -1;
    AsmOpScale[slot] := 1;
    AsmOpVal[slot] := AttBindOff[n];
    AsmOpSize[slot] := AttBindSize[n];
  end;
end;

procedure AttParseOperand(slot: Integer);
var disp: Int64; n: Integer; modCh: Char;
begin
  AsmOpKind[slot] := AOP_NONE;
  AsmOpReg[slot] := 0; AsmOpSize[slot] := 0; AsmOpVal[slot] := 0;
  AsmOpIndex[slot] := -1; AsmOpScale[slot] := 1;
  AttSkipSpace;

  { immediate }
  if AttPeek = '$' then
  begin
    Inc(AttPos);
    AsmOpKind[slot] := AOP_IMM;
    AsmOpVal[slot] := AttParseAddExpr;
    Exit;
  end;

  if AttPeek = '%' then
  begin
    if AttExtended and (AttPeek2 <> '%') then
    begin
      Inc(AttPos);
      { %N, or a SIZE MODIFIER on it: %b0 is operand 0's low byte, %w0 its
        16-bit half. gcc calls these operand modifiers and they select a
        REGISTER WIDTH, not a different operand.

        THIS COMMENT USED TO LIST %b0 / %w0 / %k0 / %l0 AND THE CODE READ NONE
        OF THEM -- only a bare digit. The comment was the aspiration and the
        code was the truth, which is the pairing CLAUDE.md says to decide
        rather than reconcile. Decided by measuring: across every header on
        this box the modifiers that actually occur are %w1 (12), %b0 (6),
        %w0 (5) and %h0 (4), and no %k, %l, %q or %z at all. So b and w are
        built and the rest stay refused by name.

        %h IS DELIBERATELY NOT HERE and it is not an oversight -- it is the
        high byte (%ah/%ch/%dh/%bh), which this backend cannot NAME. At size 1
        EncPrefixAndREX FORCES a REX prefix for register numbers 4..7, because
        in the encoder's vocabulary those are spl/bpl/sil/dil; a REX prefix is
        also precisely what makes %ah unencodable. So emitting %h0 as
        (reg 4, size 1) would assemble silently to spl -- a wrong REGISTER with
        no diagnostic, which is the class this project treats as most
        expensive. It needs a high-byte operand kind in the shared x86-64
        encoder, which is Track A and is filed separately.
        bug-c-inline-asm-constraint-q-is-unsupported-and-it-blocks-every-sdl-header }
      if (AttPeek = 'b') or (AttPeek = 'w') then
      begin
        modCh := AttPeek;
        Inc(AttPos);
        if not AttIsDigit(AttPeek) then
          Error('C: inline asm template has a size modifier %' + modCh
                + ' that is not followed by an operand number');
        n := AttReadOperandNumber;
        if AttBindKind[n] <> ATTBIND_REG then
          Error('C: inline asm template applies the size modifier %' + modCh
                + ' to operand %' + AIntToStr(n) + ', which is a memory operand'
                + ' — a width modifier selects a register half');
        AsmOpKind[slot] := AOP_REG;
        AsmOpReg[slot] := AttBindReg[n];
        if modCh = 'b' then AsmOpSize[slot] := 1 else AsmOpSize[slot] := 2;
        Exit;
      end;
      { %h<n>: the HIGH byte of operand n -- %ah/%ch/%dh/%bh. The encoder
        numbers these 4..7 at size 1 with NO REX prefix, which is the same
        numbering the disassembler already prints
        ('al','cl','dl','bl','ah','ch','dh','bh', asmdisasm_x64.inc), so the
        high form of base register r is simply r + 4.

        ONLY a/b/c/d HAVE a high byte, and the refusal below is the whole
        safety of this arm: an operand allocated to rsi or r10 has no %h form
        at all, and r+4 would silently name a DIFFERENT register that does
        exist. The Q constraint class exists precisely to guarantee the base is
        one of the four, so a template pairing %h with a plain "r" is the shape
        that reaches this error -- and it is a real mistake in the source, not
        a gap here. AsmPrefixAndREX carries the matching ISA refusal for the
        REX-only combinations.
        bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register }
      if AttPeek = 'h' then
      begin
        Inc(AttPos);
        if not AttIsDigit(AttPeek) then
          Error('C: inline asm template has a size modifier %h that is not'
                + ' followed by an operand number');
        n := AttReadOperandNumber;
        if AttBindKind[n] <> ATTBIND_REG then
          Error('C: inline asm template applies %h to operand %'
                + AIntToStr(n) + ', which is a memory operand — a high-byte'
                + ' modifier selects a register half');
        if (AttBindReg[n] < 0) or (AttBindReg[n] > 3) then
          Error('C: inline asm template uses %h on operand %' + AIntToStr(n)
                + ', which was pinned to a register that has no high byte —'
                + ' only a, b, c and d do. Constrain that operand with "Q"'
                + ' so it can only be one of those four');
        AsmOpKind[slot] := AOP_REG;
        AsmOpReg[slot] := AttBindReg[n] + 4;
        AsmOpSize[slot] := 1;
        AsmHigh8Operand := True;
        Exit;
      end;
      if AttPeek = '[' then
      begin
        AttUseOperand(slot, AttReadNamedOperand);
        Exit;
      end;
      if AttIsDigit(AttPeek) then
      begin
        n := AttReadOperandNumber;
        if (AttBindKind[n] = ATTBIND_IMM) or (AttBindKind[n] = ATTBIND_MEMREG) then
          AttUseOperand(slot, n)
        else if AttBindKind[n] = ATTBIND_REG then
        begin
          AsmOpKind[slot] := AOP_REG;
          AsmOpReg[slot] := AttBindReg[n];
          AsmOpSize[slot] := AttBindSize[n];
        end
        else
        begin
          { An `"m"` operand is a FRAME SLOT -- `[rbp+disp32]`, the same operand
            form a named Pascal local takes -- and costs no register at all.
            That is what gcc does (it spills the value and writes `-8(%rbp)`),
            and the register it saves is not a nicety: the i386 caller-saved
            pool is five registers, and the two busybox comba blocks want one
            more than they have if every `"m"` burns one.

            It USED to be `[reg]` with the caller pinning a register to hold the
            ADDRESS. Both encode the same access; only the pressure differs. }
          AsmOpKind[slot] := AOP_MEM;
          AsmOpReg[slot] := 0;
          AsmOpIndex[slot] := -1;
          AsmOpScale[slot] := 1;
          AsmOpVal[slot] := AttBindOff[n];
          AsmOpSize[slot] := AttBindSize[n];
        end;
        Exit;
      end;
      Error('C: inline asm template has an unsupported % escape'
            + ' — write %% for a register in an extended asm statement');
    end;
    AttParseRegisterRef(slot);
    Exit;
  end;

  if AttAtLabelRef then
  begin
    AttParseLabelRef(slot);
    Exit;
  end;

  { a displacement, then a required ( ) — a bare absolute address is refused }
  if AttIsDigit(AttPeek) or (AttPeek = '-') or (AttPeek = '+') or (AttPeek = '(') then
  begin
    disp := 0;
    if AttPeek <> '(' then disp := AttParseAddExpr;
    AttSkipSpace;
    if (AttPeek <> '(') and AttGasMode then
    begin
      AsmOpKind[slot] := AOP_MEMR;
      AsmOpReg[slot] := -1;
      AsmOpIndex[slot] := -1;
      AsmOpScale[slot] := 1;
      AsmOpVal[slot] := disp;
      AsmOpSize[slot] := 0;
      Exit;
    end;
    if AttPeek <> '(' then
      Error('C: inline asm template has an absolute memory address,'
            + ' which is not supported');
    AttParseMemory(slot, disp, True);
    Exit;
  end;

  if AttIsAlpha(AttPeek) then
    Error('C: inline asm template names the symbol "' + AttReadWord
          + '", which is not supported — operands must be registers,'
          + ' immediates or memory');
  Error('C: inline asm template has an operand it cannot read');
end;

{ ---- mnemonics ------------------------------------------------------------

  An AT&T mnemonic carries its operand size as a b/w/l/q suffix. Stripping one
  blindly is wrong in both directions: `mul` would become `mu`, and `movq` is
  ALSO a real Intel mnemonic in AsmDispatch -- the SSE 64-bit move -- so
  handing `movq` straight through would encode an xmm instruction for a
  template that meant a 64-bit `mov`. Hence an explicit base list rather than
  a suffix rule.

  The list is deliberately short: what the four x86-64-reachable asm blocks in
  busybox's tls_sp_c32.c use, plus the rows of the same ALU table that come
  for free and are tested alongside. Everything else refuses BY NAME. A
  narrower reader with an honest refusal beats a wider one that guesses. }

function AttBaseIsKnown(const b: AnsiString): Boolean;
begin
  Result := CaseEqual(b,'mov') or CaseEqual(b,'add') or CaseEqual(b,'adc')
         or CaseEqual(b,'sub') or CaseEqual(b,'sbb') or CaseEqual(b,'and')
         or CaseEqual(b,'or')  or CaseEqual(b,'xor') or CaseEqual(b,'cmp')
         or CaseEqual(b,'mul') or CaseEqual(b,'imul') or CaseEqual(b,'neg')
         or CaseEqual(b,'not') or CaseEqual(b,'inc') or CaseEqual(b,'dec')
         or CaseEqual(b,'test') or CaseEqual(b,'xchg') or CaseEqual(b,'lea')
         { bswapl/bswapq (SDL_endian.h's SDL_Swap32/SDL_Swap64) and `int $3`
           (SDL_assert.h's SDL_TriggerBreakpoint). `pause` is NOT here: it
           takes no operands, so it never reaches the suffix split -- the
           zero-operand arm passes it to AttEmitInstr unchanged. }
         or CaseEqual(b,'bswap') or CaseEqual(b,'int')
         { shifts and rotates (libtomcrypt's ROL/ROR/ROLc/ROL64c, dropbear).
           AsmDispatch has encoded all six since the Intel path got them; only
           this list kept the AT&T spelling out. }
         or CaseEqual(b,'shl') or CaseEqual(b,'sal') or CaseEqual(b,'shr')
         or CaseEqual(b,'sar') or CaseEqual(b,'rol') or CaseEqual(b,'ror')
         { kernel code (Gibux): port I/O, the stack ops a far return is
           built from, and the descriptor-table and TLB instructions.
           AsmSystemOp encodes them; the i386 sink refuses them by name. }
         or CaseEqual(b,'in') or CaseEqual(b,'out')
         or CaseEqual(b,'push') or CaseEqual(b,'pop')
         or CaseEqual(b,'lgdt') or CaseEqual(b,'lidt') or CaseEqual(b,'ltr')
         or CaseEqual(b,'invlpg')
         or CaseEqual(b,'clflush') or CaseEqual(b,'clflushopt')
         or CaseEqual(b,'clwb')
         { Gibux SMP: the atomic read-modify-writes (with `lock`, below) and
           the descriptor-register reads. rdtscp takes no operands, so it
           never reaches this list (the zero-operand arm passes it on). }
         or CaseEqual(b,'cmpxchg') or CaseEqual(b,'xadd')
         or CaseEqual(b,'bsf') or CaseEqual(b,'bsr')
         or CaseEqual(b,'str') or CaseEqual(b,'sldt')
         or CaseEqual(b,'sgdt') or CaseEqual(b,'sidt') or CaseEqual(b,'rdpid')
         or CaseEqual(b,'fxsave64') or CaseEqual(b,'fxrstor64')
         or CaseEqual(b,'fxsave') or CaseEqual(b,'fxrstor')
         or CaseEqual(b,'ldmxcsr') or CaseEqual(b,'stmxcsr')
         or CaseEqual(b,'xsave64') or CaseEqual(b,'xrstor64')
         or CaseEqual(b,'xsaveopt64') or CaseEqual(b,'xsavec64')
         or CaseEqual(b,'xsave') or CaseEqual(b,'xrstor')
         or CaseEqual(b,'xsaveopt') or CaseEqual(b,'xsavec')
         or CaseEqual(b,'rdrand') or CaseEqual(b,'rdseed')
         { set<cc> r/m8 (`rdrand %0; setc %1`); the shared encoder has it. }
         or (AsmStartsWith(b, 'set') and (Length(b) > 3) and (AsmCC(AsmTail(b, 3)) >= 0))
         { cmov<cc> r, r/m (sntrup761.c's constant-time compares: `cmovnew`).
           The shared encoder has these too. `cmovl` is cmov-if-less, not
           cmov with an l suffix, which is gas's reading as well: the whole word
           is tried as a base before a suffix is split off. }
         or (AsmStartsWith(b, 'cmov') and (Length(b) > 4) and (AsmCC(AsmTail(b, 4)) >= 0));
end;

{ Split an AT&T mnemonic into its Intel base and the size its suffix names.
  size 0 means "unsuffixed" -- legal AT&T when a register operand fixes the
  size, and left for AsmOpSizeOf to work out exactly as the Intel path does. }
function AttSplitMnemonic(const mn: AnsiString; var base: AnsiString;
                          var size: Integer): Boolean;
var n: Integer; last: Char; stem: AnsiString;
begin
  Result := False;
  size := 0;
  n := Length(mn);
  if n = 0 then Exit;
  if AttBaseIsKnown(mn) then begin base := mn; Result := True; Exit; end;
  last := AsmRegLower(mn[n]);
  stem := Copy(mn, 1, n - 1);
  if not AttBaseIsKnown(stem) then Exit;
  if last = 'b' then size := 1
  else if last = 'w' then size := 2
  else if last = 'l' then size := 4
  else if last = 'q' then size := 8
  else Exit;
  base := stem;
  Result := True;
end;

{ ---- one instruction ------------------------------------------------------ }

{ The value of an all-digit label name, or -1. }
function AttReadLabelNum(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 1 to Length(s) do
  begin
    if not AttIsDigit(s[i]) then begin Result := -1; Exit; end;
    Result := Result * 10 + (Ord(s[i]) - Ord('0'));
  end;
end;

{ After an instruction: if it reserved a rip-relative label displacement,
  remember where, and where the instruction ENDS (rip at run time). }
procedure AttNoteRipFix;
begin
  if AsmRipFixPos < 0 then Exit;
  if AttFixCount >= ATT_MAX_LABELS then
    Error('C: inline asm template has more than ' + AIntToStr(ATT_MAX_LABELS)
          + ' label references');
  AttFixPos[AttFixCount] := AsmRipFixPos;
  AttFixEnd[AttFixCount] := AsmBytesCount;
  AttFixNum[AttFixCount] := AttPendLblNum;
  AttFixFwd[AttFixCount] := AttPendLblFwd;
  AttFixOrd[AttFixCount] := AttInstrOrd;
  Inc(AttFixCount);
  AsmRipFixPos := -1;
end;

{ Resolve every label reference of the template just encoded. `Nb` is the
  latest definition at or before the referencing instruction, `Nf` the first
  one after it -- gas's rule. }
procedure AttResolveLabels;
var i, k, tgt, d: Integer;
begin
  for i := 0 to AttFixCount - 1 do
  begin
    tgt := -1;
    for k := 0 to AttLblCount - 1 do
      if AttLblNum[k] = AttFixNum[i] then
      begin
        if AttFixFwd[i] then
        begin
          if (AttLblOrd[k] >= AttFixOrd[i]) and (tgt < 0) then tgt := AttLblPos[k];
        end
        else if AttLblOrd[k] < AttFixOrd[i] then
          tgt := AttLblPos[k];
      end;
    if tgt < 0 then
    begin
      if AttFixFwd[i] then
        Error('C: inline asm template references ' + AIntToStr(AttFixNum[i])
              + 'f, but no label ' + AIntToStr(AttFixNum[i]) + ': follows it')
      else
        Error('C: inline asm template references ' + AIntToStr(AttFixNum[i])
              + 'b, but no label ' + AIntToStr(AttFixNum[i]) + ': precedes it');
    end;
    d := tgt - AttFixEnd[i];
    AsmBytes[AttFixPos[i]]     := Byte(d and $FF);
    AsmBytes[AttFixPos[i] + 1] := Byte((d shr 8) and $FF);
    AsmBytes[AttFixPos[i] + 2] := Byte((d shr 16) and $FF);
    AsmBytes[AttFixPos[i] + 3] := Byte((d shr 24) and $FF);
  end;
end;

procedure AttEncodeOne;
var mn, base: AnsiString;
    size, nops, i, tmpKind, tmpReg, tmpIdx, tmpScale, tmpSize: Integer;
    tmpVal: Int64;
begin
  AttSkipSpace;
  if AttAtSeparator then Exit;

  mn := AttReadWord;
  if mn = '' then Error('C: inline asm template expected an instruction');
  AttSkipSpace;
  { `lock` is a PREFIX, F0, emitted ahead of the instruction it qualifies:
    `lock cmpxchgl %2,(%1)` on one line, or `lock;` / `lock` alone with the
    instruction after the separator (both gas spellings, both in real
    kernels). F0 is a legacy prefix, so it precedes the 66 and REX bytes the
    instruction emits itself. The i386 path renders text lines and has no
    prefix support, so it refuses by name. Gibux SMP: futex and spinlock
    read-modify-writes that race other CPUs. }
  if CaseEqual(mn, 'lock') then
  begin
    if AttSinkText then
      Error('C: inline asm lock prefix is not supported on the i386 path');
    AsmB($F0);
    if AttPeek = ';' then begin Inc(AttPos); Exit; end;
    if AttAtSeparator then Exit;
    mn := AttReadWord;
    if mn = '' then Error('C: inline asm template expected an instruction after lock');
    AttSkipSpace;
  end;
  if (not AttAtSeparator) and (AttPeek = ':') and AttIsDigit(mn[1]) and
     (Length(mn) <= 9) and (AttReadLabelNum(mn) >= 0) then
  begin
    if AttSinkText then
      Error('C: inline asm template defines a local label, which the i386'
            + ' path does not support');
    if AttLblCount >= ATT_MAX_LABELS then
      Error('C: inline asm template defines more than '
            + AIntToStr(ATT_MAX_LABELS) + ' local labels');
    AttLblNum[AttLblCount] := AttReadLabelNum(mn);
    AttLblOrd[AttLblCount] := AttInstrOrd;
    AttLblPos[AttLblCount] := AsmBytesCount;
    Inc(AttLblCount);
    Inc(AttPos);
    Exit;
  end;
  if (not AttAtSeparator) and (AttPeek = ':') then
    Error('C: inline asm template defines the label "' + mn
          + '", which is not supported — only numeric local labels are');
  Inc(AttInstrOrd);
  AsmRipFixPos := -1;

  { A zero-operand instruction is passed through unchanged: cmc, nop, ret and
    friends carry no AT&T suffix, so the base list must not see them.

    THROUGH THE SEAM, like every other instruction. This line called AsmDispatch
    directly for one day and it was the second path that stayed broken: on i386
    that encodes x86-64 bytes into AsmBytes, which that target's codegen never
    reads because it replays LINES -- so `cpuid` compiled with no diagnostic and
    executed as nothing, and busybox's powertop.c came back with a zeroed CPU.
    Caught by test/casm_gnu_operands_i386.c's cpuid row against gcc -m32; a row
    that only checked the four TUs compiled would have called it done. }
  if AttAtSeparator then
  begin
    if not AttEmitInstr(mn, 0) then
      Error('C: inline asm template has an unsupported instruction: ' + mn);
    AttNoteRipFix;
    Exit;
  end;

  { jmp / jcc to a numeric local label: always the rel32 form (E9, 0F 8x),
    so no relaxation is needed and the displacement is patched like any
    other label reference -- relative to the end of the instruction. }
  if (CaseEqual(mn, 'jmp') or
      (AsmStartsWith(mn, 'j') and (AsmCC(AsmTail(mn, 1)) >= 0))) and
     AttIsDigit(AttPeek) then
  begin
    if AttSinkText then
      Error('C: inline asm template branches to a local label, which the i386'
            + ' path does not support');
    i := 0;
    while AttIsDigit(AttPeek) do
    begin
      i := i * 10 + (Ord(AttPeek) - Ord('0'));
      Inc(AttPos);
    end;
    if not ((AttPeek = 'f') or (AttPeek = 'b')) then
      Error('C: inline asm template branch target must be a local label'
            + ' written Nf or Nb');
    AttPendLblFwd := AttPeek = 'f';
    AttPendLblNum := i;
    Inc(AttPos);
    AttSkipSpace;
    if not AttAtSeparator then
      Error('C: inline asm template has trailing text after ' + mn);
    if CaseEqual(mn, 'jmp') then
      AsmB($E9)
    else
    begin
      AsmB($0F);
      AsmB($80 or AsmCC(AsmTail(mn, 1)));
    end;
    AsmRipFixPos := AsmBytesCount;
    AsmB(0); AsmB(0); AsmB(0); AsmB(0);
    AttNoteRipFix;
    Exit;
  end;

  if not AttSplitMnemonic(mn, base, size) then
    Error('C: inline asm template has an unsupported instruction: ' + mn);

  { Cleared per INSTRUCTION, which is what makes the flag safe to read from
    AsmPrefixAndREX without knowing how many operands this instruction has:
    a high-byte operand in one instruction can never colour the next. }
  AsmHigh8Operand := False;
  nops := 0;
  while not AttAtSeparator do
  begin
    if nops >= 4 then
      Error('C: inline asm template has more than 4 operands: ' + mn);
    AttParseOperand(nops);
    Inc(nops);
    AttSkipSpace;
    if AttPeek = ',' then begin Inc(AttPos); AttSkipSpace; end
    else Break;
  end;
  AttSkipSpace;
  if not AttAtSeparator then
    Error('C: inline asm template has trailing text after the operands of ' + mn);

  { AT&T writes `op src, dst`; asmenc's slot 0 is the DESTINATION. Reverse the
    whole list -- this is the single point where operand order is converted,
    and it is why nothing downstream needs to know which syntax it came from. }
  for i := 0 to (nops div 2) - 1 do
  begin
    tmpKind := AsmOpKind[i];   tmpReg := AsmOpReg[i];
    tmpSize := AsmOpSize[i];   tmpVal := AsmOpVal[i];
    tmpIdx := AsmOpIndex[i];   tmpScale := AsmOpScale[i];
    AsmOpKind[i] := AsmOpKind[nops-1-i];   AsmOpReg[i] := AsmOpReg[nops-1-i];
    AsmOpSize[i] := AsmOpSize[nops-1-i];   AsmOpVal[i] := AsmOpVal[nops-1-i];
    AsmOpIndex[i] := AsmOpIndex[nops-1-i]; AsmOpScale[i] := AsmOpScale[nops-1-i];
    AsmOpKind[nops-1-i] := tmpKind;   AsmOpReg[nops-1-i] := tmpReg;
    AsmOpSize[nops-1-i] := tmpSize;   AsmOpVal[nops-1-i] := tmpVal;
    AsmOpIndex[nops-1-i] := tmpIdx;   AsmOpScale[nops-1-i] := tmpScale;
  end;

  { The suffix is the ONLY size information when no operand is a register --
    `sbbq $0, 2*8(%0)` is a memory/immediate pair, and without the q it would
    encode as a dword (AsmOpSizeOf's documented fallback). Push it onto the
    memory operands, which is where AsmOpSizeOf looks. A register operand that
    disagrees with the suffix is a mistake in the template, not something to
    paper over. }
  { in/out carry their width on the DATA register (al/ax/eax) and take the
    port in dx whatever the suffix says, so the suffix-vs-register check below
    would refuse `outb %al, %dx` for the dx it is required to name. }
  if CaseEqual(base,'in') or CaseEqual(base,'out') then size := 0;
  if size <> 0 then
    for i := 0 to nops - 1 do
    begin
      if (AsmOpKind[i] = AOP_MEMR) and (AsmOpSize[i] = 0) then AsmOpSize[i] := size;
      { An `"m"` operand reaches here as AOP_MEM carrying its C type's width.
        The suffix still wins: `movl %7` on a wider slot is the template asking
        for a dword, and AsmOpSizeOf reads AOP_MEM before it reads anything
        else, so leaving the type's width in place would silently encode the
        wrong size. A register that disagrees is still an error below --
        a register NAMES its width, a frame slot does not. }
      if AsmOpKind[i] = AOP_MEM then AsmOpSize[i] := size;
      { A shift or rotate COUNT is %cl whatever the suffix says (`roll %cl,
        %0`): the count register has no width of its own to agree with.
        After the reversal above it is slot 1. }
      if (i = 1) and (AsmOpKind[i] = AOP_REG) and (AsmOpReg[i] = 1)
         and (AsmOpSize[i] = 1)
         and (CaseEqual(base,'shl') or CaseEqual(base,'sal')
              or CaseEqual(base,'shr') or CaseEqual(base,'sar')
              or CaseEqual(base,'rol') or CaseEqual(base,'ror')) then
        Continue;
      if (AsmOpKind[i] = AOP_REG) and (AsmOpSize[i] <> size) then
        Error('C: inline asm template writes ' + mn + ' with a '
              + AIntToStr(AsmOpSize[i] * 8) + '-bit register');
    end;

  if not AttEmitInstr(base, nops) then
    Error('C: inline asm template has an unsupported instruction: ' + mn);
  AttNoteRipFix;
end;

{ ---- the whole template ---------------------------------------------------

  Encodes into AsmBytes exactly as AsmParseBody does, so the AN_ASM /
  IR_ASM node this produces is indistinguishable at codegen from a Pascal
  block: startOff and len name a span the blit loop copies. }
{ Encode `tpl` into AsmBytes. The operand bindings must already be set by the
  caller (AttResetBindings + AttBindOperand), because a `%N` is resolved during
  this call and there is no later pass that could fix one up. }
procedure AttEncodeTemplate(const tpl: AnsiString; isExt: Boolean;
                            var startOff, len: Integer);
begin
  AttSrc := tpl;
  AttPos := 1;
  AttExtended := isExt;
  AttMaxOpnd := -1;
  { Same span rule as AttBeginBlock/AttEndBlock, and for the same reason: the
    counter this walks is whichever one the target's sink is filling. }
  AttBeginBlock(startOff);
  AttInstrOrd := 0;
  AttLblCount := 0;
  AttFixCount := 0;
  AsmRipFixPos := -1;
  AttSkipSeparators;
  while not AttAtEnd do
  begin
    AttEncodeOne;
    AttSkipSeparators;
  end;
  AttResolveLabels;
  AttEndBlock(startOff, len);
end;

{ ---- the moves that bind operands to their pinned registers ----------------

  An operand's value lives in an ordinary compiler-made local, written and read
  by ordinary C assignments the parser synthesises around this block. All the
  asm has to do is move between that local's frame slot and the pinned
  register, which AOP_MEM already means: `[rbp+disp32]`, exactly the form
  AsmParseOperand builds for a named Pascal local. So the prologue and epilogue
  go through the SAME encoder as everything else, and no new IR node, no
  codegen change and no register allocator is involved.

  This is what makes pinning cheap here. The registers are chosen at parse
  time, so the choice reaches AsmBytes; nothing is live in a register across a
  statement boundary in this compiler, so nothing has to be saved first. }
{ push/pop one register, at the target's stack width. Used to bracket a block
  that a FIXED-register constraint forced onto a register the caller expects to
  survive -- `cpuid` writes ebx and busybox procps/powertop.c asks for it by
  name, so there is nothing to re-choose. Everything inside the block addresses
  memory through the FRAME pointer, so moving the stack pointer between the
  push and the pop changes no operand. }
procedure AttEmitPushPop(regNum: Integer; doPush: Boolean);
var i: Integer;
begin
  for i := 0 to 3 do
  begin
    AsmOpKind[i] := AOP_NONE; AsmOpReg[i] := 0; AsmOpSize[i] := 0;
    AsmOpVal[i] := 0; AsmOpIndex[i] := -1; AsmOpScale[i] := 1;
  end;
  AsmHigh8Operand := False;   { these build operands without the operand loop }
  AsmOpKind[0] := AOP_REG;
  AsmOpReg[0] := regNum;
  AsmOpSize[0] := TARGET_PTR_SIZE;
  if doPush then
  begin
    if not AttEmitInstr('push', 1) then
      Error('C: inline asm could not encode the save of a callee-saved register');
  end
  else if not AttEmitInstr('pop', 1) then
    Error('C: inline asm could not encode the restore of a callee-saved register');
end;

procedure AttEmitFrameMove(regNum, size, frameOff: Integer; load: Boolean);
var i: Integer;
begin
  for i := 0 to 3 do
  begin
    AsmOpKind[i] := AOP_NONE; AsmOpReg[i] := 0; AsmOpSize[i] := 0;
    AsmOpVal[i] := 0; AsmOpIndex[i] := -1; AsmOpScale[i] := 1;
  end;
  AsmHigh8Operand := False;   { these build operands without the operand loop }
  if load then
  begin
    AsmOpKind[0] := AOP_REG;  AsmOpReg[0] := regNum; AsmOpSize[0] := size;
    AsmOpKind[1] := AOP_MEM;  AsmOpVal[1] := frameOff; AsmOpSize[1] := size;
  end
  else
  begin
    AsmOpKind[0] := AOP_MEM;  AsmOpVal[0] := frameOff; AsmOpSize[0] := size;
    AsmOpKind[1] := AOP_REG;  AsmOpReg[1] := regNum; AsmOpSize[1] := size;
  end;
  if not AttEmitInstr('mov', 2) then
    Error('C: inline asm could not encode an operand move');
end;

{ Open a block: the caller emits its own prologue moves, then the template,
  then its epilogue moves, and closes with AttEndBlock to get the span. }
{ Encode a template that is already inside an open block (bindings set). }
procedure AttEncodeTemplateInner(const tpl: AnsiString; isExt: Boolean);
var ignoreStart, ignoreLen: Integer;
begin
  AttEncodeTemplate(tpl, isExt, ignoreStart, ignoreLen);
end;
