{ pyeval — a real exec()/eval() for the Python subset uforth's PYTHON-bodied
  words are written in (feature-lib-pyexec, engine 1: the reflective
  tree-walker). Correctness reference; a JIT drops in later over the same
  grammar.

  MILESTONE 1 (this unit's initial scope): the 60 "pure-stack" corpus blocks —
  the ones that touch only push/pop/fpush/fpop and NO other vm.* member. That is
  exactly the set of PYTHON-bodied stdlib words (SWAP, OVER, ROT, /, MOD, bit
  ops, ternary min/max, …) that SEGFAULT today because pyexec is a stub.

  Grammar: statements separated by `;`/newline, plus COMPOUND blocks with Python
  indentation — if/elif/else, while (+break), for-in over range()/lists.
  Assignment + augassign, expression statements. Full expression grammar:
  ternary, boolean and/or/not, comparisons (incl. chains), |^& bit ops, <<>>
  shifts, +-*/ // %, unary -/+/~, calls, int/float/hex literals, names,
  True/False/None. Locals live in pyeval's own name/value arrays (LclSet) —
  TPyDict keyed by an AnsiString-boxed Variant is unreliable (see LclSet note).

  Still out of scope (M2/M3, or the bignum tail): attribute access (vm.here),
  subscripts (vm.memory[i]), method calls (vm.define_word), def, arbitrary-
  precision ints (`x & 0xFFFFFFFFFFFFFFFF` as unsigned), f-strings. Rejected with
  a clear error rather than misbehaving.

  Host bridge (M1 convention): a bare call `push(x)` / `pop()` / `fpush(x)` /
  `fpop()` dispatches through PyHostCall(g["vm"], name, args) — the trampoline
  reflects the method on vm's class (case-insensitively) and calls its code
  pointer through a typed proc-pointer cast whose shape matches (RetKind, Arity,
  float-ness). pxx's own codegen supplies each target's ABI; no hand asm. See
  test/test_pyeval_m1.pas for the standalone driver.

  IMPLEMENTATION NOTE — every node evaluator is a PROCEDURE returning through a
  `var res: Variant`, never a Variant-returning function. A Variant function whose
  Result is assigned from another Variant call corrupts the value under the
  current codegen (NRVO/hidden-dest aliasing — see
  project_variant_fn_return_forward_nrvo_corruption / a filed Track A ticket).
  var-out procedures sidestep it entirely. Helpers that BUILD a variant via
  pointer writes (Make*, pyadd_v, …) are safe as functions.

  NOT auto-used by NilPy yet: build + test standalone first so a parse error here
  cannot break every NilPy compile. Wiring exec()->EvalPyStmts is the last step
  of the arc (feature-lib-pyexec build plan step 5). }
unit pyeval;

interface

uses pylib, typinfo, promocore;

{ Run a statement sequence `src` with globals g / locals l (Python's explicit
  exec form; uforth always passes both). Assignments write locals; name reads
  try locals then globals. }
procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);
{ eval(src) — evaluate ONE expression against the same namespaces and yield its
  value. The var-out procedure is the real one (see the IMPLEMENTATION NOTE
  above); the function is the shape a call site can use as an expression, and
  it only ever writes its Result THROUGH the var parameter, never assigns it
  from another Variant call, which is the form that corrupts. }
procedure EvalPyExpr(const src: AnsiString; g: TPyDict; l: TPyDict;
                     var res: Variant);
function pyeval_expr(const src: AnsiString; g: TPyDict; l: TPyDict): Variant;

{ Reflect `name` on vm's class and call it with the variant args held in the
  TPyList `args` (args.at(0..count-1)); the boxed result comes back in `res`.
  Args ride in a TPyList rather than an `array of Variant`: an OPEN array of
  Variant silently miscompiles (indexing/Length reads only the first element —
  Track A ticket), and a class value is just a pointer that lowers cleanly.
  Public so the eventual bound-method path (M3) and tests can share it. }
procedure PyHostCall(vmobj: Pointer; const name: AnsiString;
                     args: TPyList; kwNames: TPyList; var res: Variant);

{ Reverse bridge: invoke a captured pyeval closure (a nested `def` passed to a
  host method as a value) with one Variant argument. NilPy's PyMakeDynCall routes
  here when the callee variant carries the VT_PYCLOSURE tag. }
function PyClosureCall1(const clv: Variant; const a0: Variant): Variant;

{ Pointer-form reverse bridge: a closure stored in a Callable/Pointer field
  (Word.native) and called as `word.native(vm2)`. pyclosure_is tells a closure
  object apart from a real compiled function address so the field-call site can
  branch. }
{ Box a class's RTTI blob address as a VT_CLASSREF variant — how a NilPy CLASS
  used as a VALUE is represented (`cls = A`, `{"a": A}[k](x)`). The AN_CLASSREF
  lowering calls this BY NAME, so it must stay in the interface. }
function PyBoxClassRef(p: Pointer): Variant;
function pyclassref_is(const cb: Variant): Boolean;

function pyclosure_is(p: Pointer): Boolean;
function pyclosure_call_ptr(objptr: Pointer; const a0: Variant): Integer;
{ The same call, keeping the RESULT — what a key function is for. }
function pyclosure_call1(objptr: Pointer; const a0: Variant): Variant;
{ Python's `sorted(xs, key=..., reverse=...)`. Lives here rather than in pylib
  because the key is a CLOSURE and only this unit can invoke one. Stable
  insertion sort: n is small in every censused use (a dict's items), and
  stability is part of sorted()'s contract — equal keys keep their input order.
  key = nil means sort by the elements themselves. }
function sorted(l: TPyList; key: Pointer = nil; reverse: Boolean = False): TPyList;
{ sorted(d, key=..., reverse=...) over a DICT — Python sorts its KEYS. The
  no-key form already reached a list somehow, but `sorted(d, key=f)` had no
  overload to bind to and failed with 'no overload of sorted matches these
  arguments' (bug-nilpy-sorted-over-a-dict-with-a-key-function). Delegates to
  the list form over keylist, so the key/reverse handling stays in one place. }
function sorted(d: TPyDict; key: Pointer = nil; reverse: Boolean = False): TPyList; overload;
{ a str is an iterable too: sorted("cba") -> ['a','b','c'] }
function sorted(const s: AnsiString; key: Pointer = nil; reverse: Boolean = False): TPyList; overload;
{ sorted(<variant>) — a VARIANT argument, which is what a list element, a dict
  value or an unannotated parameter is. Without it the call bound the TPyList
  overload and the compiler inserted an unchecked unwrap, so a variant holding a
  STRING was reinterpreted as a list instance and `for x in ["cab"]: sorted(x)`
  SEGFAULTED. `list` never had the bug because it has such an overload; this is
  the same fix on the pyeval side.
  bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked }
function sorted(const v: Variant; key: Pointer = nil; reverse: Boolean = False): TPyList; overload;

{ min(l)/max(l) over a LIST, WITH Python's `key=`. They live here rather than in
  pylib beside the scalar min/max because `key=` needs PyCallKey1's callable
  dispatch, and `pyeval uses pylib`, not the reverse — the same constraint
  sorted() is here for. The keyless list form moved here whole rather than
  staying in pylib as a sibling, which would have made `min(xs)` ambiguous
  across the two units.

  `min(xs, key=f)` only RESOLVES because the keyword promoter now falls back
  across units (bug-nilpy-keyword-arg-vs-overload-set): `min` is picked from
  pylib's two-Variant scalar form, and the keyword `key` is what re-targets it
  here.

  Python compares the KEYS and returns the ELEMENT, and on a tie returns the
  FIRST — so the scan keeps a strict > / < and never replaces on equality. }
function min(l: TPyList; key: Pointer = nil): Variant; overload;
function max(l: TPyList; key: Pointer = nil): Variant; overload;
{ ...and over a CURSOR: drain, then the routine that already exists. Declared
  AFTER the others on purpose — declaration order decides which class overload
  a VARIANT argument unwraps into, and putting these first made sum(v)/min(v)
  over a variant holding a list bind the cursor parameter and segfault. }
function sorted(it: TPyIter; key: Pointer = nil; reverse: Boolean = False): TPyList; overload;
function min(it: TPyIter; key: Pointer = nil): Variant; overload;
function max(it: TPyIter; key: Pointer = nil): Variant; overload;
{ ...and over a RANGE, which is a sequence rather than a cursor but reaches
  these the same way: materialise once, then the routine that already exists. }
function sorted(r: TPyRange; key: Pointer = nil; reverse: Boolean = False): TPyList; overload;
function min(r: TPyRange; key: Pointer = nil): Variant; overload;
function max(r: TPyRange; key: Pointer = nil): Variant; overload;

{ `map(f, xs)` / `filter(f, xs)` over an arbitrary callable VALUE -- the
  general form beside the existing map(int|str|float, xs) conversion shims.
  Same PyCallKey1 dispatch sorted()'s key= already uses. }
function pymap_call(key: Pointer; l: TPyList): TPyList;
function pyfilter_call(key: Pointer; l: TPyList): TPyList;

{ The LAZY forms — CPython's `map` and `filter` are cursor objects, not lists
  (feature-nilpy-lazy-iterator-objects). The cursor itself lives in pylib; these
  two exist here only because a map cursor has to CALL the callable it stored
  and PyCallKey1 lives in this unit. Installing PyIterCallHook at construction
  is what guarantees the hook is set before any cursor can reach it — there is
  no unit-initialisation order to depend on. }
function pymap_iter(key: Pointer; const v: Variant): TPyIter;
function pyfilter_iter(key: Pointer; const v: Variant): TPyIter;
{ ONE entry each, taking a cursor — the frontend converts the iterable once
  (PyMakeIterOf). There was briefly a spelling per argument type here, because
  the parser arm reaches these through FindProc and it never consults overloads
  ([[project_findproc_by_name_ignores_overloads]]); `range` arriving as a
  fourth iterable shape is what showed that dispatch to be the wrong mechanism
  rather than merely a verbose one. }
function pymap_iter_i(key: Pointer; up: TPyIter): TPyIter;
function pyfilter_iter_i(key: Pointer; up: TPyIter): TPyIter;

{ Build a closure from raw SOURCE text — the compiled frontend's lowering of a
  Python `lambda`: `lambda vm: vm.push(A)` becomes
  pyclosure_src_new('vm', 'return vm.push(A)') with each free name's VALUE
  captured at build time via pyclosure_src_cap (returns the object, so the
  frontend can chain caps as one expression). The result is the same
  magic-sentinel closure object Word.native already dispatches on. }
function pyclosure_src_new(const params, src: AnsiString): Pointer;
function pyclosure_src_cap(obj: Pointer; const name: AnsiString; const v: Variant): Pointer;
function pyclosure_setarity(obj: Pointer; req, tot: Int64): Pointer;

{ BOUND COMPILED FUNCTION: a nested def taken as a value whose captures must
  travel with it (uforth's MARKER: `def restore(v): ...snapshot locals...;
  define_word(name, native=restore)`). The object carries the COMPILED code
  address plus each captured value as a register word; the field-call bridge
  recognises it by magic (like a closure) and calls code(arg, bound...).
  The body runs NATIVELY — no pyeval subset limits. }
function pyboundfn_new(code: Pointer; n: Int64; a0var: Int64): Pointer;
function pyboundfn_bind(obj: Pointer; idx: Int64; v: Int64): Pointer;
{ Declare how many OWN parameters the compiled body takes before its captures.
  Without it the bridge assumes one — see the NOwn note on TBoundFnObj. }
function pyboundfn_setown(obj: Pointer; nown: Int64): Pointer;
{ Declare which bound slots are a lambda's DEFAULTED parameters, so a caller
  that supplies one overrides the default instead of having the argument
  silently dropped — see the NDef note on TBoundFnObj. }
function pyboundfn_setdefaults(obj: Pointer; base, count, varmask: Int64): Pointer;
{ Bind a CLASS capture, taking a reference so it outlives the enclosing call. }
function pyboundfn_bind_obj(obj: Pointer; idx: Int64; p: Pointer): Pointer;
function pyboundfn_is(p: Pointer): Boolean;
{ Is this pointer a heap CALLABLE — a pyeval closure or a lifted bound-fn —
  rather than a bare code address? The call-through-a-Callable-parameter path
  needs the question before it jumps: a lambda's value is an OBJECT, and the
  typed indirect call jumped into the object's own bytes
  (bug-nilpy-callable-annotated-param-segfaults-on-a-heap-callable). }
function pycallable_obj_is(p: Pointer): Boolean;
function pyboundfn_bind_var(obj: Pointer; idx: Int64; const v: Variant): Pointer;
{ Bind a `nonlocal` capture: an 8-byte heap CELL seeded with the current value,
  whose ADDRESS is what travels. The callee's parameter for such a capture is
  declared BY-REF (PyBodyDeclaresNonlocal -> Params[].IsRef), so the body stores
  THROUGH the bound word — and every other binder passes a value, so the body
  wrote through `0` and the process died
  (bug-nilpy-nonlocal-capture-in-an-escaping-closure-fails-to-parse). The cell
  outliving the enclosing frame is the point: it is what lets two calls to one
  escaped closure share state, the way CPython's cell does. Leaked with the
  bound-fn object, like pyboundfn_bind_var's slot — same reasoning, same rarity. }
function pyboundfn_bind_cell(obj: Pointer; idx: Int64; v: Int64): Pointer;
{ A FRAME cell: the one shared storage for an enclosing local that some nested
  def declares `nonlocal`. CPython gives every closure over a frame — and the
  frame itself — ONE cell; pxx used to give each closure a fresh copy, so the
  frame did not see the closure's writes and vice versa
  (bug-nilpy-an-escaped-nonlocal-cell-is-not-shared-with-the-enclosing-frame).
  Allocated once in the enclosing prologue; every access on both sides is an
  indirection through it, and binding it into a closure passes the ADDRESS, so
  the storage survives the frame. Leaked like the bound-fn object it feeds:
  nothing owns the cell once both the frame and the closures are gone, and the
  shapes that reach here are few. Eight bytes whatever the value's width — the
  store may be a 32-bit `mov %eax,(%rcx)` for an inferred int or a full word for
  an Int64/Double, and over-allocating is free while under-allocating would
  scribble the next heap object. }
function pycell_new: Pointer;
function pyboundfn_call_ptr(objptr: Pointer; const a0: Variant): Integer;
{ Same call, but the callee's Variant RESULT is handed back. pyvar_callv* used
  the discarding form, so a lifted def reached through a VALUE always answered
  None — `return inner` then `f(1)`
  (bug-nilpy-returning-a-nested-def-yields-none). Var-out rather than a Variant
  function result: that return convention corrupts through this bridge. }
procedure pyboundfn_callv(objptr: Pointer; const a0: Variant; var res: Variant);
{ The general form: up to three OWN arguments before the bound captures. The
  one-argument wrapper above is the historic entry point. }
procedure pyboundfn_callvn(objptr: Pointer; const a0, a1, a2: Variant;
                           nargs: Int64; var res: Variant);

{ Invoke whatever kind of Python callable a value holds, with one argument or
  none. NilPy has four shapes — a BOUND METHOD (tag 8, {code, receiver}), a
  pyeval CLOSURE, a lifted bound-fn (both magic-tagged heap objects boxed as an
  integer), and a plain compiled def (its code ADDRESS, likewise boxed) — and
  every library that accepts a callable meets all four. The dispatch lived
  inside lib/pcl/tkinter.pas; it belongs here, next to the two object kinds only
  this unit can recognise. }
procedure pycall_value(const cb: Variant; const arg: Variant; withArg: Boolean);

{ The same dispatch, as an EXPRESSION — `f = <anything callable>` then `f(a, b)`.
  pycall_value answers "run this handler"; these answer "what does calling it
  give me", which is what a NilPy dynamic call site needs. All four shapes are
  covered, so the compiler no longer has to guess from the variant's tag which
  bridge to emit: PyMakeDynCall lowers `<variant>(args)` straight to these for
  arities 0..3. A nil payload raises TypeError, as Python does.

  Lives here, not in pylib, because two of the four shapes are objects only this
  unit can recognise — and pyeval is always loaded for a .npy program. }
function pyvar_callv0(const cb: Variant): Variant;
function pyvar_callv1(const cb: Variant; const a0: Variant): Variant;
function pyvar_callv2(const cb: Variant; const a0, a1: Variant): Variant;
{ The four-argument dispatcher. Past arity 3 the old lowering calls through the
  callee's payload as a code ADDRESS — a segfault for a lambda, whose value is
  an object. bug-nilpy-a-four-parameter-lambda-segfaults-when-called }
function pyvar_callv4(const cb: Variant; const a0, a1, a2, a3: Variant): Variant;
function pyvar_callv3(const cb: Variant; const a0, a1, a2: Variant): Variant;

{ Box a callable OBJECT pointer (a lambda's pyeval closure or lifted bound-fn)
  as a variant, so a lambda bound to a NAME is typed tyVariant and the name's
  call site takes the dynamic-call path at all. }
function pyvar_of_callable(p: Pointer): Variant;

implementation

const
  { Ord(TTypeKind) codes (defs.inc); the enum itself is compiler-internal and not
    visible to a builtin unit, so the reflection blob's numeric kinds are used raw. }
  TK_DOUBLE  = 19;
  TK_VARIANT = 22;
  TK_ANSISTR = 23;   { Ord(tyAnsiString) — Exception.Create's one parameter }

  { Token kinds — plain integer consts (not an enum) so they are valid `case`
    labels; pxx rejects Ord(enumconst) as a case label. }
  PK_EOF    = 0;
  PK_NAME   = 1;
  PK_INT    = 2;
  PK_FLOAT  = 3;
  PK_STR    = 4;
  PK_BYTES  = 14;   { b'...' literal — chars are byte values }
  PK_OP     = 5;
  PK_NL     = 6;
  PK_INDENT = 7;
  PK_DEDENT = 8;
  PK_BIGINT = 9;   { integer/hex literal that overflows Int64; TkText = its text }

type
  PPyRec = ^TPyRec;
  TPyRec = record
    VType:   Int64;
    Payload: Int64;
  end;

  { pointer types for boxing/unboxing reflected fields by TTypeKind }
  PLongInt = ^LongInt;
  PByte    = ^Byte;
  PSingle  = ^Single;
  PVariant = ^Variant;

  { Trampoline thunk shapes (Self = leading Pointer). fpush/fpop carry a Double;
    everything else uses the all-Variant family below, which covers a
    NilPy-compiled host (every method param/return is a Variant) and the typed
    push/pop shapes alike — a Variant arg is passed by address, a Variant result
    via the hidden destination, both supplied by pxx's own codegen. }
  TFpushFn = procedure(self: Pointer; v: Double);
  TFpopFn  = function(self: Pointer): Double;

  { Variant-return, N Variant args (N = 0..5). }
  TVFn0 = function(self: Pointer): Variant;
  TVFn1 = function(self: Pointer; const a: Variant): Variant;
  TVFn2 = function(self: Pointer; const a, b: Variant): Variant;
  TVFn3 = function(self: Pointer; const a, b, c: Variant): Variant;
  TVFn4 = function(self: Pointer; const a, b, c, d: Variant): Variant;
  TVFn5 = function(self: Pointer; const a, b, c, d, e: Variant): Variant;
  { void (procedure), N Variant args. }
  TVPr0 = procedure(self: Pointer);
  TVPr1 = procedure(self: Pointer; const a: Variant);
  TVPr2 = procedure(self: Pointer; const a, b: Variant);
  TVPr3 = procedure(self: Pointer; const a, b, c: Variant);
  TVPr4 = procedure(self: Pointer; const a, b, c, d: Variant);
  TVPr5 = procedure(self: Pointer; const a, b, c, d, e: Variant);
  { …and the shapes a NilPy `*args` constructor has: the star slot is a TPyList
    CLASS parameter (a plain pointer), never a Variant, so it cannot ride in a
    TVPr* slot. Only the star-LAST forms exist, which is all Python allows for
    a positional `*args`. }
  { An EXCEPTION subclass inherits Exception.Create(const msg: AnsiString) and
    is constructed through it — a class VALUE holding one is the `raise cls(m)`
    registry shape, so the string arity-1 form has to exist beside the variant
    ones. }
  TSPr1 = procedure(self: Pointer; const s: AnsiString);
  TVPrS1 = procedure(self: Pointer; l: TPyList);
  TVPrS2 = procedure(self: Pointer; const a: Variant; l: TPyList);
  TVPrS3 = procedure(self: Pointer; const a, b: Variant; l: TPyList);
  { AnsiString-return (e.g. next_token_strict), N Variant args (0..2). }
  TSFn0 = function(self: Pointer): AnsiString;
  TSFn1 = function(self: Pointer; const a: Variant): AnsiString;
  TSFn2 = function(self: Pointer; const a, b: Variant): AnsiString;
  TSFn3 = function(self: Pointer; const a, b, c: Variant): AnsiString;
  TSFn4 = function(self: Pointer; const a, b, c, d: Variant): AnsiString;
  TSFn5 = function(self: Pointer; const a, b, c, d, e: Variant): AnsiString;
  { Int64-return, N Variant args. The families used to stop at 2 while the
    Variant and void ones went to 5, so an ordinary three-parameter method was
    refused by ARITY — `pyeval: int-return arity 3 unsupported for put` — with
    all-positional arguments. bug-pyeval-three-param-host-method-unsupported }
  TIFn0 = function(self: Pointer): Int64;
  TIFn1 = function(self: Pointer; const a: Variant): Int64;
  TIFn2 = function(self: Pointer; const a, b: Variant): Int64;
  TIFn3 = function(self: Pointer; const a, b, c: Variant): Int64;
  TIFn4 = function(self: Pointer; const a, b, c, d: Variant): Int64;
  TIFn5 = function(self: Pointer; const a, b, c, d, e: Variant): Int64;
  { Double-return and CLASS/pointer-return, which had no arm at all: a host
    method answering a float or an object died on "unsupported host-call return
    kind" rather than on arity. Same Variant-argument ABI as the families above. }
  TDFn0 = function(self: Pointer): Double;
  TDFn1 = function(self: Pointer; const a: Variant): Double;
  TDFn2 = function(self: Pointer; const a, b: Variant): Double;
  TDFn3 = function(self: Pointer; const a, b, c: Variant): Double;
  TDFn4 = function(self: Pointer; const a, b, c, d: Variant): Double;
  TDFn5 = function(self: Pointer; const a, b, c, d, e: Variant): Double;
  TOFn0 = function(self: Pointer): Pointer;
  TOFn1 = function(self: Pointer; const a: Variant): Pointer;
  TOFn2 = function(self: Pointer; const a, b: Variant): Pointer;
  TOFn3 = function(self: Pointer; const a, b, c: Variant): Pointer;
  TOFn4 = function(self: Pointer; const a, b, c, d: Variant): Pointer;
  TOFn5 = function(self: Pointer; const a, b, c, d, e: Variant): Pointer;
  { Register-family shape: every param travels as ONE pointer-sized value in an
    integer register, so one set of thunk types calls them all —
    int/int64/bool/char/pointer/class directly, AnsiString as its data pointer,
    and a VARIANT as the ADDRESS of its 16-byte slot, which is precisely how pxx
    passes `const a: Variant` (see TVFn1 above: same ABI, spelled differently).

    That last one is why this is not "the pointer family" any more. It used to
    refuse a signature that MIXED a variant with scalars, and uforth's
    `define_word(name: str, native: Optional[Callable], forth_body,
    immediate: bool) -> Word` is exactly that: `native` became a variant when a
    `Callable` parameter did (bug-nilpy-bound-method-cannot-pass-through-a-
    callable-parameter), leaving the signature in neither family and every call
    dead with "unsupported param shape".
    bug-nilpy-pyeval-host-call-refuses-a-mixed-variant-and-scalar-param-shape

    Three RESULT flavours, because a result — unlike an argument — does not fit
    one register for every kind: an Int64 (ordinal / class / pointer), a Variant
    (hidden destination), an AnsiString (managed). The Int64 one used to be the
    only thunk here, so an AnsiString-returning method in this family had its
    string handle boxed by pyvar_of_int and came back as an INTEGER. }
  TPFn0 = function(self: Pointer): Int64;
  TPFn1 = function(self: Pointer; a: Int64): Int64;
  TPFn2 = function(self: Pointer; a, b: Int64): Int64;
  TPFn3 = function(self: Pointer; a, b, c: Int64): Int64;
  TPFn4 = function(self: Pointer; a, b, c, d: Int64): Int64;
  TPFn5 = function(self: Pointer; a, b, c, d, e: Int64): Int64;
  TPVFn0 = function(self: Pointer): Variant;
  TPVFn1 = function(self: Pointer; a: Int64): Variant;
  TPVFn2 = function(self: Pointer; a, b: Int64): Variant;
  TPVFn3 = function(self: Pointer; a, b, c: Int64): Variant;
  TPVFn4 = function(self: Pointer; a, b, c, d: Int64): Variant;
  TPVFn5 = function(self: Pointer; a, b, c, d, e: Int64): Variant;
  TPSFn0 = function(self: Pointer): AnsiString;
  TPSFn1 = function(self: Pointer; a: Int64): AnsiString;
  TPSFn2 = function(self: Pointer; a, b: Int64): AnsiString;
  TPSFn3 = function(self: Pointer; a, b, c: Int64): AnsiString;
  TPSFn4 = function(self: Pointer; a, b, c, d: Int64): AnsiString;
  TPSFn5 = function(self: Pointer; a, b, c, d, e: Int64): AnsiString;

{ ---- variant makers (build via pointer writes -> safe as functions) ---- }

function MakeFloat(d: Double): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 3;               { VT_DOUBLE }
  PDouble(@r^.Payload)^ := d;
end;

function MakeStr(const s: AnsiString): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 6;               { VT_STRING }
  PAnsiString(@r^.Payload)^ := s;
end;

function MakeNone: Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 0; r^.Payload := 0;
end;

{ box a CLASS (its RTTI blob address) as a VT_CLASSREF variant — a NilPy class
  used as a VALUE. No retain: the payload is a static data address, not a heap
  block, so the clear/retain emitters must leave tag 11 alone. }
function PyBoxClassRef(p: Pointer): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 11; r^.Payload := Int64(p);
end;

function pyclassref_is(const cb: Variant): Boolean;
begin
  pyclassref_is := (PPyRec(@cb)^.VType = 11) and (PPyRec(@cb)^.Payload <> 0);
end;

{ box a class/object pointer as a VT_OBJECT variant }
function PyBoxObj(p: Pointer): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 7; r^.Payload := Int64(p);
  { slot takes its own +1 (magic-guarded; see the borrow-everywhere note in
    feature-nilpy-object-reclamation slice 2) }
  PXXObjRetain(p);
end;

{ ---- promotable-int (bignum) integer layer --------------------------------

  Python ints are arbitrary precision. pyeval keeps them as Int64 while they fit
  and PROMOTES to promocore.pas's bignum on overflow — the value's variant simply
  changes shape (VT_INT64 <-> VT_PROMO_INT64). Bignum is a TRANSIENT intermediate
  (the double-cell MATH words compute a 128-bit product then mask/shift it back
  into two 64-bit cells before push); the Forth stack itself stays 64-bit. Only
  the ~13 MATH words ever trigger it, so the Int64 fast path is untouched.

  Overhead is a non-issue: the tree-walker re-parses per call and dominates; the
  promo path engages only on actual overflow. Bitwise `&`/`<<`/`>>` reduce to
  mod/mul/div by powers of two (the only forms the corpus uses); a general bignum
  bitwise-and with a non-power-of-2 mask is unsupported and errors clearly. }

const VT_PROMO = 8193;   { VT_PROMO_INT64_TAG — a bignum boxed in a variant }

function IsPromoV(const v: Variant): Boolean;
begin IsPromoV := PPyRec(@v)^.VType = VT_PROMO; end;

function IsIntishV(const v: Variant): Boolean;
var t: Int64;
begin
  t := PPyRec(@v)^.VType;
  IsIntishV := (t = 1) or (t = 2) or (t = 4) or (t = VT_PROMO);
end;

{ Int64 value of any int-ish variant, promo included (a promo that exceeds
  Int64 narrows mod 2^64, two's complement — callers coerce only where a
  64-bit cell is expected, and the wrap is what keeps the masked-cell idiom an
  identity; the CHECKED PXXPromoToInt64 trapped mid-idiom). }
function PyToI64(const v: Variant): Int64;
var s: array[0..1] of NativeInt;
begin
  if IsPromoV(v) then
  begin
    PXXPromoInit(@s); PXXPromoFromVariant(@s, @v);
    PyToI64 := PXXPromoToInt64Wrap(@s);
    PXXPromoClear(@s);
  end
  else PyToI64 := pyvar_to_int(v);
end;

{ NOTE — these return Variant via a `var res` out-param, NEVER as a function
  result. A Variant function whose Result is assigned from another Variant call
  corrupts the value under the current codegen (the NRVO forward bug — see the
  unit header); a var-out procedure sidesteps it. So `res := pyvar_of_int(x)` and
  `PromoOp(a,b,op,res)` are safe here, where `Result := pyvar_of_int(x)` would not
  be. }

{ a op b through promotable-int; the result auto-demotes to VT_INT64 when it
  fits (PXXPromoToVariant), so bignum never lingers once it is back in range.
  op: 1 add, 2 sub, 3 mul, 4 floordiv, 5 mod, 6 and, 7 or, 8 xor,
  9 shl, 10 shr (the bitwise five have Python two's-complement semantics). }
procedure PromoOp(const a, b: Variant; op: Integer; var res: Variant);
var pa, pb, pr: array[0..1] of NativeInt;
begin
  PXXPromoInit(@pa); PXXPromoInit(@pb); PXXPromoInit(@pr);
  PXXPromoFromVariant(@pa, @a);
  PXXPromoFromVariant(@pb, @b);
  if op = 1 then PXXPromoAdd(@pr, @pa, @pb)
  else if op = 2 then PXXPromoSub(@pr, @pa, @pb)
  else if op = 3 then PXXPromoMul(@pr, @pa, @pb)
  else if op = 4 then PXXPromoDiv(@pr, @pa, @pb)
  else if op = 6 then PXXPromoAnd(@pr, @pa, @pb)
  else if op = 7 then PXXPromoOr(@pr, @pa, @pb)
  else if op = 8 then PXXPromoXor(@pr, @pa, @pb)
  else if op = 9 then PXXPromoShl(@pr, @pa, @pb)
  else if op = 10 then PXXPromoShr(@pr, @pa, @pb)
  else PXXPromoMod(@pr, @pa, @pb);
  PXXPromoToVariant(@res, @pr);
  PXXPromoClear(@pa); PXXPromoClear(@pb); PXXPromoClear(@pr);
end;

function PromoCmp(const a, b: Variant): Int64;
var pa, pb: array[0..1] of NativeInt;
begin
  PXXPromoInit(@pa); PXXPromoInit(@pb);
  PXXPromoFromVariant(@pa, @a); PXXPromoFromVariant(@pb, @b);
  PromoCmp := PXXPromoCmp(@pa, @pb);
  PXXPromoClear(@pa); PXXPromoClear(@pb);
end;

{ 2^k as a variant (Int64 while it fits, else promo). }
procedure Pow2V(k: Int64; var res: Variant);
var s, t: array[0..1] of NativeInt; i: Int64;
begin
  if (k >= 0) and (k < 62) then begin res := pyvar_of_int(Int64(1) shl k); Exit; end;
  PXXPromoInit(@s); PXXPromoInit(@t); PXXPromoFromInt(@s, 1);
  i := 1;
  while i <= k do begin PXXPromoMulInt(@t, @s, 2); PXXPromoCopy(@s, @t); i := i + 1; end;
  PXXPromoToVariant(@res, @s);
  PXXPromoClear(@s); PXXPromoClear(@t);
end;

procedure PyIAdd(const a, b: Variant; var res: Variant);
var ia, ib, s: Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then begin PromoOp(a, b, 1, res); Exit; end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b); s := ia + ib;
  if ((ib > 0) and (s < ia)) or ((ib < 0) and (s > ia)) then PromoOp(a, b, 1, res)
  else res := pyvar_of_int(s);
end;

procedure PyISub(const a, b: Variant; var res: Variant);
var ia, ib, s: Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then begin PromoOp(a, b, 2, res); Exit; end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b); s := ia - ib;
  if ((ib < 0) and (s < ia)) or ((ib > 0) and (s > ia)) then PromoOp(a, b, 2, res)
  else res := pyvar_of_int(s);
end;

procedure PyIMul(const a, b: Variant; var res: Variant);
var ia, ib, r: Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then begin PromoOp(a, b, 3, res); Exit; end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b);
  { the div-based overflow probe below itself SIGFPEs when r = Low(Int64) and
    ia = -1 (hardware idiv overflow), so the -1 multiplier is decided here:
    it overflows only for ib = Low(Int64). }
  if ia = -1 then
  begin
    if ib = Low(Int64) then PromoOp(a, b, 3, res)
    else res := pyvar_of_int(-ib);
    Exit;
  end;
  r := ia * ib;
  if (ia <> 0) and (r div ia <> ib) then PromoOp(a, b, 3, res)
  else res := pyvar_of_int(r);
end;

procedure PyIFloorDiv(const a, b: Variant; var res: Variant);
begin
  if IsPromoV(a) or IsPromoV(b) then PromoOp(a, b, 4, res)
  { Low(Int64) // -1 = 2^63, past Int64 — and the hardware idiv traps SIGFPE
    on exactly that pair, so it must promote BEFORE reaching pyfloordiv_v. }
  else if (pyvar_to_int(a) = Low(Int64)) and (pyvar_to_int(b) = -1) then
    PromoOp(a, b, 4, res)
  else res := pyfloordiv_v(a, b);
end;

procedure PyIMod(const a, b: Variant; var res: Variant);
begin
  if IsPromoV(a) or IsPromoV(b) then PromoOp(a, b, 5, res)
  { same idiv SIGFPE pair as PyIFloorDiv (the result is simply 0) }
  else if (pyvar_to_int(a) = Low(Int64)) and (pyvar_to_int(b) = -1) then
    PromoOp(a, b, 5, res)
  else res := pymod_v(a, b);
end;

{ `a << n` == a * 2^n; routed through PyIMul so overflow auto-promotes. }
procedure PyIShl(const a, nv: Variant; var res: Variant);
var p: Variant;
begin
  Pow2V(PyToI64(nv), p);
  PyIMul(a, p, res);
end;

{ `a >> n` == floor(a / 2^n) (Python arithmetic shift). Promo -> the promo
  runtime's arithmetic shr; Int64 -> the existing sign-propagating shift. }
procedure PyIShr(const a, nv: Variant; var res: Variant);
begin
  if IsPromoV(a) then PromoOp(a, nv, 10, res)
  else res := pyshr_v(a, nv);
end;

{ `a & b`. Both Int64 -> plain and (Int64 AND is already two's complement).
  A promo side -> the promo runtime's bitwise AND (Python two's-complement
  fixed-width view), which makes `-2 & 0xFFFFFFFFFFFFFFFF` the positive
  unsigned reading — the earlier mask-only mod-2^k rewrite kept the SIGN of a
  negative operand (Pascal mod truncates) and broke exactly those cells. }
procedure PyIBitAnd(const a, b: Variant; var res: Variant);
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
    res := pyvar_of_int(pyvar_to_int(a) and pyvar_to_int(b))
  else
    PromoOp(a, b, 6, res);
end;

procedure PyIBitOr(const a, b: Variant; var res: Variant);
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
    res := pyvar_of_int(pyvar_to_int(a) or pyvar_to_int(b))
  else
    PromoOp(a, b, 7, res);
end;

procedure PyIBitXor(const a, b: Variant; var res: Variant);
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
    res := pyvar_of_int(pyvar_to_int(a) xor pyvar_to_int(b))
  else
    PromoOp(a, b, 8, res);
end;

function PyICmp(const a, b: Variant): Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then PyICmp := PromoCmp(a, b)
  else PyICmp := pycmp_v(a, b);
end;

function PyIEq(const a, b: Variant): Boolean;
begin
  if IsPromoV(a) or IsPromoV(b) then PyIEq := PromoCmp(a, b) = 0
  else PyIEq := pyeq_v(a, b);
end;

{ `is` identity, plus the compiled Optional[str] narrowing: a host method typed
  Optional[str] returns None as an EMPTY AnsiString across the trampoline (the
  documented sentinel), so `tok is None` must accept '' — without it EXTRA.UFO's
  `.( ` loop (`tok = vm.next_token(); if tok is None: break`) never saw the end
  of the line and re-spun the tokenizer forever. }
function PyIsIdentity(const a, b: Variant): Boolean;
begin
  if ((PPyRec(@a)^.VType = 0) and (PPyRec(@b)^.VType = 6) and
      (PPyAnsiString(@PPyRec(@b)^.Payload)^ = '')) or
     ((PPyRec(@b)^.VType = 0) and (PPyRec(@a)^.VType = 6) and
      (PPyAnsiString(@PPyRec(@a)^.Payload)^ = '')) then
    PyIsIdentity := True
  else
    PyIsIdentity := PyIEq(a, b);
end;

{ Parse an integer/hex literal that overflowed Int64 into a promo variant. }
procedure PyBigLit(const text: AnsiString; var res: Variant);
var s, t: array[0..1] of NativeInt; i, n: Integer; c: Char; d, base: Int64; isHex: Boolean;
begin
  PXXPromoInit(@s); PXXPromoInit(@t);
  n := Length(text); i := 1; isHex := False;
  if (n >= 2) and (text[1] = '0') and ((text[2] = 'x') or (text[2] = 'X')) then
  begin isHex := True; i := 3; base := 16; end
  else base := 10;
  PXXPromoFromInt(@s, 0);
  while i <= n do
  begin
    c := text[i];
    if c <> '_' then
    begin
      if isHex then
      begin
        if (c >= '0') and (c <= '9') then d := Ord(c) - Ord('0')
        else if (c >= 'a') and (c <= 'f') then d := Ord(c) - Ord('a') + 10
        else d := Ord(c) - Ord('A') + 10;
      end
      else
        d := Ord(c) - Ord('0');
      { s := s*base + d, via a temp to avoid dst/src aliasing }
      PXXPromoMulInt(@t, @s, base);
      PXXPromoAddInt(@s, @t, d);
    end;
    i := i + 1;
  end;
  PXXPromoToVariant(@res, @s);
  PXXPromoClear(@s); PXXPromoClear(@t);
end;

{ ---- host-call trampoline ---- }

{ Case-insensitive method lookup over the class hierarchy. GetMethInfoByName is
  case-SENSITIVE, but Pascal identifiers are case-insensitive and the Python
  corpus spells calls lowercase (`pop`) against methods RTTI records as declared
  (`Pop`), so the bridge must fold case. }
function PyLowerStr(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  Result := s;
  for i := 1 to Length(Result) do
  begin
    c := Result[i];
    if (c >= 'A') and (c <= 'Z') then Result[i] := Chr(Ord(c) + 32);
  end;
end;

{ Case-insensitive string equality with NO allocation — the previous
  lowercase-both-then-compare cost two fresh PXXStrFromLit buffers per call,
  and PyFindMethCI runs once per host-method dispatch (the doloop leak the
  valgrind libc-heap profile attributed to PyHostCall). }
function PyEqCI(const a, b: AnsiString): Boolean;
var i, n: Integer; ca, cb: Char;
begin
  n := Length(a);
  if n <> Length(b) then begin PyEqCI := False; Exit; end;
  for i := 1 to n do
  begin
    ca := a[i]; cb := b[i];
    if (ca >= 'A') and (ca <= 'Z') then ca := Chr(Ord(ca) + 32);
    if (cb >= 'A') and (cb <= 'Z') then cb := Chr(Ord(cb) + 32);
    if ca <> cb then begin PyEqCI := False; Exit; end;
  end;
  PyEqCI := True;
end;

function PyFindMethCI(cls: PClassRTTI; const name: AnsiString): PMethInfo;
var curr: PClassRTTI; meths: PMethInfo; i: Integer;
begin
  PyFindMethCI := nil;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
    begin
      meths := curr^.MethsPtr;
      for i := 0 to Integer(curr^.MethCount) - 1 do
        { The `meths[i].NamePtr^` (^AnsiString deref) to a `const AnsiString`
          param no longer leaks: the isNilPy arg lowering now owns a
          managed-string deref arg via a hidden local (ir.inc,
          bug-a-nilpy-managed-deref-to-const-arg-leaks). The earlier per-site
          `mn := NamePtr^` bind is therefore unnecessary. }
        if PyEqCI(meths[i].NamePtr^, name) then
        begin
          PyFindMethCI := @meths[i];
          Exit;
        end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

{ Reorder `args` so a KEYWORD argument lands on the parameter it names.

  pyeval had the keyword's name and nothing to match it against — the method
  RTTI carried param kinds and arity but no names — so ParseArgs appended
  kwargs POSITIONALLY and `w.insert(chars=x, index=y)` silently bound them
  swapped. Tk discarded the call and printed nothing; no error either way
  (bug-nilpy-pyeval-fallback-still-binds-host-kwargs-by-position). The names now
  live in the second half of the param block (see rtti_emit.inc), which is what
  makes this possible at all.

  `kwNames` is parallel to `args`: entry i is the keyword arg i was written
  with, or '' if it was positional. CPython's rule: positionals fill left to
  right, then each keyword goes to its own parameter.

  A GAP — a keyword targeting parameter 3 while 2 has no value — is refused
  loudly rather than guessed. The marshaller below can only express omitted
  TRAILING params (it tests `(i-1) >= nargs` against a dense list), so a gap has
  no representation; inventing a filler would put this straight back into the
  silent-wrong-argument class the whole ticket is about. }
procedure PyBindHostKwArgs(args, kwNames: TPyList; mi: PMethInfo;
                           n: Integer; const mname: AnsiString);
var i, p, cnt, arity, tgt, nextPos, maxIdx: Integer;
    anyKw: Boolean;
    nm: AnsiString;
    pk: PInt64;
    src: TPyList;
    seen: array[0..31] of Boolean;
begin
  if (kwNames = nil) or (args = nil) then Exit;
  cnt := args.count;
  if (cnt = 0) or (kwNames.count <> cnt) then Exit;
  anyKw := False;
  for i := 0 to cnt - 1 do
    if pystr_of(kwNames.at(i)) <> '' then begin anyKw := True; Break; end;
  if not anyKw then Exit;
  pk := PInt64(mi^.ParamKinds);
  if (pk = nil) or (n <= 0) or (n > 31) then Exit;
  arity := Integer(mi^.Arity);

  for p := 0 to n - 1 do seen[p] := False;
  src := TPyList.Create;
  for i := 0 to cnt - 1 do src.append(args.at(i));

  { positionals first, in the order written }
  nextPos := 0;
  for i := 0 to cnt - 1 do
    if pystr_of(kwNames.at(i)) = '' then
    begin
      if nextPos >= n then
      begin
        src.Free;
        EvalError('too many positional args to ' + mname);
      end;
      args.put(nextPos, src.at(i));
      seen[nextPos] := True;
      Inc(nextPos);
    end;

  { then every keyword, at the index its NAME declares }
  maxIdx := nextPos - 1;
  for i := 0 to cnt - 1 do
  begin
    nm := pystr_of(kwNames.at(i));
    if nm = '' then Continue;
    tgt := -1;
    { param p of the user-visible signature is Params[p+1]; Self is 0 }
    for p := 0 to n - 1 do
      if PyEqCI(PString(NativeInt(pk[arity + p + 1]))^, nm) then
      begin tgt := p; Break; end;
    if tgt < 0 then
    begin
      src.Free;
      EvalError('host method ' + mname + ' has no parameter named ' + nm);
    end;
    if seen[tgt] then
    begin
      src.Free;
      EvalError(mname + ' got multiple values for parameter ' + nm);
    end;
    { `args` keeps its length through this whole permutation, so a target at or
      past it is precisely the GAP case — `put(chars=x)` on `put(index, chars)`
      wants slot 1 while slot 0 has no value. Caught HERE rather than by the
      completeness check below, because reaching that check would mean writing
      out of range first. }
    if tgt >= cnt then
    begin
      src.Free;
      EvalError('cannot bind ' + nm + '= in a call to ' + mname +
                ': it would leave an earlier parameter with no value, and this' +
                ' call shape can only omit TRAILING parameters');
    end;
    args.put(tgt, src.at(i));
    seen[tgt] := True;
    if tgt > maxIdx then maxIdx := tgt;
  end;
  src.Free;

  { every slot up to the highest one used must actually have a value }
  for p := 0 to maxIdx do
    if not seen[p] then
      EvalError('cannot bind keyword args to ' + mname +
                ': parameter ' + pystr_of(Int64(p)) +
                ' has no value and this call shape cannot omit a middle one');
end;

procedure PyHostCall(vmobj: Pointer; const name: AnsiString;
                     args: TPyList; kwNames: TPyList; var res: Variant);
var
  cls: PClassRTTI;
  mi:  PMethInfo;
  fpushfn: TFpushFn; fpopfn: TFpopFn;
  n, nargs: Integer;    { n = user args (Arity - 1) }
  a0, a1, a2, a3, a4: Variant;
  pk: PInt64;
  allVariant: Boolean;
  i: Integer;
  rk: Int64;
  code: Pointer;
  vf0: TVFn0; vf1: TVFn1; vf2: TVFn2; vf3: TVFn3; vf4: TVFn4; vf5: TVFn5;
  vp0: TVPr0; vp1: TVPr1; vp2: TVPr2; vp3: TVPr3; vp4: TVPr4; vp5: TVPr5;
  sf0: TSFn0; sf1: TSFn1; sf2: TSFn2; sf3: TSFn3; sf4: TSFn4; sf5: TSFn5;
  if0: TIFn0; if1: TIFn1; if2: TIFn2; if3: TIFn3; if4: TIFn4; if5: TIFn5;
  df0: TDFn0; df1: TDFn1; df2: TDFn2; df3: TDFn3; df4: TDFn4; df5: TDFn5;
  of0: TOFn0; of1: TOFn1; of2: TOFn2; of3: TOFn3; of4: TOFn4; of5: TOFn5;
  pf0: TPFn0; pf1: TPFn1; pf2: TPFn2; pf3: TPFn3; pf4: TPFn4; pf5: TPFn5;
  pvf0: TPVFn0; pvf1: TPVFn1; pvf2: TPVFn2; pvf3: TPVFn3; pvf4: TPVFn4; pvf5: TPVFn5;
  psf0: TPSFn0; psf1: TPSFn1; psf2: TPSFn2; psf3: TPSFn3; psf4: TPSFn4; psf5: TPSFn5;
  ptrFamily: Boolean;
  pa: array[0..4] of Int64;
  psHold: array[0..4] of AnsiString;   { keep AnsiString-by-value args alive across the call }
  { VARIANT args, whose ADDRESS is what travels. A raw TPyRec, deliberately NOT
    a Variant: this is a marshalling BUFFER, not an owner. The value is owned by
    `args` for the whole call, and a managed Variant local here would release it
    a second time on the way out — the callee's own copy then dangled and the
    block came back as some list's element storage, so calling through it jumped
    into a variant array. `-dPXX_HEAP_DEBUG` says WRITE AFTER FREE. }
  pvHold: array[0..4] of TPyRec;
  pret: Int64;
begin
  cls := GetInstanceRTTI(vmobj);
  if cls = nil then begin writeln('pyeval: no RTTI on vm for host call ', name); Halt(1); end;
  mi := PyFindMethCI(cls, name);
  if mi = nil then begin writeln('pyeval: vm has no method ', name); Halt(1); end;

  n := Integer(mi^.Arity) - 1;   { drop Self }
  PyBindHostKwArgs(args, kwNames, mi, n, name);
  nargs := args.count;
  pk := PInt64(mi^.ParamKinds);
  rk := mi^.RetKind;

  { --- Double param/return shapes (fpush/fpop): the one non-Variant family --- }
  if (rk = 0) and (n = 1) and (pk <> nil) and (pk[1] = TK_DOUBLE) then
  begin
    fpushfn := TFpushFn(mi^.Code);
    fpushfn(vmobj, pyvar_to_float(args.at(0)));
    res := MakeNone;
    Exit;
  end;
  if (rk = TK_DOUBLE) and (n = 0) then
  begin
    fpopfn := TFpopFn(mi^.Code);
    res := MakeFloat(fpopfn(vmobj));
    Exit;
  end;

  { --- general family: every param is a Variant (true for a NilPy-compiled host,
        and for the typed push/pop shapes). Pass args by value (pxx passes each
        `const Variant` by address); box the result per RetKind. --- }
  allVariant := True;
  if pk <> nil then
    for i := 1 to n do
      if pk[i] <> TK_VARIANT then allVariant := False;

  { --- pointer-family shape: an annotated host method whose params are all
        pointer-sized register values (int/int64/bool/char/pointer/class/
        AnsiString-by-value). uforth's `define_word(name: str, native: Callable,
        forth_body, immediate: bool) -> Word` is the driver. Each arg is coerced
        to the Int64 the callee's ABI expects in an integer register; omitted
        trailing params are filled from their per-kind zero default (None -> nil,
        False -> 0), matching Python's defaults. --- }
  if not allVariant then
  begin
    ptrFamily := (n <= 5) and (pk <> nil);
    if ptrFamily then
      for i := 1 to n do
        if not ((pk[i] = 1) or (pk[i] = 2) or (pk[i] = 3) or (pk[i] = 13) or
                (pk[i] = 17) or (pk[i] = 6) or (pk[i] = 23) or
                (pk[i] = TK_VARIANT)) then ptrFamily := False;
    if not ptrFamily then
    begin
      { Name the offending parameter. "unsupported param shape" on its own cost
        a bisect to turn into a sentence, and the shape is the whole question. }
      writeln('pyeval: host method ', name, ' has an unsupported param shape',
              ' (arity ', n, '), kinds:');
      if pk <> nil then
        for i := 1 to n do
          writeln('  param ', i, ' kind ', pk[i]);
      Halt(1);
    end;
    for i := 0 to 4 do pa[i] := 0;
    for i := 1 to n do
    begin
      { A VARIANT param takes the ADDRESS of a 16-byte slot, which is what a
        `const Variant` parameter means at the ABI. pvHold owns the slot for the
        duration of the call — an `args.at()` temporary would not outlive the
        expression, and the callee reads through the pointer. Same reason
        psHold exists for an AnsiString.

        An OMITTED variant param is a real None (VT_EMPTY), NOT the zero the
        other kinds default to: zero would be a NULL address and the callee
        dereferences it unconditionally. `define_word("X", native=w)` omitting
        `forth_body` and `wid` is the everyday case. }
      if pk[i] = TK_VARIANT then
      begin
        if (i - 1) >= nargs then
        begin
          pvHold[i-1].VType := 0;          { VT_EMPTY — a real None, see below }
          pvHold[i-1].Payload := 0;
        end
        else
        begin
          a0 := args.at(i-1);
          pvHold[i-1].VType := PPyRec(@a0)^.VType;      { RAW copy: no retain, }
          pvHold[i-1].Payload := PPyRec(@a0)^.Payload;  { and so no release }
        end;
        pa[i-1] := Int64(NativeInt(@pvHold[i-1]));
      end
      else if (i - 1) >= nargs then
        pa[i-1] := 0            { omitted -> per-kind zero default }
      else if pk[i] = 23 then
      begin
        psHold[i-1] := pystr_of(args.at(i-1));
        pa[i-1] := Int64(NativeInt(Pointer(psHold[i-1])));
      end
      else if (pk[i] = 17) or (pk[i] = 6) then
      begin
        { a Pointer/Callable/class param: a closure -> its object pointer, an
          object/function value -> its payload pointer, None -> nil. }
        a0 := args.at(i-1);
        case PPyRec(@a0)^.VType of
          VT_PYCLOSURE: pa[i-1] := PPyRec(@a0)^.Payload;
          7:            pa[i-1] := PPyRec(@a0)^.Payload;
          0:            pa[i-1] := 0;
        else            pa[i-1] := pyvar_to_int(a0);
        end;
      end
      else
        pa[i-1] := pyvar_to_int(args.at(i-1));   { int/int64/bool/char }
    end;
    code := mi^.Code;
    { The RESULT decides the thunk, the arguments never do — they are all one
      register wide by now. A Variant result comes back through the hidden
      destination and an AnsiString is managed, so neither can be read out of
      the Int64 thunk: `pyvar_of_int` on a string handle used to hand the caller
      an INTEGER, silently. }
    if rk = TK_VARIANT then
    begin
      case n of
        0: begin pvf0 := TPVFn0(code); res := pvf0(vmobj); end;
        1: begin pvf1 := TPVFn1(code); res := pvf1(vmobj, pa[0]); end;
        2: begin pvf2 := TPVFn2(code); res := pvf2(vmobj, pa[0], pa[1]); end;
        3: begin pvf3 := TPVFn3(code); res := pvf3(vmobj, pa[0], pa[1], pa[2]); end;
        4: begin pvf4 := TPVFn4(code); res := pvf4(vmobj, pa[0], pa[1], pa[2], pa[3]); end;
        5: begin pvf5 := TPVFn5(code); res := pvf5(vmobj, pa[0], pa[1], pa[2], pa[3], pa[4]); end;
      end;
      Exit;
    end;
    if rk = 23 then
    begin
      case n of
        0: begin psf0 := TPSFn0(code); res := MakeStr(psf0(vmobj)); end;
        1: begin psf1 := TPSFn1(code); res := MakeStr(psf1(vmobj, pa[0])); end;
        2: begin psf2 := TPSFn2(code); res := MakeStr(psf2(vmobj, pa[0], pa[1])); end;
        3: begin psf3 := TPSFn3(code); res := MakeStr(psf3(vmobj, pa[0], pa[1], pa[2])); end;
        4: begin psf4 := TPSFn4(code); res := MakeStr(psf4(vmobj, pa[0], pa[1], pa[2], pa[3])); end;
        5: begin psf5 := TPSFn5(code); res := MakeStr(psf5(vmobj, pa[0], pa[1], pa[2], pa[3], pa[4])); end;
      end;
      Exit;
    end;
    case n of
      0: begin pf0 := TPFn0(code); pret := pf0(vmobj); end;
      1: begin pf1 := TPFn1(code); pret := pf1(vmobj, pa[0]); end;
      2: begin pf2 := TPFn2(code); pret := pf2(vmobj, pa[0], pa[1]); end;
      3: begin pf3 := TPFn3(code); pret := pf3(vmobj, pa[0], pa[1], pa[2]); end;
      4: begin pf4 := TPFn4(code); pret := pf4(vmobj, pa[0], pa[1], pa[2], pa[3]); end;
      5: begin pf5 := TPFn5(code); pret := pf5(vmobj, pa[0], pa[1], pa[2], pa[3], pa[4]); end;
    end;
    { box the result by its kind: class/pointer -> VT_OBJECT; ordinal -> int;
      void (rk=0) -> None. }
    if (rk = 6) or (rk = 17) then
    begin
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := pret;
      PXXObjRetain(Pointer(NativeInt(pret)));   { slot owns +1 (magic-guarded) }
    end
    else if rk = 0 then res := MakeNone
    else res := pyvar_of_int(pret);
    Exit;
  end;
  if nargs < n then
  begin writeln('pyeval: too few args to ', name, ' (need ', n, ', got ', nargs, ')'); Halt(1); end;

  if n >= 1 then a0 := args.at(0);
  if n >= 2 then a1 := args.at(1);
  if n >= 3 then a2 := args.at(2);
  if n >= 4 then a3 := args.at(3);
  if n >= 5 then a4 := args.at(4);
  { A host method (push/define_word/…) expects 64-bit cells: coerce any bignum
    arg back to Int64 so a promo never leaks onto the Forth stack. The double-cell
    words mask to 64 bits before push; this is the defensive belt. }
  if IsPromoV(a0) then a0 := pyvar_of_int(PyToI64(a0));
  if IsPromoV(a1) then a1 := pyvar_of_int(PyToI64(a1));
  if IsPromoV(a2) then a2 := pyvar_of_int(PyToI64(a2));
  if IsPromoV(a3) then a3 := pyvar_of_int(PyToI64(a3));
  if IsPromoV(a4) then a4 := pyvar_of_int(PyToI64(a4));
  code := mi^.Code;

  { Variant return }
  if rk = TK_VARIANT then
  begin
    case n of
      0: begin vf0 := TVFn0(code); res := vf0(vmobj); end;
      1: begin vf1 := TVFn1(code); res := vf1(vmobj, a0); end;
      2: begin vf2 := TVFn2(code); res := vf2(vmobj, a0, a1); end;
      3: begin vf3 := TVFn3(code); res := vf3(vmobj, a0, a1, a2); end;
      4: begin vf4 := TVFn4(code); res := vf4(vmobj, a0, a1, a2, a3); end;
      5: begin vf5 := TVFn5(code); res := vf5(vmobj, a0, a1, a2, a3, a4); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    Exit;
  end;

  { void return }
  if rk = 0 then
  begin
    case n of
      0: begin vp0 := TVPr0(code); vp0(vmobj); end;
      1: begin vp1 := TVPr1(code); vp1(vmobj, a0); end;
      2: begin vp2 := TVPr2(code); vp2(vmobj, a0, a1); end;
      3: begin vp3 := TVPr3(code); vp3(vmobj, a0, a1, a2); end;
      4: begin vp4 := TVPr4(code); vp4(vmobj, a0, a1, a2, a3); end;
      5: begin vp5 := TVPr5(code); vp5(vmobj, a0, a1, a2, a3, a4); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    res := MakeNone;
    Exit;
  end;

  { AnsiString return (next_token_strict, next_token, …) — arity 0..5 }
  if rk = 23 then
  begin
    case n of
      0: begin sf0 := TSFn0(code); res := MakeStr(sf0(vmobj)); end;
      1: begin sf1 := TSFn1(code); res := MakeStr(sf1(vmobj, a0)); end;
      2: begin sf2 := TSFn2(code); res := MakeStr(sf2(vmobj, a0, a1)); end;
      3: begin sf3 := TSFn3(code); res := MakeStr(sf3(vmobj, a0, a1, a2)); end;
      4: begin sf4 := TSFn4(code); res := MakeStr(sf4(vmobj, a0, a1, a2, a3)); end;
      5: begin sf5 := TSFn5(code); res := MakeStr(sf5(vmobj, a0, a1, a2, a3, a4)); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    Exit;
  end;

  { Int64 / Integer / Boolean / Char return — arity 0..5.

    An implicitly-returning NilPy method lands HERE, not in the void arm: a def
    with no `return` is typed Integer, which is why an ordinary
    `def put(self, a, b, c)` was refused as "int-return arity 3" even though it
    returns nothing. That typing is its own, separately tracked gap
    (feature-nilpy-none-variant); what this arm owes it is the arity. }
  if (rk = 13) or (rk = 1) or (rk = 2) or (rk = 3) then
  begin
    case n of
      0: begin if0 := TIFn0(code); res := pyvar_of_int(if0(vmobj)); end;
      1: begin if1 := TIFn1(code); res := pyvar_of_int(if1(vmobj, a0)); end;
      2: begin if2 := TIFn2(code); res := pyvar_of_int(if2(vmobj, a0, a1)); end;
      3: begin if3 := TIFn3(code); res := pyvar_of_int(if3(vmobj, a0, a1, a2)); end;
      4: begin if4 := TIFn4(code); res := pyvar_of_int(if4(vmobj, a0, a1, a2, a3)); end;
      5: begin if5 := TIFn5(code); res := pyvar_of_int(if5(vmobj, a0, a1, a2, a3, a4)); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    { A BOOLEAN return shares this family's ABI but not its Python type: boxed
      as an int it printed `1` where CPython prints `True`. Re-boxed by the
      declared kind after the call, so the one register-shaped family still
      serves all four kinds. }
    if rk = 2 then res := pyvar_of_bool(pyvar_to_int(res) <> 0);
    Exit;
  end;

  { Double / Single return — arity 0..5. No arm at all before this: a host
    method answering a float died on "unsupported host-call return kind". }
  if (rk = 19) or (rk = 18) then
  begin
    case n of
      0: begin df0 := TDFn0(code); res := df0(vmobj); end;
      1: begin df1 := TDFn1(code); res := df1(vmobj, a0); end;
      2: begin df2 := TDFn2(code); res := df2(vmobj, a0, a1); end;
      3: begin df3 := TDFn3(code); res := df3(vmobj, a0, a1, a2); end;
      4: begin df4 := TDFn4(code); res := df4(vmobj, a0, a1, a2, a3); end;
      5: begin df5 := TDFn5(code); res := df5(vmobj, a0, a1, a2, a3, a4); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    Exit;
  end;

  { CLASS / pointer return — arity 0..5, boxed as VT_OBJECT with the slot taking
    its own reference, exactly as the no-argument fast path above does. This is
    what lets a reflected call hand back an object the next call can reach. }
  if (rk = 6) or (rk = 17) then
  begin
    pret := nil;
    case n of
      0: begin of0 := TOFn0(code); pret := of0(vmobj); end;
      1: begin of1 := TOFn1(code); pret := of1(vmobj, a0); end;
      2: begin of2 := TOFn2(code); pret := of2(vmobj, a0, a1); end;
      3: begin of3 := TOFn3(code); pret := of3(vmobj, a0, a1, a2); end;
      4: begin of4 := TOFn4(code); pret := of4(vmobj, a0, a1, a2, a3); end;
      5: begin of5 := TOFn5(code); pret := of5(vmobj, a0, a1, a2, a3, a4); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := pret;
    PXXObjRetain(Pointer(NativeInt(pret)));
    Exit;
  end;

  writeln('pyeval: unsupported host-call return kind ', rk, ' for ', name);
  Halt(1);
end;

{ ---- field (attribute) reflection: M2 ---- }

{ Read field `name` on `obj` and box it by its TTypeKind. Scalar kinds unbox to
  int/bool/float; a string field to a str variant; anything else (a class-valued
  field like memory/stack) is boxed as VT_OBJECT holding the field's stored
  pointer, so a following subscript / method call can reach it. }
procedure PyFieldGet(obj: Pointer; const name: AnsiString; var res: Variant);
var
  cls: PClassRTTI;
  kind: Int64;
  p: Pointer;
  r: PPyRec;
  mi: PMethInfo;
  noArgs: TPyList;
  gname: AnsiString;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then
  begin
    { A @property compiles to a METHOD, so an attribute read that misses the
      fields must invoke a 0-arg method of that name (uforth's `vm.base` — a
      miss here read the dynattr store instead, yielded None, and `ud % base`
      divided by zero). Arity 1 = self only, the getter shape; anything wider
      is a real method and stays a plain (dynattr) miss so `vm.push` as a
      value is not suddenly a call. }
    gname := '__prop_get_' + name;      { the @property getter's mangled name }
    mi := PyFindMethCI(cls, gname);
    if mi = nil then
    begin
      gname := name;
      mi := PyFindMethCI(cls, name);
    end;
    if (mi <> nil) and (mi^.Arity = 1) then
    begin
      noArgs := TPyList.Create;
      PyHostCall(obj, gname, noArgs, TPyList(nil), res);
      noArgs.Free;
      Exit;
    end;
    res := pydynattr_get(obj, name);
    Exit;
  end;
  r := PPyRec(@res);
  case kind of
    1: res := pyvar_of_int(PLongInt(p)^);        { tyInteger — 4-byte }
    2: res := pyvar_of_bool(PByte(p)^ <> 0);     { tyBoolean }
    3: res := pyvar_of_int(PByte(p)^);           { tyChar }
    13: res := pyvar_of_int(PInt64(p)^);         { tyInt64 }
    18: res := MakeFloat(PSingle(p)^);           { tySingle }
    19: res := MakeFloat(PDouble(p)^);           { tyDouble }
    22: res := PVariant(p)^;                      { tyVariant — copy the slot }
    23: res := MakeStr(PAnsiString(p)^);          { tyAnsiString (deref arg owned by the isNilPy arg lowering) }
  else
    { class / aggregate field: the slot holds an object pointer; expose it as a
      VT_OBJECT so subscripts and method calls can reach the container. A field
      read BORROWS — the field keeps its own ref — so the variant must take +1
      (no-op on unheadered Pascal instances; the variant's scope-exit release
      balances it once the object arms are live). }
    r^.VType := 7; r^.Payload := PInt64(p)^;
    PXXObjRetain(Pointer(NativeInt(r^.Payload)));
  end;
end;

{ Write `val` into scalar/string field `name` on `obj`, coercing to the field's
  kind. Object-typed fields are not writable this way in M2 (would need lifetime
  handling); rejected. }
procedure PyFieldSet(obj: Pointer; const name: AnsiString; const val: Variant);
var
  cls: PClassRTTI;
  kind: Int64;
  p: Pointer;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then begin pydynattr_set(obj, name, val); Exit; end;
  case kind of
    1: PLongInt(p)^ := pyvar_to_int(val);
    2: if pyvar_to_bool(val) then PByte(p)^ := 1 else PByte(p)^ := 0;
    3: PByte(p)^ := pyvar_to_int(val) and $FF;
    13: PInt64(p)^ := pyvar_to_int(val);
    18: PSingle(p)^ := pyvar_to_float(val);
    19: PDouble(p)^ := pyvar_to_float(val);
    22: PVariant(p)^ := val;
    23: PAnsiString(p)^ := pystr_of(val);
  else
    begin writeln('pyeval: cannot assign to object-typed attribute ', name); Halt(1); end;
  end;
end;

{ container[index] read. `container` is a VT_OBJECT variant; a list yields the
  element (Python negative indexing), a bytes object an int, a dict the value at
  the key. Slices are not handled here (M2b). }
procedure PySubscriptGet(const container: Variant; const index: Variant;
                         var res: Variant);
var o: TObject; li: TPyList; by: TPyBytes; di: TPyDict; i, n: Int64;
    s: AnsiString;
begin
  if PPyRec(@container)^.VType = 6 then
  begin
    { s[i] — a one-character string, Python indexing (the pictured-numeric
      digit table `'0123456789...'[digit]` comes through here) }
    s := PPyAnsiString(@PPyRec(@container)^.Payload)^;
    n := Length(s); i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then
    raise IndexError.Create('string index out of range');
    res := MakeStr(s[i + 1]);
    Exit;
  end;
  if PPyRec(@container)^.VType <> 7 then
  raise TypeError.Create(Chr(39) + PyVarTypeName(pyvartag(container)) + Chr(39) +
                           ' object is not subscriptable');
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); n := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then raise IndexError.Create('list index out of range');
    res := li.at(i);
  end
  else if o is TPyBytes then
  begin
    by := TPyBytes(o); n := by.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then raise IndexError.Create('index out of range');
    res := pyvar_of_int(by.at(i));
  end
  else if o is TPyDict then
  begin
    di := TPyDict(o);
    res := di.fetch(index);
  end
  else
    raise TypeError.Create(Chr(39) + pytype_name_v(container) + Chr(39) +
         ' object is not subscriptable');
end;

{ container[index] = val }
procedure PySubscriptSet(const container: Variant; const index: Variant;
                         const val: Variant);
var o: TObject; li: TPyList; by: TPyBytes; di: TPyDict; i, n: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  raise TypeError.Create(Chr(39) + PyVarTypeName(pyvartag(container)) + Chr(39) +
                           ' object does not support item assignment');
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); n := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then
      raise IndexError.Create('list assignment index out of range');
    li.put(i, val);
  end
  else if o is TPyBytes then
  begin
    by := TPyBytes(o); n := by.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then raise IndexError.Create('index out of range');
    by.put(i, pyvar_to_int(val) and $FF);
  end
  else if o is TPyDict then
  begin
    di := TPyDict(o);
    di.store(index, val);
  end
  else
    raise TypeError.Create(Chr(39) + pytype_name_v(container) + Chr(39) +
         ' object does not support item assignment');
end;

{ container[lo:hi] = value. bytes take a variant RHS holding bytes; lists take a
  list RHS. Omitted bounds arrive as PY_SLICE_OMIT. }
procedure PySliceSet(const container: Variant; lo, hi: Int64; const val: Variant);
var o: TObject;
begin
  if PPyRec(@container)^.VType <> 7 then
  raise TypeError.Create(Chr(39) + PyVarTypeName(pyvartag(container)) + Chr(39) +
                           ' object does not support slice assignment');
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyBytes then
    pybytes_setslice_v(TPyBytes(o), lo, hi, val)
  else if o is TPyList then
    pylist_setslice(TPyList(o), lo, hi, TPyList(pyvarobj(val)))
  else
    raise TypeError.Create(Chr(39) + pytype_name_v(container) + Chr(39) +
         ' object does not support slice assignment');
end;

{ del container[index] }
procedure PyDelSubscript(const container: Variant; const index: Variant);
var o: TObject; li: TPyList; di: TPyDict; i, nn: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  raise TypeError.Create(Chr(39) + PyVarTypeName(pyvartag(container)) + Chr(39) +
                           ' object does not support item deletion');
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); nn := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + nn;
    if (i < 0) or (i >= nn) then raise IndexError.Create('list index out of range');
    li.pop_at(i);
  end
  else if o is TPyDict then
    TPyDict(o).remove(index)
  else
    raise TypeError.Create(Chr(39) + pytype_name_v(container) + Chr(39) +
         ' object does not support item deletion');
end;

{ ---- tokenizer ---- }

var
  { token arrays (module-global; EvalPyStmts is not reentrant across a single
    source, which is fine — uforth runs one block body at a time) }
  TkKind:  array of Integer;
  TkText:  array of AnsiString;
  TkInt:   array of Int64;
  TkFloat: array of Double;
  TkN:     Integer;

  Src:  AnsiString;
  SLen: Integer;
  Pos:  Integer;      { 1-based cursor into Src during tokenize }
  Cur:  Integer;      { current token index during eval }

  EnvG: TPyDict;   { host-provided globals (read-only here); holds "vm" etc. }
  { host-provided LOCALS — exec(src, g, l)'s third argument. Consulted on a name
    MISS rather than copied in at entry: copying would put every pre-existing
    entry into LclNames, and LclFind is a linear scan, so seeding an N-entry
    namespace would make every name lookup in the exec'd source O(N). uforth
    calls exec in a hot loop against a namespace that grows across a run, so
    that cost is not hypothetical. A miss here is one dict indexof.
    bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent }
  EnvL: TPyDict;

  { Local scope kept as parallel arrays rather than a TPyDict: TPyDict keyed by a
    Variant boxed from an AnsiString is unreliable (store/indexof box the string
    inconsistently, and a heap key's bytes go stale — see the boxing landmine in
    pylib). Owned AnsiString names compared with `=` are exact and stable. }
  LclNames: array of AnsiString;
  LclVals:  array of Variant;
  LclN:     Integer;

  { Control-flow state. `Executing` gates side effects: while walking a
    not-taken branch (if/elif/else, or a while/for that skips its body once to
    advance past it) the grammar is still consumed but calls don't dispatch,
    stores don't write, and undefined names resolve to None instead of erroring.
    `BreakFlag` unwinds the innermost loop. }
  Executing: Boolean;
  BreakFlag: Boolean;
  { set by ExecStatement when the statement was a compound block (if/while/for):
    such a statement self-terminates at its DEDENT, so no `;`/NL separator follows. }
  StmtWasCompound: Boolean;

  { nested `def` functions: name -> (body token position, comma-joined params).
    A call saves/restores the local scope + cursor for a fresh function frame. }
  FnName:    array of AnsiString;
  FnBodyPos: array of Integer;
  FnParams:  array of AnsiString;
  FnN:       Integer;
  ReturnFlag:  Boolean;
  ReturnValue: Variant;

procedure AddTok(kind: Integer; const text: AnsiString; iv: Int64; fv: Double);
begin
  if TkN >= Length(TkKind) then
  begin
    if Length(TkKind) = 0 then SetLength(TkKind, 64)
    else SetLength(TkKind, Length(TkKind) * 2);
    SetLength(TkText, Length(TkKind));
    SetLength(TkInt, Length(TkKind));
    SetLength(TkFloat, Length(TkKind));
  end;
  TkKind[TkN] := kind;
  TkText[TkN] := text;
  TkInt[TkN] := iv;
  TkFloat[TkN] := fv;
  TkN := TkN + 1;
end;

function IsDigit(c: Char): Boolean;
begin
  IsDigit := (c >= '0') and (c <= '9');
end;

function IsHexDigit(c: Char): Boolean;
begin
  IsHexDigit := IsDigit(c) or ((c >= 'a') and (c <= 'f')) or
                ((c >= 'A') and (c <= 'F'));
end;

function IsIdentStart(c: Char): Boolean;
begin
  IsIdentStart := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))
                  or (c = '_');
end;

function IsIdentChar(c: Char): Boolean;
begin
  IsIdentChar := IsIdentStart(c) or IsDigit(c);
end;

function HexVal(c: Char): Int64;
begin
  if IsDigit(c) then HexVal := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then HexVal := Ord(c) - Ord('a') + 10
  else HexVal := Ord(c) - Ord('A') + 10;
end;

procedure TokError(const msg: AnsiString);
begin
  writeln('pyeval tokenizer: ', msg);
  Halt(1);
end;

function PyEscQuote(const s: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    if s[i] = '''' then Result := Result + '''''' else Result := Result + s[i];
  end;
end;

{ Source-level f-string desugar: rewrite `f'lit{expr:spec}lit'` into
  `('lit' + __fmt(expr, 'spec') + 'lit')` before tokenizing, so the normal
  expression grammar evaluates the holes. Normal string literals are copied
  verbatim (never rewritten). Nested brackets inside a hole are respected;
  `{{`/`}}` are literal braces; a `!r`/`!s`/`!a` conversion is parsed and
  ignored. Keeps f-strings out of the tokenizer/evaluator entirely. }
function PreprocessFStrings(const src: AnsiString): AnsiString;
var
  i, n, depth: Integer;
  c, q, ch: Char;
  outp, seg, hole, spec: AnsiString;
  prevIdent, needPlus: Boolean;
begin
  outp := ''; i := 1; n := Length(src); prevIdent := False;
  while i <= n do
  begin
    c := src[i];
    { normal string literal — copy verbatim }
    if (c = '''') or (c = '"') then
    begin
      q := c; outp := outp + c; i := i + 1;
      while (i <= n) and (src[i] <> q) do
      begin
        if (src[i] = '\') and (i < n) then begin outp := outp + src[i]; i := i + 1; end;
        outp := outp + src[i]; i := i + 1;
      end;
      if i <= n then begin outp := outp + src[i]; i := i + 1; end;
      prevIdent := False;
      continue;
    end;
    { f-string prefix (f/F not part of a longer identifier, followed by a quote) }
    if ((c = 'f') or (c = 'F')) and (not prevIdent) and (i < n)
       and ((src[i+1] = '''') or (src[i+1] = '"')) then
    begin
      q := src[i+1]; i := i + 2;
      outp := outp + '(';
      seg := ''; needPlus := False;
      while (i <= n) and (src[i] <> q) do
      begin
        ch := src[i];
        if (ch = '{') and (i < n) and (src[i+1] = '{') then begin seg := seg + '{'; i := i + 2; end
        else if (ch = '}') and (i < n) and (src[i+1] = '}') then begin seg := seg + '}'; i := i + 2; end
        else if ch = '{' then
        begin
          if seg <> '' then
          begin
            if needPlus then outp := outp + ' + ';
            outp := outp + '''' + PyEscQuote(seg) + '''';
            needPlus := True; seg := '';
          end;
          i := i + 1; hole := ''; depth := 0;
          while (i <= n) and not ((depth = 0) and
                 ((src[i] = '}') or (src[i] = ':') or (src[i] = '!'))) do
          begin
            if (src[i] = '(') or (src[i] = '[') or (src[i] = '{') then depth := depth + 1
            else if (src[i] = ')') or (src[i] = ']') or (src[i] = '}') then depth := depth - 1;
            hole := hole + src[i]; i := i + 1;
          end;
          spec := '';
          if (i <= n) and (src[i] = '!') then
          begin i := i + 1; if i <= n then i := i + 1; end;   { !r/!s/!a — ignored }
          if (i <= n) and (src[i] = ':') then
          begin
            i := i + 1;
            while (i <= n) and (src[i] <> '}') do begin spec := spec + src[i]; i := i + 1; end;
          end;
          if (i <= n) and (src[i] = '}') then i := i + 1;
          if needPlus then outp := outp + ' + ';
          outp := outp + '__fmt(' + hole + ', ''' + PyEscQuote(spec) + ''')';
          needPlus := True;
        end
        else begin seg := seg + ch; i := i + 1; end;
      end;
      if i <= n then i := i + 1;   { closing quote }
      if seg <> '' then
      begin
        if needPlus then outp := outp + ' + ';
        outp := outp + '''' + PyEscQuote(seg) + '''';
        needPlus := True;
      end;
      if not needPlus then outp := outp + '''''';   { empty f-string }
      outp := outp + ')';
      prevIdent := False;
    end
    else
    begin
      outp := outp + c;
      prevIdent := IsIdentChar(c);
      i := i + 1;
    end;
  end;
  Result := outp;
end;

procedure Tokenize(const s: AnsiString);
var
  c, c2, hc: Char;
  start, hv, hk: Integer;
  ident, op, slit: AnsiString;
  iv, dg: Int64;
  fv, scale: Double;
  isFloat, ovf: Boolean;
  atLineStart: Boolean;
  col, sp: Integer;
  indent: array of Integer;   { indentation stack; indent[0] = 0 }
  nInd: Integer;
begin
  Src := s; SLen := Length(s); Pos := 1; TkN := 0;
  SetLength(indent, 64); indent[0] := 0; nInd := 1;
  atLineStart := True;
  while Pos <= SLen do
  begin
    { Python offside rule: at the start of each logical (non-blank, non-comment)
      line, compare leading-whitespace width to the indent stack and emit
      INDENT / DEDENT tokens. Blank and comment-only lines never change indent. }
    if atLineStart then
    begin
      sp := Pos; col := 0;
      while (sp <= SLen) and ((Src[sp] = ' ') or (Src[sp] = #9)) do
      begin col := col + 1; sp := sp + 1; end;
      { blank line or comment-only line: consume through its newline, no change }
      if (sp > SLen) or (Src[sp] = #10) or (Src[sp] = #13) or (Src[sp] = '#') then
      begin
        while (Pos <= SLen) and (Src[Pos] <> #10) do Pos := Pos + 1;
        if Pos <= SLen then Pos := Pos + 1;   { the newline }
        continue;   { still atLineStart }
      end;
      Pos := sp;   { skip the leading whitespace }
      if col > indent[nInd-1] then
      begin
        if nInd >= Length(indent) then SetLength(indent, Length(indent) * 2);
        indent[nInd] := col; nInd := nInd + 1;
        AddTok(PK_INDENT, '', 0, 0);
      end
      else
        while (nInd > 1) and (col < indent[nInd-1]) do
        begin nInd := nInd - 1; AddTok(PK_DEDENT, '', 0, 0); end;
      atLineStart := False;
    end;
    c := Src[Pos];
    if c = #10 then
    begin
      AddTok(PK_NL, '', 0, 0);
      Pos := Pos + 1;
      atLineStart := True;
      continue;
    end;
    { whitespace (not newline) }
    if (c = ' ') or (c = #9) or (c = #13) then
    begin
      Pos := Pos + 1;
      continue;
    end;
    { comment (to end of line; the newline is handled at the top of the loop) }
    if c = '#' then
    begin
      while (Pos <= SLen) and (Src[Pos] <> #10) do Pos := Pos + 1;
      continue;
    end;
    { number }
    if IsDigit(c) then
    begin
      { hex — overflow past Int64 becomes a promo big-literal token }
      if (c = '0') and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = 'x') or (Src[Pos+1] = 'X')) then
      begin
        start := Pos;
        Pos := Pos + 2;
        iv := 0; ovf := False;
        if (Pos > SLen) or (not IsHexDigit(Src[Pos])) then
          TokError('malformed hex literal');
        while (Pos <= SLen) and (IsHexDigit(Src[Pos]) or (Src[Pos] = '_')) do
        begin
          if Src[Pos] <> '_' then
          begin
            dg := HexVal(Src[Pos]);
            if iv > (High(Int64) - dg) div 16 then ovf := True;
            if not ovf then iv := iv * 16 + dg;
          end;
          Pos := Pos + 1;
        end;
        if ovf then AddTok(PK_BIGINT, Copy(Src, start, Pos - start), 0, 0)
        else AddTok(PK_INT, '', iv, 0);
        continue;
      end;
      { decimal int or float }
      start := Pos;
      iv := 0; isFloat := False; ovf := False;
      while (Pos <= SLen) and (IsDigit(Src[Pos]) or (Src[Pos] = '_')) do
      begin
        if Src[Pos] <> '_' then
        begin
          dg := Ord(Src[Pos]) - Ord('0');
          if iv > (High(Int64) - dg) div 10 then ovf := True;
          if not ovf then iv := iv * 10 + dg;
        end;
        Pos := Pos + 1;
      end;
      fv := iv;
      if (Pos <= SLen) and (Src[Pos] = '.') then
      begin
        isFloat := True;
        Pos := Pos + 1;
        scale := 0.1;
        while (Pos <= SLen) and IsDigit(Src[Pos]) do
        begin
          fv := fv + (Ord(Src[Pos]) - Ord('0')) * scale;
          scale := scale * 0.1;
          Pos := Pos + 1;
        end;
      end;
      if (Pos <= SLen) and ((Src[Pos] = 'e') or (Src[Pos] = 'E')) then
        TokError('float exponent literals not supported in M1');
      if isFloat then AddTok(PK_FLOAT, '', 0, fv)
      else if ovf then AddTok(PK_BIGINT, Copy(Src, start, Pos - start), 0, 0)
      else AddTok(PK_INT, '', iv, 0);
      continue;
    end;
    { identifier / keyword }
    if IsIdentStart(c) then
    begin
      { reject f-strings up front (M1-rest) }
      if ((c = 'f') or (c = 'F')) and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = '''') or (Src[Pos+1] = '"')) then
        TokError('f-strings not supported in M1');
      { b'...' — a BYTES literal: scan like a string, tag PK_BYTES }
      if ((c = 'b') or (c = 'B')) and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = '''') or (Src[Pos+1] = '"')) then
      begin
        Pos := Pos + 1;
        c2 := Src[Pos];
        Pos := Pos + 1;
        slit := '';
        while (Pos <= SLen) and (Src[Pos] <> c2) do
        begin
          if (Src[Pos] = '\') and (Pos + 1 <= SLen) then
          begin
            Pos := Pos + 1;
            case Src[Pos] of
              'n': slit := slit + #10;
              't': slit := slit + #9;
              'r': slit := slit + #13;
              '\': slit := slit + '\';
              '''': slit := slit + '''';
              '"': slit := slit + '"';
              '0': slit := slit + #0;
              'x':
                begin
                  hv := 0;
                  if (Pos + 2 <= SLen) then
                  begin
                    for hk := 1 to 2 do
                    begin
                      Pos := Pos + 1;
                      hc := Src[Pos];
                      if (hc >= '0') and (hc <= '9') then hv := hv * 16 + Ord(hc) - 48
                      else if (hc >= 'a') and (hc <= 'f') then hv := hv * 16 + Ord(hc) - 87
                      else if (hc >= 'A') and (hc <= 'F') then hv := hv * 16 + Ord(hc) - 55;
                    end;
                  end;
                  slit := slit + Chr(hv);
                end;
            else
              slit := slit + Src[Pos];
            end;
          end
          else
            slit := slit + Src[Pos];
          Pos := Pos + 1;
        end;
        if Pos > SLen then TokError('unterminated bytes literal');
        Pos := Pos + 1;
        AddTok(PK_BYTES, slit, 0, 0);
        continue;
      end;
      start := Pos;
      while (Pos <= SLen) and IsIdentChar(Src[Pos]) do Pos := Pos + 1;
      ident := Copy(Src, start, Pos - start);
      AddTok(PK_NAME, ident, 0, 0);
      continue;
    end;
    { string literal }
    if (c = '''') or (c = '"') then
    begin
      c2 := c;
      Pos := Pos + 1;
      slit := '';
      while (Pos <= SLen) and (Src[Pos] <> c2) do
      begin
        if (Src[Pos] = '\') and (Pos + 1 <= SLen) then
        begin
          Pos := Pos + 1;
          case Src[Pos] of
            'n': slit := slit + #10;
            't': slit := slit + #9;
            'r': slit := slit + #13;
            '\': slit := slit + '\';
            '''': slit := slit + '''';
            '"': slit := slit + '"';
            '0': slit := slit + #0;
            'x':
              begin
                hv := 0;
                if (Pos + 2 <= SLen) then
                  for hk := 1 to 2 do
                  begin
                    Pos := Pos + 1;
                    hc := Src[Pos];
                    if (hc >= '0') and (hc <= '9') then hv := hv * 16 + Ord(hc) - 48
                    else if (hc >= 'a') and (hc <= 'f') then hv := hv * 16 + Ord(hc) - 87
                    else if (hc >= 'A') and (hc <= 'F') then hv := hv * 16 + Ord(hc) - 55;
                  end;
                slit := slit + Chr(hv);
              end;
          else
            slit := slit + Src[Pos];
          end;
        end
        else
          slit := slit + Src[Pos];
        Pos := Pos + 1;
      end;
      if Pos > SLen then TokError('unterminated string');
      Pos := Pos + 1;   { closing quote }
      AddTok(PK_STR, slit, 0, 0);
      continue;
    end;
    { operators / punctuation — longest match first }
    c2 := #0;
    if Pos + 1 <= SLen then c2 := Src[Pos+1];
    { 3-char: //= <<= >>= }
    if ((c = '/') and (c2 = '/') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '//=', 0, 0); Pos := Pos + 3; continue; end;
    if ((c = '<') and (c2 = '<') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '<<=', 0, 0); Pos := Pos + 3; continue; end;
    if ((c = '>') and (c2 = '>') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '>>=', 0, 0); Pos := Pos + 3; continue; end;
    { 2-char }
    op := '';
    if (c = '/') and (c2 = '/') then op := '//'
    else if (c = '*') and (c2 = '*') then op := '**'
    else if (c = '<') and (c2 = '<') then op := '<<'
    else if (c = '>') and (c2 = '>') then op := '>>'
    else if (c = '<') and (c2 = '=') then op := '<='
    else if (c = '>') and (c2 = '=') then op := '>='
    else if (c = '=') and (c2 = '=') then op := '=='
    else if (c = '!') and (c2 = '=') then op := '!='
    else if (c = '+') and (c2 = '=') then op := '+='
    else if (c = '-') and (c2 = '=') then op := '-='
    else if (c = '*') and (c2 = '=') then op := '*='
    else if (c = '%') and (c2 = '=') then op := '%='
    else if (c = '&') and (c2 = '=') then op := '&='
    else if (c = '|') and (c2 = '=') then op := '|='
    else if (c = '^') and (c2 = '=') then op := '^=';
    if op <> '' then
    begin AddTok(PK_OP, op, 0, 0); Pos := Pos + 2; continue; end;
    { 1-char }
    case c of
      '+', '-', '*', '/', '%', '&', '|', '^', '~',
      '<', '>', '=', '(', ')', '[', ']', ',', ':', '.', ';', '{', '}':
        begin
          AddTok(PK_OP, Copy(Src, Pos, 1), 0, 0);
          Pos := Pos + 1;
        end;
    else
      TokError('unexpected character ' + Copy(Src, Pos, 1));
    end;
  end;
  { close any open blocks at end of input }
  if (TkN > 0) and (TkKind[TkN-1] <> PK_NL) then AddTok(PK_NL, '', 0, 0);
  while nInd > 1 do begin nInd := nInd - 1; AddTok(PK_DEDENT, '', 0, 0); end;
  AddTok(PK_EOF, '', 0, 0);
end;

{ ---- evaluator (recursive descent; every node returns via a var-out param) ---- }

procedure EvalError(const msg: AnsiString);
begin
  writeln('pyeval: ', msg);
  Halt(1);
end;

function CurKind: Integer;
begin
  CurKind := TkKind[Cur];
end;

function CurText: AnsiString;
begin
  CurText := TkText[Cur];
end;

function IsOp(const s: AnsiString): Boolean;
begin
  IsOp := (TkKind[Cur] = PK_OP) and (TkText[Cur] = s);
end;

function IsKw(const s: AnsiString): Boolean;
begin
  IsKw := (TkKind[Cur] = PK_NAME) and (TkText[Cur] = s);
end;

procedure Advance;
begin
  if TkKind[Cur] <> PK_EOF then Cur := Cur + 1;
end;

procedure ExpectOp(const s: AnsiString);
begin
  if not IsOp(s) then EvalError('expected ' + s);
  Advance;
end;

function LclFind(const name: AnsiString): Integer;
var i: Integer;
begin
  LclFind := -1;
  for i := 0 to LclN - 1 do
    if LclNames[i] = name then begin LclFind := i; Exit; end;
end;

procedure LclSet(const name: AnsiString; const v: Variant);
var i: Integer;
begin
  i := LclFind(name);
  if i >= 0 then begin LclVals[i] := v; Exit; end;
  if LclN >= Length(LclNames) then
  begin
    if Length(LclNames) = 0 then SetLength(LclNames, 16)
    else SetLength(LclNames, Length(LclNames) * 2);
    SetLength(LclVals, Length(LclNames));
  end;
  LclNames[LclN] := name;
  LclVals[LclN] := v;
  LclN := LclN + 1;
end;

{ Python type objects (int/str/…) as first-class values, needed by isinstance's
  second argument. Encoded in a pyeval-internal variant tag 100 whose payload is
  the VT_* the type maps to (int->2, float->3, bool->4, str->6, bytes/list/dict
  use their container discriminators 7/107/207). -1 if `name` is not a type. }
const PY_TYPETAG = 100;
function PyTypeCode(const name: AnsiString): Int64;
begin
  if (name = 'int') then PyTypeCode := 2
  else if (name = 'float') then PyTypeCode := 3
  else if (name = 'bool') then PyTypeCode := 4
  else if (name = 'str') then PyTypeCode := 6
  else if (name = 'bytes') or (name = 'bytearray') then PyTypeCode := 7
  else if (name = 'list') or (name = 'tuple') then PyTypeCode := 107  { a tuple IS a TPyList }
  else if (name = 'dict') then PyTypeCode := 207
  else PyTypeCode := -1;
end;

procedure LclDelete(const name: AnsiString);
var i, j: Integer;
begin
  i := LclFind(name);
  if i < 0 then Exit;
  for j := i to LclN - 2 do
  begin LclNames[j] := LclNames[j+1]; LclVals[j] := LclVals[j+1]; end;
  LclN := LclN - 1;
end;

function FnFind(const name: AnsiString): Integer;
var i: Integer;
begin
  FnFind := -1;
  for i := 0 to FnN - 1 do
    if FnName[i] = name then begin FnFind := i; Exit; end;
end;

procedure FnRegister(const name: AnsiString; bodyPos: Integer; const params: AnsiString);
var i: Integer;
begin
  i := FnFind(name);
  if i >= 0 then
  begin FnBodyPos[i] := bodyPos; FnParams[i] := params; Exit; end;
  if FnN >= Length(FnName) then
  begin
    if Length(FnName) = 0 then SetLength(FnName, 8)
    else SetLength(FnName, Length(FnName) * 2);
    SetLength(FnBodyPos, Length(FnName));
    SetLength(FnParams, Length(FnName));
  end;
  FnName[FnN] := name; FnBodyPos[FnN] := bodyPos; FnParams[FnN] := params;
  FnN := FnN + 1;
end;

{ ---- persistent closures: a nested `def` captured as a VALUE (M2c) ---- }
{ A pyeval `def` used as a value — passed to a host method (uforth's
  `vm.define_word(name, native=_w)`) and called back much later as
  `word.native(vm2)` — must OUTLIVE its EvalPyStmts: Tokenize reuses the global
  token buffer on the next exec, and the enclosing locals (`name`) are gone too.
  So snapshot the whole token buffer, the body position, the params, and the
  enclosing locals into a persistent record. Boxed as a VT_PYCLOSURE (tag 9)
  variant whose payload is the record index; the reverse bridge (NilPy's
  PyMakeDynCall) sees the tag and routes the call to PyClosureCall1. }
{ MIRRORS compiler/defs.inc's VT_PYCLOSURE_TAG / VT_BOUNDFN_TAG — a builtin unit
  cannot see defs.inc, so the numbers are written twice and MUST be changed
  together. The compiler side is what the variant clear/retain emitters test
  against; this side is what stamps the tag. }
const VT_PYCLOSURE = 9;
      VT_BOUNDFN   = 10;
      { …and the two STATIC-address arms of the same family. Neither payload is
        a heap block, so neither joins the object-tag lists; they exist so the
        callee guard can tell code and a class apart from an integer. }
      VT_CLASSREF  = 11;
      VT_CALLABLE  = 12;
      VT_BTYPE     = 13;   { a BUILTIN type used as a value — converts }
{ The two tags PyNotCallable still names by number. Same mirror rule as the
  block above — they restate compiler/defs.inc's VT_BOUNDMETHOD / VT_OBJECT and
  must change with them. Prefixed VT_NC_ so the duplicate names cannot collide
  with anything a later include brings in.

  This list used to hold VT_INT/VT_DOUBLE/VT_BOOL/VT_CHAR/VT_STRING/
  VT_PROMO_BASE too, because the guard was a REFUSAL list. It is an allow-list
  now (see PyNotCallable), so the non-callable tags do not need naming at all —
  which is the point: a tag nobody thought about is refused by default instead
  of being let through. }
const VT_NC_BOUNDMETHOD = 8;
      VT_NC_OBJECT      = 7;
type
  TPyClosure = record
    Kinds:  array of Integer;
    Texts:  array of AnsiString;
    Ints:   array of Int64;
    Floats: array of Double;
    NTok:   Integer;
    BodyPos: Integer;
    Params:  AnsiString;
    CapNames: array of AnsiString;
    CapVals:  array of Variant;
    CapN:    Integer;
    { True for a closure built from raw SOURCE (pyclosure_src_new): its body is
      a FLAT statement stream at indent 0, run by a top-level loop rather than
      ExecSuite's after-a-colon suite grammar. }
    FlatSrc: Boolean;
    { The legal argument-count RANGE, ReqN..TotN, or ReqN = -1 for "arity
      unknown, do not check". Recorded by the builder rather than counted from
      Params, because the two disagree: a closure built for a nested DEF binds
      its defaults as captures and leaves them out of Params, so a count read
      off Params under-counts and would reject a legal call. Only the lambda
      lowering calls pyclosure_setarity, so every other builder stays lenient —
      which is what keeps the callback bridges working. }
    ReqN: Integer;
    TotN: Integer;
  end;
  { A closure passed to a Callable/Pointer host param (uforth's
    `define_word(name, native=_w)`) is stored in the class's Pointer-typed field
    (Word.native) and later called as `word.native(vm2)` — an indirect call
    through a raw pointer, NOT the Variant dynamic-call path. So the value living
    in that field must be a POINTER that the call site can tell apart from a real
    compiled function address. A TClosureObj does that: its first word is a fixed
    Magic sentinel (the address of a pyeval global), which a real code pointer's
    first instruction bytes will not match, so `word.native(vm2)` can branch —
    closure -> PyClosureCallPtr, real fn -> the plain indirect call. }
  TClosureObj = record
    Magic: Pointer;
    Cidx:  Int64;
  end;
  PClosureObj = ^TClosureObj;
var
  Closures: array of TPyClosure;
  ClosureN: Integer;

  PyClosureMagicMarker: Integer;   { its ADDRESS is the closure sentinel }

{ Recycle stack of dead Closures[] rows (feature-nilpy-object-reclamation):
  a closure OBJECT is a refcounted RAW2 block; when it dies, PyEvalClosureFree
  releases the row's captures and token refs and parks the index here for the
  next creator. }
var
  ClosureFreeStk: array of Integer;
  ClosureFreeN: Integer;

{ TWO object families share the RAW2 population and therefore the one finalize
  hook, told apart by their first word. The bound-fn half is implemented below,
  next to its own type — TBoundFnObj is declared after this point. }
procedure PyBoundFnFreeIfMine(objp: Pointer; var handled: Boolean); forward;

procedure PyEvalClosureFree(objp: Pointer);
var c, i: Integer; wasBoundFn: Boolean;
begin
  if objp = nil then Exit;
  wasBoundFn := False;
  PyBoundFnFreeIfMine(objp, wasBoundFn);
  if wasBoundFn then Exit;
  if PClosureObj(objp)^.Magic <> @PyClosureMagicMarker then Exit;
  c := Integer(PClosureObj(objp)^.Cidx);
  if (c < 0) or (c >= ClosureN) then Exit;
  Closures[c].Kinds := nil;
  Closures[c].Texts := nil;
  Closures[c].Ints := nil;
  Closures[c].Floats := nil;
  for i := 0 to Closures[c].CapN - 1 do
  begin
    Closures[c].CapNames[i] := '';
    Closures[c].CapVals[i] := 0;   { variant := int releases any payload }
  end;
  SetLength(Closures[c].CapNames, 0);
  SetLength(Closures[c].CapVals, 0);
  Closures[c].CapN := 0;
  Closures[c].Params := '';
  Closures[c].NTok := 0;
  if ClosureFreeN >= Length(ClosureFreeStk) then
  begin
    if Length(ClosureFreeStk) = 0 then SetLength(ClosureFreeStk, 16)
    else SetLength(ClosureFreeStk, Length(ClosureFreeStk) * 2);
  end;
  ClosureFreeStk[ClosureFreeN] := c;
  ClosureFreeN := ClosureFreeN + 1;
end;

{ Pop a recycled registry row, or mint a fresh one. }
function PyClosureAllocRow: Integer;
{ Hand back a row in a DEFINED state. A recycled row used to arrive holding its
  predecessor's BodyPos / FlatSrc / ReqN / TotN — precisely the four fields
  PyEvalClosureFree does not clear AND PyMakeClosure does not set, so a nested
  `def` captured as a value inherited them wholesale:

    * ReqN/TotN — a recycled row from a LAMBDA (the only builder that calls
      pyclosure_setarity) made the new closure claim the lambda's arity, so
      uforth's `0 VALUE ii` died with "<lambda>() takes 0 positional arguments
      but 1 were given" while its `def _w(vm2)` plainly takes one. Every builder
      except the lambda lowering is meant to be LENIENT (ReqN = -1); this is
      what silently made one of them strict, and strict about the wrong number.
    * FlatSrc — a recycled row from pyclosure_src_new would run a nested def's
      INDENTED body under the flat top-level grammar. Not observed in the wild,
      same root, closed here rather than left to be found the hard way.

  Resetting HERE rather than in each builder: the free path and the builders
  between them covered five of the nine fields, and the four that fell through
  are the ones no one owned. One owner, every field.
  bug-nilpy-pyeval-lambda-host-word-arity-mismatch }
var c: Integer;
begin
  if ClosureFreeN > 0 then
  begin
    ClosureFreeN := ClosureFreeN - 1;
    c := ClosureFreeStk[ClosureFreeN];
  end
  else
  begin
    if ClosureN >= Length(Closures) then
    begin
      if Length(Closures) = 0 then SetLength(Closures, 8)
      else SetLength(Closures, Length(Closures) * 2);
    end;
    c := ClosureN;
    ClosureN := ClosureN + 1;
  end;
  Closures[c].Kinds := nil;
  Closures[c].Texts := nil;
  Closures[c].Ints := nil;
  Closures[c].Floats := nil;
  Closures[c].NTok := 0;
  Closures[c].BodyPos := 0;
  Closures[c].Params := '';
  SetLength(Closures[c].CapNames, 0);
  SetLength(Closures[c].CapVals, 0);
  Closures[c].CapN := 0;
  Closures[c].FlatSrc := False;
  Closures[c].ReqN := -1;      { lenient unless the builder says otherwise }
  Closures[c].TotN := -1;
  PyClosureAllocRow := c;
end;

function PyMakeClosureObj(cidx: Int64): Pointer;
var o: PClosureObj;
begin
  PXXObjFinalizeHook := @PyObjFinalize;
  PyClosureFinalizeHook := @PyEvalClosureFree;
  o := PClosureObj(PXXObjAllocRaw2(SizeOf(TClosureObj)));
  o^.Magic := @PyClosureMagicMarker;
  o^.Cidx  := cidx;
  PyMakeClosureObj := Pointer(o);
end;

{ ---- bound compiled functions (see interface note) ---- }
type
  TBoundFnObj = record
    Magic:  Pointer;
    Code:   Pointer;
    NBound: Int64;
    A0Var:  Int64;   { 1 = the user argument is a VARIANT param (pass its address) }
    { How many OWN (user-visible) parameters the compiled body takes before its
      lifted capture parameters. The bridge used to assume exactly one and
      always pass a leading argument, so a `def b():` with captures had every
      capture land one register too far right and read garbage
      (bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one).
      Defaults to 1 in pyboundfn_new, which is what the lambda lifter relies on
      — it injects a dummy own parameter for exactly this reason — so only the
      nested-def path needs to say otherwise, via pyboundfn_setown. }
    NOwn:   Int64;
    { A lambda's DEFAULTED parameters. `lambda x, y=k: x*y` lifts y as a bound
      slot holding k, because that is how the frontend spells a build-time
      default — but y is still a PARAMETER, and `f(3, 4)` must see 4. Without
      these the extra argument was clipped against NOwn and silently dropped,
      so f(3, 4) returned f(3)'s answer with no diagnostic
      (bug-nilpy-a-lambda-call-is-not-arity-checked).

      NDef      how many trailing bound slots are defaulted params.
      NDefBase  the CALLER-side argument index the first of them occupies.
                Not NOwn: a zero-parameter lambda is lifted under a dummy own
                parameter, so `lambda x=j: x` has NOwn=1 while x is the
                caller's argument 0.
      DefVarMask  bit d set = that param is a Variant, so an overriding
                argument travels by ADDRESS like every other variant param. }
    NDef:       Int64;
    NDefBase:   Int64;
    DefVarMask: Int64;
    Bound:  array[0..19] of Int64;
    { What each Bound[] slot OWNS, so the finalizer can undo exactly what the
      binder did — the binders are the only writers and each knows its own
      answer, so this is recorded, never guessed from the value:
        BK_PLAIN   0  a copied scalar, or a SHARED frame cell's address; owns nothing
        BK_OBJ     1  pyboundfn_bind_obj retained it
        BK_VARSLOT 2  pyboundfn_bind_var's private 16-byte variant slot
        BK_CELL    3  pyboundfn_bind_cell's private 8-byte cell
      TWO BITS PER SLOT packed into one word, not an array: this record is
      allocated once per escaping closure, and the whole point of the change
      that added this field is to make that allocation cheap enough to reclaim
      — a per-slot array grew the object enough to push it into the next
      allocator size class, which MEASURABLY made the still-leaking shapes
      leak more. 20 slots x 2 bits = 40 bits, so one Int64 is ample. }
    BKindMask: Int64;
  end;
  PBoundFnObj = ^TBoundFnObj;
  { A plain compiled def taken as a value: the value IS its code address.
    Declared as returning a VARIANT, because that is what an unannotated
    `def f(): ...` compiles to — and a Variant result travels through a hidden
    destination POINTER (r10 on x86-64), which the callee unconditionally
    copies its result into on the way out. Calling such a def through a
    `: Int64` pointer left r10 holding whatever the last call did, so the
    epilogue's `rep movsb` wrote 16 bytes to a garbage address: every
    `command=` / `after` callback that was a plain def segfaulted the moment it
    RETURNED. A `-> None` callee ignores the destination, so declaring it here
    is safe for both shapes (the caller's slot is a zeroed local either way). }
  TPyCallFn0 = function: Variant;
  TPyCallFn1 = function(const a0: Variant): Variant;
  TPyCallFn2 = function(const a0, a1: Variant): Variant;
  TPyCallFn3 = function(const a0, a1, a2: Variant): Variant;
  TPyCallFn4 = function(const a0, a1, a2, a3: Variant): Variant;
  { Variant results, not Int64: an unannotated NilPy def returns its value
    through a hidden destination pointer the callee always copies into. Through
    an Int64-typed pointer that register held stale data and the callee's
    epilogue wrote 16 bytes over whatever it pointed at — a wild store on every
    lifted-bound-fn callback, which is how Tcl's own command table ended up
    corrupted ("invalid command name pxxcb") in a long-running Tk app. }
  { ONE TYPE PER ARITY, 0..32, with no gaps. There used to be gaps (no TBF10,
    no TBF12, nothing above 13) and the dispatch below rounded UP to the next
    type it had — calling a 10-parameter body through TBF11. Measured: that
    SEGFAULTS, it does not degrade to a wrong value, so every closure whose
    own-params + captures landed on a missing arity crashed (uforth's MARKER
    restore, 1 own + 11 captures = 12, took the ANS coreext word set with it).
    Passing MORE arguments than the body declares is unsafe here whatever the
    reason, so the rule is exact arity, never round up.
    32 is the ceiling the frontend already
    enforces on a lifted signature (MAX_PROC_PARAMS / "too many parameters
    after capture"), so this table now covers everything that can reach it. }
  TBF0  = function: Variant;
  TBF1  = function(a0: Int64): Variant;
  TBF2  = function(a0, a1: Int64): Variant;
  TBF3  = function(a0, a1, a2: Int64): Variant;
  TBF4  = function(a0, a1, a2, a3: Int64): Variant;
  TBF5  = function(a0, a1, a2, a3, a4: Int64): Variant;
  TBF6  = function(a0, a1, a2, a3, a4, a5: Int64): Variant;
  TBF7  = function(a0, a1, a2, a3, a4, a5, a6: Int64): Variant;
  TBF8  = function(a0, a1, a2, a3, a4, a5, a6, a7: Int64): Variant;
  TBF9  = function(a0, a1, a2, a3, a4, a5, a6, a7, a8: Int64): Variant;
  TBF10 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9: Int64): Variant;
  TBF11 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10: Int64): Variant;
  TBF12 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11: Int64): Variant;
  TBF13 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12: Int64): Variant;
  TBF14 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13: Int64): Variant;
  TBF15 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14: Int64): Variant;
  TBF16 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15: Int64): Variant;
  TBF17 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16: Int64): Variant;
  TBF18 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17: Int64): Variant;
  TBF19 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18: Int64): Variant;
  TBF20 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19: Int64): Variant;
  TBF21 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20: Int64): Variant;
  TBF22 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21: Int64): Variant;
  TBF23 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22: Int64): Variant;
  TBF24 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23: Int64): Variant;
  TBF25 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24: Int64): Variant;
  TBF26 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25: Int64): Variant;
  TBF27 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26: Int64): Variant;
  TBF28 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27: Int64): Variant;
  TBF29 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28: Int64): Variant;
  TBF30 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29: Int64): Variant;
  TBF31 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30: Int64): Variant;
  TBF32 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31: Int64): Variant;
const
  { Bound[] slot ownership — see TBoundFnObj.BKindMask. }
  BK_PLAIN   = 0;
  BK_OBJ     = 1;
  BK_VARSLOT = 2;
  BK_CELL    = 3;

{ The two-bit field for slot `idx`. Written by the binders, read by the
  finalizer; nothing else may touch the mask. }
procedure PyBFSetKind(o: PBoundFnObj; idx: Int64; k: Int64);
begin
  if (idx < 0) or (idx > 19) then Exit;
  o^.BKindMask := (o^.BKindMask and (not (Int64(3) shl (idx * 2))))
                  or ((k and 3) shl (idx * 2));
end;

function PyBFGetKind(o: PBoundFnObj; idx: Int64): Int64;
begin
  PyBFGetKind := BK_PLAIN;
  if (idx < 0) or (idx > 19) then Exit;
  PyBFGetKind := (o^.BKindMask shr (idx * 2)) and 3;
end;

var
  PyBoundFnMagicMarker: Integer;

function pyboundfn_new(code: Pointer; n: Int64; a0var: Int64): Pointer;
var o: PBoundFnObj; i: Integer;
begin
  { A HEADERED refcounted block, not GetMem: the plain block had no refcount, so
    nothing could ever free it and every capture it retained stayed retained.
    RAW2 is the same population TClosureObj uses, and the two are told apart in
    the finalizer by their Magic field — see PyEvalClosureFree. Both hooks are
    installed here as well as in PyMakeClosureObj, because a program may create
    a lifted bound-fn without ever building an interpreted closure. }
  PXXObjFinalizeHook := @PyObjFinalize;
  PyClosureFinalizeHook := @PyEvalClosureFree;
  o := PBoundFnObj(PXXObjAllocRaw2(SizeOf(TBoundFnObj)));
  o^.Magic := @PyBoundFnMagicMarker;
  o^.Code := code;
  o^.NBound := n;
  o^.A0Var := a0var;
  o^.NOwn := 1;   { the historic assumption; pyboundfn_setown overrides it }
  { NDefBase = -1 means ARITY UNCHECKED. Only the lambda lifter calls
    pyboundfn_setdefaults, so every other bound-fn user — nested defs, the
    callback bridges — keeps the lenient behaviour its comment relies on.
    Read only when NDef > 0 elsewhere, so -1 is inert there.
    bug-nilpy-lifted-lambda-does-not-enforce-arity }
  o^.NDef := 0; o^.NDefBase := -1; o^.DefVarMask := 0;   { no defaulted params unless told }
  o^.BKindMask := 0;
  for i := 0 to 19 do o^.Bound[i] := 0;
  pyboundfn_new := Pointer(o);
end;

function pyboundfn_setown(obj: Pointer; nown: Int64): Pointer;
{ Chained after pyboundfn_new like the binds are, rather than added as a fourth
  parameter to it: the existing call sites build that call as an AST by hand and
  one of them passes only two arguments, so widening the signature is a bigger
  change than the fix warrants. }
var o: PBoundFnObj;
begin
  o := PBoundFnObj(obj);
  o^.NOwn := nown;
  pyboundfn_setown := obj;
end;

function pyboundfn_setdefaults(obj: Pointer; base, count, varmask: Int64): Pointer;
{ Declare that `count` bound slots, starting at bound index 0, are DEFAULTED
  parameters whose caller-side positions begin at `base`. Chained after
  pyboundfn_new like setown, and only by the lambda lifter — everything else
  leaves NDef at 0 and keeps the historic behaviour untouched, which is what
  keeps the lenient callback bridges lenient. }
var o: PBoundFnObj;
begin
  o := PBoundFnObj(obj);
  o^.NDefBase := base;
  o^.NDef := count;
  o^.DefVarMask := varmask;
  pyboundfn_setdefaults := obj;
end;

function pyboundfn_bind_obj(obj: Pointer; idx: Int64; p: Pointer): Pointer;
{ Bind a CLASS capture, taking a reference. The enclosing scope releases its own
  reference when it returns, so binding the bare handle left the closure holding
  a freed object — `def b(): return len(L)` over a captured list answered 0
  once the parent had returned. The matching release is the finalizer's, keyed
  on BK_OBJ. }
var o: PBoundFnObj;
begin
  if p <> nil then PXXObjRetain(p);
  o := PBoundFnObj(obj);
  o^.Bound[idx] := Int64(NativeInt(p));
  PyBFSetKind(o, idx, BK_OBJ);
  pyboundfn_bind_obj := obj;
end;

function pyboundfn_bind(obj: Pointer; idx: Int64; v: Int64): Pointer;
var o: PBoundFnObj;
begin
  o := PBoundFnObj(obj);
  o^.Bound[idx] := v;
  { BK_PLAIN even though it is sometimes an ADDRESS: this is the binder a
    SHARED frame cell (pycell_new) uses, and that cell belongs to the frame and
    to every other closure over it. Freeing it here would dangle the siblings. }
  PyBFSetKind(o, idx, BK_PLAIN);
  pyboundfn_bind := obj;
end;

function pyboundfn_is(p: Pointer): Boolean;
begin
  pyboundfn_is := (p <> nil) and (PBoundFnObj(p)^.Magic = @PyBoundFnMagicMarker);
end;

function pycallable_obj_is(p: Pointer): Boolean;
begin
  pycallable_obj_is := (p <> nil) and (pyclosure_is(p) or pyboundfn_is(p));
end;

procedure PyBoundFnFreeIfMine(objp: Pointer; var handled: Boolean);
{ The bound-fn half of the RAW2 finalize hook. Undoes exactly what the binders
  recorded in BKind — no guessing from the value, because a plain Int64 slot and
  a pointer slot are indistinguishable at this point, and one of the pointer
  shapes (a SHARED pycell_new frame cell, bound with the plain binder) must
  NOT be freed here: the frame and every sibling closure still hold it.
  The object block itself is freed by PXXObjRelease, which called us. }
var bo: PBoundFnObj; pv: PVariant; i: Integer;
begin
  handled := False;
  if objp = nil then Exit;
  if PBoundFnObj(objp)^.Magic <> @PyBoundFnMagicMarker then Exit;
  handled := True;
  bo := PBoundFnObj(objp);
  for i := 0 to 19 do
  begin
    if bo^.Bound[i] = 0 then Continue;
    if PyBFGetKind(bo, i) = BK_OBJ then
      PXXObjRelease(Pointer(NativeInt(bo^.Bound[i])))
    else if PyBFGetKind(bo, i) = BK_VARSLOT then
    begin
      { a whole variant slot: release what it carries, then the slot }
      pv := PVariant(NativeInt(bo^.Bound[i]));
      pv^ := 0;                     { variant := int releases any payload }
      FreeMem(Pointer(pv));
    end
    else if PyBFGetKind(bo, i) = BK_CELL then
      FreeMem(Pointer(NativeInt(bo^.Bound[i])));
    bo^.Bound[i] := 0;
    PyBFSetKind(bo, i, BK_PLAIN);
  end;
end;

{ Bind a VARIANT capture: variant params travel BY ADDRESS, and the enclosing
  local dies with its frame — so the value is copied into a small heap slot
  that lives as long as the object (leaked with it; markers are few). }
function pyboundfn_bind_var(obj: Pointer; idx: Int64; const v: Variant): Pointer;
var o: PBoundFnObj; pv: PVariant;
begin
  o := PBoundFnObj(obj);
  pv := GetMem(16);   { a Variant slot: 8-byte tag + 8-byte payload }
  PPyRec(pv)^.VType := 0; PPyRec(pv)^.Payload := 0;
  pv^ := v;
  o^.Bound[idx] := Int64(NativeInt(Pointer(pv)));
  PyBFSetKind(o, idx, BK_VARSLOT);
  pyboundfn_bind_var := obj;
end;

{ Bind a `nonlocal` capture as an 8-byte heap cell holding the current value and
  bind its ADDRESS — see the declaration for why nothing else will do. Eight
  bytes regardless of the capture's width: the by-ref store may be a 32-bit
  `mov %eax,(%rcx)` for an inferred int or a full word for an Int64/Double, and
  over-allocating is free here while under-allocating would scribble the next
  heap object. A VARIANT capture keeps pyboundfn_bind_var, whose 16-byte slot is
  already the right shape for a by-address variant. }
function pyboundfn_bind_cell(obj: Pointer; idx: Int64; v: Int64): Pointer;
var o: PBoundFnObj; pc: PInt64;
begin
  o := PBoundFnObj(obj);
  pc := PInt64(GetMem(8));
  pc^ := v;
  o^.Bound[idx] := Int64(NativeInt(Pointer(pc)));
  PyBFSetKind(o, idx, BK_CELL);   { a PRIVATE copy, unlike the shared pycell_new one }
  pyboundfn_bind_cell := obj;
end;

{ See the declaration: the ONE shared cell for a frame local that a nested def
  declares `nonlocal`. Zeroed, because Python's cell starts unbound and the
  enclosing frame's own first assignment is what gives it a value. }
function pycell_new: Pointer;
var pv: PVariant;
begin
  { SIXTEEN bytes, not eight: a variant cell needs a whole {tag, payload} slot,
    and over-allocating for a scalar is free while under-allocating would
    scribble the next heap object. Zeroed exactly as pyboundfn_bind_var zeroes
    its slot — a variant must not start on stale bytes. }
  pv := PVariant(GetMem(16));
  PPyRec(pv)^.VType := 0;
  PPyRec(pv)^.Payload := 0;
  pycell_new := Pointer(pv);
end;

{ Call code(a0, bound...). a0 is the ONE user argument — a class/object variant
  yields its instance pointer, an int its value. Missing arities pad upward
  (extra register args are ABI-harmless); a procedure callee's garbage result
  is discarded. }
procedure pycall_value(const cb: Variant; const arg: Variant; withArg: Boolean);
var p: Pointer; f1: TPyCallFn1; f0: TPyCallFn0; vres: Variant;
begin
  vres := pynone;
  if pycallback_is(cb) then
  begin
    if withArg then pycallback_call1(cb, arg) else pycallback_call0(cb);
    Exit;
  end;
  p := Pointer(NativeInt(PPyRec(@cb)^.Payload));
  if p = nil then Exit;
  if pyclosure_is(p) then
  begin
    pyclosure_call_ptr(p, arg);
    Exit;
  end;
  if pyboundfn_is(p) then
  begin
    pyboundfn_call_ptr(p, arg);
    Exit;
  end;
  { a plain compiled def: the value IS its code address }
  if withArg then
  begin
    f1 := TPyCallFn1(p);
    vres := f1(arg);
  end
  else
  begin
    f0 := TPyCallFn0(p);
    vres := f0();     { the parens matter: a bare name is the POINTER, not a call }
  end;
end;

function pyboundfn_call_ptr(objptr: Pointer; const a0: Variant): Integer;
var rvd: Variant;
begin
  rvd := pynone;
  pyboundfn_callv(objptr, a0, rvd);
  pyboundfn_call_ptr := 0;
end;

{ Marshal ONE own argument the way the bridge always has: a variant own param
  travels by address, an object variant yields its instance pointer, None is 0,
  anything else coerces to an integer. Factored out so the multi-argument form
  below cannot drift from the single-argument one. }
function PyBoundFnArgWord(o: PBoundFnObj; const a: Variant; slot: PVariant): Int64;
begin
  if o^.A0Var <> 0 then
  begin
    slot^ := a;
    PyBoundFnArgWord := Int64(NativeInt(Pointer(slot)));
    Exit;
  end;
  case PPyRec(@a)^.VType of
    7: PyBoundFnArgWord := PPyRec(@a)^.Payload;
    0: PyBoundFnArgWord := 0;
  else PyBoundFnArgWord := pyvar_to_int(a);
  end;
end;

function PyBoundFnDefWord(const a: Variant; isvar: Int64; slot: PVariant): Int64;
{ The same conversion as PyBoundFnArgWord, but for an argument overriding a
  DEFAULTED parameter — whose variant-ness is per-slot (it follows the type of
  the captured value the default came from) rather than the object-wide A0Var
  the own parameters share. }
begin
  if isvar <> 0 then
  begin
    slot^ := a;
    PyBoundFnDefWord := Int64(NativeInt(Pointer(slot)));
    Exit;
  end;
  case PPyRec(@a)^.VType of
    7: PyBoundFnDefWord := PPyRec(@a)^.Payload;
    0: PyBoundFnDefWord := 0;
  else PyBoundFnDefWord := pyvar_to_int(a);
  end;
end;

procedure pyboundfn_callvn(objptr: Pointer; const a0, a1, a2: Variant;
                           nargs: Int64; var res: Variant);
{ Call code(own..., bound...). The own arguments come first because that is the
  order the compiled body declares them in — its capture parameters were LIFTED
  onto the end of its own signature by the frontend.

  This used to hardcode one own argument. A closure with none (`def b():`, the
  commonest shape in Python) therefore had a spurious leading argument inserted
  and read every capture one register too far right; a closure with two or three
  had its extra arguments dropped by pyvar_callv2/3 and the captures shifted the
  other way. Only arity 1 lined up
  (bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one). }
var o: PBoundFnObj; b: PInt64; code: Pointer;
    va0, va1, va2: Variant;
    vd0, vd1, vd2: Variant;   { by-address slots for an OVERRIDDEN variant default }
    dv: Int64;
    p: array[0..31] of Int64;
    n, i: Integer;
    f0: TBF0; f1: TBF1; f2: TBF2; f3: TBF3; f4: TBF4; f5: TBF5;
    f6: TBF6; f7: TBF7; f8: TBF8; f9: TBF9; f10: TBF10; f11: TBF11;
    f12: TBF12; f13: TBF13; f14: TBF14; f15: TBF15; f16: TBF16; f17: TBF17;
    f18: TBF18; f19: TBF19; f20: TBF20; f21: TBF21; f22: TBF22; f23: TBF23;
    f24: TBF24; f25: TBF25; f26: TBF26; f27: TBF27; f28: TBF28; f29: TBF29;
    f30: TBF30; f31: TBF31; f32: TBF32;
    rv: Variant;
begin
  rv := pynone;
  o := PBoundFnObj(objptr);
  code := o^.Code;
  { the body takes what it declares, not what the caller happened to supply }
  n := o^.NOwn;
  if n > nargs then n := nargs;
  if n > 3 then n := 3;
  for i := 0 to 31 do p[i] := 0;
  if n > 0 then p[0] := PyBoundFnArgWord(o, a0, @va0);
  if n > 1 then p[1] := PyBoundFnArgWord(o, a1, @va1);
  if n > 2 then p[2] := PyBoundFnArgWord(o, a2, @va2);
  { a body declaring MORE own params than the caller passed still gets a slot
    per parameter -- zeroed, which is what an unsupplied argument reads as }
  n := o^.NOwn;
  if n > 31 then n := 31;
  b := @o^.Bound[0];
  for i := 0 to o^.NBound - 1 do
    if n + i <= 31 then p[n + i] := b[i];

  { A DEFAULTED parameter is a bound slot the caller may override. Done after
    the bind copy above, deliberately: the default is written first and the
    supplied argument overwrites it, so "not supplied" needs no sentinel.
    Argument NDefBase+i is the caller-side position of defaulted param i —
    NOT NOwn+i, because a zero-parameter lambda carries a dummy own parameter
    the caller never counts. }
  for i := 0 to o^.NDef - 1 do
    if (i <= 2) and (o^.NDefBase + i < nargs) and (n + i <= 31) then
    begin
      dv := (o^.DefVarMask shr i) and 1;
      case o^.NDefBase + i of
        0: p[n + i] := PyBoundFnDefWord(a0, dv, @vd0);
        1: p[n + i] := PyBoundFnDefWord(a1, dv, @vd1);
        2: p[n + i] := PyBoundFnDefWord(a2, dv, @vd2);
      end;
    end;
  { EXACT arity only — see the TBF table. Never round up: a call with more
    arguments than the body declares crashes it. }
  case n + o^.NBound of
    0: begin f0 := TBF0(code); rv := f0(); end;
    1: begin f1 := TBF1(code); rv := f1(p[0]); end;
    2: begin f2 := TBF2(code); rv := f2(p[0], p[1]); end;
    3: begin f3 := TBF3(code); rv := f3(p[0], p[1], p[2]); end;
    4: begin f4 := TBF4(code); rv := f4(p[0], p[1], p[2], p[3]); end;
    5: begin f5 := TBF5(code); rv := f5(p[0], p[1], p[2], p[3], p[4]); end;
    6: begin f6 := TBF6(code); rv := f6(p[0], p[1], p[2], p[3], p[4], p[5]); end;
    7: begin f7 := TBF7(code); rv := f7(p[0], p[1], p[2], p[3], p[4], p[5], p[6]); end;
    8: begin f8 := TBF8(code); rv := f8(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]); end;
    9: begin f9 := TBF9(code); rv := f9(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]); end;
    10: begin f10 := TBF10(code); rv := f10(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9]); end;
    11: begin f11 := TBF11(code); rv := f11(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10]); end;
    12: begin f12 := TBF12(code); rv := f12(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11]); end;
    13: begin f13 := TBF13(code); rv := f13(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12]); end;
    14: begin f14 := TBF14(code); rv := f14(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13]); end;
    15: begin f15 := TBF15(code); rv := f15(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14]); end;
    16: begin f16 := TBF16(code); rv := f16(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15]); end;
    17: begin f17 := TBF17(code); rv := f17(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16]); end;
    18: begin f18 := TBF18(code); rv := f18(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17]); end;
    19: begin f19 := TBF19(code); rv := f19(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18]); end;
    20: begin f20 := TBF20(code); rv := f20(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19]); end;
    21: begin f21 := TBF21(code); rv := f21(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20]); end;
    22: begin f22 := TBF22(code); rv := f22(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21]); end;
    23: begin f23 := TBF23(code); rv := f23(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22]); end;
    24: begin f24 := TBF24(code); rv := f24(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23]); end;
    25: begin f25 := TBF25(code); rv := f25(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24]); end;
    26: begin f26 := TBF26(code); rv := f26(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25]); end;
    27: begin f27 := TBF27(code); rv := f27(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25], p[26]); end;
    28: begin f28 := TBF28(code); rv := f28(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25], p[26], p[27]); end;
    29: begin f29 := TBF29(code); rv := f29(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25], p[26], p[27], p[28]); end;
    30: begin f30 := TBF30(code); rv := f30(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25], p[26], p[27], p[28], p[29]); end;
    31: begin f31 := TBF31(code); rv := f31(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25], p[26], p[27], p[28], p[29], p[30]); end;
    32: begin f32 := TBF32(code); rv := f32(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16], p[17], p[18], p[19], p[20], p[21], p[22], p[23], p[24], p[25], p[26], p[27], p[28], p[29], p[30], p[31]); end;
  else
    { unreachable: the frontend refuses a lifted signature past 32 parameters.
      Say so rather than returning None — a silent wrong answer here is how the
      rounded-up call above stayed hidden for so long. }
    raise TypeError.Create('closure call needs ' + pystr_of(n + o^.NBound)
      + ' argument slots, past the 32 the runtime bridge can pass');
  end;
  res := rv;
end;

procedure pyboundfn_callv(objptr: Pointer; const a0: Variant; var res: Variant);
begin
  pyboundfn_callvn(objptr, a0, pynone, pynone, 1, res);
end;


{ Closure from raw SOURCE (the compiled `lambda` lowering). Tokenizes the body
  text into the closure's own snapshot buffer — the live interpreter state
  (token buffer, cursor, source scanner) is saved and restored, so this is safe
  to call from inside a running EvalPyStmts. BodyPos 0 = the start of the flat
  `return <expr>` statement; ExecSuite's inline form runs it. }
function pyclosure_src_new(const params, src: AnsiString): Pointer;
var sKinds: array of Integer; sTexts: array of AnsiString;
    sInts: array of Int64; sFloats: array of Double;
    sTkN, sCur, sPos, sSLen: Integer; sSrc: AnsiString;
    c, i: Integer;
begin
  sKinds := TkKind; sTexts := TkText; sInts := TkInt; sFloats := TkFloat;
  sTkN := TkN; sCur := Cur; sSrc := Src; sPos := Pos; sSLen := SLen;
  Tokenize(src);
  c := PyClosureAllocRow;
  { ref-share, not deep-copy — see PyMakeClosure; here Tokenize(src) just
    allocated these arrays fresh, so nothing else mutates them }
  Closures[c].Kinds  := TkKind;
  Closures[c].Texts  := TkText;
  Closures[c].Ints   := TkInt;
  Closures[c].Floats := TkFloat;
  Closures[c].NTok := TkN;
  Closures[c].BodyPos := 0;
  Closures[c].Params := params;
  SetLength(Closures[c].CapNames, 0);
  SetLength(Closures[c].CapVals, 0);
  Closures[c].CapN := 0;
  Closures[c].FlatSrc := True;
  Closures[c].ReqN := -1;          { unchecked unless pyclosure_setarity says otherwise }
  Closures[c].TotN := -1;
  TkKind := sKinds; TkText := sTexts; TkInt := sInts; TkFloat := sFloats;
  TkN := sTkN; Cur := sCur; Src := sSrc; Pos := sPos; SLen := sSLen;
  pyclosure_src_new := PyMakeClosureObj(c);
end;

function pyclosure_src_cap(obj: Pointer; const name: AnsiString; const v: Variant): Pointer;
var c, n: Integer;
begin
  c := PClosureObj(obj)^.Cidx;
  n := Closures[c].CapN;
  SetLength(Closures[c].CapNames, n + 1);
  SetLength(Closures[c].CapVals, n + 1);
  Closures[c].CapNames[n] := name;
  Closures[c].CapVals[n] := v;
  Closures[c].CapN := n + 1;
  pyclosure_src_cap := obj;
end;

function pyclosure_setarity(obj: Pointer; req, tot: Int64): Pointer;
{ Declare the closure's legal argument-count range. Chained after
  pyclosure_src_new like the caps are, and emitted ONLY by the lambda lowering
  — a builder that does not call this leaves ReqN = -1 and is never checked. }
var c: Integer;
begin
  pyclosure_setarity := obj;
  if obj = nil then Exit;
  if not pyclosure_is(obj) then Exit;
  c := Integer(PClosureObj(obj)^.Cidx);
  if (c < 0) or (c >= ClosureN) then Exit;
  Closures[c].ReqN := Integer(req);
  Closures[c].TotN := Integer(tot);
end;

{ The argument count `n` is legal for this callable, or it is not our business.
  False ONLY when the callee is a closure that declared a range and n is outside
  it — an unknown or unchecked callee always answers True, so this can never
  turn a working lenient path into a raising one. }
function PyClosureArityBad(o: Pointer; n: Int64; var lo, hi: Int64): Boolean;
var c: Integer;
begin
  PyClosureArityBad := False;
  lo := 0; hi := 0;
  if o = nil then Exit;
  if not pyclosure_is(o) then Exit;
  c := Integer(PClosureObj(o)^.Cidx);
  if (c < 0) or (c >= ClosureN) then Exit;
  if Closures[c].ReqN < 0 then Exit;              { unchecked }
  lo := Closures[c].ReqN;
  hi := Closures[c].TotN;
  PyClosureArityBad := (n < lo) or (n > hi);
end;

function PyBoundFnArityBad(o: Pointer; n: Int64; var lo, hi: Int64): Boolean;
{ The bound-fn twin of PyClosureArityBad. A LIFTED lambda enforced nothing,
  while the pyeval closure handling the same construct raised correctly — so
  `lambda x: x` called with two arguments answered 1 instead of raising, and
  called with none it SEGFAULTED. Which of the two paths a lambda took was
  decided by whether its body happened to contain a call.

  The legal range is NDefBase .. NDefBase + NDef: NDefBase is the caller-side
  index where defaulted params begin, i.e. the count of REQUIRED arguments, and
  each defaulted param widens the range by one. NDefBase < 0 = unchecked, which
  is every bound-fn the lambda lifter did not build. }
var b: PBoundFnObj;
begin
  PyBoundFnArityBad := False;
  lo := 0; hi := 0;
  if o = nil then Exit;
  if not pyboundfn_is(o) then Exit;
  b := PBoundFnObj(o);
  if b^.NDefBase < 0 then Exit;                   { unchecked }
  lo := b^.NDefBase;
  hi := b^.NDefBase + b^.NDef;
  PyBoundFnArityBad := (n < lo) or (n > hi);
end;

procedure PyRaiseArity(n, lo, hi: Int64);
{ CPython's wording is "takes N positional arguments but M were given"; the
  name of the lambda is not available here, so the message names the shape
  instead. TypeError, not a bare Exception, so `except TypeError:` catches it
  the way it does in CPython. }
var want: AnsiString;
begin
  { pystr_of, not IntToStr — a builtin unit has no sysutils. }
  if lo <> hi then
    want := 'from ' + pystr_of(lo) + ' to ' + pystr_of(hi) + ' positional arguments'
  else if lo = 1 then
    want := '1 positional argument'
  else
    want := pystr_of(lo) + ' positional arguments';
  raise TypeError.Create('<lambda>() takes ' + want + ' but '
    + pystr_of(n) + ' were given');
end;

procedure PyClassRefNew(const cb: Variant; nargs: Integer;
                        const a0, a1, a2, a3: Variant; var res: Variant);
{ `cls(args)` where `cls` holds a VT_CLASSREF variant — a NilPy class reached as
  a VALUE. Allocates the DYNAMIC class the blob names (size@InstanceSize), stamps
  its VMT, and runs its `create` through the blob's own method table, so a value
  holding A and one holding B each construct their own class from one call site.

  Why the ctor is reflected rather than dispatched through a VMT slot: a NilPy
  constructor is deliberately given NO virtual slot (pyparser's slot assignment
  excludes isCtor), so there is no slot number two unrelated classes could agree
  on. The RTTI method table already carries every method's name AND code address
  for the host bridge below, which makes the lookup a reuse rather than new
  machinery.

  The ctor MUST have all-Variant parameters — PyClassUsedAsValue widens it for
  exactly this reason. Calling one that was not widened would reinterpret a
  boxed variant as a raw Int64, so a mismatch raises instead: a wrong value here
  is unrecoverable, and the only way to reach it is a compiler bug.

  Result is a var-out parameter, not a function result: the same Variant-fn-
  return NRVO corruption PyClosureCall1 is written around. }
var
  cls: PClassRTTI;
  mi: PMethInfo;
  inst: Pointer;
  pk: PInt64;
  i, n, starIdx, nFixed: Integer;
  av: array[0..3] of Variant;    { the call's arguments, then the ctor's }
  star: TPyList;
  vp0: TVPr0; vp1: TVPr1; vp2: TVPr2; vp3: TVPr3; vp4: TVPr4;
  vs1: TVPrS1; vs2: TVPrS2; vs3: TVPrS3; sp1: TSPr1;
  strCtor: Boolean;
begin
  res := pynone;
  cls := PClassRTTI(Pointer(NativeInt(PPyRec(@cb)^.Payload)));
  if cls = nil then Exit;
  av[0] := a0; av[1] := a1; av[2] := a2; av[3] := a3;
  n := 0;
  starIdx := -1;
  mi := PyFindMethCI(cls, 'create');
  if mi <> nil then
  begin
    n := Integer(mi^.Arity) - 1;             { user args; index 0 is Self }
    { a `*args` parameter is a PACKED slot, not a pass-through one: the caller
      owes it a TPyList of every surplus argument. Its index rides in the meth
      Flags word (RTTI_METH_STARIDX_SHIFT) because nothing else in the reflected
      signature distinguishes it from an ordinary parameter. }
    starIdx := Integer((mi^.Flags shr 8) and 255) - 1;
    if n > 4 then
      raise TypeError.Create('constructing ' + cls^.NamePtr^ + ' through a '
        + 'class value supports at most 4 constructor parameters');
    if starIdx >= 0 then
    begin
      nFixed := starIdx - 1;                 { fixed user args before the star }
      if nargs < nFixed then PyRaiseArity(nargs, nFixed, nFixed);
      if starIdx > 3 then
        raise TypeError.Create('constructing ' + cls^.NamePtr^ + ' through a '
          + 'class value supports at most 2 fixed parameters before *args');
      star := TPyList.Create;
      for i := nFixed to nargs - 1 do star.append(av[i]);
    end
    else if n <> nargs then PyRaiseArity(nargs, n, n);
    pk := PInt64(mi^.ParamKinds);
    { `class E(Exception): pass` inherits Exception.Create(const msg:
      AnsiString) — a REAL signature this must marshal to, not a widening the
      frontend forgot. Recognised as its own shape rather than folded into the
      check below, because the check exists to catch exactly the case where the
      frontend DID forget. }
    strCtor := (n = 1) and (starIdx < 0) and (pk <> nil) and (pk[1] = TK_ANSISTR);
    if (pk <> nil) and (not strCtor) then
      for i := 1 to n do
        if (pk[i] <> TK_VARIANT) and (i <> starIdx) then
          raise TypeError.Create('cannot construct ' + cls^.NamePtr^
            + ' through a class VALUE: its constructor takes '
            + pystr_of(pk[i]) + ' at position ' + pystr_of(Int64(i))
            + ', which this path cannot marshal');
  end;
  inst := PXXObjAlloc(NativeInt(cls^.InstanceSize));
  PPointer(inst)^ := cls^.VMTPtr;            { stamp the dynamic class's VMT }
  if mi <> nil then
  begin
    { through a typed proc VARIABLE, not a cast-and-call — the same shape
      PyHostCall's trampoline uses below. }
    if strCtor then
    begin
      sp1 := TSPr1(mi^.Code);
      sp1(inst, pystr_of(av[0]));
    end
    else if starIdx >= 0 then
      case starIdx of
        1: begin vs1 := TVPrS1(mi^.Code); vs1(inst, star); end;
        2: begin vs2 := TVPrS2(mi^.Code); vs2(inst, av[0], star); end;
        3: begin vs3 := TVPrS3(mi^.Code); vs3(inst, av[0], av[1], star); end;
      end
    else
      case n of
        0: begin vp0 := TVPr0(mi^.Code); vp0(inst); end;
        1: begin vp1 := TVPr1(mi^.Code); vp1(inst, av[0]); end;
        2: begin vp2 := TVPr2(mi^.Code); vp2(inst, av[0], av[1]); end;
        3: begin vp3 := TVPr3(mi^.Code); vp3(inst, av[0], av[1], av[2]); end;
        4: begin vp4 := TVPr4(mi^.Code); vp4(inst, av[0], av[1], av[2], av[3]); end;
      end;
  end;
  { create(rc=1) then the slot's own +1, and no release of the alloc's — the
    convention every other object-producing site in this unit uses (the list and
    dict literal arms below). Being consistent matters more than being tight:
    reclamation is one open design (feature-nilpy-object-reclamation), and an
    extra release HERE against a convention that keeps the +1 elsewhere is a
    use-after-free, not a saving. }
  res := PyBoxObj(inst);
end;


function PyMakeClosure(fnIdx: Integer): Variant;
var c, i: Integer; r: PPyRec;
begin
  c := PyClosureAllocRow;
  { REFERENCE-share the token arrays instead of deep-copying: a full snapshot
    of the exec source per closure (every `ns["__body__"]` lookup!) was the
    dominant per-call leak in uforth's PYTHON-word path (~20 KB/exec). Safe
    because the tokenization cache never mutates a live buffer in place — on a
    miss the live refs are nilled first and Tokenize allocates fresh arrays
    (see the cache note above). }
  Closures[c].Kinds  := TkKind;
  Closures[c].Texts  := TkText;
  Closures[c].Ints   := TkInt;
  Closures[c].Floats := TkFloat;
  Closures[c].NTok    := TkN;
  Closures[c].BodyPos := FnBodyPos[fnIdx];
  Closures[c].Params  := FnParams[fnIdx];
  SetLength(Closures[c].CapNames, LclN);
  SetLength(Closures[c].CapVals, LclN);
  for i := 0 to LclN - 1 do
  begin
    Closures[c].CapNames[i] := LclNames[i];
    Closures[c].CapVals[i]  := LclVals[i];
  end;
  Closures[c].CapN := LclN;
  r := PPyRec(@Result);
  r^.VType   := VT_PYCLOSURE;
  r^.Payload := Int64(NativeInt(PyMakeClosureObj(c)));   { payload = closure-obj pointer }
end;

procedure EnvGet(const name: AnsiString; var res: Variant);
var i: Integer; tc: Int64;
begin
  i := LclFind(name);
  if i >= 0 then
    res := LclVals[i]
  { locals dict, THEN globals — Python's order. }
  else if (EnvL <> nil) and (EnvL.indexof(name) >= 0) then
    res := EnvL.fetch(name)
  else if (EnvG <> nil) and (EnvG.indexof(name) >= 0) then
    res := EnvG.fetch(name)
  else
  begin
    tc := PyTypeCode(name);
    if tc >= 0 then
    begin PPyRec(@res)^.VType := PY_TYPETAG; PPyRec(@res)^.Payload := tc; end
    else if FnFind(name) >= 0 then
      { a nested `def` used as a bare value (no call) — capture it as a closure so
        it survives being stored by a host method and called back later. }
      res := PyMakeClosure(FnFind(name))
    else if not Executing then
      res := MakeNone      { walking a skipped branch — names may be undefined }
    else
    begin
      EvalError('name not defined: ' + name);
      res := MakeNone;
    end;
  end;
end;

procedure ParseExpr(var res: Variant); forward;   { conditional/ternary — lowest }
procedure ParsePower(var res: Variant); forward;  { `**`, tighter than unary minus }
procedure ParseCall(const callee: AnsiString; var res: Variant); forward;
procedure ParseMethodCall(const recv: Variant; const mname: AnsiString;
                          var res: Variant); forward;
procedure CallUserFn(fnIdx: Integer; args: TPyList; var res: Variant); forward;

{ atom, then a postfix chain of `.attr` (field read) and `[index]` (subscript). }
procedure ParsePrimary(var res: Variant);
var
  name, fld: AnsiString;
  recv, idx, elem, hiTmp: Variant;
  li: TPyList;
  dd: TPyDict;
  loVal, hiVal: Int64;
  haveLo: Boolean;
begin
  { ---- targeted module intercepts (import is a no-op statement) ----
    sys.stdout.write(EXPR) / sys.stdout.flush() — the corpus's D. / D.R
    printers. stderr writes are swallowed (matching the compiled side). }
  if (TkKind[Cur] = PK_NAME) and (TkText[Cur] = 'sys') and
     (TkKind[Cur+1] = PK_OP) and (TkText[Cur+1] = '.') then
  begin
    Advance; Advance;                    { sys . }
    name := CurText; Advance;            { stdout / stderr }
    if (CurKind = PK_OP) and (CurText = '.') then Advance;
    fld := CurText; Advance;             { write / flush }
    ExpectOp('(');
    if not IsOp(')') then
    begin
      ParseExpr(recv);
      if (fld = 'write') and (name = 'stdout') and Executing then
        write(pystr_of(recv));
    end;
    ExpectOp(')');
    res := MakeNone;
    Exit;
  end;
  { ---- atom ---- }
  if TkKind[Cur] = PK_INT then
  begin res := pyvar_of_int(TkInt[Cur]); Advance; end
  else if TkKind[Cur] = PK_BIGINT then
  begin PyBigLit(TkText[Cur], res); Advance; end
  else if TkKind[Cur] = PK_FLOAT then
  begin res := MakeFloat(TkFloat[Cur]); Advance; end
  else if TkKind[Cur] = PK_BYTES then
  begin
    res := PyBoxObj(Pointer(bytes(TkText[Cur])));   { chars are the byte values }
    Advance;
  end
  else if TkKind[Cur] = PK_STR then
  begin res := MakeStr(TkText[Cur]); Advance; end
  else if IsOp('[') then
  begin
    { list literal }
    Advance;
    li := TPyList.Create;
    while not IsOp(']') do
    begin
      ParseExpr(elem);
      li.append(elem);
      if IsOp(',') then Advance
      else if not IsOp(']') then EvalError('expected , or ] in list literal');
    end;
    ExpectOp(']');
    PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
    PXXObjRetain(Pointer(li));   { slot owns +1 (magic-guarded) }
  end
  else if IsOp('{') then
  begin
    { dict literal { k: v, ... } or set literal { v, ... } (empty {} -> dict).
      A set is backed by a TPyList, per pylib's set model. }
    Advance;
    if IsOp('}') then
    begin
      Advance;
      dd := TPyDict.Create;
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(dd));
      PXXObjRetain(Pointer(dd));   { slot owns +1 (magic-guarded) }
    end
    else
    begin
      ParseExpr(elem);
      if IsOp(':') then
      begin
        { dict }
        Advance; ParseExpr(idx);   { idx = value }
        dd := TPyDict.Create; dd.store(elem, idx);
        while IsOp(',') do
        begin
          Advance;
          if IsOp('}') then Break;
          ParseExpr(elem); ExpectOp(':'); ParseExpr(idx);
          dd.store(elem, idx);
        end;
        ExpectOp('}');
        PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(dd));
        PXXObjRetain(Pointer(dd));   { slot owns +1 (magic-guarded) }
      end
      else
      begin
        { set -> TPyList }
        li := TPyList.Create; li.append(elem);
        while IsOp(',') do
        begin
          Advance;
          if IsOp('}') then Break;
          ParseExpr(elem); li.append(elem);
        end;
        ExpectOp('}');
        PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
        PXXObjRetain(Pointer(li));   { slot owns +1 (magic-guarded) }
      end;
    end;
  end
  else if TkKind[Cur] = PK_NAME then
  begin
    name := TkText[Cur];
    if name = 'True' then begin Advance; res := pyvar_of_bool(True); end
    else if name = 'False' then begin Advance; res := pyvar_of_bool(False); end
    else if name = 'None' then begin Advance; res := MakeNone; end
    else
    begin
      Advance;
      if IsOp('(') then ParseCall(name, res)
      else EnvGet(name, res);
    end;
  end
  else if IsOp('(') then
  begin
    { `(expr)` is a grouping; `(a, b, ...)` is a tuple. A tuple is backed by a
      TPyList (same VT_OBJECT representation), so membership (`x in (d, 10)`) and
      iteration work — uforth's WORD uses `mem[..] not in (d, 10)`. }
    Advance;
    ParseExpr(res);
    if IsOp(',') then
    begin
      li := TPyList.Create;
      li.append(res);
      while IsOp(',') do
      begin
        Advance;
        if IsOp(')') then Break;   { trailing comma }
        ParseExpr(elem);
        li.append(elem);
      end;
      { …and it must SAY it is a tuple. The backing TPyList is a list by
        default (PYSEQ_LIST is 0), so a tuple built here printed with brackets
        and answered `list` to type(); the compiled lowering stamps the kind via
        pylist_mark_tuple and this path simply never did, which made a tuple's
        display depend on whether its lambda took the interpreted or the lifted
        route (bug-nilpy-a-tuple-returned-from-a-lambda-becomes-a-list). }
      li.FKind := PYSEQ_TUPLE;
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
      PXXObjRetain(Pointer(li));   { slot owns +1 (magic-guarded) }
    end;
    ExpectOp(')');
  end
  else
  begin EvalError('unexpected token in expression: "' + TkText[Cur] + '"'); res := MakeNone; end;

  { ---- postfix chain ---- }
  while IsOp('.') or IsOp('[') do
  begin
    if IsOp('.') then
    begin
      Advance;
      if TkKind[Cur] <> PK_NAME then EvalError('expected attribute name after "."');
      fld := TkText[Cur]; Advance;
      recv := res;
      if IsOp('(') then
        ParseMethodCall(recv, fld, res)
      else if Executing then PyFieldGet(pyvarobj(recv), fld, res)
      else res := MakeNone;
    end
    else
    begin
      { subscript or slice }
      Advance;   { [ }
      recv := res;
      haveLo := False;
      if not IsOp(':') then begin ParseExpr(idx); haveLo := True; end;
      if IsOp(':') then
      begin
        { slice [lo:hi(:step)] — bounds int-coerced, omitted -> PY_SLICE_OMIT }
        loVal := PY_SLICE_OMIT; hiVal := PY_SLICE_OMIT;
        if haveLo then loVal := pyvar_to_int(idx);
        Advance;
        if (not IsOp(']')) and (not IsOp(':')) then
        begin ParseExpr(hiTmp); hiVal := pyvar_to_int(hiTmp); end;
        if IsOp(':') then   { step — parsed and ignored (M2) }
        begin Advance; if not IsOp(']') then ParseExpr(hiTmp); end;
        ExpectOp(']');
        if Executing then res := pyvar_slice(recv, loVal, hiVal) else res := MakeNone;
      end
      else
      begin
        { plain index — keep idx as a Variant so dict string keys work }
        if not haveLo then EvalError('empty subscript');
        ExpectOp(']');
        if Executing then PySubscriptGet(recv, idx, res) else res := MakeNone;
      end;
    end;
  end;
end;

procedure ParseUnary(var res: Variant);
var t: Variant;
begin
  if IsOp('-') then
  begin
    Advance; ParseUnary(t);
    { -a: promo-aware (0 - a) for a bignum — and for Low(Int64), whose plain
      neg wraps to itself while Python yields +2^63 }
    if IsPromoV(t) or (IsIntishV(t) and (PyToI64(t) = Low(Int64))) then
      PromoOp(pyvar_of_int(0), t, 2, res)
    else res := pyneg_v(t);
    Exit;
  end;
  if IsOp('+') then
  begin Advance; ParseUnary(res); Exit; end;
  if IsOp('~') then
  begin
    Advance; ParseUnary(t);
    { ~a = -a - 1; a bignum operand goes through the promo runtime }
    if IsPromoV(t) then
    begin
      PromoOp(pyvar_of_int(-1), t, 2, res);   { -1 - a == ~a }
      Exit;
    end;
    res := pyinvert_v(t);
    Exit;
  end;
  ParsePower(res);
end;

{ `**` — Python's power operator: right-associative, and binding TIGHTER than
  unary minus (`-2 ** 2` is `-(2**2)` = -4, not `(-2)**2`). ParseUnary calls
  here rather than straight to ParsePrimary, and the exponent recurses into
  ParseUnary (not ParsePower) so it can itself start with a unary op
  (`2 ** -1`) while still getting right-associativity for `2 ** 3 ** 2`
  through that same recursion. Mirrors the compiled frontend's `**`
  (parser.inc, ParseFactor) which lexes/parses the identical shape and lowers
  to the same pypow_v — this exec()-side grammar was simply missing
  (feature-pyeval-power-operator). }
procedure ParsePower(var res: Variant);
var b: Variant;
begin
  ParsePrimary(res);
  if IsOp('**') then
  begin
    Advance;
    ParseUnary(b);
    if not Executing then res := MakeNone
    else res := pypow_v(res, b);
  end;
end;

procedure ParseMul(var res: Variant);
var a, b, t: Variant;
begin
  ParseUnary(a);
  while IsOp('*') or IsOp('/') or IsOp('//') or IsOp('%') do
  begin
    if IsOp('*') then
    begin Advance; ParseUnary(b);
      { skip-mode: names read as None and pymul_v on a mixed pair raises —
        same rule as // below }
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIMul(a, b, t); a := t; end
      else if (PPyRec(@a)^.VType = 7) and
              (TObject(Pointer(PPyRec(@a)^.Payload)) is TPyBytes) and IsIntishV(b) then
        { b'..' * n — bytes repetition }
        a := PyBoxObj(Pointer(pybytes_repeat(TPyBytes(pyvarobj(a)), pyvar_to_int(b))))
      else a := pymul_v(a, b); end
    else if IsOp('//') then
    begin Advance; ParseUnary(b);
      { skipping a not-taken/def-skip branch: names read as None(0), so a real
        divide would be 0 div 0 -> runtime error 200. No side effect matters
        here, so just yield None. }
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIFloorDiv(a, b, t); a := t; end else a := pyfloordiv_v(a, b); end
    else if IsOp('%') then
    begin Advance; ParseUnary(b);
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIMod(a, b, t); a := t; end else a := pymod_v(a, b); end
    else begin Advance; ParseUnary(b);
      if not Executing then a := MakeNone
      else a := MakeFloat(pyvar_to_float(a) / pyvar_to_float(b)); end;
  end;
  res := a;
end;

procedure ParseAdd(var res: Variant);
var a, b, t: Variant;
begin
  ParseMul(a);
  while IsOp('+') or IsOp('-') do
  begin
    if IsOp('+') then
    begin Advance; ParseMul(b);
      { skip-mode: names read as None, and pyadd_v('...' + None) raises a
        TypeError out of a branch that is not even taken — the dead
        `raise E('msg: ' + name)` in uforth's tick. Yield None like //. }
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIAdd(a, b, t); a := t; end else a := pyadd_v(a, b); end
    else
    begin Advance; ParseMul(b);
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyISub(a, b, t); a := t; end else a := pysub_v(a, b); end;
  end;
  res := a;
end;

procedure ParseShift(var res: Variant);
var a, b, t: Variant;
begin
  ParseAdd(a);
  while IsOp('<<') or IsOp('>>') do
  begin
    if IsOp('<<') then begin Advance; ParseAdd(b); PyIShl(a, b, t); a := t; end
    else begin Advance; ParseAdd(b); PyIShr(a, b, t); a := t; end;
  end;
  res := a;
end;

procedure ParseBitAnd(var res: Variant);
var a, b, t: Variant;
begin
  ParseShift(a);
  while IsOp('&') do
  begin Advance; ParseShift(b);
    if IsIntishV(a) and IsIntishV(b) then begin PyIBitAnd(a, b, t); a := t; end else a := pybitand_v(a, b); end;
  res := a;
end;

procedure ParseBitXor(var res: Variant);
var a, b, t: Variant;
begin
  ParseBitAnd(a);
  while IsOp('^') do
  begin Advance; ParseBitAnd(b);
    if IsIntishV(a) and IsIntishV(b) then begin PyIBitXor(a, b, t); a := t; end else a := pybitxor_v(a, b); end;
  res := a;
end;

procedure ParseBitOr(var res: Variant);
var a, b, t: Variant;
begin
  ParseBitXor(a);
  while IsOp('|') do
  begin Advance; ParseBitXor(b);
    if IsIntishV(a) and IsIntishV(b) then begin PyIBitOr(a, b, t); a := t; end else a := pybitor_v(a, b); end;
  res := a;
end;

function PyCmpAhead: Boolean;
begin
  PyCmpAhead := IsOp('<') or IsOp('>') or IsOp('<=') or IsOp('>=')
    or IsOp('==') or IsOp('!=') or IsKw('is') or IsKw('in')
    or (IsKw('not') and (TkKind[Cur+1] = PK_NAME) and (TkText[Cur+1] = 'in'));
end;

procedure ParseCompare(var res: Variant);
var a, b: Variant; c: Int64; ok: Boolean;
begin
  ParseBitOr(a);
  if not PyCmpAhead then begin res := a; Exit; end;
  { Python chains: a < b < c == (a<b) and (b<c). `is`/`is not` are identity
    (value-equality here — sufficient for the `x is None` idiom); `in`/`not in`
    are membership. }
  ok := True;
  while PyCmpAhead do
  begin
    if IsOp('==') then begin Advance; ParseBitOr(b); ok := ok and PyIEq(a, b); end
    else if IsOp('!=') then begin Advance; ParseBitOr(b); ok := ok and (not PyIEq(a, b)); end
    else if IsOp('<') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c < 0); end
    else if IsOp('>') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c > 0); end
    else if IsOp('<=') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c <= 0); end
    else if IsOp('>=') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c >= 0); end
    else if IsKw('is') then
    begin
      Advance;
      if IsKw('not') then begin Advance; ParseBitOr(b); ok := ok and (not PyIsIdentity(a, b)); end
      else begin ParseBitOr(b); ok := ok and PyIsIdentity(a, b); end;
    end
    else if IsKw('in') then
    begin Advance; ParseBitOr(b); ok := ok and pyvar_contains(b, a); end
    else { not in }
    begin Advance; Advance; ParseBitOr(b); ok := ok and (not pyvar_contains(b, a)); end;
    a := b;
  end;
  res := pyvar_of_bool(ok);
end;

procedure ParseNot(var res: Variant);
var t: Variant;
begin
  if IsKw('not') then
  begin Advance; ParseNot(t); res := pyvar_of_bool(not pyvar_to_bool(t)); Exit; end;
  ParseCompare(res);
end;

procedure ParseAnd(var res: Variant);
var a, b: Variant; sv: Boolean;
begin
  ParseNot(a);
  while IsKw('and') do
  begin
    Advance;
    { SHORT-CIRCUIT via a skip-mode parse of the dead operand — uforth's TO:
      `isinstance(current, tuple) and len(current) == 3` must not evaluate
      len() when current is an int. Value semantics: a and b -> b if a. }
    if Executing and pyvar_to_bool(a) then
    begin
      ParseNot(b);
      a := b;
    end
    else
    begin
      sv := Executing; Executing := False;
      ParseNot(b);
      Executing := sv;
    end;
  end;
  res := a;
end;

procedure ParseOr(var res: Variant);
var a, b: Variant; sv: Boolean;
begin
  ParseAnd(a);
  while IsKw('or') do
  begin
    Advance;
    if Executing and not pyvar_to_bool(a) then
    begin
      ParseAnd(b);
      a := b;
    end
    else
    begin
      sv := Executing; Executing := False;
      ParseAnd(b);
      Executing := sv;
    end;
  end;
  res := a;
end;

{ ternary — lowest precedence. `A if C else B`. M1 evaluates all three eagerly
  and selects (the corpus branches are side-effect-free); a documented deviation
  mirroring pyor_v/pyand_v. }
procedure ParseExpr(var res: Variant);
var a, b, cond: Variant;
begin
  ParseOr(a);
  if IsKw('if') then
  begin
    Advance;
    ParseOr(cond);
    if not IsKw('else') then EvalError('ternary missing else');
    Advance;
    ParseExpr(b);
    if pyvar_to_bool(cond) then res := a else res := b;
    Exit;
  end;
  res := a;
end;

{ ---- builtins ---- }

{ isinstance(value, typeobj). typeobj is a PY_TYPETAG sentinel (payload = the
  type code from PyTypeCode). Maps the value's runtime tag/class to a code and
  compares. }
function PyIsInstance(const v: Variant; const t: Variant): Boolean;
var vt, want: Int64; o: TObject;
begin
  PyIsInstance := False;
  if PPyRec(@t)^.VType <> PY_TYPETAG then Exit;   { second arg was not a type }
  want := PPyRec(@t)^.Payload;
  vt := PPyRec(@v)^.VType;
  if (want = 2) then PyIsInstance := (vt = 1) or (vt = 2)                 { int }
  else if (want = 3) then PyIsInstance := (vt = 3)                        { float }
  else if (want = 4) then PyIsInstance := (vt = 4)                        { bool }
  else if (want = 6) then PyIsInstance := (vt = 6) or (vt = 5)            { str/char }
  else if vt = 7 then
  begin
    o := TObject(Pointer(PPyRec(@v)^.Payload));
    if want = 7 then PyIsInstance := o is TPyBytes
    else if want = 107 then PyIsInstance := o is TPyList
    else if want = 207 then PyIsInstance := o is TPyDict;
  end;
end;

{ hasattr(obj, name): a field or method of that name exists on obj's class.
  Also covers the dynamic-attribute store uforth uses (vm._trans_ptr lazy init). }
function PyHasAttr(const obj: Variant; const name: AnsiString): Boolean;
var cls: PClassRTTI; kind: Int64; p: Pointer;
begin
  PyHasAttr := False;
  { a CLASS held as a value: its attributes live in the bind registry, and its
    METHODS are in the blob it points at (no instance to walk from).
    bug-nilpy-class-attribute-through-a-class-reference-reads-garbage }
  if PPyRec(@obj)^.VType = 11 then
  begin
    cls := PClassRTTI(Pointer(PPyRec(@obj)^.Payload));
    if cls = nil then Exit;
    PyHasAttr := (PyClsAttrSlotOf(Pointer(cls), name, kind) <> nil) or
                 (PyFindMethCI(cls, name) <> nil);
    Exit;
  end;
  if PPyRec(@obj)^.VType <> 7 then Exit;
  cls := GetInstanceRTTI(Pointer(PPyRec(@obj)^.Payload));
  if cls = nil then Exit;
  p := GetFieldPtr(Pointer(PPyRec(@obj)^.Payload), cls, name, kind);
  if p <> nil then begin PyHasAttr := True; Exit; end;
  if PyFindMethCI(cls, name) <> nil then begin PyHasAttr := True; Exit; end;
  PyHasAttr := pydynattr_has(Pointer(PPyRec(@obj)^.Payload), name);
end;

{ range(...) materialised into a TPyList, boxed as a VT_OBJECT variant. }
function pyrange_list(args: TPyList): Variant;
var lo, hi, step, i: Int64; n: Integer; r: TPyList; ro: PPyRec;
begin
  n := args.count;
  if n = 1 then begin lo := 0; hi := pyvar_to_int(args.at(0)); step := 1; end
  else if n = 2 then
    begin lo := pyvar_to_int(args.at(0)); hi := pyvar_to_int(args.at(1)); step := 1; end
  else
    begin lo := pyvar_to_int(args.at(0)); hi := pyvar_to_int(args.at(1));
          step := pyvar_to_int(args.at(2)); end;
  r := TPyList.Create;
  if step > 0 then
  begin i := lo; while i < hi do begin r.append(pyvar_of_int(i)); i := i + step; end; end
  else if step < 0 then
  begin i := lo; while i > hi do begin r.append(pyvar_of_int(i)); i := i + step; end; end;
  ro := PPyRec(@Result); ro^.VType := 7; ro^.Payload := Int64(Pointer(r));
  PXXObjRetain(Pointer(r));   { slot owns +1 (magic-guarded) }
end;

procedure CallBuiltin(const name: AnsiString; args: TPyList;
                      const endKw, sepKw: AnsiString;
                      haveEnd, haveSep: Boolean; var res: Variant);
var i, nargs: Integer; s, sep, endc: AnsiString; cand, e: Variant; li: TPyList;
begin
  nargs := args.count;
  if name = 'int' then
  begin
    if nargs <> 1 then EvalError('int() expects 1 arg in M1');
    cand := args.at(0);
    { int() of a bignum is identity (stays arbitrary precision); else pyint_v }
    if IsPromoV(cand) then res := cand else res := pyint_v(cand);
    Exit;
  end;
  if name = 'float' then
  begin
    if nargs <> 1 then EvalError('float() expects 1 arg');
    res := MakeFloat(pyvar_to_float(args.at(0))); Exit;
  end;
  if name = 'abs' then
  begin
    if nargs <> 1 then EvalError('abs() expects 1 arg');
    cand := args.at(0);
    if IsPromoV(cand) or (IsIntishV(cand) and (PyToI64(cand) = Low(Int64))) then
    begin
      { promo, or Low(Int64) whose plain abs wraps to itself: 0 - a }
      if PromoCmp(cand, pyvar_of_int(0)) < 0 then PromoOp(pyvar_of_int(0), cand, 2, res)
      else res := cand;
    end
    else res := pyabs_v(cand);
    Exit;
  end;
  if name = 'bool' then
  begin
    if nargs <> 1 then EvalError('bool() expects 1 arg');
    res := pyvar_of_bool(pyvar_to_bool(args.at(0))); Exit;
  end;
  if name = 'len' then
  begin
    if nargs <> 1 then EvalError('len() expects 1 arg');
    res := pyvar_of_int(pylen_v(args.at(0))); Exit;
  end;
  if name = 'ord' then
  begin
    if nargs <> 1 then EvalError('ord() expects 1 arg');
    res := pyvar_of_int(pyord_v(args.at(0))); Exit;
  end;
  if name = 'chr' then
  begin
    if nargs <> 1 then EvalError('chr() expects 1 arg');
    res := MakeStr(pystr_ofchar(Chr(pyvar_to_int(args.at(0)) and $FF))); Exit;
  end;
  if name = 'str' then
  begin
    if nargs <> 1 then EvalError('str() expects 1 arg');
    res := MakeStr(pystr_of(args.at(0))); Exit;
  end;
  if name = 'hex' then
  begin
    if nargs <> 1 then EvalError('hex() expects 1 arg');
    res := MakeStr(hex(pyvar_to_int(args.at(0)))); Exit;
  end;
  if name = '__fmt' then
  begin
    { f-string hole: __fmt(value, 'spec') — see PreprocessFStrings }
    res := MakeStr(pyformat_of(args.at(0), pystr_of(args.at(1)))); Exit;
  end;
  if name = 'isinstance' then
  begin
    res := pyvar_of_bool(PyIsInstance(args.at(0), args.at(1))); Exit;
  end;
  if name = 'repr' then
  begin
    if nargs <> 1 then EvalError('repr() expects 1 arg');
    res := MakeStr(pyvar_repr(args.at(0))); Exit;
  end;
  if (name = 'bytearray') or (name = 'bytes') then
  begin
    { bytearray() / bytearray(n) / bytes(existing) }
    if nargs = 0 then
      res := PyBoxObj(Pointer(bytearray))
    else
    begin
      cand := args.at(0);
      if PPyRec(@cand)^.VType = 7 then
        res := PyBoxObj(Pointer(bytes(TPyBytes(pyvarobj(cand)))))
      else
        res := PyBoxObj(Pointer(bytearray(pyvar_to_int(cand))));
    end;
    Exit;
  end;
  if name = 'hasattr' then
  begin
    res := pyvar_of_bool(PyHasAttr(args.at(0), pystr_of(args.at(1)))); Exit;
  end;
  if name = 'min' then
  begin
    if nargs < 1 then EvalError('min() needs args');
    cand := args.at(0);
    for i := 1 to nargs - 1 do
    begin e := args.at(i); if pycmp_v(e, cand) < 0 then cand := e; end;
    res := cand; Exit;
  end;
  if name = 'max' then
  begin
    if nargs < 1 then EvalError('max() needs args');
    cand := args.at(0);
    for i := 1 to nargs - 1 do
    begin e := args.at(i); if pycmp_v(e, cand) > 0 then cand := e; end;
    res := cand; Exit;
  end;
  if name = 'list' then
  begin
    { list() -> a fresh empty list; list(xs) -> a shallow copy }
    li := TPyList.Create;
    if nargs > 0 then
    begin
      cand := args.at(0);
      if (PPyRec(@cand)^.VType = 7) and
         (TObject(Pointer(PPyRec(@cand)^.Payload)) is TPyList) then
        li.extend(TPyList(pyvarobj(cand)))
      else if PPyRec(@cand)^.VType = 6 then
      begin
        { list("abc") -> one-character strings, Python's str iteration }
        s := PPyAnsiString(@PPyRec(@cand)^.Payload)^;
        for i := 1 to Length(s) do
          li.append(MakeStr(s[i]));
      end
      else
        EvalError('list(): unsupported argument');
    end;
    res := PyBoxObj(Pointer(li));
    Exit;
  end;
  if name = 'reversed' then
  begin
    { reversed(list|str) -> a reversed LIST (materialised) }
    li := TPyList.Create;
    if nargs > 0 then
    begin
      cand := args.at(0);
      if (PPyRec(@cand)^.VType = 7) and
         (TObject(Pointer(PPyRec(@cand)^.Payload)) is TPyList) then
      begin
        for i := TPyList(pyvarobj(cand)).count - 1 downto 0 do
          li.append(TPyList(pyvarobj(cand)).at(i));
      end
      else if PPyRec(@cand)^.VType = 6 then
      begin
        s := PPyAnsiString(@PPyRec(@cand)^.Payload)^;
        for i := Length(s) downto 1 do
          li.append(MakeStr(s[i]));
      end
      else
        EvalError('reversed(): unsupported argument');
    end;
    res := PyBoxObj(Pointer(li));
    Exit;
  end;
  if name = 'range' then
  begin
    { range(stop) | range(start,stop) | range(start,stop,step) -> a materialised
      TPyList of ints (correctness-first; a lazy iterator can come later). }
    res := pyrange_list(args);
    Exit;
  end;
  if name = 'print' then
  begin
    s := '';
    if haveSep then sep := sepKw else sep := ' ';
    if haveEnd then endc := endKw else endc := #10;
    for i := 0 to nargs - 1 do
    begin
      if i > 0 then s := s + sep;
      s := s + pystr_of(args.at(i));
    end;
    write(s); write(endc);
    res := MakeNone; Exit;
  end;
  EvalError('unknown call: ' + name + '()');
  res := MakeNone;
end;

function IsHostName(const name: AnsiString): Boolean;
begin
  IsHostName := (name = 'push') or (name = 'pop')
             or (name = 'fpush') or (name = 'fpop');
end;

procedure ParseCall(const callee: AnsiString; var res: Variant);
var
  args: TPyList;
  v, vmv: Variant;
  kwname, endKw, sepKw: AnsiString;
  haveEnd, haveSep: Boolean;
  vmobj: Pointer;
begin
  ExpectOp('(');
  args := TPyList.Create;
  haveEnd := False; haveSep := False;
  endKw := ''; sepKw := '';
  while not IsOp(')') do
  begin
    { keyword arg?  NAME '=' expr  (but not '==') }
    if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP)
       and (TkText[Cur+1] = '=') then
    begin
      kwname := TkText[Cur];
      Advance; Advance;   { name '=' }
      ParseExpr(v);
      if kwname = 'end' then begin endKw := pystr_of(v); haveEnd := True; end
      else if kwname = 'sep' then begin sepKw := pystr_of(v); haveSep := True; end
      else if kwname = 'flush' then { ignore }
      else EvalError('unsupported keyword arg: ' + kwname);
    end
    else
    begin
      ParseExpr(v);
      args.append(v);
    end;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('expected , or ) in call');
  end;
  ExpectOp(')');

  { skipped branch: consume the call but do not dispatch (no side effects) }
  if not Executing then begin res := MakeNone; args.Free; Exit; end;

  { user-defined nested function takes precedence (Python scoping) }
  if FnFind(callee) >= 0 then
  begin CallUserFn(FnFind(callee), args, res); args.Free; Exit; end;

  if IsHostName(callee) then
  begin
    { The receiver is not a separate "vm" global -- it is already IN the
      bound method `callee` itself resolves to (`env = {"push": b.push}`
      boxes b as push's `recv`). Reading it from a hardcoded "vm" key was
      uforth's own variable name leaking into the general exec() contract:
      any other caller's env (`{"draw": c.draw}`, no "vm" key at all)
      failed every host call with a message naming an identifier it never
      wrote (bug-pyeval-exec-requires-a-globals-key-named-vm). }
    if (EnvG = nil) or (EnvG.indexof(callee) < 0) then
      EvalError('host call ' + callee + ' but "' + callee + '" not in globals');
    vmv := EnvG.fetch(callee);
    if not pycallback_is(vmv) then
      EvalError('host call ' + callee + ' is not a bound method');
    vmobj := pybound_recv(vmv);
    { ParseCall's own loop above REFUSES any keyword it does not know, so a
      host call reached this way never carries an unbound keyword. }
    PyHostCall(vmobj, callee, args, TPyList(nil), res);
    args.Free;
    Exit;
  end;
  CallBuiltin(callee, args, endKw, sepKw, haveEnd, haveSep, res);
  args.Free;
end;

{ `( expr, ... )` into `args`; a `signed=<bool>` keyword arg (to_bytes/from_bytes)
  is captured into signedKw, other keyword args are ignored (e.g. byteorder is
  positional and consumed as an ordinary arg). }
procedure ParseArgs(args: TPyList; kwNames: TPyList; var signedKw: Boolean);
var v, itv, item: Variant; kw, gname: AnsiString;
    exprStart, endPos, gi, gn: Integer;
    gres, glist: TPyList; go: TObject; gby: TPyBytes; gs: AnsiString;
    gexec: Boolean;
begin
  signedKw := False;
  ExpectOp('(');
  while not IsOp(')') do
  begin
    if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP) and (TkText[Cur+1] = '=') then
    begin
      kw := TkText[Cur]; Advance; Advance; ParseExpr(v);
      { `signed=` steers pyint.to_bytes and is consumed out-of-band. Every other
        keyword arg is a host-method kwarg (uforth's `define_word(name,
        native=_w)`): append it positionally. uforth passes kwargs in the
        method's declaration order, and PyHostCall fills any omitted trailing
        params from their per-kind defaults, so positional order is correct. }
      if kw = 'signed' then signedKw := pyvar_to_bool(v)
      else
      begin
        { pad the parallel list up to here FIRST, so every earlier argument is
          marked positional at its own index — then append the two together.
          Padding only at the end would put the '' markers after the names. }
        if kwNames <> nil then
          while kwNames.count < args.count do kwNames.append(MakeStr(''));
        args.append(v);
        if kwNames <> nil then kwNames.append(MakeStr(kw));
      end;
    end
    else
    begin
      { PROBE pass with Executing off: finds the expression's span end without
        evaluating (a genexp's item expr mentions the not-yet-bound loop var).
        Not a genexp -> re-parse for real; genexp -> per-item replays below. }
      exprStart := Cur;
      gexec := Executing;
      Executing := False;
      ParseExpr(v);
      Executing := gexec;
      if not IsKw('for') then
      begin
        Cur := exprStart;
        ParseExpr(v);
      end
      else
      begin
        { GENERATOR EXPRESSION `EXPR for NAME in ITER` — evaluated eagerly to a
          list (`''.join(chr(vm.memory[a+i]) for i in range(u))`, the corpus's
          string builders). The item expression's TOKEN SPAN is re-evaluated
          per element with NAME bound — same replay trick the typing pre-pass
          uses. No `if` filter and one loop variable: honest errors otherwise. }
        Advance;
        if TkKind[Cur] <> PK_NAME then EvalError('genexp: expected a name after for');
        gname := TkText[Cur]; Advance;
        if not IsKw('in') then EvalError('genexp: expected in');
        Advance;
        ParseExpr(itv);
        endPos := Cur;
        if not gexec then
        begin
          { skip-mode (a def registration walk): structure parsed, nothing runs }
          v := MakeNone;
          args.append(v);
          if IsOp(',') then Advance
          else if not IsOp(')') then EvalError('expected , or ) in method call');
          Continue;
        end;
        gres := TPyList.Create;
        if PPyRec(@itv)^.VType = 6 then
        begin
          gs := PPyAnsiString(@PPyRec(@itv)^.Payload)^;
          for gi := 1 to Length(gs) do
          begin
            LclSet(gname, MakeStr(gs[gi]));
            Cur := exprStart; ParseExpr(item);
            gres.append(item);
          end;
        end
        else
        begin
          go := TObject(Pointer(PPyRec(@itv)^.Payload));
          if go is TPyList then
          begin
            glist := TPyList(go); gn := glist.count;
            for gi := 0 to gn - 1 do
            begin
              LclSet(gname, glist.at(gi));
              Cur := exprStart; ParseExpr(item);
              gres.append(item);
            end;
          end
          else if go is TPyBytes then
          begin
            gby := TPyBytes(go); gn := gby.count;
            for gi := 0 to gn - 1 do
            begin
              LclSet(gname, pyvar_of_int(gby.at(gi)));
              Cur := exprStart; ParseExpr(item);
              gres.append(item);
            end;
          end
          else
            EvalError('genexp: unsupported iterable');
        end;
        Cur := endPos;
        PPyRec(@v)^.VType := 7;
        PPyRec(@v)^.Payload := Int64(NativeInt(Pointer(gres)));
        PXXObjRetain(Pointer(gres));   { slot owns +1 (magic-guarded) }
      end;
      args.append(v);
    end;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('expected , or ) in method call');
  end;
  ExpectOp(')');
end;

{ recv.mname(args). Dispatches str / list / bytes / dict methods to pylib; any
  other VT_OBJECT receiver is treated as a reflected HOST object and routed
  through the trampoline (PyHostCall). Method coverage is the corpus subset;
  unsupported names error clearly. }
procedure ParseMethodCall(const recv: Variant; const mname: AnsiString;
                          var res: Variant);
var
  args: TPyList;
  kwNames: TPyList;
  o: TObject; li: TPyList; by: TPyBytes;
  s: AnsiString; b2: TPyBytes;
  i: Integer;
  signedKw: Boolean;
  rvt: Int64;
begin
  args := TPyList.Create;
  kwNames := TPyList.Create;
  ParseArgs(args, kwNames, signedKw);
  { trailing positionals get their '' markers here — see the pad in ParseArgs }
  while kwNames.count < args.count do kwNames.append(MakeStr(''));
  if not Executing then begin res := MakeNone; kwNames.Free; Exit; end;
  rvt := PPyRec(@recv)^.VType;

  { int.to_bytes(length, byteorder, *, signed=…) -> bytes }
  if (rvt = 1) or (rvt = 2) or (rvt = 4) then
  begin
    if mname = 'to_bytes' then
    begin
      by := pyint_to_bytes(pyvar_to_int(recv), pyvar_to_int(args.at(0)), signedKw);
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(by));
      PXXObjRetain(Pointer(by));   { slot owns +1 (magic-guarded) }
      Exit;
    end;
    EvalError('int method not supported: ' + mname);
  end;

  { int.from_bytes(bytes, byteorder, *, signed=…) — a static method on the int
    type object (a PY_TYPETAG sentinel). }
  if rvt = PY_TYPETAG then
  begin
    if (PPyRec(@recv)^.Payload = 2) and (mname = 'from_bytes') then
    begin
      res := pyvar_of_int(pyint_from_bytes(TPyBytes(pyvarobj(args.at(0))), signedKw));
      Exit;
    end;
    EvalError('type method not supported: ' + mname);
  end;

  { string methods }
  if rvt = 6 then
  begin
    s := PAnsiString(@PPyRec(@recv)^.Payload)^;
    if mname = 'upper' then res := MakeStr(pystr_upper(s))
    else if mname = 'lower' then res := MakeStr(pystr_lower(s))
    else if mname = 'strip' then
    begin
      if args.count = 0 then res := MakeStr(pystr_strip(s))
      else res := MakeStr(pystr_strip_chars(s, pystr_of(args.at(0))));
    end
    else if mname = 'join' then
      res := MakeStr(pystr_join(s, TPyList(pyvarobj(args.at(0)))))
    else if mname = 'startswith' then
      res := pyvar_of_bool(pystr_startswith(s, pystr_of(args.at(0))))
    else if mname = 'endswith' then
      res := pyvar_of_bool(pystr_endswith(s, pystr_of(args.at(0))))
    else if mname = 'rjust' then
    begin
      if args.count >= 2 then
        res := MakeStr(pystr_rjust_c(s, pyvar_to_int(args.at(0)), pystr_of(args.at(1))))
      else
        res := MakeStr(pystr_rjust(s, pyvar_to_int(args.at(0))));
    end
    else if mname = 'find' then
      res := pyvar_of_int(pystr_find(s, pystr_of(args.at(0))))
    else if mname = 'index' then
    begin
      { str.index: find, but a MISS is a ValueError instead of -1 }
      i := pystr_find(s, pystr_of(args.at(0)));
      if i < 0 then EvalError('ValueError: substring not found');
      res := pyvar_of_int(i);
    end
    else if mname = 'encode' then
    begin
      b2 := pystr_encode(s);
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(b2));
      PXXObjRetain(Pointer(b2));   { slot owns +1 (magic-guarded) }
    end
    else
      EvalError('str method not supported: ' + mname);
    Exit;
  end;

  if PPyRec(@recv)^.VType = 7 then
  begin
    o := TObject(Pointer(PPyRec(@recv)^.Payload));
    if o is TPyList then
    begin
      li := TPyList(o);
      if mname = 'append' then begin li.append(args.at(0)); res := MakeNone; end
      else if mname = 'insert' then
        begin li.insert(pyvar_to_int(args.at(0)), args.at(1)); res := MakeNone; end
      else if mname = 'pop' then
      begin
        if args.count = 0 then res := li.pop
        else res := li.pop(pyvar_to_int(args.at(0)));
      end
      else if mname = 'clear' then begin li.clear; res := MakeNone; end
      else if mname = 'extend' then
        begin li.extend(TPyList(pyvarobj(args.at(0)))); res := MakeNone; end
      else
        EvalError('list method not supported: ' + mname);
      Exit;
    end;
    if o is TPyBytes then
    begin
      by := TPyBytes(o);
      if mname = 'append' then begin by.append(pyvar_to_int(args.at(0))); res := MakeNone; end
      else if mname = 'decode' then
      begin
        if args.count = 0 then res := MakeStr(by.decode('utf-8'))
        else res := MakeStr(by.decode(pystr_of(args.at(0))));
      end
      else if mname = 'extend' then
        begin by.extend(TPyBytes(pyvarobj(args.at(0)))); res := MakeNone; end
      else
        EvalError('bytes method not supported: ' + mname);
      Exit;
    end;
    { otherwise: a reflected host object (vm) — dispatch through the trampoline }
    PyHostCall(Pointer(PPyRec(@recv)^.Payload), mname, args, kwNames, res);
    kwNames.Free;
    Exit;
  end;

  EvalError('cannot call method ' + mname + ' on this value');
end;

{ ---- statements ---- }

procedure SkipSeparators;
begin
  while IsOp(';') or (CurKind = PK_NL) do Advance;
end;

procedure ExecStatement; forward;

{ Execute (or, if `doEval` is False, merely skip) the suite that follows a `:`.
  A suite is either INLINE — simple statements to end of line — or a BLOCK:
  NEWLINE INDENT statement+ DEDENT. Skipping walks the same grammar with
  Executing off so the token cursor lands past the suite either way. }
procedure ExecSuite(doEval: Boolean);
var saved: Boolean;
begin
  saved := Executing;
  Executing := saved and doEval;
  if CurKind = PK_NL then
  begin
    { block form }
    while CurKind = PK_NL do Advance;
    if CurKind <> PK_INDENT then
    begin Executing := saved; EvalError('expected an indented block'); end;
    Advance;   { INDENT }
    while (CurKind <> PK_DEDENT) and (CurKind <> PK_EOF) do
    begin
      if BreakFlag or ReturnFlag then
      begin
        { unwinding a loop or function: fast-skip the rest with eval off }
        Executing := False;
      end;
      ExecStatement;
      SkipSeparators;
    end;
    if CurKind = PK_DEDENT then Advance;
  end
  else
  begin
    { inline form: simple statements until newline / dedent / eof }
    while (CurKind <> PK_NL) and (CurKind <> PK_DEDENT) and (CurKind <> PK_EOF) do
    begin
      if BreakFlag or ReturnFlag then Executing := False;
      ExecStatement;
      while IsOp(';') do Advance;
    end;
  end;
  Executing := saved;
end;

procedure ExecIf;
var cond: Variant; done: Boolean;
begin
  Advance;   { if }
  ParseExpr(cond);
  ExpectOp(':');
  done := Executing and pyvar_to_bool(cond);
  ExecSuite(done);
  while IsKw('elif') do
  begin
    Advance;
    ParseExpr(cond);
    ExpectOp(':');
    if (not done) and Executing and pyvar_to_bool(cond) then
    begin ExecSuite(True); done := True; end
    else
      ExecSuite(False);
  end;
  if IsKw('else') then
  begin
    Advance; ExpectOp(':');
    ExecSuite(Executing and (not done));
  end;
end;

procedure ExecWhile;
var cond: Variant; condPos: Integer; guard: Int64;
begin
  Advance;   { while }
  condPos := Cur;
  guard := 0;
  while True do
  begin
    Cur := condPos;
    ParseExpr(cond);
    ExpectOp(':');
    if Executing and pyvar_to_bool(cond) then
    begin
      ExecSuite(True);
      if ReturnFlag then Break;   { unwind to the function frame }
      if BreakFlag then begin BreakFlag := False; Break; end;
      guard := guard + 1;
      if guard > 100000000 then EvalError('while: iteration guard tripped');
    end
    else
    begin
      ExecSuite(False);   { skip body once to advance past it }
      Break;
    end;
  end;
end;

procedure ExecFor;
var
  varName: AnsiString;
  iter: Variant;
  lst: TPyList;
  bodyPos, i, n: Integer;
begin
  Advance;   { for }
  if CurKind <> PK_NAME then EvalError('for: expected a loop variable');
  varName := TkText[Cur]; Advance;
  if not IsKw('in') then EvalError('for: expected "in"');
  Advance;
  ParseExpr(iter);
  ExpectOp(':');
  bodyPos := Cur;
  if not Executing then begin ExecSuite(False); Exit; end;
  if PPyRec(@iter)^.VType <> 7 then
    EvalError('for: M1/M2 iterate over a list/range only');
  lst := TPyList(Pointer(PPyRec(@iter)^.Payload));
  n := lst.count;
  if n = 0 then begin ExecSuite(False); Exit; end;
  for i := 0 to n - 1 do
  begin
    LclSet(varName, lst.at(i));
    Cur := bodyPos;
    ExecSuite(True);
    if ReturnFlag then Exit;   { unwind to the function frame }
    if BreakFlag then begin BreakFlag := False; Exit; end;
  end;
  { after the last real iteration Cur is already past the suite }
end;

function IsAssignOp(const s: AnsiString): Boolean;
begin
  IsAssignOp := (s = '=') or (s = '+=') or (s = '-=') or (s = '*=')
    or (s = '//=') or (s = '%=') or (s = '&=') or (s = '|=') or (s = '^=')
    or (s = '<<=') or (s = '>>=');
end;

{ Token-only scan: does a NAME (.attr | [expr])* chain from Cur end at an assign
  op? Decides assignment vs expression statement without evaluating anything. }
function AssignmentAhead: Boolean;
var p, depth: Integer;
begin
  AssignmentAhead := False;
  p := Cur;
  if TkKind[p] <> PK_NAME then Exit;
  p := p + 1;
  while True do
  begin
    if (TkKind[p] = PK_OP) and (TkText[p] = '.') then
    begin
      p := p + 1;
      if TkKind[p] <> PK_NAME then Exit;
      p := p + 1;
    end
    else if (TkKind[p] = PK_OP) and (TkText[p] = '[') then
    begin
      depth := 1; p := p + 1;
      while (depth > 0) and (TkKind[p] <> PK_EOF) do
      begin
        if (TkKind[p] = PK_OP) and (TkText[p] = '[') then depth := depth + 1
        else if (TkKind[p] = PK_OP) and (TkText[p] = ']') then depth := depth - 1;
        p := p + 1;
      end;
    end
    else
      Break;
  end;
  AssignmentAhead := (TkKind[p] = PK_OP) and IsAssignOp(TkText[p]);
end;

{ Assignment to a local, an attribute (obj.field), or a subscript
  (container[index]) — plain and augmented. The receiver chain is walked and
  intermediate steps read normally; only the final step is the lvalue. }
procedure DoAssignment;
var
  base, aug, fld: AnsiString;
  recv, idx, rhs, cur, v, tcont, tindex, hiTmp: Variant;
  tkind: Integer;   { 0 local, 1 attribute, 2 subscript, 3 slice }
  tname: AnsiString;
  tobj: Pointer;
  tlo, thi: Int64;
  isSlice, haveIdx: Boolean;
begin
  base := TkText[Cur]; Advance;
  tkind := 0; tname := base; tobj := nil;
  if IsOp('.') or IsOp('[') then
  begin
    EnvGet(base, recv);
    while True do
    begin
      if IsOp('.') then
      begin
        Advance;
        fld := TkText[Cur]; Advance;
        if (TkKind[Cur] = PK_OP) and IsAssignOp(TkText[Cur]) then
        begin tkind := 1; tobj := pyvarobj(recv); tname := fld; Break; end;
        if Executing then PyFieldGet(pyvarobj(recv), fld, recv) else recv := MakeNone;
      end
      else if IsOp('[') then
      begin
        Advance;
        isSlice := False; haveIdx := False; tlo := PY_SLICE_OMIT; thi := PY_SLICE_OMIT;
        if not IsOp(':') then begin ParseExpr(idx); haveIdx := True; end;
        if IsOp(':') then
        begin
          isSlice := True;
          if haveIdx then tlo := pyvar_to_int(idx);
          Advance;
          if (not IsOp(']')) and (not IsOp(':')) then begin ParseExpr(hiTmp); thi := pyvar_to_int(hiTmp); end;
          if IsOp(':') then begin Advance; if not IsOp(']') then ParseExpr(hiTmp); end;
        end;
        ExpectOp(']');
        if (TkKind[Cur] = PK_OP) and IsAssignOp(TkText[Cur]) then
        begin
          if isSlice then begin tkind := 3; tcont := recv; end
          else begin tkind := 2; tcont := recv; tindex := idx; end;
          Break;
        end;
        if Executing then
        begin
          if isSlice then recv := pyvar_slice(recv, tlo, thi)
          else PySubscriptGet(recv, idx, recv);
        end
        else recv := MakeNone;
      end
      else
        EvalError('invalid assignment target');
    end;
  end;

  aug := TkText[Cur]; Advance;
  ParseExpr(rhs);
  if not Executing then Exit;

  if aug <> '=' then
  begin
    if tkind = 3 then EvalError('augmented slice assignment not supported');
  end;

  if aug = '=' then v := rhs
  else
  begin
    if tkind = 0 then EnvGet(tname, cur)
    else if tkind = 1 then PyFieldGet(tobj, tname, cur)
    else PySubscriptGet(tcont, tindex, cur);
    { promo-aware for the int-ish operators (the double-cell re-sign step
      `lo -= 0x10000000000000000` is an augassign with a bignum RHS) }
    if aug = '+=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIAdd(cur, rhs, v) else v := pyadd_v(cur, rhs); end
    else if aug = '-=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyISub(cur, rhs, v) else v := pysub_v(cur, rhs); end
    else if aug = '*=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIMul(cur, rhs, v) else v := pymul_v(cur, rhs); end
    else if aug = '//=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIFloorDiv(cur, rhs, v) else v := pyfloordiv_v(cur, rhs); end
    else if aug = '%=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIMod(cur, rhs, v) else v := pymod_v(cur, rhs); end
    else if aug = '&=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIBitAnd(cur, rhs, v) else v := pybitand_v(cur, rhs); end
    else if aug = '|=' then v := pybitor_v(cur, rhs)
    else if aug = '^=' then v := pybitxor_v(cur, rhs)
    else if aug = '<<=' then PyIShl(cur, rhs, v)
    else PyIShr(cur, rhs, v);
  end;

  if tkind = 0 then LclSet(tname, v)
  else if tkind = 1 then PyFieldSet(tobj, tname, v)
  else if tkind = 2 then PySubscriptSet(tcont, tindex, v)
  else PySliceSet(tcont, tlo, thi, v);
end;

{ del NAME | del container[index] (chains supported; final step deleted). }
procedure ExecDel;
var base, fld: AnsiString; recv, idx: Variant;
begin
  Advance;   { del }
  if CurKind <> PK_NAME then EvalError('del: expected a target');
  base := TkText[Cur]; Advance;
  if not (IsOp('.') or IsOp('[')) then
  begin
    if Executing then LclDelete(base);
    Exit;
  end;
  EnvGet(base, recv);
  while True do
  begin
    if IsOp('.') then
    begin
      Advance; fld := TkText[Cur]; Advance;
      if Executing then PyFieldGet(pyvarobj(recv), fld, recv) else recv := MakeNone;
    end
    else if IsOp('[') then
    begin
      Advance; ParseExpr(idx); ExpectOp(']');
      if not (IsOp('.') or IsOp('[')) then
      begin
        if Executing then PyDelSubscript(recv, idx);
        Exit;
      end;
      if Executing then PySubscriptGet(recv, idx, recv) else recv := MakeNone;
    end
    else
      EvalError('del: invalid target');
  end;
end;

{ raise ExcName('message') | raise ExcName | raise. The exception class name is
  consumed as a bare identifier (it is not a defined value); the first call
  argument, if any, is the message. Propagated by halting with a diagnostic —
  catchable try/except is a later milestone. }
procedure ExecRaise;
var excName, msg: AnsiString; args: TPyList; v: Variant; sk: Boolean;
begin
  Advance;   { raise }
  msg := '';
  if CurKind = PK_NAME then
  begin
    excName := TkText[Cur]; Advance;
    if IsOp('(') then
    begin
      args := TPyList.Create;
      ParseArgs(args, TPyList(nil), sk);   { a raise's argument list has no keywords to bind }
      if args.count > 0 then begin v := args.at(0); msg := pystr_of(v); end;
    end;
  end
  else
    excName := 'Exception';
  if Executing then
  begin
    writeln('pyeval: ', excName, ': ', msg);
    Halt(1);
  end;
end;

{ def name(p1, p2, ...): SUITE — registers the function and skips its body. }
procedure ExecDef;
var name, params, pname: AnsiString; bodyPos: Integer; dv: Variant;
begin
  Advance;   { def }
  if CurKind <> PK_NAME then EvalError('def: expected a name');
  name := TkText[Cur]; Advance;
  ExpectOp('(');
  params := '';
  while not IsOp(')') do
  begin
    if CurKind <> PK_NAME then EvalError('def: expected a parameter name');
    pname := TkText[Cur]; Advance;
    if IsOp('=') then
    begin
      { `def _const(v, _lo=lo):` — a DEFAULT bound at def time (the corpus's
        capture idiom). Evaluate NOW and store as a LOCAL of the defining
        scope: PyMakeClosure snapshots the scope, so the body resolves the
        name through the capture. Not appended to params — the call site
        never passes it. }
      Advance;
      ParseExpr(dv);
      if Executing then LclSet(pname, dv);
    end
    else
    begin
      if params <> '' then params := params + ',';
      params := params + pname;
    end;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('def: expected , or ) in params');
  end;
  ExpectOp(')');
  ExpectOp(':');
  bodyPos := Cur;
  if Executing then FnRegister(name, bodyPos, params);
  ExecSuite(False);   { skip the body — it runs on call }
end;

procedure ExecStatement;
var v: Variant;
begin
  StmtWasCompound := False;
  { compound statements (self-terminating at DEDENT). Set the flag AFTER the call
    returns — the nested statements inside the block reset it. }
  if IsKw('if') then begin ExecIf; StmtWasCompound := True; Exit; end;
  if IsKw('while') then begin ExecWhile; StmtWasCompound := True; Exit; end;
  if IsKw('for') then begin ExecFor; StmtWasCompound := True; Exit; end;
  if IsKw('def') then begin ExecDef; StmtWasCompound := True; Exit; end;
  if IsKw('del') then begin ExecDel; Exit; end;
  if IsKw('raise') then begin ExecRaise; Exit; end;
  if IsKw('break') then begin Advance; if Executing then BreakFlag := True; Exit; end;
  if IsKw('return') then
  begin
    Advance;
    if (CurKind = PK_NL) or (CurKind = PK_EOF) or (CurKind = PK_DEDENT) or IsOp(';') then
      v := MakeNone
    else
      ParseExpr(v);
    if Executing then begin ReturnValue := v; ReturnFlag := True; end;
    Exit;
  end;
  if IsKw('pass') then begin Advance; Exit; end;
  if IsKw('import') then
  begin
    { `import sys` / `import time` — the module NAMES resolve through the
      targeted intercepts (sys.stdout.write etc.); the statement itself is
      consumed and ignored. Dotted names allowed. }
    Advance;
    while (CurKind = PK_NAME) or ((CurKind = PK_OP) and (CurText = '.')) or
          ((CurKind = PK_OP) and (CurText = ',')) do
      Advance;
    Exit;
  end;
  if IsKw('continue') or IsKw('elif') or IsKw('else') then
    EvalError('statement "' + CurText + '" is not supported yet');

  if (TkKind[Cur] = PK_NAME) and AssignmentAhead then
  begin DoAssignment; Exit; end;

  { expression statement (e.g. push(x), pop()) — value discarded }
  ParseExpr(v);
end;

{ Call a nested `def` function: fresh local scope bound to the params, body run
  from its recorded token position, `return` value captured. The caller's scope,
  cursor, and return state are saved and restored so calls nest and re-enter. }
procedure CallUserFn(fnIdx: Integer; args: TPyList; var res: Variant);
var
  savedNames: array of AnsiString;
  savedVals:  array of Variant;
  savedN, savedCur, i, ai, plen: Integer;
  savedRF: Boolean;
  savedRV: Variant;
  params, pname: AnsiString;
begin
  { save the caller frame }
  savedN := LclN;
  SetLength(savedNames, LclN); SetLength(savedVals, LclN);
  for i := 0 to LclN - 1 do begin savedNames[i] := LclNames[i]; savedVals[i] := LclVals[i]; end;
  savedCur := Cur; savedRF := ReturnFlag; savedRV := ReturnValue;

  { fresh scope + bind params positionally }
  LclN := 0;
  params := FnParams[fnIdx];
  plen := Length(params); ai := 0; pname := ''; i := 1;
  while i <= plen + 1 do
  begin
    if (i > plen) or (params[i] = ',') then
    begin
      if pname <> '' then
      begin
        if ai < args.count then LclSet(pname, args.at(ai)) else LclSet(pname, MakeNone);
        ai := ai + 1; pname := '';
      end;
    end
    else
      pname := pname + params[i];
    i := i + 1;
  end;

  { run the body }
  ReturnFlag := False; ReturnValue := MakeNone;
  Cur := FnBodyPos[fnIdx];
  ExecSuite(True);
  res := ReturnValue;

  { restore the caller frame }
  ReturnFlag := savedRF; ReturnValue := savedRV;
  Cur := savedCur;
  LclN := savedN;
  if Length(LclNames) < savedN then SetLength(LclNames, savedN);
  if Length(LclVals) < savedN then SetLength(LclVals, savedN);
  for i := 0 to savedN - 1 do begin LclNames[i] := savedNames[i]; LclVals[i] := savedVals[i]; end;
end;

{ Run a captured closure (PyMakeClosure) with `args`. The whole interpreter state
  is swapped to the closure's snapshot — its own token buffer, a fresh scope
  holding the captured free vars plus the bound params, and the body cursor — then
  fully restored, so a closure can run while another EvalPyStmts / closure is on
  the stack (a native PYTHON word may call another). }
procedure PyClosureInvoke(cidx: Integer; args: TPyList; var res: Variant);
var
  sKinds:  array of Integer;   sTexts: array of AnsiString;
  sInts:   array of Int64;     sFloats: array of Double;
  sTkN, sCur, sLclN, sFnN, i, ai, plen: Integer;
  sLclNames: array of AnsiString; sLclVals: array of Variant;
  sFnName:  array of AnsiString;   sFnBodyPos: array of Integer;
  sFnParams: array of AnsiString;
  sRF, sExec, sBreak: Boolean; sRV: Variant;
  params, pname: AnsiString;
begin
  { save caller interpreter state }
  sKinds := TkKind; sTexts := TkText; sInts := TkInt; sFloats := TkFloat;
  sTkN := TkN; sCur := Cur; sLclN := LclN; sFnN := FnN;
  SetLength(sLclNames, LclN); SetLength(sLclVals, LclN);
  for i := 0 to LclN - 1 do begin sLclNames[i] := LclNames[i]; sLclVals[i] := LclVals[i]; end;
  SetLength(sFnName, FnN); SetLength(sFnBodyPos, FnN); SetLength(sFnParams, FnN);
  for i := 0 to FnN - 1 do
  begin sFnName[i] := FnName[i]; sFnBodyPos[i] := FnBodyPos[i]; sFnParams[i] := FnParams[i]; end;
  sRF := ReturnFlag; sRV := ReturnValue; sExec := Executing; sBreak := BreakFlag;

  { install the closure's snapshot token buffer }
  TkKind := Closures[cidx].Kinds; TkText := Closures[cidx].Texts;
  TkInt  := Closures[cidx].Ints;  TkFloat := Closures[cidx].Floats;
  TkN := Closures[cidx].NTok;

  { fresh scope: captured free vars first, params second (params shadow) }
  LclN := 0; FnN := 0;
  for i := 0 to Closures[cidx].CapN - 1 do
    LclSet(Closures[cidx].CapNames[i], Closures[cidx].CapVals[i]);
  params := Closures[cidx].Params;
  plen := Length(params); ai := 0; pname := ''; i := 1;
  while i <= plen + 1 do
  begin
    if (i > plen) or (params[i] = ',') then
    begin
      if pname <> '' then
      begin
        { A DEFAULTED parameter is bound as a CAP under its own name — that is
          how both lambda lowerings spell a build-time default — and the caps
          were installed just above. So an UNSUPPLIED parameter must leave that
          value alone; overwriting it with None is what stopped a defaulted name
          from being listed as a parameter at all, and listing it is what makes a
          caller's argument override the default
          (bug-nilpy-a-lambda-call-is-not-arity-checked). A supplied argument
          still wins: f(3, 4) is 12, f(3) is 3*k. A parameter with no default and
          no argument still reads None, exactly as before. }
        if ai < args.count then LclSet(pname, args.at(ai))
        else if LclFind(pname) < 0 then LclSet(pname, MakeNone);
        ai := ai + 1; pname := '';
      end;
    end
    else pname := pname + params[i];
    i := i + 1;
  end;

  Executing := True; BreakFlag := False;
  ReturnFlag := False; ReturnValue := MakeNone;
  Cur := Closures[cidx].BodyPos;
  if Closures[cidx].FlatSrc then
  begin
    { source-built closure: flat statements at indent 0 until EOF }
    SkipSeparators;
    while (CurKind <> PK_EOF) and not ReturnFlag do
    begin
      ExecStatement;
      SkipSeparators;
    end;
  end
  else
    ExecSuite(True);
  res := ReturnValue;

  { restore caller interpreter state }
  TkKind := sKinds; TkText := sTexts; TkInt := sInts; TkFloat := sFloats;
  TkN := sTkN; Cur := sCur;
  FnN := sFnN;
  if Length(FnName) < sFnN then
  begin SetLength(FnName, sFnN); SetLength(FnBodyPos, sFnN); SetLength(FnParams, sFnN); end;
  for i := 0 to sFnN - 1 do
  begin FnName[i] := sFnName[i]; FnBodyPos[i] := sFnBodyPos[i]; FnParams[i] := sFnParams[i]; end;
  LclN := sLclN;
  if Length(LclNames) < sLclN then begin SetLength(LclNames, sLclN); SetLength(LclVals, sLclN); end;
  for i := 0 to sLclN - 1 do begin LclNames[i] := sLclNames[i]; LclVals[i] := sLclVals[i]; end;
  ReturnFlag := sRF; ReturnValue := sRV; Executing := sExec; BreakFlag := sBreak;
end;

{ ONE dispatcher for `<variant>(args)`, keeping the result. The four shapes a
  NilPy callable value can have — a {code, recv} pair (tag 8), a pyeval closure
  object, a lifted bound-fn object, and a plain compiled code address — are told
  apart HERE, at run time, instead of by guessing the tag at compile time. The
  var-out calls into Result sidestep the Variant-fn-return NRVO corruption, the
  same reason PyClosureCall1 is written that way.

  A closure object may arrive either as a tag-9 variant or as a bare payload
  pointer (a lambda bound to a name), so both are probed. }
function PyCallableObj(const cb: Variant): Pointer;
{ The callable OBJECT a variant carries, or nil when the payload is a plain code
  address (or nothing at all). }
begin
  PyCallableObj := nil;
  if PPyRec(@cb)^.Payload = 0 then Exit;
  PyCallableObj := Pointer(NativeInt(PPyRec(@cb)^.Payload));
  if pyclosure_is(PyCallableObj) or pyboundfn_is(PyCallableObj) then Exit;
  PyCallableObj := nil;
end;

procedure PyNotCallable(const cb: Variant);
{ The callee guard: raise TypeError for a value that cannot possibly be code,
  instead of jumping to its payload and dumping core
  (bug-nilpy-calling-a-non-callable-segfaults).

  An ALLOW-LIST, not a refusal list, and that inversion is the whole point of
  feature-nilpy-a-callable-value-needs-its-own-variant-tag. It USED to be a
  refusal list because it had to be: a plain def's code address boxed as
  VT_INT64 (2) — the same tag `3 + 4`, `2**40` and `int("99")` wear, since
  1-vs-2 is an integer WIDTH distinction and says nothing about callability.
  Refusing tag 2 would have broken every ordinary call through a def value (106
  of them across the .npy corpus, measured), so `(3 + 4)(x)` jumped to address 7
  and dumped core and NO test on the tag could have stopped it.

  A callable now carries VT_CALLABLE (12) — stamped in the backends'
  variant-boxing tag selection off the SOURCE IR node (IRSrcIsCallable: a code
  address, or the pyboundfn_*/pyclosure_* chain a lambda in an argument position
  lowers to), see defs.inc — so the tags finally partition and the guard can
  state what IS callable:

    8  VT_BOUNDMETHOD  {code, recv} pair (pybound_new)
    9  VT_PYCLOSURE    pyeval source closure
    10 VT_BOUNDFN      lifted bound-fn
    11 VT_CLASSREF     a class used as a value — constructs
    12 VT_CALLABLE     a plain compiled code address
    7  VT_OBJECT       ONLY when its class defines __call__

  Everything else is refused, which is strictly more than the old list caught:
  VT_INT64, VT_EMPTY-with-a-payload, and any tag added later that forgets to say
  whether it is code. 8 and 11 are unreachable in practice (pycallback_is /
  pyclassref_is short-circuit ahead of every caller) and are listed anyway — an
  allow-list fails CLOSED, so naming one tag too many costs nothing and omitting
  one costs a TypeError on working code. }
var t: Int64;
begin
  { TypeError, not a bare Exception: `except TypeError:` must see it. This was
    the one raise site of the family left in pyeval when the pylib ones were
    converted (bug-nilpy-pytypeerror-halts-instead-of-raising), so `n()` on a
    None binding was catchable only as `except Exception:` while every other
    NilPy TypeError matched by name. The class name is printed by the unhandled
    handler, so the text stays identical without the literal prefix. }
  if PPyRec(@cb)^.Payload = 0 then
    raise TypeError.Create('object is not callable — the name is '
      + 'None (an import that did not resolve, or a value never assigned)');

  t := PPyRec(@cb)^.VType;
  if (t = VT_NC_BOUNDMETHOD) or (t = VT_PYCLOSURE) or (t = VT_BOUNDFN) or
     (t = VT_CLASSREF) or (t = VT_CALLABLE) or (t = VT_BTYPE) then Exit;

  { A class INSTANCE (tag 7) — a list, dict, tuple or a user object. Callable
    only if its class defines `__call__`; otherwise the payload is an instance
    pointer and jumping to it faults. An instance that DOES define `__call__`
    falls through to the existing path rather than being refused here — wiring
    that dispatch up is its own ticket
    (bug-nilpy-a-call-dunder-on-an-instance-is-not-dispatched); refusing it
    would be a regression, so this arm stays narrow. }
  if t = VT_NC_OBJECT then
  begin
    if PyFindMethCI(GetInstanceRTTI(Pointer(NativeInt(PPyRec(@cb)^.Payload))),
                    '__call__') = nil then
      raise TypeError.Create('object is not callable');
    Exit;
  end;

  { the allow-list's closing arm: an int, a float, a string, a promo, a tag
    nobody has classified — none of them is code. }
  raise TypeError.Create('object is not callable');
end;

function PyCallDunder(const cb: Variant; n: Integer;
                      const a0, a1, a2: Variant; var res: Variant): Boolean;
{ `obj(...)` where obj is a class INSTANCE whose class defines `__call__` —
  Python's callable-object protocol. Answers False for anything else, so each
  pyvar_callv<n> can offer the value here and fall through unchanged.

  PyNotCallable has always let this shape past (it refuses a tag-7 instance only
  when the class has NO `__call__`), and past it the payload — an INSTANCE
  POINTER — was called as a code address, which dumps core.

  Only the DYNAMIC receiver ever got here, and that is why the bug outlived so
  much: `c(5)` on a named local works and always has, because the frontend knows
  c's class and lowers a direct method call. Reach the same instance through a
  dict, a list, a call result or an unannotated parameter and the receiver is a
  variant, this dispatcher runs, and it faulted. Measured on `pinned`: `c(5)`
  printed 10, `{"c": c}["c"](5)` segfaulted
  (bug-nilpy-a-call-dunder-on-an-instance-is-not-dispatched, whose own repro is
  the passing static form).

  PyHostCall is the existing by-name trampoline and handles the ABI shapes, so
  this is a receiver + an argument list and nothing else. It is reached only
  after PyFindMethCI has confirmed the method, which is what makes PyHostCall's
  missing-method Halt unreachable from here. }
var inst: Pointer; args: TPyList;
begin
  PyCallDunder := False;
  if PPyRec(@cb)^.VType <> VT_NC_OBJECT then Exit;
  inst := Pointer(NativeInt(PPyRec(@cb)^.Payload));
  if inst = nil then Exit;
  if PyFindMethCI(GetInstanceRTTI(inst), '__call__') = nil then Exit;
  args := TPyList.Create;
  if n >= 1 then args.append(a0);
  if n >= 2 then args.append(a1);
  if n >= 3 then args.append(a2);
  PyHostCall(inst, '__call__', args, TPyList(nil), res);
  args.Free;
  PyCallDunder := True;
end;

function pyvar_callv0(const cb: Variant): Variant;
var o: Pointer; aLo, aHi: Int64; f0: TPyCallFn0; args: TPyList;
begin
  Result := pynone;
  if pycallback_is(cb) then begin Result := pybound_callv0(cb); Exit; end;
  { a CLASS reached as a VALUE constructs — told apart by its own tag, which
    is the whole reason VT_CLASSREF exists (an untagged blob address is
    indistinguishable from the code address a plain def rides as, and this
    site would have jumped into the RTTI blob). }
  if pyclassref_is(cb) then begin PyClassRefNew(cb, 0, pynone, pynone, pynone, pynone, Result); Exit; end;
  { the zero-argument form of the same thing — `list()` through a binding }
  if pybtype_is(cb) then begin pybtype_call0(cb, Result); Exit; end;
  PyNotCallable(cb);
  if PyCallDunder(cb, 0, pynone, pynone, pynone, Result) then Exit;
  o := PyCallableObj(cb);
  if PyClosureArityBad(o, 0, aLo, aHi) then PyRaiseArity(0, aLo, aHi);
  if PyBoundFnArityBad(o, 0, aLo, aHi) then PyRaiseArity(0, aLo, aHi);
  if o <> nil then
  begin
    if pyclosure_is(o) then
    begin
      args := TPyList.Create;
      PyClosureInvoke(PClosureObj(o)^.Cidx, args, Result);
      args.Free;
    end
    else pyboundfn_callvn(o, pynone, pynone, pynone, 0, Result);
    Exit;
  end;
  f0 := TPyCallFn0(Pointer(NativeInt(PPyRec(@cb)^.Payload)));
  Result := f0();
end;

function pyvar_callv1(const cb: Variant; const a0: Variant): Variant;
var o: Pointer; aLo, aHi: Int64; f1: TPyCallFn1; args: TPyList;
begin
  Result := pynone;
  if pycallback_is(cb) then begin Result := pybound_callv1(cb, a0); Exit; end;
  { a CLASS reached as a VALUE constructs — told apart by its own tag, which
    is the whole reason VT_CLASSREF exists (an untagged blob address is
    indistinguishable from the code address a plain def rides as, and this
    site would have jumped into the RTTI blob). }
  if pyclassref_is(cb) then begin PyClassRefNew(cb, 1, a0, pynone, pynone, pynone, Result); Exit; end;
  { a BUILTIN TYPE reached as a value CONVERTS — `text_type = str` then
    `text_type(x)`. Beside the class arm because it is the same concept: a type
    held as a value, called. bug-n-a-type-name-is-not-a-first-class-value }
  if pybtype_is(cb) then begin pybtype_call1(cb, a0, Result); Exit; end;
  PyNotCallable(cb);
  if PyCallDunder(cb, 1, a0, pynone, pynone, Result) then Exit;
  o := PyCallableObj(cb);
  if PyClosureArityBad(o, 1, aLo, aHi) then PyRaiseArity(1, aLo, aHi);
  if PyBoundFnArityBad(o, 1, aLo, aHi) then PyRaiseArity(1, aLo, aHi);
  if o <> nil then
  begin
    if pyclosure_is(o) then
    begin
      args := TPyList.Create;
      args.append(a0);
      PyClosureInvoke(PClosureObj(o)^.Cidx, args, Result);
      args.Free;
    end
    else pyboundfn_callvn(o, a0, pynone, pynone, 1, Result);
    Exit;
  end;
  f1 := TPyCallFn1(Pointer(NativeInt(PPyRec(@cb)^.Payload)));
  Result := f1(a0);
end;

function pyvar_callv2(const cb: Variant; const a0, a1: Variant): Variant;
var o: Pointer; aLo, aHi: Int64; f2: TPyCallFn2; args: TPyList;
begin
  Result := pynone;
  if pycallback_is(cb) then begin Result := pybound_callv2(cb, a0, a1); Exit; end;
  { a CLASS reached as a VALUE constructs — told apart by its own tag, which
    is the whole reason VT_CLASSREF exists (an untagged blob address is
    indistinguishable from the code address a plain def rides as, and this
    site would have jumped into the RTTI blob). }
  if pyclassref_is(cb) then begin PyClassRefNew(cb, 2, a0, a1, pynone, pynone, Result); Exit; end;
  PyNotCallable(cb);
  if PyCallDunder(cb, 2, a0, a1, pynone, Result) then Exit;
  o := PyCallableObj(cb);
  if PyClosureArityBad(o, 2, aLo, aHi) then PyRaiseArity(2, aLo, aHi);
  if PyBoundFnArityBad(o, 2, aLo, aHi) then PyRaiseArity(2, aLo, aHi);
  if o <> nil then
  begin
    if pyclosure_is(o) then
    begin
      args := TPyList.Create;
      args.append(a0); args.append(a1);
      PyClosureInvoke(PClosureObj(o)^.Cidx, args, Result);
      args.Free;
    end
    else pyboundfn_callvn(o, a0, a1, pynone, 2, Result);
    Exit;
  end;
  f2 := TPyCallFn2(Pointer(NativeInt(PPyRec(@cb)^.Payload)));
  Result := f2(a0, a1);
end;

function pyvar_callv4(const cb: Variant; const a0, a1, a2, a3: Variant): Variant;
{ The FOUR-argument dispatcher. Arities past 3 used to keep the older lowering,
  which unboxes the callee and calls through the payload as a code ADDRESS —
  fine for a plain def, and a SEGFAULT for a lambda, whose value is a closure or
  bound-fn OBJECT that no tag guard there recognises. `q = lambda a,b,c,e: ...;
  q(1,2,3,4)` therefore jumped to the object pointer. A def bound to a name and
  called with four arguments always worked, which is what made the crash look
  like a lambda-arity problem rather than a missing dispatch.

  The interpreted closure has no arity limit — its arguments travel as a TPyList
  — so it is served exactly as at arity 3. The shapes whose bridges DO stop at
  three raise here instead of being handed a truncated argument list: dropping
  arguments silently is the failure mode this dispatcher exists to remove.
  bug-nilpy-a-four-parameter-lambda-segfaults-when-called }
var o: Pointer; aLo, aHi: Int64; f4: TPyCallFn4; args: TPyList;
begin
  Result := pynone;
  if pycallback_is(cb) then begin Result := pybound_callv4(cb, a0, a1, a2, a3); Exit; end;
  if pyclassref_is(cb) then begin PyClassRefNew(cb, 4, a0, a1, a2, a3, Result); Exit; end;
  PyNotCallable(cb);
  o := PyCallableObj(cb);
  if PyClosureArityBad(o, 4, aLo, aHi) then PyRaiseArity(4, aLo, aHi);
  if PyBoundFnArityBad(o, 4, aLo, aHi) then PyRaiseArity(4, aLo, aHi);
  if o <> nil then
  begin
    if pyclosure_is(o) then
    begin
      args := TPyList.Create;
      args.append(a0); args.append(a1); args.append(a2); args.append(a3);
      PyClosureInvoke(PClosureObj(o)^.Cidx, args, Result);
      args.Free;
      Exit;
    end;
    { a LIFTED bound-fn: the bridge carries three own arguments, and a lambda of
      four own parameters is not lifted for exactly that reason — so this is
      unreachable today, and says so rather than truncating if it ever is not. }
    raise TypeError.Create('a compiled closure takes at most 3 arguments, got 4');
  end;
  { a plain compiled code address — what the old lowering handled correctly }
  f4 := TPyCallFn4(Pointer(NativeInt(PPyRec(@cb)^.Payload)));
  Result := f4(a0, a1, a2, a3);
end;

function pyvar_callv3(const cb: Variant; const a0, a1, a2: Variant): Variant;
var o: Pointer; aLo, aHi: Int64; f3: TPyCallFn3; args: TPyList;
begin
  Result := pynone;
  if pycallback_is(cb) then begin Result := pybound_callv3(cb, a0, a1, a2); Exit; end;
  { a CLASS reached as a VALUE constructs — told apart by its own tag, which
    is the whole reason VT_CLASSREF exists (an untagged blob address is
    indistinguishable from the code address a plain def rides as, and this
    site would have jumped into the RTTI blob). }
  if pyclassref_is(cb) then begin PyClassRefNew(cb, 3, a0, a1, a2, pynone, Result); Exit; end;
  PyNotCallable(cb);
  if PyCallDunder(cb, 3, a0, a1, a2, Result) then Exit;
  o := PyCallableObj(cb);
  if PyClosureArityBad(o, 3, aLo, aHi) then PyRaiseArity(3, aLo, aHi);
  if PyBoundFnArityBad(o, 3, aLo, aHi) then PyRaiseArity(3, aLo, aHi);
  if o <> nil then
  begin
    if pyclosure_is(o) then
    begin
      args := TPyList.Create;
      args.append(a0); args.append(a1); args.append(a2);
      PyClosureInvoke(PClosureObj(o)^.Cidx, args, Result);
      args.Free;
    end
    else pyboundfn_callvn(o, a0, a1, a2, 3, Result);
    Exit;
  end;
  f3 := TPyCallFn3(Pointer(NativeInt(PPyRec(@cb)^.Payload)));
  Result := f3(a0, a1, a2);
end;

function pyvar_of_callable(p: Pointer): Variant;
{ A lambda's value is a heap OBJECT pointer, and a pointer-typed local never
  reaches the dynamic-call path (that path keys on tyVariant). Box it, tagging a
  pyeval closure as VT_PYCLOSURE so the existing tag-9 consumers keep working,
  and a lifted bound-fn as VT_BOUNDFN.

  The bound-fn arm used to stamp VType 0 and "ride as a bare payload". That was
  survivable for DISPATCH — every consumer tells the shapes apart by the
  object's magic (pyclosure_is / pyboundfn_is / PyCallableObj), never by the tag
  — but VType 0 is VT_EMPTY, which matches nothing in EmitVariantClear /
  EmitVariantRetain, so the slot holding an escaping closure was not a managed
  slot and the object was never released. Every escaping closure leaked itself
  and everything it had retained
  (bug-nilpy-bound-fn-closure-objects-are-never-freed). }
begin
  PPyRec(@Result)^.Payload := Int64(NativeInt(p));
  if pyclosure_is(p) then PPyRec(@Result)^.VType := VT_PYCLOSURE
  else if pyboundfn_is(p) then PPyRec(@Result)^.VType := VT_BOUNDFN
  { anything else here is a plain compiled code address. It used to ride as
    VT_EMPTY ("a bare payload"), which is what a None binding also wears — so
    the guard's payload test was the only thing separating the two. VT_CALLABLE
    says what it is; the payload is still static, so nothing manages it. }
  else PPyRec(@Result)^.VType := VT_CALLABLE;
end;

{ Reverse bridge, 1-arg form: NilPy's PyMakeDynCall calls this when the callee
  VARIANT is a VT_PYCLOSURE. The var-out call into Result sidesteps the
  Variant-fn-return NRVO corruption. }
function PyClosureCall1(const clv: Variant; const a0: Variant): Variant;
var args: TPyList;
begin
  args := TPyList.Create;
  args.append(a0);
  PyClosureInvoke(PClosureObj(NativeInt(PPyRec(@clv)^.Payload))^.Cidx, args, Result);
  args.Free;
end;

{ Is `p` a closure object rather than a real compiled function address? The
  call-through-field site (`word.native(vm2)`) uses this to choose the bridge.
  Reading the first word of a code pointer is safe; a real function's opening
  bytes will not equal the sentinel address. }
function pyclosure_is(p: Pointer): Boolean;
begin
  pyclosure_is := (p <> nil) and (PClosureObj(p)^.Magic = @PyClosureMagicMarker);
end;

{ Reverse bridge, POINTER form: `word.native(vm2)` where the Callable field holds
  a closure object (uforth's VARIABLE/CONSTANT words). The closure's result is
  discarded — a Forth native word is `-> None`. }
function pyclosure_call1(objptr: Pointer; const a0: Variant): Variant;
var args: TPyList;
begin
  args := TPyList.Create;
  args.append(a0);
  PyClosureInvoke(PClosureObj(objptr)^.Cidx, args, Result);
  args.Free;
end;

type
  { Local to this dispatcher: a callable value reaching `key: Pointer` has
    already lost its Variant wrapper (and with it, for a bound-method-shaped
    value, the VType=8 tag that would normally answer pycallback_is) -- these
    match pylib.pas's own private TPyCbF1/TPyCbM1, redeclared here since that
    pair lives in pylib's implementation section, not its interface. }
  TPyKeyCbF1 = function(const a0: Variant): Variant;
  TPyKeyCbM1 = function(recv: Pointer; const a0: Variant): Variant;
  { matches pylib.pas's own private TPyBoundRec -- the {code,recv} pair
    pybound_new allocates; also private to that unit's implementation. }
  TPyKeyBoundRec = record Code, Recv: Pointer; end;
  PPyKeyBoundRec = ^TPyKeyBoundRec;

{ Call an arbitrary callable VALUE reaching a Pointer-typed parameter (a
  `key=`/`cmp=`-style callback argument) with one Variant argument, keeping
  the result -- unlike pyclosure_call_ptr/pyboundfn_call_ptr, which exist for
  the discard-the-result (event-handler) callers and answer 0. Covers all
  four shapes a NilPy callable value can take:
    - a bound method / a builtin or plain def used as a bare value
      (`f = len`, `f = obj.method`) -- pybound_new's {code,recv} pair,
      identified on the bare pointer via PXXObjIsBoundPair (the Variant-level
      VType=8 tag that pycallback_is normally reads is not available here);
    - a pyeval closure (an interpreted lambda/nested-def) -- pyclosure_is;
    - a lifted bound-fn (a compiled lambda/nested-def with captures) --
      pyboundfn_is;
    - a plain compiled def's bare code address (the one shape with no tag at
      all, identified purely by elimination of the other three).
  feature-nilpy-callable-value-unified-dispatch }
function PyCallKey1(key: Pointer; const a0: Variant): Variant;
var code, recv: Pointer; m1: TPyKeyCbM1; f1: TPyKeyCbF1; res: Variant;
begin
  Result := pynone;
  if key = nil then Exit;
  if PXXObjIsBoundPair(key) then
  begin
    code := PPyKeyBoundRec(key)^.Code;
    recv := PPyKeyBoundRec(key)^.Recv;
    if code = nil then Exit;
    if recv = nil then begin f1 := TPyKeyCbF1(code); Result := f1(a0); end
    else begin m1 := TPyKeyCbM1(code); Result := m1(recv, a0); end;
    Exit;
  end;
  if pyclosure_is(key) then begin Result := pyclosure_call1(key, a0); Exit; end;
  if pyboundfn_is(key) then
  begin
    res := pynone;
    pyboundfn_callv(key, a0, res);
    Result := res;
    Exit;
  end;
  { shape D: a bare compiled def's code address, no tag to check }
  f1 := TPyKeyCbF1(key);
  Result := f1(a0);
end;

function min(l: TPyList; key: Pointer): Variant; overload;
var i: Integer; bestK, k: Variant;
begin
  if (l = nil) or (l.count = 0) then
    raise ValueError.Create('min() iterable argument is empty');
  Result := l.at(0);
  if key = nil then bestK := Result else bestK := PyCallKey1(key, Result);
  for i := 1 to l.count - 1 do
  begin
    if key = nil then k := l.at(i) else k := PyCallKey1(key, l.at(i));
    if pyvar_lt(k, bestK) then
    begin
      bestK := k;
      Result := l.at(i);
    end;
  end;
end;

function max(l: TPyList; key: Pointer): Variant; overload;
var i: Integer; bestK, k: Variant;
begin
  if (l = nil) or (l.count = 0) then
    raise ValueError.Create('max() iterable argument is empty');
  Result := l.at(0);
  if key = nil then bestK := Result else bestK := PyCallKey1(key, Result);
  for i := 1 to l.count - 1 do
  begin
    if key = nil then k := l.at(i) else k := PyCallKey1(key, l.at(i));
    if pyvar_gt(k, bestK) then
    begin
      bestK := k;
      Result := l.at(i);
    end;
  end;
end;

function sorted(d: TPyDict; key: Pointer; reverse: Boolean): TPyList; overload;
begin
  if d = nil then Result := TPyList.Create
  else Result := sorted(d.keylist, key, reverse);
end;

{ `sorted("cba")` -> ['a','b','c']. Python sorts any ITERABLE, and a str is one.
  Without this overload the AnsiString handle bound to the TPyList overload and
  was dereferenced as an object: `sorted(s)` printed an empty list for a short
  string and SEGFAULTED in a larger program
  (bug-nilpy-sorted-over-a-string-segfaults). Same shape as list(const s), which
  already had its own overload — this is the sibling that was missing. }
function sorted(const s: AnsiString; key: Pointer; reverse: Boolean): TPyList; overload;
begin
  { pystr_charlist, not a private byte walk: `sorted("béa")` split the é into
    its two UTF-8 bytes and answered four elements where list() answered three.
    Same lesson as the note on pystr_charlist — one exploder, not two.
    bug-nilpy-non-ascii-string-surface-measured }
  Result := sorted(pystr_charlist(s), key, reverse);
end;

function sorted(const v: Variant; key: Pointer; reverse: Boolean): TPyList; overload;
var o: TObject; seq: TPyList;
begin
  { dispatch on the runtime tag through pylib's ONE object->sequence chain
    (pyseq_of_obj), exactly as list(const v: Variant) does. This was a
    hand-copied chain of four `is` tests and, like the other copies, it never
    grew the user-`__iter__` arm: `sorted(bag)` answered [] on an object that
    iterates correctly in a `for`
    (bug-nilpy-builtins-over-a-user-iterable-answer-empty). Sorting a dict
    still sorts its KEYS — pyseq_of_obj answers the key list. }
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    seq := pyseq_of_obj(o);
    if seq <> nil then begin Result := sorted(seq, key, reverse); Exit; end;
  end;
  if pyvartag(v) = 6 then begin Result := sorted(pystr_of(v), key, reverse); Exit; end;
  Result := TPyList.Create;      { None / empty }
end;

function sorted(l: TPyList; key: Pointer; reverse: Boolean): TPyList;
var r, keys: TPyList; i, j: Integer; kv, ev: Variant; swapped: Boolean;
begin
  r := TPyList.Create;
  Result := r;
  if l = nil then Exit;
  keys := TPyList.Create;
  for i := 0 to l.count - 1 do
  begin
    ev := l.at(i);
    r.append(ev);
    if key <> nil then keys.append(PyCallKey1(key, ev))
    else keys.append(ev);
  end;
  { insertion sort, moving the key list in lockstep so a key is computed once }
  for i := 1 to r.count - 1 do
  begin
    j := i;
    swapped := True;
    while (j > 0) and swapped do
    begin
      if reverse then swapped := pyvar_gt(keys.at(j), keys.at(j - 1))
      else swapped := pyvar_lt(keys.at(j), keys.at(j - 1));
      if swapped then
      begin
        ev := r.at(j); r.put(j, r.at(j - 1)); r.put(j - 1, ev);
        kv := keys.at(j); keys.put(j, keys.at(j - 1)); keys.put(j - 1, kv);
        Dec(j);
      end;
    end;
  end;
  keys.Free;
end;

{ `map(f, xs)` over an arbitrary callable VALUE -- the general form beside
  the existing map(int|str|float, xs) conversion shims. Same PyCallKey1
  dispatch sorted()'s key= already uses, so every callable shape (a lifted
  lambda, a plain def, a bound method, and a builtin via
  PyGetOrMakeCallableWrapper) works here for free.
  feature-nilpy-aggregate-builtins }
function pymap_call(key: Pointer; l: TPyList): TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  if (l = nil) or (key = nil) then Exit;
  for i := 0 to l.count - 1 do
    Result.append(PyCallKey1(key, l.at(i)));
end;

{ `filter(f, xs)` -- keep the elements where f(x) is truthy. `filter(None,
  xs)` (Python's own "keep the truthy elements" shorthand) is key=nil here. }
function pyfilter_call(key: Pointer; l: TPyList): TPyList;
var i: Integer; ev: Variant;
begin
  Result := TPyList.Create;
  if l = nil then Exit;
  for i := 0 to l.count - 1 do
  begin
    ev := l.at(i);
    if key = nil then
    begin
      if pyvar_to_bool(ev) then Result.append(ev);
    end
    else if pyvar_to_bool(PyCallKey1(key, ev)) then Result.append(ev);
  end;
end;

function pymap_iter(key: Pointer; const v: Variant): TPyIter;
begin
  PyIterCallHook := @PyCallKey1;
  Result := pyiter_map(key, v);
end;

function pyfilter_iter(key: Pointer; const v: Variant): TPyIter;
begin
  PyIterCallHook := @PyCallKey1;
  Result := pyiter_filter(key, v);
end;

function pymap_iter_i(key: Pointer; up: TPyIter): TPyIter;
begin
  PyIterCallHook := @PyCallKey1;
  Result := pyiter_map_i(key, up);
end;

function pyfilter_iter_i(key: Pointer; up: TPyIter): TPyIter;
begin
  PyIterCallHook := @PyCallKey1;
  Result := pyiter_filter_i(key, up);
end;

function sorted(it: TPyIter; key: Pointer; reverse: Boolean): TPyList; overload;
begin
  Result := sorted(pyiter_drain(it), key, reverse);
end;

function min(it: TPyIter; key: Pointer): Variant; overload;
begin
  Result := min(pyiter_drain(it), key);
end;

function max(it: TPyIter; key: Pointer): Variant; overload;
begin
  Result := max(pyiter_drain(it), key);
end;

function sorted(r: TPyRange; key: Pointer; reverse: Boolean): TPyList; overload;
begin
  Result := sorted(list(r), key, reverse);
end;

function min(r: TPyRange; key: Pointer): Variant; overload;
begin
  Result := min(list(r), key);
end;

function max(r: TPyRange; key: Pointer): Variant; overload;
begin
  Result := max(list(r), key);
end;

function pyclosure_call_ptr(objptr: Pointer; const a0: Variant): Integer;
var args: TPyList; r: Variant;
begin
  args := TPyList.Create;
  args.append(a0);
  PyClosureInvoke(PClosureObj(objptr)^.Cidx, args, r);
  args.Free;
  pyclosure_call_ptr := 0;
end;

{ Trampoline that runs the pending `__body__` def. exec() stores a variant
  pointing here into the caller's namespace dict; NilPy's `ns["__body__"]()`
  unboxes the payload (this address) and calls it with the all-Variant dynamic
  ABI (0 args, Variant result — see PyMakeDynCall / PyDynCallSig). Runs the def
  registered by the immediately-preceding EvalPyStmts over the still-live token
  stream + EnvG. A var-out call into Result (not `Result := CallUserFn(...)`)
  sidesteps the Variant-fn-return NRVO corruption. }
function PyBodyTramp: Variant;
var idx: Integer; noArgs: TPyList;
begin
  idx := FnFind('__body__');
  if idx < 0 then begin PPyRec(@Result)^.VType := 0; PPyRec(@Result)^.Payload := 0; Exit; end;
  noArgs := TPyList.Create;
  CallUserFn(idx, noArgs, Result);
  noArgs.Free;
end;

{ ---- tokenization cache ------------------------------------------------
  A PYTHON-bodied Forth word re-enters EvalPyStmts with the SAME source on
  every execution, and tokenize+preprocess dominated the interpreter (~3ms per
  word — the blocktest ELF-HASH loops made it visible). Direct-mapped cache
  keyed by the raw source; a hit reuses the token arrays by reference. On a
  miss the live refs are NILLED first so Tokenize allocates fresh arrays and
  never mutates a cached buffer in place. }
const PYTOK_CACHE = 64;
type
  TTokCacheEntry = record
    Src:    AnsiString;
    Kinds:  array of Integer;
    Texts:  array of AnsiString;
    Ints:   array of Int64;
    Floats: array of Double;
    NTok:   Integer;
  end;
var
  TokCache: array[0..PYTOK_CACHE-1] of TTokCacheEntry;

function PyTokCacheSlot(const src: AnsiString): Integer;
var n: Integer;
begin
  n := Length(src);
  if n = 0 then begin PyTokCacheSlot := 0; Exit; end;
  PyTokCacheSlot := (n * 31 + Ord(src[1]) * 7 + Ord(src[n])) mod PYTOK_CACHE;
end;

procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);
var cslot, si: Integer;
begin
  EnvG := g;
  { Locals live in pyeval's own arrays (see LclSet), and `l` is SEEDED FROM and
    FLUSHED BACK TO them — which is what makes exec bind anything at all.

    It used to be accepted for API compatibility and otherwise ignored, on the
    reasoning that uforth's block locals are function-internal and never read
    back by the host. True of uforth, and false of `exec` as a Python builtin:

      d = {}; exec("x = 1 + 2", d, d); print(sorted(d.keys()))

    left `d` EMPTY where CPython has `['__builtins__', 'x']`. The call compiled,
    ran, returned, and bound nothing — a program depending on it ran to
    completion producing wrong results, which is the failure mode the
    upward-compatibility rule exists to prevent.

    The flush is frame-correct without doing anything about frames: CallUserFn
    saves and restores the whole local frame around a call, so by the time
    control returns here LclN holds exactly the TOP-LEVEL bindings — which is
    precisely the set CPython puts in `l`. A function body's locals were never
    in this frame to leak.
    bug-n-exec-builtin-is-a-silent-no-op-and-eval-is-absent }
  LclN := 0;
  EnvL := l;
  FnN := 0;
  Executing := True;
  BreakFlag := False;
  ReturnFlag := False;
  { Dedent first (as CPython's exec path does via textwrap.dedent): a corpus
    block extracted from indented .UFO source carries a uniform leading indent on
    every line, which would otherwise tokenize as a spurious opening INDENT. }
  cslot := PyTokCacheSlot(src);
  if TokCache[cslot].Src = src then
  begin
    TkKind := TokCache[cslot].Kinds;
    TkText := TokCache[cslot].Texts;
    TkInt := TokCache[cslot].Ints;
    TkFloat := TokCache[cslot].Floats;
    TkN := TokCache[cslot].NTok;
  end
  else
  begin
    TkKind := nil; TkText := nil; TkInt := nil; TkFloat := nil;
    Tokenize(PreprocessFStrings(pytextwrap_dedent(src)));
    TokCache[cslot].Src := src;
    TokCache[cslot].Kinds := TkKind;
    TokCache[cslot].Texts := TkText;
    TokCache[cslot].Ints := TkInt;
    TokCache[cslot].Floats := TkFloat;
    TokCache[cslot].NTok := TkN;
  end;
  Cur := 0;
  SkipSeparators;
  while (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT) do
  begin
    ExecStatement;
    if (not StmtWasCompound) and (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT)
       and not (IsOp(';') or (CurKind = PK_NL)) then
      EvalError('expected end of statement, got "' + CurText + '"');
    SkipSeparators;
  end;
  { The uforth exec() idiom is `exec("def __body__(): ...", env, ns)` followed by
    `ns["__body__"]()`. The loop above only REGISTERED the def (ExecDef records its
    body span). Publish it into the caller's namespace as a callable variant so
    the separate `ns["__body__"]()` reaches it: the value's payload is
    &PyBodyTramp, unboxed and called through the dynamic-call ABI. Keyed with a
    VT_STRING matching NilPy's dict key (PyVarEq compares string content).

    pyvar_of_callable, NOT PyBoxObj: the payload is a CODE ADDRESS, and PyBoxObj
    stamps VT_OBJECT (7), which claims the payload is a headered heap instance.
    Nothing inspected a tag-7 payload as an instance, so the lie was inert —
    until the callee guard began asking whether a tag-7 receiver's class defines
    `__call__`. GetInstanceRTTI then read a class pointer out of the bytes
    BEFORE the trampoline's entry point and PyFindMethCI walked that garbage
    chain, so every uforth run dumped core with its output still unflushed
    (regression-test-uforth-00, bisected to the guard — the guard exposed this,
    it did not introduce it). pyvar_of_callable stamps VT_CALLABLE for a bare
    code address, which is what this is, and takes no phantom reference. }
  if (l <> nil) and (FnFind('__body__') >= 0) then
    l.store(MakeStr('__body__'), pyvar_of_callable(Pointer(@PyBodyTramp)));
  { ...and every other top-level binding, which is the general case the
    `__body__` line above was the one hand-wired instance of. }
  if l <> nil then
    for si := 0 to LclN - 1 do
      l.store(MakeStr(LclNames[si]), LclVals[si]);
end;

{ eval(src) — the EXPRESSION twin of the above. Same namespaces, same seeding;
  the difference is that it parses one expression and yields its value instead
  of running a statement sequence.

  A var-out procedure, not a Variant function: a Variant function whose Result
  is assigned from another Variant call corrupts the value under the current
  codegen (see the IMPLEMENTATION NOTE at the top of this unit). Nothing is
  flushed back — an expression binds no names. }
procedure EvalPyExpr(const src: AnsiString; g: TPyDict; l: TPyDict;
                     var res: Variant);
var cslot, si: Integer;
begin
  EnvG := g;
  LclN := 0;
  FnN := 0;
  Executing := True;
  BreakFlag := False;
  ReturnFlag := False;
  EnvL := l;
  cslot := PyTokCacheSlot(src);
  if TokCache[cslot].Src = src then
  begin
    TkKind := TokCache[cslot].Kinds;
    TkText := TokCache[cslot].Texts;
    TkInt := TokCache[cslot].Ints;
    TkFloat := TokCache[cslot].Floats;
    TkN := TokCache[cslot].NTok;
  end
  else
  begin
    TkKind := nil; TkText := nil; TkInt := nil; TkFloat := nil;
    Tokenize(PreprocessFStrings(pytextwrap_dedent(src)));
    TokCache[cslot].Src := src;
    TokCache[cslot].Kinds := TkKind;
    TokCache[cslot].Texts := TkText;
    TokCache[cslot].Ints := TkInt;
    TokCache[cslot].Floats := TkFloat;
    TokCache[cslot].NTok := TkN;
  end;
  Cur := 0;
  SkipSeparators;
  ParseExpr(res);
  SkipSeparators;
  { CPython's eval takes an EXPRESSION, not a suite: `eval("x = 1")` is a
    SyntaxError there. Refusing trailing tokens keeps that, and keeps the much
    worse silent shape out — half an input evaluated and the rest dropped. }
  if (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT) then
    EvalError('eval() takes a single expression, got "' + CurText + '"');
end;

function pyeval_expr(const src: AnsiString; g: TPyDict; l: TPyDict): Variant;
begin
  EvalPyExpr(src, g, l, Result);
end;

initialization
  { The ONE callable dispatcher, published to pylib for the whole run rather
    than only while a map/filter cursor is alive. pylib is the lower unit and
    cannot see PyCallKey1, so anything down there that must CALL a callable
    variant of any of the four shapes (min/max with a `key=` held in a variable)
    goes through this hook — and it was previously installed only by
    pymap_iter/pyfilter_iter, i.e. exactly when a map happened to be running.
    bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload }
  PyIterCallHook := @PyCallKey1;

end.
