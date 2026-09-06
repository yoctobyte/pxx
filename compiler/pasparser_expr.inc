{ ===== pasparser_expr.inc — Pascal frontend: the expression parser ===========

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: Pascal's precedence chain — ParseFactorCore / ParseFactor /
  ParseTerm / ParseSimpleExpr / ParseExpr — and the constant-expression
  evaluators that ride on it (integer, REAL-valued, and the initialiser forms).

  This is the file the "duplicate the parser, share the AST" rule is ABOUT:
  Pascal binds `and`/`or` tighter than comparison and reads `in` as set
  membership, and Python does neither. Do not factor any of it into a helper
  shared with pyparser.inc/cparser.inc — a shared parser helper couples two
  specs and is then wrong in both:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

procedure ParseFactor; forward;

{ A SIZED BOOLEAN, normalised to an ordinary Boolean: `n <> 0`, typed
  tyBoolean -- or `n` untouched when it is not one.

  NORMALISE RATHER THAN GROW A SECOND PATH. ByteBool/WordBool/LongBool are
  integers of their own width carrying their booleanness in the SemId channel
  beside the kind, so anything that dispatches on the kind alone answers
  correctly about what it was handed and gets a sized boolean wrong. There are
  at least five such places -- stdout write, the Text-file writer, Str,
  `array of const` boxing, and the LOGICAL `not` lowering -- and the third was
  found only because someone fixed the first two and looked one type over.

  A per-site `or SemIsBool(...)` arm is the shape that keeps missing one, and
  it would ALSO have to teach each site how to marshal an Int16 into a
  one-byte Boolean parameter. So the value is converted ONCE, here, into
  something every one of them already handles, and none of them learns
  anything.

  `<> 0` AND NOT A TRUNCATION, which is the whole reason this is a conversion
  rather than a re-tag: a C-ABI boolean is true for ANY nonzero value, and 1 is
  not privileged. Logical `not` lowers to `xor 1`, correct for a canonical 0/1
  Boolean and wrong for `ByteBool(200)` -- $C8 xor 1 is $C9, still nonzero,
  still true. Measured 2026-09-06 by this file's own test, which caught it
  because it carries a nonzero-but-not-one row.

  Placed at the top of the expression parser rather than beside its first
  caller: pasparser_stmt.inc's four renderer sites use it too and that file is
  included later. NodeSemIdOf's body is far below and reached through the
  forward in pasparser_name.inc.
  bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time
  bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln }
function SemBoolAsBoolean(n: Integer): Integer;
var sbZero: Integer;
begin
  Result := n;
  if n < 0 then Exit;
  if not SemIsBool(NodeSemIdOf(n)) then Exit;
  sbZero := AllocNode(AN_INT_LIT);
  ASTIVal[sbZero] := 0;
  ASTTk[sbZero] := ASTTk[n];
  Result := AllocNode(AN_BINOP);
  ASTIVal[Result] := Ord(tkNeq);
  ASTLeft[Result] := n;
  ASTRight[Result] := sbZero;
  ASTTk[Result] := Ord(tyBoolean);
end;

{ Does this node produce a value whose MEANING is a truth value -- a plain
  Boolean, a tyBool8, or a sized boolean carrying its booleanness in the SemId
  channel? Asked of BOTH operands before either is normalised, so that
  `a and 3` (a type error someone made) is left alone to be diagnosed rather
  than quietly rewritten into something that compiles. }
function NodeIsBooleanMeaning(n: Integer): Boolean;
begin
  Result := False;
  if n < 0 then Exit;
  Result := (IntToTypeKind(ASTTk[n]) = tyBoolean) or
            (IntToTypeKind(ASTTk[n]) = tyBool8) or
            SemIsBool(NodeSemIdOf(n));
end;

{ Both operands of a BOOLEAN operator, normalised together when at least one of
  them is a sized boolean.

  `and`, `or` and `xor` between two truth values are LOGICAL in FPC, and a
  sized boolean reaching them as a bare integer makes them BITWISE: measured
  2026-09-06 against fpc 3.2.2 with `a := ByteBool(200); b := ByteBool(1)`,
  `a and b` answered 0 where FPC answers TRUE, and `a or b` answered -55. Both
  operands are true and their conjunction was false -- the same class of defect
  as `not`, one operator over, and invisible to any probe using only 0 and 1.

  The comparisons go the same way: `a = b` compared the raw ordinals 200 and 1
  and said FALSE where FPC compares truth values and says TRUE. That is why the
  p70 ticket's line "comparisons are unaffected" is true of the values it was
  measured with and not of the type.

  BOTH SIDES, and only when at least one is sized: normalising a pair that is
  already two plain Booleans would wrap nodes for nothing, and normalising a
  pair where the other side is an integer would paper over a type error.
  bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time }
procedure SemBoolNormalisePair(var l, r: Integer);
begin
  if not (SemIsBool(NodeSemIdOf(l)) or SemIsBool(NodeSemIdOf(r))) then Exit;
  if not (NodeIsBooleanMeaning(l) and NodeIsBooleanMeaning(r)) then Exit;
  l := SemBoolAsBoolean(l);
  r := SemBoolAsBoolean(r);
end;

{ A truth value MATERIALISED as a sized boolean of kind `tk`: `0 - (n <> 0)`,
  which is 0 for false and ALL BITS SET for true.

  This is the C-ABI convention and it is the other half of why these types are
  signed. FPC stores True as all-bits-set and reads it back through a signed
  ordinal, so `Ord(ByteBool(True))` is -1; pxx stored a plain 1 and answered 1.
  The two are NOT the same question as the signedness of the kind -- LongBool
  has been tyInteger, and therefore signed, the whole time and still answered 1,
  which is the control that separates them (frankA, 2026-09-06). A row set built
  on `True` reads as "the change did nothing" against a kind fix, and one built
  on `ByteBool(255)` reads as "sized booleans are fixed" against this one.
  Neither is right on its own and both are one plausible test file away.

  `<> 0` rather than negating the operand directly: a plain Boolean is canonical
  0/1 here and negating it would do, but this is also the funnel a nonzero
  sized-boolean value can reach, and `0 - 200` is not all-bits-set. Writing the
  cheap form would be correct today and would fail the day the caller widens.
  Constant folding removes it for a literal operand.
  bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln }
function SemBoolMaterialise(n: Integer; tk: TTypeKind): Integer;
var mbZero, mbCmp: Integer;
begin
  Result := n;
  if n < 0 then Exit;
  mbZero := AllocNode(AN_INT_LIT);
  ASTIVal[mbZero] := 0;
  ASTTk[mbZero] := ASTTk[n];
  mbCmp := AllocNode(AN_BINOP);
  ASTIVal[mbCmp] := Ord(tkNeq);
  ASTLeft[mbCmp] := n;
  ASTRight[mbCmp] := mbZero;
  ASTTk[mbCmp] := Ord(tyBoolean);
  mbZero := AllocNode(AN_INT_LIT);
  ASTIVal[mbZero] := 0;
  ASTTk[mbZero] := Ord(tk);
  Result := AllocNode(AN_BINOP);
  ASTIVal[Result] := Ord(tkMinus);
  ASTLeft[Result] := mbZero;
  ASTRight[Result] := mbCmp;
  ASTTk[Result] := Ord(tk);
end;

{ A UNARY operator overload on an aggregate operand, built as an ORDINARY CALL.

  `-a`, `not a` and `+a` where the operand is a record/class that declares
  `operator -/not/+ (const a: T): T`. Returns -1 when there is no such overload,
  and the caller then keeps its own node.

  A CALL, deliberately, and not a tagged AN_NEG/AN_NOT for ir.inc to re-resolve.
  Both spellings produce the same machine code for `b := -a`, and they differ
  everywhere else: an AN_NEG is not one of the five kinds ASTNodeIsCall names,
  so IRLowerAddress had no arm for it and `(-a).F` — a FIELD selected off the
  result — refused with `IR_UNSUPPORTED: could not lower AST node (kind 6)`,
  as did `(not a).F` with kind 7. terecs6 asserts exactly that shape.
  Growing IRLowerAddress two more kinds would have fixed those two lines and
  left every other address position (an argument, a `with`, an index base) to
  be discovered one at a time; a call is already correct in all of them.

  So the tag-then-re-resolve path is gone rather than extended: the operand's
  type is known here, the lookup is the same lookup, and doing it once in the
  parser deletes the duplicate in ir.inc instead of adding a third copy.
  devdocs/dev/normalise-dont-special-case.md
  feature-p-fpc-global-operator-overload-declarations }
function UnaryOpOverloadCall(opKind, operand: Integer): Integer;
var pi, argN, callN: Integer;
begin
  UnaryOpOverloadCall := -1;
  if (operand < 0) or (not TkIsRecordOrClass(ASTTk[operand])) then Exit;
  pi := FindOpOverloadUnary(opKind, ASTTk[operand], ResolveNodeRec(operand));
  if pi < 0 then Exit;
  argN := AllocNode(AN_ARG);
  ASTLeft[argN] := operand;
  ASTTk[argN] := ASTTk[operand];
  callN := AllocNode(AN_CALL);
  ASTIVal[callN] := pi;
  ASTLeft[callN] := argN; ASTRight[callN] := -1;
  ASTTk[callN] := Ord(Procs[pi].RetType);
  UnaryOpOverloadCall := callN;
end;

{ Is this node a Boolean LITERAL, and which one?

  Deliberately AN_BOOL_LIT only. A `const B = False` is NOT folded, for the same
  reason the C side does not fold `const int z = 0`: gcc and tcc both keep
  propagation-through-a-variable and clang prunes it, so nothing portable may
  rely on either answer, and
  decided/decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0
  puts it explicitly outside the consensus core. }
function PasBoolLit(n: Integer; var v: Boolean): Boolean;
begin
  PasBoolLit := False;
  { -OO emits what the source says, so every fold in this file switches off
    HERE rather than at each call site: this helper is the single question they
    all ask, and a gate at the choke point cannot be forgotten by the next fold
    someone adds. }
  if SourceOneToOne then Exit;
  if (n < 0) or (n >= ASTNodeCount) then Exit;
  if ASTKind[n] <> AN_BOOL_LIT then Exit;
  v := ASTIVal[n] <> 0;
  PasBoolLit := True;
end;

{ The folded result of a logical operator, as a literal the NEXT fold can read.
  Returning a literal rather than the surviving operand is what makes a CHAIN
  collapse: `(False or False) or (not True)` is left-associative, so the first
  `or` hands its result to the second AS AN OPERAND, and an unfolded binop there
  stops the chain one step in. }
function PasMakeBoolLit(b: Boolean): Integer;
begin
  Result := AllocNode(AN_BOOL_LIT);
  if b then ASTIVal[Result] := 1 else ASTIVal[Result] := 0;
  ASTTk[Result] := Ord(tyBoolean);
end;


{ The real factor parser. ParseFactor below wraps it to apply NilPy's str-method
  suffix uniformly — this body has 67 Exit points, so a suffix loop written at
  its tail would silently miss most of them (it missed str(t).upper(), the exact
  uforth shape). }
{ How many bytes of THIS local's frame slot the zero-init contract must cover,
  0 when it holds nothing managed. Split out of the loop below so the "which
  kinds are managed, and how far do they reach" table has exactly ONE owner: the
  late-temp pass in ir_codegen.inc (hidden locals minted DURING a body's parse,
  after this prologue pass has already run) needs the same answer and must not
  grow a second copy of it — the copies are what let the for-in container temp
  fall through every arm at once
  (bug-a-a-for-in-container-temp-is-not-zero-initialised). }
function ManagedLocalZeroBytes(i: Integer): Integer;
var zeroBytes, elemCount: Integer;
begin
  { ASK IsArray ONCE. Every arm below answers PER ELEMENT and the count is
    applied at the end, because nine arms each remembering to multiply is how
    three of them shipped without it -- interfaces, then Variants, then promo
    ints, each found from the outside as a use-after-free far from its cause.
    A new arm that supplies only a per-element size is now correct for arrays
    by construction rather than by remembering; that is the point
    (devdocs/dev/normalise-dont-special-case.md -- the second path is the one
    that stays broken, and here there were nine).

    The two HANDLE-level shapes come FIRST and are deliberately NOT
    per-element: those slots hold a pointer, not a payload, so they answer in
    full and keep elemCount at 1. Everything after them is per-element. }
  zeroBytes := 0;
  elemCount := 1;
  if Syms[i].IsArray and (Syms[i].ArrLen <> -1) and (SymElemDynDepth[i] > 0) then
    { Fixed array whose elements are dynamic-array HANDLES (`array[..] of TA`):
      nil every pointer-sized slot so SetLength on an element does not release
      a garbage "old" handle. Answers in full — the count is the array's, but
      the size is a pointer, not the element type's. }
    zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE
  else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
    zeroBytes := TARGET_PTR_SIZE                          { dyn-array handle }
  else
  begin
    { From here every arm answers PER ELEMENT. count = elements in a STATIC
      array, else 1; applied once, at the bottom. }
    if Syms[i].IsArray and (Syms[i].ArrLen <> -1) then elemCount := Syms[i].ArrLen;

    if Syms[i].TypeKind = tyAnsiString then
    zeroBytes := TARGET_PTR_SIZE
  else if Syms[i].TypeKind = tyVariant then
  begin
    { STATIC ARRAY of Variant -- `av: array[0..3] of Variant`. Exactly the
      AnsiString arm above, one indirection out, and it was missing: the arm
      zeroed ONE element's worth (16 bytes) for an array of any length, so
      av[0] started empty and av[1..] held stack garbage. A Variant's first
      word is its TAG, and the very first `av[i] := x` RELEASES the old
      contents -- so whenever the frame garbage under av[1..] happened to
      carry a tag the release path recognises, that store decremented a
      refcount through a payload the slot never owned.

      Measured in pylib's PyBoundPairCallKwBody, whose `av: array[0..3] of
      Variant` is exactly this shape: `for i := nPos to 3 do av[i] := pynone`
      ran `decq -0x10(%rax)` with rax pointing 40 bytes into an unrelated
      bound-pair record, decrementing that record's Sig field by one. The pair
      then read its signature one byte early and refused a legal two-argument
      call as "missing 510 required positional argument(s)".

      Same shape and the same red herring as
      bug-a-a-local-array-of-interfaces-is-not-zero-initialised: it is
      invisible on a clean stack, so it appears and disappears when an
      unrelated routine changes the frame in front of it -- which is why it
      surfaced as a NilPy regression with no NilPy change behind it.
      regression-test-nilpy-test-nilpy-star-operand-in-a-variant }
    zeroBytes := TypeSlotSize(tyVariant);
  end
  { RecordNeedsZeroInit, not RecordHasManagedFields: an interface FIELD is
    excluded from the finalization predicate on purpose (releasing it under
    the record heap lock deadlocks), but it still has to START NIL — nilling
    a stack slot takes no lock. Sharing one predicate between the two
    questions meant a record whose only refcounted member was an interface
    was never zeroed, so `r.f := x` released stack garbage and dispatched
    _Release through a junk IMT. The documented trade was a benign LEAK; what
    it actually produced was a use-after-free.
    bug-a-a-record-with-an-interface-field-is-not-zero-initialised }
  else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
          RecordNeedsZeroInit(Syms[i].RecName) then
    zeroBytes := RecSize(Syms[i].RecName)
  else if (Syms[i].TypeKind = tyRecord) and Syms[i].IsArray and
          RecordNeedsZeroInit(Syms[i].ElemRecName) then
    { The record arms keep their own IsArray test, and must: they differ in
      WHICH rec id they read (RecName vs ElemRecName), not merely in count --
      and each falls THROUGH to the COM arms when RecordNeedsZeroInit says no,
      which a merged arm would swallow. }
    zeroBytes := RecSize(Syms[i].ElemRecName)
  else if SymIsComInterface(i) then
    { COM/ARC interface fat pointer: must start nil so the ARC release at
      first overwrite / scope exit sees an empty slot, not stale stack bytes
      (a garbage IMT would dispatch _Release into nowhere). }
    zeroBytes := RecSize(Syms[i].RecName)
  else if SymElemIsComInterface(i) then
    { STATIC ARRAY of COM interfaces — `keep: array[0..N] of IFoo`. Exactly
      the arm above, one indirection out, and it did not exist: every
      managed-local pass keys on SymIsComInterface, which answers False for
      an array on purpose, and the managed-RECORD-array arm above does not
      claim it either (an interface UCls has no managed FIELDS). So the slots
      held stack garbage and the very first `keep[i] := x` ran the ARC
      release on that garbage, dispatching _Release through a junk IMT.

      It presented as `uses sysutils` causing a segfault -- add the unit and
      an otherwise identical program crashes -- which is a pure red herring:
      the unit's initialisation merely DIRTIES the stack the routine is about
      to use. With a hand-written stack-dirtying routine the same crash
      reproduces with no sysutils at all, and with a clean stack the bug is
      invisible because the garbage happens to be zero. A constant index and
      a global array both "worked" for the same accidental reason.
      bug-a-a-local-array-of-interfaces-is-not-zero-initialised }
    zeroBytes := RecSize(SymTR[i].ElemRec)
  else if (Syms[i].TypeKind = tyClass) and NilPyUserCode then
    { NilPy-user class local: refcounted binding — must start nil so the
      rebind release and the scope-exit release see an empty slot
      (feature-nilpy-object-reclamation slice 4). }
    zeroBytes := TARGET_PTR_SIZE
  else if TypeIsPromoInt(Syms[i].TypeKind) then
    { Promotable int: a {tag, payload} pair whose tag MUST start
      PROMO_TAG_INLINE (0). The scope-exit cleanup calls PXXPromoClear on
      every promo local unconditionally (EmitManagedLocalCleanup), and that
      routine RELEASES the payload as a managed string whenever the tag
      reads PROMO_TAG_HEAP (1) — so a local left unwritten on the executed
      path was cleared with stale stack bytes, and bytes that happened to
      read {1, <a live pointer>} freed a block nobody had freed.

      PXXPromoClear's own header says it cannot be used on uninitialised
      memory; the temps satisfy that through SymIsHiddenArgTemp's prologue
      zero, and named locals had NOTHING. Cleanup without init: this list
      is where the init half belongs, beside every other managed kind.

      Found via uforth: `w_repeat` returns early, leaving a promo local
      untouched, and the frame garbage under it read as a heap-tier slot
      pointing at a live bound-fn object. Freeing it put a live block on the
      free bin, PXXAlloc handed it out again for a string, and the next
      `word.native(vm)` through that object jumped into the string data —
      three layers and thousands of lines from the cause, with the object
      still refcount-alive the whole time.
      bug-nilpy-write-after-free-on-a-callable-held-in-a-dataclass-field

      ...and the ARRAY shape, which this arm refused with `not IsArray` — the
      THIRD arm of this chain to ship without asking. `promoint64` is a
      spellable Pascal type name (pasparser_decl.inc:543), so
      `a: array[0..3] of promoint64` is an ordinary Pascal local and the guard
      was an omission, not the deliberate decision it was left as. It zeroed
      NOTHING for the whole array — not one element's worth, as the Variant arm
      had — while EmitManagedLocalCleanup's promo arm, which has the same
      missing IsArray, still called PXXPromoClear on the slot address at scope
      exit. So element 0 was cleared from stack garbage, and PXXPromoClear
      releases the payload as a managed string whenever the tag reads
      PROMO_TAG_HEAP: a frame carrying {1, <pointer-shaped bytes>} freed a
      block the slot never owned. test_promoint_local_array_zero_init
      segfaults on the pre-fix compiler.
      bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice }
    zeroBytes := TypeSlotSize(Syms[i].TypeKind);

  end;

  { Apply the count ONCE, here, for every per-element arm above. }
  zeroBytes := elemCount * zeroBytes;

  { PXXDBG a.mlzero -- the chain above is nine independent arms, each of which
    has to remember to ask IsArray for itself, and two have already SHIPPED
    without it (interfaces, then Variants). Both were found from the outside,
    as a use-after-free three layers from the cause, because a missed zero is
    invisible on a clean stack. This channel makes the table answer for itself
    instead: every local the chain looked at, what it decided, and -- the line
    that matters -- MISS, for a local of a kind the chain HANDLES that still
    came out zeroBytes=0. A third omission is one grep of this output away
    rather than one memory-corruption report away.
    bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice }
  if PxxDbgEnabled('a.mlzero') then
  begin
    if (zeroBytes = 0) and
       ((Syms[i].TypeKind = tyAnsiString) or (Syms[i].TypeKind = tyVariant) or
        (Syms[i].TypeKind = tyClass) or TypeIsPromoInt(Syms[i].TypeKind) or
        SymIsComInterface(i) or SymElemIsComInterface(i) or
        ((Syms[i].TypeKind = tyRecord) and Syms[i].IsArray) or
        ((Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray)) then
    begin
      Write('PXXDBG a.mlzero MISS sym=', Syms[i].Name, ' tk=', Ord(Syms[i].TypeKind));
      if Syms[i].IsArray then Write(' ARRAY len=', Syms[i].ArrLen)
      else Write(' scalar');
      if TypeIsPromoInt(Syms[i].TypeKind) then Write(' promoint');
      if Syms[i].TypeKind = tyClass then Write(' class nilpyuser=', NilPyUserCode);
      if (Syms[i].TypeKind = tyRecord) then
        Write(' recname=', Syms[i].RecName, ' elemrec=', Syms[i].ElemRecName);
      WriteLn(' -> zeroBytes=0');
    end
    else
      WriteLn('PXXDBG a.mlzero sym=', Syms[i].Name, ' tk=', Ord(Syms[i].TypeKind),
              ' isarray=', Syms[i].IsArray, ' arrlen=', Syms[i].ArrLen,
              ' -> ', zeroBytes);
  end;
  ManagedLocalZeroBytes := zeroBytes;
end;

{ Zero every managed local in [fromSym, SymCount) — see the zero-init contract
  above EmitZeroFrameSlot. Extracted from the Pascal routine-body path so the
  NilPy def/method paths get the SAME guarantee: they build their locals through
  their own pre-pass and never ran this loop, which was invisible while an
  inferred NilPy string local was a FROZEN string (nothing to release) and
  became a release of stale stack bytes the moment those locals turned managed
  (bug-nilpy-string-local-truncates-at-255).

  Managed locals (dynamic arrays, AnsiStrings, and records/arrays containing
  them) hold managed pointer slots. Zero their full extent before the body so a
  first SetLength / assignment sees nil rather than stale stack bytes — and so an
  ARC-correct whole-record copy can safely release the (nil) old fields. }
procedure EmitManagedLocalsZeroInit(fromSym: Integer);
var i: Integer;
begin
  for i := fromSym to SymCount - 1 do
    if Syms[i].Kind = skLocal then
      { One owner for the guarantee, every target, every size. }
      EmitZeroFrameSlot(Syms[i].Offset, ManagedLocalZeroBytes(i));
end;

function PyMakeUnsupportedOperand: Integer;
{ An AN_CALL to pylib's PyUnsupportedOperandError: a genuine RUNTIME TypeError
  where these sites previously called the compiler's Error() and aborted the
  build. CPython raises at run time, so `try: a + b / except TypeError:` — the
  normal way to probe for operator support — must COMPILE and run its handler.
  Same shape the __contains__ / ordering / bitwise misses already use.
  bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising. }
var pi, node: Integer;
begin
  pi := FindProc('PyUnsupportedOperandError');
  if pi < 0 then Error('Nil Python: pylib (PyUnsupportedOperandError) not loaded');
  node := AllocNode(AN_CALL);
  ASTIVal[node] := pi;
  ASTTk[node] := Ord(tyBoolean);
  ASTLeft[node] := -1;
  PyMakeUnsupportedOperand := node;
end;

function PyReflName(op: TTokenKind): AnsiString;
{ The reflected dunder for a binary operator: `a <op> b` falls back to
  `b.__r<op>__(a)`. One table so the two call sites (ParseSimpleExpr for +/-,
  ParseTerm for * / // %) cannot drift. }
begin
  case op of
    tkPlus:  PyReflName := '__radd__';
    tkMinus: PyReflName := '__rsub__';
    tkStar:  PyReflName := '__rmul__';
    tkSlash: PyReflName := '__rtruediv__';
    tkDiv:   PyReflName := '__rfloordiv__';
    tkMod:   PyReflName := '__rmod__';
    tkAt:    PyReflName := '__rmatmul__';
    else     PyReflName := '';
  end;
end;

function PyReflectedDunder(const rname: AnsiString; left, right: Integer): Integer;
{ Python's REFLECTED fallback: when the LEFT operand does not implement the
  operator, the RIGHT operand's `__r<op>__` is tried with the operands swapped
  (`3 + C(4)` -> `C(4).__radd__(3)`). Returns -1 when the right operand is not a
  user class declaring that method, so the caller keeps its existing path.

  Measured absent before this: all seven reflected forms fell through to the
  numeric typing and computed on the class HANDLE — `3 + C(4)` gave 1744830491,
  `3 * C(4)` gave -1906311096, silently
  (feature-nilpy-arithmetic-dunders-full-protocol). The two comments in this
  file that said the fallback "is not implemented" were the only trace of it;
  there was no partially-wired path.

  The RIGHT operand becomes the receiver and the LEFT becomes the argument —
  that swap is the whole point, and getting it backwards yields a plausible
  wrong answer rather than an error. }
var ci: Integer;
begin
  PyReflectedDunder := -1;
  if not PyExprMode then Exit;
  if IntToTypeKind(ASTTk[right]) <> tyClass then Exit;
  if ResolveNodeRec(right) < REC_UCLASS_BASE then Exit;
  if PyRecIsPylibOwnClass(ResolveNodeRec(right)) then Exit;
  ci := ResolveNodeRec(right) - REC_UCLASS_BASE;
  if FindUMeth(ci, rname) < 0 then Exit;
  PyReflectedDunder := PyCallMeth1(ci, rname, right, left);
end;

{ May this argument be duplicated for a by-value OPEN ARRAY parameter?

  Two source shapes carry a length header at [data-8] and so can be copied: a
  DYNAMIC ARRAY, and an OPEN-ARRAY PARAMETER being forwarded onward. The second
  is not optional — `procedure Outer(x: array of Integer); begin Inner(x)`
  must give Inner its own copy too, and leaving it out left the inner write
  visible to Outer (measured against FPC, which answers the caller's original
  value).

  Elements must own nothing: AN_DYN_COPY moves bytes, so a managed or nested
  element would be duplicated WITHOUT a retain and released twice. The Copy
  intrinsic refuses nesting for the same reason; the managed case is added here
  because this copy is emitted implicitly rather than asked for, so a crash
  would arrive unannounced. Those element types keep the old aliasing behaviour
  until AN_DYN_COPY learns element-aware retain
  (feature-dynarray-copy-nested-element-type). }
function OpenArrayCopyEligible(node: Integer): Boolean;
var si: Integer; et: TTypeKind; isDyn, isOpenParam: Boolean;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] <> AN_IDENT then Exit;   { a bare name is the censused shape }
  si := ASTIVal[node];
  if (si < 0) or (si >= SymCount) then Exit;
  if not Syms[si].IsArray then Exit;
  if SymElemDynDepth[si] > 0 then Exit;     { nested — AN_DYN_COPY refuses it too }
  isDyn := (Syms[si].ArrLen = -1) and (SymDynDepth[si] = 1);
  { an OPEN-ARRAY parameter: AllocParam stamps the ArrLen = 1000 "length
    unknown" placeholder and leaves the dyn depth at 0, which is exactly what
    distinguishes it from a named dynamic-array param (depth >= 1) and from a
    named FIXED array param (a real ArrLen) }
  isOpenParam := (Syms[si].Kind = skParam) and (SymDynDepth[si] = 0) and
                 (Syms[si].ArrLen = 1000);
  if not (isDyn or isOpenParam) then Exit;
  et := Syms[si].ElemType;
  Result := (et = tyInteger) or (et = tyBoolean) or (et = tyChar) or
            (et = tyInt8) or (et = tyUInt8) or (et = tyInt16) or (et = tyUInt16) or
            (et = tyInt32) or (et = tyUInt32) or (et = tyInt64) or (et = tyUInt64) or
            (et = tyNativeInt) or (et = tyNativeUInt) or (et = tyPointer) or
            (et = tySingle) or (et = tyDouble);
end;

{ `Copy(node)` — the whole-array duplicate, built as the very node the Copy
  intrinsic builds (source, index 0, count MaxInt). }
function MakeWholeDynCopy(node: Integer): Integer;
var idxN, cntN, argA, argB: Integer;
begin
  idxN := AllocNode(AN_INT_LIT);
  ASTIVal[idxN] := 0; ASTTk[idxN] := Ord(tyInteger);
  cntN := AllocNode(AN_INT_LIT);
  ASTIVal[cntN] := 2147483647; ASTTk[cntN] := Ord(tyInteger);
  Result := AllocNode(AN_DYN_COPY);
  ASTLeft[Result] := node;
  argA := AllocNode(AN_ARG); ASTLeft[argA] := idxN;
  argB := AllocNode(AN_ARG); ASTLeft[argB] := cntN;
  ASTRight[argA] := argB;
  ASTRight[Result] := argA;
  ASTTk[Result] := Ord(tyPointer);
end;

{ `a + b` / `Concat(a, b, ...)` over dynamic arrays. ONE construction, used by
  BOTH spellings — the ticket asked for that explicitly and
  normalise-dont-special-case says why: the second entry point is the one that
  stays broken.

  Concat IS the array-SPLICE Insert with the insertion point pinned past the
  end. PXXDynInsArrFill clamps its index to [0..len], so a MaxInt index means
  "append", and AN_DYN_INSERT's whole fresh-buffer + managed-element-retain
  machinery serves unchanged — no second lowering, no second ARC story.

  The index is a CONSTANT and not a `Length(a)` node on purpose: a Length node
  would re-evaluate the left operand, so `Concat(F(), G())` would call F twice.
  MakeWholeDynCopy above pins its count the same way, for the same reason. }
function DynConcatOperandsEligible(left, right: Integer): Boolean;
{ May `left + right` (or `Concat(left, right)`) be a dynamic-array concatenation?

  A NAMED PREDICATE AND NOT AN INLINE TEST, because there are three doors into
  MakeDynConcat -- the `+` operator, the Concat intrinsic, and Concat's
  multi-argument fold -- and a gate written three times is three gates. The one
  that already differed is why this exists: the operator door tested
  `NodeDynDepth(both) > 0`, so an ELEMENT LIST on one side never reached the
  retag inside MakeDynConcat at all and got the generic
  "arithmetic operator not supported for dynamic arrays" from a check two
  thousand lines away that is correct about ordinary arithmetic.

  An element list is eligible only OPPOSITE a real dynamic array, because the
  array is what names the element type. `[1] + [2]` is not eligible and gets the
  ordinary refusal -- neither side knows what it holds, and guessing Integer
  would be a wrong answer wearing a working program. }
begin
  Result := False;
  if (left < 0) or (right < 0) then Exit;
  if (NodeDynDepth(left) >= 1) and (NodeDynDepth(right) >= 1) then
  begin Result := True; Exit; end;
  if (NodeDynDepth(left) >= 1) and (ASTKind[right] = AN_SET_LIT) and
     SetLitElemsArePlain(right) then
  begin Result := True; Exit; end;
  if (NodeDynDepth(right) >= 1) and (ASTKind[left] = AN_SET_LIT) and
     SetLitElemsArePlain(left) then
    Result := True;
end;

procedure RefuseUntypedElementListConcat(left, right: Integer);
{ `Concat([1, 2, 3], [6, 8, 10])` -- BOTH operands element lists, so nothing in
  the expression names an element type. fpc takes it from the ASSIGNMENT's
  destination; the expression parser has no channel carrying that, and inventing
  one is a design change rather than a gate widening.

  MEASURED 2026-09-06, AND PRE-EXISTING: this compiled clean and answered
  `len=4310464 a0=1358 a3=0` where fpc says `len=6 a0=1 a3=6` -- verified against
  the pre-change compiler by stashing, so the widening below did not introduce
  it and does not fix it. A silent wrong length out of a call that looks like it
  worked is the expensive shape, and it was sitting directly beside the case
  this change DOES fix (`Concat(a, [x])`, either order), which is exactly how a
  half-landed feature certifies its own broken half.

  So it is refused by name and the refusal says what would be needed.
  fpc-testsuite tarray14. }
begin
  if (left < 0) or (right < 0) then Exit;
  if (ASTKind[left] = AN_SET_LIT) and (ASTKind[right] = AN_SET_LIT) and
     (NodeDynDepth(left) = 0) and (NodeDynDepth(right) = 0) then
    Error('array concatenation: neither operand is a dynamic array, so nothing '
        + 'names the element type -- give one operand a typed array variable, '
        + 'or assign the lists first');
end;

function MakeDynConcat(left, right: Integer): Integer;
var argA, argB, idxN: Integer;
begin
  { `a + [4]` and `[0] + a` -- AN ELEMENT LIST AS ONE OPERAND. It arrives as an
    AN_SET_LIT, because `[...]` is a set until something says otherwise, and the
    something is normally the ASSIGNMENT's left-hand side. Here there is no
    assignment to ask: `CheckArray(a, [1, 2, 3, 4])` passes one as an ARGUMENT
    and `a += [5]` has the array on the other side of the operator.

    So the SIBLING OPERAND names the element type, exactly as the destination
    does in an assignment and as the type name does in `TDynArr.Create(...)`.
    Same retag, third caller, no fourth answer to "what is a dynamic-array
    literal" -- which is the whole reason RetagSetLitAsArrayCtor is one routine
    reached through a forward rather than a thing each door does for itself.

    Only ONE side is retagged: `[1] + [2]` has no operand that knows an element
    type and still gets the ordinary "both operands must be dynamic arrays",
    which is the honest answer rather than a guess at Integer.
    fpc-testsuite tarray17 }
  if (ASTKind[left] = AN_SET_LIT) and (NodeDynDepth(right) >= 1) and
     SetLitElemsArePlain(left) then
    RetagSetLitAsArrayCtor(left, NodeDynBaseTk(right), NodeDynDepth(right));
  if (ASTKind[right] = AN_SET_LIT) and (NodeDynDepth(left) >= 1) and
     SetLitElemsArePlain(right) then
    RetagSetLitAsArrayCtor(right, NodeDynBaseTk(left), NodeDynDepth(left));
  if (NodeDynDepth(left) < 1) or (NodeDynDepth(right) < 1) then
    Error('array concatenation: both operands must be dynamic arrays');
  if NodeDynDepth(left) <> NodeDynDepth(right) then
    Error('array concatenation: the operands'' nesting differs');
  if (NodeDynBaseTk(left) <> NodeDynBaseTk(right)) or
     ((NodeDynBaseTk(left) = tyRecord) and
      (NodeDynBaseRec(left) <> NodeDynBaseRec(right))) then
    Error('array concatenation: the operands'' element types differ');
  { Frozen-string elements are refused by dynamic-array Insert for the same
    reason (the element width is the declared capacity, not TypeSlotSize), and a
    silent wrong stride is exactly what this ticket's diagnostic replaced. }
  if NodeDynBaseTk(left) = tyString then
    Error('array concatenation: frozen-string element type not yet supported');
  if FindProc('PXXDynInsArrFill') < 0 then
    Error('array concatenation: helper unavailable (needs the builtin unit; not on ESP)');
  idxN := AllocNode(AN_INT_LIT);
  ASTIVal[idxN] := 2147483647; ASTTk[idxN] := Ord(tyInteger);
  Result := AllocNode(AN_DYN_INSERT);
  ASTIVal[Result] := 1;                     { the array-splice form }
  ASTLeft[Result] := left;
  argA := AllocNode(AN_ARG); ASTLeft[argA] := right;    { spliced-in array }
  argB := AllocNode(AN_ARG); ASTLeft[argB] := idxN;     { index = append }
  ASTRight[argA] := argB;
  ASTRight[Result] := argA;
  ASTTk[Result] := Ord(tyPointer);
end;

function TryFoldBracketCtorLen(var n: Integer): Boolean;
{ `[e1, ..., en]` as the operand of Low / High / Length is an open-array
  CONSTRUCTOR, not a set — that is FPC's reading — and the answer is a
  compile-time COUNT whatever the elements are: Length = n, Low = 0,
  High = n - 1. Measured against fpc 3.2.2 for `[]`, char elements, string
  elements and non-constant elements; the count is the whole rule.

  pxx read the brackets as a SET and then took Length of the bitmask, so
  `Length([1,2])` answered 6 (bits 1 and 2 set), `Length([5,9])` answered 544,
  `Length(['a','b'])` answered 0 (bits 97 and 98, past the low word) — and
  Low/High refused the operand outright with `expected array variable or
  ordinal type`. A silently wrong count is the expensive kind of wrong, and this
  one looked plausible for small sets: `Length([1])` answered 2.

  Consumes the bracket list, and returns False having consumed NOTHING when the
  operand does not start with `[`. The element expressions are parsed for their
  TOKENS and the nodes discarded: the result is a constant, so nothing in them
  is evaluated — which is what FPC does too. }
begin
  TryFoldBracketCtorLen := False;
  if CurTok.Kind <> tkLBrack then Exit;
  Next;
  n := 0;
  if CurTok.Kind <> tkRBrack then
  begin
    ParseExpr;
    n := 1;
    while Eat(tkComma) do
    begin
      ParseExpr;
      Inc(n);
    end;
  end;
  Expect(tkRBrack, ']');
  TryFoldBracketCtorLen := True;
end;

procedure FoldBracketCtorBound(n: Integer);
{ The shared tail of the three arms: hand back `n` as a plain Integer constant. }
begin
  Expect(tkRParen, ')');
  CurASTNode := AllocNode(AN_INT_LIT);
  ASTIVal[CurASTNode] := n;
  ASTTk[CurASTNode] := Ord(tyInteger);
  LastExprTk := tyInteger;
end;

procedure ParseFactorCore;
var negConstVal: Int64;   { value of a negated CONSTANT — types the AN_NEG node }
    fcNode: Integer;     { FloatCastToTemp's result — a float cast is a conversion through a hidden temp, at all three doors }
    eoNode: Integer;     { TryExplicitOpCast's result — an `operator Explicit` on a record/class operand, at both name doors }
    aliasEtid: Integer;  { the enum identity of an alias cast target — from the alias table's column, never from the kind }
    lenSavedHoist, lenTrialHoist: Integer;   { the len() intercept's parked hoist queue }
    rndRawArg: Integer;      { round(x, n): the argument node before the float unbox }
    bcN: Integer;            { element count of a `[..]` open-array constructor operand }
    copyElemRec: Integer;    { element rec of a dynamic-array Copy's source, for a `[i]` suffix }
    mrefNode: Integer;       { a `@`-less method reference inside a method-pointer cast, or -1 }
    ptrCastElemTk: TTypeKind;   { element of a PChar/PWideChar cast — what `p^` and `p[i]` yield }
    castSem: Integer;    { the SEMANTIC IDENTITY a named-type cast confers — an enum's type index for `TEnum(x)`, a sized boolean's for `ByteBool(x)`, else SEM_NONE. See the cast arm }
    intBaseArg, atRecv, atFld, atDflt, atProp: Integer; trialProcMark, trialLamMark, trialSymMark, trialFrameMark: Integer; atIsGet, atExists: Boolean; atName: AnsiString; name, grpAcc: AnsiString; recName: Integer; idx, procIdx, i, node, left, prevTok, valNode: Integer; tk: TTypeKind; op, argSeq, argSeq2, argSeq3, lastArg, argIdx, exprNode, szArg: Integer;
    smmiS, smSelfNode, mselfArg, mcCtorCi, parenRec, ctorCi, ctorArgN: Integer;
    ctorSig, ctorBrk: Integer;   { WHICH ctor wants an array at this slot, and the shared door's answer }
    supPi: Integer;   { __pxxGetInterface, for the three-argument Supports }
    { rcDelegated LEFT THIS BLOCK with the record-name cast's own suffix loop:
      ParseCastPostfixSuffix carries the equivalent bit (pcMovedOff) as its own
      local, because it is state of the WALK and never of the factor parser.
      refactor-p-three-hand-rolled-postfix-loops }
    pcMovedOff: Boolean;    { the pointer-alias cast walk has left the CAST -- see its loop }
    derefRem, derefBaseTk, derefBaseRec: Integer;   { `(x)^` pointer shape, from ResolveDerefShape }
    dpeTk, dpeRec, dpeCap: Integer;   { `p^[i]` element shape, from DerefPtrArrayElem }
    ndFlat: Integer;   { flattened N-D subscript tail from ParseNDSubscriptTail, or -1 }
    ndIsND: Boolean;   { …and whether the base was N-D at all, for the partial-row case }
    lenSi: Integer;   { Length(v) — the SYMBOL, when the operand is a bare identifier }
    nestCtorCi: Integer;   { `TOuter.TInner.Create` — the nested class, resolved by scope }
    nestScanCi, nestScanPos, nestDepth, nestI: Integer;   { …walking N levels of it }
    mthName: AnsiString;   { @TClass.Method — name read via GetTokenStr (may be a type keyword) }
    mcCtorNm: AnsiString;
    nArgs, argsHead, currArg: Integer; argTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    kwIdx, slotIdx: Integer;   { NilPy keyword argument: binding+1, and the param it fills }
    ci, mmi, mpi, mcallNode, mlastArg, smSelfIdx, smselfArg: Integer;
    aliasIdx, fieldNode, indexNode, baseNode, baseRec, fIdx, mci, margSeq, margIdx, mexprNode, mai, pri, qUnit: Integer;
    fieldName, methName: AnsiString; isAssign: Boolean; castTk: TTypeKind;
    liftedVar, identNode, addrNode: Integer;
    rcCi, rcMmi, rcPi, rcTmp, rcSelf, rcSelfArg, savedRecId: Integer;   { advanced-record ctor call }
    castTk2: TTypeKind;   { postfix tail on a record-factory result }
    helperPi, sci: Integer;
    isLiftedCall: Boolean;
    bitNot: Boolean; notOrdTk: TTypeKind; notConstV: Int64;
    notBlv: Boolean;              { `not` over a Boolean LITERAL — folded, see the site }
    unOvl: Integer;   { unary operator overload on a record/class operand }
    szAi, szFlatLen, szDi, szBrDepth, szNIdx, szBase, szRec, szQUnit: Integer;
    szNestCi, szHops, szI: Integer; szNestName: AnsiString;   { SizeOf(TOuter.TInner) — the SCOPED nested row }
    szScan, szBd, szExprNode: Integer;
    szFldRec: Integer; szFldName: AnsiString;   { SizeOf(<expr>.field) — the OWNER's record and the field name }
    szLitNeg: Boolean;   { SizeOf(-1) — the sign is its own token and changes the width }
    szIsExpr: Boolean;
    szExprTk: TTypeKind;
    hlBoundV: Int64;
    hlBoundTk: TTypeKind;
    hlBoundEid: Integer;   { TryOrdinalVarBound's enum identity; -1 = not an enum }
    hlValTk: TTypeKind; hlCap: Integer;          { High/Low over a STRING operand }
    hlIsFrozen, hlIsAnsi, hlIsArrOp: Boolean;
    dpaCount, dpaLo, dpaFlat: Integer;   { `p^` over a pointer-to-fixed-array: first-dim span, low bound, and total element count }
    frRowLen, frRowLo: Integer;          { `d[i]` over a dyn array of fixed rows: the row's extent and low bound }
    dynCtorAi: Integer;                  { `TDynArr.Create(...)`: the ArrType row the type NAME resolved to -- the element type is read from there and not from a destination, because the node may never have one }
    mcCi: Integer; mcFin: Boolean;   { metaclass receiver at the end of a cast-deref chain }
 szElemTk: TTypeKind; szBTk: TTypeKind; szBTkAny: TTypeKind;
 szDeclTk: TTypeKind; szNameConsumed: Boolean;
    seEtid, seOrd: Integer;
    dfSym, dfRec, dfAi: Integer; dfTk: TTypeKind; dfSaveStatic: Boolean;  { Default(T) over an aggregate }
    dfNestCi, dfHops, dfI: Integer; dfNestName: AnsiString;   { Default(TOuter.TInner) — the SCOPED nested row }
    lenFieldRec, lenFieldIdx: Integer;   { Length() of a static-array record field }
    cpyPi: Integer;   { Copy(s,i,n)[k]: the __pxxStrCopy proc index, kept past ci's reuse }
    ccReg, ccNode: Integer; ccKey: AnsiString; ccTk: TTypeKind;   { bare class-const in a method body }
    mapProc, mapConv: Integer; mapKind: AnsiString;   { NilPy map(<type>, xs) }
    rndArg: Integer;   { first operand of NilPy round(x, n) }
    rndIntArg: Boolean;      { …and was it an INTEGER? then round is identity }
    rndArgTk, rndRawTk: TTypeKind;   { its type, to restore after the identity }
    fwdList, fwdDict: Integer;   { `f(*args, **kwargs)` forwarded into fixed parameters }
    vcNode: Integer;   { a typecast of a VARIANT, rewritten as the conversion }
    strAliasCast: Boolean;   { the C4 cast names a STRING alias -- a value no-op, but its postfix tail is still the shared suffix loop }
    strAliasOpTk: TTypeKind; { ...and the OPERAND's kind, which is what decides no-op vs reinterpret }
    strAliasIdx: Boolean;    { ...and it is FOLLOWED BY `[`, so the tail is the shared suffix loop rather than an Exit }
    tiName: AnsiString; tiTk: TTypeKind;   { widened TypeInfo(T): scalar/string/class/record }
    tiAlias: Integer;   { …and the alias-table row when it is a NAMED structural type }
    tiArr: Integer;     { …and the ArrType row when it is a NAMED array type }
    elemTk: TTypeKind; elemRec: Integer;   { pointee of the node a `^` is applied to }
    pyLateDefPi: Integer;   { NilPy def not yet bound at this call site; -1 = none }
    arrCast: Boolean;       { this named-type cast targets an ARRAY type: take the
                              operand's address and deref, so it reinterprets storage }
    acAddr, acDeref: Integer;
begin
  { NilPy runs its own copy of this routine (pyparser.inc). The dispatch is
    here rather than at the call sites so that every caller — and every
    recursive re-entry through the expression layers — stays untouched. }
  if PyExprMode then
  begin
    PyParseFactorCore;
    Exit;
  end;
  LastExprTk := tyInteger;
  { An unqualified `Read`/`Write`/`Readln`/`Writeln` that names a METHOD of the
    enclosing class is an ORDINARY IDENTIFIER here, not the console intrinsic:
    `if Read(Buffer,Count) < Count` inside TStream.ReadBuffer is the shape, and
    it is FPC's and Delphi's own RTL. The four names lex as keyword tokens, so
    the case below has no arm for them and every such expression died on
    `expected expression`.

    NORMALISED RATHER THAN GIVEN A FOURTH ARM. The tkIdent arm below already
    resolves an implicit-Self method call, with the overload and arity questions
    asked correctly -- pasparser_stmt.inc's own copy carries a comment about
    being the arm that did NOT ask them and stayed broken for it. So the token is
    rewritten to tkIdent and falls into that arm, rather than a fresh copy of it
    landing here to drift the same way.

    The rewrite is applied to the TOKEN STREAM as well as to CurTok, because the
    tkIdent arm hands `TokPos - 2` back to ParseLValueAST, which re-reads
    Tokens[] and would otherwise see the keyword again. That is durable and it
    is correct to be: the decision is about a member of the class whose method
    body encloses this token, so a re-parse of the same position (a generic
    body compiled per specialization) asks the same question of the same class
    and gets the same answer. }
    { ...and the same rewrite for a GLOBAL routine of one of those four names,
      through the same two lines rather than a second arm. The method question
      is asked FIRST: an unqualified name inside a method means the member, and
      `Self.` is not what disambiguates AWAY from a global -- it is what
      disambiguates TOWARDS the member, so the member has to win here. }
  if IntrinsicNamesSelfMethodHere or IntrinsicNamesGlobalRoutineHere then
  begin
    CurTok.Kind := tkIdent;
    if (TokPos - 1) >= 0 then Tokens[TokPos - 1].Kind := tkIdent;
  end;
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal;
      { A literal wider than Int64 carries its DIGIT TEXT (the lexer sets SVal
        only in that case). ASTIVal holds the wrapped 64-bit reading, which is
        still the right QWord value; the span lets a promotable-int target take
        the exact value instead (feature-a-promoint-wide-literals). }
      { A literal that does not fit a signed 32-bit Integer is an Int64; the
        i386 backend keys its 64-bit codegen off this type. }
      if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      if Tokens[TokPos - 1].SLen > 0 then
      begin
        ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
        ASTSLen[node] := Tokens[TokPos - 1].SLen;
        { Force Int64 even though the WRAPPED value may look small: 2^64 wraps
          to 0 and would otherwise be typed tyInteger, which is both wrong and
          indistinguishable from a char literal's char-pool span. }
        ASTTk[node] := Ord(tyInt64);
      end;
      CurASTNode := node; Next;
    end;
    tkLBrack:
    begin
      CurASTNode := ParseSetLiteralAST;
      LastExprTk := tySet;
    end;
    tkBegin:
    begin
      Error('unexpected begin in expression');
    end;
    tkNil:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyPointer); CurASTNode := node; Next; LastExprTk := tyPointer;
    end;
    tkPlusPlus, tkMinusMinus:
    begin
      { Prefix `++lv` / `--lv`: bump first, yield the NEW value. Operand must be
        an lvalue (parsed as a factor so postfix/suffixes still bind). }
      bitNot := CurTok.Kind = tkPlusPlus; Next;   { bitNot reused as isIncrement }
      ParseFactor;
      node := AllocNode(AN_INCDEC);
      ASTLeft[node] := CurASTNode;
      if bitNot then ASTIVal[node] := 1 else ASTIVal[node] := -1;
      ASTSOffset[node] := 0;   { prefix → new value }
      ASTTk[node] := ASTTk[CurASTNode];
      CurASTNode := node; LastExprTk := IntToTypeKind(ASTTk[node]);
    end;
    tkIf:
    begin
      { Conditional EXPRESSION `if c then a else b` (the value-bearing form the C
        frontend's ternary `c ? a : b` lowers to). Reached only in expression
        position: a statement-leading `if` is parsed by ParseStatementAST before
        any factor, so this never shadows the if-statement. `else` is mandatory —
        an expression must yield a value. Arms are full expressions; parenthesize
        when embedding in a larger one. Result type = the then-arm's type. }
      Next;                          { consume 'if' }
      ParseExpr; left := CurASTNode; { condition }
      Expect(tkThen, 'then');
      ParseExpr; identNode := CurASTNode; tk := LastExprTk;  { then-arm }
      Expect(tkElse, 'else');
      ParseExpr; addrNode := CurASTNode;                     { else-arm }
      { A frozen string-literal arm types as tyString; carry the result as a
        managed AnsiString (managed-default) so it has a real handle downstream
        (writeln arg, assignment) — the IR per-arm assign coerces the literal. }
      if tk = tyString then tk := tyAnsiString;
      valNode := AllocNode(AN_PAIR);
      ASTLeft[valNode] := identNode; ASTRight[valNode] := addrNode;
      node := AllocNode(AN_TERNARY);
      ASTLeft[node] := left; ASTRight[node] := valNode;
      ASTTk[node] := Ord(tk);
      CurASTNode := node; LastExprTk := tk;
    end;
    tkDefault:
    begin
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Default(T): zero value of the type — ordinals/pointers/chars in v1
          (records/strings later). `default` lexes as its own token. }
        Next; Expect(tkLParen, '(');
        { `Default(TTest.TRecord)` — a type nested in a class or record body,
          named through its owner. Strip the qualifier FIRST, so every check and
          every dispatch below sees the type actually named: done later, the
          file-type and unspecialized-generic diagnostics would interrogate the
          OWNER's name instead. `dfNestCi` keeps the scope-correct row for the
          aggregate arm — two owners may each declare a `TSub`, and the bare
          lookup answers with whichever registered first.

          Nothing is consumed unless the leading name really owns nested types
          AND a `.ident` follows, which is the same guard the `var r:
          TTest.TRecord` and `SizeOf` paths use. When the registry resolves
          nothing (a nested subrange, enum or array is not a UClass row) the
          single-qualifier strip is still right: pxx registers those flat, so
          the qualifier only disambiguates the parse. }
        dfNestCi := -1; dfHops := 0;
        if (CurTok.Kind = tkIdent) and (NestedOwnerCi(CurTok.SVal) >= 0) and
           (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot) and
           (Tokens[TokPos + 1].Kind = tkIdent) then
        begin
          dfNestCi := ScanNestedTypeRun(CurTok.SVal, dfNestName, dfHops);
          { The stripped qualifier names the owner, and since aliases became
            owner-scoped the bare member name is no longer findable without it.
            The comment above -- "pxx registers those flat, so the qualifier
            only disambiguates the parse" -- was true until then and is what
            made a nested SUBRANGE (tdefault8) stop resolving.
            regression-test-core-test-record-nested-type-section }
          if dfNestCi >= 0 then QualTypeOwnerCi := dfNestCi
          else QualTypeOwnerCi := NestedOwnerCi(CurTok.SVal);
          if dfHops = 0 then dfHops := 1;   { bare-name strip, one qualifier }
          for dfI := 1 to dfHops do
          begin
            Next;   { past the owner name — CurTok is now '.' }
            Next;   { past '.'            — CurTok is now the nested type name }
          end;
        end;
        { FPC-parity diagnostics: Default() is not defined for file types —
          neither TextFile itself nor a record that (transitively) contains one
          (bug-pascal-missing-diagnostics-fail-tests / tdefault2, tdefault6). }
        if CurTok.Kind = tkIdent then
        begin
          if CaseEqual(CurTok.SVal, 'text') or CaseEqual(CurTok.SVal, 'textfile') or
             CaseEqual(CurTok.SVal, 'filerec') then
            Error('Default: file types are not allowed');
          i := IsRecordType(CurTok.SVal);
          if (i <> REC_NONE) and RecContainsTextRec(i) then
            Error('Default: the record type contains a file field');
          { An UNSPECIALIZED generic template is not a type — it has no size and no zero
            value, so Default(TTest) is undefined (tdefault11/12). `Default(TTest<Integer>)`
            (delphi) is fine, hence the '<' lookahead; the objfpc form starts with
            `specialize`, so CurTok is not the template name there. }
          if IsGenericTemplateName(CurTok.SVal) and
             not ((TokPos < TokCount) and (Tokens[TokPos].Kind = tkLt)) then
            Error('Default: the generic type ' + CurTok.SVal + ' must be specialized');
          { A HELPER type is not a type you can hold a value of — it names a set
            of methods bolted onto another type and has no storage of its own,
            so it has no zero value either (tdefault13). Same shape as the
            unspecialized-generic refusal above. }
          i := FindUClass(CurTok.SVal);
          if (i >= 0) and (UClsHelperTk[i] >= 0) then
            Error('Default: a helper type has no value');
        end;
        { An AGGREGATE type has no integer zero: `Default(TRec)` used to yield
          the same INT_LIT 0 as `Default(Integer)`, and the record assignment
          then copied RecSize bytes from address 0 -- a SEGFAULT. A static
          array was worse, because it was silent: `ar := Default(TArr)` stored
          an integer into an array slot and left every element untouched, so a
          dirty array stayed dirty and nothing said so.

          Zero of an aggregate is a whole zeroed OBJECT, so materialise one:
          a hidden static (BSS, therefore zero-filled at load) variable of that
          exact type, which nothing can ever write to -- Default() is an rvalue,
          so it cannot be passed by reference or assigned through. The ordinary
          record/array copy then does the rest, managed fields included.
          A CLASS is not an aggregate here (IsRecordType excludes it) and keeps
          the integer 0, which is its correct nil.
          bug-p-default-of-a-record-segfaults-of-an-array-does-nothing }
        dfSym := -1;
        dfTk := tyInt64;
        if CurTok.Kind = tkIdent then
        begin
          { The SCOPED row when the qualifier resolved one and it is a record;
            otherwise the flat bare-name lookup, unchanged. A nested CLASS is
            not an aggregate — it keeps the integer 0 that is its correct nil,
            exactly as an unqualified class does. }
          if (dfNestCi >= 0) and UClsIsRecord[dfNestCi] then
            dfRec := REC_UCLASS_BASE + dfNestCi
          else if dfNestCi >= 0 then
            dfRec := REC_NONE
          else
            dfRec := IsRecordType(CurTok.SVal);
          if dfRec <> REC_NONE then
          begin
            dfSaveStatic := AllocStaticLocal;
            AllocStaticLocal := True;
            LastTypeRecId := dfRec;
            LastTypeIsSub := False;
            dfSym := AllocVar('', tyRecord);
            AllocStaticLocal := dfSaveStatic;
            dfTk := tyRecord;
          end
          else
          begin
            dfAi := FindArrayType(CurTok.SVal);
            if (dfAi >= 0) and (not ArrTypeIsDyn[dfAi]) then
            begin
              { A FIXED array alias. Multi-dimensional and row-element forms
                carry shape AllocArray cannot rebuild from lo/hi alone -- refuse
                those LOUDLY rather than fall back to the integer 0 that made
                this a silent bug in the first place. }
              if (ArrTypeNDims[dfAi] > 1) or (ArrTypeElemRowLen[dfAi] <> 0) then
                Error('Default: multi-dimensional array types are not supported yet');
              dfSaveStatic := AllocStaticLocal;
              AllocStaticLocal := True;
              LastTypeRecId := ArrTypeElemRec[dfAi];
              LastTypeIsSub := False;
              LastTypeElemDynDepth := 0;
              dfSym := AllocArray('', IntToTypeKind(ArrTypeElemTk[dfAi]),
                                  ArrTypeLo[dfAi], ArrTypeHi[dfAi]);
              AllocStaticLocal := dfSaveStatic;
              dfTk := IntToTypeKind(ArrTypeElemTk[dfAi]);
            end;
          end;
        end;
        if dfSym >= 0 then
        begin
          node := AllocNode(AN_IDENT);
          ASTIVal[node] := dfSym;
          ASTTk[node] := Ord(dfTk);
        end
        else
        begin
          { The zero of a STRING is '' and the zero of a class, interface or
            pointer is nil -- neither is the integer 0 wearing an Int64 tag,
            which is what this arm produced for every non-aggregate type. It
            worked by accident (the store is the same bytes) and it lied to
            everything that reads the tag: with assignments now type-checked,
            `s := Default(string)` reported "cannot assign Int64 to AnsiString"
            on code that is correct and that FPC accepts.

            Resolving the type here rather than skipping over its tokens also
            makes the node say what it is: `c := Default(TCls)` becomes exactly
            the node `c := nil` builds. Aggregates keep the materialised static
            above -- they are the case that cannot be a literal at all.
            bug-a-an-assignment-is-not-type-checked-at-all (follow-up) }
          dfTk := ParseTypeKind;
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := 0;
          if TypeIsManagedStr(dfTk) or TypeIsFrozenString(dfTk) then
          begin
            node := AllocNode(AN_STR_LIT);
            ASTSOffset[node] := 0;
            ASTSLen[node] := 0;
            ASTTk[node] := Ord(dfTk);
          end
          else if (dfTk = tyClass) or (dfTk = tyPointer) then
            ASTTk[node] := Ord(tyPointer)
          else
          begin
            { every ordinal, char, bool, float and enum: the integer zero, as
              before, and the tag it always had. }
            ASTTk[node] := Ord(tyInt64);
            dfTk := tyInt64;
          end;
        end;
        i := 1;
        while (i > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLParen then Inc(i)
          else if CurTok.Kind = tkRParen then Dec(i);
          if i > 0 then Next;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        LastExprTk := dfTk;
      end
      else
      begin
        node := AllocNode(AN_DEFAULT);
        ASTTk[node] := Ord(tyUnknown);
        CurASTNode := node;
        LastExprTk := tyUnknown;
        Next;
      end;
    end;
    tkAt:
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('expected identifier after @');
      name := CurTok.SVal;
      idx := FindSym(name);
      { @obj.method yields a TMethod (Code+Data): obj is a class instance var,
        method one of its methods. Code = method proc address,
        Data = the instance pointer. Only valid as the RHS of an assignment to
        a TMethod-shaped target (handled in AN_ASSIGN). }
      if (idx >= 0) and (Syms[idx].RecName >= REC_UCLASS_BASE) and
         (not UClsIsRecord[Syms[idx].RecName - REC_UCLASS_BASE]) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
      begin
        ci := Syms[idx].RecName - REC_UCLASS_BASE;
        { A MEMBER IS NOT ONLY A METHOD OR A FIELD, AND THIS ARM KNEW TWO OF THE
          THREE. It asked FindUMeth, then FindUField, then raised
          `@obj.method: unknown method or field` -- so `@o.Items[0].Ev`, whose
          first selector is an indexed PROPERTY, was refused by name resolution
          rather than by the missing selector walk that this arm's other face
          had. A guard built by ENUMERATING member kinds goes wrong by the kind
          nobody listed, and properties are the kind this family keeps
          forgetting: the implicit-deref rule enumerated field and method and
          not property in exactly the same way
          (test_an_implicit_deref_through_every_opener records that one).

          Decided BEFORE the two Next's rather than after, because
          ParseClassRecordSelectors' loop is `[tkDot, tkLBrack]` and wants
          CurTok sitting ON the dot -- consuming it first and rewinding would be
          a second way to spell the same thing. The member name is therefore
          peeked out of Tokens[TokPos + 1].
          bug-p-at-over-a-class-base-consumes-only-one-selector }
        if (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkIdent) and
           (FindUMeth(ci, GetTokenStr(TokPos + 1)) < 0) and
           (FindUField(ci, GetTokenStr(TokPos + 1)) < 0) then
        begin
          valNode := AllocNode(AN_IDENT);
          ASTIVal[valNode] := idx;
          ASTTk[valNode] := Ord(tyClass);
          Next;            { consume obj name; CurTok is the '.' the walker wants }
          tk := tyClass;
          node := ParseClassRecordSelectors(valNode, Syms[idx].RecName, tk);
          valNode := AllocNode(AN_ADDR);
          ASTLeft[valNode] := node;
          ASTTk[valNode] := Ord(tyPointer);
          CurASTNode := valNode;
          LastExprTk := tyPointer;
          Exit;
        end;
        Next;            { consume obj name (CurTok = '.') }
        Next;            { consume '.' (CurTok = method name) }
        if CurTok.Kind <> tkIdent then Error('expected method name after @obj.');
        mmi := FindUMeth(ci, CurTok.SVal);
        if mmi < 0 then
        begin
          { @obj.field — ADDRESS of an instance field (blcksock's
            `buf := @Value.Value`). AN_ADDR over the field lvalue. }
          mmi := FindUField(ci, CurTok.SVal);
          if mmi < 0 then Error('@obj.method: unknown method or field');
          valNode := AllocNode(AN_IDENT);
          ASTIVal[valNode] := idx;
          ASTTk[valNode] := Ord(tyClass);
          node := AllocNode(AN_FIELD);
          ASTLeft[node] := valNode;
          ASTSOffset[node] := Tokens[TokPos-1].SOffset;
          ASTSLen[node] := Tokens[TokPos-1].SLen;
          ASTTk[node] := UFldTk[mmi];
          Next;   { consume field name }
          { ...AND THE REST OF THE DESIGNATOR, which this arm used to leave in
            the token stream. It consumed the object name, the dot and exactly
            ONE identifier and then took the address of that, so `@o.R.N` --
            a class instance, a record field, a field of THAT -- parsed as
            `@o.R` and left `.N` for the statement parser, which reported
            `a statement cannot start with '.'`. The error text depends on
            what follows the truncated parse and not on the defect, which is
            why the same cause reads as three unrelated bugs: `@o.R.Ev` gives
            `expected 'then' before '.'` and `@o.Items[0].Ev` gives
            `@obj.method: unknown method or field`, the latter because the
            name after the dot is a PROPERTY and both FindUMeth and FindUField
            miss it.

            THE BOUNDARY SAYS IT IS THE CLASS BASE AND NOT THE SHAPE: `@r.Inner.N`
            over a plain record and `@a[0].N` over an array element both
            compiled throughout, because those go through ParseLValueAST, which
            has always walked the whole chain. One opener of three.

            ParseClassRecordSelectors is that walk -- fields, methods,
            properties, default properties and `[` -- so this hands it the tail
            rather than growing a sixth hand-rolled selector loop here.
            refactor-p-three-hand-rolled-postfix-loops
            bug-p-at-over-a-class-base-consumes-only-one-selector }
          if CurTok.Kind in [tkDot, tkLBrack] then
          begin
            tk := IntToTypeKind(ASTTk[node]);
            node := ParseClassRecordSelectors(node, ResolveNodeRec(node), tk);
          end;
          valNode := AllocNode(AN_ADDR);
          ASTLeft[valNode] := node;
          ASTTk[valNode] := Ord(tyPointer);
          CurASTNode := valNode;
          LastExprTk := tyPointer;
          Exit;
        end;
        valNode := AllocNode(AN_IDENT);   { object value = the instance pointer }
        ASTIVal[valNode] := idx;
        ASTTk[valNode] := Ord(tyClass);
        node := AllocNode(AN_METHODREF);
        ASTIVal[node] := UMthProc_[mmi];
        ASTLeft[node] := valNode;
        { Record the method's VMT slot (>=0 virtual, -1 non-virtual) so the code
          pointer resolves through the object's VMT at runtime, not the static base
          address — `@baseref.VirtualMethod` must capture the derived override
          (bug-a-method-pointer-virtual-captures-static-address). }
        ASTRight[node] := UMthVirSlot[mmi];
        { Typed as a Pointer: in a value/argument context @obj.Method surfaces its
          CODE address (IR lowering yields IR_PROCADDR), so it matches a Pointer
          parameter — `TakesPtr(@h.M)`. Assignment to a TMethod target still
          captures code+data: AN_ASSIGN keys on the AN_METHODREF node kind, not
          this type, so `pm := @h.M` / `widget.OnClick := @h.M` are unaffected. }
        ASTTk[node] := Ord(tyPointer);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      { @Method bare inside a method body: implicit Self — @BinaryCompareKey
        == @Self.BinaryCompareKey (an AN_METHODREF: Code+Data). Checked before
        the plain @proc case so a method wins over a same-named free routine
        (innermost scope), matching the other implicit-Self dispatches. }
      else if (idx < 0) and (CurProc >= 0) and (CurSelfClass >= REC_UCLASS_BASE) and
              (Procs[CurProc].ParamCount > 0) and
              (FindUMeth(SelfMemberCi(name), name) >= 0) and
              ((TokPos >= TokCount) or (Tokens[TokPos].Kind <> tkDot)) then
      begin
        mmi := FindUMeth(SelfMemberCi(name), name);
        valNode := AllocNode(AN_IDENT);
        ASTIVal[valNode] := Procs[CurProc].Params[0].SymIdx;   { Self }
        ASTTk[valNode] := Ord(tyClass);
        node := AllocNode(AN_METHODREF);
        ASTIVal[node] := UMthProc_[mmi];
        ASTLeft[node] := valNode;
        ASTRight[node] := UMthVirSlot[mmi];   { VMT slot (>=0 virtual): resolve via VMT }
        ASTTk[node] := Ord(tyPointer);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      { @TClass.Method — the method's raw CODE address, reached through the TYPE
        name rather than an instance. No Data half and no VMT lookup: with no
        object there is nothing to dispatch on, so FPC yields the static address
        of that class's own implementation even for a virtual method, which is
        exactly what makes the idiom useful — hand-built VMTs (rtl-generics'
        Generics.Defaults fills its IComparer VMT records with
        `@TRawInterface._AddRef` and friends).

        Guarded on idx < 0 so a VARIABLE of the same name keeps the @obj.method
        path above; a class TYPE is not in the sym table, which is precisely why
        this used to fall through to ParseLValueAST and get diagnosed as
        `cannot call non-static method on class type directly` — the @ never
        reached the decision, so taking an address was read as calling. }
      else if (idx < 0) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) and
              (FindUClass(name) >= 0) then
      begin
        ci := FindUClass(name);
        Next;            { consume class name (CurTok = '.') }
        Next;            { consume '.' (CurTok = method name) }
        { A method may be NAMED after a type keyword (generics.defaults'
          `TCompare.Single`), and those tokens carry an empty SVal — read the
          name via GetTokenStr, never SVal. }
        if not IsMethodNameTok then Error('expected method name after @' + name + '.');
        mthName := GetTokenStr(TokPos - 1);
        mmi := FindUMeth(ci, mthName);
        if mmi < 0 then Error('@' + name + '.' + mthName + ': unknown method');
        node := AllocNode(AN_PROCADDR);
        ASTIVal[node] := UMthProc_[mmi];
        ASTTk[node] := Ord(tyPointer);
        Next;            { consume method name }
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      { @proc: not a variable but a known routine → absolute code address }
      else if (idx < 0) and (FindProc(name) >= 0) then
      begin
        node := AllocNode(AN_PROCADDR);
        ASTIVal[node] := FindProc(name);
        ASTTk[node] := Ord(tyPointer);
        Next;
        CurASTNode := node;
        LastExprTk := tyPointer;
      end
      else
      begin
        Next;
        valNode := ParseLValueAST(idx, TokPos - 2);
        node := AllocNode(AN_ADDR);
        ASTLeft[node] := valNode;
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        LastExprTk := tyPointer;
      end;
    end;
    tkFloat:
    begin
      node := AllocNode(AN_FLOAT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyDouble);
      CurASTNode := node; LastExprTk := tyDouble; Next;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean); CurASTNode := node; Next; LastExprTk := tyBoolean;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean); CurASTNode := node; Next; LastExprTk := tyBoolean;
    end;
    tkString:
    begin
      prevTok := TokPos - 1;
      if Length(CurTok.SVal) = 1 then
      begin
        node := AllocNode(AN_INT_LIT); ASTIVal[node] := Ord(CurTok.SVal[1]); ASTTk[node] := Ord(tyChar);
        ASTSOffset[node] := Tokens[prevTok].SOffset; ASTSLen[node] := Tokens[prevTok].SLen;
        CurASTNode := node; Next; LastExprTk := tyChar;
      end
      else
      begin
        prevTok := TokPos - 1; Next;
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := Tokens[prevTok].SOffset; ASTSLen[node] := Tokens[prevTok].SLen;
        ASTTk[node] := Ord(tyString); CurASTNode := node;
        LastExprTk := tyString;
        { Trailing index on the LITERAL itself — `'hello'[1]`, which FPC takes.
          A NAMED string constant has had this since bug-const-string-index-
          miscompiles; the bare literal is the same AN_STR_LIT node and lowers
          the same way (IRLowerAddress reaches its IR_CONST_STR storage), so it
          was missing the loop and nothing else. Kept as the identical shape,
          NOT routed through GenMakeStringValueIndex: a literal's storage IS
          addressable, so it needs no temp.
          bug-a-indexing-a-parenthesised-string-compiles-and-segfaults }
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          indexNode := AllocNode(AN_INDEX);
          ASTLeft[indexNode] := node;
          ParseExpr;
          ASTRight[indexNode] := CurASTNode;
          Expect(tkRBrack, ']');
          ASTTk[indexNode] := Ord(tyChar);
          node := indexNode; CurASTNode := node;
          LastExprTk := tyChar;
        end;
      end;
    end;
    tkLParen:
    begin
      Next; ParseExpr;
      { C comma operator `(a, b, ...)`: each operand but the last is evaluated for
        its side effects then discarded; the value is the last. A parenthesised
        comma list is otherwise a syntax error in pxx, so this is conflict-free
        and reads identically to C. Right-nested AN_COMMA so lowering discards
        each Left in turn. }
      if (CurTok.Kind = tkComma) then
      begin
        node := CurASTNode;
        while Eat(tkComma) do
        begin
          ParseExpr;
          valNode := AllocNode(AN_COMMA);
          ASTLeft[valNode] := node;
          ASTRight[valNode] := CurASTNode;
          ASTTk[valNode] := ASTTk[CurASTNode];
          node := valNode;
        end;
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
      end;
      Expect(tkRParen, ')');
      { Postfix suffix on a parenthesised expression: `(p)^`, `(p+k)^`, `(r).f`,
        `(a)[i]`. Without this the `^`/`.`/`[` were left dangling and the grouped
        value was used as-is (e.g. `(p)^` returned the pointer, not the pointee). }
      node := CurASTNode;
      while ((CurTok.Kind = tkCaret) or
             (CurTok.Kind in [tkDot, tkLBrack])) do
      begin
        { A grouped value whose type is a CLASS goes to the real member/index dispatcher --
          `(Data as TJSONArray)[0].ClassType` (fcl-json's suite).

          This tail used to hand-roll `.` and `[` itself, and it did so WITHOUT the class id:
          ResolveNodeRec has always known an as-cast's class, but the tail never asked. So
          `(b as T)[i]` built a raw AN_INDEX instead of dispatching the DEFAULT PROPERTY --
          leaving the AN_AS_CAST orphaned and unlowerable -- and `(b as T).Member` silently
          DROPPED an unresolvable member and evaluated to the object pointer.

          It was the THIRD copy of member/index dispatch (ParseLValueAST's suffix loop,
          ParseClassRecordSelectors, and this). The duplication was the bug, so this hands off
          rather than growing a fourth: default properties, virtual methods, properties and the
          class-reference ops all come along for free, and cannot drift again. }
        if (CurTok.Kind in [tkDot, tkLBrack]) then
        begin
          parenRec := ResolveNodeRec(node);
          if parenRec >= REC_UCLASS_BASE then
          begin
            tk := IntToTypeKind(ASTTk[node]);
            node := ParseClassRecordSelectors(node, parenRec, tk);
            recName := ResolveNodeRec(node);
            Continue;
          end;
          { …and a TYPE-HELPER method on the grouped VALUE: `(F).ToUpper`,
            `(s + 'x').Twice`. Asked here rather than in the hand-rolled `.`
            tail below because the tail has already consumed the dot by the
            time it knows what it is looking at. A grouped record/class went to
            the real dispatcher above, so this only ever sees the scalar shapes
            that have no member path of their own.
            feature-p-delphi-string-helpers }
          if CurTok.Kind = tkDot then
          begin
            tk := IntToTypeKind(ASTTk[node]);
            valNode := TypeHelperOnValue(node, tk);
            if valNode >= 0 then
            begin
              node := valNode;
              recName := ResolveNodeRec(node);
              Continue;
            end;
          end;
        end;

        if CurTok.Kind = tkCaret then
        begin
          Next;
          indexNode := AllocNode(AN_DEREF);
          ASTLeft[indexNode] := node;
          { Resolve the pointee from the inner node — and now through the SAME
            walk the direct `ident^` path uses, rather than a second, smaller
            one that knew only NodePtrElem.

            The old copy answered the immediate pointee and stamped NOTHING, so
            the deref node carried no remaining-depth and no ultimate base:
            `(qa[0])^` over an `array of ^PChar` printed the address, `'x' + it`
            was empty and `Length` answered the pointer, while the identical
            `qa[0]^` one character to the left was correct in all seven
            contexts. ResolveDerefShape keeps the NodePtrElem fallback for
            pointer ARITHMETIC — `(pc + 2)^` still reads one char, not four
            bytes (bug-p-a-pchar-plus-offset-loses-its-type-when-dereferenced) —
            so this is strictly the old behaviour plus the shapes the copy
            lacked. refactor-centralize-managed-string-pchar-conversion }
          tk := tyInteger; recName := REC_NONE;
          ResolveDerefShape(node, tk, recName, derefRem, derefBaseTk, derefBaseRec);
          ASTSOffset[indexNode] := derefRem;
          ASTSLen[indexNode] := derefBaseTk;
          if derefBaseRec > 0 then ASTIVal[indexNode] := derefBaseRec;
          ASTTk[indexNode] := StrValTk(tk);
          node := indexNode;
        end
        else if CurTok.Kind = tkLBrack then
        begin
          if NodeIsIndexableStringValue(node) then
          begin
            { A grouped STRING has no addressable base, so a raw AN_INDEX over
              it indexes the string HANDLE rather than a slot holding one:
              `(s)[3]` compiled clean and segfaulted at run time, and
              `(s + 'x')[3]` reached IR_UNSUPPORTED. Materialise into a temp and
              index that — the same move, and now literally the same code, as
              the string-returning-call arm in pasparser_lval.inc.
              bug-a-indexing-a-parenthesised-string-compiles-and-segfaults }
            node := GenMakeStringValueIndex(node);
            tk := tyChar;
          end
          else
          begin
            Next;
            indexNode := AllocNode(AN_INDEX);
            ASTLeft[indexNode] := node;
            ParseExpr;
            ASTRight[indexNode] := CurASTNode;
            Expect(tkRBrack, ']');
            ASTTk[indexNode] := ASTTk[node];
            node := indexNode;
          end;
        end
        else { tkDot — field or method of the grouped record/class value }
        begin
          Next;
          if CurTok.Kind in [tkEOF, tkSemicolon, tkAssign, tkRBrack, tkRParen] then
            Error('expected field name after .');
          prevTok := TokPos - 1;
          fieldName := GetTokenStr(prevTok);
          baseRec := ResolveNodeRec(node);
          mci := -1; mmi := -1;
          if baseRec >= REC_UCLASS_BASE then
          begin
            mci := baseRec - REC_UCLASS_BASE;
            if FindUProp(mci, fieldName) < 0 then
            begin
              mmi := FindUMethOverloadAhead(mci, fieldName, CountCallArgsAhead);
              if isNilPy and (mmi >= 0) then
                mmi := PyPromoteOverloadByKwAt(mci, mmi, PyKwNamesTokPos, fieldName);
            end;
          end;
          if (mmi >= 0) and (mci >= 0) then EnforceMethVis(mmi, fieldName);
          if (mmi >= 0) and (mci >= 0) and UClsIsInterface[mci] then
          begin
            { `(iface-expr).M(args)` — dispatch through the IMT slot, exactly like
              the direct `iface.M` path. The grouped node is the interface value. }
            mpi := UMthProc_[mmi];
            Next; { consume method name }
            mcallNode := AllocNode(AN_INTF_CALL);
            ASTRight[mcallNode] := node;
            ASTIVal[mcallNode] := mpi;
            ASTSOffset[mcallNode] := UMthVirSlot[mmi];
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            mlastArg := -1;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mai := 1; { param 0 = Self (provided by the fat pointer) }
              { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
                accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
                the `)` to ParseExpr and reports "expected expression". A method with NO parameters
                already worked, because the loop simply never ran. }
              if CurTok.Kind = tkRParen then
              begin
                if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
                  FillDefaultArgs(mpi, 1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
              end;
              { `d.update(a=1)` / `d.update(**e)` — the keywords-are-KEYS case,
                asked the same way every other argument loop asks it. }
              if PyKwDictArgsHere(mpi) then
              begin
                margSeq := AllocNode(AN_ARG);
                ASTLeft[margSeq] := PyBuildKeywordDictHere;
                ASTIVal[margSeq] := 0;
                ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
                mai := Procs[mpi].ParamCount;
              end;
              { `obj.m(*xs)` — a call-site UNPACK (the callee declares ordinary
                parameters; the star is on the CALL). A star is not an expression, so
                the arity loop below cannot parse it: hand the whole argument list to
                the NilPy path, which expands the list across the remaining slots. }
              if isNilPy and (mai <= Procs[mpi].ParamCount-1) and PyStarArgAhead then
                PyStarUnpackMethodArgs(mpi, mcallNode, mlastArg, mai);
              while mai <= Procs[mpi].ParamCount-1 do
              begin
                if Procs[mpi].Params[mai].IsRef or Procs[mpi].Params[mai].IsArray then
                begin
                  if ByRefArgStartsExpression(ParamIsConstVariant(mpi, mai)) then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseArgExpr; mexprNode := CurASTNode;
                  end
                  else
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end
                else begin ParseArgExpr; mexprNode := CurASTNode; end;
                SetLitCheckArg(mexprNode, mpi, mai);
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                if mlastArg = -1 then ASTLeft[mcallNode] := margSeq
                else ASTRight[mlastArg] := margSeq;
                mlastArg := margSeq;
                if (mai < Procs[mpi].ParamCount-1) and CanFillDefaultsFrom(mpi, mai+1) then
                begin
                  FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  mai := Procs[mpi].ParamCount-1;
                end
                else if mai < Procs[mpi].ParamCount-1 then Expect(tkComma, ',')
              else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
                Inc(mai);
              end;
              ExpectCallRParen(mpi, mlastArg);
            end
            else if ParamsDefaultedFrom(mpi, 1) then
              { parenless `(iface-expr).M;` -- see ParamsDefaultedFrom }
              FillDefaultArgs(mpi, 1, mcallNode, mlastArg)
            else CheckMethodCallArity(mpi);
            node := mcallNode;
          end
          else if mmi >= 0 then
          begin
            { `(expr).M(args)` on a non-interface class/record value (e.g.
              `(o as T).M`). The interface branch above only handled IMT dispatch;
              without this a class method silently lowered to an AN_FIELD read and
              was never called. Mirrors ParseClassRecordSelectors: static or
              virtual dispatch, Self = the grouped value (arg 0). }
            mpi := UMthProc_[mmi];
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
              mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := node;   { Self = arg 0 }
            ASTLeft[mcallNode] := margSeq;
            mlastArg := margSeq;
            Next; { consume method name }
            if CurTok.Kind = tkLParen then
            begin
              Next;
              mai := 1;
              { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC
                accepts it (fcl-json's own suite calls `J.FormatJSON()`); without this the loop hands
                the `)` to ParseExpr and reports "expected expression". A method with NO parameters
                already worked, because the loop simply never ran. }
              if CurTok.Kind = tkRParen then
              begin
                if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
                  FillDefaultArgs(mpi, 1, mcallNode, mlastArg);
                mai := Procs[mpi].ParamCount;   { nothing to parse; Expect(tkRParen) consumes it }
              end;
              nArgs := 0;
              while mai <= Procs[mpi].ParamCount - 1 do
              begin
                { NilPy `key=expr` here too. This is the loop a receiver reached
                  through a FIELD lands in (`self.canvas.create_window(...)`),
                  and it was the one method-call path with no keyword binding —
                  so an ordinary tkinter call worked through a local and failed
                  through a field (bug-nilpy-kwargs-on-a-field-receiver). }
                kwIdx := PyKwArgIndex(mpi, 1);
                if kwIdx > 0 then slotIdx := kwIdx - 1 else slotIdx := mai;
                if Procs[mpi].Params[slotIdx].IsRef or Procs[mpi].Params[slotIdx].IsArray then
                begin
                  if ByRefArgStartsExpression(ParamIsConstVariant(mpi, slotIdx)) then
                  begin
                    { non-ident by-ref/array arg (@obj.Method to a method-pointer
                      param, [..] literals, casts): parse as an expression }
                    ParseArgExpr; mexprNode := CurASTNode;
                  end
                  else
                  begin
                    margIdx := FindSym(CurTok.SVal); Next;
                    mexprNode := ParseLValueAST(margIdx, TokPos - 2);
                  end;
                end
                else begin ParseArgExpr; mexprNode := CurASTNode; end;
                margSeq := AllocNode(AN_ARG); ASTLeft[margSeq] := mexprNode;
                ASTIVal[margSeq] := kwIdx;
                ASTRight[mlastArg] := margSeq; mlastArg := margSeq;
                Inc(nArgs);
                if (kwIdx = 0) and (mai < Procs[mpi].ParamCount-1) and
                   CanFillDefaultsFrom(mpi, mai+1) then
                begin
                  FillDefaultArgs(mpi, mai+1, mcallNode, mlastArg);
                  mai := Procs[mpi].ParamCount-1;
                end
                else if mai < Procs[mpi].ParamCount-1 then
                begin
                  if isNilPy and (CurTok.Kind = tkRParen) then Break;
                  Expect(tkComma, ',');
                end
              else if isNilPy and (CurTok.Kind = tkComma) then Next;  { Python trailing comma }
                Inc(mai);
              end;
              { reorder keyword arguments into declaration order and fill the
                holes below the highest bound parameter }
              margSeq := ASTRight[ASTLeft[mcallNode]];   { first REAL arg (past Self) }
              if margSeq >= 0 then
              begin
                PyBindKwArgs(mpi, margSeq, mlastArg, nArgs);
                ASTRight[ASTLeft[mcallNode]] := margSeq;
              end;
              { -1, not mlastArg: PyBindKwArgs has just REORDERED this chain
                into declaration order, so mlastArg is no longer its tail and
                absorbing into it would append elements to the wrong slot.
                Python packs *args itself (PyPackStarArgs) anyway. }
              ExpectCallRParen(mpi, -1);
            end
            else if ParamsDefaultedFrom(mpi, 1) then
              { parenless `(o as T).M;` -- see ParamsDefaultedFrom }
              FillDefaultArgs(mpi, 1, mcallNode, mlastArg)
            else CheckMethodCallArity(mpi);
            { result type for chaining (e.g. (o as T).GetChild.M) }
            if (Procs[mpi].RetType = tyClass) or (Procs[mpi].RetType = tyRecord) then
              ASTTk[mcallNode] := Ord(Procs[mpi].RetType);
            node := mcallNode;
          end
          else
          begin
            { Property on a grouped/cast value `(expr).Prop` — resolve to the
              backing field or getter call like ParseClassRecordSelectors (read
              side only: a grouped value is not an lvalue). Falling through to
              the raw field builder read offset 0 — the VMT pointer
              (bug-downcast-inherited-property-wrong-offset's sibling). }
            pri := -1;
            if mci >= 0 then pri := FindUProp(mci, fieldName);
            if (pri >= 0) and (UPropReadFLen[pri] > 0) then
            begin
              fieldNode := AllocNode(AN_FIELD);
              ASTLeft[fieldNode] := node;
              ASTSOffset[fieldNode] := UPropReadFOff[pri];
              ASTSLen[fieldNode] := UPropReadFLen[pri];
              grpAcc := '';
              for i := 0 to UPropReadFLen[pri] - 1 do
                AppendChar(grpAcc, TokChars[UPropReadFOff[pri] + i]);
              ASTTk[fieldNode] := Ord(RecFieldType(baseRec, grpAcc));
              Next;
              node := fieldNode;
            end
            else if (pri >= 0) and (UPropReadMLen[pri] > 0) then
            begin
              grpAcc := '';
              for i := 0 to UPropReadMLen[pri] - 1 do
                AppendChar(grpAcc, TokChars[UPropReadMOff[pri] + i]);
              mmi := FindUMeth(mci, grpAcc);
              if mmi < 0 then Error('getter method not found: ' + grpAcc);
              mpi := UMthProc_[mmi];
              Next; { consume property name }
              margIdx := -1;
              if UPropIsIndexed[pri] then ParsePropIndexArgs(margIdx, mlastArg)
            else PropIndexConstArg(pri, margIdx, mlastArg);
              { Getter args: [index...]; MakeAccessorCall places Self. }
              mcallNode := MakeAccessorCall(mci, mmi, mpi, node, margIdx);
              node := mcallNode;
            end
            else if pri >= 0 then
              Error('property is write-only')
            else
            begin
              { The guard ParseSelectors and ParseClassRecordSelectors both
                apply here, and this fourth copy of member dispatch did not:
                without it `(F).Twice` on a string-returning F built a field
                read at offset 0 and printed 113, ord('q'). RecFieldType's
                not-found default (tyInteger at offset 0) is the same trap in
                all four copies, so it is asked the same question in all four.
                bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes }
              RequireValueHasMembers(baseRec, fieldName);
              RequireRecMember(baseRec, fieldName);
              fieldNode := AllocNode(AN_FIELD);
              ASTLeft[fieldNode] := node;
              ASTSOffset[fieldNode] := Tokens[prevTok].SOffset;
              ASTSLen[fieldNode] := Tokens[prevTok].SLen;
              ASTTk[fieldNode] := Ord(RecFieldType(baseRec, fieldName));
              Next;
              node := fieldNode;
            end;
          end;
        end;
      end;
      CurASTNode := node;
    end;
    tkMinus:
    begin
      Next; ParseFactor;
      left := CurASTNode;
      { A record/class operand with `operator -` is a CALL and nothing below
        applies to it -- the widening, the constant fold and the {$Q+} tag are
        all about integer negation. See UnaryOpOverloadCall for why this is a
        call rather than a tagged AN_NEG. }
      unOvl := UnaryOpOverloadCall(Ord(tkMinus), left);
      if unOvl >= 0 then
      begin
        CurASTNode := unOvl;
        Exit;
      end;
      node := AllocNode(AN_NEG); ASTLeft[node] := left;
      { Carry the operand's type, as the additive-level sign in ParseSimpleExpr
        does. Left untagged, `-(a // b)` on an Int64-returning helper printed
        18446744073709551613 instead of -3 — the untyped node read unsigned.

        ...except for an INTEGER operand, where FPC widens to Int64 first and
        carrying the operand's type is the bug. Measured, every integer type:
        `SizeOf(-x)` is 8 for Byte, ShortInt, Word, SmallInt, Integer, Cardinal,
        Int64, QWord, NativeInt and NativeUInt alike — FPC's unary minus has ONE
        result type. Carrying an unsigned operand's own width instead negated
        inside it, so `-b shr 1` on a Byte answered 2147483644 ($7FFFFFFC, a
        32-bit logical shift of $FFFFFFF8) where FPC says 9223372036854775804:
        the sign was gone before the shift ever ran, which is why the shift path
        was never where this could be fixed.

        The default dialect, not behind --strict-fpc: a silent wrong VALUE is a
        bug, not parity work (decide-unary-minus-widening-in-the-default-dialect,
        confirmed by the owner 2026-08-19).

        Deliberately NOT widened: tyBoolean and tyBool8 (not arithmetic),
        tyPointer (no sign), the promotable ints (already arbitrary precision,
        so a width has no meaning), and every float — where the operand type IS
        the result type. bug-p-unary-minus-on-an-unsigned-operand-truncates-to-32-bits }
      { A negated CONSTANT is the exception, and it is not a small one: FPC folds
        a constant expression and gives the result the SMALLEST SIGNED type that
        holds the value, so `-1` is a LongInt and stays one. Widening it changed
        three measured behaviours at once -- `IntToHex(-1, 8)` printed 16 digits
        because the Int64 overload won, `-7` in an `array of const` arrived as
        vtInt64 so a vtInteger reader skipped it, and the overload-width table
        moved its literal row to int64. All three are LongInt under FPC, and all
        three came back from Track T within the hour
        (regression-test-core-test-asm-emit and its two siblings). The widening
        below is about a negated VARIABLE, where FPC really does have one result
        type -- `-b` on a Byte is Int64 while `-7` is not. }
      if ASTConstIntValue(left, negConstVal, 0) then
      begin
        negConstVal := -negConstVal;
        if (negConstVal >= -2147483648) and (negConstVal <= 2147483647) then
          ASTTk[node] := Ord(tyInteger)
        else
          ASTTk[node] := Ord(tyInt64);
      end
      else if NegWidensToInt64(IntToTypeKind(ASTTk[left])) then ASTTk[node] := Ord(tyInt64)
      else ASTTk[node] := ASTTk[left];
      { {$Q+} region: unary minus is overflow-checked too. FPC raises
        EIntOverflow on `-Low(Int64)` and on nothing else once the widening
        above is in place — every narrower type's negation fits an Int64.
        The check itself is not a new IR op: ir.inc rewrites a tagged AN_NEG
        into `0 - x`, the same rewrite the promotable-int and variant arms
        already use, so the existing IR_BINOP check runs and no backend moves.
        feature-pascal-overflow-checks-q-plus }
      if TokQChecks[TokPos - 1] then ASTQChk[node] := True;
      CurASTNode := node;
    end;
    tkNot:
    begin
      Next; ParseFactor;
      left := CurASTNode;
      { `not` is bitwise complement for an INTEGER operand (matches FPC) and
        logical for everything else, decided from the operand's own ASTTk and
        nothing else.

        It used to be decided from ASTTk *and* a WHITELIST of operand node kinds
        "whose type is authoritative", because the frontend once tagged some
        logically-Boolean expressions tyInteger and trusting those flipped them
        to `not rax` instead of `xor rax,1`. That list was a museum -- array
        element, field, deref, Ord(x), value-cast, nested not, and/or/xor at
        explicit width, arithmetic binop, unary minus -- and every entry arrived
        AFTER someone shipped wrong bits, which is what
        feature-a-trust-the-operand-type-for-not was filed to end: a whitelist of
        the shapes someone happened to hit is not a rule, and the next shape is
        already wrong with nobody knowing which.

        The premise had EXPIRED. The mistagging it worked around was fixed by
        other work: `not (a = b)`, `not Eat(...)`, `not (p and q)` and
        `not (p or q)` all carry ASTTk = tyBoolean today (measured with
        PXXDBG=a.ast). So the whitelist was fully subsumed by the type tag, and
        deleting it changes no emitted code:

          - the self-host fixedpoint converges in one round;
          - the compiler WITH the list and the compiler WITHOUT it emit a
            BYTE-IDENTICAL compiler.pas -- the largest and most `not`-dense
            program in the repo -- and byte-identical binaries for the bitwise
            tests and cbitnot_b11.c;
          - a 53-expression `not` differential against fpc 3.2.2 (every operand
            shape the list ever named, plus comparisons, boolean ops, qword
            and/or/xor, Ord, casts, calls, derefs, array elements) gives exactly
            the same results before and after.

        Note the direction, which is why this is safe by construction: the old
        condition was `integer-typed AND whitelisted`, so removing the second
        half can only turn LOGICAL into BITWISE, never the reverse. The only way
        it could break is an integer-TAGGED operand that is logically Boolean --
        precisely what compiler.pas being byte-identical rules out.

        Do not re-add a node-kind arm here. If a shape is wrong, the tag is
        wrong; fix the tag. }
      { `not` OVER A BOOLEAN LITERAL answers itself. Folded here and not only at
        the `and`/`or` sites, for the same reason the C side folds its truthy
        helper: a chain is left-associative, so `(False or False) or (not True)`
        hands the second `or` an operand that must ALREADY be a literal or the
        chain stops one step in. Measured on exactly that line.
        feature-a-fold-the-consensus-dead-branch-core-at-every-level }
      if PasBoolLit(left, notBlv) then
      begin
        CurASTNode := PasMakeBoolLit(not notBlv);
        LastExprTk := tyBoolean;
        Exit;
      end;
      { `not` over an aggregate is only ever a user overload -- see the AN_NEG
        arm above; same guard, same reason. Ahead of the node allocation and the
        bitwise/logical split, because neither answer is meaningful for a record
        and the overload's result is a call, not an AN_NOT. }
      unOvl := UnaryOpOverloadCall(Ord(tkNot), left);
      if unOvl >= 0 then
      begin
        CurASTNode := unOvl;
        LastExprTk := IntToTypeKind(ASTTk[unOvl]);
        Exit;
      end;
      { A SIZED BOOLEAN is an integer of its own width carrying a MEANING its
        kind cannot express -- that is the C ABI, and the width is right. The
        tag says tyInt8 and the note above says to trust the tag. The tag is not
        wrong here; it is INCOMPLETE, and the identity beside it is the rest of
        the answer.

        NORMALISED rather than given an arm: the operand becomes an ordinary
        `x <> 0` Boolean and everything below this line -- the bitwise/logical
        split, the literal fold, the codegen -- runs unchanged and unaware. A
        `bitNot := False` here would have been the smaller edit and WRONG, since
        the logical path lowers to `xor 1`, which is correct for a canonical 0/1
        Boolean and not for `ByteBool(200)`.

        This is also NOT the node-kind whitelist that arm forbids. That asked
        "is this SHAPE one whose type I believe"; this asks what the value
        MEANS, through the one resolver that knows which of the five identity
        channels applies to which node shape, so a new node shape is right here
        for free rather than wrong by default.

        Without it `var a: ByteBool; a := True` made `if a` and `if not a` BOTH
        fire, silently, with no diagnostic: `not 1` is 254 as a byte and -2 as a
        LongBool, both nonzero, both true. Right for False only by accident
        (`not 0` is nonzero, which is the wanted answer), so a probe that only
        sets False cannot see it.
        bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time }
      left := SemBoolAsBoolean(left);
      node := AllocNode(AN_NOT); ASTLeft[node] := left;
      bitNot := (ASTTk[left] = 1) or ((ASTTk[left] >= 7) and (ASTTk[left] <= 16));
      if bitNot then
      begin
        ASTTk[node] := ASTTk[left];
        { FPC complements `ord(x)` at the OPERAND's width: ord(char/boolean) is
          byte-sized (`not ord('a')` = 158, not -98); a subword/64-bit integer
          operand keeps its own width; an enum stays the 4-byte default. }
        if (ASTKind[left] = AN_CALL) and (Integer(ASTIVal[left]) = -Ord(tkOrd)) then
        begin
          notOrdTk := IntToTypeKind(ASTTk[ASTLeft[ASTLeft[left]]]);
          if (notOrdTk = tyChar) or (notOrdTk = tyBoolean) then
            ASTTk[node] := Ord(tyUInt8)
          else if (Ord(notOrdTk) >= 7) and (Ord(notOrdTk) <= 16) then
            ASTTk[node] := Ord(notOrdTk);
        end;
        { ...unless the operand is a CONSTANT, and then the width question does
          not arise: FPC evaluates a constant expression in a signed 64-bit
          type, so `not High(Byte)` is -256, `not Low(Byte)` is -1 and
          `not Ord('A')` is -66 -- while the same `not` over a byte-typed
          VARIABLE complements at the variable's own width (254), which is why
          this must not fire on a variable.

          ParseFactor's tkMinus arm has typed a negated constant this way since
          ASTConstIntValue was written for it; `not` is the same rule and was
          never given it, so a constant operand complemented inside its small
          type and produced a POSITIVE number where fpc gives a negative one.
          bug-p-not-of-a-builtin-round-or-trunc-call-is-logical }
        if ASTConstIntValue(left, notConstV, 0) then
        begin
          { the SMALLEST signed type the complement fits in, which is what FPC
            gives a constant expression -- not a blanket Int64. The difference
            is not cosmetic: forcing 64 bits made `not 255` an IR_NOT with a
            64-bit result over a 32-bit immediate, and arm32 leaves the high
            half of such a NOT undefined (measured: -579161170041110784 for
            `not 255`, correct on x86-64/i386/aarch64/riscv32). That backend
            gap is filed separately; typing the constant the way fpc does is
            right on its own terms and stops feeding it. }
          notConstV := not notConstV;
          if (notConstV >= -2147483648) and (notConstV <= 2147483647) then
            ASTTk[node] := Ord(tyInteger)
          else
            ASTTk[node] := Ord(tyInt64);
        end;
        LastExprTk := IntToTypeKind(ASTTk[node]);
      end
      else
      begin
        ASTTk[node] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
      end;
      CurASTNode := node;
    end;
    tkInteger_T, tkLongWord_T:
    begin
      { 'byte'/'longword' collide with 'integer'/'longint' on token KIND (all
        four lex as tkInteger_T/tkLongWord_T -- see asmenc.inc's documented
        landmine on this), so disambiguate on the source text, same technique
        SizeOf's type-name parsing already uses. A genuine byte/cardinal cast
        needs real width truncation (AN_PTR_CAST, routes through the masking
        logic in ir.inc's AN_PTR_CAST case) -- not the Integer/LongWord
        "value-pun" passthrough (AN_CALL, result bit pattern = operand's,
        unchanged), which stays exactly as it was for actual Integer/LongInt
        casts. See bug-narrowing-typecast-rvalue-no-truncate. }
      if CaseEqual(CurTok.SVal, 'byte') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        { demote a promotable operand first — see PromoDemoteToInt64 }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        vcNode := VariantCastToTemp(CurASTNode, tyUInt8);   { Byte(v) converts }
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyUInt8;
        end
        else
        begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;
          ASTTk[node] := Ord(tyUInt8);
          CurASTNode := node;
          LastExprTk := tyUInt8;
        end;
      end
      else if CaseEqual(CurTok.SVal, 'longword') then
      begin
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        { demote a promotable operand first — see PromoDemoteToInt64 }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        vcNode := VariantCastToTemp(CurASTNode, tyUInt32);   { LongWord(v) converts }
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyUInt32;
        end
        else
        begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;
          ASTTk[node] := Ord(tyUInt32);
          CurASTNode := node;
          LastExprTk := tyUInt32;
        end;
      end
      else
      begin
        op := Ord(CurTok.Kind);
        Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
        { a promotable operand demotes before the pun — see PromoDemoteToInt64 }
        CurASTNode := PromoDemoteToInt64(CurASTNode);
        { …and a VARIANT operand is a CONVERSION, not a pun — see
          VariantCastToTemp. Same Exit shape as the Explicit-operator arm
          just below. }
        vcNode := VariantCastToTemp(CurASTNode, tyInteger);
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyInteger;
          Exit;
        end;
        { `operator Explicit(a: TFoo): Integer` — an Integer(recordValue)
          cast with a matching Explicit overload is the conversion CALL
          (toperator11), not the value-pun. }
        if ((IntToTypeKind(ASTTk[CurASTNode]) = tyRecord) or
            (IntToTypeKind(ASTTk[CurASTNode]) = tyClass)) then
        begin
          i := FindOpOverload(OPK_EXPLICIT, ASTTk[CurASTNode], ResolveNodeRec(CurASTNode));
          if (i >= 0) and TypeIsOrdinal(Procs[i].RetType) then
          begin
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
            node := AllocNode(AN_CALL); ASTIVal[node] := i;
            ASTTk[node] := Ord(Procs[i].RetType);
            ASTLeft[node] := argSeq;
            CurASTNode := node;
            LastExprTk := Procs[i].RetType;
            Exit;
          end;
        end;
        { `Integer(x)` is a NARROWING cast the moment x is wider than 32 bits
          or 32-bit UNSIGNED, and FPC truncates it: Integer(LongWord(4000000000))
          is -294967296. The pun below hands the bit pattern through untouched,
          so it answered 4000000000 -- while `LongInt(x)`, the exact synonym,
          was right all along, because `longint` is not a type TOKEN and took
          the identifier path into a real AN_PTR_CAST. One concept, two
          spellings, and the fix for the other spellings (byte/longword, in
          bug-narrowing-typecast-rvalue-no-truncate) deliberately left this one
          alone -- which is precisely how the second path stays broken.
          An operand that cannot change value under the cast (a signed 32-bit
          or narrower ordinal, Char, Boolean) keeps the pun, so the common
          `Integer(someInteger)` emits no masking at all.
          bug-p-integer-cast-does-not-truncate-in-rvalue-position }
        castTk := IntToTypeKind(ASTTk[CurASTNode]);
        if TypeIsOrdinal(castTk) and (castTk <> tyBoolean) and (castTk <> tyChar) and
           ((TypeSlotSize(castTk) > 4) or
            ((TypeSlotSize(castTk) = 4) and not TypeSigned(castTk))) then
        begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
          LastExprTk := tyInteger;
          Exit;
        end;
        node := AllocNode(AN_CALL); ASTIVal[node] := -op;
        ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
      end;
    end;
    tkChar_T, tkBoolean_T:
    begin
      { `Char(x)` / `Boolean(x)` value-puns — same passthrough model as Chr/Ord:
        the result type is the cast type, the bit pattern is the operand's. }
      op := Ord(CurTok.Kind);
      if CurTok.Kind = tkChar_T then LastExprTk := tyChar else LastExprTk := tyBoolean;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      { demote a promotable operand first, or the pun takes the low byte of the
        SLOT ADDRESS — `Char(n)` for n = 65 gave a character from the pointer,
        not 'A'. See PromoDemoteToInt64. }
      CurASTNode := PromoDemoteToInt64(CurASTNode);
      { a VARIANT operand converts instead of punning — see VariantCastToTemp.
        `Char(v)` punned the tag word into a control character and `Boolean(v)`
        was right only by accident (a non-zero tag reads as True). }
      if op = Ord(tkChar_T) then castTk := tyChar else castTk := tyBoolean;
      vcNode := VariantCastToTemp(CurASTNode, castTk);
      if vcNode >= 0 then
      begin
        CurASTNode := vcNode;
        LastExprTk := castTk;
      end
      else
      begin
        { The SAME node the identifier-spelled casts build (AN_PTR_CAST with
          ASTIVal = -1, the built-in ordinal pun), not an AN_CALL intrinsic.
          `Char` and `Boolean` are lexer TOKENS while `AnsiChar` is an
          identifier, so the two spellings took different paths and drifted:
          after the narrowing mask learned about tyChar, `AnsiChar(258)`
          answered 2 like FPC and `Char(258)` still answered 258. One concept,
          one node — now both spellings narrow through the one arm in ir.inc.
          bug-p-a-char-cast-does-not-truncate-to-one-byte }
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := -1;    { built-in cast }
        if op = Ord(tkChar_T) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyBoolean);
        CurASTNode := node;
      end;
    end;
    tkSingle_T, tkDouble_T, tkExtended_T, tkReal_T:
    begin
      { Value typecast to a float type, `Single(expr)` / `Double(expr)`. Unlike
        the integer/char puns this is a real conversion (int->float, or
        double->single narrowing), so desugar to a hidden temp of the cast type
        plus an assignment — the ordinary store path already coerces the operand.
        Reuses the generic assign-then-yield node (AN_STR_FROM_CHAR: Left = the
        store side-effect, Right = the temp read). `Extended` aliases Double. }
      { The temp's type is the CAST's, not the OPERAND's: `ParseExpr` overwrites
        LastExprTk with the operand's kind, so `op := AllocVar('', LastExprTk)`
        handed the "conversion" a temp of the source type and the conversion
        never happened — `Single(d)` in expression position printed the
        unnarrowed double (3.7000000000 vs FPC's 3.7000000480), and for a
        VARIANT operand it built a VARIANT temp, so `Double(v)` stored the
        16-byte record through an 8-byte value and SEGFAULTED. Capturing the
        kind before ParseExpr fixes both: a variant temp becomes a real Double
        temp, and the store path then emits the variant unbox by itself.
        bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting }
      { `Real` was the one float keyword with no arm here, so `r := Real(d)` --
        a plain Double-to-Real cast that fpc 3.2.2 compiles -- was refused with
        `expected expression` while `var r: Real` declared fine. A name that
        answers at the DECLARATION door and is refused at the CAST door is the
        family bug-p-thirteen-builtin-type-names-answer-at-some-doors-and-are-
        refused-at-others is about, and this was the fourteenth.

        It takes RealTypeKind rather than tyDouble: `Real` is the target's
        native float depth, and ESP and riscv32 have no hardware double, so
        spelling tyDouble here would silently widen the cast on exactly the
        targets the type exists to keep narrow. That is the same rule
        BuiltinScalarTypeKind's `real` row already states. }
      if CurTok.Kind = tkSingle_T then castTk := tySingle
      else if CurTok.Kind = tkReal_T then castTk := RealTypeKind
      else castTk := tyDouble;
      LastExprTk := castTk;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      LastExprTk := castTk;
      { THE FOURTH COPY OF THIS BLOCK, and the one that was here first: the
        alias door and the builtin-name door each grew their own transcription
        of it, and the builtin-name door's never arrived, which is how
        `Currency(i)` came to hand on an integer's bits. One body now. }
      fcNode := FloatCastToTemp(CurASTNode, castTk);
      if fcNode >= 0 then CurASTNode := fcNode;
    end;
    tkString_T:
    begin
      { `String(x)`. For a string operand it is identity (passthrough). For a Char
        operand it must produce a *string value*; route through AN_STR_FROM_CHAR
        which reuses the `s := c` store into a hidden temp, then yields the temp —
        so it works in both frozen and managed string modes with no backend code. }
      LastExprTk := tyString;
      Next; Expect(tkLParen, '('); ParseExpr; Expect(tkRParen, ')');
      if (IntToTypeKind(ASTTk[CurASTNode]) = tyString) or
         (IntToTypeKind(ASTTk[CurASTNode]) = tyAnsiString) then
      begin
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkString_T);
        ASTTk[node] := ASTTk[CurASTNode];
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
      end
      else if IntToTypeKind(ASTTk[CurASTNode]) = tyChar then
      begin
        { Build the desugar at parse time so it goes through the same AST passes
          as hand-written code: a hidden string temp, `__t := c` (char->string
          store), and a read of __t. AN_STR_FROM_CHAR.Left = the assign (side
          effect), .Right = the temp read (the yielded value). The temp is tyString
          to match the `String` keyword (always frozen tyString in this dialect,
          even under PXX_MANAGED_STRING where only `AnsiString` is managed). }
        op := AllocVar('', tyString);
        node := AllocNode(AN_STR_FROM_CHAR);
        argSeq := AllocNode(AN_IDENT);       { LHS of the store }
        ASTIVal[argSeq] := op; ASTTk[argSeq] := Ord(Syms[op].TypeKind);
        left := AllocNode(AN_ASSIGN);
        ASTLeft[left] := argSeq; ASTRight[left] := CurASTNode;
        ASTTk[left] := Ord(Syms[op].TypeKind);
        ASTLeft[node] := left;
        identNode := AllocNode(AN_IDENT);     { the yielded value }
        ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
        ASTRight[node] := identNode;
        ASTTk[node] := Ord(Syms[op].TypeKind);
        CurASTNode := node;
      end
      else
      begin
        { A VARIANT operand is the variant->string CONVERSION (FPC's
          `String(v)`), which the store into a string temp already emits —
          see VariantCastToTemp. Before this it was a hard error. }
        vcNode := VariantCastToTemp(CurASTNode, tyString);
        if vcNode >= 0 then
        begin
          CurASTNode := vcNode;
          LastExprTk := tyString;
        end
        else
        begin
          { EVERYTHING else is a TYPECAST, which is what `String(x)` is in every
            position the conversions above do not claim.

            This arm used to be `if tyPointer then cast else Error`. The pointer
            half was itself a fix -- `String(p)` on a PChar was rejected while
            `AnsiString(p)`, `s := p` and `StrPas(p)` all worked -- and it landed
            as one more operand kind rather than as the rule, so the next operand
            kind hit the same wall. It did: `String(p^)` over an UNTYPED pointer
            deref, where `Integer(p^)`, `PtrUInt(p^)`, `Pointer(p^)`,
            `TObject(p^)` and `AnsiString(p^)` all compile and only the `String`
            spelling does not. That takes out every string-instantiated container
            in FPC's own fgl.pp, whose `T(FList.Items[i]^)` is this exact shape.

            The reason it kept happening is structural and worth stating once:
            `String` is a KEYWORD token (tkString_T) with its own branch, so it
            never reaches the identifier-cast path that serves `ansistring`,
            `shortstring` and the rest. Two mechanisms for one concept. So the
            branch now ENDS in the cast the identifier path builds rather than in
            an error, and the conversions above stay what they are: a Char, a
            managed string and a Variant are genuine conversions and are answered
            before this.

            No operand kind is refused here any more, which matches what the
            identifier path already does -- pxx accepts `AnsiString(i)` where fpc
            says "Illegal type conversion". Accepting a form fpc rejects is not a
            defect (see the FPC-parity ceiling in CLAUDE.md); the two spellings
            DISAGREEING was.
            bug-p-a-string-typecast-is-a-conversion-and-not-a-cast
            bug-p-string-of-a-pchar-is-rejected-while-ansistring-of-it-works }
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          ASTIVal[node] := -1;              { built-in cast, as the ident path does }
          if PasDefineExists('PXX_MANAGED_STRING') then
            ASTTk[node] := Ord(tyAnsiString)
          else
            ASTTk[node] := Ord(tyString);
          CurASTNode := node;
          LastExprTk := IntToTypeKind(ASTTk[node]);
        end;
      end;
      { `String(r)[4]` -- the KEYWORD spelling of the indexed string cast.
        The subscript was left standing and the enclosing expression reported
        `expected ')' before '['`. Same walk, same call, as the identifier
        spelling `AnsiString(r)[4]` and the alias spelling `t(r)[4]` -- this arm
        exists precisely because `String` is a keyword token and never reaches
        the identifier path, which is the structural reason this file keeps
        fixing one concept three times.
        bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere

        HOISTED OUT OF THE REINTERPRET BRANCH, 2026-09-06. It was placed inside
        the final `else` -- the generic typecast -- so it served `String(p)[2]`
        over a pointer and NOT `String(s)[2]` over a string, which takes the
        passthrough branch at the top of this arm and is the spelling ordinary
        code actually writes. `AnsiString(s)[2]` worked throughout, so the two
        spellings disagreed exactly as this arm's own header says they must not.
        Confirmed against the PINNED compiler, so it predates today's change.
        A fix placed on one branch of a four-branch arm is the same defect as a
        fix placed on one door of four.
        refactor-p-five-dispatch-sites-for-one-named-type-cast }
      if CurTok.Kind = tkLBrack then
      begin
        castTk := IntToTypeKind(ASTTk[CurASTNode]);
        CurASTNode := ParseClassRecordSelectors(CurASTNode, REC_NONE, castTk);
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
      end;
    end;
    tkIdent:
    begin
      name := CurTok.SVal;

      if CaseEqual(name, 'await') and CurProcIsAsync then
      begin
        { `await E` as an expression. Binds tightly (a unary/primary operand, like
          Python) so `await f() + 1` is `(await f()) + 1`. STACKFUL: documentary —
          AN_AWAIT lowers straight to its operand; the awaited call suspends on its
          own via the reactor/CoYield. STACKLESS (later): the transform split point. }
        Next;
        ParseFactor;
        node := AllocNode(AN_AWAIT);
        ASTLeft[node] := CurASTNode;
        ASTTk[node]   := Ord(LastExprTk);
        CurASTNode := node;
        Exit;
      end;
      if NilPyUserCode and (name = '__name__') then
      begin
        { compiled as the main program, so __name__ is always "__main__". }
        Next;
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := StoredName('__main__'); ASTSLen[node] := 8;
        ASTTk[node] := Ord(tyString);
        CurASTNode := node; LastExprTk := tyString;
        Exit;
      end;
      if NilPyUserCode and (name = '__file__') then
      begin
        { __file__ — derived from the RESOLVED executable at run time, never
          from the source path the compiler happened to see, which would leak
          the build environment into every shipped binary.
          decide-nilpy-dunder-file-for-a-compiled-program

          MAIN module: the executable itself, so os.path.exists(__file__) is
          True. IMPORTED module: <exe_dir>/<module>.py, a VIRTUAL path — no
          file is there, but os.path.dirname(os.path.abspath(__file__)), the
          only form real code uses, is the executable's directory for every
          module. Both are the freezer convention (PyInstaller/cx_Freeze).

          CurrentUnitIdx is the seam: >= 0 means "parsing an imported unit",
          which is the same test every other main-module-only NilPy rule uses. }
        Next;
        if CurrentUnitIdx >= 0 then
        begin
          idx := FindProc('pysys_module_file');
          if idx < 0 then
            Error('Nil Python: pylib (pysys_module_file) not loaded');
          valNode := AllocNode(AN_STR_LIT);
          ASTSOffset[valNode] :=
            StoredName(LowerCase(Strs[CurrentUnitIdx].Text) + '.py');
          ASTSLen[valNode] := Length(Strs[CurrentUnitIdx].Text) + 3;
          ASTTk[valNode] := Ord(tyString);
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := valNode;
          ASTRight[argSeq] := -1;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := idx;
          ASTTk[node] := Ord(tyAnsiString);
          ASTLeft[node] := argSeq;
          CurASTNode := node; LastExprTk := tyAnsiString;
          Exit;
        end;
        node := AllocNode(AN_CALL);
        idx := FindProc('pysys_file');
        if idx < 0 then Error('Nil Python: pylib (pysys_file) not loaded');
        ASTIVal[node] := idx; ASTTk[node] := Ord(tyAnsiString); ASTLeft[node] := -1;
        CurASTNode := node; LastExprTk := tyAnsiString;
        Exit;
      end;
      if NilPyUserCode and (name = 'pystr_of') and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { f-string hole: the LEXER desugars {x} to pystr_of(x), so the semantic
          rewrites str()/print() apply to a CLASS argument (Exception -> .msg,
          container -> repr) never fired here — an exception or a list inside
          an f-string rendered as an empty string
          (feature-nilpy-exception-message-text). Parse the argument; when a
          class rewrite applies the result is already a string, so the
          pystr_of call is dropped (it is the identity on strings). Any other
          argument type REWINDS and takes the ordinary overload path,
          unchanged byte for byte. }
        intBaseArg := TokPos;            { rewind point: CurTok = pystr_of }
        { park the hoist queue across the TRIAL parse — see the len() intercept
          below for what a discarded parse's leftover hoists do }
        { A trial parse REGISTERS as well as queues: a lambda in this argument
          runs RegisterProc('$pylam'+N) and pushes PyPendLam*, and the rewind
          below undid neither -- so the abandoned attempt left an orphan proc
          whose body was still compiled and emitted (measured: +1 proc and
          ~350 B of dead code per lambda inside a len()/f-string argument,
          scaling linearly). Nothing was WRONG, only because PyLamSeq is
          monotonic so the retry mints a fresh name instead of colliding; a
          construct named from the SOURCE would have duplicated.
          feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
        trialProcMark := ProcCount;
        trialLamMark  := PyPendLamCount;
        { SymCount is the table a rewound trial parse dirties MOST -- measured at
          +6 for a single comprehension, +1 for an ordinary temp -- and it was
          the one missing from this ticket's inherited rollback list, which named
          seven tables that never move and omitted the three that do.
          SymRollbackTo already existed and simply was not called here; the
          FrameSize restore is its pair, exactly as at the routine-exit site. }
        trialSymMark   := SymCount;
        trialFrameMark := FrameSize;
        lenSavedHoist := PyHoistPark;
        Next; Expect(tkLParen, '('); ParseArgExpr;
        lenTrialHoist := PyHoistPark;
        PyHoistRestore(lenSavedHoist);
        if IntToTypeKind(ASTTk[CurASTNode]) = tyClass then
        begin
          atRecv := ResolveNodeRec(CurASTNode);
          if atRecv >= REC_UCLASS_BASE then
          begin
            { __str__/__repr__ if declared, else an Exception's .msg — the one
              PyClassStrNode decision. This site used to test Exception FIRST
              and read .msg unconditionally, so a user __str__ on an exception
              subclass never ran and an f-string rendered the constructor
              argument instead
              (bug-nilpy-user-str-dunder-on-an-exception-subclass-is-ignored). }
            atDflt := PyClassStrNode(CurASTNode, atRecv - REC_UCLASS_BASE);
            if atDflt >= 0 then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              Expect(tkRParen, ')');
              CurASTNode := atDflt; LastExprTk := tyAnsiString;
              Exit;
            end;
            procIdx := -1;
            if atRecv - REC_UCLASS_BASE = FindUClass('TPyList') then
              procIdx := FindProc('pylist_repr')
            else if atRecv - REC_UCLASS_BASE = FindUClass('TPyDict') then
              procIdx := FindProc('pydict_repr')
            else
              { any OTHER user class: CPython's `<__main__.N object at 0x...>`,
                and 'None' for a nil handle — a CLASS-TYPED None, which is what
                a method returning `self` on one path and None on another
                yields. Without it an f-string hole fell through to the ordinary
                overload path and rendered the instance HANDLE as an integer,
                the same arm PyReprContainer had for print().
                bug-nilpy-str-of-a-plain-instance-prints-the-handle-and-a-class-typed-none-prints-zero }
              procIdx := FindProc('pyobj_str_of');
            if procIdx >= 0 then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
              node := AllocNode(AN_CALL);
              ASTIVal[node] := procIdx; ASTTk[node] := Ord(tyAnsiString);
              ASTLeft[node] := argSeq;
              Expect(tkRParen, ')');
              CurASTNode := node; LastExprTk := tyAnsiString;
              Exit;
            end;
          end;
        end;
        { no class rewrite: rewind and take the ordinary overload path }
        ProcRollbackTo(trialProcMark);
        PyPendLamCount := trialLamMark;
        SymRollbackTo(trialSymMark);
        FrameSize := trialFrameMark;
        TokPos := intBaseArg - 1; Next;
      end;
      { ...unless the program declares its own `len`, which REPLACES the
        builtin in Python. A name-keyed intrinsic never consults the symbol
        table, so it could not notice the user's def and the call went to the
        builtin silently (bug-nilpy-user-def-does-not-shadow-a-pylib-builtin).
        Checked here rather than inside, so the dunder rewrite below does not
        run either. }
      if NilPyUserCode and CaseEqual(name, 'len') and (not PyUserShadowsProc(name)) and
         (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { A class that defines `__len__` must be measured BY IT:
          `len(C())` otherwise falls through to len's ordinary Pascal
          overloads (TPyList/TPyDict/TPyBytes/AnsiString/Variant), none of
          which match a plain class instance -- yet the compiler's overload
          matcher still silently picks SOME overload (observed: the
          TPyList-only one, reading FLen off whatever bytes happen to sit
          at that offset in the instance -- a plausible-looking but WRONG
          number, no diagnostic
          (bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic).
          Parse the argument; a pylib CONTAINER class (TPyList/TPyDict/
          TPyBytes, which DO have a matching overload) REWINDS and takes the
          ordinary overload path unchanged. Any OTHER class -- with or
          without `__len__` -- is handled HERE and never rewound: the
          overload matcher's silent-wrong-pick for an unmatched tyClass
          argument is not safe to fall back on, unlike a genuinely absent
          overload for a scalar type. First attempt rewound unconditionally
          and depended on which OTHER classes happened to exist elsewhere in
          the same file for whether the no-`__len__` case raised or read
          garbage -- confirmed with PXXDBG=a.ir: the same wrong proc index
          got called either way; it only LOOKED fixed by coincidence. }
        intBaseArg := TokPos;
        { PARK the hoist queue across this TRIAL parse. The argument is parsed
          to learn its TYPE and, for most shapes, thrown away and re-parsed
          below — but a parse has SIDE EFFECTS: a string method on a call
          result queues a hidden-temp assignment, and the discarded parse's
          copy stayed in the queue and was emitted. So `len(f.read().upper())`
          read the file TWICE at run time — once for the abandoned AST and once
          for the real one — and the second read got the empty string a
          consumed file returns: len answered 0, exactly as if the file had
          been empty, and `.split("\n")` on it answered 1.
          Parked on a FRESH chain rather than by remembering the head, for the
          reason PyParseMethod records: PySeqAppend mutates the saved chain's
          tail in place, so a plain restore cannot unlink anything.
          bug-nilpy-len-of-a-string-method-on-a-file-read-answers-zero }
        { A trial parse REGISTERS as well as queues: a lambda in this argument
          runs RegisterProc('$pylam'+N) and pushes PyPendLam*, and the rewind
          below undid neither -- so the abandoned attempt left an orphan proc
          whose body was still compiled and emitted (measured: +1 proc and
          ~350 B of dead code per lambda inside a len()/f-string argument,
          scaling linearly). Nothing was WRONG, only because PyLamSeq is
          monotonic so the retry mints a fresh name instead of colliding; a
          construct named from the SOURCE would have duplicated.
          feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
        trialProcMark := ProcCount;
        trialLamMark  := PyPendLamCount;
        { SymCount is the table a rewound trial parse dirties MOST -- measured at
          +6 for a single comprehension, +1 for an ordinary temp -- and it was
          the one missing from this ticket's inherited rollback list, which named
          seven tables that never move and omitted the three that do.
          SymRollbackTo already existed and simply was not called here; the
          FrameSize restore is its pair, exactly as at the routine-exit site. }
        trialSymMark   := SymCount;
        trialFrameMark := FrameSize;
        lenSavedHoist := PyHoistPark;
        Next; Expect(tkLParen, '('); ParseArgExpr;
        lenTrialHoist := PyHoistPark;
        PyHoistRestore(lenSavedHoist);
        if IntToTypeKind(ASTTk[CurASTNode]) = tyClass then
        begin
          atRecv := ResolveNodeRec(CurASTNode);
          { TPyRange joins the pylib container classes here: it HAS a matching
            len() overload, so it rewinds into the ordinary overload path like
            they do. Without it a range fell into the no-__len__ arm below and
            `len(range(3))` raised "not a container". }
          { …unless the class OVERRIDES `__len__`, in which case it is that
            method CPython calls and this one has to as well. The container
            test above is by KIND, so a `dict` subclass matched it and went
            straight to pylib's count() — `len(c)` was right by luck (the
            override delegated) and would have been silently wrong for any
            override that did anything else.
            bug-n-a-builtin-subclass-subscript-operator-skips-the-override }
          if (atRecv >= REC_UCLASS_BASE) and
             (PyRecOverridesDunder(atRecv, '__len__') or
              ((not PyRecIsCls(atRecv, 'TPyList')) and
               (not PyRecIsCls(atRecv, 'TPyDict')) and
               (not PyRecIsCls(atRecv, 'TPyRange')) and
               (not PyRecIsCls(atRecv, 'TPyBytes')))) then
          begin
            { a CURSOR: CPython answers `object of type 'map' has no len()`,
              not a generic "not a container". Same runtime-raise shape as the
              no-__len__ arm below, just with the accurate message — and it is
              the one row going lazy deliberately makes stricter. }
            if (FindUClass('TPyIter') >= 0) and
               (atRecv = REC_UCLASS_BASE + FindUClass('TPyIter')) then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              prevTok := FindProc('pyiter_no_len');
              if prevTok < 0 then Error('Nil Python: pylib (pyiter_no_len) not loaded');
              atDflt := AllocNode(AN_ARG);
              ASTLeft[atDflt] := CurASTNode;
              ASTRight[atDflt] := -1;
              Expect(tkRParen, ')');
              atRecv := AllocNode(AN_CALL);
              ASTIVal[atRecv] := prevTok;
              ASTTk[atRecv] := Ord(tyInt64);
              ASTLeft[atRecv] := atDflt;
              CurASTNode := atRecv; LastExprTk := tyInt64;
              Exit;
            end;
            atFld := FindUMeth(atRecv - REC_UCLASS_BASE, '__len__');
            if atFld >= 0 then
            begin
              PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
              atDflt := PyCallMeth1(atRecv - REC_UCLASS_BASE,
                                    PyRawName(UMthNOff[atFld], UMthNLen[atFld]),
                                    CurASTNode, -1);
              if atDflt < 0 then Error('Nil Python: len() could not call __len__');
              Expect(tkRParen, ')');
              CurASTNode := atDflt; LastExprTk := IntToTypeKind(ASTTk[atDflt]);
              Exit;
            end;
            { no __len__ on a non-container class: a genuine RUNTIME error
              (try/except around this must still compile and run its
              handler), not a compile-time Error() or a rewind into the
              overload matcher's unsafe fallback. }
            { the argument's own setup still runs, as it did before this parse
              was parked — only its VALUE is unused }
            PyHoistMerge(lenSavedHoist, lenTrialHoist);
            prevTok := FindProc('PyNotContainerError');
            if prevTok < 0 then Error('Nil Python: pylib (PyNotContainerError) not loaded');
            Expect(tkRParen, ')');
            atDflt := AllocNode(AN_CALL);
            ASTIVal[atDflt] := prevTok;
            ASTTk[atDflt] := Ord(tyInt64);
            ASTLeft[atDflt] := -1;
            CurASTNode := atDflt; LastExprTk := tyInt64;
            Exit;
          end;
        end;
        { a pylib container class, or a non-class argument: rewind and take
          the ordinary overload path, unchanged byte for byte }
        ProcRollbackTo(trialProcMark);
        PyPendLamCount := trialLamMark;
        SymRollbackTo(trialSymMark);
        FrameSize := trialFrameMark;
        TokPos := intBaseArg - 1; Next;
      end;
      { hex/bin/oct of an ARBITRARY-PRECISION int. Python's take any width, while
        pylib's are `function hex(n: Int64)`, so once a value has grown past a
        machine word (or came from a wide literal) the call simply has no
        matching overload — measured today, before the promotion default even
        lands: `x = 1180591620717411303424; hex(x)` fails to compile.

        A `PromoInt` OVERLOAD in pylib cannot be written: a PromoInt PARAMETER
        cannot be handed to the promo runtime at all, and `shr` / `Integer(n)`
        on one are both broken, so the digit loop is unwritable in Pascal
        source (bug-a-promoint-shr-yields-nothing-and-a-machine-int-cast-yields-
        the-slot-address). So this lowers to promocore's own base conversion,
        which works off the bignum limbs directly — the same shape `**` uses for
        pypow_v and `writeln` uses for PXXPromoToStr.

        Guarded by PyUserShadowsProc like every other name-keyed lowering: an
        IR-level rewrite doing exactly this without the guard is what made a
        user `def len(x)` unreachable
        (bug-nilpy-user-def-len-of-a-container-still-binds-the-builtin).

        A NON-promo argument REWINDS to the ordinary Int64 overload, so native
        values keep today's code path untouched. }
      if NilPyUserCode and (not PyUserShadowsProc(name)) and
         (CaseEqual(name, 'hex') or CaseEqual(name, 'bin') or CaseEqual(name, 'oct')) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        intBaseArg := TokPos;
        { same parked TRIAL parse as the two intercepts above }
        { A trial parse REGISTERS as well as queues: a lambda in this argument
          runs RegisterProc('$pylam'+N) and pushes PyPendLam*, and the rewind
          below undid neither -- so the abandoned attempt left an orphan proc
          whose body was still compiled and emitted (measured: +1 proc and
          ~350 B of dead code per lambda inside a len()/f-string argument,
          scaling linearly). Nothing was WRONG, only because PyLamSeq is
          monotonic so the retry mints a fresh name instead of colliding; a
          construct named from the SOURCE would have duplicated.
          feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
        trialProcMark := ProcCount;
        trialLamMark  := PyPendLamCount;
        { SymCount is the table a rewound trial parse dirties MOST -- measured at
          +6 for a single comprehension, +1 for an ordinary temp -- and it was
          the one missing from this ticket's inherited rollback list, which named
          seven tables that never move and omitted the three that do.
          SymRollbackTo already existed and simply was not called here; the
          FrameSize restore is its pair, exactly as at the routine-exit site. }
        trialSymMark   := SymCount;
        trialFrameMark := FrameSize;
        lenSavedHoist := PyHoistPark;
        Next; Expect(tkLParen, '('); ParseArgExpr;
        lenTrialHoist := PyHoistPark;
        PyHoistRestore(lenSavedHoist);
        if TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          PyHoistMerge(lenSavedHoist, lenTrialHoist);   { the trial AST is kept }
          if CaseEqual(name, 'hex') then i := 16
          else if CaseEqual(name, 'oct') then i := 8
          else i := 2;
          procIdx := FindProc('PXXPromoToBase');
          if procIdx < 0 then
            Error('Nil Python: promocore (PXXPromoToBase) not loaded');
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          valNode := AllocNode(AN_INT_LIT);
          ASTIVal[valNode] := i;
          ASTTk[valNode] := Ord(tyInteger);
          argSeq2 := AllocNode(AN_ARG);
          ASTLeft[argSeq2] := valNode;
          ASTRight[argSeq2] := -1;
          ASTRight[argSeq] := argSeq2;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyAnsiString);
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := tyAnsiString;
          Exit;
        end;
        { a machine-width argument: rewind, take the ordinary overload }
        ProcRollbackTo(trialProcMark);
        PyPendLamCount := trialLamMark;
        SymRollbackTo(trialSymMark);
        FrameSize := trialFrameMark;
        TokPos := intBaseArg - 1; Next;
      end;
      if NilPyUserCode and (name = 'int') and (not PyUserShadowsProc(name)) then
      begin
        Next; Expect(tkLParen, '('); ParseArgExpr;
        { `int(s, base)` — the two-argument radix form. A separate pylib
          function rather than another intrinsic, because it must RAISE
          ValueError on a bad parse (pylib declares the Python exception
          hierarchy so it can), and the -200 intrinsic has no way to fail. }
        if CurTok.Kind = tkComma then
        begin
          intBaseArg := CurASTNode;
          Next;
          ParseArgExpr;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := FindProc('pyint_parse');
          if ASTIVal[node] < 0 then Error('Nil Python: pylib (pyint_parse) not loaded');
          ASTTk[node] := Ord(tyInt64);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := intBaseArg;
          intBaseArg := AllocNode(AN_ARG); ASTLeft[intBaseArg] := CurASTNode;
          ASTRight[argSeq] := intBaseArg;
          ASTRight[intBaseArg] := -1;
          ASTLeft[node] := argSeq;
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := tyInt64;
          Exit;
        end;
        Expect(tkRParen, ')');
        { int() of an ARBITRARY-PRECISION int is the IDENTITY in Python, and it
          must STAY arbitrary precision — `int(2**70)` is 2**70, not a narrowed
          one. The -200 intrinsic's parameter is not a promo, and this site
          hand-builds its call (project_findproc_by_name_ignores_overloads), so
          the promo arrived as its SLOT ADDRESS and printed as a small number.
          Handing the argument straight back is both correct and free. }
        if TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        node := AllocNode(AN_CALL);
        { int(float) truncates toward zero, which is exactly the -203 Trunc
          intrinsic -- reuse it rather than duplicating its SSE lowering. Every
          other argument type goes to -200, whose lowering handles string
          (parse the text), variant (unbox) and int/bool (identity). }
        { A user class declaring `__int__`. Python asks the object; this asked
          nothing and handed the -200 intrinsic an object HANDLE, so
          `int(V(4))` printed 129729065648272 — the pointer. Silent, and the
          class plainly declares the member. The float twin is in float()'s
          arm below. bug-nilpy-int-and-float-ignore-their-dunders }
        if (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
           (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) and
           (not PyRecIsPylibOwnClass(ResolveNodeRec(CurASTNode))) then
        begin
          if FindUMeth(ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE, '__int__') >= 0 then
            node := PyCallMeth1(ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE,
                                '__int__', CurASTNode, -1)
          else
            { no __int__ at all: CPython raises TypeError naming the class, and
              at RUN time, so `try: int(o) / except TypeError:` still compiles —
              the trade PyNoSetitemError already makes }
            node := PyClassErrCallNode('PyNoIntError',
                                       ResolveNodeRec(CurASTNode) - REC_UCLASS_BASE);
          if node >= 0 then
          begin
            CurASTNode := node;
            LastExprTk := IntToTypeKind(ASTTk[node]);
            Exit;
          end;
        end;
        { The NODE's type, not LastExprTk. `int(7/2)` printed
          4615063718147915776 -- 3.5's BIT PATTERN read as an integer -- because
          LastExprTk after an operator expression is the last FACTOR's type
          (tyInteger for the `2`), so the float arm was skipped and the -200
          intrinsic took the raw payload. The identical `x = 7/2; int(x)` was
          correct, which is what makes this a side-channel bug rather than an
          int() one: an ident leaves LastExprTk agreeing with the node.
          Take the kind from the VALUE, not from a side channel -- the rule
          project_variant_store_kind_came_from_the_ast_not_the_value records.
          bug-nilpy-int-of-a-division-reads-the-doubles-bits }
        if TypeIsFloat(IntToTypeKind(ASTTk[CurASTNode])) or TypeIsFloat(LastExprTk) then
        begin
          ASTIVal[node] := -203; ASTTk[node] := Ord(tyInt64);
        end
        else if IntToTypeKind(ASTTk[CurASTNode]) = tyVariant then
        begin
          { int(<variant>) — the ordinary shape for a module-scope binding, a
            container element or an unannotated parameter. The variant may hold
            an arbitrary-precision int, so the result cannot be Int64 either:
            typed VARIANT and lowered to pylib's pyint_v, which passes a
            VT_PROMO_INT64 payload straight through and narrows nothing.
            (bug-nilpy-int-of-a-variant-held-bignum-raises — `int(2**64)` used
            to abort with EVariantError, which is not a value Python has.) }
          ASTIVal[node] := -200; ASTTk[node] := Ord(tyVariant);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
          LastExprTk := tyVariant;
          Exit;
        end
        else if (IntToTypeKind(ASTTk[CurASTNode]) = tyString) or
                (IntToTypeKind(ASTTk[CurASTNode]) = tyAnsiString) then
        begin
          { int(<str>) is where a value WIDER THAN Int64 actually enters a
            program — the digits are data, so nothing about the parse can be
            decided at compile time — and Python's int has no width. So it is
            typed a PROMOTABLE INT, the same type a wide LITERAL already gets a
            few hundred lines up, which is what makes `n = int(s)` then `n + 1`
            and `str(n)` all stay exact. Typed HERE and not patched during
            lowering: `write` reads its argument's type before lowering the
            argument, so a retype at lowering lands too late for the one
            consumer that most needs it
            (bug-nilpy-int-of-a-long-decimal-string-narrows).
            tyChar is deliberately NOT here: a one-character string cannot
            exceed 9, so it keeps the cheaper Int64 path. }
          ASTIVal[node] := -200; ASTTk[node] := Ord(tyPromoInt64);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
          LastExprTk := tyPromoInt64;
          Exit;
        end
        else
        begin
          { tyInt64, not tyInteger: NilPy's int is a 64-bit cell. The -200
            result is a full 64-bit value; typing it 32-bit made an inferred
            local truncate it at the store (`start = int(vm.pop())` of
            maxint read back as -1 — uforth's DO index). }
          ASTIVal[node] := -200; ASTTk[node] := Ord(tyInt64);
        end;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyInt64;
        Exit;
      end
      else if isNilPy and ((name = 'hasattr') or (name = 'getattr')) then
      begin
        { Resolved against the receiver's DECLARED fields — see PyAttrFieldIdx
          for why a compile-time answer is the right shape here. }
        atIsGet := name = 'getattr';
        Next; Expect(tkLParen, '(');
        ParseExpr;
        atRecv := CurASTNode;
        { A COMPUTED name — `getattr(self, "do_" + verb)` — cannot be answered
          from the receiver's declared fields at compile time, which is what
          the whole path below does. Route it to the runtime resolver instead
          of refusing it. }
        { A string LITERAL is only the literal path when the whole argument is
          that literal — `"zz" + "z"` starts with a string token and is still a
          computed name, and reading it as the literal choked on the '+'. }
        if (CurTok.Kind = tkComma) and (TokPos < TokCount) and
           ((Tokens[TokPos].Kind <> tkString) or
            ((TokPos + 1 < TokCount) and
             (not (Tokens[TokPos + 1].Kind in [tkComma, tkRParen])))) then
        begin
          Expect(tkComma, ',');
          ParseExpr;
          atFld := CurASTNode;             { the name EXPRESSION }
          atDflt := -1;
          if CurTok.Kind = tkComma then
          begin
            Next;
            ParseExpr;
            atDflt := CurASTNode;
          end;
          Expect(tkRParen, ')');
          CurASTNode := PyMakeDynAttrByExpr(atRecv, atFld, atDflt, not atIsGet);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        atName := PyParseAttrName;
        atFld := PyAttrFieldIdx(atRecv, atName);
        { hasattr asks a WIDER question than "is it a declared field" — a method
          is an attribute too. Answered from the same tables the call uses; see
          PyAttrExists. Only the hasattr ANSWER moves: `atFld` stays the field
          index, because getattr builds a field read out of it and a method
          index there would be read as an offset.
          bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false }
        atExists := (atFld >= 0) or ((not atIsGet) and PyAttrExists(atRecv, atName));
        { a PROPERTY is neither a field nor a dynamic attribute: getattr must
          build the read `o.p` builds, or it raises AttributeError for a name
          hasattr (which does see properties) has just said yes to
          (bug-nilpy-hasattr-does-not-see-a-property) }
        atProp := -1;
        if atFld < 0 then atProp := PyMakePropRead(atRecv, atName);
        if atProp >= 0 then atExists := True;
        atDflt := -1;
        if CurTok.Kind = tkComma then
        begin
          Next;
          ParseExpr;
          atDflt := CurASTNode;
        end;
        Expect(tkRParen, ')');
        if atIsGet and (atProp >= 0) then
        begin
          CurASTNode := atProp;
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        { An undeclared attribute may be set DYNAMICALLY at run time (on a
          variant OR a class instance), which a compile-time field check cannot
          see — resolve hasattr/getattr through the dynamic-attribute store. A
          getattr WITH a default keeps the old behaviour (return the default for
          an unknown attribute) rather than the store, which is what the
          censused getattr(e, "errno", 1) probes want. }
        if (not atExists) and (not (atIsGet and (atDflt >= 0))) and
           (IntToTypeKind(ASTTk[atRecv]) in [tyVariant, tyClass]) then
        begin
          { A VARIANT receiver has no static class, so atFld < 0 here does NOT
            mean "not declared" — it means "not knowable yet". Answering the
            dynamic store alone reported False for a field that is declared and
            reads fine on the same receiver: `box[0].x` worked while
            `hasattr(box[0], "x")` said False, silently, and the idiom that
            breaks is the guard `if not hasattr(o, "x")`, so control went down
            the wrong branch rather than raising
            (bug-nilpy-hasattr-on-a-variant-receiver-always-answers-false).
            A tyCLASS receiver keeps today's answer exactly: its class WAS
            resolved, so atFld < 0 there genuinely means undeclared. }
          if (not atIsGet) and (IntToTypeKind(ASTTk[atRecv]) = tyVariant) then
          begin
            atRecv := PyEvalOnce(atRecv);   { read once per candidate + once for the tag }
            atDflt := PyHasAttrRuntimeChain(atRecv, atName);
          end
          else
            atDflt := -1;
          if atIsGet then CurASTNode := PyMakeDynAttrGet(atRecv, atName)
          else
          begin
            { a VARIANT receiver keeps its tag: a class held as a value has its
              attributes in the bind registry, and the unwrapped-pointer form
              would key the question on the RTTI blob's address and answer False
              (bug-nilpy-class-attribute-through-a-class-reference-reads-garbage) }
            { the WIDE predicates, not the store-only ones: hasattr must answer
              True for a method and for a name the class's __getattr__ answers
              for, which is CPython's definition of it (getattr does not raise).
              bug-nilpy-getattr-dunder-not-supported }
            if IntToTypeKind(ASTTk[atRecv]) = tyVariant then
              idx := FindProc('pydynattr_has_any_v')
            else
              idx := FindProc('pydynattr_hasattr');
            if idx < 0 then Error('Nil Python: pylib (pydynattr_hasattr) not loaded');
            argSeq := AllocNode(AN_ARG);
            if IntToTypeKind(ASTTk[atRecv]) = tyVariant then ASTLeft[argSeq] := atRecv
            else ASTLeft[argSeq] := PyMakeObjPtr(atRecv);
            argSeq2 := AllocNode(AN_STR_LIT);
            ASTSOffset[argSeq2] := StoredName(atName); ASTSLen[argSeq2] := Length(atName);
            ASTTk[argSeq2] := Ord(tyString);
            argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := argSeq2; ASTRight[argSeq3] := -1;
            ASTRight[argSeq] := argSeq3;
            node := AllocNode(AN_CALL); ASTIVal[node] := idx;
            ASTTk[node] := Ord(tyBoolean); ASTLeft[node] := argSeq;
            { ...or the receiver's RUN-TIME class declares it }
            if atDflt >= 0 then
            begin
              argSeq2 := AllocNode(AN_BINOP);
              ASTIVal[argSeq2] := Ord(tkOr);
              ASTLeft[argSeq2] := node; ASTRight[argSeq2] := atDflt;
              ASTTk[argSeq2] := Ord(tyBoolean);
              node := argSeq2;
            end;
            CurASTNode := node;
          end;
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        if not atIsGet then
        begin
          node := AllocNode(AN_INT_LIT);
          if atExists then ASTIVal[node] := 1 else ASTIVal[node] := 0;
          ASTTk[node] := Ord(tyBoolean);
          CurASTNode := node;
          LastExprTk := tyBoolean;
          Exit;
        end;
        { getattr WITH a default on an undeclared attribute of a class/variant:
          the attribute may have been set DYNAMICALLY, so return the stored value
          if present else the default — `pydynattr_has(o,n) ? pydynattr_get(o,n) :
          default`. Without the store check this always returned the default, so
          `getattr(vm, "_x", None)` reported None even after `vm._x = ...`. }
        if (atFld < 0) and (atDflt >= 0) and
           (IntToTypeKind(ASTTk[atRecv]) in [tyVariant, tyClass]) then
        begin
          { same tag-preserving choice as the hasattr branch above }
          { the wide predicates, same reason as the hasattr arm above — a
            default must not win over a value __getattr__ would have produced }
          if IntToTypeKind(ASTTk[atRecv]) = tyVariant then
            idx := FindProc('pydynattr_has_any_v')
          else
            idx := FindProc('pydynattr_hasattr');
          if idx < 0 then Error('Nil Python: pylib (pydynattr_hasattr) not loaded');
          argSeq := AllocNode(AN_ARG);
          if IntToTypeKind(ASTTk[atRecv]) = tyVariant then ASTLeft[argSeq] := atRecv
          else ASTLeft[argSeq] := PyMakeObjPtr(atRecv);
          argSeq2 := AllocNode(AN_STR_LIT);
          ASTSOffset[argSeq2] := StoredName(atName); ASTSLen[argSeq2] := Length(atName);
          ASTTk[argSeq2] := Ord(tyString);
          argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := argSeq2; ASTRight[argSeq3] := -1;
          ASTRight[argSeq] := argSeq3;
          node := AllocNode(AN_CALL); ASTIVal[node] := idx;
          ASTTk[node] := Ord(tyBoolean); ASTLeft[node] := argSeq;
          { box the default into a variant so both ternary branches share the
            variant representation (a raw scalar branch would be misread) }
          idx := FindProc('pyvar_box');
          if idx < 0 then Error('Nil Python: pylib (pyvar_box) not loaded');
          argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := atDflt; ASTRight[argSeq2] := -1;
          argSeq3 := AllocNode(AN_CALL); ASTIVal[argSeq3] := idx;
          ASTTk[argSeq3] := Ord(tyVariant); ASTLeft[argSeq3] := argSeq2;
          atDflt := argSeq3;
          { the value branch and the boxed default, joined by a ternary typed variant }
          argSeq2 := AllocNode(AN_PAIR);
          ASTLeft[argSeq2] := PyMakeDynAttrGet(atRecv, atName);
          ASTRight[argSeq2] := atDflt;
          argSeq3 := AllocNode(AN_TERNARY);
          ASTLeft[argSeq3] := node; ASTRight[argSeq3] := argSeq2;
          ASTTk[argSeq3] := Ord(tyVariant);
          CurASTNode := argSeq3;
          LastExprTk := tyVariant;
          Exit;
        end;
        if atFld >= 0 then
        begin
          { the field exists: an ordinary field read }
          node := AllocNode(AN_FIELD);
          ASTLeft[node] := atRecv;
          ASTSOffset[node] := StoredName(atName);
          ASTSLen[node] := Length(atName);
          ASTTk[node] := UFldTk[atFld];
          CurASTNode := node;
          LastExprTk := IntToTypeKind(UFldTk[atFld]);
          Exit;
        end;
        if atDflt < 0 then
          Error('Nil Python: getattr on an attribute this type does not declare needs a default');
        CurASTNode := atDflt;
        LastExprTk := IntToTypeKind(ASTTk[atDflt]);
        Exit;
      end
      else if isNilPy and (name = 'setattr') and (not PyUserShadowsProc('setattr')) then
      begin
        { The third member of the attribute trio. hasattr and getattr have been
          here since the protocol landed and setattr was simply absent —
          `undefined variable (setattr)` — so the read half of a dynamic
          attribute was expressible and the write half was not, on a receiver
          whose `o.name = v` form already writes through the same store.
          bug-nilpy-setattr-is-absent }
        Next; Expect(tkLParen, '(');
        ParseExpr;
        atRecv := CurASTNode;
        { A COMPUTED name — `setattr(o, "f_" + k, v)`, which is the shape that
          makes setattr worth having at all. Same literal-vs-expression test
          getattr uses: a string TOKEN is the literal path only when the whole
          argument is that token. }
        if (CurTok.Kind = tkComma) and (TokPos < TokCount) and
           ((Tokens[TokPos].Kind <> tkString) or
            ((TokPos + 1 < TokCount) and
             (not (Tokens[TokPos + 1].Kind in [tkComma, tkRParen])))) then
        begin
          Expect(tkComma, ',');
          ParseExpr;
          atFld := CurASTNode;             { the name EXPRESSION }
          Expect(tkComma, ',');
          ParseExpr;
          atDflt := CurASTNode;            { the value }
          Expect(tkRParen, ')');
          CurASTNode := PyMakeDynAttrSetByExpr(atRecv, atFld, atDflt);
          LastExprTk := tyUnknown;
          Exit;
        end;
        atName := PyParseAttrName;         { consumes the ',' and the literal }
        Expect(tkComma, ',');
        ParseExpr;
        atDflt := CurASTNode;              { the value }
        Expect(tkRParen, ')');
        atFld := PyAttrFieldIdx(atRecv, atName);
        if atFld >= 0 then
        begin
          { a DECLARED field: the ordinary field store, so setattr and
            `o.name = v` write the same slot rather than two }
          node := AllocNode(AN_FIELD);
          ASTLeft[node] := atRecv;
          ASTSOffset[node] := StoredName(atName);
          ASTSLen[node] := Length(atName);
          ASTTk[node] := UFldTk[atFld];
          argSeq := AllocNode(AN_ASSIGN);
          ASTLeft[argSeq] := node;
          ASTRight[argSeq] := atDflt;
          CurASTNode := argSeq;
          LastExprTk := tyUnknown;
          Exit;
        end;
        CurASTNode := PyMakeDynAttrSet(atRecv, atName, PyForceVariant(atDflt));
        LastExprTk := tyUnknown;
        Exit;
      end
      { ELEVEN NilPy arms stood here -- exec, eval, open, float, map, filter,
        next, str, round, divmod and bool -- and none of them could fire.

        Every one led with NilPyUserCode, and ParseFactorCore opens with an
        unconditional `if PyExprMode then begin PyParseFactorCore; Exit; end`.
        NilPyUserCode is `isNilPy and ((CurrentUnitIdx < 0) or PyExprMode)`, so
        below that dispatch it reduces to `isNilPy and CurrentUnitIdx < 0` -- a
        NilPy compile whose MAIN PROGRAM is being parsed as Pascal, which a .npy
        cannot produce, because isNilPy is set from the root file's extension
        alone and a Python main program leaves at the Exit above.

        Measured as well as argued, in one build carrying the control and the
        measurement so a zero could not be a dead probe: `if NilPyUserCode`
        immediately above the dispatch and immediately below it, over all 827
        .npy programs in test/ -- 96762 fires above, 0 below.

        NilPy source is parsed by pyparser.inc's own PyParseFactorCore, which
        has live copies of these. Removing them changed no program's output.
        Do not add a NilPy arm here; add it there. The longer argument, and the
        nine isNilPy arms deleted for the same reason in 2026-08, are in the
        note further down this procedure.
        bug-p-nilpy-diagnostics-exist-on-both-arms-of-the-parsefactorcore-carve-out }
      else if (CaseEqual(name, 'trunc') or CaseEqual(name, 'round') or
               CaseEqual(name, 'frac') or CaseEqual(name, 'int')) and
              (not PyUserShadowsProc(name)) and
              (Tokens[TokPos].Kind = tkLParen) then
      begin
        { only a call `name(...)` is the float intrinsic; a bare identifier of the
          same name (e.g. the FRAC const) falls through to normal handling }
        { Float intrinsics via SSE conversions (specialId 203-206):
          Trunc -> Int64 (toward zero), Round -> Int64 (nearest-even),
          Frac/Int -> Double (fractional part / integer part as float). }
        if CaseEqual(name, 'trunc') then prevTok := -203
        else if CaseEqual(name, 'round') then prevTok := -204
        else if CaseEqual(name, 'frac') then prevTok := -205
        else prevTok := -206;
        Next; Expect(tkLParen, '('); ParseExpr;
        { NilPy hands these intrinsics whatever the expression's static type is,
          and an inferred local or parameter is a VARIANT. The lowering below is
          a raw SSE conversion of a double, so a variant argument converted its
          16-byte slot instead of the number it holds — `round(r * 255)` on a
          parameter printed a stack address. Unbox first. (An expression whose
          STATIC type came out non-variant can still be a variant at run time —
          `x * 255` types integer but lowers to a variant multiply — so the
          codegen's own IRTk = tyVariant check is the real backstop; this one
          only covers the plainly-typed cases.) }
        { …but the two-argument `round` must NOT be unboxed: its answer keeps the
          argument's INTNESS, and a double is where that information dies —
          `round(2 ** 70, 2)` came back as 1.18e+21. Remember the raw node and
          hand THAT to the variant-aware routine below.
          bug-nilpy-two-argument-round-of-an-int-returns-a-float }
        rndRawArg := CurASTNode;
        rndRawTk := LastExprTk;
        if isNilPy and (LastExprTk = tyVariant) then
        begin
          node := AllocNode(AN_CALL);
          ASTIVal[node] := FindProc('pyvar_to_float');
          if ASTIVal[node] < 0 then Error('Nil Python: pylib (pyvar_to_float) not loaded');
          ASTTk[node] := Ord(tyDouble);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
          ASTRight[argSeq] := -1;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
          LastExprTk := tyDouble;
        end;
        { Python's `round(x, ndigits)` — a FLOAT rounded to that many decimals,
          a different operation from the one-argument form (which yields an
          int). songformatter writes `round(pct, 2)` when normalising scores. }
        if NilPyUserCode and CaseEqual(name, 'round') and (CurTok.Kind = tkComma) then
        begin
          Next;
          rndArg := CurASTNode;
          { CPython's `round(x, n)` keeps x's TYPE: an int in, an int out,
            whatever n is. `round(6, 2)` is 6, not 6.0, and a report that
            rounds an integral total to two places printed 6.0 where every
            other implementation prints 6 — while the ONE-argument round(6)
            was right, so the two spellings disagreed with each other.
            bug-nilpy-two-argument-round-of-an-int-returns-a-float }
          rndIntArg := (rndRawTk = tyInteger) or (rndRawTk = tyInt64) or
                       (rndRawTk = tyBoolean) or TypeIsPromoInt(rndRawTk);
          rndArgTk := rndRawTk;
          rndArg := rndRawArg;               { the un-unboxed argument }
          ParseExpr;
          Expect(tkRParen, ')');
          { …and with a non-negative ndigits the rounding cannot change an
            integer at all, so the whole call is the identity. A NEGATIVE
            ndigits does round (`round(1234, -2)` is 1200, still an int) and a
            computed one is unknown here; both keep the float path below, which
            is what shipped — the int-typed answer for those needs a pylib
            routine and is recorded on the ticket. }
          { a statically-typed int with a non-negative LITERAL ndigits needs no
            call at all — rounding an integer up cannot change it. NOT a bool:
            `round(True, 2)` is 1 in CPython, an int, so the identity would keep
            a value that PRINTS as True. }
          if rndIntArg and (rndArgTk <> tyBoolean) and
             (ASTKind[CurASTNode] = AN_INT_LIT) and
             (ASTIVal[CurASTNode] >= 0) then
          begin
            CurASTNode := rndArg;
            LastExprTk := rndArgTk;
            Exit;
          end;
          { a statically-typed INT with any other ndigits: an int result, so
            `round(1234, -2)` is 1200 and not 1200.0 }
          if rndIntArg and (not TypeIsPromoInt(rndArgTk)) then
          begin
            argSeq := FindProc('pyround_int');
            if argSeq < 0 then Error('Nil Python: pylib (pyround_int) not loaded');
            node := AllocNode(AN_CALL);
            ASTIVal[node] := argSeq;
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := rndArg;
            prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := CurASTNode;
            ASTRight[prevTok] := -1;
            ASTRight[argSeq] := prevTok;
            ASTLeft[node] := argSeq;
            ASTTk[node] := Ord(tyInt64);
            CurASTNode := node;
            LastExprTk := tyInt64;
            Exit;
          end;
          { a VARIANT or a PROMO argument: the intness is a run-time fact, so the
            variant-aware routine decides — and it gets the RAW argument, before
            the float unbox that would have thrown that fact away }
          if isNilPy and ((rndRawTk = tyVariant) or TypeIsPromoInt(rndRawTk)) then
          begin
            argSeq := FindProc('pyround_v');
            if argSeq < 0 then Error('Nil Python: pylib (pyround_v) not loaded');
            node := AllocNode(AN_CALL);
            ASTIVal[node] := argSeq;
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := rndRawArg;
            prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := CurASTNode;
            ASTRight[prevTok] := -1;
            ASTRight[argSeq] := prevTok;
            ASTLeft[node] := argSeq;
            ASTTk[node] := Ord(tyVariant);
            CurASTNode := node;
            LastExprTk := tyVariant;
            Exit;
          end;
          argSeq := FindProc('pyround_n');
          if argSeq < 0 then Error('Nil Python: pylib (pyround_n) not loaded');
          node := AllocNode(AN_CALL);
          ASTIVal[node] := argSeq;
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := rndArg;
          prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := CurASTNode;
          ASTRight[prevTok] := -1;
          ASTRight[argSeq] := prevTok;
          ASTLeft[node] := argSeq;
          ASTTk[node] := Ord(tyDouble);
          CurASTNode := node;
          LastExprTk := tyDouble;
          Exit;
        end;
        Expect(tkRParen, ')');
        { round()/trunc() of an ARBITRARY-PRECISION int is the IDENTITY, same as
          int() above: rounding an integer cannot change it, and narrowing it
          would lose the precision that is the whole point. -203/-204 are raw
          SSE conversions, so a promo argument had its SLOT ADDRESS converted —
          `round(i + 1)` printed 5553816. Only the int-yielding pair: frac/int
          (-205/-206) are the float intrinsics and NilPy's own `int` is handled
          at its own site. }
        if isNilPy and ((prevTok = -203) or (prevTok = -204)) and
           TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
        begin
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
          Exit;
        end;
        { …and the same value reached through a VARIANT — a module global
          holding `2 ** 70` types tyVariant here, not promo, so the guard above
          missed it and the SSE conversion of the unboxed double answered
          -9223372036854775808. The variant routine keeps a promo exact, an int
          an int, and rounds a float half-to-even into one.
          bug-nilpy-two-argument-round-of-an-int-returns-a-float }
        if isNilPy and (prevTok = -204) and (rndRawTk = tyVariant) then
        begin
          argSeq := FindProc('pyround1_v');
          if argSeq < 0 then Error('Nil Python: pylib (pyround1_v) not loaded');
          node := AllocNode(AN_CALL);
          ASTIVal[node] := argSeq;
          prevTok := AllocNode(AN_ARG); ASTLeft[prevTok] := rndRawArg;
          ASTRight[prevTok] := -1;
          ASTLeft[node] := prevTok;
          ASTTk[node] := Ord(tyVariant);
          CurASTNode := node;
          LastExprTk := tyVariant;
          Exit;
        end;
        node := AllocNode(AN_CALL); ASTIVal[node] := prevTok;
        if (prevTok = -203) or (prevTok = -204) then ASTTk[node] := Ord(tyInt64)
        else ASTTk[node] := Ord(tyDouble);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;
      qUnit := ConsumeUnitQualifier(name);
      { A qualified member whose name Pascal RESERVES: `tk.END` is what every
        tkinter application writes, and a library cannot declare a constant
        called END, so it declares END_ and the name is mapped here. The same
        trailing-underscore convention the reserved METHOD names already use
        (set_, destroy_). Applied to the qualified form only, so an ordinary
        Pascal `unit.End` is untouched — there is no such thing. }
      if isNilPy and (qUnit >= 0) then name := PyMapReservedMember(name);
      prevTok := TokPos - 1;
      if CaseEqual(name, 'inherited') then
      begin
        CurASTNode := ParseInheritedCallAST;
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;
      { `TEnum.member` — scoped-enum member access (also legal on unscoped
        enums, FPC parity; bug-pascal-scopedenums-ignored). Folds to the
        member's ordinal. Guarded on the name not being a real symbol so a
        record var shadowing an enum type name keeps the field path. }
      if (qUnit < 0) and (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
         (FindSym(name) < 0) then
      begin
        seEtid := FindEnumType(name);
        if (seEtid >= 0) and
           FindEnumMemberOrd(seEtid, GetTokenStr(TokPos+1), seOrd) then
        begin
          Next; Next; Next;   { TEnum, '.', member }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := seOrd;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
          LastExprTk := tyInteger;
          Exit;
        end;
      end;
      { ---- SizeOf(TypeName) intrinsic: resolved at parse time to AN_INT_LIT ---- }
      if CaseEqual(name, 'sizeof') then
      begin
        Next; { consume 'SizeOf' }
        Expect(tkLParen, '(');
        { ---- SizeOf(<expression>) ----
          Everything below this block reads the operand as a NAME (optionally
          `.field` and one `[...]`), never as an expression, which is why
          `SizeOf(p^)`, `SizeOf(i + 1)`, `SizeOf(Abs(i))` and `SizeOf(@i)` were
          compile errors while `SizeOf(i)` worked. FPC takes any expression and
          answers with its static type, and that is the only portable way to ask
          what type an expression actually HAS -- there is no TypeOf to print.
          The width rules in devdocs/dev/pascal-dialect-divergences.md were
          confirmed against FPC exactly this way (`SizeOf(i + 1)` = 8 and
          `SizeOf(i shl 1)` = 4 state the promotion rule in one line each), and
          the probe could not be written against pxx.

          Dispatch, not replacement: the name path below carries a pile of hard-
          won cases (a variable's DECLARED type rather than its element type, an
          N-D subscript naming a row vs a scalar, a dynamic handle being pointer
          width) that an expression's ASTTk does not model, so it stays the
          path for anything shaped like a name. This block only decides which
          one to use, by scanning the operand's tokens to the closing ')':
          anything at bracket-depth 0 that is not an identifier or a '.' means
          the operand is an expression.

          Deliberately NOT routed here: a LITERAL operand. FPC types an integer
          literal as the smallest type that holds it (SizeOf(1) = 1,
          SizeOf(256) = 2), a real literal as Single (SizeOf(3.5) = 4) and a
          string literal by its length (SizeOf('abc') = 3) -- none of which the
          expression's own type reproduces, so routing them here would answer 8
          and 8 and 8 silently. The block just below models that rule instead,
          and the expression path is still the wrong place for a literal. }

        { ---- SizeOf(<literal>) ----
          A BARE literal, optionally signed, and nothing else: FPC types it by
          its VALUE, so the answer has nothing to do with what the expression
          parser would infer. Measured against fpc 3.2.2, and the whole table is
          pinned in test/test_sizeof_of_a_literal.pas:

            1 127 128 255 -> 1     256 32767 32768 65535 -> 2
            65536 100000  -> 4     5000000000            -> 8
            -1 -> 1   -129 -> 2    3.5 -> 4 (Single, NOT Double)
            'a' '' -> 1   'abc' -> 3 (its LENGTH -- an array[1..3] of Char)
            nil -> pointer width   True/False -> 1

          Two of those look harmless to get wrong and are wrong everywhere:
          SizeOf(3.5) is 4 because an untyped real constant is Single-typed for
          this purpose even though it promotes to Double in arithmetic, and
          SizeOf('abc') is 3 because a string literal is its own array of Char,
          not a handle.

          A SET literal is left refused. fpc's answer is inscrutable — `[1,2]`
          and `[1,200]` are both 2 — and pxx bakes 32-byte masks, so any number
          chosen here would be a guess reaching GetMem.
          feature-p-sizeof-of-a-literal }
        szScan := TokPos - 1;
        szLitNeg := (szScan >= 0) and (szScan + 1 < TokCount) and
                    (Tokens[szScan].Kind = tkMinus) and
                    (Tokens[szScan + 1].Kind in [tkInteger, tkFloat]);
        if (szScan >= 0) and (szScan + 1 < TokCount) and
           (Tokens[szScan].Kind in [tkPlus, tkMinus]) and
           (Tokens[szScan + 1].Kind in [tkInteger, tkFloat]) then
          Inc(szScan);
        if (szScan >= 0) and (szScan + 1 < TokCount) and
           (Tokens[szScan + 1].Kind = tkRParen) and
           (Tokens[szScan].Kind in [tkInteger, tkFloat, tkString, tkNil,
                                    tkTrue, tkFalse]) then
        begin
          if szScan > TokPos - 1 then Next;   { the sign }
          prevTok := SizeOfLiteralToken(TokPos - 1, szLitNeg);
          Next;                               { the literal }
          Expect(tkRParen, ')');
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := prevTok;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
          LastExprTk := tyInteger;
          Exit;
        end;

        szIsExpr := False;
        szScan := TokPos - 1;
        if (szScan >= 0) and (szScan < TokCount) then
        begin
          if Tokens[szScan].Kind in [tkAt, tkMinus, tkPlus, tkNot, tkLParen] then
            szIsExpr := True
          else if (Tokens[szScan].Kind = tkIdent) or
                  (BuiltinTypeNameTk(GetTokenStr(szScan)) <> tyUnknown) then
          begin
            szBd := 0;
            while (not szIsExpr) and (szScan < TokCount) do
            begin
              if Tokens[szScan].Kind = tkLBrack then
              begin
                { The name path indexes only a genuine ARRAY symbol. `s[1]` on a
                  string reaches it too and dies on the '[' with "expected )",
                  so a subscript on anything else is an expression. }
                if (szBd = 0) and (szScan > 0) and
                   (Tokens[szScan - 1].Kind = tkIdent) then
                begin
                  szRec := FindSym(GetTokenStr(szScan - 1));
                  if (szRec >= 0) and (not Syms[szRec].IsArray) then szIsExpr := True;
                end;
                Inc(szBd);
              end
              else if Tokens[szScan].Kind = tkRBrack then Dec(szBd)
              else if szBd = 0 then
              begin
                if Tokens[szScan].Kind = tkRParen then Break;
                { A qualified TYPE name is `ident (. name)*`, and the trailing
                  name may be a reserved TYPE token rather than a plain
                  identifier — `SizeOf(System.LongWord)`, `SizeOf(System.Pointer)`.
                  Testing tkIdent alone sent those down the expression path,
                  where `System.LongWord` is not a value: `undefined variable
                  (LongWord)`. The FIRST token already accepted a builtin type
                  name (the arm above); the rest of the run did not.
                  bug-p-sizeof-of-a-qualified-builtin-type-name }
                if (szScan > TokPos - 1) and
                   (not (Tokens[szScan].Kind in [tkIdent, tkDot])) and
                   (BuiltinTypeNameTk(GetTokenStr(szScan)) = tyUnknown) then
                  szIsExpr := True;
              end;
              Inc(szScan);
            end;
          end;
        end;
        if szIsExpr then
        begin
          ParseExpr;
          szExprNode := CurASTNode;
          szExprTk := IntToTypeKind(ASTTk[szExprNode]);
          { `SizeOf(p^)` where p points at a named FIXED array is the whole
            AGGREGATE's width. The node carries its ELEMENT kind (an array node
            always does), so this answered the element size — 4 for an
            `array[0..3] of LongWord` where FPC says 16, and that number reaches
            GetMem and Move. }
          if DerefPtrArrayInfo(szExprNode, dpaCount, dpaLo, dpaFlat) then
          begin
            Expect(tkRParen, ')');
            node := AllocNode(AN_INT_LIT);
            { a RECORD element is sized by its record id, not by TypeSlotSize(tyRecord) }
            { the FLAT count: SizeOf is the whole aggregate's width, so a
              multi-dim pointee is every element, not the first dimension. }
            if szExprTk = tyRecord then
              ASTIVal[node] := dpaFlat * RecSize(ResolveNodeRec(szExprNode))
            else
              ASTIVal[node] := dpaFlat * TypeSlotSize(szExprTk);
            ASTTk[node] := Ord(tyInteger);
            CurASTNode := node;
            LastExprTk := tyInteger;
            Exit;
          end;
          { A FIELD reached as an EXPRESSION — `SizeOf(p^.A)`. The name path
            below sizes `r.A` correctly through RecFieldByteSize; this path did
            not exist for it, because a `^` anywhere in the operand routes to
            the expression path and a field node carries its ELEMENT kind. So
            `SizeOf(p^.A)` on an `array[0..3] of Integer` answered 4 where FPC
            says 16 — silently, into GetMem and Move, which is the same failure
            RecFieldByteSize was written to end
            (bug-p-sizeof-an-array-field-returns-the-element-size). The ticket
            for this row expected a PARSE error and got a wrong number instead:
            the expression dispatch had since started accepting the operand
            without teaching anything downstream to size it.

            The same helper, deliberately: a second formula here is how the two
            spellings of one question drift apart. It also sizes a RECORD-typed
            field, which the refusal below would otherwise decline.
            bug-p-every-compile-time-intrinsic-hand-rolls-its-own-operand-parser }
          if ASTKind[szExprNode] = AN_FIELD then
          begin
            szFldName := GetASTIdentName(szExprNode);
            szFldRec := ResolveNodeRec(ASTLeft[szExprNode]);
            if (szFldRec <> REC_NONE) and (Length(szFldName) > 0) and
               (RecFieldType(szFldRec, szFldName) <> tyUnknown) then
            begin
              prevTok := RecFieldByteSize(szFldRec, szFldName);
              Expect(tkRParen, ')');
              node := AllocNode(AN_INT_LIT);
              ASTIVal[node] := prevTok;
              ASTTk[node] := Ord(tyInteger);
              CurASTNode := node;
              LastExprTk := tyInteger;
              Exit;
            end;
          end;
          { A RECORD-typed expression that CAN name its record — `SizeOf(p^)`
            where p is a `^TRec`. The refusal below is about a general node
            carrying no record id; ResolveNodeRec is the compiler's own answer
            to "which record is this node", and where it answers, the size is
            not a guess. Asked here rather than widening the refusal's condition
            so that the refusal keeps meaning exactly what its comment says.

            `SizeOf(p^)` over a pointer-to-ARRAY is handled above, by
            DerefPtrArrayInfo; over a pointer-to-RECORD it fell to this refusal,
            so the two spellings of "the whole pointee" disagreed. }
          if szExprTk = tyRecord then
          begin
            szFldRec := ResolveNodeRec(szExprNode);
            if szFldRec <> REC_NONE then
            begin
              prevTok := RecSize(szFldRec);
              Expect(tkRParen, ')');
              node := AllocNode(AN_INT_LIT);
              ASTIVal[node] := prevTok;
              ASTTk[node] := Ord(tyInteger);
              CurASTNode := node;
              LastExprTk := tyInteger;
              Exit;
            end;
          end;
          { A record-typed expression needs a record id to be sized and the AST
            does not carry one on a general node, so refuse rather than answer
            TypeSlotSize(tyRecord). Same for an operand whose type we failed to
            infer: a wrong size reaches GetMem and Move, so a diagnostic beats
            a plausible number. }
          if (szExprTk = tyUnknown) or (szExprTk = tyRecord) then
            Error('SizeOf: cannot size this expression (record or untyped) -- name the type or the variable instead');
          { `SizeOf(p^)` where the pointee IS a `string[N]` -- the fourth shape
            this dispatch has to ask about before its fallthrough, beside the
            pointer-to-array, the field and the pointer-to-record above.

            The fallthrough is TypeSlotSize, which takes a KIND and no capacity,
            so it answered pointer width: 8 for a `^string[10]` where fpc says
            11, in both declaration orders and for both the `PT = ^TT; TT =
            string[10]` and the direct `PT = ^string[10]` spellings. It reaches a
            value the same way its parent bug did -- `FillChar(p^, SizeOf(p^), 0)`
            clears 8 of 11 bytes.

            NOT SizeOfSlot(szExprTk, FrozenStrCapOfDeref(...)), which is the
            obvious repair and is wrong: an ident node for a frozen string
            carries the legacy overloaded tyString whatever the symbol holds, and
            tyString's length prefix is eight bytes against a shortstring's one.
            That spelling answers 24 here -- a loud wrong number replacing a
            quiet one. DerefFrozenStrSlotSize takes the kind and the capacity out
            of the SAME symbol, which is the invariant its own comment carries.
            bug-p-sizeof-through-a-pointer-to-a-string-n-answers-pointer-width }
          prevTok := DerefFrozenStrSlotSize(szExprNode);
          if prevTok = 0 then
            prevTok := TypeSlotSize(szExprTk);
          Expect(tkRParen, ')');
          { The operand subtree is DROPPED, so nothing in it is ever lowered and
            `SizeOf(F(x))` cannot call F -- FPC discards the expression too and
            keeps only its type. }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := prevTok;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
          LastExprTk := tyInteger;
          Exit;
        end;
        { Peek at the type token to determine the kind }
        name := CurTok.SVal;
        { `SizeOf(System.TMethod)` / `SizeOf(System.LongWord)` — and any OTHER
          unit qualifier: `SizeOf(Math.Float)` is how rtl-generics spells the
          width it hashes. ConsumeUnitQualifier is the expression parser's own
          resolver (it starts with EatSystemQualifier, so System.* is still
          covered) and returns -1 without consuming anything when the leading
          name is not a unit — which is what leaves `SizeOf(TOuter.TInner)` to
          the class-qualifier strip just below. One resolver, not a second
          hand-rolled copy: devdocs/dev/normalise-dont-special-case.md. }
        szQUnit := ConsumeUnitQualifier(name);   { the consumption is the point }
        { SizeOf has its own hand-rolled type dispatch, so it needs the class-qualifier
          strip too: `SizeOf(TOuter.TInner)` on a class-nested type. Without it the parse
          died on the '.' while `var r: TOuter.TInner` already worked — a half-working
          feature is worse than an absent one. Same rule as ParseTypeKind: pxx registers
          nested types globally, so the qualifier only disambiguates the parse.

          The walk is ScanNestedTypeRun's, shared with Default() — it keeps the
          row the qualifier NAMES rather than dropping the qualifier and looking
          the bare name up flat. Two records may each declare a `TSub`; the flat
          lookup answers with whichever registered first, so `SizeOf(TB.TSub)`
          reported TA's width — silently, and only in SizeOf: `var y: TB.TSub`
          already resolved through the registry and was right. The scope-blind
          half of bug-a-duplicate-class-name-check-is-scope-blind. This was an
          inline copy of that walk until Default() turned out to need a third
          one; the bare-name strip stays as the fallback for the (common) case
          where the nested type kept its unqualified registration. }
        szNestCi := -1;
        if (CurTok.Kind = tkIdent) and (FindUClass(name) >= 0) and
           (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) and
           (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkIdent) then
        begin
          szNestCi := ScanNestedTypeRun(name, szNestName, szHops);
          { same as Default()'s strip above, same reason }
          if szNestCi >= 0 then QualTypeOwnerCi := szNestCi
          else QualTypeOwnerCi := NestedOwnerCi(name);
          if szHops = 0 then szHops := 1;   { bare-name strip, one qualifier }
          for szI := 1 to szHops do
          begin
            Next;             { past the owner name — CurTok is now '.' }
            Next;             { past '.'            — CurTok is now the nested name }
          end;
          name := CurTok.SVal;
        end;
        { A builtin type spelled as a KEYWORD token (Double, Char, String, ...)
          carries no SVal, so give `name` the token's own text -- then ONE
          name-keyed lookup answers every builtin, whichever way it lexed. That
          split is what left SizeOf(Double) and SizeOf(Variant) rejected while
          SizeOf(Integer) worked: the token-kind arms and the name arms were two
          tables, and only the second one ever got extended. }
        if name = '' then name := GetTokenStr(TokPos - 1);
        szBTkAny := BuiltinTypeNameTk(name);
        szBTk := szBTkAny;
        szNameConsumed := False;
        { A USER DECLARATION WINS OVER A BUILTIN NAME, and this table cannot be
          consulted before checking that. Its own header says so -- "callers must
          consult a user type alias FIRST where that matters: this answers what
          the name means as a BUILTIN, not what the current scope binds it to" --
          and SizeOf is a caller for which it matters, because the builtin arm
          below is tried first and the record/alias/array/enum/variable tables
          are only reached in its `else`.

          That was harmless for as long as the table was a strict subset that
          happened to exclude the shadowable names. It stopped being harmless
          when the table was merged with the declaration path's: `type Currency =
          record a, b, c: Integer; end` then measured 8 instead of 12, a Boolean
          named `longbool` measured 4 instead of 1, and a ten-byte array named
          `tdatetime` measured 8 instead of 10 -- three silent wrong sizes,
          feeding GetMem and Move, all three confirmed against FPC 3.2.2.

          Only for a name spelled as a plain IDENTIFIER: a builtin that lexed as
          a keyword token cannot have been redeclared, which is the same
          condition the user-lookup branch below already tests.
          bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts }
        if (szBTk <> tyUnknown) and (CurTok.Kind = tkIdent) and
           ((IsRecordType(name) <> REC_NONE) or (FindUClass(name) >= 0) or
            (FindArrayType(name) >= 0) or (FindTypeAlias(name) >= 0) or
            (FindEnumType(name) >= 0) or (FindVarSym(name) >= 0)) then
          szBTk := tyUnknown;
        if szBTk = tyShortString then
          { A ShortString's size IS its capacity plus the length prefix, and
            TypeSlotSize takes a kind with no capacity to answer from. The
            `shortstring` NAME never reaches here -- BuiltinTypeNameNeedsDecl
            routes it through ParseTypeKind, which sets LastTypeStrCap -- so the
            only spelling that arrives with this kind and no capacity is a bare
            `string` under {$H-}, which is the third name for the same type.
            255 is that spelling's capacity, exactly as the `shortstring` arm
            in pasparser_decl.inc sets it.
            feature-p-h-minus-makes-a-bare-string-a-shortstring }
          prevTok := SizeOfSlot(tyShortString, 255)
        else if szBTk <> tyUnknown then
          prevTok := TypeSlotSize(szBTk)
        else if CurTok.Kind = tkIdent then
        begin
        { Try record/class type. A user `type X = ...` alias SHADOWS a
            same-named builtin descriptor record (the compiler exposes
            internal RTTI records like TProc/TParam under common names —
            see ParseTypeKind's identical guard) — only accept the record
            match if no user alias claims the same name, otherwise fall
            through to the alias branch below. }
          if szNestCi >= 0 then
            idx := REC_UCLASS_BASE + szNestCi
          else
          begin
            idx := IsRecordType(name);
            if idx = REC_NONE then
            begin
              ci := FindUClass(name);
              if ci >= 0 then
                idx := REC_UCLASS_BASE + ci;
            end;
          end;
          if (idx <> REC_NONE) and ((szNestCi >= 0) or (FindTypeAlias(name) < 0)) then
            prevTok := RecSize(idx)
          else
          begin
            { Named array type (`TArr = array[..] of T` / `array of T`):
              mirrors ParseVarSection's FindArrayType check, which resolves
              this BEFORE falling into ParseTypeKind's alias/enum lookup --
              so it must be tried here too, ahead of FindTypeAlias/
              FindEnumType below. A dynamic-array alias is a reference
              (handle), so its SizeOf is just the pointer width, same as
              any other managed handle. }
            szAi := FindArrayType(name);
            if szAi >= 0 then
              { ArrTypeByteSize (symtab.inc) is this rule, moved there when
                New's two spellings turned out to need the same answer and had
                been sizing the block off the ELEMENT kind. It carries the dyn,
                multi-dim and record-element arms this branch used to hold. }
              prevTok := ArrTypeByteSize(szAi)
            else
            begin
              { Named type alias (integer/pointer/set/enum/proc-type alias --
                anything ParseTypeKind resolves via FindTypeAlias/
                FindEnumType for a `var x: T` declaration) or a named enum
                type. Mirrors ParseTypeKind's tkIdent branch so `SizeOf(T)`
                accepts the same type names a variable declaration does
                (bug-sizeof-array-and-typename-wrong, symptom 2). }
              aliasIdx := FindTypeAlias(name);
              if aliasIdx >= 0 then
              begin
                if AliasTk[aliasIdx] = Ord(tyRecord) then
                  prevTok := RecSize(AliasElemRec[aliasIdx])   { e.g. method-pointer-of-object alias }
                else
                  prevTok := SizeOfSlot(IntToTypeKind(AliasTk[aliasIdx]), AliasStrCap[aliasIdx]);
              end
              else if FindEnumType(name) >= 0 then
                { THE THIRD COPY of "an enum is integer-sized", and the one a
                  {$PACKENUM} fix would most easily miss: the record-field path
                  reaches the width through ParseTypeKind's kind, so field
                  OFFSETS come out right while SizeOf(TheType) keeps answering 4.
                  Both were wrong here and only one was visible in a layout test. }
                prevTok := TypeSlotSize(EnumStorageTypeKind(FindEnumType(name)))
              else
              begin
                { Not a type name — accept a VARIABLE operand (FPC/Delphi allow
                  SizeOf(v) = size of v's declared type, not just SizeOf(Type)).
                  A record-by-value var uses its record size; everything else its
                  scalar type size (TypeSlotSize returns pointer width for class/
                  pointer references). }
                sci := FindVarSym(name);   { a bare class var is a variable here too }
                { ...but a FIELD of the enclosing class shadows an outer variable
                  of the same name, and FindVarSym does not know that. Measured:
                  a global `G: array[0..99] of Byte` beside a field `G:
                  array[0..15] of Byte` made SizeOf(G) answer 100 inside the
                  method while Length(G) on the same name answered 16 -- fpc
                  says 16 for both. Two intrinsics, one name, two receivers,
                  no diagnostic.

                  A method LOCAL of a field's name loses here too. That spelling
                  is a Duplicate identifier under fpc, so no compiling program
                  can tell the difference, and matching the precedence every
                  other intrinsic already applies is worth more than preserving
                  our own answer for a program fpc refuses. }
                if (CurMethClass >= REC_UCLASS_BASE) and
                   (FindUField(CurMethClass - REC_UCLASS_BASE, name) >= 0) then
                  sci := -1;
                if sci >= 0 then
                begin
                  if (Tokens[TokPos].Kind = tkDot) and (Syms[sci].RecName >= 0) and
                     (not Syms[sci].IsArray) then
                  begin
                    { SizeOf(obj.field[.field..]) — walk the selector chain
                      (never evaluating, like every SizeOf operand) and
                      report the FINAL field's size (blcksock's
                      SizeOf(Value.Value)).

                      Sized through RecFieldByteSize, NOT TypeSlotSize(RecFieldType):
                      RecFieldType answers an array field's ELEMENT kind, so the
                      latter reported 4 for an `array[0..2] of Integer` field
                      while the same array as a plain VAR reported 12, silently
                      and with the comment here claiming array fields errored out
                      (bug-p-sizeof-an-array-field-returns-the-element-size). One
                      field-size answer for everyone rather than a formula per
                      caller: devdocs/dev/normalise-dont-special-case.md. }
                    szRec := Syms[sci].RecName;
                    szElemTk := tyUnknown;
                    Next;   { consume the identifier; CurTok = '.' }
                    while CurTok.Kind = tkDot do
                    begin
                      Next;   { consume '.'; CurTok = field name }
                      if CurTok.Kind <> tkIdent then Error('SizeOf: expected field name');
                      szElemTk := RecFieldType(szRec, CurTok.SVal);
                      if szElemTk = tyUnknown then Error('SizeOf: unknown field');
                      prevTok := RecFieldByteSize(szRec, CurTok.SVal);
                      szRec := RecFieldRecId(szRec, CurTok.SVal);
                      if Tokens[TokPos].Kind = tkDot then Next;   { deeper chain }
                    end;
                    { CurTok = the last field name; the shared trailing Next
                      below moves past it to the ')'. prevTok already holds that
                      field's size. }
                  end
                  else if Syms[sci].IsArray and (Tokens[TokPos].Kind = tkLBrack) and
                     (SymArrNDims[sci] <= 1) then
                  begin
                    { SizeOf(arr[i]): the index expression's VALUE is never
                      evaluated by SizeOf (exactly like a type name's own
                      contents) -- skip the balanced brackets and report
                      the array's ELEMENT size, so the common idiom
                      `SizeOf(arr) div SizeOf(arr[0])` (element count)
                      works (bug-sizeof-array-and-typename-wrong, the
                      remaining symptom-2 gap). Only one level of
                      indexing on a genuinely 1-D array; a chained
                      `arr[i].field` is out of scope, and an N-D array
                      (SymArrNDims >= 2) needs its own row/sub-array
                      accounting depending on how many indices are given
                      (`m[0]` is a row, `m[0,1]` is a scalar) -- rather
                      than silently reporting the wrong (scalar) size,
                      that case falls through to the "unknown" error
                      below by NOT matching this guard. }
                    Next;                { consume the identifier; CurTok = '[' }
                    Next;                { consume '['; CurTok = start of index expr }
                    szBrDepth := 1;
                    while (szBrDepth > 0) and (CurTok.Kind <> tkEOF) do
                    begin
                      if CurTok.Kind = tkLBrack then Inc(szBrDepth)
                      else if CurTok.Kind = tkRBrack then Dec(szBrDepth);
                      if szBrDepth > 0 then Next;
                    end;
                    { CurTok = ']'; the shared trailing Next below moves past
                      it to the enclosing SizeOf(...)'s ')'. }
                    if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                      prevTok := RecSize(Syms[sci].ElemRecName)
                    else
                      prevTok := SizeOfSlot(Syms[sci].ElemType, SymStrCap[sci]);
                  end
                  else if Syms[sci].IsArray and (Tokens[TokPos].Kind = tkLBrack) then
                  begin
                    { SizeOf(m[i]) / SizeOf(m[i,j,..]) on a genuine N-D fixed
                      array (SymArrNDims[sci] >= 2 -- the <= 1 case is
                      handled above): mirrors the two subscript forms real
                      indexing supports (BuildPartialNDRowIndex /
                      BuildFlatNDIndex) -- a single subscript names a whole
                      row (sub-array), one subscript per dimension names a
                      scalar element. Indices are never evaluated (same
                      rationale as the 1-D case above), so just count
                      top-level commas while skipping the balanced
                      brackets. }
                    Next;                { consume the identifier; CurTok = '[' }
                    Next;                { consume '['; CurTok = start of first index expr }
                    szBrDepth := 1; szNIdx := 1;
                    while (szBrDepth > 0) and (CurTok.Kind <> tkEOF) do
                    begin
                      if CurTok.Kind = tkLBrack then Inc(szBrDepth)
                      else if CurTok.Kind = tkRBrack then Dec(szBrDepth)
                      else if (CurTok.Kind = tkComma) and (szBrDepth = 1) then Inc(szNIdx);
                      if szBrDepth > 0 then Next;
                    end;
                    { CurTok = ']'; the shared trailing Next below moves past
                      it to the enclosing SizeOf(...)'s ')'. }
                    szBase := sci * MAX_ARR_DIMS;
                    if szNIdx = 1 then
                    begin
                      szFlatLen := 1;
                      for szDi := 1 to SymArrNDims[sci] - 1 do
                        szFlatLen := szFlatLen * SymArrDimSpan[szBase + szDi];
                      if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                        prevTok := RecSize(Syms[sci].ElemRecName) * szFlatLen
                      else
                        prevTok := SizeOfSlot(Syms[sci].ElemType, SymStrCap[sci]) * szFlatLen;
                    end
                    else if szNIdx = SymArrNDims[sci] then
                    begin
                      if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                        prevTok := RecSize(Syms[sci].ElemRecName)
                      else
                        prevTok := SizeOfSlot(Syms[sci].ElemType, SymStrCap[sci]);
                    end
                    else
                    begin
                      Error('SizeOf: wrong number of array subscripts');
                      prevTok := 0;
                    end;
                  end
                  else if Syms[sci].IsArray and
                          ((SymDynDepth[sci] > 0) or (Syms[sci].ArrLen < 0)) then
                    { A DYNAMIC array variable is a handle, so pointer width --
                      the rule the named dynamic-array ALIAS branch above already
                      applies, and the one a dynamic-array FIELD gets from
                      RecFieldByteSize. Falling into the static formula below
                      multiplied the element size by ArrLen = -1 and SizeOf(d)
                      answered **-4**: a negative size, silently, which
                      `GetMem(SizeOf(d))` and any Move/FillChar sized that way
                      would carry straight into the allocator
                      (found widening bug-p-sizeof-an-array-field-returns-the-element-size). }
                    prevTok := TARGET_PTR_SIZE
                  else if Syms[sci].IsArray then
                  begin
                    { Array symbols store the ELEMENT type in TypeKind/ElemType
                      (a recurring landmine throughout this codebase), so the
                      aggregate size is elementSize * ArrLen (ArrLen already
                      holds the flattened element count for N-D arrays too --
                      see bug-sizeof-array-and-typename-wrong). }
                    if (Syms[sci].ElemType = tyRecord) and (Syms[sci].ElemRecName >= 0) then
                      prevTok := RecSize(Syms[sci].ElemRecName) * Syms[sci].ArrLen
                    else
                      prevTok := SizeOfSlot(Syms[sci].ElemType, SymStrCap[sci]) * Syms[sci].ArrLen;
                  end
                  else if (Syms[sci].TypeKind = tyRecord) and (Syms[sci].RecName >= 0) then
                    prevTok := RecSize(Syms[sci].RecName)
                  else
                    prevTok := SizeOfSlot(Syms[sci].TypeKind, SymStrCap[sci]);
                end
                else
                begin
                  { RECOVERS. The stand-in was already here (a size of 0) —
                    only the halt had to go, and this is the shape the rest of
                    the sweep keeps finding: a diagnostic whose caller already
                    knows what to carry on with.
                    feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
                  { The demotion above is a PREFERENCE, not a verdict. Some
                    builtin names ALSO match an internal registration that this
                    branch cannot size -- `ShortString` matches one and then
                    falls through every arm -- so a name demoted here and not
                    resolved must come back to the builtin answer rather than
                    become a rejection. Without this, restoring user-declaration
                    precedence silently un-fixed SizeOf(ShortString).
                    bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts }
                  { A BARE FIELD OF THE ENCLOSING CLASS. Every other intrinsic
                    that takes a name -- Length, Low, High, Ord, Assigned, Inc,
                    FillChar -- already resolves `FBuf` inside a method against
                    an implicit Self; SizeOf never learned it, so
                    `SizeOf(FBuffer)` said "unknown type or variable" while
                    `SizeOf(Self.FBuffer)` on the same field answered correctly.
                    fcl-passrc pscanner.pp:2338 is that call.

                    Asked here rather than beside FindVarSym above so a LOCAL of
                    the same name keeps winning, which is the ordinary shadowing
                    rule and is what FindVarSym already gives us by having
                    answered first. RecFieldByteSize, not TypeSlotSize over
                    RecFieldType, for the reason the selector-chain arm above
                    states: RecFieldType answers an ARRAY field's element kind.
                    FindUField walks the parent chain, so an inherited field
                    resolves too.
                    bug-p-sizeof-of-a-bare-field-is-the-one-intrinsic-that-never-learned-implicit-self }
                  if (CurMethClass >= REC_UCLASS_BASE) and
                     (FindUField(CurMethClass - REC_UCLASS_BASE, name) >= 0) then
                    prevTok := RecFieldByteSize(CurMethClass, name)
                  else if (CurTok.Kind = tkIdent) and BuiltinTypeNameNeedsDecl(name) then
                  begin
                    { A BUILTIN NAME THE KIND TABLE CANNOT SIZE -- resolve it
                      the way a DECLARATION does, and size whatever comes back.
                      `ShortString` is a 255-cap tyShortString (256 bytes),
                      `TextFile` is the RTL `text` RECORD (4128), and the three
                      pointer names are pointee-carrying arms; not one of those
                      three facts is a function of a TTypeKind, so the
                      TypeSlotSize(kind) fallback just below -- which was added
                      for precisely this shape (582e4de09) -- cannot reach them
                      and all five said `unknown type or variable` while
                      `var v: N` accepted every one.
                      Deliberately NOT a name-to-width table: ParseTypeKind's
                      arms stay the only place these widths are decided.
                      ParseTypeKind consumes the name itself, so the shared
                      trailing Next is suppressed.
                      bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size }
                    szDeclTk := ParseTypeKind;
                    szNameConsumed := True;
                    if (szDeclTk = tyRecord) and (LastTypeRecId <> REC_NONE) then
                      prevTok := RecSize(LastTypeRecId)
                    else
                      prevTok := SizeOfSlot(szDeclTk, LastTypeStrCap);
                  end
                  else if szBTkAny <> tyUnknown then
                    prevTok := TypeSlotSize(szBTkAny)
                  else
                  begin
                    ErrorRecover('SizeOf: unknown type or variable');
                    prevTok := 0;
                  end;
                end;
              end;
            end;
          end;
        end
        else
        begin
          Error('SizeOf: expected type name');
          prevTok := 0;
        end;
        if not szNameConsumed then
          Next; { consume type token — ParseTypeKind already did when it ran }
        Expect(tkRParen, ')');
        node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := prevTok;
        ASTTk[node] := Ord(tyInteger);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxTlsBase') then
      begin
        { The calling thread's TLS base. Reading it is the only part that needs a
          compiler: INSTALLING a block is arch_prctl(ARCH_SET_FS) and goes through
          __pxxrawsyscall like any other syscall, from the thread itself -- which is
          why this ticket did NOT need CLONE_SETTLS, a sixth __pxxclone argument, or
          four backend changes to IR_CLONE (see
          feature-a-thread-local-storage-via-clone-settls). }
        Next; { consume '__pxxTlsBase' }
        if TargetArch <> TARGET_X86_64 then
          Error('__pxxTlsBase is x86-64 only: the other targets have a readable thread register (aarch64 tpidr_el0, arm32 tpidruro) but this runtime has no way to SET one yet, and answering with the parent thread''s block would be a plausible wrong pointer. x86-64 installs its block with arch_prctl(ARCH_SET_GS) in the clone stub; the others need an equivalent before this can answer.');
        node := AllocNode(AN_TLSBASE);
        ASTTk[node] := Ord(tyPointer);
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxrawsyscall') then
      begin
        { Raw syscall intrinsic: lowered to the target's native syscall
          instruction. First arg = syscall number, then up to 6 arguments. }
        Next; { consume '__pxxrawsyscall' }
        Expect(tkLParen, '(');
        node := AllocNode(AN_SYSCALL);
        ASTTk[node] := Ord(tyInt64);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs > 7 then Error('__pxxrawsyscall: at most 7 arguments (nr + 6)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxcoswitch') then
      begin
        { Low-level coroutine context switch: __pxxcoswitch(pfrom, pto: Pointer).
          Both args are the addresses of the from/to TCoroCtx records. Lowers to
          a call to the bare CoSwitch runtime stub. }
        Next; { consume '__pxxcoswitch' }
        Expect(tkLParen, '(');
        node := AllocNode(AN_COSWITCH);
        ASTTk[node] := Ord(tyPointer);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs <> 2 then Error('__pxxcoswitch: expects exactly 2 arguments (pfrom, pto)');
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxclone') then
      begin
        { Libc-free thread spawn: __pxxclone(flags, childStack, entry, arg, ctidptr).
          Lowers to a call to the bare clone+trampoline stub. Returns the child tid
          (Int64) in the parent; never returns in the child. }
        Next; { consume '__pxxclone' }
        { Thread spawn requires the thread-safe runtime: without --threadsafe the
          heap allocator, ARC refcounts and console I/O have no locking, so any
          allocation/writeln from a second thread corrupts shared state. Fail at
          compile time, not as a heisencrash (feature-threadsafe-heap-contract). }
        if not ThreadSafeMode then
          Error('__pxxclone (thread creation) requires --threadsafe or {$threadsafe on}: the default heap/ARC/console-I/O runtime is not thread-safe');
        { The clone+trampoline stub is emitted lazily (jmp-over) at the first IR_CLONE
          codegen — see EnsureCloneStub — so nothing to arrange here. }
        Expect(tkLParen, '(');
        node := AllocNode(AN_CLONE);
        ASTTk[node] := Ord(tyInt64);
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs <> 5 then Error('__pxxclone: expects exactly 5 arguments (flags, childStack, entry, arg, ctidptr)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      { THE IDENT-SPELLED ORDINAL CAST DOOR USED TO BE HERE, and it was the
        SECOND of the two name-keyed scalar cast doors in this function. It
        recognised via OrdinalNameToTk and built AN_PTR_CAST; the door below
        (`castTk := BuiltinScalarTypeKind(name)`) recognises a strict SUPERSET
        of the same names and builds the same node with strictly more work
        around it -- the operator-Explicit conversion, the Pointer/AN_ADDR
        spelling, the enum identity. Measured, not assumed: OrdinalNameToTk is
        31 names, BuiltinScalarTypeKind 51, the first a strict subset with no
        shared name disagreeing.
        refactor-p-five-dispatch-sites-for-one-named-type-cast

        Deleted after a TWO-ARMED poison control, because "the rows did not
        move" alone cannot tell a correct fall-through from a third path
        answering by luck. Poisoning the door below (castTk := tyUInt8 for one
        name) is INERT while this door exists -- it catches the name first --
        and with this door gone it changes that name's rows. The same poison on
        `int64` SEGFAULTS the self-host, from the compiler's own source rather
        than from a probe. Both directions, so the arm that answers is named
        rather than inferred.

        Equivalence measured over 31 names x 4 constant values + a runtime
        operand + the string-context rows (163 rows, byte-identical), 93 rows
        with a VARIANT operand (the one place the two doors differed in
        structure: this one wrapped the converted temp, the other exits), the
        nine widechar tests, and the three committed differentials.

        THE -3 WIDECHAR MARKER WENT WITH IT, and that is the hazard this
        ticket named. It was already redundant: NodeIsWideCharVal answers on
        `ASTTk = tyWideChar` as well, and every node this door stamped -3 on
        also carried that kind, so the marker could never be the deciding arm.
        Two spellings proved it -- `UnicodeChar(x)` reached this door and was
        NEVER stamped -3 (the guard read the NAME, not the kind) yet behaved
        identically to `WideChar(x)` in every string context. NilPy's frontend
        keeps its own verbatim copy of this door and its own -3
        (pyparser.inc), per the duplicate-the-parser-per-language rule, so the
        -3 arm of NodeIsWideCharVal is still live -- for N, not for P.

        The System-qualifier exemption `(qUnit = -2)` went with it too. The
        door below does not spell one, and it did not need one: with a
        shadowing `var Int64: LongInt`, `System.Int64(65769)` still answers
        65769 exactly as fpc 3.2.2 does, and the unqualified `Int64(65769)` is
        still a syntax error on both -- so the shadow is real and the probe
        is aimed at it. }

      { TypeInfo(T) -- FPC's System intrinsic. Enum types (the original support) yield
        the address of the enum RTTI blob {name, count, names[]} directly, unchanged --
        that is what typinfo.pas's GetEnumName/GetEnumNameCount already take, and
        fpjson's RTTI streaming is gated on it staying exactly as it was.

        Scalars, strings, classes and records (feature-pascal-corpus-generics: rung 3
        needs TypeInfo(T) for GENERIC PARAMETERS, e.g. Generics.Defaults selecting a
        comparer by Kind) go through a SEPARATE, uniform "PTypeInfo" header --
        {Kind, NamePtr, DataPtr} -- built by EmitTypeInfoHeaders once EmitRTTI has run
        (rtti_emit.inc) and read generically by typinfo.pas regardless of category. No
        FPC byte-layout parity is implied or needed (see feature-pascal-corpus-generics
        "NO DECISION NEEDED" recon note) -- typinfo.pas owns the whole translation. }
      { __pxxExceptObject: the exception OBJECT in flight — the same shape as
        __pxxExceptAddr below in every respect, and deliberately written as its
        twin rather than as a variant of it. sysutils.ExceptObject wraps it and
        casts the result to TObject; keeping the intrinsic UNTYPED is what lets
        the wrapper live in the RTL, where TObject is in scope, instead of
        teaching the parser about a class it does not otherwise know. }
      if CaseEqual(name, '__pxxExceptObject') and (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        Next;
        if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        EnableExceptionRuntime;   { readable without this unit ever raising }
        node := AllocNode(AN_EXCEPTOBJ);
        ASTTk[node] := Ord(tyPointer);
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      { __pxxExceptAddr: the raise site of the exception in flight. Zero-arg, and the
        reserved prefix keeps it out of the user's namespace — sysutils.ExceptAddr is a
        one-line wrapper over it. Parens optional, like any zero-arg Pascal function. }
      if CaseEqual(name, '__pxxExceptAddr') and (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        Next;
        if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        EnableExceptionRuntime;   { a program may read the raise site without raising itself }
        node := AllocNode(AN_EXCEPTADDR);
        ASTTk[node] := Ord(tyPointer);
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      { __pxxSigCode / __pxxSigAddr / __pxxSigContext: the siginfo of the signal
        currently being dispatched. Zero-arg with optional parens and a reserved
        prefix, exactly like __pxxExceptAddr above — an RTL wrapper gives them
        friendly names.

        si_code is THE reason SA_SIGINFO exists here: it is the only carrier of
        which fault occurred (the MXCSR status flags read 0x00 inside a handler,
        measured — see feature-float-exception-mask-control).

        Hosted Linux targets only, and REFUSED elsewhere (xtensa/ESP) rather than
        answering 0: a target whose handlers are installed without SA_SIGINFO
        never writes the slots, and a plausible 0 ("SI_USER", "no fault address")
        is exactly the silent wrong value this dialect refuses to invent — the
        same call the ESP PAL makes with PAL_ERR_UNSUPPORTED.
        feature-signal-siginfo-ucontext }
      { __pxxSigPCPtr joins them: the ADDRESS of the saved program counter inside
        that ucontext — the one word whose location is per-arch knowledge the
        compiler already has and a Pascal program does not.

        A POINTER rather than a read/write pair on purpose. Handing back the slot
        address makes reading it (`PPtrUInt(__pxxSigPCPtr)^`) and rewriting it
        (`PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Recover)`) ordinary Pascal, so one
        intrinsic covers both directions and the compiler owns exactly one fact:
        the offset. Rewriting it is what turns a fault into a catchable raise —
        the handler points the PC at a Pascal proc that raises, and the exception
        runtime's shadow stack (BSS_EXC_TOP, a setjmp chain) unwinds from there
        regardless of the interrupted SP. WHICH exception to raise stays a
        library question, deliberately: see
        decide-int-div-zero-behavior-unification, still open on where a builtin
        exception class should live.

        Meaningful only while a handler is running (ctx is nil otherwise, so the
        pointer would be a small bogus address) — same caller-must-know contract
        as si_addr being a pid for a kill()-delivered signal. }
      { __pxxSigSPPtr is its other half, and exists because rewriting the PC
        alone is not enough when the fault WAS the stack. The kernel resumes the
        redirect target on the FAULTING frame's stack pointer, which after a
        stack overflow is by definition a stack with nothing left — so the raise
        stub re-faults on its own prologue, is redirected again, and the process
        spins on the guard page until the watchdog kills it (measured:
        bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset).
        Handing back the address of the saved SP lets a handler move the resumed
        code onto a stack that has room:

          PPtrUInt(__pxxSigSPPtr)^ := PtrUInt(@spare[High(spare)-64]) and not 15;
          PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);

        where `spare` is an ordinary global array — the compiler deliberately
        supplies no stack of its own, because how much room a recovery path
        needs, and whether it is per-thread, is a program's call, not a
        compiler's. (An altstack does NOT solve this: SA_ONSTACK gives the
        HANDLER a stack, and the handler was never the problem — it is what the
        kernel resumes on AFTER sigreturn that re-faults.)

        The exception runtime stays consistent across the switch: ExcLongJmp
        restores SP from the setjmp buffer of the frame that owns the `except`,
        not from the resumed context, so the shadow chain (BSS_EXC_TOP) unwinds
        to a frame on the ORIGINAL stack and the borrowed one is simply
        abandoned. The raise stub only ever needs room to reach ExcRaise. }
      if (CaseEqual(name, '__pxxSigCode') or CaseEqual(name, '__pxxSigAddr') or
          CaseEqual(name, '__pxxSigContext') or CaseEqual(name, '__pxxSigPCPtr') or
          CaseEqual(name, '__pxxSigSPPtr') or
          CaseEqual(name, '__pxxSigNum')) and
         (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        { __pxxSigNum used to refuse everywhere but x86-64, because only that
          dispatch stub parked the number and answering 0 would have sent every
          signal to handler 0 — a plausible wrong value in the place hardest to
          notice. All five hosted stubs park it as of 2026-08-31, so the refusal
          is gone and the question below (does this target have a signal runtime
          at all) is the only one left. }
        { Every target that HAS a signal runtime installs it with SA_SIGINFO, so
          this asks that one question and nothing else. It used to read
          `TargetArch = TARGET_XTENSA`, which was a fact about the PLATFORM
          ("FreeRTOS is not a Unix") written as a test on the ARCH back when the
          two were the same thing for xtensa; the hosted profile separated them
          and the premise expired
          (ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired).
          TargetHasSignalRuntime is that axis, shared with the two dispatchers in
          ir_codegen.inc so a target cannot be accepted here and absent there. }
        if not TargetHasSignalRuntime then
          Error(name + ' needs SA_SIGINFO, which this target''s signal runtime '
                + 'does not install (feature-signal-siginfo-ucontext)');
        { __pxxSigPCPtr / __pxxSigSPPtr need one MORE per-arch fact than the rest:
          the byte offset of the saved PC/SP inside ucontext_t, which is measured
          per target and is -1 where nobody has measured it. Keyed on the VALUE
          rather than on an arch list, because a list is what went stale above:
          add the row to UContextPCOffset and this opens by itself. }
        if ((CaseEqual(name, '__pxxSigPCPtr') and (UContextPCOffset < 0)) or
            (CaseEqual(name, '__pxxSigSPPtr') and (UContextSPOffset < 0))) then
          Error(name + ' needs the saved-PC/SP offset inside this target''s '
                + 'ucontext_t, which has not been measured yet '
                + '(UContextPCOffset in ir.inc)');
        if NoSignals then
          Error(name + ' requires the signal runtime (built with --no-signals)');
        Next;
        if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_SIGINFO);
        if CaseEqual(name, '__pxxSigCode') then
        begin
          { tyInteger, NOT tyInt64: si_code's real width is a signed 32-bit int,
            and on the ILP32 targets an Int64 is a register PAIR — a stub would
            have to write a second sign word into the slot, and every backend's
            IR_EXC_STORE moves exactly one machine word. Typing it at the field's
            true width sidesteps the pair on all six backends at once. (Decided
            2026-08-13, feature-signal-siginfo-ucontext: small now, breaking
            later.) The x86-64 stub still sign-extends into its 8-byte slot, so
            the slot stays self-consistent whoever reads it. }
          ASTIVal[node] := 0; ASTTk[node] := Ord(tyInteger);
        end
        else if CaseEqual(name, '__pxxSigAddr') then
        begin
          ASTIVal[node] := 1; ASTTk[node] := Ord(tyPointer);
        end
        else if CaseEqual(name, '__pxxSigContext') then
        begin
          ASTIVal[node] := 2; ASTTk[node] := Ord(tyPointer);
        end
        else if CaseEqual(name, '__pxxSigPCPtr') then
        begin
          ASTIVal[node] := 3; ASTTk[node] := Ord(tyPointer);
        end
        else if CaseEqual(name, '__pxxSigSPPtr') then
        begin
          ASTIVal[node] := 5; ASTTk[node] := Ord(tyPointer);
        end
        else
        begin
          { __pxxSigNum. tyInteger for the same reason __pxxSigCode is: the
            kernel's signo is a 32-bit int, and an Int64 is a register PAIR on
            the ILP32 targets this will grow to. }
          ASTIVal[node] := 4; ASTTk[node] := Ord(tyInteger);
        end;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        CurASTNode := node;
        Exit;
      end;

      { `p := New(PRec)` — New's FUNCTION form, which takes the pointer TYPE and
        hands the block back instead of storing it through a variable. FPC has
        had both spellings forever and rtl-generics uses this one
        (`Result := New(PSpoofInterfacedTypeSizeObject)` in Generics.Defaults);
        pxx had only the statement form, in the statement parser, so the
        expression spelling came out as `undefined variable (New)`.

        Same lowering as that arm — GetMem(SizeOf(pointee)) — with the size read
        off the ALIAS row rather than off a variable's symbol, which is the only
        difference between the two spellings. Note this is deliberately NOT a
        second New: the intrinsic that allocates is one concept and its two
        surface forms must agree, so if the size rule ever changes it changes in
        both arms or neither (devdocs/dev/normalise-dont-special-case.md).

        Guarded so it can only fire on the real intrinsic: a user `New` proc or
        variable wins, a `(` must follow, and the argument must be an IDENT that
        names a POINTER type alias — `New(p)` over a variable is the statement
        form and never reaches here.
        bug-p-new-as-a-function-over-a-pointer-type-is-undefined }
      if CaseEqual(name, 'New') and
         ((qUnit = -2) or ((FindProc(name) < 0) and (FindSym(name) < 0))) and
         (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
         (Tokens[TokPos + 1].Kind = tkIdent) and
         (FindTypeAlias(GetTokenStr(TokPos + 1)) >= 0) and
         (AliasTk[FindTypeAlias(GetTokenStr(TokPos + 1))] = Ord(tyPointer)) then
      begin
        Next; Expect(tkLParen, '(');
        aliasIdx := FindTypeAlias(CurTok.SVal);
        Next;                                  { the pointer type name }
        Expect(tkRParen, ')');
        { The array-pointee arm the statement form carries, on this form's own
          carrier: AliasElemTk is the ELEMENT kind for `P1D = ^T1D`, so without
          this `New(P1D)` allocated one element and the caller overran the block.
          The comment above says the size rule changes in both arms or neither
          -- this is that. bug-p-new-of-a-pointer-to-an-array-type-allocates-the-element-size }
        if AliasPtrElemArrAi[aliasIdx] >= 0 then
          i := ArrTypeByteSize(AliasPtrElemArrAi[aliasIdx])
        else
          i := TypeStorageSize(IntToTypeKind(AliasElemTk[aliasIdx]), AliasElemRec[aliasIdx]);
        exprNode := AllocNode(AN_INT_LIT);
        ASTIVal[exprNode] := i;
        ASTTk[exprNode] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG);
        ASTLeft[argSeq] := exprNode;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkGetMem);
        ASTLeft[node] := argSeq;
        ASTTk[node] := Ord(tyPointer);
        LastExprTk := tyPointer;
        LastTypeRecId := AliasElemRec[aliasIdx];
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, 'TypeInfo') and
         ((qUnit = -2) or ((FindProc(name) < 0) and (FindSym(name) < 0))) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        i := -1; ci := -1; tiTk := tyUnknown; tiName := ''; tiAlias := -1; tiArr := -1;
        if CurTok.Kind = tkIdent then
        begin
          tiName := CurTok.SVal;
          i := FindEnumType(tiName);
          if i < 0 then
          begin
            ci := FindUClass(tiName);
            if ci < 0 then
            begin
              { The string names are decided HERE rather than deferred to
                BuiltinTypeNameTk below, because the two answer different
                questions. BuiltinTypeNameTk reports the internal type TAG a
                `string` variable carries (tyString in an unmanaged build);
                RTTI has to report the string MODEL the program observes, and
                pxx's `string` is pointer-sized (SizeOf = 8) and grows past
                255 — measured — i.e. an AnsiString, which is also what FPC
                answers for `string` under {$H+}. Deferring these rows would
                report ShortString for a type that is nothing of the kind. }
              if tiTk = tyUnknown then
              begin
                if CaseEqual(tiName, 'string') or CaseEqual(tiName, 'ansistring') then tiTk := tyAnsiString
                else if CaseEqual(tiName, 'shortstring') then tiTk := tyShortString
                else
                  { Everything else builtin comes from the ONE table — the float
                    family, Variant, Pointer, CodePointer. This path used to keep
                    a private subset of it (single/double/real/extended and
                    nothing more), so TypeInfo(Pointer) and TypeInfo(Variant)
                    were refused while SizeOf of the same names worked. Exactly
                    the duplicate-table defect BuiltinTypeNameTk's own header
                    comment describes SizeOf having had
                    (devdocs/dev/normalise-dont-special-case.md). }
                  tiTk := BuiltinTypeNameTk(tiName);
              end;
              { Then the NAMED type tables, which the builtin names cannot be in.
                Arrays keep their own table (ArrType*), so both are consulted:
                `TArr = array[0..3] of Integer` / `TDyn = array of Integer`, then
                `TSub = 1..10`, `TSet = set of TEnum`, `TProc = procedure(...)`,
                `TStr20 = string[20]`, a plain `TMyInt = Integer`. Last, not
                first, so every builtin spelling keeps resolving exactly as it
                did; this only turns an error into an answer. }
              if tiTk = tyUnknown then tiArr := FindArrayType(tiName);
              if (tiTk = tyUnknown) and (tiArr < 0) then tiAlias := FindTypeAlias(tiName);
            end;
          end;
        end
        else if CurTok.Kind in [tkInteger_T, tkBoolean_T, tkChar_T, tkString_T, tkReal_T,
                                 tkLongWord_T, tkSingle_T, tkDouble_T, tkExtended_T] then
        begin
          { Type-keyword tokens (Integer/Boolean/Char/String/Real/LongWord/Single/
            Double/Extended lex as their OWN token kind, not tkIdent -- SVal is
            empty for these, read the spelling via GetTokenStr like the class-body
            method-named-after-a-type-keyword path does, b332. }
          { TokPos - 1, not TokPos: Next has already advanced past this token
            (lexer.inc's Next reads Tokens[TokPos] then Inc(TokPos)), so
            GetTokenStr(TokPos) returns the `)` AFTER the type name. That was
            invisible while tiName fed only the "not supported" error, which
            this branch never reaches — the case below always assigns a kind. }
          tiName := GetTokenStr(TokPos - 1);
          { Resolve from the SPELLING first, not the token kind. `byte` and
            `integer` both lex as tkInteger_T (lexer.inc:229/284 — one token,
            two spellings), so switching on the kind alone reported
            TypeInfo(Byte) as tkInteger named "Integer" while the identical
            TypeInfo(UInt8) — an ordinary tkIdent, resolved by name — correctly
            said "Byte". FPC says Byte. The type system was never confused:
            SizeOf(Byte) has always been 1; only this path lost the spelling.
            OrdinalNameToTk answers tyUnknown for the non-ordinal keywords
            (string/real/single/double/extended), which is what the case below
            still handles. }
          tiTk := OrdinalNameToTk(tiName);
          if tiTk <> tyUnknown then
          begin
            { resolved by name }
          end
          else
          case CurTok.Kind of
            tkInteger_T:  tiTk := tyInteger;
            tkBoolean_T:  tiTk := tyBoolean;
            tkChar_T:     tiTk := tyChar;
            tkString_T:   tiTk := tyAnsiString;
            { RealTypeKind, not tyDouble: `Real` is the target's native float
              depth, and on xtensa/riscv32 that is Single by design. RTTI has to
              report the type the program actually got, the same reason
              BuiltinTypeNameTk stopped hard-wiring it.
              bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets }
            tkReal_T:     tiTk := RealTypeKind;
            tkLongWord_T: tiTk := tyUInt32;
            tkSingle_T:   tiTk := tySingle;
            tkDouble_T:   tiTk := tyDouble;
            tkExtended_T: tiTk := tyExtended;
          end;
        end
        else
          Error('TypeInfo expects a type name');
        Next;
        Expect(tkRParen, ')');
        node := AllocNode(AN_TYPEINFO);
        if i >= 0 then
          { legacy enum path: ASTLeft stays -1, ASTIVal = enum type id, exactly as before }
          ASTIVal[node] := i
        else if ci >= 0 then
        begin
          ASTLeft[node] := 1;
          if UClsIsRecord[ci] then
            ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_RECORD, ci)
          else
            ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_CLASS, ci);
        end
        else if tiTk <> tyUnknown then
        begin
          ASTLeft[node] := 1;
          ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_ORD, Ord(tiTk));
        end
        else if tiArr >= 0 then
        begin
          ASTLeft[node] := 1;
          ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_ARRAY, tiArr);
        end
        else if tiAlias >= 0 then
        begin
          ASTLeft[node] := 1;
          ASTIVal[node] := RegisterTypeInfoReq(TYPEINFO_REQ_CAT_ALIAS, tiAlias);
        end
        else
          Error('TypeInfo is not supported for type: ' + tiName);
        ASTTk[node] := Ord(tyPointer);
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      if (CaseEqual(name, 'get_frame') or CaseEqual(name, 'get_pc_addr')) and
         (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        { FPC's System stack-frame intrinsics, reached with no `uses` -- so they are
          soft keywords (a real symbol of the same name still wins, per the guard).

            get_frame    the current function's frame pointer
            get_pc_addr  the return address of the current function

          FPC allows both bare and with an empty (). Diagnostic code (fpcunit's
          CallerAddr, any backtrace) walks the chain with these plus
          get_caller_stackinfo below. }
        { The program body runs at the ELF entry, where SysV leaves no linked frame
          (rbp = 0 -- it IS the outermost frame). So there is nothing to read and
          nothing to walk: say so at compile time rather than fault at runtime.
          Routines, including unit init sections, all have a real prologue. }
        if CurProc < 0 then
          Error(name + ' needs a stack frame, and the program body has none (it is the outermost frame): call it from a routine');
        FrameIntrinsicUsed := True;
        if CurProc >= 0 then ProcFrameSensitive[CurProc] := True;
        if CaseEqual(name, 'get_frame') then node := AllocNode(AN_FRAME)
        else node := AllocNode(AN_PCADDR);
        ASTTk[node] := Ord(tyPointer);
        Next;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        LastExprTk := tyPointer;
        CurASTNode := node;
        Exit;
      end;

      { __pxxGetFPUMask / __pxxSetFPUMask(m): the float-exception MASK.

        The value is a 6-bit set in FPC's TFPUException order — bit 0
        exInvalidOp, 1 exDenormalized, 2 exZeroDivide, 3 exOverflow,
        4 exUnderflow, 5 exPrecision — where 1 means MASKED, i.e. the quiet
        IEEE behaviour (inf/NaN propagate) that is pxx's default and stays it.
        Clearing a bit UNMASKS: the offending SSE instruction then traps
        SIGFPE, and __pxxSigCode says which (FPE_FLTDIV/OVF/UND/INV) — the
        MXCSR status flags cannot, they read 0x00 inside a handler because
        Linux hands it a clean FP state (measured, see the ticket).

        SET returns the PREVIOUS mask, so save/restore is one expression and
        this family needs no statement-position hook — the same call
        __pxxSigPCPtr made by handing back a pointer instead of adding a setter.

        x86-64 only for now, and REFUSED elsewhere rather than accepted as a
        no-op. On aarch64/arm32 the FPCR/FPSCR trap-enable bits are permitted
        to be RES0 (most implementations never trap), and RISC-V has no
        trapping FP at all — only sticky flags. Accepting the call there would
        report a mask that does nothing, which is the silent wrong answer this
        dialect refuses to invent. feature-float-exception-mask-control }
      if (CaseEqual(name, '__pxxGetFPUMask') or CaseEqual(name, '__pxxSetFPUMask')) and
         (FindProc(name) < 0) and (FindSym(name) < 0) then
      begin
        if TargetArch = TARGET_I386 then
          Error(name + ' is not ported to i386 yet: it does its float '
                + 'arithmetic in SSE too, so MXCSR is the same mechanism, but '
                + 'its x87 control word (used for the int conversions) would '
                + 'have to move with it '
                + '(feature-float-exception-mask-control)')
        else if TargetArch <> TARGET_X86_64 then
          Error(name + ' is x86-64 only: this target has no architecturally '
                + 'guaranteed float-exception trap enable '
                + '(feature-float-exception-mask-control)');
        node := AllocNode(AN_FPUMASK);
        ASTTk[node] := Ord(tyInteger);
        if CaseEqual(name, '__pxxGetFPUMask') then
        begin
          ASTIVal[node] := 0;
          Next;
          if (TokPos <= TokCount) and (CurTok.Kind = tkLParen) then
          begin
            Next;
            Expect(tkRParen, ')');
          end;
        end
        else
        begin
          ASTIVal[node] := 1;
          Next;
          Expect(tkLParen, '(');
          ParseExpr;
          ASTLeft[node] := CurASTNode;
          Expect(tkRParen, ')');
        end;
        LastExprTk := tyInteger;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxmulhi_u64') then
      begin
        { __pxxmulhi_u64(a, b): the HIGH 64 bits of the unsigned 128-bit product
          a*b (the low half is an ordinary a*b). Lowers to IR_MULHI -- x86-64
          `mul`, aarch64 `umulh`. 64-bit targets only; lowering rejects the
          32-bit ones. Portable callers use lib/rtl's MulHiU64 wrapper. }
        node := AllocNode(AN_MULHI);
        ASTTk[node] := Ord(tyUInt64);
        Next; { consume the intrinsic name }
        Expect(tkLParen, '(');
        ParseExpr;
        ASTLeft[node] := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr;
        ASTRight[node] := CurASTNode;
        Expect(tkRParen, ')');
        LastExprTk := tyUInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxblockmove') or CaseEqual(name, '__pxxblockfill') then
      begin
        { __pxxblockmove(dest, src, n) / __pxxblockfill(dest, n, byteval): the
          machine's bulk memory instruction, inline. Both return dest so they
          can be written as an expression statement. The MOVE is forward-only --
          overlap is the caller's question, and builtin's __pxxMove answers it
          in Pascal before it gets here. x86-64 only; lowering refuses the rest,
          which is why every caller keeps a {$ifdef}-guarded Pascal loop. }
        node := AllocNode(AN_BLOCK_MEM);
        ASTTk[node] := Ord(tyNativeInt);
        if CaseEqual(name, '__pxxblockmove') then ASTIVal[node] := 0
        else ASTIVal[node] := 1;
        Next; { consume the intrinsic name }
        Expect(tkLParen, '(');
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if nArgs <> 3 then
          Error('__pxxblockmove/__pxxblockfill: expects 3 arguments');
        LastExprTk := tyNativeInt;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__pxxatomic_xchg') or CaseEqual(name, '__pxxatomic_cas')
         or CaseEqual(name, '__pxxatomic_add')
         or CaseEqual(name, '__pxxatomic_xchg64') or CaseEqual(name, '__pxxatomic_cas64')
         or CaseEqual(name, '__pxxatomic_add64') then
      begin
        { Atomic read-modify-write on addr^, returning the OLD value:
            __pxxatomic_xchg(addr, val)            *addr := val
            __pxxatomic_cas (addr, expected, newv)  if *addr=expected then *addr:=newv
            __pxxatomic_add (addr, delta)           *addr := *addr + delta
          The plain names are 32-bit ops; the *64 variants are full-width
          (Int64 counters / pointer-sized slots). The op is baked at parse
          time; lowers to IR_ATOMIC. }
        node := AllocNode(AN_ATOMIC);
        ASTTk[node] := Ord(tyInt64);
        if CaseEqual(name, '__pxxatomic_xchg') then ASTIVal[node] := ATOMIC_XCHG
        else if CaseEqual(name, '__pxxatomic_cas') then ASTIVal[node] := ATOMIC_CAS
        else if CaseEqual(name, '__pxxatomic_add') then ASTIVal[node] := ATOMIC_ADD
        else if CaseEqual(name, '__pxxatomic_xchg64') then ASTIVal[node] := ATOMIC_XCHG64
        else if CaseEqual(name, '__pxxatomic_cas64') then ASTIVal[node] := ATOMIC_CAS64
        else ASTIVal[node] := ATOMIC_ADD64;
        Next; { consume the intrinsic name }
        Expect(tkLParen, '(');
        lastArg := -1;
        nArgs := 0;
        repeat
          ParseExpr;
          exprNode := CurASTNode;
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := exprNode;
          if lastArg = -1 then
            ASTLeft[node] := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
        until not Eat(tkComma);
        Expect(tkRParen, ')');
        if (ASTIVal[node] = ATOMIC_CAS) or (ASTIVal[node] = ATOMIC_CAS64) then
        begin
          if nArgs <> 3 then Error('__pxxatomic_cas: expects 3 arguments (addr, expected, newval)');
        end
        else if nArgs <> 2 then Error('__pxxatomic_xchg/add: expects 2 arguments (addr, val)');
        LastExprTk := tyInt64;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__resources') then
      begin
        Next; { consume '__resources' }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_RESOURCES);
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, '__rttireg') then
      begin
        Next; { consume '__rttireg' }
        if CurTok.Kind = tkLParen then
        begin
          Next;
          Expect(tkRParen, ')');
        end;
        node := AllocNode(AN_RTTI_REG);
        ASTTk[node] := Ord(tyPointer);
        CurASTNode := node;
        Exit;
      end;

      if qUnit >= 0 then
      begin
        idx := FindSymInUnit(name, qUnit);
        procIdx := FindProcInUnit(name, qUnit);
      end
      else if qUnit = -2 then
      begin
        { `System.X`: the builtin/global must win over any same-named
          local/param — Synapse's `System.Length(buf)` inside
          SendBufferTo(...; Length: Integer). Leave idx unbound so the
          builtin branches below take the name. }
        idx := -1;
        { NOT FindProcBound: this arm exists so an explicit `System.X` reaches
          the BUILTIN, and scope hiding would hand back the used unit's
          same-named routine instead — `System.Random(i+1)` stopped reaching
          System's generator (test_builtin_name_demote). A qualified call names
          its scope; hiding is for unqualified ones. }
        procIdx := FindProc(name);
      end
      else
      begin
        idx := FindSym(name);
        { a BARE reference binds under the scope-hiding rule — FindProc alone
          answers with the set's representative, which ignores `uses` order.
          In NilPy user code a pylib row must match EXACTLY: Python is
          case-sensitive and pylib IS its builtin namespace. }
        if NilPyUserCode then procIdx := FindProcNilPyBound(name)
        else procIdx := FindProcBound(name);
      end;

      { The EXPRESSION half of the own-field-beats-a-unit-name rule; the
        statement half sits on the assignment path in ParseStatementAST. Skipped
        for an explicitly qualified `unit.Name`, which asks for that unit's
        symbol by construction. }
      if qUnit < 0 then idx := OwnFieldBeatsSym(idx, name);

      { A NilPy program's OWN class beats a pylib routine of the same name.
        Shadowing a builtin is ordinary Python — `class Counter:`, `def list(...)`
        — and from that point on the name means the user's. pylib spells
        collections.Counter as overloaded FUNCTIONS, so `Counter` bound to those
        instead, and `Counter.k` on the user's class died with
        '"k": no such member on this record/class': an error about a MEMBER,
        which sends the reader to the class body rather than to the name
        (bug-nilpy-user-class-named-like-a-pylib-builtin-is-shadowed).

        UClsUnitIdx = -1 is "declared in the main program", so this only fires
        for a class the user wrote; a pylib class keeps losing to a pylib
        routine exactly as before, and Pascal is untouched. }
      { …matched EXACTLY. FindUClassInUnit is case-insensitive, Pascal-style, so
        a lowercase `def f` lost its proc to `class F` — and then, since classes
        became values, `f(1, 2)` compiled clean and raised "takes 0 positional
        arguments" from the ctor of a class the program never named. Python is
        case-sensitive: `f` and `F` are unrelated names and neither shadows the
        other. This is the site that decides it; PyIsClassTypeExact (typing),
        PyIsExactCtorName (construction) and the two guards added beside them
        are the same rule at the other four
        (bug-nilpy-a-lowercase-name-is-hijacked-by-a-case-matching-class). }
      if NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and (idx < 0) and
         (FindUClassInUnit(name, -1) >= 0) and PyIsClassTypeExact(name) then
        procIdx := -1;

      { The Pascal twin of the rule above: a TYPE declared HERE beats a ROUTINE
        of the same name imported from a used unit. `type PI = ^Integer;` then
        `PI(pp)^` bound to System/math's paramless `Pi` and died with
        "no overload of PI matches these arguments — candidates: PI()", an error
        about arguments for a construct that has none, which sends the reader
        looking at the cast instead of at the name.

        Innermost declaration wins is the ordinary Pascal rule, and it is
        already applied here for routines (bug-p-program-function-does-not-shadow-
        used-unit) and for NilPy classes above. Types were the arm nobody wrote,
        so the only names that could collide were the ones an RTL unit happens
        to export as a function — `Pi` being the one people actually hit,
        because `PI` is the conventional spelling of `^Integer`.

        Deliberately narrow: only when the alias is declared in the unit being
        compiled AND the routine is not, and only in front of `(`, which is the
        one position where a type name is a CAST rather than a value. A type and
        a routine of one name in ONE scope is illegal, so this cannot pick
        between two local declarations.
        bug-a-a-source-type-alias-loses-to-a-used-units-function-in-a-cast }
      if (not NilPyUserCode) and (qUnit < 0) and (procIdx >= 0) and (idx < 0) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        aliasIdx := FindTypeAlias(name);
        if (aliasIdx >= 0) and (AliasUnitIdx[aliasIdx] = CurrentUnitIdx) and
           (ProcUnitIdx[procIdx] <> CurrentUnitIdx) then
          procIdx := -1;
      end;

      { A NilPy module-level `def` is NOT bound above its own `def` statement —
        Python rebinds the name when that statement RUNS, so a module-body call
        that precedes it still reaches whatever the name meant before.

        PyUserShadowsProc already answers that question, and it gates both the
        overload demote and every name-keyed intrinsic below. But each of those
        intrinsic guards ALSO requires `procIdx < 0`, and for a builtin that has
        no proc of its own name — `ord`, `chr`, `abs`, `set`, `id`, `hash`,
        `ascii`, `callable`, `iter`, `range`, … are lowered by NAME dispatch,
        not as pylib routines — the user's def is then the ONLY proc called
        `ord`, ordinary resolution found it from anywhere in the module, and the
        intrinsic never got the chance. `print(ord("A"))` above a `def ord(x)`
        printed the user's answer where CPython prints 65, silently. The
        positional rule was being enforced by COMPETITION, not by the gate, and
        it lapsed for exactly the builtins that have no competitor.
        bug-nilpy-intrinsic-only-builtin-is-shadowed-from-the-top-of-the-module

        So unbind the name here, where every intrinsic guard downstream reads
        it, and REBIND it just before the ordinary call paths (`sci :=
        FindStrConst(name)` below). Unbinding it permanently would turn a
        module-body forward call into a compile error, and CPython accepts one
        that never executes (`if False: helper()` above `def helper()`) — NilPy
        is upward compatible with CPython, so refusing that is not allowed.

        Module body only (CurProc < 0): inside a def body the code runs after
        the whole module has executed, so an ordinary forward reference between
        two defs is legal Python and must keep working. }
      { A LOCAL BINDING BEATS A `def` OF THE SAME NAME.

        In Python a `def` is not a namespace of its own -- it is a name binding
        like any other, and inside a function body a local binding shadows the
        module-level one for the WHOLE body. NilPy resolved a bare-name call
        against declared procedures first and only fell back to variables, so a
        `def` outranked every later rebinding. `normalise-dont-special-case`:
        one concept (a name that denotes something callable) served by two
        mechanisms, and the second one is the one that was broken.

        Silent, which is what made it expensive -- the WRONG function ran and
        returned a plausible value. It only turned loud where the two arities
        disagree, which is how it was found: webencodings' `iter_decode` does
        `decode = decoder.decode` and then `decode(b'', final=True)`, bound to
        the module-level `def decode(input, fallback_encoding, errors=...)`,
        and the compiler said `decode has no parameter named 'final'` -- a
        diagnostic that is CORRECT ABOUT THE WRONG CALLEE, which is why it read
        as a signature bug. That one line was the first wall on 12 of the 38
        remaining third-party corpus files.

        skLocal/skParam only, deliberately. Python's scoping makes a local
        binding unconditionally win for the whole body, so no ordering question
        arises and the rule needs no token positions. A MODULE-level rebinding
        (`f = o.f` after `def f`) is the same bug and is NOT fixed here: at
        module level the answer depends on which statement ran last, which this
        site cannot see. That arm stays open in the ticket rather than being
        guessed at.

        NOT fixable by re-ranking FindProc -- see the warning above MatchElig in
        symtab.inc: that was tried and broke the compiler's own self-compile and
        the NilPy stdlib, because FindProc returns an overload-set
        representative whose SIGNATURE callers read types off. It is not a "what
        does this name call" query. The decision belongs here.
        bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name }
      if NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and
         (idx >= 0) and (Syms[idx].Kind in [skLocal, skParam]) then
        procIdx := -1;

      pyLateDefPi := -1;
      if NilPyUserCode and (qUnit < 0) and (procIdx >= 0) and
         (ProcUnitIdx[procIdx] = -1) and (not PyDefBoundHere(procIdx)) and
         (not PyUserShadowsProc(name)) then
      begin
        pyLateDefPi := procIdx;
        procIdx := -1;
      end;

      { Bare class const inside a method body — `Result := Max` where TFoo declares
        `const Max`. FPC scope order: a genuine local/param shadows it, but a class
        const BEATS a unit global of the same name (repro 2: a method's `Size` is
        the class const 777, not the unit const 10). So fire whenever the name did
        not bind to a local/param. Walks own class then ancestors; qualified
        `TFoo.Max` is handled separately in ParseLValueAST.
        bug-pascal-class-const-visibility. }
      if (qUnit < 0) and (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) and
         (not ((idx >= 0) and (Syms[idx].Kind in [skLocal, skParam]))) then
      begin
        ccReg := FindClassConst(CurMethClass - REC_UCLASS_BASE, name);
        if ccReg >= 0 then
        begin
          if StrictVisibility then
            EnforceMemberVis(ClassConstCi[ccReg], ClassConstVis[ccReg], name);
          ccKey := ClassConstMangle(ClassConstCi[ccReg], name);
          ccNode := EmitClassConstNode(ccKey, ccTk);
          if ccNode >= 0 then
          begin
            Next;
            CurASTNode := ccNode;
            LastExprTk := ccTk;
            Exit;
          end;
          { No literal backing — a TYPED class const is writable STORAGE, so it
            has a symbol. Route the BARE in-method reference through it: the
            name is mangled now, so plain FindSym on the source spelling misses
            and without this the const would be invisible inside its own class's
            methods. ParseLValueAST re-entry gets the suffixes (`TAG[1]`) too.
            bug-p-two-classes-typed-consts-of-the-same-name-collide }
          ccNode := FindSym(ccKey);
          if ccNode >= 0 then
          begin
            { Note the order: capture the identifier's token index, CONSUME it,
              and only then re-enter. ParseLValueAST's contract is that the
              caller has already consumed the name (it reads the spelling from
              the token INDEX it is handed, not from the cursor) — the literal
              path above does its own `Next` for the same reason. Re-entering
              without consuming left `N` as the current token, so an enclosing
              `Writeln('w: ', N)` reported `Expected: ), but got: N`. }
            prevTok := TokPos - 1;
            Next;
            CurASTNode := ParseLValueAST(ccNode, prevTok);
            LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
            Exit;
          end;
        end;
      end;

      { A bare class-reference OPERATION inside a method body -- implicit Self:
        `ClassName`, `ClassType`, `InheritsFrom(C)` with no receiver (fpcunit's
        TTestCase.GetTestName reads a bare ClassName).

        GenMakeImplicitMetaclass already yields the right blob for either method kind:
        an instance method's Self walks to its RUNTIME class, a class method's Self IS
        the class. So this is the same operation as the qualified form, with the
        receiver implied. A member of that name on the class still wins. }
      if (procIdx < 0) and (idx < 0) and (qUnit < 0) and
         (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) and
         IsClassRefOpName(name) and
         (FindUMeth(CurMethClass - REC_UCLASS_BASE, name) < 0) and
         (FindUField(CurMethClass - REC_UCLASS_BASE, name) < 0) then
      begin
        smSelfNode := GenMakeImplicitMetaclass;
        if smSelfNode >= 0 then
        begin
          Next;                    { consume the operation name }
          node := GenMakeClassRefOp(smSelfNode, name, tk);
          if node >= 0 then
          begin
            node := ParseClassRefOpTail(node, tk);
            LastExprTk := tk;
            CurASTNode := node;
            Exit;
          end;
        end;
      end;

      { Bare call to a sibling CLASS (static) method, from inside a class method.

        CurSelfClass is deliberately unset in a `class procedure` -- it is static and
        has no Self -- so every implicit-Self dispatch above is skipped, and the name
        used to fall through to "undefined variable". But a static method needs no
        Self: it is callable exactly like a plain proc, so all that was missing was
        finding it. Bind procIdx and let the ordinary call machinery (args, defaults,
        overloads) do the rest.

        Keyed on CurMethClass, which IS set for both method kinds -- the same reason
        the bare `class var` lookup uses it. Only STATIC methods qualify: an instance
        method reached from a class method has no instance to run on, and must keep
        failing. A local/param (idx >= 0), a real proc (procIdx >= 0) or a unit
        qualifier all still win. This is fpcunit's TAssert.FailEquals calling Fail. }
      if (procIdx < 0) and (idx < 0) and (qUnit < 0) and
         (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) then
      begin
        smmiS := FindUMethOverloadAhead(CurMethClass - REC_UCLASS_BASE, name, CountCallArgsAhead);
        if (smmiS >= 0) and UMthIsStatic[smmiS] and (UMthProc_[smmiS] >= 0) then
        begin
          EnforceMethVis(smmiS, name);
          smSelfNode := GenMakeImplicitMetaclass;
          if smSelfNode >= 0 then
          begin
            Next;                 { consume the method name }
            GenVirtSlot := UMthVirSlot[smmiS];
            node := GenMakeStaticMethodCall(UMthProc_[smmiS], smSelfNode);
            LastExprTk := Procs[UMthProc_[smmiS]].RetType;
            CurASTNode := node;
            Exit;
          end;
        end;
      end;

      if (idx >= 0) and (Syms[idx].TypeKind = tyAuto) then
        Error('use of auto variable before type is inferred');

      { FPC scoping: inside a method, the enclosing class's own method shadows
        a same-name plain proc from an outer/uses scope (innermost scope wins —
        sysutils.Move vs TGame.Move). Clearing procIdx routes the name to the
        implicit-Self dispatch below instead of plain-proc overload matching,
        which knows nothing of methods. A local var/param (idx >= 0) still
        shadows the method; a unit-qualified name (qUnit >= 0) stays explicit.
        See bug-implicit-self-method-loses-to-unit-proc. }
      { qUnit = -1 only: `System.X` (qUnit = -2) names the RTL routine
        explicitly, so the class method must not shadow it — the statement-side
        twin has the same guard (fpjson's System.Delete vs TJSONArray.Delete). }
      { …but NOT in NilPy, where a bare name is NEVER a method: Python reaches
        a method only through `self.`, so an unqualified call names the
        module-level function even when the class has one of the same name.
        songformatter's `def select_image(self): select_image()` is exactly
        that — a method delegating to the module function it shadows — and
        routing it to implicit-Self dispatch made it a call of ITSELF with the
        wrong arity. }
      { …and NOT isNilPy, which is true for the WHOLE compilation. A Pascal
        RTL unit pulled in behind a NilPy program is still Pascal and still
        wants FPC's shadowing rule: lib/rtl/classes.pas `uses sysutils`, so
        TStrings.SetValueFromIndex's bare `Delete(Index)` bound
        sysutils.Delete(var s; index, count) and the unit failed to compile at
        all under NilPy while compiling clean under Pascal — the same file, the
        same pin. NilPyUserCode is the predicate that asks what was actually
        meant ("code the NilPy user wrote", PyExprMode telling a .py module
        body from a Pascal unit). bug-a-the-import-escape-hatch-fails-on-classes-pas }
      if (procIdx >= 0) and (qUnit = -1) and (idx < 0) and (not NilPyUserCode) and
         (CurSelfClass >= REC_UCLASS_BASE) and
         (FindUMeth(SelfMemberCi(name), name) >= 0) then
        procIdx := -1;

      { `Eof` (standard input), no args -> Boolean. The textfile RTL declares
        `Eof(var f: Text)`, but a bare `Eof` / `Eof()` cannot bind that file arg,
        so the no-arg form routes to stdin Eof regardless of that proc; the
        `Eof(f)` form (a `(` followed by an argument) falls through to the real
        routine. `idx < 0` keeps a user variable named Eof winning as a var.
        Lowers to the special-builtin call id 210 (EmitEof). }
      if CaseEqual(name, 'Eof') and (idx < 0) and
         (Tokens[TokPos].Kind <> tkLParen) then
      begin
        Next;                                  { consume Eof }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -210;
        ASTTk[node] := Ord(tyBoolean);
        ASTLeft[node] := -1;
        CurASTNode := node;
        LastExprTk := tyBoolean;
        Exit;
      end;
      if CaseEqual(name, 'Eof') and (idx < 0) and
         (Tokens[TokPos].Kind = tkLParen) and (Tokens[TokPos + 1].Kind = tkRParen) then
      begin
        Next; Next; Next;                      { consume Eof ( ) }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -210;
        ASTTk[node] := Ord(tyBoolean);
        ASTLeft[node] := -1;
        CurASTNode := node;
        LastExprTk := tyBoolean;
        Exit;
      end;

      { `Supports(obj, IFoo): Boolean` — the function form of `obj is IFoo` —
        and `Supports(obj, IFoo, Intf)`, which ALSO hands back the interface.
        The two-argument form reuses the interface implementation query
        (AN_IS_TEST). The three-argument form is FPC's own definition spelled
        out: `Result := (Instance <> nil) and Instance.GetInterface(IID, Intf)`,
        so it lowers to the very call `obj.GetInterface(IFoo, Intf)` builds —
        __pxxGetInterface(obj, @guid, @Intf) — rather than growing a second
        interface-lookup path beside the one that already exists.
        feature-a-supports-three-argument-form }
      if CaseEqual(name, 'Supports') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Supports: expected interface name');
        ci := FindUClass(CurTok.SVal);
        if (ci < 0) or not UClsIsInterface[ci] then Error('Supports: second argument must be an interface');
        Next;
        if CurTok.Kind = tkComma then
        begin
          if not UClsHasGuid[ci] then
            Error('Supports: the three-argument form needs the interface to declare a GUID');
          supPi := FindProc('__pxxGetInterface');
          if supPi < 0 then Error('Supports: the interface runtime is not linked');
          Next;                                { consume the ',' }
          node := AllocNode(AN_CALL);
          ASTIVal[node] := supPi;
          ASTTk[node] := Ord(Procs[supPi].RetType);
          argSeq := AllocNode(AN_ARG);         { arg 0 = the instance }
          ASTLeft[argSeq] := exprNode;
          ASTLeft[node] := argSeq;
          valNode := AllocNode(AN_ADDR);       { arg 1 = @<the GUID blob> }
          ASTLeft[valNode] := AllocNode(AN_GUIDCONST);
          ASTIVal[ASTLeft[valNode]] := InternGuidBlob(ci);
          ASTTk[ASTLeft[valNode]] := Ord(tyRecord);
          ASTSLen[ASTLeft[valNode]] := REC_UCLASS_BASE + FindUClass('TGuid');
          ASTTk[valNode] := Ord(tyPointer);
          exprNode := AllocNode(AN_ARG);
          ASTLeft[exprNode] := valNode;
          ASTRight[argSeq] := exprNode;
          ParseExpr;                           { arg 2 = @<the interface variable> }
          valNode := AllocNode(AN_ADDR);
          ASTLeft[valNode] := CurASTNode;
          ASTTk[valNode] := Ord(tyPointer);
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := valNode;
          ASTRight[exprNode] := argSeq;
          Expect(tkRParen, ')');
          CurASTNode := node; LastExprTk := tyBoolean;
          Exit;
        end;
        Expect(tkRParen, ')');
        node := AllocNode(AN_IS_TEST);
        ASTLeft[node] := exprNode; ASTIVal[node] := ci; ASTTk[node] := Ord(tyBoolean);
        CurASTNode := node; LastExprTk := tyBoolean;
        Exit;
      end;

      { GetMem(size): function form, soft keyword (statement form GetMem(p, n)
        lives in ParseStatementAST). }
      if CaseEqual(name, 'GetMem') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr;
        valNode := CurASTNode;
        Expect(tkRParen, ')');
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkGetMem);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        LastExprTk := tyPointer;
        Exit;
      end;


      if CaseEqual(name, 'SysOpen') and SoftIntrinsicOpenSym(name, qUnit) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Soft-keyword intrinsic: the spelling lexes as a plain ident and is
          dispatched here on the NAME, so `function SysRead...` and a variable
          called SysClose are legal. A user routine or an in-scope symbol
          shadows it; `System.X` reaches the intrinsic anyway.
          bug-p-sysopen-intrinsic-shadows-a-user-function-name }
        Next; Expect(tkLParen, '(');
        if CurTok.Kind <> tkIdent then Error('SysOpen: expected string var');
        idx := FindSym(CurTok.SVal); Next;
        valNode := ParseLValueAST(idx, TokPos - 2);
        if (idx < 0) or ((not TypeIsFrozenString(Syms[idx].TypeKind)) and
                         (Syms[idx].TypeKind <> tyAnsiString)) then Error('SysOpen: not a string var');
        Expect(tkComma, ',');

        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
        ParseExpr;
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := CurASTNode;
        ASTRight[argSeq] := argSeq2;
        Expect(tkRParen, ')');

        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSysOpen);
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, 'SysRead') and SoftIntrinsicOpenSym(name, qUnit) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Soft-keyword intrinsic: the spelling lexes as a plain ident and is
          dispatched here on the NAME, so `function SysRead...` and a variable
          called SysClose are legal. A user routine or an in-scope symbol
          shadows it; `System.X` reaches the intrinsic anyway.
          bug-p-sysopen-intrinsic-shadows-a-user-function-name }
        Next; Expect(tkLParen, '(');
        ParseExpr;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('SysRead: expected array var');
        idx := FindSym(CurTok.SVal); Next;
        valNode := ParseLValueAST(idx, TokPos - 2);
        if (idx < 0) or not Syms[idx].IsArray then Error('SysRead: not an array var');
        Expect(tkComma, ',');

        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := valNode;
        ASTRight[argSeq] := argSeq2;
        ParseExpr;
        argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := CurASTNode;
        ASTRight[argSeq2] := argSeq3;
        Expect(tkRParen, ')');

        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSysRead);
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end;

      if CaseEqual(name, 'SysWrite') and SoftIntrinsicOpenSym(name, qUnit) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Soft-keyword intrinsic: the spelling lexes as a plain ident and is
          dispatched here on the NAME, so `function SysRead...` and a variable
          called SysClose are legal. A user routine or an in-scope symbol
          shadows it; `System.X` reaches the intrinsic anyway.
          bug-p-sysopen-intrinsic-shadows-a-user-function-name }
        Next; Expect(tkLParen, '(');
        ParseExpr;
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        Expect(tkComma, ',');
        if CurTok.Kind <> tkIdent then Error('Syswrite: expected array var');
        idx := FindSym(CurTok.SVal); Next;
        valNode := ParseLValueAST(idx, TokPos - 2);
        if (idx < 0) or not Syms[idx].IsArray then Error('Syswrite: not an array var');
        Expect(tkComma, ',');

        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := valNode;
        ASTRight[argSeq] := argSeq2;
        ParseExpr;
        argSeq3 := AllocNode(AN_ARG); ASTLeft[argSeq3] := CurASTNode;
        ASTRight[argSeq2] := argSeq3;
        Expect(tkRParen, ')');

        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkSyswrite);
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end;

      { ParamCount / ParamStr (and the pxx spellings ArgCount / ArgStr): soft-
        keyword intrinsics. They used to lex as tkArgCount/tkArgStr, which made
        the SPELLING unusable as a name anywhere -- `procedure ParamStr;` failed
        at the declaration with `expected name`, and FPC's own custapp declares
        methods called exactly that. Now they are plain idents dispatched on the
        name, with a user routine or an in-scope symbol shadowing them and
        `System.ParamStr` as the escape hatch, like every other soft intrinsic.

        NO '(' REQUIREMENT ON ParamCount, unlike Ord/Chr/Length below: FPC's
        ParamCount is routinely written bare (`for i := 1 to ParamCount do`), so
        the lookahead that disambiguates the others would break the common
        spelling. The shadow test alone carries it -- which is correct, because a
        bare name that is NOT shadowed can only be the intrinsic.
        bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names }
      if (CaseEqual(name, 'ParamCount') or CaseEqual(name, 'ArgCount')) and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) then
      begin
        Next;
        if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgCount);
        { ParamCount is an Integer, and the node has to SAY so. Left unset it
          defaulted to tyUnknown, and anything that materialises the value into a
          hidden temp copied that: `for i := 0 to ParamCount do` gave the loop
          LIMIT temp no type. x86-64 and the other backends do not inspect it and
          happened to work; i386 checks every symbol it touches, so it refused —
          which is why `uses pylib` could not be built for i386 AT ALL (pylib's
          pysys_argv is exactly this loop), taking base64, http and
          examples/net/httpdemo.pas with it, and every NilPy program besides.
          The tkArgStr arm below never had the bug because it allocates its
          destination temp explicitly typed. Hoisting the limit into a variable,
          or using a USER function as the limit, both worked — that pair is what
          localised it here rather than to the for-loop lowering.
          bug-a-paramcount-node-has-no-type-so-i386-refuses-any-pylib-user }
        ASTTk[node] := Ord(tyInteger);
        CurASTNode := node;
        Exit;
      end;

      if (CaseEqual(name, 'ParamStr') or CaseEqual(name, 'ArgStr')) and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        { Inline ParamStr(i): the 2-arg ArgStr(i, var) codegen needs a destination
          string. Synthesize a hidden frozen-string temp, copy argv[i] into it
          (EmitArgvToString — a frozen buffer write, no managed release, so the temp
          needs no nil-init), and yield the temp. Lets ParamStr(i) be used directly
          in any expression (comparison, argument), not only as an assignment RHS.
          The temp is tyString (frozen) even under managed strings, matching the
          `String` keyword temp above. }
        Next; Expect(tkLParen, '(');
        ParseExpr;                            { index expression }
        Expect(tkRParen, ')');
        op := AllocVar('', tyString);
        { 2-arg ArgStr call: arg0 = index, arg1 = the temp (lvalue) }
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        identNode := AllocNode(AN_IDENT);
        ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := identNode;
        ASTRight[argSeq] := argSeq2;
        node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkArgStr);
        ASTLeft[node] := argSeq;
        { AN_STR_FROM_CHAR: Left = the ArgStr side-effect, Right = read the temp. }
        left := AllocNode(AN_STR_FROM_CHAR);
        ASTLeft[left] := node;
        identNode := AllocNode(AN_IDENT);
        ASTIVal[identNode] := op; ASTTk[identNode] := Ord(Syms[op].TypeKind);
        ASTRight[left] := identNode;
        ASTTk[left] := Ord(Syms[op].TypeKind);
        { `ParamStr(i)[1]` — the SUBSCRIPT this arm used to leave in the token
          stream. Every other string value already indexes: a literal has its own
          loop above, a user function and `Copy` go through the call-result path,
          and all three end at GenMakeStringValueIndex, which is what this calls.
          NOT a sixth hand-rolled `[` walker — refactor-p-three-hand-rolled-postfix-loops
          counts five already, and the helper is where the temp and the
          side-effect ordering are decided once.

          The old behaviour was not a parse error, which is why it survived:
          returning here with `[` pending left it to whatever came next, and in
          ASSIGNMENT-STATEMENT position that was ParseStatementAST's catch-all
          `else`, which skipped to the `;` in silence. So `cc := ParamStr(0)[1]`
          stored the low byte of the string POINTER — a different wrong character
          on every run — while `WriteLn(ParamStr(0)[1])` refused loudly, because
          an argument list has no catch-all. One defect, two faces, and the loud
          face is the one that got filed.
          bug-p-a-builtin-call-result-cannot-be-indexed-inside-parentheses }
        if (CurTok.Kind = tkLBrack) and NodeIsIndexableStringValue(left) then
        begin
          left := GenMakeStringValueIndex(left);
          CurASTNode := left;
          LastExprTk := tyChar;
        end
        else
          CurASTNode := left;
        Exit;
      end;

      { Ord(x)/Chr(x): soft-keyword intrinsics (same recipe as Length below —
        plain idents, name dispatch, user proc / in-scope symbol shadows,
        must be followed by '('). }
      if (CaseEqual(name, 'Ord') or CaseEqual(name, 'Chr')) and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        if CaseEqual(name, 'Chr') then
        begin op := Ord(tkChr); LastExprTk := tyChar; end
        else
        begin op := Ord(tkOrd); LastExprTk := tyInteger; end;
        Next; Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        { `Chr(<constant>)` IS a character constant, and `Ord(<constant>)` an
          integer one — fold rather than emit a call. Not an optimisation: the
          char-constant-to-PChar conversion keys on IsCharLitNode, i.e. on the
          node being a literal, so `Show(Chr(45))` through a `PChar` parameter
          passed the ORDINAL and SEGFAULTED while `Show('-')`, `Show(#45)` and
          `Show(Dash)` were all already right. FPC's rule, measured: a character
          CONSTANT converts and `Chr(i)` for a variable i does not — it is
          "Incompatible type for arg no. 1: Got Char, expected PChar" there, and
          it is refused here too, in CoerceCharLitArg.

          Ord is folded in the same breath for the same reason its sibling is:
          they are one arm, and leaving half of it emitting a call is how the
          next reader learns the wrong rule.
          bug-p-three-mechanisms-decide-what-becomes-a-pchar-and-they-disagree }
        if (CurASTNode >= 0) and (ASTKind[CurASTNode] = AN_INT_LIT) then
        begin
          node := AllocNode(AN_INT_LIT);
          if op = Ord(tkChr) then
          begin
            { a Char is one byte here, so the fold truncates exactly as a store
              into a Char does }
            ASTIVal[node] := ASTIVal[CurASTNode] and 255;
            ASTTk[node]   := Ord(tyChar);
          end
          else
          begin
            ASTIVal[node] := ASTIVal[CurASTNode];
            ASTTk[node]   := Ord(tyInteger);
          end;
          CurASTNode := node;
          Exit;
        end;
        node := AllocNode(AN_CALL); ASTIVal[node] := -op;
        if op = Ord(tkChr) then ASTTk[node] := Ord(tyChar) else ASTTk[node] := Ord(tyInteger);
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := CurASTNode;
        ASTLeft[node] := argSeq;
        CurASTNode := node;
        Exit;
      end;

      { High(x): soft-keyword intrinsic. High(arr) := Length(arr) - 1 — reuses
        the Length call + a subtraction, so no new IR/codegen; works for open
        arrays, dyn arrays and (via the folds) static arrays alike.

        `(qUnit = -2)` is the SYSTEM-QUALIFIER EXEMPTION, and the same expression
        appears verbatim at every soft-keyword intrinsic here — grep it. Writing
        `System.High(a)` names the builtin on purpose, exactly as `System.Move`
        does inside a class with its own Move, so a same-named local must not
        take it: `var High: Integer` made `System.High(a)` report "undefined
        variable (High)" where FPC 3.2.2 prints the bound.

        It is spelled out per site because each intrinsic tests its own
        preconditions. That is also how it drifted: `Ord`/`Chr` and `Length` had
        it (someone hit Synapse's `System.Length(buf)`), and `High`, `Low`,
        `GetMem`, `TypeInfo` and the ident-spelled ordinal casts did not — every
        site broken until somebody tripped over that one. Found by enumerating
        the guards rather than by falling over them.
        meta-a-second-paths-reimplement-the-first-paths-decisions }
      if CaseEqual(name, 'High') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        { `High([e1,..,en])` -- an open-array constructor, not a set. }
        if TryFoldBracketCtorLen(bcN) then
        begin
          FoldBracketCtorBound(bcN - 1);
          Exit;
        end;
        { High(ordinalType) / High(enum) folds to a compile-time constant. }
        if TryFoldHighLowType(True, node) then
        begin
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := IntToTypeKind(ASTTk[node]);
          Exit;
        end;
        { A STRING-shaped operand — a literal, a parenthesised expression, or a
          name with an operator after it — is legal in fpc and was refused here
          for every spelling: `if CurTok.Kind <> tkIdent then Error(...)`.
          `High(F)` escaped only because a NAME starts with an identifier.
          HighLowOperandIsExpr decides by SHAPE rather than by the first token,
          so `sh + 'x'` reaches the expression path instead of stopping the
          lvalue parser at `sh`; and `High(3)` still reaches the arms below and
          keeps its clear error rather than reaching the runtime Length tail and
          producing garbage. }
        if HighLowOperandIsExpr then
        begin
          idx := -1;
          ParseExpr;
          valNode := CurASTNode;
        end
        else
        begin
        if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type');
        idx := FindSym(CurTok.SVal);
        if (idx < 0) and (FindProc(CurTok.SVal) >= 0) then
        begin
          { `High(MakeArr)` — the operand is a CALL, not a variable. This arm
            insisted on an lvalue and handed FindSym's -1 straight to
            ParseLValueAST, so a perfectly ordinary array-returning function
            came back as `undefined variable (MakeArr)`. Length two arms below
            has always used ParseExpr for exactly this reason and works on the
            same operand — one intrinsic accepting what its sibling rejects,
            over the same expression.
            Every fold below is guarded on `idx >= 0`, so a call falls through
            to the runtime Length-1 tail, which is the right answer for a dyn
            array and is what Length itself already lowers to.
            compat-pascal-index-a-function-call-result }
          ParseExpr;
          valNode := CurASTNode;
        end
        else
        begin
          Next;
          { See Length below: ParseLValueAST handles implicit-Self + undefined. }
          valNode := ParseLValueAST(idx, TokPos - 2);
        end;
        end;
        Expect(tkRParen, ')');
        { …and what KIND of value the operand turned out to be, which is what
          decides a STRING's bounds. Computed once, read by the frozen and the
          managed arm below.

          An ARRAY operand is excluded outright — every array arm above has
          already claimed those, and a dyn array of AnsiString has ELEMENT type
          tyAnsiString on its symbol, so without `IsNodeArray` a `array of
          string` FIELD would have been read as a string and answered Length
          instead of Length-1.

          The FROZEN arm additionally insists on a plain variable, because that
          is the only operand whose declared CAPACITY is on hand: a
          `string[6]`-returning FUNCTION has no ProcRet capacity row, and
          answering the 255 default there would turn today's too-small bound
          into a too-large one — a loop reading off the end rather than stopping
          early, which is the worse of the two wrongs. It keeps the Length-1
          tail and is recorded as a gap on the ticket. }
        hlIsArrOp := IsNodeArray(valNode) or
                     ((idx >= 0) and (idx < SymCount) and Syms[idx].IsArray);
        if (idx >= 0) and (idx < SymCount) and (ASTKind[valNode] = AN_IDENT) and
           (ASTIVal[valNode] = idx) then
          hlValTk := Syms[idx].TypeKind
        else
          hlValTk := IntToTypeKind(ASTTk[valNode]);
        hlIsFrozen := (not hlIsArrOp) and TypeIsFrozenString(hlValTk) and
                      (idx >= 0) and (idx < SymCount) and
                      (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx);
        hlIsAnsi := (not hlIsArrOp) and (hlValTk = tyAnsiString);
        hlCap := DEFAULT_STR_CAP;
        if hlIsFrozen and (SymStrCap[idx] > 0) then hlCap := SymStrCap[idx];
        { High of a whole 1-D static array folds to its upper index bound (see
          the Length fold below for why the runtime path can't serve a static
          array). The lower bound is in Syms[].ConstVal (0 for a 0-based
          array), so the upper bound is ConstVal + count - 1 — NOT count - 1,
          which silently miscompiled non-zero-based arrays (array[5..9] -> 4
          instead of 9). }
        if (idx >= 0) and (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx) and
           Syms[idx].IsArray and (Syms[idx].ArrLen >= 0) and (Syms[idx].Kind <> skParam) and
           (SymArrNDims[idx] <= 1) then
        begin
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := Syms[idx].ConstVal + Syms[idx].ArrLen - 1; ASTTk[CurASTNode] := Ord(tyInteger);
          StampArrIdxType(CurASTNode, SymArrIdxTk[idx], SymArrIdxEnumId[idx]);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end
        else if (idx >= 0) and (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx) and
                Syms[idx].IsArray and (Syms[idx].ArrLen >= 0) and (Syms[idx].Kind <> skParam) and
                (SymArrNDims[idx] >= 2) then
        begin
          { High of a WHOLE multi-dim static array = the FIRST dimension's upper
            bound (FPC: `High(m)` reports dim 0). The runtime -tkLength path reads
            a [data-8] header a static array has none of, so multi-dim used to
            return -1. First-dim low/span live in SymArrDim{Lo,Span}[sym*MAX+0]. }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := SymArrDimLo[idx * MAX_ARR_DIMS] + SymArrDimSpan[idx * MAX_ARR_DIMS] - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
          StampArrIdxType(CurASTNode, SymArrIdxTk[idx], SymArrIdxEnumId[idx]);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end
        else if (ASTKind[valNode] = AN_FIELD) and
                RecFieldIsArray(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) and
                (RecFieldArrLen(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) >= 0) and
                (RecFieldDynDepth(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) = 0) then
        begin
          { High of a whole fixed-size record/class FIELD array folds like the
            plain-var case; the runtime Length path would read a [data-8]
            header a raw field has none of, so High(ctx.Buffer) returned
            garbage/-1 and synacode's SHA1 never zeroed its buffers. Field
            arrays record only their COUNT (low bound normalised to 0). }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] :=
            RecFieldArrLen(ResolveNodeRec(ASTLeft[valNode]), GetASTIdentName(valNode)) - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else if DerefPtrArrayInfo(valNode, dpaCount, dpaLo, dpaFlat) then
        begin
          { `High(p^)` over a pointer to a named FIXED array — same fold as the
            whole-static-array arm, off the pointer symbol's pointee metadata. }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := dpaLo + dpaCount - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else if NodeFixedRowInfo(valNode, frRowLen, frRowLo) then
        begin
          { `High(d[i])` where d is `array of array[lo..hi] of Base`. The row's
            extent is on the base symbol and never on this node, so this fell to
            the Length-1 tail and answered -1 — `for j := Low(r) to High(r)`
            simply did not run. See NodeFixedRowInfo. }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := frRowLo + frRowLen - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else if (idx >= 0) and (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx) and
                TryOrdinalVarBound(idx, True, hlBoundV, hlBoundTk, hlBoundEid) then
        begin
          { High of an ordinal VARIABLE is its type's upper bound. Without this
            arm it fell into the Length-1 fallback below and answered -1 for
            every scalar -- see TryOrdinalVarBound.
            The enum identity rides alongside the kind, the same pair
            TryFoldHighLowType stamps for the TYPE-NAME spelling: without it
            `High(a)` printed 2 where fpc prints wed, while `High(D)` was
            right, so one intrinsic answered differently for two spellings of
            the same question. bug-p-low-and-high-of-an-enum-variable-print-the-ordinal }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := hlBoundV; ASTTk[CurASTNode] := Ord(hlBoundTk);
          if hlBoundEid >= 0 then ASTSemId[CurASTNode] := hlBoundEid;
          LastExprTk := hlBoundTk;
          Exit;
        end
        else if ASTKind[valNode] = AN_STR_LIT then
        begin
          { A string CONSTANT is an array-of-CHAR constant in fpc, so its bounds
            are its OWN length, 0-based: High('abc') = 2. This has to sit ABOVE
            the frozen arm — a literal's type kind is tyString, and the frozen
            arm's 255 default would claim it and answer 255.

            Keyed on the NODE, not on the token, deliberately: `High(('ab'))` is
            1 in fpc too, so a token test would have had to know about
            parentheses; and `High('ab' + s)` must NOT land here, because a
            concatenation is a string EXPRESSION and takes the managed or frozen
            base below. Low needs no twin — its tail already answers 0, which is
            the same 0 a literal wants.
            bug-p-high-and-low-refuse-every-non-identifier-operand }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := ASTSLen[valNode] - 1;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else if hlIsFrozen then
        begin
          { A FROZEN string's bounds are its declared CAPACITY, not its current
            length — fpc answers 10 for `sh: string[10]` and 255 for a
            ShortString, and 0-based, because index 0 is the length byte. The
            Length-1 tail below answered 1 for a two-character string[10] and 2
            for a three-character ShortString. SymStrCap 0 means the kind
            default. bug-p-high-and-low-of-a-string-are-off-by-one }
          CurASTNode := AllocNode(AN_INT_LIT);
          ASTIVal[CurASTNode] := hlCap;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end
        else if hlIsAnsi then
        begin
          { A MANAGED string is 1-BASED. `s[1]` is its first character in pxx
            exactly as in fpc, so its last valid index IS Length(s) — not
            Length(s)-1, which is the tail below and is the answer for a
            0-based dynamic array. So `for i := Low(s) to High(s) do Write(s[i])`
            read s[0] and dropped the last character: a silent wrong value in
            the canonical spelling, in a shape that compiled.
            bug-p-high-and-low-of-a-string-are-off-by-one }
          node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
        end
        else
        begin
          node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
          ASTLeft[node] := argSeq;
          valNode := AllocNode(AN_INT_LIT); ASTIVal[valNode] := 1; ASTTk[valNode] := Ord(tyInteger);
          CurASTNode := AllocNode(AN_BINOP);
          ASTIVal[CurASTNode] := Ord(tkMinus);
          ASTLeft[CurASTNode] := node; ASTRight[CurASTNode] := valNode;
          ASTTk[CurASTNode] := Ord(tyInteger);
        end;
        { read the folded node rather than asserting Integer: a char-, Boolean-
          or enum-indexed array's bound is typed by its INDEX, and the arms
          above stamp that on the node. Every other arm still builds a
          tyInteger node, so this is the same answer for them. }
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;

      { Low(x): soft-keyword intrinsic. Low(ordinalType)/Low(enum) folds to a
        compile-time constant. Low of an array variable is the declared lower
        index bound — Syms[].ConstVal for a 1-D static array (array[5..9] ->
        5); 0 for open/dynamic arrays and 0-based statics. }
      if CaseEqual(name, 'Low') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        { `Low([e1,..,en])` -- an open-array constructor, not a set. }
        if TryFoldBracketCtorLen(bcN) then
        begin
          FoldBracketCtorBound(0);
          Exit;
        end;
        if TryFoldHighLowType(False, node) then
        begin
          Expect(tkRParen, ')');
          CurASTNode := node;
          LastExprTk := IntToTypeKind(ASTTk[node]);
          Exit;
        end;
        { A STRING-shaped operand — a literal, a parenthesised expression, or a
          name with an operator after it — is legal in fpc and was refused here
          for every spelling: `if CurTok.Kind <> tkIdent then Error(...)`.
          `High(F)` escaped only because a NAME starts with an identifier.
          HighLowOperandIsExpr decides by SHAPE rather than by the first token,
          so `sh + 'x'` reaches the expression path instead of stopping the
          lvalue parser at `sh`; and `High(3)` still reaches the arms below and
          keeps its clear error rather than reaching the runtime Length tail and
          producing garbage. }
        if HighLowOperandIsExpr then
        begin
          idx := -1;
          ParseExpr;
          valNode := CurASTNode;
        end
        else
        begin
        if CurTok.Kind <> tkIdent then Error('Low: expected array variable or ordinal type');
        idx := FindSym(CurTok.SVal);
        if (idx < 0) and (FindProc(CurTok.SVal) >= 0) then
        begin
          { `Low(MakeArr)` — a CALL operand, exactly as in the High arm above,
            and fixed the same way rather than left as the one of the pair that
            still says "undefined variable". Falls through to the `else 0` tail,
            which is the lower bound of every dynamic array. }
          ParseExpr;
          valNode := CurASTNode;
        end
        else
        begin
          Next;
          valNode := ParseLValueAST(idx, TokPos - 2);   { consume the array variable }
        end;
        end;
        Expect(tkRParen, ')');
        { …and what KIND of value the operand turned out to be, which is what
          decides a STRING's bounds. Computed once, read by the frozen and the
          managed arm below.

          An ARRAY operand is excluded outright — every array arm above has
          already claimed those, and a dyn array of AnsiString has ELEMENT type
          tyAnsiString on its symbol, so without `IsNodeArray` a `array of
          string` FIELD would have been read as a string and answered Length
          instead of Length-1.

          The FROZEN arm additionally insists on a plain variable, because that
          is the only operand whose declared CAPACITY is on hand: a
          `string[6]`-returning FUNCTION has no ProcRet capacity row, and
          answering the 255 default there would turn today's too-small bound
          into a too-large one — a loop reading off the end rather than stopping
          early, which is the worse of the two wrongs. It keeps the Length-1
          tail and is recorded as a gap on the ticket. }
        hlIsArrOp := IsNodeArray(valNode) or
                     ((idx >= 0) and (idx < SymCount) and Syms[idx].IsArray);
        if (idx >= 0) and (idx < SymCount) and (ASTKind[valNode] = AN_IDENT) and
           (ASTIVal[valNode] = idx) then
          hlValTk := Syms[idx].TypeKind
        else
          hlValTk := IntToTypeKind(ASTTk[valNode]);
        hlIsFrozen := (not hlIsArrOp) and TypeIsFrozenString(hlValTk) and
                      (idx >= 0) and (idx < SymCount) and
                      (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx);
        hlIsAnsi := (not hlIsArrOp) and (hlValTk = tyAnsiString);
        hlCap := DEFAULT_STR_CAP;
        if hlIsFrozen and (SymStrCap[idx] > 0) then hlCap := SymStrCap[idx];
        CurASTNode := AllocNode(AN_INT_LIT);
        { the DEFAULT type, set before the chain rather than after it: the array
          arms below stamp the index type on this node, and a blanket
          `ASTTk := tyInteger` at the bottom used to overwrite them -- which is
          why High(c) answered 'e' while Low(c) still answered 97. }
        ASTTk[CurASTNode] := Ord(tyInteger);
        { FIRST, because the two whole-array arms below ask about the SYMBOL and
          not about the operand: they fire on `Low(d[i])` just as happily as on
          `Low(d)` and answer the OUTER array's lower bound. The High chain's
          equivalents each carry an `(ASTKind[valNode] = AN_IDENT) and
          (ASTIVal[valNode] = idx)` guard and these two do not — measured
          2026-09-06, `var m: array[5..9] of array[2..3] of LongInt` gives
          `Low(m[5])` = 5 against fpc's 2, and `High(m[5])` = -1 against 3. That
          nested-STATIC case is a different defect (pxx flattens nested static
          dimensions, so `m[5]` is not a row value in our model at all) and is
          filed separately; adding the missing guard here would move it from one
          wrong answer to another, so it is not done blind. What this arm claims
          is only the dynamic-of-fixed-row shape, where the right answer is
          known. See NodeFixedRowInfo, and
          bug-p-low-and-high-of-a-nested-static-array-row-answer-the-outer-arrays-bounds,
          which carries the reason rather than only the measurement -- a comment
          reaches whoever opens this function and everyone else arrives from the
          queue. }
        if NodeFixedRowInfo(valNode, frRowLen, frRowLo) then
          ASTIVal[CurASTNode] := frRowLo
        else if (idx >= 0) and Syms[idx].IsArray and (Syms[idx].Kind <> skParam) and
           (SymArrNDims[idx] <= 1) then
        begin
          ASTIVal[CurASTNode] := Syms[idx].ConstVal;
          StampArrIdxType(CurASTNode, SymArrIdxTk[idx], SymArrIdxEnumId[idx]);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end
        else if (idx >= 0) and Syms[idx].IsArray and (Syms[idx].Kind <> skParam) and
                (SymArrNDims[idx] >= 2) then
        begin
          { Low of a whole multi-dim static array = the FIRST dimension's lower
            bound (SymArrDimLo[sym*MAX+0]); was silently 0. }
          ASTIVal[CurASTNode] := SymArrDimLo[idx * MAX_ARR_DIMS];
          StampArrIdxType(CurASTNode, SymArrIdxTk[idx], SymArrIdxEnumId[idx]);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end
        else if DerefPtrArrayInfo(valNode, dpaCount, dpaLo, dpaFlat) then
          { `Low(p^)`: the pointee's declared lower bound. }
          ASTIVal[CurASTNode] := dpaLo
        else if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx) and
                TryOrdinalVarBound(idx, False, hlBoundV, hlBoundTk, hlBoundEid) then
        begin
          { Low of an ordinal VARIABLE is its type's lower bound; the `else 0`
            below answered 0 for Integer, SmallInt and every named subrange.
            Paired with the High arm above -- see TryOrdinalVarBound, including
            the enum identity, which the two must stamp identically or
            `Low(a)..High(a)` prints one end as a name and the other as a
            number. }
          ASTIVal[CurASTNode] := hlBoundV;
          ASTTk[CurASTNode] := Ord(hlBoundTk);
          if hlBoundEid >= 0 then ASTSemId[CurASTNode] := hlBoundEid;
          LastExprTk := hlBoundTk;
          Exit;
        end
        else if hlIsAnsi then
          { A MANAGED string is 1-BASED, so its first valid index is 1 and not
            the 0 this tail gives every dynamic array. Paired with the High arm
            above — the two together are what make
            `for i := Low(s) to High(s)` walk the whole string.
            bug-p-high-and-low-of-a-string-are-off-by-one }
          ASTIVal[CurASTNode] := 1
        else
          { …a FROZEN string lands here and 0 is right for it: index 0 is the
            length byte, which is exactly why fpc reports 0 for `string[N]` and
            for a ShortString while reporting 1 for a managed one. }
          ASTIVal[CurASTNode] := 0;
        { read the folded node rather than asserting Integer: a char-, Boolean-
          or enum-indexed array's bound is typed by its INDEX, and the arms
          above stamp that on the node. Every other arm still builds a
          tyInteger node, so this is the same answer for them. }
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;

      { Length(x): soft-keyword intrinsic (lexes as a plain ident, so `var
        length: ...` is a legal identifier like in FPC — pilot for
        bug-hard-keyword-intrinsics-block-identifier-use). A user routine of
        the same name shadows it, and a plain `length` not followed by `(`
        resolves as an ordinary identifier via the normal paths below. }
      if CaseEqual(name, 'Length') and
         ((qUnit = -2) or ((procIdx < 0) and (FindSym(name) < 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        { `Length([e1,..,en])` -- an open-array constructor, not a set. }
        if TryFoldBracketCtorLen(bcN) then
        begin
          FoldBracketCtorBound(bcN);
          Exit;
        end;
        { Length of a string LITERAL folds to its char count at compile time
          (FPC: Length('hello') = 5). Covers the common literal forms without
          the runtime [-8]-header path, which only an lvalue string/array has.

          The `)` lookahead is load-bearing: this guard used to ask only whether
          the argument STARTS with a literal and then demanded `)`, so
          `Length('ab' + s)` — the literal as the LEFT operand of a concat — was
          a PARSE ERROR, while `Length(s + 'ab')` and `Length(('ab') + s)`, the
          same expression twice more, both compiled. A fast path that is not a
          strict subset of the general one
          (devdocs/dev/normalise-dont-special-case.md); anything but a bare
          literal now falls into the ParseExpr path below, which already lowers
          a concat r-value.
          bug-p-length-of-a-string-literal-plus-anything-does-not-parse }
        if (CurTok.Kind = tkString) and (Tokens[TokPos].Kind = tkRParen) then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Length(CurTok.SVal); ASTTk[node] := Ord(tyInteger);
          Next; Expect(tkRParen, ')');
          CurASTNode := node;
          Exit;
        end;
        { Any string/array r-value: an lvalue (var/field/element) keeps the
          force-addressed [data-8] header read; a non-lvalue managed-string
          value (concat / function result) lowers as a value (IR side
          de-references the handle directly — see IsASTLValue gate in ir.inc). }
        ParseExpr;
        valNode := CurASTNode;
        Expect(tkRParen, ')');
        { A SET has no length, and FPC says so — `Type mismatch`. pxx fell
          through to the runtime -tkLength path, which read the 32-byte bitset as
          a string handle and answered the low word of the BITMASK: `s := [1,2];
          Length(s)` printed 6, `[5,9]` printed 544, `['a','b']` printed 0. It
          looked like a plausible small number for a small set, which is how it
          survived. Refused rather than given a meaning: FPC has no Length(set),
          so anything invented here would be pxx-only, and the caller almost
          certainly meant the element COUNT, which is not what any spelling of
          this used to return.
          Excludes an ARRAY operand, and that exclusion is the whole subtlety: an
          array symbol's TypeKind is its ELEMENT's, so `ds: array of TDays` with
          `TDays = set of ...` reads as tySet on both the symbol and the node.
          `Length(ds)` there is the array's length and is entirely legal —
          test_dynarray_insert_delete has four of them, and they are what caught
          the first version of this check.
          bug-p-length-low-and-high-of-a-set-answer-the-bitmask }
        if (not IsNodeArray(valNode)) and
           (not ((ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
                 (ASTIVal[valNode] < SymCount) and Syms[ASTIVal[valNode]].IsArray)) and
           ((IntToTypeKind(ASTTk[valNode]) = tySet) or
            ((ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
             (ASTIVal[valNode] < SymCount) and
             (Syms[ASTIVal[valNode]].TypeKind = tySet))) then
          ErrorRecover('Length: a set has no length (did you mean the element count?)');
        { Length of a whole 1-D static array is a compile-time constant (FPC
          too): the runtime -tkLength path reads a [data-8] length header,
          which only a dyn array / open-array param has — a bare static array
          has none. Params (incl. open arrays) and multi-dim keep the runtime
          path. }
        lenFieldRec := -1; lenFieldIdx := -1;
        if ASTKind[valNode] = AN_FIELD then
        begin
          lenFieldRec := ResolveNodeRec(ASTLeft[valNode]);
          if lenFieldRec >= REC_UCLASS_BASE then
            lenFieldIdx := FindUField(lenFieldRec - REC_UCLASS_BASE, GetASTIdentName(valNode));
        end;
        if (IntToTypeKind(ASTTk[valNode]) = tyChar) and (ASTCharArrayCap(valNode) < 0) and
           not ((ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
                (ASTIVal[valNode] < SymCount) and Syms[ASTIVal[valNode]].IsArray) then
        begin
          { …but NOT a static `array of Char`, whose AST node is ALSO typed
            tyChar (the arrayness is on the symbol). `Length(a)` on an
            array[0..7] of Char is 8, the array's length — this arm answered 1,
            the length of a Char, for as long as it has existed.
            bug-p-a-char-array-is-not-a-string-in-any-direction

            …and NOT a DYNAMIC `array of Char` either, which is the same
            oversight one shape further out. `ASTCharArrayCap` answers the
            STATIC capacity, so it is < 0 for a dyn array exactly as it is for a
            bare Char — the guard above cannot tell them apart, and every
            `Length(w)` on a `w: array of Char` folded to the constant 1 while
            `High(w)` answered 5 and the elements read back correctly. The
            IsArray test is what distinguishes a symbol that HAS a length from a
            scalar Char; it covers the static case too, so the capacity test is
            now belt-and-braces rather than the only guard.

            Why it folded rather than merely mis-lowering: this arm replaces the
            call with an AN_INT_LIT, so `Length(w)` never reached codegen at all
            — `PXXDBG=a.ir` shows `const_int ival=1` where `array of Byte` emits
            a real `call -44`. A fold is invisible to every backend, which is
            why no target-specific test caught it.
            bug-p-length-of-a-dynamic-array-of-char-returns-1 }
          { `Length(c)` where c is a CHAR is 1 — FPC's answer, and the same one
            `Length('y')` on a character LITERAL already gave. A Char VARIABLE
            fell through to the runtime -tkLength path, which read the value as
            a string handle and returned the CODE POINT: `c := 'x'; Length(c)`
            answered 120. Latent for as long as chars have existed; surfaced by
            bug-pascal-ord-of-a-one-char-string-const-is-its-address, which makes
            `const Sep = '/'` a Char, at which point `Length(Sep)` SEGFAULTED
            instead of merely lying. Folded here so every target gets it. }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := 1; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
           Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen >= 0) and
           (Syms[ASTIVal[valNode]].Kind <> skParam) and (SymArrNDims[ASTIVal[valNode]] <= 1) then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Syms[ASTIVal[valNode]].ArrLen; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if (ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] >= 0) and
                Syms[ASTIVal[valNode]].IsArray and (Syms[ASTIVal[valNode]].ArrLen >= 0) and
                (Syms[ASTIVal[valNode]].Kind <> skParam) and (SymArrNDims[ASTIVal[valNode]] >= 2) then
        begin
          { Length of a WHOLE multi-dim static array = the FIRST dimension's count
            (FPC). A static array carries no [data-8] header, so the runtime
            -tkLength path returned 0 for multi-dim; fold to the first-dim span
            (SymArrDimSpan[sym*MAX+0]). }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := SymArrDimSpan[ASTIVal[valNode] * MAX_ARR_DIMS]; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if NodeFixedRowInfo(valNode, frRowLen, frRowLo) then
        begin
          { `Length(d[i])` over a dyn array of fixed rows. The row has no
            [data-8] header — it is bytes inside the outer array's block — so
            the runtime path read one off it and answered 0 while `d[i][j]`
            indexed correctly, exactly the shape the `p^` arm below describes.
            See NodeFixedRowInfo. }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := frRowLen;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if DerefPtrArrayInfo(valNode, dpaCount, dpaLo, dpaFlat) then
        begin
          { `Length(p^)` where p points at a named FIXED array. The pointee has
            no [data-8] header, so the runtime path read one off a value that has
            none and answered 0 while `p^[i]` indexed correctly — the metadata
            was there, Length just never asked. Fold to the extent, the same move
            the whole-static-array and static-array-FIELD arms make. }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := dpaCount;
          ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else if (lenFieldIdx >= 0) and UFldIsArray[lenFieldIdx] and
                (UFldArrLen[lenFieldIdx] >= 0) and (UFldDynDepth[lenFieldIdx] = 0) and
                (UFldArrNDims[lenFieldIdx] <= 1) then
        begin
          { Length of a whole 1-D static-array FIELD (`Length(rec.arr)`, or a bare
            `Length(arr)` reaching an implicit-Self field) — like the AN_IDENT case,
            a static array carries no runtime [data-8] header, so fold to the field's
            declared count. Without this the runtime -tkLength path read a nonexistent
            header and returned 0 (tforin25: a record enumerator's `FIndex < Length(FArr)`
            was `< 0`, so the for-in ran zero times). }
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := UFldArrLen[lenFieldIdx]; ASTTk[node] := Ord(tyInteger);
          CurASTNode := node;
        end
        else
        begin
          { Length(p) over a PChar is FPC's strlen, not the pointer. Normalise
            the OPERAND — the same move the concat, relational and argument
            boundaries already make for this shape — so the runtime Length path
            below sees an ordinary string and needs to know nothing about
            pointers. `Length(arr[0])` over an `array of PChar` happened to
            answer correctly already; a plain `Length(p)` printed the ADDRESS,
            which is the two-arms-of-one-concept split this ticket is about.
            (The wrap materialises a temporary to measure it; a strlen intrinsic
            would avoid that, at the cost of a second mechanism for one concept.)
            refactor-centralize-managed-string-pchar-conversion }
          if (not CProgramMode) and IsNodePChar(valNode) then
            valNode := WrapPCharToString(valNode);
          { Length wants a STRING, an ARRAY or a PChar. `Length(i)` over an
            Integer reached this runtime path, which reads a [data-8] length
            header off the value, and answered 1 -- a plausible number, no
            diagnostic, exit 0. FPC says "Illegal qualifier".

            NARROW ON PURPOSE — a BARE IDENTIFIER naming a non-array ordinal or
            float symbol, and nothing else. The first version tested the node's
            TYPE KIND instead, and a node's kind is the wrong question here for
            the same reason it is wrong for an open-array parameter: an
            array-shaped node carries its ELEMENT kind, so every one of these
            legal spellings was refused —

              Length(MakeDyn(3))    a function returning a dynamic array (tyPointer,
                                    and TypeIsOrdinal answers True for a pointer)
              Length(gr.mm[0])      an inner dynarray reached through a record field
              Length(pfx^)          a deref of a pointer-to-fixed-array

            — each reported as "not Integer" or "not Pointer", the diagnostic
            naming its own bug. Every one of those is a CHAIN; the shape the
            check was measured against is not. Asking the SYMBOL, once, at the
            only node where a symbol is unambiguously the whole operand, is the
            question that has a right answer.
            bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong,
            regression-test-core-test-length-dynarray-call }
          lenSi := -1;
          if (ASTKind[valNode] = AN_IDENT) then lenSi := ASTIVal[valNode];
          { …and NOT for a name that did not resolve. The Integer that check
            would name is PoisonSym's stand-in, so the message describes the
            recovery rather than the program: `Length(NoSuchVar)` printed the
            undefined name AND "not Integer", where fpc prints one line.
            feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
          if (not CProgramMode) and (lenSi >= 0) and (lenSi < SymCount) and
             (not ASTIsPoisoned(valNode)) and
             (not Syms[lenSi].IsArray) and
             (TypeIsOrdinal(Syms[lenSi].TypeKind) or TypeIsFloat(Syms[lenSi].TypeKind)) and
             (Syms[lenSi].TypeKind <> tyPointer) and
             (not IsNodeArray(valNode)) and (ASTCharArrayCap(valNode) < 0) then
            ErrorRecover('Length needs a string, an array or a PChar, not '
                         + TypeKindSpelling(Syms[lenSi].TypeKind));
          node := AllocNode(AN_CALL); ASTIVal[node] := -Ord(tkLength); ASTTk[node] := Ord(tyInteger);
          argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := valNode;
          ASTLeft[node] := argSeq;
          CurASTNode := node;
        end;
        LastExprTk := tyInteger;
        Exit;
      end;

      { Succ(e)/Pred(e)/Odd(e): System ordinal intrinsics, folded to arithmetic
        (no `uses`, target-independent, the argument used exactly once so no
        double-eval). Succ -> e+1, Pred -> e-1, Odd -> (e and 1) = 1 (Boolean).
        A user routine of the same name (procIdx>=0) shadows. }
      if (CaseEqual(name, 'Succ') or CaseEqual(name, 'Pred')) and
         (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 1; ASTTk[left] := Ord(tyInteger);
        op := AllocNode(AN_BINOP);
        if CaseEqual(name, 'Succ') then ASTIVal[op] := Ord(tkPlus) else ASTIVal[op] := Ord(tkMinus);
        ASTLeft[op] := node; ASTRight[op] := left; ASTTk[op] := ASTTk[node];
        { Succ/Pred of an enum is still that enum — the desugar to `e +/- 1`
          would otherwise drop the identity and WriteLn would print the ordinal. }
        ASTSemId[op] := NodeSemIdOf(node);
        { {$Q+}: FPC checks Succ/Pred too — the desugar IS a +/- binop, so
          tag it like one (feature-overflow-checks-cross-and-intrinsics). }
        if TokQChecks[TokPos - 1] then ASTQChk[op] := True;
        CurASTNode := op; LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;
      if CaseEqual(name, 'Odd') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 1; ASTTk[left] := Ord(tyInteger);
        op := AllocNode(AN_BINOP); ASTIVal[op] := Ord(tkAnd);
        ASTLeft[op] := node; ASTRight[op] := left; ASTTk[op] := Ord(tyInteger);
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 1; ASTTk[left] := Ord(tyInteger);
        CurASTNode := AllocNode(AN_BINOP); ASTIVal[CurASTNode] := Ord(tkEq);
        ASTLeft[CurASTNode] := op; ASTRight[CurASTNode] := left; ASTTk[CurASTNode] := Ord(tyBoolean);
        LastExprTk := tyBoolean;
        Exit;
      end;

      { CompareByte/CompareChar(b1, b2, len): System memcmp primitives ->
        the __pxxCompareByte builtin (byte-wise; Char is a byte here). Soft
        alias like the statement-side Move/FillChar: rename + re-resolve so
        the normal call machinery (untyped const params) does the rest. }
      if (CaseEqual(name, 'CompareByte') or CaseEqual(name, 'CompareChar')) and
         (procIdx < 0) and (idx < 0) and (Tokens[TokPos].Kind = tkLParen) and
         (FindProc('__pxxCompareByte') >= 0) and
         ((CurSelfClass < REC_UCLASS_BASE) or
          (FindUMeth(CurSelfClass - REC_UCLASS_BASE, name) < 0)) then
      begin
        name := '__pxxCompareByte';
        procIdx := FindProc(name);
      end;

      { IsManagedType(T): compile-time intrinsic — True when T is a
        refcounted/managed type. v1: string kinds and dynamic-array type
        names; everything else False. Name-based (the argument is a type). }
      if CaseEqual(name, 'IsManagedType') and (procIdx < 0) and (idx < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        node := AllocNode(AN_BOOL_LIT);
        ASTIVal[node] := 0;
        if (CurTok.Kind = tkString_T) or
           ((CurTok.Kind = tkIdent) and (CaseEqual(CurTok.SVal, 'ansistring') or
             (FindArrayType(CurTok.SVal) >= 0))) then
          ASTIVal[node] := 1;
        ASTTk[node] := Ord(tyBoolean);
        i := 1;
        while (i > 0) and (CurTok.Kind <> tkEOF) do
        begin
          if CurTok.Kind = tkLParen then Inc(i)
          else if CurTok.Kind = tkRParen then Dec(i);
          if i > 0 then Next;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        LastExprTk := tyBoolean;
        Exit;
      end;

      { Assigned(p): System intrinsic -> p <> nil (pointer/class/proc-var).
        Same eval-once inline shape as Succ/Pred/Odd; a user symbol shadows. }
      if CaseEqual(name, 'Assigned') and (procIdx < 0) and (idx < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        left := AllocNode(AN_INT_LIT); ASTIVal[left] := 0; ASTTk[left] := Ord(tyPointer);
        CurASTNode := AllocNode(AN_BINOP); ASTIVal[CurASTNode] := Ord(tkNeq);
        ASTLeft[CurASTNode] := node; ASTRight[CurASTNode] := left; ASTTk[CurASTNode] := Ord(tyBoolean);
        { Tag it: `Assigned(fp)` must keep testing the POINTER even in Delphi
          mode, where the identical `fp <> nil` node calls fp instead. }
        ASTSLen[CurASTNode] := PAS_BINOP_ASSIGNED;
        LastExprTk := tyBoolean;
        Exit;
      end;

      { UpCase(c): System intrinsic -> __pxxUpCase helper (Char->Char, eval-once). }
      if CaseEqual(name, 'UpCase') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('__pxxUpCase');
        if helperPi < 0 then Error('UpCase: builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq; ASTTk[CurASTNode] := Ord(tyChar);
        LastExprTk := tyChar;
        Exit;
      end;

      { RolDWord/RorDWord/RolQWord/RorQWord(value, n): FPC System bit-rotate
        intrinsics (generics.hashes' xxHash mixers). Same soft-alias shape as
        UpCase: hidden __pxx helpers so no real proc of these names exists to
        shadow a user's own. }
      if (CaseEqual(name, 'RolDWord') or CaseEqual(name, 'RorDWord') or
          CaseEqual(name, 'RolQWord') or CaseEqual(name, 'RorQWord')) and
         (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr; op := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('__pxx' + name);
        if helperPi < 0 then Error(name + ': builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        left := AllocNode(AN_ARG); ASTLeft[left] := op; ASTRight[argSeq] := left;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq;
        ASTTk[CurASTNode] := Ord(Procs[helperPi].RetType);
        LastExprTk := Procs[helperPi].RetType;
        Exit;
      end;

      { Pos(sub, s): System substring search -> __pxxPos helper (1-based, 0 if not
        found). A `uses sysutils` Pos or any user routine shadows (procIdx>=0). }
      if CaseEqual(name, 'Pos') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr; op := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('__pxxPos');
        if helperPi < 0 then Error('Pos: builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        left := AllocNode(AN_ARG); ASTLeft[left] := op; ASTRight[argSeq] := left;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq; ASTTk[CurASTNode] := Ord(tyInteger);
        LastExprTk := tyInteger;
        Exit;
      end;



      { Abs(e)/Sqr(e): System intrinsics lowered to builtin helpers (eval-once;
        int and float variants by the argument type). No `uses`; user routine of
        the same name shadows. ESP (no builtin unit) errors with a clear message. }
      { …and in NilPy USER code the intrinsic also wins over a routine of the
        same name that came from a PASCAL RTL UNIT. `abs` is a Python builtin
        there, and what a pulled unit happens to declare must not change what it
        means: `import math` links lib/rtl/math, whose Abs(Integer) is declared
        first, and the whole block below was skipped because `abs` now RESOLVED
        — so `abs(-0.0)` answered -0.0 (math's Abs is `if x < 0 then -x`, and
        -0.0 < 0 is False) and `abs([-0.0][0])` answered 6626872, a variant read
        as an integer. Own language first, and it overrules import order:
        the same rule that says a Python name means the Python thing.

        A NilPy `def abs(x)` of the user's OWN still shadows — that proc is
        declared in the user's unit (or the main program, unit index -1), which
        is exactly what the unit test excludes. Pascal parsing is untouched:
        NilPyUserCode is false there, so the gate stays `procIdx < 0`.
        bug-nilpy-uses-math-breaks-abs-on-a-float }
      if (CaseEqual(name, 'Abs') or CaseEqual(name, 'Sqr')) and
         ((procIdx < 0) or
          (NilPyUserCode and (procIdx < ProcCount) and
           (ProcUnitIdx[procIdx] <> CurrentUnitIdx) and
           (ProcUnitIdx[procIdx] >= 0))) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkRParen, ')');
        if TypeIsFloat(IntToTypeKind(ASTTk[node])) then
        begin
          if CaseEqual(name, 'Abs') then helperPi := FindProc('__pxxAbsDbl')
          else helperPi := FindProc('__pxxSqrDbl');
        end
        else
        begin
          if CaseEqual(name, 'Abs') then helperPi := FindProc('__pxxAbsInt')
          else helperPi := FindProc('__pxxSqrInt');
        end;
        if helperPi < 0 then Error(name + ': builtin helper unavailable (needs the builtin unit; not on ESP)');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        CurASTNode := AllocNode(AN_CALL); ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq;
        if TypeIsFloat(IntToTypeKind(ASTTk[node])) then ASTTk[CurASTNode] := Ord(tyDouble)
        else if CaseEqual(name, 'Abs') then ASTTk[CurASTNode] := ASTTk[node]
        else ASTTk[CurASTNode] := Ord(tyInt64);
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;

      { divmod(a, b) -> (a // b, a % b), both already correct on negative
        operands via pyfloordiv_v/pyfloormod_v.
        feature-nilpy-power-operator-and-divmod }
      if NilPyUserCode and CaseEqual(name, 'divmod') and (procIdx < 0) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        Expect(tkComma, ',');
        ParseExpr; left := CurASTNode;
        Expect(tkRParen, ')');
        helperPi := FindProc('pydivmod_v');
        if helperPi < 0 then Error('Nil Python: pylib (pydivmod_v) not loaded');
        argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := node;
        argSeq2 := AllocNode(AN_ARG); ASTLeft[argSeq2] := left; ASTRight[argSeq2] := -1;
        ASTRight[argSeq] := argSeq2;
        CurASTNode := AllocNode(AN_CALL);
        ASTIVal[CurASTNode] := helperPi;
        ASTLeft[CurASTNode] := argSeq;
        ASTTk[CurASTNode] := Ord(Procs[helperPi].RetType);
        ASTRight[CurASTNode] := ProcRetRecId[helperPi];
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        Exit;
      end;

      { Concat(s1, s2, ..., sn): the System string-concatenation intrinsic, just
        chained `+`. Folded here so it needs no `uses` and reuses the working
        string-concat codegen.

        This arm is for when NO `Concat` is in scope at all. When one IS —
        `lib/rtl/sysutils` declares a two-argument one — `procIdx >= 0` sends the
        call down the ordinary overload path, and the intrinsic is picked up
        again at the no-overload-match point below, where whether the user's
        Concat actually accepts these arguments has been decided rather than
        guessed. Same pair as `Copy`, for the same reason and with the same
        obligation to stay in step.
        compat-pascal-uses-sysutils-withdraws-the-variadic-concat

        FPC's Concat is ALSO the dynamic-array concatenation, so the first
        operand's shape picks which one this is — one intrinsic, two element
        types, decided by the same left-fold. Everything below the fold is
        shared; only the node the fold builds differs
        (feature-p-dynamic-array-concatenation). }
      if CaseEqual(name, 'Concat') and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; node := CurASTNode;
        while Eat(tkComma) do
        begin
          ParseExpr;
          { ASK BOTH OPERANDS, NOT JUST THE ACCUMULATOR. `Concat([0], a)` starts
            the fold on an element list, which is depth 0, so the ARRAY
            concatenation was never chosen and the fold built a STRING `+` chain
            instead -- reported far later as `arithmetic operator not supported
            for dynamic arrays`, at the next statement mentioning the variable.
            The eligibility predicate is the same one the `+` operator uses, so
            the two doors cannot disagree about what a concatenable pair is. }
          RefuseUntypedElementListConcat(node, CurASTNode);
          if DynConcatOperandsEligible(node, CurASTNode) then
            node := MakeDynConcat(node, CurASTNode)
          else
          begin
            left := AllocNode(AN_BINOP);
            ASTIVal[left] := Ord(tkPlus);
            ASTLeft[left] := node; ASTRight[left] := CurASTNode;
            ASTTk[left] := Ord(tyAnsiString);
            node := left;
          end;
        end;
        Expect(tkRParen, ')');
        CurASTNode := node;
        { A one-argument `Concat(a)` over an array is the identity and never
          reaches MakeDynConcat, so ask the NODE what it is rather than
          remembering which branch ran. }
        if NodeDynDepth(node) > 0 then LastExprTk := tyPointer
        else LastExprTk := tyAnsiString;
        Exit;
      end;

      { Generic dynamic-array Copy(arr, index [, count]) intrinsic, when no Copy
        function is in scope (a string `sysutils.Copy` keeps the proc path; that
        case, and Copy(dynarray) shadowed by a string Copy, are handled at the
        no-overload-match point below). Lowered into a fresh element-type-aware
        `array of T` via AN_DYN_COPY. }
      if CaseEqual(name, 'Copy') and ((qUnit = -2) or (procIdx < 0)) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next; Expect(tkLParen, '(');
        ParseExpr; exprNode := CurASTNode;            { source array }
        { The index is OPTIONAL: `Copy(a)` is FPC's whole-array shorthand for a
          dynamic array, and it is the escape hatch users need once assignment
          aliases, so it is the natural way to duplicate an array
          (bug-p-copy-single-argument-form-missing-for-dynamic-arrays). Parsed
          permissively here and rejected below for a non-array, because the
          string-vs-dynarray decision needs the first argument's TYPE and that is
          not known until it has been parsed. }
        node := -1; addrNode := -1;
        if Eat(tkComma) then
        begin
          ParseExpr; node := CurASTNode;              { index }
          if Eat(tkComma) then begin ParseExpr; addrNode := CurASTNode; end;  { count }
        end;
        Expect(tkRParen, ')');
        { ANY dyn-array-typed expression, not just a bare name: `Copy(g[0])` and
          `Copy(r.items)` are what a per-level deep copy is spelled with, and FPC
          accepts both. }
        if NodeDynDepth(exprNode) >= 1 then
        begin
          { NESTED source: the raw byte copy in AN_DYN_COPY would move SUB-ARRAY
            HANDLES with the base element's size — TypeSlotSize of the deepest type, 4
            for `array of array of Integer` — so element 1 onward read a bogus
            handle and `h[1][1]` segfaulted. Refused loudly here, exactly as
            dynamic-array Delete and Insert already refuse the same shape, until
            AN_DYN_COPY learns the handle stride AND the element-aware retain a
            nested copy needs (feature-dynarray-copy-nested-element-type).
            Reproduced on pinned, so it is not a regression — just a crash nobody
            had asked for yet. }
          { The depth > 1 refusal is gone: AN_DYN_COPY learned the handle
            stride, the temp's real depth and the element-aware retain
            (feature-dynarray-copy-nested-element-type). The SymElemDynDepth
            guard stays — a dyn array whose ELEMENT is a separately named
            dyn-array type is a different shape from syntactic nesting, and
            NodeDynDepth does not fold the two, so lifting it would go back to
            striding by the wrong size. }
          if (ASTKind[exprNode] = AN_IDENT) and (ASTIVal[exprNode] >= 0) and
             (SymElemDynDepth[ASTIVal[exprNode]] > 0) then
            Error('Copy: dynamic-array element type not yet supported for '
                  + 'dynamic-array Copy (feature-dynarray-copy-nested-element-type)');
          if node = -1 then
          begin
            node := AllocNode(AN_INT_LIT);
            ASTIVal[node] := 0; ASTTk[node] := Ord(tyInteger);
          end;
          if addrNode = -1 then
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 2147483647; ASTTk[addrNode] := Ord(tyInteger);
          end;
          argSeq := AllocNode(AN_DYN_COPY);
          ASTLeft[argSeq] := exprNode;
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := node;
          ci := AllocNode(AN_ARG); ASTLeft[ci] := addrNode;
          ASTRight[lastArg] := ci;
          ASTRight[argSeq] := lastArg;
          { Pointer-typed: the result is a dyn-array handle, so the assignment
            stores all 8 bytes (an element-typed tag would truncate it). }
          ASTTk[argSeq] := Ord(tyPointer);
          { `Copy(a, 1, 2)[0]` — the postfix chain, which this branch used to
            Exit straight past, so the trailing `[` reached the statement parser
            as a stray token and reported `unexpected token` at the wrong place
            (dynarray-copy-and-alias in fpc_diff_probe). A dyn-array VALUE has no
            address to index, and the answer to that is the hidden temp
            IndexDynArrayValue already builds for an array-returning CALL —
            keyed on the node's element shape, which for this node is the
            SOURCE array's (the same trio AN_DYN_COPY's own lowering reads).
            The string arm below does the same thing through
            ApplyCallResultPtrSuffix. }
          if CurTok.Kind = tkLBrack then
          begin
            copyElemRec := NodeDynBaseRec(exprNode);
            LastExprTk := NodeDynBaseTk(exprNode);
            CurASTNode := IndexDynArrayValue(argSeq, Ord(NodeDynBaseTk(exprNode)),
                                             copyElemRec, NodeDynDepth(exprNode),
                                             copyElemRec, LastExprTk);
            Exit;
          end;
          CurASTNode := argSeq;
          Exit;
        end;
        { One argument and NOT a dynamic array. FPC rejects `Copy(s)` on a string
          too — the shorthand is a dynamic-array feature only — so this is a
          match with the reference implementation, not a gap. Diagnosed by name
          rather than falling into the string path below, which would report a
          missing index as a type error. }
        if node = -1 then
          Error('Copy: the one-argument Copy(a) is the whole-array shorthand and ' +
                'needs a DYNAMIC ARRAY; on a string give the index and count ' +
                '(Copy(s, 1, n)), which is what FPC requires too');
        { A Char first argument (`Copy('a', 1, 1)`): FPC promotes char -> string,
          so materialise a 1-char string and route through the string-Copy path
          below — the same promotion `+` and String() already do. Without this a
          char fell through to the dynamic-array error (a loud rejection of valid
          Pascal). }
        if IntToTypeKind(ASTTk[exprNode]) = tyChar then
          exprNode := WrapCharToStringExpr(exprNode);
        { A PChar first argument: FPC converts it to a string, as in every other
          string context. Normalise the OPERAND here — beside the Char promotion
          above, and the same move already made at the Length, concat,
          relational and argument boundaries — so the string-Copy path below
          sees an ordinary string and needs to know nothing about pointers.
          Without it `Copy(p, 2, 3)` fell through to the dynamic-array error, a
          loud rejection of code FPC accepts, and it did so for EVERY PChar
          spelling at once — a var, `q^`, `q[0]`, an array element, a record
          field, a call result, a `const PChar` parameter, an `out` parameter.
          That spread is the tell: unrecognised at this BOUNDARY, not one broken
          shape. refactor-centralize-managed-string-pchar-conversion }
        if (not CProgramMode) and IsNodePChar(exprNode) then
          exprNode := WrapPCharToString(exprNode);
        { String first argument: bare `Copy(s, index[, count])` lowers to the
          __pxxStrCopy substring helper (builtin unit, pulled by the pre-scan), so
          string Copy needs no `uses sysutils`. 2-arg form -> count = rest (huge,
          clamped to the end by the helper). The lib `sysutils.Copy` keeps the
          explicit-uses overload path. }
        ci := FindProc('__pxxStrCopy');
        cpyPi := ci;
        if (ci >= 0) and (IntToTypeKind(ASTTk[exprNode]) in [tyString, tyAnsiString, tyFixedString]) then
        begin
          if addrNode = -1 then
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 2147483647; ASTTk[addrNode] := Ord(tyInteger);
          end;
          argSeq := AllocNode(AN_CALL);
          ASTIVal[argSeq] := ci;
          ASTTk[argSeq] := Ord(tyAnsiString);
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := exprNode;       { s }
          ASTLeft[argSeq] := lastArg;
          ci := AllocNode(AN_ARG); ASTLeft[ci] := node;                     { index }
          ASTRight[lastArg] := ci;
          lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := addrNode;       { count }
          ASTRight[ci] := lastArg;
          { `Copy(s, 2, 3)[1]` -- the postfix chain, which this branch used to
            Exit straight past. A builtin's branch returns an ordinary AN_CALL,
            so it wants the SAME suffix walk a user call gets; without the call
            the trailing `[` reached the statement parser as a stray token and
            reported `unexpected token` pointing at the wrong place. This is why
            `Nm()[1]` and `Copy(s,2,3)[1]` disagreed despite both being a string
            indexed off a call. compat-pascal-index-a-function-call-result }
          if CurTok.Kind in [tkLBrack, tkCaret, tkDot] then
          begin
            ApplyCallResultPtrSuffix(argSeq, cpyPi);
            Exit;
          end;
          CurASTNode := argSeq;
          LastExprTk := tyAnsiString;
          Exit;
        end;
        Error('Copy: dynamic-array Copy needs a dynamic-array first argument ' +
              '(string Copy needs the strutils/sysutils unit)');
      end;

      { Indirect call through a procedural-type variable: v(args) as an expression. }
      if (idx >= 0) and (SymProcSig[idx] >= 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        node := ParseProcVarCallAST(idx, SymProcSig[idx]);
        CurASTNode := node;
        LastExprTk := IntToTypeKind(ASTTk[node]);
        Exit;
      end;

      { Class typecast as an expression: TClass(expr). A hard reinterpret (no
        runtime check, unlike `as`); classes are pointers so the value is
        unchanged, only the static type. Tagged AN_CLASS_CAST so a trailing
        .field / [i] resolves its offset against TClass (ResolveNodeRec maps the
        node to the class record). Must precede the pointer-alias cast below,
        which would otherwise mis-handle a class name as a plain pointer cast and
        resolve every field at offset 0. Field reads and writes both work via the
        class-typed AN_FIELD base path in IRLowerAddress. }
      { `IsClassType` matches case-INSENSITIVELY, Pascal-style, and this branch
        reads `Name(x)` as a CLASS CAST. In NilPy that is wrong twice over:
        Python has no cast syntax, and its names are case-sensitive — so
        `class F` plus `def f(a, b)` made `f(1, 2)` parse as a cast of `F` and
        fail with "Expected: )" on the second argument, naming a call that is
        ordinary Python. The exact-case construction intercept above already
        claims a genuine `F(...)`, so under PyExprMode a name reaching here is
        by definition NOT that class and must fall through to the call path.

        Same family as bug-nilpy-calling-an-instance-named-like-its-class-runs-
        the-constructor and the TYPING half PyIsClassTypeExact fixed: one
        case-insensitive lookup per site, each found separately
        (bug-nilpy-a-lowercase-name-is-hijacked-by-a-case-matching-class). }
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        ci := FindUClass(name);
        Next;                  { consume class name }
        Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        node := AllocNode(AN_CLASS_CAST);
        ASTLeft[node] := CurASTNode;
        ASTIVal[node] := ci;
        ASTTk[node]   := Ord(tyClass);
        tk := tyClass;
        if CurTok.Kind in [tkDot, tkLBrack] then
          node := ParseClassRecordSelectors(node, REC_UCLASS_BASE + ci, tk);
        CurASTNode := node;
        LastExprTk := tk;
        Exit;
      end;

      { TObject(expr) — cast to the IMPLICIT root class (no UCls row exists for
        the builtin TObject unless the user declared one, which the branch
        above catches). Classes are pointers, so this is a pure static retag;
        the value then feeds `is` / `as` / class casts (blcksock's
        `TObject(SocketList[n]) is TBlockSocket`). No member selectors — the
        root has none. }
      if (idx < 0) and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) and
         CaseEqual(name, 'TObject') and (FindUClass(name) < 0) then
      begin
        Next;                  { consume 'TObject' }
        Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        ASTTk[CurASTNode] := Ord(tyClass);
        LastExprTk := tyClass;
        Exit;
      end;

      { Record-name reinterpret cast: TRec(ptr)^.field. Treats TRec(ptr) as a
        pointer reinterpret whose pointee is the record TRec, then handles the
        trailing ^ / .field / [i] (mirrors the pointer-alias path). A class name
        already went to AN_CLASS_CAST above; a record name is not a type alias so
        it would otherwise fall through to "unexpected token". }
      if (idx < 0) and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) and
         (IsRecordType(name) >= REC_UCLASS_BASE) then
      begin
        baseRec := IsRecordType(name);
        Next;                  { consume record type name }
        Expect(tkLParen, '(');
        ParseExpr;
        Expect(tkRParen, ')');
        node := AllocNode(AN_PTR_CAST);
        ASTLeft[node] := CurASTNode;
        { plain pointer reinterpret -- no char +8 adapter -- but the field is
          read by ir.inc as an ALIAS INDEX, and 0 is alias row ZERO there,
          not "no alias". Mint the row that says what this cast points at,
          so TRec(p)[i] strides by a TRec the way PRec(p)[i] already does.
          See EnsureRecPtrAlias. }
        ASTIVal[node] := EnsureRecPtrAlias(baseRec);
        if ASTIVal[node] < 0 then ASTIVal[node] := 0;
        ASTTk[node]   := Ord(tyPointer);
        tk := tyPointer; recName := baseRec;
        { A VALUE typecast of a RECORD is an in-place reinterpret in FPC, and it
          is one whether or not a `.field` follows. `TRec(q).high` took this
          branch; bare `TQ(r)` — the whole-record reinterpret, `q := TQ(r)` —
          did not, so it stayed a POINTER cast: the assignment copied a record
          from whatever address r's first 8 bytes happened to spell, and
          segfaulted. Same construct, two shapes, and the shape without the
          trailing accessor is the one that was wrong.
          bug-a-a-whole-record-hard-cast-is-lowered-as-a-pointer-cast
          `^` still means the pointer path — `TRec(p)^` derefs the VALUE. }
        if (CurTok.Kind = tkDot) or
           ((CurTok.Kind <> tkCaret) and
            (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord)) then
        begin
          { VALUE typecast used directly with `.field` — `TRec(q).high` — is
            FPC's in-place reinterpret: the field lives at @q + offset. Build a
            rec-tagged deref of the OPERAND'S ADDRESS so the ordinary field
            path resolves offsets (mirrors `TRec(p)^.field`, which derefs the
            pointer VALUE instead). Previously the AN_FIELD sat straight on the
            PTR_CAST, ResolveNodeRec saw REC_NONE, and every field silently
            resolved at offset 0 (bug-pascal-record-cast-field-offset). }
          fieldNode := AllocNode(AN_ADDR);
          ASTLeft[fieldNode] := ASTLeft[node];
          ASTTk[fieldNode] := Ord(tyPointer);
          indexNode := AllocNode(AN_DEREF);
          ASTLeft[indexNode] := fieldNode;
          ASTIVal[indexNode] := baseRec;   { pointee rec for ResolveNodeRec }
          ASTTk[indexNode] := Ord(tyRecord);
          node := indexNode;
          tk := tyRecord;
        end;
        { The suffix chain -- `^`, `.field`, `[i]` -- through the ONE walker the
          pointer-alias spelling above also uses. This site had its own 132-line
          copy until refactor-p-three-hand-rolled-postfix-loops; every arm of it
          was a weaker version of the same arm over there, and each gap had been
          filed separately as a silent wrong value on this spelling only --
          `TLongWordRec(l).b[0]` read a Byte at the RECORD's width, `TA(b).pi^`
          was refused outright because the delegating arm never re-entered for
          the trailing `^`, `TRec(raw)^[1,1]` could not take a comma subscript,
          and an array field indexed through the chain lost its element type.
          One walker means a fix here cannot reach one spelling and miss the
          other, which is the whole of normalise-dont-special-case.

          aliasIdx is -1: THIS SPELLING HAS NO ALIAS ROW. `TRec(raw)` is
          `PRec(raw)` with no declared PRec, so there is nothing for
          ResolveDerefShape to read, and the cast node's ASTIVal is 0 for "plain
          reinterpret" -- a value the resolver would take as alias row ZERO. The
          seed below is the exact and complete answer instead: a record-name cast
          is a pointer to that record, at depth one, and nothing else.
          test_record_name_cast_strides_by_its_record }
        ParseCastPostfixSuffix(node, tk, recName, -1, tyRecord, baseRec,
                               0, Ord(tyUnknown), REC_NONE);
        CurASTNode := node;
        LastExprTk := tk;
        Exit;
      end;

      { C4: pointer-type-alias cast — PFoo(expr) where PFoo = ^TFoo }
      if (idx < 0) and (procIdx < 0) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        aliasIdx := FindTypeAlias(name);
        { ...and, only if that missed, a BUILT-IN pointer name: `PInteger(p)^`. Registered
          lazily, on first use, which is what keeps a source declaration winning -- FindTypeAlias
          ran first, so a real PInteger in the source or the RTL was already found. Registering
          these up front instead shadows the source (FindTypeAlias is first-wins) and silently
          re-types this compiler's own `PWord = ^NativeInt`. }
        if aliasIdx < 0 then aliasIdx := EnsureBuiltinPtrAlias(name);
        { ...and, only if BOTH missed, a named ARRAY type: `TArr(aa)[1]`.

          FPC treats a value typecast to an array type as an in-place storage
          reinterpret -- exactly what `PArr(@aa)^[1]` already spells here -- so
          this takes the operand's ADDRESS and DEREFS the cast, and everything
          below (the suffix walk, the element kind, the low bound, dynamic vs
          fixed) is the pointer-alias path unchanged.

          Arrays were the ONLY type kind with no cast at all: record, string
          alias, pointer alias, class, integer alias, enum, set and procedural
          all worked, and all three array flavours answered "undefined
          variable" because the NAME never resolved. Ordered third so a source
          declaration still outranks it, same rule as the builtin names above.
          bug-p-a-cast-to-an-array-type-is-not-recognised }
        arrCast := False;
        if aliasIdx < 0 then
        begin
          aliasIdx := EnsureArrayPtrAlias(name);
          arrCast := aliasIdx >= 0;
        end;
        if aliasIdx >= 0 then
        begin
          Next; { consume alias type name }
          Expect(tkLParen, '(');
          { A cast to a METHOD-POINTER type supplies the context that makes a
            bare `obj.M` a reference rather than a call -- the same context an
            assignment to a method-pointer variable supplies, asked through the
            one helper both now share. Gated on the alias being a method pointer
            (AliasProcSig >= 0 AND tyRecord, the 16-byte {Code, Data} form the
            call arm below already distinguishes from the pointer form), so no
            other cast flavour changes how its operand is read.
            bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults }
          mrefNode := -1;
          if (AliasProcSig[aliasIdx] >= 0) and (AliasTk[aliasIdx] = Ord(tyRecord)) then
            mrefNode := TryParseParenlessMethodRef;
          if mrefNode >= 0 then
          begin
            CurASTNode := mrefNode;
            LastExprTk := tyRecord;
          end
          else
            ParseExpr;
          Expect(tkRParen, ')');
          { The array cast reinterprets STORAGE, so the pointer it stands for is
            the operand's address. Everything downstream then sees exactly the
            node `PArr(@aa)` builds. }
          if arrCast then
          begin
            acAddr := AllocNode(AN_ADDR);
            ASTLeft[acAddr] := CurASTNode;
            ASTTk[acAddr] := Ord(tyPointer);
            CurASTNode := acAddr;
          end;
          { `TFn(p)(args)` -- CALL straight through a procedural-type cast, the
            natural way to dispatch through a hand-built VMT (rtl-generics
            reaches its comparers this way). The capability was entirely
            present: `f := TFn(p); f(args)` worked, only the direct spelling was
            `unexpected token` -- on the CALL line, so it read as a problem with
            the argument list.

            ONE site, and that is the whole answer to the question this ticket
            was parked on ("count the cast paths and decide whether they should
            be one"). The other cast flavours -- the builtin scalar names, the
            PChar adapter, enums, `string` -- can NEVER produce a callable
            value, because a procedural type is always user-DECLARED and so is
            always a type ALIAS. So the call postfix has exactly one possible
            receiver shape and belongs here, rather than being a fifth
            per-flavour postfix handler. (`^`, `.field` and `[i]` after a cast
            already work; `(` was the only postfix missing.)

            A method-pointer alias is tyRecord -- 16 bytes of {Code, Data} --
            and the cast is a pure retype of the operand, which records already
            carry by address; the pointer form needs the AN_PTR_CAST wrapper.
            Same split the record arm below states for the non-call case.
            bug-p-cannot-call-directly-through-a-procedural-type-cast }
          if (AliasProcSig[aliasIdx] >= 0) and (CurTok.Kind = tkLParen) then
          begin
            if AliasTk[aliasIdx] = Ord(tyRecord) then
            begin
              ASTTk[CurASTNode] := Ord(tyRecord);
              node := CurASTNode;
            end
            else
            begin
              node := AllocNode(AN_PTR_CAST);
              ASTLeft[node] := CurASTNode;
              ASTIVal[node] := aliasIdx;
              ASTTk[node]   := Ord(tyPointer);
            end;
            CurASTNode := BuildIndirectCallAST(node, AliasProcSig[aliasIdx],
                                               AliasTk[aliasIdx] = Ord(tyRecord));
            LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
            Exit;
          end;
          strAliasCast := (AliasTk[aliasIdx] = Ord(tyAnsiString)) or
                          (AliasTk[aliasIdx] = Ord(tyString));
          { A FROZEN-string alias (`type TS = String[20]`) is the sibling of the
            same defect and was found by grepping for one rather than by a second
            report: it is not ordinal, not float, not record, so it falls into
            the POINTER fall-through below and its `[i]` is then read through the
            PChar adapter -- `TS(sh)[1]` answered an empty character where fpc
            3.2.2 answers `w`, silently, on the pinned compiler too. Only the
            INDEXED shape joins here: the value shape (`WriteLn(TS(sh))`,
            `Length(TS(sh))`, `Pos(TS('rl'), sh)`) was MEASURED correct on the
            pin and is left on the path that produced it. }
          strAliasIdx := (CurTok.Kind = tkLBrack) and
                         (strAliasCast or
                          TypeIsFrozenString(IntToTypeKind(AliasTk[aliasIdx])));
          if strAliasCast and (CurTok.Kind <> tkLBrack) then
          begin
            { STRING-typed alias cast — `tbtstring(' ')` (Pascal Script):
              a value-level no-op, NOT a pointer reinterpret. Keep the
              operand node and its own string kind; consumers coerce
              frozen<->managed as usual. Tagging it tyPointer made
              Pos(tbtstring(' '), s) miss every string overload.

              An INDEX after the cast is the one thing this exit must not take
              with it: it falls through to the shared suffix loop below instead.
              See the note at the fall-through.

              THE NO-OP IS CORRECT ONLY WHEN THE OPERAND IS ALREADY A STRING,
              AND THE OPERAND'S KIND IS THEREFORE THE DISCRIMINATOR -- not the
              alias's, which is a string in both cases. Over a POINTER-typed
              slot the same cast is a real REINTERPRET, and returning the
              operand unchanged left `t(p)` a pointer: `type t = AnsiString;
              var p: Pointer; t(p) := 'abc'; writeln(t(p))` printed 4261104 --
              the pointer as a number, no diagnostic -- where fpc 3.2.2 prints
              abc. uPSCompiler.pas stores every string this way, 93 times.

              THE BUILT-IN SPELLING ALREADY DID THIS RIGHT, which is what makes
              the fix a route rather than an invention: `AnsiString(p)` and
              `String(p)` both print abc and answer Length 3 today, on this arm's
              own model -- an AN_PTR_CAST with ASTIVal = -1, built by the
              identifier path and by tkString_T's final else. Two spellings of
              one concept, one of them taught. So the non-string operand takes
              the same node the built-in takes, with the ALIAS's string kind
              rather than the dialect default, because that is the only thing
              the alias adds.

              Retagging ASTTk in place was tried by a previous session and
              REVERTED for being worse than the bug -- `writeln` then printed
              abc plus out-of-bounds memory and `Length` still answered the
              pointer. That is the tell that the tag is not what the lowering
              reads; the CAST NODE is.

              THE TEST IS `= tyPointer` AND NOT `not TypeIsAnyString`, and the
              difference is requirement 3 of the ticket. Written the second way
              this arm compiles and passes the pointer rows and SILENTLY BREAKS
              `Pos(tbtstring(' '), s)` -- the one-character literal ' ' arrives
              tagged tyChar, so "not a string" swept it into the reinterpret and
              Pos answered nothing. A char operand is a CONVERSION (the built-in
              String(c) has a whole AN_STR_FROM_CHAR arm for it), never a
              reinterpret. The ticket's boundary table measured exactly one
              failing operand -- a Pointer-typed slot, with or without
              indirection -- so that is the operand this arm changes, and
              nothing else moves. A wider negative test is not a wider fix; it
              is a wider blast radius wearing the same green.
              bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer }
            strAliasOpTk := IntToTypeKind(ASTTk[CurASTNode]);
            if strAliasOpTk <> tyPointer then
              LastExprTk := strAliasOpTk
            else
            begin
              node := AllocNode(AN_PTR_CAST);
              ASTLeft[node] := CurASTNode;
              ASTIVal[node] := -1;              { built-in cast, as the ident path does }
              ASTTk[node]   := AliasTk[aliasIdx];
              CurASTNode := node;
              LastExprTk := IntToTypeKind(AliasTk[aliasIdx]);
            end;
            Exit;
          end;
          if AliasTk[aliasIdx] = Ord(tyRecord) then
          begin
            { RECORD-typed alias cast. A METHOD-POINTER type is one of these: a
              `procedure of object` value is a 16-byte {Code, Data} record, and so is
              System.TMethod -- so `TRunMethod(m)` (fpcunit's RunBare, building a
              callable from a MethodAddress result) is a pure REINTERPRET of the same
              two words, not a pointer conversion.

              Records are carried BY ADDRESS in this IR, so the operand node is already
              exactly the right thing; it only needs retyping. Wrapping it in AN_PTR_CAST
              took the record's first word as if it were the value and produced a method
              pointer whose Code was garbage -- which called into nothing. }
            ASTTk[CurASTNode] := Ord(tyRecord);
            LastExprTk := tyRecord;
            LastTypeRecId := AliasElemRec[aliasIdx];
            Exit;
          end;
          { ORDINAL-typed alias cast — `type TaByte = byte; TaByte(c)`. Without
            this the alias fell into the POINTER fall-through below, which
            reinterprets at pointer width and never narrows: with c = $12345678,
            `Byte(c)` gave 120 and `TaByte(c)` gave 305419896. Same for word,
            shortint, smallint, longword, integer — every narrowing spelling —
            and `TaChar(65)` SEGFAULTED, because a pointer-typed cast of an
            ordinal is not a thing any consumer downstream expects.

            The alias is not exotic: FPC's own idiom for a compile-time-selected
            mask is `type ToByte = byte`, and rtl-generics' hash mixer indexes
            `crc32ctab[0, ToByte(crc)]` with it. Unnarrowed that index reached
            ~4.3e9 into a [0..3, byte] table, so `uses Generics.Hashes` died in
            its unit initialization with nothing reporting anything
            (bug-p-a-cast-through-an-ordinal-type-alias-does-not-truncate).

            The node built here is the SAME one every other spelling of an
            ordinal cast builds — AN_PTR_CAST with ASTIVal = -1, the
            width-truncating value cast — so this arm adds a spelling, not a
            mechanism. tyPointer is excluded explicitly because TypeIsOrdinal
            INCLUDES it (the trap IRLowerCallArg's promo arms document), and a
            pointer alias must keep the reinterpret below. }
          { ONE BODY FOR THE ARMS THAT ARE NOT ABOUT WHICH DOOR YOU CAME IN
            THROUGH. This was four transcriptions of the builtin-name door's
            arms -- a variant target boxing, an `operator Explicit`, an ordinal
            narrowing with its enum identity, a float converting through a temp
            -- and every one of them arrived here late and separately, which is
            the seven defects this ticket recorded on 2026-09-06. The enum id
            comes from the alias table's own column rather than from a name
            lookup or a kind test; see TryScalarNamedCast for why it is a
            parameter.

            The arms below this line are the ones that GENUINELY differ by
            door -- an indexed string alias, a pointer alias walking with
            AliasElemTk -- and TryScalarNamedCast declines those targets so they
            still reach their own code. }
          aliasEtid := -1;
          if AliasSemId[aliasIdx] <> 0 then
            aliasEtid := AliasSemId[aliasIdx] - 1
          else if IntToTypeKind(AliasTk[aliasIdx]) = tyInteger then
            aliasEtid := FindEnumType(name);
          if TryScalarNamedCast(IntToTypeKind(AliasTk[aliasIdx]), aliasEtid) then Exit;
          if strAliasIdx then
          begin
            { INDEXED string-alias cast — `TAlias(s)[1]`, and the `[1]` was being
              DROPPED rather than misparsed. The arm above is right that the cast
              is a value-level no-op, but it returned with the subscript still
              standing in the token stream, so whatever came next swallowed it
              and the expression silently answered the WHOLE STRING: pxx printed
              `hello` where fpc 3.2.2 prints `h`, with no diagnostic. Three faces
              by position from that one cause -- silent wrong value in an
              assignment, `cannot assign AnsiString to Char`, and `expected ')'
              before '['` in argument position -- which is why it read as three
              defects.

              There is nothing to reinterpret, so the base IS the operand; the
              cast owes the tail only a node and a type. The suffix loop below
              already states the string-index rule (`[i]` on a string yields
              tyChar) for `PR(raw)^.s[2]`, so this adds a caller to that walk
              rather than a fifth private one -- which is the whole point, since
              a fifth walker is what
              refactor-p-one-lvalue-path-for-statements-and-expressions exists
              to stop.
              bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index }
            node := CurASTNode;
            tk   := IntToTypeKind(ASTTk[CurASTNode]);
            { ...but "the base IS the operand" holds only for a STRING operand.
              A POINTER slot (`type t = AnsiString; var r: Pointer; t(r)[2]`)
              has nothing string-shaped on the node at all: it is tyPointer, so
              the retag below moved only the TK while the walk kept indexing a
              raw pointer, and the read answered a blank. The operand class is
              exactly what a `TAlias(x)` call site hides -- the arm above was
              measured on a string variable and "this part works" scoped to
              that, one operand class over.

              A REINTERPRET needs a node, not a tag: the same AN_PTR_CAST the
              whole-value store already builds through FinishCastAsLValueStore,
              carrying the alias's string kind, so the IR lowering can tell a
              string cast from the PChar adapter. ival -1 is the built-in-cast
              marker the ident path uses, deliberately NOT the alias index --
              this is a non-pointer alias and every reader of that slot expects
              a POINTER alias row there.
              bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere }
            if tk = tyPointer then
            begin
              node := AllocNode(AN_PTR_CAST);
              ASTLeft[node] := CurASTNode;
              ASTIVal[node] := -1;
              ASTTk[node]   := AliasTk[aliasIdx];
              CurASTNode    := node;
              tk            := IntToTypeKind(ASTTk[node]);
            end;
            if not (TypeIsFrozenString(tk) or (tk = tyString) or
                    (tk = tyAnsiString)) then
              tk := IntToTypeKind(AliasTk[aliasIdx]);
            recName := REC_NONE;
          end
          else
          begin
          node := AllocNode(AN_PTR_CAST);
          ASTLeft[node] := CurASTNode;
          { A custom alias to ^Char/^AnsiChar (e.g. `type PC = ^Char; PC(s)`)
            must behave like PChar(s): the -2 adapter skips the 8-byte length
            prefix for a string operand (and is a plain reinterpret otherwise),
            instead of pointing at the prefix. See bug-pointer-cast-custom-alias.

            ...but ONLY when the pointee is a bare Char. `AliasElemTk = tyChar`
            is a PROXY for "this points at a character", and it is also true of
            `PCharA = ^array[0..3] of Char`, whose pointee is an ARRAY that
            happens to hold chars. Stamping -2 there is not merely the wrong
            adapter: -2 REPLACES aliasIdx in the same slot, and aliasIdx is the
            only thing carrying AliasPtrElemArrAi — the pointee's array row. So
            the subscript lost the element type entirely and the AN_INDEX came
            out tk=0 (tyUnknown), measured with PXXDBG=a.ast.

            What that cost: `PCharA(@ca)^[1]` printed 7061644217361130338 where
            fpc 3.2.2 prints `b`, and `Ord(PCharA(@ca)^[1])` gave 1644192610
            against 98 — TypeSlotSize(tyUnknown) is a 4-byte read. Silent, no
            diagnostic. The same line through a POINTER VARIABLE (`p := @ca;
            p^[1]`) was always correct, because that route asks the SYMBOL's
            SymPtrElemArrAi and never passes through this stamp.

            Every NUMERIC element kind was unaffected and correct — byte, word,
            integer, int64, double all match FPC — because none of them takes
            this branch. Only an array whose ELEMENT is Char could reach it, so
            the one flavour that looks least likely to have a width bug was the
            only one that had one.
            bug-p-a-pointer-alias-to-an-array-of-char-takes-the-pchar-adapter }
          if (AliasElemTk[aliasIdx] = Ord(tyChar)) and
             (AliasPtrElemArrAi[aliasIdx] < 0) then
            ASTIVal[node] := -2
          else
            ASTIVal[node] := aliasIdx;
          ASTTk[node]   := Ord(tyPointer);
          { Set locals so the suffix loop below can resolve ^ and .field }
          tk      := tyPointer;
          recName := AliasElemRec[aliasIdx];  { pointee record id, used after ^ }
          { An ARRAY cast denotes the ARRAY, not a pointer to it, so it carries
            an implicit `^`: `TArr(aa)[1]` is `PArr(@aa)^[1]`. Injecting the
            deref HERE rather than teaching the suffix loop about array casts is
            what keeps this from becoming a sixth postfix walker -- from this
            point the node is byte-for-byte what the PArr spelling produces, and
            the loop below cannot tell the two apart. }
          if arrCast then
          begin
            acDeref := AllocNode(AN_DEREF);
            ASTLeft[acDeref] := node;
            ASTIVal[acDeref] := AliasElemRec[aliasIdx];
            ASTTk[acDeref] := ArrTypeElemTk[AliasPtrElemArrAi[aliasIdx]];
            node := acDeref;
            tk := IntToTypeKind(ArrTypeElemTk[AliasPtrElemArrAi[aliasIdx]]);
          end;
          end;
          { Inline metaclass-cast construction `TFooClass(expr).Create(args)`: the
            alias is a `class of T` (element tyClass) and the next selector is
            `.Create`. Dispatch through the metaclass like the variable form (the
            streamer's `TComponentClass(GetClass(n)).Create(owner)`). }
          { `TFooClass(expr).AnyCtor(args)` -- an inline metaclass CAST, then construct.

            Two things this used to get wrong, both the same shape as the metaclass-VAR path:
            it matched only a constructor literally spelled `create`, and it picked the
            overload with FindUMeth (first NAME match, argument count ignored). fpjson does
            `TJSONObjectClass(DefaultJSONInstanceTypes[jitObject]).Create(Data)` where Create
            is overloaded (parameterless, and `array of const`) -- so it picked the
            PARAMETERLESS one and then complained about the argument it did not want.

            The name is only consumed once it is known to BE a constructor, so a non-ctor
            member still falls through to the paths below. }
          { ...or the name is `Create` and the class declares NO constructor at all:
            the implicit root ctor. Same fallback the metaclass-VARIABLE receiver
            grew in ParseMetaclassMemberTail -- both spellings reach the one
            BuildMetaclassNew, so both must agree on what `Create` means.
            bug-a-metaclass-create-needs-a-declared-constructor }
          if (IntToTypeKind(AliasElemTk[aliasIdx]) = tyClass) and
             (AliasElemRec[aliasIdx] >= REC_UCLASS_BASE) and
             (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) and
             (((FindUMeth(AliasElemRec[aliasIdx] - REC_UCLASS_BASE, GetTokenStr(TokPos)) >= 0) and
               UMthIsCtor[FindUMeth(AliasElemRec[aliasIdx] - REC_UCLASS_BASE, GetTokenStr(TokPos))]) or
              ((FindUMeth(AliasElemRec[aliasIdx] - REC_UCLASS_BASE, GetTokenStr(TokPos)) < 0) and
               CaseEqual(GetTokenStr(TokPos), 'Create'))) then
          begin
            mcCtorCi := AliasElemRec[aliasIdx] - REC_UCLASS_BASE;
            mcCtorNm := GetTokenStr(TokPos);
            Next;   { consume '.'  -> CurTok is the ctor name, '(' at TokPos }
            i := FindUMethOverloadAhead(mcCtorCi, mcCtorNm, CountCallArgsAhead);
            if i < 0 then i := FindUMeth(mcCtorCi, mcCtorNm);
            if i >= 0 then
            begin
              EnforceMethVis(i, mcCtorNm);
              Next; { consume the constructor name }
              node := BuildMetaclassNew(node, mcCtorCi, i);
              CurASTNode := node;
              LastExprTk := tyClass;
              Exit;
            end;
            Next; { consume `Create`: the implicit root ctor, mmi = -1 }
            node := BuildMetaclassNew(node, mcCtorCi, -1);
            CurASTNode := node;
            LastExprTk := tyClass;
            Exit;
          end;
          { Run suffix loop: handle chains of ^, .field, and [i] on the cast result. }
          { The suffix chain -- `^`, `.field`, `[i]` -- through the ONE walker
            the record-name spelling below also uses. aliasIdx is this cast's
            alias row and the seed is that row's element, so the resolver is
            asked and its decline restores to the alias.
            refactor-p-three-hand-rolled-postfix-loops }
          ParseCastPostfixSuffix(node, tk, recName, aliasIdx,
                                 IntToTypeKind(AliasElemTk[aliasIdx]),
                                 AliasElemRec[aliasIdx],
                                 0, Ord(tyUnknown), REC_NONE);
          CurASTNode := node;
          LastExprTk := tk;
          Exit;
        end
        else
        begin
          { Built-in typecast }
          castTk := tyUnknown;
          if CaseEqual(name, 'pchar') or CaseEqual(name, 'pansichar') or
             CaseEqual(name, 'pwidechar') then
          begin
            { PChar(s): yields a C `const char*` into the string's char data.
              Lowered specially (sentinel -2) to skip the inline length prefix
              for string operands; a plain Pointer reinterpret otherwise.

              PWideChar shares this arm rather than getting its own, and the
              ONLY thing that differs is the ELEMENT the cast yields — which is
              why it is a variable here instead of a second fifty-line copy with
              tyChar changed to tyWideChar in three places. The pointer
              operation is identical: same -2 adapter, same +8 past an inline
              length prefix, same PXXPCharOf for a managed handle.

              A PWideChar element is tyWideChar, so `p^` is a WideChar and `p[i]`
              steps two bytes. That is the same typing PWideChar already gets as
              a DECLARED type (ParseTypeKind's pwidechar arm sets
              LastTypePointerElemTk := tyWideChar); the cast was simply missing,
              so `var p: PWideChar` compiled and `p := PWideChar(w)` was
              "undefined variable (PWideChar)".

              GATED ON PXX_WIDE_PAYLOAD, and the measurement is why. I first wrote
              this arm ungated, on the reasoning that WideString's UTF-8 payload
              is an INHERITED divergence the cast merely passes along. That is
              false, and one probe said so: on 'hi', `w[1]` is 104 in both
              compilers, because indexing steps ONE byte through the UTF-8
              payload and widens — right for ASCII by construction. But
              `PWideChar(w)[0]` steps TWO bytes and yields 26984 ($6968, 'h' and
              'i' packed) where FPC gives 104. So the cast does not inherit the
              existing divergence; it introduces a NEW one, and on plain ASCII,
              which is where nobody would look for it.

              Under the define the same probe gives 104 and the arm is simply
              correct. So it is allowed there and REFUSED otherwise, with the
              refusal naming the gate. A program that cannot compile is a worse
              outcome than one that runs — but a program that silently reads
              packed byte pairs as characters is worse than both, and that is
              this repo's expensive bug class exactly: a plausible wrong value
              far from its cause. The real unblock is retiring the gate, which
              is measured and ticketed as
              chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload. }
            if CaseEqual(name, 'pwidechar') then
            begin
              if not PasDefineExists('PXX_WIDE_PAYLOAD') then
                Error('PWideChar(...) needs {$define PXX_WIDE_PAYLOAD}: without it a ' +
                      'WideString holds UTF-8 bytes, so the cast would walk them two at ' +
                      'a time and yield packed byte pairs instead of characters ' +
                      '(chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload)');
              ptrCastElemTk := tyWideChar;
            end
            else ptrCastElemTk := tyChar;
            Next; { consume type name }
            Expect(tkLParen, '(');
            ParseExpr;
            Expect(tkRParen, ')');
            node := AllocNode(AN_PTR_CAST);
            ASTLeft[node] := CurASTNode;
            ASTIVal[node] := -2; { PChar adapter }
            ASTTk[node]   := Ord(tyPointer);
            { `PChar(s)^` — deref of the cast: a char lvalue at the string's
              first data byte (Synapse's `Stream.Write(PAnsiChar(Value)^, ...)`
              — bug-cast-deref-as-varparam-arg). Mirrors the Pointer(expr)^
              untyped-deref below; by-ref args take the address. }
            if CurTok.Kind = tkCaret then
            begin
              Next;
              indexNode := AllocNode(AN_DEREF);
              ASTLeft[indexNode] := node;
              ASTTk[indexNode] := Ord(ptrCastElemTk);
              CurASTNode := indexNode;
              LastExprTk := ptrCastElemTk;
              Exit;
            end;
            { PChar(s)[i]: index the cast result -> a char element. The shared
              postfix loop's AN_PTR_CAST branch reads AliasElemTk[ASTIVal], which
              the -2 adapter has no entry for, so handle the subscript here. }
            while CurTok.Kind = tkLBrack do
            begin
              Next; { consume '[' }
              ParseExpr;
              Expect(tkRBrack, ']');
              indexNode := AllocNode(AN_INDEX);
              ASTLeft[indexNode]  := node;
              ASTRight[indexNode] := CurASTNode;
              ASTTk[indexNode]    := Ord(ptrCastElemTk);
              node := indexNode;
            end;
            CurASTNode    := node;
            if ASTKind[node] = AN_INDEX then LastExprTk := ptrCastElemTk
            else LastExprTk := tyPointer;
            Exit;
          end;
          { The ONE builtin-scalar table, shared with ParseTypeKind. This site
            used to carry its own ~12-arm subset of it, so a dozen names that
            DECLARED fine were "undefined variable" in a cast (ByteBool,
            WordBool, LongBool, Comp, ValReal, TDateTime, Currency, SizeUInt,
            UTF8String, RawByteString, OleVariant, CodePointer — all legal in
            FPC), and where the two overlapped they disagreed: this chain said
            `longint` was tyInteger and `nativeint`/`ptrint` tyInt64, which is
            simply false on a 32-bit target.
            bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree }
          castTk := BuiltinScalarTypeKind(name);
          { `string` is a KEYWORD, not one of the identifier-spelled builtins,
            so it stays here rather than joining the shared table. }
          if (castTk = tyUnknown) and CaseEqual(name, 'string') then castTk := tyString;
          { Ordinal->enum typecast, TEnum(intExpr): a reinterpret at the enum's
            OWN storage width, which under {$PACKENUM} is no longer always
            integer-sized (cf. ParseTypeKind / the SizeOf branch above). The
            enum->ordinal direction already worked via the Integer(...) case.
            See bug-integer-to-enum-typecast-undefined-variable.

            castSem is captured HERE rather than re-derived below, because the
            identity guard used to read `castTk = tyInteger` -- which was a
            correct test only while every enum WAS tyInteger. Narrowing the kind
            without moving that guard would have made `TSmall(i)` under
            {$PACKENUM 1} lose its enum identity and print an ordinal, with
            nothing failing: the same shape as NodeSemIdOf naming one of five
            call kinds. Two lines that must change together, so they hold one
            value between them instead of agreeing by coincidence. }
          { …and a BUILTIN name may confer one too: `ByteBool(x)` is a
            reinterpret at one byte that also says the value is a truth value.
            Asked from the same shadow table the DECLARATION path asks, so a
            cast and a declaration of the same name cannot disagree -- the
            drift BuiltinScalarTypeKind's own header exists to end. }
          castSem := BuiltinScalarSemId(name);
          if castTk = tyUnknown then
          begin
            castSem := SemEnum(FindEnumType(name));
            if castSem >= 0 then castTk := EnumStorageTypeKind(castSem);
          end;

          if castTk <> tyUnknown then
          begin
            Next; { consume type name }
            Expect(tkLParen, '(');
            ParseExpr;
            Expect(tkRParen, ')');
            { THE SHARED CONSTRUCTION HALF -- see TryScalarNamedCast, which
              this door's own arms were the model for. It answers for a variant
              target, an `operator Explicit`, an ordinal narrowing (carrying the
              enum identity captured above) and a float conversion, and DECLINES
              tyPointer and the string kinds, whose continuations below are
              genuinely this door's own. }
            { `ByteBool(True)` is a truth value being SPELLED as a sized
              boolean, so it materialises all-bits-set exactly as an assignment
              does -- fpc answers Ord(ByteBool(True)) = -1. `ByteBool(200)` is
              NOT this shape: an integer source is a reinterpret and keeps its
              bits, which is the row that says the two are different questions.
              Ahead of TryScalarNamedCast because the operand is what changes,
              not the construction. }
            if SemIsBool(castSem) and
               ((IntToTypeKind(ASTTk[CurASTNode]) = tyBoolean) or
                (IntToTypeKind(ASTTk[CurASTNode]) = tyBool8)) then
              CurASTNode := SemBoolMaterialise(CurASTNode, castTk);
            { A CHAR operand cast to a STRING type is a CONVERSION, not a
              reinterpret: `AnsiString(c)` must materialise a 1-char string.
              Falling through built an AN_PTR_CAST that re-typed the character
              itself as a string, so the string machinery dereferenced the
              ordinal 65 as a pointer — a SEGFAULT, not a wrong value, on every
              identifier spelling (AnsiString, UnicodeString, WideString,
              UTF8String, RawByteString) while the KEYWORD spelling `String(c)`
              printed 'A'. fpc accepts all six and answers 'A'.

              This is the exact mirror of the defect the tkString_T arm's own
              closing comment records: there the keyword branch lacked the
              POINTER cast the identifier path had, and it was fixed by teaching
              the keyword branch. The sibling direction was never checked, so the
              same seam reopened facing the other way. Hence the shared
              WrapCharToStringExpr rather than a second copy of the desugar —
              the construction is one thing or it drifts again.
              refactor-p-five-dispatch-sites-for-one-named-type-cast }
            if TypeIsAnyString(castTk) and
               (IntToTypeKind(ASTTk[CurASTNode]) = tyChar) then
            begin
              CurASTNode := WrapCharToStringExpr(CurASTNode);
              LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
              Exit;
            end;
            if TryScalarNamedCast(castTk, castSem) then Exit;
            { ...and on a promotable int, `Pointer(n)` IS `@n`, so make it one.
              Punning the operand worked for a LOCAL, whose rvalue already is
              its slot address, and CRASHED for a by-ref PARAMETER, whose cell
              holds the address instead — one spelling, two meanings, with a
              segfault on the side that a line earlier had worked. AN_ADDR is
              right for both: it resolves through the parameter cell exactly as
              `@n` does. Not shared: TypeIsOrdinal INCLUDES tyPointer (the trap
              IRLowerCallArg's promo arms document), and the alias door routes a
              pointer alias through the suffix walk instead. }
            if (castTk = tyPointer) and
               TypeIsPromoInt(IntToTypeKind(ASTTk[CurASTNode])) then
            begin
              node := AllocNode(AN_ADDR);
              ASTLeft[node] := CurASTNode;
              ASTTk[node] := Ord(tyPointer);
              CurASTNode := node;
              LastExprTk := tyPointer;
              Exit;
            end;
            { A VARIANT operand converts rather than reinterpreting the record.
              Reached here only for the kinds TryScalarNamedCast declined --
              `AnsiString(v)` and the pointer spellings; the ordinal targets ask
              it inside that routine. `Pointer(v)` is excluded there and stays a
              reinterpret. }
            vcNode := VariantCastToTemp(CurASTNode, castTk);
            if vcNode >= 0 then
            begin
              CurASTNode := vcNode;
              LastExprTk := castTk;
              Exit;
            end;
            node := AllocNode(AN_PTR_CAST);
            ASTLeft[node] := CurASTNode;
            ASTIVal[node] := -1; { indicates built-in cast }
            ASTTk[node]   := Ord(castTk);
            { `TEnum(i)` — the cast target IS the value's enum type, and the
              reinterpret to its storage kind is the only trace left of it. Keep
              the identity or WriteLn prints the ordinal. castSem is SEM_NONE for
              `Integer(x)` and every other builtin spelling, and is set only by
              the enum arm above -- it does not ask what kind the cast became,
              which is what let {$PACKENUM} narrow the kind safely. }
            if castSem <> SEM_NONE then ASTSemId[node] := castSem;
            { `Pointer(expr)^` — FPC's untyped deref, legal where only the
              ADDRESS matters (an untyped var/const argument: synautil's
              `Move(Pointer(Value)^, ...)` is the driving consumer). There is
              no pointee type, so model the deref as a Byte lvalue — the
              address is identical and untyped params take the address. }
            if (castTk = tyPointer) and (CurTok.Kind = tkCaret) then
            begin
              Next;
              indexNode := AllocNode(AN_DEREF);
              ASTLeft[indexNode] := node;
              ASTTk[indexNode] := Ord(tyUInt8);
              CurASTNode := indexNode;
              LastExprTk := tyUInt8;
              Exit;
            end;
            { `AnsiString(r)[2]` -- the BUILT-IN spelling of the indexed string
              cast, which did not parse at all: this arm exits with the cast
              node and the subscript still standing, so the enclosing expression
              met it and reported `expected ')' before '['`. Its alias twin
              `t(r)[2]` reaches the shared selector walk a few hundred lines up
              and has done since
              bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index --
              one concept, two spellings, one of them taught, which is the third
              time this exact seam has been fixed in this file.

              Hand the walk the cast NODE, not the operand: over a Pointer slot
              the operand is a pointer and only the node carries the string
              kind. The walk already answers tyChar for `[i]` on a string base.
              bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere }
            if TypeIsAnyString(castTk) and (CurTok.Kind = tkLBrack) then
            begin
              CurASTNode := ParseClassRecordSelectors(node, REC_NONE, castTk);
              LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
              Exit;
            end;
            CurASTNode    := node;
            LastExprTk    := castTk;
            Exit;
          end;
        end;
      end;

      { `TRec.Create(...)` — an advanced-record CONSTRUCTOR, invoked on the TYPE.

        A record ctor has no heap and no VMT: it just fills a fresh receiver. So the call
        materialises a hidden temp of the record type, passes it as Self (by reference, like
        any record method), and the expression's VALUE is that temp — which is exactly the
        ASTLiftedVar shape (call emitted as a statement, node yields the var).

        Checked BEFORE the class path below: that one lowers to GetMem, which would
        heap-allocate a record and hand back a pointer where a value belongs. }
      if (idx < 0) and (procIdx < 0) and (IsRecordType(name) <> REC_NONE) and
         (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
         (Tokens[TokPos+1].Kind = tkIdent) and
         (FindUMeth(IsRecordType(name) - REC_UCLASS_BASE, GetTokenStr(TokPos+1)) >= 0) then
      begin
        rcCi := IsRecordType(name) - REC_UCLASS_BASE;
        rcMmi := FindUMeth(rcCi, GetTokenStr(TokPos+1));
        rcPi := UMthProc_[rcMmi];

        Next; { record type name }
        Next; { dot }
        Next; { method name }

        if (UClsHelperTk[rcCi] >= 0) or UMthIsStatic[rcMmi] then
        begin
          { A STATIC method through the type name — a TYPE HELPER's
            (TU32Helper.GetSignMask) or a plain record's
            (`TRec.MakeI(5)`, rtl-generics' TComparerService). No receiver
            exists: Self is a by-value dummy the static body may not read, and
            the call's type is the method's REAL return type.

            The discriminator is STATIC, not helper-ness. It was written as
            `UClsHelperTk >= 0` because a helper was the case in hand, so a
            plain record's static kept the record-FACTORY shape below: it
            allocated a temp receiver, typed the call tyRecord, and the
            expression read that untouched temp — `TRec.MakeI(5)` returned
            GARBAGE with no diagnostic, at every call site, for any return type.
            One test (`class function` in a record, called on the type) covers
            both arms now. }
          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := rcPi;
          ASTTk[mcallNode] := Ord(Procs[rcPi].RetType);
          rcSelf := AllocNode(AN_INT_LIT);
          ASTIVal[rcSelf] := 0;
          ASTTk[rcSelf] := Ord(Procs[rcPi].Params[0].TypeKind);
        end
        else
        begin
          savedRecId := LastTypeRecId;
          LastTypeRecId := REC_UCLASS_BASE + rcCi;
          rcTmp := AllocVar('', tyRecord);          { the fresh receiver }
          LastTypeRecId := savedRecId;

          mcallNode := AllocNode(AN_CALL);
          ASTIVal[mcallNode] := rcPi;
          ASTTk[mcallNode] := Ord(tyRecord);
          ASTLiftedVar[mcallNode] := rcTmp;

          rcSelf := AllocNode(AN_IDENT);            { Self = the temp, passed by reference }
          ASTIVal[rcSelf] := rcTmp;
          ASTTk[rcSelf] := Ord(tyRecord);
        end;
        rcSelfArg := AllocNode(AN_ARG);
        ASTLeft[rcSelfArg] := rcSelf;
        ASTLeft[mcallNode] := rcSelfArg;
        mlastArg := rcSelfArg;

        if CurTok.Kind = tkLParen then
        begin
          Next;
          while CurTok.Kind <> tkRParen do
          begin
            ParseExpr;
            margSeq := AllocNode(AN_ARG);
            ASTLeft[margSeq] := CurASTNode;
            ASTRight[mlastArg] := margSeq;
            mlastArg := margSeq;
            if CurTok.Kind = tkComma then Next
            else if CurTok.Kind <> tkRParen then Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');
        end;

        if (UClsHelperTk[rcCi] >= 0) or UMthIsStatic[rcMmi] then
          LastExprTk := Procs[rcPi].RetType
        else
        begin
          LastTypeRecId := REC_UCLASS_BASE + rcCi;
          LastExprTk := tyRecord;
          { postfix chaining on the ctor result: TPt.Create(7,8).Sum — the
            lifted temp is an addressable record, so the ordinary selector
            machinery works on the call node (the known gap on
            feature-pascal-record-constructors). }
          if CurTok.Kind in [tkDot, tkLBrack] then
          begin
            castTk2 := tyRecord;
            mcallNode := ParseClassRecordSelectors(mcallNode, REC_UCLASS_BASE + rcCi, castTk2);
            LastExprTk := castTk2;
          end;
        end;
        CurASTNode := mcallNode;
        Exit;
      end;

      { `TOuter.TInner.Create` — a nested class constructed through its owner.
        One extra hop, taken before the fast path below so that path sees the
        shape it already knows; the resolved nested ci is carried past the flat
        lookup, which would otherwise bind whichever class of that bare name
        registered first. bug-a-duplicate-class-name-check-is-scope-blind }
      nestCtorCi := -1;
      if (idx < 0) and (procIdx < 0) and (NestedOwnerCi(name) >= 0) and
         (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
         (FindNestedClassLikeCi(NestedOwnerCi(name), GetTokenStr(TokPos+1)) >= 0) then
      begin
        { Walk the whole `. nested . nested ...` run, then require `Create` after
          it. This was a FIXED three-token lookahead, so exactly one level of
          nesting could be constructed and `tthree.tmid.tleaf.Create` reported
          "class method not found: Create". Scanning before consuming keeps the
          non-constructor spellings untouched: nothing is eaten unless the run
          really does end in Create.
          bug-p-a-nested-class-method-implementation-takes-only-one-qualifier }
        nestScanCi := NestedOwnerCi(name);
        nestScanPos := TokPos;          { at the '.' after the outermost name }
        nestDepth := 0;
        while (nestScanPos + 1 < TokCount) and (Tokens[nestScanPos].Kind = tkDot) and
              (Tokens[nestScanPos+1].Kind = tkIdent) and
              (FindNestedClassLikeCi(nestScanCi, GetTokenStr(nestScanPos+1)) >= 0) do
        begin
          nestScanCi := FindNestedClassLikeCi(nestScanCi, GetTokenStr(nestScanPos+1));
          Inc(nestDepth);
          nestScanPos := nestScanPos + 2;
        end;
        if (nestDepth > 0) and (nestScanPos + 1 < TokCount) and
           (Tokens[nestScanPos].Kind = tkDot) and (Tokens[nestScanPos+1].Kind = tkIdent) and
           ((GetTokenStr(nestScanPos+1) = 'Create') or (GetTokenStr(nestScanPos+1) = 'create')) then
        begin
          nestCtorCi := nestScanCi;
          for nestI := 1 to nestDepth do
          begin
            Next;   { the enclosing class name }
            Next;   { '.' — CurTok is now the next nested type name }
          end;
          { The RESOLVED class's own name, not the spelling that named it. For a
            nested CLASS the two are identical, which is why the token worked; for
            a nested type ALIAS the spelling is `TP` and no class of that name
            exists, so the `IsClassType(name)` gate below refused the very hop
            this walk had just resolved. Taking the name off the ci makes the
            alias case take the same road the registry case already takes.
            bug-p-a-qualified-nested-alias-is-invisible-to-low-high-and-a-constructor }
          name := GetTokenStrFromRaw(UClsNOff[nestCtorCi], UClsNLen[nestCtorCi]);
        end;
      end;
      { `TAB.Create(1 + 2, i)` -- Delphi's DYNAMIC-ARRAY constructor, and it is
        not a constructor at all: it is the element list `[1 + 2, i]` wearing a
        method call's spelling. fpc-testsuite tarrconstr1 / tarrconstr6.

        So this arm parses the argument list with the SAME routine the
        declaration-form initialiser uses and hands the result to the SAME
        retag, rather than growing a third way to build a dynamic-array
        literal. `[...]` in a statement, `(...)` in a declaration and
        `T.Create(...)` here are now one node built one way; the alternative
        was three call sites that agree today.

        THE TYPE NAME IS WHY THIS CANNOT WAIT FOR AN_ASSIGN. The literal
        spellings are retagged from the ASSIGNMENT's left-hand side, which is
        the only place their element type is known. Here the element type is on
        the row `FindArrayType` just returned, and it is known BEFORE the node
        has a destination -- which is the whole point, because tarrconstr6
        passes `TLongIntArray.Create(1, 2, 3)` as an ARGUMENT and there is no
        assignment to read it off. A construct that only works when assigned is
        exactly the half-a-feature this file's siblings keep recording.

        Refuses a dynamic array of FIXED ROWS for the reason ir.inc's AN_ASSIGN
        arm refuses it: a row is bytes inside the outer block, not a handle, so
        the open-array constructor lowering has nothing to build and the retag
        would emit silent garbage. Named here as well as there because the two
        paths reach the lowering independently. }
      if (idx < 0) and (procIdx < 0) and (CurTok.Kind = tkIdent) and
         (FindArrayType(name) >= 0) and ArrTypeIsDyn[FindArrayType(name)] and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
         ((GetTokenStr(TokPos+1) = 'Create') or (GetTokenStr(TokPos+1) = 'create')) then
      begin
        dynCtorAi := FindArrayType(name);
        Next;   { the array type name }
        Next;   { '.' }
        Next;   { 'Create' }
        if ArrTypeElemRowLen[dynCtorAi] > 0 then
          Error('a dynamic array of fixed rows cannot be built by ' + name +
                '.Create -- assign the rows after SetLength');
        CurASTNode := ParseDynArrayInitElemsAST(0);
        RetagSetLitAsArrayCtor(CurASTNode,
                               IntToTypeKind(ArrTypeElemTk[dynCtorAi]),
                               ArrTypeDynDepth[dynCtorAi]);
        Exit;
      end;
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
         (Tokens[TokPos+1].Kind = tkIdent) and
         ((GetTokenStr(TokPos+1) = 'Create') or (GetTokenStr(TokPos+1) = 'create')) then
      begin
        Next; { Eat class name }
        Next; { Eat dot }
        Next; { Eat 'Create' }

        argsHead := -1;
        lastArg := -1;
        { `sysutils.Exception.Create(..)` must construct SYSUTILS' class. The
          qualifier was already consumed into qUnit above, and until now it was
          only consumed — the class itself resolved by flat first match, so a
          qualified name silently built whichever unit's class registered
          first. That was invisible while at most one unit declared any given
          class name; it stopped being invisible when pylib and sysutils each
          got their own `Exception` (siblings under ExceptionBase). Falls back
          to the flat lookup when the qualified one finds nothing, so a
          qualifier that names a module rather than the declaring unit behaves
          as before. }
        ctorCi := -1;
        if nestCtorCi >= 0 then ctorCi := nestCtorCi;   { the nested hop above }
        if (ctorCi < 0) and (qUnit >= 0) then ctorCi := FindUClassInUnit(name, qUnit);
        if ctorCi < 0 then ctorCi := FindUClass(name);
        if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual CTOR name=', name,
          ' qunit=', qUnit, ' inunit=', FindUClassInUnit(name, qUnit),
          ' flat=', FindUClass(name), ' -> ctorCi=', ctorCi);
        ctorArgN := 0;
        if CurTok.Kind = tkLParen then
        begin
          Next;
          while CurTok.Kind <> tkRParen do
          begin
            { THE BRACKET DOOR, DELEGATED -- and this one was answering the
              wrong half of the question, not merely asking it locally. It sent
              every `[...]` to ParseVarRecLiteralAST because its predicate is a
              Boolean, so `TC.Create([10, 20, 30])` against
              `constructor Create(const A: array of Integer)` built a TVarRec
              vector the callee read with an Integer stride: sum 10 against
              fpc's 60, while `o.M([10, 20, 30])` on the identical signature in
              the same file was right. ClassCtorArraySigAt returns the ctor row,
              which is what TryParseBracketArgForSlot needs.
              bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path }
            ctorSig := -1;
            ctorBrk := -1;
            if CurTok.Kind = tkLBrack then
            begin
              ctorSig := ClassCtorArraySigAt(ctorCi, ctorArgN);
              if ctorSig >= 0 then
                ctorBrk := TryParseBracketArgForSlot(ctorSig, ctorArgN + 1);
            end;
            if ctorBrk >= 0 then
              CurASTNode := ctorBrk
            else
              ParseExpr;
            Inc(ctorArgN);
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := CurASTNode;
            if argsHead = -1 then
              argsHead := argSeq
            else
              ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            if CurTok.Kind = tkComma then
              Next
            else if CurTok.Kind <> tkRParen then
              Error('expected comma or close parenthesis');
          end;
          Expect(tkRParen, ')');
        end;

        idx := IsRecordType(name);
        if idx = REC_NONE then
        begin
          { Use the class ALREADY resolved above, do not resolve it a second
            time. `ctorCi` honours the unit qualifier; a fresh `FindUClass(name)`
            here is flat, so it silently answered the other unit's `Exception`
            and `idx` — which is what every consumer below uses (RecSize, the
            overload match, the emitted class) — disagreed with `ctorCi`. Two
            lookups for one question, and only one of them had the fix. }
          if ctorCi >= 0 then
            idx := REC_UCLASS_BASE + ctorCi;
        end;
        prevTok := RecSize(idx);

        { Constructor ARITY check (FPC parity) + trailing-default fill. The
          codegen's ctor marshalling pops exactly ParamCount registers, so a
          missing (or extra) argument used to compile silently and desync the
          caller's stack by 8 bytes per miscount — a garbage-Self /
          nondeterministic-crash bug, not a wrong-answer one
          (bug-tthread-execute-writeln-crash's true root cause). }
        if idx >= REC_UCLASS_BASE then
        begin
          i := FindUCtorOverloadArgs(idx - REC_UCLASS_BASE, argsHead);
          if i >= 0 then
          begin
            mpi := UMthProc_[i];
            { count the explicit args parsed above }
            mlastArg := 0;
            argSeq := argsHead;
            while argSeq <> -1 do
            begin
              Inc(mlastArg);
              argSeq := ASTRight[argSeq];
            end;
            if mlastArg > Procs[mpi].ParamCount - 1 then
              Error('too many arguments to constructor ' + name + '.Create');
            { fill missing trailing args from declared defaults; a missing
              non-default arg is a compile error like FPC }
            while mlastArg < Procs[mpi].ParamCount - 1 do
            begin
              if not ProcParamHasDefault[mpi * MAX_PROC_PARAMS + (mlastArg + 1)] then
                Error('not enough arguments to constructor ' + name +
                      '.Create (parameter ' + Procs[mpi].Params[mlastArg + 1].Name + ' has no default)');
              { ONE builder for a declared default, shared with every other call
                path (DefaultArgValueNode). This site used to hand-roll a
                str/ordinal pair of its own, which meant it missed everything
                the shared builder had learned since: float and set defaults,
                the AnsiString-vs-frozen tagging, and — the one that smashed the
                stack — retagging a VARIANT parameter's ordinal as tyInteger so
                IRLowerCallArg BOXES it. Tagged tyVariant the boxing was skipped
                and the callee dereferenced the bare ordinal 0 as a 16-byte
                variant slot, corrupting the caller's frame far from the call
                (bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory). }
              exprNode := DefaultArgValueNode(mpi, mlastArg + 1);
              argSeq := AllocNode(AN_ARG);
              ASTLeft[argSeq] := exprNode;
              if argsHead = -1 then
                argsHead := argSeq
              else
                ASTRight[lastArg] := argSeq;
              lastArg := argSeq;
              Inc(mlastArg);
            end;
          end
          else if argsHead <> -1 then
            Error(name + ' has no constructor Create, but arguments were given');
        end;

        { Construct GetMem(sz) AST node }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := -Ord(tkGetMem);
        ASTTk[node] := Ord(tyClass);
        ASTRight[node] := idx; { preserve created user-class id }

        exprNode := AllocNode(AN_INT_LIT);
        ASTIVal[exprNode] := prevTok;
        ASTTk[exprNode] := Ord(tyInteger);

        { The first argument to the GetMem call is the size }
        szArg := AllocNode(AN_ARG);
        ASTLeft[szArg] := exprNode;
        ASTLeft[node] := szArg;

        { The rest of the arguments are constructor arguments! }
        if argsHead <> -1 then
          ASTRight[szArg] := argsHead;

        { A SELECTOR on the fresh instance — `TThing.Create(2).n`,
          `TList.Create.Count`. Without this the chain was simply DROPPED: the
          IR went straight from the GetMem call to the store, so an Integer
          variable received the instance POINTER and the program printed
          garbage with no diagnostic at all
          (bug-p-member-off-a-constructor-result-yields-garbage). The identical
          shape on an ordinary function result — `Make(4).n` — was always
          correct, which is what said the machinery works and only this exit
          was missing it. Same call the TClass(expr) path makes.

          `idx` is ALREADY a full rec id here (REC_UCLASS_BASE + ci, assigned
          just above alongside the arity check) — not a bare class index,
          despite what ASTRight's "user-class id" comment reads like. Adding
          REC_UCLASS_BASE again lands on a different record and every member
          comes back "no such member". }
        castTk := tyClass;
        if CurTok.Kind in [tkDot, tkLBrack] then
        begin
          node := ParseClassRecordSelectors(node, idx, castTk);
          LastExprTk := castTk;
        end;

        CurASTNode := node;
        Exit;
      end;
      if (idx < 0) and (procIdx < 0) and IsClassType(name) and
         (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) then
      begin
        { Same qualified resolution as the `.Create` fast path above: a bare
          FindUClass here is flat, so `sysutils.Exception.CreateFmt` picked
          whichever unit's `Exception` registered first. }
        ci := -1;
        if qUnit >= 0 then ci := FindUClassInUnit(name, qUnit);
        if ci < 0 then ci := FindUClass(name);
        if PxxDbgEnabled('a.qual') then WriteLn('PXXDBG a.qual STATICM name=', name,
          ' mem=', GetTokenStr(TokPos+1), ' qunit=', qUnit, ' flat=', FindUClass(name),
          ' -> ci=', ci);
        mmi := FindUMeth(ci, GetTokenStr(TokPos+1));
        if (mmi >= 0) and (qUnit >= 0) and UMthIsCtor[mmi] and
           (not UMthIsStatic[mmi]) then
        begin
          { A QUALIFIED, NAMED constructor: `sysutils.Exception.CreateFmt(..)`.
            The fast path above matches only the exact spelling `Create`, and
            everything else fell through to ParseLValueAST's class-member arm,
            which resolves the class flat and never sees a qualifier — so the
            wrong unit's constructor ran and `CreateFmt('[%5d]',[3])` came out
            `[%5d]` instead of `[    3]`.

            Construction itself is NOT reimplemented here: this hands off to
            BuildMetaclassNew, the same builder the unqualified arm uses, so the
            two shapes differ only in how the class is looked up. Gated on
            qUnit >= 0 deliberately — with no qualifier there is nothing this
            path knows that the existing one does not. }
          mcCtorNm := GetTokenStr(TokPos+1);
          Next;                        { consume class name }
          Expect(tkDot, '.');          { CurTok is now the ctor name }
          i := FindUMethOverloadAhead(ci, mcCtorNm, CountCallArgsAhead);
          if i < 0 then i := FindUMeth(ci, mcCtorNm);
          if i >= 0 then
          begin
            EnforceMethVis(i, mcCtorNm);
            Next;                      { consume ctor name }
            mselfArg := AllocNode(AN_CLASSREF);
            ASTIVal[mselfArg] := ci;
            ASTTk[mselfArg] := Ord(tyPointer);
            CurASTNode := BuildMetaclassNew(mselfArg, ci, i);
            LastExprTk := tyClass;
            Exit;
          end;
        end;
        if mmi >= 0 then
        begin
          if UMthIsStatic[mmi] then
          begin
            { `TClassName.ClassMethod(...)` in an EXPRESSION. Self is the class named,
              which is exactly what makes `TMyTest.Suite` see Self = TMyTest. }
            mpi := UMthProc_[mmi];
            Next; { consume class name }
            Expect(tkDot, '.');
            Next; { consume method name }
            mselfArg := AllocNode(AN_CLASSREF);
            ASTIVal[mselfArg] := ci;
            ASTTk[mselfArg] := Ord(tyPointer);
            GenVirtSlot := UMthVirSlot[mmi];
            mcallNode := GenMakeStaticMethodCall(mpi, mselfArg);
            LastExprTk := Procs[mpi].RetType;
            { ...and the RESULT may carry a selector tail: `TFactory.GetObj.Inst(14)`.
              This arm used to Exit with the bare call, so the trailing `.Inst(14)`
              was left in the token stream -- where ParseStatementAST's catch-all
              `while not (CurTok.Kind in [...]) do Next` silently ate it. The call
              to GetObj RAN, the chained call VANISHED, exit 0, and the assignment
              stored the object pointer where 42 belonged. It also made
              `TFactory.GetObj.NoSuchXY` COMPILE, because a tail that is skipped is
              never resolved. Same shared walker the instance-reached arm uses
              (pasparser_lval.inc:2602) -- the result's record, never the
              receiver's.
              bug-p-a-call-chained-onto-a-class-method-result-is-dropped }
            if CurTok.Kind = tkDot then
            begin
              tk := LastExprTk;
              if (tk = tyClass) or (tk = tyRecord) then
              begin
                recName := ProcRetRecId[mpi];
                if recName <> REC_NONE then
                begin
                  mcallNode := ParseClassRecordSelectors(mcallNode, recName, tk);
                  LastExprTk := tk;
                end;
              end;
            end;
            CurASTNode := mcallNode;
            Exit;
          end;
        end;
      end;
      { Named set constant — but only if the name does not resolve to a real
        variable/parameter/const symbol first. A same-named variable (FindSetConst
        is case-insensitive: a `set of char` const `C` would otherwise shadow a
        char var `c`) must win. }
      sci := -1;
      if idx < 0 then sci := FindSetConst(name);
      if sci >= 0 then
      begin
        { Named set constant — yields the baked 32-byte mask's address, exactly
          like an all-constant set literal (lowered via IR_SET_LIT). }
        node := AllocNode(AN_SET_CONST_REF);
        ASTIVal[node] := SetConstOff[sci];
        ASTTk[node] := Ord(tySet); CurASTNode := node; Next;
        LastExprTk := tySet;
        Exit;
      end;
      { Past every name-keyed intrinsic: nothing claimed the name, so restore the
        not-yet-bound NilPy def unbound above and let the ordinary call paths use
        it. See the comment at the unbind for why this is not left at -1. }
      if pyLateDefPi >= 0 then procIdx := pyLateDefPi;
      sci := FindStrConst(name);
      { A VARIABLE in scope beats an untyped string constant of the same name. The string
        constant table is not scoped -- a `const S = 'A string';` declared inside one method
        stays visible to every later one -- so without this test a later method's local
        `var S : TJSONString` was silently EXPANDED INTO THE CONSTANT'S TEXT. ParseFactor
        handed back an AN_STR_LIT, consumed the identifier, and left `.AsJSON` unconsumed;
        the caller then reported "expected ," at the dot, pointing at the selector rather
        than at the name it had just mis-resolved.

        Pascal scoping says the innermost declaration wins, and the local var IS innermost
        here. Same discipline the LineEnding fallback below already applies. Found in
        fcl-json's testjsondata.pp, which declares a method-local `const S` early on and a
        method-local `var S : TJSONString` later -- hence the decl-ORDER dependence.

        (The constant table not being SCOPED at all is a separate, larger defect --
        bug-pascal-string-const-not-scoped -- and this guard does not pretend to fix it.)

        …and NOT when the name was reached through an explicit qualifier. A
        written `unit.Name` asks for THAT unit's declaration by construction, so
        an unrelated same-named variable elsewhere has no business cancelling
        it — the same exemption `OwnFieldBeatsSym` already takes above. Without
        it, `mimic_string.digits` stopped resolving the moment the program
        declared anything called `digits`, and the diagnostic named `digits` —
        i.e. it accused the very line that was creating the variable, pointing
        away from the const it had just refused to see. In NilPy that is the
        ordinary spelling of a module import (`digits = string.digits`), which
        is how it reached the corpus as a wall.
        bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails }
      if (sci >= 0) and (qUnit = -1) and (FindSym(name) >= 0) then sci := -1;
      if (sci < 0) and CaseEqual(name, 'LineEnding') and
         ((qUnit <> -1) or (FindSym(name) < 0)) then
      begin
        { System.LineEnding as an ordinary expression (`s := s + LineEnding;`). Same
          FALLBACK discipline as the const-concat path: only when nothing else declares
          the name, so a source's own LineEnding still wins. Interned so it becomes an
          ordinary frozen string literal from here on. }
        sci := RegisterLineEndingConst;
      end;
      if sci >= 0 then
      begin
        { Untyped string constant — expand to a string literal over its span. }
        node := AllocNode(AN_STR_LIT);
        ASTSOffset[node] := StrConstSOff[sci]; ASTSLen[node] := StrConstSLen[sci];
        ASTTk[node] := Ord(tyString); CurASTNode := node; Next;
        { Trailing index `RAMP[i]` -> a char from the literal's frozen storage
          (bug-const-string-index-miscompiles). The AN_STR_LIT base is lowered
          via its IR_CONST_STR value in IRLowerAddress. }
        while CurTok.Kind = tkLBrack do
        begin
          Next;
          indexNode := AllocNode(AN_INDEX);
          ASTLeft[indexNode] := node;
          ParseExpr;
          ASTRight[indexNode] := CurASTNode;
          Expect(tkRBrack, ']');
          ASTTk[indexNode] := Ord(tyChar);
          node := indexNode; CurASTNode := node;
          LastExprTk := tyChar;
        end;
      end
      else if (idx >= 0) and (Syms[idx].Kind = skConst) then
      begin
        { A CONST WITH AN ARGUMENT LIST IS NOT A CALL, AND SILENTLY FOLDING IT
          TO ITS VALUE THREW THE ARGUMENTS AWAY. Pascal is case-insensitive, so
          `const PYITER_MAP = 4;` and `function pyiter_map(...)` in one unit are
          ONE identifier with two meanings -- and compiler/builtin/pylib.pas had
          four such pairs. `pyiter_map(key, v)` resolved here, answered 4, and
          the `(key, v)` was dropped: a plausible small integer where a cursor
          object belonged, on every target. Only i386 ever objected, and only
          indirectly, because it alone refuses to LOAD a const symbol.

          FPC rejects the declaration pair itself ("overloaded identifier
          isn't a function"), so parity could not have found this either. We
          keep accepting the pair -- accepting what FPC rejects is not a defect
          here, and a tag constant beside its constructor is a real thing to
          write -- but a CALL of the const is a mistake in any reading, and the
          rule is to leave the mistake visible rather than to answer it.

          A procedural-typed const (`const F: TFn = @Triple;` then `F(5)`) is a
          real call and does NOT come through here: it is not folded to a
          literal. Checked before this guard was written, both in pxx and in
          FPC, and both answer 15.
          bug-a-a-const-and-a-routine-of-the-same-name-silently-resolve-to-the-const }
        if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
          Error('''' + name + ''' is a CONST and cannot be called. If a routine '
                + 'of this name is also declared, they are the SAME identifier '
                + '(Pascal is case-insensitive) and the const won -- rename one '
                + 'of them');
        { A float-typed const carries its IEEE-754 bits in ConstVal — emit a
          float literal, not an int literal (an AN_INT_LIT tagged tyDouble would
          be mis-codegen'd as an integer). }
        if TypeIsFloat(Syms[idx].TypeKind) then
          node := AllocNode(AN_FLOAT_LIT)
        else
          node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := Syms[idx].ConstVal; ASTTk[node] := Ord(Syms[idx].TypeKind);
        { An enum MEMBER const folds to its ordinal here, which is where the enum
          identity would be lost — carry it on the literal (see ASTSemId). }
        ASTSemId[node] := SymSemId[idx];
        { A CHAR const folds to a bare ordinal too, and a bare ordinal is not a
          one-character STRING to anything downstream: `pv := Dash` stored 45
          into a PChar and segfaulted, while `pv := '-'` and `pv := #45` — which
          both carry the literal's char-pool span — were already right. Give the
          folded node the same span a written literal has, so the PChar assign
          in ir.inc, `case s of Dash`, and the argument coercion all see ONE
          shape rather than two spellings of it.
          bug-single-char-literal-as-pchar-argument-segfaults }
        if IntToTypeKind(ASTTk[node]) = tyChar then EnsureCharLitSpan(node);
        CurASTNode := node; Next;
      end
      else if (CurProc >= 0) and Procs[CurProc].IsFunc and
              (Tokens[TokPos].Kind <> tkLParen) and
              not DelphiMode and
              ((name = Procs[CurProc].Name) or
               CaseEqual(name, LastDotName(Procs[CurProc].Name))) then
      begin
        { Bare function name in its own body, read as a value = the result var
          (FPC `FuncName` synonym for `Result`, e.g. `F := F + x`). The assign
          side (`FuncName := ...`) is handled at the statement level; this is the
          read side. A following `(` is a recursive call, not a result read, so
          it is excluded above and falls through to the call paths below.

          {$mode delphi} delta: in Delphi a bare own-name read is NEVER the result
          var — it is a (recursive) reference to the routine: paramless -> a call,
          with-params -> the function value (an error unless bound to a proc-typed
          target, which the @-relax bind sites handle). So this whole branch is
          skipped in delphi mode; `Result` is used to read the result there. In
          objfpc/default a bare own-name read is the result var (the project flip).

          Now FPC-faithful for ALL param counts (the paramless flip, bug-bare-
          function-name-call-vs-resultvar). A bare paramless own-name no longer
          recurses — `F()` is required to recurse. The 9 paramless self-recursion
          sites in the frontend were pre-hardened to explicit `F()` (commit
          c87785d) before this flip, so self-host stays byte-identical. Trailing
          `.field`/`[i]`/`^` resolve via ParseLValueAST. }
        { Opt-in footgun diagnostic (--warn-self-result): for a PARAMETERLESS
          function, a bare own-name value read is the Result, but a
          recursive-descent author usually meant `Name()`. Self-host-invisible
          (the rule is the same in seed and self-host), so it silently miscompiles
          user code — surface the ambiguity. Only paramless (with-params bare name
          can't be a call, so it is unambiguously Result). See
          bug-paramless-self-recursion-silent-result-read. }
        if WarnSelfResult and (Procs[CurProc].ParamCount = 0) then
          Warn('bare own name ''' + name + ''' reads the result of parameterless '
            + 'function ' + Procs[CurProc].Name + '; write ' + name
            + '() for a recursive call, or Result to read the result');
        Next;
        CurASTNode := ParseLValueAST(Procs[CurProc].RetSymIdx, TokPos - 2);
        LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
      end
      { NilPy: a `-> None` def is a procedure; its call statement flows through
        the expression parser (PyParseStatement's fallthrough), so accept
        proc calls here in NilPy mode only. Pascal keeps rejecting proc-in-expr. }
      { NOTHING NILPY BELONGS BELOW THIS LINE, and the reason is structural
        rather than stylistic. ParseFactorCore opens with an unconditional
        `if PyExprMode then begin PyParseFactorCore; Exit; end` — so every
        statement in this routine runs with PyExprMode FALSE, i.e. while parsing
        a PASCAL unit (defs.inc:4199, pasparser_proc.inc:4697), whoever pulled
        it in. NilPy source is parsed by pyparser.inc's own copy of this
        argument loop, which is where its star/keyword handling lives and works.

        Nine `isNilPy` arms used to sit here — star-unpack in four spellings, the
        keyword-overload retarget, the bare generator expression, the dict-keyword
        builder and both iterable fixups. They were reached ~3000 times per NilPy
        compile and did nothing, because `isNilPy` asks "did this compilation
        start from a .npy file" and the question here is "is THIS unit Python".
        Removed 2026-08-31 with the measurement in
        bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag.

        If you are about to add an `isNilPy` arm here: it cannot fire. Add it to
        PyParseFactorCore instead.

        AND THIS NOTE IS FAR MORE GENERAL THAN THE NINE ARMS IT WAS WRITTEN
        ABOUT — measured 2026-09-04, so the population is stated rather than
        implied. A reachability probe wrapping the CONDITION of every
        `Nil Python:` guard in this file (not its body: they are all `... not
        loaded` guards, which can only speak when the RTL is broken), run over
        all 830 `.npy` programs in test/:

          28 sites INSIDE this procedure   -> 0 fires
           3 sites OUTSIDE it              -> 3 fires (all of them)

        Position relative to the dispatch above is a PERFECT discriminator, and
        it is the only thing that is. The corpus is not the reason for the zero:
        246 of those programs use `len(`, 820 use `int(`, 25 `open(`, 22
        `float(`, 17 `round(`, 12 `getattr`, 9 `exec(` — every construct these
        arms serve, richly represented, and not one reached the Pascal copy.
        Controls that had to fire before the zero meant anything: the Pascal arm
        of this dispatch 44471 times and the NilPy arm 115 times on one .npy.

        17 of the 28 are dead STRUCTURALLY, not merely unobserved: they gate on
        NilPyUserCode, which symtab.inc:25 defines as
        `isNilPy and ((CurrentUnitIdx < 0) or PyExprMode)`. Below this dispatch
        PyExprMode is false by construction, so the guard reduces to `isNilPy
        and CurrentUnitIdx < 0` — the MAIN PROGRAM of a NilPy compile parsed as
        non-Python, which a .npy cannot produce, because its main program is
        Python and therefore left at the Exit above. The other 11 gate on plain
        `isNilPy`, which IS true while the Pascal RTL is parsed, so those are
        reachable in principle and their zero is empirical only. Two different
        claims; do not let the first carry the second.

        Do NOT read duplication as the test. All 28 dead ones happen to be
        duplicated verbatim in pyparser.inc, but so is a LIVE one
        (`TPyList.extend`, in ParseExpr), so "this string exists on both arms"
        does not mean "this copy is dead" — only position does. That inference
        looked perfect at 291 of 830 programs and dissolved at 830.
        bug-p-nilpy-diagnostics-exist-on-both-arms-of-the-parsefactorcore-carve-out }
      else if (procIdx >= 0) and (Procs[procIdx].IsFunc or isNilPy) and (Tokens[TokPos].Kind = tkLParen) then
      begin
        Next;
        Expect(tkLParen, '(');
        argsHead := -1;
        lastArg := -1;
        nArgs := 0;
        while CurTok.Kind <> tkRParen do
        begin
          { `dict(a=1, b=2)` / `dict(**e)` — in Python the keyword NAMES are dict
            KEYS, not parameter names, so this is not keyword binding at all:
            the run becomes the one dict argument `dict()` already takes.
            The whole run up to `)` is consumed here. }
          node := PyKwDictArgNode(procIdx);
          if node >= 0 then
          begin
            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := node;
            ASTIVal[argSeq] := 0;
            if argsHead = -1 then argsHead := argSeq else ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
            Inc(nArgs);
            Break;
          end;
          { NilPy `key=expr`: consumes the name, yields paramIndex+1 (0 = positional) }
          kwIdx := PyKwArgIndex(procIdx, 0);
          if kwIdx > 0 then slotIdx := kwIdx - 1 else slotIdx := nArgs;
          node := TryParseBracketArgForSlot(procIdx, slotIdx);
          if node >= 0 then CurASTNode := node
          else
          begin
            node := TryDelphiBareProcArg;
            if node >= 0 then CurASTNode := node else ParseArgExpr;
          end;
          SetLitCheckArg(CurASTNode, procIdx, slotIdx);
          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := CurASTNode;
          ASTIVal[argSeq] := kwIdx;
          if argsHead = -1 then
            argsHead := argSeq
          else
            ASTRight[lastArg] := argSeq;
          lastArg := argSeq;
          Inc(nArgs);
          if ProcFlexColumn[procIdx] then ParseFlexColumnTail(lastArg, nArgs);
          if CurTok.Kind = tkComma then
            Next
          else if CurTok.Kind <> tkRParen then
            Error('expected comma or close parenthesis');
        end;
        Expect(tkRParen, ')');
        PyPackStarArgs(procIdx, argsHead, lastArg, nArgs, 0);
        PyBindKwArgs(procIdx, argsHead, lastArg, nArgs);

        { a builtin TYPE in a callback slot becomes the address of the routine
          that type performs — BEFORE the types below are read, since they are
          what picks the overload (bug-nilpy-a-builtin-type-as-a-key-callback-
          segfaults) }
        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          argTypes[i] := IntToTypeKind(ASTTk[exprNode]);
          { `@obj.Method` (AN_METHODREF) surfaces as tyPointer in a value context,
            but as a call argument it fills a method-pointer (`of object`, tyRecord)
            parameter — the IR lowering materialises its {Code,Data} pair for a
            tyRecord param. Report it as tyRecord so overload matching binds it to
            the method-pointer param, mirroring the assignment path
            (bug-pascal-methodref-arg-to-named-of-object-param-no-match). }
          { A dyn-array-returning CALL is a dyn-array VALUE, and a dyn-array
            VARIABLE reports its ELEMENT kind here -- an array node carries the
            element type, the array-ness lives on the symbol. The call node
            carries tyPointer (the handle), so `SumI(dy)` and `SumI(MkI)` arrived
            at overload resolution as DIFFERENT types for the same value, and
            only parameters whose element type happens to accept a Pointer (the
            ordinals) matched at all: `array of string`, `array of Boolean` and
            `array of TRec` were "no overload matches: (Pointer)".
            bug-p-a-call-result-is-refused-as-a-const-open-array-argument }
          if ((ASTKind[exprNode] = AN_CALL) or (ASTKind[exprNode] = AN_VIRTUAL_CALL) or
              (ASTKind[exprNode] = AN_INTF_CALL) or (ASTKind[exprNode] = AN_CALL_IND) or
              (ASTKind[exprNode] = AN_DYN_COPY)) and
             (NodeDynDepth(exprNode) >= 1) and (NodeDynBaseTk(exprNode) <> tyUnknown) then
            argTypes[i] := NodeDynBaseTk(exprNode);
          if ASTKind[exprNode] = AN_METHODREF then argTypes[i] := tyRecord;
          currArg := ASTRight[currArg];
        end;

        procIdx := MatchCallDelphiProcAddr(name, qUnit, nArgs, argsHead, argTypes);
        if procIdx < 0 then
        begin
          { Generic dynamic-array Copy(arr[, index [, count]]) intrinsic. Only when
            no Copy function matches (so a string `sysutils.Copy` is never
            shadowed) and the first argument is a dynamic array. Lowered into a
            fresh element-type-aware `array of T` (AN_DYN_COPY). String Copy keeps
            the RTL path.

            nArgs = 1 — FPC's whole-array shorthand — is accepted here as well as
            at the bare-intrinsic site in ParseFactor, and BOTH are needed: which
            path a program takes depends on whether a `Copy` function is in scope
            at all, so fixing only one made `Copy(a)` compile without `uses
            sysutils` and fail with "no overload of Copy matches" with it. The two
            arms even failed with different messages, which is exactly how a
            double case stays half-broken
            (devdocs/dev/normalise-dont-special-case.md). }
          if CaseEqual(name, 'Copy') and (nArgs >= 1) and (nArgs <= 3) and
             (NodeDynDepth(ASTLeft[argsHead]) >= 1) then
          begin
            { Same pair as the arm above, and they must stay in step — this is
              the double case normalise-dont-special-case warns about, and the
              two already drifted apart once. }
            if (ASTKind[ASTLeft[argsHead]] = AN_IDENT) and
               (ASTIVal[ASTLeft[argsHead]] >= 0) and
               (SymElemDynDepth[ASTIVal[ASTLeft[argsHead]]] > 0) then
              Error('Copy: dynamic-array element type not yet supported for '
                    + 'dynamic-array Copy (feature-dynarray-copy-nested-element-type)');
            node := AllocNode(AN_DYN_COPY);
            ASTLeft[node] := ASTLeft[argsHead];                 { source array }
            if nArgs >= 2 then
              exprNode := ASTLeft[ASTRight[argsHead]]           { index }
            else
            begin
              exprNode := AllocNode(AN_INT_LIT);
              ASTIVal[exprNode] := 0; ASTTk[exprNode] := Ord(tyInteger);
            end;
            if nArgs = 3 then
              addrNode := ASTLeft[ASTRight[ASTRight[argsHead]]] { count }
            else
            begin
              addrNode := AllocNode(AN_INT_LIT);
              ASTIVal[addrNode] := 2147483647; ASTTk[addrNode] := Ord(tyInteger);
            end;
            argSeq := AllocNode(AN_ARG); ASTLeft[argSeq] := exprNode;
            lastArg := AllocNode(AN_ARG); ASTLeft[lastArg] := addrNode;
            ASTRight[argSeq] := lastArg;
            ASTRight[node] := argSeq;
            { Pointer-typed: dyn-array handle result, stored full-width on assign. }
            ASTTk[node] := Ord(tyPointer);
            CurASTNode := node;
            Exit;
          end;
          { Concat(s1, ..., sn) / Concat(arr1, ..., arrn): the twin of the
            bare-intrinsic arm in ParseFactor, and needed for the same reason the
            Copy pair above is — which path a program takes depends on whether a
            `Concat` routine is in scope AT ALL, and `lib/rtl/sysutils` declares a
            two-argument one. So `uses sysutils` withdrew the variadic intrinsic
            outright and turned a working `Concat('a','b','c')` into `no overload
            of Concat matches these arguments`; the dynamic-array form went the
            same way, since sysutils' Concat has the right ARITY for two arrays
            and the wrong types.

            Reached only when no overload matched, so a real
            `sysutils.Concat(s1, s2)` is never shadowed — shadowing a builtin
            with a routine of the same name is right, withdrawing it for calls
            that routine cannot accept is not, and FPC's `uses sysutils` changes
            nothing here.
            Guarded on the FIRST argument being something Concat can actually
            join — a dynamic array or a string/char — exactly as the Copy arm
            above is guarded on a dynamic array. Without it a plainly wrong
            `Concat(rec1, rec2, rec3)` would fold into `rec1 + rec2 + rec3` and
            be reported as a missing `+` overload instead of as the wrong call
            it is.
            compat-pascal-uses-sysutils-withdraws-the-variadic-concat }
          { The gate asks the FIRST argument what kind of Concat this is, so a
            leading element list (`Concat([0], a)`) answered "neither" and the
            call fell through to the no-overload-match error. Ask whether the
            first PAIR is concatenable instead -- same predicate as the operator
            door and the intrinsic fold above. }
          if CaseEqual(name, 'Concat') and (nArgs >= 2) and (ASTRight[argsHead] >= 0) then
            RefuseUntypedElementListConcat(ASTLeft[argsHead], ASTLeft[ASTRight[argsHead]]);
          if CaseEqual(name, 'Concat') and (nArgs >= 1) and
             ((NodeDynDepth(ASTLeft[argsHead]) > 0) or
              ((nArgs >= 2) and (ASTRight[argsHead] >= 0) and
               DynConcatOperandsEligible(ASTLeft[argsHead], ASTLeft[ASTRight[argsHead]])) or
              (IntToTypeKind(ASTTk[ASTLeft[argsHead]]) in
                 [tyString, tyAnsiString, tyShortString, tyFixedString, tyChar])) then
          begin
            node := ASTLeft[argsHead];
            argSeq := ASTRight[argsHead];
            while argSeq <> -1 do
            begin
              if DynConcatOperandsEligible(node, ASTLeft[argSeq]) then
                node := MakeDynConcat(node, ASTLeft[argSeq])
              else
              begin
                exprNode := AllocNode(AN_BINOP);
                ASTIVal[exprNode] := Ord(tkPlus);
                ASTLeft[exprNode] := node;
                ASTRight[exprNode] := ASTLeft[argSeq];
                ASTTk[exprNode] := Ord(tyAnsiString);
                node := exprNode;
              end;
              argSeq := ASTRight[argSeq];
            end;
            CurASTNode := node;
            { one-argument Concat is the identity and never reaches
              MakeDynConcat, so ask the NODE rather than which branch ran }
            if NodeDynDepth(node) > 0 then LastExprTk := tyPointer
            else LastExprTk := tyAnsiString;
            Exit;
          end;
          procIdx := TryFillTrailingDefaults(name, qUnit, nArgs, argsHead, lastArg);
          { Variadic bracket-elision: `f(a, b, c)` where f's last parameter is
            `array of const`. LAST of the fallbacks -- an ordinary overload and
            a defaulted one both win over it, which is how the ticket's "the
            variadic form is a fallback" rule is enforced by placement rather
            than by a rule. TWIN SITE in pasparser_stmt.inc; keep them in step.
            feature-writeln-as-library }
          if procIdx < 0 then
            procIdx := TryElideVariadicBrackets(name, qUnit, nArgs, argsHead, lastArg, argTypes);
          if procIdx < 0 then
          begin
            { RECOVERABLE, and the value half of the statement site's recovery
              (see pasparser_stmt.inc). The caller is mid-EXPRESSION, so an
              empty statement is not available as a stand-in -- it needs a
              VALUE, and the same poison rule applies as for an undefined name:
              an ordinary Integer 0, which every enclosing operator accepts, so
              one bad call does not cascade into a second diagnostic about the
              expression around it. Nothing poisoned can reach codegen; the
              driver halts on ErrCount > 0 before any emission.
              feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
            ErrorRecover('no overload of ' + name + ' matches these arguments' + OverloadReport);
            CurASTNode := AllocNode(AN_INT_LIT);
            ASTIVal[CurASTNode] := 0;
            ASTTk[CurASTNode] := Ord(tyInteger);
            LastExprTk := tyInteger;
            Exit;
          end;
        end;


        isLiftedCall := (procIdx >= 0) and (Procs[procIdx].ParamCount > nArgs) and
                        (ProcParamPtrDepth[procIdx * MAX_PROC_PARAMS + nArgs] = 2);

        if isLiftedCall then
        begin
          liftedVar := AllocVar('', tyPointer);
          identNode := AllocNode(AN_IDENT);
          ASTIVal[identNode] := liftedVar;
          ASTTk[identNode] := Ord(tyPointer);

          addrNode := AllocNode(AN_ADDR);
          ASTLeft[addrNode] := identNode;
          ASTTk[addrNode] := Ord(tyPointer);

          argSeq := AllocNode(AN_ARG);
          ASTLeft[argSeq] := addrNode;

          if argsHead = -1 then
          begin
            argsHead := argSeq;
            lastArg := argSeq;
          end
          else
          begin
            ASTRight[lastArg] := argSeq;
            lastArg := argSeq;
          end;

          argTypes[nArgs] := tyPointer;
          Inc(nArgs);

          while nArgs < Procs[procIdx].ParamCount do
          begin
            addrNode := AllocNode(AN_INT_LIT);
            ASTIVal[addrNode] := 0;
            ASTTk[addrNode] := Ord(tyPointer);

            argSeq := AllocNode(AN_ARG);
            ASTLeft[argSeq] := addrNode;

            if argsHead = -1 then
            begin
              argsHead := argSeq;
              lastArg := argSeq;
            end
            else
            begin
              ASTRight[lastArg] := argSeq;
              lastArg := argSeq;
            end;

            argTypes[nArgs] := tyPointer;
            Inc(nArgs);
          end;
        end;

        { A one-character literal argument is BOTH a Char and a one-character
          string; the PARAMETER decides. One resolver, pasparser_name.inc —
          this loop and its byte-identical twin in the overloaded-call path
          (pasparser_stmt.inc) each used to open-code the frozen-string half
          and neither knew about a PChar parameter.
          bug-single-char-literal-as-pchar-argument-segfaults }
        CoerceCharLitArgs(procIdx, argsHead);

        currArg := argsHead;
        for i := 0 to nArgs - 1 do
        begin
          exprNode := ASTLeft[currArg];
          if Procs[procIdx].Params[i].IsRef or Procs[procIdx].Params[i].IsArray then
          begin
            { AN_SLICE is here because A SLICE OF AN LVALUE IS AN LVALUE: `a[3..6]`
              names the caller's own elements, and passing it to `var u: array of
              Char` must let the callee write them. That is the entire reason the
              slice is a node and not a `Copy` desugar -- a copy is a perfectly
              good VALUE and discards exactly this. Refusing it here would have
              left the const direction working and the var direction refused,
              which is the half-a-feature shape this file keeps recording. }
            if not ((ASTKind[exprNode] = AN_IDENT) or (ASTKind[exprNode] = AN_INDEX) or (ASTKind[exprNode] = AN_FIELD) or
                    (ASTKind[exprNode] = AN_DEREF) or IsVarArgLvalueCast(exprNode) or
                    (ASTKind[exprNode] = AN_METHODREF) or
                    (ASTKind[exprNode] = AN_VARREC_ARRAY) or (ASTKind[exprNode] = AN_ARRAY_CTOR) or
                    (ASTKind[exprNode] = AN_SLICE)) then
            begin
              { ONE rule, not a list of type kinds: only an explicit `var`/`out`
                needs a true lvalue. See ByRefArgNeedsLvalue for why the
                five-armed disjunction that used to live here was the wrong
                question. bug-a-a-non-lvalue-is-refused-as-an-interface-argument }
              if ByRefArgNeedsLvalue(procIdx, i) then
                Error('by-reference argument must be a variable');
            end;
          end;
          currArg := ASTRight[currArg];
        end;

        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        ASTLeft[node] := argsHead;
        if isLiftedCall then
        begin
          ASTLiftedVar[node] := liftedVar;
          ASTTk[node] := Ord(tyPointer);
        end;

        ApplyCallResultPtrSuffix(node, procIdx);  { f(...)^ / ^.field / [i] }
        if isLiftedCall then
        begin
          CurASTNode := node;
          LastExprTk := tyPointer;
        end;
        Exit;
      end
      else if (idx < 0) and (procIdx >= 0) and Procs[procIdx].IsFunc and
              ((Procs[procIdx].ParamCount = 0) or
               ((Procs[procIdx].ParamCount > 0) and
                ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + 0])) then
      begin
        { Bare paramless function called by name in an expression. Guarded on
          `idx < 0`: a variable in scope with the same name (PXX is
          case-insensitive, so a local `clauseCount` collides with a function
          `ClauseCount`) must SHADOW the function — fall through to the var read
          below. Without this guard the local read was silently compiled as a
          call to the function (bug-impl-prescan-codegen-regression: the real
          defect was here, name resolution, not slot/offset allocation). }
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        { ...or ALL-DEFAULTED, which is paramless at the call site. The EXPRESSION
          arm of the same defect the statement path had (`a := F` alongside `P;`),
          found by testing the sibling rather than the ticket's own repro: the
          ticket reported statement position only, and fixing that one left
          `a := F` still reporting "undefined variable (F)". Defaults are trailing
          in Pascal, so parameter 0 having one means they all do.
          bug-p-parenless-call-to-an-all-defaulted-routine-is-an-undefined-variable. }
        if Procs[procIdx].ParamCount > 0 then
        begin
          argSeq := -1;
          FillDefaultArgs(procIdx, 0, node, argSeq);
        end;
        { …and record that the arguments are all compiler-filled, so Delphi
          mode's @-optional retry can tell this from a written `F(2)`. }
        ASTCallParenless[node] := True;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        ApplyCallResultPtrSuffix(node, procIdx);  { f()^ / ^.field / [i] }
        Exit;
      end
      else
      begin
        { Implicit Self.method dispatch for methods called bare inside a class body in expression context }
        node := -1;
        if (idx < 0) and (procIdx < 0) and (CurSelfClass >= REC_UCLASS_BASE) then
        begin
          { …on the CLASS HELPER that owns this body when it declares the name,
            otherwise on the extended class — SelfMemberCi. }
          ci := SelfMemberCi(name);
          mmi := FindUMethOverloadAhead(ci, name, CountCallArgsAhead);
          if mmi >= 0 then
          begin
            EnforceMethVis(mmi, name);
            mpi := UMthProc_[mmi];
            Next; { consume method name }
            smSelfIdx := Procs[CurProc].Params[0].SymIdx;
            smselfArg := AllocNode(AN_ARG);
            valNode := AllocNode(AN_IDENT);
            ASTIVal[valNode] := smSelfIdx;
            ASTTk[valNode] := Ord(tyClass);
            ASTLeft[smselfArg] := valNode;
            if UMthVirSlot[mmi] >= 0 then
            begin
              mcallNode := AllocNode(AN_VIRTUAL_CALL);
              ASTRight[mcallNode] := UMthVirSlot[mmi];
            end
            else
              mcallNode := AllocNode(AN_CALL);
            ASTIVal[mcallNode] := mpi;
            if (mpi >= 0) then
              ASTTk[mcallNode] := Ord(Procs[mpi].RetType)
            else
              ASTTk[mcallNode] := Ord(tyInteger);
            ASTLeft[mcallNode] := smselfArg;
            mlastArg := smselfArg;
            if CurTok.Kind = tkLParen then
            begin
              Next;
              i := 1;
              { `d.update(**e)` reaches THIS loop (the plain class-method one,
                which has no keyword handling at all and met the `*` with
                "expected expression"), while `d.update(a=1)` reaches the
                arity-driven loop above — the same construct through two paths,
                so both ask the one builder. }
              if PyKwDictArgsHere(mpi) then
              begin
                argSeq := AllocNode(AN_ARG);
                ASTLeft[argSeq] := PyBuildKeywordDictHere;
                ASTIVal[argSeq] := 0;
                ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                Inc(i);
              end;
              while CurTok.Kind <> tkRParen do
              begin
                ParseExpr;
                argSeq := AllocNode(AN_ARG);
                ASTLeft[argSeq] := CurASTNode;
                ASTRight[mlastArg] := argSeq;
                mlastArg := argSeq;
                Inc(i);
                if CurTok.Kind = tkComma then Next;
              end;
              Expect(tkRParen, ')');
            end;
            { trailing `.field` / `[i]` on a class/record method result }
            if (mpi >= 0) and (CurTok.Kind in [tkDot, tkLBrack]) and
               ((Procs[mpi].RetType = tyClass) or (Procs[mpi].RetType = tyRecord)) then
              mcallNode := ParseClassRecordSelectors(mcallNode, ProcRetRecId[mpi], tk);
            CurASTNode := mcallNode;
            node := mcallNode;
          end;
        end;
        if node = -1 then
        begin
          Next;
          CurASTNode := ParseLValueAST(idx, TokPos - 2);
          LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
        end;
      end;
    end;
    else Error('expected expression');
  end;
  { Postfix `lv++` / `lv--` on the parsed factor (must be an lvalue): yields the
    OLD value, bumps after. tkPlusPlus/tkMinusMinus are new tokens never produced
    for existing source, so this is inert for non-C code (self-host byte-identical). }
  while CurTok.Kind in [tkPlusPlus, tkMinusMinus] do
  begin
    node := AllocNode(AN_INCDEC);
    ASTLeft[node] := CurASTNode;
    if CurTok.Kind = tkPlusPlus then ASTIVal[node] := 1 else ASTIVal[node] := -1;
    ASTSOffset[node] := 1;   { postfix → old value }
    ASTTk[node] := ASTTk[CurASTNode];
    CurASTNode := node; LastExprTk := IntToTypeKind(ASTTk[node]);
    Next;
  end;
end;

{ NilPy str-method suffix, applied to EVERY factor however ParseFactorCore
  returned. The postfix `.member` path inside the core catches ident and field
  bases (they run through ParseLValueAST); a string LITERAL and a CALL RESULT
  are not lvalues and arrive here with CurTok still on the '.'. Both routes
  share pyparser's PyParseStrMethod.

  Factor level is the ONLY correct level: a method binds tighter than `+`.
  Applying this after the additive layer made `"a" + "b".upper()` parse as
  `("a" + "b").upper()` and silently print AB where CPython prints aB. }
function ProcIsConstructor(pi: Integer): Boolean;
{ Does proc index pi belong to a method declared `constructor`? A constructor
  is registered with IsFunc=False — its declaration keyword is neither
  `function` nor `procedure` — so the no-result check below has to let it
  through: `v := TFoo.Create` is the ordinary way to build an object and IS a
  value. A `destructor` shares that IsFunc=False and is deliberately NOT
  exempted: `x := v.Destroy` is not a value in any dialect.

  A linear scan, deliberately: it only ever runs for a call whose proc is not a
  function, which is a constructor call or the bug being caught, never a hot
  path. UMthIsCtor is per-METHOD; the reverse map from a proc index does not
  exist and is not worth adding for this. }
var m: Integer;
begin
  ProcIsConstructor := False;
  for m := 0 to UMthCount - 1 do
    if UMthProc_[m] = pi then
    begin
      if UMthIsCtor[m] then ProcIsConstructor := True;
      Exit;
    end;
end;

procedure ParseFactor;
var smNameTok, smBase, sdTok, tpObjNode, tpBlobNode, tpCallNode: Integer;
    sdName: AnsiString;
    smName: AnsiString;      { the intercepted int-method name at this suffix }
    smTk, tpTk: TTypeKind;   { receiver kind for a suffix on a fresh construction }
    ppBase, ppExp, ppPi, ppArgSeq, ppArgSeq2: Integer;   { `**` power operator }
    enStart, enArg0, enArg1: Integer;   { enumerate(xs, start=N) }
    zipB, zipC, zipD: Integer;   { zip(a, b[, c[, d]]) — -1 for an absent stream }
    pySuffixTokPos: Integer;   { token cursor at the top of the suffix cluster }
    pyFactorStop: Boolean;   { a NilPy factor form that must NOT run the suffix cluster }
begin
  { The NilPy forms that used to open this routine — `type(x).__name__`,
    `super().m()`, `lambda`, and the factor chain ParseFactorCore was the `else`
    of — now live in pyparser.inc. What is left here is the DISPATCH, and it
    names nothing frontend-specific.

    Two answers, not one, because the original had two: a prefix form finishes
    ParseFactor outright, while a factor form usually falls through into the
    Python suffix cluster below. `stop` carries the two zip arms that did not.
    refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops }
  if FrontendFactorPrefix then Exit;
  if not FrontendFactorForm(pyFactorStop) then
    ParseFactorCore
  else if pyFactorStop then
    Exit;
  { PASCAL type-helper suffix on a factor that is a VALUE, not an lvalue: a
    string LITERAL (`'xy'.ToUpper`), a bare CALL RESULT (`F.Twice`,
    `Copy(s,1,1).Twice`). Those never run through ParseLValueAST, so they
    arrive here with CurTok still on the '.' — the same reason the NilPy
    str-method loops below sit at this level, and for the same reason FACTOR
    level is the only correct one: a method binds tighter than `+`, so
    `'a' + 'b'.Twice` must be `'a' + ('b'.Twice)`.

    A loop, so `F.Twice.Twice` chains. TypeHelperOnValue declines and consumes
    nothing when the member is not a helper method, which leaves every other
    '.' shape on the path it already took.
    feature-p-delphi-string-helpers }
  while (not PyExprMode) and (CurTok.Kind = tkDot) and (CurASTNode >= 0) and
        (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) do
  begin
    smTk := IntToTypeKind(ASTTk[CurASTNode]);
    smBase := TypeHelperOnValue(CurASTNode, smTk);
    if smBase < 0 then Break;
    CurASTNode := smBase;
    LastExprTk := smTk;
  end;
  { --- the Python SUFFIX cluster -------------------------------------------
    Nine loops follow, each claiming one (suffix token, receiver shape) pair:
    `.method()` on a str base, on a call result, on a class expression, on a
    variant; `[i]`; a dynamic CALL through a variant; the `__call__` protocol.
    They are written as a SEQUENCE, so without this outer loop each one gets
    exactly one turn and a suffix is only reachable in the ORDER the loops
    happen to appear. `g(3).show()` needs the dynamic-call loop (last) and then
    the call-result method loop (third) — backwards through the sequence — so it
    was a parse error, while `o = g(3); o.show()` worked
    (bug-nilpy-a-method-call-on-a-callable-values-result-is-refused).

    Python's grammar has no such ordering: a primary takes `.attr`, `[i]` and
    `(args)` suffixes in ANY sequence, any number of times. So the cluster
    re-runs until a pass consumes nothing, which makes it order-independent
    without touching the nine loops individually. The right shape is ONE
    dispatcher over the suffix tokens rather than nine loops — nine mechanisms
    for one concept is well past the two-is-a-smell line — but that is a rewrite
    of a hot region, and this makes the composition correct meanwhile.

    Termination is on TOKEN PROGRESS, not on the node changing: a loop that
    rewrites the node without consuming input would otherwise spin forever. }
  repeat
    pySuffixTokPos := TokPos;
  { `<int>.to_bytes(n, "little", signed=s)` / `<int>.bit_length()`, the other
    half of the pair. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        PyIsIntMethodName(LowerCase(GetTokenStr(TokPos))) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        PyIsIntMethodBaseTk(IntToTypeKind(ASTTk[CurASTNode]),
                            LowerCase(GetTokenStr(TokPos))) do
  begin
    smBase := CurASTNode;
    smName := LowerCase(GetTokenStr(TokPos));
    Next; Next;                 { '.' and the name; CurTok = '(' }
    CurASTNode := PyParseIntMethod(smBase, smName);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { the float half of the same pair — see PyIsFloatMethodName }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        PyIsFloatMethodName(LowerCase(GetTokenStr(TokPos))) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        PyIsFloatMethodBaseTk(IntToTypeKind(ASTTk[CurASTNode]),
                              LowerCase(GetTokenStr(TokPos))) do
  begin
    smBase := CurASTNode;
    smName := LowerCase(GetTokenStr(TokPos));
    Next; Next;                 { '.' and the name; CurTok = '(' }
    CurASTNode := PyParseFloatMethod(smBase, smName,
                     PyIsIntBaseTk(IntToTypeKind(ASTTk[smBase])));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        PyIsStrBaseTk(IntToTypeKind(ASTTk[CurASTNode])) do
  begin
    Next;                       { consume '.'; CurTok = the method name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name; CurTok = '(' }
    CurASTNode := PyParseStrMethod(CurASTNode, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { A method on a CALL RESULT whose declared type is a scalar — `get(a, b,
    c).split("x")`. An unannotated def's result is inferred, and an expression
    the inferrer cannot type comes back tyInteger while the VALUE at run time
    is whatever Python made it (the same call prints its string correctly).
    The string loop above needs a string-typed base, so this shape did not
    parse at all. Routed to runtime dispatch, which is what decides a variant's
    method everywhere else; a receiver that really is a number still fails
    there, by name. Restricted to a CALL base so nothing else changes.

    AN_TERNARY is admitted for the SECOND link of such a chain: the
    runtime-dispatched method this loop builds comes back as a ternary (the
    `pyvar_is_strtag(recv) ? str-method : class-method` fan PyParseVariantMethod
    assembles), not as an AN_CALL, so `open(p).read().strip().upper()` had a
    receiver no loop in this cluster claimed and reported `unexpected token` at
    the second name — while `.strip()` alone parsed. Latent until a name was
    declared by BOTH a class and the str table (which is program-dependent: it
    fires the moment any class in the program declares `strip`/`upper`), so
    adding the Python method set to TPyBytes made it universal. A user's own
    `(a if c else b).upper()` lands here too, which is the same rule Python
    has — a primary takes a suffix whatever produced it.
    bug-nilpy-a-chained-method-on-a-runtime-dispatched-result-is-refused }
  { AN_VIRTUAL_CALL alongside AN_CALL for the reason spelled out at the bare-
    ATTRIBUTE loop below: a call is two node kinds, and a method on a class that
    participates in a hierarchy is built as the virtual one. Both loops had
    drifted to knowing only AN_CALL while the subscript guard further down
    already tested both, so `P(7).mk().mk().a` and `P(7).mk().txt().upper()`
    stopped at the SECOND link — one subclass anywhere in the file was enough.
    bug-n-an-attribute-off-a-call-returning-a-class-value-does-not-parse }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        ((ASTKind[CurASTNode] = AN_CALL) or
         (ASTKind[CurASTNode] = AN_VIRTUAL_CALL) or
         (ASTKind[CurASTNode] = AN_TERNARY)) and
        not (IntToTypeKind(ASTTk[CurASTNode]) in [tyClass, tyRecord]) do
  begin
    Next;                       { consume '.'; CurTok = the method name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name; CurTok = '(' }
    CurASTNode := PyParseVariantMethod(CurASTNode, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { A METHOD call on a class-typed expression that is not an ident — a fresh
    construction, `Cls().m()`. ParseFactorCore does this for an ident receiver
    and the ctor intercept exits before it, so the call was a parse error
    (bug-nilpy-method-call-on-fresh-construction). Looped, so chains compose. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind = tkLParen) and
        (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
        (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) do
  begin
    smBase := CurASTNode;
    Next;                       { consume '.'; CurTok = the method name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name; CurTok = '(' }
    CurASTNode := PyParseClassMethodCall(smBase,
                    ResolveNodeRec(smBase) - REC_UCLASS_BASE, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { …and a PROPERTY or FIELD read on that fresh construction, which carries no
    parentheses: `Path(self.file_path).name`. The loop above needs a '(' after
    the member, so the no-argument form — the one pathlib's name/stem/suffix
    are written with — still had nowhere to go and reported "expected newline
    after statement". Read through the ordinary class-selector machinery, the
    same as for an ident receiver. }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind <> tkLParen) and
        (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
        (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) do
  begin
    smBase := CurASTNode;
    smTk := IntToTypeKind(ASTTk[smBase]);
    CurASTNode := ParseClassRecordSelectors(smBase, ResolveNodeRec(smBase), smTk);
    LastExprTk := smTk;
  end;
  { …and a bare ATTRIBUTE on a receiver the frontend cannot type as a class:
    `mk(3).v`, `g(3).v` — a call RESULT, where there is no symbol to key on. The
    class-selector loop just above needs a statically known class; the method
    loops all need a '(' after the name. So a bare attribute on a call result
    was claimed by nobody and reported `unexpected token`, while
    `o = mk(3); o.v` worked — the same asymmetry the '.method()' and '[i]'
    halves of this family already had.

    Routed to the dynamic attribute read, which is what an unknown receiver
    gets everywhere else. That was only half a fix until pylib's getter learned
    to fall back to the class's DECLARED fields (PyDeclaredAttrGet): before
    that it consulted the setattr side-store alone and answered a false
    AttributeError for a field that plainly exists, which is why this ticket
    was filed rather than the parse gap papered over.
    bug-nilpy-a-bare-attribute-on-a-call-result-is-refused

    AN_TERNARY for the same reason as the '.method()' loop above — a
    runtime-dispatched result is a ternary, so `x.split(",").foo` needs it too.

    AN_VIRTUAL_CALL because a call is one of TWO node kinds, and this loop knew
    only one. A method reached on a class that participates in a hierarchy is
    dispatched through the VMT and built as AN_VIRTUAL_CALL rather than AN_CALL
    — so the identical program compiled or did not depending on whether the
    receiver's class had a SUBCLASS anywhere in the file:

        class P:
            def __init__(self, a): self.a = a
            def mk(self):
                cls = P
                return cls(self.a)      # a classref value call -> variant
        class Q(P):                     # <-- delete these two lines and it compiles
            pass
        print(P(7).mk().a)              # pascal26: unexpected token

    An unrelated class declaring its own `mk` does NOT trigger it, which is what
    rules out the overload-set explanation the ticket opened with: it is
    inheritance, not name collision. `P(self.a)` — a STATIC construction — is
    unaffected because it types as tyClass and the class-selector loop above
    claims it; only a call whose result is a variant reaches this loop at all.

    The diagnostic named neither the subclass nor the class-valued return, so it
    read as a typo at the field name. A factory method plus a subclass is the
    reason to write a factory method in the first place.
    bug-n-an-attribute-off-a-call-returning-a-class-value-does-not-parse }
  while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) and
        (Tokens[TokPos + 1].Kind <> tkLParen) and
        ((ASTKind[CurASTNode] = AN_CALL) or
         (ASTKind[CurASTNode] = AN_VIRTUAL_CALL) or
         (ASTKind[CurASTNode] = AN_TERNARY)) and
        not (IntToTypeKind(ASTTk[CurASTNode]) in [tyClass, tyRecord]) do
  begin
    smBase := CurASTNode;
    Next;                       { consume '.'; CurTok = the attribute name }
    smNameTok := TokPos - 1;
    Next;                       { consume the name }
    CurASTNode := PyMakeDynAttrGet(smBase, GetTokenStr(smNameTok));
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { Same asymmetry for the SUBSCRIPT suffix: `s[i]` on an ident goes through
    ParseLValueAST, but a string literal and a call RESULT are not lvalues, so
    `"abc"[1]` and `"a b".split(" ")[1]` never consumed the '[' and were parse
    errors (bug-nilpy-subscript-on-literal). Reaching here at all means nobody
    else claimed the bracket. Looped, and with the str-method suffix re-applied
    inside, so `"abc"[1].upper()` and longer chains keep composing. }
  while PyExprMode and (CurTok.Kind = tkLBrack) and
        (PySubscriptableSuffix(CurASTNode) or PyIsSliceBase(CurASTNode)) do
  begin
    smBase := CurASTNode;
    Next;                       { consume '[' }
    { A SLICE is a subscript whose index is followed by ':' — and `b[:n]` has
      no low bound at all, so the colon can also be the very first token. }
    if CurTok.Kind = tkColon then
      CurASTNode := PyParseSliceTail(smBase, -1)
    else
    begin
      PyParseBoolExpr;
      if CurTok.Kind = tkColon then
        CurASTNode := PyParseSliceTail(smBase, CurASTNode)
      else
      begin
        Expect(tkRBrack, ']');
        CurASTNode := PyMakeSuffixIndex(smBase, CurASTNode);
      end;
    end;
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
          (Tokens[TokPos].Kind = tkIdent) and
          (Tokens[TokPos + 1].Kind = tkLParen) and
          PyIsStrBaseTk(IntToTypeKind(ASTTk[CurASTNode])) do
    begin
      Next;
      smNameTok := TokPos - 1;
      Next;
      CurASTNode := PyParseStrMethod(CurASTNode, GetTokenStr(smNameTok));
      LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    end;
    { A subscript of a CONTAINER yields a VARIANT, not a str — a list holds
      variants — so the str-method loop above never fired for `make()[0].upper()`
      and the '.' was left for whoever came next: "unexpected token". Routed to
      the runtime-dispatching variant method path, which is what an ident
      receiver of the same shape already gets. }
    while PyExprMode and (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
          (Tokens[TokPos].Kind = tkIdent) and
          (Tokens[TokPos + 1].Kind = tkLParen) and
          (IntToTypeKind(ASTTk[CurASTNode]) = tyVariant) do
    begin
      Next;
      smNameTok := TokPos - 1;
      Next;
      CurASTNode := PyParseVariantMethod(CurASTNode, GetTokenStr(smNameTok));
      LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
    end;
  end;
  { A value followed by '(' is a DYNAMIC call through whatever it holds —
    `ns["__body__"]()`, the function exec() built. Nothing else claimed the '(',
    so a call is the only reading: Python has no juxtaposition operator, so
    there is no other thing `x(y)` can mean. Looped so a returned callable can
    be called again.

    The test USED to be `= tyVariant`, and a non-variant factor therefore fell
    out of the loop leaving the '(' for nobody — the argument list was SILENTLY
    DISCARDED and the expression evaluated to the callee. `x = (add)(4, 5)`
    answered a raw code address instead of 9 and `(3 + 4)(1)` answered 7, while
    the identical call through a variant-typed name worked
    (bug-nilpy-a-parenthesised-callee-drops-its-arguments). Silently dropping
    half an expression is the worst available reading of a '(' — even "not
    callable" is better, because it is CPython's answer and it is loud.

    Widening is only SAFE now: pyvar_callv<n> takes `const cb: Variant`, so the
    ordinary argument coercion boxes a non-variant callee, and until callables
    had their own variant tag a boxed code address was indistinguishable from a
    boxed integer — this loop would have started routing `(3 + 4)(1)` to an
    indirect jump to address 7 rather than to a TypeError. With VT_CALLABLE the
    guard tells them apart, so a real callable dispatches and everything else
    raises (feature-nilpy-a-callable-value-needs-its-own-variant-tag).

    A user-class INSTANCE is excluded because the loop below claims it: that is
    the `__call__` protocol, which needs the receiver, not a boxed handle. A
    pylib CONTAINER (tyClass, but below REC_UCLASS_BASE) is NOT excluded — it
    belongs here, where `(1, 2)(3)` becomes CPython's TypeError. }
  while PyExprMode and (CurTok.Kind = tkLParen) and (CurASTNode >= 0) and
        not ((IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
             (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE)) do
  begin
    CurASTNode := PyMakeDynCall(CurASTNode);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  { A CLASS INSTANCE followed by '(' -- Python's callable-object protocol,
    `a(10)` where `a`'s class defines `__call__`. Loops so a `__call__`
    that itself returns another callable instance composes.
    feature-nilpy-dunder-call-protocol }
  while PyExprMode and (CurTok.Kind = tkLParen) and
        (IntToTypeKind(ASTTk[CurASTNode]) = tyClass) and
        (ResolveNodeRec(CurASTNode) >= REC_UCLASS_BASE) do
  begin
    CurASTNode := PyMakeCallDunder(CurASTNode);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;
  until (not PyExprMode) or (TokPos = pySuffixTokPos);
  { --- end of the suffix cluster ------------------------------------------- }
  { `**` -- Python's power operator: right-associative, and binding TIGHTER
    than unary minus (`-2 ** 2` is `-(2**2)` = -4, not `(-2)**2`). Recognized
    here, at the very end of ParseFactor, rather than in ParseTerm alongside
    `*`/`/`: a unary-minus operand recurses into THIS SAME ParseFactor (see
    ParseFactorCore's tkMinus case), so checking for `**` here means the
    unary minus wraps the WHOLE power expression, and the exponent's own
    recursive ParseFactor call gives right-associativity
    (`2**3**2` = `2**(3**2)` = 512) for free -- no separate precedence
    plumbing needed. Lexed as two adjacent tkStar tokens; the NilPy lexer has
    no dedicated `**` token (the same shape `**kwargs` already relies on, in
    the unrelated parameter-list grammar).
    feature-nilpy-power-operator-and-divmod }
  if PyExprMode and (CurTok.Kind = tkStar) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkStar) then
  begin
    Next; Next;                { the two '*' tokens }
    ppBase := CurASTNode;
    ParseFactor;
    ppExp := CurASTNode;
    { the lowering itself (dunders, then pypow_v) is PyMakePow — shared with
      `**=`, which must produce the identical node }
    CurASTNode := PyMakePow(ppBase, ppExp);
    LastExprTk := IntToTypeKind(ASTTk[CurASTNode]);
  end;

  { A PROCEDURE used as a VALUE. ParseFactor only ever runs in expression
    position, so a call node reaching here whose proc has no result is the
    error FPC reports as "Can't read or write variables of this type".

    Without this the call COMPILED and yielded whatever happened to be in the
    return register: `n := f.DoIt` assigned stack junk and `f.DoArg(3) + 1`
    evaluated to 4 — the argument read back out
    (bug-p-procedure-method-in-an-expression-yields-garbage). Silent, and it
    also absorbed signature drift: it is what hid pxx's `WaitFor: procedure`
    from a probe written to compare against FPC's `WaitFor: LongWord`.

    METHOD calls are the shape that got here; a bare procedure name was already
    rejected (as "undefined variable"), which is why only methods produced
    garbage. Constructors are exempt — see ProcIsConstructor.

    Pascal only. C has its own void-value diagnostics and NilPy's `None`-typed
    calls are values by design, so neither goes through this.

    StmtCallDepth: the `(`-led STATEMENT branch of ParseStatementAST runs
    the expression parser over what is really a statement — `(o as T).M;` — so
    the check stands down inside it. Sub-expressions of such a statement are
    unchecked as a result; that shape is rare and the alternative is a false
    error on every `(o as T).M;`. }
  if (not isNilPy) and (not PyExprMode) and (not CProgramMode) and
     (StmtCallDepth = 0) and (CurASTNode >= 0) and
     ((ASTKind[CurASTNode] = AN_CALL) or (ASTKind[CurASTNode] = AN_VIRTUAL_CALL)) and
     (ASTIVal[CurASTNode] >= 0) and (ASTIVal[CurASTNode] < ProcCount) and
     (not Procs[ASTIVal[CurASTNode]].IsFunc) and
     (not ProcIsConstructor(ASTIVal[CurASTNode])) then
    Error('"' + Procs[ASTIVal[CurASTNode]].Name +
          '" is a procedure and has no result to use in an expression');
end;

function FloatBinopResultTk(ltk, rtk: TTypeKind): TTypeKind;
{ Result type of a float-producing binop. On double-native targets every float
  op widens to Double (Single is storage-only). On ESP (xtensa/riscv) Single is
  first-class: single op single -> single, only an explicit Double operand pulls
  the result to soft-Double. Ordinal operands count as "not Double" so int/int
  under '/' yields the native depth (Single on ESP). }
begin
  if (ltk = tyExtended) or (rtk = tyExtended) then
    FloatBinopResultTk := tyExtended
  else if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
  begin
    if (ltk = tyDouble) or (rtk = tyDouble) then
      FloatBinopResultTk := tyDouble
    else
      FloatBinopResultTk := tySingle;
  end
  else
    FloatBinopResultTk := tyDouble;
end;

{ Rewrite a PROMO operand of a float-typed binop into an explicit
  PXXPromoToDouble call; anything else is handed back untouched.

  A float binop lowers its operands as machine values, and a promo rvalue IS
  the slot address (decide-promoint-rvalue-representation) — so `(i + 1) + 2.5`
  added 2.5 to a POINTER and printed 5553978.5, and `(i + 1) / 2` was just as
  wrong. Converting HERE, as an ordinary AN_CALL, is the same lever hex/bin/oct
  and str() use: the promo->Pointer argument arm in IRLowerCallArg carries the
  slot address to promocore without any hand-built IR.

  PXXPromoToDouble reads the true value off the limbs rather than narrowing
  first, so a bignum operand converts to a large float, not to an approximation
  of its low 64 bits. }
function PromoWidenToDouble(n: Integer): Integer;
var pwProc, pwArg, pwCall: Integer;
begin
  PromoWidenToDouble := n;
  if n < 0 then Exit;
  if not TypeIsPromoInt(IntToTypeKind(ASTTk[n])) then Exit;
  pwProc := FindProc('PXXPromoToDouble');
  if pwProc < 0 then Exit;        { promocore not loaded — leave as-is }
  pwArg := AllocNode(AN_ARG);
  ASTLeft[pwArg] := n;
  ASTRight[pwArg] := -1;
  pwCall := AllocNode(AN_CALL);
  ASTIVal[pwCall] := pwProc;
  ASTTk[pwCall] := Ord(tyDouble);
  ASTLeft[pwCall] := pwArg;
  PromoWidenToDouble := pwCall;
end;

{ Rewrite a PROMO operand of a machine-integer TYPECAST into an explicit
  PXXPromoToInt64 call; anything else is handed back untouched.

  `Integer(n)` / `Int64(n)` are value-PUNS: the result's bit pattern is the
  operand's. For a promotable int the operand's bit pattern is its SLOT ADDRESS
  (decide-promoint-rvalue-representation), so `n := 12; writeln(Int64(n))`
  printed a pointer. Demoting first makes the pun operate on a real machine
  integer, which leaves every existing cast rule (width truncation, sign) doing
  exactly what it did before.

  CHECKED (PXXPromoToInt64, RunError 215) rather than the wrapping demote: a
  Pascal cast of a value that does not fit is the case a programmer wants told
  about, and silently delivering `value mod 2^64` is the defect the whole type
  exists to remove. NilPy's own int-annotated narrowing is separate and stays
  wrapping — it goes through IRLowerCallArg and the assignment path, not here. }
function PromoDemoteToInt64(n: Integer): Integer;
var pdProc, pdArg, pdCall: Integer;
begin
  PromoDemoteToInt64 := n;
  if n < 0 then Exit;
  if not TypeIsPromoInt(IntToTypeKind(ASTTk[n])) then Exit;
  pdProc := FindProc('PXXPromoToInt64');
  if pdProc < 0 then Exit;        { promocore not loaded — leave as-is }
  pdArg := AllocNode(AN_ARG);
  ASTLeft[pdArg] := n;
  ASTRight[pdArg] := -1;
  pdCall := AllocNode(AN_CALL);
  ASTIVal[pdCall] := pdProc;
  ASTTk[pdCall] := Ord(tyInt64);
  ASTLeft[pdCall] := pdArg;
  PromoDemoteToInt64 := pdCall;
end;

{ A typecast of a VARIANT operand, rewritten as the variant CONVERSION.

  FPC and Delphi define `Int64(v)` / `Double(v)` / `Char(v)` as exactly the
  conversion `i := v` performs; pxx lowered them as ordinary hard casts of the
  16-byte variant RECORD, so the value read was the TAG word (`Int64(v)` on
  v=9 answered 1) and the float kinds reinterpreted those bytes as an address
  and segfaulted. The assignment form was already right, which is the
  double-case shape normalise-dont-special-case.md warns about — so this
  NORMALISES the cast onto the assignment: store into a hidden temp of the
  cast's type (ir.inc's AN_ASSIGN arm emits the VariantTo*/pyvar_to_* unbox
  there) and yield the temp. One mechanism, every spelling, all six backends,
  no new IR op. Reuses the generic assign-then-yield node AN_STR_FROM_CHAR
  (Left = the store side-effect, Right = the temp read), same as the float and
  String() casts below.

  Returns -1 for "not mine" — a non-variant operand, or a target no variant
  payload can stand in for (pointer/record/set/class). That set is
  IRVariantUnboxKind's, ASKED rather than mirrored; it lives in symtab.inc, not
  ir.inc, because NilPy's *args forwarder needs the same answer. `Pointer(v)`
  stays a reinterpret — the address of the record is the only sensible reading
  of it — and that falls out of the predicate rather than being subtracted from
  it here, which is what the old wording claimed and no copy ever did.
  bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting }
function VariantCastToTemp(n: Integer; target: TTypeKind): Integer;
var vcTmp, vcAsg, vcLhs, vcRd, vcNd: Integer;
begin
  VariantCastToTemp := -1;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyVariant then Exit;
  { ASK the predicate that owns this set rather than mirroring it. The list
    here was CHARACTER-FOR-CHARACTER identical to IRVariantUnboxKind's, and the
    comment above still said "minus tyPointer" although neither copy has ever
    listed tyPointer -- a difference that was documented and did not exist.
    Both copies were missing tyWideChar for the same reason and neither could
    tell you the other was wrong. }
  if not IRVariantUnboxKind(target) then Exit;
  vcTmp := AllocVar('', target);
  vcNd  := AllocNode(AN_STR_FROM_CHAR);
  vcLhs := AllocNode(AN_IDENT);
  ASTIVal[vcLhs] := vcTmp; ASTTk[vcLhs] := Ord(Syms[vcTmp].TypeKind);
  vcAsg := AllocNode(AN_ASSIGN);
  ASTLeft[vcAsg] := vcLhs; ASTRight[vcAsg] := n;
  ASTTk[vcAsg] := Ord(Syms[vcTmp].TypeKind);
  ASTLeft[vcNd] := vcAsg;
  vcRd := AllocNode(AN_IDENT);
  ASTIVal[vcRd] := vcTmp; ASTTk[vcRd] := Ord(Syms[vcTmp].TypeKind);
  ASTRight[vcNd] := vcRd;
  ASTTk[vcNd] := Ord(Syms[vcTmp].TypeKind);
  VariantCastToTemp := vcNd;
end;

function TryScalarNamedCast(castTk: TTypeKind; semId: Integer): Boolean;
{ THE SHARED CONSTRUCTION HALF OF A NAMED-TYPE SCALAR CAST — the arms that must
  mean the same thing however the type NAME was recognised.

  `SomeName(expr)` reaches a cast through several recognition rules in
  ParseFactorCore, and this ticket exists because they build the node separately
  and drift: SEVEN defects on 2026-09-06 alone, every one of them an arm one
  door had and its sibling did not (a float target reinterpreting, an enum alias
  losing its identity, a variant alias reading the tag word, an
  `operator Explicit` answering at one door only, and the enum fix being half a
  fix under {$PACKENUM 1}). Each is a case this routine could not have had.

  IT ANSWERS FOR EXACTLY THE TARGETS WHOSE CONTINUATION IS DOOR-INDEPENDENT, and
  declines the rest by returning False so each caller keeps its own arms. It
  declines tyPointer (the builtin door turns `Pointer(n)` on a promotable int
  into AN_ADDR and then may take a `^`; the alias door routes a pointer alias
  through the suffix walk with AliasElemTk) and it declines the string kinds
  (the builtin door hands `AnsiString(r)[2]` to the selector walk; the alias
  door has its own indexed-string-alias path). Those two are the real
  differences between the doors; everything above them was duplication.

  THE ORDER IS THE BUILTIN DOOR'S AND IT IS NOT ARBITRARY. Explicit before the
  ordinal and float arms, because an overload naming this exact target is the
  more specific answer for a record or class operand and the arms below would
  reinterpret its bytes. The two arms whose relative order looks load-bearing
  and is not: PromoDemoteToInt64 is a no-op on a record or class, so Explicit
  may sit on either side of it, and VariantCastToTemp declines a non-variant
  operand, so it may sit on either side of Explicit. Measured before merging
  rather than reasoned about: a variant narrowed to ShortInt answers 44 through
  both doors and under fpc 3.2.2, which is the row where the two orders would
  have differed.

  refactor-p-five-dispatch-sites-for-one-named-type-cast }
var scNode, scTmp: Integer;
begin
  TryScalarNamedCast := False;
  if castTk = tyPointer then Exit;
  { `Variant(x)` is the BOXING conversion, not a retag of an integer AS a
    variant record. See VariantBoxToTemp -- unconditional, including an operand
    that is ALREADY a variant, which is the one shape an earlier exemption
    preserved and had no reason to. }
  if castTk = tyVariant then
  begin
    scTmp := VariantBoxToTemp(CurASTNode);
    if scTmp >= 0 then CurASTNode := scTmp;
    LastExprTk := tyVariant;
    TryScalarNamedCast := True;
    Exit;
  end;
  scTmp := TryExplicitOpCast(CurASTNode, castTk);
  if scTmp >= 0 then
  begin
    CurASTNode := scTmp;
    LastExprTk := castTk;
    TryScalarNamedCast := True;
    Exit;
  end;
  if TypeIsOrdinal(castTk) then
  begin
    { demote a promotable operand BEFORE narrowing, or the cast truncates the
      SLOT ADDRESS -- see PromoDemoteToInt64. }
    CurASTNode := PromoDemoteToInt64(CurASTNode);
    { A VARIANT operand converts rather than reinterpreting its record — and
      the conversion ALREADY YIELDS A TEMP OF THE TARGET TYPE, so it returns
      here rather than falling through to be wrapped in an AN_PTR_CAST as well.

      That was the one behavioural difference between the two doors' copies of
      this block, and the BYTE-IDENTITY control is what found it: the builtin
      door exited here, the alias door wrapped, and 14 of 15 corpus files came
      out byte-identical across the merge while
      test_a_variant_cast_to_widechar_converts_like_char changed. Its OUTPUT was
      unaffected and so was every other test's — the extra node is a no-op cast
      from a kind to itself — so no value assertion anywhere could have seen it,
      and the merge would have silently added a redundant node to every
      variant-to-ordinal cast in the tree. Exiting is both the smaller code and
      the behaviour the door with the most traffic already had. }
    scTmp := VariantCastToTemp(CurASTNode, castTk);
    if scTmp >= 0 then
    begin
      CurASTNode := scTmp;
      LastExprTk := castTk;
      TryScalarNamedCast := True;
      Exit;
    end;
    scNode := AllocNode(AN_PTR_CAST);
    ASTLeft[scNode] := CurASTNode;
    ASTIVal[scNode] := -1;   { the width-truncating value cast }
    ASTTk[scNode]   := Ord(castTk);
    { the SEMANTIC IDENTITY comes in as a PARAMETER, from whichever table the
      caller asked -- FindEnumType or BuiltinScalarSemId at the builtin door,
      the alias table's AliasSemId column at the alias door -- and is never
      re-derived from the kind here. A guard on the layout kind is a bet the
      layout kind never narrows, and {$PACKENUM 1} is that bet losing.
      It was `enumId` and tested `>= 0`; that is now one FAMILY of identity
      rather than the whole domain, so the test is against SEM_NONE. Without
      this, `LongBool(True)` produced a bare tyInteger and `l and LongBool(x)`
      went bitwise -- the cast is exactly where a sized boolean's meaning is
      spelled out loud and it was the one place that dropped it. }
    if semId <> SEM_NONE then ASTSemId[scNode] := semId;
    CurASTNode := scNode;
    LastExprTk := castTk;
    TryScalarNamedCast := True;
    Exit;
  end;
  if TypeIsFloat(castTk) then
  begin
    scTmp := FloatCastToTemp(CurASTNode, castTk);
    if scTmp >= 0 then CurASTNode := scTmp;
    LastExprTk := castTk;
    TryScalarNamedCast := True;
    Exit;
  end;
end;

function TryExplicitOpCast(n: Integer; castTk: TTypeKind): Integer;
{ `operator Explicit(a: TFoo): Integer` — a value cast of a RECORD or CLASS
  operand that has a matching Explicit overload is the conversion CALL, not a
  reinterpret. Answers -1 for every other operand and whenever no overload
  returns the cast's type, so a caller can ask unconditionally.

  SHARED BECAUSE THE ALIAS DOOR NEVER HAD IT. `type TInt = Integer; TInt(f)`
  answered 4 -- the record's raw first field -- where `Integer(f)` answered 40
  and fpc 3.2.2 answers 40 for both. Same shape as FloatCastToTemp beside it:
  the builtin-name door grew the arm, the user-alias door three hundred lines
  above kept falling through to AN_PTR_CAST, and nothing connects the two but a
  reader noticing.
  refactor-p-five-dispatch-sites-for-one-named-type-cast }
var eoSci, eoArg, eoNd: Integer;
begin
  TryExplicitOpCast := -1;
  if n < 0 then Exit;
  if (IntToTypeKind(ASTTk[n]) <> tyRecord) and
     (IntToTypeKind(ASTTk[n]) <> tyClass) then Exit;
  eoSci := FindOpOverload(OPK_EXPLICIT, ASTTk[n], ResolveNodeRec(n));
  if eoSci < 0 then Exit;
  if Procs[eoSci].RetType <> castTk then Exit;
  eoArg := AllocNode(AN_ARG);
  ASTLeft[eoArg] := n;
  eoNd := AllocNode(AN_CALL);
  ASTIVal[eoNd] := eoSci;
  ASTTk[eoNd]   := Ord(castTk);
  ASTLeft[eoNd] := eoArg;
  TryExplicitOpCast := eoNd;
end;

function FloatCastToTemp(n: Integer; castTk: TTypeKind): Integer;
{ A cast to a FLOAT type is a real CONVERSION -- int->float, or double->single
  narrowing -- and never a reinterpret of the operand's bits. Model it exactly
  as the `Double(x)` KEYWORD arm already does: a hidden temp of the CAST's type,
  the ordinary store into it (which coerces), and the temp read back as the
  value.

  SHARED BECAUSE IT WAS WRITTEN ONCE AND THE SIBLING DOOR NEVER GOT IT. The
  user-alias door grew this arm when `type TaD = double; TaD(3.75)` was found
  answering 4615626668101337088; the BUILTIN-NAME door three hundred lines below
  kept falling through to the AN_PTR_CAST reinterpret, so `Currency(i)`,
  `TDateTime(i)` and `ValReal(i)` handed on the integer's bit pattern as a
  double while `type TCur = Currency; TCur(i)` converted. Those three are the
  whole reachable set: every other float spelling (`Double`, `Single`,
  `Extended`, `Real`) is a LEXER KEYWORD and is answered by the keyword arm,
  which has always converted. The names that reach the builtin-NAME door are
  precisely the ones FPC's System unit spells as identifiers.

  refactor-p-five-dispatch-sites-for-one-named-type-cast }
var fcTmp, fcAsg, fcLhs, fcRd, fcNd: Integer;
begin
  FloatCastToTemp := -1;
  if n < 0 then Exit;
  fcTmp := AllocVar('', castTk);
  fcNd  := AllocNode(AN_STR_FROM_CHAR);
  fcLhs := AllocNode(AN_IDENT);                { store LHS = the temp }
  ASTIVal[fcLhs] := fcTmp; ASTTk[fcLhs] := Ord(Syms[fcTmp].TypeKind);
  fcAsg := AllocNode(AN_ASSIGN);
  ASTLeft[fcAsg] := fcLhs; ASTRight[fcAsg] := n;
  ASTTk[fcAsg] := Ord(Syms[fcTmp].TypeKind);
  ASTLeft[fcNd] := fcAsg;
  fcRd := AllocNode(AN_IDENT);                 { yielded value = the temp }
  ASTIVal[fcRd] := fcTmp; ASTTk[fcRd] := Ord(Syms[fcTmp].TypeKind);
  ASTRight[fcNd] := fcRd;
  ASTTk[fcNd] := Ord(Syms[fcTmp].TypeKind);
  FloatCastToTemp := fcNd;
end;

function VariantBoxToTemp(n: Integer): Integer;
{ THE MIRROR OF VariantCastToTemp, and the reason `Variant(x)` can be a boxing
  conversion AND still have a type.

  `Variant(x)` yielded the OPERAND node so the assignment would box it, which
  fixed the segfault (b6815e5b8) and made the expression's static type the
  operand's. SizeOf reads the NODE's tk (`szExprTk := IntToTypeKind(ASTTk[..])`,
  not LastExprTk), so `SizeOf(Variant(x))` answered a scalar width -- 8 against
  `SizeOf(vov)`'s 16 for `vov: OleVariant`. Stamping tyVariant on the operand
  node is not available: IRLowerBoxOperand takes the SOURCE kind from that same
  field, so the store would copy 16 bytes out of a 4-byte integer, which is the
  pun the fix removed.

  A TEMP separates the two readings. The assignment's RHS is still the operand,
  carrying its own scalar kind, so the box is the one `v := x` already performs;
  the expression handed back is a READ of a tyVariant temp, so every consumer
  that asks what this expression IS gets the right answer.

  I recorded the lost static type as CLAUDE.md's implementation latitude in
  b6815e5b8's own comment. It is not: that clause is about an intermediate's
  type differing from FPC's, and the row that failed
  (test_builtin_type_names_cast_and_declare) never mentions FPC -- it asserts
  that OUR OleVariant and OUR Variant(x) agree with EACH OTHER. A relation
  between two of our own answers is the assertion shape CLAUDE.md prefers, and
  no parity clause reaches it. A caveat gets believed rather than re-tested,
  which is exactly what happened here for a day.
  regression-test-core-test-builtin-type-names-cast-and-declare }
var vbTmp, vbAsg, vbLhs, vbRd, vbNd: Integer;
begin
  VariantBoxToTemp := -1;
  if n < 0 then Exit;
  vbTmp := AllocVar('', tyVariant);
  vbNd  := AllocNode(AN_STR_FROM_CHAR);
  vbLhs := AllocNode(AN_IDENT);
  ASTIVal[vbLhs] := vbTmp; ASTTk[vbLhs] := Ord(tyVariant);
  vbAsg := AllocNode(AN_ASSIGN);
  ASTLeft[vbAsg] := vbLhs; ASTRight[vbAsg] := n;
  ASTTk[vbAsg] := Ord(tyVariant);
  ASTLeft[vbNd] := vbAsg;
  vbRd := AllocNode(AN_IDENT);
  ASTIVal[vbRd] := vbTmp; ASTTk[vbRd] := Ord(tyVariant);
  ASTRight[vbNd] := vbRd;
  ASTTk[vbNd] := Ord(tyVariant);
  VariantBoxToTemp := vbNd;
end;

{ Apply PromoWidenToDouble to both operands of a float-typed binop, in place. }
{ Pascal widens a `div`/`mod` pair to a type that holds BOTH operands, and an
  integer LITERAL's range is its own value, not a declared type -- so `q div 10`
  is an unsigned division (10 fits QWord) while `q div n` with `n: Int64` is a
  signed one. The signedness rule below reads only the two operand TYPES, so a
  positive literal divisor carried tyInteger into it and would have flipped every
  unsigned division by a constant to signed, turning any QWord above 2^63
  negative. Retype the LITERAL instead of teaching the rule about literals: one
  "unsigned iff both operands are" rule then serves the result type and all six
  backends, with no second path to keep in step (normalise-dont-special-case). }
{ A DECIMAL literal above Int64max is an UNSIGNED value, and this is where that
  is written down.

  The lexer keeps the digit text of any literal it could not fit in an Int64
  (ASTSLen > 0), because the wrapped 64-bit reading is still the right QWord
  value and only the text says which. But the node is TYPED tyInt64, so every
  operation that reads signedness reads it wrong: `18446744073709551615 div 5`
  answered 0 against FPC's 3689348814741910323, and
  `9223372036854775808 > 1` answered FALSE.

  ASTIVal alone cannot tell this literal from a genuinely negative one -- both
  are negative Int64s -- which is why the guard in
  NormalizeUnsignedLiteralOperand below is correct as written and had to be
  answered HERE instead, from the fact the lexer already recorded.

  Not done at the literal's CREATION, where it would look tidier: IsWideIntLit
  keys on tyInt64, and every promotable-int path (the digit text reaching
  PXXPromoFromStr, the variant boxing, the Write arm) asks it. Retyping every
  wide literal up front would make that predicate silently stop matching --
  those sites do not error, they take the other branch -- so the retag happens
  only on the two arms that actually read signedness.

  tyPromoInt64 is excluded for the same reason: that is NilPy's arbitrary-
  precision typing of the same literal and it owns its own arithmetic.
  Past UInt64 there is no correct 64-bit reading at all, so those keep tyInt64
  and reach ir.inc's out-of-range diagnostic at the point of use.
  bug-p-qword-div-by-a-literal-above-2-63-is-signed }
procedure NormalizeWideUnsignedLiteral(lit: Integer);
begin
  if CProgramMode then Exit;
  if lit < 0 then Exit;
  if not IsWideIntLit(lit) then Exit;
  if ASTTk[lit] = Ord(tyPromoInt64) then Exit;
  if DecDigitsExceed(GetTokenStrFromRaw(ASTSOffset[lit], ASTSLen[lit]),
                     '18446744073709551615') then Exit;
  ASTTk[lit] := Ord(tyUInt64);
end;

procedure NormalizeUnsignedLiteralOperand(typed, lit: Integer);
begin
  if CProgramMode then Exit;
  if (typed < 0) or (lit < 0) then Exit;
  if ASTKind[lit] <> AN_INT_LIT then Exit;
  if ASTIVal[lit] < 0 then Exit;
  if not TypeIsOrdinal(IntToTypeKind(ASTTk[typed])) then Exit;
  if TypeSigned(IntToTypeKind(ASTTk[typed])) then Exit;
  ASTTk[lit] := Ord(tyUInt64);
end;

procedure PromoWidenBinopOperands(node: Integer);
begin
  if node < 0 then Exit;
  ASTLeft[node] := PromoWidenToDouble(ASTLeft[node]);
  ASTRight[node] := PromoWidenToDouble(ASTRight[node]);
end;

{ The two arithmetic refusals that had no home outside IR lowering.

  Both already exist in `ir.inc`'s AN_BINOP chain and STAY there as the backstop
  for nodes nobody parsed. But a diagnostic that lives ONLY in lowering is one
  that vanishes the moment anything EARLIER in the file was reported: error
  recovery stops lowering at the first recovered diagnostic (`if ErrCount > 0
  then Exit` in CompileAST), so a file with two mistakes reported the first and
  wrote a binary. A dialect rule belongs in the dialect's parser -- the same
  move `93c0ee76d` made for the record-ORDERING rule, whose refusal sits at the
  relational level for exactly this reason.

  Called from the TAIL of ParseTerm's and ParseSimpleExpr's loops, after the
  node's type is settled and after every arm that REWRITES the node has already
  `continue`d away: `a + b` over two dynamic arrays is a concatenation
  (MakeDynConcat) and an overloaded operator is a call, and neither reaches
  here. So the two conditions below are the leftovers, and they match the
  lowering arms' conditions term for term.

  RECOVERS rather than halting -- the node left behind is an ordinary typed
  AN_BINOP, so the parse carries on and the file's later mistakes are reported
  too, which is the whole point of moving the check here.

  NilPy is excluded: its records reach lowering through arms of their own, and
  its backstop is unchanged. C is excluded for the reason the lowering arm gives
  -- struct pointer/array arithmetic tags operands tyRecord legitimately.
  bug-a-error-recovery-silences-every-lowering-only-diagnostic }
procedure CheckArithOperandsHaveAMeaning(op: TTokenKind; left, right: Integer);
begin
  if CProgramMode or PyExprMode then Exit;
  if not ((op = tkPlus) or (op = tkMinus) or (op = tkStar) or (op = tkSlash) or
          (op = tkDiv) or (op = tkMod)) then Exit;
  { A dynamic array on ONE side (two is concatenation and never arrives here).
    Adding the two handles produced a wild pointer and a runtime SIGSEGV. }
  if ((NodeDynDepth(left) > 0) or (NodeDynDepth(right) > 0)) and
     ((op = tkPlus) or (op = tkMinus) or (op = tkStar) or (op = tkDiv)) then
  begin
    ErrorRecover('arithmetic operator not supported for dynamic arrays '
                 + '(only `a + b` over two dynamic arrays is defined, as concatenation)');
    Exit;
  end;
  { A record operand with no registered overload: this used to add the records'
    first qwords and produce garbage, or a wild pointer copy, at run time. }
  if ((IntToTypeKind(ASTTk[left]) = tyRecord) or
      (IntToTypeKind(ASTTk[right]) = tyRecord)) and
     (FindOpOverload2(Ord(op), ASTTk[left], ResolveNodeRec(left),
                      ASTTk[right], ResolveNodeRec(right)) < 0) then
    ErrorRecover('no operator overload found for record operands '
                 + '(operator not declared, or its unit not compiled?)'
                 + ' — PXXDBG=a.opovl prints the lookup and every candidate');
end;

procedure ParseTerm;
var op: TTokenKind; left, right, node, opSOffset, opSLen, opci: Integer;
    ixTry: Integer;   { a repeat count coerced through __index__ }
    blv: Boolean;                 { a constant left operand of `and` }
    shiftLitLeft: Boolean;        { shift over an operand with no DECLARED width }
    shiftPromoS, shiftPromoU: TTypeKind;
begin
  ParseFactor;
  while (((CurTok.Kind in [tkStar, tkSlash, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr'))) and
        not (PyExprMode and (CurTok.Kind in [tkAnd, tkShl]))) or
        { Python's `@` (matrix multiply) binds at THIS precedence. Only in
          NilPy: `@` is Pascal's address-of prefix, which ParseFactor owns.
          Decorator-`@` never reaches here — it is consumed at statement
          start, before any expression is parsed
          (bug-nilpy-matmul-operator-does-not-parse). }
        (PyExprMode and (CurTok.Kind = tkAt)) do
  begin
    opSOffset := Tokens[TokPos - 1].SOffset;
    opSLen := Tokens[TokPos - 1].SLen;
    op := CurTok.Kind; Next;
    { The loop condition above admits tkIdent only when its text is 'shr', so
      here tkIdent IS `shr` and nothing else. Rename it on the way in, once, so
      the AN_BINOP — and the IR_BINOP lowered from it — carries the IR's own
      name for the operator instead of the lexer's accident. Every consumer
      downstream reads tkShrLogical; none has to know how Pascal spells it.
      NOT tkShr, which is the ARITHMETIC shift-right (C's `>>` on a signed
      operand): collapsing the two makes `i shr 1` for i: Integer = -8 emit
      `sar` and answer -4 on every native backend.
      bug-a-shr-reaches-the-ir-spelled-as-tkident }
    if op = tkIdent then op := tkShrLogical;
    left := CurASTNode;
    ParseFactor;
    right := CurASTNode;
    { `and` between two truth values is LOGICAL, and a sized boolean reaching
      it as a bare integer makes it bitwise -- see SemBoolNormalisePair. }
    if op = tkAnd then SemBoolNormalisePair(left, right);
    { A CONSTANT LEFT OPERAND OF `and`, folded HERE because it is LOWERING and
      not an optimisation. Pascal `and`/`or` short-circuit -- this compiler has
      no {$BOOLEVAL} and measured 0 calls for `False and Bump` -- so dropping
      the right operand is the language's own rule rather than a liberty.

      What it costs to skip: the right arm is still EMITTED, so a call in it to
      a declared-but-never-defined external becomes a real reference and the
      binary dies before main with `undefined symbol`. MEASURED on
      `if False and (NeverDefinedP = 0)` at -O0, -O2 AND -O3 -- IROptConstBranch
      cannot rescue it, because the and/or lowering materialises its result in a
      boolean temp and the branch RELOADS it, so the operand feeding the jump is
      a load_sym. The C sibling of this is 88ef1232f; the parser is duplicated
      per language by design, so this is its own fold and not a shared helper.
      feature-a-fold-the-consensus-dead-branch-core-at-every-level }
    if (op = tkAnd) and (ASTTk[right] = Ord(tyBoolean)) and PasBoolLit(left, blv) then
    begin
      if blv then CurASTNode := right else CurASTNode := PasMakeBoolLit(False);
      continue;
    end;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTSOffset[node] := opSOffset; ASTSLen[node] := opSLen;
    { {$Q+} region: * is overflow-checked (feature-pascal-overflow-checks-q-plus) }
    if (op = tkStar) and TokQChecks[TokPos - 1] then ASTQChk[node] := True;
    { `a @ b` — `__matmul__`, then the reflected `__rmatmul__`, then TypeError.
      Never an AN_BINOP: `@` has NO arithmetic meaning in Python at all (no
      builtin type implements it), so falling through to the numeric typing
      would compute on the class handle exactly as the other dunders did before
      they were dispatched. The node allocated above is discarded, like the
      list-repeat and bytes-repeat arms below. }
    if PyExprMode and (op = tkAt) then
    begin
      node := -1;
      if (IntToTypeKind(ASTTk[left]) = tyClass) and
         (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
         (not PyRecIsPylibOwnClass(ResolveNodeRec(left))) then
        node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__matmul__',
                            left, right);
      if node < 0 then node := PyReflectedDunder(PyReflName(op), left, right);
      if node < 0 then node := PyMakeUnsupportedOperand;
      CurASTNode := node;
      continue;
    end;
    { A sequence REPEAT COUNT may be an object with `__index__` — `[0] * C(3)`,
      `"ab" * C(2)`. The repeat tests below only recognise an ordinal, so the
      object fell past them into the arithmetic/dunder path and raised
      TypeError. Coerce ONLY when doing so actually turns the pair into a
      repeat: `C(3) * 5` with no `__mul__` must stay a TypeError, not silently
      become 15 (bug-nilpy-unary-numeric-dunders-return-raw-handle). }
    if PyExprMode and (op = tkStar) then
    begin
      ixTry := PyIndexCoerce(right);
      if (ixTry <> right) and
         (PyListRepeatPair(left, ixTry) or PyBytesRepeatPair(left, ixTry) or
          PyIsStrBaseTk(IntToTypeKind(ASTTk[left]))) then
      begin right := ixTry; ASTRight[node] := right; end
      else
      begin
        ixTry := PyIndexCoerce(left);
        if (ixTry <> left) and
           (PyListRepeatPair(ixTry, right) or PyBytesRepeatPair(ixTry, right) or
            PyIsStrBaseTk(IntToTypeKind(ASTTk[right]))) then
        begin left := ixTry; ASTLeft[node] := left; end;
      end;
    end;
    opci := -1;
    { EITHER operand: `1.5 + cx` is as much an overloaded operator as `cx + 1.5`,
      and FPC accepts both. The lookup key stays the LEFT operand and the right
      one is matched against the entry's second parameter, so a scalar-left
      entry is only ever reachable from an expression that has an aggregate in
      it — which is what keeps `3 * 5` plain arithmetic with an
      `(Integer, TCx)` operator in scope.
      feature-a-operator-table-keyed-on-both-operands }
    if TkIsRecordOrClass(ASTTk[left]) or TkIsRecordOrClass(ASTTk[right]) then
      opci := FindOpOverload2(Ord(op), ASTTk[left], ResolveNodeRec(left),
                              ASTTk[right], ResolveNodeRec(right));
    if opci >= 0 then
      { Overloaded operator on a record/class operand returns its result type. }
      ASTTk[node] := Ord(Procs[opci].RetType)
    { `xs * n` on a LIST repeats it, and `bytes([ch]) * u` on BYTES. Built as
      direct calls rather than tagged like the string case, because the RESULT's
      class identity has to survive into a local: an AN_BINOP carries no record
      id, so an inferred local would hold a tyClass with no identity and len()
      would mis-pick its overload (feature-nilpy-list-repeat).

      BEFORE the variant arm below, not after. A repeat is decided by the
      SEQUENCE operand, which is statically known here — one side IS a list or
      bytes node — while the COUNT may be anything, including a variant. Sitting
      after the variant arm, the whole pair was tagged tyVariant the moment the
      count had no static type and the repeat builders were never reached: the
      statement stayed an arithmetic multiply and coerced the SEQUENCE to a
      number, so uforth's `bytes([ch]) * u` inside `def w_fill(vm2)` raised
      "expected a number, got object" — pointing at a coercion rather than at a
      missed repeat. `[7] * u` survived only because the runtime variant
      multiply happens to handle a list on the LEFT, which is why `u * [7]`
      failed while `[7] * u` passed.
      bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic }
    { complex `*` and `/`, either operand order, mixed with int/float. Before
      every arm below: complex is a pylib class, so the dunder arms exclude it
      and it would otherwise reach the generic arithmetic and compute on the
      object HANDLE. }
    else if PyExprMode and (op in [tkStar, tkSlash]) and
            (PyNodeIsComplex(left) or PyNodeIsComplex(right)) then
    begin
      node := PyMakeComplexBinop(op, left, right);
      if node < 0 then node := PyMakeUnsupportedOperand;
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkStar) and PyListRepeatPair(left, right) then
    begin
      node := PyMakeListRepeat(left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkStar) and PyBytesRepeatPair(left, right) then
    begin
      node := PyMakeBytesRepeat(left, right);
      CurASTNode := node;
      continue;
    end
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    { Python's `s * n` REPEATS the text (either operand order), and the IR
      lowers it to pystr_repeat — but the node had been tagged with the
      arithmetic result here, so a local taking its value was typed Integer and
      `len(s)` found no overload
      (bug-a-nilpy-str-repeat-local-infers-as-int). Tag it at parse time, where
      the inference reads it. }
    else if PyExprMode and (op = tkStar) and
            (PyIsStrBaseTk(IntToTypeKind(ASTTk[left])) <>
             PyIsStrBaseTk(IntToTypeKind(ASTTk[right]))) then
      ASTTk[node] := Ord(tyAnsiString)
    { `xs * n` on a LIST repeats it. Built as a direct call rather than tagged
      like the string case, because the RESULT's class identity has to survive
      into a local: an AN_BINOP carries no record id, so an inferred local would
      hold a tyClass with no identity and len() would mis-pick its overload
      (feature-nilpy-list-repeat). }
    else if PyExprMode and (op in [tkStar, tkSlash, tkDiv, tkMod]) and (opci < 0) and
            (IntToTypeKind(ASTTk[left]) <> tyClass) and
            (PyReflectedDunder(PyReflName(op), left, right) >= 0) then
    begin
      CurASTNode := PyReflectedDunder(PyReflName(op), left, right);
      continue;
    end
    else if PyExprMode and (op in [tkStar, tkSlash, tkDiv, tkMod]) and (opci < 0) and
            (IntToTypeKind(ASTTk[left]) = tyClass) and
            (ResolveNodeRec(left) >= REC_UCLASS_BASE) then
    begin
      { `Vector(1,2) * 3` — a user class's own `__mul__`/`__truediv__` dunder.
        Neither the list-repeat nor bytes-repeat branch above matched, so a
        bare tyClass LEFT operand is a genuine user object — dispatch to its
        dunder rather than falling through to the arithmetic AN_BINOP built
        above, which silently computed garbage on the class HANDLE as if it
        were a number (bug-nilpy-arithmetic-operator-dunders-not-dispatched,
        same root cause as the +/- fix in ParseSimpleExpr). Only the LEFT
        operand's class is consulted, matching Python's left-operand-first
        dunder lookup — no `__rmul__`/`__rtruediv__` fallback. }
      { `//` and `%` join the same branch: measured, they were NOT dispatched —
        C(7) // C(3) answered 0 and C(7) % C(3) answered 126959237464088, both
        computed on the class HANDLE (feature-nilpy-arithmetic-dunders-full-
        protocol).

        pylib's OWN rows reach here only when no earlier branch claimed them —
        list-repeat and bytes-repeat already handled the `*` forms — so for them
        the operator has no Python meaning and the answer is the runtime
        TypeError below, NOT the dunder lookup and NOT a fall-through. Excluding
        them from the branch entirely was measured WRONG: `[1,2] / 3` then fell
        past this arm into the generic arithmetic and silently computed on the
        list HANDLE, where it had previously produced a loud (if compile-time)
        error. Skip the lookup, keep the raise. }
      if PyRecIsPylibOwnClass(ResolveNodeRec(left)) then node := -1
      else if op = tkStar then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__mul__', left, right)
      else if op = tkDiv then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__floordiv__', left, right)
      else if op = tkMod then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__mod__', left, right)
      else node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__truediv__', left, right);
      if node < 0 then
        node := PyMakeUnsupportedOperand;   { runtime TypeError, not a build abort }
      CurASTNode := node;
      continue;
    end
    { Python's `"%s=%d" % args` — string INTERPOLATION, not arithmetic. With no
      case for it the node kept the numeric `mod` typing and the lowering applied
      integer mod to a string handle: `"%.2f" % 3.14159` printed 0.0 and
      `"%s" % s` printed a pointer, compiling clean either way
      (bug-nilpy-percent-string-format-garbage). Recognised on the LEFT operand
      being a str, which is what Python dispatches on too. }
    else if PyExprMode and (op = tkMod) and
            PyIsStrBaseTk(IntToTypeKind(ASTTk[left])) then
    begin
      node := PyMakePercentFormat(left, right);
      CurASTNode := node;
      continue;
    end
    else if (op = tkAnd) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if op = tkSlash then
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));  { '/' produces native-depth float }
      PromoWidenBinopOperands(node);
    end
    else if PyExprMode and ((op = tkDiv) or (op = tkMod)) and
            (TypeIsFloat(IntToTypeKind(ASTTk[left])) or
             TypeIsFloat(IntToTypeKind(ASTTk[right]))) then
      { Python's `//` and `%` yield a FLOAT as soon as either operand is one.
        Typing from the LEFT operand alone made `3 % 2.5` an integer-typed
        node, and ir.inc's retype to tyDouble (when it routes to pyfloormod_f)
        came too late for anything that had already bound an overload from the
        node's type: `str(3 % 2.5)` picked the Int64 str() and printed
        4602678819172646912, the double's BIT PATTERN, while a bare
        `print(3 % 2.5)` was right because print reads the type after lowering
        (bug-nilpy-str-of-mixed-mod-prints-double-bits).

        PyExprMode-only: Pascal's own `div`/`mod` are integer spellings, so the
        Pascal dialect and the self-host binary are untouched. }
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]),
                                            IntToTypeKind(ASTTk[right])));
      PromoWidenBinopOperands(node);
    end
    else if (op = tkDiv) or (op = tkMod) then
    begin
      { the wide literal answers for ITSELF first -- with two literal operands
        there is no unsigned-typed operand for the pair rule to key on, and
        `9223372036854775808 div 2` divided signed }
      NormalizeWideUnsignedLiteral(left);
      NormalizeWideUnsignedLiteral(right);
      NormalizeUnsignedLiteralOperand(left, right);
      NormalizeUnsignedLiteralOperand(right, left);
      ASTTk[node] := Ord(TypeDivideResultPair(IntToTypeKind(ASTTk[left]),
                                              IntToTypeKind(ASTTk[right])));
    end
    else if (op = tkShrLogical) or (op = tkShl) then
    begin
      { A SHIFT happens at NATIVE width, and its result is not truncated back to
        the operand's declared width — `1 shl 40` is 2^40, not 0, and
        `-a shr 1` (a: Integer) is the 64-bit logical shift.
        decide-shift-operator-promotion-width (user, 2026-08-10): "pxx
        truncating to 32-bit is wrong"; FPC's own answers are inconsistent here
        (it widens the operand for `shr` but masks the count for `shl`, and its
        constant folder contradicts its runtime path), so copying them is left
        to --strict-fpc. Widening never loses information; truncating does, and
        truncating is how `1 shl 40` became 0.
        C keeps its own semantics: CProgramMode's `<<` wraps at the declared
        width, which is what the standard says, so the promotion is Pascal-only.
        bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc }
      { …and under --strict-fpc, promote ONLY a compile-time constant operand.
        That is FPC's own asymmetry, faithfully: its constant FOLDER answers
        `1 shl 40` = 2^40 and `-8 shr 1` = 9223372036854775804 at full width,
        while the same expressions over a VARIABLE wrap at the operand's
        declared width. Strict mode is documented as copying FPC's bugs, and
        this is one of them.
        bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths }
      { …and a NEGATED operand of any shape, not just a negated literal, because
        FPC's unary minus yields a 64-bit value: measured, `SizeOf(-x)` is 8 for
        EVERY integer operand type (Byte, ShortInt, Word, SmallInt, Integer,
        Cardinal, Int64) and all seven answer 9223372036854775804 for
        `-x shr 1`. So FPC's operand is already wide and its narrow-shift
        asymmetry never applies to it — reproducing that asymmetry over `-a`
        made --strict-fpc the ONE mode that disagreed with FPC on this row,
        while pxx's own default agreed.
        bug-p-strict-fpc-narrows-a-negated-integer-shift-the-default-gets-right }
      { …and a LITERAL left operand promotes to 64 bits on EVERY target, not to
        the target's native width. It has no declared width to preserve, so
        there is nothing for "native" to mean; capping it at native left
        `writeln(1 shl 40)` answering 256 on i386 (x86 masks the count to 5
        bits) and 0 on arm32 — two different wrong answers, neither of them a
        model, and the exact trap the 2026-08-10 ruling was made to remove,
        surviving on the targets that were dismissed with "native there IS 32
        bits". It also disagreed with ConstEval, which folds
        `const K = 1 shl 40` at Int64 on every target, in the SAME program.
        A DECLARED narrow variable still promotes to native and no further:
        that half is the ruling and does not move.
        bug-a-an-untyped-literal-shift-is-target-width-on-32-bit-targets }
      shiftLitLeft := (ASTKind[left] = AN_INT_LIT) or (ASTKind[left] = AN_NEG);
      if shiftLitLeft then
      begin
        shiftPromoS := tyInt64;     shiftPromoU := tyUInt64;
      end
      else
      begin
        shiftPromoS := tyNativeInt; shiftPromoU := tyNativeUInt;
      end;
      if (not CProgramMode) and
         ((not StrictShiftWidth) or shiftLitLeft) and
         TypeIsMachineInt(IntToTypeKind(ASTTk[left])) and
         (TypeSlotSize(IntToTypeKind(ASTTk[left])) < TypeSlotSize(shiftPromoS)) then
      begin
        if TypeSigned(IntToTypeKind(ASTTk[left])) then
          ASTTk[node] := Ord(shiftPromoS)
        else
          ASTTk[node] := Ord(shiftPromoU);
        { Carry the width down onto the LITERAL itself, not just onto the binop
          node. A 64-bit register makes the two indistinguishable, which is why
          x86-64 and aarch64 were right with only the node tagged; the 32-bit
          pair path reads the operand's OWN type to decide how to materialise
          it, so a node tagged tyInt64 over a tyInt32 literal shifted a
          half-built pair and answered 0. The literal has no declared width to
          contradict — giving it the result's width is what "untyped" means —
          and doing it here means no backend has to know. }
        if shiftLitLeft then ASTTk[left] := ASTTk[node];
      end
      else
        ASTTk[node] := ASTTk[left];
    end
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
      PromoWidenBinopOperands(node);
    end
    else if TypeIsPromoInt(IntToTypeKind(ASTTk[left])) or
            TypeIsPromoInt(IntToTypeKind(ASTTk[right])) then
      { Promotable int is infectious — see the twin arm in the other binop
        typing site. Above the ordinal arm because promo is deliberately not
        TypeIsOrdinal. }
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]),
                                              IntToTypeKind(ASTTk[right])))
    else if PyExprMode and PyIntGrowsOp(op) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[left])) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[right])) then
      { NilPy: `*` over two NATIVE ints is still arbitrary precision — see
        PyIntGrowsOp. Below the promo arm (which already covers the mixed
        case) and above the ordinal one, which would type it tyInteger. }
      ASTTk[node] := Ord(tyPromoInt64)
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(TypeArithmeticResult(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])))
    else
      ASTTk[node] := Ord(tyInteger);
    CheckArithOperandsHaveAMeaning(op, left, right);
    CurASTNode := node;
    { Keep the side channel with the VALUE. LastExprTk was last written by
      ParseFactor, so after `7 / 2` it held the type of the `2` — and every
      consumer that asks it about "the expression I just parsed" got the last
      FACTOR instead. `int(7/2)` printed 3.5's bit pattern and `float(7/2)`
      printed 4.6e18, while the identical `x = 7/2; int(x)` was correct because
      an ident leaves the two agreeing. Fixed at the source rather than at each
      consumer: the arms below and in ParseSimpleExpr end the same way.
      bug-nilpy-int-of-a-division-reads-the-doubles-bits }
    LastExprTk := IntToTypeKind(ASTTk[node]);
  end;
end;

procedure ParseSimpleExpr;
var op: TTokenKind; neg: Boolean; left, right, node, opci: Integer;
    blv: Boolean;                 { a constant left operand of `or` }
    hadPos: Boolean; posOvl: Integer;
begin
  { Unary minus binds TIGHTER than the multiplicative level in EVERY frontend
    here — Pascal included. It used to be treated as an additive-level sign for
    Pascal/C on the grounds that FPC reads `-7 div 2` as `-(7 div 2)`; that is
    true and also unobservable, because both readings give -3. The operators
    that DO expose it are `and` and `shr`, and measured against FPC:

        var x: Integer; x := 8;
        -x and 12    FPC 8                     pxx -8      { -(x and 12) }
        -x shr 1     FPC 9223372036854775804   pxx -4      { -(x shr 1)  }

    so the old note picked `div` to check the very question `div` cannot answer.
    C agrees with FPC here too (`-a & b` is `(-a) & b`).

    The minus now always falls through to ParseFactor's own tkMinus case, which
    negates ONE factor — the path PyExprMode already took, for the same reason.
    bug-a-unary-minus-binds-looser-than-and-shr }
  neg := False;
  { Unary plus is identity FOR EVERY BUILT-IN OPERAND, so its binding is
    unobservable and eating it here is cheaper than teaching the factor a no-op
    case. It is NOT identity for a record that overloads it: FPC calls
    `class operator Positive(a: TFoo): TFoo` and terecs6 asserts a body that
    changes the value (`Result.F := a.F+1`), so the identity reading would
    print a different number rather than fail to compile.

    So the plus is remembered rather than merely eaten, and the overload is
    dispatched on the parsed operand -- the only point where its type is known.
    The result is an ordinary AN_CALL, not a tagged unary node like AN_NEG's:
    a call is what the operand shape already lowers correctly (const-by-ref
    params, a record return), and it needs no AST kind and no ir.inc arm.
    feature-p-fpc-global-operator-overload-declarations }
  hadPos := (CurTok.Kind = tkPlus);
  Eat(tkPlus);
  ParseTerm;
  if hadPos then
  begin
    posOvl := UnaryOpOverloadCall(Ord(tkPlus), CurASTNode);
    if posOvl >= 0 then CurASTNode := posOvl;
  end;
  if neg then
  begin
    node := AllocNode(AN_NEG); ASTLeft[node] := CurASTNode; ASTTk[node] := ASTTk[CurASTNode]; CurASTNode := node;
  end;
  { tkSymDiff (`><`, set symmetric difference) rides the ADDITIVE level, which is
    where FPC puts it alongside set `+` and `-`. Only the Pascal lexer produces
    the token, so no frontend gate is needed. }
  while (CurTok.Kind in [tkPlus, tkMinus, tkOr, tkXor, tkSymDiff]) and
        not (PyExprMode and (CurTok.Kind in [tkOr, tkXor])) do
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseTerm;
    right := CurASTNode;
    { the `or` half of the same rule -- see ParseTerm's `and` note.

      NOT `xor`, and that is MEASURED rather than an oversight. fpc 3.2.2 makes
      `and`/`or` on sized booleans LOGICAL and leaves `xor` BITWISE, which is
      visible only with a nonzero-not-one operand: with a = ByteBool(200) and
      b = ByteBool(1), FPC answers `Ord(a and b)` = 1 and `Ord(a or b)` = 1 --
      canonical truth values -- while `Ord(a xor b)` is -55, i.e. 200 xor 1 =
      201 reinterpreted signed. Bit patterns are meaningful in the type family
      that exists for the C ABI, so this is FPC being deliberate rather than
      inconsistent, and we match it. Do not "fix" the asymmetry. }
    if op = tkOr then SemBoolNormalisePair(left, right);
    { WideChar concatenation is STRING building, not integer addition (FPC:
      WideChar+WideChar is a two-unit UTF-16 string). Both sides widechar ->
      the surrogate-aware pair helper, so `WideChar(u1)+WideChar(u2)` of a
      surrogate pair yields the single 4-byte code point (fpjson's \uXXXX
      decoder). One widechar side against a string -> convert that side to
      its UTF-8 encoding and concatenate normally. }
    if (op = tkPlus) and NodeIsWideCharVal(left) and NodeIsWideCharVal(right) then
    begin
      opci := FindProc('__pxxWideCharPairToUTF8');
      if opci < 0 then Error('WideChar concatenation: __pxxWideCharPairToUTF8 helper not loaded');
      node := AllocNode(AN_ARG);
      ASTLeft[node] := left; ASTTk[node] := Ord(tyInteger);
      left := AllocNode(AN_ARG);
      ASTLeft[left] := right; ASTRight[left] := -1; ASTTk[left] := Ord(tyInteger);
      ASTRight[node] := left;
      left := node;
      node := AllocNode(AN_CALL);
      ASTIVal[node] := opci;
      ASTTk[node] := Ord(Procs[opci].RetType);
      ASTLeft[node] := left; ASTRight[node] := -1;
      CurASTNode := node;
      continue;
    end;
    { A 2-byte ordinal (tyUInt16 = WideChar; there is no distinct WideChar type)
      concatenated with a string/char MUST be a widechar — `Word + string` is
      invalid Pascal — so convert it, matching the widechar(x)-cast case. This
      catches a bare `w: WideChar` variable, which NodeIsWideCharVal (cast-only)
      misses; without it `'x' + w` crashed. Restricted to the SINGLE-sided form:
      `tyUInt16 + tyUInt16` stays integer addition (Word+Word), since two 2-byte
      ordinals are ambiguous and must not be silently turned into string-building.
      See bug-pascal-widechar-var-to-string-other-contexts. }
    if (op = tkPlus) and
       (NodeIsWideCharVal(left) or (IntToTypeKind(ASTTk[left]) = tyUInt16)) and
       ((ASTTk[right] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyString)) or
        (ASTTk[right] = Ord(tyChar))) then
      left := WrapWideCharToUTF8(left)
    else if (op = tkPlus) and
       (NodeIsWideCharVal(right) or (IntToTypeKind(ASTTk[right]) = tyUInt16)) and
       ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[left] = Ord(tyString)) or
        (ASTTk[left] = Ord(tyChar))) then
      right := WrapWideCharToUTF8(right);
    { A PChar operand of `+` whose OTHER side is a string or a char is a CONCAT
      operand, not pointer arithmetic — `s := 'Error: ' + strerror(e)` is the
      shape, and it is FPC's answer too (measured: PChar+Char = 'abcdeQ',
      Char+PChar = 'Qabcde', while PChar+Integer stays pointer arithmetic).

      pxx got BOTH halves wrong, silently, in the two directions that look
      least alike. With a multi-char literal the node typed as tyString and the
      concat codegen read the POINTER as string data, appending one garbage
      byte ('xy' + p -> 'xy?'). With a single-char literal — tyChar, an ordinal
      — the `ordinal + pointer` arm below claimed it first and the whole
      expression became pointer arithmetic: 'x' + p offset the pointer by 120
      bytes and produced ''. One expression, two unrelated wrong answers, no
      diagnostic in either.

      Normalising HERE rather than adding a third arm below is the point: every
      downstream arm then sees two string operands and needs to know nothing
      about PChar. It sits next to the WideChar wrap above for the same reason —
      same problem, same place, one shape. Excluded in C mode, where `p + 'x'`
      genuinely IS pointer arithmetic (a char is an int there).
      refactor-centralize-managed-string-pchar-conversion }
    if (op = tkPlus) and not CProgramMode then
    begin
      if IsNodePChar(left) and
         ((ASTTk[right] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyString)) or
          (ASTTk[right] = Ord(tyChar))) then
        left := WrapPCharToString(left)
      else if IsNodePChar(right) and
         ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[left] = Ord(tyString)) or
          (ASTTk[left] = Ord(tyChar))) then
        right := WrapPCharToString(right);
    end;
    { A frozen-string OPERAND presents as a tyString value, exactly as a symbol
      read does. StrValTk normalises every symbol site; a CALL node does not —
      it carries Ord(Procs[pi].RetType), the STORAGE kind, at some 50 sites — so
      `P + '!'` with `P: shortstring` arrived here as tyShortString, missed the
      concat arm below (which tests tyString / tyAnsiString / tyChar) and fell
      into POINTER ARITHMETIC: `writeln(P + '!')` printed an address and
      `a := P + '!'` gave the empty string, while `v + '!'` on a shortstring
      VARIABLE was correct all along.

      Normalised HERE, on the operand, for the same reason the WideChar and
      PChar wraps above are: every downstream arm then sees a string operand and
      needs to know nothing about which frozen kind produced it. Storage kind
      and capacity live on the symbol, not on the value.
      bug-p-a-frozen-string-concat-operand-becomes-pointer-arithmetic }
    if not CProgramMode then
    begin
      if TypeIsFrozenString(IntToTypeKind(ASTTk[left])) then
        ASTTk[left] := StrValTk(IntToTypeKind(ASTTk[left]));
      if TypeIsFrozenString(IntToTypeKind(ASTTk[right])) then
        ASTTk[right] := StrValTk(IntToTypeKind(ASTTk[right]));
    end;
    { A CONSTANT LEFT OPERAND OF `or` -- the mirror of the `and` fold in
      ParseTerm, and see its comment for why this is lowering. `xor` is
      DELIBERATELY NOT FOLDED here: it does not short-circuit, so both operands
      are evaluated whatever the left one is, and dropping the right would
      remove side effects the language promises to run. }
    if ((op = tkOr) and (ASTTk[right] = Ord(tyBoolean)) and PasBoolLit(left, blv)) then
    begin
      if blv then CurASTNode := PasMakeBoolLit(True) else CurASTNode := right;
      continue;
    end;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    { `a xor b` over two sized booleans stays BITWISE (see the SemBoolNormalisePair
      call above) and its RESULT is still a sized boolean of that width, so it
      renders TRUE/FALSE rather than the bit pattern. fpc 3.2.2 prints TRUE for
      ByteBool(200) xor ByteBool(1) while `Ord` of the same expression is -55 --
      one value, a boolean TYPE and an integer PATTERN, which is precisely the
      pair a kind alone cannot hold. Both operands, and the same width: mixing
      widths is not a shape FPC gives a sized-boolean result to. }
    if (op = tkXor) and (NodeSemIdOf(left) = NodeSemIdOf(right)) and
       SemIsBool(NodeSemIdOf(left)) then
      ASTSemId[node] := NodeSemIdOf(left);
    { {$Q+} region: + and - are overflow-checked (feature-pascal-overflow-checks-q-plus) }
    if ((op = tkPlus) or (op = tkMinus)) and TokQChecks[TokPos - 1] then
      ASTQChk[node] := True;
    opci := -1;
    { EITHER operand: `1.5 + cx` is as much an overloaded operator as `cx + 1.5`,
      and FPC accepts both. The lookup key stays the LEFT operand and the right
      one is matched against the entry's second parameter, so a scalar-left
      entry is only ever reachable from an expression that has an aggregate in
      it — which is what keeps `3 * 5` plain arithmetic with an
      `(Integer, TCx)` operator in scope.
      feature-a-operator-table-keyed-on-both-operands }
    if TkIsRecordOrClass(ASTTk[left]) or TkIsRecordOrClass(ASTTk[right]) then
      opci := FindOpOverload2(Ord(op), ASTTk[left], ResolveNodeRec(left),
                              ASTTk[right], ResolveNodeRec(right));
    if opci >= 0 then
      { Overloaded operator on a record/class operand: the node's type is the
        operator's result type, so an inferred target and the aggregate-return
        copy are sized correctly (not the tyInteger catch-all below). }
      ASTTk[node] := Ord(Procs[opci].RetType)
    else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
      ASTTk[node] := Ord(tyVariant)
    else if (op = tkPlus) and not PyExprMode and not CProgramMode and
            DynConcatOperandsEligible(left, right) then
    begin
      { `a + b` over two dynamic arrays — FPC's {$modeswitch arrayoperators} /
        Delphi-mode concatenation. SAME node the Concat intrinsic builds, so
        there is one lowering to keep correct rather than two
        (feature-p-dynamic-array-concatenation). A dyn array on only ONE side
        stays the loud refusal in ir.inc: it used to add the two handles and
        hand back a wild pointer. }
      node := MakeDynConcat(left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPlus) and PyNodeIsPyBytes(left) and PyNodeIsPyBytes(right) then
    begin
      { b1 + b2 — bytes concatenation (uforth WRITE-LINE) }
      node := PyMakeBytesBinCall('pybytes_concat', left, right, tyClass);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPlus) and PyNodeIsPyList(left) and PyNodeIsPyList(right) then
    begin
      { xs + ys — list concatenation (uforth {: :} locals: list(a)+list(b)) }
      node := PyMakeListBinCall('pylist_concat', left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPipe) and PyNodeIsPyDict(left) and PyNodeIsPyDict(right) then
    begin
      { d1 | d2 — PEP 584 dict union. Checked before the set arm below since
        a dict is a distinct tyClass identity from TPyList, and only dict
        needs `|` disambiguated from set's own use of it. }
      node := PyMakeDictBinCall('pydict_or', left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op in [tkAmp, tkPipe, tkMinus, tkXor]) and
            PyNodeIsPyList(left) and PyNodeIsPyList(right) then
    begin
      { Python's set operators: & (intersection), | (union), - (difference),
        ^ (symmetric difference). A list supports NONE of these four, so two
        TPyList operands here are unambiguously a set operation — see
        pyset_and's own comment for why this silently did raw pointer
        arithmetic before (bug-nilpy-set-and-dict-operators-do-raw-pointer-
        arithmetic). }
      if op = tkAmp then node := PyMakeListBinCall('pyset_and', left, right)
      else if op = tkPipe then node := PyMakeListBinCall('pyset_or', left, right)
      else if op = tkMinus then node := PyMakeListBinCall('pyset_sub', left, right)
      else node := PyMakeListBinCall('pyset_xor', left, right);
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op = tkPlus) and
            (PyNodeIsPyList(left) or PyNodeIsPyList(right)) then
    begin
      { `[1,2] + "x"` — one side is a list and the other is not: CPython
        raises TypeError at RUN time (`can only concatenate list (not "str")
        to list`); NilPy's list-concat branch above already requires BOTH
        sides typed as a list, so a mismatched pair fell through into the
        tyString-concat branch below, which only checks "either side is a
        string" and ignores that the OTHER side is a raw class/list POINTER —
        silently reinterpreting it as string data instead of raising
        (bug-nilpy-list-plus-nonlist-silently-corrupts-instead-of-typeerror).
        NilPy resolves types statically, so this is caught here as a compile
        error rather than deferred to a run-time exception. }
      { runtime TypeError, matching CPython, rather than a build abort — the
        static type is known here but Python's answer is an exception. }
      CurASTNode := PyMakeUnsupportedOperand;
      continue;
    end
    { complex `+` and `-`, either operand order, mixed with int/float — before
      the reflected and user-class arms, both of which exclude pylib classes. }
    else if PyExprMode and (op in [tkPlus, tkMinus]) and
            (PyNodeIsComplex(left) or PyNodeIsComplex(right)) then
    begin
      node := PyMakeComplexBinop(op, left, right);
      if node < 0 then node := PyMakeUnsupportedOperand;
      CurASTNode := node;
      continue;
    end
    else if PyExprMode and (op in [tkPlus, tkMinus]) and
            (IntToTypeKind(ASTTk[left]) <> tyClass) and
            (PyReflectedDunder(PyReflName(op), left, right) >= 0) then
    begin
      { reflected: the LEFT operand is not a user class, so try the RIGHT
        operand's __radd__/__rsub__ with the operands swapped. }
      CurASTNode := PyReflectedDunder(PyReflName(op), left, right);
      continue;
    end
    else if PyExprMode and (op in [tkPlus, tkMinus]) and
            (IntToTypeKind(ASTTk[left]) = tyClass) and
            (ResolveNodeRec(left) >= REC_UCLASS_BASE) then
    begin
      { `Vector(1,2) + Vector(3,4)` — a user class's own operator dunder
        (`__add__`/`__sub__`). Neither operand reached here as a TPyList/
        TPyDict (those branches above already `continue`d), so a bare tyClass
        LEFT operand is a genuine user object: dispatch to its dunder method
        rather than falling through to the arithmetic/pointer typing below,
        which silently computed garbage on the two class HANDLES as if they
        were integers (bug-nilpy-arithmetic-operator-dunders-not-dispatched).
        Only the LEFT operand's class is consulted — matching Python's
        left-operand-first dunder lookup; the right-operand `__radd__`/
        `__rsub__` fallback (e.g. `3 * Vector(...)`) is not implemented. }
      if op = tkPlus then node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__add__', left, right)
      else node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__sub__', left, right);
      if node < 0 then
        node := PyMakeUnsupportedOperand;   { runtime TypeError, not a build abort }
      CurASTNode := node;
      continue;
    end
    else if (op = tkPlus) and ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyAnsiString))) then
      ASTTk[node] := Ord(tyAnsiString)
    else if (op = tkPlus) and ((ASTTk[left] = Ord(tyString)) or (ASTTk[right] = Ord(tyString)) or
                          ((ASTTk[left] = Ord(tyChar)) and (ASTTk[right] = Ord(tyChar)))) then
    begin
      { Managed default: type literal/char concat as a MANAGED result. The
        frozen concat codegen builds its result in a 272-byte buffer carved
        off the stack with NO restore (documented in IRLowerCallArg) — fine
        for a one-off, but `s := 'p' + Chr(i)` in a loop leaked 272 bytes of
        stack per iteration and overflowed after ~30k iterations
        (bug-frozen-concat-stack-carve-loop-overflow). The managed concat
        path heap-allocates and already accepts tyString/tyChar operands.
        Frozen self-build (-uPXX_MANAGED_STRING) keeps the old typing. }
      if PasDefineExists('PXX_MANAGED_STRING') then
        ASTTk[node] := Ord(tyAnsiString)
      else
        ASTTk[node] := Ord(tyString);
    end
    else if (op = tkMinus) and
            (ASTTk[left] = Ord(tyPointer)) and (ASTTk[right] = Ord(tyPointer)) then
      { POINTER DIFFERENCE is a NUMBER, not a pointer. tyPointer is reported as
        ordinal by TypeIsOrdinal, so `p - q` matched the pointer-arithmetic arm
        below and the result node stayed tyPointer — which is only invisible
        while the value is assigned to an integer. `Writeln(pc - pc0)` on a
        ^Char / ^Byte then printed the DIFFERENCE AS A STRING and segfaulted
        dereferencing address 3, while the identical expression assigned to a
        PtrInt first printed 3. The lowering already scales by the element size;
        only the node's type was wrong.
        bug-p-pointer-difference-is-typed-as-a-pointer }
      ASTTk[node] := Ord(tyNativeInt)
    else if ((op = tkPlus) or (op = tkMinus)) and
            (ASTTk[left] = Ord(tyPointer)) and
            TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
      ASTTk[node] := Ord(tyPointer)
    else if (op = tkPlus) and
            TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and
            (ASTTk[right] = Ord(tyPointer)) then
      ASTTk[node] := Ord(tyPointer)
    else if (ASTTk[left] = Ord(tySet)) or (ASTTk[right] = Ord(tySet)) then
      ASTTk[node] := Ord(tySet)
    else if ((op = tkOr) or (op = tkXor)) and (ASTTk[left] = Ord(tyBoolean)) and (ASTTk[right] = Ord(tyBoolean)) then
      ASTTk[node] := Ord(tyBoolean)
    else if (ASTTk[left] = Ord(tySingle)) or (ASTTk[left] = Ord(tyDouble)) or (ASTTk[left] = Ord(tyExtended)) or
            (ASTTk[right] = Ord(tySingle)) or (ASTTk[right] = Ord(tyDouble)) or (ASTTk[right] = Ord(tyExtended)) then
    begin
      ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
      PromoWidenBinopOperands(node);
    end
    else if TypeIsPromoInt(IntToTypeKind(ASTTk[left])) or
            TypeIsPromoInt(IntToTypeKind(ASTTk[right])) then
      { A promotable int is infectious: mixing it with any ordinary integer
        yields a promotable int. This arm must sit ABOVE the ordinal arm because
        promo is deliberately not reported by TypeIsOrdinal — without it the
        result fell through to the tyInteger default and the IR lowering never
        saw a promo type, so overflow silently WRAPPED (25! came out as 25! mod
        2^64 instead of trapping). Below the float arm, so promo-with-float
        still resolves as float. }
      ASTTk[node] := Ord(TypeArithmeticResultOp(IntToTypeKind(ASTTk[left]),
                                                IntToTypeKind(ASTTk[right]), op))
    else if PyExprMode and PyIntGrowsOp(op) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[left])) and
            PyIsMachineIntTk(IntToTypeKind(ASTTk[right])) then
      { NilPy: `+`/`-` over two NATIVE ints is still arbitrary precision — see
        PyIntGrowsOp. Below the promo arm (which already covers the mixed case)
        and above the ordinal one, which would type it tyInteger and wrap. }
      ASTTk[node] := Ord(tyPromoInt64)
    else if TypeIsOrdinal(IntToTypeKind(ASTTk[left])) and TypeIsOrdinal(IntToTypeKind(ASTTk[right])) then
    begin
      { FPC range-based constants: a NON-NEGATIVE integer literal paired with a
        QWord operand joins the UNSIGNED domain. The literal $f0000000 widens to
        tyInt64 at parse (> maxint), and the equal-width signed-wins rule then
        demoted `q + $f0000000` to Int64 — correct bits, but printed/compared
        SIGNED (tint642's lo/hi section). A negative literal keeps the old rule. }
      if (ASTTk[left] = Ord(tyUInt64)) and (ASTKind[right] = AN_INT_LIT) and
         (ASTIVal[right] >= 0) then
        ASTTk[node] := Ord(TypeArithmeticResultOp(tyUInt64, tyUInt64, op))
      else if (ASTTk[right] = Ord(tyUInt64)) and (ASTKind[left] = AN_INT_LIT) and
              (ASTIVal[left] >= 0) then
        ASTTk[node] := Ord(TypeArithmeticResultOp(tyUInt64, tyUInt64, op))
      else
        ASTTk[node] := Ord(TypeArithmeticResultOp(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]), op));
    end
    else
      ASTTk[node] := Ord(tyInteger);
    CheckArithOperandsHaveAMeaning(op, left, right);
    CurASTNode := node;
    { the additive level's half of the same rule — see ParseTerm's note }
    LastExprTk := IntToTypeKind(ASTTk[node]);
  end;
end;

{ THE SEMANTIC IDENTITY of an expression node, or SEM_NONE — an enum's type
  index, or the width of the sized boolean it is.

  THIS FUNCTION IS WHERE "WHOSE IDENTITY IS IT" IS WRITTEN DOWN, and that is the
  one obligation the identity design is under. Identity is not carried by the
  TYPE (an enum is tyInteger at codegen; a ByteBool is tyInt8), so every shape
  that can name such a value has to be asked separately — and each has to be
  asked about the RIGHT SUBJECT:

    ident            SymSemId        tagged at the var decl — the value's OWN
    folded member    ASTSemId        a member const folds to its ordinal literal
    a[i]             SymElemEnumId   an array symbol's TypeKind IS its element kind,
                                     so the ELEMENT's identity needs its own slot
    r.f              UFldSemId       the field twin of SymSemId
    F(...)           ProcRetSemId    a call node has no symbol and no field

  An ARRAY ident answers NOTHING here even when its elements have an identity,
  and a WHOLE array field likewise: `WriteLn(a)` must not claim to be an enum.
  A bare "is there an identity" read is what hands `set of TCol` its ELEMENT's
  member names. Add a shape by adding an arm that names its subject, never by
  widening an existing one.

  READ THE `= SEM_NONE` FALLBACKS BELOW AS LOAD-BEARING. They were `< 0` while
  the only family was enums and every real value was >= 0; a sized boolean's
  identity is NEGATIVE, so `< 0` silently discarded it and fell through to
  ASTSemId. Measured 2026-09-06: `function F: LongBool` and `r.f: ByteBool` both
  stamped their channels correctly and both still printed the ordinal, because
  this line threw the answer away three lines after finding it.

  Whatever migrates type identity into one vehicle
  ([[feature-a-typeref-migrate-consumers]]) should absorb all five; until then a
  shape that is missing here prints the ORDINAL where FPC prints the name, which
  is the whole of bug-p-an-enum-reached-through-a-field-or-index-still-writes-its-ordinal. }
function NodeSemIdOf(node: Integer): Integer;
var neBase, neRec, neFld: Integer;
begin
  Result := SEM_NONE;
  if node < 0 then Exit;
  if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) then
  begin
    { An ARRAY ident is not an enum VALUE even when its elements are: SymSemId
      is deliberately left clear on it, and answering SymElemEnumId here would
      make `WriteLn(a)` claim to be an enum. }
    if not Syms[ASTIVal[node]].IsArray then Result := SymSemId[ASTIVal[node]];
    Exit;
  end;
  if ASTKind[node] = AN_INDEX then
  begin
    { ASTLeft of an AN_INDEX is the base NODE (defs.inc's "base sym idx" comment
      predates the Pascal path), so an indexed array reaches its element identity
      through the base ident's SymElemEnumId, and an indexed array FIELD through
      that field's UFldSemId — which holds the ELEMENT's enum for an array. }
    neBase := ASTLeft[node];
    { `dd[0][1]` over `array of array of TEnum`: every level has the same element
      identity, so walk down to the base the declaration actually named. }
    while (neBase >= 0) and (ASTKind[neBase] = AN_INDEX) do neBase := ASTLeft[neBase];
    if neBase >= 0 then
    begin
      if (ASTKind[neBase] = AN_IDENT) and (ASTIVal[neBase] >= 0) and
         (ASTIVal[neBase] < SymCount) then
        Result := SymElemEnumId[ASTIVal[neBase]]
      else if ASTKind[neBase] = AN_FIELD then
      begin
        neRec := ResolveNodeRec(ASTLeft[neBase]);
        if neRec >= REC_UCLASS_BASE then
        begin
          neFld := FindUField(neRec - REC_UCLASS_BASE, GetASTIdentName(neBase));
          if (neFld >= 0) and UFldIsArray[neFld] then Result := UFldSemId[neFld];
        end;
      end;
    end;
    if Result = SEM_NONE then Result := ASTSemId[node];
    Exit;
  end;
  if ASTKind[node] = AN_FIELD then
  begin
    neRec := ResolveNodeRec(ASTLeft[node]);
    if neRec >= REC_UCLASS_BASE then
    begin
      neFld := FindUField(neRec - REC_UCLASS_BASE, GetASTIdentName(node));
      { UFldSemId holds the ELEMENT's enum for an array field, so a WHOLE array
        field must not answer it — same rule as the ident arm above. }
      if (neFld >= 0) and (not UFldIsArray[neFld]) then Result := UFldSemId[neFld];
    end;
    if Result = SEM_NONE then Result := ASTSemId[node];
    Exit;
  end;
  if ASTNodeIsCall(node) and (ASTIVal[node] >= 0) and (ASTIVal[node] < ProcCount) then
  begin
    { A call node has no symbol and no field, so the callee's row is the only
      place the result's enum identity survives.

      ASKED THROUGH ASTNodeIsCall, not `= AN_CALL`. This arm named ONE of the
      five call kinds, and every one of them carries a Procs[] index in IVal --
      so an enum returned through anything but a direct call lost its identity
      and `Writeln` printed the ORDINAL. Measured against fpc 3.2.2 with
      `TF = function(k: Integer): TCol`: `Writeln(fp(1))` printed **1** where
      FPC prints **cGreen**, while the direct `Writeln(Pick(1))` printed cGreen
      on both. Silent wrong OUTPUT with no diagnostic, and the direct-call
      control is what says it is the node shape and not the feature.

      Found by a census of the ProcRet* columns (2026-09-04) rather than by a
      report: the procedural-signature path did not fill ProcRetSemId either,
      and fixing only that changed nothing, because this reader could not see
      the node. Both halves were needed and neither is sufficient -- which is
      the argument for measuring a fix rather than reasoning about it. }
    Result := ProcRetSemId[ASTIVal[node]];
    if Result = SEM_NONE then Result := ASTSemId[node];
    Exit;
  end;
  { An enum MEMBER reached here as a folded ordinal literal; ASTSemId is the only
    thing that still remembers which enum minted it. }
  Result := ASTSemId[node];
end;

procedure ParseExpr;
var op: TTokenKind; left, right, node, isci, isNode, isArg, isArg2: Integer; isIsTest: Boolean;
    chMid, chSym, chAssign, chSeq, chRight, chCmp, chAnd: Integer;   { Python comparison chaining }
    spDepth, spI: Integer;
    ordDirect, ordRefl: AnsiString; ordLCi, ordRCi, ordErr: Integer;   { Python ordering dunders }
    caOp, caRhs: Integer;   { compound assignment: the binop token, and the NilPy variant rewrite }
    caBinTk: TTokenKind;    { same token as caOp, kept typed for the NilPy dunder dispatch }
begin
  { NilPy argument UNPACKING of a list literal: `f(*[a, b, c])` means
    `f(a, b, c)`, and with a literal that is purely syntactic — songformatter
    writes `canvas.setStrokeColorRGB(*[0.0, 0.0, 0.0])`.

    The '*' and '[' are consumed here and the elements are then parsed as
    ordinary arguments: every argument loop in this parser already reads
    `expr (',' expr)*`, so the commas INSIDE the literal do the work. The only
    token the loops cannot make sense of is the closing ']', which is consumed
    at the end of whichever ParseExpr call lands on it.

    Nothing is mutated. An earlier version rewrote the ']' into a comma, which
    worked once and then broke: NilPy re-parses a body (the module-local
    pre-pass trial-parses, def bodies are compiled from stored token
    positions), and the second pass met a '[' whose ']' had been overwritten.

    Only a LITERAL list splices: unpacking a variable needs its length at
    compile time, so `f(*xs)` still walls at the '*' rather than quietly
    passing one argument. }
  if isNilPy and (CurTok.Kind = tkStar) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLBrack) then
  begin
    Next;                              { consume '*' }
    Next;                              { consume '[' }
    Inc(PyStarSpliceDepth);
  end;
  ParseSimpleExpr;
  { `X is T` / `X as T` — is/as are contextual identifiers (not reserved tokens),
    treated as operators only when followed by a known class name, so a stray
    identifier is never hijacked. Parser-resolved into their own AST nodes (per
    the and/or lesson: never key behaviour off a global flag). }
  { `E is <class-reference VALUE>` -- the class to test against is only known at
    runtime: a TClass variable, param, or field (fpcunit's
    `if not (E is FExpectedException)`, where FExpectedException: TClass is a field).

    AN_IS_TEST carries a compile-time class INDEX, so it cannot express this. But the
    test is exactly InheritsFrom on the instance's blob:

        E is cr   ==   __pxxInheritsFrom(rtti_of(E), cr)

    which is the operation already built for `x.InheritsFrom(C)`. Recognised only when
    the right-hand ident is a class-reference-typed symbol or field -- a known class
    NAME still takes the compile-time path above, and anything else leaves `is` alone. }
  if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'is') and
     (not PyExprMode) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
     (FindUClass(GetTokenStr(TokPos)) < 0) and
     IdentIsClassRefValue(GetTokenStr(TokPos)) and
     (FindProc('__pxxInheritsFrom') >= 0) then
  begin
    Next;                       { consume 'is' }
    left := CurASTNode;
    node := GenMakeRttiOfCall(left);            { the instance's runtime class }
    ParseFactor;                                { the class-reference operand }
    right := CurASTNode;
    isci := FindProc('__pxxInheritsFrom');
    isNode := AllocNode(AN_CALL);
    ASTIVal[isNode] := isci;
    ASTTk[isNode] := Ord(tyBoolean);
    isArg := AllocNode(AN_ARG);
    ASTLeft[isArg] := node;
    ASTLeft[isNode] := isArg;
    isArg2 := AllocNode(AN_ARG);
    ASTLeft[isArg2] := right;
    ASTRight[isArg] := isArg2;
    LastExprTk := tyBoolean;
    CurASTNode := isNode;
    { no Exit: the class-REFERENCE `is` is the third arm of the same relational
      level, and leaving it out would have made `E is cr = b` the one spelling
      still refused. }
  end;

  { NOT under PyExprMode for `is`: Pascal's `E is TClass` is a TYPE test, but
    Python's `is` is IDENTITY and never a type test (`isinstance` is the type
    test, and has its own branch). This intercept sits in the SHARED ParseExpr
    and fired first, so NilPy's `x is K(2)` was read as the Pascal type test
    `x is K` — the constructor never ran, the trailing `(2)` was left behind,
    and the answer was True because x really is a K. Silent at module scope,
    a bare parse error inside a def, and INVISIBLE to a boolean-only test
    because `X() is Y()` is False either way — which is how it was filed as
    "a construction on the right of is does not parse".
    `is not` was unaffected (this pattern does not match it), which is what
    made the two shapes look unrelated.
    bug-nilpy-construction-on-the-right-of-is-does-not-parse }
  if (CurTok.Kind = tkIdent) and
     ((CaseEqual(CurTok.SVal, 'is') and (not PyExprMode)) or
      CaseEqual(CurTok.SVal, 'as')) and
     (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) and
     (FindUClass(GetTokenStr(TokPos)) >= 0) then
  begin
    isIsTest := CaseEqual(CurTok.SVal, 'is');
    Next;
    isci := FindUClass(CurTok.SVal);
    Next;
    left := CurASTNode;
    if isIsTest then
    begin
      node := AllocNode(AN_IS_TEST);
      ASTLeft[node] := left; ASTIVal[node] := isci; ASTTk[node] := Ord(tyBoolean);
    end
    else
    begin
      node := AllocNode(AN_AS_CAST);
      ASTLeft[node] := left; ASTIVal[node] := isci;
      { `obj as IFoo` yields an interface VALUE (a CORBA fat pointer, a 2-word
        record); `obj as TClass` yields a class reference. }
      if UClsIsInterface[isci] then ASTTk[node] := Ord(tyRecord)
      else ASTTk[node] := Ord(tyClass);
    end;
    CurASTNode := node;
    { no Exit: `is` and `as` are relational-level too -- see the `in` arm. }
  end;
  if (CurTok.Kind = tkIn) and not PyExprMode then
  begin
    Next;
    if CurTok.Kind = tkLBrack then
    begin
      CurASTNode := ParseSetMembershipAST(CurASTNode);
    end
    else
    begin
      left := CurASTNode;
      ParseSimpleExpr;
      right := CurASTNode;
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkIn);
      ASTLeft[node] := left;
      ASTRight[node] := right;
      ASTTk[node] := Ord(tyBoolean);
      CurASTNode := node;
    end;
    { FALLS THROUGH to the comparison level below, and used to Exit. `in` is a
      RELATIONAL operator in Pascal, at the same precedence as `=`, so
      `MS in CurrentModeSwitches = Enable` means `(MS in ...) = Enable` --
      fcl-passrc pscanner.pp:3806 writes exactly that and we answered
      `expected 'then'`. Exiting here made `in` a precedence level of its own
      that nothing could follow, and the same Exit was on the `is`/`as` arm
      above (`o is TB = b`, equally legal, equally refused).
      bug-p-a-relational-operator-cannot-follow-in-is-or-another-comparison }
  end;
  { WHILE, not IF: the Pascal comparison level is LEFT-ASSOCIATIVE, so
    `i < 2 = b` is `(i < 2) = b` and `i = 1 = b` is `(i = 1) = b`. fpc 3.2.2
    compiles both and prints TRUE. The comment on the Python chaining loop at
    the bottom of this arm says "Pascal has no chained comparison (`a < b < c`
    is a type error there)" -- wrong about the language, and wrong when
    written: it is a type error only where the third operand is not Boolean.
    Pascal's chain is plain left association and NOT Python's conjunction
    desugar, which is why this is a loop around the whole arm rather than a
    widening of that loop's guard. In PyExprMode the inner loop consumes the
    chain first and this one re-tests to nothing. }
  while CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] do
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseSimpleExpr;
    right := CurASTNode;
    { …and comparing two truth values compares their TRUTH, not their raw
      ordinals. Ahead of the enum diagnostics below, which ask
      `NodeSemIdOf(x) >= 0` and are therefore about the enum family only -- a
      sized boolean's identity is negative and cannot reach them. }
    SemBoolNormalisePair(left, right);
    { FPC-parity: an ENUM operand cannot compare against a pointer — there is
      no implicit conversion between them (toperatorerror). Detection is
      ident-level (SymSemId is tagged at var decls), so complex expressions
      stay unchecked — this is a diagnostic, not a type system. }
    if (NodeSemIdOf(left) >= 0) and (IntToTypeKind(ASTTk[right]) = tyPointer) or
       (NodeSemIdOf(right) >= 0) and (IntToTypeKind(ASTTk[left]) = tyPointer) then
      Error('cannot compare an enum with a pointer');
    { ...and two DIFFERENT enum types have no common ordering either: `aColor = apple`
      compared TColor against TFruit's ordinal and quietly answered yes/no. Same
      identity, same ident-level limits as the assignment check. }
    if (NodeSemIdOf(left) >= 0) and (NodeSemIdOf(right) >= 0) and
       (NodeSemIdOf(left) <> NodeSemIdOf(right)) then
      Error('cannot compare enum type ' +
            GetTokenStrFromRaw(EnumTypeNOff[NodeSemIdOf(left)], EnumTypeNLen[NodeSemIdOf(left)]) +
            ' with enum type ' +
            GetTokenStrFromRaw(EnumTypeNOff[NodeSemIdOf(right)], EnumTypeNLen[NodeSemIdOf(right)]));
    { ORDERING a record operand with no registered `class operator`. `b := r < 1`
      compared the record's first qword against 1 and answered off garbage; FPC
      says "Illegal qualifier".

      The identical refusal exists in ir.inc's binop lowering and stays there as
      the backstop for nodes nobody parsed — but a diagnostic that lives ONLY in
      lowering is one that vanishes the moment anything EARLIER in the file was
      reported: error recovery stops lowering at the first recovered diagnostic
      (`if ErrCount > 0 then Exit` in CompileAST), so this one went silent behind
      its six siblings and a file with seven errors still wrote a binary. A
      dialect rule belongs in the dialect's parser, beside the enum-comparison
      diagnostics just above — which is also why the check is a PARSE-time
      FindOpOverload2 lookup rather than a flag lowering has to carry.

      Only the ORDERING operators, exactly as the lowering arm has it: `=`/`<>`
      stay exempt because a method-pointer compare is a legitimate record `=`,
      and C is exempt because struct pointer/array arithmetic tags operands
      tyRecord legitimately.
      regression-test-core-test-indexing-length-for-new-inc-positive }
    if (not CProgramMode) and
       ((op = tkLt) or (op = tkGt) or (op = tkLe) or (op = tkGe)) and
       ((IntToTypeKind(ASTTk[left]) = tyRecord) or
        (IntToTypeKind(ASTTk[right]) = tyRecord)) and
       (FindOpOverload2(Ord(op), ASTTk[left], ResolveNodeRec(left),
                        ASTTk[right], ResolveNodeRec(right)) < 0) then
      { RECOVERS: the node it leaves behind is an ordinary boolean AN_BINOP, so
        the parse carries on and the file's LATER mistakes are reported too --
        which is the whole point of moving the check here. A plain Error() would
        halt at 49 and lose the `with` and the function-result assignment. }
      ErrorRecover('no operator overload found for ordering a record operand '
            + '(< > <= >= need an explicit `class operator`)'
            + ' — PXXDBG=a.opovl prints the lookup and every candidate');
    { FPC range-based constants: a NON-NEGATIVE literal compared against an
      UNSIGNED operand compares UNSIGNED — retag the literal so codegen's
      TypeCompareUnsigned sees two unsigned operands. Without this
      `q > $f0000000` (literal widened to tyInt64 at parse) compared signed
      and a qword >= 2^63 answered wrong (tint642 family). This read
      `= tyUInt64` for years, i.e. it fixed the 8-byte arm of a rule that
      applies at every width; it is the same normalisation `div`/`mod` needs,
      so both now call the one helper. }
    { ...but a ONE-CHARACTER literal against a PChar is a STRING comparison, and
      it has to be normalised to the string BEFORE that unsigned retag runs. A
      pointer is an unsigned operand, so NormalizeUnsignedLiteralOperand claimed
      `'-'` first and retagged it tyUInt64 — after which the PChar wrap below
      could no longer recognise a char operand, and `p = '-'` silently compared
      the POINTER against 45 and answered False. `p = '--'` was right all along,
      the same length boundary as the argument case, and equally invisible.
      bug-single-char-literal-as-pchar-argument-segfaults }
    if not CProgramMode then
    begin
      if IsNodePChar(left) then RetagCharLitAsStr(right)
      else if IsNodePChar(right) then RetagCharLitAsStr(left);
    end;
    { ...and, as at div/mod, a literal wider than Int64 is unsigned on its own
      authority: `9223372036854775808 > 1` answered FALSE because BOTH operands
      were literals and neither could tell the pair rule anything. }
    NormalizeWideUnsignedLiteral(left);
    NormalizeWideUnsignedLiteral(right);
    NormalizeUnsignedLiteralOperand(left, right);
    NormalizeUnsignedLiteralOperand(right, left);
    { A PChar compared against a string or a char compares CONTENTS, as in FPC.
      pxx compared the two POINTERS, so `p = 'alpha'` answered whatever pointer
      identity happened to say: True when p had been assigned that very literal
      (same data-section handle), False for the same text built at runtime.
      `PChar(s) = 'alpha'` with s built by concatenation was already answering
      the wrong thing before any of this; the assign-a-literal case only looked
      right by luck, and stopped looking right the moment
      bug-p-a-string-literal-assigned-to-a-pchar-is-empty made the assignment
      store char 0 instead of the handle.

      Normalised HERE, on the operand, for the same reason the `+` wrap sits at
      the additive level: every downstream comparison arm then sees two string
      operands and needs to know nothing about PChar. Excluded in C mode, where
      `p == "x"` genuinely IS a pointer comparison.
      refactor-centralize-managed-string-pchar-conversion }
    if not CProgramMode then
    begin
      if IsNodePChar(left) and
         ((ASTTk[right] = Ord(tyAnsiString)) or (ASTTk[right] = Ord(tyString)) or
          (ASTTk[right] = Ord(tyChar))) then
        left := WrapPCharToString(left)
      else if IsNodePChar(right) and
         ((ASTTk[left] = Ord(tyAnsiString)) or (ASTTk[left] = Ord(tyString)) or
          (ASTTk[left] = Ord(tyChar))) then
        right := WrapPCharToString(right);
    end;
    if PyExprMode and (op in [tkEq, tkNeq]) and
       PyNodeIsPyBytes(left) and PyNodeIsPyBytes(right) then
    begin
      { bytes VALUE equality (`raw == b""`): the class-pair fallthrough
        compared POINTERS, which is Python-wrong for bytes }
      node := PyMakeBytesBinCall('pybytes_eq', left, right, tyBoolean);
      if op = tkNeq then
      begin
        left := AllocNode(AN_NOT);
        ASTLeft[left] := node;
        ASTTk[left] := Ord(tyBoolean);
        node := left;
      end;
      CurASTNode := node;
      Exit;
    end;
    { A user class that defines `__eq__` is compared BY IT — Python's own rule,
      and the same shape as PyStrOfValue dispatching `__str__`. Without it `==`
      fell through to a pointer compare, so `V(1) == V(1)` was False with the
      method sitting right there unused, and `!=` was wrong from the same cause.
      The failure direction is the bad one: two equal values report unequal, so
      a membership test or an `if got == expected` takes the wrong branch
      silently (bug-nilpy-eq-dunder-ignored).

      `__lt__` and `__len__` already dispatched, so this is wiring rather than
      machinery. Built at AST level through PyCallMeth1, NOT as hand-rolled IR:
      the `other` parameter is normally unannotated, i.e. a by-reference
      variant, and a hand-built IR_ARG skips IRLowerCallArg
      (project_irlowercallarg_hand_built_args_landmine).

      The result keeps the METHOD's own return type rather than being forced to
      Boolean — the callee's ABI decides, and an annotated `-> bool` or an
      inferred boolean body both land there anyway. Non-virtual, exactly like
      the `__str__` dispatch: it resolves against the operand's static class. }
    { `!=` prefers a declared `__ne__`. CPython does NOT define `!=` as
      `not __eq__` when `__ne__` is present — it calls `__ne__`, whose result is
      returned as-is and need not even be a Boolean. Without this a class that
      deliberately breaks the symmetry (three-valued comparisons, NaN-like
      sentinels, "always unequal" wrappers) had its method silently ignored and
      got the negated `__eq__` instead (bug-nilpy-ne-dunder-ignored-always-
      negates-eq). The auto-derived case below stays: with only `__eq__`
      declared, CPython DOES derive `!=` as its negation, and that already
      matched. }
    { complex `==` / `!=` compares the two components. Without this the pair
      fell through to a reference compare, so `complex(1,2) == complex(1,2)`
      answered False -- two equal numbers by every Python rule, unequal here
      only because they were separate allocations. Either operand may be a
      real: `complex(2,0) == 2` is True in CPython. }
    if PyExprMode and (op in [tkEq, tkNeq]) and
       (PyNodeIsComplex(left) or PyNodeIsComplex(right)) then
    begin
      node := PyMakeComplexBinop(op, left, right);
      if node >= 0 then
      begin
        CurASTNode := node;
        Exit;
      end;
    end;
    { The RIGHT operand needs no type at all. Python's comparison dunders take
      ANY object — `obj == 1`, `obj < 1.5`, `obj == "s"`, `obj == None` — and
      requiring a class on both sides meant the method was simply never
      consulted: a `__eq__` returning True unconditionally still compared
      UNEQUAL, so the answer was the OPPOSITE of CPython, silently, with one
      class and no inheritance. Only the LEFT operand decides whose dunder
      runs, which is Python's own left-operand-first rule and what the
      arithmetic arms above already do.
      bug-n-a-comparison-dunder-against-a-non-class-operand-answers-wrongly }
    if PyExprMode and (op = tkNeq) and
       (IntToTypeKind(ASTTk[left]) = tyClass) and
       (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
       not PyRecIsPylibOwnClass(ResolveNodeRec(left)) and
       (FindUMeth(ResolveNodeRec(left) - REC_UCLASS_BASE, '__ne__') >= 0) then
    begin
      node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__ne__',
                          left, right);
      if node >= 0 then
      begin
        CurASTNode := node;
        Exit;
      end;
    end;
    { ...and the same for `__eq__` — see the note on the `__ne__` arm above. }
    if PyExprMode and (op in [tkEq, tkNeq]) and
       (IntToTypeKind(ASTTk[left]) = tyClass) and
       (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
       not PyRecIsPylibOwnClass(ResolveNodeRec(left)) and
       (FindUMeth(ResolveNodeRec(left) - REC_UCLASS_BASE, '__eq__') >= 0) then
    begin
      node := PyCallMeth1(ResolveNodeRec(left) - REC_UCLASS_BASE, '__eq__',
                          left, right);
      if node >= 0 then
      begin
        if op = tkNeq then
        begin
          right := AllocNode(AN_NOT);
          ASTLeft[right] := node;
          ASTTk[right] := Ord(tyBoolean);
          node := right;
        end;
        CurASTNode := node;
        Exit;
      end;
    end;
    { ORDERING dunders — `<` `<=` `>` `>=` between two class instances. Without
      this the operands fell through to a raw POINTER compare, so `C(3) < C(1)`
      answered by allocation address with `__lt__` sitting right there unused —
      silent and wrong, the same failure family as the `__eq__` case above
      (measured: `a < b` -> True where CPython says False).

      CPython's rule, measured rather than assumed: try the DIRECT dunder on the
      left operand, else the REFLECTED partner on the right operand (`a > b`
      falls back to `b.__lt__(a)`, which is why a class defining only `__lt__`
      supports both `<` and `>`). Ordering has NO identity fallback the way `==`
      does — when neither exists CPython raises TypeError, so a runtime raise is
      the correct answer, not a pointer compare.

      Built through PyCallMeth1 at AST level for the reason the `__eq__` block
      records: the `other` parameter is normally an unannotated by-reference
      variant, and a hand-built IR_ARG would skip IRLowerCallArg
      (project_irlowercallarg_hand_built_args_landmine).

      pylib's OWN containers are excluded, and that exclusion is load-bearing: a
      TPyList is `tyClass` too, but it already compares LEXICOGRAPHICALLY further
      down (`[1,2] < [1,3]`). A first version without the guard captured lists
      here and, finding no `__lt__` on them, raised "comparison not supported" —
      turning working list comparison into a runtime abort
      (caught by test_nilpy_mixed_type_operands). Same exclusion the
      `__contains__` dispatch makes in pyparser.inc, for the same reason: a bare
      tyClass operand only means "genuine user object" AFTER pylib's own rows are
      ruled out. }
    { The ORDERING pair, and the same widening: either operand being a genuine
      user object is enough. `b < 1` answered by allocation address with
      `__lt__` sitting right there unused, exactly as `b == 1` did — the whole
      family shared one over-strict guard.

      The two sides are now asked SEPARATELY: `ordLCi` / `ordRCi` are -1 for a
      non-class operand, and FindUMeth(-1, ...) finds nothing, so the direct
      lookup is tried on the left and the REFLECTED one on the right without
      either needing the other to be a class. Requiring both was what made
      `b < 1` fall through to the identity/numeric path.
      bug-n-a-comparison-dunder-against-a-non-class-operand-answers-wrongly }
    { ...but a VARIANT operand is not a "non-class operand", it is an UNKNOWN
      one, and this arm has no fall-through: when it finds no dunder it emits a
      raise. So capturing a pair with a variant on one side turns the runtime
      answer into a compile-time refusal. Measured: `lhs = 0; lhs = V(7); lhs < p`
      where V declares `__lt__` — the left is statically a variant, so ordLCi is
      -1, the REFLECTED `__gt__` is looked for on the right and V does not have
      one, and the whole comparison became `raise TypeError: comparison not
      supported`. CPython calls `lhs.__lt__(p)`; so does pylib's pycmp_v, which
      is where a variant operand belongs and where it went before this arm was
      widened to either side.

      The dispatch would be wrong even when a dunder IS found, for the same
      reason: Python asks the LEFT operand's type first, and with the left a
      variant we cannot know whether it has the direct dunder — jumping to the
      right operand's reflected one reverses the order the language specifies.
      Both directions are therefore excluded, not just variant-on-the-left.

      This does not narrow the fix it qualifies: `b < 1`, `b == "s"`,
      `obj < 1.5` all still dispatch, because an int/str/float operand IS
      statically known to have no dunders. Only tyVariant is unknowable here.
      regression-test-nilpy-test-nilpy-variant-operand-arith-dunders }
    if PyExprMode and (op in [tkLt, tkLe, tkGt, tkGe]) and
       (IntToTypeKind(ASTTk[left]) <> tyVariant) and
       (IntToTypeKind(ASTTk[right]) <> tyVariant) and
       (((IntToTypeKind(ASTTk[left]) = tyClass) and
         (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
         not PyRecIsPylibOwnClass(ResolveNodeRec(left))) or
        ((IntToTypeKind(ASTTk[right]) = tyClass) and
         (ResolveNodeRec(right) >= REC_UCLASS_BASE) and
         not PyRecIsPylibOwnClass(ResolveNodeRec(right)))) then
    begin
      case op of
        tkLt: begin ordDirect := '__lt__'; ordRefl := '__gt__'; end;
        tkLe: begin ordDirect := '__le__'; ordRefl := '__ge__'; end;
        tkGt: begin ordDirect := '__gt__'; ordRefl := '__lt__'; end;
        else  begin ordDirect := '__ge__'; ordRefl := '__le__'; end;
      end;
      ordLCi := -1;
      if (IntToTypeKind(ASTTk[left]) = tyClass) and
         (ResolveNodeRec(left) >= REC_UCLASS_BASE) and
         not PyRecIsPylibOwnClass(ResolveNodeRec(left)) then
        ordLCi := ResolveNodeRec(left) - REC_UCLASS_BASE;
      ordRCi := -1;
      if (IntToTypeKind(ASTTk[right]) = tyClass) and
         (ResolveNodeRec(right) >= REC_UCLASS_BASE) and
         not PyRecIsPylibOwnClass(ResolveNodeRec(right)) then
        ordRCi := ResolveNodeRec(right) - REC_UCLASS_BASE;
      node := -1;
      if (ordLCi >= 0) and (FindUMeth(ordLCi, ordDirect) >= 0) then
        node := PyCallMeth1(ordLCi, ordDirect, left, right)
      else if (ordRCi >= 0) and (FindUMeth(ordRCi, ordRefl) >= 0) then
        { reflected: the RIGHT operand is the receiver and the left the argument }
        node := PyCallMeth1(ordRCi, ordRefl, right, left);
      if node < 0 then
      begin
        { Neither dunder — a genuine RUNTIME TypeError (a try/except around it
          must still compile and run its handler), not a compile-time Error()
          that would abort the whole build. Same shape the `__contains__` miss
          uses in pyparser.inc. }
        ordErr := FindProc('PyNotOrderableError');
        if ordErr < 0 then Error('Nil Python: pylib (PyNotOrderableError) not loaded');
        node := AllocNode(AN_CALL);
        ASTIVal[node] := ordErr;
        ASTTk[node] := Ord(tyBoolean);
        ASTLeft[node] := -1;
      end;
      CurASTNode := node;
      Exit;
    end;
    { `3 == "ab"` — a STRING compared with a NUMBER under ==/!=. In Python that
      is simply False (True for !=): objects of different types are unequal, it
      is not an error. Here it reached the string comparison with the NUMBER as
      the string handle and dereferenced 3 as a pointer, so the one-liner
      `print(3 == "ab")` SEGFAULTED (bug-nilpy-int-equals-string-segfaults).
      A string against a bool, a class handle or None crashed the same way.

      Answered at parse time, since both static types are known: a `str` is
      equal only to a `str`. PyEqDisjointFromString (symtab.inc) says which
      types qualify and, more importantly, which do not — tyChar (a
      one-character literal can carry it, so `"a" == c` must stay a real
      comparison) and tyVariant (not known until run time).

      The operands are still EVALUATED, through a right-nested comma, because
      `f() == "x"` must still call f. Folding to a bare literal would have
      dropped the call. Ordering comparisons (`3 < "ab"`) are a different
      question — Python raises TypeError there — and are left to
      decide-nilpy-mixed-type-operand-policy. }
    if PyExprMode and (op in [tkEq, tkNeq]) and
       ((IntToTypeKind(ASTTk[left]) in [tyString, tyAnsiString, tyShortString, tyFixedString]) <>
        (IntToTypeKind(ASTTk[right]) in [tyString, tyAnsiString, tyShortString, tyFixedString])) and
       (PyEqDisjointFromString(IntToTypeKind(ASTTk[left])) or
        PyEqDisjointFromString(IntToTypeKind(ASTTk[right]))) then
    begin
      node := AllocNode(AN_BOOL_LIT);
      ASTIVal[node] := Ord(op = tkNeq);
      ASTTk[node] := Ord(tyBoolean);
      chSeq := AllocNode(AN_COMMA);
      ASTLeft[chSeq] := right;
      ASTRight[chSeq] := node;
      ASTTk[chSeq] := Ord(tyBoolean);
      node := AllocNode(AN_COMMA);
      ASTLeft[node] := left;
      ASTRight[node] := chSeq;
      ASTTk[node] := Ord(tyBoolean);
      CurASTNode := node;
      Exit;
    end;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op); ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(tyBoolean); CurASTNode := node;

    { Python COMPARISON CHAINING: `0 <= i < n` means `(0 <= i) and (i < n)` with
      the middle operand evaluated ONCE. That single evaluation is why it cannot
      be desugared by repeating the token text — `a < f() < b` would call f
      twice (feature-nilpy-comparison-chaining). Anything but a plain
      ident/literal is bound to a hidden local first: an IR value node is a
      SUBTREE, so referencing one twice RE-EMITS it. PyExprMode-only because
      Pascal's chain means something DIFFERENT -- plain left association,
      `(a < b) < c` -- and is handled by the `while` around this whole arm.
      This comment used to say "Pascal has no chained comparison (`a < b < c`
      is a type error there)"; that is true only where the third operand is not
      Boolean, and fpc compiles `i < 2 = b`. }
    while PyExprMode and (CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe]) do
    begin
      if (ASTKind[right] = AN_IDENT) or (ASTKind[right] = AN_INT_LIT) or
         (ASTKind[right] = AN_FLOAT_LIT) then
        chMid := right
      else
      begin
        chSym := AllocVar('', IntToTypeKind(ASTTk[right]));
        chMid := AllocNode(AN_IDENT);
        ASTIVal[chMid] := chSym;
        ASTTk[chMid] := ASTTk[right];
        chAssign := AllocNode(AN_ASSIGN);
        ASTLeft[chAssign] := chMid;
        ASTRight[chAssign] := right;
        { (t := mid, t) — evaluate the middle operand once, yield the temp }
        chSeq := AllocNode(AN_COMMA);
        ASTLeft[chSeq] := chAssign;
        ASTRight[chSeq] := chMid;
        ASTTk[chSeq] := ASTTk[right];
        ASTRight[node] := chSeq;    { the FIRST comparison consumes the binding }
      end;
      op := CurTok.Kind; Next;
      ParseSimpleExpr;
      chRight := CurASTNode;
      chCmp := AllocNode(AN_BINOP);
      ASTIVal[chCmp] := Ord(op);
      ASTLeft[chCmp] := chMid;
      ASTRight[chCmp] := chRight;
      ASTTk[chCmp] := Ord(tyBoolean);
      chAnd := AllocNode(AN_BINOP);
      ASTIVal[chAnd] := Ord(tkAnd);
      ASTLeft[chAnd] := node;
      ASTRight[chAnd] := chCmp;
      ASTTk[chAnd] := Ord(tyBoolean);
      node := chAnd;
      right := chRight;
      CurASTNode := node;
    end;
  end;
  { Compound assignment expression `lv += rhs` (and -= *= /=), right-associative
    so `a += b += c` nests on the Right and each yields its stored value. The
    tokens are new to pxx (no existing source produces them) so this tail is inert
    for non-C code → self-host byte-identical. The lvalue check is done at IR
    lowering (where IsASTLValue is visible), which also rejects `a++ += x`. The
    plain value-bearing `=` (op = tkAssign) is produced by the C frontend; the
    node + lowering handle it as the trivial store-and-yield subset of this. }
  { ...but NOT when the target is a SUBSCRIPT READ through a receiver that is
    not a name — `f()[k] += 1`. The node this tail would take as its lvalue is
    a pyvar_getitem CALL: there is no address to read-modify-write, so the
    AN_ASSIGN built below stored into the call's result and the update was
    silently DISCARDED (measured: `get_dict()["n"] += 2` left the dict at 1).
    Declining here leaves the operator for NilPy's statement-level arm, which
    is the one place that can express the store — it desugars to
    pyvar_setitem(recv, k, pyvar_getitem(recv, k) OP rhs).

    `**=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=` are not in the token set
    above and already fall through to that arm; this only stops the four that
    do reach here from claiming the shape first.
    bug-n-a-subscript-store-whose-receiver-is-a-call-result-does-not-parse }
  if (CurTok.Kind in [tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq]) and
     not (NilPyUserCode and PyIsVarGetitemCall(CurASTNode)) then
  begin
    op := CurTok.Kind; Next;
    left := CurASTNode;
    ParseExpr;                 { right-assoc: RHS may itself be a compound assign }
    right := CurASTNode;
    { tkSlashEq means DIFFERENT operators in different frontends, which is the
      trap here: NilPy's lexer emits it for `//=` (floor division — `/=` gets
      tkTrueDivEq), while Pascal and C emit it for `/=` (real division). Mapping
      it unconditionally to tkSlash made `self.n //= 3` perform TRUE division —
      25 //= 3 gave 8.333… instead of 8, silently
      (bug-nilpy-floor-div-assign-is-true-division).

      The ELSE is no longer a silent fallthrough to division either: that shape
      is exactly how this bug arrived, and it would have done the same for the
      next compound token added. }
    case op of
      tkPlusEq:  caBinTk := tkPlus;
      tkMinusEq: caBinTk := tkMinus;
      tkStarEq:  caBinTk := tkStar;
      tkSlashEq: if NilPyUserCode then caBinTk := tkDiv
                 else caBinTk := tkSlash;
      else       begin caBinTk := tkSlash;
                       Error('internal: unhandled compound-assignment operator'); end;
    end;
    caOp := Ord(caBinTk);
    { A NilPy VARIANT lvalue must NOT take the compound-assign node. That node
      computes the lvalue address once and does a scalar read-modify-write, which
      on a 16-byte variant slot reads the payload as a raw machine word: `self.n
      += 3` yielded True, `-=` an empty line and `*=` 4.94e-323 — the integer's
      bit pattern read as a double
      (bug-nilpy-augmented-assign-to-a-variant-typed-field-corrupts-it).

      This tail is documented as "inert for non-C code", and it is for Pascal —
      but NilPy's `+=` lexes to tkPlusEq too, and a DOTTED target (`self.n += 3`)
      reaches the expression parser before NilPy's own augmented-assignment path
      can see it. A field initialised from an UNANNOTATED ctor parameter is
      variant-typed, which is the most idiomatic constructor in Python, so this
      was the common case rather than a corner.

      Rewritten to the explicit `lv = lv <op> rhs`, which is exactly what NilPy's
      own augmented path builds for a bare name and is measured correct — the
      binop goes through the variant-aware dispatch instead of a raw word
      update. `+` keeps the AUGADD mark so a variant holding a LIST still extends
      IN PLACE (bug-nilpy-augmented-add-on-variant-list-is-not-in-place).

      EITHER side, not just the lvalue: the mirror case is an INT field with a
      variant OPERAND (`def add(self, v): self.n += v`, v an unannotated
      parameter), where the raw update added the variant's low word read as a
      truthy 1 — `C(10).add(5)` returned 11
      (bug-nilpy-augmented-assign-of-a-variant-param-to-an-int-field-adds-one).
      Same missing conversion seen from the other end, and the same explicit
      rewrite fixes it; the binop's own typing then widens as it does for a
      written-out `self.n = self.n + v`. }
    { A NilPy target holding a USER CLASS instance takes neither the compound
      node nor the variant rewrite: `h.acc += 5` must call __iadd__ (or __add__
      and rebind), and with neither declared must RAISE. The raw read-modify-
      write added the two instance HANDLES and stored the sum into a class slot,
      so the field read back as 0 — silently, dunder never called
      (bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero).

      It lands HERE rather than in NilPy's own augmented path for the same
      reason the variant fix above does: a DOTTED target reaches this shared
      expression tail first, so pyparser's site never sees it. The helper is
      NilPy's (pyparser.inc) and returns -1 for anything that is not a user
      class, which keeps Pascal and C on their existing path. }
    caRhs := -1;
    { `h.xs += [3]` on a LIST-typed field is Python's in-place extend, the same
      rule bug-a-nilpy-list-augmented-add-segfaults established for a bare name.
      pyparser's augmented path carries that special case, but — again — only a
      bare name reaches it, so the dotted spelling fell through to the compound
      node, added the two list HANDLES and SEGFAULTED (measured against the
      pinned binary too: pre-existing, not a regression of the dunder work). }
    if NilPyUserCode and (caBinTk = tkPlus) and (PyNodeListCi(left) >= 0) then
    begin
      caRhs := PyCallMeth1(PyNodeListCi(left), 'extend', left, right);
      if caRhs < 0 then Error('Nil Python: pylib TPyList.extend not loaded');
    end;
    { `o.xs *= 2` / `d[k] *= 2` on a SEQUENCE is the REPEAT, not a multiply —
      see PyAugMulNode. Unlike the in-place `extend` above, the repeat is a
      VALUE, so it needs the store built around it. }
    if (caRhs < 0) and NilPyUserCode and (caBinTk = tkStar) then
    begin
      node := PyAugMulNode(left, right);
      if node >= 0 then
      begin
        { …unless the repeat was built IN PLACE, in which case the mutation IS
          the statement: storing the same handle back through this target
          released the list before the append ran and `h.xs *= 2` came out
          EMPTY, while the identical local was right. }
        if PyAugMulInPlace then
          caRhs := node
        else
        begin
          caRhs := AllocNode(AN_ASSIGN);
          ASTLeft[caRhs] := left;
          ASTRight[caRhs] := node;
        end;
      end;
    end;
    if (caRhs < 0) and NilPyUserCode then
      caRhs := PyAugClassDunderNode(left, caBinTk, right);
    if caRhs >= 0 then
      CurASTNode := caRhs
    else if NilPyUserCode and ((IntToTypeKind(ASTTk[left]) = tyVariant) or
                               (IntToTypeKind(ASTTk[right]) = tyVariant)) then
    begin
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := caOp;
      ASTLeft[node] := left; ASTRight[node] := right;
      { WIDEN the two operand types, exactly as NilPy's own augmented path does
        for a bare name. Taking the lvalue's type instead makes an int-typed
        binop over a VARIANT operand, which reads the variant's 16-byte slot as
        a machine word and yields a pointer; taking tyVariant unconditionally
        would box the result into a scalar field. The widen is what the written
        out `self.n = self.n + v` gets, and that spelling is measured correct. }
      ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]),
                                 IntToTypeKind(ASTTk[right])));
      if (caOp = Ord(tkPlus)) and (IntToTypeKind(ASTTk[left]) = tyVariant) then
        ASTSLen[node] := PY_BINOP_AUGADD;
      caRhs := node;
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := left; ASTRight[node] := caRhs;
      CurASTNode := node;
    end
    else
    begin
      node := AllocNode(AN_COMPOUND_ASSIGN);
      ASTLeft[node] := left; ASTRight[node] := right;
      ASTIVal[node] := caOp;
      ASTTk[node] := ASTTk[left];
      CurASTNode := node;
    end;
  end;
  { The closing ']' of a `*[...]` argument splice: the elements were handed to
    the caller's argument loop one comma at a time, and this is the token the
    loop would not know what to do with. Consumed by whichever ParseExpr call
    lands on it — the last element's. }
  if (PyStarSpliceDepth > 0) and (CurTok.Kind = tkRBrack) then
  begin
    Dec(PyStarSpliceDepth);
    Next;
  end;
end;

function ConstIntCastWidth(const nm: AnsiString; var bytes: Integer; var signed: Boolean): Boolean;
{ True if `nm` is an integer-family type name usable as a const typecast; sets
  the result width in bytes and whether it sign-extends. Recognises both the
  tk*_T keyword spellings and the tkIdent type aliases (Int64/UInt64/...).
  Uses CaseEqual (not LowerCase) so it stays callable before LowerCase is
  declared — self-host requires declaration-before-use. }
var tk: TTypeKind;
begin
  { THE THIRD COPY OF THE BUILTIN TYPE-NAME TABLE, now derived from the one
    shared with the declaration path and the runtime cast chain instead of
    spelling the names again. It answered a different QUESTION -- a width and a
    signedness rather than a kind -- which is why the earlier merge left it
    behind; but TypeSlotSize and TypeSigned answer that question FROM a kind, so
    the name table itself was never the part that had to be duplicated.

    IT WAS NOT HARMLESS, and this ticket said it probably was. `nativeint`,
    `ptrint`, `nativeuint` and `ptruint` were 8 bytes UNCONDITIONALLY -- the
    same claim the runtime chain used to make and had corrected, since these
    are pointer-sized BY DEFINITION. Measured on i386 and arm32, one program:

      const A = NativeInt(4294967296 + 5);   ->  4294967301
      var   a: NativeInt; a := 4294967296+5; ->  5

    The const fold and the runtime cast disagreed about the SAME cast in the
    same program, and the const one produced a value that does not fit the type
    on that target. Self-inconsistent, so it needs no oracle to be wrong. Both
    32-bit targets, both signed and unsigned; x86-64 could never show it because
    there 8 is the right answer.

    Deriving also picks up `sizeint`/`sizeuint`, which the shared table has and
    this list never did -- they were simply not castable in a const expression.

    The accepted KINDS stay an explicit closed set rather than TypeIsOrdinal,
    which would newly admit Boolean and enums; this is a widths-of-the-integer-
    family question and that is a deliberate boundary, not an omission.
    refactor-a-the-const-cast-width-table-is-the-third-copy }
  tk := BuiltinScalarTypeKind(nm);
  Result := (tk = tyInt8) or (tk = tyUInt8) or (tk = tyInt16) or (tk = tyUInt16) or
            (tk = tyInt32) or (tk = tyUInt32) or (tk = tyInt64) or (tk = tyUInt64) or
            (tk = tyNativeInt) or (tk = tyNativeUInt) or (tk = tyInteger) or (tk = tyChar);
  if Result then
  begin
    bytes := TypeSlotSize(tk);
    signed := TypeSigned(tk);
  end
  else
  begin
    bytes := 8; signed := True;
  end;
end;

function ConstAliasCastWidth(const nm: AnsiString; var bytes: Integer; var signed: Boolean): Boolean;
{ True if `nm` is a user type alias whose target is ordinal and therefore usable
  as a const typecast. }
var aliasIdx: Integer; tk: TTypeKind;
begin
  Result := False;
  aliasIdx := FindTypeAlias(nm);
  if aliasIdx < 0 then Exit;
  tk := IntToTypeKind(AliasTk[aliasIdx]);
  if not TypeIsOrdinal(tk) then Exit;
  bytes := TypeSlotSize(tk);
  signed := TypeSigned(tk);
  Result := True;
end;

function ConstCastWidth(const nm: AnsiString; var bytes: Integer; var signed: Boolean): Boolean;
{ THE ONE ENTRY POINT for "is `nm` a type name a CONST expression may cast
  through, and how wide is it". It exists to own the ORDER, because the order is
  load-bearing and it was wrong when it lived at the call site: a source
  declaration outranks a builtin (symtab.inc:6215 documents that inverting that
  breaks the compiler outright), and this door asked the builtin table first.

    type LongInt = Int64;
    const A = LongInt(4294967296 + 5);   ->  5             (builtin, 4 bytes)
    var b: LongInt; b := LongInt(...);   ->  4294967301    (alias, 8 bytes)

  Fixed at the call site in 4be17cb8f; here so that a future caller cannot get
  it wrong again by asking the two halves in the order that reads naturally.
  A rule spelled once is not a rule spelled at every caller.
  refactor-p-five-dispatch-sites-for-one-named-type-cast }
begin
  Result := ConstAliasCastWidth(nm, bytes, signed);
  if not Result then
    Result := ConstIntCastWidth(nm, bytes, signed);
end;

function ConstApplyCast(r: Int64; bytes: Integer; signed: Boolean): Int64;
{ Reinterpret r to the cast width, matching the runtime wrap behaviour. Sign
  extension uses subtraction (Result - 2^width) rather than `not`, and decimal
  literals (which exceed signed-32 and so parse as Int64), avoiding the hex-width
  / `not Int64()` folding pitfalls. }
begin
  Result := r;
  if bytes = 1 then
  begin
    Result := r and 255;
    if signed and (Result >= 128) then Result := Result - 256;
  end
  else if bytes = 2 then
  begin
    Result := r and 65535;
    if signed and (Result >= 32768) then Result := Result - 65536;
  end
  else if bytes = 4 then
  begin
    Result := r and 4294967295;
    if signed and (Result >= 2147483648) then Result := Result - 4294967296;
  end;
  { bytes = 8: full width, no change }
end;

function ConstEval: Int64; forward;
function ConstEvalOrdBound: Int64; forward;
procedure ParseArrayDimBounds(var lo, hi: Integer); forward;   { body sits with the const helpers }

function ConstEvalFactor: Int64;
{ Primary of a const expression: literal / true / false / single-char literal /
  named const / parenthesised expr / integer typecast. Unary +/- binds tightest
  (so -2*3 = -(2)*3 = -6 and 2*-3 = -6). No code emitted. }
var r: Int64; idx: Integer; castBytes: Integer; castSigned: Boolean;
    cName: AnsiString; cQUnit, ceOrd: Integer; hasConstCast, hlHigh: Boolean; sofTk: TTypeKind;
    ccBaseCi, ccReg: Integer;
begin
  r := 0;
  CEOrdTk := tyInteger; CEEnumId := -1;
  { see CEOrdTk: reset here, narrowed by the ordinal-producing arms below (the
    char literal, TEnum.member, Chr, High/Low, a named ordinal const) and by
    the relational level in ConstEval }
  { NB: the parens on the recursive ConstEvalFactor() are required — a bare own
    function name in an expression reads the (uninitialised) Result var instead
    of recursing, both under the FPC seed and self-hosted. }
  if CurTok.Kind = tkMinus then begin Next; Result := -ConstEvalFactor(); CEOrdTk := tyInteger; CEEnumId := -1; Exit; end;
  if CurTok.Kind = tkPlus  then begin Next; Result :=  ConstEvalFactor(); CEOrdTk := tyInteger; CEEnumId := -1; Exit; end;
  { `not` KEEPS the operand's boolean-ness: `not (a > b)` is a Boolean, `not 5`
    is an integer -- and the OPERATOR follows the operand, logical for a Boolean
    and bitwise otherwise. `not True` folded bitwise gives -2, which is a
    non-zero Boolean and therefore printed TRUE. }
  if CurTok.Kind = tkNot then
  begin
    Next;
    r := ConstEvalFactor();
    if CEOrdTk = tyBoolean then
    begin
      if r = 0 then Result := 1 else Result := 0;
    end
    else
    begin
      Result := not r;
      { bitwise `not` of an ordinal is a number -- but an unsigned 64-bit one
        stays unsigned, as it does in FPC: `not High(QWord)` is 0 either way,
        while `not QWord(0) - 1` is 2^64-2 unsigned and -2 signed. Clearing the
        kind here would have made the sign depend on which operator came next,
        which is the partial answer this feature refused to ship. }
      if not TkIsUnsigned64(CEOrdTk) then CEOrdTk := tyInteger;
      CEEnumId := -1;
    end;
    Exit;
  end;
  if CurTok.Kind = tkNil   then begin Next; Result := 0; Exit; end;   { `= nil` default params (FPC RTL) }
  hasConstCast := False;
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { ONE door, and it owns the alias-before-builtin ORDER internally rather
      than leaving it to be spelled here -- see ConstCastWidth for the cast this
      site used to fold to 5 while the runtime cast of the same expression in
      the same program answered 4294967301. }
    hasConstCast := ConstCastWidth(CurTok.SVal, castBytes, castSigned);
  end;
  if hasConstCast then
  begin
    { Integer typecast in a const expression, e.g. `Int64(1) shl 52`. Evaluate
      the inner expression then reinterpret to the cast width. FPC/Delphi fold
      these; ISO Pascal does not. NB: `ConstEval()` needs the parens — a bare
      `ConstEval` in an assignment RHS reads the function result var, not a call. }
    Next; Expect(tkLParen, '(');
    r := ConstEval(); Expect(tkRParen, ')');
    r := ConstApplyCast(r, castBytes, castSigned);
    { An integer typecast REPLACES the operand's kind, whatever it was -- and an
      8-byte UNSIGNED cast is how `QWord(x)` and `NativeUInt(x)` are spelled, so
      the cast is also the way to ENTER unsigned folding without a High()/Low().
      FPC's constexp.pas leans on exactly this: `r>qword(high(int64))` at line
      329 casts a signed bound up and then compares unsigned. }
    if (castBytes = 8) and (not castSigned) then CEOrdTk := tyUInt64
    else CEOrdTk := tyInteger;
    CEEnumId := -1;
  end
  else if CurTok.Kind = tkInteger then begin r := CurTok.IVal; Next; end
  else if CurTok.Kind = tkTrue  then begin r := 1; CEOrdTk := tyBoolean; Next; end
  else if CurTok.Kind = tkFalse then begin r := 0; CEOrdTk := tyBoolean; Next; end
  else if (CurTok.Kind = tkString) and (Length(CurTok.SVal) = 1) then
    { single-char literal 'x' used as an ordinal constant (Char typed-const
      element, `Ord('A')`-free contexts) -> its character code. }
    begin r := Ord(CurTok.SVal[1]); CEOrdTk := tyChar; Next; end
  else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'sizeof') then
  begin
    { SizeOf(TypeName) as a compile-time constant — needed for default-parameter
      values (`= sizeof(Pointer)`) and const expressions; FPC folds it. Minimal
      scope: a type name/keyword resolved via ParseTypeKind -> its byte size
      (covers sizeof(Pointer)/sizeof(Integer)/sizeof(TRec)). A sizeof(variable)
      or sizeof(arr[i]) form is not folded here (rare in a const context; the
      full expression path in ParseFactor handles those). See
      feature-sizeof-const-intrinsic-in-const-eval. }
    Next; Expect(tkLParen, '(');
    sofTk := ParseTypeKind;
    r := TypeStorageSize(sofTk, LastTypeRecId);
    Expect(tkRParen, ')');
  end
  else if (CurTok.Kind = tkIdent) and (TokPos + 1 < TokCount) and
          (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos+1].Kind = tkIdent) and
          (FindEnumType(CurTok.SVal) >= 0) and
          FindEnumMemberOrd(FindEnumType(CurTok.SVal), GetTokenStr(TokPos+1), ceOrd) then
  begin
    { `TEnum.member` in a constant expression (case labels, const decls) —
      scoped-enum access; folds to the ordinal. }
    r := ceOrd;
    CEEnumId := FindEnumType(CurTok.SVal);   { CurTok is still the type name }
    Next; Next; Next;   { TEnum, '.', member }
  end
  else if (CurTok.Kind = tkIdent) and
          (CaseEqual(CurTok.SVal, 'high') or CaseEqual(CurTok.SVal, 'low')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { High(T)/Low(T) as a compile-time constant — array bounds and const
      declarations (bug-pascal-high-low-in-const-expr). Type-name operands
      only, mirroring the sizeof fold above; High(variable) stays a runtime
      expression outside const contexts. }
    hlHigh := CaseEqual(CurTok.SVal, 'high');
    Next; Expect(tkLParen, '(');
    if not TryConstHighLowValue(hlHigh, r) then
      Error('High/Low in a constant expression: expected an ordinal type name');
    Expect(tkRParen, ')');
  end
  else if (CurTok.Kind = tkIdent) and
          (CaseEqual(CurTok.SVal, 'ord') or CaseEqual(CurTok.SVal, 'succ') or
           CaseEqual(CurTok.SVal, 'pred')) and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { Ord(x)/Succ(x)/Pred(x) as compile-time constants
      (compat-pascal-const-expr-ord-chr-succ): `case KeyCode of Ord('q'): ...`
      is the ordinary way to write a key handler and none of these folded, so
      it had to be spelled as a bare numeric literal with a comment instead.
      This evaluator already represents every ordinal value (char, enum,
      bool) as a bare Int64 — a char literal folds to its own ordinal via the
      tkString branch above, an enum member via the TEnum.member branch — so
      Ord(x) needs no conversion at all: it IS whatever x already evaluates
      to here. Succ/Pred are the same value +/-1, same as the runtime
      intrinsics. }
    cName := LowerCase(CurTok.SVal);
    Next; Expect(tkLParen, '(');
    r := ConstEval();
    Expect(tkRParen, ')');
    if cName = 'succ' then r := r + 1
    else if cName = 'pred' then r := r - 1
    else
      { `Ord` is exactly the operator that DISCARDS the ordinal's type, so it
        must clear the channel its operand set -- inheriting it would make
        `const N = Ord('a')` print `a`. Succ/Pred keep it, which is what makes
        `const E = Succ(eA)` print eB. }
      begin CEOrdTk := tyInteger; CEEnumId := -1; end;
  end
  else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'chr') and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
  begin
    { Chr(x): the inverse of Ord above, and for the same reason a no-op on the
      underlying Int64 value here — this evaluator has no separate
      char/integer representation, only the eventual type annotation on the
      const/case-label distinguishes them. }
    Next; Expect(tkLParen, '(');
    r := ConstEval();
    Expect(tkRParen, ')');
    CEOrdTk := tyChar; CEEnumId := -1;   { Chr is the operator that ADDS the char type }
  end
  else if (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'length') and
          (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
          (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkString) then
  begin
    { Length('literal') as a compile-time constant — the only const-foldable
      shape (a variable's length is not known until runtime, and this
      evaluator has no string representation beyond a literal's own token).
      Only entered when the very next token IS a string literal, so
      Length(someConstStringVariable) falls through to the ordinary "not a
      constant" diagnostic below rather than being silently mishandled. }
    Next; Expect(tkLParen, '(');
    r := Length(CurTok.SVal);
    Next;
    Expect(tkRParen, ')');
  end
  else if CurTok.Kind = tkIdent then
  begin
    { A `Unit.Const` qualifier (e.g. `termio.FIONREAD`) — ConsumeUnitQualifier
      leaves the parser on the member name and yields the unit index; resolve the
      const in that unit's scope, same as the ordinary-expression path. }
    cName := CurTok.SVal;
    cQUnit := ConsumeUnitQualifier(cName);
    if cQUnit >= 0 then
      idx := FindSymInUnit(cName, cQUnit)
    else
      idx := FindSym(cName);
    { A bare scalar class const in a const context — a sibling reference while the
      class body is still being parsed (`const B = A + 1`) or a class const used in
      a method's const expression. The backing lives under a mangled key, so the
      bare FindSym above misses it; recover it via the class-const registry.
      bug-pascal-class-const-visibility. }
    if (cQUnit < 0) and (idx < 0) then
    begin
      ccBaseCi := -1;
      if ParsingClassConstCi >= 0 then ccBaseCi := ParsingClassConstCi
      else if CurMethClass >= REC_UCLASS_BASE then ccBaseCi := CurMethClass - REC_UCLASS_BASE;
      if ccBaseCi >= 0 then
      begin
        ccReg := FindClassConst(ccBaseCi, cName);
        if ccReg >= 0 then idx := FindSym(ClassConstMangle(ClassConstCi[ccReg], cName));
      end;
    end;
    if (idx >= 0) and (Syms[idx].Kind = skConst) then
    begin
      r := Syms[idx].ConstVal;
      { a named ordinal const keeps its own kind through the fold, so
        `const A = 1 > 0; B = A and True;` types B as Boolean too, and
        `const C = 'z'; D = C;` types D as Char rather than 122. }
      if (Syms[idx].TypeKind = tyBoolean) or (Syms[idx].TypeKind = tyChar) or
         TkIsUnsigned64(Syms[idx].TypeKind) then
        { ...and an UNSIGNED 64-bit const keeps its kind for the same reason and
          with more at stake: `const A = High(QWord); B = A > 5;` reads A back
          as the bit pattern -1, so without this B folds signed and is FALSE.
          feature-p-const-evaluator-carries-unsigned-64-bit }
        CEOrdTk := Syms[idx].TypeKind
      else
        CEOrdTk := tyInteger;
      CEEnumId := SymSemId[idx];
    end
    else
      { compat-pascal-const-expr-ord-chr-succ: this used to dump raw lexer
        token state (line/kind/offset for a 10-token window) to stderr before
        erroring — internal debugging output that leaked onto every failing
        const expression, not just this fold's own development. The error
        message alone already names the offending token. }
      Error('not a constant');
    Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEval(); Expect(tkRParen, ')');
  end;
  Result := r;
end;

function ConstEvalTerm: Int64;
{ Multiplicative precedence level (binds tighter than +/-): * div mod and shl
  shr, left-associative. `shr` is lexed as an identifier (no tkShr token), like
  the runtime term parser. }
var r, v: Int64; op: TTokenKind; lTk: TTypeKind; lEid: Integer;
    unsg: Boolean;
begin
  r := ConstEvalFactor;
  lTk := CEOrdTk; lEid := CEEnumId;
  while (CurTok.Kind in [tkStar, tkDiv, tkMod, tkAnd, tkShl]) or
        ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'shr')) do
  begin
    if CurTok.Kind = tkIdent then
    begin
      { `shr` -- the first of the seven operations where the Int64 this
        evaluator carries is only a BIT PATTERN and the sign question is real.
        `High(QWord) shr 1` is 2^63-1; an arithmetic shift of -1 answers -1.
        The unsignedness rides in on CEOrdTk from TryConstHighLowValue and
        SURVIVES the operation, because a qword shifted is still a qword --
        that propagation is what makes `high(qword) div bb < aa` (FPC's own
        constexp.pas:321) fold correctly rather than one operator too late.
        feature-p-const-evaluator-carries-unsigned-64-bit }
      unsg := TkIsUnsigned64(lTk);
      Next; v := ConstEvalFactor;
      if unsg or TkIsUnsigned64(CEOrdTk) then
      begin
        r := Int64(UInt64(r) shr UInt64(v));
        lTk := tyUInt64;
      end
      else
      begin r := r shr v; lTk := tyInteger; end;
      lEid := -1;
    end
    else
    begin
      op := CurTok.Kind; Next; v := ConstEvalFactor;
      unsg := TkIsUnsigned64(lTk) or TkIsUnsigned64(CEOrdTk);
      { `and` over two Booleans is a Boolean; over anything else it is the
        bitwise operator and the result is an integer. Same rule as fpc's, and
        the reason `const F = (a > b) and (c < d)` types as Boolean here.
        Arithmetic over any OTHER ordinal is a number too -- `Ord('a') * 2` is
        not a char -- so everything else clears, exactly as before. }
      if (op = tkAnd) and (lTk = tyBoolean) and (CEOrdTk = tyBoolean) then
        lTk := tyBoolean
      else if unsg then
      begin lTk := tyUInt64; lEid := -1; end
      else
      begin lTk := tyInteger; lEid := -1; end;
      { *, and and shl are bit-identical signed or unsigned on two's-complement,
        so only div and mod branch. Listing them separately rather than casting
        every arm keeps the signed path byte-for-byte what it was. }
      case op of
        tkStar: r := r * v;
        tkDiv:  if unsg then r := Int64(UInt64(r) div UInt64(v)) else r := r div v;
        tkMod:  if unsg then r := Int64(UInt64(r) mod UInt64(v)) else r := r mod v;
        tkAnd:  r := r and v;
        tkShl:  r := r shl v;
      end;
    end;
  end;
  CEOrdTk := lTk; CEEnumId := lEid;
  Result := r;
end;

function ConstEvalAdd: Int64;
{ Additive precedence level of a const expression: + - or xor, left-associative;
  multiplicative ops bind tighter (ConstEvalTerm). Fixes the old flat
  right-to-left fold that ignored operator precedence (`2*3+1` gave 8, not 7).
  ConstEval sits ABOVE this with the relational level, so this is no longer the
  entry point -- call ConstEval. }
var r, v: Int64; op: TTokenKind; lTk: TTypeKind; lEid: Integer;
begin
  r := ConstEvalTerm;
  lTk := CEOrdTk; lEid := CEEnumId;
  while CurTok.Kind in [tkPlus, tkMinus, tkOr, tkXor] do
  begin
    op := CurTok.Kind; Next; v := ConstEvalTerm;
    { same rule as `and` in ConstEvalTerm: boolean only when both sides are }
    if (op in [tkOr, tkXor]) and (lTk = tyBoolean) and (CEOrdTk = tyBoolean) then
      lTk := tyBoolean
    { +, -, or and xor are bit-identical on two's-complement, so no arm below
      changes -- but the KIND has to survive them, or `High(QWord) - 1 > 0`
      would compare signed one level up and answer FALSE. Propagating the type
      through the operations that do not need it is the whole reason the
      relational level can trust it. }
    else if TkIsUnsigned64(lTk) or TkIsUnsigned64(CEOrdTk) then
    begin lTk := tyUInt64; lEid := -1; end
    else
    begin lTk := tyInteger; lEid := -1; end;
    case op of
      tkPlus:  r := r + v;
      tkMinus: r := r - v;
      tkOr:    r := r or v;
      tkXor:   r := (r or v) and not (r and v);  { a xor b; the compiler must
                 stay buildable by an older seed that lacks the xor operator }
    end;
  end;
  CEOrdTk := lTk; CEEnumId := lEid;
  Result := r;
end;

function ConstEval: Int64;
{ Evaluate a compile-time constant expression (no code emitted).

  RELATIONAL level, the loosest-binding one in Pascal, so `a + b = c` reads as
  `(a + b) = c`. It had no level at all: `const F = 1 > 0` died on the `>` with
  "Expected: begin", and `const F = (1 > 0) and (2 < 3)` on the `>` inside the
  parens -- while `const F = True and False` worked, so booleans were half
  supported. The idiom this blocks is the portability constant,
  `const Is64 = SizeOf(Pointer) = 8`.

  A relational result is a BOOLEAN, and this evaluator has only Int64, so the
  fact is carried out of band in CEOrdTk for the const declaration to read --
  otherwise the const is declared tyInteger and `WriteLn(F)` prints 1 rather
  than TRUE. }
var r, v: Int64; op: TTokenKind; unsg: Boolean;
begin
  r := ConstEvalAdd;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    { The last of the seven sign-sensitive operations. = and <> compare bit
      patterns and are the same either way; the four ORDERED ones are not, and
      this is where the whole unsigned channel pays off: `high(qword) div bb <
      aa` -- FPC's constexp.pas:321, the expression this feature was opened for
      -- reads a huge positive left operand, which as an Int64 is -1 and would
      be less than everything. }
    unsg := TkIsUnsigned64(CEOrdTk);
    op := CurTok.Kind; Next; v := ConstEvalAdd;
    unsg := unsg or TkIsUnsigned64(CEOrdTk);
    case op of
      tkEq:  if r =  v then r := 1 else r := 0;
      tkNeq: if r <> v then r := 1 else r := 0;
      tkLt:  if (unsg and (UInt64(r) <  UInt64(v))) or
                ((not unsg) and (r <  v)) then r := 1 else r := 0;
      tkLe:  if (unsg and (UInt64(r) <= UInt64(v))) or
                ((not unsg) and (r <= v)) then r := 1 else r := 0;
      tkGt:  if (unsg and (UInt64(r) >  UInt64(v))) or
                ((not unsg) and (r >  v)) then r := 1 else r := 0;
      tkGe:  if (unsg and (UInt64(r) >= UInt64(v))) or
                ((not unsg) and (r >= v)) then r := 1 else r := 0;
    end;
    CEOrdTk := tyBoolean; CEEnumId := -1;
  end;
  Result := r;
end;

function ConstEvalOrdBound: Int64;
{ ONE BOUND of an ordinal subrange -- `lo..hi` in `var n: 1..5`, `set of 1..10`,
  `type T = 'a'..'z'`, `array[0..15]`. Evaluated at the SIMPLE-EXPRESSION level,
  not ConstEval's.

  Deliberately not ConstEval. A subrange bound is an ORDINAL, so a relational
  operator cannot legally appear at its top level -- and ConstEval's relational
  level (added for `const Is64 = SizeOf(Pointer) = 8`) ate the `=` that STARTS
  the initialiser of a typed constant:

    const t: array[0..3] of 0..15 = (%0000, %1000, %0100, %1100);

  parsed the high bound as `15 = (0`, then demanded a ')' and found a ','.
  (fpc-source compiler/cutils.pas:306 -- reverse_byte's nibble table.) Every
  operator a bound can actually contain lives at this level or below, including
  ZenGL's `High(LongWord) shr 1 - 1`.

  One function for all four sites, because they are one construct: the anonymous
  subrange in ParseTypeKind, the named `T = lo..hi` in ParseTypeSection, the
  element of `set of lo..hi`, and an array dimension. }
begin
  ConstEvalOrdBound := ConstEvalAdd;
end;

{ ===== REAL-valued constant expressions =====

  ConstEval above is integer-only, and for a long time the only real a const
  section could hold was a bare literal token recognised by its FIRST token.
  Everything else went to the integer evaluator, which produced four distinct
  wrongs from the one gap (bug-p-const-expressions-are-integer-only):

    const A = 3.14; B = A;        -> B printed 4614253070214989087 (the IEEE
                                     bits, read as an integer). SILENT.
    const A: double = 3;          -> 0.00  (integer 3 stored where bits go)
    const A: double = -3;         -> Nan
    const TwoPi = 3.14 * 2;       -> "unexpected token" at the `*`

  So: a parallel evaluator over Double, entered only when the expression is
  provably real (ConstExprIsFloat). When it is not, the integer path runs
  exactly as before -- which is what keeps every existing const byte-identical. }

function ConstEvalF: Double; forward;

function ConstSymIsFloat(idx: Integer): Boolean;
begin
  ConstSymIsFloat := (idx >= 0) and (Syms[idx].Kind = skConst) and
                     ((Syms[idx].TypeKind = tyDouble) or
                      (Syms[idx].TypeKind = tySingle) or
                      (Syms[idx].TypeKind = tyExtended));
end;

function ConstExprIsFloat: Boolean;
{ Lookahead from the CURRENT token over one const expression: is a real
  involved? A real literal, a `/` (real division always yields a real, so
  `6 / 3` is 2.0 and not 2), or a bare name that already resolves to a real
  const. Stops at the expression's terminator at paren depth 0.

  Deliberately conservative: a false answer costs nothing (the integer path is
  unchanged), a true answer only routes to an evaluator that also handles pure
  integers. Bare names only -- a qualified `unit.RealConst` falls through to the
  integer path and its old behaviour rather than resolving units in lookahead. }
var i, depth: Integer; k: TTokenKind;
begin
  ConstExprIsFloat := False;
  i := TokPos - 1;   { CurTok is Tokens[TokPos-1] }
  depth := 0;
  while i < TokCount do
  begin
    k := Tokens[i].Kind;
    if (k = tkLParen) or (k = tkLBrack) then Inc(depth)
    else if (k = tkRParen) or (k = tkRBrack) then
    begin
      if depth = 0 then Exit;
      Dec(depth);
    end
    else if depth = 0 then
    begin
      if (k = tkSemicolon) or (k = tkComma) or (k = tkEq) then Exit;
    end;
    if k = tkFloat then begin ConstExprIsFloat := True; Exit; end;
    if k = tkSlash then begin ConstExprIsFloat := True; Exit; end;
    if (k = tkIdent) and
       ConstSymIsFloat(FindSym(GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen))) then
      begin ConstExprIsFloat := True; Exit; end;
    Inc(i);
  end;
end;

function ConstEvalFFactor: Double;
{ Primary of a real const expression: unary +/-, a real or integer literal, a
  named const (real -> its bits decoded, integer -> widened), parens. }
var r: Double; idx: Integer;
begin
  r := 0;
  { NB: the parens on the recursive call are required -- a bare own function
    name reads the Result var instead of recursing (project note:
    bare-funcname-is-Result). }
  if CurTok.Kind = tkMinus then begin Next; ConstEvalFFactor := -ConstEvalFFactor(); Exit; end;
  if CurTok.Kind = tkPlus  then begin Next; ConstEvalFFactor :=  ConstEvalFFactor(); Exit; end;
  if CurTok.Kind = tkFloat then
  begin
    r := ExDecBitsToDouble(CurTok.IVal); Next;
  end
  else if CurTok.Kind = tkInteger then
  begin
    r := CurTok.IVal; Next;
  end
  else if CurTok.Kind = tkLParen then
  begin
    Next; r := ConstEvalF(); Expect(tkRParen, ')');
  end
  else if (CurTok.Kind = tkIdent) and ConstSymIsFloat(FindSym(CurTok.SVal)) then
  begin
    idx := FindSym(CurTok.SVal);
    r := ExDecBitsToDouble(Syms[idx].ConstVal);
    Next;
  end
  else
    { Anything this evaluator does not model itself -- SizeOf, Ord/Chr/Succ, an
      integer typecast, an enum member, a unit-qualified or class const -- is an
      INTEGER factor, so hand the same token to the integer evaluator and widen
      its result. ConstEvalFactor and not ConstEval: a factor keeps the
      precedence, where a full expression would swallow the `* 2.5` after it. }
    r := ConstEvalFactor;
  ConstEvalFFactor := r;
end;

function ConstEvalFTerm: Double;
{ Multiplicative level: `*` and `/`. `div`/`mod` are integer operators and are
  deliberately absent -- an expression containing one is not routed here. }
var r, v: Double; op: TTokenKind;
begin
  r := ConstEvalFFactor;
  while (CurTok.Kind = tkStar) or (CurTok.Kind = tkSlash) do
  begin
    op := CurTok.Kind; Next; v := ConstEvalFFactor;
    if op = tkStar then r := r * v
    else
    begin
      if v = 0 then Error('division by zero in a constant expression');
      r := r / v;
    end;
  end;
  ConstEvalFTerm := r;
end;

function ConstEvalF: Double;
{ Additive level: + and -, left-associative. }
var r, v: Double; op: TTokenKind;
begin
  r := ConstEvalFTerm;
  while (CurTok.Kind = tkPlus) or (CurTok.Kind = tkMinus) do
  begin
    op := CurTok.Kind; Next; v := ConstEvalFTerm;
    if op = tkPlus then r := r + v else r := r - v;
  end;
  ConstEvalF := r;
end;

{ Parse one constant initializer value (scalar). A float literal yields its IEEE
  754 bit pattern (carried as Int64, same as AN_FLOAT_LIT); everything else goes
  through the integer ConstEval. Lets a `Double` initializer like 3.14 work. }
function ParseInitVal: Int64;
begin
  { Anything real -- a bare literal, a signed literal (the lexer emits the sign
    as its own token), or a whole expression like `3.14 * 2`, `1 / 3` or an
    alias of a real const -- goes through the real evaluator and yields IEEE
    bits. One path, so `= -2.5` and `= 2.5 * -1` cannot disagree. }
  if ConstExprIsFloat then Result := ExDecDoubleToBits(ConstEvalF())
  else Result := ConstEval;
end;

function ParseInitValTk(tk: TTypeKind): Int64;
{ ParseInitVal where the DESTINATION type is known. A real destination always
  yields IEEE bits, so `const A: Double = 3` stores 3.0 rather than the integer
  3 -- which read back as 0.00, and as Nan for `= -3`. }
begin
  if TypeIsFloat(tk) then ParseInitValTk := ExDecDoubleToBits(ConstEvalF())
  else ParseInitValTk := ParseInitVal;
end;

{ Does a STRING LITERAL, written in a slot of this type, mean "the address of
  the literal's character data"?

  Every string kind, obviously — and a CHAR POINTER, which is the whole of the
  gap this exists to close. `const GP: PChar = '-'` used to fall through to
  ConstEval, where a ONE-character literal is a perfectly good ordinal and an
  ordinal is a perfectly good initialiser for a pointer-sized slot: the
  declaration compiled and the program then dereferenced address 45. Two or more
  characters had no ordinal, so those at least refused, loudly and with an
  unrelated message.

  The char/uint8/int8 triple is IsNodePChar's, deliberately: this predicate and
  that one answer the same question about the same slot at two different times
  (declaration vs. lowering), and the pending-init emitter hands the AN_STR_LIT
  it records straight to IsNodePChar. If they disagreed, the const would parse
  and then store the wrong thing — the identical defect one construct over.

  A plain `Pointer` is NOT included: FPC refuses `const P: Pointer = 'x'`, and
  more to the point pxx's own ASSIGNMENT path refuses to guess there too —
  `p := 'abc'` on a `Pointer` stores the HANDLE, so accepting the literal here
  would make the declaration disagree with the statement that spells it out.
  bug-p-typed-constants-cannot-hold-a-pointer-a-nested-aggregate-or-storage }
function InitValDestTakesStrLit(tk: TTypeKind; ptrElemTk: Integer): Boolean;
begin
  InitValDestTakesStrLit :=
    TypeIsFrozenString(tk) or (tk in [tyString, tyAnsiString, tyShortString]) or
    ((tk = tyPointer) and ((ptrElemTk = Ord(tyChar)) or
                           (ptrElemTk = Ord(tyUInt8)) or
                           (ptrElemTk = Ord(tyInt8))));
end;

{ Recognise the constant-initializer value forms that are NOT plain ordinals, so
  a record-constant field can carry them: a string literal, `@proc`, and `@var`.
  ConstEval cannot evaluate any of these -- and, crucially, does not CONSUME them
  either, so letting one reach ParseInitValTk desyncs the field loop and the next
  iteration reports `expected field name in record constant` pointing at the
  value rather than at the real gap (that misleading message is what this exists
  to prevent).

  The three shapes map onto init kinds the emitter ALREADY implements -- 1 =
  AN_STR_LIT, 2 = AN_PROCADDR, 4 = AN_ADDR of an ident -- which the C frontend
  has been producing for struct initializers all along; only the Pascal side was
  never wired to them. Kinds 1/2/4 leave FOff untouched, so they compose with the
  record-field target the emitter builds when FOff >= 0.

  Returns True and sets kind/val/aux with the tokens consumed; returns False with
  NOTHING consumed, so the caller falls through to the ordinal path unchanged. }
function TryParseInitValForm(tk: TTypeKind; ptrElemTk: Integer;
                             var kind: Integer; var val: Int64; var aux: Integer): Boolean;
var pi, si, ci, mi: Integer;
begin
  TryParseInitValForm := False;
  kind := 0; val := 0; aux := 0;

  { The string arm keys on the DESTINATION type, not on the token: a single-char
    literal in a tyChar field is an ORDINAL, and ConstEvalFactor special-cases it
    as one. Taking it as a string here compiled fine and stored the wrong bytes —
    `C: Char = 'Z'` printed garbage (test_typed_const_record). Same hazard the
    array-of-record path documents a few hundred lines below; it is the token
    being ambiguous, so only the target can decide. }
  if (CurTok.Kind = tkString) and InitValDestTakesStrLit(tk, ptrElemTk) then
  begin
    kind := 1;
    val  := Tokens[TokPos - 1].SOffset;
    aux  := Tokens[TokPos - 1].SLen;
    Next;
    TryParseInitValForm := True;
    Exit;
  end;

  { `@name` -- a link-time address. A routine wins over a variable of the same
    name here for the same reason MatchEligBase does: `@F` names the routine. }
  if (CurTok.Kind = tkAt) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) then
  begin
    { `@TClass.Method` -- the same raw code address the expression-level @ arm
      yields, so a hand-built VMT can be a CONSTANT rather than filled in at
      startup. This is the shape rtl-generics' Generics.Defaults uses. }
    if (TokPos + 2 < TokCount) and (Tokens[TokPos + 1].Kind = tkDot) and
       IsMethodNameTokAt(TokPos + 2) then
    begin
      ci := FindUClass(GetTokenStr(TokPos));
      if ci >= 0 then
      begin
        mi := FindUMeth(ci, GetTokenStr(TokPos + 2));
        if mi >= 0 then
        begin
          kind := 2; val := UMthProc_[mi];
          Next; Next; Next; Next;   { @ Class . Method }
          TryParseInitValForm := True;
          Exit;
        end;
      end;
    end;
    pi := FindProc(GetTokenStr(TokPos));
    if pi >= 0 then
    begin
      kind := 2; val := pi;
      Next; Next;
      TryParseInitValForm := True;
      Exit;
    end;
    { A SIBLING class const or class var, named bare inside the class body:
      `Comparer_Int8_Instance: Pointer = @Comparer_Int8_VMT;` — the shape
      rtl-generics' Generics.Defaults builds its comparer table with. A typed
      class const's storage is registered under a MANGLED key (so two classes'
      same-named consts do not share a slot), so the bare name is invisible to
      FindSym and the `@` arm fell through to the ordinal path, which cannot
      consume `@name` — the section then desynced and reported `unexpected
      token` at the NEXT declaration. Asked through the registry, like every
      other access site (qualified, bare-in-method, const-fold).
      Checked BEFORE the global lookup: a class member shadows a unit-level name
      of the same spelling inside the class body, as in FPC. }
    if ParsingClassConstCi >= 0 then
    begin
      si := FindClassConstSym(ParsingClassConstCi, GetTokenStr(TokPos));
      if si < 0 then si := FindClassVar(ParsingClassConstCi, GetTokenStr(TokPos));
      if si >= 0 then
      begin
        kind := 4; val := si;
        Next; Next;
        TryParseInitValForm := True;
        Exit;
      end;
    end;
    si := FindSym(GetTokenStr(TokPos));
    if si >= 0 then
    begin
      kind := 4; val := si;
      Next; Next;
      TryParseInitValForm := True;
      Exit;
    end;
  end;
end;
