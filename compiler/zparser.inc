{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Zig Parser (skeleton) =====
  Hand-builds AST directly, same technique as rparser.inc/aparser.inc,
  reusing the shared AN_* node kinds and rparser.inc's small node helpers
  (RSeqAppend/RMakeIdent/RBinOp/RWiden/RIntToStr — included earlier in
  compiler.pas, so plain calls work) — no new AST nodes, no new IR, no
  backend work. This is the esoteric-frontend-probe skeleton
  (devdocs/progress/working/feature-zig-frontend.md, sub-ticket 1): the
  goal is exercising the shared AST->IR->codegen pipeline with a Zig-shaped
  program, NOT making Zig usable.

  v1 subset: top-level `[pub] fn name(a: i64, ...) RetType { ... }`
  functions (max 4 scalar params, same limit as the Rust skeleton),
  `var`/`const` declarations with optional type annotation (type inferred
  from the initializer otherwise, incl. `= undefined` for declare-only),
  assignment and compound assignment (+= -= *= /=), if/else if/else,
  while with optional `: (continue-expression)`, range for
  `for (lo..hi) |i|` (exclusive upper bound, per Zig), break/continue,
  return, integer/bool/string expressions with and/or, function calls,
  and `std.debug.print("fmt", .{args})` lowered onto the same
  AN_WRITE/AN_WRITELN machinery Pascal's writeln and BASIC's PRINT use
  ({}/{d}/{s}/{c}/{any} placeholders; {{ }} escapes NOT handled).

  Sub-ticket 2 (zig-structs-and-pointers) adds, still purely frontend-side
  (structs reuse the UClass/AddUField machinery exactly like rparser.inc,
  pointers/arrays reuse tyPointer/AN_ADDR/AN_DEREF and AllocArray/AN_INDEX):
  - top-level `const Name = struct { f: T, ... };` with SCALAR fields only;
    `var s: Name = undefined;`, field read/write `s.f`, and struct-literal
    initializers `var s = Name{ .f = expr, ... };` lowered to per-field
    assignments (same no-construct-node shape as the Rust skeleton).
  - `*T` / `*const T` pointers to scalars: `&x` address-of (plain variables
    only), `p.*` deref in expressions and as an assignment target, pointer
    variables (annotated or inferred from `&x`) and pointer fn params.
  - `[N]T` fixed arrays of scalars: `var a: [N]T = undefined;`, indexing
    `a[i]` read/write, and `a.len`.
  Postfix is single-level (fields are scalar, so `s.f.g` cannot arise;
  no `&a[i]`, no pointer-to-struct auto-deref, no array literals).

  The "theoretic completion" pass (2026-07-08) adds everything further that
  pure parse-time desugaring onto the EXISTING IR reaches (still zero
  shared-internals changes; see the per-section comments for shapes):
  - `switch` statements (hidden scrutinee temp + AN_IF chain),
  - `defer` / `errdefer` (fn-level stash, reverse replay at every exit),
  - optionals `?T` (auto-registered {__has,__val} UClass; null, assignment,
    `if (x) |v|` capture, `orelse`, `.?`),
  - error unions `!T` (errno-style global __zig_err slot, caller-clears
    convention; `return error.X`, `try`, `catch v`, `catch |e| {}`),
  - minimal slices (auto-registered __ptr+__len UClass; `a[lo..hi]`,
    `s[i]` read/write via raw pointer math, `s.len`),
  - comptime-generics, type-param subset: `fn f(comptime T: type, ...)`
    monomorphized by token-buffer substitution per explicit call-site type
    (`f(i64, x)`), mangled + cached — rparser.inc's RSpecializeGenericFn
    ported (see ZSpecializeGenericFn). NOT comptime evaluation.
  What remains is exactly the non-frontend work: a real comptime VM
  (values, control flow, builtins), record-ABI-dependent shapes (optional/
  struct/slice params and returns), and std breadth — all parked per the
  umbrella ticket; they need shared machinery, not more zparser.

  Known semantic deviations, accepted for a probe skeleton:
  - `continue` inside a `while ... : (expr)` loop skips the continue
    expression (Zig runs it); the test avoids that combination.
  - No integer overflow/underflow safety checks, no comptime — see the
    umbrella ticket's non-goals.
  - `const` is not enforced as immutable (parsed like `var`).
  - Compound assignment (`+=` …) works on plain variables only, not on
    `s.f` / `a[i]` / `p.*` targets (those take plain `=`).
  - defer/errdefer registration is lexical and fn-scoped (a defer inside a
    conditional block replays at every exit; no block scoping).
  - try/catch only as a whole statement or whole var initializer, never
    nested inside an expression; one global error slot (single-threaded);
    a defer body calling another !T function can clobber a pending error.
  - optionals/slices are locals-only (no params/returns — record ABI).
  - `/` and `%` follow the shared IR's division semantics (no divTrunc
    distinction), fine for the positive-operand test programs. }

function ZParseExpr: Integer; forward;
function ZParseBlock: Integer; forward;
function ZParseStatement: Integer; forward;
function ZParseIf: Integer; forward;
function ZSpecializeGenericFn(gfi: Integer; const concreteTypeName: AnsiString): Integer; forward;

{ ===== comptime-generics (sub-ticket #6, type-param subset) =====
  `fn f(comptime T: type, ...)` monomorphized by token-buffer substitution
  — the SAME mechanism Pascal's generics and rparser.inc's
  RSpecializeGenericFn use, ported: the fn's tokens are remembered at
  prescan, each call site `f(i64, args...)` copies them with T replaced by
  the concrete type name (and the comptime param dropped), then compiles
  the copy as an ordinary fn under a mangled name (`f$i64`), cached per
  type. Zig is easier than Rust here: the type arrives explicitly as the
  first argument, no inference. NOT comptime evaluation: no comptime
  values, no comptime control flow, no builtins — type parameters only,
  and only as the FIRST parameter. }
{ (state lives in zdefs.inc — see the prescan-bug note there) }

function ZFindGenericFn(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to ZGenericFnCount - 1 do
    if ZGenericFns[i].Name = name then begin Result := i; Exit; end;
end;

{ True when the fn signature starting at Tokens[i] (tkFn) opens with a
  `comptime` first parameter — i.e. it is a generic template, not an
  ordinary fn. }
function ZFnIsGenericAt(i: Integer): Boolean;
begin
  Result := (Tokens[i + 2].Kind = tkLParen) and
            (Tokens[i + 3].Kind = tkIdent) and (GetTokenStr(i + 3) = 'comptime');
end;

{ Zig type name -> TTypeKind. Sets LastTypeRecId when the name is a known
  struct (the AllocVar/AddUField convention every frontend uses to pass a
  record id alongside tyRecord). allowStruct=False rejects struct names —
  fn params/returns and struct fields stay scalar in this skeleton. }
function ZTypeKindFromName(const name: AnsiString; allowStruct: Boolean): TTypeKind;
var ci: Integer;
begin
  Result := tyUnknown;
  LastTypeRecId := REC_NONE;
  if name = 'i8' then Result := tyInt8
  else if name = 'u8' then Result := tyUInt8
  else if name = 'i16' then Result := tyInt16
  else if name = 'u16' then Result := tyUInt16
  else if name = 'i32' then Result := tyInteger
  else if name = 'u32' then Result := tyUInt32
  else if name = 'i64' then Result := tyInt64
  else if name = 'u64' then Result := tyUInt64
  else if name = 'isize' then Result := tyNativeInt
  else if name = 'usize' then Result := tyNativeUInt
  else if name = 'bool' then Result := tyBoolean
  { void: callers ignore the value; the unused Result slot trick C's void
    and the Rust skeleton's () already use. }
  else if name = 'void' then Result := tyInteger
  else
  begin
    ci := FindUClass(name);
    if ci >= 0 then
    begin
      if not allowStruct then
        Error('Zig: struct type ' + name + ' is only allowed for local variables in the skeleton (scalar fn params/returns and struct fields only)');
      LastTypeRecId := REC_UCLASS_BASE + ci;
      Result := tyRecord;
    end
    else
      Error('Zig: unknown type ' + name + ' (skeleton supports the fixed-width integer types, bool, void and declared struct names)');
  end;
end;

{ Prime the LastTypePointer* globals AllocVar/AllocParam read for tyPointer
  symbols: a single-level pointer to a scalar element type. }
procedure ZSetPtrType(elemTk: TTypeKind);
begin
  LastTypePointerElemTk := elemTk;
  LastTypePointerElemRec := REC_NONE;
  LastTypePointerAlias := -1;
  LastTypePointerDepth := 1;
  LastTypePointerBaseTk := Ord(elemTk);
  LastTypePointerBaseRec := REC_NONE;
end;

{ ===== defer / errdefer (fn-level, parse-time desugar) =====
  Deferred statements are stashed per function and replayed in reverse
  declaration order at every exit: normal returns + fn end run the plain
  defers; error exits (batch: error unions) run errdefer + defer both.
  DEVIATION (documented): registration is lexical, not dynamic — a defer
  written inside a conditional block still replays at every exit, and
  defers are fn-scoped, not block-scoped. Probe-skeleton semantics. }
{ (state lives in zdefs.inc — see the prescan-bug note there) }

function ZAppendDefers(seq: Integer; errPath: Boolean): Integer;
var i: Integer;
begin
  Result := seq;
  for i := ZDeferCount - 1 downto 0 do
    if errPath or not ZDeferIsErr[i] then
      Result := RSeqAppend(Result, ZDeferNode[i]);
end;

{ Builds a `return`'s AST: plain AN_EXIT when no defers; otherwise Zig
  semantics — evaluate the value into a hidden temp FIRST, replay the
  plain defers, then exit with the temp. The value expression (if hasVal)
  is parsed from the current position; terminators are the caller's. }
function ZMakeReturn(hasVal: Boolean): Integer;
var seq, node, tmpSym: Integer;
begin
  if ZDeferCount = 0 then
  begin
    node := AllocNode(AN_EXIT);
    if hasVal then ASTLeft[node] := ZParseExpr;
    Result := node;
    Exit;
  end;
  seq := -1;
  if hasVal then
  begin
    tmpSym := AllocVar('', Procs[CurProc].RetType);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(tmpSym);
    ASTRight[node] := ZParseExpr;
    seq := RSeqAppend(seq, node);
    seq := ZAppendDefers(seq, False);
    node := AllocNode(AN_EXIT);
    ASTLeft[node] := RMakeIdent(tmpSym);
    seq := RSeqAppend(seq, node);
  end
  else
  begin
    seq := ZAppendDefers(seq, False);
    seq := RSeqAppend(seq, AllocNode(AN_EXIT));
  end;
  Result := seq;
end;

{ ===== optionals (?T) and error unions (!T) — parse-time desugars =====

  ?T: one auto-registered UClass per element type, named "?i64" etc, with
  __has (i64 @0) + __val (T @8) — 16 bytes, the same tag+payload shape the
  Rust skeleton's enums use, zero new machinery. `x = null` / `x = expr` /
  `orelse` / `if (x) |v|` / `x.?` all lower to field reads/writes on it.
  Locals only (no optional params/returns — record ABI is out of scope).

  !T: an errno-style GLOBAL error slot (__zig_err : i64, BSS). Convention:
  the CALLER clears the slot before an erroring call (try/catch do), the
  callee sets it only on `return error.X`; error names auto-register into
  a global name->code table (codes start at 1). `try f()` = clear, call,
  propagate-if-set (errdefer + defer replay, then exit); `catch` = clear,
  call, on-error run the |e| handler or swallow. Scalar payload returns
  ride the normal return value. DEVIATIONS (documented): single-threaded
  by construction (one global slot); `try`/`catch` are allowed only as a
  whole var-decl initializer or a whole statement, not nested inside
  expressions; a defer body that itself calls an erroring function will
  clobber a pending error slot. }
{ (state lives in zdefs.inc — see the prescan-bug note there) }

function ZTypeNameOf(tk: TTypeKind): AnsiString;
begin
  case tk of
    tyInt8: Result := 'i8';
    tyUInt8: Result := 'u8';
    tyInt16: Result := 'i16';
    tyUInt16: Result := 'u16';
    tyInteger: Result := 'i32';
    tyUInt32: Result := 'u32';
    tyInt64: Result := 'i64';
    tyUInt64: Result := 'u64';
    tyNativeInt: Result := 'isize';
    tyNativeUInt: Result := 'usize';
    tyBoolean: Result := 'bool';
    else Result := '?';
  end;
end;

function ZOptClassFor(elemTk: TTypeKind): Integer;
var name: AnsiString; ci: Integer;
begin
  name := '?' + ZTypeNameOf(elemTk);
  ci := FindUClass(name);
  if ci < 0 then
  begin
    ci := AddUClass(RStoredName(name), Length(name));
    UClsIsRecord[ci] := True;
    AddUField(ci, RStoredName('__has'), 5, 0, Ord(tyInt64), REC_NONE);
    AddUField(ci, RStoredName('__val'), 5, 8, Ord(elemTk), REC_NONE);
    UClsAlign[ci] := 8;
    UClsSize_[ci] := 16;
    ZOptCi[ci] := True;
  end;
  Result := ci;
end;

function ZIsOptSym(symIdx: Integer): Boolean;
begin
  Result := (Syms[symIdx].TypeKind = tyRecord) and
            (Syms[symIdx].RecName >= REC_UCLASS_BASE) and
            ZOptCi[Syms[symIdx].RecName - REC_UCLASS_BASE];
end;

{ ===== slices (probe-minimal): `var s = a[lo..hi];` over a fixed array =====
  One auto-registered UClass per element type, named "[]i64" etc, holding
  __ptr (raw element address as i64 @0) + __len (i64 @8). `s[i]` lowers to
  AN_DEREF(__ptr + i*elemsize) — the same raw-int64-pointer-math trick the
  C frontend's partial-index decay uses — and works as an assign target;
  `s.len` reads __len. No slice params/returns, no slice-of-slice, no
  re-slicing, no bounds checks. }
{ (state lives in zdefs.inc — see the prescan-bug note there) }

function ZSliceClassFor(elemTk: TTypeKind): Integer;
var name: AnsiString; ci: Integer;
begin
  name := '[]' + ZTypeNameOf(elemTk);
  ci := FindUClass(name);
  if ci < 0 then
  begin
    ci := AddUClass(RStoredName(name), Length(name));
    UClsIsRecord[ci] := True;
    AddUField(ci, RStoredName('__ptr'), 5, 0, Ord(tyInt64), REC_NONE);
    AddUField(ci, RStoredName('__len'), 5, 8, Ord(tyInt64), REC_NONE);
    UClsAlign[ci] := 8;
    UClsSize_[ci] := 16;
    ZSliceCi[ci] := True;
    ZSliceElemTk[ci] := elemTk;
  end;
  Result := ci;
end;

function ZIsSliceSym(symIdx: Integer): Boolean;
begin
  Result := (Syms[symIdx].TypeKind = tyRecord) and
            (Syms[symIdx].RecName >= REC_UCLASS_BASE) and
            ZSliceCi[Syms[symIdx].RecName - REC_UCLASS_BASE];
end;

{ True when the bracket run starting at Tokens[TokPos] (the `[`) contains a
  top-level `..` — i.e. `name[lo..hi]` is a slice, not an index. }
function ZBrackHasDotDot: Boolean;
var k, depth: Integer;
begin
  Result := False;
  k := TokPos + 1;
  depth := 1;
  while (depth > 0) and (Tokens[k].Kind <> tkEOF) do
  begin
    if Tokens[k].Kind = tkLBrack then Inc(depth)
    else if Tokens[k].Kind = tkRBrack then Dec(depth)
    else if (Tokens[k].Kind = tkDotDot) and (depth = 1) then
    begin
      Result := True;
      Exit;
    end;
    Inc(k);
  end;
end;

function ZFieldNode(baseNode: Integer; const fname: AnsiString; ftk: TTypeKind): Integer;
begin
  Result := AllocNode(AN_FIELD);
  ASTLeft[Result] := baseNode;
  ASTSOffset[Result] := RStoredName(fname);
  ASTSLen[Result] := Length(fname);
  ASTTk[Result] := Ord(ftk);
end;

function ZIntLit(v: Int64): Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyInt64);
end;

function ZAssignNode(lhs, rhs: Integer): Integer;
begin
  Result := AllocNode(AN_ASSIGN);
  ASTLeft[Result] := lhs;
  ASTRight[Result] := rhs;
end;

function ZErrCode(const name: AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to ZErrCount - 1 do
    if ZErrName[i] = name then begin Result := i + 1; Exit; end;
  if ZErrCount >= 256 then Error('Zig: too many error names (skeleton limit 256)');
  ZErrName[ZErrCount] := name;
  Inc(ZErrCount);
  Result := ZErrCount;
end;

{ `__zig_err <> 0` condition node. }
function ZErrSetCond: Integer;
begin
  Result := RBinOp(tkNeq, RMakeIdent(ZErrSlotSym), ZIntLit(0), tyBoolean);
end;

{ AN_IF(cond, PAIR(thenNode, elseNode)) }
function ZIfNode(condNode, thenNode, elseNode: Integer): Integer;
var pairNode: Integer;
begin
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  Result := AllocNode(AN_IF);
  ASTLeft[Result] := condNode;
  ASTRight[Result] := pairNode;
end;

function ZParsePrimary: Integer;
var node, symIdx, procIdx, argNode, lastArg, idxNode, postNode, fTokIdx, gfi: Integer;
    name, typeName: AnsiString;
begin
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyInteger);
      Next; Result := node;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkString:
    begin
      node := AllocNode(AN_STR_LIT);
      ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
      ASTSLen[node] := Tokens[TokPos - 1].SLen;
      ASTTk[node] := Ord(tyString);
      Next; Result := node;
    end;
    tkLParen:
    begin
      Next; node := ZParseExpr; Expect(tkRParen, ')'); Result := node;
    end;
    tkIdent:
    begin
      name := CurTok.SVal;
      if (Length(name) > 0) and (name[1] = '@') then
        Error('Zig: builtin ' + name + ' is not supported by the frontend skeleton (feature-zig-frontend)');
      { `error.Name` as a value — the error's i64 code (e.g. for comparing
        a caught |e| against a specific error). }
      if (name = 'error') and (Tokens[TokPos].Kind = tkDot) then
      begin
        Next; Next; { error . }
        if CurTok.Kind <> tkIdent then Error('Zig: expected error name after error.');
        Result := ZIntLit(ZErrCode(CurTok.SVal));
        Next;
        Exit;
      end;
      Next;
      if CurTok.Kind = tkLParen then
      begin
        procIdx := FindProc(name);
        if procIdx < 0 then
        begin
          { generic call `f(i64, args...)` — the explicit type argument
            selects/creates the specialization, then drops out of the
            emitted argument list. }
          gfi := ZFindGenericFn(name);
          if gfi < 0 then Error('Zig: call to undefined function ' + name);
          Next; { ( }
          if CurTok.Kind <> tkIdent then
            Error('Zig: generic fn ' + name + ' needs a type name as its first argument');
          typeName := CurTok.SVal;
          Next;
          procIdx := ZSpecializeGenericFn(gfi, typeName);
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTTk[node] := Ord(Procs[procIdx].RetType);
          lastArg := -1;
          if Eat(tkComma) then
            repeat
              argNode := AllocNode(AN_ARG);
              ASTLeft[argNode] := ZParseExpr;
              ASTRight[argNode] := -1;
              if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
              lastArg := argNode;
            until not Eat(tkComma);
          Expect(tkRParen, ')');
          Result := node;
          Exit;
        end;
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        lastArg := -1;
        if CurTok.Kind <> tkRParen then
          repeat
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := ZParseExpr;
            ASTRight[argNode] := -1;
            if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
            lastArg := argNode;
          until not Eat(tkComma);
        Expect(tkRParen, ')');
        Result := node;
        Exit;
      end;
      symIdx := FindSym(name);
      if symIdx < 0 then Error('Zig: undefined variable ' + name);
      node := RMakeIdent(symIdx);
      { Postfix: a[i] / s.field / p.* / a.len — single level only (struct
        fields are scalar in the skeleton, so chains cannot arise). }
      if (CurTok.Kind = tkLBrack) and ZIsSliceSym(symIdx) then
      begin
        { s[i] — AN_DEREF(__ptr + i*elemsize), raw i64 pointer math (the C
          frontend's decay trick); reads and assignment targets both work. }
        Next;
        idxNode := ZParseExpr;
        Expect(tkRBrack, ']');
        postNode := AllocNode(AN_DEREF);
        ASTLeft[postNode] := RBinOp(tkPlus,
          ZFieldNode(node, '__ptr', tyInt64),
          RBinOp(tkStar, idxNode,
            ZIntLit(TypeSize(ZSliceElemTk[Syms[symIdx].RecName - REC_UCLASS_BASE])),
            tyInt64),
          tyInt64);
        ASTTk[postNode] := Ord(ZSliceElemTk[Syms[symIdx].RecName - REC_UCLASS_BASE]);
        node := postNode;
      end
      else if CurTok.Kind = tkLBrack then
      begin
        if not Syms[symIdx].IsArray then Error('Zig: [] index on non-array variable ' + name);
        Next;
        idxNode := ZParseExpr;
        Expect(tkRBrack, ']');
        postNode := AllocNode(AN_INDEX);
        ASTLeft[postNode] := node;
        ASTRight[postNode] := idxNode;
        ASTTk[postNode] := Ord(Syms[symIdx].ElemType);
        node := postNode;
      end
      else if CurTok.Kind = tkDot then
      begin
        Next;
        if CurTok.Kind = tkStar then
        begin
          if Syms[symIdx].TypeKind <> tyPointer then Error('Zig: .* deref on non-pointer variable ' + name);
          Next;
          postNode := AllocNode(AN_DEREF);
          ASTLeft[postNode] := node;
          ASTTk[postNode] := Ord(Syms[symIdx].PtrElemTk);
          node := postNode;
        end
        else if CurTok.Kind = tkQuestion then
        begin
          { `x.?` unwrap — no safety check (skeleton: undefined behaviour on
            null, matching Zig's ReleaseFast semantics). }
          if not ZIsOptSym(symIdx) then Error('Zig: .? on non-optional variable ' + name);
          Next;
          node := ZFieldNode(node, '__val',
            RecFieldType(Syms[symIdx].RecName, '__val'));
        end
        else if (CurTok.Kind = tkIdent) and Syms[symIdx].IsArray and (CurTok.SVal = 'len') then
        begin
          { Fixed-size array: .len is a compile-time constant. }
          Next;
          postNode := AllocNode(AN_INT_LIT);
          ASTIVal[postNode] := Syms[symIdx].ArrLen;
          ASTTk[postNode] := Ord(tyInt64);
          node := postNode;
        end
        else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'len') and ZIsSliceSym(symIdx) then
        begin
          { slice .len — the runtime __len field }
          Next;
          node := ZFieldNode(node, '__len', tyInt64);
        end
        else if CurTok.Kind = tkIdent then
        begin
          if Syms[symIdx].TypeKind <> tyRecord then Error('Zig: field access on non-struct variable ' + name);
          fTokIdx := TokPos - 1;
          postNode := AllocNode(AN_FIELD);
          ASTLeft[postNode] := node;
          ASTSOffset[postNode] := Tokens[fTokIdx].SOffset;
          ASTSLen[postNode] := Tokens[fTokIdx].SLen;
          ASTTk[postNode] := Ord(RecFieldType(Syms[symIdx].RecName, CurTok.SVal));
          node := postNode;
          Next;
        end
        else Error('Zig: expected field name, * or len after .');
      end;
      Result := node;
    end;
    else
    begin
      Error('Zig: unexpected token in expression');
      Result := -1;
    end;
  end;
end;

function ZParseUnary: Integer;
var node, symIdx: Integer;
begin
  if CurTok.Kind = tkAmp then
  begin
    { &x address-of — plain variables only (no &a[i] / &s.f in the skeleton;
      keeping the operand an AN_IDENT also lets var-decl inference read the
      addressed symbol's type straight off ASTLeft). }
    Next;
    if CurTok.Kind <> tkIdent then Error('Zig: & needs a plain variable operand (skeleton)');
    symIdx := FindSym(CurTok.SVal);
    if symIdx < 0 then Error('Zig: undefined variable ' + CurTok.SVal);
    if Syms[symIdx].IsArray or (Syms[symIdx].TypeKind = tyRecord) then
      Error('Zig: & on arrays/structs is not supported by the skeleton');
    Next;
    node := AllocNode(AN_ADDR);
    ASTLeft[node] := RMakeIdent(symIdx);
    ASTTk[node] := Ord(tyPointer);
    Result := node;
    Exit;
  end;
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    ASTLeft[node] := ZParseUnary();
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node;
    Exit;
  end;
  if CurTok.Kind = tkLogNot then
  begin
    Next;
    node := AllocNode(AN_NOT);
    ASTLeft[node] := ZParseUnary();
    ASTTk[node] := Ord(tyBoolean);
    Result := node;
    Exit;
  end;
  Result := ZParsePrimary;
end;

function ZParseMul: Integer;
var left, right: Integer; opTk: TTokenKind; rt: TTypeKind;
begin
  left := ZParseUnary;
  while CurTok.Kind in [tkStar, tkSlash, tkMod] do
  begin
    opTk := CurTok.Kind; Next;
    right := ZParseUnary;
    rt := RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]));
    { Zig / on integers is trunc division — the shared tkSlash BINOP is
      Pascal's REAL division (yields double bits; reinterpreted as int64
      that's garbage, found by the probe's own first run). All skeleton
      types are integers, so lower / as tkDiv (integer div) always. }
    if opTk = tkSlash then opTk := tkDiv;
    left := RBinOp(opTk, left, right, rt);
  end;
  Result := left;
end;

function ZParseAdd: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := ZParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := ZParseMul;
    left := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
  end;
  Result := left;
end;

function ZParseCmp: Integer;
var left, right: Integer; opTk: TTokenKind;
begin
  left := ZParseAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := ZParseAdd;
    left := RBinOp(opTk, left, right, tyBoolean);
  end;
  Result := left;
end;

function ZParseAnd: Integer;
var left, right: Integer;
begin
  left := ZParseCmp;
  while CurTok.Kind = tkAnd do
  begin
    Next;
    right := ZParseCmp;
    left := RBinOp(tkAnd, left, right, tyBoolean);
  end;
  Result := left;
end;

function ZParseExpr: Integer;
var left, right, symIdx, tern, pairNode: Integer;
    elemTk: TTypeKind;
begin
  left := ZParseAnd;
  while CurTok.Kind = tkOr do
  begin
    Next;
    right := ZParseAnd;
    left := RBinOp(tkOr, left, right, tyBoolean);
  end;
  { `x orelse default` — value select via AN_TERNARY (the C frontend's
    node): has ? val : default. x must be a plain optional variable. }
  while (CurTok.Kind = tkIdent) and (CurTok.SVal = 'orelse') do
  begin
    if (ASTKind[left] <> AN_IDENT) or not ZIsOptSym(ASTIVal[left]) then
      Error('Zig: orelse needs a plain optional variable on its left (skeleton)');
    symIdx := ASTIVal[left];
    elemTk := RecFieldType(Syms[symIdx].RecName, '__val');
    Next;
    right := ZParseAnd;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := ZFieldNode(RMakeIdent(symIdx), '__val', elemTk);
    ASTRight[pairNode] := right;
    tern := AllocNode(AN_TERNARY);
    ASTLeft[tern] := RBinOp(tkNeq, ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64),
                            ZIntLit(0), tyBoolean);
    ASTRight[tern] := pairNode;
    ASTTk[tern] := Ord(elemTk);
    left := tern;
  end;
  Result := left;
end;

function ZParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode, symIdx, vSym, capAssign: Integer;
    vname: AnsiString;
    elemTk: TTypeKind;
begin
  Next; { if }
  Expect(tkLParen, '(');   { Zig requires parens around the condition }
  condNode := ZParseExpr;
  Expect(tkRParen, ')');
  capAssign := -1;
  if CurTok.Kind = tkPipe then
  begin
    { `if (x) |v| { ... }` — optional unwrap-capture: condition becomes
      x.__has <> 0 and the then-block starts with v := x.__val (v is an
      ordinary fresh local, the Rust match-bind trick). }
    if (ASTKind[condNode] <> AN_IDENT) or not ZIsOptSym(ASTIVal[condNode]) then
      Error('Zig: |capture| needs a plain optional variable condition (skeleton)');
    symIdx := ASTIVal[condNode];
    elemTk := RecFieldType(Syms[symIdx].RecName, '__val');
    Next;
    if CurTok.Kind <> tkIdent then Error('Zig: expected capture name in |x|');
    vname := CurTok.SVal;
    Next;
    Expect(tkPipe, '|');
    vSym := AllocVar(vname, elemTk);
    capAssign := ZAssignNode(RMakeIdent(vSym),
      ZFieldNode(RMakeIdent(symIdx), '__val', elemTk));
    condNode := RBinOp(tkNeq, ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64),
                       ZIntLit(0), tyBoolean);
  end;
  Expect(tkBegin, '{');
  thenNode := ZParseBlock;
  Expect(tkEnd, '}');
  if capAssign >= 0 then
    thenNode := RSeqAppend(RSeqAppend(-1, capAssign), thenNode);
  elseNode := -1;
  if CurTok.Kind = tkElse then
  begin
    Next;
    if CurTok.Kind = tkIf then
      { Parens force a real recursive call — a bare name here would read the
        implicit Result alias instead (documented project pitfall, see
        frank2-paramless-name-semantics / rparser.inc's identical comment). }
      elseNode := ZParseIf()
    else
    begin
      Expect(tkBegin, '{');
      elseNode := ZParseBlock;
      Expect(tkEnd, '}');
    end;
  end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

{ Shared by plain assignment statements and the while-loop continue
  expression: `name = expr` / `name op= expr`, desugaring compound forms to
  name = name op expr. Does NOT consume a trailing `;`. }
function ZParseAssign: Integer;
var name: AnsiString; symIdx, rhsNode, node, seq: Integer; opTk: TTokenKind;
    elemTk: TTypeKind;
begin
  if CurTok.Kind <> tkIdent then Error('Zig: expected variable name in assignment');
  name := CurTok.SVal;
  symIdx := FindSym(name);
  if symIdx < 0 then Error('Zig: assignment to undefined variable ' + name);
  Next;
  opTk := CurTok.Kind;
  if not (opTk in [tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq]) then
    Error('Zig: expected = or compound assignment after ' + name);
  Next;
  if ZIsOptSym(symIdx) then
  begin
    { optional variable: `x = null` clears, `x = expr` sets tag+payload }
    if opTk <> tkAssign then Error('Zig: optionals only take plain = (skeleton)');
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'null') then
    begin
      Next;
      Result := ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64), ZIntLit(0));
      Exit;
    end;
    elemTk := RecFieldType(Syms[symIdx].RecName, '__val');
    rhsNode := ZParseExpr;
    seq := RSeqAppend(-1, ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64), ZIntLit(1)));
    Result := RSeqAppend(seq, ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__val', elemTk), rhsNode));
    Exit;
  end;
  rhsNode := ZParseExpr;
  case opTk of
    tkPlusEq:  rhsNode := RBinOp(tkPlus,  RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    tkMinusEq: rhsNode := RBinOp(tkMinus, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    tkStarEq:  rhsNode := RBinOp(tkStar,  RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    tkSlashEq: rhsNode := RBinOp(tkSlash, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
    else ;
  end;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := RMakeIdent(symIdx);
  ASTRight[node] := rhsNode;
  Result := node;
end;

function ZParseWhile: Integer;
var node, condNode, bodyNode, contNode: Integer;
begin
  Next; { while }
  Expect(tkLParen, '(');
  condNode := ZParseExpr;
  Expect(tkRParen, ')');
  contNode := -1;
  if CurTok.Kind = tkColon then
  begin
    { `while (cond) : (i += 1) { ... }` — the continue expression runs after
      each iteration; desugared by appending it to the body end. (Deviation:
      `continue` skips it here — see the header note.) }
    Next;
    Expect(tkLParen, '(');
    contNode := ZParseAssign;
    Expect(tkRParen, ')');
  end;
  Expect(tkBegin, '{');
  bodyNode := ZParseBlock;
  Expect(tkEnd, '}');
  if contNode <> -1 then
    bodyNode := RSeqAppend(bodyNode, contNode);
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := condNode;
  ASTRight[node] := bodyNode;
  Result := node;
end;

{ `for (lo..hi) |name| { ... }` — Zig's range for; upper bound EXCLUSIVE
  (unlike Pascal/Ada/BASIC), so the desugared loop compares with < :
  i := lo; while i < hi { body; i := i + 1 } — same AN_ASSIGN/AN_WHILE
  shape aparser.inc's for-lowering uses. }
function ZParseFor: Integer;
var vname: AnsiString;
    symIdx, loNode, hiNode, bodyNode, initNode, condNode, incNode, oneNode, whileNode: Integer;
begin
  Next; { for }
  Expect(tkLParen, '(');
  loNode := ZParseExpr;
  Expect(tkDotDot, '..');
  hiNode := ZParseExpr;
  Expect(tkRParen, ')');
  Expect(tkPipe, '|');
  if CurTok.Kind <> tkIdent then Error('Zig: expected capture name in |x|');
  vname := CurTok.SVal;
  Next;
  Expect(tkPipe, '|');

  symIdx := AllocVar(vname, tyInt64);

  Expect(tkBegin, '{');
  bodyNode := ZParseBlock;
  Expect(tkEnd, '}');

  initNode := AllocNode(AN_ASSIGN);
  ASTLeft[initNode] := RMakeIdent(symIdx);
  ASTRight[initNode] := loNode;

  condNode := RBinOp(tkLt, RMakeIdent(symIdx), hiNode, tyBoolean);

  incNode := AllocNode(AN_INT_LIT);
  ASTIVal[incNode] := 1;
  ASTTk[incNode] := Ord(tyInteger);
  incNode := RBinOp(tkPlus, RMakeIdent(symIdx), incNode, tyInt64);
  oneNode := incNode;
  incNode := AllocNode(AN_ASSIGN);
  ASTLeft[incNode] := RMakeIdent(symIdx);
  ASTRight[incNode] := oneNode;
  bodyNode := RSeqAppend(bodyNode, incNode);

  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := condNode;
  ASTRight[whileNode] := bodyNode;

  Result := RSeqAppend(RSeqAppend(-1, initNode), whileNode);
end;

{ `try f(...);` statement (value discarded): clear slot, call, propagate
  (errdefer+defer replay + exit) if the callee set the slot. }
function ZTryStmt: Integer;
var callNode, seq, propSeq: Integer;
begin
  callNode := ZParseExpr;
  if (ASTKind[callNode] <> AN_CALL) or not ZProcErrs[ASTIVal[callNode]] then
    Error('Zig: try needs a direct call to a !T function (skeleton)');
  if (CurProc < 0) or not ZProcErrs[CurProc] then
    Error('Zig: try requires the enclosing function to return !T (use catch instead)');
  seq := RSeqAppend(-1, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
  seq := RSeqAppend(seq, callNode);
  propSeq := ZAppendDefers(-1, True);
  propSeq := RSeqAppend(propSeq, AllocNode(AN_EXIT));
  Result := RSeqAppend(seq, ZIfNode(ZErrSetCond, propSeq, -1));
end;

{ `var x = try f(...);` body: clear slot, call into the fresh variable,
  propagate (errdefer+defer replay, exit) if the callee set the slot. }
function ZTryVarInit(const name: AnsiString; hasType: Boolean; vtype: TTypeKind): Integer;
var callNode, symIdx, seq, propSeq: Integer;
begin
  callNode := ZParseExpr;
  if (ASTKind[callNode] <> AN_CALL) or not ZProcErrs[ASTIVal[callNode]] then
    Error('Zig: try needs a direct call to a !T function (skeleton)');
  if (CurProc < 0) or not ZProcErrs[CurProc] then
    Error('Zig: try requires the enclosing function to return !T (use catch instead)');
  if not hasType then vtype := IntToTypeKind(ASTTk[callNode]);
  symIdx := AllocVar(name, vtype);
  seq := RSeqAppend(-1, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
  seq := RSeqAppend(seq, ZAssignNode(RMakeIdent(symIdx), callNode));
  propSeq := ZAppendDefers(-1, True);
  propSeq := RSeqAppend(propSeq, AllocNode(AN_EXIT));
  Result := RSeqAppend(seq, ZIfNode(ZErrSetCond, propSeq, -1));
end;

{ `var name [: T] = expr;` / `const name [: T] = expr;` — const is parsed
  like var (no immutability enforcement in the skeleton). `= undefined`
  declares without initializing. Type inferred from the initializer when
  no annotation is given (Zig infers pervasively). Annotation forms:
  scalar name, struct name, `*T` / `*const T` (scalar T), `[N]T` (scalar T,
  N an integer literal; arrays take `= undefined` only — no array
  literals). RHS forms besides plain expressions: a struct literal
  `Name{ .f = expr, ... }` lowered to per-field assignments (the Rust
  skeleton's no-construct-node shape), and `&x` whose pointer type is
  inferred from the addressed variable. Trailing `;` left to the caller. }
function ZParseVarDecl: Integer;
var name, fname: AnsiString;
    symIdx, rhsNode, node, ci, fTokIdx, identNode, fieldNode, seq, arrLen: Integer;
    vtype, ptrElemTk, arrElemTk, optElemTk: TTypeKind;
    hasType, isPtr, isArr, isOpt: Boolean;
    declRec: Integer;
begin
  Next; { var / const }
  if CurTok.Kind <> tkIdent then Error('Zig: expected name after var/const');
  name := CurTok.SVal;
  Next;
  vtype := tyInt64; hasType := False; declRec := REC_NONE;
  isPtr := False; ptrElemTk := tyUnknown;
  isArr := False; arrElemTk := tyUnknown; arrLen := 0;
  isOpt := False; optElemTk := tyUnknown;
  if CurTok.Kind = tkColon then
  begin
    Next;
    if CurTok.Kind = tkStar then
    begin
      Next;
      if CurTok.Kind = tkConst then Next; { *const T — constness ignored }
      if CurTok.Kind <> tkIdent then Error('Zig: expected type name after *');
      ptrElemTk := ZTypeKindFromName(CurTok.SVal, False);
      isPtr := True;
      Next;
    end
    else if CurTok.Kind = tkQuestion then
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('Zig: expected scalar type after ?');
      optElemTk := ZTypeKindFromName(CurTok.SVal, False);
      isOpt := True;
      Next;
    end
    else if CurTok.Kind = tkLBrack then
    begin
      Next;
      if CurTok.Kind <> tkInteger then Error('Zig: array size must be an integer literal (skeleton)');
      arrLen := CurTok.IVal;
      if arrLen <= 0 then Error('Zig: array size must be positive');
      Next;
      Expect(tkRBrack, ']');
      if CurTok.Kind <> tkIdent then Error('Zig: expected element type after [N]');
      arrElemTk := ZTypeKindFromName(CurTok.SVal, False);
      isArr := True;
      Next;
    end
    else
    begin
      if CurTok.Kind <> tkIdent then Error('Zig: expected type name after :');
      vtype := ZTypeKindFromName(CurTok.SVal, True);
      declRec := LastTypeRecId;
      Next;
    end;
    hasType := True;
  end;
  Expect(tkAssign, '=');
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'undefined') then
  begin
    Next;
    if not hasType then Error('Zig: `= undefined` needs an explicit type annotation');
    if isArr then AllocArray(name, arrElemTk, 0, arrLen - 1)
    else if isPtr then
    begin
      ZSetPtrType(ptrElemTk);
      AllocVar(name, tyPointer);
    end
    else if isOpt then
    begin
      { safer-than-Zig deviation: an undefined optional starts as null so
        `if (x)` on it is well-defined. }
      LastTypeRecId := REC_UCLASS_BASE + ZOptClassFor(optElemTk);
      symIdx := AllocVar(name, tyRecord);
      Result := ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64), ZIntLit(0));
      Exit;
    end
    else
    begin
      LastTypeRecId := declRec;
      AllocVar(name, vtype);
    end;
    Result := -1;
    Exit;
  end;
  { `= null` — optional set to none }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'null') then
  begin
    Next;
    if not isOpt then Error('Zig: null initializer needs a ?T annotation (skeleton)');
    LastTypeRecId := REC_UCLASS_BASE + ZOptClassFor(optElemTk);
    symIdx := AllocVar(name, tyRecord);
    Result := ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64), ZIntLit(0));
    Exit;
  end;
  if isArr then Error('Zig: arrays only take `= undefined` (no array literals in the skeleton)');
  { `= try f(...)` — clear the error slot, call, propagate on error, else
    the payload lands in the fresh variable. Whole-initializer form only. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'try') then
  begin
    if isOpt or isPtr then Error('Zig: try initializer for a scalar variable only (skeleton)');
    Next;
    Result := ZTryVarInit(name, hasType, vtype);
    Exit;
  end;
  { struct literal RHS: `Name{ .f = expr, ... }` }
  if (CurTok.Kind = tkIdent) and (FindUClass(CurTok.SVal) >= 0) and
     (Tokens[TokPos].Kind = tkBegin) then
  begin
    if isPtr then Error('Zig: struct literal assigned to a pointer variable');
    ci := FindUClass(CurTok.SVal);
    if hasType and (declRec <> REC_UCLASS_BASE + ci) then
      Error('Zig: struct literal type does not match the annotation');
    Next; Expect(tkBegin, '{');
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    identNode := RMakeIdent(symIdx);
    seq := -1;
    while CurTok.Kind <> tkEnd do
    begin
      Expect(tkDot, '.');
      if CurTok.Kind <> tkIdent then Error('Zig: expected field name after . in struct literal');
      fname := CurTok.SVal;
      fTokIdx := TokPos - 1;
      Next;
      Expect(tkAssign, '=');
      rhsNode := ZParseExpr;
      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := identNode;
      ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
      ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
      ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, fname));
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := fieldNode;
      ASTRight[node] := rhsNode;
      seq := RSeqAppend(seq, node);
      if not Eat(tkComma) then Break;
    end;
    Expect(tkEnd, '}');
    Result := seq;
    Exit;
  end;
  { `var s = arr[lo..hi];` — slice creation, initializer position only:
    __ptr := &arr[lo] (AN_ADDR over AN_INDEX — IRLowerAddress computes the
    element address), __len := hi - lo (exclusive hi, as in Zig). }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkLBrack) and
     ZBrackHasDotDot then
  begin
    if hasType then Error('Zig: slice variables infer their type from the initializer (skeleton)');
    symIdx := FindSym(CurTok.SVal);
    if (symIdx < 0) or not Syms[symIdx].IsArray then
      Error('Zig: slicing needs a fixed-array variable (skeleton)');
    arrElemTk := Syms[symIdx].ElemType;
    Next;
    Expect(tkLBrack, '[');
    rhsNode := ZParseExpr;   { lo }
    Expect(tkDotDot, '..');
    node := ZParseExpr;      { hi (exclusive) }
    Expect(tkRBrack, ']');
    ci := ZSliceClassFor(arrElemTk);
    fieldNode := AllocNode(AN_INDEX);
    ASTLeft[fieldNode] := RMakeIdent(symIdx);
    ASTRight[fieldNode] := rhsNode;
    ASTTk[fieldNode] := Ord(arrElemTk);
    identNode := AllocNode(AN_ADDR);
    ASTLeft[identNode] := fieldNode;
    ASTTk[identNode] := Ord(tyPointer);
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    seq := RSeqAppend(-1,
      ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__ptr', tyInt64), identNode));
    Result := RSeqAppend(seq,
      ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__len', tyInt64),
        RBinOp(tkMinus, node, rhsNode, tyInt64)));
    Exit;
  end;
  rhsNode := ZParseExpr;
  { `var x = f() catch default;` — clear-before-call, call, on-error take
    the default and swallow the error. Whole-initializer form only. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'catch') then
  begin
    if isOpt or isPtr then Error('Zig: catch initializer for a scalar variable only (skeleton)');
    if (ASTKind[rhsNode] <> AN_CALL) or not ZProcErrs[ASTIVal[rhsNode]] then
      Error('Zig: catch needs a direct call to a !T function on its left (skeleton)');
    Next;
    if CurTok.Kind = tkPipe then Error('Zig: catch |e| is a statement form; a catch initializer takes a default value (skeleton)');
    if not hasType then vtype := IntToTypeKind(ASTTk[rhsNode]);
    symIdx := AllocVar(name, vtype);
    seq := RSeqAppend(-1, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
    seq := RSeqAppend(seq, ZAssignNode(RMakeIdent(symIdx), rhsNode));
    node := RSeqAppend(-1, ZAssignNode(RMakeIdent(symIdx), ZParseExpr));
    node := RSeqAppend(node, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
    Result := RSeqAppend(seq, ZIfNode(ZErrSetCond, node, -1));
    Exit;
  end;
  if isOpt then
  begin
    { `var x: ?T = expr;` — some(expr) }
    LastTypeRecId := REC_UCLASS_BASE + ZOptClassFor(optElemTk);
    symIdx := AllocVar(name, tyRecord);
    seq := RSeqAppend(-1, ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__has', tyInt64), ZIntLit(1)));
    Result := RSeqAppend(seq, ZAssignNode(ZFieldNode(RMakeIdent(symIdx), '__val', optElemTk), rhsNode));
    Exit;
  end;
  if isPtr then
  begin
    ZSetPtrType(ptrElemTk);
    symIdx := AllocVar(name, tyPointer);
  end
  else if hasType then
  begin
    if vtype = tyRecord then Error('Zig: struct variables take `= undefined` or a struct literal');
    symIdx := AllocVar(name, vtype);
  end
  else if ASTKind[rhsNode] = AN_ADDR then
  begin
    { `const p = &x;` — pointer type inferred from the addressed variable
      (ZParseUnary guarantees ASTLeft is an AN_IDENT). }
    ZSetPtrType(Syms[ASTIVal[ASTLeft[rhsNode]]].TypeKind);
    symIdx := AllocVar(name, tyPointer);
  end
  else
  begin
    vtype := IntToTypeKind(ASTTk[rhsNode]);
    if vtype = tyUnknown then vtype := tyInt64;
    { Zig's `const x = 42` makes a comptime_int; the closest runtime type
      the skeleton has is i64 for integers, so widen small literals. }
    if vtype = tyInteger then vtype := tyInt64;
    symIdx := AllocVar(name, vtype);
  end;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := RMakeIdent(symIdx);
  ASTRight[node] := rhsNode;
  Result := node;
end;

{ `std.debug.print("fmt", .{arg, ...});` — the only std call the skeleton
  understands. The fmt string is split on {...} placeholders; literal
  segments become AN_STR_LIT nodes pointing straight into the fmt token's
  already-decoded TokChars bytes (segments are substrings, so offset
  arithmetic suffices — no copying), each placeholder consumes the next
  .{...} argument, and everything is chained as one AN_ARG list under a
  single AN_WRITE / AN_WRITELN (WRITELN when fmt ends in \n, which is then
  stripped), exactly the shape BASIC's PRINT emits. {{ }} escapes are not
  handled (skeleton). }
function ZParseStdDebugPrint: Integer;
var fmtOff, fmtLen, i, segStart: Integer;
    node, lastArg, argNode, litNode: Integer;
    argExprs: array[0..7] of Integer;
    argCount, argUsed: Integer;
    isLn: Boolean;

  procedure AddArg(exprNode: Integer);
  begin
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := exprNode;
    ASTRight[argNode] := -1;
    if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
    lastArg := argNode;
  end;

  procedure AddSegment(off, len: Integer);
  begin
    if len <= 0 then Exit;
    litNode := AllocNode(AN_STR_LIT);
    ASTSOffset[litNode] := off;
    ASTSLen[litNode] := len;
    ASTTk[litNode] := Ord(tyString);
    AddArg(litNode);
  end;

begin
  Next; { std }
  Expect(tkDot, '.');
  if not ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'debug')) then
    Error('Zig: only std.debug.print is supported by the frontend skeleton');
  Next;
  Expect(tkDot, '.');
  if not ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'print')) then
    Error('Zig: only std.debug.print is supported by the frontend skeleton');
  Next;
  Expect(tkLParen, '(');
  if CurTok.Kind <> tkString then Error('Zig: std.debug.print needs a string literal format');
  fmtOff := Tokens[TokPos - 1].SOffset;
  fmtLen := Tokens[TokPos - 1].SLen;
  Next;

  { collect the .{...} argument expressions up front }
  argCount := 0;
  if Eat(tkComma) then
  begin
    Expect(tkDot, '.');
    Expect(tkBegin, '{');
    if CurTok.Kind <> tkEnd then
      repeat
        if argCount > 7 then Error('Zig: std.debug.print supports at most 8 arguments (skeleton)');
        argExprs[argCount] := ZParseExpr;
        Inc(argCount);
      until not Eat(tkComma);
    Expect(tkEnd, '}');
  end;
  Expect(tkRParen, ')');

  isLn := (fmtLen > 0) and (TokChars[fmtOff + fmtLen - 1] = #10);
  if isLn then Dec(fmtLen);

  node := AllocNode(AN_WRITE);
  if isLn then ASTKind[node] := AN_WRITELN;
  ASTLeft[node] := -1;
  lastArg := -1;
  argUsed := 0;

  segStart := 0;
  i := 0;
  while i < fmtLen do
  begin
    if TokChars[fmtOff + i] = '{' then
    begin
      AddSegment(fmtOff + segStart, i - segStart);
      while (i < fmtLen) and (TokChars[fmtOff + i] <> '}') do Inc(i);
      if i >= fmtLen then Error('Zig: unterminated {} placeholder in format string');
      Inc(i); { step past the closing brace }
      segStart := i;
      if argUsed >= argCount then Error('Zig: more {} placeholders than .{} arguments');
      AddArg(argExprs[argUsed]);
      Inc(argUsed);
    end
    else
      Inc(i);
  end;
  AddSegment(fmtOff + segStart, fmtLen - segStart);
  if argUsed < argCount then Error('Zig: more .{} arguments than {} placeholders');

  Result := node;
end;

{ `switch (expr) { v1, v2 => arm, ..., else => arm }` — desugars to a
  hidden scrutinee temp + an AN_IF chain (the same no-new-nodes shape the
  Rust skeleton's match uses; `=>` is tkAssign+tkGt, the two-token trick
  rparser documents). Arm values are integer expressions compared by `==`
  (comma-separated lists OR together); arm bodies are `{ blocks }` or a
  single call expression. No ranges, no capture, statement position only. }
function ZParseSwitch: Integer;
var tmpSym, tmpAssign, chain, pairNode, ifNode, i, armCount, elseBody: Integer;
    conds: array[0..63] of Integer;
    bodies: array[0..63] of Integer;

  function ArmBody: Integer;
  begin
    if CurTok.Kind = tkBegin then
    begin
      Next;
      Result := ZParseBlock;
      Expect(tkEnd, '}');
    end
    else if CurTok.Kind = tkExit then
    begin
      { `N => return expr` arm — terminated by the arm comma or closing brace }
      Next;
      Result := ZMakeReturn((CurTok.Kind <> tkComma) and (CurTok.Kind <> tkEnd));
    end
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'std') and
            (Tokens[TokPos].Kind = tkDot) then
      Result := ZParseStdDebugPrint
    else
      Result := ZParseExpr;   { single expression arm — a call, usually }
  end;

  procedure ExpectFatArrow;
  begin
    if CurTok.Kind <> tkAssign then Error('Zig: expected => after switch arm value');
    Next;
    if CurTok.Kind <> tkGt then Error('Zig: expected => after switch arm value');
    Next;
  end;

begin
  Next; { switch }
  Expect(tkLParen, '(');
  tmpSym := AllocVar('', tyInt64);
  tmpAssign := AllocNode(AN_ASSIGN);
  ASTLeft[tmpAssign] := RMakeIdent(tmpSym);
  ASTRight[tmpAssign] := ZParseExpr;
  Expect(tkRParen, ')');
  Expect(tkBegin, '{');
  armCount := 0; elseBody := -1;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Zig: unterminated switch');
    if CurTok.Kind = tkElse then
    begin
      Next;
      ExpectFatArrow;
      elseBody := ArmBody;
    end
    else
    begin
      if armCount >= 64 then Error('Zig: too many switch arms (skeleton limit 64)');
      conds[armCount] := RBinOp(tkEq, RMakeIdent(tmpSym), ZParseExpr, tyBoolean);
      while CurTok.Kind = tkComma do
      begin
        Next;
        conds[armCount] := RBinOp(tkOr, conds[armCount],
          RBinOp(tkEq, RMakeIdent(tmpSym), ZParseExpr, tyBoolean), tyBoolean);
      end;
      ExpectFatArrow;
      bodies[armCount] := ArmBody;
      Inc(armCount);
    end;
    if not Eat(tkComma) then Break;
  end;
  Expect(tkEnd, '}');
  chain := elseBody;
  for i := armCount - 1 downto 0 do
  begin
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := bodies[i];
    ASTRight[pairNode] := chain;
    ifNode := AllocNode(AN_IF);
    ASTLeft[ifNode] := conds[i];
    ASTRight[ifNode] := pairNode;
    chain := ifNode;
  end;
  Result := RSeqAppend(RSeqAppend(-1, tmpAssign), chain);
end;

function ZParseStatement: Integer;
var node, seq, tmpSym: Integer;
begin
  case CurTok.Kind of
    tkIf: begin Result := ZParseIf; Exit; end;
    tkWhile: begin Result := ZParseWhile; Exit; end;
    tkFor: begin Result := ZParseFor; Exit; end;
    tkBegin: begin Next; Result := ZParseBlock; Expect(tkEnd, '}'); Exit; end;
    tkSemicolon: begin Next; Result := -1; Exit; end;
    tkVar, tkConst:
    begin
      Result := ZParseVarDecl;
      Expect(tkSemicolon, ';');
      Exit;
    end;
    tkExit:
    begin
      Next;
      if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'error') and
         (Tokens[TokPos].Kind = tkDot) then
      begin
        { `return error.Name;` — replay errdefer+defer, set the error slot
          (AFTER the defers so a defer's own calls cannot clobber it), exit. }
        if (CurProc < 0) or not ZProcErrs[CurProc] then
          Error('Zig: return error.X needs a !T return type');
        Next; Next; { error . }
        if CurTok.Kind <> tkIdent then Error('Zig: expected error name after error.');
        seq := ZAppendDefers(-1, True);
        seq := RSeqAppend(seq, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(ZErrCode(CurTok.SVal))));
        seq := RSeqAppend(seq, AllocNode(AN_EXIT));
        Next;
        Expect(tkSemicolon, ';');
        Result := seq;
        Exit;
      end;
      Result := ZMakeReturn(CurTok.Kind <> tkSemicolon);
      Expect(tkSemicolon, ';');
      Exit;
    end;
    tkBreak: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_BREAK); Exit; end;
    tkContinue: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_CONTINUE); Exit; end;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'std') and
     (Tokens[TokPos].Kind = tkDot) then
  begin
    Result := ZParseStdDebugPrint;
    Expect(tkSemicolon, ';');
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'switch') and
     (Tokens[TokPos].Kind = tkLParen) then
  begin
    Result := ZParseSwitch;
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and
     ((CurTok.SVal = 'defer') or (CurTok.SVal = 'errdefer')) then
  begin
    if ZDeferCount >= 32 then Error('Zig: too many defers in one function (skeleton limit 32)');
    ZDeferIsErr[ZDeferCount] := (CurTok.SVal = 'errdefer');
    Next;
    { Parens force a real recursive call — a bare name here would read the
      implicit Result alias instead (the ZParseIf comment's same pitfall,
      which bit again right here: frank2-paramless-name-semantics). }
    node := ZParseStatement();   { a `{ block }` or a single statement }
    if node >= 0 then
    begin
      ZDeferNode[ZDeferCount] := node;
      Inc(ZDeferCount);
    end;
    Result := -1;
    Exit;
  end;

  { `try f(...);` — whole-statement error propagation }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'try') then
  begin
    Next;
    Result := ZTryStmt;
    Expect(tkSemicolon, ';');
    Exit;
  end;

  { `_ = expr;` discard — common in Zig for unused results. Must be checked
    BEFORE the general assignment branch, which would otherwise report `_`
    as an undefined variable. }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = '_') and
     (Tokens[TokPos].Kind = tkAssign) then
  begin
    Next; Next;
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'try') then
    begin
      Next;
      Result := ZTryStmt;   { `_ = try f();` — same propagation, value dropped }
    end
    else
      Result := ZParseExpr;   { evaluated for side effects, value dropped }
    Expect(tkSemicolon, ';');
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and
     (Tokens[TokPos].Kind in [tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq]) then
  begin
    Result := ZParseAssign;
    Expect(tkSemicolon, ';');
    Exit;
  end;

  Result := ZParseExpr;   { bare call statement, or a postfix lvalue }
  { `s.f = e;` / `a[i] = e;` / `p.* = e;` — the plain-variable dispatch above
    only catches ident-then-assign-op, so postfix targets land here as a
    parsed expression followed by `=`. Plain `=` only (no compound). }
  if (CurTok.Kind = tkAssign) and
     ((ASTKind[Result] = AN_FIELD) or (ASTKind[Result] = AN_INDEX) or
      (ASTKind[Result] = AN_DEREF)) then
  begin
    Next;
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := Result;
    ASTRight[node] := ZParseExpr;
    Result := node;
  end
  { `f() catch |e| { ... };` / `f() catch expr;` statement — clear before
    the call, run the handler (with e bound to the code) or swallow. }
  else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'catch') then
  begin
    if (ASTKind[Result] <> AN_CALL) or not ZProcErrs[ASTIVal[Result]] then
      Error('Zig: catch needs a direct call to a !T function on its left (skeleton)');
    Next;
    seq := RSeqAppend(-1, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
    seq := RSeqAppend(seq, Result);
    if CurTok.Kind = tkPipe then
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('Zig: expected capture name in catch |e|');
      tmpSym := AllocVar(CurTok.SVal, tyInt64);
      Next;
      Expect(tkPipe, '|');
      Expect(tkBegin, '{');
      node := RSeqAppend(-1, ZAssignNode(RMakeIdent(tmpSym), RMakeIdent(ZErrSlotSym)));
      node := RSeqAppend(node, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
      node := RSeqAppend(node, ZParseBlock);
      Expect(tkEnd, '}');
    end
    else
    begin
      node := ZParseExpr;   { fallback value — meaningless for a discarded call }
      node := RSeqAppend(-1, ZAssignNode(RMakeIdent(ZErrSlotSym), ZIntLit(0)));
    end;
    Result := RSeqAppend(seq, ZIfNode(ZErrSetCond, node, -1));
  end;
  Expect(tkSemicolon, ';');
end;

function ZParseBlock: Integer;
var stmt: Integer;
begin
  Result := -1;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Zig: unterminated block (missing })');
    stmt := ZParseStatement;
    Result := RSeqAppend(Result, stmt);
  end;
end;

{ ===== Top-level: struct + fn signature prescan, then body compilation ===== }

{ Registers every top-level `const Name = struct { f: T, ... };` as a UClass
  with laid-out fields — the same AddUClass/AddUField machinery rparser.inc's
  struct pass uses. Fields must be scalar (no nested structs/arrays/pointers
  in the skeleton). The token pattern is specific enough that no brace-depth
  tracking is needed: `struct` only appears in this position. }
procedure ZRegisterStructs;
var i, j, ci, curOff, sz, align, nameTokIdx: Integer; tk: TTypeKind;
begin
  i := 0;
  while Tokens[i].Kind <> tkEOF do
  begin
    if (Tokens[i].Kind = tkConst) and (Tokens[i + 1].Kind = tkIdent) and
       (Tokens[i + 2].Kind = tkAssign) and (Tokens[i + 3].Kind = tkIdent) and
       (GetTokenStr(i + 3) = 'struct') and (Tokens[i + 4].Kind = tkBegin) then
    begin
      if FindUClass(GetTokenStr(i + 1)) >= 0 then Error('Zig: duplicate struct ' + GetTokenStr(i + 1));
      ci := AddUClass(Tokens[i + 1].SOffset, Tokens[i + 1].SLen);
      UClsIsRecord[ci] := True;
      curOff := 0; align := 1;
      j := i + 5;
      while Tokens[j].Kind <> tkEnd do
      begin
        if Tokens[j].Kind = tkEOF then Error('Zig: unterminated struct ' + GetTokenStr(i + 1));
        if Tokens[j].Kind <> tkIdent then Error('Zig: expected field name in struct ' + GetTokenStr(i + 1));
        nameTokIdx := j; Inc(j);
        if Tokens[j].Kind <> tkColon then Error('Zig: expected : after field name in struct ' + GetTokenStr(i + 1));
        Inc(j);
        if Tokens[j].Kind <> tkIdent then Error('Zig: expected scalar field type in struct ' + GetTokenStr(i + 1));
        tk := ZTypeKindFromName(GetTokenStr(j), False);
        Inc(j);
        sz := TypeSize(tk);
        if TypeAlign(tk) > align then align := TypeAlign(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        AddUField(ci, Tokens[nameTokIdx].SOffset, Tokens[nameTokIdx].SLen, curOff, Ord(tk), REC_NONE);
        Inc(curOff, sz);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      UClsAlign[ci] := align;
      UClsSize_[ci] := AlignTo(curOff, align);
    end;
    Inc(i);
  end;
end;

{ Registers the fn signature starting at Tokens[i] (must be tkFn); returns
  nothing useful beyond the registration side effect. Zig signature shape:
  fn name(p: T, ...) RetType — return type directly after ), no arrow. }
procedure ZRegisterFnSignatureAt(i: Integer; var mainIsVoid: Boolean);
var j, nparams, k, procIdx: Integer; name, retName: AnsiString;
    pnames: array[0..5] of AnsiString; ptypes: array[0..5] of TTypeKind;
    retType: TTypeKind; fnErrs: Boolean;
begin
  name := GetTokenStr(i + 1);
  j := i + 2;
  if Tokens[j].Kind <> tkLParen then Error('Zig: expected ( after fn ' + name);
  Inc(j); nparams := 0;
  while Tokens[j].Kind <> tkRParen do
  begin
    if nparams >= 6 then Error('Zig: too many parameters (register-convention limit is 6)');
    if Tokens[j].Kind <> tkIdent then Error('Zig: expected parameter name in ' + name);
    pnames[nparams] := GetTokenStr(j); Inc(j);
    if Tokens[j].Kind <> tkColon then Error('Zig: expected : in parameter list of ' + name);
    Inc(j);
    if Tokens[j].Kind = tkStar then
    begin
      { `p: *T` / `p: *const T` pointer parameter — an 8-byte scalar in the
        same rdi/rsi/rdx/rcx slots; pointee recorded in the body pass. }
      Inc(j);
      if Tokens[j].Kind = tkConst then Inc(j);
      if Tokens[j].Kind <> tkIdent then Error('Zig: expected pointee type after * in ' + name);
      ZTypeKindFromName(GetTokenStr(j), False); { validate scalar }
      ptypes[nparams] := tyPointer;
    end
    else if Tokens[j].Kind = tkLBrack then
    begin
      { `p: []T` slice parameter — the 16-byte __ptr/__len record, passed by
        address like every record param (IsRef marked after RegisterProc). }
      Inc(j);
      if Tokens[j].Kind <> tkRBrack then Error('Zig: expected ] in []T parameter of ' + name);
      Inc(j);
      if Tokens[j].Kind <> tkIdent then Error('Zig: expected element type in []T parameter of ' + name);
      ZSliceClassFor(ZTypeKindFromName(GetTokenStr(j), False));
      ptypes[nparams] := tyRecord;
    end
    else
    begin
      if Tokens[j].Kind <> tkIdent then Error('Zig: expected parameter type in ' + name);
      ptypes[nparams] := ZTypeKindFromName(GetTokenStr(j), False);
    end;
    Inc(j);
    Inc(nparams);
    if Tokens[j].Kind = tkComma then Inc(j);
  end;
  Inc(j); { consume ) }
  fnErrs := False;
  if Tokens[j].Kind = tkLogNot then
  begin
    { `!T` — inferred-error-set return; payload rides the normal return
      value, the error the global __zig_err slot. }
    fnErrs := True;
    Inc(j);
  end;
  if Tokens[j].Kind <> tkIdent then Error('Zig: expected return type after ) in fn ' + name);
  retName := GetTokenStr(j);
  retType := ZTypeKindFromName(retName, False);
  if (name = 'main') and (retName = 'void') then
  begin
    if fnErrs then Error('Zig: fn main() !void is not supported by the skeleton (catch errors in main)');
    mainIsVoid := True;
  end;
  procIdx := RegisterProc(name, True, retType, nparams, pnames, ptypes);
  k := procIdx; { silence unused warning on compilers that care }
  if k < 0 then Error('Zig: internal error registering ' + name);
  { record (slice) params are passed by address — same as the Rust frontend }
  for k := 0 to nparams - 1 do
    if ptypes[k] = tyRecord then Procs[procIdx].Params[k].IsRef := True;
  ZProcErrs[procIdx] := fnErrs;
end;

procedure ZRegisterFnSignatures(var mainIsVoid: Boolean);
var i, depth: Integer;
begin
  i := 0; depth := 0;
  while Tokens[i].Kind <> tkEOF do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkFn) and (Tokens[i + 1].Kind = tkIdent) and
            not ZFnIsGenericAt(i) then
      ZRegisterFnSignatureAt(i, mainIsVoid);
    Inc(i);
  end;
end;

procedure ZParseTopLevelFn;
var name, pname: AnsiString;
    procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode: Integer;
    pnames: array[0..5] of AnsiString; ptypes: array[0..5] of TTypeKind;
    pElemTk: array[0..5] of TTypeKind;
    pSliceCi: array[0..5] of Integer;  { slice-param element UClass, or -1 }
begin
  Next; { fn }
  if CurTok.Kind <> tkIdent then Error('Zig: expected function name');
  name := CurTok.SVal; Next;
  procIdx := FindProc(name);
  if procIdx < 0 then Error('Zig: internal error — signature prescan missed ' + name);
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if CurTok.Kind <> tkIdent then Error('Zig: expected parameter name');
    pname := CurTok.SVal; Next;
    Expect(tkColon, ':');
    pElemTk[nparams] := tyUnknown;
    pSliceCi[nparams] := -1;
    if CurTok.Kind = tkStar then
    begin
      Next;
      if CurTok.Kind = tkConst then Next;
      if CurTok.Kind <> tkIdent then Error('Zig: expected pointee type after *');
      pElemTk[nparams] := ZTypeKindFromName(CurTok.SVal, False);
      ptypes[nparams] := tyPointer;
    end
    else if CurTok.Kind = tkLBrack then
    begin
      { `p: []T` slice parameter (matches the prescan). }
      Next;
      Expect(tkRBrack, ']');
      if CurTok.Kind <> tkIdent then Error('Zig: expected element type in []T parameter');
      pSliceCi[nparams] := ZSliceClassFor(ZTypeKindFromName(CurTok.SVal, False));
      ptypes[nparams] := tyRecord;
    end
    else
    begin
      if CurTok.Kind <> tkIdent then Error('Zig: expected parameter type');
      ptypes[nparams] := ZTypeKindFromName(CurTok.SVal, False);
    end;
    pnames[nparams] := pname;
    Next;
    Inc(nparams);
    if not Eat(tkComma) then Break;
  end;
  Expect(tkRParen, ')');
  if CurTok.Kind = tkLogNot then Next; { !T — recorded by the prescan }
  if CurTok.Kind <> tkIdent then Error('Zig: expected return type after )');
  Next; { return type — already registered by the prescan }

  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0; CurProc := procIdx;
  Procs[procIdx].BodyAddr := CodeLen;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    if ptypes[i] = tyPointer then ZSetPtrType(pElemTk[i]);
    { slice param: a by-address record — set LastTypeRecId so AllocParam
      records the slice UClass (RecName), and pass isRef so s[i]/s.len read
      through the pointer. }
    if (ptypes[i] = tyRecord) and (pSliceCi[i] >= 0) then
    begin
      LastTypeRecId := REC_UCLASS_BASE + pSliceCi[i];
      idx := AllocParam(pnames[i], ptypes[i], True, False);
    end
    else
    begin
      LastTypeRecId := REC_NONE;
      idx := AllocParam(pnames[i], ptypes[i], False, False);
    end;
    Procs[procIdx].Params[i].SymIdx := idx;
  end;
  idx := AllocVar('Result', Procs[procIdx].RetType);
  Procs[procIdx].RetSymIdx := idx;

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  { spill the SysV integer arg registers into the frame slots — shared with
    the Rust frontend (REmitParamRegSpill handles r8/r9 via REX.R for the
    5th/6th param; the old inline case i of 0..3 miscompiled those). }
  REmitParamRegSpill(procIdx, nparams);

  ZDeferCount := 0;
  Expect(tkBegin, '{');
  bodyNode := ZParseBlock;
  Expect(tkEnd, '}');
  { Fall-through fn end is a normal exit: replay plain defers. (A body
    ending in `return` already replayed them and jumps past this.) }
  if ZDeferCount > 0 then
    bodyNode := ZAppendDefers(bodyNode, False);

  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

{ Registers every top-level `fn name(comptime T: type, ...)` template:
  records name, type-param name and the fn's whole token span for
  ZSpecializeGenericFn to copy-and-substitute per call site. }
procedure ZRegisterGenericFns;
var i, j, depth, gfi: Integer;
begin
  i := 0;
  while Tokens[i].Kind <> tkEOF do
  begin
    if (Tokens[i].Kind = tkFn) and (Tokens[i + 1].Kind = tkIdent) and ZFnIsGenericAt(i) then
    begin
      if ZGenericFnCount >= Z_MAX_GENERIC_FNS then Error('Zig: too many generic functions (skeleton limit 64)');
      gfi := ZGenericFnCount; Inc(ZGenericFnCount);
      ZGenericFns[gfi].Name := GetTokenStr(i + 1);
      if Tokens[i + 4].Kind <> tkIdent then
        Error('Zig: expected type parameter name after comptime in ' + ZGenericFns[gfi].Name);
      ZGenericFns[gfi].ParamName := GetTokenStr(i + 4);
      if (Tokens[i + 5].Kind <> tkColon) or (Tokens[i + 6].Kind <> tkIdent) or
         (GetTokenStr(i + 6) <> 'type') then
        Error('Zig: only `comptime T: type` (first parameter) is supported by the skeleton in ' + ZGenericFns[gfi].Name);
      j := i + 7;
      while (Tokens[j].Kind <> tkBegin) and (Tokens[j].Kind <> tkEOF) do Inc(j);
      if Tokens[j].Kind = tkEOF then Error('Zig: missing body for generic fn ' + ZGenericFns[gfi].Name);
      depth := 1; Inc(j);
      while (depth > 0) and (Tokens[j].Kind <> tkEOF) do
      begin
        if Tokens[j].Kind = tkBegin then Inc(depth)
        else if Tokens[j].Kind = tkEnd then Dec(depth);
        Inc(j);
      end;
      if depth > 0 then Error('Zig: unterminated body in generic fn ' + ZGenericFns[gfi].Name);
      ZGenericFns[gfi].TokStart := i;
      ZGenericFns[gfi].TokCnt := j - i;
      i := j;
    end
    else
      Inc(i);
  end;
end;

{ Copies the template's tokens with the fn name manged to `name$T`, the
  `comptime T: type[,]` parameter DROPPED (the copy must be an ordinary
  fn) and every T ident replaced by the concrete type name, registers the
  copy's signature, then compiles it in place — bracketed by a jmp because
  specialization triggers mid-expression inside the CALLER's body and the
  copy's code would otherwise land in the caller's instruction stream
  (rparser.inc found that segfault the hard way; same fix). The caller's
  CurProc/FrameSize and defer stash are saved around the nested
  ZParseTopLevelFn — both are per-fn globals the nested parse clobbers. }
function ZSpecializeGenericFn(gfi: Integer; const concreteTypeName: AnsiString): Integer;
var mangledName: AnsiString;
    procIdx, i, k, srcIdx, startTok, concreteOff, concreteLen, jmpPatch: Integer;
    skipLo, skipHi: Integer;
    savedTokPos, savedCurProc, savedFrameSize, savedDC: Integer;
    savedCurTok: TToken;
    savedDeferNode: array[0..31] of Integer;
    savedDeferIsErr: array[0..31] of Boolean;
    dummyMainIsVoid: Boolean;
begin
  mangledName := ZGenericFns[gfi].Name + '$' + concreteTypeName;
  procIdx := FindProc(mangledName);
  if procIdx >= 0 then begin Result := procIdx; Exit; end;

  concreteOff := RStoredName(concreteTypeName);
  concreteLen := Length(concreteTypeName);
  { the comptime param: tokens TokStart+3..+6 (`comptime T : type`), plus
    the separating comma when more parameters follow }
  skipLo := ZGenericFns[gfi].TokStart + 3;
  skipHi := ZGenericFns[gfi].TokStart + 6;
  if Tokens[ZGenericFns[gfi].TokStart + 7].Kind = tkComma then
    skipHi := ZGenericFns[gfi].TokStart + 7;

  startTok := TokCount;
  for i := 0 to ZGenericFns[gfi].TokCnt - 1 do
  begin
    srcIdx := ZGenericFns[gfi].TokStart + i;
    if (srcIdx >= skipLo) and (srcIdx <= skipHi) then Continue;
    if TokCount >= MAX_TOKENS then Error('Zig: token buffer overflow specializing ' + ZGenericFns[gfi].Name);
    Tokens[TokCount] := Tokens[srcIdx];
    if srcIdx = ZGenericFns[gfi].TokStart + 1 then
    begin
      Tokens[TokCount].SOffset := RStoredName(mangledName);
      Tokens[TokCount].SLen := Length(mangledName);
    end
    else if (Tokens[srcIdx].Kind = tkIdent) and
            (GetTokenStr(srcIdx) = ZGenericFns[gfi].ParamName) then
    begin
      Tokens[TokCount].SOffset := concreteOff;
      Tokens[TokCount].SLen := concreteLen;
    end;
    Inc(TokCount);
  end;

  dummyMainIsVoid := False;
  ZRegisterFnSignatureAt(startTok, dummyMainIsVoid);

  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);   { skip over the copy's code }

  savedTokPos := TokPos;
  savedCurTok := CurTok;
  savedCurProc := CurProc;
  savedFrameSize := FrameSize;
  savedDC := ZDeferCount;
  for k := 0 to savedDC - 1 do
  begin
    savedDeferNode[k] := ZDeferNode[k];
    savedDeferIsErr[k] := ZDeferIsErr[k];
  end;

  TokPos := startTok;
  Next; { load the copy's 'fn' token }
  ZParseTopLevelFn;

  TokPos := savedTokPos;
  CurTok := savedCurTok;
  CurProc := savedCurProc;
  FrameSize := savedFrameSize;
  ZDeferCount := savedDC;
  for k := 0 to savedDC - 1 do
  begin
    ZDeferNode[k] := savedDeferNode[k];
    ZDeferIsErr[k] := savedDeferIsErr[k];
  end;

  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  Result := FindProc(mangledName);
  if Result < 0 then Error('Zig: internal error specializing ' + ZGenericFns[gfi].Name);
end;

procedure ParseZigProgram;
var callPatch, mainIdx, structDepth: Integer;
    mainIsVoid: Boolean;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Zig frontend: only the x86-64 target is supported by the skeleton (feature-zig-frontend)');

  mainIsVoid := False;
  { The errno-style error slot for !T functions — a BSS global (CurProc is
    -1 here, so AllocVar makes it skGlobal). Allocated unconditionally:
    8 bytes, and the prescan needs it before any body parses. }
  LastTypeRecId := REC_NONE;
  ZErrSlotSym := AllocVar('__zig_err', tyInt64);
  ZGenericFnCount := 0;
  ZRegisterStructs;
  ZRegisterGenericFns;
  ZRegisterFnSignatures(mainIsVoid);
  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('Zig: no fn main() found');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  { Entry stub: call main(), then exit_group — with main's return value as
    the exit code when main returns an integer, or 0 for `fn main() void`
    (whose Result slot is never written, so its eax is garbage). Same
    convention as the Rust skeleton's stub. }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E8); callPatch := CodeLen; EmitI32(0);   { call main }
  if mainIsVoid then
  begin
    EmitB($31); EmitB($FF);          { xor edi, edi }
  end
  else
  begin
    EmitB($89); EmitB($C7);          { mov edi, eax }
  end;
  EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
  EmitB($0F); EmitB($05);            { syscall }

  while CurTok.Kind <> tkEOF do
  begin
    { `pub` is accepted and ignored (no module system in the skeleton). }
    if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'pub') then Next
    { `const std = @import("std");` — accepted and swallowed whole so real
      Zig program headers parse; std is special-cased in ZParseStatement. }
    else if (CurTok.Kind = tkConst) and (Tokens[TokPos].Kind = tkIdent) and
            (GetTokenStr(TokPos) = 'std') then
    begin
      while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
      Expect(tkSemicolon, ';');
    end
    { `const Name = struct { ... };` — already registered by ZRegisterStructs —
      and `const E = error { ... };` — error names auto-register on use, the
      declaration is decorative: skip past braces + semicolon either way. }
    else if (CurTok.Kind = tkConst) and (Tokens[TokPos].Kind = tkIdent) and
            (Tokens[TokPos + 1].Kind = tkAssign) and (Tokens[TokPos + 2].Kind = tkIdent) and
            ((GetTokenStr(TokPos + 2) = 'struct') or (GetTokenStr(TokPos + 2) = 'error')) then
    begin
      Next; Next; Next; Next; { const Name = struct }
      Expect(tkBegin, '{');
      structDepth := 1;
      while structDepth > 0 do
      begin
        if CurTok.Kind = tkEOF then Error('Zig: unterminated struct declaration');
        if CurTok.Kind = tkBegin then Inc(structDepth)
        else if CurTok.Kind = tkEnd then Dec(structDepth);
        Next;
      end;
      Expect(tkSemicolon, ';');
    end
    { generic template — buffered by the prescan, compiled per call site;
      skip its tokens here (it cannot compile as-is: T is not a type yet). }
    else if (CurTok.Kind = tkFn) and ZFnIsGenericAt(TokPos - 1) then
    begin
      while (CurTok.Kind <> tkBegin) and (CurTok.Kind <> tkEOF) do Next;
      Expect(tkBegin, '{');
      structDepth := 1;
      while structDepth > 0 do
      begin
        if CurTok.Kind = tkEOF then Error('Zig: unterminated generic fn body');
        if CurTok.Kind = tkBegin then Inc(structDepth)
        else if CurTok.Kind = tkEnd then Dec(structDepth);
        Next;
      end;
    end
    else if CurTok.Kind = tkFn then ZParseTopLevelFn
    else Error('Zig: expected fn (or pub fn) at top level');
  end;

  ApplyCallFixups;
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;
