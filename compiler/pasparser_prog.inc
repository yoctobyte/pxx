{ ===== pasparser_prog.inc — Pascal frontend: program/unit driver =============

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Textually included from pasparser.inc at
  exactly the point it used to occupy, so include ORDER is unchanged — that is
  what makes the carve-out provable by the self-host fixedpoint rather than by
  reading it.

  Contents: ParseProgram and the drivers around it — the emitted-runtime forward
  registration, the main body, unit init/finalization ordering, the goto-fixup
  verification, and the final ApplyCallFixups.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ ===== Program ===== }

procedure RegisterEmittedStringRuntimeForwards;
{ Forward-declare exactly the builtinheap procs that EmitAnsiStringRuntime's own
  machine code CALLS, so the shims can be emitted BEFORE builtinheap is parsed.

  The ordering is not a preference: the emitted runtime sits right after the
  entry stub and is reached by a direct relative `call`, so every site that
  calls it must be compiled after it — which includes the pulled RTL units
  themselves. Emitting it after the pull is therefore too late, and pre-declaring
  is the price. `ParseUsesUnit` fills the bodies in.

  ONE copy, shared by the drivers that need it. It exists because there were
  two hand-rolled copies (Pascal's ParseProgram and NilPy's) and the C driver
  had NONE — so a Pascal unit `#include`d from C compiled a call to
  AnsiStrFromLiteralAddr while that address was still 0, i.e. a call to the ELF
  entry point (bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit).
  ParseProgram still registers a much larger, target-conditional SUPERSET
  inline (variants, interface ARC, the float writers, the xtensa divide
  helpers); this is the minimum the emitter itself needs, and adding a call to
  the emitted runtime is what makes a driver need it. }
var i: Integer; savedUnitIdx: Integer;
    dummyNames: array[0..3] of AnsiString;
    dummyTypes: array[0..3] of TTypeKind;
begin
  savedUnitIdx := CurrentUnitIdx;
  CurrentUnitIdx := InternStr('builtinheap');
  dummyNames[0] := 'size';    dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'align';   dummyTypes[1] := tyInteger;
  i := RegisterProc('PXXAlloc', True, tyPointer, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'p';       dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXFree', False, tyPointer, 1, dummyNames, dummyTypes);
  { the emitted obj blobs call these (feature-nilpy-object-reclamation) }
  i := RegisterProc('PXXObjRetain', False, tyPointer, 1, dummyNames, dummyTypes);
  i := RegisterProc('PXXObjRelease', False, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'p';       dummyTypes[0] := tyPointer;
  dummyNames[1] := 'newSize'; dummyTypes[1] := tyNativeInt;
  dummyNames[2] := 'align';   dummyTypes[2] := tyInteger;
  i := RegisterProc('PXXRealloc', True, tyPointer, 3, dummyNames, dummyTypes);
  dummyNames[0] := 'len';     dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'src';     dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXStrFromLit', True, tyPointer, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'lenA';    dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';    dummyTypes[1] := tyPointer;
  dummyNames[2] := 'srcB';    dummyTypes[2] := tyPointer;
  dummyNames[3] := 'lenB';    dummyTypes[3] := tyNativeInt;
  i := RegisterProc('PXXStrConcat', True, tyPointer, 4, dummyNames, dummyTypes);
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'srcB';    dummyTypes[1] := tyPointer;
  dummyNames[2] := 'lenB';    dummyTypes[2] := tyNativeInt;
  i := RegisterProc('PXXStrAppend', False, tyPointer, 3, dummyNames, dummyTypes);
  dummyNames[0] := 'dest';    dummyTypes[0] := tyPointer;
  dummyNames[1] := 'right';   dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXVarStrAppend', True, tyInt64, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'path';    dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrLoadFile', True, tyPointer, 1, dummyNames, dummyTypes);
  CurrentUnitIdx := savedUnitIdx;
end;

procedure DetectPascalRuntimeNeeds(var needsHeap, needsAnsiRuntime, needsDivStub: Boolean);
{ Conservative pre-scan for optional emitted runtime support. Imported units
  are treated as opaque: keep the support bundle if uses is present. }
var i: Integer; name: AnsiString;
begin
  needsHeap := False;
  needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING');
  { div-by-zero abort stub (feature-opt-div0-stub-on-use): only integer
    `div`/`mod` sites can branch to it, and only when no builtinheap
    PXXDivZero is in the program — a unit-bearing program (tkUses => heap)
    always has PXXDivZero, so the stub matters exactly for unit-free sources,
    whose division must appear as a div/mod TOKEN in this scan. `/` yields a
    float in Pascal — no integer-div check. Division-free programs skip the
    stub and its 37-byte message. }
  needsDivStub := False;
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkUses, tkArray, tkClass] then
      needsHeap := True;
    if (Tokens[i].Kind = tkDiv) or (Tokens[i].Kind = tkMod) then
      needsDivStub := True;
    { EVERY target writes floats through the builtinheap Pascal helpers
      (PXXWriteFloat*), so any float-producing token pulls the unit.
      tkSlash counts: integer / integer yields a float.

      This used to name only the 32-bit cross targets, because x86-64 and
      aarch64 had self-contained hand-written emitters. They no longer do —
      both now shim onto PXXWriteFloatSci/Nat/Fixed so there is ONE correctly
      rounded formatter instead of four
      (bug-a-writeln-float-exponent-form-not-correctly-rounded,
      bug-a-writeln-nonfinite-float-aarch64-emitters-unchecked). A program that
      writes a float but needs no heap — the Algol and Fortran skeletons are
      exactly that — then failed with "compiler error: PXXWriteFloatSci not
      found", because the whole registration block lives under `needHeapUnit`.
      Shimming moved the dependency; this is where it has to be paid. }
    if Tokens[i].Kind in [tkFloat, tkSlash] then
      needsHeap := True;
    if Tokens[i].Kind = tkUses then
      needsAnsiRuntime := True;
    if Tokens[i].Kind = tkIdent then
    begin
      name := GetTokenStr(i);
      if CaseEqual(name, 'AnsiString') or CaseEqual(name, 'Variant') then
        needsAnsiRuntime := True;
      if ((TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) or
          (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)) and
         (CaseEqual(name, 'Single') or CaseEqual(name, 'Double') or
          CaseEqual(name, 'Real') or CaseEqual(name, 'Extended')) then
        needsHeap := True;
      if CaseEqual(name, 'New') or CaseEqual(name, 'Dispose') or
         CaseEqual(name, 'ReallocMem') or CaseEqual(name, 'SetLength') or
         { getmem/freemem are soft keywords (plain idents) now — match by name
           like New/Dispose, replacing the old tkGetMem/tkFreeMem kind check. }
         CaseEqual(name, 'GetMem') or CaseEqual(name, 'FreeMem') then
        needsHeap := True;
    end;
    Inc(i);
  end;
  if needsAnsiRuntime then needsHeap := True;
end;

procedure FixupTVarRecLayout;
{ builtinheap declares TVarRec with three sequential fields; here we overlap
  VAnsiString onto the value union (VInteger's offset) and right-size the record
  to a pointer-sized tag plus one pointer-sized value slot — exactly FPC's
  system.TVarRec (SizeOf 16 on x86-64, 8 on i386). Records the resolved id in
  TVarRecId for the `array of const` parser/lowering paths. }
var ci, fi: Integer;
begin
  TVarRecId := REC_NONE;
  ci := FindUClass('TVarRec');
  if ci < 0 then Exit;
  TVarRecId := REC_UCLASS_BASE + ci;
  { Overlap every value-union field onto the single pointer-sized value slot at
    offset TARGET_PTR_SIZE (field 0 = VType stays at offset 0). VInteger already
    lands there from the sequential layout; VAnsiString/VBoolean/VChar/VPointer/
    VPChar/VInt64/VExtended are forced onto it so `array of const` element reads
    by tag all hit the same slot — exactly FPC's variant TVarRec. }
  for fi := UClsFBase[ci] + 1 to UClsFBase[ci] + UClsFCount[ci] - 1 do
    UFldOff_[fi] := TARGET_PTR_SIZE;
  UClsSize_[ci] := 2 * TARGET_PTR_SIZE;
  UClsAlign[ci] := TARGET_PTR_SIZE;
end;

procedure CompilePendingGlobalInits;
{ Emit the recorded constant global-var initializers as assignments, at the
  current code position (just before `main begin`). }
var i, identNode, valNode, idxLit, target, assignNode, lenVal, innerAddr: Integer;
    initTk: Integer;
begin
  for i := 0 to PendingInitCount - 1 do
  begin
    { The recorded Tk is the DECLARED storage kind; every target built below is
      an EXPRESSION, so it must carry the value kind the resolver would have
      given the same `a[0] := 'aa'` written by hand — StrValTk, which folds
      tyFixedString/tyShortString onto tyString. Without it a frozen-string
      element kept its storage spelling, IR_STORE_MEM's frozen arm (which tests
      `tk = tyString`) did not fire, and the store fell through to the generic
      8-byte path that wrote the source HANDLE into the slot: a const array of
      string[N] read back as pointer garbage, with no diagnostic.
      bug-a-a-typed-const-array-of-string-n-is-never-initialised }
    initTk := StrValTk(IntToTypeKind(PendingInitTk[i]));
    identNode := AllocNode(AN_IDENT);
    ASTIVal[identNode] := PendingInitSym[i];
    ASTTk[identNode] := Ord(Syms[PendingInitSym[i]].TypeKind);

    target := identNode;

    if (PendingInitElem[i] <> PI_ELEM_NONE) and (PendingInitElem[i] <> PI_ELEM_ADDRG) then   { an index MAY be negative }
    begin
      idxLit := AllocNode(AN_INT_LIT);
      ASTIVal[idxLit] := PendingInitElem[i];
      ASTTk[idxLit] := Ord(tyInteger);
      target := AllocNode(AN_INDEX);
      ASTLeft[target] := identNode;
      ASTRight[target] := idxLit;
      ASTTk[target] := initTk;
    end;

    if PendingInitFOff[i] >= 0 then
    begin
      { Record typed-const field: `sym.field := value`; when Elem is also set,
        this becomes `sym[elem].field := value`. }
      valNode := AllocNode(AN_FIELD);
      ASTLeft[valNode] := target;
      ASTSOffset[valNode] := PendingInitFOff[i];
      ASTSLen[valNode] := PendingInitFLen[i];
      target := valNode;
      ASTTk[target] := initTk;
    end;

    if PendingInitKind[i] = 7 then
    begin
      { Array-valued record-const field element: `sym.field[ValAux] := v`.
        The FIELD target was just built above; index into it (TGuid's D4). }
      idxLit := AllocNode(AN_INT_LIT);
      ASTIVal[idxLit] := PendingInitValAux[i];
      ASTTk[idxLit] := Ord(tyInteger);
      valNode := AllocNode(AN_INDEX);
      ASTLeft[valNode] := target;
      ASTRight[valNode] := idxLit;
      ASTTk[valNode] := initTk;
      target := valNode;
    end;

    if PendingInitElem[i] = PI_ELEM_ADDRG then
    begin
      { Address-of-global pointer init: `T *p = &g;` or `T *p = &arr[N];`.
        Emit `p := @g` (AN_ADDR of target sym) or `p := @g + byte_offset`
        (ValAux carries the byte offset; 0 = plain &g). }
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(Syms[PendingInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
      if PendingInitValAux[i] <> 0 then
      begin
        { &arr[offset]: add constant byte offset to array base pointer }
        idxLit := AllocNode(AN_INT_LIT);
        ASTIVal[idxLit] := PendingInitValAux[i];
        ASTTk[idxLit] := Ord(tyInt64);
        innerAddr := AllocNode(AN_BINOP);
        ASTIVal[innerAddr] := Ord(tkPlus);
        ASTLeft[innerAddr] := valNode;
        ASTRight[innerAddr] := idxLit;
        ASTTk[innerAddr] := Ord(tyPointer);
        valNode := innerAddr;
      end;
      { re-point: assignment target is the pointer sym, value is the address }
      target := identNode;
    end
    else if PendingInitFOff[i] = -4 then
    begin
      { C pointer-array element initialized to the address of a named global
        (a `char[]` array name decaying to `char*`, or `&g`). Value index in
        PendingInitVal is the target sym; emit `arr[ei] := @g`. The array
        element target was already built above (Elem >= 0 => AN_INDEX). }
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(Syms[PendingInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
    end
    else if (PendingInitFOff[i] = -3) or (PendingInitKind[i] = 1) then
    begin
      { C pointer-array string initializer, e.g. char-star array from strings.
        PendingInitVal/FLen carry the raw token-string span; assignment lowering
        applies the C string-literal-to-char-pointer +8 adjustment. }
      valNode := AllocNode(AN_STR_LIT);
      ASTSOffset[valNode] := PendingInitVal[i];
      if PendingInitFOff[i] = -3 then lenVal := PendingInitFLen[i]
      else lenVal := PendingInitValAux[i];
      ASTSLen[valNode] := lenVal;
      ASTTk[valNode] := Ord(tyString);
    end
    else if PendingInitKind[i] = 2 then
    begin
      valNode := AllocNode(AN_PROCADDR);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else if PendingInitKind[i] = 8 then
    begin
      { CLASS-REFERENCE element (an array of metaclasses initialised with class names).
        Val is the class INDEX; AN_CLASSREF yields its RTTI blob address, resolved after
        EmitRTTI through the per-class data-ref sentinel. }
      valNode := AllocNode(AN_CLASSREF);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else if PendingInitKind[i] = 4 then
    begin
      valNode := AllocNode(AN_IDENT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(Syms[PendingInitVal[i]].TypeKind);
      innerAddr := AllocNode(AN_ADDR);
      ASTLeft[innerAddr] := valNode;
      ASTTk[innerAddr] := Ord(tyPointer);
      valNode := innerAddr;
    end
    else if PendingInitKind[i] = 3 then
    begin
      valNode := AllocNode(AN_FLOAT_LIT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := initTk;
    end
    else if PendingInitKind[i] = 5 then
    begin
      { metaclass const init: class VMT address }
      valNode := AllocNode(AN_CLASSREF);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := Ord(tyPointer);
    end
    else
    begin
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := PendingInitVal[i];
      ASTTk[valNode] := initTk;
      { A RECORD-typed slot reaching the scalar-literal path means the source
        wrote a scalar where a record lives, and `nil` is the only one the
        record-constant parser accepts there: a method-pointer field (the
        16-byte {Code,Data} record) or an interface field. Tagged tyRecord the
        literal 0 is an ADDRESS to copy 16 bytes from, so `const R: TRec = (n:
        4; ev: nil)` segfaulted in startup code before main ran -- and the
        record's OTHER fields never got initialised either, so the failure did
        not look like it was about `ev`. Tagged tyPointer it is the same node a
        written `ev := nil` builds, and AN_ASSIGN's tyRecord arm zeroes the
        field's full width. bug-a-nil-is-not-accepted-as-a-method-pointer-argument }
      if (initTk = Ord(tyRecord)) and (PendingInitVal[i] = 0) then
        ASTTk[valNode] := Ord(tyPointer);
    end;

    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := target;
    ASTRight[assignNode] := valNode;

    CompileAST(assignNode);
    ASTNodeCount := ASTArenaFloor;
  end;
end;

procedure RegisterBuiltinTGuid;
{ System.TGuid — pxx has no System unit, so mint the record unconditionally
  (cheap: one UCls row) so interface GUID constants and any explicit TGuid
  use resolve. Layout = FPC's: D1:LongWord, D2/D3:Word, D4:array[0..7] of Byte
  (16 bytes). feature-embed-pascal-script's IUnknown_Guid shape. }
var ci: Integer;
begin
  if FindUClass('TGuid') >= 0 then Exit;
  ci := AddUClass(TokCharsAppend('TGuid'), 5);
  UClsIsRecord[ci] := True;
  AddUField(ci, TokCharsAppend('D1'), 2, 0, Ord(tyUInt32), REC_NONE);
  AddUField(ci, TokCharsAppend('D2'), 2, 4, Ord(tyUInt16), REC_NONE);
  AddUField(ci, TokCharsAppend('D3'), 2, 6, Ord(tyUInt16), REC_NONE);
  AddUField(ci, TokCharsAppend('D4'), 2, 8, Ord(tyUInt8), REC_NONE);
  UFldIsArray[UFldCount-1] := True;
  UFldArrLen[UFldCount-1] := 8;
  UClsSize_[ci] := 16;
  UClsAlign[ci] := 4;
end;

procedure RegisterBuiltinTObject;
{ System.TObject as a minimal instantiable class (var o: TObject;
  o := TObject.Create). Zero fields, no user methods — the VMT-pointer slot
  at offset 0 (size = one pointer). Auto-Create (fieldless-class path) and the
  builtin obj.Free desugar serve construction/destruction; RTTI-backed methods
  (ClassName/GetHashCode/...) are a separate ticket. Kept an IMPLICIT parent
  for every other class (the `class(TObject)` guard checks by name), so this
  adds a usable row without relocating any VMT. feature-pascal-builtin-tobject-class. }
var ci, i, vmtN: Integer;
begin
  if FindUClass('TObject') >= 0 then Exit;
  ci := AddUClass(TokCharsAppend('TObject'), 7);
  UClsIsRecord[ci] := False;
  UClsSize_[ci] := TARGET_PTR_SIZE;   { VMT pointer slot at offset 0 }
  UClsAlign[ci] := TARGET_PTR_SIZE;
  { A real (empty) VMT + RTTI-backlink word + LAYOUT-backlink word, the same
    shape every DECLARED class gets. Without it UClsVMTOffset stayed -1 and the
    ctor's VMT stamp wrote a garbage data reference into [instance+0] — so
    anything reading an instance's class identity (`o is T`'s runtime blob walk,
    ClassName) walked wild memory for a plain TObject.Create instance. One
    padding slot, never dispatched (the root has no virtuals until an override
    materialises one). }
  for i := 0 to 15 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  UClsVMTOffset[ci] := DataLen;
  { The root virtuals' reserved slots, same count every DECLARED class gets, so
    TObject's own table is the base of the layout rather than an exception to
    it. Still at least one word when nothing is reserved (--compact-classes),
    which is the padding slot this always had.
    feature-a-tobject-root-method-vmt-slots. }
  UClsVirtCount[ci] := RootVMTSlotCount;
  vmtN := RootVMTSlotCount;
  if vmtN < 1 then vmtN := 1;
  for i := 0 to vmtN * 8 - 1 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
end;

{ Give TObject's row its four root METHODS, so a receiver statically typed
  TObject resolves `o.Equals(x)` / `o.GetHashCode` / `o.ToString` through the
  ordinary member lookup and dispatches VIRTUALLY through the fixed slot — which
  is the entire point of reserving the slots.

  LAZY, and it has to be: the bodies are ordinary Pascal in the builtin unit, so
  the procs do not exist until that unit is loaded, which happens after the
  token pre-scan. Called once from ParseProgram right after the ambient units
  are in. When the builtin unit is NOT linked the rows are simply not added, and
  `o.Equals(x)` is the ordinary "no such member" compile error — a refusal, not
  a nil dispatch. `Destroy` is deliberately not among them: `Free` calls Destroy
  only for a class that declares one, and a direct `TObject.Destroy` has never
  been a member here. }
procedure AddTObjectRootMethod(ci, slot: Integer; const nm, helper: AnsiString);
var pi, mi: Integer;
begin
  pi := FindProc(helper);
  if pi < 0 then Exit;   { builtin not linked — see the note above }
  AddUMeth(ci, TokCharsAppend(nm), Length(nm), pi);
  mi := UMthCount - 1;
  UMthVirSlot[mi] := slot;
  { TObject's own VMT was emitted long before these rows existed (it is minted
    in RegisterBuiltinTObject, at startup), so nothing else will ever fill its
    slots — the decl-time fill loop only runs for a class the PARSER declares. }
  if UClsVMTOffset[ci] >= 0 then
  begin
    if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
    MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + slot * 8;
    MethodFixups[MethodFixCount].ProcIdx := pi;
    Inc(MethodFixCount);
  end;
end;

procedure EnsureTObjectRootMethods;
var ci, n: Integer;
begin
  n := RootVMTSlotCount;
  if n <= 0 then Exit;
  ci := FindUClass('TObject');
  if ci < 0 then Exit;
  if FindUMeth(ci, 'Equals') >= 0 then Exit;   { idempotent }
  if ROOT_VMT_EQUALS < n then
    AddTObjectRootMethod(ci, ROOT_VMT_EQUALS, 'Equals', '__pxxTObjectEquals');
  if ROOT_VMT_GETHASHCODE < n then
    AddTObjectRootMethod(ci, ROOT_VMT_GETHASHCODE, 'GetHashCode', '__pxxTObjectGetHashCode');
  if ROOT_VMT_TOSTRING < n then
    AddTObjectRootMethod(ci, ROOT_VMT_TOSTRING, 'ToString', '__pxxTObjectToString');
end;

{ Fill every class's UNRESOLVED reserved root slots with the default bodies.
  Deferred to the end of compilation on purpose: a class's VMT is emitted when
  the class is declared, and at that moment the builtin unit may not have been
  parsed, so the default procs do not exist yet. MethodFixups are applied at
  link time, so recording them late is fine — the DataPos is already reserved.

  A slot the class (or an ancestor) DOES resolve is left alone: ResolveVMTSlotProc
  already wired it. }
procedure FillRootVMTSlotDefault(ci, slot: Integer; const helper: AnsiString);
var hp: Integer;
begin
  if UClsVMTOffset[ci] < 0 then Exit;
  if ResolveVMTSlotProc(ci, slot) >= 0 then Exit;
  hp := FindProc(helper);
  if hp < 0 then Exit;
  if MethodFixCount >= MAX_METHFIX then Error('too many virtual method fixups');
  MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + slot * 8;
  MethodFixups[MethodFixCount].ProcIdx := hp;
  Inc(MethodFixCount);
end;

procedure FillRootVMTSlotDefaults;
var ci, n: Integer;
begin
  n := RootVMTSlotCount;
  if n <= 0 then Exit;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] or UClsIsInterface[ci] then Continue;
    if UClsVirtCount[ci] < n then Continue;
    if ROOT_VMT_EQUALS < n then
      FillRootVMTSlotDefault(ci, ROOT_VMT_EQUALS, '__pxxTObjectEquals');
    if ROOT_VMT_GETHASHCODE < n then
      FillRootVMTSlotDefault(ci, ROOT_VMT_GETHASHCODE, '__pxxTObjectGetHashCode');
    if ROOT_VMT_TOSTRING < n then
      FillRootVMTSlotDefault(ci, ROOT_VMT_TOSTRING, '__pxxTObjectToString');
  end;
  { ROOT_VMT_DESTROY is deliberately left nil when nothing overrides it: Free
    dispatches Destroy only for a class that declares one, so an unfilled slot 0
    is unreachable rather than a trap waiting to fire. }
end;

procedure ParseProgram;
var jmpPatch, i, j, wdDepth: Integer; needsPromoInt: Boolean;
    doneUses, doneDecls, hasExceptions, needsBuiltin,
    needsHeap, needsAnsiRuntime, needsDivStub, needHeapUnit, hasCoroutine, needsTextfile: Boolean;
    usesMath, needsMath: Boolean;
    usesTextfile: Boolean; tnm: AnsiString;
    savedUnitIdx, afterDeclTok: Integer;
    exitPi: Integer;   { PXXExitProcess — the main-body epilogue, see the end of this routine }
    dummyNames: array[0..7] of AnsiString;
    dummyTypes: array[0..7] of TTypeKind;
begin
  PendingInitCount := 0;
  ArrTypeCount := 0;
  StrConstCount := 0;
  SetConstCount := 0;
  ClassConstCount := 0;
  ParsingClassConstCi  := -1;
  ParsingClassBodyCi   := -1;
  NestedTypeCount      := 0;
  ParsingClassConstVis := 0;
  { Decl-order gating defaults: no body active (a high sentinel means "see all"
    outside a routine body — main body + pre-scan), strict by default. }
  CurBodyHdrTok    := $7FFFFFFF;
  DeclOrderStrict  := not LaxDeclOrder;   { strict by default; --lax-decl-order / {$DECLORDER OFF} opts out }
  { The `program Name;` header is OPTIONAL, matching FPC (and Turbo Pascal
    back to 1.0, where the heading was decorative) — a source that opens
    directly with uses/type/var/const/begin/... is a valid program
    (bug-pascal-headerless-program; 111 FPC-conformance tests hit this).
    A file that opens with `unit` is a unit compiled as a program: pxx is a
    whole-program compiler with no .ppu model, so say that plainly instead
    of "expected program". }
  if CurTok.Kind = tkUnit then
    Error('this file is a unit, not a program — compile a program that uses it (pxx has no standalone-unit output)');
  if CurTok.Kind = tkProgram then
  begin
    Next;
    if CurTok.Kind = tkEOF then Error('expected program name');
    DbgProgName := CurTok.SVal;  { -g: names the main-body subprogram }
    Next;  { program name can be any identifier (even keyword) }
    if CurTok.Kind = tkLParen then
      begin Next; while CurTok.Kind <> tkRParen do Next; Next; end;
    Eat(tkSemicolon);
  end
  else
    DbgProgName := 'program';    { headerless: anonymous main subprogram for -g }

  { Reserve BSS[0..7] for initial rsp (argv access) }
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_PTR    := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_END    := BSSSize; Inc(BSSSize, 8);
  BSS_FREE_LIST   := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_LOCK   := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_POS    := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_LEN    := BSSSize; Inc(BSSSize, 8);
  BSS_PEEK_VALID  := BSSSize; Inc(BSSSize, 8);
  BSS_PEEK_BYTE   := BSSSize; Inc(BSSSize, 8);
  BSS_LINE_BUF    := BSSSize; Inc(BSSSize, LINE_BUF_SIZE);
  BSS_INTBUF      := BSSSize; Inc(BSSSize, INTBUF_SIZE);
  { BSS_IO_OWNER / BSS_IO_DEPTH are NOT allocated here any more: they belong to
    EmitIoLockStubsForTarget, alongside the stubs that are their only reader.
    Allocating them here meant every non-Pascal driver left both at 0 — i.e.
    aliased onto the same eight bytes — which is a second, independent way for
    --threadsafe to break (bug-a-threadsafe-segfaults-on-every-nilpy-program). }
  EnsureSignalBss;   { the BSS_SIG_* block — allocated here to keep this driver's
                       layout; idempotent, and every other frontend gets it from
                       EmitProgramRuntimeStubsForTarget instead }
  ExceptionUsed := False;
  CoroutineUsed := False;
  CloneStubAddr := 0;        { 0 = clone+trampoline stub not yet emitted (lazy) }
  hasExceptions := False;
  hasCoroutine := False;
  needsBuiltin := False;
  needsTextfile := False;
  usesMath := False;
  needsMath := False;
  needsPromoInt := False;
  { Default standard surface: textfile (classic Text/Assign/Reset/WriteLn) is
    loaded by default on every non-ESP program, so `var f: Text` resolves
    uniformly in programs, units, methods, and nested scopes — no token-scan
    special case. Its numeric write dispatch formats through builtin's
    StrInt/StrFloat, so builtin is pulled in too. ESP backends (xtensa/riscv32)
    cannot compile either unit yet, so they stay opt-in via explicit `uses`. }
  { Source opt-out: a program defining PXX_NODEFAULTRTL (the compiler itself does)
    suppresses the default surface the same as the --no-default-rtl flag. The
    define travels with the source, so every self-build path — bootstrap,
    cross-bootstrap, stabilize, manual — opts out without per-site Makefile flags. }
  if PasDefineExists('PXX_NODEFAULTRTL') then NoDefaultRtl := True;
  RegisterBuiltinTGuid;
  RegisterBuiltinTObject;
  { Only pull the implicit textfile surface when the source actually references
    the file type. Scanning the already-lexed token stream up front for a bare
    `Text`/`TextFile`/`IOResult` identifier (any position — var/param/field/
    return/method, so more robust than the old `: Text` positional scan) skips
    the ~0.19s textfile+builtin load for the common file-less program (plain
    writeln to stdout uses builtins, not the textfile RTL). A length pre-check
    avoids building a string for every token. An explicit `uses textfile` still
    loads it regardless (handled in the token loop below). }
  if (not NoDefaultRtl) and (not TargetIsEspClass) then
  begin
    usesTextfile := False;
    for i := 0 to TokCount - 1 do
      if (Tokens[i].Kind = tkIdent) and
         ((Tokens[i].SLen = 4) or (Tokens[i].SLen = 5) or (Tokens[i].SLen = 8)) then
      begin
        tnm := GetTokenStr(i);
        if CaseEqual(tnm, 'text') or CaseEqual(tnm, 'textfile') or CaseEqual(tnm, 'ioresult') or
           { Flush(f)/Flush(output): FPC System surface, lives in textfile
             (which also declares the standard Input/Output files). }
           CaseEqual(tnm, 'flush') then
        begin usesTextfile := True; Break; end;
      end;
    if usesTextfile then
    begin
      needsBuiltin := True;
      needsTextfile := True;
    end;
  end;
  { FPC declares the elementary math functions in the System unit, so
    `writeln(sqrt(16.0))` compiles with no `uses` at all. We keep them in the
    `math` unit — 618 lines of correctly-rounded numerics (Sqrt alone carries a
    Dekker two-product correction step) that has no business being duplicated
    into builtin. So instead of redeclaring them, pull `math` in on demand the
    same way `textfile` is pulled for Text/IOResult/Flush: scan the token stream
    for a bare use of one of the System-surface names and add the unit.
    A user routine of the same name still shadows at the call site, exactly as
    with the textfile names. }
  if (not NoDefaultRtl) and (not TargetIsEspClass) then
  begin
    { Require a following '(' — these are all functions, and `ln` in
      particular is a plausible variable name (a line number). Without the
      check, `var ln: Integer` would silently pull 35KB of math into a program
      that never calls it. }
    for i := 0 to TokCount - 1 do
      if (Tokens[i].Kind = tkIdent) and
         (Tokens[i].SLen >= 2) and (Tokens[i].SLen <= 6) then
      begin
        tnm := GetTokenStr(i);
        if (CaseEqual(tnm, 'sqrt') or CaseEqual(tnm, 'exp') or
            CaseEqual(tnm, 'ln') or CaseEqual(tnm, 'sin') or
            CaseEqual(tnm, 'cos') or CaseEqual(tnm, 'arctan')) and
           (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkLParen) then
        begin usesMath := True; Break; end;
        { Pi is the exception to the '(' rule: FPC's System declares it too, and
          it is PARAMLESS, so it is written bare. Nothing distinguishes it from
          a variable named `pi` at this stage, so a program with one pays ~35KB
          of unreferenced math. That is a size cost, not a correctness one — the
          variable still shadows the unit's function
          (bug-p-program-function-does-not-shadow-used-unit). }
        if CaseEqual(tnm, 'pi') then
        begin usesMath := True; Break; end;
      end;
    if usesMath then needsMath := True;
  end;
  DetectPascalRuntimeNeeds(needsHeap, needsAnsiRuntime, needsDivStub);
  { Full builtin (Str/Val/Variant) is pulled only for AnsiString/exception
    programs and on demand for Str/Val (token loop below). The heap allocator
    and managed-string helpers live in the separate `builtinheap` unit so a
    heap-only program does not drag in the conversion routines (which need
    features not yet on every target). }
  { Plain AnsiString needs only builtinheap (allocator + PXXStr*), not the full
    builtin conversions. Variant/Str/Val/uses pull builtin in the token loop. }
  needHeapUnit := needsHeap or needsAnsiRuntime or ComInterfaceUsed;

  if needHeapUnit then
  begin
    savedUnitIdx := CurrentUnitIdx;
    CurrentUnitIdx := InternStr('builtinheap');

    dummyNames[0] := 'size';  dummyTypes[0] := tyNativeInt;
    dummyNames[1] := 'align'; dummyTypes[1] := tyInteger;
    i := RegisterProc('PXXAlloc', True, tyPointer, 2, dummyNames, dummyTypes);

    dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXFree', False, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
    dummyNames[1] := 'newSize'; dummyTypes[1] := tyNativeInt;
    dummyNames[2] := 'align'; dummyTypes[2] := tyInteger;
    i := RegisterProc('PXXRealloc', True, tyPointer, 3, dummyNames, dummyTypes);

  { Managed-string ARC helpers are target-independent (allocator-backed), so
    register them on every target including ESP. }
  dummyNames[0] := 'len';   dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'src';   dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXStrFromLit', True, tyPointer, 2, dummyNames, dummyTypes);

  { PChar('') / PChar(emptyAnsiString) must not be nil: substitutes a static #0
    byte for a nil managed handle (FPC-compat, prevents nil-deref at C calls). }
  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXPCharOf', True, tyPointer, 1, dummyNames, dummyTypes);

  { Generic dynamic-array Copy support helpers (clamp count + raw byte copy). }
  dummyNames[0] := 'srcData'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'index';   dummyTypes[1] := tyNativeInt;
  dummyNames[2] := 'count';   dummyTypes[2] := tyNativeInt;
  i := RegisterProc('PXXClampLen', True, tyNativeInt, 3, dummyNames, dummyTypes);

  dummyNames[0] := 'dest';  dummyTypes[0] := tyPointer;
  dummyNames[1] := 'src';   dummyTypes[1] := tyPointer;
  dummyNames[2] := 'n';     dummyTypes[2] := tyNativeInt;
  i := RegisterProc('PXXMemCopy', True, tyPointer, 3, dummyNames, dummyTypes);

  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'srcB';  dummyTypes[2] := tyPointer;
  dummyNames[3] := 'lenB';  dummyTypes[3] := tyNativeInt;
  i := RegisterProc('PXXStrConcat', True, tyPointer, 4, dummyNames, dummyTypes);

  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'srcB';    dummyTypes[1] := tyPointer;
  dummyNames[2] := 'lenB';    dummyTypes[2] := tyNativeInt;
  i := RegisterProc('PXXStrAppend', False, tyPointer, 3, dummyNames, dummyTypes);

  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrIncRef', False, tyPointer, 1, dummyNames, dummyTypes);
  i := RegisterProc('PXXStrDecRef', False, tyPointer, 1, dummyNames, dummyTypes);
  { COM/ARC interface ARC helpers: not on ESP (indirect IMT dispatch the ESP
    backends can't lower; bodies are {$ifndef PXX_ESP}-guarded in builtinheap). }
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
  begin
    { All four take the interface ID as their last argument: an interface value is
      a bare instance pointer now, so the IMT (and with it the _AddRef/_Release
      slots) is resolved from the instance's RTTI blob by id at run time. }
    dummyNames[0] := 'inst';    dummyTypes[0] := tyPointer;
    dummyNames[1] := 'ifaceId'; dummyTypes[1] := tyNativeInt;
    i := RegisterProc('PXXIntfIMTOf', True, tyPointer, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'p';       dummyTypes[0] := tyPointer;
    dummyNames[1] := 'ifaceId'; dummyTypes[1] := tyNativeInt;
    i := RegisterProc('PXXIntfAddRef', True, tyNativeInt, 2, dummyNames, dummyTypes);
    i := RegisterProc('PXXIntfRelease', True, tyNativeInt, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'inst';    dummyTypes[0] := tyPointer;
    dummyNames[1] := 'ifaceId'; dummyTypes[1] := tyNativeInt;
    i := RegisterProc('PXXIntfAddRefRaw', True, tyNativeInt, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'dest';    dummyTypes[0] := tyPointer;
    dummyNames[1] := 'src';     dummyTypes[1] := tyPointer;
    dummyNames[2] := 'ifaceId'; dummyTypes[2] := tyNativeInt;
    i := RegisterProc('PXXIntfAssign', False, tyPointer, 3, dummyNames, dummyTypes);
  end;
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrUnique', True, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'strSlot'; dummyTypes[0] := tyPointer;
  dummyNames[1] := 'newLen';  dummyTypes[1] := tyNativeInt;
  i := RegisterProc('PXXStrSetLen', False, tyPointer, 2, dummyNames, dummyTypes);

  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'lenB';  dummyTypes[2] := tyNativeInt;
  dummyNames[3] := 'srcB';  dummyTypes[3] := tyPointer;
  i := RegisterProc('PXXStrEq', True, tyInt64, 4, dummyNames, dummyTypes);

  { Xtensa software integer-divide helpers: only when targeting an LX6 part
    (--xtensa-cpu=lx6). Registered (hence emitted) only then so LX7 images
    stay lean and keep their native quos/rems. }
  if (TargetArch = TARGET_XTENSA) and XtensaSoftDivide then
  begin
    dummyNames[0] := 'n'; dummyTypes[0] := tyUInt32;
    dummyNames[1] := 'd'; dummyTypes[1] := tyUInt32;
    i := RegisterProc('__pxx_udivsi3', True, tyUInt32, 2, dummyNames, dummyTypes);
    dummyNames[0] := 'a'; dummyTypes[0] := tyInteger;
    dummyNames[1] := 'b'; dummyTypes[1] := tyInteger;
    i := RegisterProc('__pxx_divsi3', True, tyInteger, 2, dummyNames, dummyTypes);
    i := RegisterProc('__pxx_modsi3', True, tyInteger, 2, dummyNames, dummyTypes);
  end;

  { File load, variant and float-format helpers are not on ESP yet. }
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
  begin
    dummyNames[0] := 'path';  dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXStrLoadFile', True, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'dest';      dummyTypes[0] := tyPointer;
    dummyNames[1] := 'left';      dummyTypes[1] := tyPointer;
    dummyNames[2] := 'right';     dummyTypes[2] := tyPointer;
    dummyNames[3] := 'opTk';      dummyTypes[3] := tyNativeInt;
    dummyNames[4] := 'isCompare'; dummyTypes[4] := tyNativeInt;
    i := RegisterProc('PXXVarBinOp', True, tyInt64, 5, dummyNames, dummyTypes);

    dummyNames[0] := 'dest';      dummyTypes[0] := tyPointer;
    dummyNames[1] := 'right';     dummyTypes[1] := tyPointer;
    i := RegisterProc('PXXVarStrAppend', True, tyInt64, 2, dummyNames, dummyTypes);

    dummyNames[0] := 'v';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXVarClear', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXVarRetain', False, tyPointer, 1, dummyNames, dummyTypes);
    { object retain/release: the emitted obj blobs call these (population-tag
      guard + finalizer hook live in the Pascal bodies) — registered here so
      EmitAnsiStringRuntime can reference them before builtinheap parses
      (feature-nilpy-object-reclamation) }
    dummyNames[0] := 'p';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXObjRetain', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXObjRelease', False, tyPointer, 1, dummyNames, dummyTypes);
    i := RegisterProc('PXXWriteVariant', False, tyPointer, 1, dummyNames, dummyTypes);

    dummyNames[0] := 'p';         dummyTypes[0] := tyPointer;
    i := RegisterProc('PXXWriteFloatNat', False, tyPointer, 1, dummyNames, dummyTypes);
    dummyNames[1] := 'decimals';  dummyTypes[1] := tyNativeInt;
    dummyNames[2] := 'width';     dummyTypes[2] := tyNativeInt;
    i := RegisterProc('PXXWriteFloatFixed', False, tyPointer, 3, dummyNames, dummyTypes);
    { Sci takes (p, fracdigits, expdigits) — the SAME three-slot shape as Fixed.
      It was registered with one parameter until 2026-08-19, which is the other
      half of why write(d:W) could not narrow the mantissa: even had the emitter
      passed a width, the pre-registration here declared no slot to receive it. }
    dummyNames[1] := 'fracdigits'; dummyTypes[1] := tyNativeInt;
    dummyNames[2] := 'expdigits';  dummyTypes[2] := tyNativeInt;
    i := RegisterProc('PXXWriteFloatSci', False, tyPointer, 3, dummyNames, dummyTypes);
  end;

    CurrentUnitIdx := savedUnitIdx;
  end;
  for i := 0 to MAX_GOTO_LABELS - 1 do GotoLabelIRId[i] := -1;
  i := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkTry, tkRaise] then hasExceptions := True;
    { `class operator Finalize` desugars to a try..finally around the routine
      body (WrapManagementOps), and the exception runtime's stubs are emitted
      HERE, from a token pre-scan, long before that body is parsed. A program
      whose only try is one the compiler synthesised therefore called a stub at
      code offset 0. Trigger on the declaration itself, which is the same
      evidence the desugar will act on.
      feature-pascal-class-management-operators }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'finalize') and
       (i > 0) and (Tokens[i - 1].Kind = tkIdent) and
       CaseEqual(GetTokenStr(i - 1), 'operator') then
      hasExceptions := True;
    { A program naming the promotable-int type pulls its runtime (and, through
      it, bignum). Nothing else references those entry points, so a Pascal or C
      program that never names the type keeps them unreachable and DCE drops
      them — the "no size growth" half of the feature's own gate. }
    if (Tokens[i].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(i), 'promoint') or CaseEqual(GetTokenStr(i), 'promoint64')
        or CaseEqual(GetTokenStr(i), 'promoint32')) then
      needsPromoInt := True;
    { The coroutine context-switch stub must be emitted before the main body
      (it is reached only by `call`), so detect any use of the low-level
      __pxxcoswitch intrinsic up front. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), '__pxxcoswitch') then
      hasCoroutine := True;
    { Pull in the builtin unit (Str/Val backing) only if the program calls
      Str(...) or Val(...) — name immediately followed by '(', so plain
      variables/params named str/val don't drag it in. No DCE, so this keeps it
      out of programs that never use them. }
    { The full `builtin` unit (Str/Val/Variant) uses frozen-string concat, which
      the ESP backends (xtensa/riscv32) cannot lower, so it is never pulled there
      — a program that genuinely needs Str/Val on ESP fails at the call site
      instead of dragging in an uncompilable unit. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { `x.Equals(...)` / `x.GetHashCode` / `x.ToString` pulls the builtin unit:
      the TObject root methods' default bodies (__pxxTObject*) live there, and
      EnsureTObjectRootMethods only registers the rows when it can see the procs.
      Dot-preceded on purpose — a class of your own that merely DECLARES a
      ToString should not drag 42 KB in. feature-a-tobject-root-method-vmt-slots }
    if (Tokens[i].Kind = tkIdent) and (i > 0) and (Tokens[i - 1].Kind = tkDot) and
       (RootVMTSlotCount > 0) and (not TargetIsEspClass) and
       (CaseEqual(GetTokenStr(i), 'equals') or CaseEqual(GetTokenStr(i), 'gethashcode')
        or CaseEqual(GetTokenStr(i), 'tostring')) then
      needsBuiltin := True;
    { A VARIANT anywhere in the program pulls the builtin unit, because assigning
      a variant to a scalar lowers to VariantToInt64/Double/Bool/Char/Str and
      IRLowerVariantAsScalar hard-Errors when FindProc cannot see one. The unit
      used to arrive only as a side effect of some OTHER feature (a string
      variable pulled it, a Double did not), so on cross targets whether a
      program built at all was decided by an unrelated declaration:
      `out_ := someVariant` failed with "variant unbox: VariantToInt64 builtin
      not loaded" on i386/aarch64/arm32 while x86-64 compiled it
      (bug-a-variant-unbox-wrong-on-32bit-and-unavailable-cross). Same ESP
      exclusions as the Str/Val pull above — those targets cannot compile the
      unit, and there a variant program fails at the call site instead. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'variant') and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { Bare `Copy(...)` on a string lowers to the __pxxStrCopy substring helper in
      the builtin unit (see ParseFactor). Pull the unit so the helper resolves;
      the string-vs-dynarray decision is made at the call site, so a dynarray-only
      Copy just leaves the extra helper unused. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and CaseEqual(GetTokenStr(i), 'copy') and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { WideChar / UCS4Char / UnicodeChar: pulled on ANY mention, because each is
      a declarable TYPE and the conversion helpers (__pxxWideCharToUTF8 and the
      pair form, __pxxUCS4ToUTF8) are needed wherever such a value reaches a
      string context — which is not only at a cast.

      WideChar used to be pulled ONLY for a `widechar(` CAST, on the reasoning
      spelled out for UCS4Char right here: "unlike WideChar it is a declarable
      TYPE". That reasoning was simply wrong — `var w: WideChar` is as ordinary
      as `var c: UCS4Char` — and the consequence was a HARD COMPILE ERROR on
      code FPC accepts:

          var w: WideChar; s: AnsiString;
          begin w := 'A'; s := w; end.
          -> "WideChar->string conversion: __pxxWideCharToUTF8 helper not loaded"

      and it failed only when the program contained no `WideChar(` cast
      anywhere, which is why it survived: every test that exercised the
      conversion happened to write the cast. Found by a WideChar-source x
      string-context differential against FPC
      (refactor-centralize-managed-string-pchar-conversion).

      The cost is a builtin unit pulled by a program that merely NAMES the type
      and never converts — the same cost this arm already accepted for
      UCS4Char, and the same failure mode as not pulling it is a build abort. }
    if (Tokens[i].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(i), 'widechar') or CaseEqual(GetTokenStr(i), 'ucs4char') or
        CaseEqual(GetTokenStr(i), 'unicodechar')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { The hardware-entropy intrinsics (__pxxCpuHasHwRandom / __pxxHwRandom64)
      live in the builtin unit, and lib/rtl/random.pas is required to call them
      with no per-arch anything of its own — that mandate is the whole reason
      they are compiler-side. Bare-name match: the probe takes no arguments, so
      it is normally written without parentheses.
      feature-a-rdrand-cpuid-compiler-builtins }
    if (Tokens[i].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(i), '__pxxcpuhashwrandom') or
        CaseEqual(GetTokenStr(i), '__pxxhwrandom64')) and (not TargetIsEspClass) then
      needsBuiltin := True;
    { `obj.MethodAddress(name)` / `obj.MethodName(addr)` lower to __pxxMethodAddress /
      __pxxMethodName in the builtin unit (see ParseLValueAST) — FPC has them on
      TObject in System, so they must work with no `uses`. A class with a method of
      that name shadows at the call site, leaving the helpers unused. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'methodaddress') or CaseEqual(GetTokenStr(i), 'methodname') or
        { Supports(obj, IFoo, Intf) lowers to the same __pxxGetInterface — the
          two-argument form does not, but an unused helper is dropped anyway. }
        CaseEqual(GetTokenStr(i), 'supports') or
        CaseEqual(GetTokenStr(i), 'getinterface')) and (not TargetIsEspClass) then
      needsBuiltin := True;
    { `x.ClassName` lowers to __pxxClassName (+ __pxxRttiOf for an instance) — see
      GenMakeClassNameCall. Unlike the helpers above it takes NO arguments, so it is
      normally written with no '(' and must be matched on the bare name. A class with
      a member of that name shadows at the call site, leaving the helpers unused. }
    if (Tokens[i].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(i), 'classname') or CaseEqual(GetTokenStr(i), 'inheritsfrom') or
        CaseEqual(GetTokenStr(i), 'classparent') or
        CaseEqual(GetTokenStr(i), 'instancesize') or CaseEqual(GetTokenStr(i), 'classnameis') or
        { `E is <class-reference VALUE>` lowers to __pxxInheritsFrom (see ParseExpr).
          Whether the right-hand side is a class NAME (compile-time, no helper) or a
          TClass value (runtime, helper) is not knowable from the tokens, so the
          soft-keyword `is` pulls the unit. An unused helper is dropped by the linker
          path anyway; a missing one would silently disable the operator. }
        CaseEqual(GetTokenStr(i), 'is')) and (not TargetIsEspClass) then
      needsBuiltin := True;
    { A write/writeln with a VARIABLE field width pre-formats through
      StrInt/StrFloat/StrChar/StrStrW/StrBool, which live in the builtin unit —
      so a program with no `uses` clause failed with `StrInt not loaded`,
      naming a routine the user never wrote. Pull the unit when a ':' inside a
      write argument list is followed by something other than an integer
      literal; a LITERAL width formats inline in codegen and needs nothing.
      bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit }
    if ((Tokens[i].Kind = tkwrite) or (Tokens[i].Kind = tkwriteln)) and
       (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkLParen) and
       (not TargetIsEspClass) then
    begin
      wdDepth := 0;
      j := i + 1;
      while j < TokCount do
      begin
        if Tokens[j].Kind = tkLParen then Inc(wdDepth)
        else if Tokens[j].Kind = tkRParen then
        begin
          Dec(wdDepth);
          if wdDepth = 0 then Break;
        end
        else if (Tokens[j].Kind = tkColon) and (wdDepth = 1) and
                (j + 1 < TokCount) and (Tokens[j + 1].Kind <> tkInteger) then
          needsBuiltin := True;
        Inc(j);
      end;
    end;
    { Bare `Delete(...)` / `Insert(...)` on a string lower to __pxxStrDelete /
      __pxxStrInsert in the builtin unit (see ParseStatementAST). Pull the unit so
      the helpers resolve; a user routine of the same name shadows at the call
      site, leaving the helpers unused. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'delete') or CaseEqual(GetTokenStr(i), 'insert')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { `InterLocked*(...)` resolve to the wrappers in the builtin unit — FPC
      declares them in `system`, so real FPC source calls them with NO uses
      line and must still compile (bug-a-interlocked-family-needs-a-uses-clause-
      unlike-fpc). Prefix-matched so the *64 peers come along. A user routine or
      `uses palatomic` shadows at the call site, leaving these unused. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (Length(GetTokenStr(i)) >= 11) and
       CaseEqual(Copy(GetTokenStr(i), 1, 11), 'InterLocked') and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { Bare `Abs(...)` / `Sqr(...)` lower to the __pxxAbs*/__pxxSqr* helpers in the
      builtin unit (see ParseFactor). Pull the unit so they resolve; a user
      routine of the same name shadows. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'abs') or CaseEqual(GetTokenStr(i), 'sqr')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { Bare `UpCase(...)` / `Pos(...)` lower to __pxxUpCase / __pxxPos in the
      builtin unit (see ParseFactor); pull it so they resolve. ESP can't. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'upcase') or CaseEqual(GetTokenStr(i), 'pos') or
        CaseEqual(GetTokenStr(i), 'roldword') or CaseEqual(GetTokenStr(i), 'rordword') or
        CaseEqual(GetTokenStr(i), 'rolqword') or CaseEqual(GetTokenStr(i), 'rorqword')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { Bare `Move(...)` / `FillChar(...)`: System memory primitives live in the
      builtin unit (FPC keeps them in System, no `uses` needed). Pull the unit
      so they resolve; a user routine of the same name shadows at the call
      site. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'assert') or
        CaseEqual(GetTokenStr(i), 'move') or CaseEqual(GetTokenStr(i), 'fillchar') or
        CaseEqual(GetTokenStr(i), 'fillbyte') or CaseEqual(GetTokenStr(i), 'filldword') or
        CaseEqual(GetTokenStr(i), 'comparebyte') or CaseEqual(GetTokenStr(i), 'comparechar')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { FPC System surface living in builtin as plain Pascal: the PRNG
      (Random/Randomize/RandSeed) plus HexStr/RunError/UniqueString. Call-shaped
      names require the '(' (a variable named random must not drag the unit
      in); randseed/randomize are legitimately bare (RandSeed := 17;
      Randomize;). A user declaration of the same name shadows at the use
      site, leaving the unit's version unused. ESP can't compile builtin. }
    if (Tokens[i].Kind = tkIdent) and
       (((i + 1 < TokCount) and (Tokens[i + 1].Kind = tkLParen) and
         (CaseEqual(GetTokenStr(i), 'random') or CaseEqual(GetTokenStr(i), 'hexstr') or
          CaseEqual(GetTokenStr(i), 'runerror') or CaseEqual(GetTokenStr(i), 'uniquestring') or
          CaseEqual(GetTokenStr(i), 'lo') or CaseEqual(GetTokenStr(i), 'hi') or
          CaseEqual(GetTokenStr(i), 'swap'))) or
        CaseEqual(GetTokenStr(i), 'randseed') or CaseEqual(GetTokenStr(i), 'randomize')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { Variant use needs VariantToStr (in builtin) for variant writes — on
      x86-64. Cross targets serve variants from builtinheap (PXXVar* helpers)
      and cannot compile the full builtin unit yet. }
    if (Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'Variant') and
       (TargetArch = TARGET_X86_64) then
      needsBuiltin := True;
    if (Tokens[i].Kind = tkUses) and (not TargetIsEspClass) then
      needsBuiltin := True;
    { A PChar/PAnsiChar in scope may be converted to string — implicitly in a
      `string` assignment or string-param call, or explicitly via string(pc).
      Both lower to the PCharToString helper (in builtin). Pull the unit so the
      helper resolves in a standalone program. Gated by `not NoDefaultRtl` so the
      compiler's own PXX_NODEFAULTRTL self-build (uses PChar heavily, ships its own
      builtins) never drags in builtin.pas. ESP can't compile builtin. }
    if (not NoDefaultRtl) and (Tokens[i].Kind = tkIdent) and
       (CaseEqual(GetTokenStr(i), 'pchar') or CaseEqual(GetTokenStr(i), 'pansichar')) and
       (not TargetIsEspClass) then
      needsBuiltin := True;
    { …and the same rule for a static `array of Char`, which IS a string in both
      directions and lowers to __pxxCharArrayToStr / __pxxStrToCharArray (also
      in builtin). Keyed on the token PAIR `of` + `char` so it fires for
      `array[0..7] of Char` and `array of Char` and nothing else — `char` alone
      appears in almost every program and would drag builtin.pas into all of
      them. bug-p-a-char-array-is-not-a-string-in-any-direction }
    if (not NoDefaultRtl) and (Tokens[i].Kind = tkOf) and (i + 1 < TokCount) and
       (Tokens[i + 1].Kind = tkChar_T) and (not TargetIsEspClass) then
      needsBuiltin := True;
    Inc(i);
  end;

  { The entry stub: save the initial sp, then jump to the main body. Its six
    per-arch arms used to be spelled out right here, in the Pascal driver only
    — which is why every other frontend open-coded the x86-64 one and nothing
    else, and a NilPy arm32 binary began with x86-64 bytes. Same move as
    EmitIoLockStubsForTarget below, for the same reason.
    False = no mmap heap arena: the Pascal model grows the break lazily in
    builtinheap. bug-a-nilpy-on-cross-targets-four-remaining-walls }
  EmitProgramEntryForTarget(False, jmpPatch);
  { The emitted AnsiString runtime is x86-64 machine code; i386 string IR ops
    call the builtinheap Pascal helpers directly instead, so skip the shim
    emission there (its AnsiStr*Addr labels stay 0 and are never referenced). }
  if needsAnsiRuntime and (TargetArch = TARGET_X86_64) then EmitAnsiStringRuntime;
  { Integer div-by-zero abort stub (Runtime error 200): referenced by div/mod
    sites that have no builtinheap PXXDivZero to call. Emitted only when the
    pre-scan saw a div/mod token (feature-opt-div0-stub-on-use) — division-free
    programs carry neither the stub nor its message string. x86-64 only for now
    (other backends keep their per-target hardware behavior until their sites
    get the check — see bug-integer-div-zero-sigfpe-uncatchable). }
  { needsHeap keeps the stub: builtinheap's OWN div sites compile before its
    PXXDivZero is registered (FindProc misses mid-unit) and fall back to the
    stub. C mode likewise (C tokens carry no tkDiv; C '%'/'/' emit checks).
    The trim targets exactly the unit-free division-free Pascal program. }
  if (TargetArch = TARGET_X86_64) and (needsDivStub or needsHeap or CProgramMode) then
    EmitDiv0Stub;
  { The one "finish the runtime" step: signal runtime (restorer / dispatch /
    sethook / install stubs; --no-signals opts out) plus the --threadsafe I/O
    lock stubs. Both used to be spelled out here, in the Pascal driver only,
    which is precisely why the other eight frontends shipped without either. }
  EmitProgramRuntimeStubsForTarget;
  { --fpc-float-errors decoder stub (feature-float-exception-mask-control):
    emitted next to the signal runtime because it IS a signal hook. }
  if FpcFloatErrors then
  begin
    if TargetArch <> TARGET_X86_64 then
      Error('--fpc-float-errors is x86-64 only: the float-exception mask has no '
            + 'portable mechanism (feature-float-exception-mask-control)');
    if NoSignals then
      Error('--fpc-float-errors needs the signal runtime; it is the SIGFPE hook '
            + 'that turns the trap into a runtime error (drop --no-signals)');
    EmitFpcFloatErrStub;
  end;
  { --fpc-mem-errors decoder stub: same placement and same reason — it IS a
    signal hook. bug-a-a-memory-fault-is-a-raw-sigsegv-not-runtime-error-216 }
  if FpcMemErrors then
  begin
    if TargetArch <> TARGET_X86_64 then
      Error('--fpc-mem-errors is x86-64 only so far: the si_code/si_addr parking '
            + 'the decoder reads is the SA_SIGINFO dispatch, which the other '
            + 'signal runtimes shape differently');
    if NoSignals then
      Error('--fpc-mem-errors needs the signal runtime; it is the SIGSEGV/SIGBUS '
            + 'hook that turns the fault into a runtime error (drop --no-signals)');
    EmitFpcMemErrStub;
  end;
  if hasExceptions then EnableExceptionRuntime;
  if hasCoroutine then EnableCoroutineRuntime;

  { Compile the runtime units before user declarations, so their proc bodies
    land in the proc region after the entry jump and are resolvable. builtinheap
    (allocator + PXXStr*) first, then the Str/Val/Variant conversions. }
  { The ESP-class targets have no FPU codegen: every float op lowers to the
    __pxx_* soft-float kernels. Pull the softfloat unit implicitly (like
    builtinheap) so hosted riscv32 programs with floats (sysutils pulls float
    code) do not each need a manual `uses softfloat`. FIRST — the builtinheap/
    builtin float bodies compile against the kernels. }
  { arm32 has hardware VFP, but its double->int convert is 32-bit only; a 64-bit
    Trunc/Round of a large double routes to the soft-float __pxx_d2i64 kernel
    (mirrors the C-frontend pull in cparser), so arm32 pulls softfloat too. }
  if ((((TargetArch = TARGET_RISCV32) and (not EspBareBoot))) or (TargetArch = TARGET_ARM32)) and
     (needHeapUnit or needsBuiltin) then
    ParseUsesUnitAmbient('softfloat');
  { The promotable-int runtime is written in ordinary Pascal over managed
    strings and bignum, so it needs the heap allocator and the Str/Val
    conversions regardless of what the user program itself uses. }
  if needsPromoInt then
  begin
    needHeapUnit := True;
    needsBuiltin := True;
  end;
  if needHeapUnit then ParseUsesUnitAmbient('builtinheap');
  if needsBuiltin then ParseUsesUnitAmbient('builtin');
  { the TYPE is spelled PromoInt; the UNIT implementing it is promocore — see
    the note at the top of compiler/builtin/promocore.pas for why they differ }
  if needsPromoInt then ParseUsesUnitAmbient('promocore');
  { Implicit text-file unit (classic `Text`/Assign/Reset/... surface), loaded
    like an explicit `uses textfile` would be — before user declarations, so the
    Text record + its procedures resolve and proc-local `var f: Text` gets normal
    managed-field zero-init. }
  if needsTextfile then ParseUsesUnitAmbient('textfile');
  if needsMath then ParseUsesUnitAmbient('math');
  FixupTVarRecLayout;
  DbgGlobalScopeBase := SymCount;  { -g: program globals are declared past here }

  { ===== Declaration pre-scan (pass 1) =====
    Walk the program's top-level declarations registering every routine's header
    (signature), and parsing types/consts/vars/uses for real, but SKIPPING the
    routine bodies — recording each subroutine's token span. After this pass the
    whole section is visible, so a routine may call any other regardless of
    source order and mutual recursion needs no `forward`. Generic/operator/
    specialize/label declarations are handled in full here (not body-deferred);
    they keep their existing source-order visibility. }
  PreScanPass := True;
  DeclItemCount := 0;
  doneDecls := False;
  while not doneDecls do
    case CurTok.Kind of
      tkUses:
      begin
        Next;
        doneUses := False;
        while (CurTok.Kind in [tkIdent, tkString]) and not doneUses do
        begin
          ParseUsesEntry;
          if not Eat(tkComma) then doneUses := True;
        end;
        Eat(tkSemicolon);
      end;
      tkVar:      ParseVarSection;
      tkConst:    ParseConstSection(-1, 0);
      tkType:     ParseTypeSection;
      tkClass,
      tkProcedure,
      tkFunction:
      if (CurTok.Kind = tkClass) and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkIdent) and CaseEqual(GetTokenStr(TokPos), 'operator') then
      begin
        { `class operator TPt.+ (const a, b: TPt): TPt;` — an advanced-record operator
          DEFINITION. Like a plain `operator` definition it emits its body in place and
          rewrites the token stream, so it is parsed in full during the pre-scan rather than
          body-deferred (bug-unit-operator-def-silently-skipped). }
        PreScanPass := False;
        ParseOperatorDef;
        PreScanPass := True;
      end
      else
      begin
        if DeclItemCount >= MAX_DECL_ITEMS then Error('too many top-level declarations');
        DeclItemStart[DeclItemCount] := TokPos - 1;
        ParseSubroutine;
        if not GenericMethodBuffered then
        begin
          DeclItemEnd[DeclItemCount] := TokPos - 1;
          Inc(DeclItemCount);
        end;
      end;
      tkIdent:
        { generic / specialize / operator definitions emit their body in place
          (and rewrite the token stream), so they are parsed in full during the
          pre-scan pass — not body-deferred — by clearing PreScanPass around
          them. They are not recorded for the body pass. }
        if CaseEqual(CurTok.SVal, 'generic') then
        begin PreScanPass := False; ParseGenericFunctionDef; PreScanPass := True; end
        else if CaseEqual(CurTok.SVal, 'specialize') then
        begin PreScanPass := False; ParseTopLevelSpecialize; PreScanPass := True; end
        else if CaseEqual(CurTok.SVal, 'operator') then
        begin PreScanPass := False; ParseOperatorDef; PreScanPass := True; end
        else if CaseEqual(CurTok.SVal, 'constructor') or CaseEqual(CurTok.SVal, 'destructor') then
        begin
          if DeclItemCount >= MAX_DECL_ITEMS then Error('too many top-level declarations');
          DeclItemStart[DeclItemCount] := TokPos - 1;
          ParseSubroutine;
          if not GenericMethodBuffered then
          begin
            DeclItemEnd[DeclItemCount] := TokPos - 1;
            Inc(DeclItemCount);
          end;
        end
        else if CaseEqual(CurTok.SVal, 'resourcestring') then
          ParseConstSection(-1, 0)      { registers as plain string constants }
        else if CaseEqual(CurTok.SVal, 'label') then
          ParseLabelSection
        else
          doneDecls := True;
      else
        doneDecls := True;
    end;
  PreScanPass := False;
  { The root methods' bodies come from the `builtin` unit, so TObject's rows can
    only be minted once every `uses` has been processed — which is the end of
    pass 1, not the ambient-unit block above. Before pass 2, so a body's
    `o.Equals(x)` on a static TObject sees the member.
    feature-a-tobject-root-method-vmt-slots }
  EnsureTObjectRootMethods;
  afterDeclTok := TokPos - 1;   { the program-body `begin` (re-read after pass 2) }

  { ===== Body pass (pass 2) =====
    Re-parse each recorded subroutine, now with the whole section visible, to emit
    its body (the header pass left it as a forward; this completes it). Spans are
    replayed in source order so body code lands in its original relative order. }
  Pass2BodyTok := afterDeclTok;
  Pass2Active  := True;
  i := 0;
  while i < DeclItemCount do   { not a fixed `for`: a lifted nested routine appends fresh items mid-loop }
  begin
    TokPos := DeclItemStart[i];
    Next;
    ParseSubroutine;
    Inc(i);
  end;
  Pass2Active := False;
  TokPos := Pass2BodyTok;
  Next;

  { Patch jmp to point here (start of main body) }
  PatchProgramEntryJump(jmpPatch);

  { Default signal install (SIGINT/SIGTERM) — six arch arms, lifted into
    EmitDefaultSignalInstallForTarget so the other frontends get it too.
    bug-a-only-the-pascal-driver-emits-the-signal-runtime }
  EmitDefaultSignalInstallForTarget;
  { --fpc-float-errors: hook SIGFPE, then UNMASK what FPC unmasks. In that
    order — the hook must be installed before the first trap can fire, and the
    mask write is the thing that makes traps possible at all.

    The mask value is FPC's own, measured with GetExceptionMask under FPC 3.x
    rather than assumed: masked = {exDenormalized, exUnderflow, exPrecision}
    = bits 1|4|5 = 50, i.e. invalid / zero-divide / overflow UNMASKED. }
  { --fpc-mem-errors: hook SIGSEGV and SIGBUS. SigSetHook falls through into
    SigInstall, so one call per signal both records the hook and registers the
    dispatch handler — and the dispatch handler is what parks si_code/si_addr
    the decoder reads. }
  if FpcMemErrors then
  begin
    EmitAsmX64(['mov edi, %', 11]);                      { SIGSEGV }
    EmitCodeAbsToRdx(FpcMemErrStubAddr);
    EmitAsmX64(['mov rsi, rdx']);
    IREmitCodeCall(SigSetHookAddr);
    EmitAsmX64(['mov edi, %', 7]);                       { SIGBUS }
    EmitCodeAbsToRdx(FpcMemErrStubAddr);
    EmitAsmX64(['mov rsi, rdx']);
    IREmitCodeCall(SigSetHookAddr);
  end;
  if FpcFloatErrors then
  begin
    EmitAsmX64(['mov edi, %', 8]);                       { SIGFPE }
    EmitCodeAbsToRdx(FpcFloatErrStubAddr);
    EmitAsmX64(['mov rsi, rdx']);
    IREmitCodeCall(SigSetHookAddr);
    { Raw bytes, like IR_FPU_MASK's emitter: the text assembler has no
      stmxcsr/ldmxcsr. 50 shl 7 = $1900 = the FPC mask in MXCSR position. }
    EmitB($0F); EmitB($AE); EmitB($5C); EmitB($24); EmitB($F8);   { stmxcsr [rsp-8] }
    EmitB($8B); EmitB($44); EmitB($24); EmitB($F8);               { mov eax, [rsp-8] }
    EmitB($25); EmitB($7F); EmitB($E0); EmitB($FF); EmitB($FF);   { and eax, ~$1F80 }
    EmitB($0D); EmitB($00); EmitB($19); EmitB($00); EmitB($00);   { or eax, $1900 }
    EmitB($89); EmitB($44); EmitB($24); EmitB($F8);               { mov [rsp-8], eax }
    EmitB($0F); EmitB($AE); EmitB($54); EmitB($24); EmitB($F8);   { ldmxcsr [rsp-8] }
  end;

  { Constant global/class initializers FIRST — before any user code runs.

    They are CONSTANTS: a `const` array's contents cannot depend on anything a unit's
    initialization section does, but the reverse is emphatically not true. fpjson's
    initialization section reads a class const (`FElementSep := ElementSeps[FCompressedJSON]`)
    and, with the old order, read it while it was still all zeros — so every JSON document it
    formatted came out with no separators, no braces and no colons. Silently: the structure
    was right, the punctuation was simply absent.

    Emitting the initializers first is also just what the words mean. A constant that does not
    hold its value until after the program has started running is not a constant. }
  CompilePendingGlobalInits;

  { ...then unit initialization sections, in dependency order (a used unit is fully parsed —
    and its init proc registered — before the using unit). This is where e.g. the LCL `Forms`
    unit creates Application. }
  for i := 0 to InitProcCount - 1 do
    EmitCallProc(InitProcs[i]);

  Expect(tkBegin, 'begin');
  DbgMainBodyStart := CodeLen;   { -g: program-body code range → main subprogram }
  ParseBlock;
  DbgMainBodyEnd := CodeLen;
  { -g: snapshot the program's own global vars (skGlobal past the runtime units)
    as children of the main-body subprogram. }
  if DebugInfo then
    for i := DbgGlobalScopeBase to SymCount - 1 do
      if Syms[i].Kind = skGlobal then DbgRecordVar(-1, i, True);
  Expect(tkEnd, 'end');
  Eat(tkDot);

  { Verify all forward goto fixups were resolved }
  for i := 0 to GotoLabelCount - 1 do
    if GotoLabelCodePos[i] = -1 then
    begin
      for j := 0 to GotoFixupCount - 1 do
        if TokSlicesMatch(GotoFixupNOff[j], GotoFixupNLen[j], GotoLabelNOff[i], GotoLabelNLen[i]) then
          Error('goto target label never placed: ' +
            GetTokenStrFromRaw(GotoLabelNOff[i], GotoLabelNLen[i]));
    end;

  EmitMainBodyIntfTempRelease;
  { Falling off the end of main is FPC's `Halt(ExitCode)`: run the unit
    finalization sections in REVERSE init order, then exit with whatever
    ExitCode holds AFTER them — a finalization is allowed to change it, and
    that is the whole erroru.pp idiom.

    Routed through the Pascal PXXExitProcess (`Halt(ExitCode)`) rather than a
    raw exit-syscall emission, because "terminate with the value of a global"
    would otherwise need a new emitter in each of six backends, while
    terminating with a computed VALUE is something the AN_HALT lowering already
    does on all of them. PXXExitProcess's own Halt calls the finalization
    runner, so the explicit call here would be redundant — it stays only for
    the build that has no builtinheap, where PXXExitProcess does not exist.
    The runner's run-once guard makes whichever path arrives first the only
    one. feature-pascal-exitcode-finalization-halt }
  exitPi := FindProc('PXXExitProcess');
  if exitPi >= 0 then
    EmitCallProc(exitPi)
  else if (FiniProcCount > 0) or (FiniRunnerProc >= 0) then
    EmitCallProc(GetFiniRunnerProc);
  EmitExit(0);   { unreachable once PXXExitProcess is in — it does not return }
  EmitFinalizerRunnerBody;
  FillRootVMTSlotDefaults;
  ApplyCallFixups;
end;
