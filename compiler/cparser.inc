{ SPDX-License-Identifier: MPL-2.0 }
{ ===== C Parser ===== }

function ParseCBlockAST: Integer; forward;
function ParseCStatementAST: Integer; forward;
procedure SkipBraceBlock; forward;
procedure ParseCSubroutine; forward;
function ParseCExpr: Integer; forward;
function ParseCCommaExpr: Integer; forward;
function CEvalConstExpr: Int64; forward;
function CBraceTopLevelInitCountAt(openIdx: Integer): Integer; forward;
procedure CSkipCInitElement; forward;
function CInitLocalAggregate(symIdx, elemTkOrd, elemRecId, arrLen,
                             nDims, dim0, elemsBelow: Integer;
                             isArr: Boolean): Integer; forward;
procedure ParseCTypedef; forward;
procedure ParseCEnumDecl; forward;
procedure ParseCStructDecl; forward;
function IsBareStructDecl: Boolean; forward;
function IsBareEnumDecl: Boolean; forward;
function IsCTypeTok: Boolean; forward;
function ParseCDeclType: TTypeKind; forward;
function ParseCCommaStmt: Integer; forward;
function ParseCSwitchAST: Integer; forward;
function CNodeIsPointer(node: Integer): Boolean; forward;
{ CNodeDecaysToPointer forward moved to forwards.inc (must sit above ir.inc:901,
  which calls it; this spot is below that use — too late for the FPC seed). }
function CNodePtrElemRec(node: Integer): Integer; forward;
procedure ParseCStructInto(ci: Integer; isUnion: Boolean); forward;

{ ===== C expression compiler (Slice B) =====
  A real recursive-descent C expression parser at C precedence, replacing the
  earlier Pascal-ParseExpr borrow. Emits the shared AST nodes (AN_BINOP, AN_NEG,
  AN_NOT, AN_INT_LIT, AN_IDENT, AN_CALL, AN_ASSIGN, AN_STR_LIT) so the existing
  IR lowering and all backends apply unchanged.

  Operator-token mapping into AN_BINOP.IVal: the IR's binop validator accepts
  ops with ordinal <= Ord(tkShl) plus tkXor, and encodes shift-right as the
  *tkIdent* operator (shift-left = tkShl). So the distinct C lexer tokens from
  Slice A are translated here to the operator tokens the IR understands:
    C `&`(tkAmp)->tkAnd bitwise, `|`(tkPipe)->tkOr bitwise, `^`->tkXor,
    `<<`->tkShl, `>>`->tkIdent(shr), `/`->tkDiv (integer division),
    `&&`->tkAnd / `||`->tkOr but tagged tyBoolean for the short-circuit path. }

{ Result type of a binary node: comparisons/logical -> Boolean; otherwise widen
  to Int64 if either operand is Int64, else Integer. }
function CBinResultTk(opTok, l, r: Integer): Integer;
begin
  if (opTok = Ord(tkEq)) or (opTok = Ord(tkNeq)) or (opTok = Ord(tkLt)) or
     (opTok = Ord(tkLe)) or (opTok = Ord(tkGt)) or (opTok = Ord(tkGe)) or
     (opTok = Ord(tkAnd)) or (opTok = Ord(tkOr)) then
    Result := Ord(tyBoolean)
  else if TypeIsFloat(IntToTypeKind(ASTTk[l])) or TypeIsFloat(IntToTypeKind(ASTTk[r])) then
  begin
    { Float arithmetic (`d+1`, `a*b`, …): the result is float, NOT integer —
      otherwise the BINOP was tagged tyInteger and the backend INTEGER-added the
      two IEEE bit patterns, producing a garbage near-infinity double. Promote to
      the wider operand type (Extended > Double > Single). }
    if (IntToTypeKind(ASTTk[l]) = tyExtended) or (IntToTypeKind(ASTTk[r]) = tyExtended) then
      Result := Ord(tyExtended)
    else if (IntToTypeKind(ASTTk[l]) = tyDouble) or (IntToTypeKind(ASTTk[r]) = tyDouble) then
      Result := Ord(tyDouble)
    else
      Result := Ord(tySingle);
  end
  { Integer usual-arithmetic-conversion result, preserving SIGNEDNESS so the IR
    lowering picks signed vs unsigned compares/division/shifts correctly. C
    promotes unsigned char/short to signed int, so only unsigned int (tyUInt32)
    and unsigned long/long-long (tyUInt64) keep an unsigned result. Rank order:
    unsigned 64 > signed 64 > unsigned 32 > signed 32. Without this an inline
    `i - 1u` (unsigned) was tagged signed, so `(i - 1u) < asize` compiled to a
    SIGNED compare (lua `findindex` looped forever in `pairs`). }
  else if (IntToTypeKind(ASTTk[l]) = tyUInt64) or (IntToTypeKind(ASTTk[r]) = tyUInt64) then
    Result := Ord(tyUInt64)
  else if (IntToTypeKind(ASTTk[l]) = tyInt64) or (IntToTypeKind(ASTTk[r]) = tyInt64) then
    Result := Ord(tyInt64)
  else if (IntToTypeKind(ASTTk[l]) = tyUInt32) or (IntToTypeKind(ASTTk[r]) = tyUInt32) or
          (IntToTypeKind(ASTTk[l]) = tyNativeUInt) or (IntToTypeKind(ASTTk[r]) = tyNativeUInt) then
    Result := Ord(tyUInt32)
  else
    Result := Ord(tyInteger);
end;

function CIntegerPromoteTk(tk: TTypeKind): TTypeKind;
begin
  Result := tk;
  if TypeIsOrdinal(tk) and (TypeSize(tk) < TypeSize(tyInteger)) then
    Result := tyInteger;
end;

function CTernaryResultTk(thenE, elseE: Integer): Integer;
var tTk, eTk: TTypeKind;
begin
  tTk := IntToTypeKind(ASTTk[thenE]);
  eTk := IntToTypeKind(ASTTk[elseE]);
  if TypeIsFloat(tTk) or TypeIsFloat(eTk) then
  begin
    if (tTk = tyExtended) or (eTk = tyExtended) then Result := Ord(tyExtended)
    else if (tTk = tyDouble) or (eTk = tyDouble) then Result := Ord(tyDouble)
    else Result := Ord(tySingle);
  end
  else if TypeIsOrdinal(tTk) and TypeIsOrdinal(eTk) then
  begin
    tTk := CIntegerPromoteTk(tTk);
    eTk := CIntegerPromoteTk(eTk);
    if tTk = eTk then Result := Ord(tTk)
    else if (tTk = tyUInt64) or (eTk = tyUInt64) then Result := Ord(tyUInt64)
    else if (tTk = tyInt64) or (eTk = tyInt64) then Result := Ord(tyInt64)
    else Result := Ord(tyInteger);
  end
  else
    Result := ASTTk[thenE];
end;

{ Wrap a node in `(e & $FFFFFFFF)` to truncate it to 32 bits, zero-extended into
  the 64-bit register. pxx evaluates integer arithmetic in 64-bit registers, so
  an inline C `unsigned int` expression (`a - 10`, `0u - 1`) keeps the full 64-bit
  value instead of wrapping modulo 2^32; the mask restores C semantics. The mask
  literal is tagged tyInt64 so it is not itself re-truncated; the result is
  tyUInt32 so downstream arithmetic/comparisons stay in the unsigned domain. Built
  directly (not via CMakeBinop) to avoid re-wrapping the AND. }
function CTrunc32(e: Integer): Integer;
var node, mask: Integer;
begin
  mask := AllocNode(AN_INT_LIT);
  ASTIVal[mask] := $FFFFFFFF;
  ASTTk[mask] := Ord(tyInt64);
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(tkAnd);   { bitwise AND on integer operands }
  ASTLeft[node] := e;
  ASTRight[node] := mask;
  ASTTk[node] := Ord(tyUInt32);
  Result := node;
end;

{ True when a comparison of these two operand nodes resolves to the C unsigned
  32-bit domain: both operands are <= 32-bit ordinals and at least one is
  unsigned int (tyUInt32). C usual-arithmetic-conversions then convert the signed
  operand to unsigned, so the compare is unsigned. We model that by truncating
  both operands to 32 bits (CTrunc32), leaving two non-negative values whose
  signed and unsigned 64-bit comparison agree — without touching the shared
  TypeCompareUnsigned (which keeps Pascal's signed-wins-at-equal-width rule). A
  64-bit operand drops to the existing wider-operand path. }
function CCmpUnsigned32(l, r: Integer): Boolean;
var lt, rt: TTypeKind;
begin
  Result := False;
  lt := IntToTypeKind(ASTTk[l]); rt := IntToTypeKind(ASTTk[r]);
  if not (TypeIsOrdinal(lt) and TypeIsOrdinal(rt)) then Exit;
  if (TypeSize(lt) > 4) or (TypeSize(rt) > 4) then Exit;
  Result := (lt = tyUInt32) or (rt = tyUInt32);
end;

{ Build an AN_BINOP from a C operator token and two operand nodes. cTok is the
  raw C lexer token kind (CurTok.Kind ordinal). }
{ Wrap an expression in `(e != 0)` so a logical operand becomes a true 0/1
  boolean. C `&&`/`||` must yield exactly 0/1, and the short-circuit IR stores
  the operand value into a 1-byte boolean temp — a raw `2` would read back as 2.
  Normalising both operands here keeps the result canonical. }
function CMakeTruthy(e: Integer): Integer;
var node, zero: Integer;
begin
  zero := AllocNode(AN_INT_LIT);
  ASTIVal[zero] := 0;
  ASTTk[zero] := Ord(tyInteger);
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(tkNeq);
  ASTLeft[node] := e;
  ASTRight[node] := zero;
  ASTTk[node] := Ord(tyBoolean);
  Result := node;
end;

{ C 6.3.1.3: a cast to a narrower integer type TRUNCATES the value and
  re-extends it by the TARGET's signedness. AN_PTR_CAST alone only retags, so
  `(char)0x80` kept the full-width 0x80 and `c == (char)c` compared equal —
  tcc's imm8-fit check then encoded `cmp $0x80` as a sign-extended imm8
  (0xffffff80), miscompiling every C program it built (b192). Build
  ((x & mask) ^ signbit) - signbit for signed targets, x & mask for unsigned.
  Plain C char is SIGNED on x86-64/Linux, so tyChar extends. }
function CMakeNarrowIntCast(operand: Integer; castTk: TTypeKind): Integer;
var bits: Integer; isSgn: Boolean; m, sb: Int64;
    lit, n1: Integer;
begin
  bits := TypeSize(castTk) * 8;
  isSgn := castTk in [tyChar, tyInt8, tyInt16, tyInt32];
  m := (Int64(1) shl bits) - 1;
  lit := AllocNode(AN_INT_LIT); ASTIVal[lit] := m; ASTTk[lit] := Ord(tyInt64);
  n1 := AllocNode(AN_BINOP); ASTIVal[n1] := Ord(tkAnd);
  ASTLeft[n1] := operand; ASTRight[n1] := lit; ASTTk[n1] := Ord(tyInt64);
  Result := n1;
  if isSgn then
  begin
    sb := Int64(1) shl (bits - 1);
    lit := AllocNode(AN_INT_LIT); ASTIVal[lit] := sb; ASTTk[lit] := Ord(tyInt64);
    n1 := AllocNode(AN_BINOP); ASTIVal[n1] := Ord(tkXor);
    ASTLeft[n1] := Result; ASTRight[n1] := lit; ASTTk[n1] := Ord(tyInt64);
    lit := AllocNode(AN_INT_LIT); ASTIVal[lit] := sb; ASTTk[lit] := Ord(tyInt64);
    Result := AllocNode(AN_BINOP); ASTIVal[Result] := Ord(tkMinus);
    ASTLeft[Result] := n1; ASTRight[Result] := lit; ASTTk[Result] := Ord(tyInt64);
  end;
end;

{ C99 6.7.8p21: an aggregate initializer with fewer initializers than members
  zero-initializes the remainder (and 6.7.8p10 semantics for what "zero" means).
  Lower as an `x := Default(T)` assignment BEFORE the listed element stores:
  AN_DEFAULT on a record / fixed-array lhs becomes IR_DEFAULT_MEM, a whole-
  object zero of RecSize/ArrLen*elemSize bytes. Without this, a local
  `struct scope f = { 0 };` left every member after the first as stack
  garbage — tcc's self-compile read a garbage Sym* from exactly that
  pattern (feature-c-corpus-tcc, b189). }
function CMakeZeroLocal(idx: Integer; tk: TTypeKind): Integer;
var idn, dn, asn, seq: Integer;
begin
  idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(tk);
  dn := AllocNode(AN_DEFAULT);
  asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := dn;
  ASTTk[asn] := Ord(tk);
  seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
  Result := seq;
end;

function CMakeBinop(cTok, l, r: Integer): Integer;
var node, ivalOp: Integer;
begin
  ivalOp := cTok;
  if cTok = Ord(tkSlash) then
  begin
    { C `/` is integer division on ints (-> tkDiv) but REAL division on floats.
      The backend's float arithmetic path keys on tkSlash (divsd); keep tkSlash
      when either operand is float, else `0.5/scale` integer-divided the IEEE bit
      patterns into garbage. }
    if TypeIsFloat(IntToTypeKind(ASTTk[l])) or TypeIsFloat(IntToTypeKind(ASTTk[r])) then
      ivalOp := Ord(tkSlash)
    else
      ivalOp := Ord(tkDiv);
  end
  else if cTok = Ord(tkShr) then
  begin
    { C `>>` on a SIGNED operand is an arithmetic shift (sign-extends); on an
      UNSIGNED operand it's logical, same as Pascal's `shr` (logical by
      design). Both previously collapsed onto the same `tkIdent` sentinel
      (the encoding every backend's codegen already uses for logical shr,
      since Pascal's own `shr` lexes as a plain identifier with no dedicated
      token) -- so C's signed `>>` always shifted in zeros instead of the
      sign bit (bug-c-signed-arith-shift-right). `tkShr` itself (the C
      lexer's dedicated `>>` token) was never otherwise reached by codegen,
      so it's free to repurpose as the "arithmetic shr" sentinel for the
      signed case; the unsigned case keeps the existing `tkIdent` logical
      path unchanged. }
    if TypeSigned(IntToTypeKind(ASTTk[l])) then
      ivalOp := Ord(tkShr)
    else
      ivalOp := Ord(tkIdent);
  end
  else if cTok = Ord(tkAmp) then ivalOp := Ord(tkAnd)     { bitwise AND }
  else if cTok = Ord(tkPipe) then ivalOp := Ord(tkOr);    { bitwise OR }
  { tkPlus/tkMinus/tkStar/tkMod/tkShl/tkXor/tkAnd(&&)/tkOr(||)/comparisons map
    straight through. }
  if (cTok = Ord(tkAnd)) or (cTok = Ord(tkOr)) then       { logical && / || }
  begin
    l := CMakeTruthy(l);
    r := CMakeTruthy(r);
  end;
  { C unsigned 32-bit comparison: truncate both operands so the compare runs on
    two non-negative values (signed == unsigned 64-bit result), matching C's
    convert-to-unsigned rule for `int < unsigned int` (e.g. `-1 < 1u` -> 0). }
  if ((cTok = Ord(tkEq)) or (cTok = Ord(tkNeq)) or (cTok = Ord(tkLt)) or
      (cTok = Ord(tkLe)) or (cTok = Ord(tkGt)) or (cTok = Ord(tkGe))) and
     CCmpUnsigned32(l, r) then
  begin
    l := CTrunc32(l);
    r := CTrunc32(r);
  end;
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := ivalOp;
  ASTLeft[node] := l;
  ASTRight[node] := r;
  ASTTk[node] := CBinResultTk(cTok, l, r);
  { Pointer arithmetic `ptr +/- int` (or `int + ptr`) stays a pointer, carrying
    the element record on ASTSOffset so `(p+i)->field` / `(p+i)[j]` resolve (the
    IR already scales the offset by element size). }
  if (cTok = Ord(tkPlus)) or (cTok = Ord(tkMinus)) then
  begin
    if CNodeDecaysToPointer(l) then
    begin ASTTk[node] := Ord(tyPointer); ASTSOffset[node] := CNodePtrElemRec(l); end
    else if (cTok = Ord(tkPlus)) and CNodeDecaysToPointer(r) then
    begin ASTTk[node] := Ord(tyPointer); ASTSOffset[node] := CNodePtrElemRec(r); end;
  end;
  { C unsigned int (32-bit) arithmetic wraps modulo 2^32. The result is only
    tyUInt32 for the integer unsigned-32 arithmetic path (comparisons -> Boolean,
    pointer arith -> tyPointer above), so mask it back to 32 bits. }
  if IntToTypeKind(ASTTk[node]) = tyUInt32 then
    node := CTrunc32(node);
  Result := node;
end;

{ Binary-operator precedence (higher binds tighter); -1 = not a binary op.
  Note `&`=tkAmp(bitwise, 8) is distinct from `&&`=tkAnd(logical, 4), and
  `|`=tkPipe(bitwise, 6) from `||`=tkOr(logical, 3) since Slice A. }
function CBinPrec(k: TTokenKind): Integer;
begin
  case k of
    tkStar, tkSlash, tkMod:        Result := 11;
    tkPlus, tkMinus:               Result := 10;
    tkShl, tkShr:                  Result := 9;
    tkLt, tkLe, tkGt, tkGe:        Result := 8;
    tkEq, tkNeq:                   Result := 7;
    tkAmp:                         Result := 6;   { bitwise & }
    tkXor:                         Result := 5;   { bitwise ^ }
    tkPipe:                        Result := 4;   { bitwise | }
    tkAnd:                         Result := 3;   { logical && }
    tkOr:                          Result := 2;   { logical || }
    else                           Result := -1;
  end;
end;

function ParseCUnary: Integer; forward;
function ParseCPostfix: Integer; forward;

{ Build the shared-IR AN_INCDEC value node (master shape): Left = the lvalue
  (address computed once at lowering), ASTIVal = +1/-1 (the lowering scales by
  element size for a pointer), ASTSOffset = 1 for postfix (yield OLD value) / 0
  for prefix (yield NEW). The pointed-at record for `(p++)->field` is derived from
  the lvalue (Left) by CNodePtrElemRec, not carried on the node. }
function CMakeIncDec(lv: Integer; isInc, isPre: Boolean): Integer;
var node: Integer;
begin
  node := AllocNode(AN_INCDEC);
  ASTLeft[node] := lv;
  if isInc then ASTIVal[node] := 1 else ASTIVal[node] := -1;
  if isPre then ASTSOffset[node] := 0 else ASTSOffset[node] := 1;
  ASTTk[node] := ASTTk[lv];
  Result := node;
end;

{ Precedence-climbing binary-expression parser (left-associative). }
function ParseCBinExpr(minPrec: Integer): Integer;
var left, right, cTok, prec: Integer;
begin
  left := ParseCUnary;
  while True do
  begin
    prec := CBinPrec(CurTok.Kind);
    if prec < minPrec then Break;
    cTok := Ord(CurTok.Kind);
    Next;
    right := ParseCBinExpr(prec + 1);   { left-assoc: strictly-higher on the right }
    left := CMakeBinop(cTok, left, right);
  end;
  Result := left;
end;

{ The pointer to a va_list's control block, for the __pxx_va_* helpers. va_list
  is `__pxx_va_elem[1]`, so a LOCAL va_list is an array — take its address (&ap[0]).
  A va_list PARAMETER decayed to a pointer at the call site, so the identifier
  already IS the control-block pointer — pass it as-is. }
function CVaListAddr(apNode: Integer): Integer;
begin
  Result := AllocNode(AN_ADDR);
  ASTLeft[Result] := apNode;
  ASTIVal[Result] := ResolveNodeRec(apNode);
  ASTTk[Result] := Ord(tyPointer);
end;

{ A primary: integer/char/string literal, parenthesised expr, identifier
  (constant -> folded literal; variable -> AN_IDENT; name followed by `(` ->
  call with an AN_ARG chain). }
function ParseCPrimary: Integer;
var node, idx, procIdx, argHead, argTail, argNode, valNode, calleeNode: Integer;
    apNode, addrNode, callNode, helper, a2, a3, a4, a5, a5arg: Integer;
    vaK, vaPIdx, vaGpBytes, vaRegSz: Integer;
    vt: TTypeKind;
    name: AnsiString;
begin
  Result := -1;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := CurTok.IVal;
      if (CAttrFlags[TokPos - 1] and 4) <> 0 then
        { `u`/`U`-suffixed literal: unsigned. <=2^32-1 is unsigned int (tyUInt32),
          else unsigned long (tyUInt64). }
        if (CurTok.IVal >= 0) and (CurTok.IVal <= $FFFFFFFF) then
          ASTTk[node] := Ord(tyUInt32)
        else
          ASTTk[node] := Ord(tyUInt64)
      else if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      Next;
      Result := node;
    end;
    tkFloat:
    begin
      { float literal — IVal carries the IEEE-754 double bit pattern (clexer) }
      node := AllocNode(AN_FLOAT_LIT);
      ASTIVal[node] := CurTok.IVal;
      ASTTk[node] := Ord(tyDouble);
      Next;
      Result := node;
    end;
    tkString:
    begin
      node := AllocNode(AN_STR_LIT);
      ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
      ASTSLen[node] := Tokens[TokPos - 1].SLen;
      ASTTk[node] := Ord(tyString);
      Next;
      { Adjacent string literals concatenate (C: `"a" "b"` == `"ab"`; lua's
        `lua_pushliteral` expands to `"" s`). The decoded chars of consecutive
        string tokens are contiguous in TokChars, so just extend the length. }
      while CurTok.Kind = tkString do
      begin
        ASTSLen[node] := ASTSLen[node] + Tokens[TokPos - 1].SLen;
        Next;
      end;
      Result := node;
    end;
    tkLParen:
    begin
      Next;
      Result := ParseCExpr;
      { Parenthesized comma EXPRESSION `(a, b, c)` — evaluate each for side
        effects, yield the last. lua uses `((void)l, expr)` pervasively (api_check
        / lua_lock expand to it). Build left-nested AN_COMMA nodes. }
      while CurTok.Kind = tkComma do
      begin
        Next;
        valNode := ParseCExpr;
        node := AllocNode(AN_COMMA);
        ASTLeft[node] := Result;       { evaluated, discarded }
        ASTRight[node] := valNode;     { yields the value }
        ASTTk[node] := ASTTk[valNode];
        Result := node;
      end;
      Expect(tkRParen, ')');
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      Next;
      { varargs builtins, desugared over stdarg.h's va_list struct + the pure-C
        __pxx_va_* helpers (so the only special codegen is the variadic prologue). }
      if (name = '__builtin_va_arg') and (CurTok.Kind = tkLParen) then
      begin
        { __builtin_va_arg(ap, type) -> *(type*)__pxx_va_arg_{gp|fp}(&ap) }
        Next;
        apNode := ParseCExpr; Eat(tkComma);
        vt := ParseCDeclType;
        if CTypePtrDepth > 0 then vt := tyPointer;
        Expect(tkRParen, ')');
        addrNode := CVaListAddr(apNode);
        { SysV AMD64 variadic ABI: integer/pointer args arrive in the GP regs and
          floats in the XMM regs; the variadic prologue saves both classes into
          __va_save (GP at +0, XMM/FP at +48). va_arg(double) therefore reads the
          FP save area, va_arg(int/ptr) the GP area. (An earlier model pushed every
          arg through GP and read floats from gp too; that mismatched the actual
          SysV call+prologue and made %f/%g render 0 — bug-c-double-vararg.) }
        if TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32] then
        begin
          { 32-bit cross: 4-byte word slots; a 64-bit arg spans two. The helper is
            size-driven — pass the arg's byte size so it steps by 4 or 8. }
          helper := FindProc('__pxx_va_arg_cross32');
          a3 := AllocNode(AN_INT_LIT); ASTIVal[a3] := TypeSize(vt); ASTTk[a3] := Ord(tyInteger);
          argNode := AllocNode(AN_ARG); ASTLeft[argNode] := addrNode;
          a2 := AllocNode(AN_ARG); ASTLeft[a2] := a3; ASTRight[a2] := -1; ASTRight[argNode] := a2;
          callNode := AllocNode(AN_CALL); ASTIVal[callNode] := helper;
          ASTTk[callNode] := Ord(tyPointer); ASTLeft[callNode] := argNode;
          node := AllocNode(AN_DEREF); ASTLeft[node] := callNode; ASTTk[node] := Ord(vt);
          Result := node; Exit;
        end;
        if TargetArch <> TARGET_X86_64 then
          { Cross (aarch64): single GP-style save area (floats carried as GP bits),
            so every type reads through the one 8-byte-slot cross helper. }
          helper := FindProc('__pxx_va_arg_cross')
        else if TypeIsFloat(vt) then
          helper := FindProc('__pxx_va_arg_fp')
        else
          helper := FindProc('__pxx_va_arg_gp');
        argNode := AllocNode(AN_ARG); ASTLeft[argNode] := addrNode; ASTRight[argNode] := -1;
        callNode := AllocNode(AN_CALL); ASTIVal[callNode] := helper;
        ASTTk[callNode] := Ord(tyPointer); ASTLeft[callNode] := argNode;
        node := AllocNode(AN_DEREF); ASTLeft[node] := callNode; ASTTk[node] := Ord(vt);
        Result := node; Exit;
      end
      else if (name = '__builtin_va_start') and (CurTok.Kind = tkLParen) then
      begin
        { __builtin_va_start(ap, last) -> __pxx_va_start_impl(&ap, &__va_save, NGP, __va_overflow, NFP) }
        Next;
        apNode := ParseCExpr; Eat(tkComma);
        valNode := ParseCExpr;   { `last` named param — discarded }
        Expect(tkRParen, ')');
        addrNode := CVaListAddr(apNode);
        idx := FindSym('__va_save');
        a2 := AllocNode(AN_IDENT); ASTIVal[a2] := idx; ASTTk[a2] := Ord(tyRecord);
        node := AllocNode(AN_ADDR); ASTLeft[node] := a2; ASTTk[node] := Ord(tyPointer);
        { Seed counts are capped at the register-class capacity (6 GP / 8 FP):
          named params beyond those spill to the caller stack and never occupy
          the register save area — an uncapped seed (e.g. gp_offset = 7*8)
          would misindex it. The stack-spilled named params are skipped via
          the __va_overflow anchor instead (prologue). }
        a3 := AllocNode(AN_INT_LIT);
        if TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32] then
        begin
          { 32-bit cross: seed gp_offset with the reg-area BYTES consumed by named
            params (one word = 4 bytes, a by-value i64/double = 8), capped at the
            reg-area size; fp_offset carries that reg-area size. i386 has no arg
            registers (regsize 0) so every named+variadic arg is on the stack. }
          if TargetArch = TARGET_ARM32 then vaRegSz := 16
          else if TargetArch = TARGET_RISCV32 then vaRegSz := 32
          else vaRegSz := 0;
          vaGpBytes := 0;
          if CurProc >= 0 then
            for vaK := 0 to Procs[CurProc].ParamCount - 1 do
            begin
              vaPIdx := Procs[CurProc].Params[vaK].SymIdx;
              if ((Procs[CurProc].Params[vaK].TypeKind = tyInt64) or
                  (Procs[CurProc].Params[vaK].TypeKind = tyUInt64) or
                  (Procs[CurProc].Params[vaK].TypeKind = tyDouble)) and
                 (not Syms[vaPIdx].IsRef) and (not Syms[vaPIdx].IsArray) then
                Inc(vaGpBytes, 8)
              else Inc(vaGpBytes, 4);
            end;
          if vaGpBytes > vaRegSz then vaGpBytes := vaRegSz;
          ASTIVal[a3] := vaGpBytes;
        end
        else if TargetArch <> TARGET_X86_64 then
        begin
          { Cross (aarch64): one GP save area, every named param (any class)
            consumed one slot, so seed gp_offset past ALL named args (capped to
            the 8-slot area). fp_offset is unused by __pxx_va_arg_cross. }
          if CurProc >= 0 then ASTIVal[a3] := ProcNamedGP[CurProc] + ProcNamedFP[CurProc]
          else ASTIVal[a3] := 0;
          if ASTIVal[a3] > 8 then ASTIVal[a3] := 8;
        end
        else
        begin
          if CurProc >= 0 then ASTIVal[a3] := ProcNamedGP[CurProc] else ASTIVal[a3] := 0;
          if ASTIVal[a3] > 6 then ASTIVal[a3] := 6;
        end;
        ASTTk[a3] := Ord(tyInteger);
        idx := FindSym('__va_overflow');
        a4 := AllocNode(AN_IDENT); ASTIVal[a4] := idx; ASTTk[a4] := Ord(tyPointer);
        a5 := AllocNode(AN_INT_LIT);
        if TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32] then
          ASTIVal[a5] := vaRegSz                 { 5th arg = reg-area size for impl32 }
        else
        begin
          if CurProc >= 0 then ASTIVal[a5] := ProcNamedFP[CurProc] else ASTIVal[a5] := 0;
          if ASTIVal[a5] > 8 then ASTIVal[a5] := 8;
        end;
        ASTTk[a5] := Ord(tyInteger);
        if TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32] then
          helper := FindProc('__pxx_va_start_impl32')
        else
          helper := FindProc('__pxx_va_start_impl');
        argNode := AllocNode(AN_ARG); ASTLeft[argNode] := addrNode;
        calleeNode := AllocNode(AN_ARG); ASTLeft[calleeNode] := node; ASTRight[argNode] := calleeNode;
        valNode := AllocNode(AN_ARG); ASTLeft[valNode] := a3; ASTRight[calleeNode] := valNode;
        apNode := AllocNode(AN_ARG); ASTLeft[apNode] := a4; ASTRight[valNode] := apNode;
        a5arg := AllocNode(AN_ARG); ASTLeft[a5arg] := a5; ASTRight[apNode] := a5arg; ASTRight[a5arg] := -1;
        callNode := AllocNode(AN_CALL); ASTIVal[callNode] := helper;
        ASTTk[callNode] := Ord(tyPointer); ASTLeft[callNode] := argNode;
        Result := callNode; Exit;
      end
      else if (name = '__builtin_va_end') and (CurTok.Kind = tkLParen) then
      begin
        Next; apNode := ParseCExpr; Expect(tkRParen, ')');
        node := AllocNode(AN_INT_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyInteger);
        Result := node; Exit;
      end
      else if (name = '__builtin_va_copy') and (CurTok.Kind = tkLParen) then
      begin
        { __builtin_va_copy(dest, src) duplicates a va_list's traversal state.
          va_list is `__pxx_va_elem[1]` (a 24-byte control block), so copy that
          record from &src[0] to &dest[0]. Build an assignment of two record-typed
          derefs; the record-copy path emits IR_COPY_REC of the full struct. }
        Next;
        apNode := ParseCExpr; Eat(tkComma);   { dest }
        valNode := ParseCExpr;                 { src }
        Expect(tkRParen, ')');
        addrNode := CVaListAddr(apNode);       { &dest[0], ASTIVal = elem rec }
        a2 := CVaListAddr(valNode);            { &src[0] }
        a3 := AllocNode(AN_DEREF); ASTLeft[a3] := addrNode;
        ASTTk[a3] := Ord(tyRecord); ASTIVal[a3] := ASTIVal[addrNode];
        a4 := AllocNode(AN_DEREF); ASTLeft[a4] := a2;
        ASTTk[a4] := Ord(tyRecord); ASTIVal[a4] := ASTIVal[a2];
        node := AllocNode(AN_ASSIGN); ASTLeft[node] := a3; ASTRight[node] := a4;
        ASTTk[node] := Ord(tyRecord);
        Result := node; Exit;
      end;
      if CurTok.Kind = tkLParen then
      begin
        { call — direct (named function) or indirect (fn-pointer variable) }
        Next;
        argHead := -1; argTail := -1;
        if CurTok.Kind <> tkRParen then
        begin
          while True do
          begin
            valNode := ParseCExpr;
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := valNode;
            ASTRight[argNode] := -1;
            if argHead = -1 then argHead := argNode
            else ASTRight[argTail] := argNode;
            argTail := argNode;
            if CurTok.Kind = tkComma then begin Next; Continue; end;
            Break;
          end;
        end;
        Expect(tkRParen, ')');
        { gcc builtin `__builtin_expect(x, c)` is a branch-prediction hint that
          evaluates to its first argument — lua uses it pervasively via
          l_likely/l_unlikely. Reduce it to that argument's value. }
        if (name = '__builtin_expect') and (argHead >= 0) then
        begin
          Result := ASTLeft[argHead];
          Exit;
        end;
        procIdx := FindProc(name);
        if procIdx >= 0 then
        begin
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTTk[node] := Ord(Procs[procIdx].RetType);
          ASTLeft[node] := argHead;
        end
        else
        begin
          idx := FindSym(name);
          if (idx >= 0) and (SymProcSig[idx] >= 0) then
          begin
            { `f(args)` where f is a fn-pointer variable -> indirect call.
              ASTRight = the callee value (the variable), ASTIVal = the
              signature Procs[] index (marshalling + return type). }
            calleeNode := AllocNode(AN_IDENT);
            ASTIVal[calleeNode] := idx;
            ASTTk[calleeNode] := Ord(tyPointer);
            node := AllocNode(AN_CALL_IND);
            ASTLeft[node]  := argHead;
            ASTRight[node] := calleeNode;
            ASTIVal[node]  := SymProcSig[idx];
            ASTTk[node]    := Ord(Procs[SymProcSig[idx]].RetType);
            ASTSLen[node]  := 0;
          end
          else
            Error('call to undeclared function: ' + name);
        end;
        Result := node;
      end
      else
      begin
        idx := FindSym(name);
        if idx < 0 then
        begin
          { A bare function name decays to its address (a fn-pointer value),
            e.g. `BinOp f = add;`. Otherwise an unresolved identifier (a token
            left by a self-referential / unmodelled macro) degrades to a 0
            literal — best-effort frontend, matching the old skip leniency. }
          procIdx := FindProc(name);
          if procIdx >= 0 then
          begin
            node := AllocNode(AN_PROCADDR);
            ASTIVal[node] := procIdx;
            ASTTk[node] := Ord(tyPointer);
          end
          else
          begin
            node := AllocNode(AN_INT_LIT);
            ASTIVal[node] := 0;
            ASTTk[node] := Ord(tyInteger);
          end;
        end
        else if Syms[idx].Kind = skConst then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Syms[idx].ConstVal;
          ASTTk[node] := Ord(Syms[idx].TypeKind);
        end
        else
        begin
          node := AllocNode(AN_IDENT);
          ASTIVal[node] := idx;
          ASTTk[node] := Ord(Syms[idx].TypeKind);
        end;
        Result := node;
      end;
    end;
    else
      Error('expected C expression');
  end;
end;

function CNodePtrDepth(node: Integer): Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := SymPtrDepth[ASTIVal[node]]
    else if Syms[ASTIVal[node]].TypeKind = tyPointer then
    begin
      Result := SymPtrDepth[ASTIVal[node]];
      if Result = 0 then Result := 1;
    end;
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      if (ASTKind[ASTLeft[node]] = AN_IDENT) and Syms[ASTIVal[ASTLeft[node]]].IsArray then
        Result := SymPtrDepth[ASTIVal[ASTLeft[node]]]
      else
      begin
        Result := CNodePtrDepth(ASTLeft[node]) - 1;
        if Result < 1 then Result := 1;
      end;
    end;
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      Result := CNodePtrDepth(ASTLeft[node]) - 1;
      if Result < 1 then Result := 1;
    end;
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      if (ASTIVal[node] >= 0) and (AliasPtrDepth[ASTIVal[node]] > 0) then
        Result := AliasPtrDepth[ASTIVal[node]]
      else
        Result := 1;
    end;
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if CNodeIsPointer(ASTLeft[node]) then Result := CNodePtrDepth(ASTLeft[node])
    else if CNodeIsPointer(ASTRight[node]) then Result := CNodePtrDepth(ASTRight[node]);
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTLeft[ASTRight[node]]) then
      Result := CNodePtrDepth(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTRight[ASTRight[node]]) then
      Result := CNodePtrDepth(ASTRight[ASTRight[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePtrDepth(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePtrDepth(ASTLeft[node]);
end;

function CNodePtrBaseTk(node: Integer): Integer;
var baseNode: Integer;
begin
  Result := Ord(tyUnknown);
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := SymPtrBaseTk[ASTIVal[node]]
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    Result := CNodePtrBaseTk(baseNode);
  end
  else if ASTKind[node] = AN_DEREF then
    Result := CNodePtrBaseTk(ASTLeft[node])
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    if (ASTIVal[node] >= 0) and (AliasPtrBaseTk[ASTIVal[node]] <> Ord(tyUnknown)) then
      Result := AliasPtrBaseTk[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if CNodeIsPointer(ASTLeft[node]) then Result := CNodePtrBaseTk(ASTLeft[node])
    else if CNodeIsPointer(ASTRight[node]) then Result := CNodePtrBaseTk(ASTRight[node]);
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTLeft[ASTRight[node]]) then
      Result := CNodePtrBaseTk(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTRight[ASTRight[node]]) then
      Result := CNodePtrBaseTk(ASTRight[ASTRight[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePtrBaseTk(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePtrBaseTk(ASTLeft[node]);
end;

{ Pointed-at / element TTypeKind ordinal of a pointer or array node, used to tag
  AN_DEREF / AN_INDEX results. Defaults to Integer for shapes not yet modelled. }
function CNodePointeeTk(node: Integer): Integer;
var recId, inner, depth, baseTk: Integer; fieldName: AnsiString;
begin
  Result := Ord(tyInteger);
  if node < 0 then Exit;
  { A string literal is a `char[]`, so indexing/dereferencing it yields a char —
    the rvalue load must be a single byte. Defaulting to tyInteger read 4 bytes,
    so `int c = "abc"[0]` came back with the adjacent chars in the high bits
    (c != 'a' though c & 0xFF was right). }
  if ASTKind[node] = AN_STR_LIT then
  begin
    Result := Ord(tyChar);
    Exit;
  end;
  if (ASTKind[node] = AN_DEREF) and (ASTLeft[node] >= 0) and
     (ASTKind[ASTLeft[node]] = AN_ADDR) then
  begin
    { `**(&mp)` — the inner `*(&mp)` IS mp, so the outer load's width is mp's
      own pointee. Without this the outer deref of tcc's TOK_GET `**(p)`
      (p substituted as &macro_ptr) loaded 8 bytes and every token comparison
      saw garbage in the high half. Any other AN_DEREF operand falls through
      to the depth-aware case below. }
    Result := CNodePointeeTk(ASTLeft[ASTLeft[node]]);
    Exit;
  end;
  if ASTKind[node] = AN_ADDR then
  begin
    { `*(&x)` — the deref of an address-of yields x's own type. Without this the
      pointee defaulted to tyInteger and a `*(&d) = expr` store of an 8-byte
      double (lua's `tonumber` macro: `*(n) = fltvalue(o)` with n = &local)
      truncated to a 4-byte store, dropping the high 32 bits of every float. }
    inner := ASTLeft[node];
    if inner < 0 then
      Result := Ord(tyInteger)
    else if (ASTKind[inner] = AN_IDENT) and not Syms[ASTIVal[inner]].IsArray then
      Result := Ord(Syms[ASTIVal[inner]].TypeKind)
    else if ASTKind[inner] = AN_FIELD then
    begin
      recId := ResolveNodeRec(ASTLeft[inner]);
      fieldName := GetASTIdentName(inner);
      if not RecFieldIsArray(recId, fieldName) then
        Result := Ord(RecFieldType(recId, fieldName))
      else
        Result := ASTTk[inner];
    end
    else
      Result := ASTTk[inner];
    Exit;
  end;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := Ord(Syms[ASTIVal[node]].ElemType)
    else if Syms[ASTIVal[node]].TypeKind = tyPointer then
    begin
      depth := SymPtrDepth[ASTIVal[node]];
      if depth >= 2 then
        Result := Ord(tyPointer)
      else
        Result := Ord(Syms[ASTIVal[node]].PtrElemTk);
    end;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    if RecFieldIsArray(recId, fieldName) then
      Result := Ord(RecFieldType(recId, fieldName))
    else if RecFieldType(recId, fieldName) = tyPointer then
      Result := Ord(RecFieldPtrElemTk(recId, fieldName));
  end
  else if ASTKind[node] = AN_CALL then
  begin
    if (ASTIVal[node] >= 0) and
       (Procs[ASTIVal[node]].RetType = tyPointer) then
      Result := ProcRetPtrElemTk[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    { `*(T*)expr`: the cast carries the pointed-at type in its type-alias slot
      (castDepth>0 -> ASTIVal = alias idx, AliasElemTk = T). Without this the
      deref defaulted to tyInteger and a `*(long*)&d` / `*(double*)p` load read
      only 4 bytes — narrowing every 8-byte double moved through a pointer cast. }
    if (IntToTypeKind(ASTTk[node]) = tyPointer) and (ASTIVal[node] >= 0) then
      Result := AliasElemTk[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      depth := CNodePtrDepth(node);
      baseTk := CNodePtrBaseTk(node);
      if depth >= 2 then
        Result := Ord(tyPointer)
      else if baseTk <> Ord(tyUnknown) then
        Result := baseTk
      else if ASTKind[ASTLeft[node]] = AN_IDENT then
        Result := Ord(Syms[ASTIVal[ASTLeft[node]]].PtrElemTk)
      else
        Result := ASTTk[node];
    end
    else
      Result := ASTTk[node];
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    if IntToTypeKind(ASTTk[node]) = tyPointer then
    begin
      depth := CNodePtrDepth(node);
      baseTk := CNodePtrBaseTk(node);
      if depth >= 2 then
        Result := Ord(tyPointer)
      else if baseTk <> Ord(tyUnknown) then
        Result := baseTk
      else
        Result := ASTTk[node];
    end
    else
      Result := ASTTk[node];
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if CNodeIsPointer(ASTLeft[node]) then
      Result := CNodePointeeTk(ASTLeft[node])
    else if CNodeIsPointer(ASTRight[node]) then
      Result := CNodePointeeTk(ASTRight[node]);
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTLeft[ASTRight[node]]) then
      Result := CNodePointeeTk(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and CNodeDecaysToPointer(ASTRight[ASTRight[node]]) then
      Result := CNodePointeeTk(ASTRight[ASTRight[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePointeeTk(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePointeeTk(ASTLeft[node]);
end;

{ True when a node denotes a pointer value, so `.`/`->` (both lex to tkDot in C)
  on it means C `->` (deref then field) rather than direct field access. }
function CNodeIsPointer(node: Integer): Boolean;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := (Syms[ASTIVal[node]].TypeKind = tyPointer) and not Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldType(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) = tyPointer
  else if ASTKind[node] = AN_INDEX then
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_DEREF then
    { `*p` where p is `T**`: the deref is itself a pointer value, so `(*p)->f`
      is a real C `->` (deref then field), not a `.` on an embedded record.
      ParseCUnary tags AN_DEREF with the pointee type (CNodePointeeTk). Without
      this, `(*p)->f` mis-lowered to a field of the slot holding `*p` (it read /
      addressed `p`'s own storage instead of `*p`'s target). }
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if (ASTKind[node] = AN_BINOP) or (ASTKind[node] = AN_INCDEC) then
    { pointer arithmetic / `p++` keeps a pointer type (CMakeBinop / CMakeIncDec) }
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_CALL then
    { a function returning a pointer — `f()->field` must deref the result }
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_PTR_CAST then
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_TERNARY then
    Result := IntToTypeKind(ASTTk[node]) = tyPointer
  else if ASTKind[node] = AN_ADDR then
    Result := True
  else if ASTKind[node] = AN_ASSIGN then
    { `(p = x)->field`: the assignment yields the (pointer) LHS value }
    Result := CNodeIsPointer(ASTLeft[node]);
end;

function CNodeDecaysToPointer(node: Integer): Boolean;
var recId: Integer; fieldName: AnsiString;
begin
  Result := CNodeIsPointer(node);
  if Result or (node < 0) then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1)
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    Result := RecFieldIsArray(recId, fieldName) and
              (RecFieldDynDepth(recId, fieldName) = 0);
  end;
end;

{ Pointed-at record id of a pointer-valued node, for `(p+i)->field` resolution.
  Pointer-arithmetic binops / `p++` carry it on ASTSOffset. }
function CNodePtrElemRec(node: Integer): Integer;
var baseNode, recId: Integer; fieldName: AnsiString;
begin
  Result := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray then
      Result := Syms[ASTIVal[node]].ElemRecName
    else
      Result := Syms[ASTIVal[node]].PtrElemRec;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    if RecFieldIsArray(recId, fieldName) then
      Result := ResolveNodeRec(node)
    else
      Result := RecFieldPtrElemRec(recId, fieldName);
  end
  else if ASTKind[node] = AN_ADDR then
  begin
    if ASTIVal[node] > 0 then
      Result := ASTIVal[node]
    else
      Result := ResolveNodeRec(ASTLeft[node]);
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    if ASTKind[baseNode] = AN_IDENT then
      Result := Syms[ASTIVal[baseNode]].PtrElemRec
    else if ASTKind[baseNode] = AN_FIELD then
    begin
      recId := ResolveNodeRec(ASTLeft[baseNode]);
      fieldName := GetASTIdentName(baseNode);
      Result := RecFieldPtrElemRec(recId, fieldName);
    end;
  end
  else if ASTKind[node] = AN_BINOP then
    Result := ASTSOffset[node]      { pointer-arith binop carries the elem rec }
  else if ASTKind[node] = AN_TERNARY then
    Result := ASTSOffset[node]
  else if ASTKind[node] = AN_CALL then
  begin
    if (ASTIVal[node] >= 0) and
       (Procs[ASTIVal[node]].RetType = tyPointer) then
      Result := ProcRetPtrElemRec[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    if ASTIVal[node] >= 0 then
      Result := AliasElemRec[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_INCDEC then
    Result := CNodePtrElemRec(ASTLeft[node])   { `p++`: elem rec from the lvalue }
  else if ASTKind[node] = AN_DEREF then
    { `*p` where p is `T**`: *p is a `T*` whose pointed-at record is the same
      base record recorded on p. Needed so `(*p)->field` resolves non-zero field
      offsets (without it the record was unknown and every field landed at 0). }
    Result := CNodePtrElemRec(ASTLeft[node])
  else if ASTKind[node] = AN_ASSIGN then
    Result := CNodePtrElemRec(ASTLeft[node]);
end;

{ Size in bytes of the type just consumed by ParseCDeclType (globals CType*). }
function CTypeSizeBytes(tk: TTypeKind): Integer;
begin
  if CTypePtrDepth > 0 then Result := TARGET_PTR_SIZE
  else if tk = tyRecord then Result := RecSize(CTypeBaseRec)
  else Result := TypeSize(tk);
end;

{ `sizeof(type)`, `sizeof(expr)`, or `sizeof expr` -> a compile-time integer.
  CurTok is the `sizeof` identifier. Folds a type operand to its size; an
  identifier operand to its symbol's size; otherwise a conservative pointer
  size (full expression-type sizing arrives with the type system). }
function ParseCSizeof: Integer;
var node, sz, si, depth, recId, arrLen, savedPos: Integer; tk, elemTk: TTypeKind; fieldName: AnsiString;
begin
  Next; { sizeof }
  sz := TARGET_PTR_SIZE;
  node := -1;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    savedPos := TokPos;
    if IsCTypeTok then
    begin
      tk := ParseCDeclType;
      sz := CTypeSizeBytes(tk);
    end
    else if CurTok.Kind = tkStar then
    begin
      { `sizeof(*p)` -> size of the pointed-at type, not the pointer. Without
        this the operand fell through to the default pointer size, so e.g. lua's
        `memcpy(ra+4, ra, 3*sizeof(*ra))` (ra a StackValue*) copied 3*8 instead
        of 3*16 bytes and dropped the generic-for state/control values. }
      Next;  { consume '*' }
      if CurTok.Kind = tkIdent then
      begin
        si := FindSym(CurTok.SVal);
        { `sizeof(*s.field)` / `sizeof(*s->field)` — deref of a pointer-typed
          struct field yields the field's POINTEE size, not the pointer size.
          Without this `CLEAR_HASH`'s `(hash_size-1)*sizeof(*s->head)` (head a
          `Pos*`) used 8 instead of 2 and zmemzero'd ~4x too much, wiping the
          deflate flush marker. tkDot covers both `.` and `->`. }
        if (si >= 0) and (Tokens[TokPos].Kind = tkDot) and
           (Tokens[TokPos + 1].Kind = tkIdent) then
        begin
          fieldName := GetTokenStrFromRaw(Tokens[TokPos + 1].SOffset, Tokens[TokPos + 1].SLen);
          recId := REC_NONE;
          if Syms[si].TypeKind = tyPointer then recId := Syms[si].PtrElemRec
          else if Syms[si].TypeKind = tyRecord then
          begin
            { an ARRAY of records keeps the element record in ElemRecName
              (RecName is unset) — `arr->field` / `arr[i].field` sizing }
            if Syms[si].IsArray then recId := Syms[si].ElemRecName
            else recId := Syms[si].RecName;
          end;
          if (recId <> REC_NONE) and (RecFieldType(recId, fieldName) = tyPointer) then
          begin
            elemTk := RecFieldPtrElemTk(recId, fieldName);
            if elemTk = tyRecord then sz := RecSize(RecFieldPtrElemRec(recId, fieldName))
            else sz := TypeSize(elemTk);
          end;
        end
        else if (si >= 0) and (Syms[si].TypeKind = tyPointer) then
        begin
          if Syms[si].PtrElemTk = tyRecord then sz := RecSize(Syms[si].PtrElemRec)
          else sz := TypeSize(Syms[si].PtrElemTk);
        end;
      end;
    end
    else if CurTok.Kind = tkString then
    begin
      { `sizeof("lit")` is the char-array size = decoded byte length + 1 (NUL),
        NOT the default pointer size. lua's `new_localvarliteral(ls,v)` registers
        a hidden local of length `sizeof(v)-1`; with the pointer-size default,
        `sizeof("self")-1` was 7 not 4, so the colon-method `self` parameter was
        registered under a 7-char garbage name and every `self` reference inside
        the body resolved to a nil global. The string token carries its decoded
        length in SLen (escapes already folded). }
      sz := Tokens[TokPos - 1].SLen + 1;
    end
    else if CurTok.Kind = tkIdent then
    begin
      si := FindSym(CurTok.SVal);
      if si >= 0 then
      begin
        Next;
        if CurTok.Kind = tkDot then
        begin
          Next;
          if CurTok.Kind = tkIdent then
          begin
            fieldName := CurTok.SVal;
            recId := REC_NONE;
            if Syms[si].TypeKind = tyPointer then
              recId := Syms[si].PtrElemRec
            else if Syms[si].TypeKind = tyRecord then
            begin
              { an ARRAY of records keeps the element record in ElemRecName
                (RecName is unset) — `arr->field` sizing, c-testsuite 00205's
                `sizeof(cases->c)/sizeof(cases->c[0])` }
              if Syms[si].IsArray then recId := Syms[si].ElemRecName
              else recId := Syms[si].RecName;
            end;
            if recId <> REC_NONE then
            begin
              if Tokens[TokPos].Kind = tkLBrack then
              begin
                if RecFieldIsArray(recId, fieldName) then
                begin
                  elemTk := RecFieldType(recId, fieldName);
                  if elemTk = tyRecord then
                    sz := RecSize(RecFieldRecId(recId, fieldName))
                  else
                    sz := TypeSize(elemTk);
                end
                else if RecFieldType(recId, fieldName) = tyPointer then
                begin
                  elemTk := RecFieldPtrElemTk(recId, fieldName);
                  if elemTk = tyRecord then
                    sz := RecSize(RecFieldPtrElemRec(recId, fieldName))
                  else
                    sz := TypeSize(elemTk);
                end
                else if RecFieldType(recId, fieldName) = tyRecord then
                  sz := RecSize(RecFieldRecId(recId, fieldName))
                else
                  sz := TypeSize(RecFieldType(recId, fieldName));
              end
              else if RecFieldIsArray(recId, fieldName) and (RecFieldArrLen(recId, fieldName) >= 0) then
              begin
                arrLen := RecFieldArrLen(recId, fieldName);
                elemTk := RecFieldType(recId, fieldName);
                if elemTk = tyRecord then
                  sz := arrLen * RecSize(RecFieldRecId(recId, fieldName))
                else
                  sz := arrLen * TypeSize(elemTk);
              end
              else if RecFieldType(recId, fieldName) = tyRecord then
                sz := RecSize(RecFieldRecId(recId, fieldName))
              else
                sz := TypeSize(RecFieldType(recId, fieldName));
            end;
          end;
        end
        else
        begin
        if CurTok.Kind = tkLBrack then
        begin
          { `sizeof(arr[i])` / `sizeof(p[i])` — the size of ONE element, not the
            whole array. Without this, the ubiquitous `ArraySize(x)` idiom
            `sizeof(x)/sizeof(x[0])` folded to 1 (whole/whole), so e.g. sqlite's
            built-in-extension loop ran a single iteration. }
          if Syms[si].IsArray then
          begin
            if Syms[si].ElemType = tyRecord then sz := RecSize(Syms[si].ElemRecName)
            else sz := TypeSize(Syms[si].ElemType);
          end
          else if Syms[si].TypeKind = tyPointer then
          begin
            if Syms[si].PtrElemTk = tyRecord then sz := RecSize(Syms[si].PtrElemRec)
            else sz := TypeSize(Syms[si].PtrElemTk);
          end
          else sz := TypeSize(Syms[si].TypeKind);
        end
        else if Syms[si].IsArray then
        begin
          if Syms[si].ElemType = tyRecord then
            sz := Syms[si].ArrLen * RecSize(Syms[si].ElemRecName)
          else
            sz := Syms[si].ArrLen * TypeSize(Syms[si].ElemType);
        end
        else if Syms[si].TypeKind = tyRecord then sz := RecSize(Syms[si].RecName)
        else sz := TypeSize(Syms[si].TypeKind);
        end;
      end;
    end;
    { General-expression operand none of the special cases consumed (e.g.
      `sizeof(!a)`, `sizeof(a+b)`): parse it and size by its result type. C `!`
      and comparisons yield int (4). }
    if (sz = TARGET_PTR_SIZE) and (TokPos = savedPos) and
       (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) then
    begin
      node := ParseCExpr;
      tk := IntToTypeKind(ASTTk[node]);
      if tk = tyRecord then sz := RecSize(ResolveNodeRec(node))
      else if tk = tyPointer then sz := TARGET_PTR_SIZE
      else if TypeIsFloat(tk) then sz := TypeSize(tk)
      else sz := 4;
    end;
    { Skip the rest of the operand to the MATCHING `)` — balanced parens, so
      `sizeof((l)[0])` / `sizeof(a[i])` don't stop at an inner `)`. }
    depth := 1;
    while CurTok.Kind <> tkEOF do
    begin
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then
      begin
        Dec(depth);
        if depth = 0 then Break;
      end;
      Next;
    end;
    Expect(tkRParen, ')');
    { `sizeof (expr)->field` / `sizeof (expr).field` (C 6.5.3: the postfix
      chain is part of the operand), e.g. tcc's
      `sizeof ((Stab_Sym*)0)->n_value`. Only fires when the parenthesized
      operand was parsed as a general expression (node >= 0); the field access
      after the `)` belongs to sizeof, so consume it and size the field.
      tkDot covers both `.` and `->`. }
    if (node >= 0) and (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) then
    begin
      Next;   { consume '.' / '->' }
      fieldName := CurTok.SVal;
      recId := CNodePtrElemRec(node);
      if recId = REC_NONE then recId := ResolveNodeRec(node);
      if recId <> REC_NONE then
      begin
        if RecFieldIsArray(recId, fieldName) and (RecFieldArrLen(recId, fieldName) >= 0) then
        begin
          arrLen := RecFieldArrLen(recId, fieldName);
          elemTk := RecFieldType(recId, fieldName);
          if elemTk = tyRecord then sz := arrLen * RecSize(RecFieldRecId(recId, fieldName))
          else sz := arrLen * TypeSize(elemTk);
        end
        else if RecFieldType(recId, fieldName) = tyPointer then sz := TARGET_PTR_SIZE
        else if RecFieldType(recId, fieldName) = tyRecord then
          sz := RecSize(RecFieldRecId(recId, fieldName))
        else sz := TypeSize(RecFieldType(recId, fieldName));
      end;
      Next;   { consume the field name }
    end;
  end
  else if CurTok.Kind = tkIdent then
  begin
    si := FindSym(CurTok.SVal);
    Next;   { consume the base identifier }
    { Unparenthesized `sizeof s.field` / `sizeof p->field` (C 6.5.3): resolve the
      field's size, including array members (`sizeof file->filename` where
      filename is `char[1024]` — tcc's tccpp.c). tkDot covers both `.` and `->`.
      Without this only the base ident was consumed and `->field` dangled. }
    if (si >= 0) and (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) then
    begin
      Next;   { consume '.' / '->' }
      fieldName := CurTok.SVal;
      recId := REC_NONE;
      if Syms[si].TypeKind = tyPointer then recId := Syms[si].PtrElemRec
      else if Syms[si].TypeKind = tyRecord then recId := Syms[si].RecName;
      if recId <> REC_NONE then
      begin
        if RecFieldIsArray(recId, fieldName) and (RecFieldArrLen(recId, fieldName) >= 0) then
        begin
          arrLen := RecFieldArrLen(recId, fieldName);
          elemTk := RecFieldType(recId, fieldName);
          if elemTk = tyRecord then sz := arrLen * RecSize(RecFieldRecId(recId, fieldName))
          else sz := arrLen * TypeSize(elemTk);
        end
        else if RecFieldType(recId, fieldName) = tyPointer then sz := TARGET_PTR_SIZE
        else if RecFieldType(recId, fieldName) = tyRecord then
          sz := RecSize(RecFieldRecId(recId, fieldName))
        else sz := TypeSize(RecFieldType(recId, fieldName));
      end;
      Next;   { consume the field name }
    end
    else if si >= 0 then
    begin
      if Syms[si].IsArray then
      begin
        if Syms[si].ElemType = tyRecord then
          sz := Syms[si].ArrLen * RecSize(Syms[si].ElemRecName)
        else
          sz := Syms[si].ArrLen * TypeSize(Syms[si].ElemType);
      end
      else if Syms[si].TypeKind = tyRecord then sz := RecSize(Syms[si].RecName)
      else sz := TypeSize(Syms[si].TypeKind);
    end;
  end
  else if CurTok.Kind = tkString then
  begin
    { Unparenthesized `sizeof "lit"` — the char-array size (decoded length +
      NUL), same as the parenthesized case above. tcc's ld path does
      `sizeof ARMAG - 1` (ARMAG = "!<arch>\n"): the pointer-size default gave
      7 instead of 8 and every archive-member read was off by one. }
    sz := Tokens[TokPos - 1].SLen + 1;
    Next;
  end
  else
  begin
    { `sizeof unary-expression` without parens (C 6.5.3), e.g. `sizeof 0`,
      `sizeof !a`. Parse the operand at unary precedence (so `sizeof 0 < 2` is
      `(sizeof 0) < 2`) and size it by its result type. A bare integer constant
      is int (4). }
    node := ParseCUnary;
    tk := IntToTypeKind(ASTTk[node]);
    if tk = tyRecord then sz := RecSize(ResolveNodeRec(node))
    else if (tk = tyUnknown) or (tk = tyInteger) then sz := 4
    else sz := TypeSize(tk);
  end;
  node := AllocNode(AN_INT_LIT);
  ASTIVal[node] := sz;
  ASTTk[node] := Ord(tyInteger);
  Result := node;
end;

{ Peek: is the `(` at CurTok the start of a cast `(type)…`? Rewinds. }
function CIsCastAhead: Boolean;
var savedPos: Integer;
begin
  savedPos := TokPos - 1;          { index of the '(' }
  Next;                            { CurTok = first token inside the parens }
  Result := IsCTypeTok;
  TokPos := savedPos; Next;        { rewind to '(' }
end;

{ Unary prefix: `- + ! ~ * &`, sizeof, and casts `(type)expr`. }
function ParseCUnary: Integer;
var node, operand, castElemTk, castElemRec, castDepth, castBaseTk, castBaseRec,
    argSeq, castProcSig: Integer;
    castTk, opTk: TTypeKind; isVoidCast: Boolean;
begin
  { sizeof }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'sizeof') then
  begin
    Result := ParseCSizeof();
    Exit;
  end;
  { cast: (type) unary -> reinterpret/retag the operand to the target type }
  if (CurTok.Kind = tkLParen) and CIsCastAhead then
  begin
    Next; { ( }
    castTk := ParseCDeclType;
    castDepth := CTypePtrDepth;
    castElemTk := CTypeElemTk;
    castElemRec := CTypeElemRec;
    castBaseTk := CTypePtrBaseTk;
    castBaseRec := CTypePtrBaseRec;
    castProcSig := CTypeProcSig;   { fn-pointer cast `(ret(*)(params))e`: callable value }
    isVoidCast := CTypeIsVoid and (CTypePtrDepth = 0);
    Expect(tkRParen, ')');
    operand := ParseCUnary();   { recurses — clobbers the CType* globals, so castProcSig was captured above }
    { `(void)expr` evaluates expr for its side effects and discards the value.
      Return the operand unwrapped so a void-cast call statement (e.g. the lua
      API macro `lua_pushglobaltable` = `((void)lua_rawgeti(...))`) keeps its
      call and is not pruned as a dead retag node. A `void *` cast (depth > 0)
      is a real pointer cast and stays on the retag path below. }
    if isVoidCast then begin Result := operand; Exit; end;
    { A NUMERIC float<->int cast must CONVERT, not bit-reinterpret: `(int)1.5`==1,
      `(double)i`==(double)i. AN_PTR_CAST only retags, so it left the IEEE bits
      and read them as an integer (-> 0). Route through the existing cross-target
      float intrinsics: -203 Trunc (float->int, toward zero = C cast semantics)
      and -206 Int (int->float, cvtsi2sd). Pointer casts, same-class and
      float<->float casts keep the reinterpret/retag path below. }
    opTk := IntToTypeKind(ASTTk[operand]);
    if (castDepth = 0) and (not TypeIsFloat(castTk)) and TypeIsOrdinal(castTk)
       and TypeIsFloat(opTk) then
    begin
      node := AllocNode(AN_CALL); ASTIVal[node] := -203;   { Trunc: float -> int }
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := operand;
      ASTLeft[node] := argSeq; ASTTk[node] := Ord(castTk);
      Result := node; Exit;
    end
    else if (castDepth = 0) and TypeIsFloat(castTk)
            and TypeIsOrdinal(opTk) and (not TypeIsFloat(opTk)) then
    begin
      node := AllocNode(AN_CALL); ASTIVal[node] := -206;   { Int: int -> float }
      argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := operand;
      ASTLeft[node] := argSeq; ASTTk[node] := Ord(castTk);
      Result := node; Exit;
    end;
    { narrow integer cast: truncate + re-extend by target signedness
      (C 6.3.1.3) — see CMakeNarrowIntCast. Pointer-width and 64-bit casts
      keep the plain retag (no value change at full width). }
    if (castDepth = 0) and TypeIsOrdinal(castTk) and (not TypeIsFloat(castTk))
       and (castTk <> tyBoolean) and (castTk <> tyPointer)
       and (TypeSize(castTk) < 8)
       and TypeIsOrdinal(opTk) and (not TypeIsFloat(opTk)) then
      operand := CMakeNarrowIntCast(operand, castTk);
    node := AllocNode(AN_PTR_CAST);
    ASTLeft[node] := operand;
    ASTIVal[node] := -1;            { numeric / pointer reinterpret-retag }
    ASTRight[node] := castProcSig;  { >=0 iff cast to a fn-pointer type: callee sig for CNodeProcSig }
    if castDepth > 0 then
    begin
      RegisterPtrAlias(0, 0, castElemTk, castElemRec, 0, 0);
      AliasPtrDepth[AliasCount-1] := castDepth;
      AliasPtrBaseTk[AliasCount-1] := castBaseTk;
      AliasPtrBaseRec[AliasCount-1] := castBaseRec;
      ASTIVal[node] := AliasCount - 1;
      ASTTk[node] := Ord(tyPointer);
    end
    else ASTTk[node] := Ord(castTk);
    Result := node;
    Exit;
  end;
  case CurTok.Kind of
    tkStar:   { *p dereference }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_DEREF);
      ASTLeft[node] := operand;
      ASTTk[node] := CNodePointeeTk(operand);
      if CNodePtrElemRec(operand) > 0 then
        ASTIVal[node] := CNodePtrElemRec(operand);
      Result := node;
    end;
    tkAmp:    { &x address-of }
    begin
      Next;
      operand := ParseCUnary();
      { `&(call())` is a C constraint violation only the crtl setjmp macro's
        `&(env)` can produce — when env is a POINTER-VALUED call (tcc's
        `setjmp(_tcc_setjmp(...))`, glibc array-decay style). The pointer value
        already IS the buffer address, so yield the call itself; a struct env
        (an lvalue) still takes the normal address-of path. }
      if (ASTKind[operand] = AN_CALL) and
         (IntToTypeKind(ASTTk[operand]) = tyPointer) then
      begin
        Result := operand;
        Exit;
      end;
      node := AllocNode(AN_ADDR);
      ASTLeft[node] := operand;
      ASTIVal[node] := ResolveNodeRec(operand);
      ASTTk[node] := Ord(tyPointer);
      Result := node;
    end;
    tkMinus:
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_NEG);
      ASTLeft[node] := operand;
      ASTTk[node] := ASTTk[operand];
      Result := node;
    end;
    tkPlus:
    begin
      Next;
      Result := ParseCUnary();
    end;
    tkNot:   { `~` bitwise NOT }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_NOT);
      ASTLeft[node] := operand;
      { Preserve the (promoted) operand type, mirroring unary `-`. Hardcoding
        tyInteger dropped an unsigned/64-bit operand's type, so `~(size_t)0`
        divided as a SIGNED int (-1) — e.g. `(~(size_t)0)/4` came out 0 on
        aarch64. Sub-int operands promote to int per C. }
      opTk := IntToTypeKind(ASTTk[operand]);
      if (opTk = tyChar) or (opTk = tyBoolean) or (TypeSize(opTk) < 4) then
        ASTTk[node] := Ord(tyInteger)
      else
        ASTTk[node] := ASTTk[operand];
      Result := node;
    end;
    tkLogNot:   { `!` logical NOT -> (operand == 0), a 0/1 boolean }
    begin
      Next;
      operand := ParseCUnary();
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := operand;
      ASTRight[node] := AllocNode(AN_INT_LIT);
      ASTIVal[ASTRight[node]] := 0;
      ASTTk[ASTRight[node]] := Ord(tyInteger);
      ASTTk[node] := Ord(tyBoolean);
      Result := node;
    end;
    tkPlusPlus:   { prefix ++lv }
    begin
      Next;
      operand := ParseCUnary();
      Result := CMakeIncDec(operand, True, True);
    end;
    tkMinusMinus: { prefix --lv }
    begin
      Next;
      operand := ParseCUnary();
      Result := CMakeIncDec(operand, False, True);
    end;
    else
      Result := ParseCPostfix();
  end;
end;

{ Procedural-call signature of a node that yields a function-pointer value, or -1.
  Unwraps `*fnptr` (dereferencing a function pointer yields the same callee) and
  resolves the signature of a fn-pointer variable or record field. `callee`
  returns the node whose value is the function address (the var/field itself,
  never the deref) so `(*p->cb)(args)` calls through `p->cb`. }
function CNodeProcSig(node: Integer; var callee: Integer): Integer;
var inner, recId, commaCallee: Integer; fname: AnsiString;
begin
  Result := -1; callee := node;
  if node < 0 then Exit;
  inner := node;
  while ASTKind[inner] = AN_DEREF do inner := ASTLeft[inner];
  callee := inner;
  if ASTKind[inner] = AN_COMMA then
  begin
    { `(a, fn)(args)` — tcc's tcc_error_noabort macro: the comma expr yields the
      callee. The signature comes from the RIGHT arm; the callee stays the WHOLE
      comma node so the left arm's side effects still run (AN_CALL_IND evaluates
      its callee node as a value). }
    Result := CNodeProcSig(ASTRight[inner], commaCallee);
    Exit;
  end;
  if ASTKind[inner] = AN_IDENT then
    Result := SymProcSig[ASTIVal[inner]]
  else if ASTKind[inner] = AN_PROCADDR then
    { `(name)(args)` — a parenthesized bare function name decayed to its address
      (AN_PROCADDR). Its own proc is the call signature; the callee value is the
      procaddr node. Enables the C `(gzgetc)(g)` parenthesized-function-name
      call idiom (zlib's gzgetc macro fallback arm). }
    Result := ASTIVal[inner]
  else if ASTKind[inner] = AN_CALL then
    { `go()(args)` — the callee is the RESULT of a call whose return type is a
      function pointer; that fn's return signature makes the second `()` an
      indirect call. }
    Result := ProcRetProcSig[ASTIVal[inner]]
  else if (ASTKind[inner] = AN_INDEX) and (ASTKind[ASTLeft[inner]] = AN_IDENT) then
    { `arr[i](args)` — call through an element of a function-pointer array; the
      array sym carries the per-element call signature in SymElemProcSig. }
    Result := SymElemProcSig[ASTIVal[ASTLeft[inner]]]
  else if ASTKind[inner] = AN_PTR_CAST then
    Result := ASTRight[inner]   { cast to a fn-pointer type carries its callee sig (>=0), else -1 }
  else if ASTKind[inner] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[inner]);
    if recId <> REC_NONE then
    begin
      fname := GetTokenStrFromRaw(ASTSOffset[inner], ASTSLen[inner]);
      Result := RecFieldProcSig(recId, fname);
    end;
  end;
end;

{ Postfix layer: a primary optionally followed by `++`/`--`. Array/field/call
  postfix (`[] . -> ()`) arrive with the lvalue increment. }
function ParseCPostfix: Integer;
var node, idxExpr, inode, dnode, fnode, baseFld, recId, fldOff, fldLen: Integer;
    argHead, argTail, argNode, valNode, sig, calleeNode2: Integer;
    rowStride, strideLit, mulNode: Integer;
    ndimsF, flatNode, spanD, ndi, nIdx: Integer;
    done: Boolean; fieldName: AnsiString;
begin
  node := ParseCPrimary;
  done := False;
  while not done do
  begin
    if CurTok.Kind = tkLBrack then        { subscript a[i] / p[i] }
    begin
      Next;
      idxExpr := ParseCExpr;
      Expect(tkRBrack, ']');
      if (ASTKind[node] = AN_IDENT) and NodeArrNDInfo(node) and
         (CurTok.Kind = tkLBrack) then
      begin
        { Local/global multidimensional C array `a[i][j]`: flatten the chained
          subscripts to one AN_INDEX over the row-major storage. }
        NDIdxNode[0] := idxExpr;
        nIdx := 1;
        while (CurTok.Kind = tkLBrack) and (nIdx < NDInfoNDims) do
        begin
          Next;
          NDIdxNode[nIdx] := ParseCExpr;
          Inc(nIdx);
          Expect(tkRBrack, ']');
        end;
        if nIdx <> NDInfoNDims then Error('wrong number of array subscripts');
        inode := AllocNode(AN_INDEX);
        ASTLeft[inode] := node;
        ASTRight[inode] := BuildFlatNDIndex(nIdx);
        ASTTk[inode] := Ord(Syms[ASTIVal[node]].ElemType);
        node := inode;
      end
      else if (ASTKind[node] = AN_FIELD) and
         (RecFieldArrNDims(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) >= 2) then
      begin
        { Multidim array struct field `T m[A][B]..`. The generic per-subscript
          AN_INDEX path mis-strides the outer index (CNodePointeeTk(AN_FIELD)
          defaults to Integer -> 4-byte outer stride), so handle the whole
          subscript run here:
          - FULL index `m[i][j]..` (one subscript per dimension): flatten to a
            single AN_INDEX(field, Horner(i,j,..)) — the field-base AN_INDEX
            strides by the real element size, so the address is correct.
          - PARTIAL index `m[i]` (fewer subscripts than dims): C array decay to
            the ROW ADDRESS `&field + i*rowStride` as a raw pointer value, so
            `T** p = m[i]` gets the row and a later `p[j]` indexes it. }
        ndimsF := RecFieldArrNDims(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
        baseFld := node;            { remember the AN_FIELD for stride/row queries }
        flatNode := idxExpr; ndi := 1;
        while (CurTok.Kind = tkLBrack) and (ndi < ndimsF) do
        begin
          Next;
          { flat := flat*span[ndi] + nextIdx  (Horner, element units) }
          spanD := RecFieldArrDimSpanAt(ResolveNodeRec(ASTLeft[baseFld]), GetASTIdentName(baseFld), ndi);
          strideLit := AllocNode(AN_INT_LIT); ASTIVal[strideLit] := spanD; ASTTk[strideLit] := Ord(tyInteger);
          mulNode := AllocNode(AN_BINOP); ASTIVal[mulNode] := Ord(tkStar);
          ASTLeft[mulNode] := flatNode; ASTRight[mulNode] := strideLit; ASTTk[mulNode] := Ord(tyInteger);
          idxExpr := ParseCExpr;
          Expect(tkRBrack, ']');
          inode := AllocNode(AN_BINOP); ASTIVal[inode] := Ord(tkPlus);
          ASTLeft[inode] := mulNode; ASTRight[inode] := idxExpr; ASTTk[inode] := Ord(tyInteger);
          flatNode := inode;
          Inc(ndi);
        end;
        if ndi >= ndimsF then
        begin
          { full index: one flat AN_INDEX, element stride from the field type }
          inode := AllocNode(AN_INDEX);
          ASTLeft[inode] := baseFld;
          ASTRight[inode] := flatNode;
          ASTTk[inode] := Ord(RecFieldType(ResolveNodeRec(ASTLeft[baseFld]), GetASTIdentName(baseFld)));
          node := inode;
        end
        else
        begin
          { partial index -> row pointer. rowStride = product(remaining spans)*elem.
            Tag operands tyInt64 so the add is raw 64-bit (no pointer-stride scale);
            the AN_FIELD value decays to its address as the base. }
          rowStride := RecFieldRowStride(ResolveNodeRec(ASTLeft[baseFld]), GetASTIdentName(baseFld));
          ASTTk[baseFld] := Ord(tyInt64);
          strideLit := AllocNode(AN_INT_LIT); ASTIVal[strideLit] := rowStride; ASTTk[strideLit] := Ord(tyInt64);
          mulNode := AllocNode(AN_BINOP); ASTIVal[mulNode] := Ord(tkStar);
          ASTLeft[mulNode] := flatNode; ASTRight[mulNode] := strideLit; ASTTk[mulNode] := Ord(tyInt64);
          inode := AllocNode(AN_BINOP); ASTIVal[inode] := Ord(tkPlus);
          ASTLeft[inode] := baseFld; ASTRight[inode] := mulNode; ASTTk[inode] := Ord(tyPointer);
          node := inode;
        end;
      end
      else
      begin
        inode := AllocNode(AN_INDEX);
        ASTLeft[inode] := node;
        ASTRight[inode] := idxExpr;
        ASTTk[inode] := CNodePointeeTk(node);
        node := inode;
      end;
    end
    else if CurTok.Kind = tkDot then      { `.` field, or `->` (also tkDot) }
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('field name expected after .');
      fldOff := Tokens[TokPos - 1].SOffset;
      fldLen := Tokens[TokPos - 1].SLen;
      fieldName := CurTok.SVal;
      { On a pointer base this is C `->`: dereference, then take the field. }
      baseFld := node;
      if CNodeIsPointer(node) then
      begin
        dnode := AllocNode(AN_DEREF);
        ASTLeft[dnode] := node;
        ASTTk[dnode] := Ord(tyRecord);
        { A computed pointer (e.g. `(p+i)->f`, `(p++)->f`) has no symbol/field for
          ResolveNodeRec to walk, so carry the element record on the deref
          (ResolveNodeRec honours ASTIVal[AN_DEREF] > 0). }
        if CNodePtrElemRec(node) > 0 then
          ASTIVal[dnode] := CNodePtrElemRec(node);
        baseFld := dnode;
      end;
      recId := ResolveNodeRec(baseFld);
      fnode := AllocNode(AN_FIELD);
      ASTLeft[fnode] := baseFld;
      ASTSOffset[fnode] := fldOff;
      ASTSLen[fnode] := fldLen;
      if recId <> REC_NONE then
        ASTTk[fnode] := Ord(RecFieldType(recId, fieldName))
      else
        ASTTk[fnode] := Ord(tyInteger);
      Next;   { consume field name }
      { fn-pointer field call: `rec.field(args)` / `p->field(args)` lowers to an
        indirect call through the field value (callee = AN_FIELD node). }
      if (CurTok.Kind = tkLParen) and (recId <> REC_NONE) and
         (RecFieldProcSig(recId, fieldName) >= 0) then
      begin
        sig := RecFieldProcSig(recId, fieldName);
        Next;                                 { consume '(' }
        argHead := -1; argTail := -1;
        if CurTok.Kind <> tkRParen then
          while True do
          begin
            valNode := ParseCExpr;
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := valNode; ASTRight[argNode] := -1;
            if argHead = -1 then argHead := argNode
            else ASTRight[argTail] := argNode;
            argTail := argNode;
            if CurTok.Kind = tkComma then begin Next; Continue; end;
            Break;
          end;
        Expect(tkRParen, ')');
        inode := AllocNode(AN_CALL_IND);
        ASTLeft[inode]  := argHead;
        ASTRight[inode] := fnode;             { callee value = the fn-pointer field }
        ASTIVal[inode]  := sig;
        ASTTk[inode]    := Ord(Procs[sig].RetType);
        ASTSLen[inode]  := 0;
        node := inode;
      end
      else
        node := fnode;
    end
    else if (CurTok.Kind = tkLParen) and (CNodeProcSig(node, calleeNode2) >= 0) then
    begin
      { indirect call through a parenthesized/dereferenced fn-pointer value, e.g.
        `(*g->frealloc)(g->ud, ...)` — lua's allocator idiom. }
      sig := CNodeProcSig(node, calleeNode2);
      Next;                                  { consume '(' }
      argHead := -1; argTail := -1;
      if CurTok.Kind <> tkRParen then
        while True do
        begin
          valNode := ParseCExpr;
          argNode := AllocNode(AN_ARG);
          ASTLeft[argNode] := valNode; ASTRight[argNode] := -1;
          if argHead = -1 then argHead := argNode
          else ASTRight[argTail] := argNode;
          argTail := argNode;
          if CurTok.Kind = tkComma then begin Next; Continue; end;
          Break;
        end;
      Expect(tkRParen, ')');
      inode := AllocNode(AN_CALL_IND);
      ASTLeft[inode]  := argHead;
      ASTRight[inode] := calleeNode2;
      ASTIVal[inode]  := sig;
      ASTTk[inode]    := Ord(Procs[sig].RetType);
      ASTSLen[inode]  := 0;
      node := inode;
    end
    else if (CurTok.Kind = tkPlusPlus) or (CurTok.Kind = tkMinusMinus) then
    begin
      if CurTok.Kind = tkPlusPlus then node := CMakeIncDec(node, True, False)
      else node := CMakeIncDec(node, False, False);
      Next;
    end
    else
      done := True;
  end;
  Result := node;
end;

{ Top-level C expression: assignment (right-assoc), incl. compound-assign and the
  conditional `?:` operator. The comma operator is handled at statement level. }
function ParseCExpr: Integer;
var left, rhs, node, cTok, baseOp, thenE, elseE, pair: Integer;
begin
  left := ParseCBinExpr(1);
  { conditional `cond ? a : b` — sits between logical-or and assignment, and is
    right-associative (`a ? b : c ? d : e` = `a ? b : (c ? d : e)`). Only the
    taken branch is evaluated (lowered via a hidden temp in ir.inc). }
  if CurTok.Kind = tkQuestion then
  begin
    Next;
    thenE := ParseCCommaExpr();   { middle: C `expression`, so comma is allowed }
    Expect(tkColon, ':');
    elseE := ParseCExpr();        { else: right-associative }
    pair := AllocNode(AN_PAIR);
    ASTLeft[pair] := thenE;
    ASTRight[pair] := elseE;
    node := AllocNode(AN_TERNARY);
    ASTLeft[node] := left;        { condition }
    ASTRight[node] := pair;
    ASTTk[node] := CTernaryResultTk(thenE, elseE);
    if CProgramMode and (CNodeDecaysToPointer(thenE) or CNodeDecaysToPointer(elseE)) then
    begin
      ASTTk[node] := Ord(tyPointer);
      if CNodeDecaysToPointer(thenE) then
        ASTSOffset[node] := CNodePtrElemRec(thenE)
      else
        ASTSOffset[node] := CNodePtrElemRec(elseE);
    end;
    left := node;
  end;
  case CurTok.Kind of
    tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq, tkModEq,
    tkAmpEq, tkPipeEq, tkXorEq, tkShlEq, tkShrEq:
    begin
      cTok := Ord(CurTok.Kind);
      Next;
      rhs := ParseCExpr();   { right-associative }
      if cTok <> Ord(tkAssign) then
      begin
        { x OP= y  ==>  x = x OP y. The left operand node is reused as the
          binop's left; since it is a pure lvalue read this is safe. }
        baseOp := Ord(tkPlus);
        if cTok = Ord(tkMinusEq) then baseOp := Ord(tkMinus)
        else if cTok = Ord(tkStarEq) then baseOp := Ord(tkStar)
        else if cTok = Ord(tkSlashEq) then baseOp := Ord(tkSlash)
        else if cTok = Ord(tkModEq) then baseOp := Ord(tkMod)
        else if cTok = Ord(tkAmpEq) then baseOp := Ord(tkAmp)
        else if cTok = Ord(tkPipeEq) then baseOp := Ord(tkPipe)
        else if cTok = Ord(tkXorEq) then baseOp := Ord(tkXor)
        else if cTok = Ord(tkShlEq) then baseOp := Ord(tkShl)
        else if cTok = Ord(tkShrEq) then baseOp := Ord(tkShr);
        rhs := CMakeBinop(baseOp, left, rhs);
      end;
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := left;
      ASTRight[node] := rhs;
      ASTTk[node] := ASTTk[left];
      Result := node;
    end;
    else
      Result := left;
  end;
end;

function CTypedefHashKey(const name: AnsiString): Integer;
var i, h: Integer;
begin
  h := 5381;                  { djb2; small literals to stay self-host safe }
  for i := 1 to Length(name) do
    h := ((h * 33) + Ord(name[i])) and 1073741823;  { mask to 30 bits }
  Result := h and 16383;      { table size - 1 }
end;

function CTypedefNameMatches(idx: Integer; const name: AnsiString): Boolean;
var j: Integer;
begin
  Result := False;
  if CTypedefNameLen[idx] <> Length(name) then Exit;
  for j := 0 to CTypedefNameLen[idx] - 1 do
    if CTypedefChars[CTypedefNameOff[idx] + j] <> name[j + 1] then Exit;
  Result := True;
end;

{ O(1) average lookup via the open-addressed hash. Slots hold idx+1; 0 = empty. }
function FindCTypedef(const name: AnsiString): Integer;
var slot, stored: Integer;
begin
  slot := CTypedefHashKey(name);
  while True do
  begin
    stored := CTypedefHash[slot];
    if stored = 0 then begin Result := -1; Exit; end;
    if CTypedefNameMatches(stored - 1, name) then begin Result := stored - 1; Exit; end;
    slot := (slot + 1) and 16383;
  end;
end;

procedure CTypedefHashInsert(idx: Integer; const name: AnsiString);
var slot: Integer;
begin
  slot := CTypedefHashKey(name);
  while CTypedefHash[slot] <> 0 do slot := (slot + 1) and 16383;
  CTypedefHash[slot] := idx + 1;
end;

{ Index of a struct/union tag in the tag table, or -1. O(1) via CTagHash. }
function CTagNameMatches(idx: Integer; const name: AnsiString): Boolean;
var j: Integer;
begin
  Result := False;
  if CTagNameLen[idx] <> Length(name) then Exit;
  for j := 0 to CTagNameLen[idx] - 1 do
    if CTagChars[CTagNameOff[idx] + j] <> name[j + 1] then Exit;
  Result := True;
end;

function FindCTagIdx(const name: AnsiString): Integer;
var slot, stored: Integer;
begin
  slot := CTypedefHashKey(name);
  while True do
  begin
    stored := CTagHash[slot];
    if stored = 0 then begin Result := -1; Exit; end;
    if CTagNameMatches(stored - 1, name) then begin Result := stored - 1; Exit; end;
    slot := (slot + 1) and 16383;
  end;
end;

{ Struct/union tag lookup. Returns the record id (REC_UCLASS_BASE+ci) or -1. }
function FindCTag(const name: AnsiString): Integer;
var idx: Integer;
begin
  idx := FindCTagIdx(name);
  if idx >= 0 then Result := CTagRec[idx] else Result := -1;
end;

procedure AddCTag(const name: AnsiString; recId: Integer);
var idx, i: Integer;
begin
  idx := FindCTagIdx(name);
  if idx >= 0 then begin CTagRec[idx] := recId; Exit; end;  { update (forward -> defined) }
  if CTagCount >= MAX_CTYPEDEF then Error('C tag table overflow');
  if CTagCharLen + Length(name) >= 524288 then Error('C tag chars pool overflow');
  CTagNameOff[CTagCount] := CTagCharLen;
  CTagNameLen[CTagCount] := Length(name);
  for i := 1 to Length(name) do begin CTagChars[CTagCharLen] := name[i]; Inc(CTagCharLen); end;
  CTagRec[CTagCount] := recId;
  i := CTypedefHashKey(name);
  while CTagHash[i] <> 0 do i := (i + 1) and 16383;
  CTagHash[i] := CTagCount + 1;
  Inc(CTagCount);
end;

{ Resolve a struct/union tag to its record id, creating a forward (empty)
  record if the tag has not been seen — so `struct Node *next;` inside Node and
  forward declarations resolve. }
function FindOrForwardCTag(const name: AnsiString): Integer;
var rec, ci: Integer;
begin
  rec := FindCTag(name);
  if rec >= 0 then begin Result := rec; Exit; end;
  { Out of record-table headroom (e.g. GTK's thousands of tags): resolve the tag
    as opaque (REC_NONE) instead of allocating a UClass, so a macro-soup header
    degrades gracefully rather than overflowing MAX_UCLASS. }
  if UClsCount >= MAX_UCLASS - 1 then begin Result := REC_NONE; Exit; end;
  ci := AddUClass(0, 0);
  UClsIsRecord[ci] := True;
  rec := REC_UCLASS_BASE + ci;
  AddCTag(name, rec);
  Result := rec;
end;

{ Lay out an inline struct/union body `{ ... }` (CurTok at the brace) into a
  record, used for `struct|union [tag] { ... }` in a TYPE position. `rec` is the
  tag's record (>= REC_UCLASS_BASE) or REC_NONE for an anonymous body; on return
  it holds the laid-out record id. }
procedure CParseInlineAggBody(var rec: Integer; isUnion: Boolean);
var d: Integer;
begin
  if (rec < REC_UCLASS_BASE) and (UClsCount < MAX_UCLASS - 1) then
  begin
    rec := REC_UCLASS_BASE + AddUClass(0, 0);
    UClsIsRecord[rec - REC_UCLASS_BASE] := True;
  end;
  if rec >= REC_UCLASS_BASE then
    ParseCStructInto(rec - REC_UCLASS_BASE, isUnion)
  else
  begin
    d := 0;   { no record headroom: skip the body with balanced braces }
    repeat
      if CurTok.Kind = tkBegin then Inc(d)
      else if CurTok.Kind = tkEnd then Dec(d);
      Next;
    until (d = 0) or (CurTok.Kind = tkEOF);
  end;
end;

procedure AddCTypedefEx(const name: AnsiString; tk: TTypeKind; elemTk, rec: Integer);
var idx, i: Integer;
begin
  idx := FindCTypedef(name);
  if idx >= 0 then
  begin
    CTypedefTk[idx] := Ord(tk);
    CTypedefElemTk[idx] := elemTk;
    CTypedefRec[idx] := rec;
    CTypedefProcSig[idx] := -1;
    CTypedefIsFnType[idx] := False;
    Exit;
  end;
  if CTypedefCount >= MAX_CTYPEDEF then Error('C typedef table overflow');
  if CTypedefCharLen + Length(name) >= 524288 then Error('C typedef chars pool overflow');

  CTypedefNameOff[CTypedefCount] := CTypedefCharLen;
  CTypedefNameLen[CTypedefCount] := Length(name);
  for i := 1 to Length(name) do
  begin
    CTypedefChars[CTypedefCharLen] := name[i];
    Inc(CTypedefCharLen);
  end;

  CTypedefTk[CTypedefCount] := Ord(tk);
  CTypedefElemTk[CTypedefCount] := elemTk;
  CTypedefRec[CTypedefCount] := rec;
  CTypedefProcSig[CTypedefCount] := -1;
  CTypedefIsFnType[CTypedefCount] := False;
  CTypedefHashInsert(CTypedefCount, name);
  Inc(CTypedefCount);
end;

procedure AddCTypedef(const name: AnsiString; tk: TTypeKind);
begin
  AddCTypedefEx(name, tk, Ord(tyUnknown), REC_NONE);
end;

{ Register a function-pointer typedef: `Name` resolves to a pointer value, but
  carries `sigPi` (a signature Procs[] entry, BodyAddr=-1, ProcCdecl) so a var of
  this type is callable through AN_CALL_IND with proper marshalling. }
procedure AddCTypedefFnPtr(const name: AnsiString; sigPi: Integer);
var idx: Integer;
begin
  AddCTypedef(name, tyPointer);
  idx := FindCTypedef(name);
  if idx >= 0 then CTypedefProcSig[idx] := sigPi;
end;

function CTypedefShadowed(const name: AnsiString): Boolean;
var si: Integer;
begin
  { True when an in-scope ordinary identifier hides a typedef of this name.
    C 6.2.1: an object/function declared in an inner scope with the same name
    hides the typedef there. Must be an EXACT-case match — C is case-sensitive,
    and FindSym has a case-insensitive fallback (`item` would otherwise match a
    typedef `Item` and wrongly suppress it). FindSym is block-scope-aware, so
    this only fires for a live shadow. }
  si := FindSym(name);
  { Only a block-scope local or a parameter can validly shadow a typedef in C —
    a file-scope object with a typedef's name is a redefinition, illegal. So
    restrict to skLocal/skParam: this both matches the real case (trees.c local
    `int code;`) and avoids false shadows from unrelated globals/builtins that
    merely share the name (e.g. a builtin `x` would otherwise suppress `typedef
    int x;` — c-testsuite 00022). Exact-case (C is case-sensitive; FindSym has a
    case-insensitive fallback). }
  Result := (si >= 0) and StrEqual(Syms[si].Name, name)
            and (Syms[si].Kind in [skLocal, skParam]);
end;

function IsCTypeTok: Boolean;
begin
  Result := CurTok.Kind in [tkInteger_T, tkChar_T, tkCVoid, tkCShort,
    tkCLong, tkCSigned, tkCUnsigned, tkCFloat, tkCDouble, tkCBool, tkConst,
    tkRecord { 'struct' }];
  if (not Result) and (CurTok.Kind = tkIdent) then
    Result := (CurTok.SVal = 'union') or (CurTok.SVal = 'enum') or
              { typedef name is a type only if not shadowed by a variable of the
                same exact name — zlib inftrees.h `typedef ... code;` vs trees.c
                `int code;` loop var. }
              ((FindCTypedef(CurTok.SVal) >= 0) and not CTypedefShadowed(CurTok.SVal));
end;

function CUnsignedOf(tk: TTypeKind): TTypeKind;
begin
  Result := tk;
  if tk = tyInt16 then Result := tyUInt16
  else if tk = tyInt32 then Result := tyUInt32
  else if tk = tyInt64 then Result := tyUInt64;
end;

{ Consume a C declaration-specifier sequence (const, signed/unsigned,
  short/long[/long], int/char/void/float/double/_Bool) followed by any
  pointer suffix, and return the mapped Pascal/ABI TTypeKind. Sets the
  global CTypeIsVoid when the result is bare `void` (no pointer). Width and
  signedness are preserved: long/long long -> 8-byte on LP64, short -> 2,
  any pointer -> untyped Pointer (8). }
function ParseCDeclType: TTypeKind;
var
  isUnsigned, isSigned, isFloatTy, isVoid, loop, sawBase, isTypedef, isAggBase: Boolean;
  tdIsFnType: Boolean;
  shortCount, longCount, tdIdx, depth, baseRec, tdElemTk, tdElemRec: Integer;
  base, fpRet, fpPType: TTypeKind;
  fpName: AnsiString;
  fpNameOff, fpNameLen: Integer;   { name token off/len, kept local — a recursive ParseCDeclType (params) resets the globals }
  fpArrLen: Integer;               { array dimension of `(*name[N])` — kept local, restored after the param recursion resets the global }
  fpNParams, fpSig, fnRetNParams, pi: Integer;
  fpPTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  fpPNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
  fnRetPTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  fnRetPNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
  fnRetPDepths, fnRetPBaseTk, fnRetPBaseRec, fnRetPElemTk, fnRetPElemRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  fnRetPRecId, fnRetPProcSig: array[0..MAX_PROC_PARAMS-1] of Integer;
  fnRetIsFunc: Boolean;
begin
  isUnsigned := False; isSigned := False; isFloatTy := False; isVoid := False;
  sawBase := False; isTypedef := False; isAggBase := False;
  shortCount := 0; longCount := 0; base := tyInt32; baseRec := REC_NONE;
  tdElemTk := Ord(tyUnknown); tdElemRec := REC_NONE;
  tdIsFnType := False;
  CTypeProcSig := -1;
  CTypeFnPtrName := '';
  CTypeFnPtrNameOff := 0; CTypeFnPtrNameLen := 0;
  CTypeFnPtrArrLen := -2;
  CTypeFnRetIsFunc := False;
  CTypeFnRetParamCount := 0;
  loop := True;
  while loop do
  begin
    case CurTok.Kind of
      tkConst:     Next;
      tkCSigned:   begin isSigned := True; sawBase := True; Next; end;
      tkCUnsigned: begin isUnsigned := True; sawBase := True; Next; end;
      tkCShort:    begin Inc(shortCount); sawBase := True; Next; end;
      tkCLong:     begin Inc(longCount); sawBase := True; Next; end;
      tkInteger_T: begin base := tyInt32; sawBase := True; Next; end;
      tkChar_T:    begin base := tyChar; sawBase := True; Next; end;
      tkCVoid:     begin isVoid := True; sawBase := True; Next; end;
      tkCFloat:    begin base := tySingle; isFloatTy := True; sawBase := True; Next; end;
      tkCDouble:   begin base := tyDouble; isFloatTy := True; sawBase := True; Next; end;
      tkCBool:     begin base := tyUInt8; sawBase := True; Next; end;
      tkRecord:    { 'struct' [tag] [inline body] in type position }
        begin
          Next;
          base := tyRecord; isAggBase := True; sawBase := True;
          if CurTok.Kind = tkIdent then begin baseRec := FindOrForwardCTag(CurTok.SVal); Next; end;
          if CurTok.Kind = tkBegin then CParseInlineAggBody(baseRec, False);
        end;
      tkIdent:
        begin
          { A typedef name is a type only in type position (before any base
            type is seen); otherwise it is the declarator name — stop.
            `union`/`enum` keywords are idents in this lexer. }
          { Storage classes / qualifiers may appear anywhere in the
            declaration-specifier sequence, including AFTER the type
            (`TCCSem static rt_sem;` — tcc). They're idents in this lexer;
            consume without affecting the type. (A LEADING `static` never
            reaches here — the callers' IsCTypeTok gate fails on it and the
            block-scope statement parser handles it explicitly.) }
          if (CurTok.SVal = 'static') or (CurTok.SVal = 'extern') or
             (CurTok.SVal = 'inline') or (CurTok.SVal = 'volatile') or
             (CurTok.SVal = 'register') or (CurTok.SVal = 'restrict') or
             (CurTok.SVal = '__inline') or (CurTok.SVal = '__inline__') or
             (CurTok.SVal = '_Noreturn') then
            Next
          else if (not sawBase) and (CurTok.SVal = 'union') then
          begin
            Next;
            base := tyRecord; isAggBase := True; sawBase := True;
            if CurTok.Kind = tkIdent then begin baseRec := FindOrForwardCTag(CurTok.SVal); Next; end;
            if CurTok.Kind = tkBegin then CParseInlineAggBody(baseRec, True);
          end
          else if (not sawBase) and (CurTok.SVal = 'enum') then
          begin
            Next;
            if CurTok.Kind = tkIdent then Next;   { tag — enum value is just an int }
            base := tyInt32; sawBase := True;
          end
          else
          begin
            tdIdx := -1;
            if not sawBase then tdIdx := FindCTypedef(CurTok.SVal);
            if tdIdx >= 0 then
            begin
              base := IntToTypeKind(CTypedefTk[tdIdx]);
              baseRec := CTypedefRec[tdIdx];
              tdElemTk := CTypedefElemTk[tdIdx];
              tdElemRec := CTypedefRec[tdIdx];
              CTypeProcSig := CTypedefProcSig[tdIdx]; { fn-pointer typedef carries a call signature }
              tdIsFnType := CTypedefIsFnType[tdIdx];   { function-TYPE typedef: a `*` decays, not indirects }
              sawBase := True; isTypedef := True;
              Next;
            end
            else loop := False;
          end;
        end;
      else loop := False;
    end;
  end;

  CTypeIsVoid := isVoid;

  if isVoid then
    Result := tyInteger          { placeholder; pointer suffix overrides below }
  else if isAggBase then
    Result := tyRecord           { struct/union tag reference }
  else if isTypedef then
    Result := base               { typedef carries its own resolved kind }
  else if isFloatTy then
    Result := base
  else if base = tyUInt8 then
    Result := base               { _Bool is a 1-byte integer type }
  else if base = tyChar then
  begin
    if isSigned then base := tyInt8
    else if isUnsigned then base := tyUInt8;
    Result := base;              { plain char stays tyChar }
  end
  else
  begin
    { C `long` is machine-word-sized (ILP32/LP64): 8 bytes on a 64-bit target,
      4 on a 32-bit one. `long long` is always 64-bit. (Previously `long` was
      64-bit on every target — consistent but C-divergent, and it bloated
      size_t/ptrdiff_t/intptr_t on 32-bit. size_t = `unsigned long` etc. follow
      this automatically via CUnsignedOf.) 64-bit targets keep `long`=tyInt64
      exactly as before (byte-identical); only 32-bit `long` drops to tyInt32. }
    if shortCount > 0 then base := tyInt16
    else if longCount >= 2 then base := tyInt64
    else if longCount = 1 then
    begin
      if TARGET_PTR_SIZE = 8 then base := tyInt64 else base := tyInt32;
    end
    else base := tyInt32;
    if isUnsigned then base := CUnsignedOf(base);
    Result := base;
  end;

  { Pointer suffix. Every star is still an 8-byte Pointer at the value level,
    but we now record the pointed-at type (depth 1) and the depth, so a typed
    handle can deref/index/field correctly and a struct pointer knows its
    record. Depth >= 2 reports the element as Pointer (a `T**` derefs to a
    `T*`). The base (Result) before the stars is the element kind. }
  CTypePtrDepth := 0;
  CTypeElemTk := Ord(tyUnknown);
  CTypeElemRec := REC_NONE;
  CTypePtrBaseTk := Ord(tyUnknown);
  CTypePtrBaseRec := REC_NONE;
  CTypeBaseRec := baseRec;
  if isTypedef and (Result = tyPointer) then
  begin
    CTypeElemTk := tdElemTk;
    CTypeElemRec := tdElemRec;
  end;
  { Function-TYPE typedef `typedef R N(args)` used as `N *p`: the star is the
    C function-to-pointer DECAY, not an extra indirection — `N *p` is the
    callable pointer, same as a fn-pointer typedef's `N p`. Absorb one star,
    keep Result=Pointer + the call signature; any further stars then indirect
    normally through the block below. }
  if tdIsFnType and (CurTok.Kind = tkStar) then
  begin
    Next;                         { consume the decay star }
    while CurTok.Kind = tkConst do Next;
    Result := tyPointer;          { CTypeProcSig stays set: directly callable }
  end;
  if CurTok.Kind = tkStar then
  begin
    CTypeProcSig := -1;           { `FnPtrTypedef *` = pointer-to-fn-ptr, not directly callable }
    CTypeElemTk := Ord(Result);   { the pointed-at scalar/typedef kind at depth 1 }
    CTypeElemRec := baseRec;      { ...and its record id, if it is a struct }
    CTypePtrBaseTk := Ord(Result);
    CTypePtrBaseRec := baseRec;
    while CurTok.Kind = tkStar do
    begin
      Inc(CTypePtrDepth);
      Next;
      { skip a pointer-level `const`/`volatile` qualifier: `char *const p`,
        `T * const * p` — without this the declarator name is never reached and
        the variable goes undeclared (read as 0). }
      while CurTok.Kind = tkConst do Next;
    end;
    if CTypePtrDepth >= 2 then
    begin
      { Pointer-to-pointer: the immediate element is itself a pointer (stride =
        pointer size), but KEEP the base record so `T** p; p[i]->field` resolves
        — ResolveNodeRec consults PtrElemRec at the AN_DEREF(AN_INDEX) (two-level)
        point. Was REC_NONE, which dropped the struct (lua's
        `TString **p = G(L)->strcache[i]; getstr(p[j])`). }
      CTypeElemTk := Ord(tyPointer);
      CTypeElemRec := baseRec;
    end;
    Result := tyPointer;
    CTypeIsVoid := False;
  end;

  { Function-pointer declarator: ret (*name)(params) — e.g. sqlite3_exec's
    callback. Without this the base type (int) leaks through as the param
    type, so a Pointer/nil argument fails overload and would truncate to 4
    bytes. Detect `(` immediately followed by `*`, collapse to Pointer, and
    skip both the `(*name)` declarator group and the trailing `(params)`
    group so the caller's parameter loop resyncs on the next `,`/`)`. }
  if (CurTok.Kind = tkLParen) and (Tokens[TokPos].Kind = tkStar) then
  begin
    fpRet := Result;                  { return type parsed above (before the '(') }
    if isVoid then fpRet := tyInteger;
    Result := tyPointer;
    CTypeIsVoid := False;
    fpName := '';
    fpArrLen := -2;
    fnRetIsFunc := False;
    fnRetNParams := 0;
    { first group `(*name)` — collapse to Pointer, capturing the declarator name }
    depth := 0;
    repeat
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then Dec(depth)
      else if (CurTok.Kind = tkIdent) and (fpName = '') then
      begin
        fpName := CurTok.SVal;
        { CurTok.SOffset/SLen are NOT maintained by Next (it only fills
          Kind/IVal/Line/SVal) — read the live token-char ref from Tokens[]. The
          name is the current token, i.e. Tokens[TokPos-1] (Next pre-increments).
          Keep in locals: the recursive ParseCDeclType for the params resets the
          CTypeFnPtrName* globals. }
        fpNameOff := Tokens[TokPos-1].SOffset; fpNameLen := Tokens[TokPos-1].SLen;
        if Tokens[TokPos].Kind = tkLParen then
        begin
          { Function returning a function pointer: `ret (*Name(params))(...)`.
            The params inside the first group belong to the real function Name,
            not to the returned function pointer. Capture them for
            ParseCSubroutine, then let the outer group consume its closing `)`. }
          fnRetIsFunc := True;
          Next;                         { consume name -> CurTok is '(' }
          Next;                         { consume function param-list '(' }
          while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
          begin
            if CurTok.Kind = tkDot then
            begin
              { variadic marker; ParseCSubroutine does not need it for sqlite's
                fn-returning-fnptr shape, so just consume it. }
              Next;
            end
            else if IsCTypeTok then
            begin
              fpPType := ParseCDeclType();
              if CTypeIsVoid then
              begin
                { `(void)` empty parameter list }
              end
              else if fnRetNParams < MAX_PROC_PARAMS then
              begin
                fnRetPTypes[fnRetNParams] := fpPType;
                fnRetPDepths[fnRetNParams] := CTypePtrDepth;
                fnRetPBaseTk[fnRetNParams] := CTypePtrBaseTk;
                fnRetPBaseRec[fnRetNParams] := CTypePtrBaseRec;
                fnRetPElemTk[fnRetNParams] := CTypeElemTk;
                fnRetPElemRec[fnRetNParams] := CTypeElemRec;
                fnRetPRecId[fnRetNParams] := CTypeBaseRec;
                fnRetPProcSig[fnRetNParams] := CTypeProcSig;
                if CTypeFnPtrName <> '' then
                  fnRetPNames[fnRetNParams] := CTypeFnPtrName
                else if CurTok.Kind = tkIdent then
                begin
                  fnRetPNames[fnRetNParams] := CurTok.SVal;
                  Next;
                end
                else
                begin
                  fnRetPNames[fnRetNParams] := 'arg0';
                  fnRetPNames[fnRetNParams][4] := Chr(Ord('0') + fnRetNParams);
                end;
                Inc(fnRetNParams);
              end;
            end
            else
              Next;
            Eat(tkComma);
          end;
          Eat(tkRParen);
          Continue;
        end;
      end
      else if (CurTok.Kind = tkLBrack) and (fpName <> '') then
      begin
        { Array-of-function-pointer declarator `ret (*name[N])(params)` — capture
          the dimension so the var/global is registered as an ARRAY of callable
          pointers (sqlite's sqlite3BuiltinExtensions[]). `[]` = unbounded (sized
          from its initializer); `[N]` = fixed. The trailing Next below consumes
          the closing ']'. }
        Next;                          { consume '[' }
        if CurTok.Kind = tkRBrack then fpArrLen := -1
        else fpArrLen := CEvalConstExpr;
      end;
      Next;
    until (depth = 0) or (CurTok.Kind = tkEOF);
    { second group `(params)` — capture param types to build a call signature }
    fpNParams := 0;
    if CurTok.Kind = tkLParen then
    begin
      Next;                           { consume the parameter-list '(' }
      while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
      begin
        if IsCTypeTok then
        begin
          { NB parens REQUIRED: bare `ParseCDeclType` would read this function's
            own Result (pxx bare-funcname rule), not recurse -> infinite loop. }
          fpPType := ParseCDeclType();
          if CTypeIsVoid then
          begin
            { (void) — no parameter }
          end
          else if fpNParams < MAX_PROC_PARAMS then
          begin
            fpPTypes[fpNParams] := fpPType;
            fpPNames[fpNParams] := 'a';
            Inc(fpNParams);
          end;
          if CurTok.Kind = tkIdent then Next;  { optional parameter name }
        end
        else
          Next;                       { e.g. `...` varargs marker }
        Eat(tkComma);
      end;
      Eat(tkRParen);
    end;
    { Register the call signature whether or not the declarator carried a name.
      A NAMED form `ret (*name)(params)` threads CTypeFnPtrName onto the
      typedef/var/field/param; an ABSTRACT form `ret (*)(params)` has no name but
      still needs CTypeProcSig set so a cast to a function-pointer type
      (`((int(*)(const char*,int,int))p)(args)` — sqlite's osOpen syscall-table
      idiom) yields a callable value. }
    fpSig := RegisterProc('$cfnptr', True, fpRet, fpNParams, fpPNames, fpPTypes);
    Procs[fpSig].BodyAddr := -1;
    ProcCdecl[fpSig] := True;          { C ABI (System V) for the indirect call }
    CTypeProcSig := fpSig;             { caller threads this onto the typedef/var/field/cast }
    { A function pointer is a non-void pointer VALUE. The inner signature parse
      (e.g. `void (*x)(void)`'s `void` return / `(void)` params) leaves the
      global CTypeIsVoid set, which made an enclosing param list treat the whole
      fn-ptr parameter as a `(void)` no-arg and DROP it — undercounting the outer
      ParamCount (bug-c-fnptr-void-param-dropped, the sqlite3BenignMallocHooks
      arg-count mismatch). Clear it now that the declarator is a pointer. }
    CTypeIsVoid := False;
    if fpName <> '' then
    begin
      CTypeFnPtrName := fpName;
      CTypeFnPtrNameOff := fpNameOff;  { assign AFTER the param recursion that reset the globals }
      CTypeFnPtrNameLen := fpNameLen;
      CTypeFnPtrArrLen := fpArrLen;    { ditto: `(*name[N])` dimension, clobbered by the param recursion }
      if fnRetIsFunc then
      begin
        CTypeFnRetIsFunc := True;
        CTypeFnRetParamCount := fnRetNParams;
        for pi := 0 to fnRetNParams - 1 do
        begin
          CTypeFnRetPTypes[pi] := fnRetPTypes[pi];
          CTypeFnRetPNames[pi] := fnRetPNames[pi];
          CTypeFnRetPDepths[pi] := fnRetPDepths[pi];
          CTypeFnRetPBaseTk[pi] := fnRetPBaseTk[pi];
          CTypeFnRetPBaseRec[pi] := fnRetPBaseRec[pi];
          CTypeFnRetPElemTk[pi] := fnRetPElemTk[pi];
          CTypeFnRetPElemRec[pi] := fnRetPElemRec[pi];
          CTypeFnRetPRecId[pi] := fnRetPRecId[pi];
          CTypeFnRetPProcSig[pi] := fnRetPProcSig[pi];
        end;
      end;
    end;
  end;
end;

function CAllocDeclVar(const name: AnsiString; tk: TTypeKind): Integer;
var savedCurProc: Integer;
begin
  savedCurProc := CurProc;
  if CLocalStaticDecl then CurProc := -1;
  Result := AllocVar(name, tk);
  CurProc := savedCurProc;
end;

function CAllocDeclArray(const name: AnsiString; elemType: TTypeKind; lo, hi: Integer): Integer;
var savedCurProc: Integer;
begin
  savedCurProc := CurProc;
  if CLocalStaticDecl then CurProc := -1;
  Result := AllocArray(name, elemType, lo, hi);
  CurProc := savedCurProc;
end;

{ Wrap a static-local declaration's initializer chain (AN_SEQ head) in a
  one-time guard: `if guard == 0 { guard = 1; <inits> }`. C runs a block-scope
  static's initializer ONCE (load-time semantics), not on every function
  entry; the storage moved to BSS but the init assignments stayed inline in
  the body. The guard is a hidden BSS int (zero at load), so the un-guarded
  first entry runs the inits and every later call skips them.
  See bug-c-static-local-initializer-reruns-every-call. }
function CWrapStaticInitOnce(head: Integer): Integer;
var gsym, savedCurProc, idn, zero, cond, one, asn, seq1, pairN, ifn, blk: Integer;
begin
  savedCurProc := CurProc;
  CurProc := -1;                       { guard is a global (BSS) slot }
  gsym := AllocVar('$staticinit$' + MangleSuffix(SymCount), tyInteger);
  CurProc := savedCurProc;
  { cond: guard == 0 }
  idn := AllocNode(AN_IDENT); ASTIVal[idn] := gsym; ASTTk[idn] := Ord(tyInteger);
  zero := AllocNode(AN_INT_LIT); ASTIVal[zero] := 0; ASTTk[zero] := Ord(tyInteger);
  cond := AllocNode(AN_BINOP); ASTIVal[cond] := Ord(tkEq);
  ASTLeft[cond] := idn; ASTRight[cond] := zero; ASTTk[cond] := Ord(tyBoolean);
  { then-branch: guard := 1; <original init chain> }
  idn := AllocNode(AN_IDENT); ASTIVal[idn] := gsym; ASTTk[idn] := Ord(tyInteger);
  one := AllocNode(AN_INT_LIT); ASTIVal[one] := 1; ASTTk[one] := Ord(tyInteger);
  asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := one;
  ASTTk[asn] := Ord(tyInteger);
  seq1 := AllocNode(AN_SEQ); ASTLeft[seq1] := asn; ASTRight[seq1] := head;
  blk := AllocNode(AN_BLOCK); ASTLeft[blk] := seq1;
  pairN := AllocNode(AN_PAIR); ASTLeft[pairN] := blk; ASTRight[pairN] := -1;
  ifn := AllocNode(AN_IF); ASTLeft[ifn] := cond; ASTRight[ifn] := pairN;
  Result := ifn;
end;

{ A local declaration line: <type> name [= init] (, name [= init])* ;
  Each name is allocated (a global slot in a top-level main where CurProc<0, a
  stack local inside a function) so subsequent statements resolve it; returns an
  AN_BLOCK whose AN_SEQ chain holds the initialiser assignments (an empty block
  when there are no initialisers). Increment-1 scope: scalar declarators; array
  and per-declarator pointer-depth handling come later. }
function ParseCLocalDeclAST: Integer;
var baseTk, declTk, scalarTk: TTypeKind;
    head, tail, seq, asn, idn, initExpr, blk, idx: Integer;
    elemTkOrd, elemRec, arrLen, procSig: Integer;
    ptrDepth, ptrBaseTk, ptrBaseRec: Integer;
    declElemTk, declElemRec, declProcSig, declPtr, scalarRec: Integer;
    declPtrDepth, declBaseTk, declBaseRec: Integer;
    hadStar: Boolean;
    name: AnsiString;
    inode, idxLit, ei, nArrElems, brDepth: Integer;
    recBase, fldI, fTk, fieldNode, recArrInitCount: Integer;
    dimCount, dimVal, flatLen, di: Integer;
    arrElems: array[0..255] of Integer;
    dimSpan: array[0..MAX_ARR_DIMS-1] of Integer;
begin
  baseTk := ParseCDeclType;   { specifiers + first declarator's pointer suffix }
  { Capture the pointer element type/record now — ParseCExpr below must not
    clobber the CType* globals (it does not run ParseCDeclType). }
  elemTkOrd := CTypeElemTk;
  elemRec := CTypeElemRec;
  ptrDepth := CTypePtrDepth;
  ptrBaseTk := CTypePtrBaseTk;
  ptrBaseRec := CTypePtrBaseRec;
  procSig := CTypeProcSig;    { fn-pointer typedef signature, if any }
  if CTypeFnPtrName <> '' then
  begin
    { Inline function-pointer local `RET (*name)(params) [= init];` —
      ParseCDeclType consumed the whole declarator and captured the name + call
      signature. The name-reading loop below would Break (the name token is
      already consumed), so allocate the local here as an 8-byte callable
      pointer and parse the optional initializer. Mirrors the ParseCStructInto
      inline fn-ptr member branch. (Capture the name now: a cast inside the
      initializer expression re-runs ParseCDeclType and resets the global.) }
    name := CTypeFnPtrName;
    idx := CAllocDeclVar(name, tyPointer);
    Syms[idx].PtrElemTk := tyUnknown;
    Syms[idx].PtrElemRec := REC_NONE;
    SymPtrDepth[idx] := 1;
    SymPtrBaseTk[idx] := Ord(tyUnknown);
    SymPtrBaseRec[idx] := REC_NONE;
    if procSig >= 0 then SymProcSig[idx] := procSig;
    head := -1; tail := -1;
    if CurTok.Kind = tkAssign then
    begin
      Next;
      initExpr := ParseCExpr;
      idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(tyPointer);
      asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := initExpr;
      ASTTk[asn] := Ord(tyPointer);
      seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
      head := seq; tail := seq;
    end;
    if CurTok.Kind <> tkComma then
    begin
      Eat(tkSemicolon);
      blk := AllocNode(AN_BLOCK);
      if CLocalStaticDecl and (head <> -1) then
      begin
        seq := AllocNode(AN_SEQ);
        ASTLeft[seq] := CWrapStaticInitOnce(head); ASTRight[seq] := -1;
        ASTLeft[blk] := seq;
      end
      else
        ASTLeft[blk] := head;
      Result := blk;
      Exit;
    end;
    { `int (*fp)(int, char**), ret;` (tcc_run) — more declarators follow the
      inline fn-ptr. Fall into the multi-declarator loop below; the siblings'
      scalar base is the fn-ptr's RETURN type (the declaration's specifier
      base). head/tail keep any fn-ptr initializer already collected. }
    scalarTk := Procs[procSig].RetType;
    scalarRec := CTypeBaseRec;
    hadStar := False;
    Next;   { consume the ',' — the loop handles stars/name of each sibling }
    declPtr := 0;
    while CurTok.Kind = tkStar do begin Inc(declPtr); Next; end;
    if declPtr > 0 then
    begin
      declTk := tyPointer; declPtrDepth := declPtr;
      declBaseTk := Ord(scalarTk); declBaseRec := scalarRec;
      if declPtr = 1 then begin declElemTk := Ord(scalarTk); declElemRec := scalarRec; end
      else begin declElemTk := Ord(tyPointer); declElemRec := REC_NONE; end;
    end
    else
    begin
      declTk := scalarTk; declElemTk := Ord(tyUnknown); declElemRec := scalarRec;
      declPtrDepth := 0; declBaseTk := Ord(tyUnknown); declBaseRec := REC_NONE;
    end;
    declProcSig := -1;
  end
  else
  begin
  { Multi-declarator support `T *a, b, *c;`: the `*` binds to each declarator, not
    the base. ParseCDeclType folded the FIRST declarator's star into baseTk, so
    recover the pre-star scalar base; each later declarator gets its own stars.
    A pointer from a *literal* star (elemTk known) is redistributable; a pointer
    from a typedef (no star) is the whole type and applies to every sibling. }
  hadStar := (baseTk = tyPointer) and (CTypePtrDepth > 0);
  if hadStar then begin scalarTk := IntToTypeKind(ptrBaseTk); scalarRec := ptrBaseRec; end
  else begin scalarTk := baseTk; scalarRec := CTypeBaseRec; end;
  declTk := baseTk; declElemTk := elemTkOrd; declElemRec := elemRec; declProcSig := procSig;
  declPtrDepth := ptrDepth; declBaseTk := ptrBaseTk; declBaseRec := ptrBaseRec;
  head := -1; tail := -1;
  end;
  while True do
  begin
    if CurTok.Kind <> tkIdent then Break;
    name := CurTok.SVal; Next;
    if CurTok.Kind = tkLParen then
    begin
      { Block-scope function prototype `int f(params);` (C 6.7 — a declaration,
        no definition). The function lives at file scope; the local proto is a
        no-op, so skip the balanced parameter list and emit no code. }
      brDepth := 1; Next;
      while (brDepth > 0) and (CurTok.Kind <> tkEOF) do
      begin
        if CurTok.Kind = tkLParen then Inc(brDepth)
        else if CurTok.Kind = tkRParen then Dec(brDepth);
        Next;
      end;
      if CurTok.Kind = tkComma then begin Next; Continue; end;
      Break;
    end;
    if CurTok.Kind = tkLBrack then
    begin
      { fixed array  T name[N][M]...  — dimensions are constant expressions.
        Storage is flattened row-major for >=2 dimensions and tagged with
        SymArrNDims so chained indexing can rebuild the flat element index. An
        unsized 1-D `[]` (arrLen=-1) is sized from the initializer below. }
      dimCount := 0;
      flatLen := 1;
      while CurTok.Kind = tkLBrack do
      begin
        Next;
        if CurTok.Kind = tkRBrack then dimVal := -1
        else dimVal := CEvalConstExpr;
        Expect(tkRBrack, ']');
        if dimCount >= MAX_ARR_DIMS then Error('too many C array dimensions');
        dimSpan[dimCount] := dimVal;
        Inc(dimCount);
      end;
      if dimCount = 1 then
        arrLen := dimSpan[0]
      else
      begin
        flatLen := 1;
        for di := 0 to dimCount - 1 do
        begin
          if dimSpan[di] < 1 then dimSpan[di] := 1;
          flatLen := flatLen * dimSpan[di];
        end;
        arrLen := flatLen;
      end;
      { An array of structs needs the element record id so AllocArray sizes the
        slot by RecSize, not a default — `struct V a[N]; a[i].f` was using the
        wrong stride. }
      if declTk = tyRecord then LastTypeRecId := scalarRec;
      { Array brace-initializer for scalar/pointer element arrays: parse each
        element expression up front (so an unsized open-bracket array is sized
        from the count) and generate arr-index-k := ek assignments at the
        declaration point. Reuses the C expr lowering, so string-literal / addr /
        cast elements all materialise correctly (this is how lua's
        luaT_eventname char-pointer table gets real data instead of stack
        garbage). Record-element arrays (each element a nested brace group) and
        over-long lists fall back to the balanced-brace skip below. }
      nArrElems := 0;
      recArrInitCount := 0;
      if (CurTok.Kind = tkAssign) and (declTk = tyRecord) and
         (Tokens[TokPos].Kind = tkBegin) then
        recArrInitCount := CBraceTopLevelInitCountAt(TokPos);
      if (CurTok.Kind = tkAssign) and (declTk <> tyRecord) and
         (Tokens[TokPos].Kind = tkBegin) and (dimCount >= 2) and
         (declTk <> tyPointer) and TypeIsOrdinal(declTk) then
      begin
        Next; Next;   { consume the assign then the open brace }
        brDepth := 1;
        while (brDepth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then
          begin
            Inc(brDepth);
            Next;
          end
          else if CurTok.Kind = tkEnd then
          begin
            Dec(brDepth);
            Next;
          end
          else if CurTok.Kind = tkComma then
            Next
          else
          begin
            if nArrElems > 255 then Error('too many C array initializer elements');
            arrElems[nArrElems] := ParseCExpr;
            Inc(nArrElems);
          end;
        end;
      end
      else if (CurTok.Kind = tkAssign) and (declTk <> tyRecord) and
         (Tokens[TokPos].Kind = tkBegin) and (dimCount <= 1) then
      begin
        Next; Next;   { consume the assign then the open brace }
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          if nArrElems > 255 then begin nArrElems := -1; Break; end;
          arrElems[nArrElems] := ParseCExpr;
          Inc(nArrElems);
          if CurTok.Kind = tkComma then begin Next; Continue; end;
          Break;
        end;
        if nArrElems >= 0 then Expect(tkEnd, '}')
        else begin
          { oversize: finish the balanced-brace skip from wherever we stopped }
          brDepth := 1;
          while (brDepth > 0) and (CurTok.Kind <> tkEOF) do
          begin
            if CurTok.Kind = tkBegin then Inc(brDepth)
            else if CurTok.Kind = tkEnd then Dec(brDepth);
            Next;
          end;
          nArrElems := 0;
        end;
      end
      else if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkString) and
              (declTk <> tyRecord) and (declTk <> tyPointer) and
              (dimCount <= 1) and TypeIsOrdinal(declTk) then
      begin
        { Local `char buf[] = "literal"` (and int8/u8 element arrays): the global
          path already sizes+inits from a string, but the local path only handled
          `= {...}` braces, so a string-initialised block-scope array fell through
          to arrLen=1 with no data — sqlite3JoinType's block-scope
          `static const char zKeyText[]` read out of bounds, so every keyword join
          (LEFT/INNER/...) was "unknown join type". Expand the string (and any
          adjacent literals) into per-character element assignments + a NUL, the
          same arrElems path the brace initializer uses. }
        Next;   { consume '='; CurTok is now the string, i.e. Tokens[TokPos-1] }
        while (CurTok.Kind = tkString) do
        begin
          ei := 0;
          while ei < Tokens[TokPos - 1].SLen do
          begin
            if nArrElems > 255 then begin nArrElems := -1; Break; end;
            idxLit := AllocNode(AN_INT_LIT);
            ASTIVal[idxLit] := Ord(TokChars[Tokens[TokPos - 1].SOffset + ei]);
            ASTTk[idxLit] := Ord(tyChar);
            arrElems[nArrElems] := idxLit;
            Inc(nArrElems);
            Inc(ei);
          end;
          if nArrElems < 0 then Break;
          Next;
        end;
        if nArrElems < 0 then
          Error('local string-initialised array exceeds 256 bytes')
        else
        begin
          { NUL terminator so the array is a valid C string. }
          idxLit := AllocNode(AN_INT_LIT);
          ASTIVal[idxLit] := 0; ASTTk[idxLit] := Ord(tyChar);
          arrElems[nArrElems] := idxLit;
          Inc(nArrElems);
        end;
      end;
      if arrLen < 1 then
      begin
        if nArrElems > 0 then arrLen := nArrElems
        else if recArrInitCount > 0 then arrLen := recArrInitCount
        else arrLen := 1;
      end
      else if (dimCount <= 1) and (nArrElems > arrLen) then arrLen := nArrElems;
      if (dimCount <= 1) and (recArrInitCount > arrLen) then arrLen := recArrInitCount;
      idx := CAllocDeclArray(name, declTk, 0, arrLen - 1);
      if dimCount >= 2 then
      begin
        SymArrNDims[idx] := dimCount;
        for di := 0 to dimCount - 1 do
        begin
          SymArrDimLo[idx * MAX_ARR_DIMS + di] := 0;
          SymArrDimSpan[idx * MAX_ARR_DIMS + di] := dimSpan[di];
        end;
      end;
      if declTk = tyPointer then
      begin
        Syms[idx].PtrElemTk := IntToTypeKind(declElemTk);
        Syms[idx].PtrElemRec := declElemRec;
        SymPtrDepth[idx] := declPtrDepth;
        SymPtrBaseTk[idx] := declBaseTk;
        SymPtrBaseRec[idx] := declBaseRec;
      end;
      { C99 6.7.8p21: any brace initializer zero-fills the tail the list does
        not reach — zero the whole array before the element stores. }
      if (nArrElems > 0) or (recArrInitCount > 0) then
      begin
        seq := CMakeZeroLocal(idx, declTk);
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
      end;
      for ei := 0 to nArrElems - 1 do
      begin
        idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(declTk);
        idxLit := AllocNode(AN_INT_LIT); ASTIVal[idxLit] := ei; ASTTk[idxLit] := Ord(tyInteger);
        inode := AllocNode(AN_INDEX); ASTLeft[inode] := idn; ASTRight[inode] := idxLit;
        ASTTk[inode] := Ord(declTk);
        asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := inode; ASTRight[asn] := arrElems[ei];
        ASTTk[asn] := Ord(declTk);
        seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
      end;
      if (CurTok.Kind = tkAssign) and (declTk = tyRecord) and
         (Tokens[TokPos].Kind = tkBegin) and (scalarRec >= REC_UCLASS_BASE) then
      begin
        { Local array-of-record initializer — recursive brace-elision walker
          (chain mode): each element's fields (incl. nested subarrays / structs,
          00091-style) materialise, not just the one-level flat scalars. Zero
          the whole array first (C99 6.7.8p21), then splice the walker's stores. }
        Next;   { consume the assign; CurTok = the outer opening brace }
        seq := CMakeZeroLocal(idx, declTk);
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
        seq := CInitLocalAggregate(idx, Ord(tyRecord), scalarRec, arrLen, 1, arrLen, 1, True);
        if seq <> -1 then
        begin
          if head = -1 then head := seq else ASTRight[tail] := seq;
          while ASTRight[seq] <> -1 do seq := ASTRight[seq];
          tail := seq;
        end;
      end
      { Unconsumed initializer (record-element array, or non-brace): balanced skip. }
      if CurTok.Kind = tkAssign then
      begin
        Next;
        if CurTok.Kind = tkBegin then
        begin
          brDepth := 0;
          repeat
            if CurTok.Kind = tkBegin then Inc(brDepth)
            else if CurTok.Kind = tkEnd then Dec(brDepth);
            Next;
          until (brDepth = 0) or (CurTok.Kind = tkEOF);
        end
        else
          while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                (CurTok.Kind <> tkEOF) do Next;
      end;
    end
    else
    begin
      { A struct-by-value local needs its record id so field access resolves and
        AllocVar reserves RecSize bytes. }
      if declTk = tyRecord then LastTypeRecId := scalarRec;
      idx := CAllocDeclVar(name, declTk);
      if declTk = tyPointer then
      begin
        Syms[idx].PtrElemTk := IntToTypeKind(declElemTk);
        Syms[idx].PtrElemRec := declElemRec;
        SymPtrDepth[idx] := declPtrDepth;
        SymPtrBaseTk[idx] := declBaseTk;
        SymPtrBaseRec[idx] := declBaseRec;
        if declProcSig >= 0 then SymProcSig[idx] := declProcSig;  { fn-pointer var: callable }
      end;
      initExpr := -1;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        if CurTok.Kind = tkBegin then
        begin
          if (declTk = tyRecord) and (scalarRec >= REC_UCLASS_BASE) then
          begin
            { Non-array local record initializer — the recursive brace-elision
              walker (chain mode) handles nested/anonymous aggregates, elided
              flat lists, and `.field` designators. C99 6.7.8p21: zero the whole
              record first, then the walker's stores overwrite their slots. }
            seq := CMakeZeroLocal(idx, declTk);
            if head = -1 then head := seq else ASTRight[tail] := seq;
            tail := seq;
            seq := CInitLocalAggregate(idx, Ord(declTk), scalarRec, 1, 1, 1, 1, False);
            if seq <> -1 then
            begin
              if head = -1 then head := seq else ASTRight[tail] := seq;
              while ASTRight[seq] <> -1 do seq := ASTRight[seq];   { advance to chain tail }
              tail := seq;
            end;
            initExpr := -1;
          end
          else
          begin
            { Aggregate initializer `= { ... }` on unsupported local shapes
              (e.g. nested aggregate fields): balanced-brace skip so inner
              commas/braces don't end it early. }
            arrLen := 0;   { reuse as brace depth }
            repeat
              if CurTok.Kind = tkBegin then Inc(arrLen)
              else if CurTok.Kind = tkEnd then Dec(arrLen);
              Next;
            until (arrLen = 0) or (CurTok.Kind = tkEOF);
          end;
        end
        else
          initExpr := ParseCExpr;
      end;
      if initExpr >= 0 then
      begin
        idn := AllocNode(AN_IDENT); ASTIVal[idn] := idx; ASTTk[idn] := Ord(declTk);
        asn := AllocNode(AN_ASSIGN); ASTLeft[asn] := idn; ASTRight[asn] := initExpr;
        ASTTk[asn] := Ord(declTk);
        seq := AllocNode(AN_SEQ); ASTLeft[seq] := asn; ASTRight[seq] := -1;
        if head = -1 then head := seq else ASTRight[tail] := seq;
        tail := seq;
      end;
    end;
    if CurTok.Kind = tkComma then
    begin
      Next;
      { next declarator's own pointer level (`*c` in `T *a, b, *c`) }
      declPtr := 0;
      while CurTok.Kind = tkStar do begin Inc(declPtr); Next; end;
      if declPtr > 0 then
      begin
        declTk := tyPointer;
        declPtrDepth := declPtr;
        declBaseTk := Ord(scalarTk);
        declBaseRec := scalarRec;
        if declPtr = 1 then begin declElemTk := Ord(scalarTk); declElemRec := scalarRec; end
        else begin declElemTk := Ord(tyPointer); declElemRec := REC_NONE; end;
        declProcSig := -1;
      end
      else if hadStar then
      begin
        { sibling with no star, base had a redistributable star: plain scalar }
        declTk := scalarTk; declElemTk := Ord(tyUnknown); declElemRec := scalarRec;
        declPtrDepth := 0; declBaseTk := Ord(tyUnknown); declBaseRec := REC_NONE;
        declProcSig := -1;
      end
      else
      begin
        { base carries no redistributable star (plain/typedef): siblings get the
          same full base type + metadata }
        declTk := baseTk; declElemTk := elemTkOrd; declElemRec := elemRec;
        declPtrDepth := ptrDepth; declBaseTk := ptrBaseTk; declBaseRec := ptrBaseRec;
        declProcSig := procSig;
      end;
      Continue;
    end;
    Break;
  end;
  Eat(tkSemicolon);
  blk := AllocNode(AN_BLOCK);
  if CLocalStaticDecl and (head <> -1) then
  begin
    { static locals: initializers run once, not per call }
    seq := AllocNode(AN_SEQ);
    ASTLeft[seq] := CWrapStaticInitOnce(head); ASTRight[seq] := -1;
    ASTLeft[blk] := seq;
  end
  else
    ASTLeft[blk] := head;   { -1 = empty block, emits nothing }
  Result := blk;
end;

{ A full C expression INCLUDING the top-level comma operator `a, b` — yields an
  AN_COMMA (evaluate left for side effects, value is the right). Used where C
  allows a comma expression: if/while/for conditions. (Function arguments and
  initializer lists keep using ParseCExpr, which stops at a comma separator.) }
function ParseCCommaExpr: Integer;
var node: Integer;
begin
  Result := ParseCExpr;
  while CurTok.Kind = tkComma do
  begin
    Next;
    node := AllocNode(AN_COMMA);
    ASTLeft[node] := Result;
    ASTRight[node] := ParseCExpr;
    ASTTk[node] := ASTTk[ASTRight[node]];
    Result := node;
  end;
end;

function ParseCIfAST: Integer;
var cond, thenS, elseS, node, pair: Integer;
begin
  Next; { if }
  Expect(tkLParen, '(');
  cond := ParseCCommaExpr;
  Expect(tkRParen, ')');
  thenS := ParseCStatementAST;
  elseS := -1;
  if CurTok.Kind = tkElse then begin Next; elseS := ParseCStatementAST; end;
  node := AllocNode(AN_IF);
  ASTLeft[node] := cond;
  pair := AllocNode(AN_PAIR);
  ASTLeft[pair] := thenS;
  ASTRight[pair] := elseS;
  ASTRight[node] := pair;
  Result := node;
end;

function ParseCWhileAST: Integer;
var cond, body, node: Integer;
begin
  Next; { while }
  Expect(tkLParen, '(');
  cond := ParseCCommaExpr;
  Expect(tkRParen, ')');
  body := ParseCStatementAST;
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := cond;
  ASTRight[node] := body;
  Result := node;
end;

{ Build `(e == 0)` as a tyBoolean node — logical negation / `!e`. }
function CMakeIsZero(e: Integer): Integer;
var node, zero: Integer;
begin
  zero := AllocNode(AN_INT_LIT); ASTIVal[zero] := 0; ASTTk[zero] := Ord(tyInteger);
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(tkEq);
  ASTLeft[node] := e; ASTRight[node] := zero;
  ASTTk[node] := Ord(tyBoolean);
  Result := node;
end;

{ Append `stmt` as a new AN_SEQ node onto a chain; returns the new tail.
  `*head` is set on the first append. }
function CSeqAppend(stmt: Integer; var head, tail: Integer): Integer;
var seq: Integer;
begin
  seq := AllocNode(AN_SEQ); ASTLeft[seq] := stmt; ASTRight[seq] := -1;
  if head = -1 then head := seq else ASTRight[tail] := seq;
  tail := seq;
  Result := seq;
end;

{ `for (init; cond; post) body`.
  - No post: desugars to `init; while (cond) body` (continue->cond is correct).
  - With post: a `continue` must still run `post`, but the loop machinery's
    continue target is the while condition. So we desugar to a constant-true
    loop that runs `post` at the TOP (guarded by a first-iteration flag) before
    re-checking the condition:
        init; first = 1;
        while (1) { if (!first) post; first = 0; if (!cond) break; body; }
    A continue jumps to the while head, runs post, re-checks cond — exactly C
    semantics. An empty cond is constant-true. }
function ParseCForAST: Integer;
var initNode, cond, post, body, loop, whileBody, outer, trueCond: Integer;
    oHead, oTail, bHead, bTail, flagVar, flagSet, flagClr, ifPost, ifBrk, brk: Integer;
    idn1, idn2: Integer;
begin
  Next; { for }
  Expect(tkLParen, '(');

  initNode := -1;
  if CurTok.Kind = tkSemicolon then
    Next
  else if IsCTypeTok then
    initNode := ParseCLocalDeclAST
  else
  begin
    initNode := ParseCCommaStmt;
    Eat(tkSemicolon);
  end;

  if CurTok.Kind = tkSemicolon then
  begin
    cond := AllocNode(AN_INT_LIT); ASTIVal[cond] := 1; ASTTk[cond] := Ord(tyBoolean);
  end
  else
    cond := ParseCCommaExpr;
  Expect(tkSemicolon, ';');

  post := -1;
  if CurTok.Kind <> tkRParen then post := ParseCCommaStmt;
  Expect(tkRParen, ')');

  body := ParseCStatementAST;

  oHead := -1; oTail := -1;
  if initNode >= 0 then CSeqAppend(initNode, oHead, oTail);

  if post < 0 then
  begin
    { simple: while (cond) body }
    loop := AllocNode(AN_WHILE);
    ASTLeft[loop] := cond;
    ASTRight[loop] := body;
    CSeqAppend(loop, oHead, oTail);
  end
  else
  begin
    flagVar := AllocVar('', tyBoolean);

    { first = 1 }
    idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
    flagSet := AllocNode(AN_ASSIGN); ASTLeft[flagSet] := idn1;
    ASTRight[flagSet] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagSet]] := 1;
    ASTTk[ASTRight[flagSet]] := Ord(tyInteger); ASTTk[flagSet] := Ord(tyBoolean);
    CSeqAppend(flagSet, oHead, oTail);

    bHead := -1; bTail := -1;

    { if (!first) post  ->  if (first == 0) post }
    idn2 := AllocNode(AN_IDENT); ASTIVal[idn2] := flagVar; ASTTk[idn2] := Ord(tyBoolean);
    ifPost := AllocNode(AN_IF);
    ASTLeft[ifPost] := CMakeIsZero(idn2);
    ASTRight[ifPost] := AllocNode(AN_PAIR);
    ASTLeft[ASTRight[ifPost]] := post;
    ASTRight[ASTRight[ifPost]] := -1;
    CSeqAppend(ifPost, bHead, bTail);

    { first = 0 }
    idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
    flagClr := AllocNode(AN_ASSIGN); ASTLeft[flagClr] := idn1;
    ASTRight[flagClr] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagClr]] := 0;
    ASTTk[ASTRight[flagClr]] := Ord(tyInteger); ASTTk[flagClr] := Ord(tyBoolean);
    CSeqAppend(flagClr, bHead, bTail);

    { if (!cond) break }
    ifBrk := AllocNode(AN_IF);
    ASTLeft[ifBrk] := CMakeIsZero(cond);
    brk := AllocNode(AN_BREAK);
    ASTRight[ifBrk] := AllocNode(AN_PAIR);
    ASTLeft[ASTRight[ifBrk]] := brk;
    ASTRight[ASTRight[ifBrk]] := -1;
    CSeqAppend(ifBrk, bHead, bTail);

    { body }
    CSeqAppend(body, bHead, bTail);

    whileBody := AllocNode(AN_BLOCK); ASTLeft[whileBody] := bHead;
    trueCond := AllocNode(AN_INT_LIT); ASTIVal[trueCond] := 1; ASTTk[trueCond] := Ord(tyBoolean);
    loop := AllocNode(AN_WHILE);
    ASTLeft[loop] := trueCond;
    ASTRight[loop] := whileBody;
    CSeqAppend(loop, oHead, oTail);
  end;

  outer := AllocNode(AN_BLOCK);
  ASTLeft[outer] := oHead;
  Result := outer;
end;

{ `do body while (cond);` — body runs once, then repeats while cond. Desugared
  with a first-iteration flag to a constant-checked while so break/continue keep
  C semantics: `flag=1; while (flag || cond) { flag=0; body }`. A continue jumps
  to the while head, where flag is 0, so cond is re-checked (correct). }
function ParseCDoWhileAST: Integer;
var body, cond, flagVar, loop, whileBody, outer: Integer;
    oHead, oTail, bHead, bTail, flagSet, flagClr, orCond, idn1, idn2: Integer;
begin
  Next; { do }
  body := ParseCStatementAST;
  if CurTok.Kind = tkWhile then Next else Error('while expected after do');
  Expect(tkLParen, '(');
  cond := ParseCCommaExpr;   { C `expression`: do..while (++p, f); — tcc }
  Expect(tkRParen, ')');
  Eat(tkSemicolon);

  flagVar := AllocVar('', tyBoolean);
  oHead := -1; oTail := -1;

  idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
  flagSet := AllocNode(AN_ASSIGN); ASTLeft[flagSet] := idn1;
  ASTRight[flagSet] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagSet]] := 1;
  ASTTk[ASTRight[flagSet]] := Ord(tyInteger); ASTTk[flagSet] := Ord(tyBoolean);
  CSeqAppend(flagSet, oHead, oTail);

  bHead := -1; bTail := -1;
  idn2 := AllocNode(AN_IDENT); ASTIVal[idn2] := flagVar; ASTTk[idn2] := Ord(tyBoolean);
  flagClr := AllocNode(AN_ASSIGN); ASTLeft[flagClr] := idn2;
  ASTRight[flagClr] := AllocNode(AN_INT_LIT); ASTIVal[ASTRight[flagClr]] := 0;
  ASTTk[ASTRight[flagClr]] := Ord(tyInteger); ASTTk[flagClr] := Ord(tyBoolean);
  CSeqAppend(flagClr, bHead, bTail);
  CSeqAppend(body, bHead, bTail);
  whileBody := AllocNode(AN_BLOCK); ASTLeft[whileBody] := bHead;

  idn1 := AllocNode(AN_IDENT); ASTIVal[idn1] := flagVar; ASTTk[idn1] := Ord(tyBoolean);
  orCond := CMakeBinop(Ord(tkOr), idn1, cond);
  loop := AllocNode(AN_WHILE); ASTLeft[loop] := orCond; ASTRight[loop] := whileBody;
  CSeqAppend(loop, oHead, oTail);

  outer := AllocNode(AN_BLOCK); ASTLeft[outer] := oHead;
  Result := outer;
end;

{ A comma-separated expression sequence in statement position (expression
  statement, for-init, for-post): each expression runs for its side effects with
  the value discarded, so it lowers to a block of the expressions as statements.
  A single expression (no comma) returns just that node. }
function ParseCCommaStmt: Integer;
var head, tail, blk: Integer;
begin
  Result := ParseCExpr;
  if CurTok.Kind <> tkComma then Exit;
  head := -1; tail := -1;
  CSeqAppend(Result, head, tail);
  while CurTok.Kind = tkComma do
  begin
    Next;
    CSeqAppend(ParseCExpr, head, tail);
  end;
  blk := AllocNode(AN_BLOCK); ASTLeft[blk] := head;
  Result := blk;
end;

function ParseCStatementAST: Integer;
var node, exprNode, seq, seq2, blk: Integer;
begin
  Result := -1;
  if CurTok.Kind = tkEOF then Exit;

  { empty statement }
  if CurTok.Kind = tkSemicolon then
  begin
    Next;
    node := AllocNode(AN_BLOCK); ASTLeft[node] := -1;
    Result := node;
    Exit;
  end;

  { block-scope typedef declaration. C typedefs are compile-time only; register
    the alias and emit an empty statement node. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then
  begin
    ParseCTypedef;
    node := AllocNode(AN_BLOCK);
    ASTLeft[node] := -1;
    Result := node;
    Exit;
  end;

  { block-scope static declaration: parse as a normal local declaration but
    allocate the declared storage in BSS so pointers to it survive the block.
    This is needed for sqlite's `static sqlite3_vfs aVfs[]` registry table. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'static') then
  begin
    Next;
    if IsCTypeTok then
    begin
      CLocalStaticDecl := True;
      Result := ParseCLocalDeclAST;
      CLocalStaticDecl := False;
      Exit;
    end;
  end;

  { local variable declaration }
  if IsCTypeTok then
  begin
    CLocalStaticDecl := False;
    Result := ParseCLocalDeclAST;
    Exit;
  end;

  { return [expr]; — the expression is optional for void functions }
  if CurTok.Kind = tkExit then
  begin
    Next;
    node := AllocNode(AN_EXIT);
    if CurTok.Kind <> tkSemicolon then
      ASTLeft[node] := ParseCExpr
    else
      ASTLeft[node] := -1;
    Eat(tkSemicolon);
    Result := node;
    Exit;
  end;

  if CurTok.Kind = tkIf then begin Result := ParseCIfAST; Exit; end;
  if CurTok.Kind = tkWhile then begin Result := ParseCWhileAST; Exit; end;
  if CurTok.Kind = tkFor then begin Result := ParseCForAST; Exit; end;
  if CurTok.Kind = tkDo then begin Result := ParseCDoWhileAST; Exit; end;
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'switch') then
  begin Result := ParseCSwitchAST; Exit; end;

  { `case CONST:` / `default:` labels inside a switch body — emitted as marker
    nodes that the switch lowering turns into dispatch targets. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'case') then
  begin
    Next;
    node := AllocNode(AN_CASE);
    ASTIVal[node] := CEvalConstExpr;
    Expect(tkColon, ':');
    Result := node;
    Exit;
  end;
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'default') then
  begin
    Next;
    Expect(tkColon, ':');
    Result := AllocNode(AN_DEFAULT);
    Exit;
  end;

  { `goto label;` }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'goto') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('expected label name after goto');
    node := AllocNode(AN_GOTO);
    ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
    ASTSLen[node] := Tokens[TokPos - 1].SLen;
    Next;
    Eat(tkSemicolon);
    Result := node;
    Exit;
  end;

  { `label:` — a goto target as a statement (after case/default, which are above) }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkColon) then
  begin
    { Register the label name so AN_LABEL/AN_GOTO resolve it (C labels are not
      pre-declared; the table is reset per function in ParseCSubroutine). }
    if GotoLabelCount >= MAX_GOTO_LABELS then Error('too many labels');
    GotoLabelNOff[GotoLabelCount] := Tokens[TokPos - 1].SOffset;
    GotoLabelNLen[GotoLabelCount] := Tokens[TokPos - 1].SLen;
    GotoLabelCodePos[GotoLabelCount] := -1;
    Inc(GotoLabelCount);
    node := AllocNode(AN_LABEL);
    ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
    ASTSLen[node] := Tokens[TokPos - 1].SLen;
    Next; Next;    { consume ident and colon }
    { C 6.8.1: a label PREFIXES a statement — they are ONE statement. Returning
      the label alone detached the following statement from an enclosing
      unbraced if: tcc's `if (t0 == TOK_PPJOIN) bad_twosharp: tcc_error(...)`
      ran the error unconditionally. (A label directly before a closing brace
      stays bare — GCC-extension form.) }
    if (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) then
    begin
      { Parse the statement BEFORE allocating the seq nodes: the recursive
        parse grows the AST arrays, so an `ASTLeft[new] := ParseC...` store
        can land in a stale (reallocated-away) array. }
      exprNode := ParseCStatementAST();   { () — bare name would read Result }
      seq2 := AllocNode(AN_SEQ); ASTLeft[seq2] := exprNode; ASTRight[seq2] := -1;
      seq := AllocNode(AN_SEQ); ASTLeft[seq] := node; ASTRight[seq] := seq2;
      blk := AllocNode(AN_BLOCK); ASTLeft[blk] := seq;
      Result := blk;
      Exit;
    end;
    Result := node;
    Exit;
  end;

  if CurTok.Kind = tkBreak then
  begin
    Next; Eat(tkSemicolon);
    Result := AllocNode(AN_BREAK);
    Exit;
  end;
  if CurTok.Kind = tkContinue then
  begin
    Next; Eat(tkSemicolon);
    Result := AllocNode(AN_CONTINUE);
    Exit;
  end;

  { nested block }
  if CurTok.Kind = tkBegin then
  begin
    Result := ParseCBlockAST;
    Exit;
  end;

  { expression statement (assignment, call, ++/--, comma sequence) }
  exprNode := ParseCCommaStmt;
  Eat(tkSemicolon);
  Result := exprNode;
end;

function ParseCBlockAST: Integer;
var blockNode, seqNode, stmtNode, lastSeq, scopeMark, si, hh, hj: Integer;
begin
  Expect(tkBegin, '{');
  { C block scope: an inner `int v` SHADOWS an outer v (FindSym's hash chain
    is newest-first, so the inner decl wins while in scope) and DIES at the
    closing brace — implemented by blanking the names of locals declared
    inside the block on exit (below). tcc's struct_decl re-declares
    `int v = btype.ref->v` in a nested block; without scoping it clobbered
    the outer v and pushed a garbage symbol token. }
  scopeMark := SymCount;
  blockNode := AllocNode(AN_BLOCK);
  lastSeq := -1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    stmtNode := ParseCStatementAST;
    if stmtNode <> -1 then
    begin
      seqNode := AllocNode(AN_SEQ);
      ASTLeft[seqNode] := stmtNode;
      if lastSeq = -1 then
        ASTLeft[blockNode] := seqNode
      else
        ASTRight[lastSeq] := seqNode;
      lastSeq := seqNode;
    end;
  end;
  Expect(tkEnd, '}');
  { End of scope: unhook this block's locals from their hash chains so name
    lookup can't bind them anymore. AST nodes already hold sym INDICES, which
    stay valid (codegen, DWARF); block-scope statics are skGlobal (BSS) and
    survive. Splice, don't rename: renamed entries stayed in the chains and
    turned hot lookups into full-chain misses (libtcc 12s -> hang). The dead
    syms are near the chain head (just allocated), so the walk is short. }
  for si := SymCount - 1 downto scopeMark do
    if (Syms[si].Kind = skLocal) and (Syms[si].Name <> '') then
    begin
      hh := SymNameFoldHash(Syms[si].Name);
      if SymHashHead[hh] = si then
        SymHashHead[hh] := SymHashPrev[si]
      else
      begin
        hj := SymHashHead[hh];
        while (hj >= 0) and (SymHashPrev[hj] <> si) do hj := SymHashPrev[hj];
        if hj >= 0 then SymHashPrev[hj] := SymHashPrev[si];
      end;
    end;
  Result := blockNode;
end;

{ C `switch (sel) { ... case CONST: ... default: ... }`. The body is parsed like
  a brace block; `case`/`default` arrive as AN_CASE/AN_DEFAULT marker nodes in the
  statement sequence (fallthrough is implicit — bodies run on into the next).
  AN_SWITCH lowering (ir.inc) turns the markers into dispatch targets + a break
  scope. }
function ParseCSwitchAST: Integer;
var node, selNode, bodyNode, seqNode, stmtNode, lastSeq: Integer;
begin
  Next;                          { consume 'switch' }
  Expect(tkLParen, '(');
  selNode := ParseCExpr;
  Expect(tkRParen, ')');
  Expect(tkBegin, '{');
  bodyNode := AllocNode(AN_BLOCK);
  lastSeq := -1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    stmtNode := ParseCStatementAST;
    if stmtNode <> -1 then
    begin
      seqNode := AllocNode(AN_SEQ);
      ASTLeft[seqNode] := stmtNode;
      if lastSeq = -1 then ASTLeft[bodyNode] := seqNode
      else ASTRight[lastSeq] := seqNode;
      lastSeq := seqNode;
    end;
  end;
  Expect(tkEnd, '}');
  node := AllocNode(AN_SWITCH);
  ASTLeft[node] := selNode;
  ASTRight[node] := bodyNode;
  Result := node;
end;

{ True iff the brace initializer at CurTok (the open brace) holds ONLY a flat list
  of integer literals + commas — no nested braces, no identifiers/macros/strings.
  The per-field PendingInit materialiser walks fields positionally and stops at the
  first close brace; a nested union/struct init (lua Node/TValue, whose body opens
  with another brace) would desync the walk on the inner brace, record wrong field
  offsets, and end at the inner close brace — leaving the outer decl misparsed (a
  pre-main crash). So only a flat all-integer struct is materialised; anything
  richer zero-inits + balanced skips. Non-consuming (scans Tokens from the inner
  token). }
function CBraceFlatIntInitCountAt(openIdx: Integer): Integer;
var j, depth, ei, maxSeen: Integer; sawValue: Boolean;
begin
  { Returns the element COUNT of a flat integer brace init = max index + 1,
    honouring `[k] =` array designators (C 6.7.8) so `{5, [2]=2, 3}` counts as
    4, not 3. -1 = not a flat int init (nested aggregate / string / non-literal
    designator index). }
  Result := 0;
  depth := 1;
  sawValue := False;
  ei := 0; maxSeen := -1;
  j := openIdx + 1;
  while (depth > 0) and (j < TokCount) do
  begin
    case Tokens[j].Kind of
      tkBegin: begin Result := -1; Exit; end;   { nested aggregate -> not flat }
      tkLBrack:
        begin
          { `[<int>] =` element designator repositions the running index. Only a
            literal index is understood here (the scanner can't fold consts). }
          if (depth = 1) and (Tokens[j + 1].Kind = tkInteger) and
             (Tokens[j + 2].Kind = tkRBrack) then
          begin
            ei := Tokens[j + 1].IVal;
            Inc(j, 2);   { land on ']'; the loop's Inc(j) steps past it }
          end
          else begin Result := -1; Exit; end;
        end;
      tkAssign: ;   { designator '=' — skip }
      tkEnd:
        begin
          if (depth = 1) and sawValue and (ei > maxSeen) then maxSeen := ei;
          Dec(depth);
        end;
      tkComma:
        begin
          if depth = 1 then
          begin
            if sawValue then
            begin
              if ei > maxSeen then maxSeen := ei;
              Inc(ei);
            end;
            sawValue := False;
          end;
        end;
      tkInteger, tkMinus, tkPlus, tkStar, tkSlash, tkMod, tkShl, tkShr, tkAmp,
      tkXor, tkPipe, tkLParen, tkRParen, tkNot, tkIdent:
        { Allowed flat constant-expression tokens. An element may be a full
          integer constant expression — parens, shifts, bitwise ops, and
          identifiers that name enum/macro constants (e.g. lua's
          `luaP_opmodes[] = { opmode(...), ... }`, which expands to
          `(((0)<<7)|...|(iABC))`). The materializer folds each element with
          CEvalConstExpr, so anything it can fold is fine here; tkBegin (nested
          aggregate) and tkString (pointer-array) still bail to their own paths. }
        if depth = 1 then sawValue := True;
      tkString: begin Result := -1; Exit; end;     { string init -> pointer path }
    else
      begin Result := -1; Exit; end;
    end;
    Inc(j);
  end;
  if depth <> 0 then begin Result := -1; Exit; end;
  Result := maxSeen + 1;
end;

function CBraceIsFlatIntInit: Boolean;
begin
  Result := CBraceFlatIntInitCountAt(TokPos - 1) >= 0;
end;

function CBraceTopLevelInitCountAt(openIdx: Integer): Integer;
var j, depth: Integer; sawValue: Boolean;
begin
  Result := 0;
  depth := 1;
  sawValue := False;
  j := openIdx + 1;
  while (depth > 0) and (j < TokCount) do
  begin
    case Tokens[j].Kind of
      tkBegin:
        begin
          if depth = 1 then sawValue := True;
          Inc(depth);
        end;
      tkEnd:
        begin
          if depth = 1 then
          begin
            if sawValue then Inc(Result);
            Dec(depth);
          end
          else
            Dec(depth);
        end;
      tkComma:
        if depth = 1 then
        begin
          if sawValue then Inc(Result);
          sawValue := False;
        end;
    else
      if depth = 1 then sawValue := True;
    end;
    Inc(j);
  end;
  if depth <> 0 then Result := -1;
end;

function CConsumeCastProcInit(var procIdx: Integer): Boolean;
{ Consume a global aggregate initializer element of the form
  `(fn_pointer_type)function_name`. File-scope struct-array initializers use the
  lightweight PendingInit recorder rather than the expression parser, so this
  recognizes the cast wrapper and reuses the existing proc-address PendingInit
  kind used by bare function names. }
var openIdx, j, depth, procTok, afterTok: Integer;
begin
  Result := False;
  procIdx := -1;
  if CurTok.Kind <> tkLParen then Exit;

  openIdx := TokPos - 1;
  j := openIdx + 1;
  depth := 1;
  while (j < TokCount) and (depth > 0) do
  begin
    if Tokens[j].Kind = tkLParen then Inc(depth)
    else if Tokens[j].Kind = tkRParen then Dec(depth);
    Inc(j);
  end;
  if depth <> 0 then Exit;

  procTok := j;       { first token after the cast's closing ')' }
  afterTok := j + 1;
  if (procTok >= TokCount) or (Tokens[procTok].Kind <> tkIdent) then Exit;
  if (afterTok < TokCount) and not (Tokens[afterTok].Kind in [tkComma, tkEnd]) then Exit;

  procIdx := FindProc(GetTokenStr(procTok));
  if procIdx < 0 then Exit;

  TokPos := afterTok;
  Next;               { CurTok now points at the delimiter after the function name }
  Result := True;
end;

procedure CSkipCInitElement;
var depth: Integer;
begin
  depth := 0;
  while (CurTok.Kind <> tkEOF) do
  begin
    if (depth = 0) and ((CurTok.Kind = tkComma) or (CurTok.Kind = tkEnd)) then Exit;
    if CurTok.Kind = tkBegin then
      Inc(depth)
    else if CurTok.Kind = tkEnd then
    begin
      if depth = 0 then Exit;
      Dec(depth);
      Next;
      if depth = 0 then Exit;
      Continue;
    end;
    Next;
  end;
end;

{ ===== Recursive C aggregate-initializer walker (C99 6.7.8) =====
  Replaces the one-level global struct / struct-array init recorders with a
  recursive walk over the TARGET TYPE TREE with brace-elision semantics: an
  open brace descends into (and bounds) the subaggregate it sits on; a flat
  run of initializers keeps filling leaves left-to-right across nested
  subaggregates (c-testsuite 00050/00091/00205). Two modes share the walk:
    emit=False  COUNT mode at declaration time — touches no AST/symbols; used
                to size an unsized `T x[] = {...}` by the number of top-level
                elements consumed under elision (nine PT elements out of a
                63-scalar flat list, not 63).
    emit=True   EMIT mode at `main` compile time (the C analogue of
                CompilePendingGlobalInits): re-seeks the recorded token
                position and re-parses, emitting one assignment per leaf via
                the ordinary ParseCExpr + CompileAST path — so casts, enum
                consts, bare fn names, string literals and &globals all lower
                through the machinery function bodies already use.
  The current leaf's access path (array-index / field frames) lives in
  CInitPath*; each leaf rebuilds its target AST chain from the path, because
  AST nodes are transient (ASTNodeCount resets after every CompileAST).
  Positional advance skips fields that overlap the bytes just consumed, which
  covers unions AND promoted anonymous-union members (all at one offset)
  without needing a union flag; bitfields advance one by one (they share
  offsets by design). Globals are BSS-zeroed, so unreached tails need no
  explicit zero-fill. }
const
  MAX_CINIT_PATH  = 32;
  MAX_C_AGG_INITS = 512;
var
  CInitPathKind: array[0..MAX_CINIT_PATH-1] of Integer;  { 0 = array index, 1 = field }
  CInitPathVal:  array[0..MAX_CINIT_PATH-1] of Integer;  { flat elem index | UFld pool idx }
  CInitPathTk:   array[0..MAX_CINIT_PATH-1] of Integer;  { ASTTk for the frame's node }
  CInitPathDepth: Integer;
  CAggCurSym: Integer;                                   { target symbol in EMIT mode }
  { LOCAL emit-to-chain mode: instead of CompileAST-ing each leaf immediately
    (global path, run at main), append AN_SEQ(assign) nodes onto a chain the
    local declaration returns as part of its block AST — so a local aggregate
    initializer compiles in declaration order with the rest of the body. }
  CInitChainMode: Boolean;
  CInitChainHead, CInitChainTail: Integer;
  CAggInitCount: Integer;
  CAggInitSym: array[0..MAX_C_AGG_INITS-1] of Integer;
  CAggInitTok: array[0..MAX_C_AGG_INITS-1] of Integer;   { token index of the opening brace }
  CAggInitRec: array[0..MAX_C_AGG_INITS-1] of Integer;
  CAggInitLen: array[0..MAX_C_AGG_INITS-1] of Integer;   { array length (elements) }
  CAggInitIsArr: array[0..MAX_C_AGG_INITS-1] of Boolean;

procedure CInitWalkRecord(ci: Integer; braced, emit: Boolean); forward;
procedure CInitWalkArray(elemTkOrd, elemRec, symIdx, fldIdx, dimLevel, nDims,
                         count, baseFlat, elemsBelow: Integer;
                         braced, emit: Boolean; var consumed: Integer); forward;

procedure CInitPathPush(kind, val, tkOrd: Integer);
begin
  if CInitPathDepth >= MAX_CINIT_PATH then Error('C initializer nesting too deep');
  CInitPathKind[CInitPathDepth] := kind;
  CInitPathVal[CInitPathDepth]  := val;
  CInitPathTk[CInitPathDepth]   := tkOrd;
  Inc(CInitPathDepth);
end;

{ Byte size of a field, for the overlap-skip positional advance. }
function CInitFieldSize(fi: Integer): Integer;
var es: Integer;
begin
  if UFldBitWidth[fi] > 0 then
  begin
    Result := UFldBitBytes[fi];
    if Result < 1 then Result := 1;
    Exit;
  end;
  if UFldTk[fi] = Ord(tyRecord) then es := RecSize(UFldRec_[fi])
  else if UFldTk[fi] = Ord(tyPointer) then es := TARGET_PTR_SIZE
  else es := TypeSize(IntToTypeKind(UFldTk[fi]));
  if UFldIsArray[fi] then Result := es * UFldArrLen[fi] else Result := es;
end;

function CInitDimSpanAt(symIdx, fldIdx, level: Integer): Integer;
begin
  if fldIdx >= 0 then Result := UFldArrDimSpan[fldIdx * MAX_ARR_DIMS + level]
  else if symIdx >= 0 then Result := SymArrDimSpan[symIdx * MAX_ARR_DIMS + level]
  else Result := 1;
end;

{ Rebuild the leaf's assignment target from the path: IDENT wrapped by
  AN_INDEX (flat element index) / AN_FIELD (name span from the UFld pool)
  frames — the same node shapes body expressions produce, so the existing
  lowering resolves offsets/strides identically. }
function CInitBuildTarget: Integer;
var node, d, lit, n2: Integer;
begin
  node := AllocNode(AN_IDENT);
  ASTIVal[node] := CAggCurSym;
  ASTTk[node] := Ord(Syms[CAggCurSym].TypeKind);
  for d := 0 to CInitPathDepth - 1 do
  begin
    if CInitPathKind[d] = 0 then
    begin
      lit := AllocNode(AN_INT_LIT);
      ASTIVal[lit] := CInitPathVal[d];
      ASTTk[lit] := Ord(tyInteger);
      n2 := AllocNode(AN_INDEX);
      ASTLeft[n2] := node; ASTRight[n2] := lit;
      ASTTk[n2] := CInitPathTk[d];
    end
    else
    begin
      n2 := AllocNode(AN_FIELD);
      ASTLeft[n2] := node;
      ASTSOffset[n2] := UFldNOff[CInitPathVal[d]];
      ASTSLen[n2] := UFldNLen[CInitPathVal[d]];
      ASTTk[n2] := CInitPathTk[d];
    end;
    node := n2;
  end;
  Result := node;
end;

{ COUNT-mode scalar skip: to the next comma / close-brace at paren depth 0. }
procedure CInitSkipScalar;
var pd: Integer;
begin
  pd := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if (pd = 0) and (CurTok.Kind in [tkComma, tkEnd, tkSemicolon]) then Exit;
    if (CurTok.Kind = tkLParen) or (CurTok.Kind = tkLBrack) then Inc(pd)
    else if (CurTok.Kind = tkRParen) or (CurTok.Kind = tkRBrack) then Dec(pd);
    Next;
  end;
end;

{ Emit a completed leaf assignment: either compile it now (global path, at
  main) or append it to the local declaration's AST chain. In chain mode the
  AST nodes must persist, so ASTNodeCount is NOT reset. }
procedure CInitEmitAssign(asn: Integer);
var seq: Integer;
begin
  if CInitChainMode then
  begin
    seq := AllocNode(AN_SEQ);
    ASTLeft[seq] := asn; ASTRight[seq] := -1;
    if CInitChainHead = -1 then CInitChainHead := seq
    else ASTRight[CInitChainTail] := seq;
    CInitChainTail := seq;
  end
  else
  begin
    CompileAST(asn);
    ASTNodeCount := 0;
  end;
end;

{ One scalar leaf. The path already addresses it. }
procedure CInitLeaf(tkOrd: Integer; emit: Boolean);
var target, e, asn: Integer;
begin
  if CurTok.Kind = tkBegin then
  begin
    { braced scalar `{ expr }` (C99 6.7.8p11) }
    Next;
    CInitLeaf(tkOrd, emit);
    while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
    begin
      CSkipCInitElement;
      if not Eat(tkComma) then Break;
    end;
    Eat(tkEnd);
    Exit;
  end;
  if emit then
  begin
    target := CInitBuildTarget;
    e := ParseCExpr;
    asn := AllocNode(AN_ASSIGN);
    ASTLeft[asn] := target; ASTRight[asn] := e;
    ASTTk[asn] := tkOrd;
    CInitEmitAssign(asn);
  end
  else
    CInitSkipScalar;
end;

{ char-array member from a string literal (adjacent literals concatenate).
  Path already holds the member's field frame; the tail stays BSS-zero, so no
  explicit NUL store is needed. }
procedure CInitFillCharArray(elemTkOrd, capacity: Integer; emit: Boolean);
var ei, k, sOff, sLen, target, lit, asn: Integer;
begin
  ei := 0;
  while CurTok.Kind = tkString do
  begin
    sOff := Tokens[TokPos - 1].SOffset;
    sLen := Tokens[TokPos - 1].SLen;
    for k := 0 to sLen - 1 do
    begin
      if emit and ((capacity < 0) or (ei < capacity)) then
      begin
        CInitPathPush(0, ei, elemTkOrd);
        target := CInitBuildTarget;
        Dec(CInitPathDepth);
        lit := AllocNode(AN_INT_LIT);
        ASTIVal[lit] := Ord(TokChars[sOff + k]);
        ASTTk[lit] := elemTkOrd;
        asn := AllocNode(AN_ASSIGN);
        ASTLeft[asn] := target; ASTRight[asn] := lit;
        ASTTk[asn] := elemTkOrd;
        CInitEmitAssign(asn);
      end;
      Inc(ei);
    end;
    Next;
  end;
end;

{ One record member: descend aggregates (braced = bounded, unbraced = elided
  flat fill), else a scalar leaf. }
procedure CInitWalkMember(fi: Integer; emit: Boolean);
var ndims, span0, eb, cons, ci2: Integer;
begin
  if UFldIsArray[fi] and (UFldDynDepth[fi] = 0) then
  begin
    CInitPathPush(1, fi, UFldTk[fi]);
    if (CurTok.Kind = tkString) and (TypeSize(IntToTypeKind(UFldTk[fi])) = 1) then
      CInitFillCharArray(UFldTk[fi], UFldArrLen[fi], emit)
    else if (CurTok.Kind = tkBegin) and (Tokens[TokPos].Kind = tkString) and
            (TypeSize(IntToTypeKind(UFldTk[fi])) = 1) then
    begin
      Next;
      CInitFillCharArray(UFldTk[fi], UFldArrLen[fi], emit);
      while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
      begin
        CSkipCInitElement;
        if not Eat(tkComma) then Break;
      end;
      Eat(tkEnd);
    end
    else
    begin
      ndims := UFldArrNDims[fi];
      if ndims < 2 then
      begin
        ndims := 1;
        span0 := UFldArrLen[fi];
        eb := 1;
      end
      else
      begin
        span0 := UFldArrDimSpan[fi * MAX_ARR_DIMS + 0];
        if span0 < 1 then span0 := 1;
        eb := UFldArrLen[fi] div span0;
        if eb < 1 then eb := 1;
      end;
      cons := 0;
      if CurTok.Kind = tkBegin then
      begin
        Next;
        CInitWalkArray(UFldTk[fi], UFldRec_[fi], -1, fi, 0, ndims, span0, 0, eb,
                       True, emit, cons);
        Eat(tkEnd);
      end
      else
        CInitWalkArray(UFldTk[fi], UFldRec_[fi], -1, fi, 0, ndims, span0, 0, eb,
                       False, emit, cons);
    end;
    Dec(CInitPathDepth);
  end
  else if (UFldTk[fi] = Ord(tyRecord)) and (UFldRec_[fi] >= REC_UCLASS_BASE) and
          (UFldBitWidth[fi] = 0) then
  begin
    ci2 := UFldRec_[fi] - REC_UCLASS_BASE;
    CInitPathPush(1, fi, UFldTk[fi]);
    if CurTok.Kind = tkBegin then
    begin
      Next;
      CInitWalkRecord(ci2, True, emit);
      Eat(tkEnd);
    end
    else
      CInitWalkRecord(ci2, False, emit);
    Dec(CInitPathDepth);
  end
  else
  begin
    CInitPathPush(1, fi, UFldTk[fi]);
    CInitLeaf(UFldTk[fi], emit);
    Dec(CInitPathDepth);
  end;
end;

procedure CInitWalkRecord(ci: Integer; braced, emit: Boolean);
var base, n, fldI, fi, fEnd, di: Integer;
begin
  base := UClsFBase[ci];
  n := UClsFCount[ci];
  fldI := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkEnd then Break;
    if (not braced) and (CurTok.Kind = tkSemicolon) then Break;
    if braced and (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) then
    begin
      { `.name =` field designator repositions the cursor (C 6.7.8). }
      Next;
      di := FindUField(ci, CurTok.SVal);
      if di >= 0 then fldI := di - base;
      Next;
      if CurTok.Kind = tkAssign then Next;
    end;
    if fldI >= n then
    begin
      if braced then
      begin
        CSkipCInitElement;
        if not Eat(tkComma) then Break;
        Continue;
      end
      else Break;
    end;
    fi := base + fldI;
    CInitWalkMember(fi, emit);
    { positional advance: skip union / promoted-anonymous-union siblings that
      overlap the bytes just consumed; bitfields advance one by one. }
    if UFldBitWidth[fi] > 0 then
      Inc(fldI)
    else
    begin
      fEnd := UFldOff_[fi] + CInitFieldSize(fi);
      Inc(fldI);
      while (fldI < n) and (UFldOff_[base + fldI] < fEnd) and
            (UFldBitWidth[base + fldI] = 0) do
        Inc(fldI);
    end;
    if CurTok.Kind = tkComma then
    begin
      { unbraced (elided) and full: leave the comma for the parent walker }
      if (not braced) and (fldI >= n) then Break;
      Next;
    end
    else Break;
  end;
end;

procedure CInitWalkArray(elemTkOrd, elemRec, symIdx, fldIdx, dimLevel, nDims,
                         count, baseFlat, elemsBelow: Integer;
                         braced, emit: Boolean; var consumed: Integer);
var i, spanN, ebN, subCons: Integer;
begin
  i := 0;
  consumed := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkEnd then Break;
    if (not braced) and (CurTok.Kind = tkSemicolon) then Break;
    if braced and (CurTok.Kind = tkLBrack) then
    begin
      { `[k] =` element designator repositions the index (C 6.7.8). }
      Next;
      i := CEvalConstExpr;
      Expect(tkRBrack, ']');
      if CurTok.Kind = tkAssign then Next;
      if i < 0 then i := 0;
    end;
    if (count >= 0) and (i >= count) then
    begin
      if braced then
      begin
        CSkipCInitElement;
        if not Eat(tkComma) then Break;
        Continue;
      end
      else Break;
    end;
    if dimLevel < nDims - 1 then
    begin
      spanN := CInitDimSpanAt(symIdx, fldIdx, dimLevel + 1);
      if spanN < 1 then spanN := 1;
      ebN := elemsBelow div spanN;
      if ebN < 1 then ebN := 1;
      if CurTok.Kind = tkBegin then
      begin
        Next;
        CInitWalkArray(elemTkOrd, elemRec, symIdx, fldIdx, dimLevel + 1, nDims,
                       spanN, baseFlat + i * elemsBelow, ebN, True, emit, subCons);
        Eat(tkEnd);
      end
      else
        CInitWalkArray(elemTkOrd, elemRec, symIdx, fldIdx, dimLevel + 1, nDims,
                       spanN, baseFlat + i * elemsBelow, ebN, False, emit, subCons);
    end
    else if (elemTkOrd = Ord(tyRecord)) and (elemRec >= REC_UCLASS_BASE) then
    begin
      CInitPathPush(0, baseFlat + i, elemTkOrd);
      if CurTok.Kind = tkBegin then
      begin
        Next;
        CInitWalkRecord(elemRec - REC_UCLASS_BASE, True, emit);
        Eat(tkEnd);
      end
      else
        CInitWalkRecord(elemRec - REC_UCLASS_BASE, False, emit);
      Dec(CInitPathDepth);
    end
    else
    begin
      CInitPathPush(0, baseFlat + i, elemTkOrd);
      CInitLeaf(elemTkOrd, emit);
      Dec(CInitPathDepth);
    end;
    Inc(i);
    if i > consumed then consumed := i;
    if CurTok.Kind = tkComma then
    begin
      if (not braced) and (count >= 0) and (i >= count) then Break;
      Next;
    end
    else Break;
  end;
end;

{ COUNT mode over a record-array initializer: how many top-level elements the
  list holds under brace elision. openIdx = token index of the opening brace.
  Restores the parse position. }
function CInitCountRecordArrayAt(openIdx, recId: Integer): Integer;
var savedIdx, cons: Integer;
begin
  savedIdx := TokPos - 1;
  TokPos := openIdx; Next;   { CurTok = the opening brace }
  Next;                      { first token inside }
  CInitPathDepth := 0;
  cons := 0;
  CInitWalkArray(Ord(tyRecord), recId, -1, -1, 0, 1, -1, 0, 1, True, False, cons);
  Result := cons;
  TokPos := savedIdx; Next;
end;

{ EMIT mode: run every deferred aggregate initializer, at the start of `main`
  (called right after CompilePendingGlobalInits). Restores the parse position. }
procedure CEmitDeferredCAggInits;
var i, savedIdx, cons: Integer;
begin
  if CAggInitCount = 0 then Exit;
  savedIdx := TokPos - 1;
  for i := 0 to CAggInitCount - 1 do
  begin
    TokPos := CAggInitTok[i]; Next;   { CurTok = the opening brace }
    Next;                             { first token inside }
    CAggCurSym := CAggInitSym[i];
    CInitPathDepth := 0;
    cons := 0;
    if CAggInitIsArr[i] then
      CInitWalkArray(Ord(Syms[CAggInitSym[i]].TypeKind), CAggInitRec[i],
                     CAggInitSym[i], -1, 0, 1, CAggInitLen[i], 0, 1,
                     True, True, cons)
    else
      CInitWalkRecord(CAggInitRec[i] - REC_UCLASS_BASE, True, True);
  end;
  TokPos := savedIdx; Next;
end;

{ LOCAL aggregate initializer via the recursive brace-elision walker, built
  into an AST chain the caller splices into the declaration's block (so it
  runs in declaration order). CurTok must be at the opening brace; on return
  it is just past the matching close. Returns the head AN_SEQ (or -1). isArr =
  the local is an array (walk elements); else walk record fields. elemRecId /
  elemTkOrd describe the array element (or the record id when not isArr).
  nDims/dim0/elemsBelow give the array's shape (1 dim => dim0 = length). }
function CInitLocalAggregate(symIdx, elemTkOrd, elemRecId, arrLen,
                             nDims, dim0, elemsBelow: Integer;
                             isArr: Boolean): Integer;
var savedMode, savedHead, savedTail, savedDepth, cons: Integer;
begin
  savedMode := Ord(CInitChainMode);
  savedHead := CInitChainHead; savedTail := CInitChainTail;
  savedDepth := CInitPathDepth;
  CInitChainMode := True;
  CInitChainHead := -1; CInitChainTail := -1;
  CAggCurSym := symIdx;
  CInitPathDepth := 0;
  cons := 0;
  Next;   { consume the opening brace; CurTok = first token inside }
  if isArr then
    CInitWalkArray(elemTkOrd, elemRecId, symIdx, -1, 0, nDims, dim0, 0,
                   elemsBelow, True, True, cons)
  else
    CInitWalkRecord(elemRecId - REC_UCLASS_BASE, True, True);
  Eat(tkEnd);
  Result := CInitChainHead;
  CInitChainMode := savedMode <> 0;
  CInitChainHead := savedHead; CInitChainTail := savedTail;
  CInitPathDepth := savedDepth;
end;

{ A top-level global variable definition: <type> name (, name)* ;
  Allocated as zero-initialised BSS (CurProc<0 => skGlobal). Increment-1 scope:
  the slot is reserved and any initialiser is skipped (C zero-inits globals; a
  non-zero constant/runtime initialiser is a follow-up). Re-running across the
  two driver passes is idempotent — a name already present is not re-allocated. }
procedure ParseCGlobalVarDecl;
var baseTk: TTypeKind; name: AnsiString; depth, idx, recBase, fldI, fOff, fTk, fSz: Integer;
    recId, initSymIdx, procIdx, initOff, di: Integer; wasArr: Boolean; initV: Int64;
    negFloat: Boolean; signMask: Int64; dvv: Double;
    arrLen, dimCount, nArrElems, flatInitCount, ei, idx2: Integer;
    initStr: AnsiString;
    arrOffs, arrLens, arrKind, arrSym: array[0..255] of Integer;
begin
  baseTk := ParseCDeclType;
  recId := CTypeBaseRec;
  { Inline function-pointer (array) global `ret (*name[N])(params) [= {..}];`
    (sqlite's sqlite3BuiltinExtensions[]). ParseCDeclType already consumed the
    whole declarator — the name into CTypeFnPtrName and any `[..]` into
    CTypeFnPtrArrLen — so the name-reading loop below would Break on the `=`/`;`
    and never register the global, leaving every `name[i]` reference folding to a
    bare 0. Register it here (array of callable pointers when bracketed, else a
    scalar callable pointer) and materialise the brace initializer as
    per-element proc-address PendingInits. }
  if (((CTypeFnPtrName <> '') or (CTypeProcSig >= 0)) and (baseTk = tyPointer)) and
     ((CTypeFnPtrName <> '') or (CurTok.Kind = tkIdent)) then
  begin
    { Guard on baseTk = tyPointer: a real inline fn-ptr declarator collapses to a
      pointer, whereas a struct/union global whose LAST member is a fn pointer
      (`struct { void (*f)(void); } g;`) leaves CTypeFnPtrName set as leftover but
      yields baseTk = tyRecord — that must fall through to the normal var loop.
      Also handles a fn-pointer TYPEDEF global `fty gp = &z;` (CTypeProcSig set
      but no inline CTypeFnPtrName): the name is the next token, and the shared
      body below registers it callable (SymProcSig) and binds the init address. }
    if CTypeFnPtrName <> '' then
      name := CTypeFnPtrName
    else
    begin name := CurTok.SVal; Next; end;
    procIdx := CTypeProcSig;             { the fn-ptr call signature }
    wasArr := (CTypeFnPtrArrLen >= -1);
    nArrElems := 0;
    if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkBegin) then
    begin
      Next; Next;                        { consume assign and opening brace }
      while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
      begin
        if nArrElems > 255 then begin nArrElems := -1; Break; end;
        if (CurTok.Kind = tkIdent) and (FindProc(CurTok.SVal) >= 0) then
        begin
          arrKind[nArrElems] := 3;       { proc address }
          arrSym[nArrElems] := FindProc(CurTok.SVal);
          Next;
        end
        else if CConsumeCastProcInit(idx) then
        begin
          arrKind[nArrElems] := 3;       { (cast)proc — same proc-address form }
          arrSym[nArrElems] := idx;
        end
        else if CurTok.Kind = tkIdent then
        begin
          { NULL or another resolvable global pointer; otherwise a null slot. }
          idx := FindSym(CurTok.SVal);
          if (idx >= 0) and (CurTok.SVal <> 'NULL') then
          begin arrKind[nArrElems] := 2; arrSym[nArrElems] := idx; end
          else begin arrKind[nArrElems] := 1; arrSym[nArrElems] := 0; end;
          Next;
        end
        else if CurTok.Kind = tkInteger then
        begin
          arrKind[nArrElems] := 1; arrSym[nArrElems] := CurTok.IVal; Next;
        end
        else
        begin
          arrKind[nArrElems] := 1; arrSym[nArrElems] := 0;
          CSkipCInitElement;
        end;
        Inc(nArrElems);
        if CurTok.Kind = tkComma then begin Next; Continue; end;
        Break;
      end;
      if nArrElems >= 0 then Eat(tkEnd)
      else
      begin
        depth := 1;
        while (depth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then Inc(depth)
          else if CurTok.Kind = tkEnd then Dec(depth);
          Next;
        end;
        nArrElems := 0;
      end;
    end
    else if CurTok.Kind = tkAssign then
    begin
      { scalar initializer `= expr;` — record a single proc address if it is a
        (optionally address-of'd) function name, else skip to the terminator
        (zero default). `&func` == `func` for a function pointer, so a global
        `int (*f)(int) = &fred;` must bind the address like the bare form (else
        the pointer stayed 0 and calling it SIGSEGV'd). }
      Next;
      if CurTok.Kind = tkAmp then Next;   { optional `&` before the function name }
      if (CurTok.Kind = tkIdent) and (FindProc(CurTok.SVal) >= 0) then
      begin
        arrKind[0] := 3; arrSym[0] := FindProc(CurTok.SVal); nArrElems := 1; Next;
      end
      else
        while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    end;
    arrLen := CTypeFnPtrArrLen;
    if wasArr then
    begin
      if arrLen < 1 then
      begin
        if nArrElems > 0 then arrLen := nArrElems else arrLen := 1;
      end
      else if nArrElems > arrLen then arrLen := nArrElems;
    end;
    idx := FindSym(name);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then idx := -1;
    if idx < 0 then
    begin
      if wasArr then idx := AllocArray(name, tyPointer, 0, arrLen - 1)
      else idx := AllocVar(name, tyPointer);
    end;
    if idx >= 0 then
    begin
      { An ARRAY of callable pointers carries its ELEMENT signature in
        SymElemProcSig (the `arr[i](args)` channel) — NOT SymProcSig, which would
        mark the array variable itself as a proc value and make codegen resolve
        `arr` to a code address (corrupt indexing). A SCALAR fn pointer is itself
        callable, so it takes SymProcSig plus the scalar pointee metadata. }
      if wasArr then
      begin
        if procIdx >= 0 then SymElemProcSig[idx] := procIdx;
      end
      else
      begin
        if procIdx >= 0 then SymProcSig[idx] := procIdx;
        Syms[idx].PtrElemTk := tyUnknown;
        Syms[idx].PtrElemRec := REC_NONE;
        SymPtrDepth[idx] := 1;
      end;
    end;
    for ei := 0 to nArrElems - 1 do
    begin
      if (idx >= 0) and (PendingInitCount < MAX_PENDING_INITS) then
      begin
        PendingInitSym[PendingInitCount]  := idx;
        if wasArr then PendingInitElem[PendingInitCount] := ei
        else PendingInitElem[PendingInitCount] := -1;
        PendingInitFLen[PendingInitCount] := 0;
        PendingInitTk[PendingInitCount]   := Ord(tyPointer);
        if arrKind[ei] = 3 then
        begin
          PendingInitFOff[PendingInitCount] := -1;
          PendingInitKind[PendingInitCount] := 2;          { proc address -> AN_PROCADDR }
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end
        else if arrKind[ei] = 2 then
        begin
          PendingInitFOff[PendingInitCount] := -4;          { address of named global }
          PendingInitKind[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end
        else
        begin
          PendingInitFOff[PendingInitCount] := -1;          { NULL / integer literal }
          PendingInitKind[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end;
        Inc(PendingInitCount);
      end;
    end;
    Eat(tkSemicolon);
    Exit;
  end;
  while True do
  begin
    { A subsequent declarator carries its OWN pointer stars: `T *a, *b, *c`.
      ParseCDeclType consumed the base + the first declarator's stars, so the
      first iteration sees the bare name; later iterations (after the comma) land
      on the `*` of `*b`. Consume those stars so `*b` is read as a declarator
      rather than seen as a non-ident and dropped — a dropped global then folds
      every later use to a bare 0, and assigning to it (`loop_scope = NULL`) hits
      IRLowerAddress(int-literal) -> "Unsupported linear node" (tcc tccgen.c).
      The stars keep the base pointer depth (uniform declarators, the common case
      and all of tcc's `Sym *a, *b`). }
    while CurTok.Kind = tkStar do Next;
    if CurTok.Kind <> tkIdent then Break;
    name := CurTok.SVal; Next;
    { Global array dimension(s). Pointer arrays with string-literal initializers
      are materialized below; other arrays still mostly serve as parse/layout
      anchors for now. }
    wasArr := False;
    arrLen := 0;
    dimCount := 0;
    while CurTok.Kind = tkLBrack do
    begin
      wasArr := True;
      Inc(dimCount);
      Next;
      if dimCount = 1 then
      begin
        if CurTok.Kind = tkRBrack then arrLen := -1
        else arrLen := CEvalConstExpr;
        Expect(tkRBrack, ']');
      end
      else
      begin
        depth := 1;
        while (depth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLBrack then Inc(depth)
          else if CurTok.Kind = tkRBrack then Dec(depth);
          Next;
        end;
      end;
    end;
    nArrElems := 0;
    if (CurTok.Kind = tkAssign) and wasArr and (baseTk = tyPointer) and
       (Tokens[TokPos].Kind = tkBegin) then
    begin
      Next; Next;  { consume assignment and opening initializer token }
      while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
      begin
        if nArrElems > 255 then begin nArrElems := -1; Break; end;
        if CurTok.Kind = tkString then
        begin
          { string-literal element (kind 0): record the token span }
          arrKind[nArrElems] := 0;
          arrOffs[nArrElems] := Tokens[TokPos - 1].SOffset;
          arrLens[nArrElems] := Tokens[TokPos - 1].SLen;
          Next;
          while CurTok.Kind = tkString do
          begin
            arrLens[nArrElems] := arrLens[nArrElems] + Tokens[TokPos - 1].SLen;
            Next;
          end;
        end
        else if CurTok.Kind = tkIdent then
        begin
          { identifier element: `NULL` -> null pointer (kind 1); otherwise the
            name of a global (a `char[]` array decaying to `char*`, or another
            pointer) -> store its address (kind 2). A name we cannot resolve
            falls back to the whole-array skip path. }
          if CurTok.SVal = 'NULL' then
          begin
            arrKind[nArrElems] := 1;
            arrSym[nArrElems] := 0;
          end
          else
          begin
            arrSym[nArrElems] := FindSym(CurTok.SVal);
            if arrSym[nArrElems] < 0 then begin nArrElems := -1; Break; end;
            arrKind[nArrElems] := 2;
          end;
          Next;
        end
        else if CurTok.Kind = tkInteger then
        begin
          { integer-literal element (kind 1): typically `0`/NULL terminator in a
            `char *[]` table. Store the literal value as the pointer bits. }
          arrKind[nArrElems] := 1;
          arrSym[nArrElems] := CurTok.IVal;
          Next;
        end
        else
        begin
          nArrElems := -1;
          Break;
        end;
        Inc(nArrElems);
        if CurTok.Kind = tkComma then begin Next; Continue; end;
        Break;
      end;
      if nArrElems >= 0 then
        Expect(tkEnd, '}')
      else
      begin
        depth := 1;
        while (depth > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkBegin then Inc(depth)
          else if CurTok.Kind = tkEnd then Dec(depth);
          Next;
        end;
        nArrElems := 0;
      end;
    end;
    if wasArr then
    begin
      if arrLen < 1 then
      begin
        if nArrElems > 0 then arrLen := nArrElems
        else if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkBegin) and
                (baseTk <> tyRecord) and (baseTk <> tyPointer) and
                TypeIsOrdinal(baseTk) then
        begin
          flatInitCount := CBraceFlatIntInitCountAt(TokPos);
          if flatInitCount > 0 then arrLen := flatInitCount else arrLen := 1;
        end
        else if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkBegin) and
                (baseTk = tyRecord) then
        begin
          { unsized `T x[] = {...}`: size by elements consumed under brace
            elision (a flat 63-scalar list of 7-leaf structs = 9 elements),
            not by top-level commas. }
          if recId >= REC_UCLASS_BASE then
            flatInitCount := CInitCountRecordArrayAt(TokPos, recId)
          else
            flatInitCount := CBraceTopLevelInitCountAt(TokPos);
          if flatInitCount > 0 then arrLen := flatInitCount else arrLen := 1;
        end
        else if (CurTok.Kind = tkAssign) and (Tokens[TokPos].Kind = tkString) and
                (baseTk <> tyRecord) and (baseTk <> tyPointer) and
                TypeIsOrdinal(baseTk) then
        begin
          idx2 := TokPos;
          arrLen := Tokens[idx2].SLen;
          Inc(idx2);
          while Tokens[idx2].Kind = tkString do
          begin
            arrLen := arrLen + Tokens[idx2].SLen;
            Inc(idx2);
          end;
          Inc(arrLen);
        end
        else arrLen := 1;
      end
      else if nArrElems > arrLen then arrLen := nArrElems;
    end;
    { A struct-typed global needs its record id recorded (AllocVar reads the
      global LastTypeRecId for tyRecord) so field access `gg.f` resolves the
      offset — without this the field always landed at offset 0. }
    if baseTk = tyRecord then LastTypeRecId := recId;
    idx := FindSym(name);
    { A C global must not bind to a Pascal predefined const that only matches
      case-insensitively (e.g. C `stderr` vs the builtin `StdErr` = fd 2):
      assigning its initializer would hit "cannot assign to constant", and C
      names are case-sensitive anyway. Shadow it with a fresh exact-case global
      (the exact-case FindSym pass then resolves uses to the variable). }
    if (idx >= 0) and (Syms[idx].Kind = skConst) then idx := -1;
    if idx < 0 then
    begin
      if wasArr then
        idx := AllocArray(name, baseTk, 0, arrLen - 1)
      else
        idx := AllocVar(name, baseTk);
    end;
    if (idx >= 0) and (baseTk = tyPointer) then
    begin
      Syms[idx].PtrElemTk := IntToTypeKind(CTypeElemTk);
      Syms[idx].PtrElemRec := CTypeElemRec;
      SymPtrDepth[idx] := CTypePtrDepth;
      SymPtrBaseTk[idx] := CTypePtrBaseTk;
      SymPtrBaseRec[idx] := CTypePtrBaseRec;
    end;
    for ei := 0 to nArrElems - 1 do
    begin
      if PendingInitCount < MAX_PENDING_INITS then
      begin
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := ei;
        PendingInitTk[PendingInitCount]   := Ord(tyPointer);
        PendingInitKind[PendingInitCount] := 0;
        if arrKind[ei] = 0 then
        begin
          PendingInitFOff[PendingInitCount] := -3;  { string literal span }
          PendingInitFLen[PendingInitCount] := arrLens[ei];
          PendingInitVal[PendingInitCount]  := arrOffs[ei];
        end
        else if arrKind[ei] = 2 then
        begin
          PendingInitFOff[PendingInitCount] := -4;  { address of named global }
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end
        else
        begin
          PendingInitFOff[PendingInitCount] := -1;  { NULL / integer literal }
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := arrSym[ei];
        end;
        Inc(PendingInitCount);
      end;
    end;
    if CurTok.Kind = tkAssign then
    begin
      Next;
      { Materialise a non-array struct/union global brace-initializer as per-field
        PendingInit writes (constant values only) — so e.g. lstrlib's nativeendian
        union and small struct globals read correctly at runtime instead of zero.
        Arrays and non-constant inits fall through to the skip path. The PendingInit
        emission resolves a field by NAME, so FOff/FLen carry the field's NAME
        reference (UFldNOff/UFldNLen), which name-resolves to the correct byte
        offset for every field (unions: all at offset 0; structs: each distinct). }
      recBase := -1;
      if (recId >= REC_UCLASS_BASE) and UClsIsRecord[recId - REC_UCLASS_BASE] then
        recBase := UClsFBase[recId - REC_UCLASS_BASE];
      if (CurTok.Kind = tkBegin) and wasArr and (baseTk <> tyRecord) and
         (baseTk <> tyPointer) and TypeIsOrdinal(baseTk) and
         (idx >= 0) and CBraceIsFlatIntInit then
      begin
        Next;   { consume the opening brace }
        ei := 0;
        while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
        begin
          { `[k] =` array element designator repositions the index (C 6.7.8);
            skipped slots stay 0 (globals are BSS-zeroed). }
          if CurTok.Kind = tkLBrack then
          begin
            Next;                                     { '[' }
            ei := CEvalConstExpr;
            Expect(tkRBrack, ']');
            if CurTok.Kind = tkAssign then Next;      { '=' }
          end;
          initV := CEvalConstExpr;
          if (ei >= 0) and (ei < arrLen) and (PendingInitCount < MAX_PENDING_INITS) then
          begin
            PendingInitSym[PendingInitCount]  := idx;
            PendingInitElem[PendingInitCount] := ei;
            PendingInitFOff[PendingInitCount] := -1;
            PendingInitFLen[PendingInitCount] := 0;
            PendingInitVal[PendingInitCount]  := initV;
            PendingInitTk[PendingInitCount]   := Ord(baseTk);
            Inc(PendingInitCount);
          end;
          Inc(ei);
          Eat(tkComma);
        end;
        Eat(tkEnd);
      end
      else if (CurTok.Kind = tkBegin) and wasArr and (baseTk = tyRecord) and
         (idx >= 0) and (recBase >= 0) and
         (UClsFCount[recId - REC_UCLASS_BASE] >= 1) then
      begin
        { Array-of-struct global initializer: defer to the recursive
          brace-elision walker, replayed at `main` compile time by
          CEmitDeferredCAggInits — handles nested braces, elided flat lists,
          designators, anonymous unions and nested subarrays. }
        if CAggInitCount < MAX_C_AGG_INITS then
        begin
          CAggInitSym[CAggInitCount] := idx;
          CAggInitTok[CAggInitCount] := TokPos - 1;
          CAggInitRec[CAggInitCount] := recId;
          CAggInitLen[CAggInitCount] := arrLen;
          CAggInitIsArr[CAggInitCount] := True;
          Inc(CAggInitCount);
        end;
        SkipBraceBlock;
      end
      else if (CurTok.Kind = tkBegin) and (baseTk = tyRecord) and (not wasArr) and
         (idx >= 0) and (recBase >= 0) and
         (UClsFCount[recId - REC_UCLASS_BASE] >= 1) then
      begin
        { Non-array struct/union global initializer: same deferred recursive
          walker (see above). }
        if CAggInitCount < MAX_C_AGG_INITS then
        begin
          CAggInitSym[CAggInitCount] := idx;
          CAggInitTok[CAggInitCount] := TokPos - 1;
          CAggInitRec[CAggInitCount] := recId;
          CAggInitLen[CAggInitCount] := 1;
          CAggInitIsArr[CAggInitCount] := False;
          Inc(CAggInitCount);
        end;
        SkipBraceBlock;
      end
      else if CurTok.Kind = tkBegin then
      begin
        { `= { ... }` aggregate initializer: skip with BALANCED braces so inner
          commas (`{{"a",f},{"b",g}}`) don't end it early. }
        depth := 0;
        repeat
          if CurTok.Kind = tkBegin then Inc(depth)
          else if CurTok.Kind = tkEnd then Dec(depth);
          Next;
        until (depth = 0) or (CurTok.Kind = tkEOF);
      end
      else if (not wasArr) and (idx >= 0) and (baseTk <> tyRecord) and
              (baseTk <> tyPointer) and TypeIsOrdinal(baseTk) and
              (CurTok.Kind = tkInteger) and (Tokens[TokPos].Kind in [tkComma, tkSemicolon]) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar ordinal global `T x = <int literal>;` -> a direct PendingInit
          assign (no field offset, so the by-name emission path is unaffected),
          run at the start of main. Anything more complex falls through to skip. }
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := -1;
        PendingInitFOff[PendingInitCount] := -1;
        PendingInitFLen[PendingInitCount] := 0;
        PendingInitVal[PendingInitCount]  := CurTok.IVal;
        PendingInitTk[PendingInitCount]   := Ord(baseTk);
        Inc(PendingInitCount);
        Next;
      end
      else if (not wasArr) and (idx >= 0) and TypeIsFloat(baseTk) and
              ((CurTok.Kind = tkFloat) or
               ((CurTok.Kind = tkMinus) and (Tokens[TokPos].Kind = tkFloat)) or
               ((CurTok.Kind = tkPlus) and (Tokens[TokPos].Kind = tkFloat))) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar float global `double x = 3.14;` / `float y = -1.5;`.
          Float tokens carry IEEE-754 double bits; replay as AN_FLOAT_LIT at
          main-entry init so normal assignment lowering narrows tySingle slots. }
        negFloat := False;
        if CurTok.Kind = tkMinus then begin negFloat := True; Next; end
        else if CurTok.Kind = tkPlus then Next;
        if Tokens[TokPos].Kind in [tkComma, tkSemicolon] then
        begin
          initV := CurTok.IVal;
          if negFloat then
          begin
            signMask := 1; signMask := signMask shl 63;
            initV := initV xor signMask;
          end;
          PendingInitSym[PendingInitCount]  := idx;
          PendingInitElem[PendingInitCount] := -1;
          PendingInitFOff[PendingInitCount] := -1;
          PendingInitFLen[PendingInitCount] := 0;
          PendingInitVal[PendingInitCount]  := initV;
          PendingInitTk[PendingInitCount]   := Ord(baseTk);
          PendingInitKind[PendingInitCount] := 3;
          Inc(PendingInitCount);
          Next;
        end
        else
          while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                (CurTok.Kind <> tkEOF) do Next;
      end
      else if (not wasArr) and (idx >= 0) and (baseTk <> tyRecord) and
              (baseTk <> tyPointer) and (TypeIsOrdinal(baseTk) or TypeIsFloat(baseTk)) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar ordinal/float global with a constant-expression initializer the
          bare-literal fast paths above did not catch: a cast `(int)7`, an
          arithmetic const `2+3`, or an integer literal assigned to a float
          (`double x = 100;`). Fold with CEvalConstExpr; for a float target,
          reinterpret the integer value as its IEEE-754 double bits (the value
          lowering then narrows a tySingle slot). }
        initV := CEvalConstExpr;
        if TypeIsFloat(baseTk) then
        begin
          dvv := initV;              { Int64 -> Double value }
          Move(dvv, initV, 8);       { reinterpret to IEEE-754 bits }
        end;
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := -1;
        PendingInitFOff[PendingInitCount] := -1;
        PendingInitFLen[PendingInitCount] := 0;
        PendingInitVal[PendingInitCount]  := initV;
        PendingInitTk[PendingInitCount]   := Ord(baseTk);
        if TypeIsFloat(baseTk) then
          PendingInitKind[PendingInitCount] := 3
        else
          PendingInitKind[PendingInitCount] := 0;
        Inc(PendingInitCount);
      end
      else if (not wasArr) and (idx >= 0) and (baseTk = tyPointer) and
              (CurTok.Kind = tkString) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Scalar `char *p = "literal";` (e.g. lua's `const char *const CLIBS =
          "_CLIBS"`). Store the string-literal address into p at main entry
          (FOff = -3 string-span sentinel, Elem = -1 scalar). The assignment
          lowering applies the C string-literal +8 char-pointer adjustment. }
        PendingInitSym[PendingInitCount]  := idx;
        PendingInitElem[PendingInitCount] := -1;
        PendingInitFOff[PendingInitCount] := -3;
        PendingInitFLen[PendingInitCount] := Tokens[TokPos - 1].SLen;
        PendingInitVal[PendingInitCount]  := Tokens[TokPos - 1].SOffset;
        PendingInitTk[PendingInitCount]   := Ord(tyPointer);
        PendingInitKind[PendingInitCount] := 0;
        Inc(PendingInitCount);
        Next;
        while CurTok.Kind = tkString do
        begin
          PendingInitFLen[PendingInitCount - 1] :=
            PendingInitFLen[PendingInitCount - 1] + Tokens[TokPos - 1].SLen;
          Next;
        end;
      end
      else if wasArr and (baseTk <> tyRecord) and (baseTk <> tyPointer) and
              TypeIsOrdinal(baseTk) and (idx >= 0) and (CurTok.Kind = tkString) then
      begin
        initStr := '';
        while CurTok.Kind = tkString do
        begin
          initStr := initStr + CurTok.SVal;
          Next;
        end;
        for ei := 0 to Length(initStr) do
        begin
          if ei < arrLen then
          begin
            if ei < Length(initStr) then
              initV := Ord(initStr[ei + 1])
            else
              initV := 0;
            if PendingInitCount < MAX_PENDING_INITS then
            begin
              PendingInitSym[PendingInitCount]  := idx;
              PendingInitElem[PendingInitCount] := ei;
              PendingInitFOff[PendingInitCount] := -1;
              PendingInitFLen[PendingInitCount] := 0;
              PendingInitVal[PendingInitCount]  := initV;
              PendingInitTk[PendingInitCount]   := Ord(baseTk);
              Inc(PendingInitCount);
            end;
          end;
        end;
      end
      else if (not wasArr) and (idx >= 0) and (baseTk = tyPointer) and
              (CurTok.Kind = tkAmp) and (Tokens[TokPos].Kind = tkIdent) and
              (PendingInitCount < MAX_PENDING_INITS) then
      begin
        { Pointer global initialised to the address of another global or an
          interior element: `T *p = &g;` or `T *p = &arr[const_expr];`.
          Record a PendingInit that stores @g (+ optional byte offset) into p.
          Elem = -2 sentinel; target sym index in Val; byte offset in ValAux. }
        Next;                       { consume '&' -> CurTok = target ident }
        initSymIdx := FindSym(CurTok.SVal);
        if (initSymIdx >= 0) and
           (Tokens[TokPos].Kind in [tkComma, tkSemicolon, tkLBrack]) then
        begin
          Next;                     { consume target ident }
          initOff := 0;
          if CurTok.Kind = tkLBrack then
          begin
            Next;                   { consume '[' }
            initOff := CEvalConstExpr;
            if Syms[initSymIdx].ElemType <> tyUnknown then
              initOff := initOff * TypeSize(Syms[initSymIdx].ElemType);
            Expect(tkRBrack, ']');  { consume ']' }
          end;
          if CurTok.Kind in [tkComma, tkSemicolon] then
          begin
            PendingInitSym[PendingInitCount]  := idx;
            PendingInitElem[PendingInitCount] := -2;     { address-of-sym sentinel }
            PendingInitFOff[PendingInitCount] := -1;
            PendingInitFLen[PendingInitCount] := 0;
            PendingInitVal[PendingInitCount]  := initSymIdx;
            PendingInitValAux[PendingInitCount] := initOff; { byte offset (0 = plain &g) }
            PendingInitTk[PendingInitCount]   := Ord(tyPointer);
            Inc(PendingInitCount);
          end
          else
            while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                  (CurTok.Kind <> tkEOF) do Next;
        end
        else
          while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
                (CurTok.Kind <> tkEOF) do Next;
      end
      else
        while (CurTok.Kind <> tkComma) and (CurTok.Kind <> tkSemicolon) and
              (CurTok.Kind <> tkEOF) do Next;
    end;
    if CurTok.Kind = tkComma then begin Next; Continue; end;
    Break;
  end;
  Eat(tkSemicolon);
end;

{ Classify the top-level item starting at the current token as a function
  (definition or prototype) vs a global variable, WITHOUT consuming it: peek
  the declaration-specifiers + declarator name and test for a following `(`,
  then rewind the token cursor. }
function CTopLevelIsFunc: Boolean;
var savedPos: Integer;
begin
  savedPos := TokPos - 1;          { index of the current token }
  ParseCDeclType;
  if CTypeFnRetIsFunc then
    Result := True
  else
  begin
    if CurTok.Kind = tkIdent then Next;
    Result := (CurTok.Kind = tkLParen);
  end;
  TokPos := savedPos; Next;        { rewind }
end;

{ True when the current top-level token starts a TYPE declaration
  (`typedef …`, `enum …`, or a bare `struct/union [Tag] { … } ;` / forward),
  as opposed to a function or a global variable typed by a struct. }
function CIsTopLevelTypeDecl: Boolean;
begin
  Result := ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef')) or
            ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') and IsBareEnumDecl) or
            (((CurTok.Kind = tkRecord) or
              ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'))) and IsBareStructDecl);
end;

{ Consume a top-level declaration up to and including its terminating `;`,
  balancing any `{ }` (struct body / brace initialiser). Used in pass 2 to skip
  type declarations and globals already processed in pass 1. }
procedure SkipCDeclToSemi;
var depth: Integer;
begin
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkBegin then Inc(depth)
    else if CurTok.Kind = tkEnd then Dec(depth)
    else if (CurTok.Kind = tkSemicolon) and (depth <= 0) then begin Next; Exit; end;
    Next;
  end;
end;

{ C program driver (Slice D): compile EVERY function (not just main) plus
  top-level globals, with forward inter-function calls resolved. Two passes over
  the one token stream:
    pass 1 (CHeaderMode) — register every function signature and reserve every
            global, skipping bodies, so any call resolves regardless of order;
    pass 2 — compile each function body (ParseCSubroutine) and reserve globals
            (idempotent).
  Entry stub (x86-64, matching the pre-existing convention): save rsp, `call
  main`, then exit_group(eax) so main's int return becomes the process code. }
{ Emit the C setjmp/longjmp primitives as raw machine-code stubs and register
  them as __pxx_setjmp/__pxx_longjmp (BodyAddr = stub). lua's error model rides
  setjmp/longjmp; libc's crash here (the jmp_buf arrives NULL through the import),
  so provide them directly. jmp_buf is `long[16]` in setjmp.h, so the C arg decays
  to the buffer ADDRESS in the first argument register. Each target saves its
  ABI's callee-saved registers plus the caller stack pointer and the return
  address into env; setjmp returns 0 first and the longjmp value (mapped 0->1)
  when jumped to. Implemented for every hosted target (x86-64 desktop + the four
  cross targets that build lua/sqlite: i386, aarch64, arm32, riscv32). }
procedure EmitCSetjmpStubs;
var sjIdx, ljIdx: Integer;
    pn: array[0..1] of AnsiString; pt: array[0..1] of TTypeKind;
begin
  pn[0] := 'env'; pt[0] := tyPointer;
  sjIdx := RegisterProc('__pxx_setjmp', True, tyInteger, 1, pn, pt);
  Procs[sjIdx].BodyAddr := CodeLen;
  case TargetArch of
  TARGET_X86_64:
  begin
    { env in rdi. Layout: [0]=rbx [8]=rbp [16]=r12 [24]=r13 [32]=r14 [40]=r15
      [48]=caller-rsp [56]=return-addr. }
    EmitB($48); EmitB($89); EmitB($5F); EmitB($00);              { mov [rdi+0], rbx }
    EmitB($48); EmitB($89); EmitB($6F); EmitB($08);              { mov [rdi+8], rbp }
    EmitB($4C); EmitB($89); EmitB($67); EmitB($10);              { mov [rdi+16], r12 }
    EmitB($4C); EmitB($89); EmitB($6F); EmitB($18);              { mov [rdi+24], r13 }
    EmitB($4C); EmitB($89); EmitB($77); EmitB($20);              { mov [rdi+32], r14 }
    EmitB($4C); EmitB($89); EmitB($7F); EmitB($28);              { mov [rdi+40], r15 }
    EmitB($48); EmitB($8D); EmitB($44); EmitB($24); EmitB($08);  { lea rax, [rsp+8] }
    EmitB($48); EmitB($89); EmitB($47); EmitB($30);              { mov [rdi+48], rax }
    EmitB($48); EmitB($8B); EmitB($04); EmitB($24);              { mov rax, [rsp] }
    EmitB($48); EmitB($89); EmitB($47); EmitB($38);              { mov [rdi+56], rax }
    EmitB($31); EmitB($C0);                                      { xor eax, eax }
    EmitB($C3);                                                  { ret }
  end;
  TARGET_I386:
  begin
    { cdecl: env at [esp+4]. Layout: [0]=ebx [4]=esi [8]=edi [12]=ebp
      [16]=caller-esp(post-ret) [20]=return-addr. }
    EmitB($8B); EmitB($4C); EmitB($24); EmitB($04);   { mov ecx, [esp+4] (env) }
    EmitB($89); EmitB($59); EmitB($00);               { mov [ecx+0], ebx }
    EmitB($89); EmitB($71); EmitB($04);               { mov [ecx+4], esi }
    EmitB($89); EmitB($79); EmitB($08);               { mov [ecx+8], edi }
    EmitB($89); EmitB($69); EmitB($0C);               { mov [ecx+12], ebp }
    EmitB($8D); EmitB($44); EmitB($24); EmitB($04);   { lea eax, [esp+4] (esp after ret) }
    EmitB($89); EmitB($41); EmitB($10);               { mov [ecx+16], eax }
    EmitB($8B); EmitB($04); EmitB($24);               { mov eax, [esp] (return addr) }
    EmitB($89); EmitB($41); EmitB($14);               { mov [ecx+20], eax }
    EmitB($31); EmitB($C0);                           { xor eax, eax }
    EmitB($C3);                                       { ret }
  end;
  TARGET_AARCH64:
  begin
    { env in x0. Save x19..x28, x29, caller-sp, x30(return). Offsets in 8s. }
    EmitI32($F9000013);   { str x19, [x0, #0] }
    EmitI32($F9000414);   { str x20, [x0, #8] }
    EmitI32($F9000815);   { str x21, [x0, #16] }
    EmitI32($F9000C16);   { str x22, [x0, #24] }
    EmitI32($F9001017);   { str x23, [x0, #32] }
    EmitI32($F9001418);   { str x24, [x0, #40] }
    EmitI32($F9001819);   { str x25, [x0, #48] }
    EmitI32($F9001C1A);   { str x26, [x0, #56] }
    EmitI32($F900201B);   { str x27, [x0, #64] }
    EmitI32($F900241C);   { str x28, [x0, #72] }
    EmitI32($F900281D);   { str x29, [x0, #80] }
    EmitI32($910003E9);   { mov x9, sp }
    EmitI32($F9002C09);   { str x9,  [x0, #88] }
    EmitI32($F900301E);   { str x30, [x0, #96] }
    EmitI32($52800000);   { mov w0, #0 }
    EmitI32($D65F03C0);   { ret }
  end;
  TARGET_ARM32:
  begin
    { env in r0. Save r4..r11, sp, lr. Offsets in 4s. }
    EmitI32($E5804000);   { str r4,  [r0, #0] }
    EmitI32($E5805004);   { str r5,  [r0, #4] }
    EmitI32($E5806008);   { str r6,  [r0, #8] }
    EmitI32($E580700C);   { str r7,  [r0, #12] }
    EmitI32($E5808010);   { str r8,  [r0, #16] }
    EmitI32($E5809014);   { str r9,  [r0, #20] }
    EmitI32($E580A018);   { str r10, [r0, #24] }
    EmitI32($E580B01C);   { str r11, [r0, #28] }
    EmitI32($E580D020);   { str sp,  [r0, #32] }
    EmitI32($E580E024);   { str lr,  [r0, #36] }
    EmitI32($E3A00000);   { mov r0, #0 }
    EmitI32($E12FFF1E);   { bx lr }
  end;
  TARGET_RISCV32:
  begin
    { env in a0(x10). Save ra, sp, s0..s11. Offsets in 4s. }
    EmitI32($00152023);   { sw ra,  0(a0) }
    EmitI32($00252223);   { sw sp,  4(a0) }
    EmitI32($00852423);   { sw s0,  8(a0) }
    EmitI32($00952623);   { sw s1,  12(a0) }
    EmitI32($01252823);   { sw s2,  16(a0) }
    EmitI32($01352A23);   { sw s3,  20(a0) }
    EmitI32($01452C23);   { sw s4,  24(a0) }
    EmitI32($01552E23);   { sw s5,  28(a0) }
    EmitI32($03652023);   { sw s6,  32(a0) }
    EmitI32($03752223);   { sw s7,  36(a0) }
    EmitI32($03852423);   { sw s8,  40(a0) }
    EmitI32($03952623);   { sw s9,  44(a0) }
    EmitI32($03A52823);   { sw s10, 48(a0) }
    EmitI32($03B52A23);   { sw s11, 52(a0) }
    EmitI32($00000513);   { li a0, 0 }
    EmitI32($00008067);   { ret }
  end;
  else
    Error('EmitCSetjmpStubs: unsupported target');
  end;

  pn[0] := 'env'; pt[0] := tyPointer; pn[1] := 'val'; pt[1] := tyInteger;
  ljIdx := RegisterProc('__pxx_longjmp', False, tyInteger, 2, pn, pt);
  Procs[ljIdx].BodyAddr := CodeLen;
  case TargetArch of
  TARGET_X86_64:
  begin
    EmitB($48); EmitB($8B); EmitB($5F); EmitB($00);              { mov rbx, [rdi+0] }
    EmitB($48); EmitB($8B); EmitB($6F); EmitB($08);              { mov rbp, [rdi+8] }
    EmitB($4C); EmitB($8B); EmitB($67); EmitB($10);              { mov r12, [rdi+16] }
    EmitB($4C); EmitB($8B); EmitB($6F); EmitB($18);              { mov r13, [rdi+24] }
    EmitB($4C); EmitB($8B); EmitB($77); EmitB($20);              { mov r14, [rdi+32] }
    EmitB($4C); EmitB($8B); EmitB($7F); EmitB($28);              { mov r15, [rdi+40] }
    EmitB($48); EmitB($8B); EmitB($67); EmitB($30);              { mov rsp, [rdi+48] }
    EmitB($48); EmitB($8B); EmitB($4F); EmitB($38);              { mov rcx, [rdi+56] }
    EmitB($89); EmitB($F0);                                      { mov eax, esi  (val) }
    EmitB($85); EmitB($C0);                                      { test eax, eax }
    EmitB($75); EmitB($02);                                      { jnz +2 }
    EmitB($FF); EmitB($C0);                                      { inc eax  (0 -> 1) }
    EmitB($FF); EmitB($E1);                                      { jmp rcx }
  end;
  TARGET_I386:
  begin
    { pxx i386 ABI pushes args leftmost-deepest (arg0 at the HIGHER offset), so
      env(arg0) is at [esp+8] and val(arg1) at [esp+4] — NOT standard cdecl order.
      (setjmp's single env arg lands at [esp+4] either way, so only 2-arg longjmp
      needs the swapped offsets; the old code read env from [esp+4]=val and
      crashed dereferencing 7 as a jmp_buf pointer.) }
    EmitB($8B); EmitB($4C); EmitB($24); EmitB($08);   { mov ecx, [esp+8] (env) }
    EmitB($8B); EmitB($54); EmitB($24); EmitB($04);   { mov edx, [esp+4] (val) }
    EmitB($8B); EmitB($59); EmitB($00);               { mov ebx, [ecx+0] }
    EmitB($8B); EmitB($71); EmitB($04);               { mov esi, [ecx+4] }
    EmitB($8B); EmitB($79); EmitB($08);               { mov edi, [ecx+8] }
    EmitB($8B); EmitB($69); EmitB($0C);               { mov ebp, [ecx+12] }
    EmitB($89); EmitB($D0);                           { mov eax, edx (val) }
    EmitB($85); EmitB($C0);                           { test eax, eax }
    EmitB($75); EmitB($01);                           { jnz +1 }
    EmitB($40);                                       { inc eax (0 -> 1) }
    EmitB($8B); EmitB($61); EmitB($10);               { mov esp, [ecx+16] }
    EmitB($FF); EmitB($61); EmitB($14);               { jmp [ecx+20] }
  end;
  TARGET_AARCH64:
  begin
    { env in x0, val in w1. Restore, map 0->1, branch to saved return. }
    EmitI32($F9400013);   { ldr x19, [x0, #0] }
    EmitI32($F9400414);   { ldr x20, [x0, #8] }
    EmitI32($F9400815);   { ldr x21, [x0, #16] }
    EmitI32($F9400C16);   { ldr x22, [x0, #24] }
    EmitI32($F9401017);   { ldr x23, [x0, #32] }
    EmitI32($F9401418);   { ldr x24, [x0, #40] }
    EmitI32($F9401819);   { ldr x25, [x0, #48] }
    EmitI32($F9401C1A);   { ldr x26, [x0, #56] }
    EmitI32($F940201B);   { ldr x27, [x0, #64] }
    EmitI32($F940241C);   { ldr x28, [x0, #72] }
    EmitI32($F940281D);   { ldr x29, [x0, #80] }
    EmitI32($F9402C09);   { ldr x9,  [x0, #88] }
    EmitI32($9100013F);   { mov sp, x9 }
    EmitI32($F9403009);   { ldr x9,  [x0, #96] (return addr) }
    EmitI32($7100003F);   { cmp w1, #0 }
    EmitI32($1A9F1420);   { csinc w0, w1, wzr, ne  (val==0 -> 1) }
    EmitI32($D61F0120);   { br x9 }
  end;
  TARGET_ARM32:
  begin
    { env in r0, val in r1. }
    EmitI32($E5904000);   { ldr r4,  [r0, #0] }
    EmitI32($E5905004);   { ldr r5,  [r0, #4] }
    EmitI32($E5906008);   { ldr r6,  [r0, #8] }
    EmitI32($E590700C);   { ldr r7,  [r0, #12] }
    EmitI32($E5908010);   { ldr r8,  [r0, #16] }
    EmitI32($E5909014);   { ldr r9,  [r0, #20] }
    EmitI32($E590A018);   { ldr r10, [r0, #24] }
    EmitI32($E590B01C);   { ldr r11, [r0, #28] }
    EmitI32($E590D020);   { ldr sp,  [r0, #32] }
    EmitI32($E5902024);   { ldr r2,  [r0, #36] (return addr) }
    EmitI32($E1B00001);   { movs r0, r1  (val, set flags) }
    EmitI32($03A00001);   { moveq r0, #1  (val==0 -> 1) }
    EmitI32($E12FFF12);   { bx r2 }
  end;
  TARGET_RISCV32:
  begin
    { env in a0(x10), val in a1(x11). }
    EmitI32($00052083);   { lw ra,  0(a0) }
    EmitI32($00452103);   { lw sp,  4(a0) }
    EmitI32($00852403);   { lw s0,  8(a0) }
    EmitI32($00C52483);   { lw s1,  12(a0) }
    EmitI32($01052903);   { lw s2,  16(a0) }
    EmitI32($01452983);   { lw s3,  20(a0) }
    EmitI32($01852A03);   { lw s4,  24(a0) }
    EmitI32($01C52A83);   { lw s5,  28(a0) }
    EmitI32($02052B03);   { lw s6,  32(a0) }
    EmitI32($02452B83);   { lw s7,  36(a0) }
    EmitI32($02852C03);   { lw s8,  40(a0) }
    EmitI32($02C52C83);   { lw s9,  44(a0) }
    EmitI32($03052D03);   { lw s10, 48(a0) }
    EmitI32($03452D83);   { lw s11, 52(a0) }
    EmitI32($00058513);   { mv a0, a1  (val) }
    EmitI32($00051463);   { bnez a0, +8 }
    EmitI32($00100513);   { li a0, 1   (val==0 -> 1) }
    EmitI32($00008067);   { ret }
  end;
  else
    Error('EmitCSetjmpStubs: unsupported target');
  end;
end;

{ Known crtl-provided libc functions -> their <header> module. A C89-style
  program may declare printf/malloc/strcpy by hand instead of including the
  header (c-testsuite does this throughout); without the include the crtl
  auto-pull never fires, the prototype is marked external against libc, and in
  a libc-free link the call silently does nothing. Used by
  CPullCrtlForPrototypes below to pull the impl after pass 1. }
function CCrtlHeaderForName(const name: AnsiString): AnsiString;
begin
  Result := '';
  if (name='printf') or (name='fprintf') or (name='sprintf') or (name='snprintf') or
     (name='vprintf') or (name='vfprintf') or (name='vsprintf') or (name='vsnprintf') or
     (name='puts') or (name='putchar') or (name='getchar') or (name='fputs') or (name='fputc') or
     (name='fgets') or (name='fgetc') or (name='fopen') or (name='fclose') or (name='fread') or
     (name='fwrite') or (name='fflush') or (name='sscanf') or (name='scanf') or (name='ungetc') or
     (name='fseek') or (name='ftell') or (name='perror') or (name='remove') or (name='rename') then
    Result := 'stdio.h'
  else if (name='malloc') or (name='calloc') or (name='realloc') or (name='free') or
     (name='exit') or (name='abort') or (name='atoi') or (name='atol') or (name='atof') or
     (name='strtol') or (name='strtoul') or (name='strtod') or (name='qsort') or (name='abs') or
     (name='labs') or (name='getenv') or (name='rand') or (name='srand') then
    Result := 'stdlib.h'
  else if (name='strcpy') or (name='strncpy') or (name='strlen') or (name='strcmp') or
     (name='strncmp') or (name='strcat') or (name='strncat') or (name='strchr') or (name='strrchr') or
     (name='strstr') or (name='memcpy') or (name='memmove') or (name='memset') or (name='memcmp') or
     (name='memchr') or (name='strdup') or (name='strerror') then
    Result := 'string.h'
  else if (name='isdigit') or (name='isalpha') or (name='isalnum') or (name='isspace') or
     (name='isupper') or (name='islower') or (name='toupper') or (name='tolower') or
     (name='isxdigit') or (name='ispunct') or (name='iscntrl') or (name='isprint') or (name='isgraph') then
    Result := 'ctype.h'
  else if (name='sqrt') or (name='sin') or (name='cos') or (name='tan') or (name='pow') or
     (name='exp') or (name='log') or (name='floor') or (name='ceil') or (name='fabs') or (name='fmod') then
    Result := 'math.h';
end;

{ After pass 1: any proc still marked external (= prototype with no definition
  anywhere in the TU) whose name is a known crtl libc function pulls its crtl
  module, exactly as if the program had included the header. Returns the first
  appended token index, or -1 when nothing was pulled. The synthetic source is
  just the #include lines; CPreprocess resolves them on the normal crtl include
  path and the header auto-pull brings the sibling src/<name>.c in. The pulled
  region then goes through the same pass 1 / pass 2 as the main program.
  No-op under --system-libs (there the externals SHOULD bind to glibc). }
function CPullCrtlForPrototypes: Integer;
var
  i: Integer;
  hdr, nm, synth: AnsiString;
  wantStdio, wantStdlib, wantString, wantCtype, wantMath: Boolean;
begin
  Result := -1;
  if CUseSystemLibs then Exit;
  wantStdio := False; wantStdlib := False; wantString := False;
  wantCtype := False; wantMath := False;
  for i := 0 to ProcCount - 1 do
    if ProcExternal[i] then
    begin
      hdr := CCrtlHeaderForName(Procs[i].Name);
      if hdr = 'stdio.h' then wantStdio := True
      else if hdr = 'stdlib.h' then wantStdlib := True
      else if hdr = 'string.h' then wantString := True
      else if hdr = 'ctype.h' then wantCtype := True
      else if hdr = 'math.h' then wantMath := True;
    end;
  { IMPLICIT (undeclared) calls — C89 style with neither an include nor a hand
    prototype: `printf("x=%d\n", x)` with no declaration at all. Pass 1 never
    sees a prototype (bodies are skipped), so the ProcExternal sweep above
    misses these; the call then bound an implicit non-variadic int() and
    dropped the varargs (printed the format string literally). Scan the token
    stream for `name(` where name is a known crtl function with no registered
    proc, and pull its header like a hand prototype would — the pass-1 rerun
    over the pulled region registers the real variadic signature before any
    body compiles. A user DEFINITION of the same name anywhere in the TU was
    registered by pass 1, so FindProc filters it out here. }
  for i := 0 to TokCount - 2 do
  begin
    if wantStdio and wantStdlib and wantString and wantCtype and wantMath then Break;
    if (Tokens[i].Kind = tkIdent) and (Tokens[i + 1].Kind = tkLParen) then
    begin
      nm := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
      hdr := CCrtlHeaderForName(nm);          { cheap reject before FindProc }
      if (hdr <> '') and (FindProc(nm) < 0) then
      begin
        if hdr = 'stdio.h' then wantStdio := True
        else if hdr = 'stdlib.h' then wantStdlib := True
        else if hdr = 'string.h' then wantString := True
        else if hdr = 'ctype.h' then wantCtype := True
        else if hdr = 'math.h' then wantMath := True;
      end;
    end;
  end;
  synth := '';
  if wantStdio then AppendString(synth, '#include <stdio.h>'#10);
  if wantStdlib then AppendString(synth, '#include <stdlib.h>'#10);
  if wantString then AppendString(synth, '#include <string.h>'#10);
  if wantCtype then AppendString(synth, '#include <ctype.h>'#10);
  if wantMath then AppendString(synth, '#include <math.h>'#10);
  if Length(synth) = 0 then Exit;
  CPreprocess(synth, SourceFileDir);
  Result := CLexAppend(synth);
end;

procedure ParseCProgram;
var firstIdx, callPatch, mainIdx, rvHi, rvLo, crtlStart: Integer;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  { Program entry stub (the ELF entry at code offset 0): save the initial stack
    pointer, hand C `main(argc, argv)` the Linux initial stack ([argc][argv0]...),
    call main, then exit_group(main's return). Target-specific: x86-64 passes
    argc/argv in edi/rsi and syscalls via `syscall`; i386 passes them on the
    cdecl stack and syscalls via `int 0x80`. Other targets use a different call
    encoding for `call main`; they raise a clear error until their stub lands,
    rather than emitting x86-64 bytes that crash at runtime. }
  { Each branch emits: setup (save sp, hand main argc/argv), the call to main
    (recording callPatch at the call instruction for later body-address fixup),
    then exit_group(main's return). The call encoding differs per target (E8
    rel32 on x86 family, BL on arm32), so it lives inside each branch. }
  case TargetArch of
    TARGET_X86_64:
    begin
      EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP); { mov [initial_rsp], rsp }
      EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP); { mov rax, [initial_rsp] }
      EmitB($8B); EmitB($38);                                                       { mov edi, [rax]  (argc) }
      EmitB($48); EmitB($8D); EmitB($70); EmitB($08);                               { lea rsi, [rax+8] (argv) }
      EmitB($E8); callPatch := CodeLen; EmitI32(0);                                 { call main }
      EmitB($89); EmitB($C7);            { mov edi, eax }
      EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
      EmitB($0F); EmitB($05);            { syscall }
    end;
    TARGET_I386:
    begin
      EmitB($89); EmitB($E0);                                  { mov eax, esp }
      EmitB($A3); EmitGlobRef(BSS_INITIAL_RSP);                { mov [initial_sp], eax }
      EmitB($8D); EmitB($48); EmitB($04);                      { lea ecx, [eax+4] (argv) }
      EmitB($51);                                              { push ecx        (arg2 = argv) }
      EmitB($FF); EmitB($30);                                  { push [eax]      (arg1 = argc) }
      EmitB($E8); callPatch := CodeLen; EmitI32(0);            { call main }
      EmitB($89); EmitB($C3);            { mov ebx, eax }
      EmitB($B8); EmitI32(252);          { mov eax, 252 (exit_group) }
      EmitB($CD); EmitB($80);            { int 0x80 }
    end;
    TARGET_ARM32:
    begin
      { AAPCS: main(argc, argv) -> r0=argc, r1=argv. argc at [sp], argv = sp+4.
        Save the initial sp to BSS_INITIAL_RSP (loaded via an inline literal, the
        only way to reach an absolute address on arm32). }
      EmitI32($E59F1000);                 { ldr r1, [pc]  -> r1 = &initial_sp }
      EmitI32($EA000000);                 { b .+8 (skip the literal) }
      EmitGlobRef(BSS_INITIAL_RSP);       { literal: absolute BSS address }
      EmitI32($E581D000);                 { str sp, [r1] }
      EmitI32($E59D0000);                 { ldr r0, [sp]  (argc) }
      EmitI32($E28D1004);                 { add r1, sp, #4 (argv) }
      callPatch := CodeLen; EmitI32($EB000000);   { bl main (offset patched) }
      EmitI32($E3A070F8);                 { mov r7, #248 (exit_group) }
      EmitI32($EF000000);                 { svc #0 (r0 = exit code) }
    end;
    TARGET_AARCH64:
    begin
      { AAPCS64: main(argc, argv) -> x0=argc, x1=argv. argc at [sp], argv = sp+8.
        Save sp to BSS_INITIAL_RSP via an inline 32-bit literal (low-4GB image). }
      EmitI32($18000041);                 { ldr w1, [pc+8] -> w1 = &initial_sp }
      EmitI32($14000002);                 { b [pc+8] (skip literal) }
      EmitGlobRef(BSS_INITIAL_RSP);       { literal: absolute BSS address }
      EmitI32($910003E2);                 { mov x2, sp }
      EmitI32($F9000022);                 { str x2, [x1] }
      EmitI32($F94003E0);                 { ldr x0, [sp]  (argc) }
      EmitI32($910023E1);                 { add x1, sp, #8 (argv) }
      callPatch := CodeLen; EmitI32($94000000);   { bl main (offset patched) }
      EmitI32($D2800BC8);                 { mov x8, #94 (exit_group) }
      EmitI32($D4000001);                 { svc #0 (x0 = exit code) }
    end;
    TARGET_RISCV32:
    begin
      { RV32 ilp32: main(argc, argv) -> a0=argc, a1=argv. argc at [sp], argv=sp+4.
        Save sp to BSS_INITIAL_RSP (absolute address via the inline-literal load). }
      EmitLoadGlobAddrRISCV32(reg_t0, BSS_INITIAL_RSP);  { t0 = &initial_sp }
      rv32_sw(reg_sp, reg_t0, 0);         { sw sp, 0(t0) }
      rv32_lw(reg_a0, reg_sp, 0);         { a0 = argc = [sp] }
      rv32_addi(reg_a1, reg_sp, 4);       { a1 = argv = sp+4 }
      { auipc+jalr (full range) not JAL (+/-1MB): main can sit past 1MB in a
        large image (cross lua = 1.75MB). Both words patched below. }
      callPatch := CodeLen; rv32_auipc(reg_t0, 0); rv32_jalr(reg_ra, reg_t0, 0);
      rv32_addi(reg_a7, reg_zero, 94);    { a7 = 94 (exit_group) }
      EmitI32($00000073);                 { ecall (a0 = exit code) }
    end;
  else
    Error('C program entry stub not implemented for this target yet');
  end;

  { Auto-pull the C IO bridge (pxxcio) so the stdio veneer's
    `extern __pxx_write`/`__pxx_read` resolve to bodied Pascal procs over the
    cross-platform PAL — libc-free, one shared IO path with Pascal. Emitted AFTER
    the entry stub (which is the ELF entry at code offset 0 and never falls
    through — it exit_group's), so the unit bodies sit after it, reached only via
    call. Guarded like the Pascal default-RTL pull: skip on bare-metal ESP and
    when default RTL is opted out. }
  if (not NoDefaultRtl) and (TargetArch <> TARGET_XTENSA) and
     ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot)) then
  begin
    { Hosted riscv32 has no FPU: every float op lowers to the __pxx_* soft-float
      kernels, and pxxcio `uses math` (Sqrt etc.) pulls float bodies that compile
      against them. Pull softfloat FIRST, mirroring the Pascal ParseProgram
      epilogue — otherwise those bodies (and any C double op) fail with
      "__pxx_dmul not found". The whole guard now matches the Pascal default-RTL
      pull: hosted riscv32 is INCLUDED (was skipped entirely, leaving riscv32 C
      with no __pxx_write/malloc bridge and no softfloat). }
    if ((TargetArch = TARGET_RISCV32) and (not EspBareBoot)) or
       (TargetArch = TARGET_ARM32) then
      { arm32 has hardware VFP, but VFP's double->int convert is 32-bit only;
        a 64-bit cast of a large double (e.g. sqlite %f's double->u64) routes to
        the soft-float __pxx_d2i64 kernel, so pull the unit here too. The other
        kernels are unused dead code on arm32. }
      ParseUsesUnit('softfloat');
    ParseUsesUnit('pxxcio');
    { --threadsafe C: pull the libc-free pthread bridge (palpthread over the
      palthread/palsync PAL) so a `<pthread.h>` shim's extern __pxx_pmutex_*/
      __pxx_pthread_* resolve to bodied procs. Gated on ThreadSafeMode because
      the create/join path lowers onto __pxxclone, which is a compile error
      without the thread-safe runtime — the same gate pthread.c needs anyway.
      Dead (DCE'd) if the program includes no <pthread.h>. }
    if ThreadSafeMode then
      ParseUsesUnit('palpthread');
  end;

  { setjmp/longjmp primitives (lua's error model). After the entry stub, before
    any C body, so __pxx_setjmp/__pxx_longjmp resolve as bodied procs. }
  EmitCSetjmpStubs;

  firstIdx := TokPos - 1;
  CProgramMode := True;
  CAggInitCount := 0;

  { pass 1: lay out types, register every function signature, reserve globals }
  CHeaderMode := True;
  while CurTok.Kind <> tkEOF do
  begin
    if CIsTopLevelTypeDecl then
    begin
      if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then ParseCTypedef
      else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then ParseCEnumDecl
      else ParseCStructDecl;
    end
    else if IsCTypeTok then
    begin
      if CTopLevelIsFunc then ParseCSubroutine
      else ParseCGlobalVarDecl;
    end
    else
      Next;
  end;
  CHeaderMode := False;

  { Hand-declared libc prototypes (no header include): pull the crtl modules
    now and run the pulled region through its own pass 1, so the definitions
    replace the silent libc externals before any caller compiles. }
  crtlStart := CPullCrtlForPrototypes;
  if crtlStart >= 0 then
  begin
    TokPos := crtlStart; Next;
    CHeaderMode := True;
    while CurTok.Kind <> tkEOF do
    begin
      if CIsTopLevelTypeDecl then
      begin
        if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then ParseCTypedef
        else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then ParseCEnumDecl
        else ParseCStructDecl;
      end
      else if IsCTypeTok then
      begin
        if CTopLevelIsFunc then ParseCSubroutine
        else ParseCGlobalVarDecl;
      end
      else
        Next;
    end;
    CHeaderMode := False;
  end;

  { pass 2: compile function bodies; types/globals already done in pass 1 }
  TokPos := firstIdx; Next;
  while CurTok.Kind <> tkEOF do
  begin
    if CIsTopLevelTypeDecl then
      SkipCDeclToSemi
    else if IsCTypeTok then
    begin
      if CTopLevelIsFunc then ParseCSubroutine
      else SkipCDeclToSemi;
    end
    else
      Next;
  end;

  { pass 2 over the pulled crtl region: compile the pulled bodies. }
  if crtlStart >= 0 then
  begin
    TokPos := crtlStart; Next;
    while CurTok.Kind <> tkEOF do
    begin
      if CIsTopLevelTypeDecl then
        SkipCDeclToSemi
      else if IsCTypeTok then
      begin
        if CTopLevelIsFunc then ParseCSubroutine
        else SkipCDeclToSemi;
      end
      else
        Next;
    end;
  end;

  CProgramMode := False;
  ApplyCallFixups;

  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('main function not found');
  { Patch the entry stub's call-to-main with main's body address. x86 family: E8
    rel32 = target - (callPatch+4). arm32: BL imm24 = (target - (callPatch+8))/4
    in the low 24 bits of 0xEB000000 (pc is 8 ahead of the BL on arm). }
  if TargetArch = TARGET_ARM32 then
    Patch32(callPatch, Integer($EB000000) or
      (((Procs[mainIdx].BodyAddr - (callPatch + 8)) div 4) and $00FFFFFF))
  else if TargetArch = TARGET_AARCH64 then
    Patch32(callPatch, Integer($94000000) or
      (((Procs[mainIdx].BodyAddr - callPatch) div 4) and $03FFFFFF))
  else if TargetArch = TARGET_RISCV32 then
  begin
    RISCVPcrelSplit(Procs[mainIdx].BodyAddr - callPatch, rvHi, rvLo);
    Patch32(callPatch, EncodeRISCVAuipc(reg_t0, rvHi));
    Patch32(callPatch + 4, EncodeRISCVJalr(reg_ra, reg_t0, rvLo));
  end
  else
    Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;

procedure ParseCSubroutine;
var
  retType, ptype: TTypeKind;
  name, extLib: AnsiString;
  isFunc: Boolean;
  nparams, procIdx, i, j, idx, patchPos, sz, gli: Integer;
  intIdx, sseIdx, stackOff, ngpNamed, nfpNamed: Integer;
  pwA, pnWordsA, whiA: Integer;   { arm32 word-based param spill }
  retPtrElemTk, retPtrElemRec, retRecId, retProcSig: Integer;
  ptypes: array[0..31] of TTypeKind;
  pnames: array[0..31] of AnsiString;
  pdepths: array[0..31] of Integer;
  pbasetk: array[0..31] of Integer;
  pbaserec: array[0..31] of Integer;
  pelemtk: array[0..31] of Integer;   { pointed-at TTypeKind ordinal per pointer param }
  pelemrec: array[0..31] of Integer;
  precid: array[0..31] of Integer;    { record id per tyRecord param (for isRef field access) }
  pprocsig: array[0..31] of Integer;  { fn-pointer signature Procs[] index per param, else -1 }
  savedSC, savedFS, node, savedCurProc: Integer;
  vaSaveSym, vaSaveRec, vaOverflowSym: Integer;
  parenName, isVariadic, wasNewProc, fnRetIsFunc, forceSystemExternal, sigMatch, paramsOverflow: Boolean;
begin
  { Default DT_NEEDED soname for an external with no explicit library: math
    functions are in libm.so.6 on glibc, everything else in libc.so.6. }
  extLib := 'libc.so.6';
  retType := ParseCDeclType;
  { A function whose RETURN type is itself a function pointer (`fty go(void)`,
    fty a fn-ptr typedef) carries the returned pointer's call signature, so
    `go()(args)` lowers as an indirect call. Captured now, before param parsing
    clobbers CTypeProcSig. }
  retProcSig := CTypeProcSig;
  { Capture the return type's pointed-at type so `f()^`, `f()^.field`, `f()[i]`
    on a typed-pointer result resolve the element. }
  retPtrElemTk := Ord(tyUnknown);
  retPtrElemRec := REC_NONE;
  if (retType = tyPointer) and
     ((CTypePtrDepth > 0) or (CTypeElemTk <> Ord(tyUnknown))) then
  begin
    retPtrElemTk := CTypeElemTk;
    retPtrElemRec := CTypeElemRec;
  end;
  { An aggregate return type (`struct S f(...)`) carries its record id in
    CTypeBaseRec; capture it before param parsing overwrites CTypeBaseRec, so the
    proc records ProcRetRecId and the hidden Result slot is sized to the record
    (without it the slot was 0/garbage-sized and a by-value struct/union return —
    e.g. lua's `union { double n; long i; }` setobj path — segfaulted). }
  retRecId := REC_NONE;
  if retType = tyRecord then retRecId := CTypeBaseRec;
  if CTypeIsVoid then retType := tyInteger; { void return: value slot unused }
  fnRetIsFunc := CTypeFnRetIsFunc;
  if fnRetIsFunc then
  begin
    name := CTypeFnPtrName;
    nparams := CTypeFnRetParamCount;
    isVariadic := False;
    for i := 0 to nparams - 1 do
    begin
      ptypes[i] := CTypeFnRetPTypes[i];
      pnames[i] := CTypeFnRetPNames[i];
      pdepths[i] := CTypeFnRetPDepths[i];
      pbasetk[i] := CTypeFnRetPBaseTk[i];
      pbaserec[i] := CTypeFnRetPBaseRec[i];
      pelemtk[i] := CTypeFnRetPElemTk[i];
      pelemrec[i] := CTypeFnRetPElemRec[i];
      precid[i] := CTypeFnRetPRecId[i];
      pprocsig[i] := CTypeFnRetPProcSig[i];
    end;
  end;

  { A parenthesized declarator name `(name)(params)` — lua.h declares its whole
    API this way (`LUA_API int (lua_gettop) (lua_State *L);`). Unwrap the redundant
    parens so the name + param list parse normally. Distinct from `(*name)(...)`
    (a function pointer), which ParseCDeclType already consumes. }
  parenName := False;
  if (not fnRetIsFunc) and (CurTok.Kind = tkLParen) and
     (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos+1].Kind = tkRParen) then
  begin
    parenName := True;
    Next;   { consume '(' — CurTok is now the name }
  end;

  if (not fnRetIsFunc) and (CurTok.Kind <> tkIdent) then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  if not fnRetIsFunc then
  begin
    name := CurTok.SVal;
    Next;
  end;
  extLib := 'libc.so.6';
  if (name = 'pow') or (name = 'sqrt') or (name = 'fmod') or (name = 'floor') or
     (name = 'ceil') or (name = 'fabs') or (name = 'sin') or (name = 'cos') or
     (name = 'tan') or (name = 'asin') or (name = 'acos') or (name = 'atan') or
     (name = 'atan2') or (name = 'exp') or (name = 'log') or (name = 'frexp') or
     (name = 'ldexp') or (name = 'sinh') or (name = 'cosh') or (name = 'tanh') then
    extLib := 'libm.so.6';
  forceSystemExternal := (CurrentCLibrary <> '') or CSystemLibSelectedForSoname(extLib);
  if (not fnRetIsFunc) and parenName then Eat(tkRParen);   { consume the ')' wrapping the name }

  if (not fnRetIsFunc) and (CurTok.Kind <> tkLParen) then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  if not fnRetIsFunc then
  begin
    Expect(tkLParen, '(');
    nparams := 0;
    paramsOverflow := False;
    isVariadic := False;
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind = tkDot then isVariadic := True;   { `...` lexes to three tkDot }
      if IsCTypeTok then
      begin
        ptype := ParseCDeclType;
        if CTypeIsVoid then
        begin
          { `(void)` empty parameter list — no actual parameter }
        end
        else
        begin
          { A 17th+ parameter cannot be stored. For a DEFINITION that is fatal
            (the dropped param would read as constant 0 in the body — the
            bug-c-vararg-vastart-named-fp-stack follow-through); a
            declaration-only prototype (GTK headers) keeps the old skip, since
            the body never reads it (calling with >16 args stays unsupported).
            The overflow flag is checked at the body branch below. }
          if nparams >= MAX_PROC_PARAMS then
          begin
            paramsOverflow := True;
            { keep parsing declarators into the LAST slot; nothing is stored }
            nparams := MAX_PROC_PARAMS - 1;
          end;
          ptypes[nparams] := ptype;
          pdepths[nparams] := CTypePtrDepth;
          pbasetk[nparams] := CTypePtrBaseTk;
          pbaserec[nparams] := CTypePtrBaseRec;
          pelemtk[nparams] := CTypeElemTk;
          pelemrec[nparams] := CTypeElemRec;
          precid[nparams] := CTypeBaseRec;     { record id for a tyRecord param }
          pprocsig[nparams] := CTypeProcSig;   { fn-pointer param: callable in the body }
          if CTypeFnPtrName <> '' then
          begin
            { Inline function-pointer parameter `RET (*name)(params)` — ParseCDeclType
              consumed the whole declarator and captured the name, so the ident-read
              below would miss it and the param would be registered as `argN`, leaving
              a body reference to `name` undeclared (sqlite3ThreadCreate's xTask).
              ParseCDeclType folds the fn-ptr into tyPointer with CTypeProcSig set. }
            pnames[nparams] := CTypeFnPtrName;
          end
          else if CurTok.Kind = tkIdent then
          begin
            pnames[nparams] := CurTok.SVal;
            Next;
          end
          else
          begin
            pnames[nparams] := 'arg0';
            pnames[nparams][4] := Chr(Ord('0') + nparams);
          end;
          { C array parameter `T name[...]` decays to a pointer `T *name` (lua
            ltable `computesizes(unsigned int nums[], ...)`). Consume the bracket
            dimension(s) and retype the param as pointer-to-element. }
          if CurTok.Kind = tkLBrack then
          begin
            while CurTok.Kind = tkLBrack do
            begin
              sz := 0;   { reuse as bracket depth }
              repeat
                if CurTok.Kind = tkLBrack then Inc(sz)
                else if CurTok.Kind = tkRBrack then Dec(sz);
                Next;
              until (sz = 0) or (CurTok.Kind = tkEOF);
            end;
            if pdepths[nparams] = 0 then
            begin
              pelemtk[nparams] := Ord(ptypes[nparams]);
              pelemrec[nparams] := CTypeBaseRec;
              pbasetk[nparams] := Ord(ptypes[nparams]);
              pbaserec[nparams] := CTypeBaseRec;
              pdepths[nparams] := 1;
            end
            else
            begin
              pelemtk[nparams] := Ord(tyPointer);   { `T *name[]` -> pointer-to-pointer }
              Inc(pdepths[nparams]);
            end;
            ptypes[nparams] := tyPointer;
          end;
          Inc(nparams);
        end;
      end
      else
        Next;
      Eat(tkComma);
    end;
    Expect(tkRParen, ')');
  end;
  
  isFunc := True; { In C, everything is a function }
  
  { Register or locate Proc }
  procIdx := -1;
  if forceSystemExternal then
  begin
    { Explicit system-library routing wins over case-insensitive Pascal fallback
      (e.g. pxxcio pulls Pascal math.Sqrt, but `--system-libs=m` wants C sqrt
      to remain an external libm import). Reuse an exact C declaration/definition
      from an earlier pass if present; never bind to a differently-cased Pascal
      routine here. }
    for i := 0 to ProcCount - 1 do
      if ProcCaseSensitive[i] and (Procs[i].Name = name) and
         (Procs[i].ParamCount = nparams) then
      begin
        sigMatch := True;
        for idx := 0 to nparams - 1 do
          if Procs[i].Params[idx].TypeKind <> ptypes[idx] then sigMatch := False;
        if sigMatch then begin procIdx := i; Break; end;
      end;
  end
  else
    procIdx := FindProc(name);
  wasNewProc := procIdx < 0;
  if wasNewProc then
    procIdx := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
  { A C extern can bind by name to an existing PASCAL proc (case-insensitive
    FindProc): lua's <math.h> `sqrt`/`exp`/`sin`/... resolve to the RTL math
    routines. Such a proc keeps its Pascal internal calling convention — marking
    it cdecl here would route the call through the SysV path (floats in XMM) while
    the Pascal prologue reads its params from GP registers, so every double arg
    arrived garbage (sqrt(16)->0, ln(2)->junk). Only a genuinely new C-declared
    proc is cdecl. }
  if wasNewProc then
  begin
    ProcVariadic[procIdx] := isVariadic;
    ProcCdecl[procIdx] := True;
    { Classify named params by SysV class so va_start seeds gp_offset/fp_offset
      correctly: GP (int/ptr) named params consume GP save slots, FP (float/
      double) named params consume XMM save slots. Counting all named params as
      GP (the old behaviour) skewed both offsets whenever a variadic function had
      a named float param (e.g. `sumv(double scale, int n, ...)` reread `scale`
      in the first va_arg(double)). }
    ngpNamed := 0; nfpNamed := 0;
    for i := 0 to nparams - 1 do
      if TypeIsFloat(ptypes[i]) then Inc(nfpNamed) else Inc(ngpNamed);
    ProcNamedGP[procIdx] := ngpNamed;
    ProcNamedFP[procIdx] := nfpNamed;
  end;
  for i := 0 to nparams - 1 do
    ProcParamPtrDepth[procIdx * MAX_PROC_PARAMS + i] := pdepths[i];
  ProcRetPtrElemTk[procIdx] := retPtrElemTk;
  ProcRetPtrElemRec[procIdx] := retPtrElemRec;
  if retProcSig >= 0 then ProcRetProcSig[procIdx] := retProcSig;
  if retType = tyRecord then ProcRetRecId[procIdx] := retRecId;

  { If it is just a declaration (ends with ';'), we are done! }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkBegin) and
        (CurTok.Kind <> tkEOF) do Next;
  if CurTok.Kind = tkSemicolon then
  begin
    { Pure declaration (prototype). Mark external EXCEPT in a C-program pass 2,
      where pass 1 already settled linkage (a prototype + a later local
      definition => internal); re-marking here, before that definition is
      recompiled, would make an intervening caller emit an external call. Also
      EXCEPT when the name already resolves to a bodied proc (BodyAddr>=0): an
      auto-pulled Pascal unit (pxxcio's __pxx_write/__pxx_read) supplied the
      definition, so the C `extern` is just a forward view of it — keep it
      internal, not a dynamic libc import. }
    if (not (CProgramMode and not CHeaderMode)) and (Procs[procIdx].BodyAddr < 0) and
       (not CProcHasLocalDef[procIdx]) then
    begin
      ProcExternal[procIdx] := True;
      if CurrentCLibrary <> '' then ProcLibrary[procIdx] := InternStr(CurrentCLibrary)
      else ProcLibrary[procIdx] := InternStr(extLib);   { libm for math, else libc }
    end;
    Next;
    Exit;
  end;

  if paramsOverflow then
    Error('C function definition: more than 16 parameters not supported (MAX_PROC_PARAMS)');

  if CHeaderMode then
  begin
    { A bodied function in a C program is a local definition compiled in pass 2;
      mark it internal now so a caller compiled earlier emits a fixup (internal)
      call, not an external one. In true header-import mode bodies stay external. }
    if CProgramMode then
    begin
      { Record that a real in-TU definition exists so a later redundant prototype
        (a guardless header re-included by sibling .c files, e.g. zlib's gzguts.h)
        cannot flip it back to external — which would make the pass-2 forward call
        a dynamic import instead of an internal fixup. }
      ProcExternal[procIdx] := False;
      CProcHasLocalDef[procIdx] := True;
    end
    else
    begin
      ProcExternal[procIdx] := True;
      if CurrentCLibrary <> '' then ProcLibrary[procIdx] := InternStr(CurrentCLibrary)
      else ProcLibrary[procIdx] := InternStr(extLib);
    end;
    SkipBraceBlock;
    Exit;
  end;
  
  { Otherwise, it has a body! }
  ProcExternal[procIdx] := False;
  CProcHasLocalDef[procIdx] := True;
  Procs[procIdx].BodyAddr := CodeLen;
  
  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  { Reset the goto-label table per function (C labels are registered inline as
    `label:` is parsed; names are function-scoped). }
  GotoLabelCount := 0;
  GotoFixupCount := 0;
  for gli := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[gli] := -1;
  Procs[procIdx].ScopeBase := SymCount;
  
  { Allocate parameter slots }
  for i := 0 to nparams-1 do
  begin
    { A C record param is by-value but passed via the by-ref ABI (an 8-byte
      pointer slot the callee derefs); the caller copies the record to a temp and
      passes &temp (IRLowerCallArg), giving true by-value with correct field
      access for records of ANY size (the inline 8-byte slot could not hold >8B). }
    if ptypes[i] = tyRecord then
    begin
      LastTypeRecId := precid[i];
      idx := AllocParam(pnames[i], ptypes[i], True, False);
    end
    else
      idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    { Thread a pointer parameter's pointed-at type so `*p`, `p[i]`, and pointer
      arithmetic inside the body know the element stride/width. }
    if ptypes[i] = tyPointer then
    begin
      Syms[idx].PtrElemTk := IntToTypeKind(pelemtk[i]);
      Syms[idx].PtrElemRec := pelemrec[i];
      SymPtrDepth[idx] := pdepths[i];
      SymPtrBaseTk[idx] := pbasetk[i];
      SymPtrBaseRec[idx] := pbaserec[i];
      if pprocsig[i] >= 0 then SymProcSig[idx] := pprocsig[i];  { fn-pointer param: callable }
    end;
  end;
  
  { Return value slot }
  if retType = tyRecord then LastTypeRecId := retRecId;
  AllocVar('Result', retType);
  Procs[procIdx].RetSymIdx := SymCount - 1;
  Syms[SymCount-1].Kind := skLocal;

  { Aggregate (struct/union by value) return: allocate the hidden destination
    pointer local, exactly like a Pascal record-returning routine. The prologue
    stashes the caller's dest pointer here (EmitAggregateDestStash) and the
    epilogue copies Result into it; the caller's cdecl call path loads it into
    the indirect-result register. Without this a by-value struct/union return
    (lua's TValue union) wrote Result to a garbage pointer and segfaulted. }
  if TypeIsAggregate(retType) then
    ProcAggregateDestSym[procIdx] := AllocVar('', tyPointer);

  { Variadic: reserve a 176-byte register-save area as a hidden local `__va_save`
    plus `__va_overflow`, the caller stack overflow pointer. The prologue stores
    incoming GP+XMM arg registers in __va_save and rbp+16 in __va_overflow. }
  vaSaveSym := -1;
  vaOverflowSym := -1;
  if ProcVariadic[procIdx] then
  begin
    vaSaveRec := FindCTag('__pxx_va_save');
    if vaSaveRec >= 0 then
    begin
      LastTypeRecId := vaSaveRec;
      vaSaveSym := AllocVar('__va_save', tyRecord);
      vaOverflowSym := AllocVar('__va_overflow', tyPointer);
    end;
  end;

  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);

  { Variadic register-save prologue: store the incoming argument registers into
    __va_save so va_arg can read the variadic tail. Registers are still pristine
    here (the param copy below only reads them). Additive + gated to variadic
    functions, so non-variadic / Pascal codegen is unchanged. Per-target: SysV
    x86-64 saves 6 GP + 8 XMM (two classes); aarch64 saves x0..x7 as one 8-byte
    GP area (the pxx value model carries floats as GP bits). }
  if vaSaveSym >= 0 then
  begin
    case TargetArch of
    TARGET_X86_64:
    begin
      { overflow_arg_area starts PAST any stack-spilled NAMED params (7th+ GP /
        9th+ FP arg, 8 bytes each) — with e.g. 7 named ints the 7th sits at
        [rbp+16] and the variadic tail begins at [rbp+24]. Anchoring at a flat
        rbp+16 made va_arg re-read the spilled named params as variadic ones
        (bug-c-vararg-vastart-named-fp-stack, the overflow-area half). }
      sz := 0;
      if ProcNamedGP[procIdx] > 6 then sz := (ProcNamedGP[procIdx] - 6) * 8;
      if ProcNamedFP[procIdx] > 8 then sz := sz + (ProcNamedFP[procIdx] - 8) * 8;
      EmitB($48); EmitB($8D); EmitB($85); EmitI32(16 + sz);                     { lea rax, [rbp+16+namedSpill] }
      EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[vaOverflowSym].Offset);   { mov [rbp+o], rax }
      EmitB($48); EmitB($89); EmitB($BD); EmitI32(Syms[vaSaveSym].Offset + 0);    { mov [rbp+o], rdi }
      EmitB($48); EmitB($89); EmitB($B5); EmitI32(Syms[vaSaveSym].Offset + 8);    { rsi }
      EmitB($48); EmitB($89); EmitB($95); EmitI32(Syms[vaSaveSym].Offset + 16);   { rdx }
      EmitB($48); EmitB($89); EmitB($8D); EmitI32(Syms[vaSaveSym].Offset + 24);   { rcx }
      EmitB($4C); EmitB($89); EmitB($85); EmitI32(Syms[vaSaveSym].Offset + 32);   { r8 }
      EmitB($4C); EmitB($89); EmitB($8D); EmitI32(Syms[vaSaveSym].Offset + 40);   { r9 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[vaSaveSym].Offset + 48);   { movsd [rbp+o], xmm0 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($8D); EmitI32(Syms[vaSaveSym].Offset + 64);   { xmm1 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($95); EmitI32(Syms[vaSaveSym].Offset + 80);   { xmm2 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($9D); EmitI32(Syms[vaSaveSym].Offset + 96);   { xmm3 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($A5); EmitI32(Syms[vaSaveSym].Offset + 112);  { xmm4 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($AD); EmitI32(Syms[vaSaveSym].Offset + 128);  { xmm5 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($B5); EmitI32(Syms[vaSaveSym].Offset + 144);  { xmm6 }
      EmitB($F2); EmitB($0F); EmitB($11); EmitB($BD); EmitI32(Syms[vaSaveSym].Offset + 160);  { xmm7 }
    end;
    TARGET_AARCH64:
    begin
      { AAPCS64: x0..x7 hold the first 8 args (named + variadic), floats included
        as GP bits. Save them into __va_save[0..56] (one 8-byte slot each). The
        overflow area is the caller stack args just above the frame: [x29+16],
        pushed past any named args that spilled there (namedTotal>8). }
      EmitLoadImmA64(9, Syms[vaSaveSym].Offset);
      EmitI32($8B0903A9);                                { add x9, x29, x9 (&__va_save) }
      EmitI32($F9000120);                                { str x0, [x9, #0] }
      EmitI32($F9000521);                                { str x1, [x9, #8] }
      EmitI32($F9000922);                                { str x2, [x9, #16] }
      EmitI32($F9000D23);                                { str x3, [x9, #24] }
      EmitI32($F9001124);                                { str x4, [x9, #32] }
      EmitI32($F9001525);                                { str x5, [x9, #40] }
      EmitI32($F9001926);                                { str x6, [x9, #48] }
      EmitI32($F9001D27);                                { str x7, [x9, #56] }
      sz := 16;
      if ProcNamedGP[procIdx] + ProcNamedFP[procIdx] > 8 then
        sz := 16 + (ProcNamedGP[procIdx] + ProcNamedFP[procIdx] - 8) * 8;
      EmitLoadImmA64(10, sz);
      EmitI32($8B0A03AA);                                { add x10, x29, x10 (overflow) }
      EmitLoadImmA64(9, Syms[vaOverflowSym].Offset);
      EmitI32($8B0903A9);                                { add x9, x29, x9 }
      EmitI32($F900012A);                                { str x10, [x9, #0] }
    end;
    TARGET_RISCV32:
    begin
      { RV32: the first 8 argument words arrive in a0..a7 (named + variadic, one
        word each; a by-value i64/double spans two). Save all 8 into __va_save
        (32 bytes, 4-byte slots). va_arg walks that reg area (size 32, seeded in
        fp_offset) then the overflow. Overflow points at the first caller stack
        word [s0+8] (used only when the total exceeds 8 words). }
      EmitLoadImmRISCV32(reg_t0, Syms[vaSaveSym].Offset);
      rv32_add(reg_t0, reg_s0, reg_t0);                  { t0 = &__va_save }
      rv32_sw(reg_a0, reg_t0, 0);
      rv32_sw(reg_a0 + 1, reg_t0, 4);
      rv32_sw(reg_a0 + 2, reg_t0, 8);
      rv32_sw(reg_a0 + 3, reg_t0, 12);
      rv32_sw(reg_a0 + 4, reg_t0, 16);
      rv32_sw(reg_a0 + 5, reg_t0, 20);
      rv32_sw(reg_a0 + 6, reg_t0, 24);
      rv32_sw(reg_a0 + 7, reg_t0, 28);
      { Overflow (stack args past a7) starts at entry_sp = s0+16 — the callee's
        incoming-stack-word base after the ra/s0 prologue (see parser.inc rv32
        param spill: word k>=8 at [s0+16+(pnWords-1-k)*4]). The call site reverses
        the variadic stack tail (ir_codegen_riscv32.inc) so word 8 lands at s0+16
        and va_arg's forward walk reads args in order. Was s0+8 — off by 8, so the
        first stack-passed variadic arg read a saved-frame word (garbage). }
      EmitLoadImmRISCV32(reg_t1, 16);
      rv32_add(reg_t1, reg_s0, reg_t1);                  { t1 = s0+16 (first stack word) }
      EmitLoadImmRISCV32(reg_t0, Syms[vaOverflowSym].Offset);
      rv32_add(reg_t0, reg_s0, reg_t0);                  { t0 = &__va_overflow }
      rv32_sw(reg_t1, reg_t0, 0);                        { *__va_overflow = s0+16 }
    end;
    TARGET_I386:
    begin
      { i386 cdecl: NO argument registers — every arg is on the caller stack.
        The reg area is empty (size 0, seeded in fp_offset), so va_arg reads only
        the overflow. A variadic call pushes ALL args in forward order (arg0 at
        [ebp+8]); the named params occupy the low `namedBytes`, so the first
        variadic arg (overflow anchor) is at [ebp+8+namedBytes]. No register save. }
      sz := 0;
      for i := 0 to nparams - 1 do
        if ((ptypes[i] = tyDouble) or (ptypes[i] = tyInt64) or (ptypes[i] = tyUInt64)) and
           (not Syms[Procs[procIdx].Params[i].SymIdx].IsRef) and
           (not Syms[Procs[procIdx].Params[i].SymIdx].IsArray) then
          Inc(sz, 8)
        else
          Inc(sz, 4);
      EmitB($8D); EmitB($85); EmitI32(8 + sz);                    { lea eax, [ebp+8+namedBytes] }
      EmitB($89); EmitB($85); EmitI32(Syms[vaOverflowSym].Offset); { mov [ebp+o], eax }
    end;
    TARGET_ARM32:
    begin
      { AAPCS32: r0..r3 hold the first 4 argument words (named + variadic, one
        word each; a by-value i64/double spans two). Save them into __va_save
        [0..12] (16-byte reg area, 4-byte slots). va_arg walks that area (size 16,
        seeded in fp_offset) then the overflow. Overflow points at the first
        caller stack word [fp+8] (used only when the total exceeds 4 words). }
      EmitLoadImmArm32(9, Syms[vaSaveSym].Offset);
      EmitI32($E08B9009);                                { add r9, fp, r9 (&__va_save) }
      EmitI32($E5890000);                                { str r0, [r9, #0] }
      EmitI32($E5891004);                                { str r1, [r9, #4] }
      EmitI32($E5892008);                                { str r2, [r9, #8] }
      EmitI32($E589300C);                                { str r3, [r9, #12] }
      { Use r12 (ip) scratch for fp+8 — NOT an arg register: the param-copy below
        still reads the incoming args from r0..r3 (clobbering r0 here corrupted
        the first named param). }
      EmitI32($E28BC008);                                { add r12, fp, #8 (first stack word) }
      EmitLoadImmArm32(9, Syms[vaOverflowSym].Offset);
      EmitI32($E08B9009);                                { add r9, fp, r9 (&__va_overflow) }
      EmitI32($E589C000);                                { str r12, [r9, #0] }
    end;
    else
      Error('variadic C functions (va_arg) are not yet supported on this cross target');
    end;
  end;

  if TargetArch = TARGET_I386 then
  begin
    { i386: C cdecl args are pushed on the stack (NOT in registers as on x86-64).
      The i386 call site pushes them left-to-right (leftmost ends up deepest), so
      param i of n sits at [ebp + 8 + sz] where sz = the total stack width of the
      params to its right. Copy each into its frame slot; the caller cleans the
      arg area. Mirrors the Pascal i386 param spill (parser.inc). int/ptr =
      4-byte slots, double/Int64 = 8-byte. }
    for i := 0 to nparams - 1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := 0;
      { Non-variadic: reversed push (leftmost deepest) -> param i is above the
        params to its RIGHT, so disp = width of params i+1..n-1. Variadic: the
        call site pushes ALL args forward (arg0 at [ebp+8]), so disp = width of
        the params to its LEFT (0..i-1). }
      if ProcVariadic[procIdx] then
      begin
        for j := 0 to i - 1 do
        begin
          if Syms[Procs[procIdx].Params[j].SymIdx].IsRef then Inc(sz, 4)
          else if (ptypes[j] = tyDouble) or (ptypes[j] = tyInt64) or (ptypes[j] = tyUInt64) then Inc(sz, 8)
          else Inc(sz, 4);
        end;
      end
      else
      for j := i + 1 to nparams - 1 do
      begin
        if Syms[Procs[procIdx].Params[j].SymIdx].IsRef then Inc(sz, 4)
        else if (ptypes[j] = tyDouble) or (ptypes[j] = tyInt64) or (ptypes[j] = tyUInt64) then Inc(sz, 8)
        else Inc(sz, 4);
      end;
      if (not Syms[idx].IsRef) and
         ((ptypes[i] = tyDouble) or (ptypes[i] = tyInt64) or (ptypes[i] = tyUInt64)) then
      begin
        EmitB($8B); EmitB($85); EmitI32(8 + sz);                  { mov eax, [ebp+disp] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset);        { mov [ebp+off], eax }
        EmitB($8B); EmitB($85); EmitI32(12 + sz);                 { mov eax, [ebp+disp+4] }
        EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset + 4);    { mov [ebp+off+4], eax }
      end
      else
      begin
        EmitB($8B); EmitB($85); EmitI32(8 + sz);                  { mov eax, [ebp+disp] }
        if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
           not (Syms[idx].TypeKind in [tyPointer, tyString, tyAnsiString, tyClass]) and
           (TypeSize(Syms[idx].TypeKind) = 1) then
          begin EmitB($88); EmitB($85); EmitI32(Syms[idx].Offset); end          { mov [ebp+off], al }
        else if (not Syms[idx].IsRef) and (not Syms[idx].IsArray) and
           not (Syms[idx].TypeKind in [tyPointer, tyString, tyAnsiString, tyClass]) and
           (TypeSize(Syms[idx].TypeKind) = 2) then
          begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end { mov [ebp+off], ax }
        else
          begin EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;          { mov [ebp+off], eax }
      end;
    end;
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { arm32 word-based spill (mirrors the Pascal arm32 path in parser.inc): each
      scalar param is one machine word, a by-value Int64/UInt64/Double is two
      (lo then hi). Word k arrives in r[k] when k<4, else on the stack at
      [fp + 8 + (pnWords-1-k)*4] (the caller pushed words in index order). }
    pnWordsA := 0;
    for i := 0 to nparams - 1 do
      if ((ptypes[i] = tyInt64) or (ptypes[i] = tyUInt64) or (ptypes[i] = tyDouble)) and
         (not Syms[Procs[procIdx].Params[i].SymIdx].IsRef) and
         (not Syms[Procs[procIdx].Params[i].SymIdx].IsArray) then
        Inc(pnWordsA, 2)
      else Inc(pnWordsA, 1);
    pwA := 0;
    for i := 0 to nparams - 1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitLoadImmArm32(9, Syms[idx].Offset);
      EmitI32($E08B9009);   { add r9, fp, r9 (slot addr) }
      if ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64) or
          (Syms[idx].TypeKind = tyDouble)) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        if pwA < 4 then EmitI32($E5890000 or (pwA shl 12))
        else begin EmitI32($E59B0000 or (8 + (pnWordsA-1-pwA)*4)); EmitI32($E5890000); end;
        whiA := pwA + 1;
        if whiA < 4 then EmitI32($E5890004 or (whiA shl 12))
        else begin EmitI32($E59B0000 or (8 + (pnWordsA-1-whiA)*4)); EmitI32($E5890004); end;
        Inc(pwA, 2);
      end
      else
      begin
        if pwA < 4 then
        begin
          if sz = 1 then EmitI32($E5C90000 or (pwA shl 12))        { strb r[pw], [r9] }
          else if sz = 2 then EmitI32($E1C900B0 or (pwA shl 12))   { strh r[pw], [r9] }
          else EmitI32($E5890000 or (pwA shl 12));                 { str r[pw], [r9] }
        end
        else
        begin
          EmitI32($E59B0000 or (8 + (pnWordsA - 1 - pwA) * 4));    { ldr r0, [fp, #off] }
          if sz = 1 then EmitI32($E5C90000)
          else if sz = 2 then EmitI32($E1C900B0)
          else EmitI32($E5890000);
        end;
        Inc(pwA, 1);
      end;
    end;
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    { aarch64 (AAPCS64), mirrors the Pascal aarch64 spill: params 0..7 arrive in
      x0..x7, the rest on the stack at [x29 + 16 + (i-8)*8]. Copy each into its
      frame slot. Single by-value arrives as double bits (value model). }
    for i := 0 to nparams - 1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      if i < 8 then
      begin
        EmitLoadImmA64(9, Syms[idx].Offset);
        EmitI32($8B0903A8);              { add x8, x29, x9 (slot addr) }
        if (Syms[idx].TypeKind = tySingle) and
           (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
        begin
          EmitI32($9E670000 + (i shl 5));  { fmov d0, x[i] }
          EmitI32($1E624000);              { fcvt s0, d0 }
          EmitI32($BD000100);              { str s0, [x8] }
        end
        else if sz = 1 then EmitI32($39000100 + i)   { strb w[i], [x8] }
        else if sz = 2 then EmitI32($79000100 + i)   { strh w[i], [x8] }
        else if sz = 4 then EmitI32($B9000100 + i)   { str w[i], [x8] }
        else EmitI32($F9000100 + i);                 { str x[i], [x8] }
      end
      else
      begin
        EmitLoadImmA64(9, 16 + (i - 8) * 8);
        EmitI32($8B0903A8);              { add x8, x29, x9 -> &incoming arg }
        EmitI32($F9400109);              { ldr x9, [x8] }
        EmitLoadImmA64(10, Syms[idx].Offset);
        EmitI32($8B0A03A8);              { add x8, x29, x10 -> &local slot }
        if sz = 1 then EmitI32($39000109)
        else if sz = 2 then EmitI32($79000109)
        else if sz = 4 then EmitI32($B9000109)
        else EmitI32($F9000109);
      end;
    end;
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { RV32 word-based (mirrors the Pascal riscv32 spill in parser.inc): args
      arrive in a0..a7 (word k in a[k]); scalar = 1 word, by-value
      Int64/UInt64/Double = 2 (lo then hi). Words 8+ stay on the CALLER's stack
      (the IR_CALL site keeps the whole pushed block live when the total exceeds
      8): word k>=8 sits at [entry_sp + (pnWords-1-k)*4] = [s0 + 16 +
      (pnWords-1-k)*4] after the ra/s0 prologue. }
    pnWordsA := 0;
    for i := 0 to nparams - 1 do
      if ((Procs[procIdx].Params[i].TypeKind = tyInt64) or
          (Procs[procIdx].Params[i].TypeKind = tyUInt64) or
          (Procs[procIdx].Params[i].TypeKind = tyDouble)) and
         (not Syms[Procs[procIdx].Params[i].SymIdx].IsRef) and
         (not Syms[Procs[procIdx].Params[i].SymIdx].IsArray) then
        Inc(pnWordsA, 2)
      else
        Inc(pnWordsA, 1);
    pwA := 0;
    for i := 0 to nparams - 1 do
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      sz := ParamSize(idx);
      EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
      rv32_add(reg_t0, reg_s0, reg_t0);   { t0 = &slot }
      if ((Syms[idx].TypeKind = tyInt64) or (Syms[idx].TypeKind = tyUInt64) or
          (Syms[idx].TypeKind = tyDouble)) and
         (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
      begin
        if pwA < 8 then
          rv32_sw(reg_a0 + pwA, reg_t0, 0)                 { lo (word pw) }
        else
        begin
          rv32_lw(reg_t1, reg_s0, 16 + (pnWordsA - 1 - pwA) * 4);
          rv32_sw(reg_t1, reg_t0, 0);
        end;
        if pwA + 1 < 8 then
          rv32_sw(reg_a0 + pwA + 1, reg_t0, 4)             { hi (word pw+1) }
        else
        begin
          rv32_lw(reg_t1, reg_s0, 16 + (pnWordsA - 1 - (pwA + 1)) * 4);
          rv32_sw(reg_t1, reg_t0, 4);
        end;
        Inc(pwA, 2);
      end
      else
      begin
        if pwA < 8 then
        begin
          if sz = 1 then rv32_sb(reg_a0 + pwA, reg_t0, 0)
          else if sz = 2 then rv32_sh(reg_a0 + pwA, reg_t0, 0)
          else rv32_sw(reg_a0 + pwA, reg_t0, 0);
        end
        else
        begin
          rv32_lw(reg_t1, reg_s0, 16 + (pnWordsA - 1 - pwA) * 4);
          if sz = 1 then rv32_sb(reg_t1, reg_t0, 0)
          else if sz = 2 then rv32_sh(reg_t1, reg_t0, 0)
          else rv32_sw(reg_t1, reg_t0, 0);
        end;
        Inc(pwA, 1);
      end;
    end;
  end
  else
  begin
  { Copy SysV argument locations to local parameter slots. Integer and SSE
    classes have independent register counts; overflow args are 8-byte stack
    slots starting at [rbp+16]. }
  intIdx := 0;
  sseIdx := 0;
  stackOff := 16;
  for i := 0 to nparams-1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    sz := ParamSize(idx);
    if TypeIsFloat(ptypes[i]) and (not Syms[idx].IsRef) and (not Syms[idx].IsArray) then
    begin
      if sseIdx < 8 then
      begin
        if ptypes[i] = tySingle then EmitB($F3) else EmitB($F2);
        EmitB($0F); EmitB($11);
        case sseIdx of
          0: EmitB($85);
          1: EmitB($8D);
          2: EmitB($95);
          3: EmitB($9D);
          4: EmitB($A5);
          5: EmitB($AD);
          6: EmitB($B5);
          7: EmitB($BD);
        end;
        EmitI32(Syms[idx].Offset);
        Inc(sseIdx);
        Continue;
      end
      else
      begin
        EmitB($48); EmitB($8B); EmitB($85); EmitI32(stackOff); { mov rax, [rbp+stackOff] }
        Inc(stackOff, 8);
        if ptypes[i] = tySingle then
        begin
          EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
          EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);             { cvtsd2ss xmm0, xmm0 }
          EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); { movss [rbp+off], xmm0 }
          Continue;
        end;
        { Stack-spilled DOUBLE named param (9th+ FP arg): store the loaded
          bits. This was missing — control fell through into the integer
          register-homing code below and the slot kept garbage/zero
          (bug-c-vararg-vastart-named-fp-stack, the named-param half). }
        EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); { mov [rbp+off], rax }
        Continue;
      end;
    end
    else if intIdx >= 6 then
    begin
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(stackOff); { mov rax, [rbp+stackOff] }
      Inc(stackOff, 8);
      if sz = 1 then
      begin
        EmitB($88); EmitB($85);                   { mov [rbp+off], al }
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89); EmitB($85);       { mov [rbp+off], ax }
      end
      else if sz = 4 then
      begin
        EmitB($89); EmitB($85);                   { mov [rbp+off], eax }
      end
      else
      begin
        EmitB($48); EmitB($89); EmitB($85);       { mov [rbp+off], rax }
      end;
      EmitI32(Syms[idx].Offset);
      Continue;
    end;

    if intIdx < 4 then
    begin
      if sz = 1 then
      begin
        if (intIdx = 0) or (intIdx = 1) then EmitB($40); { REX prefix for dil, sil }
        EmitB($88);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89);
      end
      else if sz = 4 then
      begin
        EmitB($89);
      end
      else
      begin
        EmitB($48); EmitB($89);
      end;

      case intIdx of
        0: EmitB($BD);   { rdi }
        1: EmitB($B5);   { rsi }
        2: EmitB($95);   { rdx }
        3: EmitB($8D);   { rcx }
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if intIdx = 4 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($85);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($85);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($85);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($85);
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if intIdx = 5 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($8D);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($8D);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($8D);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($8D);
      end;
      EmitI32(Syms[idx].Offset);
    end;
    Inc(intIdx);
  end;
  end;  { end of x86-64 param-spill else-branch }

  { Constant global initializers (struct/union brace inits recorded as PendingInit
    during pass 1) run once at the start of `main`, before user code — the C
    analogue of the Pascal program's pre-body CompilePendingGlobalInits. }
  if name = 'main' then
  begin
    CompilePendingGlobalInits;
    CEmitDeferredCAggInits;
  end;

  { Parse & Compile Body }
  node := ParseCBlockAST;
  CompileAST(node);

  { Epilogue }
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  
  { Restore scope }
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

{ Consume a balanced brace-delimited block. CurTok must be at the opening
  tkBegin; on return CurTok is just past the matching closing brace. }
procedure SkipBraceBlock;
var depth: Integer;
begin
  depth := 0;
  repeat
    if CurTok.Kind = tkBegin then Inc(depth)
    else if CurTok.Kind = tkEnd then Dec(depth);
    Next;
  until (depth = 0) or (CurTok.Kind = tkEOF);
end;

{ Integer constant-expression evaluator for enum values. Operates on the live
  C token stream. Since Slice A the C lexer emits distinct operator tokens:
  `<<`=tkShl, `>>`=tkShr, `|`=tkPipe, `^`=tkXor, `&`=tkAmp.
  Precedence, low to high: | , ^ , & , << >> , + - , * , unary , primary.
  Unknown/unsupported tokens evaluate to 0 rather than derailing.
  (CEvalConstExpr is forward-declared at the top of the C parser.) }

function CEvalConstOffsetofAddress: Int64;
var parenDepth, recId: Integer;
    fieldName, savedFnPtrName: AnsiString;
    savedIsVoid, savedFnRetIsFunc: Boolean;
    savedPtrDepth, savedElemTk, savedElemRec, savedPtrBaseTk, savedPtrBaseRec: Integer;
    savedBaseRec, savedProcSig, savedFnPtrNameOff, savedFnPtrNameLen: Integer;
    savedFnRetParamCount: Integer;
begin
  Result := 0;
  recId := REC_NONE;
  parenDepth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkLParen then
    begin
      Next;
      Inc(parenDepth);
      if IsCTypeTok then
      begin
        savedIsVoid := CTypeIsVoid;
        savedPtrDepth := CTypePtrDepth;
        savedElemTk := CTypeElemTk;
        savedElemRec := CTypeElemRec;
        savedPtrBaseTk := CTypePtrBaseTk;
        savedPtrBaseRec := CTypePtrBaseRec;
        savedBaseRec := CTypeBaseRec;
        savedProcSig := CTypeProcSig;
        savedFnPtrName := CTypeFnPtrName;
        savedFnPtrNameOff := CTypeFnPtrNameOff;
        savedFnPtrNameLen := CTypeFnPtrNameLen;
        savedFnRetIsFunc := CTypeFnRetIsFunc;
        savedFnRetParamCount := CTypeFnRetParamCount;
        ParseCDeclType;
        recId := CTypeBaseRec;
        CTypeIsVoid := savedIsVoid;
        CTypePtrDepth := savedPtrDepth;
        CTypeElemTk := savedElemTk;
        CTypeElemRec := savedElemRec;
        CTypePtrBaseTk := savedPtrBaseTk;
        CTypePtrBaseRec := savedPtrBaseRec;
        CTypeBaseRec := savedBaseRec;
        CTypeProcSig := savedProcSig;
        CTypeFnPtrName := savedFnPtrName;
        CTypeFnPtrNameOff := savedFnPtrNameOff;
        CTypeFnPtrNameLen := savedFnPtrNameLen;
        CTypeFnRetIsFunc := savedFnRetIsFunc;
        CTypeFnRetParamCount := savedFnRetParamCount;
        if CurTok.Kind = tkRParen then
        begin
          Next;
          Dec(parenDepth);
        end;
      end;
    end
    else if CurTok.Kind = tkRParen then
    begin
      if parenDepth > 0 then Dec(parenDepth);
      Next;
    end
    else if CurTok.Kind = tkDot then
    begin
      Next;
      if CurTok.Kind = tkIdent then
      begin
        fieldName := CurTok.SVal;
        if recId <> REC_NONE then Result := RecFieldOffset(recId, fieldName);
        Next;
      end;
      while (parenDepth > 0) and (CurTok.Kind = tkRParen) do
      begin
        Dec(parenDepth);
        Next;
      end;
      Exit;
    end
    else
      Next;
  end;
end;

function CEvalConstPrimary: Int64;
var idx: Integer;
begin
  Result := 0;
  if CurTok.Kind = tkLParen then
  begin
    Next;
    if IsCTypeTok then
    begin
      { cast `(type)expr` in a constant expression — the integer value is
        unchanged for const-folding (lua's cast_int(...) = ((int)(...))). Skip the
        cast type tokens to the matching `)`, then fold the operand. NOTE the `()`
        on the recursive call: bare `CEvalConstPrimary` would read this function's
        own Result, not recurse. }
      while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
      if CurTok.Kind = tkRParen then Next;
      Result := CEvalConstPrimary();
    end
    else
    begin
      Result := CEvalConstExpr;
      if CurTok.Kind = tkRParen then Next;
    end;
  end
  else if CurTok.Kind = tkMinus then begin Next; Result := -CEvalConstPrimary(); end
  else if CurTok.Kind = tkPlus then begin Next; Result := CEvalConstPrimary(); end
  else if CurTok.Kind = tkNot then begin Next; Result := CEvalConstPrimary() xor (-1); end  { ~ : bitwise NOT (xor -1 sidesteps the `not <call>`=boolean typing quirk) }
  else if CurTok.Kind = tkAmp then begin Next; Result := CEvalConstOffsetofAddress(); end
  else if CurTok.Kind = tkInteger then begin Result := CurTok.IVal; Next; end
  else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'sizeof') then
    { `sizeof(type|expr)` in a constant expression (e.g. array dimension
      `char b[3 * sizeof(size_t)]`). Reuse the value-form folder. }
    Result := ASTIVal[ParseCSizeof]
  else if CurTok.Kind = tkIdent then
  begin
    idx := FindSym(CurTok.SVal);
    if (idx >= 0) and (Syms[idx].Kind = skConst) then Result := Syms[idx].ConstVal;
    Next;
  end;
end;

function CEvalConstMul: Int64;
var rhs: Int64;
begin
  Result := CEvalConstPrimary;
  while (CurTok.Kind = tkStar) or (CurTok.Kind = tkSlash) or (CurTok.Kind = tkMod) do
  begin
    if CurTok.Kind = tkStar then begin Next; Result := Result * CEvalConstPrimary; end
    else if CurTok.Kind = tkSlash then
    begin
      Next; rhs := CEvalConstPrimary;
      if rhs <> 0 then Result := Result div rhs else Result := 0;   { e.g. sizeof(a)/sizeof(a[0]) }
    end
    else
    begin
      Next; rhs := CEvalConstPrimary;
      if rhs <> 0 then Result := Result mod rhs else Result := 0;
    end;
  end;
end;

function CEvalConstAdd: Int64;
begin
  Result := CEvalConstMul;
  while (CurTok.Kind = tkPlus) or (CurTok.Kind = tkMinus) do
  begin
    if CurTok.Kind = tkPlus then begin Next; Result := Result + CEvalConstMul; end
    else begin Next; Result := Result - CEvalConstMul; end;
  end;
end;

function CEvalConstShift: Int64;
begin
  Result := CEvalConstAdd;
  while (CurTok.Kind = tkShl) or (CurTok.Kind = tkShr) do
  begin
    if CurTok.Kind = tkShl then begin Next; Result := Result shl CEvalConstAdd; end
    else begin Next; Result := Result shr CEvalConstAdd; end;
  end;
end;

function CEvalConstRelational: Int64;
var r: Int64;
begin
  Result := CEvalConstShift;
  while (CurTok.Kind = tkLt) or (CurTok.Kind = tkLe) or
        (CurTok.Kind = tkGt) or (CurTok.Kind = tkGe) do
  begin
    if CurTok.Kind = tkLt then begin Next; r := CEvalConstShift; if Result < r then Result := 1 else Result := 0; end
    else if CurTok.Kind = tkLe then begin Next; r := CEvalConstShift; if Result <= r then Result := 1 else Result := 0; end
    else if CurTok.Kind = tkGt then begin Next; r := CEvalConstShift; if Result > r then Result := 1 else Result := 0; end
    else begin Next; r := CEvalConstShift; if Result >= r then Result := 1 else Result := 0; end;
  end;
end;

function CEvalConstEquality: Int64;
var r: Int64;
begin
  Result := CEvalConstRelational;
  while (CurTok.Kind = tkEq) or (CurTok.Kind = tkNeq) do
  begin
    if CurTok.Kind = tkEq then begin Next; r := CEvalConstRelational; if Result = r then Result := 1 else Result := 0; end
    else begin Next; r := CEvalConstRelational; if Result <> r then Result := 1 else Result := 0; end;
  end;
end;

function CEvalConstAnd: Int64;
begin
  Result := CEvalConstEquality;
  while CurTok.Kind = tkAmp do begin Next; Result := Result and CEvalConstEquality; end;
end;

function CEvalConstXor: Int64;
begin
  Result := CEvalConstAnd;
  while CurTok.Kind = tkXor do begin Next; Result := Result xor CEvalConstAnd; end;
end;

function CEvalConstBitOr: Int64;
begin
  Result := CEvalConstXor;
  while CurTok.Kind = tkPipe do begin Next; Result := Result or CEvalConstXor; end;
end;

function CEvalConstLogAnd: Int64;
var r: Int64;
begin
  Result := CEvalConstBitOr;
  while CurTok.Kind = tkAnd do   { `&&` (the C lexer maps && -> tkAnd) }
  begin
    Next; r := CEvalConstBitOr;
    if (Result <> 0) and (r <> 0) then Result := 1 else Result := 0;
  end;
end;

function CEvalConstLogOr: Int64;
var r: Int64;
begin
  Result := CEvalConstLogAnd;
  while CurTok.Kind = tkOr do    { `||` (the C lexer maps || -> tkOr) }
  begin
    Next; r := CEvalConstLogAnd;
    if (Result <> 0) or (r <> 0) then Result := 1 else Result := 0;
  end;
end;

function CEvalConstTernary: Int64;
var t, e: Int64;
begin
  Result := CEvalConstLogOr;
  if CurTok.Kind = tkQuestion then
  begin
    Next;
    t := CEvalConstExpr;            { then-branch is a full expression }
    if CurTok.Kind = tkColon then Next;
    e := CEvalConstExpr;            { else-branch }
    if Result <> 0 then Result := t else Result := e;
  end;
end;

function CEvalConstExpr: Int64;
begin
  { Full C constant-expression precedence: ?: , || , && , | , ^ , & , ==/!= ,
    </<=/>/>= , <</>> , +/- , */ /% , unary , primary. }
  Result := CEvalConstTernary;
end;

{ Parse an enumerator list. CurTok must be at the opening tkBegin (the brace).
  Registers each enumerator as an Int32 constant (auto-incrementing from 0,
  or from the last explicit value + 1). Leaves CurTok after the closing brace. }
procedure ParseCEnumBody;
var nextVal, val: Int64; nm: AnsiString;
begin
  Next; { consume the opening brace }
  nextVal := 0;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    if CurTok.Kind = tkIdent then
    begin
      nm := CurTok.SVal; Next;
      if CurTok.Kind = tkAssign then { an = introduces an explicit value }
      begin
        Next;
        val := CEvalConstExpr;
      end
      else
        val := nextVal;
      AddConst(nm, tyInt32, val);
      nextVal := val + 1;
      if CurTok.Kind = tkComma then Next;
    end
    else
      Next;
  end;
  if CurTok.Kind = tkEnd then Next; { consume the closing brace }
end;

{ Build an AnsiString from a span of the C preprocessor character pool. }
function CMacroPoolText(off, len: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 0 to len - 1 do AppendChar(Result, CPrepChars[off + i]);
end;

{ Surface object-like integer #define macros as Pascal constants, so a C
  header's `#define SQLITE_ROW 100` is usable by name instead of being a magic
  number hardcoded in every binding. Function-like macros, string/float/empty
  bodies, and bodies that are not a pure integer constant expression are
  skipped. The macro value text is lexed into the token stream and evaluated
  with the same CEvalConstExpr used for enum values; an identifier in the body
  is accepted only when it already resolves to a registered constant (so chains
  like `#define B (A+1)` work in definition order). Must run after ParseCUnit,
  while the C header's case-sensitive mode and unit index are still in effect,
  so the constants match the exact C spelling. }
procedure RegisterCMacroConsts;
var mi, vStart, vEnd, t, savedPos: Integer;
    name, valText: AnsiString;
    firstCh: Char; ok: Boolean; v: Int64; si: Integer;
begin
  mi := 0;
  while mi < CPMCount do
  begin
    if CPMFunction[mi] or (CPMNameLen[mi] <= 0) or (CPMValueLen[mi] <= 0) then
    begin
      Inc(mi);
      Continue;
    end;
    { Cheap text prefilter: a pure integer expression starts with a digit, an
      open paren, or a unary +/-. Rejects string/identifier bodies without
      lexing them, keeping the token stream from bloating on system headers. }
    firstCh := CPrepChars[CPMValueOff[mi]];
    if not ((firstCh in ['0'..'9']) or (firstCh = '(') or
            (firstCh = '+') or (firstCh = '-')) then
    begin
      Inc(mi);
      Continue;
    end;
    name := CMacroPoolText(CPMNameOff[mi], CPMNameLen[mi]);
    if FindSym(name) >= 0 then begin Inc(mi); Continue; end;  { don't clobber }

    valText := CMacroPoolText(CPMValueOff[mi], CPMValueLen[mi]);
    vStart := CLexAppend(valText);
    vEnd := vStart;
    while (vEnd < TokCount) and (Tokens[vEnd].Kind <> tkEOF) do Inc(vEnd);

    { Guard: every token must belong to a pure integer constant expression. }
    ok := vEnd > vStart;
    t := vStart;
    while t < vEnd do
    begin
      if (Tokens[t].Kind = tkInteger) or (Tokens[t].Kind = tkLParen) or
         (Tokens[t].Kind = tkRParen) or (Tokens[t].Kind = tkPlus) or
         (Tokens[t].Kind = tkMinus) or (Tokens[t].Kind = tkStar) or
         (Tokens[t].Kind = tkShl) or (Tokens[t].Kind = tkShr) or
         (Tokens[t].Kind = tkPipe) or (Tokens[t].Kind = tkAmp) or
         (Tokens[t].Kind = tkXor) or (Tokens[t].Kind = tkNot) then
        { allowed }
      else if Tokens[t].Kind = tkIdent then
      begin
        si := FindSym(GetTokenStr(t));
        if (si < 0) or (Syms[si].Kind <> skConst) then ok := False;
      end
      else
        ok := False;
      Inc(t);
    end;

    if ok then
    begin
      savedPos := TokPos;
      TokPos := vStart;
      Next;
      v := CEvalConstExpr;
      AddConst(name, tyInt32, v);
      TokPos := savedPos;
    end;
    Inc(mi);
  end;
end;

{ Conservatively decide whether a C struct/union body is laid out as a record.
  startIdx is the opening brace (tkBegin) token index. Returns False — meaning
  fall back to an opaque pointer — for any construct ParseCStructInto cannot lay
  out correctly, so it never produces silently-wrong field offsets:
    - bitfields (`name : n`): wrong offsets for following fields,
    - nested/anonymous struct or union bodies (a second brace),
    - struct/union/enum-tag-typed fields (`struct Foo bar;`): the field would be
      dropped, shifting offsets.
  Plain POD (scalars, pointers, fixed arrays, typedef-named-type fields incl.
  nested-struct-by-value) returns True. }
function CStructBodyIsSimple(startIdx: Integer): Boolean;
var i, depth, declStart: Integer;
begin
  Result := True;
  
  { Find the preceding struct/union/typedef keyword to start scanning for attributes }
  declStart := startIdx;
  while declStart > 0 do
  begin
    if Tokens[declStart].Kind = tkRecord then Break;
    if Tokens[declStart].Kind = tkIdent then
    begin
      if (GetTokenStrFromRaw(Tokens[declStart].SOffset, Tokens[declStart].SLen) = 'union') or
         (GetTokenStrFromRaw(Tokens[declStart].SOffset, Tokens[declStart].SLen) = 'typedef') then
        Break;
    end;
    Dec(declStart);
  end;

  { Reject only alignment attributes whose value was not parsed. Supported
    packed/aligned(N) attributes are applied by ParseCStructInto. }
  for i := declStart to startIdx - 1 do
  begin
    if ((CAttrFlags[i] and 2) <> 0) and (CAttrAlignValues[i] < 1) then
    begin
      Result := False;
      Exit;
    end;
  end;

  depth := 0;
  i := startIdx;
  while i < TokCount do
  begin
    if ((CAttrFlags[i] and 2) <> 0) and (CAttrAlignValues[i] < 1) then
    begin
      Result := False;
      Exit;
    end;

    if Tokens[i].Kind = tkBegin then
      Inc(depth)   { nested aggregate bodies are now laid out as sub-records }
    else if Tokens[i].Kind = tkEnd then
    begin
      Dec(depth);
      if depth <= 0 then
      begin
        { We reached the end of the body. Now scan past the body up to the terminating semicolon }
        Inc(i);
        while (i < TokCount) and (Tokens[i].Kind <> tkEOF) do
        begin
          if ((CAttrFlags[i] and 2) <> 0) and (CAttrAlignValues[i] < 1) then
          begin
            Result := False;
            Exit;
          end;
          if Tokens[i].Kind = tkSemicolon then
            Break;
          Inc(i);
        end;
        Exit;
      end;
    end
    else if depth >= 1 then
    begin
      { Named bit-fields `name : width` are now laid out (as a full storage unit
        per field — see ParseCStructInto), so they no longer force the opaque
        fallback. An ANONYMOUS bit-field (`T : width`, padding / `:0` alignment)
        has no name token before the colon and ParseCStructInto cannot model it,
        so still reject those. struct/union/enum keywords are OK as field types
        (`struct Tag *next`, `enum E e`) because ParseCDeclType resolves a tag
        reference; an INLINE anonymous aggregate body is rejected via the
        nested-brace check above. }
      if (Tokens[i].Kind = tkColon) and (Tokens[i-1].Kind <> tkIdent) then
        begin Result := False; Exit; end;
    end;
    Inc(i);
  end;
end;

function CAttrPackedInRange(lo, hi: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if lo < 0 then lo := 0;
  if hi >= TokCount then hi := TokCount - 1;
  for i := lo to hi do
    if (CAttrFlags[i] and 1) <> 0 then
    begin
      Result := True;
      Exit;
    end;
end;

function CAttrAlignInRange(lo, hi: Integer): Integer;
var i: Integer;
begin
  Result := 0;
  if lo < 0 then lo := 0;
  if hi >= TokCount then hi := TokCount - 1;
  for i := lo to hi do
    if ((CAttrFlags[i] and 2) <> 0) and (CAttrAlignValues[i] > Result) then
      Result := CAttrAlignValues[i];
end;

function CStructDeclStart(startIdx: Integer): Integer;
begin
  Result := startIdx;
  while Result > 0 do
  begin
    if Tokens[Result].Kind = tkRecord then Exit;
    if Tokens[Result].Kind = tkIdent then
    begin
      if (GetTokenStrFromRaw(Tokens[Result].SOffset, Tokens[Result].SLen) = 'union') or
         (GetTokenStrFromRaw(Tokens[Result].SOffset, Tokens[Result].SLen) = 'typedef') then
        Exit;
    end;
    Dec(Result);
  end;
end;

function CStructEndIndex(startIdx: Integer): Integer;
var i, depth: Integer;
begin
  Result := startIdx;
  depth := 0;
  i := startIdx;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then
    begin
      Dec(depth);
      if depth = 0 then
      begin
        Result := i;
        Exit;
      end;
    end;
    Inc(i);
  end;
end;

function CStructPostAttrEnd(endIdx: Integer): Integer;
begin
  Result := endIdx;
  while (Result < TokCount) and (Tokens[Result].Kind <> tkSemicolon) and
        (Tokens[Result].Kind <> tkEOF) do
    Inc(Result);
end;

{ Record alignment of a record id (struct field by value). }
function CRecAlign(rec: Integer): Integer;
begin
  if rec >= REC_UCLASS_BASE then Result := UClsAlign[rec - REC_UCLASS_BASE]
  else Result := TARGET_PTR_SIZE;
  if Result < 1 then Result := 1;
end;

{ Parse a C struct/union body into the user record `ci`. CurTok must be at the
  opening brace (tkBegin). Fills fields with C natural alignment (each field on
  its own alignment; struct align = max member align; size rounded up to that),
  and leaves CurTok past the closing brace (tkEnd). Unions lay every field at
  offset 0 with size = the largest member. Supported field shapes: scalars,
  pointers (any depth -> Pointer, element type/record recorded for deref),
  fixed arrays `T x[N]`, and nested struct-by-value. Bitfields (`x : n`) and
  inline anonymous struct definitions are skipped, not laid out. }
procedure ParseCStructInto(ci: Integer; isUnion: Boolean);
const MAX_BF = 256;
var
  curOff, maxAlign, fnOff, fnLen, arrLen, declStars, sz, al, totalSz, thisOff: Integer;
  baseScalarTk, baseElemTk, baseElemRec, baseRecId, declTk, declElemTk, declElemRec, declRec: Integer;
  fldProcSig, subci, subRecSz, subAl, sdepth, bfCount, k: Integer;
  fTk: TTypeKind;
  isArr, firstDecl, subIsUnion: Boolean;
  { The parent's fields are BUFFERED during the walk and appended to the shared
    UFld pool only AFTER the body (and any nested sub-records) are laid out, so the
    parent's fields stay contiguous — FindUField scans [base, base+count). Without
    this, a nested-aggregate member's sub-record fields would be inserted between
    the parent's fields and break the contiguous range. }
  bfNOff, bfNLen, bfOff, bfTk, bfRec, bfElemTk, bfElemRec, bfProcSig, bfArrLen: array[0..MAX_BF-1] of Integer;
  bfIsArr: array[0..MAX_BF-1] of Boolean;
  bfBitWidth, bfBitShift, bfBitBytes: array[0..MAX_BF-1] of Integer;
  bfNDims: array[0..MAX_BF-1] of Integer;
  bfDimSpan: array[0..MAX_BF*MAX_ARR_DIMS-1] of Integer;
  fldNDims, dimVal, ndi, bitWidth, bitUnitOff, bitUnitUsed, bitUnitSize, bitUnitAlign, bitBytes: Integer;
  startIdx, endIdx, declStartIdx, attrEndIdx, fieldStartIdx, fieldAlign, structAlign: Integer;
  isBitField, structPacked, fieldPacked: Boolean;
begin
  startIdx := TokPos - 1;
  endIdx := CStructEndIndex(startIdx);
  declStartIdx := CStructDeclStart(startIdx);
  structPacked := CAttrPackedInRange(declStartIdx, startIdx);
  structAlign := CAttrAlignInRange(declStartIdx, startIdx);
  attrEndIdx := CStructPostAttrEnd(endIdx);
  if CAttrPackedInRange(endIdx + 1, attrEndIdx) then structPacked := True;
  fieldAlign := CAttrAlignInRange(endIdx + 1, attrEndIdx);
  if fieldAlign > structAlign then structAlign := fieldAlign;

  Next; { consume the opening brace }
  curOff := 0;
  maxAlign := 1;
  bfCount := 0;
  bitUnitOff := -1; bitUnitUsed := 0; bitUnitSize := 0; bitUnitAlign := 1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    { Nested inline aggregate member: struct or union with an inline body followed
      by member name(s). Lay the body out as a sub-record (recursively) and buffer
      the member(s) as record-typed fields, so outer.name.member resolves (lua
      CallInfo / GCUnion). Detected by an opening brace right after the keyword,
      optionally past a tag. }
    if ((CurTok.Kind = tkRecord) or ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'))) and
       ((Tokens[TokPos].Kind = tkBegin) or
        ((Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkBegin))) then
    begin
      subIsUnion := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'union');
      Next;  { consume struct/union keyword }
      if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkBegin) then
      begin
        subci := FindOrForwardCTag(CurTok.SVal) - REC_UCLASS_BASE;  { inline-tagged }
        Next;
      end
      else if UClsCount < MAX_UCLASS - 1 then
      begin subci := AddUClass(0, 0); UClsIsRecord[subci] := True; end
      else
        subci := -1;
      if subci >= 0 then
        ParseCStructInto(subci, subIsUnion)
      else
      begin
        sdepth := 0;
        repeat
          if CurTok.Kind = tkBegin then Inc(sdepth)
          else if CurTok.Kind = tkEnd then Dec(sdepth);
          Next;
        until (sdepth = 0) or (CurTok.Kind = tkEOF);
      end;
      if subci >= 0 then begin subRecSz := UClsSize_[subci]; subAl := UClsAlign[subci]; end
      else begin subRecSz := TARGET_PTR_SIZE; subAl := TARGET_PTR_SIZE; end;
      if subAl < 1 then subAl := 1;
      bitUnitOff := -1; bitUnitUsed := 0; bitUnitSize := 0; bitUnitAlign := 1;
      repeat
        declStars := 0;
        while CurTok.Kind = tkStar do begin Inc(declStars); Next; end;
        if CurTok.Kind <> tkIdent then
        begin
          { ANONYMOUS aggregate member (no declarator, e.g. `union { int b1; };`):
            promote the sub-record's fields into THIS record at the member's
            offset (C11 6.7.2.1), so `v.b1` resolves directly. Composes
            recursively — a nested anon aggregate already promoted its own fields
            into subci. }
          if (subci >= 0) and (declStars = 0) then
          begin
            if isUnion then thisOff := 0 else thisOff := AlignTo(curOff, subAl);
            for k := 0 to UClsFCount[subci] - 1 do
              if bfCount < MAX_BF then
              begin
                bfNOff[bfCount]    := UFldNOff[UClsFBase[subci] + k];
                bfNLen[bfCount]    := UFldNLen[UClsFBase[subci] + k];
                bfOff[bfCount]     := thisOff + UFldOff_[UClsFBase[subci] + k];
                bfTk[bfCount]      := UFldTk[UClsFBase[subci] + k];
                bfRec[bfCount]     := UFldRec_[UClsFBase[subci] + k];
                bfElemTk[bfCount]  := UFldPtrElemTk[UClsFBase[subci] + k];
                bfElemRec[bfCount] := UFldPtrElemRec[UClsFBase[subci] + k];
                bfIsArr[bfCount]   := UFldIsArray[UClsFBase[subci] + k];
                bfArrLen[bfCount]  := UFldArrLen[UClsFBase[subci] + k];
                bfProcSig[bfCount] := UFldProcSig[UClsFBase[subci] + k];
                bfBitWidth[bfCount] := UFldBitWidth[UClsFBase[subci] + k];
                bfBitShift[bfCount] := UFldBitShift[UClsFBase[subci] + k];
                bfBitBytes[bfCount] := UFldBitBytes[UClsFBase[subci] + k];
                bfNDims[bfCount]   := 0;
                Inc(bfCount);
              end;
            if isUnion then begin if subRecSz > curOff then curOff := subRecSz; end
            else curOff := thisOff + subRecSz;
            if subAl > maxAlign then maxAlign := subAl;
          end;
          Break;
        end;
        fnOff := Tokens[TokPos - 1].SOffset; fnLen := Tokens[TokPos - 1].SLen; Next;
        isArr := False; arrLen := 1; fldNDims := 0;
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          dimVal := 1;
          if CurTok.Kind <> tkRBrack then
            dimVal := CEvalConstExpr;
          arrLen := arrLen * dimVal;
          Eat(tkRBrack);
          isArr := True;
          if fldNDims < MAX_ARR_DIMS then
          begin
            bfDimSpan[bfCount * MAX_ARR_DIMS + fldNDims] := dimVal;
            Inc(fldNDims);
          end;
        end;
        if declStars > 0 then
        begin
          sz := TARGET_PTR_SIZE;
          al := TARGET_PTR_SIZE;
        end
        else
        begin
          sz := subRecSz;
          al := subAl;
        end;
        attrEndIdx := TokPos - 1;
        fieldPacked := structPacked or CAttrPackedInRange(attrEndIdx, attrEndIdx);
        fieldAlign := CAttrAlignInRange(attrEndIdx, attrEndIdx);
        if fieldPacked then al := 1;
        if fieldAlign > al then al := fieldAlign;
        if isUnion then thisOff := 0 else thisOff := AlignTo(curOff, al);
        if (subci >= 0) and (bfCount < MAX_BF) then
        begin
          bfNOff[bfCount] := fnOff; bfNLen[bfCount] := fnLen; bfOff[bfCount] := thisOff;
          if declStars > 0 then
          begin
            bfTk[bfCount] := Ord(tyPointer); bfRec[bfCount] := REC_NONE;
            if declStars = 1 then
            begin
              bfElemTk[bfCount] := Ord(tyRecord);
              bfElemRec[bfCount] := REC_UCLASS_BASE + subci;
            end
            else
            begin
              bfElemTk[bfCount] := Ord(tyPointer);
              bfElemRec[bfCount] := REC_NONE;
            end;
          end
          else
          begin
            bfTk[bfCount] := Ord(tyRecord); bfRec[bfCount] := REC_UCLASS_BASE + subci;
            bfElemTk[bfCount] := Ord(tyUnknown); bfElemRec[bfCount] := REC_NONE;
          end;
          bfIsArr[bfCount] := isArr; bfArrLen[bfCount] := arrLen;
          bfNDims[bfCount] := fldNDims; bfProcSig[bfCount] := -1;
          bfBitWidth[bfCount] := 0; bfBitShift[bfCount] := 0; bfBitBytes[bfCount] := 0;
          Inc(bfCount);
        end;
        totalSz := sz;
        if isArr then totalSz := sz * arrLen;
        if isUnion then begin if totalSz > curOff then curOff := totalSz; end
        else curOff := thisOff + totalSz;
        if al > maxAlign then maxAlign := al;
      until not Eat(tkComma);
      Eat(tkSemicolon);
    end
    else if IsCTypeTok then
    begin
      fieldStartIdx := TokPos - 1;
      fTk := ParseCDeclType;
      fldProcSig := CTypeProcSig;   { fn-pointer typedef field signature, if any }
      if CTypeFnPtrName <> '' then
      begin
        { Inline function-pointer member `RET (*name)(params);` — ParseCDeclType
          consumed the whole declarator and captured the name + call signature.
          Register it as an 8-byte pointer field; the normal name-reading loop
          below would Break (the name token is already consumed). }
        if isUnion then thisOff := 0 else thisOff := AlignTo(curOff, TARGET_PTR_SIZE);
        if bfCount < MAX_BF then
        begin
          bfNOff[bfCount] := CTypeFnPtrNameOff; bfNLen[bfCount] := CTypeFnPtrNameLen;
          bfOff[bfCount] := thisOff;
          bfTk[bfCount] := Ord(tyPointer); bfRec[bfCount] := REC_NONE;
          bfElemTk[bfCount] := Ord(tyUnknown); bfElemRec[bfCount] := REC_NONE;
          bfIsArr[bfCount] := False; bfArrLen[bfCount] := 1; bfNDims[bfCount] := 0;
          bfBitWidth[bfCount] := 0; bfBitShift[bfCount] := 0; bfBitBytes[bfCount] := 0;
          bfProcSig[bfCount] := fldProcSig;
          Inc(bfCount);
        end;
        if isUnion then begin if TARGET_PTR_SIZE > curOff then curOff := TARGET_PTR_SIZE; end
        else curOff := thisOff + TARGET_PTR_SIZE;
        if TARGET_PTR_SIZE > maxAlign then maxAlign := TARGET_PTR_SIZE;
        Eat(tkSemicolon);
      end
      else
      begin
      { Recover the base scalar/struct before pointer folding, so comma
        declarators with differing pointer levels (`int *a, b`) are correct. }
      if CTypePtrDepth > 0 then
      begin
        baseScalarTk := CTypeElemTk;
        baseElemRec := CTypeElemRec;
        baseElemTk := baseScalarTk;
      end
      else
      begin
        baseScalarTk := Ord(fTk);
        if fTk = tyPointer then
        begin
          baseElemTk := CTypeElemTk;
          baseElemRec := CTypeElemRec;
        end
        else
        begin
          baseElemTk := Ord(tyUnknown);
          baseElemRec := REC_NONE;
        end;
      end;
      baseRecId := CTypeBaseRec;

      firstDecl := True;
      repeat
        if firstDecl then
          declStartIdx := fieldStartIdx
        else
          declStartIdx := TokPos - 1;
        { stars for this declarator: the first one's stars were consumed by
          ParseCDeclType (CTypePtrDepth); later ones carry their own. }
        if firstDecl then
          declStars := CTypePtrDepth
        else
        begin
          declStars := 0;
          while CurTok.Kind = tkStar do begin Inc(declStars); Next; end;
        end;
        if CurTok.Kind <> tkIdent then Break;
        fnOff := Tokens[TokPos-1].SOffset;
        fnLen := Tokens[TokPos-1].SLen;
        Next;

        isBitField := False; bitWidth := 0;
        { Named bit-field `T name : width`. Pack consecutive fields into the
          storage unit of their declared base type and remember bit metadata for
          masked loads/stores during IR lowering. }
        if CurTok.Kind = tkColon then
        begin
          Next;
          bitWidth := CEvalConstExpr;
          isBitField := True;
        end;

        isArr := False; arrLen := 1; fldNDims := 0;
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          dimVal := 1;
          if CurTok.Kind <> tkRBrack then
            dimVal := CEvalConstExpr;
          arrLen := arrLen * dimVal;
          Eat(tkRBrack);
          isArr := True;
          { record per-dim span so a multidim field supports partial-index row
            decay (`field[i]` -> row address) in the C frontend. }
          if fldNDims < MAX_ARR_DIMS then
          begin
            bfDimSpan[bfCount * MAX_ARR_DIMS + fldNDims] := dimVal;
            Inc(fldNDims);
          end;
        end;

        if declStars > 0 then
        begin
          declTk := Ord(tyPointer); declRec := REC_NONE;
          declElemTk := baseElemTk; declElemRec := baseElemRec;
          { `int nb, *lv;` — a starred LATER declarator over a non-pointer
            base type: baseElemTk is only populated when the decl type itself
            was a pointer, so the pointee here fell to tyUnknown and
            `lv[i]` loads defaulted to 8 bytes. A 64-bit read of a 4-byte int
            slot dragged the neighbouring int into the upper half — tcc's
            symbol-version table (`int nb_local_ver, *local_ver;`) indexed
            sym_versions[2^32] and crashed (feature-c-corpus-tcc, b191).
            The pointee of such a declarator is the base scalar itself. }
          if (IntToTypeKind(declElemTk) = tyUnknown) and
             (IntToTypeKind(baseScalarTk) <> tyPointer) then
          begin
            declElemTk := baseScalarTk;
            declElemRec := baseRecId;    { struct S s, *p: keep the record }
          end;
          { Pointer-to-pointer field `T **m`: the immediate element is a pointer
            (stride = pointer size, so declElemTk = tyPointer), but KEEP the base
            record so `p->m[i]->field` resolves the field offset — mirrors the
            local-variable T** fix in ParseCDeclType (declStars>=2 there). Was
            REC_NONE, which dropped the struct and every `p->m[i]->field` landed at
            offset 0 (e.g. sqlite's `p->apCsr[i]->cacheStatus` clobbering eCurType,
            crashing ORDER BY on 32-bit targets). }
          if declStars >= 2 then begin declElemTk := Ord(tyPointer); declElemRec := baseElemRec; end;
          sz := TARGET_PTR_SIZE; al := TARGET_PTR_SIZE;
        end
        else if (IntToTypeKind(baseScalarTk) = tyRecord) and (baseRecId >= REC_UCLASS_BASE) then
        begin
          declTk := Ord(tyRecord); declRec := baseRecId;
          declElemTk := Ord(tyUnknown); declElemRec := REC_NONE;
          sz := RecSize(baseRecId); al := CRecAlign(baseRecId);
        end
        else
        begin
          declTk := baseScalarTk; declRec := REC_NONE;
          if IntToTypeKind(baseScalarTk) = tyPointer then
          begin
            declElemTk := baseElemTk;
            declElemRec := baseElemRec;
          end
          else
          begin
            declElemTk := Ord(tyUnknown);
            declElemRec := REC_NONE;
          end;
          sz := TypeSize(IntToTypeKind(baseScalarTk));
          al := TypeAlign(IntToTypeKind(baseScalarTk));
        end;
        if al < 1 then al := 1;
        attrEndIdx := TokPos - 1;
        fieldPacked := structPacked or CAttrPackedInRange(declStartIdx, attrEndIdx);
        fieldAlign := CAttrAlignInRange(declStartIdx, attrEndIdx);
        if fieldPacked then al := 1;
        if fieldAlign > al then al := fieldAlign;

        if isBitField then
        begin
          if bitWidth < 0 then bitWidth := 0;
          if bitWidth > sz * 8 then bitWidth := sz * 8;
          if isUnion then
          begin
            if (bitUnitOff < 0) or (bitUnitUsed + bitWidth > 32) then
            begin
              bitUnitOff := 0; bitUnitUsed := 0; bitUnitSize := 4; bitUnitAlign := 1;
            end;
            thisOff := bitUnitOff;
          end
          else
          begin
            if (bitUnitOff < 0) or (bitUnitUsed + bitWidth > 32) then
            begin
              thisOff := curOff;
              bitUnitOff := thisOff; bitUnitUsed := 0; bitUnitSize := 4; bitUnitAlign := 1;
            end
            else
              thisOff := bitUnitOff;
          end;
          bitBytes := (bitUnitUsed + bitWidth + 7) div 8;
          if bitBytes < 1 then bitBytes := 1;
          if bitBytes > 4 then bitBytes := 4;
        end
        else
        begin
          bitUnitOff := -1; bitUnitUsed := 0; bitUnitSize := 0; bitUnitAlign := 1;
          if isUnion then thisOff := 0
          else thisOff := AlignTo(curOff, al);
        end;

        if bfCount < MAX_BF then
        begin
          bfNOff[bfCount] := fnOff; bfNLen[bfCount] := fnLen; bfOff[bfCount] := thisOff;
          bfTk[bfCount] := declTk; bfRec[bfCount] := declRec;
          bfElemTk[bfCount] := declElemTk; bfElemRec[bfCount] := declElemRec;
          bfIsArr[bfCount] := isArr; bfArrLen[bfCount] := arrLen;
          bfNDims[bfCount] := fldNDims;
          if isBitField then
          begin
            bfBitWidth[bfCount] := bitWidth;
            bfBitShift[bfCount] := bitUnitUsed;
            bfBitBytes[bfCount] := bitBytes;
          end
          else
          begin
            bfBitWidth[bfCount] := 0;
            bfBitShift[bfCount] := 0;
            bfBitBytes[bfCount] := 0;
          end;
          if (declStars = 0) then bfProcSig[bfCount] := fldProcSig else bfProcSig[bfCount] := -1;
          Inc(bfCount);
        end;

        if isBitField then
        begin
          bitUnitUsed := bitUnitUsed + bitWidth;
          bitBytes := (bitUnitUsed + 7) div 8;
          if bitBytes < 1 then bitBytes := 1;
          if bitBytes > 4 then bitBytes := 4;
          if isUnion then
          begin
            if bitBytes > curOff then curOff := bitBytes;
          end
          else
            curOff := bitUnitOff + bitBytes;
        end
        else
        begin
          totalSz := sz;
          if isArr then totalSz := sz * arrLen;
          if isUnion then
          begin
            if totalSz > curOff then curOff := totalSz;
          end
          else
            curOff := thisOff + totalSz;
        end;
        if al > maxAlign then maxAlign := al;

        firstDecl := False;
      until not Eat(tkComma);
      Eat(tkSemicolon);
      end;  { close the non-fn-pointer-member else }
    end
    else
      Next;  { skip attributes / unknown tokens }
  end;
  Eat(tkEnd); { consume the closing brace }
  { Append the parent's buffered fields contiguously, NOW (after sub-records), and
    anchor the record's field base here. }
  UClsFBase[ci] := UFldCount;
  for k := 0 to bfCount - 1 do
  begin
    if UFldCount >= MAX_UFIELD - 1 then Break;   { pool nearly full: drop the rest }
    LastTypePointerElemTk := IntToTypeKind(bfElemTk[k]);
    LastTypePointerElemRec := bfElemRec[k];
    AddUField(ci, bfNOff[k], bfNLen[k], bfOff[k], bfTk[k], bfRec[k]);
    UFldIsArray[UFldCount-1] := bfIsArr[k];
    UFldArrLen[UFldCount-1] := bfArrLen[k];
    UFldBitWidth[UFldCount-1] := bfBitWidth[k];
    UFldBitShift[UFldCount-1] := bfBitShift[k];
    UFldBitBytes[UFldCount-1] := bfBitBytes[k];
    if bfProcSig[k] >= 0 then UFldProcSig[UFldCount-1] := bfProcSig[k];
    if bfNDims[k] >= 2 then
    begin
      UFldArrNDims[UFldCount-1] := bfNDims[k];
      for ndi := 0 to bfNDims[k] - 1 do
      begin
        UFldArrDimLo[(UFldCount-1) * MAX_ARR_DIMS + ndi]   := 0;
        UFldArrDimSpan[(UFldCount-1) * MAX_ARR_DIMS + ndi] := bfDimSpan[k * MAX_ARR_DIMS + ndi];
      end;
    end;
  end;
  if structAlign > maxAlign then maxAlign := structAlign;
  UClsSize_[ci] := AlignTo(curOff, maxAlign);
  UClsAlign[ci] := maxAlign;
end;

{ Parse a top-level `typedef ...;` and register the new type name.
  - struct/union [tag] [body] Name   -> opaque, mapped to Pointer
  - enum [tag] body Name             -> Int32, enumerators become constants
  - <decl-specifiers> Name           -> the mapped scalar/pointer type
  Function-pointer typedefs `ret (*Name)(args)` are registered as Pointer AND
  carry a signature Procs[] entry (CTypedefProcSig) so a value of the type is
  callable through AN_CALL_IND with C-ABI marshalling. }
procedure ParseCTypedef;
var tk: TTypeKind; nm, tagName: AnsiString;
    isAggregate, isUnion, hasTag: Boolean;
    ci, ptrStars, nmOff, nmLen: Integer;
    ftRet, ftPType: TTypeKind; ftNParams, ftSig: Integer;
    ftPTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    ftPNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
begin
  Next; { consume 'typedef' }

  isAggregate := (CurTok.Kind = tkRecord) or
                 ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'));
  if isAggregate then
  begin
    isUnion := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'union');
    Next; { 'struct' / 'union' }
    hasTag := False;
    if CurTok.Kind = tkIdent then              { optional tag — capture it }
    begin
      tagName := CurTok.SVal; hasTag := True; Next;
    end;
    if (CurTok.Kind = tkBegin) and
       ((UClsCount >= MAX_UCLASS - 1) or (UFldCount >= MAX_UFIELD - 128) or
        (not CStructBodyIsSimple(TokPos - 1))) then
    begin
      { Fall back to an opaque pointer when either (a) record-table headroom is
        low (C structs share the MAX_UCLASS/MAX_UFIELD tables with Pascal), or
        (b) the body uses a construct we cannot lay out without silently-wrong
        offsets (bitfields, nested/anonymous aggregates, struct/union/enum-tag
        fields). Plain POD bodies take the record path below. }
      SkipBraceBlock;
      while CurTok.Kind = tkStar do Next;
      if CurTok.Kind = tkIdent then
      begin
        nm := CurTok.SVal; Next;
        AddCTypedef(nm, tyPointer);
      end;
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
      Eat(tkSemicolon);
      Exit;
    end;
    if CurTok.Kind = tkBegin then
    begin
      { Body present: lay it out as a real record so fields are addressable.
        The typedef Name follows the body. When the struct has a tag, register
        (or reuse a forward) record for that tag BEFORE parsing the body, so a
        self-reference `struct Tag *next;` inside resolves to this same record. }
      if hasTag then
        ci := FindOrForwardCTag(tagName) - REC_UCLASS_BASE
      else
        ci := AddUClass(0, 0);
      UClsIsRecord[ci] := True;
      ParseCStructInto(ci, isUnion);
      ptrStars := 0;
      while CurTok.Kind = tkStar do begin Inc(ptrStars); Next; end;
      if CurTok.Kind = tkIdent then
      begin
        nmOff := Tokens[TokPos-1].SOffset;
        nmLen := Tokens[TokPos-1].SLen;
        nm := CurTok.SVal; Next;
        if ptrStars > 0 then
        begin
          { typedef struct {..} *Name; — the record stays anonymous, Name is a
            pointer to it (both for the C parser and as a Pascal pointer type). }
          AddCTypedefEx(nm, tyPointer, Ord(tyRecord), REC_UCLASS_BASE + ci);
          RegisterPtrAlias(nmOff, nmLen, Ord(tyRecord), REC_UCLASS_BASE + ci, 0, 0);
        end
        else
        begin
          { typedef struct {..} Name; — Name *is* the record. }
          UClsNOff[ci] := nmOff;
          UClsNLen[ci] := nmLen;
          AddCTypedefEx(nm, tyRecord, Ord(tyUnknown), REC_UCLASS_BASE + ci);
        end;
      end;
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
      Eat(tkSemicolon);
      Exit;
    end;
    { No body present (forward / separately-defined struct). With a tag, the
      typedef ALIASES that struct's (possibly forward) record — `typedef struct
      Zio ZIO;` makes `ZIO` the record and `ZIO *` a pointer to it, so a later
      `struct Zio { ... }` body fills the same record and `z->field` resolves.
      `typedef struct T *Ref;` is a pointer to it. A tagless no-body typedef
      stays an opaque pointer handle. }
    ptrStars := 0;
    while CurTok.Kind = tkStar do begin Inc(ptrStars); Next; end;
    if CurTok.Kind = tkIdent then
    begin
      nmOff := Tokens[TokPos-1].SOffset;
      nmLen := Tokens[TokPos-1].SLen;
      nm := CurTok.SVal; Next;
      if hasTag then
      begin
        ci := FindOrForwardCTag(tagName) - REC_UCLASS_BASE;
        if ptrStars > 0 then
        begin
          AddCTypedefEx(nm, tyPointer, Ord(tyRecord), REC_UCLASS_BASE + ci);
          RegisterPtrAlias(nmOff, nmLen, Ord(tyRecord), REC_UCLASS_BASE + ci, 0, 0);
        end
        else
          AddCTypedefEx(nm, tyRecord, Ord(tyUnknown), REC_UCLASS_BASE + ci);
      end
      else
        AddCTypedef(nm, tyPointer); { tagless opaque aggregate: pointer-only }
    end;
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then
  begin
    Next; { 'enum' }
    if CurTok.Kind = tkIdent then Next;      { optional tag }
    if CurTok.Kind = tkBegin then ParseCEnumBody; { enumerators -> constants }
    if CurTok.Kind = tkIdent then
    begin
      nm := CurTok.SVal; Next;
      AddCTypedef(nm, tyInt32);
    end;
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;

  { scalar / pointer typedef }
  tk := ParseCDeclType;
  { Function-pointer typedef `ret (*Name)(params)`: ParseCDeclType collapses the
    declarator to Pointer and (now) captures the name + a call signature in
    CTypeFnPtrName / CTypeProcSig. Register Name as a pointer typedef that carries
    the signature, so a value of the type is callable through AN_CALL_IND. }
  if (CTypeFnPtrName <> '') and (CTypeProcSig >= 0) then
  begin
    AddCTypedefFnPtr(CTypeFnPtrName, CTypeProcSig);
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  { Function-TYPE typedef `typedef RET NAME(params);` (a function type, NO
    pointer star) — stb_sprintf's `typedef char *STBSP_SPRINTFCB(...)` idiom,
    used as `STBSP_SPRINTFCB *callback`. ParseCDeclType returned the plain RET
    and left NAME (an ident) with `(` following. Register NAME as a
    fn-pointer-style typedef (Pointer + call signature) so `NAME *cb` / `NAME cb`
    are callable through AN_CALL_IND, exactly like `typedef RET (*NAME)(params)`
    — in every use we support a C function type and a pointer-to-function decay
    to the same callable value. }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    nm := CurTok.SVal;
    Next;                              { consume NAME -> CurTok is '(' }
    ftRet := tk;
    if CTypeIsVoid then ftRet := tyInteger;
    ftNParams := 0;
    Next;                              { consume the parameter-list '(' }
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
    begin
      if IsCTypeTok then
      begin
        ftPType := ParseCDeclType();   { parens required: see the fn-ptr note above }
        if CTypeIsVoid then
          { (void) — no parameter }
        else if ftNParams < MAX_PROC_PARAMS then
        begin
          ftPTypes[ftNParams] := ftPType;
          ftPNames[ftNParams] := 'a';
          Inc(ftNParams);
        end;
        if CurTok.Kind = tkIdent then Next;   { optional parameter name }
      end
      else
        Next;                          { `...` varargs marker }
      Eat(tkComma);
    end;
    Eat(tkRParen);
    ftSig := RegisterProc('$cfntype', True, ftRet, ftNParams, ftPNames, ftPTypes);
    Procs[ftSig].BodyAddr := -1;
    ProcCdecl[ftSig] := True;          { C ABI (System V) for the indirect call }
    CTypeIsVoid := False;
    AddCTypedefFnPtr(nm, ftSig);
    ci := FindCTypedef(nm);
    if ci >= 0 then CTypedefIsFnType[ci] := True;   { `*` decays, not indirects }
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  if CurTok.Kind = tkIdent then
  begin
    nmOff := Tokens[TokPos-1].SOffset;
    nmLen := Tokens[TokPos-1].SLen;
    nm := CurTok.SVal; Next;
    { Preserve metadata when aliasing typedefs. `typedef S Stream;` must keep the
      record id from S, otherwise `Stream *p; p->field` resolves as REC_NONE and
      all field offsets collapse to 0. Pointer aliases likewise keep their
      pointed-at type even when aliasing an existing pointer typedef rather than
      spelling a fresh `*` here. }
    if (tk = tyRecord) then
      AddCTypedefEx(nm, tk, Ord(tyUnknown), CTypeBaseRec)
    else if tk = tyPointer then
    begin
      AddCTypedefEx(nm, tk, CTypeElemTk, CTypeElemRec);
      if CTypeProcSig >= 0 then CTypedefProcSig[FindCTypedef(nm)] := CTypeProcSig;
      if (CTypePtrDepth > 0) or (CTypeElemTk <> Ord(tyUnknown)) then
        RegisterPtrAlias(nmOff, nmLen, CTypeElemTk, CTypeElemRec, 0, 0);
    end
    else
      AddCTypedef(nm, tk);
  end;
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

{ Bare top-level `enum [tag] body ;` — register the enumerators as
  constants (no new type name). }
procedure ParseCEnumDecl;
begin
  Next; { consume 'enum' }
  if CurTok.Kind = tkIdent then Next;        { optional tag }
  if CurTok.Kind = tkBegin then ParseCEnumBody;
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

{ True when the upcoming `struct`/`union` tokens are a bare struct/union
  declaration or definition (`struct Tag { ... };` or `struct Tag;`) rather than
  a function/variable typed by the struct (`struct Tag *get();`). CurTok is the
  struct/union keyword, so Tokens[TokPos] is the token after it. }
function IsBareStructDecl: Boolean;
var i, depth: Integer;
begin
  i := TokPos;
  if (i < TokCount) and (Tokens[i].Kind = tkIdent) then Inc(i);  { skip tag }
  if i >= TokCount then begin Result := False; Exit; end;
  if Tokens[i].Kind = tkSemicolon then begin Result := True; Exit; end;  { `struct Tag;` forward }
  if Tokens[i].Kind <> tkBegin then begin Result := False; Exit; end;    { `struct Tag x` etc. }
  { Scan past the balanced body; a `;` right after it is a bare type definition,
    but an identifier (a variable) means this is a struct-typed GLOBAL/var decl
    (`struct { ... } g;`) that must route to ParseCGlobalVarDecl, not ParseCStructDecl. }
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then
    begin Dec(depth); if depth = 0 then begin Inc(i); Break; end; end;
    Inc(i);
  end;
  Result := (i < TokCount) and (Tokens[i].Kind = tkSemicolon);
end;

{ True when the upcoming `enum` tokens are a bare enum declaration/definition
  (`enum Tag;` forward, or `enum [Tag] { ... };`) rather than a function/variable
  typed by the enum (`enum Tag g(void){...}` / `enum Tag x;`). Without this, an
  enum-typed function definition was mis-routed to ParseCEnumDecl, which skips to
  the first `;` — the one INSIDE the body — desyncing the whole parse (00170). }
function IsBareEnumDecl: Boolean;
var i, depth: Integer;
begin
  i := TokPos;                      { token after 'enum' }
  if (i < TokCount) and (Tokens[i].Kind = tkIdent) then Inc(i);  { skip tag }
  if i >= TokCount then begin Result := False; Exit; end;
  if Tokens[i].Kind = tkSemicolon then begin Result := True; Exit; end;   { `enum Tag;` forward }
  if Tokens[i].Kind <> tkBegin then begin Result := False; Exit; end;     { `enum Tag x/g(...)` }
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then
    begin Dec(depth); if depth = 0 then begin Inc(i); Break; end; end;
    Inc(i);
  end;
  Result := (i < TokCount) and (Tokens[i].Kind = tkSemicolon);
end;

{ Bare `struct/union [Tag] { body };` (definition) or `struct Tag;` (forward).
  A tagged definition lays the body out as a record under the tag, so other C
  declarations can use `struct Tag` by name. }
procedure ParseCStructDecl;
var isUnion, hasTag: Boolean; tagName: AnsiString; ci, tagOff, tagLen, tagRec: Integer;
begin
  isUnion := (CurTok.Kind = tkIdent) and (CurTok.SVal = 'union');
  Next; { struct / union }
  hasTag := False; tagOff := 0; tagLen := 0;
  if CurTok.Kind = tkIdent then
  begin
    tagName := CurTok.SVal;
    tagOff := Tokens[TokPos-1].SOffset; tagLen := Tokens[TokPos-1].SLen;
    hasTag := True; Next;
  end;
  if CurTok.Kind = tkBegin then
  begin
    ci := -1;
    if hasTag then
    begin
      tagRec := FindOrForwardCTag(tagName);          { may be REC_NONE if table full }
      if tagRec >= REC_UCLASS_BASE then ci := tagRec - REC_UCLASS_BASE;
    end
    else if UClsCount < MAX_UCLASS - 1 then
      ci := AddUClass(0, 0);
    if ci < 0 then
      SkipBraceBlock                                  { no headroom: opaque }
    else
    begin
      UClsIsRecord[ci] := True;
      if hasTag and (UClsNLen[ci] = 0) then
      begin
        UClsNOff[ci] := tagOff; UClsNLen[ci] := tagLen;  { name the record by its tag }
      end;
      if (UFldCount < MAX_UFIELD - 128) and CStructBodyIsSimple(TokPos - 1) then
        ParseCStructInto(ci, isUnion)
      else
        SkipBraceBlock;   { opaque: keep the tag, drop the layout }
    end;
  end
  else if hasTag then
    FindOrForwardCTag(tagName);  { forward `struct Tag;` }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

procedure ParseCUnit;
begin
  while CurTok.Kind <> tkEOF do
  begin
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'typedef') then
      ParseCTypedef
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then
      ParseCEnumDecl
    else if ((CurTok.Kind = tkRecord) or
             ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'union'))) and
            IsBareStructDecl then
      ParseCStructDecl
    else if IsCTypeTok then
      ParseCSubroutine
    else
      Next;
  end;
end;
