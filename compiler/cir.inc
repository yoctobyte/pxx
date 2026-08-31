{ cir.inc -- C-EXCLUSIVE IR lowering. Track C.

  Carved out of ir.inc on 2026-08-29
  (refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed,
  slice 1). C owned clexer/cparser/cpreproc and lib/crtl but no lowering file, so
  C-exclusive lowering lived in the shared ir.inc and most Track C tickets needed
  Track A's slot. This file is where C's lowering goes.

  WHAT BELONGS HERE: a routine that only ever runs in C mode. What does NOT: a
  `not CProgramMode` guard (that is PASCAL's lowering with C carved out -- 13 of
  ir.inc's 40 CProgramMode sites are this, and moving them here would relocate a
  third of the Pascal frontend into a C file), and a two-armed dialect decision
  where both frontends act (4 more). See the inventory in the ticket.

  HOW THEY GOT HERE, which is the part worth remembering: NOT ONE of these seven
  routines contains the string `CProgramMode`. Each is reached only from a
  C-guarded call site in ir.inc, so the grep that found the 40 sites could not
  see any of them -- 223 lines invisible to the search that defined the job.
  CASTNodeOccursIn and CASTLValueHasSideEffect even carry the C prefix in their
  names. Someone knew; a name is not an index.

  So when hunting for more C lowering to move: follow CALLERS, not the guard.
  The guard tells you where the decision is made, never where the work lives.
  And follow them TRANSITIVELY: IRBitMask became reachable only from this file
  as a RESULT of slice 1, so a one-level scan run before the move could not
  have seen it. Every extraction can create new candidates one level below it.
  tools/c_lowering_callers.py is that scan.

  AND THE RULE HAS A SECOND HALF, learned by finding a routine that passes the
  first one and must NOT move: reached-only-from-C is NECESSARY and NOT
  SUFFICIENT. The routine must also BE C -- its subject must be a C-language
  construct. IRBitMask(width) is (1 shl width) - 1 written as a loop: no AST, no
  CProgramMode, no C semantics. It is C-only by who happens to call it, not by
  what it is, and putting a general helper in a frontend's file means the day
  Pascal wants a bit mask the answer is a duplicate or a Pascal dependency on
  cir.inc. That is the parser.inc lesson running the other way -- ast_arena,
  inline_expand and ast_syminfer went to A not because Pascal stopped using them
  but because they were never Pascal's SUBJECT. Same test, opposite direction.

  Ordering: this file is included from compiler.pas AFTER ir.inc's
  IRLowerDestAddress, because IRLowerCompoundAssign calls it. IRAddrMayCall is
  called the other way (from IRLowerDestAddress), so ir.inc carries one forward
  declaration for it. Expect that shape again in later slices -- the shared
  dispatchers and the C bodies call each other in both directions. }


function IRBitStorageTk(bytes: Integer): TTypeKind;
{ Which integer type a C bit-field's STORAGE UNIT is loaded and stored as.

  C, not arithmetic -- and that is why this sits here while IRBitMask, which
  qualifies on the same reached-only-from-C test, deliberately does not. A
  general size-to-typekind map would be exact; this one ROUNDS, and every
  rounding step is a C rule: a 3-byte unit loads as 4 (C11 6.7.2.1 lets the
  implementation pick the unit, and ours is the next power of two), and
  anything past 4 loads as 8 because a `long long` bit-field's unit does. Its
  only input is RecFieldBitBytes, reading UFldBitBytes, which defs.inc
  documents as "C named bit-field width" -- Pascal parses `bitpacked` as a
  synonym for `packed` and allocates no bit-fields at all, so there is no
  Pascal caller to lose and no Pascal meaning for the rounding to be wrong for.

  UNSIGNED at every width, on purpose: the read path sign-extends by hand, so a
  signed field of exactly the unit's width must arrive zero-extended. See the
  note in IRLowerBitFieldRead. }
begin
  if bytes <= 1 then Result := tyUInt8
  else if bytes = 2 then Result := tyUInt16
  else if bytes <= 4 then Result := tyUInt32
  else Result := tyUInt64;
end;


function IRLowerBitFieldRead(fieldNode: Integer; storageAddr: Integer; storageTk: TTypeKind): Integer;
var recId, width, shift: Integer; fieldName: AnsiString; value, maskNode: Integer;
    fieldTk: TTypeKind; signBit: Int64; sbNode: Integer;
begin
  recId := ResolveNodeRec(ASTLeft[fieldNode]);
  fieldName := GetASTIdentName(fieldNode);
  width := RecFieldBitWidth(recId, fieldName);
  shift := RecFieldBitShift(recId, fieldName);
  fieldTk := RecFieldType(recId, fieldName);
  storageTk := IRBitStorageTk(RecFieldBitBytes(recId, fieldName));
  value := IRAppend(IR_LOAD_MEM, storageAddr, -1, -1, 0, Ord(storageTk));
  if shift > 0 then
    value := IRAppend(IR_BINOP, value,
                      IRAppend(IR_CONST_INT, -1, -1, -1, shift, Ord(tyInteger)),
                      Ord(tkShrLogical), 0, Ord(storageTk));
  maskNode := IRAppend(IR_CONST_INT, -1, -1, -1, IRBitMask(width), Ord(storageTk));
  Result := IRAppend(IR_BINOP, value, maskNode, Ord(tkAnd), 0, Ord(storageTk));

  { A SIGNED bitfield stores a two's-complement value in `width` bits, so the mask
    above hands it back ZERO-extended: `signed f : 7` holding -5 reads as 123. C says
    -5. Sign-extend it branchlessly with (v xor signBit) - signBit -- no arithmetic
    shift, no new IR op, correct for every width.

    Applies to EVERY signed field, whatever its width: IRBitStorageTk always picks an
    UNSIGNED storage type (tyUInt8/16/32), so the load is zero-extended even when the
    field exactly fills its unit. Guarding on `width < storage bits` (as this first
    did) left `signed f : 8` in a one-byte unit reading -7 back as 249. An unsigned
    field must of course stay zero-extended.

    csmith found this on its fourth program, and every signed bitfield in every
    generated program was wrong. The C corpora (lua/sqlite/tcc) never caught it
    because their bitfields are unsigned -- the bug was invisible to a decade of
    real-world C. }
  { C integer promotion: a bitfield NARROWER than int reads as a SIGNED int —
    every value of a sub-int field fits, so both signed and unsigned sub-int fields
    promote to `int`, and downstream signed-vs-unsigned arithmetic (subtraction,
    modulo, division, comparison) is chosen from THIS node's type. The prior code
    sign-extended in the (unsigned) storage type and left the result tagged
    unsigned, so `bit.i % bit.u` did an UNSIGNED modulo (bf-sign-2.c, bitfld-1.c,
    the gcc-torture bitfield cluster). Do the whole extension in the 32-bit
    tyInteger domain: first re-mask to a clean zero-extended value (clears garbage
    above `width` left by a sub-int storage-width op), then sign-extend if the field
    is signed. Full-width (:32) and long-long bitfields can't fit in int, so they
    keep the storage-type extension path below. }
  if width < 32 then
  begin
    maskNode := IRAppend(IR_CONST_INT, -1, -1, -1, IRBitMask(width), Ord(tyInteger));
    Result := IRAppend(IR_BINOP, Result, maskNode, Ord(tkAnd), 0, Ord(tyInteger));
    if ((fieldTk = tyInt8) or (fieldTk = tyInt16) or (fieldTk = tyInt32) or
        (fieldTk = tyInt64) or (fieldTk = tyInteger) or (fieldTk = tyNativeInt)) then
    begin
      signBit := IRBitMask(width) - (IRBitMask(width) div 2);   { = 1 shl (width-1) }
      sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(tyInteger));
      Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkXor), 0, Ord(tyInteger));
      sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(tyInteger));
      Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkMinus), 0, Ord(tyInteger));
    end;
  end
  else if ((fieldTk = tyInt8) or (fieldTk = tyInt16) or (fieldTk = tyInt32) or
           (fieldTk = tyInt64) or (fieldTk = tyInteger) or (fieldTk = tyNativeInt)) then
  begin
    { Full-width / long-long signed bitfield: sign-extend in the storage type. }
    signBit := IRBitMask(width) - (IRBitMask(width) div 2);   { = 1 shl (width-1) }
    sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(storageTk));
    Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkXor), 0, Ord(storageTk));
    sbNode := IRAppend(IR_CONST_INT, -1, -1, -1, signBit, Ord(storageTk));
    Result := IRAppend(IR_BINOP, Result, sbNode, Ord(tkMinus), 0, Ord(storageTk));
  end;
end;

function IRLowerBitFieldStore(fieldNode, rhsValue: Integer; storageTk: TTypeKind): Integer;
var recId, width, shift, addr, oldVal, clearMask, newBits, maskedNew, maskNode: Integer;
    fieldName: AnsiString; mask, shiftedMask: Int64;
begin
  recId := ResolveNodeRec(ASTLeft[fieldNode]);
  fieldName := GetASTIdentName(fieldNode);
  width := RecFieldBitWidth(recId, fieldName);
  shift := RecFieldBitShift(recId, fieldName);
  storageTk := IRBitStorageTk(RecFieldBitBytes(recId, fieldName));
  addr := IRLowerAddress(fieldNode);
  mask := IRBitMask(width);
  shiftedMask := mask shl shift;
  oldVal := IRAppend(IR_LOAD_MEM, addr, -1, -1, 0, Ord(storageTk));
  clearMask := IRAppend(IR_BINOP, oldVal,
                        IRAppend(IR_CONST_INT, -1, -1, -1, not shiftedMask, Ord(storageTk)),
                        Ord(tkAnd), 0, Ord(storageTk));
  maskedNew := IRAppend(IR_BINOP, rhsValue,
                        IRAppend(IR_CONST_INT, -1, -1, -1, mask, Ord(storageTk)),
                        Ord(tkAnd), 0, Ord(storageTk));
  if shift > 0 then
    maskedNew := IRAppend(IR_BINOP, maskedNew,
                          IRAppend(IR_CONST_INT, -1, -1, -1, shift, Ord(tyInteger)),
                          Ord(tkShl), 0, Ord(storageTk));
  newBits := IRAppend(IR_BINOP, clearMask, maskedNew, Ord(tkOr), 0, Ord(storageTk));
  Result := IRAppend(IR_STORE_MEM, addr, newBits, -1, 0, Ord(storageTk));
end;

function IRAddrMayCall(n, depth: Integer): Boolean;
{ Does evaluating this ADDRESS node RUN something? Only calls matter: every other
  address shape here is a load or an arithmetic node over one, and re-walking
  those is free and idempotent (`*p++` parks its increment in a separate
  statement, which is why that shape was never affected).

  The walk is kind-aware on purpose. IRA is a NODE index for some opcodes and a
  SYMBOL/PROC index for others (IR_LEA, IR_LOAD_SYM, IR_CALL), so a blind
  three-operand recursion would read a symbol number as a node number and answer
  from an unrelated part of the arena. Unknown kinds answer False — that is
  today's behaviour, so a shape this list misses stays exactly as it was rather
  than growing a temp nobody asked for. }
begin
  Result := False;
  if (n < 0) or (n >= IRCount) or (depth > 12) then Exit;
  case IRKind[n] of
    IR_CALL, IR_CALL_IND, IR_VIRTUAL_CALL:
      Result := True;
    IR_LOAD_MEM, IR_NEG, IR_NOT:
      Result := IRAddrMayCall(IRA[n], depth + 1);
    IR_INDEX, IR_FIELD, IR_BINOP:
      begin
        Result := IRAddrMayCall(IRA[n], depth + 1);
        if not Result then Result := IRAddrMayCall(IRB[n], depth + 1);
      end;
  end;
end;

function CASTLValueHasSideEffect(n, depth: Integer): Boolean;
{ Does EVALUATING this lvalue do anything observable — call, increment, assign?
  Only then is it worth pinning the node down; an ordinary `a[i] += 1` must keep
  the exact IR it has today, so the default answer is False and the recursion
  covers only the shapes an lvalue is actually built from. }
begin
  Result := False;
  if (n < 0) or (n >= ASTNodeCount) or (depth > 12) then Exit;
  case ASTKind[n] of
    AN_CALL, AN_VIRTUAL_CALL, AN_INCDEC, AN_ASSIGN, AN_COMPOUND_ASSIGN, AN_COMMA:
      Result := True;
    AN_DEREF, AN_FIELD, AN_PTR_CAST, AN_ADDR, AN_CLASS_CAST:
      Result := CASTLValueHasSideEffect(ASTLeft[n], depth + 1);
    AN_INDEX, AN_BINOP:
      begin
        Result := CASTLValueHasSideEffect(ASTLeft[n], depth + 1);
        if not Result then Result := CASTLValueHasSideEffect(ASTRight[n], depth + 1);
      end;
  end;
end;

function CASTNodeOccursIn(root, target, depth: Integer): Boolean;
{ Does this exact AST NODE INDEX appear inside that subtree? Node identity, not
  equality: two spellings of the same expression are two nodes, so a hit means
  one node is genuinely reachable from two places — which in C only cparser's
  `lv OP= rhs` -> `lv = lv OP rhs` desugar produces. Depth-capped; the shared
  node sits on the RHS's left spine, a few levels down at most (a plain-char
  lvalue promotes through three binops before it). }
begin
  Result := False;
  if (root < 0) or (root >= ASTNodeCount) or (depth > 24) then Exit;
  if root = target then begin Result := True; Exit; end;
  Result := CASTNodeOccursIn(ASTLeft[root], target, depth + 1);
  if not Result then Result := CASTNodeOccursIn(ASTRight[root], target, depth + 1);
end;

function IRAssignIsSharedCompound(node: Integer): Boolean;
{ Is this AN_ASSIGN the `lv = lv OP rhs` cparser builds for `lv OP= rhs`, with a
  side-effecting lvalue? The signature is exact: the binop's LEFT is the very
  same AST node index as the destination, which nothing else produces.

  Narrow on purpose -- a pure lvalue keeps the IR it has today (the shared node
  lowers to the same loads twice, which is only duplicated work), an AN_IDENT
  destination has no address to double, and a managed or aggregate destination
  belongs to the arms that know how to copy it. C has no compound assignment on
  those anyway. }
var lv: Integer; tk: TTypeKind;
begin
  Result := False;
  if not CProgramMode then Exit;
  lv := ASTLeft[node];
  if (lv < 0) or (ASTKind[lv] = AN_IDENT) then Exit;
  if (ASTRight[node] < 0) or (ASTKind[ASTRight[node]] <> AN_BINOP) then Exit;
  { The lvalue is normally the binop's own left operand, but a promotion sits in
    between when it needs one: a plain-char lvalue arrives as
    `((lv & $FF) ^ $80) - $80`, three binops deep, and that spelling kept its
    double evaluation after the direct check was already fixed. Search the RHS
    instead of guessing the depth. }
  if not CASTNodeOccursIn(ASTRight[node], lv, 0) then Exit;
  tk := IntToTypeKind(ASTTk[lv]);
  if not (TypeIsOrdinal(tk) or TypeIsFloat(tk) or (tk = tyPointer)) then Exit;
  Result := CASTLValueHasSideEffect(lv, 0);
end;

function IRLowerCompoundAssign(node: Integer): Integer;
{ C `lv OP= rhs` where lv has a SIDE EFFECT.

  cparser desugars it to `lv = lv OP rhs` and REUSES the one lvalue AST node in
  both places -- the comment there says "since it is a pure lvalue read this is
  safe", which is the assumption C breaks. Lowering walks that node twice, so
  `*f() += 1` called f twice, `a[i++] += 1` stepped i twice, and `*p++ += 1`
  advanced p by TWO. The increment operators never had it: AN_INCDEC lowers the
  address once, and that is the model here.

  Keeping the desugar is deliberate. The alternative -- switching cparser to the
  AN_COMPOUND_ASSIGN node, whose docstring promises exactly "the lvalue address
  is computed ONCE" -- looks like a one-line fix and is a trap: that node lowers
  to a raw scalar read-modify-write with no pointer-arithmetic SCALING, so
  `p += 1` on a `long long *` would step one byte. The desugar inherits all of
  C's conversion and scaling rules from the ordinary binop path, because the AST
  is untouched; only the VALUE the shared node lowers to is supplied here.

  So: lower the destination address once, read through it once, and pin the node
  to both for the duration of the RHS. Saved/restored around the recursion so a
  nested compound assignment (`a[i++] += (b[j++] += 1)`) keeps its own pinning.
  bug-c-a-compound-assignment-evaluates-its-lvalue-twice }
var lvNode, lvTk, addr, cur, val: Integer;
    savedAST, savedAddr, savedVal: Integer;
begin
  lvNode := ASTLeft[node];
  lvTk := ASTTk[lvNode];
  addr := IRLowerDestAddress(lvNode);
  cur := IRAppend(IR_LOAD_MEM, addr, -1, -1, 0, lvTk);
  savedAST := IRCompoundLvAST; savedAddr := IRCompoundLvAddr; savedVal := IRCompoundLvVal;
  IRCompoundLvAST := lvNode;
  IRCompoundLvAddr := addr;
  IRCompoundLvVal := cur;
  val := IRLowerAST(ASTRight[node]);
  IRCompoundLvAST := savedAST; IRCompoundLvAddr := savedAddr; IRCompoundLvVal := savedVal;
  Result := IRAppend(IR_STORE_MEM, addr, val, -1, 0, lvTk);
  { an assignment is an expression yielding the stored value (C 6.5.16), same
    load-back the ordinary scalar arms append }
  Result := IRAppend(IR_LOAD_MEM, addr, -1, -1, 0, lvTk);
end;

function CNodeIsDecayedRow(node: Integer): Boolean;
{ Is this node the pre-scaled byte add that cparser builds for a DECAYED ROW —
  a partial index (`m[1]` on `int m[3][4]`, `s.m[1][2]` on a field) or the no-op
  deref of a pointer-to-array?

  Those three builders compute `&base + flat*stride` themselves, so the offset
  is ALREADY IN BYTES and pointer arithmetic must not scale it a second time.

  How that used to be said, and why it is said here instead: the builders
  retagged their base `ASTTk[base] := Ord(tyInt64)`, which made
  IRNodePointerBase answer False and so kept the lowering's pointer-arith arms
  off the node. That is a flag stored in the type field, and tyInt64 is equally
  the honest tag of `long long a[8]` — so IRNodePointerBase had to guess which
  of the two it was looking at, from the node's DECLARATION. It guessed wrong
  three times, each silently:

    long long q - p                gcc n    pxx 0       (the ticket's own bug)
    (char*)(m+1)-(char*)m on
      long long m[3][4]            gcc 32   pxx 1
    *(s.v+3), long long v[8]
      as a struct FIELD            gcc 3    pxx 0

  The first was patched by whitelisting the shape that carries tyInt64 honestly
  (a fixed-extent 1-D array IDENT); the second and third are the shapes that
  whitelist did not reach, and they stayed wrong until the flag moved out of the
  type field entirely.

  ASTSLen on an AN_BINOP means exactly one thing in C mode — the three builders
  above are its only writers — and IRPointerStride was already reading it to
  answer what the row steps by. So the marker existed; the sentinel was a second,
  lossy copy of it.
  refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag }
begin
  Result := CProgramMode and (node >= 0) and (ASTKind[node] = AN_BINOP) and
            (ASTSLen[node] > 0) and (IntToTypeKind(ASTTk[node]) = tyPointer);
end;

{ Dispatch scan: walk the ENTIRE switch body (any depth — case/default labels are
  labels on arbitrarily nested statements, C 6.8.1) assigning each C marker an
  IR_LABEL and, for a case, emitting `if (sel == val) goto label`. Recurses into
  every construct EXCEPT a nested AN_SWITCH (its own cases belong to it). This is
  what lets Duff's device work: the case labels buried inside a do-while are found
  here and the body lowering (normal IRLowerAST) drops the IR_LABELs in place, so
  dispatch can jump straight into the loop. C markers carry ASTSLen=1 (distinct
  from a Pascal AN_CASE statement / the Default(T) node). }
procedure IRLowerCSwitchDispatchScan(node, selTmp, selTk: Integer; var defaultLabel: Integer);
var condNode, selSz: Integer; caseVal: Int64;
begin
  if node < 0 then Exit;
  if ASTKind[node] = AN_SWITCH then Exit;   { nested switch owns its own case labels }
  if (ASTKind[node] = AN_CASE) and (ASTSLen[node] = 1) then
  begin
    ASTSOffset[node] := IRNewLabel;
    { C 6.8.4.2: each case constant is CONVERTED to the promoted controlling
      type. quickjs switches a uint32_t tag over negative enum labels
      (JS_TAG_OBJECT = -1): the label must compare as 0xFFFFFFFF, not as a
      sign-extended 64-bit -1 that never matches a zero-extended selector. }
    caseVal := ASTIVal[node];
    selSz := TypeSize(IntToTypeKind(selTk));
    if (selSz < 8) and TypeCompareUnsigned(IntToTypeKind(selTk), IntToTypeKind(selTk)) and
       (caseVal < 0) then
      caseVal := caseVal and ((Int64(1) shl (selSz * 8)) - 1);
    condNode := IRAppend(IR_BINOP,
      IRAppend(IR_LOAD_SYM, selTmp, -1, -1, 0, selTk),
      IRAppend(IR_CONST_INT, -1, -1, -1, caseVal, selTk),
      Ord(tkNeq), 0, Ord(tyBoolean));
    IRAppend(IR_JUMP_IF_FALSE, ASTSOffset[node], condNode, -1, 0, 0);
    Exit;                                    { marker has no children of interest }
  end;
  if (ASTKind[node] = AN_DEFAULT) and (ASTSLen[node] = 1) then
  begin
    ASTSOffset[node] := IRNewLabel;
    defaultLabel := ASTSOffset[node];
    Exit;
  end;
  IRLowerCSwitchDispatchScan(ASTLeft[node], selTmp, selTk, defaultLabel);
  IRLowerCSwitchDispatchScan(ASTRight[node], selTmp, selTk, defaultLabel);
end;
