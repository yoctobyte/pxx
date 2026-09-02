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
  ATTBIND_MEM  = 2;   { %N is `[reg]`, the register holding the address: `"m"` }

var
  AttSrc     : AnsiString;   { the template being read }
  AttPos     : Integer;      { 1-based cursor into AttSrc }
  AttExtended: Boolean;      { extended asm: `%%` is an escaped `%`, `%N` an operand }
  AttMaxOpnd : Integer;      { highest %N seen, or -1 -- the caller checks it }
  AttBindKind: array[0..MAX_CASM_OPERANDS-1] of Integer;
  AttBindReg : array[0..MAX_CASM_OPERANDS-1] of Integer;
  AttBindSize: array[0..MAX_CASM_OPERANDS-1] of Integer;  { bytes; 0 = let the suffix say }
  AttBindCount: Integer;

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
  end;
  AttBindCount := 0;
end;

procedure AttBindOperand(n, kind, reg, size: Integer);
begin
  AttBindKind[n] := kind;
  AttBindReg[n] := reg;
  AttBindSize[n] := size;
  if n >= AttBindCount then AttBindCount := n + 1;
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
var num, size, idxNum, idxSize: Integer; scale: Int64;
begin
  { AttPos is on '(' }
  Inc(AttPos);
  AttSkipSpace;
  AttParseBaseOrOperand(slot);
  num := AsmOpReg[slot];
  size := AsmOpSize[slot];
  if size <> 8 then
    Error('C: inline asm template needs a 64-bit base register inside ( )');
  idxNum := -1; scale := 1;
  AttSkipSpace;
  if AttPeek = ',' then
  begin
    Inc(AttPos);
    AttSkipSpace;
    AttParseBaseOrOperand(slot);
    idxNum := AsmOpReg[slot];
    idxSize := AsmOpSize[slot];
    if idxSize <> 8 then
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

procedure AttParseOperand(slot: Integer);
var disp: Int64; n: Integer;
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
      { %N, or a modifier like %b0 / %w0 / %k0 / %l0 }
      if AttIsDigit(AttPeek) then
      begin
        n := AttReadOperandNumber;
        if AttBindKind[n] = ATTBIND_REG then
        begin
          AsmOpKind[slot] := AOP_REG;
          AsmOpReg[slot] := AttBindReg[n];
          AsmOpSize[slot] := AttBindSize[n];
        end
        else
        begin
          { An `"m"` operand: the caller put its ADDRESS in a register, so the
            template's `%N` is that register dereferenced. The width comes from
            the mnemonic's suffix, exactly as for any other memory operand. }
          AsmOpKind[slot] := AOP_MEMR;
          AsmOpReg[slot] := AttBindReg[n];
          AsmOpIndex[slot] := -1;
          AsmOpScale[slot] := 1;
          AsmOpVal[slot] := 0;
          AsmOpSize[slot] := 0;
        end;
        Exit;
      end;
      Error('C: inline asm template has an unsupported % escape'
            + ' — write %% for a register in an extended asm statement');
    end;
    AttParseRegisterRef(slot);
    Exit;
  end;

  { a displacement, then a required ( ) — a bare absolute address is refused }
  if AttIsDigit(AttPeek) or (AttPeek = '-') or (AttPeek = '+') or (AttPeek = '(') then
  begin
    disp := 0;
    if AttPeek <> '(' then disp := AttParseAddExpr;
    AttSkipSpace;
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
         or CaseEqual(b,'test') or CaseEqual(b,'xchg') or CaseEqual(b,'lea');
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
  if (not AttAtSeparator) and (AttPeek = ':') then
    Error('C: inline asm template defines the label "' + mn
          + '", which is not supported');

  { A zero-operand instruction is passed through unchanged: cmc, nop, ret and
    friends carry no AT&T suffix, so the base list must not see them. }
  if AttAtSeparator then
  begin
    if not AsmDispatch(mn, 0) then
      Error('C: inline asm template has an unsupported instruction: ' + mn);
    Exit;
  end;

  if not AttSplitMnemonic(mn, base, size) then
    Error('C: inline asm template has an unsupported instruction: ' + mn);

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
  if size <> 0 then
    for i := 0 to nops - 1 do
    begin
      if (AsmOpKind[i] = AOP_MEMR) and (AsmOpSize[i] = 0) then AsmOpSize[i] := size;
      if (AsmOpKind[i] = AOP_REG) and (AsmOpSize[i] <> size) then
        Error('C: inline asm template writes ' + mn + ' with a '
              + AIntToStr(AsmOpSize[i] * 8) + '-bit register');
    end;

  if not AsmDispatch(base, nops) then
    Error('C: inline asm template has an unsupported instruction: ' + mn);
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
  startOff := AsmBytesCount;
  AttSkipSeparators;
  while not AttAtEnd do
  begin
    AttEncodeOne;
    AttSkipSeparators;
  end;
  len := AsmBytesCount - startOff;
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
procedure AttEmitFrameMove(regNum, size, frameOff: Integer; load: Boolean);
var i: Integer;
begin
  for i := 0 to 3 do
  begin
    AsmOpKind[i] := AOP_NONE; AsmOpReg[i] := 0; AsmOpSize[i] := 0;
    AsmOpVal[i] := 0; AsmOpIndex[i] := -1; AsmOpScale[i] := 1;
  end;
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
  if not AsmDispatch('mov', 2) then
    Error('C: inline asm could not encode an operand move');
end;

{ Open a block: the caller emits its own prologue moves, then the template,
  then its epilogue moves, and closes with AttEndBlock to get the span. }
procedure AttBeginBlock(var startOff: Integer);
begin
  startOff := AsmBytesCount;
end;

procedure AttEndBlock(startOff: Integer; var len: Integer);
begin
  len := AsmBytesCount - startOff;
end;

{ Encode a template that is already inside an open block (bindings set). }
procedure AttEncodeTemplateInner(const tpl: AnsiString; isExt: Boolean);
var ignoreStart, ignoreLen: Integer;
begin
  AttEncodeTemplate(tpl, isExt, ignoreStart, ignoreLen);
end;
