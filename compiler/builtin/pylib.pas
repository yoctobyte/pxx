{ SPDX-License-Identifier: Zlib }
unit pylib;

{ Python-runtime support types for the Nil-Python frontend. Every .npy program
  pulls this unit in automatically (see ParsePyProgram).

  TPyList is Python's list: a growable array of 16-byte variant slots with
  reference semantics (a class value IS the heap pointer). The slot layout is
  builtin.pas's TVariantRecord model: {VType: Int64; Payload: Int64}, VType 0
  meaning None. A slot that OWNS its contents is written through PyVarSlotSet/
  PyVarSlotInit, which refcount a VT_STRING payload. (This unit once copied
  slots raw on the assumption that string payloads are never freed — untrue:
  boxing a str into a variant materialises a MANAGED copy, so a raw slot copy
  borrowed a pointer that the caller then released. See the comment on those
  helpers; bug-a-str-boxed-into-variant-does-not-own-bytes.)

  append returns Self so the frontend can desugar a list literal [a, b, c]
  into one chained expression: TPyList.Create.append(a).append(b).append(c).
  The default indexed property makes xs[i] work through the ordinary
  default-property machinery, read and write, with Python negative-index
  semantics. }

interface

{ NilPy's PAL — the one place a NilPy primitive reaches the kernel.
  See decide-runtime-primitive-layering. }
{ promocore: the arbitrary-precision runtime. A Variant can HOLD a promotable
  int (tag VT_PROMO_INT64, payload = the exact decimal), and the variant
  arithmetic below must not narrow it — pyvar_to_int's mod-2^64 reading turns
  2**70 into 0, so `v + 1` answered 1 for a 22-digit number. promocore has no
  uses clause of its own, so this adds no cycle. }
uses pypal, promocore;

const
  { An omitted slice bound, as emitted by the frontend for `b[:hi]` / `b[lo:]`.
    See the slice functions below for why a sentinel is safe here. }
  PY_SLICE_OMIT = 2147483647;

  { Which Python kind a TPyList was built as. One representation, three
    languages-level types; see TPyList.FKind. LIST is 0 so a fresh TPyList is a
    list without anyone having to say so. }
  PYSEQ_LIST  = 0;
  PYSEQ_TUPLE = 1;
  PYSEQ_SET   = 2;

type
  TPyVarRec = record
    VType: Int64;
    Payload: Int64;
  end;
  PPyVarRec = ^TPyVarRec;
  { rawKind=2 (a pyeval closure object) forwards through this hook; installed
    by pyeval, which owns the closure registry. nil until pyeval initializes. }
  TPyClosureFinalize = procedure(objp: Pointer);
  PInt64 = ^Int64;
  PPyAnsiString = ^AnsiString;
  PPyDouble = ^Double;

  { itertools.count shim: uforth allocates xt ids via
    next(Word._xt_counter). Generators come much later; a bare int counter
    covers the censused use. }
  TPyCounter = class
  public
    FNext: Int64;
    constructor Create(start: Int64);
    function nextval: Int64;
  end;

  { os.stat() result — only the fields uforth reads. A stub value today (the
    native word that stats a file runs under the exec path, which is stubbed);
    the class exists so `st.st_mode` resolves as a field access. }
  TPyStat = class
  public
    st_mode: Int64;
    st_size: Int64;
    constructor Create;
  end;

  TPyList = class
  public
    FLen: Integer;
    FCap: Integer;
    FItems: Pointer;
    { list, TUPLE and SET are all a TPyList — NilPy has one sequence
      representation — so the only thing separating `(1, 2)` from `[1, 2]` from
      `{1, 2}` is this KIND, stamped by the frontend from the display that was
      written. Without it every tuple printed with brackets
      (bug-nilpy-str-of-tuple-is-empty).

      It was a Boolean FIsTuple until 2026-08-06, which left a SET
      indistinguishable from a list: `type({1,2}).__name__` answered 'list' and
      `isinstance({1,2}, list)` was True. Three kinds need three values
      (bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance).
      PYSEQ_LIST is 0 so a freshly-created TPyList is a list by default. }
    FKind: Integer;
    constructor Create;
    { Python's list.append returns NONE. The Self-returning form the frontend
      chains list literals through is append_self, a SEPARATE name — flipping
      append itself would have broken `[a, b, c]`, which desugars to
      TPyList.Create.append_self(a).append_self(b)...
      (bug-nilpy-list-mutators-return-self-instead-of-none). }
    function append(const v: Variant): Variant;
    function append_self(const v: Variant): TPyList;
    { set-style insert: append only when the value is not already present.
      NilPy backs `set` with TPyList (see PyAnnTypeAt), and this is the whole
      set contract the corpus uses — `s.add(x)` then `x in s`. }
    function add(const v: Variant): TPyList;
    { NOT spelled `get`: Python lists have no .get, and sharing the name with
      TPyDict.get made every `.get(...)` on a dynamically-typed receiver
      ambiguous across classes. Internal accessor only — indexing goes through
      the default property below. }
    function at(i: Integer): Variant;
    procedure put(i: Integer; const v: Variant);
    { Two arities, and they are different Python things: the no-argument form is
      this unit's internal length accessor (len(l) goes through it), while
      Python's own `l.count(v)` counts OCCURRENCES of a value. Overloaded rather
      than renamed because the corpus writes both. }
    function count: Integer; overload;
    function count(const v: Variant): Integer; overload;
    { Python's list.index / list.remove: both find the FIRST element equal to
      v, by PyVarEq — the same content rule count() and `in` already use. index
      RAISES ValueError when absent and remove REMOVES it; a find-style -1
      return would be a different function (feature-nilpy-container-method-gaps). }
    function index(const v: Variant): Integer;
    { returns None, like Python's — a PROCEDURE here meant `r = l.remove(x)`
      read a result that was never written and yielded garbage
      (bug-nilpy-inplace-mutators-do-not-return-none) }
    function remove(const v: Variant): Variant;
    { A SHALLOW copy, like Python's: a new list holding the same element
      values, so appending to the copy leaves the original alone while a
      mutable ELEMENT stays shared. }
    function copy: TPyList;
    function pop: Variant; overload;
    function pop(i: Integer): Variant; overload;   { list.pop(index) — Python removes at i }
    function pop_at(i: Integer): Variant;
    function insert(i: Integer; const v: Variant): Variant;   { None, see remove }
    { Python's `xs += ys` / xs.extend(ys): IN-PLACE, appending ys's elements.
      `+` on two lists would add the two class HANDLES
      (bug-a-nilpy-list-augmented-add-segfaults). }
    function extend(other: TPyList): Variant;
    procedure clear;
    { list.reverse() -- IN PLACE, unlike reversed()/[::-1] which both return a
      NEW sequence. Returns Self so the statement lowering can use it as a
      value node, the same shape sort() and extend() use. }
    function reverse: Variant;
    { list.sort(reverse=) -- in place, returns None. `key=` is still absent: it
      needs PyCallKey1's callable dispatch, which lives in pyeval (which USES
      this unit, so it cannot be called from here). `reverse=` needs no callable
      at all — just the opposite pyvar_gt comparison. }
    function sort(reverse: Boolean = False): Variant;
    { `with open(p, "r") as f: f.read()`. The read-slurp model makes open()
      yield the file's LINES, and each keeps its newline, so joining them
      reproduces the file byte for byte — which is what CPython's read()
      returns. Lives here because that list IS the file object in this model. }
    function read: AnsiString;
    { close()/readlines() on a read-mode handle: the read-slurp model already
      loaded the whole file into this list, so close is a no-op and readlines
      is just the list itself (bug-nilpy-file-write-drops-data-and-read-to-
      print-dumps-rtti-memory). }
    procedure close;
    function readlines: TPyList;
    { set methods. NilPy backs `set` with the same TPyList as `list`, built via
      .add() instead of .append() (one sequence representation, see FKind's
      comment above), so these are ordinary instance methods rather than a
      distinct set class — set(x).union(set(y)) and the OPERATOR forms
      (pyset_and/or/sub/xor in this unit) share the same pycontains-based
      membership test. }
    function issubset(other: TPyList): Boolean;
    function issuperset(other: TPyList): Boolean;
    function union(other: TPyList): TPyList;
    function intersection(other: TPyList): TPyList;
    function difference(other: TPyList): TPyList;
    { set.discard: like remove(), but does NOT raise when the value is absent. }
    procedure discard(const v: Variant);
    property Items[i: Integer]: Variant read at write put; default;
  end;

  { TPyDict is Python's dict: insertion-ordered key/value pairs, both held as
    16-byte variant slots, so `Dict[str, Word]` and `Dict[int, Any]` are the
    SAME runtime type. That is what the uforth census needs — VM.dict is keyed
    by str and VM.xt_table by int, side by side in one class.

    v1 is a LINEAR SCAN. VM.dict reaches a few hundred entries and every Forth
    word lookup hits it, so this will want a hash — but a wrong hash is worse
    than a slow scan, and a hash drops in behind these same methods with no
    frontend change at all. Tracked in feature-nilpy-dict.

    Deletion SHIFTS the tail down rather than swapping the last entry into the
    hole: Python dicts preserve insertion order and uforth iterates them. }
  TPyDict = class
  public
    FLen: Integer;
    FCap: Integer;
    FKeys: Pointer;
    FVals: Pointer;
    { Open-addressing hash INDEX over the insertion-ordered FKeys/FVals arrays
      (feature-nilpy-dict): FHash holds FHashCap Int32 slots, each an index into
      FKeys (-1 = empty). FKeys stays the ordered storage (iteration order +
      delete-shift preserved); the index just makes indexof O(1) instead of a
      linear scan. Rebuilt on grow and on remove (which shifts the tail). }
    FHash: Pointer;
    FHashCap: Integer;
    constructor Create;
    function count: Integer;
    function indexof(const k: Variant): Integer;
    function fetch(const k: Variant): Variant;
    procedure store(const k: Variant; const v: Variant);
    { chainable store, for the `{k: v, ...}` literal desugar — same shape as
      TPyList.append, which is what lets a literal be ONE expression }
    function setitem(const k: Variant; const v: Variant): TPyDict;
    { Python spells both arities `.get`. Declared as overloads so the
      ordinary method-call path resolves them by argument count — no frontend
      hook needed. }
    function get(const k: Variant): Variant; overload;
    function get(const k: Variant; const d: Variant): Variant; overload;
    function remove(const k: Variant): Variant;   { None, see TPyList.remove }
    { dict.pop(key, default): remove the key and return its value, or return
      `default` if absent (never raises in the two-argument form uforth uses). }
    { Both Python arities. The one-argument form RAISES KeyError when the key
      is absent and the two-argument form returns the default — that difference
      is the whole reason Python has both, and requiring the default made the
      one-argument form a PARSE error
      (feature-nilpy-container-method-gaps). }
    function pop(const k: Variant): Variant; overload;
    function pop(const k: Variant; const d: Variant): Variant; overload;
    { Python's dict.setdefault: return the existing value, or insert the
      default and return THAT — the returned slot is the one now in the dict,
      which is what makes `d.setdefault(k, ...)[k2] = v` mutate the dict rather
      than a throwaway copy. }
    function setdefault(const k: Variant; const d: Variant): Variant;
    { dict.clear() — Python's, and what a tkinter application calls on a
      widget's `children` after destroying them. }
    procedure clear;
    { `d.items()` as a VALUE — a list of [key, value] pairs, which is what
      `sorted(d.items(), key=...)` and `list(d.items())` need. NOT named `items`:
      that collides with the default indexed property `Items[k]` above (Pascal is
      case-insensitive), so the frontend maps the Python spelling onto this name,
      exactly as keylist/vallist avoid the same clash. The for-in header form
      never reaches here — it reads the parallel key/value lists directly. }
    function itemlist: TPyList;
    function keylist: TPyList;
    function vallist: TPyList;
    { collections.Counter is this same type in Counter MODE, not a subclass.
      A subclass would be the natural shape, but inherited fields and methods
      need explicit Self. qualification here, the inherited constructor resolves
      to the wrong Create, and — fatally — the inherited default property does
      not carry subscript ASSIGNMENT, so `c[k] = v` on a subclass does not even
      parse. See bug-pascal-subclass-inherited-members. As a mode, a Counter IS
      a dict: subscript, items(), iteration and dict(c) all work already, and
      only the missing-key read changes. }
    FCounterMode: Boolean;
    { Counter.update(iterable) COUNTS elements; a plain dict's update(pairs)
      merges them. The mode picks which, which is why they share a name. }
    function update(l: TPyList): Variant;   { None, see TPyList.remove }
    function update(d: TPyDict): Variant; overload;
    { dict.copy() — a SHALLOW copy, like TPyList.copy: a new dict holding the
      same key/value pairs, so storing into the copy leaves the original alone
      while a mutable VALUE stays shared. }
    function copy: TPyDict;
    { dict.popitem() — remove and return the LAST (key, value) pair, which is
      what CPython 3.7+ does now that dicts are insertion-ordered. Raises
      KeyError on an empty dict, as CPython does. The pair is a tuple. }
    function popitem: TPyList;
    { Counter.most_common([n]): (element, count) pairs, highest count first. The
      pair is a 2-element list — NilPy has no tuple type; indexing is identical. }
    function most_common: TPyList;
    function most_common(n: Integer): TPyList; overload;
    property Items[const k: Variant]: Variant read fetch write store; default;
  end;

  { TPyBytes is Python's bytearray: a flat block of BYTES, not variant slots.
    That difference is the point — byte memory is uforth's Forth data space,
    read and written as integers, and putting 16-byte variants under it would
    cost 16x the space and lose the flat addressing the corpus relies on.

    v1 is the mapping core: allocate, index, len. SLICES (`b[a:c]`, and
    `b[a:c] = other`) need the shared parser's subscript grammar, which is
    Track A — see feature-nilpy-bytes-and-slices. }
  { Python's builtin exception hierarchy, declared HERE rather than synthesised
    by the frontend, for one reason: pylib itself must be able to RAISE these
    (int(s, base) has to fail catchably), and a Pascal unit cannot name a class
    the frontend invented at parse time. Declaring them in the library makes
    FindUClass('ValueError') resolve for `except ValueError:` and makes
    `raise ValueError.Create(..)` legal in here, with one hierarchy for both.

    PyEnsureExceptionClass creates `Exception` only when it is MISSING, so it
    now finds this one and the whole tree shares a root — which is what makes
    a bare `except Exception:` catch a ValueError. }
  Exception = class
  public
    msg: AnsiString;
    FHelpContext: Integer;
    constructor Create(const m: AnsiString);
    { The SYSUTILS surface on the same object. A .npy program pulls pylib before
      any imported unit, so sysutils' own `Exception` declaration is shadowed by
      this one and its descendants (EConvertError, …) and method bodies compile
      against THIS class — which used to have neither CreateFmt nor FMessage, so
      `import json` (or anything reaching sysutils) died on the first raise
      (bug-nilpy-rtl-exception-surface-shadowed).

      FMessage and Message are PROPERTIES over `msg`, not fields: one storage,
      so a Python `raise ValueError("mine")` and a Pascal `raise
      EConvertError.CreateFmt(...)` write the same place and both read back. Two
      synchronised fields were tried first and lost the message on the read path
      — print(e) reads the `msg` FIELD directly (the frontend synthesises that
      access), so `msg` must stay the field and everything else a view on it.
      CreateFmt is declared here and IMPLEMENTED BY sysutils, which is the unit
      that has Format(). }
    constructor CreateFmt(const m: AnsiString; const args: array of const);
    property FMessage: AnsiString read msg write msg;
    property Message: AnsiString read msg write msg;
    property HelpContext: Integer read FHelpContext write FHelpContext;
  end;
  ValueError        = class(Exception) end;
  { Python raises this for x/0, x//0 and x%0. It had no class at all, so the
    integer paths fell through to the Pascal runtime's error 200 (which no
    `except` can see) and true division produced garbage
    (bug-nilpy-runtime-raised-errors-bypass-try-except). }
  ZeroDivisionError = class(Exception) end;
  TypeError         = class(Exception) end;
  IndexError        = class(Exception) end;
  KeyError          = class(Exception) end;
  OSError           = class(Exception) end;
  AttributeError    = class(Exception) end;
  EOFError          = class(Exception) end;
  KeyboardInterrupt = class(Exception) end;
  RuntimeError      = class(Exception) end;
  NotImplementedError = class(RuntimeError) end;
  StopIteration     = class(Exception) end;
  OverflowError     = class(Exception) end;
  { CPython 3 makes IOError and EnvironmentError aliases of OSError, and
    FileNotFoundError / PermissionError subclasses of it. Real code catches
    them by name — songformatter has `except IOError:` around a file read. }
  IOError           = class(OSError) end;
  EnvironmentError  = class(OSError) end;
  FileNotFoundError = class(OSError) end;
  PermissionError   = class(OSError) end;
  FileExistsError   = class(OSError) end;
  IsADirectoryError = class(OSError) end;
  NotADirectoryError = class(OSError) end;
  InterruptedError  = class(OSError) end;
  ArithmeticError   = class(Exception) end;
  FloatingPointError = class(ArithmeticError) end;
  LookupError       = class(Exception) end;
  NameError         = class(Exception) end;
  UnboundLocalError = class(NameError) end;
  RecursionError    = class(RuntimeError) end;
  UnicodeError      = class(ValueError) end;
  UnicodeDecodeError = class(UnicodeError) end;
  UnicodeEncodeError = class(UnicodeError) end;
  MemoryError       = class(Exception) end;
  BufferError       = class(Exception) end;
  AssertionError    = class(Exception) end;
  SystemError       = class(Exception) end;
  SystemExit        = class(Exception) end;
  GeneratorExit     = class(Exception) end;
  TimeoutError      = class(OSError) end;
  ConnectionError   = class(OSError) end;
  BrokenPipeError   = class(ConnectionError) end;
  ConnectionResetError = class(ConnectionError) end;
  ConnectionRefusedError = class(ConnectionError) end;
  ConnectionAbortedError = class(ConnectionError) end;
  BlockingIOError   = class(OSError) end;
  ChildProcessError = class(OSError) end;
  ProcessLookupError = class(OSError) end;
  ImportError       = class(Exception) end;
  ModuleNotFoundError = class(ImportError) end;
  IndentationError  = class(Exception) end;
  SyntaxError       = class(Exception) end;
  TabError          = class(IndentationError) end;
  ReferenceError    = class(Exception) end;
  StopAsyncIteration = class(Exception) end;

  TPyBytes = class
  public
    FLen: Integer;
    FData: Pointer;
    constructor Create(n: Integer);
    function count: Integer;
    { see TPyList.at — bytearrays have no Python .get either }
    function at(i: Integer): Integer;
    procedure put(i: Integer; v: Integer);
    { bytearray.extend / .append — uforth builds output buffers byte by byte }
    procedure extend(src: TPyBytes);
    { NO .append here on purpose: TPyList.append already exists, and a second
      class declaring the name makes EVERY `.append(...)` on a dynamically
      typed receiver ambiguous — the same collision TPyList.get caused. Python
      does have bytearray.append, so if a corpus needs it the answer is runtime
      dispatch on the receiver's class, not another method on this class.
      (filed as feature-nilpy-runtime-method-dispatch-on-variant) }
    procedure append(v: Integer);
    { bytes.find(sub[, start]) — index of the sub-bytes at/after start (0), or -1. }
    function find(sub: TPyBytes): Integer; overload;
    function find(sub: TPyBytes; start: Integer): Integer; overload;
    { bytes.decode(encoding [, errors]). Our strings ARE byte strings, so
      latin-1 is an exact identity mapping; the `errors` argument is accepted
      and ignored because latin-1 cannot fail. Named `errors` so the keyword
      form binds through the ordinary method keyword-argument path. }
    function decode: AnsiString; overload;
    function decode(const encoding: AnsiString): AnsiString; overload;
    function decode(const encoding: AnsiString; const errors: AnsiString): AnsiString; overload;
    { bytes.endswith(suffix) — the READ-LINE CR/LF trim }
    function endswith(sfx: TPyBytes): Boolean;
    property Items[i: Integer]: Integer read at write put; default;
  end;

  { A real OS file (raw x86-64 syscalls, no libc) backing NilPy's open(path,
    mode) — uforth's CREATE-FILE/OPEN-FILE/READ-LINE/WRITE-FILE/... words. }
  TPyFile = class
  public
    FFd: Int64;
    constructor Create;
    function read(u: Int64): TPyBytes;
    function readline: TPyBytes;
    function write(b: TPyBytes): Int64; overload;
    { Python's TEXT-mode write takes a str, and that is how every ordinary
      program spells it. Without this overload `f.write("hello")` resolved to
      the TPyBytes one, passed the string's handle as a buffer and wrote ZERO
      bytes -- the file was created and left empty, with no error
      (bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory). }
    function write(const s: AnsiString): Int64; overload;
    procedure seek(pos: Int64); overload;
    procedure seek(pos: Int64; whence: Int64); overload;
    function tell: Int64;
    procedure truncate(sz: Int64);
    procedure flush;
    procedure close;
  end;


{ Python's str() for an f-string hole. Overloaded so ARGUMENT TYPE picks the
  spelling, which is the whole point: the shared str() intrinsic lowers every
  argument through StrInt/FloatToStr/VariantToStr and therefore prints a
  string's POINTER and a bool's 1 (bug-a-nilpy-str-of-string-and-bool). An
  f-string cannot wait for that — its entire job is producing text — so the
  expander emits pystr_of and gets Python's spelling per type. }
function pystr_of(const s: AnsiString): AnsiString;
function pystr_of(b: Boolean): AnsiString; overload;
function pystr_of(i: Int64): AnsiString; overload;
function PyFloatStr(d: Double): AnsiString;   { FloatToStr + Python's inf/nan spelling }
function pystr_of(d: Double): AnsiString; overload;
function pystr_of(c: Char): AnsiString; overload;
function pystr_of(const v: Variant): AnsiString; overload;
{ Python's repr() for an f-string !r hole. Differs from str() for exactly one
  type — a string gains quotes — which is why it needs the same per-type
  overload set rather than a single wrapper. }
function pyrepr_of(const s: AnsiString): AnsiString;
function pyrepr_of(b: Boolean): AnsiString; overload;
function pyrepr_of(i: Int64): AnsiString; overload;
function pyrepr_of(d: Double): AnsiString; overload;
function pyrepr_of(c: Char): AnsiString; overload;
function pyrepr_of(const v: Variant): AnsiString; overload;
{ Python's `repr()` under its OWN name. pyrepr_of already had the whole per-type
  overload set — it is what an f-string's `!r` hole lowers to — but the builtin
  NAME was never bound to anything, so `repr(x)` failed with "undefined
  variable (repr)". Thin forwarders rather than a frontend intrinsic, so the
  ordinary overload machinery does the type dispatch (and a promotable int picks
  the lossless Variant one, per ArgNarrowsInt). }
function repr(const s: AnsiString): AnsiString;
function repr(b: Boolean): AnsiString; overload;
function repr(i: Int64): AnsiString; overload;
function repr(d: Double): AnsiString; overload;
function repr(c: Char): AnsiString; overload;
function repr(const v: Variant): AnsiString; overload;
function repr(l: TPyList): AnsiString; overload;
function repr(dc: TPyDict): AnsiString; overload;
{ Python's repr() of a CONTAINER. print(xs) is the most natural debugging line
  in Python, and it used to print the TPyList instance POINTER — the container
  fell through to the integer path (bug-a-nilpy-print-of-a-list-prints-a-pointer).
  Recursive: a nested list/dict element is reprd as a container, not as its
  object tag. }
{ Mark a list as a TUPLE / a SET — the frontend calls these on the temp the
  corresponding display builds. Not "for rendering only" any more: the kind is
  what `type(x).__name__` and `isinstance` answer from, so a display that fails
  to stamp it is a wrong TYPE, not just wrong brackets. }
function pylist_mark_tuple(l: TPyList): TPyList;
function pylist_mark_set(l: TPyList): TPyList;
{ The Python type name of a sequence kind: 'list' / 'tuple' / 'set'. }
function PySeqKindName(k: Integer): AnsiString;
{ The sequence kind of a VARIANT, or -1 when it does not hold a TPyList. The
  shape isinstance() asks: it must distinguish the three kinds that share the
  row, which a class test cannot do. }
function pyseq_kind_v(const v: Variant): Integer;
function pylist_repr(l: TPyList): AnsiString;
function pybytes_repr(b: TPyBytes): AnsiString;
function pydict_repr(d: TPyDict): AnsiString;
function PyCallableStr(const v: Variant): AnsiString;
function pyvar_repr(const v: Variant): AnsiString;
{ print()'s string form of a VARIANT: a container payload (list/dict) shows its
  Python repr (`[1, 2]`), every scalar its plain str() (no quotes). Used by the
  frontend to format a variant/Any print argument, which otherwise reached the
  backend's `<object>` placeholder (bug-nilpy-print-variant-holding-list). }
function pyvar_print_of(const v: Variant): AnsiString;
{ `print(*xs)` — the unpacked list rendered as print would render its elements:
  each in print's own string form, single-space separated. leadSep asks for a
  leading separator too, which is what a print argument BEFORE the `*xs` needs;
  keeping it here rather than injecting a space at the call site is what makes
  `print("a", *[])` print `a` and not `a `, since an empty list adds nothing. }
function pyprint_star(l: TPyList; leadSep: Boolean): AnsiString;
{ Python's format() for an f-string hole with a spec. The spec arrives as the
  literal text between ':' and the closing brace; this unit is the ONE place
  that interprets it, so the lexer never has to know what "05x" means. }
function pyformat_of(i: Int64; const spec: AnsiString): AnsiString;
{ `"...{}...{:.1f}".format(a, b)` — the positional placeholders, with the same
  spec grammar the f-strings use (pyformat_of below). Named fields
  (`{name}`) and index fields (`{0}`) are NOT here: they fail loudly rather
  than being dropped, because a format spec decides what is PRINTED. }
function pystr_format(const fmt: AnsiString; const a: Variant): AnsiString;
function pystr_format2(const fmt: AnsiString; const a: Variant; const b: Variant): AnsiString;
function pystr_formatn(const fmt: AnsiString;
                       const a0, a1, a2, a3, a4, a5, a6, a7: Variant;
                       n: Integer): AnsiString;
{ Python's `"%s=%d" % args` — the printf-style operator, translated placeholder
  by placeholder into the {}-spec grammar below so padding, precision and base
  conversion have ONE implementation rather than two that drift. args is a single
  value, or a TPyList when a tuple was written, which is Python's own rule. }
function pypercent_format(const fmt: AnsiString; const args: Variant): AnsiString;
function pyformat_of(const s: AnsiString; const spec: AnsiString): AnsiString; overload;
function PyFmtFixed(d: Double; prec: Integer): AnsiString;
function pyformat_of(d: Double; const spec: AnsiString): AnsiString; overload;
function pyformat_of(const v: Variant; const spec: AnsiString): AnsiString; overload;
{ `bytearray(n)` and `bytes(b)` are spelled as ordinary FUNCTIONS rather than
  recognised by the frontend: neither name is a Pascal keyword, so both
  resolve through the normal call path with no parser hook. (`set()` needed a
  hook only because `set` IS a keyword.) }
function bytearray: TPyBytes; overload;   { bytearray() — an EMPTY buffer }
function bytearray(n: Integer): TPyBytes; overload;
{ bytearray(b"abc") — a COPY of a bytes/bytearray, never an alias. The point of
  the call is almost always to get a MUTABLE copy of an immutable bytes, so
  returning the same object would be a silent aliasing bug rather than a missing
  feature (bug-nilpy-bytearray-constructor-only-accepts-a-length). }
function bytearray(b: TPyBytes): TPyBytes; overload;
{ bytearray([1, 2, 3]) — an iterable of ints. An element outside 0..255 raises
  ValueError as CPython does, rather than truncating to a byte: a truncation
  here would be a wrong VALUE in a buffer, which is exactly the failure mode
  this type is used to avoid. }
function bytearray(l: TPyList): TPyBytes; overload;
function bytes(b: TPyBytes): TPyBytes;
{ bytes([104, 105]) — from a LIST of codepoints. A REAL overload since
  bug-a-overload-resolution-ignores-class-identity: before that, a list
  argument silently bound to the TPyBytes parameter above and was rescued by
  a runtime `is` check inside it. Correct resolution now rejects that bind,
  so the overload has to exist. }
function bytes(l: TPyList): TPyBytes; overload;
function pybytes_from_list(l: TPyList): TPyBytes;
function bytes(const s: AnsiString): TPyBytes; overload;
function pybytes_find(b: TPyBytes; sub: TPyBytes; start: Integer): Integer;
function len(b: TPyBytes): Integer; overload;
{ SLICES. `b[lo:hi]` desugars to one of these calls in the frontend, with an
  OMITTED bound passed as PY_SLICE_OMIT. That sentinel needs no disambiguation:
  Python CLAMPS slice bounds instead of raising, so a literal index of MaxInt
  already means "the end" and collides harmlessly.

  Python slice semantics, implemented once in PySliceBounds and shared by all
  three element types: a negative bound counts from the end, both bounds clamp
  into [0, n], and an inverted or empty range yields an EMPTY result rather
  than an error. This is deliberately unlike INDEXING, which raises. }
{ str.encode(encoding [, errors]) -> bytes. Our strings ARE byte strings, so
  this is a byte-for-byte copy: exact for latin-1, and for utf-8 exact only
  while every character is ASCII (see the ticket noted at the call site). }
function pystr_encode(const s: AnsiString): TPyBytes;
function pystr_slice(const s: AnsiString; lo, hi: Integer): AnsiString;
function pybytes_slice(b: TPyBytes; lo, hi: Integer): TPyBytes;
function pylist_slice(l: TPyList; lo, hi: Integer): TPyList;
{ EXTENDED slices — `b[lo:hi:step]`, any non-zero step. Separate entry points
  rather than a default parameter so the frontend picks one by arity and the
  plain 3-argument path stays exactly as it was. Bounds follow CPython's
  slice.indices(), which is NOT PySliceBounds with an extra loop: with a
  negative step an omitted low bound means n-1 (not 0) and an omitted high
  bound means "before index 0" (not n), and the clamps differ likewise.
  step = 0 raises ValueError, as in Python. }
{ `range(a, b, s)` rejects a zero step, as Python does — otherwise the loop
  never advances and hangs. Called from the frontend's while-loop desugar only
  when the step is not a literal whose sign is already known, so the common
  `range(n-1, -1, -1)` shape pays nothing. }
procedure pyrange_check_step(step: Int64);
{ `list(range(...))` — range MATERIALISED as a list.

  NilPy's `range` is not a value: it exists only as the counted-loop lowering in
  a `for` header, so `list(range(3))` failed with "undefined variable (range)"
  (bug-nilpy-missing-builtins-step-slicing-range-into-list, group 2). This is
  what the frontend calls once it has recognised that exact shape.

  Deliberately NOT reachable as a general `range(...)` value: CPython's range is
  lazy and prints as `range(0, 3)`, so making every range a list would turn a
  loud compile error into a quietly different `print(range(3))`. Materialising
  only where the program has ALREADY asked for a list keeps the two agreeing. }
function pyrange_list(lo, hi, step: Int64): TPyList;
function pystr_slice_step(const s: AnsiString; lo, hi, step: Integer): AnsiString;
function pybytes_slice_step(b: TPyBytes; lo, hi, step: Integer): TPyBytes;
function pylist_slice_step(l: TPyList; lo, hi, step: Integer): TPyList;
function pylist_del_slice(l: TPyList; lo, hi: Integer): TPyList;   { del l[lo:hi] in place }
function pylist_del_at(l: TPyList; i: Integer): TPyList;           { del l[i] in place }
procedure pylist_setslice(l: TPyList; lo, hi: Integer; src: TPyList);   { l[lo:hi] = src in place }
{ `b[lo:hi] = src`. uforth assigns a slice of the SAME length everywhere (it is
  emulating fixed-width cells in Forth data space), so a length CHANGE is
  rejected loudly rather than silently splicing: a quiet resize would move
  every address above the write and corrupt the data space. }
procedure pybytes_setslice(b: TPyBytes; lo, hi: Integer; src: TPyBytes);
procedure pybytes_setslice_v(b: TPyBytes; lo, hi: Integer; const src: Variant);   { RHS is a variant holding bytes }
{ `v.to_bytes(n, "little", signed=s)` and `int.from_bytes(b, "little",
  signed=s)`. Recognised by the frontend as INTRINSICS with a fixed argument
  shape rather than real methods, because their Python spelling carries a
  KEYWORD argument and NilPy has no keyword arguments — 36 sites in uforth,
  one spelling, so the intrinsic is far cheaper than the language feature.
  Byte order is not a parameter: every censused use is little-endian, and the
  frontend REJECTS anything else rather than silently ignoring it. }
function pyint_to_bytes(v: Int64; n: Integer; signed: Boolean): TPyBytes;
function pyint_from_bytes(b: TPyBytes; signed: Boolean): Int64;
{ Python's two-argument int(s, base). RAISES ValueError on a bad parse rather
  than halting, which is the whole point: a Forth interpreter tries EVERY input
  word as a number, so a non-numeric token is the ordinary case and a fatal
  error there would kill the interpreter on its first word. }
function pyint_parse(const s: AnsiString; base: Integer): Int64;
{ Python's float(). Split by ARGUMENT TYPE at the call site rather than
  overloaded on one name, because the frontend builds these calls directly and
  has no overload resolution there. pyfloat_parse RAISES ValueError on a bad
  parse, for the same reason pyint_parse does. }
function pyfloat_parse(const s: AnsiString): Double;
{ `float(x)` where x is a VARIANT — the tag is only known at run time, so the
  string case has to be decided there. Python parses a str and widens a number;
  the compile-time route picks pyfloat_parse or pyfloat_ofint from the STATIC
  type, and a variant fell to the latter, whose Int64 parameter unboxed through
  pyvar_to_float and raised "expected a number, got str". Anything a config
  file, a dict or a *args list carries is a variant, so that was most real
  code. }
function pyfloat_any(const v: Variant): Double;
function pyfloat_ofint(v: Int64): Double;
{ os.path / os / sys shims. Reached by NAME from the frontend's stdlib table
  (`os.path.join(...)` -> pyos_path_join), because `os` and `sys` are deferred
  imports and never become symbols.

  POSIX semantics only — '/' separators, no drive letters. Everything that can
  be answered by string manipulation is, so only exists() and getcwd() touch
  the kernel; that keeps the arch-specific syscall surface down to two calls. }
function pyos_path_isabs(const p: AnsiString): Boolean;
function pyos_path_join(const a: AnsiString; const b: AnsiString): AnsiString;
{ Python's os.path.join is VARIADIC and the corpus writes three components
  routinely. These are ordinary Pascal overloads, reachable from the stdlib
  shim table only because that call site now re-targets by ARITY — before
  FindProcArity they were added, measured to do nothing, and removed again
  (bug-nilpy-stdlib-shim-table-cannot-reach-an-overload, sighting 3). }
function pyos_path_join(const a, b, c: AnsiString): AnsiString; overload;
function pyos_path_join(const a, b, c, d: AnsiString): AnsiString; overload;
function pyos_path_dirname(const p: AnsiString): AnsiString;
function pyos_path_basename(const p: AnsiString): AnsiString;
{ os.path.isdir / os.path.isfile — a MISSING path is False, not an error, which
  is CPython's rule and the reason these cannot just be `stat` plus a field read.
  Real stat on x86-64 only, like pyos_stat; elsewhere they RAISE rather than
  answer False, because a silent False for a directory that exists is exactly
  the plausible-wrong-value this repo refuses
  (bug-nilpy-os-path-isdir-isfile-splitext-missing). }
function pyos_path_isdir(const p: AnsiString): Boolean;
function pyos_path_isfile(const p: AnsiString): Boolean;
{ os.path.splitext — (root, ext), split at the LAST dot of the basename. A
  leading dot is not an extension (".bashrc" -> (".bashrc", "")), and a dot in a
  directory component does not count. Pure string work, so it is exact on every
  target. Returns a TUPLE, as CPython does. }
function pyos_path_splitext(const p: AnsiString): TPyList;
function pyos_path_exists(const p: AnsiString): Boolean;
function pyos_path_abspath(const p: AnsiString): AnsiString;
function pyos_getcwd: AnsiString;
procedure pysys_exit(code: Integer);
{ os.remove / os.rename: unlink / rename via syscall, returning 0 (Python returns
  None; the value is unused). os.stat: a stubbed TPyStat — see the class note. }
function pyos_remove(const path: AnsiString): Integer;
function pyos_rename(const src: AnsiString; const dst: AnsiString): Integer;
function pyos_stat(const path: AnsiString): TPyStat;
{ os.environ.get(name[, default]) and os.getenv(name[, default]). The process
  environment comes from /proc/self/environ (NUL-separated NAME=VALUE records);
  reaching the real block on the initial stack needs an intrinsic that does not
  exist yet — feature-rtl-environment-variables. An UNSET variable yields None,
  not '', because that is what Python does and what `if os.environ.get(X):`
  depends on. }
{ os.startfile(path) — Windows only in CPython, and the branch that calls it is
  guarded by `sys.platform.startswith("win")`. It has to COMPILE on a file that
  supports Windows, and it must not pretend to work if reached. }
{ `s[::-1]` — a reversed STRING. `reversed(s)` yields a LIST of characters,
  which is right for `for c in reversed(s)` but wrong for a slice: a slice of a
  string is a string. }
function pystr_reverse(const s: AnsiString): AnsiString;
{ A name that came from an optional import whose module was not available.
  Binding it to None lets the file COMPILE, exactly as CPython compiles a
  module whose `try: import X` failed; this is what happens if such a name is
  actually USED, and it names the module so the message is actionable. }
function pyoptional_missing(const what: AnsiString): Variant;
function pyos_startfile(const path: AnsiString): Integer;
function pyos_environ_get(const name: AnsiString): Variant;
function pyos_environ_get_d(const name: AnsiString; const dflt: Variant): Variant;
function pyos_getenv(const name: AnsiString): Variant;
function pyos_getenv_d(const name: AnsiString; const dflt: Variant): Variant;
{ sys.stdin.read(n): read up to n bytes from fd 0, returned as a byte string.
  Returns '' at EOF (Python's read at EOF gives ''), which is exactly what
  uforth's KEY word tests for. }
function pystdin_read(n: Integer): AnsiString;
{ sys.stdin.readline(): one line from fd 0 (keeping the trailing newline), '' at
  EOF. Reads a byte at a time so it stops at the newline like Python. }
function pystdin_readline: AnsiString;
{ sys.stdin.isatty(): 0 (a non-tty). The value that makes uforth's KEY? report
  no type-ahead — the correct default for pipes/files and never wrong for the
  native words, which run under the (stubbed) exec path. }
function pystdin_isatty: Integer;
function pystr_is_none(const s: AnsiString): Boolean;
{ The None value for a str-typed slot: a NIL managed handle (what
  pystr_is_none tests). Assigning the None literal to a str field/local must
  store this, not the text 'None' a variant->string coercion produces. }
function pystr_none: AnsiString;
function pyvar_box(const v: Variant): Variant;   { box a value into a variant }
{ A BOUND METHOD captured as a value (`env["push"] = vm.push`): a heap
  {code, recv} pair boxed as a VT_BOUNDMETHOD (8) variant. Recv is the receiver
  the method needs as Self; Code is its entry. Used by the NilPy capture of
  `obj.method` with no following call (feature-nilpy-bound-method-value). uforth
  stores these in its exec env; the pyeval interpreter reaches the receiver
  through env["vm"] rather than invoking them, so a stored bound method must
  merely not crash. }
var
  PyClosureFinalizeHook: TPyClosureFinalize;

function pybound_new(code, recv: Pointer; isFunc: Boolean): Variant;
function pybound_code(const v: Variant): Pointer;
function pybound_recv(const v: Variant): Pointer;
{ True when Code is a genuine Variant-returning FUNCTION (NilPy's default def
  ABI); False when Code is a real Pascal PROCEDURE (an explicit `-> None` def)
  that never sets up the hidden-destination-pointer return convention. Lets
  the generic dynamic-call bridge (pybound_callv*/pycallback_call*) pick the
  matching call shape at runtime instead of unconditionally assuming a
  function (bug-nilpy-void-def-assigned-and-called-crashes). }
function pybound_isfunc(const v: Variant): Boolean;
{ CALL a function value from library code — the piece a callback-taking façade
  needs. `self.handler` reaches a library as a VT_BOUNDMETHOD variant (a
  {code, receiver} pair); a plain def reaches it as the same pair with a nil
  receiver. Both are invoked here so a PCL widget can hand a Tk event back to
  the Python method that asked for it.

  The callee's own arguments are variants BY ADDRESS, which is NilPy's variant
  convention, and its result is read as one machine word and discarded — an
  event handler returns None. A handler whose result rides the hidden-destination
  convention (an annotated `-> str`, say) is NOT callable this way; that needs
  the same normalisation defs got (see PyDefUsedAsValue) and is filed as
  feature-nilpy-tk-callbacks. }
function pycallback_call0(const cb: Variant): Int64;
function pycallback_call1(const cb: Variant; const a0: Variant): Int64;
{ True for a value that pycallback_call* can invoke. }
function pycallback_is(const cb: Variant): Boolean;
{ The same call with the RESULT kept — `f = obj.method` / `f = some_def` and then
  `f(a, b)` as an expression. Arities 0..3 cover every dynamic call NilPy emits a
  guard for; beyond that a receiver-less pair still runs through the plain
  indirect path (pyvar_callee_addr unwraps it). }
function pybound_callv0(const cb: Variant): Variant;
function pybound_callv1(const cb: Variant; const a0: Variant): Variant;
function pybound_callv2(const cb: Variant; const a0, a1: Variant): Variant;
function pybound_callv3(const cb: Variant; const a0, a1, a2: Variant): Variant;
{ Finalizer for dying refcounted objects, installed into builtinheap's
  PXXObjFinalizeHook by the container constructors and pybound_new: releases
  the object's children recursively before the block is freed
  (feature-nilpy-object-reclamation slice 3). rawKind = 1 means a VMT-less
  {code,recv} bound pair. }
procedure PyObjFinalize(objp: Pointer; rawKind: NativeInt);
{ input([prompt]): a line from stdin without its trailing newline. }
function pyinput_p(const prompt: AnsiString): AnsiString;
function pyinput: AnsiString;
{ sys.argv: the command line as a TPyList of strings, argv[0] = program name. }
function pysys_argv: TPyList;
function pysys_file: AnsiString;   { the __file__ dunder }
{ select.select(r, w, x, timeout): the ready-sets triple. The shim returns three
  empty lists (nothing ready), which is the safe answer for the non-tty default
  and all uforth asks of it. }
function pyselect_select(const r: Variant; const w: Variant; const x: Variant; const t: Variant): TPyList;
{ open(path[, mode, encoding=...]) in READ mode -> a TPyList of the file's
  lines, each keeping its trailing '\n' exactly as Python's `for line in f`
  yields them. The whole file is read eagerly, so the file object IS just the
  line list — iteration and .read() need no live fd, and `with open(...)` can
  treat close as a no-op. Mode/encoding are accepted and ignored (our strings
  are byte strings; latin-1/utf-8 of ASCII is identity). }
function pyopen(const path: AnsiString): TPyList;
function pyfile_read(l: TPyList): AnsiString;
{ textwrap.dedent: remove the longest run of leading whitespace common to every
  non-blank line. Blank lines are normalised to empty and ignored when
  computing the common prefix, as CPython does. }
function pytextwrap_dedent(const s: AnsiString): AnsiString;
{ exec(src, globals[, locals]) — run a Python-subset source string against the
  given namespaces. STUB: compiles and links so uforth builds, but does not yet
  evaluate the source. The real two-engine evaluator (tokenizer+parser+AST
  cache, then a tree-walker) is feature-lib-pyexec, a large separate subsystem.
  Until it lands, exec'd bodies are no-ops. }
procedure pyexec(const src: AnsiString; g: TPyDict; l: TPyDict);
{ Python's two-argument min/max. Spelled as ordinary pylib FUNCTIONS, the
  same way bytearray/bytes are: neither name is a Pascal keyword, so both
  resolve through the normal call path with no frontend hook.

  Two arguments only — Python's min/max are also variadic and also take an
  ITERABLE, and every censused use in uforth is the two-argument form (7 min,
  7 max). The other forms are absent rather than wrong: calling them is an
  unknown-arity error, not a silent answer. lib/rtl/math.pas has capitalised
  Min/Max, but NilPy programs do not load it, and Python spells them lower
  case. }
{ Python's `//` and `%`: the quotient FLOORS (rounds toward -infinity) and the
  remainder takes the DIVISOR's sign, where Pascal's div/mod truncate toward
  zero and the remainder takes the dividend's. They differ only when the signs
  disagree: -7 // 3 is -3 in Python and -2 in Pascal.

  Corrected together, never separately: the identity a = (a//b)*b + (a%b) must
  hold for every sign combination, and it does here by construction -- when the
  signs disagree the quotient loses one and the remainder gains one b, so
  (q-1)*b + (r+b) = q*b + r = a exactly.

  Distinct names per operand type rather than an overload set: a Variant
  argument would otherwise pick an overload arbitrarily
  (bug-a-len-of-variant-picks-wrong-overload). The IR lowering selects by
  operand type and calls one by name. }
{ Python's int("42"). A junk string is a ValueError in Python, so it halts
  loudly here rather than yielding a silent 0 -- the whole point of the
  ticket was that int() of a string returned a plausible wrong number. }
function pystr_to_int(const s: AnsiString): Int64;
{ ...and the ARBITRARY-PRECISION form, which is what `int(<str>)` actually
  means: Python's int has no width, so a 30-digit string is a 30-digit int.
  pystr_to_int is Int64-bound (it parses with Val) and wrapped mod 2^64 in
  silence — int("123456789012345678901234567890") answered
  -4362896299872285998 (bug-nilpy-int-of-a-long-decimal-string-narrows).
  Writes a promo SLOT rather than returning one: a promotable int is an
  aggregate, and every other producer in promocore has the same dst-first
  shape. The validation is spelled out here rather than delegated because Val
  is exactly the part that cannot be reused — it is the narrowing — while the
  ValueError wording must stay identical to pystr_to_int's, which is the
  wording the tests and the corpus already expect. }
procedure pystr_to_promo(dst: Pointer; const s: AnsiString);
{ Python's `s * n` / `n * s`: repeat the text. Multiplying a string by an
  integer otherwise multiplied its HANDLE
  (bug-a-nilpy-string-repeat-returns-a-pointer). n <= 0 yields ''. }
function pystr_repeat(const s: AnsiString; n: Int64): AnsiString;
{ The VARIANT forms. A for-in loop variable is always a variant, so without
  these the most ordinary Python loop (`for a in xs: a // 2`) silently kept
  Pascal's truncating semantics. Tag dispatch at RUNTIME is the only correct
  answer -- the payload's type is not known when lowering. }
{ Variant -> scalar with PYTHON's rules. Deliberately NOT builtin.pas's
  VariantTo* -- those serve Pascal, whose Variant is historically coercive,
  and one helper cannot hold both specs. Python raises TypeError for a string
  or object in a numeric context, and its truthiness makes ''/0/0.0/None
  false. ir.inc picks this set when PyProgramMode. }
function pyvar_to_int(const v: Variant): Int64;
{ Polymorphic operations over a VARIANT operand -- which a for-in loop
  variable always is. Python dispatches these on the RUNTIME type, so they
  cannot be resolved when lowering: `len(v)` picked an overload by static
  type and dereferenced a string as a list, and `v * 2` cannot know whether
  to repeat or multiply (bug-a-len-of-variant-picks-wrong-overload). }
function pylen_v(const v: Variant): Int64;
function pyord_v(const v: Variant): Int64;
function pyord_s(const s: AnsiString): Int64;
function PyChrRangeCheck(n: Int64): Int64;
function pymul_v(const a: Variant; const b: Variant): Variant;
{ Python's `**`. int**non-negative-int is exact within Int64 (exponentiation
  by squaring, so it inherits whatever overflow behaviour chained `*` already
  has, rather than a separate wrapping rule); a negative exponent or either
  operand a float goes through the float path (also squaring when the
  exponent is a whole number, even a negative or float-typed one, so a
  negative BASE with a whole exponent -- `(-2.0) ** 3` -- stays exact rather
  than routing through Ln of a negative number). A genuinely fractional
  exponent on a negative base is the one shape CPython answers with a complex
  number; there is no complex type here, so it degrades to NaN.
  feature-nilpy-power-operator-and-divmod }
function pypow_v(const a: Variant; const b: Variant): Variant;
{ Python's `divmod(a, b)` -- (a // b, a % b) as a 2-tuple, both of which are
  already correct on negative operands via pyfloordiv_v/pyfloormod_v. }
function pydivmod_v(const a: Variant; const b: Variant): TPyList;
function pyvar_to_float(const v: Variant): Double;
function pyvar_to_bool(const v: Variant): Boolean;
function pyvar_to_char(const v: Variant): Char;
{ Python's `a or b` / `a and b` as VALUES: `or` yields a if truthy else b; `and`
  yields b if a is truthy else a. Both operands are already evaluated (the
  caller boxed them into variants), so short-circuit side effects are lost — a
  documented deviation, harmless for the value idioms this serves (`x or []`,
  `given or "anon"`). Returns the chosen operand. }
function pyor_v(const a: Variant; const b: Variant): Variant;
function pyand_v(const a: Variant; const b: Variant): Variant;
function pyfloordiv_v(const a: Variant; const b: Variant): Variant;
function pyfloormod_v(const a: Variant; const b: Variant): Variant;
{ Arithmetic / bitwise / compare over VARIANTS, for the pyeval tree-walker
  (feature-lib-pyexec): its operands are always variants and Python dispatches
  on the runtime tag. `+` concatenates two strings, else numeric add (float if
  either is float). `%` is Python modulo (== pyfloormod). The bit ops coerce
  both sides through int() and are DISTINCT from pyand_v/pyor_v (those are the
  boolean `and`/`or`; these are `&`/`|`). pycmp_v returns -1/0/1 with Python
  cross-type numeric rules; pyeq_v is value equality across tags. }
function pyadd_v(const a: Variant; const b: Variant): Variant;
function pyaugadd_v(const a: Variant; const b: Variant): Variant;
function pysub_v(const a: Variant; const b: Variant): Variant;
function pymod_v(const a: Variant; const b: Variant): Variant;
function pybitand_v(const a: Variant; const b: Variant): Variant;
function pybitor_v(const a: Variant; const b: Variant): Variant;
function pybitxor_v(const a: Variant; const b: Variant): Variant;
function pyshl_v(const a: Variant; const b: Variant): Variant;
function pyshr_v(const a: Variant; const b: Variant): Variant;
function pyinvert_v(const a: Variant): Variant;   { ~a }
function pyneg_v(const a: Variant): Variant;      { -a }
function pycmp_v(const a: Variant; const b: Variant): Int64;   { -1/0/1 }
{ Python's `/` over two VARIANTS: always a float, ZeroDivisionError on a zero
  divisor, TypeError when either tag is not a number. pytruediv_f is the
  statically-numeric sibling and takes two Doubles — it cannot serve here,
  because coercing a variant to a Double at the call site is exactly the step
  that turned a str handle into a number
  (bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math). }
function pytruediv_v(const a: Variant; const b: Variant): Variant;
{ The ORDERING operators over variants. Each is pycmp_v plus a test, exposed as
  its own function so the lowering emits one call returning a Boolean rather
  than hand-building a compare against pycmp_v's Int64. pycmp_v raises for a
  pair Python will not order (int vs str, int vs list), which is the point:
  `3 < [1, 2]` used to answer True off a heap address. }
function pylt_v(const a: Variant; const b: Variant): Boolean;
function pyle_v(const a: Variant; const b: Variant): Boolean;
function pygt_v(const a: Variant; const b: Variant): Boolean;
function pyge_v(const a: Variant; const b: Variant): Boolean;
function pyeq_v(const a: Variant; const b: Variant): Boolean;
function pyint_v(const v: Variant): Variant;      { int(v) as a variant }
function pyvar_of_int(v: Int64): Variant;
function pyvar_of_bool(b: Boolean): Variant;
{ Identity on a Variant. Its use is the ARGUMENT side: passing a scalar here
  boxes it through the ordinary call-argument path, which is the one place that
  knows how to make a variant out of any value — so an Integer field read and a
  Variant one can be the two arms of one expression. }
function pyvar_id(const v: Variant): Variant;
function pystr_repeat_v(const v: Variant; n: Int64): AnsiString;
{ `xs * n` on a LIST: a new list whose slots are the original's, repeated.
  Python copies REFERENCES, not elements — `[[0]] * 3` gives three aliases of the
  same inner list — so the variant slots are copied as they stand
  (feature-nilpy-list-repeat). n <= 0 yields an empty list. }
{ Python's None as a VALUE. The runtime representation already existed —
  VT_EMPTY, the unassigned-slot tag — it was simply not reachable from the
  language, so a None stored in a container arrived as integer 0
  (feature-nilpy-none-variant). }
function pynone: Variant;
{ The VARIANT forms of two more builtins, for the same reason pylen_v exists: a
  for-in loop variable is always a variant, and an overload set resolved by
  static type picks the wrong member for it. }
function pylist_v(const v: Variant): TPyList;
{ The same for a DICT: `for k, v in options.items()` where options came out of
  another dict is a variant, and a two-name for-in needs the real TPyDict. }
function pydict_v(const v: Variant): TPyDict;
{ `f(*args, **kwargs)` FORWARDED into a fixed-arity callee (the third rung of
  feature-nilpy-star-args-kwargs). The call site emits a dispatch on the actual
  argument count, and these two check at run time what the desugar cannot check
  at compile time: that the count is one the callee accepts, and that no keyword
  arguments were forwarded — binding those by name would need a runtime call
  protocol, so it FAILS rather than dropping them silently. }
procedure pystar_check_arity(l: TPyList; lo: Integer; hi: Integer);
procedure pystar_no_kwargs(d: TPyDict);
{ One forwarded argument, or None when the caller passed fewer. The dispatch
  evaluates every slot up to the callee's widest arity before choosing an arm,
  so reading past the end has to be defined rather than an index error. }
function pystar_arg(l: TPyList; i: Integer): Variant;
{ abs() of a variant: the tag decides int or float, which the static
  __pxxAbsInt/__pxxAbsDbl split cannot (a for-in variable is a variant). }
function pyabs_v(const v: Variant): Variant;
function bool(const v: Variant): Boolean;
function bool(i: Int64): Boolean; overload;
function bool(d: Double): Boolean; overload;
function bool(const s: AnsiString): Boolean; overload;
function bool(l: TPyList): Boolean; overload;
function pylist_repeat(l: TPyList; n: Int64): TPyList;
function pybytes_repeat(b: TPyBytes; n: Int64): TPyBytes;
function pybytes_concat(a, b: TPyBytes): TPyBytes;
function pybytes_eq(a, b: TPyBytes): Boolean;
{ Lexicographic ORDER for bytes, -1/0/1, the same contract pylist_cmp has:
  element by element, then the shorter sequence first. Ordering operators on two
  statically-typed TPyBytes used to lower to a raw handle compare and answer
  from the two objects' HEAP ADDRESSES
  (bug-nilpy-list-ordering-compares-heap-addresses, the bytes half). }
function pybytes_cmp(a, b: TPyBytes): Int64;
function pyfile_open(const path, mode: AnsiString): TPyFile;
{ `s.rjust(w)` / `s.rjust(w, fill)` — right-align in a field of w characters.
  Python returns the string UNCHANGED when it is already at least that long
  (it never truncates), and the fill defaults to a space. }
function pystr_rjust(const s: AnsiString; w: Int64): AnsiString;
function pystr_rjust_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
function pytruediv_f(a: Double; b: Double): Double;
function pyfloordiv_i(a: Int64; b: Int64): Int64;
function pyfloormod_i(a: Int64; b: Int64): Int64;
function pyfloordiv_f(a: Double; b: Double): Double;
function pyfloormod_f(a: Double; b: Double): Double;
{ The VARIANT arm comes FIRST in each set, and that ordering is the fix, not a
  style choice: a subscript (`d["n"]`) is a variant RVALUE, matches no scalar
  arm, and resolution then bound the first declared one — the Int64 arm, handed
  a 16-byte variant unconverted, so `max(d["n"], 1)` printed a pointer while
  `v = d["n"]; max(v, 1)` was right. Declared first, the variant arm is what an
  unmatched argument falls back to, and it dispatches on the tag. }
function min(const a: Variant; const b: Variant): Variant;
function min(a: Int64; b: Int64): Int64; overload;
function min(a: Double; b: Double): Double; overload;
function max(const a: Variant; const b: Variant): Variant; overload;
function max(a: Int64; b: Int64): Int64; overload;
function max(a: Double; b: Double): Double; overload;
{ `list(x)` — a shallow COPY, as Python's list() constructor makes. Overloads
  rather than one variant-taking function so the ordinary call path resolves
  them by argument type, like min/max (feature-nilpy-missing-builtins). }
function list(l: TPyList): TPyList;
function list(const s: AnsiString): TPyList; overload;
function list(const v: Variant): TPyList; overload;
{ `list(b)` on a BYTES/bytearray yields its byte VALUES, as Python's does. It
  used to resolve to the TPyList arm — a TPyBytes handed to a list-typed
  parameter, whose `count` read the wrong field and answered 0, so the
  idiomatic way to look at a bytes value printed [] with no diagnostic
  (bug-nilpy-list-of-a-bytes-object-is-empty). `for x in b`, `len(b)` and
  `b[i]` were already right, so this is the constructor alone, not the
  iteration protocol. }
function list(b: TPyBytes): TPyList; overload;
{ tuple(iterable) — the same sequence with the TUPLE flag set. The tuple TYPE
  existed (literals work, and FKind distinguishes it) but the CONSTRUCTOR did
  not, so `tuple([1, 2])` failed with 'undefined variable (tuple)'.
  (bug-nilpy-sweep-gaps-pow-thousands-sep-stepped-slice) }
function tuple(l: TPyList): TPyList;
function tuple(const s: AnsiString): TPyList; overload;
{ tuple(b) — same as list(b) with the tuple flag; without it `tuple(<bytes>)`
  was a compile error ("no overload of tuple matches"), the loud sibling of
  the silent list(b). }
function tuple(b: TPyBytes): TPyList; overload;
{ pow(base, exp) — the function spelling of `**`, which already works. }
function pow(const a: Variant; const b: Variant): Variant;
{ pow(base, exp, mod) — MODULAR exponentiation, and genuinely a different
  algorithm rather than `(a ** b) mod m`: the intermediate power overflows long
  before the modulus does, which is the whole reason the three-argument form
  exists (bug-nilpy-sweep-gaps-pow-thousands-sep-stepped-slice, item 1).

  Integers only, as in CPython. The result takes the SIGN OF THE MODULUS —
  pow(2, 3, -5) is -2, not 3 — which is Python's floored-modulo rule and not
  what a plain `mod` gives. A NEGATIVE exponent is the modular INVERSE raised to
  |exp|, as in CPython 3.8+, and raises ValueError when the base is not coprime
  with the modulus — which is what CPython does too. }
function pow(a, b, m: Int64): Int64; overload;
{ `dict(x)` — a shallow COPY of a mapping, as Python's dict() constructor makes.
  Same overload-by-argument-type shape as list() (feature-nilpy-missing-builtins).
  uforth uses `dict(vm.dict)` to snapshot word-list state for MARKER. }
function dict(d: TPyDict): TPyDict; overload;
function dict(const v: Variant): TPyDict; overload;
{ dict(pairs) — the standard way to build a dict from zip(), .items() or parsed
  input, and platonically the overload that makes `dict([("a", 1)])` work.
  It is NOT selected yet: overload resolution takes the first candidate whose
  ARITY fits and never checks class identity for a class-typed parameter, so a
  TPyList argument binds to `dict(d: TPyDict)` above and its body reads a
  TPyList's fields as a TPyDict's — SIGSEGV
  (bug-nilpy-dict-from-pairs-and-bytes-decode-segfault, blocked on
  bug-a-overload-resolution-ignores-class-identity).
  Left in place rather than reordered on purpose: putting it FIRST does fix
  `dict(pairs)` but then breaks `dict(a_real_dict)` the same way, so ordering
  only moves the crash. Per the no-compiler-appeasement rule this stays
  platonic and waits for the resolution fix, at which point it starts being
  selected with no further change here. }
function dict(l: TPyList): TPyDict; overload;

{ dict.fromkeys(iterable): a dict with those keys, values None, insertion order
  preserved. `list(dict.fromkeys(xs))` is the standard order-preserving dedupe. }
function pydict_fromkeys(l: TPyList): TPyDict;
{ `set(iterable)` — Python's set constructor. A set is a TPyList here (see
  PyAnnTypeAt and TPyList.add), so this is "copy, skipping duplicates". The
  iterable may be a list/tuple/set, a dict (its KEYS, like CPython) or a string
  (its characters); anything else is a loud TypeError rather than a guess. }
function pyset_of(const v: Variant): TPyList;
{ `{**a, **b}` — copy src's pairs into dst, later keys winning, which is
  Python's merge rule. The frontend emits one call per `**` in a dict literal. }
procedure pydict_merge(dst: TPyDict; src: TPyDict);
{ The AGGREGATE builtins over a list (a generator expression already desugars to
  one). Each keeps Python's own answer for the empty case: sum([]) is 0, any([])
  is False, all([]) is True, and max/min of an empty sequence is an ERROR rather
  than a made-up value. Element arithmetic and comparison go through the same
  pyadd_v / PyVarCompare the operators use, so int/float/str behave as they do
  everywhere else (feature-nilpy-aggregate-builtins). }
{ a > b: numbers by value, strings by text — the comparison the aggregate
  builtins and pyeval's sorted() share. }
{ `map(int, xs)` / `map(str, xs)` / `map(float, xs)` — the conversion forms,
  which is what real code uses (`w, h = map(int, s.split("x"))`). A general
  map() over an arbitrary callable is separate work; the frontend refuses
  anything but a type name rather than guessing.
  feature-nilpy-aggregate-builtins. }
function pymap_int(l: TPyList): TPyList;
function pymap_str(l: TPyList): TPyList;
function pymap_float(l: TPyList): TPyList;
function pyvar_gt(const a: Variant; const b: Variant): Boolean;
{ `next(it)` / `next(it, default)` over a materialised sequence. NOT named
  `next`: itertools' counter already owns that name for its own argument type,
  and adding a TPyList overload made an untyped argument (a ClassVar holding a
  counter) pick the wrong one and SEGFAULT. The frontend maps the Python
  spelling onto these when the argument is a list. NilPy builds a
  generator expression into a LIST, so this is "the first element" — the whole
  sequence has already been evaluated, which is the documented difference from
  CPython's lazy generator (it matters only for an infinite or side-effecting
  generator, neither of which the corpus has). Without a default, an empty
  sequence raises StopIteration, as Python does. }
{ `zip(a, b)` as a VALUE — a list of [x, y] pairs, truncated to the shorter
  input, which is Python's rule. The for-header form never comes here: it walks
  both containers by index (PyParseForZip). }
function pyzip(a: TPyList; b: TPyList): TPyList;
{ `enumerate(xs)` as a VALUE — `for i, s in reversed(list(enumerate(t)))`. The
  for-HEADER form is a counted loop and never comes here; this is the
  materialised list of [index, item] pairs, the same shape pyzip builds. }
function pyenumerate(a: TPyList): TPyList;
{ `enumerate(xs, start)` / `enumerate(xs, start=N)` — same as pyenumerate with
  the index offset by `start`. }
function pyenumerate2(a: TPyList; start: Integer): TPyList;
{ A str exploded into a list of 1-character strs. The frontend wraps a str
  argument to zip()/enumerate() in this, because those build their calls by a
  fixed FindProc index and so never consult overloads
  (bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle). }
function pystr_charlist(const s: AnsiString): TPyList;
{ Python's `assert cond` / `assert cond, msg`. The frontend evaluates the
  condition's TRUTHINESS and hands the boolean here, so the container/str/None
  rules stay in PyMakeTruthy rather than being re-implemented. A raise (not a
  Halt) so `try/except AssertionError` runs, like every other NilPy error
  (bug-nilpy-assert-statement-not-supported). }
procedure pyassert(ok: Boolean; const msg: AnsiString);
{ Python's TWO-argument round(x, ndigits) — a float rounded to that many
  decimals, unlike the one-argument form which yields an int. Half-to-EVEN on
  the double's EXACT decimal value, which is CPython's rule; the body sits far
  below, next to the exact-decimal core it is built on. }
function pyround_n(x: Double; n: Integer): Double;
{ Python's math.floor/math.ceil return an int, unlike the RTL Math unit's
  Floor/Ceil (Double->Double, shared with the Pascal frontend and left alone
  here) -- these are the NilPy-specific int-returning shims, dispatched by
  name ahead of ordinary qualified-call resolution so `import math` never
  reaches the RTL's own Floor/Ceil for these two names. }
function pymath_floor(x: Double): Int64;
function pymath_ceil(x: Double): Int64;
function pymath_fabs(x: Double): Double;
function pynext_first(l: TPyList): Variant;
function pynext_first_or(l: TPyList; const dflt: Variant): Variant;
function sum(l: TPyList): Variant;
{ sum(iterable, start) — Python's optional second argument, the accumulator's
  initial value. `sum(xs, 10)` is an ordinary spelling and was rejected with
  "no overload of sum matches these arguments". }
function sum(l: TPyList; const start: Variant): Variant; overload;
{ Three- and four-argument min/max. Python's are variadic; only the
  two-argument and single-iterable forms existed, so `min(3, 1, 2)` did not
  compile (bug-nilpy-numeric-builtin-gaps-min-max-sum-float-inf). }
function min(const a, b, c: Variant): Variant; overload;
function min(const a, b, c, d: Variant): Variant; overload;
function max(const a, b, c: Variant): Variant; overload;
function max(const a, b, c, d: Variant): Variant; overload;
{ min(l)/max(l) over a LIST live in pyeval.pas, not here: Python's `key=` needs
  PyCallKey1's callable dispatch, and `pyeval uses pylib`, not the reverse.
  Keeping the keyless form here as well would make `min(xs)` ambiguous across
  the two units, so the whole list form moved rather than gaining a sibling. }
function max(const s: AnsiString): AnsiString; overload;
function min(const s: AnsiString): AnsiString; overload;
function any(l: TPyList): Boolean;
function all(l: TPyList): Boolean;

{ collections.Counter(...) — a TPyDict in Counter mode; see TPyDict. }
function Counter: TPyDict;
function Counter(l: TPyList): TPyDict; overload;
function Counter(const s: AnsiString): TPyDict; overload;
{ `reversed(x)` — Python returns a lazy iterator; NilPy's `for` is a counted-loop
  desugar with no iterator concept, so this is the reversed COPY, which behaves
  identically for `for x in reversed(xs)` and `list(reversed(xs))`. }
function reversed(l: TPyList): TPyList;
function reversed(const s: AnsiString): TPyList; overload;
{ `hex(n)` — Python spells it with the 0x prefix and lower-case digits, and
  spells a negative as -0x… rather than in two's complement. }
function hex(n: Int64): AnsiString;
{ `oct(n)` / `bin(n)` — same 0-prefix-and-sign convention as hex: 0o/0b, a
  leading '-' for a negative magnitude, and '0o0'/'0b0' for zero. }
function oct(n: Int64): AnsiString;
function bin(n: Int64): AnsiString;
function len(l: TPyList): Integer;
function len(d: TPyDict): Integer; overload;
function pydictcontains(d: TPyDict; const k: Variant): Boolean;
{ Python compares lists by CONTENTS. Element equality is PyVarEq, which
  already compares strings by text rather than by which copy you hold. }
function pylist_eq(a: TPyList; b: TPyList): Boolean;
{ …and the MIXED form: a list against a dynamically-typed value. `key ==
  cached_key` where the cache starts as None is ordinary Python, and comparing
  a tuple with a non-list is simply False — never an error. }
function pylist_eq_v(a: TPyList; const v: Variant): Boolean;
{ Python compares dicts by CONTENTS too — same length, and every key present in
  the other with an equal value. Order does NOT participate: `{"a":1,"b":2}`
  equals `{"b":2,"a":1}`, which is why this looks each key up rather than
  walking the two in parallel. Without it `{"k":1} == {"k":1}` was a pointer
  compare and answered False, so `if cfg == defaults:` never fired
  (bug-nilpy-dict-equality-compares-identity). Element equality is PyVarEq, the
  same rule pylist_eq uses, so nested lists and dicts compare by content too. }
function pydict_eq(a: TPyDict; b: TPyDict): Boolean;
function len(const s: AnsiString): Integer; overload;
{ len() of a VARIANT — a dynamically-typed value (a list element, a dataclass
  field, anything the frontend could not pin to a class). Without it, `len(x)`
  on such a value was a compile error listing only the class and string
  overloads, which is a wall for ordinary Python. }
function len(const v: Variant): Integer; overload;
function next(c: TPyCounter): Int64;
function pyvar_holds(const v: Variant; k: Int64): Boolean;
function pycontains(l: TPyList; const v: Variant): Boolean;
{ `x in <bytes>`. Python allows BOTH a bytes subsequence (`b"ell" in b"hello"`)
  and an integer byte value (`104 in b"hello"`). Without this the bytes receiver
  fell through to pycontains, which scans a TPyList — reading a TPyBytes'
  header words as variant slots and answering False
  (bug-nilpy-bytes-membership-always-false-for-a-bytes-needle). }
function pybytes_contains(b: TPyBytes; const v: Variant): Boolean;
function pyvar_contains(const c: Variant; const v: Variant): Boolean;
function pyset_and(a: TPyList; b: TPyList): TPyList;
function pyset_or(a: TPyList; b: TPyList): TPyList;
function pyset_sub(a: TPyList; b: TPyList): TPyList;
function pyset_xor(a: TPyList; b: TPyList): TPyList;
function pydict_or(a: TPyDict; b: TPyDict): TPyDict;
{ `sub in s` on a STRING is SUBSTRING containment in Python, not element
  membership. Without a case of its own it reached pycontains, which read the
  string handle as a TPyList and scanned its header words as variant slots —
  a segfault. }
function pystr_contains(const s: AnsiString; const sub: AnsiString): Boolean;
function pyvartag(const v: Variant): Int64;
function pyvarobj(const v: Variant): Pointer;
{ pyvarobj plus a RETAIN. Use where the unboxed pointer is STORED into a
  class-typed slot (a field, a class-typed local, a ctor argument that lands in
  a field): that slot is a new owning reference, but unlike a variant slot it is
  never released, so without the retain the object dies with the variant temp
  the value came out of and the slot dangles. The visible shape was a list built
  by `d.get(k, [])[:6]` passed to a dataclass ctor: correct at the call, garbage
  (a recycled block) by the time the field was read. }
function pyvarobj_owned(const v: Variant): Pointer;
{ The callee address of `<variant>(args)`, CHECKED. A name bound to None — an
  optional import that did not resolve, a value never assigned — has a nil
  payload, and calling it jumped to address 0: a segfault with no diagnostic,
  inside whatever routine happened to contain the call. Python raises TypeError
  there; so do we. }
function pyvar_callee_addr(const v: Variant; const what: AnsiString): Pointer;
{ The same unwrap for a `Callable[...]` PARAMETER, which is a bare pointer: it
  has no room for a receiver, so a BOUND METHOD cannot travel through one and
  says so plainly instead of borrowing the dynamic-call path's arity message
  (bug-nilpy-callable-annotated-param-segfaults-on-a-heap-callable). }
function pyvar_callable_ptr(const v: Variant; const what: AnsiString): Pointer;
{ `v[key]` / `v[key] = val` where v is a VARIANT holding a container — a dict
  entry that was itself a `.get()` result, so its container type is only known
  at run time. Dispatch on the boxed object: dict fetch/store by key, list index
  by an integer key. }
function pyvar_getitem(const v: Variant; const key: Variant): Variant;
procedure pyvar_setitem(const v: Variant; const key: Variant; const val: Variant);
{ DYNAMIC instance attributes: `obj.name = v` / `obj.name` where `name` is not a
  declared field (Python adds them freely). Stored in one global dict keyed by
  the object's address and the attribute name, so no per-class field is needed.
  uforth uses this for lazy state (`if not hasattr(vm, '_trans_ptr'): vm._trans_ptr = ...`). }
function pydynattr_get(obj: Pointer; const name: AnsiString): Variant;
procedure pydynattr_set(obj: Pointer; const name: AnsiString; const val: Variant);
function pydynattr_has(obj: Pointer; const name: AnsiString): Boolean;
{ `v[lo:hi]` where v is a VARIANT — slice the str/list/bytes it holds, at run
  time. Returns a variant of the same kind. }
function pyvar_slice(const v: Variant; lo, hi: Integer): Variant;
{ `v[lo:hi:step]` on a variant — same run-time tag dispatch, extended step. }
function pyvar_slice_step(const v: Variant; lo, hi, step: Integer): Variant;
{ `type(x).__name__` for any value — see the body for why the frontend cannot
  answer this from RTTI alone (tuple and list share one class). }
function pytype_name_v(const v: Variant): AnsiString;

{ str methods. The frontend desugars `s.upper()` into pystr_upper(s) — see
  PyParseStrMethod. ASCII-only for now: CPython's str.upper() is full-Unicode
  (and locale-independent), which needs a case-mapping table this unit does not
  carry yet. uforth's word names are ASCII plus emoji, and emoji are
  case-stable, so the corpus is unaffected; a non-ASCII byte passes through
  untouched rather than being mangled. Tracked in feature-nilpy-str-methods. }
function pystr_upper(const s: AnsiString): AnsiString;
function pystr_lower(const s: AnsiString): AnsiString;
function pystr_strip(const s: AnsiString): AnsiString;
function pystr_lstrip(const s: AnsiString): AnsiString;
function pystr_rstrip(const s: AnsiString): AnsiString;
function pystr_strip_chars(const s: AnsiString; const chars: AnsiString): AnsiString;
function pystr_lstrip_chars(const s: AnsiString; const chars: AnsiString): AnsiString;
function pystr_rstrip_chars(const s: AnsiString; const chars: AnsiString): AnsiString;
function pystr_startswith(const s: AnsiString; const pre: AnsiString): Boolean;
function pystr_endswith(const s: AnsiString; const suf: AnsiString): Boolean;
function pystr_find(const s: AnsiString; const sub: AnsiString): Integer;
{ str.index/rindex — like find/rfind but RAISE ValueError when absent, which is
  the whole difference and the reason both exist in Python. }
function pystr_index(const s: AnsiString; const sub: AnsiString): Integer;
function pystr_index_from(const s: AnsiString; const sub: AnsiString; start: Integer): Integer;
function pystr_rindex(const s: AnsiString; const sub: AnsiString): Integer;
{ str.find(sub, start): searches from `start` but reports the index in the
  ORIGINAL string, as Python does. }
function pystr_find_from(const s: AnsiString; const sub: AnsiString; start: Integer): Integer;
function pystr_isspace(const s: AnsiString): Boolean;
{ CPython: "".isdigit()/.isalpha()/.isupper()/.islower() are all FALSE — the
  all-quantifier does not hold vacuously for any of them. }
function pystr_isdigit(const s: AnsiString): Boolean;
function pystr_isalpha(const s: AnsiString): Boolean;
function pystr_isupper(const s: AnsiString): Boolean;
function pystr_islower(const s: AnsiString): Boolean;
function pystr_ofchar(c: Char): AnsiString;
function pystr_at(const s: AnsiString; i: Integer): Char;
{ Length() as a real Proc. The for-in desugar builds its AST directly and so
  needs a callable, not the shared parser's intrinsic path. }
function pystr_len(const s: AnsiString): Integer;
function pystr_join(const sep: AnsiString; l: TPyList): AnsiString;
function pystr_split_ws(const s: AnsiString): TPyList;
function pystr_split_sep(const s: AnsiString; const sep: AnsiString): TPyList;
function pystr_split_sep_max(const s: AnsiString; const sep: AnsiString; maxsplit: Integer): TPyList;
{ str.rsplit(sep, maxsplit) — splits counted from the right end. }
function pystr_rsplit_sep_max(const s: AnsiString; const sep: AnsiString; maxsplit: Integer): TPyList;
{ str.partition(sep) / str.rpartition(sep) — a 3-tuple (before, sep, after) at
  the first/last occurrence, or (s,'','') / ('','',s) when sep is absent. }
function pystr_partition(const s: AnsiString; const sep: AnsiString): TPyList;
function pystr_rpartition(const s: AnsiString; const sep: AnsiString): TPyList;
function pystr_splitlines(const s: AnsiString): TPyList;
{ str.replace(old, new[, count]) — CPython semantics: non-overlapping, left to
  right, a NEGATIVE count means "every occurrence", and an EMPTY pattern inserts
  the replacement between every character and at both ends
  ("abc".replace("", "-") = "-a-b-c-"). }
function pystr_replace(const s: AnsiString; const pat: AnsiString; const rep: AnsiString): AnsiString;
function pystr_replace_n(const s: AnsiString; const pat: AnsiString; const rep: AnsiString; count: Integer): AnsiString;
{ str.count(sub) — non-overlapping occurrences; an empty sub counts the gaps,
  Length(s)+1, as CPython does. }
function pystr_count(const s: AnsiString; const sub: AnsiString): Integer;
{ The optional start/end window Python gives find/rfind/index/count/startswith/
  endswith. One name per ARITY rather than an overload, because the frontend
  resolves these by name through FindProc, which never consults overloads
  ([[bug-nilpy-stdlib-shim-table-cannot-reach-an-overload]]) — the `_from` /
  `_range` suffix convention the str-method table already uses.

  The window is a SLICE, so it clamps and accepts negative indices exactly like
  s[a:b]; a returned INDEX is then rebased onto the original string, which is
  the part that would be silently wrong if the offset were forgotten
  (bug-nilpy-str-search-methods-lack-the-start-end-window). }
function pystr_count_from(const s, sub: AnsiString; a: Integer): Integer;
function pystr_count_range(const s, sub: AnsiString; a, b: Integer): Integer;
function pystr_find_range(const s, sub: AnsiString; a, b: Integer): Integer;
function pystr_index_range(const s, sub: AnsiString; a, b: Integer): Integer;
function pystr_rfind_from(const s, sub: AnsiString; a: Integer): Integer;
function pystr_rfind_range(const s, sub: AnsiString; a, b: Integer): Integer;
function pystr_startswith_from(const s, pre: AnsiString; a: Integer): Boolean;
function pystr_startswith_range(const s, pre: AnsiString; a, b: Integer): Boolean;
function pystr_endswith_from(const s, suf: AnsiString; a: Integer): Boolean;
function pystr_endswith_range(const s, suf: AnsiString; a, b: Integer): Boolean;
{ str.rfind(sub) — last occurrence, -1 when absent. }
function pystr_rfind(const s: AnsiString; const sub: AnsiString): Integer;
function pystr_title(const s: AnsiString): AnsiString;
function pystr_capitalize(const s: AnsiString): AnsiString;
function pystr_swapcase(const s: AnsiString): AnsiString;
function pystr_isalnum(const s: AnsiString): Boolean;
function pystr_ljust(const s: AnsiString; w: Int64): AnsiString;
function pystr_ljust_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
function pystr_center(const s: AnsiString; w: Int64): AnsiString;
function pystr_center_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
{ str.zfill(width) — left-pad with '0', keeping a leading sign in front. }
function pystr_zfill(const s: AnsiString; w: Int64): AnsiString;
{ str.expandtabs() / .expandtabs(n) — a TAB advances to the next multiple of
  tabsize measured from the start of the LINE, so the replacement width depends
  on the column and is not a fixed number of spaces. The column resets at \n and
  \r, which is what makes it per-line. tabsize <= 0 drops tabs outright, as
  CPython does (bug-nilpy-missing-builtins-step-slicing-range-into-list).
  Two arities, two NAMES: FindProc looks a proc up by bare name and is not
  arity-aware, so a same-named overload pair would resolve to whichever was
  registered first — the arity-suffix convention every other multi-arity str
  method here already uses. }
function pystr_expandtabs(const s: AnsiString): AnsiString;
function pystr_expandtabs_n(const s: AnsiString; tabsize: Int64): AnsiString;
function pystr_removeprefix(const s: AnsiString; const pre: AnsiString): AnsiString;
function pystr_removesuffix(const s: AnsiString; const suf: AnsiString): AnsiString;

implementation

{ Python's whitespace set for the argument-less strip()/isspace():
  space, tab, newline, carriage return, vertical tab, form feed. }
function PyIsSpaceCh(c: Char): Boolean;
begin
  PyIsSpaceCh := (c = ' ') or (c = Chr(9)) or (c = Chr(10)) or
                 (c = Chr(11)) or (c = Chr(12)) or (c = Chr(13));
end;

function pystr_upper(const s: AnsiString): AnsiString;
var i: Integer;
    c: Char;
begin
  { Preallocate to the known final length and write in place. The old
    `Result := Result + c` reallocated the whole string every byte — O(n^2)
    per call, and one of the top PXXStrConcat callers in profiles. }
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then
      c := Chr(Ord(c) - 32);
    Result[i] := c;
  end;
end;

function pystr_lower(const s: AnsiString): AnsiString;
var i: Integer;
    c: Char;
begin
  SetLength(Result, Length(s));   { preallocate — see pystr_upper (no per-byte realloc) }
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then
      c := Chr(Ord(c) + 32);
    Result[i] := c;
  end;
end;

{ Char -> 1-length str. Python has no character type, so a tyChar base for a
  str method (a one-char literal, or s[i]) must become a real string. Done as an
  EXPLICIT call rather than leaning on the implicit char->string conversion,
  which keys on node SHAPE not type: the literal shape converted but the
  subscript shape did not, so s[0].upper() silently produced a NUL byte
  (project_string_conversion_shape_blindspot_pattern). }
function pystr_ofchar(c: Char): AnsiString;
begin
  Result := c;
end;

function pystr_len(const s: AnsiString): Integer;
begin
  Result := Length(s);
end;

{ Python's s[i]: 0-BASED, and a NEGATIVE index counts from the end (s[-1] is the
  last character). Pascal's own subscript is 1-based with no negative form, so
  handing the index straight through read one character early and made s[0] a
  NUL — silently, on all 123 uforth subscript sites
  (bug-nilpy-str-index-off-by-one). Out of range raises IndexError like CPython,
  matching TPyList's existing PyListFix behaviour. }
{ ord() of a str. Python has no char type, so a 1-character literal is a str
  like any other and ord("a") must read its single character. }
function pyord_s(const s: AnsiString): Int64;
begin
  if Length(s) <> 1 then
  begin
    raise TypeError.Create('ord() expected a character, but string of length ' +
                           pystr_of(Int64(Length(s))) + ' found');
  end;
  Result := Ord(s[1]);
end;

{ NilPy strings are byte strings (bug-nilpy-encode-ignores-the-codec), so
  chr()'s honest range is a single byte, 0..255 -- the same range ord()
  already agrees with (pyord_s takes exactly one byte). The underlying `Chr`
  intrinsic has no bounds check of its own and silently truncated (`chr(8364)`
  gave a wrong byte instead of an error), a silent-wrong-value bug worse than
  the ticket's own repro
  (bug-nilpy-non-ascii-string-surface-measured). Loudly refusing what the byte
  model cannot represent, rather than truncating, needs no resolution of the
  larger byte-vs-codepoint string-model question that ticket defers. }
function PyChrRangeCheck(n: Int64): Int64;
begin
  if (n < 0) or (n > 255) then
    raise ValueError.Create('chr() arg not in range(256) -- NilPy strings are byte strings');
  Result := n;
end;

function pystr_at(const s: AnsiString; i: Integer): Char;
var n: Integer;
begin
  n := Length(s);
  if i < 0 then i := n + i;
  if (i < 0) or (i >= n) then
  begin
    raise IndexError.Create('string index out of range');
  end;
  Result := s[i + 1];
end;

function pystr_lstrip(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  n := Length(s);
  i := 1;
  while (i <= n) and PyIsSpaceCh(s[i]) do Inc(i);
  Result := Copy(s, i, n - i + 1);
end;

function pystr_rstrip(const s: AnsiString): AnsiString;
var n: Integer;
begin
  n := Length(s);
  while (n >= 1) and PyIsSpaceCh(s[n]) do Dec(n);
  Result := Copy(s, 1, n);
end;

function pystr_strip(const s: AnsiString): AnsiString;
begin
  Result := pystr_lstrip(pystr_rstrip(s));
end;

{ strip/lstrip/rstrip with an explicit CHARS argument: remove any leading or
  trailing character that appears in `chars` (Python's set semantics), rather
  than whitespace. `raw.rstrip("\n")` in uforth is the driving case. }
function PyInCharSet(c: Char; const chars: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to Length(chars) do
    if chars[i] = c then begin Result := True; Exit; end;
end;

function pystr_lstrip_chars(const s: AnsiString; const chars: AnsiString): AnsiString;
var i, n: Integer;
begin
  n := Length(s);
  i := 1;
  while (i <= n) and PyInCharSet(s[i], chars) do Inc(i);
  Result := Copy(s, i, n - i + 1);
end;

function pystr_rstrip_chars(const s: AnsiString; const chars: AnsiString): AnsiString;
var n: Integer;
begin
  n := Length(s);
  while (n >= 1) and PyInCharSet(s[n], chars) do Dec(n);
  Result := Copy(s, 1, n);
end;

function pystr_strip_chars(const s: AnsiString; const chars: AnsiString): AnsiString;
begin
  Result := pystr_lstrip_chars(pystr_rstrip_chars(s, chars), chars);
end;

function pystr_startswith(const s: AnsiString; const pre: AnsiString): Boolean;
var i, n: Integer;
begin
  n := Length(pre);
  if n > Length(s) then begin Result := False; Exit; end;
  for i := 1 to n do
    if s[i] <> pre[i] then begin Result := False; Exit; end;
  Result := True;   { "".startswith("") is True in CPython, and falls out here }
end;

function pystr_endswith(const s: AnsiString; const suf: AnsiString): Boolean;
var i, n, base: Integer;
begin
  n := Length(suf);
  base := Length(s) - n;
  if base < 0 then begin Result := False; Exit; end;
  for i := 1 to n do
    if s[base + i] <> suf[i] then begin Result := False; Exit; end;
  Result := True;
end;

{ CPython's str.find: 0-BASED index of the first occurrence, -1 when absent.
  Deliberately not Pascal's Pos, which is 1-based and returns 0 when absent —
  returning that unadjusted would be silently off by one everywhere and would
  make "not found" read as "found at index 0". An empty needle finds at 0. }
function pystr_find(const s: AnsiString; const sub: AnsiString): Integer;
var i, j, n, m: Integer;
    hit: Boolean;
begin
  n := Length(s);
  m := Length(sub);
  if m = 0 then begin Result := 0; Exit; end;
  for i := 1 to n - m + 1 do
  begin
    hit := True;
    for j := 1 to m do
      if s[i + j - 1] <> sub[j] then begin hit := False; Break; end;
    if hit then begin Result := i - 1; Exit; end;
  end;
  Result := -1;
end;

function pystr_find_from(const s: AnsiString; const sub: AnsiString; start: Integer): Integer;
var tail: AnsiString; r: Integer;
begin
  if start < 0 then start := start + Length(s);
  if start < 0 then start := 0;
  if start > Length(s) then begin Result := -1; Exit; end;
  tail := Copy(s, start + 1, Length(s) - start);
  r := pystr_find(tail, sub);
  if r < 0 then Result := -1 else Result := r + start;
end;

function pystr_index(const s: AnsiString; const sub: AnsiString): Integer;
begin
  Result := pystr_find(s, sub);
  if Result < 0 then
    raise ValueError.Create('substring not found');
end;

function pystr_index_from(const s: AnsiString; const sub: AnsiString; start: Integer): Integer;
begin
  Result := pystr_find_from(s, sub, start);
  if Result < 0 then
    raise ValueError.Create('substring not found');
end;

function pystr_rindex(const s: AnsiString; const sub: AnsiString): Integer;
begin
  Result := pystr_rfind(s, sub);
  if Result < 0 then
    raise ValueError.Create('substring not found');
end;

function pystr_isdigit(const s: AnsiString): Boolean;
var i: Integer;
begin
  if Length(s) = 0 then begin pystr_isdigit := False; Exit; end;
  for i := 1 to Length(s) do
    if not (s[i] in ['0'..'9']) then begin pystr_isdigit := False; Exit; end;
  pystr_isdigit := True;
end;

function pystr_isalpha(const s: AnsiString): Boolean;
var i: Integer;
begin
  if Length(s) = 0 then begin pystr_isalpha := False; Exit; end;
  for i := 1 to Length(s) do
    if not (s[i] in ['A'..'Z', 'a'..'z']) then begin pystr_isalpha := False; Exit; end;
  pystr_isalpha := True;
end;

{ CPython: a string with no CASED characters is neither upper nor lower, so
  "123".isupper() is False while "A1".isupper() is True. }
function pystr_isupper(const s: AnsiString): Boolean;
var i: Integer; cased: Boolean;
begin
  cased := False;
  for i := 1 to Length(s) do
  begin
    if s[i] in ['a'..'z'] then begin pystr_isupper := False; Exit; end;
    if s[i] in ['A'..'Z'] then cased := True;
  end;
  pystr_isupper := cased;
end;

function pystr_islower(const s: AnsiString): Boolean;
var i: Integer; cased: Boolean;
begin
  cased := False;
  for i := 1 to Length(s) do
  begin
    if s[i] in ['A'..'Z'] then begin pystr_islower := False; Exit; end;
    if s[i] in ['a'..'z'] then cased := True;
  end;
  pystr_islower := cased;
end;

{ CPython: "".isspace() is FALSE — an empty string has no characters to be
  whitespace, so the all-quantifier does not vacuously hold here. }
function pystr_isspace(const s: AnsiString): Boolean;
var i: Integer;
begin
  if Length(s) = 0 then begin Result := False; Exit; end;
  for i := 1 to Length(s) do
    if not PyIsSpaceCh(s[i]) then begin Result := False; Exit; end;
  Result := True;
end;

function pyvartag(const v: Variant): Int64;
begin
  Result := PPyVarRec(@v)^.VType;
end;

{ s.split() with NO argument: split on RUNS of whitespace, with leading and
  trailing whitespace ignored — so "".split() and "   ".split() are both [],
  and " a  b ".split() is ["a","b"]. This is a GENUINELY DIFFERENT algorithm
  from split(sep) below, not a default argument, which is why they are separate
  functions rather than one with an optional sep. }
{ s.split() with NO argument: split on RUNS of whitespace, with leading and
  trailing whitespace ignored — so "".split() and "   ".split() are both [],
  and " a  b ".split() is ["a","b"]. A GENUINELY DIFFERENT algorithm from
  split(sep), not a default argument, hence two functions.

  Every element is a FRESH Copy() of the source rather than an accumulated
  local: a list slot stores the variant's string PAYLOAD POINTER, so appending
  a reused accumulator made all three elements alias its final contents. }
function pystr_split_ws(const s: AnsiString): TPyList;
var i, n, st: Integer;
begin
  Result := TPyList.Create;
  n := Length(s);
  i := 1;
  while i <= n do
  begin
    while (i <= n) and PyIsSpaceCh(s[i]) do Inc(i);
    if i > n then Break;
    st := i;
    while (i <= n) and not PyIsSpaceCh(s[i]) do Inc(i);
    Result.append(Copy(s, st, i - st));
  end;
end;

{ s.split(sep): split on an exact separator, KEEPING empty fields —
  "a,,b".split(",") is ["a","","b"] and "".split(",") is [""]. Contrast
  split() above, which drops them. An empty separator is a ValueError in
  CPython. }
function pystr_split_sep(const s: AnsiString; const sep: AnsiString): TPyList;
var i, j, n, m, st: Integer;
    hit: Boolean;
begin
  Result := TPyList.Create;
  n := Length(s);
  m := Length(sep);
  if m = 0 then
  begin
    raise ValueError.Create('empty separator');
  end;
  st := 1;
  i := 1;
  while i <= n do
  begin
    hit := False;
    if i + m - 1 <= n then
    begin
      hit := True;
      for j := 1 to m do
        if s[i + j - 1] <> sep[j] then begin hit := False; Break; end;
    end;
    if hit then
    begin
      Result.append(Copy(s, st, i - st));
      i := i + m;
      st := i;
    end
    else
      Inc(i);
  end;
  Result.append(Copy(s, st, n - st + 1));
end;

{ s.split(sep, maxsplit): at most `maxsplit` splits, so the result has at most
  maxsplit+1 fields — the remainder (including further separators) is the last. }
function pystr_split_sep_max(const s: AnsiString; const sep: AnsiString; maxsplit: Integer): TPyList;
var i, j, n, m, st, done: Integer; hit: Boolean;
begin
  Result := TPyList.Create;
  n := Length(s);
  m := Length(sep);
  if m = 0 then
  begin
    raise ValueError.Create('empty separator');
  end;
  if maxsplit < 0 then begin Result := pystr_split_sep(s, sep); Exit; end;
  st := 1; i := 1; done := 0;
  while (i <= n) and (done < maxsplit) do
  begin
    hit := False;
    if i + m - 1 <= n then
    begin
      hit := True;
      for j := 1 to m do
        if s[i + j - 1] <> sep[j] then begin hit := False; Break; end;
    end;
    if hit then
    begin
      Result.append(Copy(s, st, i - st));
      i := i + m; st := i; Inc(done);
    end
    else
      Inc(i);
  end;
  Result.append(Copy(s, st, n - st + 1));
end;

{ s.rsplit(sep, maxsplit): like split(sep, maxsplit) but the splits are taken
  from the RIGHT end — the fields nearest the end are separated first, and
  whatever remains at the front (including further separators) is the FIRST
  field, e.g. "a,b,c".rsplit(",", 1) is ["a,b", "c"]. maxsplit < 0 behaves like
  the unlimited split(sep). }
function pystr_rsplit_sep_max(const s: AnsiString; const sep: AnsiString; maxsplit: Integer): TPyList;
var i, j, n, m, en, done: Integer; hit: Boolean; parts: TPyList; k: Integer;
begin
  n := Length(s);
  m := Length(sep);
  if m = 0 then
  begin
    raise ValueError.Create('empty separator');
  end;
  if maxsplit < 0 then begin Result := pystr_split_sep(s, sep); Exit; end;
  { collect fields walking backward, then reverse into Result }
  parts := TPyList.Create;
  en := n; i := n; done := 0;
  while (i >= 1) and (done < maxsplit) do
  begin
    hit := False;
    if i - m + 1 >= 1 then
    begin
      hit := True;
      for j := 1 to m do
        if s[i - m + j] <> sep[j] then begin hit := False; Break; end;
    end;
    if hit then
    begin
      parts.append(Copy(s, i + 1, en - i));
      i := i - m; en := i; Inc(done);
    end
    else
      Dec(i);
  end;
  parts.append(Copy(s, 1, en));
  Result := TPyList.Create;
  for k := parts.count - 1 downto 0 do Result.append(parts.at(k));
end;

{ s.partition(sep) — a 3-tuple (before, sep, after) at the FIRST occurrence, or
  (s, '', '') when sep is absent. }
function pystr_partition(const s: AnsiString; const sep: AnsiString): TPyList;
var idx: Integer;
begin
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  idx := Pos(sep, s);
  if idx = 0 then
  begin
    Result.append(s); Result.append(''); Result.append('');
  end
  else
  begin
    Result.append(Copy(s, 1, idx - 1));
    Result.append(sep);
    Result.append(Copy(s, idx + Length(sep), Length(s) - idx - Length(sep) + 1));
  end;
end;

{ s.rpartition(sep) — same shape as partition, at the LAST occurrence, or
  ('', '', s) when sep is absent. }
function pystr_rpartition(const s: AnsiString; const sep: AnsiString): TPyList;
var idx, i, n, m, j: Integer; hit: Boolean;
begin
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  n := Length(s); m := Length(sep);
  idx := 0;
  if m > 0 then
    for i := n - m + 1 downto 1 do
    begin
      hit := True;
      for j := 1 to m do
        if s[i + j - 1] <> sep[j] then begin hit := False; Break; end;
      if hit then begin idx := i; Break; end;
    end;
  if idx = 0 then
  begin
    Result.append(''); Result.append(''); Result.append(s);
  end
  else
  begin
    Result.append(Copy(s, 1, idx - 1));
    Result.append(sep);
    Result.append(Copy(s, idx + m, n - idx - m + 1));
  end;
end;

{ s.splitlines(): split on newlines, and a TRAILING newline does not produce a
  final empty field — "a\n".splitlines() is ["a"], not ["a",""]. "" is []. That
  trailing rule is what separates it from split("\n"). }
function pystr_splitlines(const s: AnsiString): TPyList;
var i, n, st: Integer;
begin
  Result := TPyList.Create;
  n := Length(s);
  st := 1;
  i := 1;
  while i <= n do
  begin
    if s[i] = Chr(10) then
    begin
      Result.append(Copy(s, st, i - st));
      st := i + 1;
    end;
    Inc(i);
  end;
  if st <= n then Result.append(Copy(s, st, n - st + 1));
end;

{ Does `pat` sit at s[i]? Shared by replace/count/rfind. i is 1-based and the
  caller has already checked that pat FITS at i. }
function PyStrMatchAt(const s: AnsiString; i: Integer; const pat: AnsiString): Boolean;
var j, m: Integer;
begin
  m := Length(pat);
  for j := 1 to m do
    if s[i + j - 1] <> pat[j] then begin Result := False; Exit; end;
  Result := True;
end;

function pystr_replace_n(const s: AnsiString; const pat: AnsiString; const rep: AnsiString; count: Integer): AnsiString;
var n, m, k, i, j, hits, outLen, o, used: Integer;
begin
  n := Length(s); m := Length(pat); k := Length(rep);
  if m = 0 then
  begin
    { empty pattern: rep goes before every character and once at the end }
    hits := n + 1;
    if (count >= 0) and (count < hits) then hits := count;
    SetLength(Result, n + hits * k);
    o := 1; used := 0;
    for i := 1 to n + 1 do
    begin
      if used < hits then
      begin
        for j := 1 to k do begin Result[o] := rep[j]; Inc(o); end;
        Inc(used);
      end;
      if i <= n then begin Result[o] := s[i]; Inc(o); end;
    end;
    Exit;
  end;
  { pass 1: how many non-overlapping matches will be taken }
  hits := 0; i := 1;
  while i <= n - m + 1 do
  begin
    if (count >= 0) and (hits >= count) then Break;
    if PyStrMatchAt(s, i, pat) then begin Inc(hits); i := i + m; end
    else Inc(i);
  end;
  if hits = 0 then begin Result := s; Exit; end;
  { pass 2: write the result in one preallocated buffer (no per-byte realloc) }
  outLen := n + hits * (k - m);
  SetLength(Result, outLen);
  o := 1; i := 1; used := 0;
  while i <= n do
  begin
    if (used < hits) and (i <= n - m + 1) and PyStrMatchAt(s, i, pat) then
    begin
      for j := 1 to k do begin Result[o] := rep[j]; Inc(o); end;
      Inc(used);
      i := i + m;
    end
    else
    begin
      Result[o] := s[i]; Inc(o); Inc(i);
    end;
  end;
end;

function pystr_replace(const s: AnsiString; const pat: AnsiString; const rep: AnsiString): AnsiString;
begin
  Result := pystr_replace_n(s, pat, rep, -1);
end;

function pystr_count(const s: AnsiString; const sub: AnsiString): Integer;
var n, m, i: Integer;
begin
  n := Length(s); m := Length(sub);
  if m = 0 then begin Result := n + 1; Exit; end;
  Result := 0;
  i := 1;
  while i <= n - m + 1 do
    if PyStrMatchAt(s, i, sub) then begin Inc(Result); i := i + m; end
    else Inc(i);
end;

function pystr_rfind(const s: AnsiString; const sub: AnsiString): Integer;
var n, m, i: Integer;
begin
  n := Length(s); m := Length(sub);
  if m = 0 then begin Result := n; Exit; end;   { CPython: "abc".rfind("") = 3 }
  i := n - m + 1;
  while i >= 1 do
  begin
    if PyStrMatchAt(s, i, sub) then begin Result := i - 1; Exit; end;   { 0-based }
    Dec(i);
  end;
  Result := -1;
end;

{ ---- the start/end window (see the interface block) ---------------------- }

function pystr_count_from(const s, sub: AnsiString; a: Integer): Integer;
begin
  Result := pystr_count(pystr_slice(s, a, PY_SLICE_OMIT), sub);
end;

function pystr_count_range(const s, sub: AnsiString; a, b: Integer): Integer;
begin
  Result := pystr_count(pystr_slice(s, a, b), sub);
end;

{ a found index is relative to the WINDOW, so rebase it onto the original
  string; -1 (not found) must stay -1 rather than becoming the offset }
function PyWindowStart(n, a: Integer): Integer;
var lo, hi: Integer;
begin
  lo := a; hi := PY_SLICE_OMIT;
  PySliceBounds(n, lo, hi);
  Result := lo;
end;

function pystr_find_range(const s, sub: AnsiString; a, b: Integer): Integer;
begin
  Result := pystr_find(pystr_slice(s, a, b), sub);
  if Result >= 0 then Result := Result + PyWindowStart(Length(s), a);
end;

function pystr_index_range(const s, sub: AnsiString; a, b: Integer): Integer;
begin
  Result := pystr_find_range(s, sub, a, b);
  if Result < 0 then raise ValueError.Create('substring not found');
end;

function pystr_rfind_from(const s, sub: AnsiString; a: Integer): Integer;
begin
  Result := pystr_rfind(pystr_slice(s, a, PY_SLICE_OMIT), sub);
  if Result >= 0 then Result := Result + PyWindowStart(Length(s), a);
end;

function pystr_rfind_range(const s, sub: AnsiString; a, b: Integer): Integer;
begin
  Result := pystr_rfind(pystr_slice(s, a, b), sub);
  if Result >= 0 then Result := Result + PyWindowStart(Length(s), a);
end;

function pystr_startswith_from(const s, pre: AnsiString; a: Integer): Boolean;
begin
  Result := pystr_startswith(pystr_slice(s, a, PY_SLICE_OMIT), pre);
end;

function pystr_startswith_range(const s, pre: AnsiString; a, b: Integer): Boolean;
begin
  Result := pystr_startswith(pystr_slice(s, a, b), pre);
end;

function pystr_endswith_from(const s, suf: AnsiString; a: Integer): Boolean;
begin
  Result := pystr_endswith(pystr_slice(s, a, PY_SLICE_OMIT), suf);
end;

function pystr_endswith_range(const s, suf: AnsiString; a, b: Integer): Boolean;
begin
  Result := pystr_endswith(pystr_slice(s, a, b), suf);
end;

function PyIsWordCh(c: Char): Boolean;
begin
  Result := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
            ((c >= '0') and (c <= '9'));
end;

function pystr_title(const s: AnsiString): AnsiString;
{ CPython: the first cased character of each run of word characters is upper,
  the rest lower. Digits count as word characters but are not cased. }
var i: Integer; c: Char; atStart: Boolean;
begin
  SetLength(Result, Length(s));
  atStart := True;
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if atStart then
    begin
      if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32);
    end
    else if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    Result[i] := c;
    atStart := not PyIsWordCh(s[i]);
  end;
end;

function pystr_capitalize(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if i = 1 then
    begin
      if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32);
    end
    else if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    Result[i] := c;
  end;
end;

function pystr_swapcase(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32)
    else if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    Result[i] := c;
  end;
end;

function pystr_isalnum(const s: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if Length(s) = 0 then Exit;   { "".isalnum() is False, like the other is* }
  for i := 1 to Length(s) do
    if not PyIsWordCh(s[i]) then Exit;
  Result := True;
end;

function pystr_ljust_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
var n, i: Integer; f: Char;
begin
  n := Length(s);
  if (w <= n) or (Length(fill) = 0) then begin Result := s; Exit; end;
  f := fill[1];
  SetLength(Result, Integer(w));
  for i := 1 to n do Result[i] := s[i];
  for i := n + 1 to Integer(w) do Result[i] := f;
end;

function pystr_ljust(const s: AnsiString; w: Int64): AnsiString;
begin
  Result := pystr_ljust_c(s, w, ' ');
end;

function pystr_center_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
var n, i, left: Integer; f: Char;
begin
  n := Length(s);
  if (w <= n) or (Length(fill) = 0) then begin Result := s; Exit; end;
  f := fill[1];
  { CPython's exact rule (Objects/unicodeobject.c pad()):
      marg = width - len;  left = marg div 2 + (marg and width and 1)
    — so the odd extra pad lands on the LEFT only when both marg and width are
    odd. "ab".center(5) = "  ab ", "abc".center(6) = " abc  ". }
  left := (Integer(w) - n) div 2 + ((Integer(w) - n) and Integer(w) and 1);
  SetLength(Result, Integer(w));
  for i := 1 to left do Result[i] := f;
  for i := 1 to n do Result[left + i] := s[i];
  for i := left + n + 1 to Integer(w) do Result[i] := f;
end;

function pystr_center(const s: AnsiString; w: Int64): AnsiString;
begin
  Result := pystr_center_c(s, w, ' ');
end;

function pystr_expandtabs_n(const s: AnsiString; tabsize: Int64): AnsiString;
var i, k, col, n, outLen: Integer; ch: Char;
begin
  { size first, then fill — `Result := Result + ch` in a loop is QUADRATIC here
    (project_pxx_string_concat_in_loop_is_quadratic). }
  outLen := 0; col := 0;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if ch = #9 then
    begin
      if tabsize <= 0 then n := 0
      else n := Integer(tabsize) - (col mod Integer(tabsize));
      outLen := outLen + n; col := col + n;
    end
    else if (ch = #10) or (ch = #13) then begin outLen := outLen + 1; col := 0; end
    else begin outLen := outLen + 1; col := col + 1; end;
  end;
  SetLength(Result, outLen);
  k := 1; col := 0;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if ch = #9 then
    begin
      if tabsize <= 0 then n := 0
      else n := Integer(tabsize) - (col mod Integer(tabsize));
      while n > 0 do begin Result[k] := ' '; Inc(k); Dec(n); Inc(col); end;
    end
    else if (ch = #10) or (ch = #13) then
    begin Result[k] := ch; Inc(k); col := 0; end
    else begin Result[k] := ch; Inc(k); Inc(col); end;
  end;
end;

function pystr_expandtabs(const s: AnsiString): AnsiString;
begin
  pystr_expandtabs := pystr_expandtabs_n(s, 8);   { Python's default tabsize }
end;

function pystr_zfill(const s: AnsiString; w: Int64): AnsiString;
var n, i, pad, signLen: Integer;
begin
  n := Length(s);
  if w <= n then begin Result := s; Exit; end;
  signLen := 0;
  if (n > 0) and ((s[1] = '-') or (s[1] = '+')) then signLen := 1;
  pad := Integer(w) - n;
  SetLength(Result, Integer(w));
  for i := 1 to signLen do Result[i] := s[i];
  for i := signLen + 1 to signLen + pad do Result[i] := '0';
  for i := signLen + 1 to n do Result[i + pad] := s[i];
end;

function pystr_removeprefix(const s: AnsiString; const pre: AnsiString): AnsiString;
begin
  if (Length(pre) > 0) and pystr_startswith(s, pre) then
    Result := Copy(s, Length(pre) + 1, Length(s) - Length(pre))
  else
    Result := s;
end;

function pystr_removesuffix(const s: AnsiString; const suf: AnsiString): AnsiString;
begin
  if (Length(suf) > 0) and pystr_endswith(s, suf) then
    Result := Copy(s, 1, Length(s) - Length(suf))
  else
    Result := s;
end;

{ sep.join(list). CPython requires every item to BE a str and raises TypeError
  otherwise — it does not stringify. Matched here rather than quietly calling
  VariantToStr on an int, which would turn a real type error into plausible
  wrong output. Variant tags: 5 = char, 6 = ansistring; a char is a 1-length
  str in Python terms, so both are accepted.
  Python's join takes any iterable; only TPyList is supported for now. }
function pystr_join(const sep: AnsiString; l: TPyList): AnsiString;
{ Preallocate to the known final length (sum of item lengths + sep*(n-1))
  and write in place. The old `Result := Result + sep`/`+ item` reallocated
  the whole string on every item — O(n^2) in the joined length, the same
  PXXStrConcat pattern pystr_upper/lower were fixed for
  (perf-nilpy-remaining-perbyte-string-builders). Each item is materialised
  ONCE into `items` (VariantToStr is not idempotent-cheap to call twice)
  and its length summed before the single allocation. }
var i, j, n, totalLen, pos: Integer;
    v: Variant;
    tag: Int64;
    items: array of AnsiString;
begin
  n := l.count;
  SetLength(items, n);
  totalLen := 0;
  for i := 0 to n - 1 do
  begin
    v := l.at(i);
    tag := pyvartag(v);
    if (tag <> 6) and (tag <> 5) then
    begin
      raise TypeError.Create('sequence item ' + pystr_of(Int64(i)) +
                             ': expected str instance');
    end;
    items[i] := VariantToStr(v);
    Inc(totalLen, Length(items[i]));
    if i > 0 then Inc(totalLen, Length(sep));
  end;
  SetLength(Result, totalLen);
  pos := 1;
  for i := 0 to n - 1 do
  begin
    if i > 0 then
      for j := 1 to Length(sep) do
      begin
        Result[pos] := sep[j];
        Inc(pos);
      end;
    for j := 1 to Length(items[i]) do
    begin
      Result[pos] := items[i][j];
      Inc(pos);
    end;
  end;
end;

function pyvarobj(const v: Variant): Pointer;
begin
  Result := Pointer(PPyVarRec(@v)^.Payload);
end;

function pyvar_callable_ptr(const v: Variant; const what: AnsiString): Pointer;
var nm: AnsiString;
begin
  if what = '' then nm := 'this argument' else nm := 'parameter ' + what;
  if (PPyVarRec(@v)^.VType = 8) and (pybound_recv(v) <> nil) then
    raise TypeError.Create(nm + ' is declared Callable[...], '
      + 'which carries a code address only, and a BOUND METHOD also needs its '
      + 'receiver — pass a plain function, a lambda, or declare the parameter '
      + 'without an annotation');
  Result := Pointer(PPyVarRec(@v)^.Payload);
  if Result = nil then
    raise TypeError.Create(nm + ' is not callable — the value '
      + 'is None (an import that did not resolve, or a name never assigned)');
end;

function pyvar_callee_addr(const v: Variant; const what: AnsiString): Pointer;
var nm: AnsiString;
begin
  { A FUNCTION VALUE (VT_BOUNDMETHOD, tag 8) carries a {code, recv} PAIR pointer,
    not a code address — jumping to the payload landed in the pair's own bytes.
    Unwrap it. A pair with a receiver cannot be called through this path at all
    (the receiver has to be prepended to the argument list); the dynamic-call
    guard routes those to pybound_callv*, so reaching here with one means an
    arity past that guard — say so instead of calling the method without Self. }
  if PPyVarRec(@v)^.VType = 8 then
  begin
    if pybound_recv(v) <> nil then
    begin
      if what = '' then nm := 'object' else nm := what;
      raise TypeError.Create(nm + ' is a bound method taking too '
        + 'many arguments to call through a name (max 3)');
    end;
    Result := pybound_code(v);
  end
  else
    Result := Pointer(PPyVarRec(@v)^.Payload);
  if Result = nil then
  begin
    if what = '' then nm := 'object' else nm := what;
    raise TypeError.Create(nm + ' is not callable — the name is '
      + 'None (an import that did not resolve, or a value never assigned)');
  end;
end;

var
  PyDynAttrStore: TPyDict;   { lazily created; keys are "addr:name" }

function PyDynAttrKey(obj: Pointer; const name: AnsiString): AnsiString;
begin
  Result := pystr_of(Int64(NativeInt(obj))) + ':' + name;
end;

procedure pydynattr_set(obj: Pointer; const name: AnsiString; const val: Variant);
begin
  if PyDynAttrStore = nil then PyDynAttrStore := TPyDict.Create;
  PyDynAttrStore.store(PyDynAttrKey(obj, name), val);
end;

function pydynattr_has(obj: Pointer; const name: AnsiString): Boolean;
begin
  Result := (PyDynAttrStore <> nil) and
            (PyDynAttrStore.indexof(PyDynAttrKey(obj, name)) >= 0);
end;

function pydynattr_get(obj: Pointer; const name: AnsiString): Variant;
begin
  { Reached with a receiver STATICALLY known to be a real class instance (or
    nil, a class-typed field/local defaulting to None) — never an int/str/etc
    scalar, so ClassName on a non-nil `obj` is always safe here. A miss is a
    genuinely missing attribute, not a "maybe dynamic, maybe not" ambiguity:
    hasattr/getattr(o, n, default) both resolve through pydynattr_has FIRST
    and never reach this branch on a miss (see their call sites in
    parser.inc), so raising cannot break either. Silently answering None
    instead let a typo'd attribute name travel arbitrarily far as a plausible
    value before anything noticed
    (bug-nilpy-missing-attribute-yields-none-instead-of-attributeerror). }
  if pydynattr_has(obj, name) then
    Result := PyDynAttrStore.fetch(PyDynAttrKey(obj, name))
  else if obj = nil then
    raise AttributeError.Create('''NoneType'' object has no attribute ''' + name + '''')
  else
    raise AttributeError.Create('''' + TObject(obj).ClassName +
      ''' object has no attribute ''' + name + '''');
end;

function PyVarTypeName(t: Int64): AnsiString; forward;

function pydynattr_get_v(const v: Variant; const name: AnsiString): Variant;
var obj: Pointer; tg: Int64; cn: AnsiString;
begin
  { Reached with a receiver that is a VARIANT — a for-loop element, `d.get(k)`,
    a plain unannotated parameter — whose runtime tag is NOT known at compile
    time. Unlike pydynattr_get above, `pyvarobj(v)`'s raw payload is only a
    real object pointer when the tag says so (VT_OBJECT); for any other tag
    (str/int/float/bool) it is scalar bits reinterpreted as an address, and
    ClassName on that would dereference garbage. Check the tag first. }
  obj := pyvarobj(v);
  if pydynattr_has(obj, name) then
  begin
    Result := PyDynAttrStore.fetch(PyDynAttrKey(obj, name));
    Exit;
  end;
  tg := pyvartag(v);
  if tg = 7 then
  begin
    if obj = nil then cn := 'NoneType' else cn := TObject(obj).ClassName;
  end
  else
    cn := PyVarTypeName(tg);
  raise AttributeError.Create('''' + cn + ''' object has no attribute ''' + name + '''');
end;

{ `type(x).__name__` for ANY value. Two things the frontend cannot do itself:

  - the pylib CONTAINERS must report their PYTHON names, not the Pascal class
    backing them. Reading the RTTI ClassName gave `TPyList` / `TPyDict` /
    `TPyBytes` — a silently wrong string, the worst failure class here.
  - `list`, `tuple` and `set` share ONE representation, so the answer depends on
    FKind at run time and cannot come from a class name at all.

  A user NilPy class still falls through to ClassName, which is already its
  Python name (bug-nilpy-type-name-reports-the-internal-pascal-class). }
function pytype_name_v(const v: Variant): AnsiString;
var obj: Pointer; tg: Int64; o: TObject;
begin
  tg := pyvartag(v);
  if tg <> 7 then
  begin
    Result := PyVarTypeName(tg);
    Exit;
  end;
  obj := pyvarobj(v);
  if obj = nil then begin Result := 'NoneType'; Exit; end;
  o := TObject(obj);
  if o is TPyList then
  begin
    Result := PySeqKindName(TPyList(o).FKind);
  end
  else if o is TPyDict then Result := 'dict'
  else if o is TPyBytes then Result := 'bytes'
  else
    { spelled `TObject(obj).ClassName`, exactly as the two AttributeError sites
      above do. Written as `o.ClassName` on an already-TObject local it compiled
      into a DYNAMIC ATTRIBUTE fetch instead of the RTTI call, and a user class
      then died with "'Dog' object has no attribute 'ClassName'". }
    Result := TObject(obj).ClassName;
end;

function pyvar_is_strtag(const v: Variant): Boolean;
begin
  Result := pyvartag(v) in [5, 6];
end;

{ True iff v's payload is a real object pointer (VT_OBJECT, tag 7) -- the only
  tag pyvarobj's raw payload may safely be dereferenced/cast for. Any other
  tag (None/int/float/str/bool) is scalar bits or a null placeholder
  reinterpreted as an address; a hard class-cast on it derefs garbage.
  bug-nilpy-container-literal-default-arg-segfaults: a class-typed method call
  on a VARIANT receiver (`b.append(a)` where `b`'s declared default `= []`
  never evaluates and falls through as None) cast that receiver unconditionally
  -- pydynattr_get_v/pyvar_getitem already guard the same way for attribute
  reads and subscripting; the method-dispatch cast in pyparser.inc did not. }
function pyvar_is_objtag(const v: Variant): Boolean;
begin
  Result := pyvartag(v) = 7;
end;

{ ALWAYS raises. `None.upper()` (or any str method on a non-str variant) used
  to render the receiver through pystr_of first — a None/int/float/bool
  receiver stringifies to plausible-looking TEXT ('None', '5', ...) and the
  method then ran on THAT, so `None.upper()` answered 'NONE' instead of
  raising (bug-nilpy-missing-attribute-yields-none-instead-of-attributeerror).
  The call site guards with pyvar_is_strtag first and only reaches this on a
  genuine non-str receiver. }
procedure pydynattr_no_method(const v: Variant; const mname: AnsiString);
var obj: Pointer; tg: Int64; cn: AnsiString;
begin
  tg := pyvartag(v);
  if tg = 7 then
  begin
    obj := pyvarobj(v);
    if obj = nil then cn := 'NoneType' else cn := TObject(obj).ClassName;
  end
  else
    cn := PyVarTypeName(tg);
  raise AttributeError.Create('''' + cn + ''' object has no attribute ''' + mname + '''');
end;

function pyvar_getitem(const v: Variant; const key: Variant): Variant;
var o: TObject; ki: Int64; tg: Int64;
begin
  { CHECK THE TAG BEFORE CASTING. This cast to TObject was unconditional, so a
    variant holding a STRING had its character data dereferenced as an object
    and the `is TPyDict` test read a VMT pointer out of string bytes ->
    SIGSEGV. Reached by three of the commonest shapes in Python:
      def f(s): return s[0]      (an unannotated str parameter)
      for w in words: w[0]       (a for-loop variable is a variant)
      xs[0][0]                   (a string that came out of a container)
    pyvar_slice, ten lines below, has always tested `pyvartag(v) = 6` first --
    the same predicate written in two places, and only one of them grew the
    string case (bug-nilpy-indexing-an-unannotated-str-parameter-segfaults). }
  tg := pyvartag(v);
  if (tg = 6) or (tg = 5) then
  begin
    ki := PPyVarRec(@key)^.Payload;
    { pystr_at applies Python's negative-index rule and raises IndexError out
      of range, so this arm inherits both }
    Result := pystr_ofchar(pystr_at(pystr_of(v), ki));
    Exit;
  end;
  if tg <> 7 then
    raise TypeError.Create('object is not subscriptable');
  o := TObject(pyvarobj(v));
  if o is TPyDict then
    Result := TPyDict(o).fetch(key)
  else if o is TPyList then
  begin
    ki := PPyVarRec(@key)^.Payload;      { list index is an integer key }
    Result := TPyList(o).at(ki);
  end
  else if o is TPyBytes then
  begin
    { bytes/bytearray index -> the integer byte value. Missing this case made
      `b[i]` on a VARIANT holding bytes (e.g. after `x = None; x = readline()`)
      raise 'not subscriptable' even though len(x) worked. }
    ki := PPyVarRec(@key)^.Payload;
    if ki < 0 then ki := ki + TPyBytes(o).count;
    Result := pyvar_of_int(TPyBytes(o).at(ki));
  end
  else
    raise TypeError.Create('object is not subscriptable');
end;

function pyvar_slice(const v: Variant; lo, hi: Integer): Variant;
var o: TObject;
begin
  if pyvartag(v) = 6 then
    Result := pystr_slice(pystr_of(v), lo, hi)     { str -> boxes to VT_STRING }
  else if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then Result := pylist_slice(TPyList(o), lo, hi)
    else if o is TPyBytes then Result := pybytes_slice(TPyBytes(o), lo, hi)
    else
      raise TypeError.Create('object is not subscriptable');
  end
  else
    raise TypeError.Create('object is not subscriptable');
end;

function pyvar_slice_step(const v: Variant; lo, hi, step: Integer): Variant;
var o: TObject;
begin
  if pyvartag(v) = 6 then
    Result := pystr_slice_step(pystr_of(v), lo, hi, step)   { str -> VT_STRING }
  else if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then Result := pylist_slice_step(TPyList(o), lo, hi, step)
    else if o is TPyBytes then Result := pybytes_slice_step(TPyBytes(o), lo, hi, step)
    else
      raise TypeError.Create('object is not subscriptable');
  end
  else
    raise TypeError.Create('object is not subscriptable');
end;

procedure pyvar_setitem(const v: Variant; const key: Variant; const val: Variant);
var o: TObject; ki: Int64;
begin
  o := TObject(pyvarobj(v));
  if o is TPyDict then
    TPyDict(o).store(key, val)
  else if o is TPyList then
  begin
    ki := PPyVarRec(@key)^.Payload;
    TPyList(o).put(ki, val);
  end
  else
  begin
    raise TypeError.Create('object does not support item assignment');
  end;
end;

constructor TPyCounter.Create(start: Int64);
begin
  FNext := start;
end;

function TPyCounter.nextval: Int64;
begin
  Result := FNext;
  FNext := FNext + 1;
end;

constructor TPyStat.Create;
begin
  st_mode := 0;
  st_size := 0;
end;


function next(c: TPyCounter): Int64;
begin
  Result := c.nextval;
end;

procedure PyIndexError;
{ RAISE, do not halt. The exception classes are declared at the top of this
  unit and a NilPy `raise IndexError(...)` is already caught correctly, but the
  runtime's own error paths wrote a line and called Halt — so NOTHING the
  runtime raised was catchable, not even by a bare `except:`, and ordinary
  defensive Python (`try: v = xs[i] except IndexError:`) could not be written
  at all (bug-nilpy-runtime-raised-errors-bypass-try-except). Uncaught, this
  still ends the process with the same exit code and a message naming the same
  class, via the unhandled-exception handler. }
begin
  raise IndexError.Create('list index out of range');
end;

constructor TPyList.Create;
begin
  { first construction installs the recursive finalizer (slice 3) }
  PXXObjFinalizeHook := @PyObjFinalize;
  FLen := 0;
  FCap := 0;
  FItems := nil;
end;

function TPyList.index(const v: Variant): Integer;
var i: Integer;
begin
  for i := 0 to FLen - 1 do
    if PyVarEq(PPyVarRec(NativeInt(FItems) + i * 16), PPyVarRec(@v)) then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
  { CPython's exact wording is `<value> is not in list` — the VALUE, not a
    placeholder, and it differs from list.remove's message. }
  raise ValueError.Create(pyrepr_of(v) + ' is not in list');
end;

function TPyList.remove(const v: Variant): Variant;
var i: Integer;
begin
  Result := pynone;   { Python's in-place mutators return None }
  for i := 0 to FLen - 1 do
    if PyVarEq(PPyVarRec(NativeInt(FItems) + i * 16), PPyVarRec(@v)) then
    begin
      pop_at(i);
      Exit;
    end;
  raise ValueError.Create('list.remove(x): x not in list');
end;

function TPyList.copy: TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  Result.FKind := FKind;
  for i := 0 to FLen - 1 do
    Result.append(at(i));
end;

function TPyList.count(const v: Variant): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to FLen - 1 do
    if PyVarEq(PPyVarRec(NativeInt(FItems) + i * 16), PPyVarRec(@v)) then Inc(Result);
end;

function TPyList.count: Integer;
begin
  Result := FLen;
end;

{ len() on a str. Same name as the list one — plain overloading inside a single
  unit, so argument type picks it; the used-unit shadowing hazard in
  project_builtin_overload_shadows_used_unit does not apply here. }
function len(const s: AnsiString): Integer; overload;
begin
  Result := Length(s);
end;

function len(l: TPyList): Integer;
begin
  Result := l.FLen;
end;

{ Translate a possibly-negative Python index; halt when out of range. }
function PyListFix(l: TPyList; i: Integer): Integer;
begin
  if i < 0 then i := i + l.FLen;
  if (i < 0) or (i >= l.FLen) then PyIndexError;
  Result := i;
end;

{ ---- ARC-correct variant-slot copies -------------------------------------
  A container slot is 16 raw bytes {VType, Payload}, and for VT_STRING (6) the
  payload IS a managed AnsiString reference. Copying the two fields directly
  therefore stored a BORROWED pointer: the caller's boxing temp released the
  string at scope exit and the slot was left dangling, so the next allocation
  reused the buffer and every same-length key/element read back as the LAST
  one stored. Silent, and the reason "assign to a local first" never helped
  (bug-a-str-boxed-into-variant-does-not-own-bytes).

  Use these for anything that makes a slot an OWNER. A pure MOVE within one
  array (the grow migrations and the insert/remove shift loops) keeps the raw
  field copy on purpose: ownership transfers, so retain/release would be
  wasted work and, for the shifts, wrong. }

{ Tags whose payload is a MANAGED AnsiString ref and must be refcounted through
  a slot copy: VT_STRING (6) and VT_PROMO_INT64 (8193, a heap-tier promotable
  int whose payload is its exact decimal). Missing the promo tag moved the raw
  pointer with no retain — the payload was freed while the slot still pointed
  at it, and the recycled bytes surfaced as another string entirely
  (the container-slot landmine). }
function PyVarSlotManaged(t: Int64): Boolean;
begin
  PyVarSlotManaged := (t = 6) or (t = 8193);
end;

{ Tags whose payload is a refcounted OBJECT block: VT_OBJECT (7, a class
  instance) and VT_BOUNDMETHOD (8, a {code,recv} pair). Retain/release ride
  PXXObjRetain/Release, which no-op unless the payload carries the
  PXX_OBJ_MAGIC header tag — so a Pascal-created (manual-lifetime) instance
  passing through a slot is left alone, and only PXXObjAlloc-headered blocks
  participate (feature-nilpy-object-reclamation slice 2). }
function PyVarSlotIsObj(t: Int64): Boolean;
begin
  { 9 = pyeval closure, 10 = lifted bound-fn — both RAW2 blocks. 10 is here so a
    closure stored IN a container is reclaimed with the container; the variant
    clear/retain emitters cover the same tag for a plain slot. }
  PyVarSlotIsObj := (t = 7) or (t = 8) or (t = 9) or (t = 10);
end;

function pyvarobj_owned(const v: Variant): Pointer;
begin
  Result := Pointer(PPyVarRec(@v)^.Payload);
  if PyVarSlotIsObj(PPyVarRec(@v)^.VType) then PXXObjRetain(Result);
end;

procedure PyVarSlotClear(dst: PPyVarRec);
begin
  if PyVarSlotManaged(dst^.VType) then PPyAnsiString(@dst^.Payload)^ := ''
  else if PyVarSlotIsObj(dst^.VType) then PXXObjRelease(Pointer(NativeInt(dst^.Payload)));
  dst^.VType := 0;
  dst^.Payload := 0;
end;

procedure PyVarSlotSet(dst: PPyVarRec; src: PPyVarRec);
{ dst must already be a valid (owned or cleared) slot. Retains BEFORE it
  releases, so slot := itself and aliasing slots are safe. }
var
  s: AnsiString;
begin
  if dst = src then Exit;
  s := '';
  if PyVarSlotManaged(src^.VType) then s := PPyAnsiString(@src^.Payload)^
  else if PyVarSlotIsObj(src^.VType) then PXXObjRetain(Pointer(NativeInt(src^.Payload)));
  PyVarSlotClear(dst);
  dst^.VType := src^.VType;
  if PyVarSlotManaged(src^.VType) then
    PPyAnsiString(@dst^.Payload)^ := s
  else
    dst^.Payload := src^.Payload;
end;

procedure PyVarSlotInit(dst: PPyVarRec; src: PPyVarRec);
{ dst is fresh/uninitialised (a function Result, a loop temp on its first
  pass): zero it first so the release half never frees garbage. }
begin
  dst^.VType := 0;
  dst^.Payload := 0;
  PyVarSlotSet(dst, src);
end;

procedure PyListGrow(l: TPyList; need: Integer);
var
  newCap, k: Integer;
  newItems: Pointer;
  src, dst: PPyVarRec;
begin
  if need <= l.FCap then Exit;
  newCap := l.FCap * 2;
  if newCap < 8 then newCap := 8;
  if newCap < need then newCap := need;
  GetMem(newItems, newCap * 16);
  for k := 0 to l.FLen - 1 do
  begin
    src := PPyVarRec(NativeInt(l.FItems) + k * 16);
    dst := PPyVarRec(NativeInt(newItems) + k * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  { the old block is unreachable the moment FItems moves — nothing else ever
    holds it, so it is freed here rather than leaked on every growth }
  { slots past FLen are fresh GetMem garbage; zero them so the ARC release in
    PyVarSlotSet never frees a wild pointer }
  for k := l.FLen to newCap - 1 do
  begin
    dst := PPyVarRec(NativeInt(newItems) + k * 16);
    dst^.VType := 0;
    dst^.Payload := 0;
  end;
  if l.FItems <> nil then FreeMem(l.FItems);
  l.FItems := newItems;
  l.FCap := newCap;
end;

function TPyList.append_self(const v: Variant): TPyList;
var
  src, dst: PPyVarRec;
begin
  PyListGrow(Self, FLen + 1);
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FItems) + FLen * 16);
  PyVarSlotSet(dst, src);
  FLen := FLen + 1;
  Result := Self;
end;

function TPyList.append(const v: Variant): Variant;
begin
  Self.append_self(v);
  Result := pynone;
end;

function TPyList.extend(other: TPyList): Variant;
var
  i, n: Integer;
  src, dst: PPyVarRec;
begin
  Result := pynone;   { Python returns None }
  if other = nil then Exit;
  { snapshot the source length FIRST: xs.extend(xs) must copy the ORIGINAL
    elements and terminate, not chase its own growth }
  n := other.FLen;
  for i := 0 to n - 1 do
  begin
    PyListGrow(Self, FLen + 1);
    src := PPyVarRec(NativeInt(other.FItems) + i * 16);
    dst := PPyVarRec(NativeInt(FItems) + FLen * 16);
    PyVarSlotSet(dst, src);
    FLen := FLen + 1;
  end;
end;

function TPyList.add(const v: Variant): TPyList;
begin
  if not pycontains(Self, v) then append(v);
  Result := Self;
end;

function TPyList.at(i: Integer): Variant;
var
  src, dst: PPyVarRec;
begin
  i := PyListFix(Self, i);
  src := PPyVarRec(NativeInt(FItems) + i * 16);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
end;

procedure TPyList.put(i: Integer; const v: Variant);
var
  src, dst: PPyVarRec;
begin
  i := PyListFix(Self, i);
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FItems) + i * 16);
  PyVarSlotSet(dst, src);
end;

function TPyList.pop: Variant;
begin
  Result := at(FLen - 1);
  FLen := FLen - 1;
end;

function TPyList.pop(i: Integer): Variant;
begin
  Result := pop_at(i);
end;

function TPyList.pop_at(i: Integer): Variant;
var
  k: Integer;
  src, dst: PPyVarRec;
begin
  i := PyListFix(Self, i);
  Result := at(i);
  for k := i to FLen - 2 do
  begin
    src := PPyVarRec(NativeInt(FItems) + (k + 1) * 16);
    dst := PPyVarRec(NativeInt(FItems) + k * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  FLen := FLen - 1;
end;

function TPyList.insert(i: Integer; const v: Variant): Variant;
var
  k: Integer;
  src, dst: PPyVarRec;
begin
  Result := pynone;   { Python's in-place mutators return None }
  { Python allows insert at len (append position) and clamps beyond. }
  if i < 0 then i := i + FLen;
  if i < 0 then i := 0;
  if i > FLen then i := FLen;
  PyListGrow(Self, FLen + 1);
  for k := FLen - 1 downto i do
  begin
    src := PPyVarRec(NativeInt(FItems) + k * 16);
    dst := PPyVarRec(NativeInt(FItems) + (k + 1) * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FItems) + i * 16);
  { the shift loop above left a DUPLICATE of the old slot i one place up, so
    this slot is a borrowed alias, not an owner -- init rather than set, or the
    release would kill the string the shifted copy now owns }
  PyVarSlotInit(dst, src);
  FLen := FLen + 1;
end;

procedure TPyList.clear;
begin
  FLen := 0;
end;

{ Python's list.reverse() — IN PLACE. `reversed(xs)` and `xs[::-1]` both build a
  NEW sequence and already existed; the in-place method did not, so `xs.reverse()`
  failed to compile: "TPyList has no method reverse"
  (bug-nilpy-list-reverse-method-missing). Swaps ends inward rather than building
  a copy, which is what "in place" is for. }
function TPyList.reverse: Variant;
var i, j: Integer; tmp: Variant;
begin
  i := 0;
  j := FLen - 1;
  while i < j do
  begin
    tmp := at(i);
    put(i, at(j));
    put(j, tmp);
    Inc(i);
    Dec(j);
  end;
  Result := pynone;   { Python returns None }
end;

{ Python's list.sort(reverse=) — IN PLACE, unlike sorted() (pyeval.pas), which
  returns a new list. `key=` is still absent: it needs PyCallKey1's
  generic-callable dispatch, which lives in pyeval.pas and cannot be called
  from here (pyeval `uses pylib`, not the reverse) — refused rather than
  guessed at. `reverse=` has no such constraint: it needs no callable, only the
  opposite `pyvar_gt` content-order comparison this unit already has (see
  max()/min() above). bug-nilpy-list-sort-method-missing,
  bug-nilpy-list-sort-rejects-key-and-reverse-with-a-bare-parse-error.

  Declaring the parameter is the whole frontend fix. The method call path in
  parser.inc drives its argument loop off ParamCount (`while mai <=
  ParamCount-1`), so with sort() taking nothing the loop body never ran, the
  keyword recognizer inside it never saw `reverse`, and control fell to
  Expect(tkRParen) — which is why a missing FEATURE surfaced as a bare
  "unexpected token" pointing at the keyword name.

  reverse=True is NOT "sort then reverse": Python keeps the sort stable either
  way, so equal elements must retain input order in both directions. Flipping
  which operand `pyvar_gt` gets keeps the comparison STRICT, so equal elements
  still do not swap and stability is preserved. }
function TPyList.sort(reverse: Boolean): Variant;
var i, j: Integer; v: Variant; swapped: Boolean;
begin
  for i := 1 to Self.count - 1 do
  begin
    j := i;
    swapped := True;
    while (j > 0) and swapped do
    begin
      if reverse then
        swapped := pyvar_gt(Self.at(j), Self.at(j - 1))
      else
        swapped := pyvar_gt(Self.at(j - 1), Self.at(j));
      if swapped then
      begin
        v := Self.at(j);
        Self.put(j, Self.at(j - 1));
        Self.put(j - 1, v);
        Dec(j);
      end;
    end;
  end;
  Result := pynone;   { Python returns None }
end;

function TPyList.read: AnsiString;
begin
  read := pyfile_read(Self);
end;

procedure TPyList.close;
begin
  { no-op: nothing held open under the read-slurp model }
end;

function TPyList.readlines: TPyList;
begin
  readlines := Self;
end;

function TPyList.issubset(other: TPyList): Boolean;
var i: Integer;
begin
  Result := True;
  if Self = nil then Exit;
  for i := 0 to Self.count - 1 do
    if not pycontains(other, Self.at(i)) then begin Result := False; Exit; end;
end;

function TPyList.issuperset(other: TPyList): Boolean;
begin
  if other = nil then begin Result := True; Exit; end;
  Result := other.issubset(Self);
end;

function TPyList.union(other: TPyList): TPyList;
begin
  Result := pyset_or(Self, other);
end;

function TPyList.intersection(other: TPyList): TPyList;
begin
  Result := pyset_and(Self, other);
end;

function TPyList.difference(other: TPyList): TPyList;
begin
  Result := pyset_sub(Self, other);
end;

procedure TPyList.discard(const v: Variant);
begin
  if Self = nil then Exit;
  if pycontains(Self, v) then Self.remove(v);
end;

{ Python `in` over a list/set-as-list. Same-tag equality only: ints/bools/
  chars by payload, floats by bits, strings by CONTENT (payload is the char
  pointer, length at ptr-8). Cross-tag numeric equality (1 == 1.0) is not
  modelled — the censused corpus uses string membership. }
{ Variant equality, shared by list membership and dict key lookup. Strings
  compare by CONTENT — a dict keyed by str is keyed by the TEXT, not by which
  copy of it you happen to be holding — and everything else compares tag and
  payload. }
function PyVarEq(p, q: PPyVarRec): Boolean;
var
  k: Integer;
  la, lb: Int64;
  a, b: PChar;
  pl, ql: TObject;
begin
  Result := False;
  { The int-family tags (VT_INT/VT_INT64/VT_BOOL) are ONE Python number and
    must compare CROSS-TAG: a masked cell comes back VT_INT64 while a
    define-time key is VT_INT, and the old tag-sensitive compare made
    xt_table.get(xt) miss its own key (uforth EXECUTE). Python agrees:
    True == 1 == 1 regardless of provenance. }
  if ((p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4)) and
     ((q^.VType = 1) or (q^.VType = 2) or (q^.VType = 4)) then
  begin
    Result := p^.Payload = q^.Payload;
    Exit;
  end;
  { A FLOAT and an int are ONE Python number too: `1 == 1.0` is True, and so
    `d[1]` and `d[1.0]` are the SAME dict key. The `==` OPERATOR already agreed
    with CPython here; only this path did not, so `1.0 in {1: 'a'}` was False and
    `{2.0: 'x'}.get(2)` missed — a silently wrong answer from an equality the
    language reports as true elsewhere
    (bug-nilpy-int-and-float-dict-keys-are-not-the-same-key).
    Float-vs-float is compared as a VALUE rather than by payload bits, so
    -0.0 == 0.0 (bit-different) and nan <> nan (bit-identical) both come out
    Python's way. }
  if ((p^.VType = 3) or (q^.VType = 3)) and
     ((p^.VType = 3) or (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4)) and
     ((q^.VType = 3) or (q^.VType = 1) or (q^.VType = 2) or (q^.VType = 4)) then
  begin
    { IDENTICAL BITS settle it first, before the numeric compare. CPython's dict
      tests `key is entry_key or key == entry_key`, and that identity half is
      what lets a NaN key find ITSELF (`q[n]` where q = {n: ...}) even though
      `n == n` is False. Comparing numerically alone turned that lookup into a
      KeyError — caught before this shipped, but only because the edge was
      probed; it is the exact case the value-compare below is meant to fix for
      -0.0 and would have broken for NaN. }
    if (p^.VType = 3) and (q^.VType = 3) and (p^.Payload = q^.Payload) then
    begin
      Result := True;
      Exit;
    end;
    Result := PyVarAsFloat(p) = PyVarAsFloat(q);
    Exit;
  end;
  if p^.VType <> q^.VType then Exit;
  if p^.VType = 7 then
  begin
    { Two OBJECTS. Identity settles it first (and covers every class this unit
      does not compare by value). A tuple lowers to a TPyList, so
      `("Options", "Debug") in BOOLEAN_SETTINGS` compares two DISTINCT list
      objects and identity alone answered False where Python says True —
      Python compares sequences ELEMENT BY ELEMENT. }
    Result := p^.Payload = q^.Payload;
    if Result then Exit;
    if (p^.Payload = 0) or (q^.Payload = 0) then Exit;
    pl := TObject(Pointer(NativeInt(p^.Payload)));
    ql := TObject(Pointer(NativeInt(q^.Payload)));
    if (pl is TPyList) and (ql is TPyList) then
    begin
      la := TPyList(pl).FLen;
      lb := TPyList(ql).FLen;
      if la <> lb then Exit;
      for k := 0 to Integer(la) - 1 do
        if not PyVarEq(PPyVarRec(NativeInt(TPyList(pl).FItems) + k * 16),
                       PPyVarRec(NativeInt(TPyList(ql).FItems) + k * 16)) then Exit;
      Result := True;
    end
    else if (pl is TPyDict) and (ql is TPyDict) then
      { …and two DICTS by contents, for the same reason. This is what makes a
        NESTED dict compare correctly: the outer pydict_eq reaches its values
        through PyVarEq, so without this arm `{"n": {"m": 1}} == {"n": {"m": 1}}`
        was False while the list-valued `{"n": [1, 2]}` form was already True.
        Mutually recursive with pydict_eq, which is why that one is
        forward-declared. }
      Result := pydict_eq(TPyDict(pl), TPyDict(ql));
    Exit;
  end;
  if p^.VType = 8193 then
  begin
    { VT_PROMO_INT64: payload is the exact decimal in a managed string —
      compare CONTENT, not the two string refs }
    Result := PPyAnsiString(@p^.Payload)^ = PPyAnsiString(@q^.Payload)^;
    Exit;
  end;
  if p^.VType = 6 then
  begin
    a := PChar(p^.Payload);
    b := PChar(q^.Payload);
    if (a = nil) or (b = nil) then
    begin
      Result := a = b;
      Exit;
    end;
    la := PInt64(NativeInt(p^.Payload) - 8)^;
    lb := PInt64(NativeInt(q^.Payload) - 8)^;
    if la <> lb then Exit;
    for k := 0 to Integer(la) - 1 do
      if a[k] <> b[k] then Exit;
    Result := True;
  end
  else
    Result := p^.Payload = q^.Payload;
end;

{ Does this variant hold the given pylib container? k: 1=list, 2=dict,
  3=bytes. The runtime side of variant-method dual dispatch. }
function pyvar_holds(const v: Variant; k: Int64): Boolean;
var o: TObject;
begin
  pyvar_holds := False;
  if pyvartag(v) <> 7 then Exit;
  o := TObject(pyvarobj(v));
  if k = 1 then pyvar_holds := o is TPyList
  else if k = 2 then pyvar_holds := o is TPyDict
  else if k = 3 then pyvar_holds := o is TPyBytes;
end;

function pycontains(l: TPyList; const v: Variant): Boolean;
var
  i: Integer;
  q: PPyVarRec;
begin
  Result := False;
  q := PPyVarRec(@v);
  for i := 0 to l.FLen - 1 do
    if PyVarEq(PPyVarRec(NativeInt(l.FItems) + i * 16), q) then
    begin
      Result := True;
      Exit;
    end;
end;

function pybytes_contains(b: TPyBytes; const v: Variant): Boolean;
var o: TObject; k: Integer; p: PByte; want: Int64;
begin
  Result := False;
  if b = nil then Exit;
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyBytes then
    begin
      { an EMPTY needle is in every sequence, which pybytes_find must agree on }
      Result := pybytes_find(b, TPyBytes(o), 0) >= 0;
      Exit;
    end;
    Exit;
  end;
  { an INTEGER needle tests a single BYTE VALUE, not a subsequence — and one
    OUTSIDE 0..255 is a ValueError in CPython, not simply absent. Answering
    False there would be a plausible wrong answer for what is really a type
    error, so it raises. }
  want := pyvar_to_int(v);
  if (want < 0) or (want > 255) then
    raise ValueError.Create('byte must be in range(0, 256)');
  for k := 0 to b.FLen - 1 do
  begin
    p := PByte(NativeInt(b.FData) + k);
    if p^ = Byte(want) then begin Result := True; Exit; end;
  end;
end;

{ Python's set operators (`&`/`|`/`-`/`^`) -- NilPy has one sequence
  representation, so a "set" is a TPyList built through `.add()` (the
  duplicate-skipping insert). These four operators were entirely
  unhandled: `&`/`|`/`-`/`^` between two class-typed (tyClass) operands
  fell through every arm of the operator-typing chain in parser.inc and
  landed on the bare-integer default, so codegen did a raw bitwise/
  subtract op on the two operands' HEAP POINTERS -- silently producing a
  huge garbage integer (`&`/`|`) or a small, meaningless one (`-`/`^`,
  pointer difference), never an error. Lists don't support any of these
  four operators in Python, so a `TPyList & TPyList` (etc.) shape is
  unambiguously a set operation once dict is ruled out first — see
  pydict_or below for dict's own use of `|`.
  bug-nilpy-set-and-dict-operators-do-raw-pointer-arithmetic }
function pyset_and(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  if (a = nil) or (b = nil) then Exit;
  for i := 0 to a.count - 1 do
    if pycontains(b, a.at(i)) then Result.add(a.at(i));
end;

function pyset_or(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  if a <> nil then
    for i := 0 to a.count - 1 do Result.add(a.at(i));
  if b <> nil then
    for i := 0 to b.count - 1 do Result.add(b.at(i));
end;

function pyset_sub(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  if a = nil then Exit;
  for i := 0 to a.count - 1 do
    if (b = nil) or not pycontains(b, a.at(i)) then Result.add(a.at(i));
end;

function pyset_xor(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  if a <> nil then
    for i := 0 to a.count - 1 do
      if (b = nil) or not pycontains(b, a.at(i)) then Result.add(a.at(i));
  if b <> nil then
    for i := 0 to b.count - 1 do
      if (a = nil) or not pycontains(a, b.at(i)) then Result.add(b.at(i));
end;

{ Python's dict union operator, PEP 584: `d1 | d2` -- a NEW dict, `d1`'s
  entries first (in order), then `d2`'s (in order), with `d2` winning any
  key collision. Same "fell through to raw pointer arithmetic" bug as the
  set operators above; dict rules out set's own `|` since both are
  distinct tyClass identities, checked before the set arm in the caller. }
function pydict_or(a: TPyDict; b: TPyDict): TPyDict;
var i: Integer; keys: TPyList;
begin
  Result := TPyDict.Create;
  if a <> nil then
  begin
    keys := a.keylist;
    for i := 0 to keys.count - 1 do
      Result.store(keys.at(i), a.fetch(keys.at(i)));
  end;
  if b <> nil then
  begin
    keys := b.keylist;
    for i := 0 to keys.count - 1 do
      Result.store(keys.at(i), b.fetch(keys.at(i)));
  end;
end;

{ `v in container` where the container is a VARIANT (its type is only known at
  run time — e.g. `x in select(...)[0]`, a list held in a dict/list slot). Unbox
  and dispatch: object -> dict key / list element, str -> substring. }
function pyvar_contains(const c: Variant; const v: Variant): Boolean;
var o: TObject;
begin
  Result := False;
  if pyvartag(c) = 7 then
  begin
    o := TObject(pyvarobj(c));
    if o is TPyDict then Result := pydictcontains(TPyDict(o), v)
    else if o is TPyList then Result := pycontains(TPyList(o), v);
  end
  else if pyvartag(c) = 6 then
    Result := pystr_contains(pystr_of(c), pystr_of(v));
end;

procedure PyKeyError;
{ RAISE — see PyIndexError. }
begin
  raise KeyError.Create('key not found');
end;

constructor TPyDict.Create;
begin
  PXXObjFinalizeHook := @PyObjFinalize;
  FLen := 0;
  FCap := 0;
  FKeys := nil;
  FVals := nil;
  FHash := nil;
  FHashCap := 0;
end;

function TPyDict.count: Integer;
begin
  Result := FLen;
end;

function len(d: TPyDict): Integer; overload;
begin
  Result := d.FLen;
end;

procedure PyDictRehash(d: TPyDict; newHashCap: Integer); forward;

procedure PyDictGrow(d: TPyDict; need: Integer);
var
  newCap, k, hashCap: Integer;
  newKeys, newVals: Pointer;
  src, dst: PPyVarRec;
begin
  if need <= d.FCap then Exit;
  newCap := d.FCap * 2;
  if newCap < 8 then newCap := 8;
  if newCap < need then newCap := need;
  GetMem(newKeys, newCap * 16);
  GetMem(newVals, newCap * 16);
  for k := 0 to d.FLen - 1 do
  begin
    src := PPyVarRec(NativeInt(d.FKeys) + k * 16);
    dst := PPyVarRec(NativeInt(newKeys) + k * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
    src := PPyVarRec(NativeInt(d.FVals) + k * 16);
    dst := PPyVarRec(NativeInt(newVals) + k * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  for k := d.FLen to newCap - 1 do
  begin
    dst := PPyVarRec(NativeInt(newKeys) + k * 16);
    dst^.VType := 0; dst^.Payload := 0;
    dst := PPyVarRec(NativeInt(newVals) + k * 16);
    dst^.VType := 0; dst^.Payload := 0;
  end;
  if d.FKeys <> nil then FreeMem(d.FKeys);
  if d.FVals <> nil then FreeMem(d.FVals);
  d.FKeys := newKeys;
  d.FVals := newVals;
  d.FCap := newCap;
  { Rebuild the hash index at ~2x capacity (load factor <= 0.5), power of two so
    indexof's `and (FHashCap-1)` masks correctly. Reinserts the FLen live keys. }
  hashCap := 16;
  while hashCap < newCap * 2 do hashCap := hashCap * 2;
  PyDictRehash(d, hashCap);
end;

function PyStrBytesHash(a: PChar; n: Integer): NativeUInt;
{ FNV-1a over n bytes at a. }
var i: Integer; h: NativeUInt;
begin
  h := NativeUInt($cbf29ce484222325);   { FNV-1a 64-bit offset basis }
  if a <> nil then
    for i := 0 to n - 1 do
      h := (h xor NativeUInt(Byte(a[i]))) * NativeUInt($100000001b3);   { FNV prime }
  Result := h;
end;

function PyVarHashKey(p: PPyVarRec): NativeUInt;
{ Hash CONSISTENT WITH PyVarEq (equal keys MUST hash equal):
  - int-family VT_INT/VT_INT64/VT_BOOL (1/2/4): by payload, tag-independent
    (PyVarEq compares these cross-tag by value);
  - VT_PROMO_INT64 (8193) and VT_STRING (6): by string CONTENT;
  - VT_OBJECT (7) holding a TPyList: by ELEMENT CONTENT, recursively. A tuple
    lowers to a TPyList, so `d[(1, 2)]` hashed the list HANDLE while PyVarEq
    compares two distinct lists element by element — every tuple key stored fine
    and then missed on lookup with a KeyError
    (bug-nilpy-tuple-dict-key-never-matches). Any other object keeps the
    identity hash, which is what PyVarEq's identity compare needs;
  - else: same VType required by PyVarEq, so hash (VType, payload).
  A wrong hash here silently loses keys, so this mirrors PyVarEq arm-for-arm. }
var h: NativeUInt; sp: PPyAnsiString; ol: TObject; k: Integer; dv: Double;
begin
  if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) then
    h := NativeUInt(p^.Payload)
  else if p^.VType = 3 then
  begin
    { A float that is numerically an INTEGER must hash as that integer, because
      PyVarEq now says they are equal and equal keys MUST hash equal — the
      invariant this whole routine is written to hold. A non-integral float
      cannot equal any int, so its bits are a fine hash.
      (bug-nilpy-int-and-float-dict-keys-are-not-the-same-key) }
    dv := PPyDouble(@p^.Payload)^;
    if (dv = Trunc(dv)) and (dv >= -9.2e18) and (dv <= 9.2e18) then
      h := NativeUInt(Int64(Trunc(dv)))
    else
      h := NativeUInt(p^.Payload);
  end
  else if p^.VType = 8193 then
  begin
    sp := PPyAnsiString(@p^.Payload);
    h := PyStrBytesHash(PChar(sp^), Length(sp^));
  end
  else if p^.VType = 6 then
  begin
    if Pointer(p^.Payload) = nil then h := PyStrBytesHash(nil, 0)
    else h := PyStrBytesHash(PChar(p^.Payload),
                             Integer(PInt64(NativeInt(p^.Payload) - 8)^));
  end
  else if (p^.VType = 7) and (p^.Payload <> 0) and
          (TObject(Pointer(NativeInt(p^.Payload))) is TPyList) then
  begin
    { sequence hash over the elements, seeded by the length — the same shape
      CPython uses for tuples, and consistent with PyVarEq's element-wise
      compare. Recurses, so a nested tuple key hashes by its contents too. }
    ol := TObject(Pointer(NativeInt(p^.Payload)));
    h := NativeUInt(TPyList(ol).FLen) * NativeUInt($9E3779B97F4A7C15);
    for k := 0 to Integer(TPyList(ol).FLen) - 1 do
      h := (h xor PyVarHashKey(PPyVarRec(NativeInt(TPyList(ol).FItems) + k * 16)))
           * NativeUInt($100000001b3);
  end
  else
    h := (NativeUInt(p^.VType) * NativeUInt($100000001b3)) xor NativeUInt(p^.Payload);
  { murmur3 fmix64 avalanche so the low bits that FHashCap-1 masks are well mixed }
  h := h xor (h shr 33);
  h := h * NativeUInt($ff51afd7ed558ccd);
  h := h xor (h shr 33);
  h := h * NativeUInt($c4ceb9fe1a85ec53);
  h := h xor (h shr 33);
  Result := h;
end;

procedure PyDictHashPut(d: TPyDict; keyIdx: Integer);
{ Insert FKeys[keyIdx]'s slot index into the open-addressing table. Caller
  guarantees the key is not already present, so no PyVarEq dup check here. }
var mask, pos: NativeUInt; slotp: PInteger;
begin
          ' hashcap=', d.FHashCap, ' fkeys=', Int64(NativeInt(d.FKeys)), ' keyIdx=', keyIdx);
  mask := NativeUInt(d.FHashCap) - 1;
  pos := PyVarHashKey(PPyVarRec(NativeInt(d.FKeys) + keyIdx * 16)) and mask;
  while True do
  begin
    slotp := PInteger(NativeInt(d.FHash) + NativeInt(pos) * 4);
    if slotp^ < 0 then begin slotp^ := keyIdx; Exit; end;
    pos := (pos + 1) and mask;
  end;
end;

procedure PyDictRehash(d: TPyDict; newHashCap: Integer);
{ (Re)build the hash index at newHashCap (a power of two) from the current
  FKeys/FLen. Called after a grow or a remove-shift changes the layout. }
var i: Integer;
begin
  if d.FHash <> nil then FreeMem(d.FHash);
  d.FHashCap := newHashCap;
  GetMem(d.FHash, newHashCap * 4);
  for i := 0 to newHashCap - 1 do
    PInteger(NativeInt(d.FHash) + i * 4)^ := -1;
  for i := 0 to d.FLen - 1 do
    PyDictHashPut(d, i);
end;

function TPyDict.indexof(const k: Variant): Integer;
var
  i: Integer;
  q: PPyVarRec;
  mask, pos: NativeUInt;
  idx: Integer;
begin
  Result := -1;
  if FLen = 0 then Exit;
  q := PPyVarRec(@k);
  if FHashCap = 0 then
  begin
    { defensive linear fallback — store() always builds the index, so this only
      runs if a dict somehow held entries with no index }
    for i := 0 to FLen - 1 do
      if PyVarEq(PPyVarRec(NativeInt(FKeys) + i * 16), q) then
      begin Result := i; Exit; end;
    Exit;
  end;
  mask := NativeUInt(FHashCap) - 1;
  pos := PyVarHashKey(q) and mask;
  while True do
  begin
    idx := PInteger(NativeInt(FHash) + NativeInt(pos) * 4)^;
    if idx < 0 then Exit;   { empty slot -> key absent }
    if PyVarEq(PPyVarRec(NativeInt(FKeys) + idx * 16), q) then
    begin Result := idx; Exit; end;
    pos := (pos + 1) and mask;
  end;
end;

function TPyDict.fetch(const k: Variant): Variant;
var
  i: Integer;
  src, dst: PPyVarRec;
begin
  i := indexof(k);
  if i < 0 then
  begin
    { Counter mode: a key that was never stored reads as 0, which is the whole
      reason counting code uses a Counter (`c[k] += 1` with no seeding). }
    if FCounterMode then
    begin
      Result := 0;
      exit;
    end;
    PyKeyError;
  end;
  src := PPyVarRec(NativeInt(FVals) + i * 16);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
end;

function TPyDict.setdefault(const k: Variant; const d: Variant): Variant;
var
  i: Integer;
  src, dst: PPyVarRec;
begin
  i := indexof(k);
  if i < 0 then
  begin
    store(k, d);
    i := indexof(k);
  end;
  src := PPyVarRec(NativeInt(FVals) + i * 16);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
end;

procedure TPyDict.store(const k: Variant; const v: Variant);
var
  i: Integer;
  src, dst: PPyVarRec;
begin
          ' self=', Int64(NativeInt(Pointer(Self))), ' hashcap=', FHashCap);
  i := indexof(k);
  if i < 0 then
  begin
    PyDictGrow(Self, FLen + 1);   { rebuilds the hash index if it grew }
    i := FLen;
    src := PPyVarRec(@k);
    dst := PPyVarRec(NativeInt(FKeys) + i * 16);
            ' fhash=', Int64(NativeInt(FHash)), ' hashcap=', FHashCap,
            ' countermode=', Ord(FCounterMode));
    PyVarSlotSet(dst, src);
    { register the new key in the index (grow keeps load factor <= 0.5, so a
      slot is always free). FHashCap is 0 only for the never-grown empty dict,
      which cannot reach here — PyDictGrow(1) always allocates it. }
    PyDictHashPut(Self, i);
    FLen := FLen + 1;
  end;
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FVals) + i * 16);
  PyVarSlotSet(dst, src);
end;

function TPyDict.setitem(const k: Variant; const v: Variant): TPyDict;
begin
  store(k, v);
  Result := Self;
end;

{ .get(k) with no default. A MISSING key yields VT_EMPTY, which is the
  runtime's None — but None is not wired into the language yet
  (feature-nilpy-none-variant), so `x is None` on the result is not usable
  until that lands. Present keys are exact today. }
function TPyDict.get(const k: Variant): Variant; overload;
var
  i: Integer;
  src, dst: PPyVarRec;
begin
  i := indexof(k);
  dst := PPyVarRec(@Result);
  if i < 0 then
  begin
    dst^.VType := 0;
    dst^.Payload := 0;
    Exit;
  end;
  src := PPyVarRec(NativeInt(FVals) + i * 16);
  PyVarSlotInit(dst, src);
end;

function TPyDict.get(const k: Variant; const d: Variant): Variant; overload;
var
  i: Integer;
  src, dst: PPyVarRec;
begin
  i := indexof(k);
  dst := PPyVarRec(@Result);
  if i < 0 then
    src := PPyVarRec(@d)
  else
    src := PPyVarRec(NativeInt(FVals) + i * 16);
  PyVarSlotInit(dst, src);
end;

function TPyDict.remove(const k: Variant): Variant;
var
  i, j: Integer;
  src, dst: PPyVarRec;
begin
  Result := pynone;   { Python's in-place mutators return None }
  i := indexof(k);
  if i < 0 then PyKeyError;
  for j := i to FLen - 2 do
  begin
    src := PPyVarRec(NativeInt(FKeys) + (j + 1) * 16);
    dst := PPyVarRec(NativeInt(FKeys) + j * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
    src := PPyVarRec(NativeInt(FVals) + (j + 1) * 16);
    dst := PPyVarRec(NativeInt(FVals) + j * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  FLen := FLen - 1;
  { the tail shift renumbered every entry after the hole, so the stored slot
    indices are stale — rebuild the index from the new layout. }
  if FHashCap > 0 then PyDictRehash(Self, FHashCap);
end;

procedure TPyDict.clear;
begin
  { drop every entry; the storage arrays stay for reuse, which is what Python's
    dict.clear() does too }
  Self.FLen := 0;
  PyDictRehash(Self, Self.FHashCap);
end;

function TPyDict.copy: TPyDict;
var ks, vs: TPyList; i: Integer;
begin
  Result := TPyDict.Create;
  Result.FCounterMode := FCounterMode;
  ks := keylist;
  vs := vallist;
  for i := 0 to ks.count - 1 do Result.store(ks.at(i), vs.at(i));
end;

function TPyDict.popitem: TPyList;
var ks, vs: TPyList; n: Integer; k: Variant;
begin
  ks := keylist;
  if ks.count = 0 then
    raise KeyError.Create('popitem(): dictionary is empty');
  vs := vallist;
  n := ks.count - 1;                  { LIFO, matching CPython 3.7+ }
  k := ks.at(n);
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;            { popitem() yields a (key, value) TUPLE }
  Result.append(k);
  Result.append(vs.at(n));
  remove(k);
end;

function TPyDict.pop(const k: Variant): Variant;
var i: Integer; src, dst: PPyVarRec;
begin
  i := indexof(k);
  if i < 0 then PyKeyError;
  src := PPyVarRec(NativeInt(FVals) + i * 16);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
  remove(k);
end;

function TPyDict.pop(const k: Variant; const d: Variant): Variant;
var i: Integer; src, dst: PPyVarRec;
begin
  i := indexof(k);
  if i < 0 then
  begin
    dst := PPyVarRec(@Result);
    src := PPyVarRec(@d);
    PyVarSlotInit(dst, src);
    Exit;
  end;
  src := PPyVarRec(NativeInt(FVals) + i * 16);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
  remove(k);
end;

{ a > b for the aggregate builtins: numbers by value, strings by text, which is
  the pair Python orders and the corpus uses. A mixed number/string comparison
  is a TypeError in CPython and halts here rather than inventing an order. }
function pymap_int(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
    for i := 0 to l.count - 1 do
      { int("200") PARSES, as CPython's int() does — the elements of a
        `s.split(...)` are strings, which is the common source for map(int, …) }
      if pyvartag(l.at(i)) = 6 then r.append(pystr_to_int(pystr_of(l.at(i))))   { 6 = VT_STRING }
      else r.append(pyvar_to_int(l.at(i)));
  pymap_int := r;
end;

function pymap_str(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
    for i := 0 to l.count - 1 do r.append(pystr_of(l.at(i)));
  pymap_str := r;
end;

function pymap_float(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
    for i := 0 to l.count - 1 do
      { float("1.5") PARSES, as CPython's float() does }
      if pyvartag(l.at(i)) = 6 then r.append(pyfloat_parse(pystr_of(l.at(i))))
      else r.append(pyvar_to_float(l.at(i)));
  pymap_float := r;
end;

function pyvar_gt(const a: Variant; const b: Variant): Boolean;
var pa, pb: PPyVarRec;
    la, lb, k, n: Int64;
    ea, eb: Variant;
    oa, ob: TObject;
    pg: Integer;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  { Two SEQUENCES compare LEXICOGRAPHICALLY: the first index where the elements
    differ decides, and if one runs out first the shorter is smaller. Without
    this arm both fell through to pyvar_to_int and `sorted([("b", 2),
    ("a", 1)])` aborted with "expected a number, got object" — the standard
    sort-by-first-field idiom (bug-nilpy-sorted-over-tuples-or-lists-fails).
    Recursive, so a list OF pairs sorts by the pair, then within it. A tuple is
    the same TPyList here, so both spellings land in one rule. }
  if (pa^.VType = 7) and (pb^.VType = 7) and
     (pa^.Payload <> 0) and (pb^.Payload <> 0) then
  begin
    oa := TObject(Pointer(NativeInt(pa^.Payload)));
    ob := TObject(Pointer(NativeInt(pb^.Payload)));
    if (oa is TPyList) and (ob is TPyList) then
    begin
      la := TPyList(oa).FLen;
      lb := TPyList(ob).FLen;
      if la < lb then n := la else n := lb;
      for k := 0 to n - 1 do
      begin
        ea := TPyList(oa).at(k);
        eb := TPyList(ob).at(k);
        if not PyVarEq(PPyVarRec(@ea), PPyVarRec(@eb)) then
        begin
          pyvar_gt := pyvar_gt(ea, eb);
          Exit;
        end;
      end;
      pyvar_gt := la > lb;
      Exit;
    end;
  end;
  if ((pa^.VType = 6) or (pa^.VType = 5)) and ((pb^.VType = 6) or (pb^.VType = 5)) then
  begin
    pyvar_gt := PyVarText(pa) > PyVarText(pb);
    Exit;
  end;
  if ((pa^.VType = 6) or (pa^.VType = 5)) or ((pb^.VType = 6) or (pb^.VType = 5)) then
  begin
    raise TypeError.Create('comparison of a string with a number');
  end;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
    pyvar_gt := pyvar_to_float(a) > pyvar_to_float(b)
  else
  begin
    { arbitrary precision stays exact — see pycmp_v. This is the SORT path, so
      without it sorted([2**65, 2**64, 5]) came back in the order it was given:
      every element narrowed to the same wrapped value and no swap ever fired. }
    pg := PXXPromoVarCmpTry(@a, @b, 5);        { 5 = greater-than }
    if pg <> 0 then pyvar_gt := (pg = 2)
    else pyvar_gt := pyvar_to_int(a) > pyvar_to_int(b);
  end;
end;


function pymath_floor(x: Double): Int64;
begin
  Result := Trunc(x);
  if (Frac(x) <> 0.0) and (x < 0.0) then Dec(Result);
end;

function pymath_ceil(x: Double): Int64;
begin
  Result := Trunc(x);
  if (Frac(x) <> 0.0) and (x > 0.0) then Inc(Result);
end;

{ math.fabs — a plain float abs. No int/float contract mismatch like floor/
  ceil (Python's fabs always returns a float, same as Abs on a Double), so
  this exists only because `import math` otherwise has no `fabs` name to
  resolve to at all (feature-nilpy-stdlib-coverage-gaps-measured). }
function pymath_fabs(x: Double): Double;
begin
  Result := Abs(x);
end;

function pyenumerate(a: TPyList): TPyList;
var r, pair: TPyList; i: Integer; pv: Variant;
begin
  r := TPyList.Create;
  pyenumerate := r;
  if a = nil then Exit;
  for i := 0 to a.count - 1 do
  begin
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;   { enumerate() yields (index, value) tuples }
    pair.append(i);
    pair.append(a.at(i));
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    r.append(pv);
  end;
end;

{ `enumerate(xs, start)` / `enumerate(xs, start=N)` — same pairs as
  pyenumerate, indices offset by `start` instead of counting from 0. }
function pyenumerate2(a: TPyList; start: Integer): TPyList;
var r, pair: TPyList; i, idx: Integer; pv: Variant;
begin
  r := TPyList.Create;
  pyenumerate2 := r;
  if a = nil then Exit;
  for i := 0 to a.count - 1 do
  begin
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;
    idx := start + i;
    pair.append(idx);
    pair.append(a.at(i));
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    r.append(pv);
  end;
end;

{ A str is an ITERABLE in Python, so `enumerate("ab")` and `zip(s, t)` are
  ordinary code — but pyenumerate/pyzip take TPyList only, and the frontend
  builds those calls by a FIXED FindProc index, so adding Pascal overloads here
  would never be consulted. The str argument is converted at the CALL SITE
  instead (PyIterArgAsList); this is the conversion it uses. Passing the raw
  AnsiString handle got it dereferenced as an object: SIGSEGV, no diagnostic
  (bug-nilpy-str-iterable-builtins-segfault-on-a-string-handle). }
function pystr_charlist(const s: AnsiString): TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  for i := 1 to Length(s) do Result.append(pystr_ofchar(s[i]));
end;

procedure pyassert(ok: Boolean; const msg: AnsiString);
begin
  if ok then Exit;
  { CPython's bare `assert x` raises AssertionError with NO message, and
    `assert x, m` raises it with m — str(e) is '' in the first case, so an empty
    message must not become a placeholder string. }
  raise AssertionError.Create(msg);
end;

function pyzip(a: TPyList; b: TPyList): TPyList;
var r, pair: TPyList; i, n: Integer; pv: Variant;
begin
  r := TPyList.Create;
  pyzip := r;
  if (a = nil) or (b = nil) then Exit;
  n := a.count;
  if b.count < n then n := b.count;
  for i := 0 to n - 1 do
  begin
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;   { zip() yields tuples }
    pair.append(a.at(i));
    pair.append(b.at(i));
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    r.append(pv);
  end;
end;

function pynext_first(l: TPyList): Variant;
begin
  if (l = nil) or (l.count = 0) then
    raise StopIteration.Create('next() on an exhausted sequence');
  pynext_first := l.at(0);
end;

function pynext_first_or(l: TPyList; const dflt: Variant): Variant;
begin
  if (l = nil) or (l.count = 0) then pynext_first_or := dflt else pynext_first_or := l.at(0);
end;

function sum(l: TPyList): Variant;
var i: Integer;
begin
  Result := pyvar_of_int(0);
  if l = nil then Exit;
  for i := 0 to l.count - 1 do Result := pyadd_v(Result, l.at(i));
end;

function sum(l: TPyList; const start: Variant): Variant; overload;
var i: Integer;
begin
  Result := start;
  if l = nil then Exit;
  for i := 0 to l.count - 1 do Result := pyadd_v(Result, l.at(i));
end;

function min(const a, b, c: Variant): Variant; overload;
begin
  Result := min(min(a, b), c);
end;

function min(const a, b, c, d: Variant): Variant; overload;
begin
  Result := min(min(min(a, b), c), d);
end;

function max(const a, b, c: Variant): Variant; overload;
begin
  Result := max(max(a, b), c);
end;

function max(const a, b, c, d: Variant): Variant; overload;
begin
  Result := max(max(max(a, b), c), d);
end;

{ Python's min()/max() take ANY iterable, not just a list -- a str iterates
  its characters. Byte-ordinal comparison, consistent with this frontend's
  byte-string model everywhere else (bug-nilpy-non-ascii-string-surface-
  measured). feature-nilpy-min-max-over-a-string. }
function max(const s: AnsiString): AnsiString;
var i: Integer; best: Char;
begin
  if Length(s) = 0 then raise ValueError.Create('max() arg is an empty sequence');
  best := s[1];
  for i := 2 to Length(s) do
    if s[i] > best then best := s[i];
  Result := best;
end;

function min(const s: AnsiString): AnsiString;
var i: Integer; best: Char;
begin
  if Length(s) = 0 then raise ValueError.Create('min() arg is an empty sequence');
  best := s[1];
  for i := 2 to Length(s) do
    if s[i] < best then best := s[i];
  Result := best;
end;

function any(l: TPyList): Boolean;
var i: Integer;
begin
  Result := False;
  if l = nil then Exit;
  for i := 0 to l.count - 1 do
    if pyvar_to_bool(l.at(i)) then begin Result := True; Exit; end;
end;

function all(l: TPyList): Boolean;
var i: Integer;
begin
  Result := True;
  if l = nil then Exit;
  for i := 0 to l.count - 1 do
    if not pyvar_to_bool(l.at(i)) then begin Result := False; Exit; end;
end;

procedure pydict_merge(dst: TPyDict; src: TPyDict);
var kl, vl: TPyList; i: Integer;
begin
  if (dst = nil) or (src = nil) then Exit;
  kl := src.keylist;
  vl := src.vallist;
  for i := 0 to kl.count - 1 do dst.store(kl.at(i), vl.at(i));
end;

function pyset_of(const v: Variant): TPyList;
var r, kl: TPyList; o: TObject; i: Integer; sv: AnsiString;
begin
  r := TPyList.Create;
  { the CONSTRUCTOR stamps the kind too, not just the `{...}` display — without
    it `set([1,1,2])` printed `[1, 2]` and answered isinstance(x, list) }
  r.FKind := PYSEQ_SET;
  Result := r;
  if pyvartag(v) = 6 then
  begin
    sv := pystr_of(v);
    for i := 1 to Length(sv) do r.add(pystr_ofchar(sv[i]));
    Exit;
  end;
  if pyvartag(v) <> 7 then
  begin
    raise TypeError.Create('set() argument must be iterable');
  end;
  o := TObject(pyvarobj(v));
  if o is TPyList then
  begin
    for i := 0 to TPyList(o).count - 1 do r.add(TPyList(o).at(i));
    Exit;
  end;
  if o is TPyDict then
  begin
    kl := TPyDict(o).keylist;
    for i := 0 to kl.count - 1 do r.add(kl.at(i));
    Exit;
  end;
  raise TypeError.Create('set() argument must be iterable');
end;

function pydict_fromkeys(l: TPyList): TPyDict;
var d: TPyDict; i: Integer;
begin
  d := TPyDict.Create;
  if l <> nil then
    for i := 0 to l.count - 1 do
      d.store(l.at(i), pynone());
  Result := d;
end;

{ ---- collections.Counter ------------------------------------------------- }

function TPyDict.update(l: TPyList): Variant;
var i: Integer; k, pair: Variant; pl: TPyList; o: TObject;
begin
  Result := pynone;   { Python's in-place mutators return None }
  if l = nil then exit;
  for i := 0 to l.count - 1 do
  begin
    if FCounterMode then
    begin
      k := l.at(i);
      store(k, VariantToInt64(fetch(k)) + 1);
    end
    else
    begin
      { a plain dict updates from (key, value) pairs }
      pair := l.at(i);
      o := TObject(pyvarobj(pair));
      if o is TPyList then
      begin
        pl := TPyList(o);
        if pl.count >= 2 then store(pl.at(0), pl.at(1));
      end;
    end;
  end;
end;

{ CPython's Counter.update(mapping) ADDS the mapping's values; a plain dict's
  update(mapping) replaces them. }
function TPyDict.update(d: TPyDict): Variant;
var ks, vs: TPyList; i: Integer; k: Variant;
begin
  Result := pynone;   { Python's in-place mutators return None }
  if d = nil then exit;
  ks := d.keylist;
  vs := d.vallist;
  for i := 0 to ks.count - 1 do
  begin
    k := ks.at(i);
    if FCounterMode then
      store(k, VariantToInt64(fetch(k)) + VariantToInt64(vs.at(i)))
    else
      store(k, vs.at(i));
  end;
end;

{ Insertion sort over an index vector: a Counter here holds a handful of note or
  chord names, so the simple thing is the right thing. }
function TPyDict.most_common(n: Integer): TPyList;
var ks, vs, pair, res: TPyList;
    idx: array of Integer;
    i, j, t, cnt: Integer;
begin
  ks := keylist;
  vs := vallist;
  cnt := ks.count;
  SetLength(idx, cnt);
  for i := 0 to cnt - 1 do idx[i] := i;
  for i := 1 to cnt - 1 do
  begin
    j := i;
    while (j > 0) and
          (VariantToInt64(vs.at(idx[j])) > VariantToInt64(vs.at(idx[j - 1]))) do
    begin
      t := idx[j];
      idx[j] := idx[j - 1];
      idx[j - 1] := t;
      j := j - 1;
    end;
  end;
  res := TPyList.Create;
  if (n >= 0) and (n < cnt) then cnt := n;
  for i := 0 to cnt - 1 do
  begin
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;   { most_common() yields (key, count) tuples }
    pair.append(ks.at(idx[i]));
    pair.append(vs.at(idx[i]));
    res.append(pair);
  end;
  Result := res;
end;

function TPyDict.most_common: TPyList;
begin
  Result := most_common(-1);
end;

{ Counter() / Counter(iterable) as plain functions, so Python's constructor
  spelling resolves through the ordinary call path with no frontend mapping —
  the same trick lib/rtl/re.pas uses for `import re`. }
function Counter: TPyDict;
var c: TPyDict;
begin
  c := TPyDict.Create;
  c.FCounterMode := True;
  Result := c;
end;

function Counter(l: TPyList): TPyDict;
var c: TPyDict;
begin
  c := TPyDict.Create;
  c.FCounterMode := True;
  c.update(l);
  Result := c;
end;

function Counter(const s: AnsiString): TPyDict;
var c: TPyDict; i: Integer;
begin
  c := TPyDict.Create;
  c.FCounterMode := True;
  for i := 1 to Length(s) do
    c.store(s[i], VariantToInt64(c.fetch(s[i])) + 1);
  Result := c;
end;

function TPyDict.itemlist: TPyList;
var r, pair, kl, vl: TPyList; i: Integer; pv: Variant;
begin
  r := TPyList.Create;
  kl := keylist;
  vl := vallist;
  for i := 0 to kl.count - 1 do
  begin
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;   { dict.items() yields (key, value) tuples }
    pair.append(kl.at(i));
    pair.append(vl.at(i));
    { box the pair as a VT_OBJECT slot and retain it — the same shape a nested
      list literal gets when it is appended }
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    r.append(pv);
  end;
  itemlist := r;
end;

function TPyDict.keylist: TPyList;
var
  i: Integer;
  src, dst: PPyVarRec;
  tmp: Variant;
begin
  Result := TPyList.Create;
  for i := 0 to FLen - 1 do
  begin
    src := PPyVarRec(NativeInt(FKeys) + i * 16);
    dst := PPyVarRec(@tmp);
    PyVarSlotInit(dst, src);
    Result.append(tmp);
    PyVarSlotClear(dst);   { tmp is reused next pass -- drop this retain }
  end;
end;

function TPyDict.vallist: TPyList;
var
  i: Integer;
  src, dst: PPyVarRec;
  tmp: Variant;
begin
  Result := TPyList.Create;
  for i := 0 to FLen - 1 do
  begin
    src := PPyVarRec(NativeInt(FVals) + i * 16);
    dst := PPyVarRec(@tmp);
    PyVarSlotInit(dst, src);
    Result.append(tmp);
    PyVarSlotClear(dst);   { tmp is reused next pass -- drop this retain }
  end;
end;

function pylist_eq_v(a: TPyList; const v: Variant): Boolean;
begin
  { a list equals only another list; None, a number or a string never does }
  if pyvartag(v) <> 7 then pylist_eq_v := (a = nil) and (pyvartag(v) = 0)
  else pylist_eq_v := pylist_eq(a, TPyList(pyvarobj(v)));
end;

function pylist_eq(a: TPyList; b: TPyList): Boolean;
var
  i: Integer;
begin
  Result := False;
  if a = b then begin Result := True; Exit; end;
  if (a = nil) or (b = nil) then Exit;
  if a.FLen <> b.FLen then Exit;
  for i := 0 to a.FLen - 1 do
    if not PyVarEq(PPyVarRec(NativeInt(a.FItems) + i * 16),
                   PPyVarRec(NativeInt(b.FItems) + i * 16)) then Exit;
  Result := True;
end;

function pydictcontains(d: TPyDict; const k: Variant): Boolean;
begin
  Result := d.indexof(k) >= 0;
end;

function PyDictIndexOfPtr(d: TPyDict; q: PPyVarRec): Integer;
{ TPyDict.indexof by SLOT POINTER. The method itself takes `const k: Variant`
  and immediately takes its address, so calling it from a walk over another
  dict's key storage would mean copying each key into a local Variant purely to
  have its address taken again. Same open-addressing probe, same linear
  fallback for the never-indexed dict. }
var
  i: Integer;
  mask, pos: NativeUInt;
  idx: Integer;
begin
  Result := -1;
  if d.FLen = 0 then Exit;
  if d.FHashCap = 0 then
  begin
    for i := 0 to d.FLen - 1 do
      if PyVarEq(PPyVarRec(NativeInt(d.FKeys) + i * 16), q) then
      begin Result := i; Exit; end;
    Exit;
  end;
  mask := NativeUInt(d.FHashCap) - 1;
  pos := PyVarHashKey(q) and mask;
  while True do
  begin
    idx := PInteger(NativeInt(d.FHash) + NativeInt(pos) * 4)^;
    if idx < 0 then Exit;              { empty slot -> key absent }
    if PyVarEq(PPyVarRec(NativeInt(d.FKeys) + idx * 16), q) then
    begin Result := idx; Exit; end;
    pos := (pos + 1) and mask;
  end;
end;

function pydict_eq(a: TPyDict; b: TPyDict): Boolean;
{ See the declaration for why this is a per-key LOOKUP rather than a parallel
  walk: dict equality ignores insertion order. }
var
  i, j: Integer;
begin
  Result := False;
  if a = b then begin Result := True; Exit; end;
  if (a = nil) or (b = nil) then Exit;
  if a.FLen <> b.FLen then Exit;
  for i := 0 to a.FLen - 1 do
  begin
    j := PyDictIndexOfPtr(b, PPyVarRec(NativeInt(a.FKeys) + i * 16));
    if j < 0 then Exit;
    if not PyVarEq(PPyVarRec(NativeInt(a.FVals) + i * 16),
                   PPyVarRec(NativeInt(b.FVals) + j * 16)) then Exit;
  end;
  Result := True;
end;

function PyVarIsFloat(p: PPyVarRec): Boolean;
begin
  PyVarIsFloat := p^.VType = 3;
end;

{ UNCHECKED: a non-float tag's raw payload is read as an integer, so a str,
  list or dict HANDLE comes back as an address. Only safe where the tag is
  already known to be numeric. Every BINARY arithmetic and ordering arm now
  coerces with pyvar_to_float instead, which raises TypeError on a tag Python
  will not accept — the six of them each spelled this check inline, and one
  gaining a case the others lacked is exactly how
  bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math survived. The one
  remaining caller is unary negation, whose operand it has already tested. }
function PyVarAsFloat(p: PPyVarRec): Double;
begin
  if p^.VType = 3 then PyVarAsFloat := PPyDouble(@p^.Payload)^
  else PyVarAsFloat := p^.Payload;
end;

function PyVarTypeName(t: Int64): AnsiString;
begin
  if t = 0 then Result := 'NoneType'
  else if (t = 1) or (t = 2) then Result := 'int'
  else if t = 3 then Result := 'float'
  else if t = 4 then Result := 'bool'
  else if (t = 5) or (t = 6) then Result := 'str'
  else if t = 7 then Result := 'object'
  else Result := '<unknown>';
end;

{ RAISES, it does not halt. It used to writeln + Halt(219), which no
  `except TypeError:` could see — the one member of the diagnostic family
  nobody converted when pystr_to_int started raising ValueError
  (bug-nilpy-pytypeerror-halts-instead-of-raising). Every call site is an
  ordinary value-returning function (pyvar_to_int/_float/_char, pyord_v,
  pylen_v, pymul_v, len, pyabs_v, pydict_v, pylist_v), never a callback frame
  or an ARC finaliser, so unwinding out of one is safe. The message text is
  unchanged so an UNCAUGHT one still reads
  `TypeError: expected <want>, got <type>` — tests match on it. }
procedure PyTypeError(t: Int64; const want: AnsiString);
begin
  raise TypeError.Create('expected ' + want + ', got ' + PyVarTypeName(t));
end;

{ `x in obj` where obj's class defines no `__contains__` -- a genuine runtime
  TypeError (catchable), not a compile-time halt: the frontend's own Error()
  aborts the WHOLE COMPILATION, which made `try: ... in obj ... except:` fail
  to even build instead of running its handler, unlike CPython.
  bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic }
{ `xs[obj]` where obj's class declares no `__index__`. CPython's message names
  both the sequence KIND and the class — "list indices must be integers or
  slices, not N" — and the kind is what makes it useful. A runtime raise
  (catchable), like every other dunder-absent case here.

  Before this the instance HANDLE was used as the position, so it raised
  IndexError "list index out of range" — and only because the handle happened to
  be far past the end. A smaller handle would have silently indexed the WRONG
  element, which is the shape this dunder family keeps producing
  (bug-nilpy-missing-index-dunder-raises-indexerror-not-typeerror). }
function PyIndexTypeError(const seqKind: AnsiString;
                          const clsName: AnsiString): Int64;
begin
  raise TypeError.Create(seqKind + ' indices must be integers or slices, not '
                         + clsName);
  PyIndexTypeError := 0;   { unreachable; a FUNCTION so it can stand in for the
                             index expression itself at every subscript site }
end;

procedure PyNotContainerError;
begin
  raise TypeError.Create('argument is not a container (no __contains__)');
end;

{ `obj(...)` where obj's class defines no `__call__` -- a genuine runtime
  TypeError, matching CPython's "'X' object is not callable" (just without
  the class name, which is not available here). }
procedure PyNotCallableError;
begin
  raise TypeError.Create('object is not callable (no __call__)');
end;

{ `a < b` on two class instances where NEITHER the direct ordering dunder nor
  its reflected partner exists -- CPython raises rather than falling back to
  identity the way `==` does, so ordering has no silent answer. Matches
  CPython's "'<' not supported between instances of 'X' and 'Y'" shape (minus
  the class names, not available here).
  bug-nilpy-comparison-dunders-not-dispatched. }
procedure PyNotOrderableError;
begin
  raise TypeError.Create('comparison not supported between these instances (no __lt__/__le__/__gt__/__ge__)');
end;

{ `obj & 1` / `obj << 2` on a class declaring none of the bitwise/shift dunders.
  Before this existed the operands fell through to the generic bitwise typing,
  which widened tyClass to a variant and dereferenced the handle -- a SEGFAULT,
  not a wrong value. bug-nilpy-bitwise-shift-on-class-operand-segfaults. }
procedure PyNotBitOperandError;
begin
  raise TypeError.Create('unsupported operand type for a bitwise or shift operator (no __and__/__or__/__xor__/__lshift__/__rshift__)');
end;

{ An operand pair Python does not define for the operator -- a missing
  __add__/__sub__/__mul__/__truediv__/__floordiv__/__mod__/__neg__, or a list
  concatenated with a non-list. CPython raises TypeError at RUN time; these
  sites used the compiler's Error() instead, so a `try/except TypeError` around
  the expression could not even BUILD -- which is the normal Python way to probe
  for operator support.
  bug-nilpy-missing-arith-dunder-aborts-compile-instead-of-raising. }
procedure PyUnsupportedOperandError;
begin
  raise TypeError.Create('unsupported operand type(s) for this operator');
end;

{ `obj[i] = v` where obj's class defines `__getitem__` but not `__setitem__`
  -- CPython's own error shape ("does not support item assignment"). }
procedure PyNoSetitemError;
begin
  raise TypeError.Create('object does not support item assignment (no __setitem__)');
end;

function pyvar_to_int(const v: Variant): Int64;
var
  p: PPyVarRec;
  ds: AnsiString;
  i: Integer;
  r: Int64;
begin
  p := PPyVarRec(@v);
  if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) then
    Result := p^.Payload
  else if p^.VType = 8193 then
  begin
    { VT_PROMO_INT64: a heap-tier promotable int (payload = exact decimal in a
      managed string). Narrowing to a machine int is NilPy's documented mod-2^64
      two's-complement reading — the same rule the compiler's promo->int store
      uses (PXXPromoToInt64Wrap) — so the masked-cell idiom stays an identity
      instead of a TypeError. }
    ds := PPyAnsiString(@p^.Payload)^;
    r := 0;
    for i := 1 to Length(ds) do
      if ds[i] in ['0'..'9'] then
        r := r * 10 + (Ord(ds[i]) - 48);   { wrapping mod 2^64 is the point }
    if (ds <> '') and (ds[1] = '-') then r := -r;
    Result := r;
  end
  else if p^.VType = 3 then
    Result := Trunc(PPyDouble(@p^.Payload)^)   { Python int(float) truncates }
  else if p^.VType = 0 then
    { None -> 0, the sentinel NilPy's Optional[int] uses (PyAnnTypeAt maps
      Optional[X]'s None to 0/nil). Reached when an Optional[int] function
      returns a missing dict.get / an unset value: the variant is VT_EMPTY and
      the scalar-return coercion routes it here. Halting would break the whole
      Optional[int]-returns-None contract (uforth's _lookup_local_slot). }
    Result := 0
  else
  begin
    { str/object: Python will not silently produce a number here.
      int("42") is a DIFFERENT operation (pystr_to_int) and stays explicit. }
    PyTypeError(p^.VType, 'a number');
    Result := 0;
  end;
end;

function pyvar_to_float(const v: Variant): Double;
var
  p: PPyVarRec;
  pslot: array[0..1] of NativeInt;   { a promo slot, like PXXPromoVarArithTry's }
begin
  p := PPyVarRec(@v);
  if p^.VType = 3 then
    Result := PPyDouble(@p^.Payload)^
  else if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) then
    Result := p^.Payload
  else if p^.VType = 8193 then
  begin
    { VT_PROMO_INT64 is a NUMBER; it was missing here, so a heap-tier
      promotable int reaching a float context raised "expected a number, got
      <unknown>".
      Read off the LIMBS via PXXPromoToDouble, not through pyvar_to_int: that
      narrows mod 2^64, so `float(2**64)` answered 0.0 — silently, since 0.0 is
      a perfectly ordinary float. A heap-tier promo is by construction outside
      Int64, which is exactly when the narrowing is guaranteed to be wrong
      (bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum). }
    PXXPromoInit(@pslot);
    PXXPromoFromVariant(@pslot, @v);
    Result := PXXPromoToDouble(@pslot);
    PXXPromoClear(@pslot);
  end
  else
  begin
    PyTypeError(p^.VType, 'a number');
    Result := 0.0;
  end;
end;

function pyvar_to_bool(const v: Variant): Boolean;
var
  p: PPyVarRec;
  o: TObject;
begin
  { Python truthiness -- TOTAL, never an error: 0, 0.0, '', None, and an EMPTY
    container are false. }
  p := PPyVarRec(@v);
  if p^.VType = 3 then
    Result := PPyDouble(@p^.Payload)^ <> 0.0
  else if p^.VType = 6 then
    Result := PPyAnsiString(@p^.Payload)^ <> ''
  else if p^.VType = 0 then
    Result := False
  else if p^.VType = 7 then
  begin
    { A boxed container is falsy when empty (Python), so a variant produced by
      `x and <list>` / `x or <dict>` tests its length, not its handle — the
      handle is never nil, which made every boxed container truthy. A non-
      container object stays truthy on its non-nil handle. }
    o := TObject(Pointer(p^.Payload));
    if o is TPyList then Result := TPyList(o).count > 0
    else if o is TPyDict then Result := TPyDict(o).count > 0
    else if o is TPyBytes then Result := TPyBytes(o).count > 0
    else Result := p^.Payload <> 0;
  end
  else
    Result := p^.Payload <> 0;
end;

function pyvar_to_char(const v: Variant): Char;
var
  p: PPyVarRec;
  t: AnsiString;
begin
  p := PPyVarRec(@v);
  if p^.VType = 5 then
    Result := Chr(p^.Payload and $FF)
  else if p^.VType = 6 then
  begin
    t := PPyAnsiString(@p^.Payload)^;
    if t = '' then begin PyTypeError(p^.VType, 'a non-empty str'); Result := #0; end
    else Result := t[1];
  end
  else
  begin
    PyTypeError(p^.VType, 'a str');
    Result := #0;
  end;
end;

function pyord_v(const v: Variant): Int64;
var
  p: PPyVarRec;
  t: AnsiString;
begin
  p := PPyVarRec(@v);
  if p^.VType = 5 then
    Result := p^.Payload and $FF
  else if p^.VType = 6 then
  begin
    t := PPyAnsiString(@p^.Payload)^;
    if Length(t) <> 1 then
    begin
      PyTypeError(p^.VType, 'a str of length 1');
      Result := 0;
    end
    else
      Result := Ord(t[1]);
  end
  else
  begin
    PyTypeError(p^.VType, 'a str of length 1');
    Result := 0;
  end;
end;

function pylen_v(const v: Variant): Int64;
var
  p: PPyVarRec;
  o: TObject;
begin
  p := PPyVarRec(@v);
  if p^.VType = 6 then
    Result := Length(PPyAnsiString(@p^.Payload)^)
  else if p^.VType = 5 then
    Result := 1                    { a one-char literal is a str of length 1 }
  else if p^.VType = 7 then
  begin
    o := TObject(Pointer(p^.Payload));
    if o is TPyList then Result := TPyList(o).count
    else if o is TPyDict then Result := TPyDict(o).count
    else if o is TPyBytes then Result := TPyBytes(o).count
    else
    begin
      PyTypeError(p^.VType, 'an object with a length');
      Result := 0;
    end;
  end
  else
  begin
    PyTypeError(p^.VType, 'a str, list, dict or bytes');
    Result := 0;
  end;
end;

function pymul_v(const a: Variant; const b: Variant): Variant;
{ `v * n`. A STRING payload repeats, a numeric one multiplies -- the whole
  reason this cannot be decided when lowering. Either operand order. }
var
  pa, pb, sp, np, r: PPyVarRec;
  txt: AnsiString;
  lo: TObject;
  ia, ib, ir: Int64;   { machine-word result, checked for overflow }
  src, rep: TPyList;
  k, cnt, li: Integer;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
  { A SEQUENCE repeats too — `[0] * n` is how Python allocates a fixed-size
    list, so this arm is not an exotic case. Same shape as the str arm below;
    it was missing, and the numeric fallthrough then multiplied the list's
    HANDLE. }
  lo := nil;
  np := nil;
  if pa^.VType = 7 then begin lo := TObject(pyvarobj(a)); np := pb; end
  else if pb^.VType = 7 then begin lo := TObject(pyvarobj(b)); np := pa; end;
  if (lo <> nil) and (lo is TPyList) then
  begin
    if (np^.VType <> 1) and (np^.VType <> 2) and (np^.VType <> 4) then
      PyTypeError(np^.VType, 'an integer to repeat a list by');
    src := TPyList(lo);
    cnt := np^.Payload;
    rep := TPyList.Create;
    rep.FKind := src.FKind;   { (1, 2) * 2 is a tuple, not a list }
    k := 0;
    while k < cnt do
    begin
      li := 0;
      while li < src.count do
      begin
        rep.append(src.at(li));
        Inc(li);
      end;
      Inc(k);
    end;
    Result := rep;
    Exit;
  end;
  sp := nil; np := nil;
  if (pa^.VType = 6) or (pa^.VType = 5) then begin sp := pa; np := pb; end
  else if (pb^.VType = 6) or (pb^.VType = 5) then begin sp := pb; np := pa; end;
  if sp <> nil then
  begin
    if (np^.VType <> 1) and (np^.VType <> 2) and (np^.VType <> 4) then
      PyTypeError(np^.VType, 'an integer to repeat a str by');
    if sp^.VType = 5 then txt := pystr_ofchar(Chr(sp^.Payload and $FF))
    else txt := PPyAnsiString(@sp^.Payload)^;
    txt := pystr_repeat(txt, np^.Payload);
    r^.VType := 6;
    PPyAnsiString(@r^.Payload)^ := txt;
    Exit;
  end;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := pyvar_to_float(a) * pyvar_to_float(b);
  end
  else
  begin
    { arbitrary precision stays exact — see pyadd_v. PXXPromoVarArithTry
      answers 0 when neither side is promo-tagged. }
    if PXXPromoVarArithTry(@Result, @a, @b, 3) <> 0 then Exit;
    { neither side promo-tagged: do it in machine words, and only if THAT
      overflows redo it exactly — see PyPromoteIntArith }
    ia := pyvar_to_int(a); ib := pyvar_to_int(b);
    ir := ia * ib;
    if PyIntOpOverflows(ia, ib, ir, 3) then
    begin
      PyPromoteIntArith(@Result, ia, ib, 3);
      Exit;
    end;
    r^.VType := 2;
    r^.Payload := ir;
  end;
end;

{ Self-contained double-precision ln/exp, used ONLY by pypow_v's fractional-
  exponent path (`2 ** 0.5`). Deliberately hand-rolled rather than `uses Math`:
  that unit declares its OWN `Max`/`Min` overloads (Integer/Integer and
  Double/Double), and pulling it in here shadowed pylib's own `max`/`min`
  overload set for the two-argument scalar form -- `max(d["n"], 1)` started
  returning garbage (test_nilpy_minmax regressed). Precision is bounded by the
  series/reduction below, not IEEE-exact, which is fine for a value that is
  about to be str()'d through this compiler's own (separately, already
  known-truncated) float formatter anyway. }
function PyMathLn(x: Double): Double;
const Ln2 = 0.6931471805599453;
var e: Integer; m, t, tt, term, sum: Double; i: Integer;
begin
  e := 0; m := x;
  while m >= 2.0 do begin m := m / 2.0; Inc(e); end;
  while m < 1.0 do begin m := m * 2.0; Dec(e); end;
  t := (m - 1.0) / (m + 1.0);
  tt := t * t;
  sum := t; term := t;
  for i := 1 to 40 do
  begin
    term := term * tt;
    sum := sum + term / (2 * i + 1);
  end;
  Result := 2.0 * sum + e * Ln2;
end;

function PyMathExp(x: Double): Double;
const Ln2 = 0.6931471805599453;
var n, i: Integer; r, term, sum: Double; neg: Boolean;
begin
  neg := x < 0.0;
  if neg then x := -x;
  n := Trunc(x / Ln2 + 0.5);
  r := x - n * Ln2;
  term := 1.0; sum := 1.0;
  for i := 1 to 25 do
  begin
    term := term * r / i;
    sum := sum + term;
  end;
  for i := 1 to n do sum := sum * 2.0;
  if neg then Result := 1.0 / sum else Result := sum;
end;

{ `base ** exp` for a non-negative integer exponent, in ARBITRARY PRECISION.
  Exponentiation by squaring, the same shape as the machine-word loop in
  pypow_v, so the two cannot drift on the exponent bits. Reached only after the
  machine loop reports overflow — `2 ** 70` answered 0, which is the exact value
  mod 2^64 and reads as a plausible number
  (bug-nilpy-pypow-integer-overflow-does-not-promote).

  Every product goes via a third slot and is copied back, because PXXPromoMul
  must not have its destination alias an operand. }
procedure PyPromoIntPow(dst: Pointer; base, exp: Int64);
var pb, pr, pt: array[0..1] of NativeInt;
    n: Int64;
begin
  PXXPromoInit(@pb); PXXPromoInit(@pr); PXXPromoInit(@pt);
  PXXPromoFromInt(@pb, base);
  PXXPromoFromInt(@pr, 1);
  n := exp;
  while n > 0 do
  begin
    if (n and 1) = 1 then
    begin
      PXXPromoMul(@pt, @pr, @pb);
      PXXPromoCopy(@pr, @pt);
    end;
    n := n shr 1;
    if n > 0 then
    begin
      PXXPromoMul(@pt, @pb, @pb);
      PXXPromoCopy(@pb, @pt);
    end;
  end;
  PXXPromoToVariant(dst, @pr);
  PXXPromoClear(@pb); PXXPromoClear(@pr); PXXPromoClear(@pt);
end;

function pypow_v(const a: Variant; const b: Variant): Variant;
var pa, pb, r: PPyVarRec;
    n: Int64; ir, ibase: Int64;
    it: Int64; ovf: Boolean;   { overflow watch on the machine-word loop }
    fr, fbase, fexp: Double; negExp: Boolean;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  if (not PyVarIsFloat(pa)) and (not PyVarIsFloat(pb)) and
     (pyvar_to_int(b) >= 0) then
  begin
    n := pyvar_to_int(b);
    ibase := pyvar_to_int(a);
    ir := 1;
    ovf := False;
    while n > 0 do
    begin
      if (n and 1) = 1 then
      begin
        it := ir * ibase;
        if PyIntOpOverflows(ir, ibase, it, 3) then begin ovf := True; Break; end;
        ir := it;
      end;
      n := n shr 1;
      { the final squaring is SKIPPED once no bits remain: the old loop always
        squared once more, which is harmless when the result is discarded but
        would report a false overflow here }
      if n > 0 then
      begin
        it := ibase * ibase;
        if PyIntOpOverflows(ibase, ibase, it, 3) then begin ovf := True; Break; end;
        ibase := it;
      end;
    end;
    if ovf then
    begin
      PyPromoIntPow(@Result, pyvar_to_int(a), pyvar_to_int(b));
      Exit;
    end;
    r^.VType := 2;
    r^.Payload := ir;
    Exit;
  end;
  fbase := pyvar_to_float(a);
  fexp := pyvar_to_float(b);
  if (fbase = 0.0) and (fexp < 0.0) then
    raise ZeroDivisionError.Create('0.0 cannot be raised to a negative power');
  if Frac(fexp) = 0.0 then
  begin
    negExp := fexp < 0.0;
    n := Trunc(Abs(fexp));
    fr := 1.0;
    while n > 0 do
    begin
      if (n and 1) = 1 then fr := fr * fbase;
      fbase := fbase * fbase;
      n := n shr 1;
    end;
    if negExp then fr := 1.0 / fr;
  end
  else
    fr := PyMathExp(fexp * PyMathLn(fbase));
  r^.VType := 3;
  PPyDouble(@r^.Payload)^ := fr;
end;

function pydivmod_v(const a: Variant; const b: Variant): TPyList;
begin
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  Result.append(pyfloordiv_v(a, b));
  Result.append(pyfloormod_v(a, b));
end;

function pyor_v(const a: Variant; const b: Variant): Variant;
var src, dst: PPyVarRec;
begin
  if pyvar_to_bool(a) then src := PPyVarRec(@a) else src := PPyVarRec(@b);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
end;

function pyand_v(const a: Variant; const b: Variant): Variant;
var src, dst: PPyVarRec;
begin
  if pyvar_to_bool(a) then src := PPyVarRec(@b) else src := PPyVarRec(@a);
  dst := PPyVarRec(@Result);
  PyVarSlotInit(dst, src);
end;

function pyfloordiv_v(const a: Variant; const b: Variant): Variant;
var
  pa, pb, r: PPyVarRec;
  dv: Double;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    dv := pyfloordiv_f(pyvar_to_float(a), pyvar_to_float(b));
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := dv;
  end
  else
  begin
    { An ARBITRARY-PRECISION operand stays exact — the same first line pyadd_v /
      pysub_v / pymul_v already carry. Without it BOTH operands went through
      pyvar_to_int below, which narrows mod 2^64: `(2**64 + 5) // 1` answered 5,
      and `x % (2**64)` raised ZeroDivisionError because the DIVISOR narrowed to
      0. Op 11 is FLOOR div, not the truncating 4 — see PXXPromoVarArithTry
      (bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum). }
    if PXXPromoVarArithTry(@Result, @a, @b, 11) <> 0 then Exit;
    r^.VType := 2;
    { pyvar_to_int, not raw Payload: a non-int-tagged operand (e.g. a VT_CHAR /
      VT_STRING digit, or an int arriving under a tag whose value is not stored
      directly in Payload) otherwise read as 0 -> a spurious divide-by-zero.
      Mirrors pysub_v/pyadd_v, which already coerce through pyvar_to_int. }
    r^.Payload := pyfloordiv_i(pyvar_to_int(a), pyvar_to_int(b));
  end;
end;

function pyfloormod_v(const a: Variant; const b: Variant): Variant;
var
  pa, pb, r: PPyVarRec;
  dv: Double;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
  { A str LEFT operand makes `%` printf-style FORMATTING, not modulo — the
    single most common `%` in Python. Statically-typed `"%d" % n` already
    reached pypercent_format, but the variant form (a format string out of a
    list, a dict or a parameter) landed here and coerced the format string to a
    number, so `f % 5` died with "expected a number, got str". }
  if (pa^.VType = 6) or (pa^.VType = 5) then
  begin
    r^.VType := 6;
    PPyAnsiString(@r^.Payload)^ := pypercent_format(PyVarText(pa), b);
    Exit;
  end;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    dv := pyfloormod_f(pyvar_to_float(a), pyvar_to_float(b));
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := dv;
  end
  else
  begin
    { arbitrary precision stays exact — see pyfloordiv_v. Op 12 is FLOOR mod
      (remainder takes the DIVISOR's sign), not the truncating 5. }
    if PXXPromoVarArithTry(@Result, @a, @b, 12) <> 0 then Exit;
    r^.VType := 2;
    { pyvar_to_int, not raw Payload — see pyfloordiv_v: a non-directly-tagged
      operand otherwise reads 0 and modulo divides by zero. }
    r^.Payload := pyfloormod_i(pyvar_to_int(a), pyvar_to_int(b));
  end;
end;

{ text of a str(6)/char(5) variant, for the string-aware ops below }
function PyVarText(p: PPyVarRec): AnsiString;
begin
  if p^.VType = 5 then Result := pystr_ofchar(Chr(p^.Payload and $FF))
  else if p^.VType = 6 then Result := PPyAnsiString(@p^.Payload)^
  else Result := '';
end;

function pyvar_of_int(v: Int64): Variant;
var r: PPyVarRec;
begin
  r := PPyVarRec(@Result);
  r^.VType := 2;
  r^.Payload := v;
end;

function pyvar_of_bool(b: Boolean): Variant;
var r: PPyVarRec;
begin
  r := PPyVarRec(@Result);
  r^.VType := 4;
  if b then r^.Payload := 1 else r^.Payload := 0;
end;

function pyvar_id(const v: Variant): Variant;
begin
  Result := v;
end;

function pyint_v(const v: Variant): Variant;
var p: PPyVarRec; pr: array[0..1] of NativeInt;
begin
  p := PPyVarRec(@v);
  { VT_PROMO_INT64: an arbitrary-precision int is ALREADY an int, and int() of
    an int is the identity in Python at any magnitude — so hand the slot back
    rather than routing through pyvar_to_int, whose mod-2^64 narrowing is the
    right rule for a masked-cell idiom and the wrong one for int() itself
    (bug-nilpy-int-of-a-variant-held-bignum-raises). }
  if p^.VType = 8193 then
    Result := v
  else if p^.VType = 6 then
  begin
    { VT_STRING: `int(v)` where the variant holds TEXT parses it — pyvar_to_int
      would raise TypeError, which is right for a string in an ARITHMETIC
      context and wrong for int() itself, whose whole job on a string is to
      parse. Through the arbitrary-precision path, so a variant-held 30-digit
      string is as exact as the statically-typed one
      (bug-nilpy-int-of-a-long-decimal-string-narrows). }
    PXXPromoInit(@pr);
    pystr_to_promo(@pr, PPyAnsiString(@p^.Payload)^);
    PXXPromoToVariant(@Result, @pr);   { same shape as pyabs_v's promo arm }
    PXXPromoClear(@pr);
  end
  else
    Result := pyvar_of_int(pyvar_to_int(v));
end;

{ Redo an int operation in ARBITRARY PRECISION after the machine one overflowed.

  Python has no fixed-width int, so a variant holding two ordinary VT_INT64s
  must still give the exact answer when they do not fit: `self.v = self.v * 2`
  on a variant field doubled correctly 63 times and then went to 0, because the
  promo runtime's own gate (PXXPromoVarArithTry) deliberately declines a pair
  where NEITHER side is promo-tagged — that gate is right for a Pascal Variant,
  whose arithmetic wraps, and wrong for NilPy, which is what this unit is.

  Only reached on the overflow path, so ordinary variant arithmetic keeps its
  machine speed and this costs nothing until it is the difference between a
  right answer and a silent wrong one. dst must already be a valid (cleared)
  variant slot: PXXPromoToVariant reads the old tag before overwriting it. }
procedure PyPromoteIntArith(dst: Pointer; x, y: Int64; op: Integer);
var pa, pb, pr: array[0..1] of NativeInt;
begin
  PXXPromoInit(@pa); PXXPromoInit(@pb); PXXPromoInit(@pr);
  PXXPromoFromInt(@pa, x);
  PXXPromoFromInt(@pb, y);
  if op = 1 then PXXPromoAdd(@pr, @pa, @pb)
  else if op = 2 then PXXPromoSub(@pr, @pa, @pb)
  else PXXPromoMul(@pr, @pa, @pb);
  PXXPromoToVariant(dst, @pr);
  PXXPromoClear(@pa); PXXPromoClear(@pb); PXXPromoClear(@pr);
end;

{ Did `x + y` / `x - y` / `x * y` leave the signed 64-bit range? Sign rules for
  the additive pair; a divide-back check for the multiply, which is exact and
  needs no 128-bit type. }
function PyIntOpOverflows(x, y, r: Int64; op: Integer): Boolean;
begin
  if op = 1 then
    PyIntOpOverflows := ((x > 0) and (y > 0) and (r < 0)) or
                        ((x < 0) and (y < 0) and (r >= 0))
  else if op = 2 then
    PyIntOpOverflows := ((x >= 0) and (y < 0) and (r < 0)) or
                        ((x < 0) and (y > 0) and (r >= 0))
  else
    PyIntOpOverflows := (x <> 0) and ((r div x) <> y);
end;

function pyadd_v(const a: Variant; const b: Variant): Variant;
var pa, pb, r: PPyVarRec; concat: AnsiString;
    oa, ob: TObject; joined: TPyList; ji: Integer;
    ia, ib, ir: Int64;   { machine-word result, checked for overflow }
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
  { list + list -> a NEW list holding both, like Python. `xs += ys` is separate
    and in-place (TPyList.extend); this is the value form, and without it the
    numeric fallthrough added the two class HANDLES. }
  if (pa^.VType = 7) and (pb^.VType = 7) then
  begin
    oa := TObject(pyvarobj(a)); ob := TObject(pyvarobj(b));
    if (oa is TPyList) and (ob is TPyList) then
    begin
      joined := TPyList.Create;
      joined.FKind := TPyList(oa).FKind;
      for ji := 0 to TPyList(oa).count - 1 do joined.append(TPyList(oa).at(ji));
      for ji := 0 to TPyList(ob).count - 1 do joined.append(TPyList(ob).at(ji));
      Result := joined;
      Exit;
    end;
  end;
  { str/char + str/char -> concat }
  if ((pa^.VType = 6) or (pa^.VType = 5)) and ((pb^.VType = 6) or (pb^.VType = 5)) then
  begin
    concat := PyVarText(pa) + PyVarText(pb);
    r^.VType := 6;
    PPyAnsiString(@r^.Payload)^ := concat;
    Exit;
  end;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := pyvar_to_float(a) + pyvar_to_float(b);
  end
  else
  begin
    { An ARBITRARY-PRECISION operand stays exact: PXXPromoVarArithTry answers 0
      when neither side is promo-tagged, so the machine-int path below is
      untouched for ordinary variants. }
    if PXXPromoVarArithTry(@Result, @a, @b, 1) <> 0 then Exit;
    { neither side promo-tagged: do it in machine words, and only if THAT
      overflows redo it exactly — see PyPromoteIntArith }
    ia := pyvar_to_int(a); ib := pyvar_to_int(b);
    ir := ia + ib;
    if PyIntOpOverflows(ia, ib, ir, 1) then
    begin
      PyPromoteIntArith(@Result, ia, ib, 1);
      Exit;
    end;
    r^.VType := 2;
    r^.Payload := ir;
  end;
end;

{ `l += y` where `l`'s STATIC type is a variant (an unannotated parameter, an
  element pulled out of a list/dict, ...) — the compile-time PyNodeListCi
  check that lowers a STATICALLY-known list target's `+=` to `TPyList.extend`
  cannot see through a variant, so this is the run-time fallback. When the
  variant holds a TPyList, extend it IN PLACE (every alias sees the new
  elements, exactly like the statically-typed case and like Python's
  `list.__iadd__`) and hand back the SAME object rather than a new one, so the
  caller's `l := pyaugadd_v(l, y)` rebinds `l` to what it already pointed at.
  Anything else falls through to ordinary `pyadd_v` (numbers add, strings
  concatenate, and a genuine type mismatch raises there)
  (bug-nilpy-augmented-add-on-variant-list-is-not-in-place). }
function pyaugadd_v(const a: Variant; const b: Variant): Variant;
var pa, pb: PPyVarRec; oa, ob: TObject; i: Integer;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  if pa^.VType = 7 then
  begin
    oa := TObject(pyvarobj(a));
    if oa is TPyList then
    begin
      if (pb^.VType = 7) and (TObject(pyvarobj(b)) is TPyList) then
      begin
        ob := TObject(pyvarobj(b));
        for i := 0 to TPyList(ob).count - 1 do TPyList(oa).append(TPyList(ob).at(i));
      end
      else
        TPyList(oa).append(b);
      { hand back the SAME object, retained -- PyVarSlotInit is the shared
        "copy a variant slot, retaining a managed payload" step pyor_v/pyand_v
        already use for returning an OPERAND as-is. }
      PyVarSlotInit(PPyVarRec(@Result), pa);
      Exit;
    end;
  end;
  Result := pyadd_v(a, b);
end;

function pysub_v(const a: Variant; const b: Variant): Variant;
var pa, pb, r: PPyVarRec;
    ia, ib, ir: Int64;   { machine-word result, checked for overflow }
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := pyvar_to_float(a) - pyvar_to_float(b);
  end
  else
  begin
    { arbitrary precision stays exact — see pyadd_v. PXXPromoVarArithTry
      answers 0 when neither side is promo-tagged. }
    if PXXPromoVarArithTry(@Result, @a, @b, 2) <> 0 then Exit;
    { neither side promo-tagged: do it in machine words, and only if THAT
      overflows redo it exactly — see PyPromoteIntArith }
    ia := pyvar_to_int(a); ib := pyvar_to_int(b);
    ir := ia - ib;
    if PyIntOpOverflows(ia, ib, ir, 2) then
    begin
      PyPromoteIntArith(@Result, ia, ib, 2);
      Exit;
    end;
    r^.VType := 2;
    r^.Payload := ir;
  end;
end;

function pymod_v(const a: Variant; const b: Variant): Variant;
begin
  Result := pyfloormod_v(a, b);
end;

function pybitand_v(const a: Variant; const b: Variant): Variant;
begin
  Result := pyvar_of_int(pyvar_to_int(a) and pyvar_to_int(b));
end;

function pybitor_v(const a: Variant; const b: Variant): Variant;
begin
  Result := pyvar_of_int(pyvar_to_int(a) or pyvar_to_int(b));
end;

function pybitxor_v(const a: Variant; const b: Variant): Variant;
begin
  Result := pyvar_of_int(pyvar_to_int(a) xor pyvar_to_int(b));
end;

function pyshl_v(const a: Variant; const b: Variant): Variant;
begin
  Result := pyvar_of_int(pyvar_to_int(a) shl pyvar_to_int(b));
end;

function pyshr_v(const a: Variant; const b: Variant): Variant;
var av, n, rv: Int64;
begin
  { Python >> is ARITHMETIC (sign-propagating, floors toward -inf). Pascal shr
    is logical, so synthesise the sign fill: -x>>n == ~(~x >> n). }
  av := pyvar_to_int(a); n := pyvar_to_int(b);
  if n >= 64 then
  begin
    if av < 0 then rv := -1 else rv := 0;
  end
  else if av < 0 then
    rv := not ((not av) shr n)
  else
    rv := av shr n;
  Result := pyvar_of_int(rv);
end;

function pyinvert_v(const a: Variant): Variant;
begin
  Result := pyvar_of_int(not pyvar_to_int(a));
end;

function pyneg_v(const a: Variant): Variant;
var p, r: PPyVarRec;
begin
  p := PPyVarRec(@a); r := PPyVarRec(@Result);
  if PyVarIsFloat(p) then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := -PyVarAsFloat(p);
  end
  else
    Result := pyvar_of_int(-pyvar_to_int(a));
end;

{ Two SEQUENCES compare lexicographically in Python: element by element, and
  the shorter one loses if it is a prefix. Without this, ordering two lists fell
  through to pyvar_to_int and — before that coercion was in place — compared
  their HANDLES, so `xs < ys` answered by heap address. }
function pylist_cmp(x: TPyList; y: TPyList): Int64;
var i, n: Integer; c: Int64;
begin
  if x = nil then n := 0 else n := x.count;
  if y <> nil then
    if y.count < n then n := y.count;
  i := 0;
  while i < n do
  begin
    c := pycmp_v(x.at(i), y.at(i));
    if c <> 0 then begin Result := c; Exit; end;
    Inc(i);
  end;
  { a common prefix: the shorter sequence sorts first }
  if x = nil then i := 0 else i := x.count;
  if y = nil then n := 0 else n := y.count;
  if i < n then Result := -1
  else if i > n then Result := 1
  else Result := 0;
end;

function pycmp_v(const a: Variant; const b: Variant): Int64;
var pa, pb: PPyVarRec; sa, sb: AnsiString; fa, fb: Double; ia, ib: Int64;
    oa, ob: TObject; pc: Integer;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  if (pa^.VType = 7) and (pb^.VType = 7) then
  begin
    oa := TObject(pyvarobj(a)); ob := TObject(pyvarobj(b));
    if (oa is TPyList) and (ob is TPyList) then
    begin
      Result := pylist_cmp(TPyList(oa), TPyList(ob));
      Exit;
    end;
    { any other object pair: no ordering defined, and reading the handles as
      numbers is what this whole family was fixed to stop doing }
    PyTypeError(pa^.VType, 'a number or a sequence');
    Result := 0;
    Exit;
  end;
  if ((pa^.VType = 6) or (pa^.VType = 5)) and ((pb^.VType = 6) or (pb^.VType = 5)) then
  begin
    sa := PyVarText(pa); sb := PyVarText(pb);
    if sa < sb then Result := -1
    else if sa > sb then Result := 1
    else Result := 0;
    Exit;
  end;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    fa := pyvar_to_float(a); fb := pyvar_to_float(b);
    if fa < fb then Result := -1
    else if fa > fb then Result := 1
    else Result := 0;
    Exit;
  end;
  { An ARBITRARY-PRECISION operand must not go through pyvar_to_int, which
    narrows mod 2^64: `2**64 > 5` answered False (0 > 5) and sorted() put the
    biggest value first. PXXPromoVarCmpTry answers 0 when NEITHER side is
    promo-tagged, so the ordinary path below is untouched for every other pair;
    on a promo pair it returns 1=False / 2=True. Asked twice — `<` then `=` —
    because this routine owes a three-way answer and the Try helper is
    predicate-shaped; both calls are on the promo path only
    (bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum). }
  pc := PXXPromoVarCmpTry(@a, @b, 3);          { 3 = less-than }
  if pc <> 0 then
  begin
    if pc = 2 then Result := -1
    else if PXXPromoVarCmpTry(@a, @b, 1) = 2 then Result := 0   { 1 = equal }
    else Result := 1;
    Exit;
  end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b);
  if ia < ib then Result := -1
  else if ia > ib then Result := 1
  else Result := 0;
end;

function pytruediv_v(const a: Variant; const b: Variant): Variant;
var r: PPyVarRec; da, db: Double;
begin
  { pyvar_to_float RAISES TypeError for a str/list/dict/None tag, so the
    coercion is the type check — there is no arm that reads a handle as a
    number. Divisor first is deliberate only in that both must be numbers
    before the zero test means anything. }
  da := pyvar_to_float(a);
  db := pyvar_to_float(b);
  if db = 0.0 then raise ZeroDivisionError.Create('division by zero');
  r := PPyVarRec(@Result);
  r^.VType := 3;
  PPyDouble(@r^.Payload)^ := da / db;
end;

function pylt_v(const a: Variant; const b: Variant): Boolean;
begin
  Result := pycmp_v(a, b) < 0;
end;

function pyle_v(const a: Variant; const b: Variant): Boolean;
begin
  Result := pycmp_v(a, b) <= 0;
end;

function pygt_v(const a: Variant; const b: Variant): Boolean;
begin
  Result := pycmp_v(a, b) > 0;
end;

function pyge_v(const a: Variant; const b: Variant): Boolean;
begin
  Result := pycmp_v(a, b) >= 0;
end;

function pyeq_v(const a: Variant; const b: Variant): Boolean;
var pa, pb: PPyVarRec;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  { None equals only None }
  if (pa^.VType = 0) or (pb^.VType = 0) then
  begin
    Result := (pa^.VType = 0) and (pb^.VType = 0);
    Exit;
  end;
  Result := pycmp_v(a, b) = 0;
end;

function pystr_repeat_v(const v: Variant; n: Int64): AnsiString;
var
  p: PPyVarRec;
begin
  p := PPyVarRec(@v);
  { raises for the same reason PyTypeError does — a halt here is invisible to
    `except TypeError:`. }
  if p^.VType <> 6 then
    raise TypeError.Create('cannot repeat a non-string value');
  { the `PPyAnsiString(@p^.Payload)^` deref arg is owned by the isNilPy arg
    lowering (bug-a-nilpy-managed-deref-to-const-arg-leaks), so no per-site
    bind is needed. }
  Result := pystr_repeat(PPyAnsiString(@p^.Payload)^, n);
end;

function pystr_repeat(const s: AnsiString; n: Int64): AnsiString;
{ Sized ONCE and filled, not accumulated. `Result := Result + s` in the loop
  reallocated and re-copied everything built so far on every iteration, so the
  total work was 1+2+...+n characters -- quadratic. `"x" * 80000` took 19
  seconds and `"x" * 100000` did not finish, while the very same string built by
  an explicit `s = s + "x"` loop in NilPy completed fine: the idiom that LOOKS
  like the fast one was the slow one (bug-nilpy-str-repeat-is-quadratic).
  Found by a scaling curve -- every small case was fine and the failure read as
  a hang, not a wrong answer. }
var
  i, k, m, total: Int64;
  j: Int64;
begin
  Result := '';
  m := Length(s);
  if (n <= 0) or (m = 0) then Exit;
  { Python raises rather than trying to build something that cannot exist; a
    silent wrap here would ask SetLength for a negative or tiny buffer and then
    write past it. }
  if n > (High(Int64) div m) then
    raise OverflowError.Create('repeated string is too long');
  total := m * n;
  SetLength(Result, total);
  k := 1;
  for i := 1 to n do
    for j := 1 to m do
    begin
      Result[k] := s[j];
      k := k + 1;
    end;
end;

function pystr_to_int(const s: AnsiString): Int64;
var
  v: Int64;
  code: Integer;
  t: AnsiString;
begin
  t := pystr_strip(s);          { Python's int() tolerates surrounding space }
  Val(t, v, code);
  if (code <> 0) or (t = '') then
  begin
    { RAISE — see PyIndexError. `int("abc")` is the shape
      bug-nilpy-int-parse-halts-instead-of-raising was opened for, and Python
      raises ValueError here. }
    raise ValueError.Create('invalid literal for int() with base 10: ' + Chr(39) + s + Chr(39));
  end;
  Result := v;
end;

procedure pystr_to_promo(dst: Pointer; const s: AnsiString);
var t: AnsiString; i, lo: Integer; ok: Boolean;
begin
  t := pystr_strip(s);          { Python's int() tolerates surrounding space }
  ok := t <> '';
  lo := 1;
  if ok and ((t[1] = '-') or (t[1] = '+')) then
  begin
    lo := 2;
    if Length(t) < 2 then ok := False;
  end;
  if ok then
    for i := lo to Length(t) do
      { explicit range rather than a set: the same reason PXXPromoFromStr
        spells it out — set membership does not lower on every target }
      if (t[i] < '0') or (t[i] > '9') then begin ok := False; Break; end;
  if not ok then
    raise ValueError.Create('invalid literal for int() with base 10: ' + Chr(39) + s + Chr(39));
  { PXXPromoFromStr reads the sign itself and STOPS at the first non-digit —
    which is why the loop above must reject junk first: without it `int("12x")`
    would quietly answer 12 where pystr_to_int raises. }
  PXXPromoFromStr(dst, t);
end;

{ Python's `/` ALWAYS yields a float and raises ZeroDivisionError on a zero
  divisor. Plain IEEE division does neither — `3 / 0` produced a saturated
  Int64 formatted through the large-float path, i.e. garbage bytes on stdout
  (bug-nilpy-runtime-raised-errors-bypass-try-except). }
function pytruediv_f(a: Double; b: Double): Double;
begin
  if b = 0 then raise ZeroDivisionError.Create('division by zero');
  pytruediv_f := a / b;
end;

function pyfloordiv_i(a: Int64; b: Int64): Int64;
var q, r: Int64;
begin
  { Python raises ZeroDivisionError; the bare `div` below traps as Pascal
    runtime error 200, which unwinds nothing and no handler can catch. }
  if b = 0 then raise ZeroDivisionError.Create('integer division or modulo by zero');
  q := a div b;
  r := a mod b;
  if (r <> 0) and ((r < 0) <> (b < 0)) then q := q - 1;
  Result := q;
end;

function pyfloormod_i(a: Int64; b: Int64): Int64;
var r: Int64;
begin
  if b = 0 then raise ZeroDivisionError.Create('integer modulo by zero');
  r := a mod b;
  if (r <> 0) and ((r < 0) <> (b < 0)) then r := r + b;
  Result := r;
end;

function pyfloordiv_f(a: Double; b: Double): Double;
var q: Double;
begin
  if b = 0 then raise ZeroDivisionError.Create('float floor division by zero');
  q := Int(a / b);
  { Int() truncates toward zero; step down when the true quotient was negative
    and inexact, so the result floors like Python's. }
  if (q * b <> a) and ((a < 0) <> (b < 0)) then q := q - 1;
  Result := q;
end;

function pyfloormod_f(a: Double; b: Double): Double;
begin
  Result := a - pyfloordiv_f(a, b) * b;
end;

function min(a: Int64; b: Int64): Int64;
begin
  if a < b then Result := a else Result := b;
end;

function min(a: Double; b: Double): Double; overload;
begin
  if a < b then Result := a else Result := b;
end;

function max(a: Int64; b: Int64): Int64; overload;
begin
  if a > b then Result := a else Result := b;
end;

function max(a: Double; b: Double): Double; overload;
begin
  if a > b then Result := a else Result := b;
end;

function min(const a: Variant; const b: Variant): Variant; overload;
begin
  if pyvar_gt(a, b) then Result := b else Result := a;
end;

function max(const a: Variant; const b: Variant): Variant; overload;
begin
  if pyvar_gt(a, b) then Result := a else Result := b;
end;


function pystr_contains(const s: AnsiString; const sub: AnsiString): Boolean;
begin
  { the empty string is contained in everything, as in Python }
  Result := (Length(sub) = 0) or (pystr_find(s, sub) >= 0);
end;

procedure PyBytesIndexError;
begin
  raise IndexError.Create('bytearray index out of range');
end;

constructor TPyBytes.Create(n: Integer);
var k: Integer; p: PByte;
begin
  PXXObjFinalizeHook := @PyObjFinalize;
  if n < 0 then n := 0;
  FLen := n;
  FData := nil;
  if n = 0 then Exit;
  GetMem(FData, n);
  { Python's bytearray(n) is n ZERO bytes, not uninitialised memory }
  for k := 0 to n - 1 do
  begin
    p := PByte(NativeInt(FData) + k);
    p^ := 0;
  end;
end;

function TPyBytes.count: Integer;
begin
  Result := FLen;
end;

{ Python's negative index counts from the end, as for str and list. }
function PyBytesFix(b: TPyBytes; i: Integer): Integer;
begin
  if i < 0 then i := i + b.FLen;
  if (i < 0) or (i >= b.FLen) then PyBytesIndexError;
  Result := i;
end;

function TPyBytes.at(i: Integer): Integer;
var p: PByte;
begin
  i := PyBytesFix(Self, i);
  p := PByte(NativeInt(FData) + i);
  Result := p^;
end;

procedure TPyBytes.put(i: Integer; v: Integer);
var p: PByte;
begin
  i := PyBytesFix(Self, i);
  p := PByte(NativeInt(FData) + i);
  { Python stores 0..255 and raises outside that; masking would silently
    accept 256 as 0, so it is rejected }
  if (v < 0) or (v > 255) then
  begin
    raise ValueError.Create('byte must be in range(0, 256)');
  end;
  p^ := v;
end;

procedure PyBytesEnsure(b: TPyBytes; need: Integer);
var np: Pointer; k: Integer; src, dst: PByte;
begin
  if need <= b.FLen then Exit;
  GetMem(np, need);
  for k := 0 to need - 1 do
  begin
    dst := PByte(NativeInt(np) + k);
    if k < b.FLen then
    begin
      src := PByte(NativeInt(b.FData) + k);
      dst^ := src^;
    end
    else
      dst^ := 0;
  end;
  b.FData := np;
  b.FLen := need;
end;

procedure TPyBytes.extend(src: TPyBytes);
var k, base: Integer; sp, dp: PByte; sl: TPyList;
begin
  if src = nil then Exit;
  { A LIST/TUPLE of ints binds to this class param too (overload resolution is
    not identity-precise): `out.extend((13, 10))` — read its VALUES instead of
    misreading TPyList fields as byte storage. }
  if TObject(src) is TPyList then
  begin
    sl := TPyList(TObject(src));
    base := FLen;
    PyBytesEnsure(Self, FLen + sl.count);
    for k := 0 to sl.count - 1 do
    begin
      dp := PByte(NativeInt(FData) + base + k);
      dp^ := Byte(pyvar_to_int(sl.at(k)) and $FF);
    end;
    Exit;
  end;
  base := FLen;
  PyBytesEnsure(Self, FLen + src.FLen);
  for k := 0 to src.FLen - 1 do
  begin
    sp := PByte(NativeInt(src.FData) + k);
    dp := PByte(NativeInt(FData) + base + k);
    dp^ := sp^;
  end;
end;

procedure TPyBytes.append(v: Integer);
var p: PByte;
begin
  if (v < 0) or (v > 255) then
  begin
    raise ValueError.Create('byte must be in range(0, 256)');
  end;
  PyBytesEnsure(Self, FLen + 1);
  p := PByte(NativeInt(FData) + (FLen - 1));
  p^ := v;
end;

function TPyBytes.decode: AnsiString; overload;
{ Python's `b.decode()` defaults to utf-8. Without this zero-argument overload a
  bare `b.decode()` bound to the one-argument form with an UNINITIALISED
  AnsiString for `encoding` and SEGFAULTED (exit 139) — `b.decode("utf-8")`
  worked all along, which is what hid it.
  bug-nilpy-dict-from-pairs-and-bytes-decode-segfault. }
begin
  Result := decode('utf-8');
end;

function TPyBytes.decode(const encoding: AnsiString): AnsiString; overload;
var k: Integer; p: PByte;
begin
  Result := '';
  for k := 0 to FLen - 1 do
  begin
    p := PByte(NativeInt(FData) + k);
    Result := Result + Chr(p^);
  end;
end;

function TPyBytes.decode(const encoding: AnsiString; const errors: AnsiString): AnsiString; overload;
begin
  Result := decode(encoding);
end;

function bytearray: TPyBytes; overload;
begin
  Result := TPyBytes.Create(0);
end;

function bytearray(n: Integer): TPyBytes; overload;
begin
  Result := TPyBytes.Create(n);
end;

function bytearray(b: TPyBytes): TPyBytes; overload;
var i: Integer;
begin
  if b = nil then begin Result := TPyBytes.Create(0); Exit; end;
  Result := TPyBytes.Create(b.FLen);
  for i := 0 to b.FLen - 1 do Result.put(i, b.at(i));
end;

function bytearray(l: TPyList): TPyBytes; overload;
var i: Integer; v: Int64;
begin
  if l = nil then begin Result := TPyBytes.Create(0); Exit; end;
  Result := TPyBytes.Create(l.count);
  for i := 0 to l.count - 1 do
  begin
    v := pyvar_to_int(l.at(i));
    if (v < 0) or (v > 255) then
      raise ValueError.Create('byte must be in range(0, 256)');
    Result.put(i, Integer(v));
  end;
end;

{ Python's slice bound normalisation, shared by str, bytes and list so the
  three cannot drift apart. Order matters: PY_SLICE_OMIT is resolved FIRST
  (an omitted low bound is 0 and an omitted high bound is n), then a negative
  bound counts from the end, and only then does the clamp run. Clamping last
  is what makes an out-of-range or inverted range yield an EMPTY slice rather
  than an error, which is the documented Python behaviour. }
procedure PySliceBounds(n: Integer; var lo, hi: Integer);
begin
  if lo = PY_SLICE_OMIT then lo := 0;
  if hi = PY_SLICE_OMIT then hi := n;
  if lo < 0 then lo := lo + n;
  if hi < 0 then hi := hi + n;
  if lo < 0 then lo := 0;
  if hi < 0 then hi := 0;
  if lo > n then lo := n;
  if hi > n then hi := n;
  { an inverted range is empty, not negative-length }
  if hi < lo then hi := lo;
end;

{ CPython's slice.indices(n) for an explicit STEP. Deliberately a separate
  routine from PySliceBounds rather than an extension of it: with a negative
  step every default and every clamp changes, so folding the two together
  would make the step=1 path harder to read for no gain.

  The high bound is EXCLUSIVE in both directions, so for a negative step it can
  legitimately land on -1 ("stop before index 0") — callers must therefore
  iterate with `while i > hi`, never `for i := lo downto hi`.

  Returns the element COUNT, which callers need to preallocate; recomputing it
  from (lo, hi, step) at each call site is where an off-by-one would hide. }
function PySliceBoundsStep(n: Integer; var lo, hi: Integer; step: Integer): Integer;
begin
  if step = 0 then raise ValueError.Create('slice step cannot be zero');
  if lo = PY_SLICE_OMIT then
  begin
    if step < 0 then lo := n - 1 else lo := 0;
  end
  else
  begin
    if lo < 0 then lo := lo + n;
    if lo < 0 then
    begin
      if step < 0 then lo := -1 else lo := 0;
    end;
    if lo >= n then
    begin
      if step < 0 then lo := n - 1 else lo := n;
    end;
  end;
  if hi = PY_SLICE_OMIT then
  begin
    if step < 0 then hi := -1 else hi := n;
  end
  else
  begin
    if hi < 0 then hi := hi + n;
    if hi < 0 then
    begin
      if step < 0 then hi := -1 else hi := 0;
    end;
    if hi >= n then
    begin
      if step < 0 then hi := n - 1 else hi := n;
    end;
  end;
  if step > 0 then
  begin
    if hi > lo then Result := ((hi - lo) + step - 1) div step else Result := 0;
  end
  else
  begin
    if lo > hi then Result := ((lo - hi) + (-step) - 1) div (-step) else Result := 0;
  end;
end;

procedure pyrange_check_step(step: Int64);
begin
  if step = 0 then raise ValueError.Create('range() arg 3 must not be zero');
end;

function pyrange_list(lo, hi, step: Int64): TPyList;
var i: Int64;
begin
  pyrange_check_step(step);
  Result := TPyList.Create;
  i := lo;
  if step > 0 then
    while i < hi do begin Result.append(i); i := i + step; end
  else
    while i > hi do begin Result.append(i); i := i + step; end;
end;

function pystr_slice_step(const s: AnsiString; lo, hi, step: Integer): AnsiString;
var i, k, cnt: Integer;
begin
  cnt := PySliceBoundsStep(Length(s), lo, hi, step);
  { SetLength once and index, never `Result := Result + ch` — that idiom is
    QUADRATIC here (project_pxx_string_concat_in_loop_is_quadratic). }
  SetLength(Result, cnt);
  i := lo;
  for k := 1 to cnt do
  begin
    Result[k] := s[i + 1];        { Python is 0-based, Pascal strings 1-based }
    i := i + step;
  end;
end;

function pybytes_slice_step(b: TPyBytes; lo, hi, step: Integer): TPyBytes;
var i, k, cnt: Integer; src, dst: PByte;
begin
  cnt := PySliceBoundsStep(b.FLen, lo, hi, step);
  Result := TPyBytes.Create(cnt);
  i := lo;
  for k := 0 to cnt - 1 do
  begin
    src := PByte(NativeInt(b.FData) + i);
    dst := PByte(NativeInt(Result.FData) + k);
    dst^ := src^;
    i := i + step;
  end;
end;

function pystr_encode(const s: AnsiString): TPyBytes;
var k: Integer; p: PByte;
begin
  Result := TPyBytes.Create(Length(s));
  for k := 1 to Length(s) do
  begin
    p := PByte(NativeInt(Result.FData) + (k - 1));
    p^ := Ord(s[k]);
  end;
end;

function pystr_slice(const s: AnsiString; lo, hi: Integer): AnsiString;
begin
  PySliceBounds(Length(s), lo, hi);
  { Copy is 1-based and takes a COUNT; Python's bounds are 0-based }
  Result := Copy(s, lo + 1, hi - lo);
end;

function pybytes_slice(b: TPyBytes; lo, hi: Integer): TPyBytes;
var k: Integer; src, dst: PByte;
begin
  PySliceBounds(b.FLen, lo, hi);
  Result := TPyBytes.Create(hi - lo);
  for k := 0 to (hi - lo) - 1 do
  begin
    src := PByte(NativeInt(b.FData) + lo + k);
    dst := PByte(NativeInt(Result.FData) + k);
    dst^ := src^;
  end;
end;

procedure pybytes_setslice(b: TPyBytes; lo, hi: Integer; src: TPyBytes);
var k, oldLen, delta: Integer; sp, dp: PByte;
begin
  PySliceBounds(b.FLen, lo, hi);
  if src.FLen <> (hi - lo) then
  begin
    { Python bytearray slice assignment RESIZES on a length mismatch —
      inserting or deleting bytes and shifting the tail. uforth's 2VARIABLE
      leans on this (`memory[h:h+16] = b'..' * 16` with a 64-byte value,
      thanks to a doubled backslash CPython also sees), so matching the
      resize is quirk-compatibility, not generosity. }
    oldLen := b.FLen;
    delta := src.FLen - (hi - lo);
    if delta > 0 then
    begin
      PyBytesEnsure(b, oldLen + delta);
      for k := oldLen - 1 downto hi do
      begin
        sp := PByte(NativeInt(b.FData) + k);
        dp := PByte(NativeInt(b.FData) + k + delta);
        dp^ := sp^;
      end;
    end
    else
    begin
      for k := hi to oldLen - 1 do
      begin
        sp := PByte(NativeInt(b.FData) + k);
        dp := PByte(NativeInt(b.FData) + k + delta);
        dp^ := sp^;
      end;
      b.FLen := oldLen + delta;
    end;
  end;
  for k := 0 to src.FLen - 1 do
  begin
    sp := PByte(NativeInt(src.FData) + k);
    dp := PByte(NativeInt(b.FData) + lo + k);
    dp^ := sp^;
  end;
end;

{ `b[lo:hi] = v` where the RHS is a VARIANT holding bytes — e.g. a value fetched
  from a dict (`mem[a:b] = snapshot["blk"]`). Unbox to the TPyBytes it holds;
  without this the variant's 16 bytes were read as a TPyBytes header and the
  length check saw garbage ("length mismatch (expected 8, got <garbage>)"). }
procedure pybytes_setslice_v(b: TPyBytes; lo, hi: Integer; const src: Variant);
var o: TObject;
begin
  if pyvartag(src) = 7 then
  begin
    o := TObject(pyvarobj(src));
    if o is TPyBytes then begin pybytes_setslice(b, lo, hi, TPyBytes(o)); Exit; end;
  end;
  raise TypeError.Create('byte slice assignment requires bytes');
end;

{ Little-endian, two's complement — the same layout the machine already uses,
  so the loop is a plain byte peel rather than anything arithmetic. Python
  raises OverflowError when the value does not fit in n bytes; that check is
  kept, because uforth stores fixed-width Forth cells and a silent truncation
  there would corrupt the data space rather than fail. }
function pyint_to_bytes(v: Int64; n: Integer; signed: Boolean): TPyBytes;
var k: Integer; p: PByte; u: Int64; fits: Boolean;
begin
  if n < 0 then n := 0;
  if (not signed) and (v < 0) then
  begin
    { A negative Int64 given to an UNSIGNED conversion: NilPy ints are 64-bit but
      Python's are unbounded, so a value like 0xFFFFFFFFFFFFFFFF (2^64-1 in
      Python) lands here as -1. For a field >= 8 bytes wide the low 8 bytes ARE
      that unsigned value's bytes (two's complement == the reinterpreted
      magnitude), zero-extended above byte 7 since the value is < 2^64 — so it
      encodes identically to Python. Only a field narrower than the 64-bit
      pattern genuinely overflows. }
    if n < 8 then
    begin
      raise OverflowError.Create('can''t convert negative int to unsigned');
    end;
    Result := TPyBytes.Create(n);
    u := v;
    for k := 0 to n - 1 do
    begin
      p := PByte(NativeInt(Result.FData) + k);
      if k < 8 then p^ := u and 255 else p^ := 0;
      u := u shr 8;
    end;
    Exit;
  end;
  { n >= 8 always fits an Int64; below that, check the value's range }
  fits := n >= 8;
  if not fits then
  begin
    if signed then
      fits := (v >= -(Int64(1) shl (8 * n - 1))) and (v < (Int64(1) shl (8 * n - 1)))
    else
      fits := v < (Int64(1) shl (8 * n));
  end;
  if not fits then
  begin
    raise OverflowError.Create('int too big to convert');
  end;
  Result := TPyBytes.Create(n);
  u := v;
  for k := 0 to n - 1 do
  begin
    p := PByte(NativeInt(Result.FData) + k);
    p^ := u and 255;
    u := u shr 8;   { arithmetic shift: sign bits fill, which is what two's
                      complement little-endian wants for a negative value }
  end;
end;

function pyint_from_bytes(b: TPyBytes; signed: Boolean): Int64;
var k: Integer; p: PByte; acc: Int64;
begin
  acc := 0;
  { high byte down to low, so each step is one shift-in }
  for k := b.FLen - 1 downto 0 do
  begin
    p := PByte(NativeInt(b.FData) + k);
    acc := (acc shl 8) or p^;
  end;
  { sign-extend from the top bit of the HIGHEST byte present }
  if signed and (b.FLen > 0) and (b.FLen < 8) then
  begin
    p := PByte(NativeInt(b.FData) + (b.FLen - 1));
    if (p^ and 128) <> 0 then
      acc := acc - (Int64(1) shl (8 * b.FLen));
  end;
  Result := acc;
end;

{ ---- exact decimal core: A COPY of lib/rtl/sysutils.pas ------------------

  The next ~420 lines are `ExDecMul` / `ExDecSplit` / `ExDecOfMant` /
  `ExDecDigits` / `ExDecRound` and the correctly-rounded parser closure
  (`ExDecCmp` .. `StrToFloatDef`) from `lib/rtl/sysutils.pas`, renamed with a
  `Py` prefix and otherwise UNCHANGED — the only edit is `IntToStr` becoming
  `StrInt(x, 0)`, which is this layer's spelling.

  It is a copy on purpose, and the reason is not layering purity. A builtin
  unit may not `uses sysutils` (NilPy's unit scope is flat, so every sysutils
  name would collide in every NilPy program), and moving the core DOWN into a
  shared builtin unit was rejected because library source has to stay
  STEPPABLE: stepping into `FloatToStr` should not walk you out of
  `sysutils.pas` into a unit you never asked about
  (decide-nilpy-where-the-exact-decimal-float-core-lives, option B).

  Reimplementing it was explicitly rejected too. Copy proven code; a second
  exact-decimal implementation is this repo's recurring failure mode — two
  readers of one construct that disagree — in its most numeric form.

  It also does not ADD a disagreeing implementation, it removes one:
  `pyfloat_parse` used to reconstruct with float arithmetic and was measurably
  wrong (`float("1e308")`, `float("0.3333333333333333")` and
  `float("2.2250738585072011e-308")` all differed from pxx's own literals). It
  is now a thin wrapper over the copy below.

  ANTI-DRIFT: `test/test_nilpy_float_repr.npy` and its Pascal sibling run both
  implementations over the same table with CPython as the oracle, so a
  divergence between this copy and sysutils' original is a test failure rather
  than a discovery. Change one, change both. }


{ ---- exact decimal expansion of a Double ---------------------------------

  Every finite double IS a finite decimal, exactly. value = mant * 2^exp2 with
  mant a 53-bit integer, and 2^-k = 5^k * 10^-k, so the exact decimal form is
  the integer mant*5^k with the point pushed k places left (k = -exp2). For
  exp2 >= 0 it is the plain integer mant*2^exp2. No approximation enters, so
  every digit produced is a real digit of the value — which is exactly what the
  normalise-in-doubles path in FloatToStrSig cannot do past 15, and why that
  routine caps there.

  Worst case is a denormal at exp2 = -1074: 5^1074 is 751 digits, times a
  16-digit mantissa, so 767 digits. Those live little-endian in limbs of nine
  decimal digits (base 10^9), grown by repeated multiply-by-small. Two chunk
  sizes do the scaling: 5^13 and 2^30, the largest powers whose per-limb
  product stays inside Int64 (10^9 * 5^13 is 1.2e18, well under 9.2e18). That
  turns the worst case into ~83 passes over ~86 limbs instead of 1074 passes
  over 767 single digits.

  Base 10^9 rather than one digit per byte is a ~9x cut in the inner loop, and
  it is the reason the exact path is affordable on BOTH sides: the decimal ->
  double search below expands a candidate per comparison, so expansion cost is
  multiplied by the search, not paid once. }
const
  PXX_PYEXDEC_LIMBS = 96;           { 9 digits each; 767 digits needs 86 }
  PXX_PYEXDEC_BASE  = 1000000000;   { 10^9 }
  PXX_PYEXDEC_P5_13 = 1220703125;   { 5^13 }
  PXX_PYEXDEC_P2_30 = 1073741824;   { 2^30 }
type
  PyTExDecBuf   = array[0..PXX_PYEXDEC_LIMBS - 1] of Int64;
  PyPExDecInt64 = ^Int64;

{ buf := buf * f. f is small enough that limb*f + carry cannot leave Int64. }
procedure PyExDecMul(var buf: PyTExDecBuf; var n: Integer; f: Int64);
var i: Integer; t, carry: Int64;
begin
  carry := 0;
  for i := 0 to n - 1 do
  begin
    t := buf[i] * f + carry;
    buf[i] := t mod PXX_PYEXDEC_BASE;
    carry := t div PXX_PYEXDEC_BASE;
  end;
  while (carry > 0) and (n < PXX_PYEXDEC_LIMBS) do
  begin
    buf[n] := carry mod PXX_PYEXDEC_BASE;
    carry := carry div PXX_PYEXDEC_BASE;
    n := n + 1;
  end;
end;

{ Split a finite value into mant * 2^exp2 with mant an integer. Reads the
  IEEE-754 fields directly; a denormal carries no implicit leading bit. }
procedure PyExDecSplit(value: Double; var mant: Int64; var exp2: Integer);
var bits, frac: Int64; be: Integer;
begin
  bits := PyPExDecInt64(@value)^;
  be   := Integer((bits shr 52) and $7FF);
  frac := bits and ((Int64(1) shl 52) - 1);
  if be = 0 then
  begin
    mant := frac;
    exp2 := -1074;
  end
  else
  begin
    mant := frac or (Int64(1) shl 52);
    exp2 := be - 1075;
  end;
end;

{ Exact digits of mant * 2^exp2: ds holds them most significant first with no
  leading zero, and decExp is the power of ten the first digit stands for (so
  267.5 gives '2675' and decExp = 2). Taking mant/exp2 rather than a Double is
  deliberate — the decimal->double side needs the exact expansion of MIDPOINTS
  between adjacent doubles, and a midpoint needs 54 bits, so it is not a
  Double. mant = 0 yields '0'. }
procedure PyExDecOfMant(mant: Int64; exp2: Integer;
                      var ds: AnsiString; var decExp: Integer);
var
  buf: PyTExDecBuf;
  n, i, k, fracDigits: Integer;
  lp: AnsiString;
begin
  n := 0;
  while mant > 0 do
  begin
    buf[n] := mant mod PXX_PYEXDEC_BASE;
    mant := mant div PXX_PYEXDEC_BASE;
    n := n + 1;
  end;
  if n = 0 then begin buf[0] := 0; n := 1; end;
  fracDigits := 0;
  if exp2 >= 0 then
  begin
    k := exp2;
    while k >= 30 do begin PyExDecMul(buf, n, PXX_PYEXDEC_P2_30); k := k - 30; end;
    while k > 0 do begin PyExDecMul(buf, n, 2); k := k - 1; end;
  end
  else
  begin
    k := -exp2;
    fracDigits := k;
    while k >= 13 do begin PyExDecMul(buf, n, PXX_PYEXDEC_P5_13); k := k - 13; end;
    while k > 0 do begin PyExDecMul(buf, n, 5); k := k - 1; end;
  end;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  { top limb unpadded (that is what drops the leading zeros), the rest padded
    to the full nine so limb boundaries do not swallow interior zeros }
  ds := StrInt(buf[n - 1], 0);
  for i := n - 2 downto 0 do
  begin
    lp := StrInt(buf[i], 0);
    while Length(lp) < 9 do lp := '0' + lp;
    ds := ds + lp;
  end;
  decExp := Length(ds) - 1 - fracDigits;
end;

{ Exact digits of a finite Double, sign ignored. }
procedure PyExDecDigits(value: Double; var ds: AnsiString; var decExp: Integer);
var mant: Int64; exp2: Integer;
begin
  PyExDecSplit(value, mant, exp2);
  PyExDecOfMant(mant, exp2, ds, decExp);
end;

{ Round an exact digit string to sig digits, half-to-EVEN on the exact
  remainder (glibc's %.*g rule — and the remainder here really is exact, so
  the tie case is a genuine tie rather than an artifact of scaling). A carry
  out of the leading digit (999 -> 100) moves the decimal exponent. }
procedure PyExDecRound(var ds: AnsiString; var decExp: Integer; sig: Integer);
var i, c: Integer; up, rest: Boolean;
begin
  if Length(ds) <= sig then Exit;
  up := False;
  if ds[sig + 1] > '5' then up := True
  else if ds[sig + 1] = '5' then
  begin
    rest := False;
    for i := sig + 2 to Length(ds) do
      if ds[i] <> '0' then begin rest := True; break; end;
    if rest then up := True
    else up := ((Ord(ds[sig]) - Ord('0')) mod 2) = 1;
  end;
  ds := Copy(ds, 1, sig);
  if up then
  begin
    i := sig;
    while i >= 1 do
    begin
      c := Ord(ds[i]) - Ord('0') + 1;
      if c < 10 then begin ds[i] := Chr(Ord('0') + c); break; end;
      ds[i] := '0';
      i := i - 1;
    end;
    if i = 0 then
    begin
      ds := '1' + Copy(ds, 1, sig - 1);
      decExp := decExp + 1;
    end;
  end;
end;

{ ---- decimal -> double, correctly rounded --------------------------------

  The old parser accumulated in doubles: one rounding per fractional digit, and
  10^e built by e successive multiplies (e up to 308, so the power itself was
  tens of ULP off). That is at most an approximation of the nearest double, and
  it is why exact 17-digit forms of 1/3, 1e-300, DBL_MAX and the denormals did
  not read back. Correct rounding means landing on the nearest double every
  time, so the value is reconstructed with the exact expansion above rather
  than with float arithmetic. }

{ Compare two exact decimals held as (digits, decExp) — digits most significant
  first with no leading zero, decExp the power of ten the first digit stands
  for. Both must be positive and nonzero. Shorter operands read as zero-padded,
  so '25'/1 and '250'/1 compare equal (both are 25). }
function PyExDecCmp(const a: AnsiString; ae: Integer;
                  const b: AnsiString; be: Integer): Integer;
var i, n: Integer; ca, cb: Char;
begin
  if ae <> be then
  begin
    if ae < be then Result := -1 else Result := 1;
    Exit;
  end;
  n := Length(a);
  if Length(b) > n then n := Length(b);
  for i := 1 to n do
  begin
    if i <= Length(a) then ca := a[i] else ca := '0';
    if i <= Length(b) then cb := b[i] else cb := '0';
    if ca <> cb then
    begin
      if ca < cb then Result := -1 else Result := 1;
      Exit;
    end;
  end;
  Result := 0;
end;

function PyExDecBitsToDouble(b: Int64): Double;
type PyPExDecDouble = ^Double;
begin
  Result := PyPExDecDouble(@b)^;
end;

function PyExDecDoubleToBits(d: Double): Int64;
begin
  Result := PyPExDecInt64(@d)^;
end;

{ A cheap approximation of int(ds) * 10^expo. This is float arithmetic and is
  therefore wrong by some ULP — it is NEVER trusted, only used to seed the
  bracket for the exact search, which then proves the answer. Getting it close
  is purely a speed matter: the search costs one exact expansion per step, and
  seeding turns a 63-step search over the whole bit range into a handful of
  steps around the right answer. Powers of ten are applied by binary splitting
  (at most nine multiplies) rather than one per decade. }
function PyExDecEstimate(const ds: AnsiString; nd, expo: Integer): Double;
var
  sig: Int64;
  i, k, e: Integer;
  w: Double;
  p10: array[0..8] of Double;
begin
  k := nd;
  if k > 17 then k := 17;
  sig := 0;
  for i := 1 to k do sig := sig * 10 + Int64(Ord(ds[i]) - Ord('0'));
  { digits we did not take are absorbed into the exponent }
  e := expo + (nd - k);
  w := sig * 1.0;
  p10[0] := 1.0e1;   p10[1] := 1.0e2;   p10[2] := 1.0e4;   p10[3] := 1.0e8;
  p10[4] := 1.0e16;  p10[5] := 1.0e32;  p10[6] := 1.0e64;  p10[7] := 1.0e128;
  p10[8] := 1.0e256;
  { the table spans 2^9-1 = 511 decades; anything past that is far outside the
    double range and only has to land on the correct side of it }
  if e > 511 then e := 511;
  if e < -511 then e := -511;
  if e > 0 then
  begin
    for i := 0 to 8 do
      if (e and (1 shl i)) <> 0 then w := w * p10[i];
  end
  else if e < 0 then
  begin
    k := -e;
    { divide rather than multiply by a negative power: keeps the intermediate
      from overflowing on the way down }
    for i := 0 to 8 do
      if (k and (1 shl i)) <> 0 then w := w / p10[i];
  end;
  Result := w;
end;

{ The double nearest to the positive decimal (ds, decExp), correctly rounded,
  ties to even.

  For positive doubles the IEEE bit pattern increases monotonically with the
  value, so "largest double <= D" is a plain ordered search over the bit
  pattern — 63 steps, each comparing D against the candidate's EXACT decimal
  expansion. There is no estimate here that could be wrong by an unknown number
  of ULP; the search cannot land anywhere but the right pair of neighbours.

  Then one decision between that double c and the next one up. Their midpoint is
  exactly (2*mant + 1) * 2^(exp2 - 1) — one formula that holds everywhere,
  including across a power-of-two boundary (where c = (2^53-1)*2^e and the next
  is 2^52*2^(e+1)) and across the denormal/normal boundary, because incrementing
  the bit pattern is exactly what both of those transitions are. The midpoint
  needs 54 bits, which is why the expansion above takes a mantissa rather than a
  Double.

  Out-of-range inputs fall out correctly rather than needing a guard: below the
  smallest denormal the search settles on bits 0 and the midpoint test rounds to
  zero, and above DBL_MAX it settles on DBL_MAX whose "next up" bit pattern is
  +Inf. }
function PyExDecNearest(const ds: AnsiString; decExp, nd, expo: Integer): Double;
var
  lo, hi, mid, mant, maxbits, step, eb: Int64;
  exp2, cmp: Integer;
  cds, mds: AnsiString;
  cexp, mexp: Integer;
  c, est: Double;

  { sign of exact(bits) - D }
  function CmpBits(b: Int64): Integer;
  var d: Double; xs: AnsiString; xe: Integer;
  begin
    d := PyExDecBitsToDouble(b);
    if b = 0 then begin CmpBits := -1; Exit; end;   { 0 < D, D is positive }
    PyExDecDigits(d, xs, xe);
    CmpBits := PyExDecCmp(xs, xe, ds, decExp);
  end;

begin
  { DBL_MAX = biased exponent 2046, mantissa all ones }
  maxbits := (Int64(2046) shl 52) or ((Int64(1) shl 52) - 1);

  { Seed from the float estimate, then widen by doubling steps until the
    bracket provably straddles D. The estimate's error is never assumed —
    if it is wildly wrong the doubling simply runs until it reaches the ends,
    which is the unseeded search and still correct. }
  est := PyExDecEstimate(ds, nd, expo);
  if (est <> est) or (est >= 1.7976931348623157e308) then eb := maxbits
  else if est <= 0.0 then eb := 0
  else
  begin
    eb := PyExDecDoubleToBits(est);
    if eb < 0 then eb := 0;
    if eb > maxbits then eb := maxbits;
  end;

  lo := eb;
  step := 1;
  while (lo > 0) and (CmpBits(lo) > 0) do
  begin
    lo := lo - step;
    if lo < 0 then lo := 0;
    step := step * 2;
  end;

  hi := eb;
  step := 1;
  while (hi < maxbits) and (CmpBits(hi) < 0) do
  begin
    hi := hi + step;
    if hi > maxbits then hi := maxbits;
    step := step * 2;
  end;

  { largest bit pattern whose exact value is <= D }
  while lo < hi do
  begin
    mid := lo + (hi - lo + 1) div 2;
    if CmpBits(mid) <= 0 then lo := mid else hi := mid - 1;
  end;

  c := PyExDecBitsToDouble(lo);
  if lo <> 0 then
  begin
    PyExDecDigits(c, cds, cexp);
    if PyExDecCmp(cds, cexp, ds, decExp) = 0 then begin Result := c; Exit; end;
  end;

  PyExDecSplit(c, mant, exp2);
  PyExDecOfMant(2 * mant + 1, exp2 - 1, mds, mexp);
  cmp := PyExDecCmp(ds, decExp, mds, mexp);
  if cmp > 0 then Result := PyExDecBitsToDouble(lo + 1)
  else if cmp < 0 then Result := c
  else if (mant mod 2) = 0 then Result := c          { exact tie -> even }
  else Result := PyExDecBitsToDouble(lo + 1);
end;

function PyStrToFloatDef(const s: AnsiString; def: Double): Double;
const
  { every digit past this is beyond any midpoint's ~1080, so it can only break
    a tie — which the sticky digit below does, without unbounded strings }
  PyEXDEC_INMAX = 1200;
var i, digit, e, k: Integer; c: Char; neg, eneg: Boolean;
    w, p: Double; in_frac, started, estarted, sticky: Boolean;
    ds: AnsiString; fracCount, nd, expo, lead: Integer; sig: Int64;
begin
  Result := def;
  i := 1; neg := False; w := 0.0; in_frac := False; started := False;
  ds := ''; fracCount := 0; sticky := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then neg := True;
    i := i + 1;
  end;
  e := 0; eneg := False; estarted := True;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      digit := Ord(c) - Ord('0');
      if in_frac then fracCount := fracCount + 1;
      { keep the digits themselves; the value is reconstructed exactly below }
      if Length(ds) < PyEXDEC_INMAX then
      begin
        if (ds <> '') or (digit <> 0) then ds := ds + c;   { drop leading zeros }
      end
      else if digit <> 0 then
        sticky := True;
      started := True;
      i := i + 1;
    end
    else if (c = '.') and (not in_frac) then
    begin
      in_frac := True;
      i := i + 1;
    end
    else if ((c = 'e') or (c = 'E')) and started then
    begin
      { exponent: [+|-]digits to the END of the string ('1e0', '1.2E+003') }
      i := i + 1;
      if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
      begin
        if s[i] = '-' then eneg := True;
        i := i + 1;
      end;
      estarted := False;
      while i <= Length(s) do
      begin
        c := s[i];
        if (c < '0') or (c > '9') then Exit;
        e := e * 10 + (Ord(c) - Ord('0'));
        estarted := True;
        i := i + 1;
      end;
      if not estarted then Exit;
    end
    else
      Exit;
  end;
  if not (started and estarted) then Exit;

  { a dropped nonzero digit past the cap makes the value strictly greater than
    the kept prefix — exactly what a sticky bit is for, and enough to settle any
    tie, since a midpoint has far fewer significant digits than the cap }
  if sticky then ds := ds + '1';

  if ds = '' then                       { all digits were zero }
  begin
    w := 0.0;
    if neg then w := -w;                { preserves -0.0 }
    Result := w;
    Exit;
  end;

  if eneg then e := -e;
  { value = int(ds) * 10^expo }
  expo := e - fracCount;
  { trailing zeros move to the exponent — cheaper, and widens the fast path }
  nd := Length(ds);
  while (nd > 1) and (ds[nd] = '0') do begin nd := nd - 1; expo := expo + 1; end;
  ds := Copy(ds, 1, nd);

  { Fast path (Clinger): with the significand under 2^53 and |expo| <= 22, both
    the significand and 10^|expo| are exactly representable, so a single
    multiply or divide is a single rounding and is therefore already the
    correctly rounded result. 10^k is built by repeated multiplication, which
    is exact up to 10^22 — deliberately not a table of literals, since parsing
    those literals is the very thing being fixed here. Covers the overwhelming
    majority of real input (JSON numbers and the like). }
  if (nd <= 15) and (expo >= -22) and (expo <= 22) then
  begin
    sig := 0;
    for k := 1 to nd do sig := sig * 10 + Int64(Ord(ds[k]) - Ord('0'));
    w := sig * 1.0;
    p := 1.0;
    if expo >= 0 then
    begin
      for k := 1 to expo do p := p * 10.0;
      w := w * p;
    end
    else
    begin
      for k := 1 to -expo do p := p * 10.0;
      w := w / p;
    end;
    if neg then w := -w;
    Result := w;
    Exit;
  end;

  { Slow path: exact reconstruction. decExp is the power of ten the first digit
    stands for. }
  lead := nd - 1 + expo;
  w := PyExDecNearest(ds, lead, nd, expo);
  if neg then w := -w;
  Result := w;
end;

{ Python's two-argument round(x, n), on the EXACT decimal value of the double.

  It lives down here, past the exact-decimal core, because that is what it is
  built on — the previous version sat up with the other numeric builtins and
  scaled in doubles, which is precisely the thing that cannot work:

    round(2.675, 2)  CPython 2.67   pxx 2.68
    round(2.665, 2)  CPython 2.67   pxx 2.66

  `2.675 * 100` is exactly 267.5 and `2.665 * 100` is exactly 266.5, in pxx
  and in CPython alike, so after scaling BOTH look like a tie and no
  tie-breaking rule can separate them. The information that decides them is in
  the double's exact value, which the scale destroyed:

    2.675 = 2.674999999999999822...  -> below the half, rounds DOWN to 2.67
    2.665 = 2.665000000000000035...  -> above the half, rounds UP   to 2.67

  Nor does a 17-significant-digit approximation suffice: 2.665 renders as
  exactly `2.6650000000000000` at 17 digits, still ambiguous at the tie
  (bug-nilpy-round-ndigits-half-up-and-ignores-negative-ndigits recorded both
  facts and left the case open pending this core).

  So: expand the double exactly, round the digit string half-to-EVEN on the
  exact remainder, and read the result back with the correctly-rounded parser
  to land on the nearest double. Every step is exact except the final read,
  which is correctly rounded — the same shape CPython uses.

  n is a decimal PLACE count, so the digit to keep down to stands for 10^-n;
  the first digit stands for 10^decExp, which makes the significant-digit
  count decExp + n + 1. Non-positive means the whole value sits below the
  rounding position: it rounds to zero, except that sig = 0 can still carry up
  to one unit in the last place (round(0.6, 0) is 1.0). At sig = 0 the digit
  before the rounding position is an implicit 0, which is even, so an exact
  tie goes to zero — round(0.5, 0) is 0.0 in Python, and this gets that for
  the same reason CPython does rather than by a special case. }
function pyround_n(x: Double; n: Integer): Double;
var
  av, r: Double;
  ds, s: AnsiString;
  decExp, sig, i: Integer;
  neg, up, rest: Boolean;
begin
  { NaN, the infinities and both zeros round to themselves. Zero is returned
    unchanged rather than rebuilt so -0.0 keeps its sign, which a comparison
    cannot preserve (-0.0 = 0.0 is True). }
  av := x;
  if av < 0 then av := -av;
  if (x <> x) or (x = 0) or (av > 1.7976931348623157e308) then
  begin
    Result := x;
    Exit;
  end;
  neg := PyExDecDoubleToBits(x) < 0;
  PyExDecDigits(av, ds, decExp);
  sig := decExp + n + 1;
  if sig <= 0 then
  begin
    up := False;
    if sig = 0 then
    begin
      { compare the value against half a unit in the last kept place }
      if ds[1] > '5' then up := True
      else if ds[1] = '5' then
      begin
        rest := False;
        for i := 2 to Length(ds) do
          if ds[i] <> '0' then begin rest := True; break; end;
        up := rest;      { an exact tie goes to the even 0 }
      end;
    end;
    if up then begin ds := '1'; decExp := -n; end
    else begin Result := 0.0; if neg then Result := -Result; Exit; end;
  end
  else
    PyExDecRound(ds, decExp, sig);
  { lay the rounded digits out as plain decimal text: ds stands for
    0.ds * 10^(decExp+1), so the point falls decExp+1 digits in }
  if decExp >= 0 then
  begin
    if Length(ds) <= decExp then
    begin
      s := ds;
      for i := Length(ds) to decExp do s := s + '0';
    end
    else if Length(ds) = decExp + 1 then
      s := ds
    else
      s := Copy(ds, 1, decExp + 1) + '.' +
           Copy(ds, decExp + 2, Length(ds) - decExp - 1);
  end
  else
  begin
    s := '0.';
    for i := 1 to -decExp - 1 do s := s + '0';
    s := s + ds;
  end;
  r := PyStrToFloatDef(s, 0.0);
  if neg then r := -r;
  Result := r;
end;

function pyfloat_any(const v: Variant): Double;
var t: Int64;
begin
  t := pyvartag(v);
  if (t = 5) or (t = 6) then pyfloat_any := pyfloat_parse(pystr_of(v))
  else pyfloat_any := pyvar_to_float(v);
end;

function pyfloat_ofint(v: Int64): Double;
begin
  Result := v;
end;

function pyfloat_parse(const s: AnsiString): Double;
var i, n, digits: Integer; seenDot, seenExp: Boolean;
    body, lowbody, clean: AnsiString;
    infv: Double;
begin
  body := s;
  i := 1; n := Length(body);
  while (i <= n) and ((body[i] = ' ') or (body[i] = #9)) do Inc(i);
  while (n >= i) and ((body[n] = ' ') or (body[n] = #9)) do Dec(n);
  body := Copy(body, i, n - i + 1);
  if Length(body) = 0 then
    raise ValueError.Create('could not convert string to float');

  { Python accepts the SPECIAL float spellings, case-insensitively and with an
    optional sign: inf, infinity, nan. float("inf") raised
    'could not convert string to float' here, which is wrong — it is how you
    write an unbounded sentinel, and the idiom `best = float("inf")` is
    everywhere (bug-nilpy-float-of-inf-nan-string-raises). Checked before the
    digit scan, since the scan has no notion of them. }
  lowbody := pystr_lower(body);
  if (lowbody = 'inf') or (lowbody = '+inf') or (lowbody = 'infinity') or
     (lowbody = '+infinity') or (lowbody = '-inf') or (lowbody = '-infinity') or
     (lowbody = 'nan') or (lowbody = '+nan') or (lowbody = '-nan') then
  begin
    { No literal spells these, so build them by overflow: 1e308*10 is +Inf and
      Inf-Inf is NaN. Verified to produce them rather than trap on this target
      (float exceptions are masked; see feature-float-exception-mask-control). }
    infv := 1.0e308;
    infv := infv * 10.0;
    if (lowbody = 'nan') or (lowbody = '+nan') or (lowbody = '-nan') then
      Result := infv - infv
    else if (lowbody = '-inf') or (lowbody = '-infinity') then
      Result := -infv
    else
      Result := infv;
    Exit;
  end;

  { The loop below VALIDATES — Python's own rules about where a sign, a point,
    an exponent and an underscore may appear, and which spellings raise
    ValueError. It no longer computes the value: accumulating digit by digit in
    doubles is one rounding per digit plus a 10^e built by e multiplies, which
    is why float("1e308"), float("0.3333333333333333") and
    float("2.2250738585072011e-308") all disagreed with pxx's own literals for
    the same numbers. The accepted text is handed to the correctly-rounded
    parser instead (bug-nilpy-float-of-a-string-is-not-correctly-rounded). }
  clean := '';
  for i := 1 to Length(body) do
    if body[i] <> '_' then clean := clean + body[i];
  seenDot := False; seenExp := False; digits := 0;
  i := 1;
  if (body[i] = '-') or (body[i] = '+') then Inc(i);
  while i <= Length(body) do
  begin
    if body[i] = '_' then begin Inc(i); Continue; end;
    if (body[i] = '.') and not seenDot and not seenExp then
    begin
      seenDot := True;
      Inc(i);
      Continue;
    end;
    if ((body[i] = 'e') or (body[i] = 'E')) and not seenExp and (digits > 0) then
    begin
      seenExp := True;
      Inc(i);
      if (i <= Length(body)) and ((body[i] = '-') or (body[i] = '+')) then
        Inc(i);
      if (i > Length(body)) or (body[i] < '0') or (body[i] > '9') then
        raise ValueError.Create('could not convert string to float');
      while (i <= Length(body)) and (body[i] >= '0') and (body[i] <= '9') do
        Inc(i);
      Continue;
    end;
    if (body[i] < '0') or (body[i] > '9') then
      raise ValueError.Create('could not convert string to float');
    Inc(digits);
    Inc(i);
  end;
  if digits = 0 then
    raise ValueError.Create('could not convert string to float');
  Result := PyStrToFloatDef(clean, 0.0);
end;

function PyDigitVal(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Result := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'z') then Result := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'Z') then Result := Ord(c) - Ord('A') + 10
  else Result := -1;
end;

function pyint_parse(const s: AnsiString; base: Integer): Int64;
var i, n, d: Integer; neg: Boolean; acc: Int64; body: AnsiString;
begin
  body := s;
  { Python strips surrounding whitespace before parsing }
  i := 1; n := Length(body);
  while (i <= n) and ((body[i] = ' ') or (body[i] = #9)) do Inc(i);
  while (n >= i) and ((body[n] = ' ') or (body[n] = #9)) do Dec(n);
  body := Copy(body, i, n - i + 1);

  neg := False;
  if (Length(body) > 0) and ((body[1] = '-') or (body[1] = '+')) then
  begin
    neg := body[1] = '-';
    body := Copy(body, 2, Length(body) - 1);
  end;

  { base 0 means "infer from the prefix", and an explicit base may also carry
    the matching prefix (int('0xff', 16) is legal in Python) }
  if (Length(body) > 1) and (body[1] = '0') then
  begin
    d := -1;
    case body[2] of
      'x', 'X': d := 16;
      'o', 'O': d := 8;
      'b', 'B': d := 2;
    end;
    if (d > 0) and ((base = 0) or (base = d)) then
    begin
      base := d;
      body := Copy(body, 3, Length(body) - 2);
    end;
  end;
  if base = 0 then base := 10;
  if (base < 2) or (base > 36) then
    raise ValueError.Create('int() base must be >= 2 and <= 36');

  { an EMPTY digit run is an error, not zero — int('') and int('0x') both raise }
  if Length(body) = 0 then
    raise ValueError.Create('invalid literal for int()');

  acc := 0;
  for i := 1 to Length(body) do
  begin
    if body[i] = '_' then Continue;      { Python allows digit separators }
    d := PyDigitVal(body[i]);
    if (d < 0) or (d >= base) then
      raise ValueError.Create('invalid literal for int()');
    acc := acc * base + d;
  end;
  if neg then acc := -acc;
  Result := acc;
end;

constructor Exception.Create(const m: AnsiString);
begin
  msg := m;
end;

{ One `array of const` element as a string / as an integer's decimal text. The
  same shape as sysutils' FmtArgStr/FmtArgInt, duplicated rather than shared
  because pylib must not pull sysutils in. }
function pyvarrec_str(const v: TVarRec): AnsiString;
var pc: PChar; i: Integer;
begin
  Result := '';
  case v.VType of
    vtAnsiString, vtPChar:
      begin
        if v.VType = vtAnsiString then pc := PChar(v.VAnsiString) else pc := PChar(v.VPChar);
        if pc <> nil then
        begin
          i := 0;
          while pc[i] <> #0 do begin Result := Result + pc[i]; Inc(i); end;
        end;
      end;
    vtChar:    Result := v.VChar;
    vtInteger: Result := pystr_of(Int64(v.VInteger));
    vtInt64:   Result := pystr_of(v.VInt64^);
    vtBoolean: if v.VBoolean then Result := 'True' else Result := 'False';
  end;
end;

function pyvarrec_int_str(const v: TVarRec): AnsiString;
begin
  case v.VType of
    vtInt64:   Result := pystr_of(v.VInt64^);
    vtBoolean: Result := pystr_of(Int64(Ord(v.VBoolean)));
    vtChar:    Result := pystr_of(Int64(Ord(v.VChar)));
  else
    Result := pystr_of(Int64(v.VInteger));
  end;
end;

{ sysutils' CreateFmt on the shadowing class. It cannot simply call Format():
  pylib is pulled into every .npy and must not depend on sysutils (which is what
  drags the whole RTL in), so the substitution is done here over the same
  `array of const` FPC passes. The subset is what the RTL's own raise sites
  actually use — %s, %d and %% — and an unsupported spec is left VERBATIM rather
  than guessed at, so a wrong message is visible as a stray %spec instead of
  silently losing its argument. }
constructor Exception.CreateFmt(const m: AnsiString; const args: array of const);
var i, ai: Integer; c: Char; outS: AnsiString;
begin
  outS := '';
  ai := 0;
  i := 1;
  while i <= Length(m) do
  begin
    c := m[i];
    if (c = '%') and (i < Length(m)) then
    begin
      c := m[i + 1];
      if c = '%' then
      begin
        outS := outS + '%';
        i := i + 2;
        Continue;
      end;
      if ((c = 's') or (c = 'd')) and (ai <= High(args)) then
      begin
        if c = 's' then outS := outS + pyvarrec_str(args[ai])
        else outS := outS + pyvarrec_int_str(args[ai]);
        ai := ai + 1;
        i := i + 2;
        Continue;
      end;
    end;
    outS := outS + m[i];
    i := i + 1;
  end;
  msg := outS;
  FHelpContext := 0;
end;

function pyos_path_isabs(const p: AnsiString): Boolean;
begin
  Result := (Length(p) > 0) and (p[1] = '/');
end;

function pyos_path_join(const a: AnsiString; const b: AnsiString): AnsiString;
begin
  { Python's join: an ABSOLUTE second component discards the first entirely,
    and an empty first component contributes nothing. }
  if pyos_path_isabs(b) then begin Result := b; Exit; end;
  if Length(a) = 0 then begin Result := b; Exit; end;
  if a[Length(a)] = '/' then Result := a + b
  else Result := a + '/' + b;
end;

function pyos_path_join(const a, b, c: AnsiString): AnsiString; overload;
begin
  Result := pyos_path_join(pyos_path_join(a, b), c);
end;

function pyos_path_join(const a, b, c, d: AnsiString): AnsiString; overload;
begin
  Result := pyos_path_join(pyos_path_join(pyos_path_join(a, b), c), d);
end;

function pyos_path_dirname(const p: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '';
  i := Length(p);
  while (i > 0) and (p[i] <> '/') do Dec(i);
  if i = 0 then Exit;              { no separator: dirname is empty }
  if i = 1 then begin Result := '/'; Exit; end;   { keep the root slash }
  Result := Copy(p, 1, i - 1);
end;

{ os.path.basename — everything after the last '/', or the whole string if
  there is none; a trailing '/' yields '' (matching CPython: dirname/basename
  always concatenate, with the separator, back to the original path).
  feature-nilpy-stdlib-coverage-gaps-measured. }
function pyos_path_basename(const p: AnsiString): AnsiString;
var i: Integer;
begin
  i := Length(p);
  while (i > 0) and (p[i] <> '/') do Dec(i);
  Result := Copy(p, i + 1, Length(p) - i);
end;

{ access(path, F_OK) — "does the name exist". Per-arch numbers, the same shape
  Randomize uses. aarch64 and riscv have no access(2), only faccessat(2), which
  takes AT_FDCWD (-100) as its first argument. A target with no number here
  reports False rather than guessing. }
function pyos_path_exists(const p: AnsiString): Boolean;
var r: Int64; cs: AnsiString;
begin
  Result := False;
  if Length(p) = 0 then Exit;
  cs := p + #0;
  Result := PyPalAccessOk(@cs[1]);
end;

function pyos_path_isdir(const p: AnsiString): Boolean;
{$ifdef CPUX86_64}
var cs: AnsiString; r: Int64; buf: array[0..143] of Byte;
{$endif}
begin
  Result := False;
{$ifdef CPUX86_64}
  if Length(p) = 0 then Exit;
  cs := p + #0;
  FillChar(buf[0], SizeOf(buf), 0);
  r := PyPalStat(@cs[1], @buf[0]);
  if r < 0 then Exit;                  { missing path is False, not an error }
  Result := ((PInt64(@buf[24])^ and $FFFFFFFF) and $F000) = $4000;   { S_IFDIR }
{$else}
  raise NotImplementedError.Create('os.path.isdir needs stat, which is x86-64 only here');
{$endif}
end;

function pyos_path_isfile(const p: AnsiString): Boolean;
{$ifdef CPUX86_64}
var cs: AnsiString; r: Int64; buf: array[0..143] of Byte;
{$endif}
begin
  Result := False;
{$ifdef CPUX86_64}
  if Length(p) = 0 then Exit;
  cs := p + #0;
  FillChar(buf[0], SizeOf(buf), 0);
  r := PyPalStat(@cs[1], @buf[0]);
  if r < 0 then Exit;
  Result := ((PInt64(@buf[24])^ and $FFFFFFFF) and $F000) = $8000;   { S_IFREG }
{$else}
  raise NotImplementedError.Create('os.path.isfile needs stat, which is x86-64 only here');
{$endif}
end;

function pyos_path_splitext(const p: AnsiString): TPyList;
var i, lastSlash, dot: Integer;
begin
  lastSlash := 0;
  for i := 1 to Length(p) do
    if p[i] = '/' then lastSlash := i;
  dot := 0;
  { scan only the BASENAME, and never accept its first character: CPython gives
    ('.bashrc', '') and ('a.b/c', '') }
  for i := lastSlash + 2 to Length(p) do
    if p[i] = '.' then dot := i;
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  if dot = 0 then
  begin
    Result.append(p);
    Result.append('');
  end
  else
  begin
    Result.append(Copy(p, 1, dot - 1));
    Result.append(Copy(p, dot, Length(p) - dot + 1));
  end;
end;

{ ---- environment ---------------------------------------------------------- }

var
  PyEnvLoaded: Boolean;
  PyEnvRaw: AnsiString;    { the whole file, NULs replaced by #1 separators }

procedure PyEnvLoad;
{ Read /proc/self/environ once. Linux-only, like pyos_getcwd's syscall set; on a
  target without it the table stays empty and every lookup is None, which is the
  honest answer for "this program has no environment". }
var buf: array[0..16383] of Char; fd, r, closed: Int64; i: Integer;
begin
  if PyEnvLoaded then Exit;
  PyEnvLoaded := True;
  PyEnvRaw := '';
  fd := PyPalOpen(PChar('/proc/self/environ'), PYPAL_O_RDONLY, 0);
  if fd < 0 then Exit;
  r := PyPalRead(fd, @buf[0], 16384);
  closed := PyPalClose(fd);
  if r <= 0 then Exit;
  for i := 0 to Integer(r) - 1 do
    if buf[i] = #0 then PyEnvRaw := PyEnvRaw + #1
    else PyEnvRaw := PyEnvRaw + buf[i];
  if Length(PyEnvRaw) > 0 then
    if PyEnvRaw[Length(PyEnvRaw)] <> #1 then PyEnvRaw := PyEnvRaw + #1;
end;

function PyEnvLookup(const name: AnsiString; var found: Boolean): AnsiString;
var i, j, recStart, n: Integer; matched: Boolean;
begin
  PyEnvLookup := '';
  found := False;
  if name = '' then Exit;
  PyEnvLoad;
  n := Length(name);
  recStart := 1;
  i := 1;
  while i <= Length(PyEnvRaw) do
  begin
    if PyEnvRaw[i] = #1 then
    begin
      { record is PyEnvRaw[recStart .. i-1] }
      if (i - recStart) > n then
        if PyEnvRaw[recStart + n] = '=' then
        begin
          matched := True;
          for j := 0 to n - 1 do
            if PyEnvRaw[recStart + j] <> name[j + 1] then begin matched := False; Break; end;
          if matched then
          begin
            for j := recStart + n + 1 to i - 1 do
              PyEnvLookup := PyEnvLookup + PyEnvRaw[j];
            found := True;
            Exit;
          end;
        end;
      recStart := i + 1;
    end;
    Inc(i);
  end;
end;

function pystr_reverse(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  for i := Length(s) downto 1 do r := r + s[i];
  pystr_reverse := r;
end;

function pyoptional_missing(const what: AnsiString): Variant;
begin
  pyoptional_missing := pynone;
  raise Exception.Create('this build has no ' + what
    + ': the import it came from could not be resolved, and the code guarding '
    + 'that (the flag its except-branch sets) let this call through anyway');
end;

function pyos_startfile(const path: AnsiString): Integer;
begin
  pyos_startfile := 0;
  raise Exception.Create('os.startfile is Windows-only and is not implemented; '
    + 'guard the call with sys.platform or use subprocess');
end;

function pyos_environ_get(const name: AnsiString): Variant;
var v: AnsiString; found: Boolean;
begin
  v := PyEnvLookup(name, found);
  if found then pyos_environ_get := v else pyos_environ_get := pynone;
end;

function pyos_environ_get_d(const name: AnsiString; const dflt: Variant): Variant;
var v: AnsiString; found: Boolean;
begin
  v := PyEnvLookup(name, found);
  if found then pyos_environ_get_d := v else pyos_environ_get_d := dflt;
end;

function pyos_getenv(const name: AnsiString): Variant;
begin
  pyos_getenv := pyos_environ_get(name);
end;

function pyos_getenv_d(const name: AnsiString; const dflt: Variant): Variant;
begin
  pyos_getenv_d := pyos_environ_get_d(name, dflt);
end;

function pyos_getcwd: AnsiString;
var buf: array[0..4095] of Char; r: Int64; i: Integer;
begin
  Result := '';
  buf[0] := #0;
  r := PyPalGetcwd(@buf[0], 4096);
  if r <= 0 then Exit;
  { the kernel returns a NUL-terminated path; length is read from the bytes so
    the differing return conventions (length vs pointer) do not matter }
  i := 0;
  while (i < 4096) and (buf[i] <> #0) do
  begin
    Result := Result + buf[i];
    Inc(i);
  end;
end;

{ Normalises '.' and '..' components after making the path absolute, which is
  what Python's abspath does (it does NOT resolve symlinks — that is realpath).
  Kept purely lexical for exactly that reason. }
function pyos_path_abspath(const p: AnsiString): AnsiString;
var full, comp, outp: AnsiString; i, j: Integer;
begin
  if pyos_path_isabs(p) then full := p
  else full := pyos_path_join(pyos_getcwd, p);
  outp := '';
  i := 1;
  while i <= Length(full) do
  begin
    while (i <= Length(full)) and (full[i] = '/') do Inc(i);
    j := i;
    while (j <= Length(full)) and (full[j] <> '/') do Inc(j);
    if j > i then
    begin
      comp := Copy(full, i, j - i);
      if comp = '..' then
        outp := pyos_path_dirname(outp)
      else if comp <> '.' then
      begin
        if (Length(outp) = 0) or (outp[Length(outp)] <> '/') then
          outp := outp + '/';
        outp := outp + comp;
      end;
    end;
    i := j;
  end;
  if Length(outp) = 0 then outp := '/';
  Result := outp;
end;

procedure pysys_exit(code: Integer);
begin
  Halt(code);
end;

{ openat(AT_FDCWD, path, O_RDONLY) + read to EOF + close, per-arch like
  pyos_path_exists. aarch64/riscv have only openat, so openat(AT_FDCWD=-100)
  is used everywhere for portability. }
function pyfile_slurp(const path: AnsiString; var ok: Boolean): AnsiString;
var cs: AnsiString; fd, nread: Int64; buf: array[0..8191] of Char; i: Integer;
    rlen, rcap: Integer;
begin
  Result := '';
  ok := False;
  rlen := 0; rcap := 0;
  if not PyPalSupported then Exit;   { unsupported target }
  cs := path + #0;
  fd := PyPalOpen(@cs[1], PYPAL_O_RDONLY, 0);
  if fd < 0 then Exit;
  nread := 8192;
  while nread = 8192 do
  begin
    nread := PyPalRead(fd, @buf[0], 8192);
    if nread > 0 then
    begin
      { Amortised-doubling append, NOT `Result := Result + buf[i]` per byte
        (that reallocated + recopied the whole string every byte — O(n^2) in
        file size, the dominant NilPy startup cost since it slurps the .UFO /
        pyeval stdlib). Grow capacity geometrically, blit each chunk in place. }
      if rlen + Integer(nread) > rcap then
      begin
        rcap := (rlen + Integer(nread)) * 2;
        if rcap < 16384 then rcap := 16384;
        SetLength(Result, rcap);   { SetLength preserves the existing rlen bytes }
      end;
      for i := 0 to Integer(nread) - 1 do
        Result[rlen + i + 1] := buf[i];
      rlen := rlen + Integer(nread);
    end;
  end;
  SetLength(Result, rlen);   { trim to the exact length read }
  nread := PyPalClose(fd);   { result discarded }
  ok := True;
end;

function pystdin_read(n: Integer): AnsiString;
var nread: Int64; buf: array[0..8191] of Char; i, want: Integer;
begin
  Result := '';
  if n <= 0 then Exit;
  if not PyPalSupported then Exit;
  want := n;
  if want > 8192 then want := 8192;
  nread := PyPalRead(0, @buf[0], want);
  if nread > 0 then
    for i := 0 to nread - 1 do Result := Result + buf[i];
end;

function pyos_remove(const path: AnsiString): Integer;
var cs: AnsiString; r: Int64;
begin
  Result := 0;
  if not PyPalSupported then Exit;
  cs := path + #0;
  r := PyPalUnlink(@cs[1]);
  { CPython os.remove RAISES on failure (deleting a missing file must be a
    catchable error — Forth-2012 DELETE-FILE expects a nonzero ior, not 0). }
  if r < 0 then
    raise FileNotFoundError.Create(path);
  Result := Integer(r);
end;

function pyos_rename(const src: AnsiString; const dst: AnsiString): Integer;
var cs, cd: AnsiString; r: Int64;
begin
  Result := 0;
  if not PyPalSupported then Exit;
  cs := src + #0; cd := dst + #0;
  r := PyPalRename(@cs[1], @cd[1]);
  { CPython os.rename raises on failure, same as os.remove above }
  if r < 0 then
    raise FileNotFoundError.Create(src);
  Result := Integer(r);
end;

function pyos_stat(const path: AnsiString): TPyStat;
var cs: AnsiString; r: Int64; buf: array[0..143] of Byte;
begin
  { Real stat on x86-64 (uforth FILE-STATUS: a missing file must raise a
    catchable OSError like CPython). Other targets keep the zeroed stub —
    their struct stat layouts differ and no gated caller observes the value. }
  Result := TPyStat.Create;
{$ifdef CPUX86_64}
  cs := path + #0;
  FillChar(buf[0], SizeOf(buf), 0);
  r := PyPalStat(@cs[1], @buf[0]);
  if r < 0 then
    raise FileNotFoundError.Create(path);
  Result.st_mode := PInt64(@buf[24])^ and $FFFFFFFF;   { u32 st_mode (uid sits above) }
  Result.st_size := PInt64(@buf[48])^;
{$endif}
end;

function pystdin_readline: AnsiString;
var one: AnsiString;
begin
  Result := '';
  while True do
  begin
    one := pystdin_read(1);
    if one = '' then Exit;           { EOF }
    Result := Result + one;
    if one = #10 then Exit;          { include and stop at the newline }
  end;
end;

function pystdin_isatty: Integer;
begin
  Result := 0;
end;

{ `s is None` for a str-typed value: a NilPy str that is None has a nil handle,
  a real string (including "") does not. Compares the managed handle, not the
  content — content compare against None read the wrong bytes and crashed. }
function pystr_is_none(const s: AnsiString): Boolean;
begin
  Result := Pointer(s) = nil;
end;

function pystr_none: AnsiString;
begin
  Result := '';
end;

{ Identity that BOXES its argument into a variant: passing a scalar to a Variant
  parameter materialises the box, so `pyvar_box(5)` yields a variant holding 5.
  Used to give a getattr default a variant representation for a variant-typed
  ternary (both branches must be variants). }
function pyvar_box(const v: Variant): Variant;
begin
  Result := v;
end;

type
  TPyBoundRec = record Code, Recv: Pointer; IsFunc: Boolean; end;
  PPyBoundRec = ^TPyBoundRec;

procedure PyObjFinalize(objp: Pointer; rawKind: NativeInt);
var
  k: Integer;
  l: TPyList;
  d: TPyDict;
  by: TPyBytes;
  o: TObject;
begin
  if objp = nil then Exit;
  if rawKind = 2 then
  begin
    { pyeval closure object: the registry entry (captures, token refs) is
      pyeval's to free }
    if PyClosureFinalizeHook <> nil then PyClosureFinalizeHook(objp);
    Exit;
  end;
  if rawKind <> 0 then
  begin
    { bound pair: drop the pair's ref on its receiver. Code is either a proc
      address or a refcounted closure obj — release both ends (magic-guarded,
      so a plain code address no-ops). }
    PXXObjRelease(PPyBoundRec(objp)^.Code);
    PXXObjRelease(PPyBoundRec(objp)^.Recv);
    Exit;
  end;
  o := TObject(objp);
  if o is TPyList then
  begin
    l := TPyList(objp);
    for k := 0 to l.FLen - 1 do
      PyVarSlotClear(PPyVarRec(NativeInt(l.FItems) + k * 16));
    if l.FItems <> nil then FreeMem(l.FItems);
    l.FItems := nil; l.FLen := 0; l.FCap := 0;
    Exit;
  end;
  if o is TPyDict then
  begin
    d := TPyDict(objp);
    for k := 0 to d.FLen - 1 do
    begin
      PyVarSlotClear(PPyVarRec(NativeInt(d.FKeys) + k * 16));
      PyVarSlotClear(PPyVarRec(NativeInt(d.FVals) + k * 16));
    end;
    if d.FKeys <> nil then FreeMem(d.FKeys);
    if d.FVals <> nil then FreeMem(d.FVals);
    if d.FHash <> nil then FreeMem(d.FHash);
    d.FKeys := nil; d.FVals := nil; d.FHash := nil;
    d.FLen := 0; d.FCap := 0; d.FHashCap := 0;
    Exit;
  end;
  if o is TPyBytes then
  begin
    by := TPyBytes(objp);
    if by.FData <> nil then FreeMem(by.FData);
    by.FData := nil; by.FLen := 0;
    Exit;
  end;
  { user class / anything else: release managed + variant fields via the
    class layout descriptor walker (kind 5 = variant slots, which recurses
    back through PXXObjRelease for held containers) }
  PXXClassFinalize(objp);
end;

function pybound_new(code, recv: Pointer; isFunc: Boolean): Variant;
var b: PPyBoundRec; r: PPyVarRec;
begin
  { RAW refcounted block (no VMT): rc at [b-16], PXX_OBJ_MAGIC_RAW at [b-8].
    The pair OWNS +1 on its receiver; PyObjFinalize's raw arm drops it when
    the pair dies (feature-nilpy-object-reclamation slice 3). }
  PXXObjFinalizeHook := @PyObjFinalize;
  b := PPyBoundRec(PXXObjAllocRaw(SizeOf(TPyBoundRec)));
  b^.Code := code;
  b^.Recv := recv;
  b^.IsFunc := isFunc;
  PXXObjRetain(code);   { a closure-obj code is refcounted; plain addresses no-op }
  PXXObjRetain(recv);
  r := PPyVarRec(@Result);
  r^.VType := 8;                       { VT_BOUNDMETHOD }
  r^.Payload := Int64(NativeInt(b));
  { the Result slot takes the construction's own +1 (ownership transfer) —
    downstream copies retain/release it like any object payload }
end;

function pybound_code(const v: Variant): Pointer;
begin
  pybound_code := PPyBoundRec(NativeInt(PPyVarRec(@v)^.Payload))^.Code;
end;

function pybound_isfunc(const v: Variant): Boolean;
begin
  pybound_isfunc := PPyBoundRec(NativeInt(PPyVarRec(@v)^.Payload))^.IsFunc;
end;

type
  { A NilPy def/method with no `-> ann` returns a VARIANT, and a Variant result
    travels through a hidden destination pointer the callee copies into on the
    way out. Calling one through a `: Int64` pointer left that register holding
    whatever the previous call put there, and the epilogue wrote 16 bytes to it.
    A `-> None` callee ignores the destination, so this shape is right for both. }
  TPyCbM0 = function(recv: Pointer): Variant;
  TPyCbM1 = function(recv: Pointer; const a0: Variant): Variant;
  TPyCbM2 = function(recv: Pointer; const a0, a1: Variant): Variant;
  TPyCbM3 = function(recv: Pointer; const a0, a1, a2: Variant): Variant;
  TPyCbF0 = function: Variant;
  TPyCbF1 = function(const a0: Variant): Variant;
  TPyCbF2 = function(const a0, a1: Variant): Variant;
  TPyCbF3 = function(const a0, a1, a2: Variant): Variant;
  { PROCEDURE-shaped siblings of the above: an explicit `-> None` def compiles
    as a genuine Pascal procedure (Procs[pi].IsFunc = False), which never sets
    up the Variant-hidden-destination-pointer convention TPyCbM*/TPyCbF*
    assume. Casting through those instead just reads back whatever garbage was
    left in that register and, worse, the callee's own epilogue writes 16
    bytes through it — hence the segfault this pair of types fixes
    (bug-nilpy-void-def-assigned-and-called-crashes). Selected at runtime via
    pybound_isfunc, which TPyBoundRec now carries per capture. }
  TPyCbMP0 = procedure(recv: Pointer);
  TPyCbMP1 = procedure(recv: Pointer; const a0: Variant);
  TPyCbMP2 = procedure(recv: Pointer; const a0, a1: Variant);
  TPyCbMP3 = procedure(recv: Pointer; const a0, a1, a2: Variant);
  TPyCbFP0 = procedure;
  TPyCbFP1 = procedure(const a0: Variant);
  TPyCbFP2 = procedure(const a0, a1: Variant);
  TPyCbFP3 = procedure(const a0, a1, a2: Variant);

function pycallback_is(const cb: Variant): Boolean;
begin
  pycallback_is := PPyVarRec(@cb)^.VType = 8;
end;

function pycallback_call0(const cb: Variant): Int64;
{ NOTE the empty parens on f0(): a bare procedural-variable NAME is not a call
  here, it is the pointer value — `pycallback_call0 := f0` silently assigned the
  code address and never invoked the callback, which is why a zero-argument
  `command=`/`after` handler did nothing at all. }
var code, recv: Pointer; m0: TPyCbM0; f0: TPyCbF0; mp0: TPyCbMP0; fp0: TPyCbFP0;
    r: Variant; isFn: Boolean;
begin
  pycallback_call0 := 0;
  r := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  recv := pybound_recv(cb);
  if code = nil then Exit;
  isFn := pybound_isfunc(cb);
  if recv = nil then
  begin
    if isFn then begin f0 := TPyCbF0(code); r := f0(); end
    else begin fp0 := TPyCbFP0(code); fp0(); end;
  end
  else
  begin
    if isFn then begin m0 := TPyCbM0(code); r := m0(recv); end
    else begin mp0 := TPyCbMP0(code); mp0(recv); end;
  end;
end;

function pycallback_call1(const cb: Variant; const a0: Variant): Int64;
var code, recv: Pointer; m1: TPyCbM1; f1: TPyCbF1; mp1: TPyCbMP1; fp1: TPyCbFP1;
    r: Variant; isFn: Boolean;
begin
  pycallback_call1 := 0;
  r := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  recv := pybound_recv(cb);
  if code = nil then Exit;
  isFn := pybound_isfunc(cb);
  if recv = nil then
  begin
    if isFn then begin f1 := TPyCbF1(code); r := f1(a0); end
    else begin fp1 := TPyCbFP1(code); fp1(a0); end;
  end
  else
  begin
    if isFn then begin m1 := TPyCbM1(code); r := m1(recv, a0); end
    else begin mp1 := TPyCbMP1(code); mp1(recv, a0); end;
  end;
end;

function pybound_recv(const v: Variant): Pointer;
begin
  pybound_recv := PPyBoundRec(NativeInt(PPyVarRec(@v)^.Payload))^.Recv;
end;

{ CALL a function value and KEEP its result — what an expression `f(x)` needs and
  pycallback_call* (a void event handler) cannot give. Both halves of the pair
  are honoured: a nil receiver is a plain def, a non-nil one a bound method whose
  receiver goes in as the hidden first argument. Every callee reached this way
  uses NilPy's function-object ABI (variant params, variant result — see
  PyDefUsedAsValue), which is exactly what these signatures declare. }
function pybound_callv0(const cb: Variant): Variant;
var code, recv: Pointer; m0: TPyCbM0; f0: TPyCbF0; mp0: TPyCbMP0; fp0: TPyCbFP0;
    isFn: Boolean;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  isFn := pybound_isfunc(cb);
  if recv = nil then
  begin
    if isFn then begin f0 := TPyCbF0(code); Result := f0(); end
    else begin fp0 := TPyCbFP0(code); fp0(); Result := pynone; end;
  end
  else
  begin
    if isFn then begin m0 := TPyCbM0(code); Result := m0(recv); end
    else begin mp0 := TPyCbMP0(code); mp0(recv); Result := pynone; end;
  end;
end;

function pybound_callv1(const cb: Variant; const a0: Variant): Variant;
var code, recv: Pointer; m1: TPyCbM1; f1: TPyCbF1; mp1: TPyCbMP1; fp1: TPyCbFP1;
    isFn: Boolean;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  isFn := pybound_isfunc(cb);
  if recv = nil then
  begin
    if isFn then begin f1 := TPyCbF1(code); Result := f1(a0); end
    else begin fp1 := TPyCbFP1(code); fp1(a0); Result := pynone; end;
  end
  else
  begin
    if isFn then begin m1 := TPyCbM1(code); Result := m1(recv, a0); end
    else begin mp1 := TPyCbMP1(code); mp1(recv, a0); Result := pynone; end;
  end;
end;

function pybound_callv2(const cb: Variant; const a0, a1: Variant): Variant;
var code, recv: Pointer; m2: TPyCbM2; f2: TPyCbF2; mp2: TPyCbMP2; fp2: TPyCbFP2;
    isFn: Boolean;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  isFn := pybound_isfunc(cb);
  if recv = nil then
  begin
    if isFn then begin f2 := TPyCbF2(code); Result := f2(a0, a1); end
    else begin fp2 := TPyCbFP2(code); fp2(a0, a1); Result := pynone; end;
  end
  else
  begin
    if isFn then begin m2 := TPyCbM2(code); Result := m2(recv, a0, a1); end
    else begin mp2 := TPyCbMP2(code); mp2(recv, a0, a1); Result := pynone; end;
  end;
end;

function pybound_callv3(const cb: Variant; const a0, a1, a2: Variant): Variant;
var code, recv: Pointer; m3: TPyCbM3; f3: TPyCbF3; mp3: TPyCbMP3; fp3: TPyCbFP3;
    isFn: Boolean;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  isFn := pybound_isfunc(cb);
  if recv = nil then
  begin
    if isFn then begin f3 := TPyCbF3(code); Result := f3(a0, a1, a2); end
    else begin fp3 := TPyCbFP3(code); fp3(a0, a1, a2); Result := pynone; end;
  end
  else
  begin
    if isFn then begin m3 := TPyCbM3(code); Result := m3(recv, a0, a1, a2); end
    else begin mp3 := TPyCbMP3(code); mp3(recv, a0, a1, a2); Result := pynone; end;
  end;
end;

{ input(): read one line from stdin and drop the trailing newline, as Python's
  input() does. (A prompt argument is printed by the caller, then ignored here.) }
function pyinput: AnsiString;
begin
  Result := pystdin_readline;
  if (Length(Result) > 0) and (Result[Length(Result)] = #10) then
    SetLength(Result, Length(Result) - 1);
  if (Length(Result) > 0) and (Result[Length(Result)] = #13) then
    SetLength(Result, Length(Result) - 1);
end;

function pyinput_p(const prompt: AnsiString): AnsiString;
{ `input(prompt)` — CPython writes the prompt to stdout WITHOUT a newline, so
  Write, not WriteLn. No explicit flush: this RTL has no Flush and its Write
  goes straight out, which is the property this relies on — if stdout ever
  becomes buffered, an interactive prompt would appear only after the user has
  typed, and this is the line to fix. }
begin
  Write(prompt);
  pyinput_p := pyinput;
end;

function pysys_argv: TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  for i := 0 to ParamCount do r.append(ParamStr(i));   { argv[0] = program name }
  Result := r;
end;

function pysys_file: AnsiString;
begin
  { __file__ — the running program's path, the closest analogue for a compiled
    binary (uforth uses it to find STD.UFO beside the script). }
  Result := ParamStr(0);
end;

function PySelectReady(const lst: Variant; events: Int64; timeoutMs: Int64): TPyList;
{ The ready subset of one select() list. A NilPy `sys.stdin` IS its file
  descriptor (the integer 0), so an entry polls as itself and the value that
  comes back is the value that went in — which is what makes CPython's
  `if sys.stdin in select.select([sys.stdin], [], [], 0)[0]` answer the same
  here. A non-integer entry (an object with no fd meaning) is skipped rather
  than guessed at. }
var res: TPyList; src: TPyList; i: Integer; v: Variant; fd: Int64;
begin
  res := TPyList.Create;
  if not pyvar_is_objtag(lst) then begin Result := res; Exit; end;
  src := TPyList(pyvarobj(lst));
  if src = nil then begin Result := res; Exit; end;
  for i := 0 to src.count - 1 do
  begin
    v := src.at(i);
    { tags 1/2 are the machine-int flavours; anything else has no fd meaning }
    if (pyvartag(v) <> 1) and (pyvartag(v) <> 2) then Continue;
    fd := pyvar_to_int(v);
    if PyPalPoll(fd, events, timeoutMs) = 1 then res.append(v);
  end;
  Result := res;
end;

function pyselect_select(const r: Variant; const w: Variant; const x: Variant; const t: Variant): TPyList;
{ `select.select(rlist, wlist, xlist, timeout)`.

  Was a STUB that always answered "nothing ready" — which is not a degraded
  answer, it is the WRONG one: a program that polls stdin to decide whether it
  is being fed a script or typed at got the interactive answer either way.
  uforth prints its `UF> ` prompt for every piped line because of exactly that
  test, so its output could never match CPython's.

  Timeout: CPython takes SECONDS as a float, and None means block. The common
  `0` (poll, do not wait) and a small float both round through here; a negative
  or missing timeout blocks, matching poll(2). The xlist has no meaning for the
  descriptors NilPy can produce, so it comes back empty. }
var res: TPyList; timeoutMs: Int64;
begin
  timeoutMs := 0;
  if pyvartag(t) = 0 then timeoutMs := -1                     { None -> block }
  else timeoutMs := Round(pyvar_to_float(t) * 1000.0);
  res := TPyList.Create;
  res.append(PySelectReady(r, 1, timeoutMs));    { POLLIN  }
  res.append(PySelectReady(w, 4, timeoutMs));    { POLLOUT }
  res.append(TPyList.Create);        { xlist — no exceptional set to report }
  Result := res;
end;

function pyopen(const path: AnsiString): TPyList;
var content, line: AnsiString; ok: Boolean; i, n: Integer;
begin
  Result := TPyList.Create;
  content := pyfile_slurp(path, ok);
  if not ok then
  begin
    raise FileNotFoundError.Create(path);
  end;
  { split into lines, each KEEPING its trailing newline — Python's file
    iteration yields lines that way, and uforth strips the '\n' itself }
  i := 1; n := Length(content); line := '';
  while i <= n do
  begin
    line := line + content[i];
    if content[i] = #10 then
    begin
      Result.append(line);
      line := '';
    end;
    Inc(i);
  end;
  if Length(line) > 0 then Result.append(line);   { last line, no trailing NL }
end;

function pyfile_read(l: TPyList): AnsiString;
var i: Integer; v: Variant;
begin
  Result := '';
  if l = nil then Exit;
  for i := 0 to l.count - 1 do
  begin
    v := l.at(i);
    Result := Result + pystr_of(v);
  end;
end;

procedure pyexec(const src: AnsiString; g: TPyDict; l: TPyDict);
begin
  { STUB — see the interface note. The tree-walker that actually runs `src`
    against g/l is feature-lib-pyexec. No-op for now so the program links. }
end;

function pytextwrap_dedent(const s: AnsiString): AnsiString;
var i, n, lineStart, wsLen, common: Integer; line: AnsiString;
    haveCommon: Boolean;
begin
  { pass 1: the common leading-whitespace length over non-blank lines }
  common := -1;
  haveCommon := False;
  i := 1; n := Length(s);
  lineStart := 1;
  while i <= n + 1 do
  begin
    if (i > n) or (s[i] = #10) then
    begin
      line := Copy(s, lineStart, i - lineStart);
      { blank line (only whitespace) does not constrain the common prefix }
      wsLen := 0;
      while (wsLen < Length(line)) and
            ((line[wsLen + 1] = ' ') or (line[wsLen + 1] = #9)) do Inc(wsLen);
      if wsLen < Length(line) then          { non-blank }
      begin
        if not haveCommon then begin common := wsLen; haveCommon := True; end
        else if wsLen < common then common := wsLen;
      end;
      lineStart := i + 1;
    end;
    Inc(i);
  end;
  if not haveCommon then common := 0;

  { pass 2: strip `common` chars from the front of each line }
  Result := '';
  i := 1; lineStart := 1;
  while i <= n + 1 do
  begin
    if (i > n) or (s[i] = #10) then
    begin
      line := Copy(s, lineStart, i - lineStart);
      if Length(line) >= common then line := Copy(line, common + 1, Length(line) - common)
      else line := '';
      Result := Result + line;
      if i <= n then Result := Result + #10;
      lineStart := i + 1;
    end;
    Inc(i);
  end;
end;

function bytes(l: TPyList): TPyBytes; overload;
begin
  Result := pybytes_from_list(l);
end;

function bytes(b: TPyBytes): TPyBytes;
var k: Integer; src, dst: PByte;
begin
  { Belt and braces. A list argument used to bind HERE, because class-arg
    overload resolution was not identity-precise, and this runtime `is` check
    was the rescue. Since bug-a-overload-resolution-ignores-class-identity a
    list binds to the real `bytes(l: TPyList)` overload above and never reaches
    this, so the check is now unreachable in normal code — kept because it is
    free and because a variant-typed argument can still arrive by another
    route. Remove once that is confirmed impossible. }
  if TObject(b) is TPyList then
  begin
    Result := pybytes_from_list(TPyList(TObject(b)));
    Exit;
  end;
  { bytes(x) is an immutable COPY in Python; immutability is not modelled, but
    the copy is, because uforth uses it to snapshot memory }
  Result := TPyBytes.Create(b.FLen);
  for k := 0 to b.FLen - 1 do
  begin
    src := PByte(NativeInt(b.FData) + k);
    dst := PByte(NativeInt(Result.FData) + k);
    dst^ := src^;
  end;
end;

{ bytes([32, 33]) — from a LIST of small ints. Called from the bytes() copy
  overload via a runtime `is` check: overload resolution binds ANY class arg
  to the first class-typed param, so a list arg arrived AS the TPyBytes param
  and the variant slots' TAG bytes were read as data (uforth FILL wrote tag
  bytes into memory). }
function pybytes_from_list(l: TPyList): TPyBytes;
var k: Integer; p: PByte;
begin
  Result := TPyBytes.Create(l.count);
  for k := 0 to l.count - 1 do
  begin
    p := PByte(NativeInt(Result.FData) + k);
    p^ := Byte(pyvar_to_int(l.at(k)) and $FF);
  end;
end;

function TPyBytes.find(sub: TPyBytes): Integer; overload;
begin
  Result := pybytes_find(Self, sub, 0);
end;

function TPyBytes.find(sub: TPyBytes; start: Integer): Integer; overload;
begin
  Result := pybytes_find(Self, sub, start);
end;

{ bytes("...") — the bytes of a string, one per character. This is also where a
  `b"..."` literal lands (the frontend rewrites it to bytes("...")). }
function bytes(const s: AnsiString): TPyBytes; overload;
var k: Integer; p: PByte;
begin
  Result := TPyBytes.Create(Length(s));
  for k := 1 to Length(s) do
  begin
    p := PByte(NativeInt(Result.FData) + (k - 1));
    p^ := Ord(s[k]);
  end;
end;

{ bytes.find(sub, start): first index at/after `start` where `sub`'s bytes match,
  or -1. `sub` is a TPyBytes (a `b"..."` literal). }
function pybytes_find(b: TPyBytes; sub: TPyBytes; start: Integer): Integer;
var i, j: Integer; match: Boolean; pb, ps: PByte;
begin
  Result := -1;
  if sub.FLen = 0 then begin Result := start; Exit; end;
  if start < 0 then start := 0;
  i := start;
  while i + sub.FLen <= b.FLen do
  begin
    match := True;
    for j := 0 to sub.FLen - 1 do
    begin
      pb := PByte(NativeInt(b.FData) + i + j);
      ps := PByte(NativeInt(sub.FData) + j);
      if pb^ <> ps^ then begin match := False; Break; end;
    end;
    if match then begin Result := i; Exit; end;
    Inc(i);
  end;
end;

function len(const v: Variant): Integer; overload;
var o: TObject; t: Int64;
begin
  t := pyvartag(v);
  if (t = 5) or (t = 6) then begin Result := Length(VariantToStr(v)); Exit; end;
  if t = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := TPyList(o).count; Exit; end;
    if o is TPyDict then begin Result := TPyDict(o).count; Exit; end;
    if o is TPyBytes then begin Result := TPyBytes(o).count; Exit; end;
  end;
  PyTypeError(t, 'a str, list, dict or bytes');
  Result := 0;
end;

function len(b: TPyBytes): Integer; overload;
begin
  Result := b.FLen;
end;


{ Integer -> text in the requested base, lower or upper case. Python has no
  sign-and-magnitude form here: a negative value formats its minus sign and
  then the magnitude, exactly as CPython does for {-255:x} = -ff. }
function PyFmtBase(v: Int64; base: Integer; upper: Boolean): AnsiString;
var tmp: AnsiString; neg: Boolean; d: Integer;
begin
  neg := v < 0;
  if neg then v := -v;
  tmp := '';
  if v = 0 then tmp := '0';
  while v > 0 do
  begin
    d := v mod base;
    if d < 10 then tmp := Chr(Ord('0') + d) + tmp
    else if upper then tmp := Chr(Ord('A') + d - 10) + tmp
    else tmp := Chr(Ord('a') + d - 10) + tmp;
    v := v div base;
  end;
  if neg then Result := '-' + tmp else Result := tmp;
end;

function PyFmtPad(const s: AnsiString; width: Integer; zero: Boolean;
                  leftAlign: Boolean): AnsiString;
var pad: AnsiString; i, need: Integer;
begin
  Result := s;
  need := width - Length(s);
  if need <= 0 then Exit;
  pad := '';
  for i := 1 to need do
    if zero then pad := pad + '0' else pad := pad + ' ';
  if leftAlign then Result := s + pad
  else if zero and (Length(s) > 0) and (s[1] in ['-', '+', ' ']) then
    { zero padding goes AFTER the sign: {-5:04d} is -005, not 0-05. '+' and the
      space flag are signs too — `{42:+06d}` is +00042, not 000+42
      (bug-nilpy-format-spec-sign-flag-unsupported). }
    Result := s[1] + pad + Copy(s, 2, Length(s) - 1)
  else
    Result := pad + s;
end;

{ `{x:*^10}`-style: an explicit fill char (any char, defaulting to space)
  followed by an alignment char, INCLUDING '^' (center) which the plain
  zero/leftAlign PyFmtPad has no notion of. Kept as a separate function rather
  than folded into PyFmtPad so every existing caller of PyFmtPad (the bare
  '<'/'>'/'0' forms) stays on its byte-identical old path; only a spec that
  actually names a fill char or '^' reaches this one.
  feature-nilpy-fstring-format-spec }
function PyFmtPadEx(const s: AnsiString; width: Integer; fillCh: Char;
                    align: Char): AnsiString;
var pad: AnsiString; i, need, leftN, rightN: Integer;
begin
  Result := s;
  need := width - Length(s);
  if need <= 0 then Exit;
  pad := '';
  for i := 1 to need do pad := pad + fillCh;
  if align = '<' then Result := s + pad
  else if align = '^' then
  begin
    leftN := need div 2;
    rightN := need - leftN;
    Result := Copy(pad, 1, leftN) + s + Copy(pad, 1, rightN);
  end
  else Result := pad + s;   { '>' or unset: right-align, same default as before }
end;

{ Supported spec grammar, deliberately small and checked rather than guessed:
    [ [fill] ('<' | '>' | '^') ] [ '0' ] [ width ] [ 'd' | 'x' | 'X' | 'o' | 'b' | 's' ]
  Anything else halts with the spec quoted, because a format spec decides what
  is PRINTED and silently ignoring one produces wrong output. }
{ The placeholder walk. Two variants rather than an open array: an open array
  of Variant is not marshalled correctly here and crashed on the second
  argument. }
function PyFormatApply(const fmt: AnsiString; args: TPyList): AnsiString;
var i, j, argi, useIdx, k, nArgs: Integer; spec, fld, outS: AnsiString;
begin
  outS := '';
  nArgs := 0;
  if args <> nil then nArgs := args.count;
  argi := 0;
  i := 1;
  while i <= Length(fmt) do
  begin
    if (fmt[i] = '{') and (i < Length(fmt)) and (fmt[i + 1] = '{') then
    begin outS := outS + '{'; Inc(i, 2); Continue; end;
    if (fmt[i] = '}') and (i < Length(fmt)) and (fmt[i + 1] = '}') then
    begin outS := outS + '}'; Inc(i, 2); Continue; end;
    if fmt[i] = '{' then
    begin
      { A replacement field is `{[field][:spec]}`. The FIELD was previously
        scanned past and thrown away, so `"{1}{0}".format(a, b)` substituted
        left-to-right and printed the arguments in the WRONG ORDER, silently —
        `{}` and `{0}{1}` agree with sequential substitution, which is why it
        stayed invisible until an index actually reordered
        (bug-nilpy-str-format-ignores-positional-indices). }
      j := i + 1;
      spec := '';
      fld := '';
      while (j <= Length(fmt)) and (fmt[j] <> '}') and (fmt[j] <> ':') do
      begin fld := fld + fmt[j]; Inc(j); end;
      if (j <= Length(fmt)) and (fmt[j] = ':') then
      begin
        Inc(j);
        while (j <= Length(fmt)) and (fmt[j] <> '}') do
        begin spec := spec + fmt[j]; Inc(j); end;
      end;
      { An all-digits field is an explicit index and does NOT advance the
        automatic counter — Python numbers `{}` and `{N}` independently, which
        is what makes `"{0}-{0}"` repeat one argument. A non-numeric field (a
        NAMED one, `{name}`) needs kwargs, which this path does not carry, so
        it keeps the previous sequential behaviour rather than erroring. }
      useIdx := -1;
      if fld <> '' then
      begin
        useIdx := 0;
        for k := 1 to Length(fld) do
          if (fld[k] >= '0') and (fld[k] <= '9') then
            useIdx := useIdx * 10 + (Ord(fld[k]) - Ord('0'))
          else
          begin useIdx := -1; Break; end;
      end;
      if useIdx < 0 then
      begin
        useIdx := argi;
        Inc(argi);
      end;
      if useIdx >= nArgs then
        raise Exception.Create('str.format: more placeholders than arguments');
      if spec = '' then outS := outS + pystr_of(args.at(useIdx))
      else outS := outS + pyformat_of(args.at(useIdx), spec);
      i := j + 1;
      Continue;
    end;
    outS := outS + fmt[i];
    Inc(i);
  end;
  PyFormatApply := outS;
end;

function pystr_format(const fmt: AnsiString; const a: Variant): AnsiString;
var args: TPyList;
begin
  args := TPyList.Create;
  args.append(a);
  pystr_format := PyFormatApply(fmt, args);
end;

{ `"{} and {}".format(a, b)` — a SEPARATE proc, not a second pystr_format
  overload: the caller (pyparser.inc) looks procs up by bare NAME via
  FindProc, which is not arity-aware, so a same-named 1-arg/2-arg overload
  pair resolved to whichever was registered first regardless of how many
  arguments were actually parsed — the second Variant arrived through a
  1-param ABI and the call segfaulted. Every other multi-arity str method
  (split/rjust/replace) already sidesteps this the same way, with its own
  arity-suffixed proc name (bug-nilpy-str-format-multiarg /
  feature-nilpy-str-format-multiarg). PyFormatApply already supported two
  positional args; only this entry point and the frontend's arity gate were
  missing. }
function pystr_format2(const fmt: AnsiString; const a: Variant; const b: Variant): AnsiString;
var args: TPyList;
begin
  args := TPyList.Create;
  args.append(a);
  args.append(b);
  pystr_format2 := PyFormatApply(fmt, args);
end;

{ THREE OR MORE placeholders. The arity-suffixed-name trick above does not
  scale past two (one proc per arity, forever), so this is the last rung: a
  FIXED-arity proc the frontend pads with None up to PYFORMAT_MAXARGS and
  tells how many are real. The substitution itself is shared — PyFormatApply
  takes the argument LIST, so every arity walks the same code and the
  positional-index and format-spec behaviour cannot drift between them.
  Beyond PYFORMAT_MAXARGS the frontend refuses loudly and names f-strings,
  which have no such limit. }
function pystr_formatn(const fmt: AnsiString;
                       const a0, a1, a2, a3, a4, a5, a6, a7: Variant;
                       n: Integer): AnsiString;
var args: TPyList;
begin
  args := TPyList.Create;
  if n > 0 then args.append(a0);
  if n > 1 then args.append(a1);
  if n > 2 then args.append(a2);
  if n > 3 then args.append(a3);
  if n > 4 then args.append(a4);
  if n > 5 then args.append(a5);
  if n > 6 then args.append(a6);
  if n > 7 then args.append(a7);
  pystr_formatn := PyFormatApply(fmt, args);
end;

function pypercent_format(const fmt: AnsiString; const args: Variant): AnsiString;
var i, width, prec, argi, nargs: Integer;
    zero, leftAlign, hasPrec, alt: Boolean;
    outS, spec: AnsiString;
    conv, signCh: Char;
    lst: TPyList;
    cur: Variant;
begin
  { TUPLE OR SINGLE VALUE — Python's rule: a tuple is a sequence of arguments, a
    list is ONE value (`"[%s]" % [1,2]` prints `[[1, 2]]`). Both are a TPyList
    here, so the answer comes from the list's own tuple flag, which the frontend
    set where the syntax was still visible and which travels with the object
    through variables and calls. }
  lst := nil;
  if PPyVarRec(@args)^.VType = 7 then
    if TObject(pyvarobj(args)) is TPyList then
      if TPyList(pyvarobj(args)).FKind = PYSEQ_TUPLE then lst := TPyList(pyvarobj(args));
  if lst <> nil then nargs := lst.count else nargs := 1;
  outS := '';
  argi := 0;
  i := 1;
  while i <= Length(fmt) do
  begin
    if fmt[i] <> '%' then
    begin
      outS := outS + fmt[i];
      Inc(i);
      Continue;
    end;
    Inc(i);
    if (i <= Length(fmt)) and (fmt[i] = '%') then
    begin
      outS := outS + '%';
      Inc(i);
      Continue;
    end;
    leftAlign := False;
    zero := False;
    width := 0;
    prec := 0;
    hasPrec := False;
    signCh := #0;
    alt := False;
    { The flag loop CONSUMED '+' and ' ' without recording them, so `"%+d" % n`
      printed 42 rather than +42 — silently dropping a flag that decides what is
      printed. '#' was not in the set at all, so it fell through to the
      conversion char and raised. Both are now carried into the {}-spec below,
      which learned them alongside
      (bug-nilpy-percent-format-drops-the-sign-and-alt-flags). }
    while (i <= Length(fmt)) and
          ((fmt[i] = '-') or (fmt[i] = '0') or (fmt[i] = '+') or (fmt[i] = ' ') or (fmt[i] = '#')) do
    begin
      if fmt[i] = '-' then leftAlign := True
      else if fmt[i] = '0' then zero := True
      else if fmt[i] = '#' then alt := True
      else signCh := fmt[i];
      Inc(i);
    end;
    while (i <= Length(fmt)) and (fmt[i] >= '0') and (fmt[i] <= '9') do
    begin
      width := width * 10 + (Ord(fmt[i]) - Ord('0'));
      Inc(i);
    end;
    if (i <= Length(fmt)) and (fmt[i] = '.') then
    begin
      hasPrec := True;
      Inc(i);
      while (i <= Length(fmt)) and (fmt[i] >= '0') and (fmt[i] <= '9') do
      begin
        prec := prec * 10 + (Ord(fmt[i]) - Ord('0'));
        Inc(i);
      end;
    end;
    if i > Length(fmt) then
    begin
      raise ValueError.Create('incomplete format');
    end;
    conv := fmt[i];
    Inc(i);
    { the argument this placeholder consumes }
    if lst <> nil then
    begin
      if argi >= nargs then
        raise TypeError.Create('not enough arguments for format string');
      cur := lst.at(argi);
    end
    else
    begin
      if argi >= 1 then
        raise TypeError.Create('not enough arguments for format string');
      cur := args;
    end;
    Inc(argi);
    { translate into the {}-spec grammar and reuse its formatter }
    spec := '';
    if leftAlign then spec := '<';
    { grammar order is [align][sign][#][0][width] — see pyformat_of }
    if signCh <> #0 then spec := spec + signCh;
    if alt then spec := spec + '#';
    if zero and (not leftAlign) then spec := spec + '0';
    if width > 0 then spec := spec + pystr_of(Int64(width));
    case conv of
      'd', 'i', 'u': spec := spec + 'd';
      'c': spec := spec + 'c';
      'x': spec := spec + 'x';
      'X': spec := spec + 'X';
      'o': spec := spec + 'o';
      'f', 'F':
        begin
          if not hasPrec then prec := 6;
          spec := spec + '.' + pystr_of(Int64(prec)) + 'f';
        end;
      'e', 'E', 'g', 'G':
        begin
          { `e`/`g` have no equivalent in the {}-spec grammar `spec` targets
            (an f-string `{x:e}` correctly refuses at compile time rather than
            silently rendering fixed-point), so build the text directly here
            and apply the same width/pad step `%s` uses just below, instead of
            routing through pyformat_of's fixed-point-only case
            (bug-nilpy-percent-e-and-g-silently-render-as-fixed-point). }
          if not hasPrec then prec := 6;
          if (conv = 'e') or (conv = 'E') then
            outS := outS + PyFmtPad(PyFmtExp(pyvar_to_float(cur), prec, conv = 'E'),
                                    width, zero, leftAlign)
          else
            outS := outS + PyFmtPad(PyFmtG(pyvar_to_float(cur), prec, conv = 'G'),
                                    width, zero, leftAlign);
          Continue;
        end;
      's':
        begin
          { a str conversion of ANY value, then the same padding.
            pyvar_print_of, not pystr_of: %s of a LIST prints it the way Python
            does (`"[%s]" % [1,2]` -> `[[1, 2]]`), and pystr_of renders a
            container as empty. It falls back to str for every scalar. }
          outS := outS + PyFmtPad(pyvar_print_of(cur), width, False, leftAlign);
          Continue;
        end;
      'r':
        begin
          { %r is repr(), NOT str(). It shared the 's' arm, so `"%r" % "v"`
            printed `v` where Python prints `'v'` — silently, and ONLY for
            string operands, since repr and str agree for numbers and pxx's
            containers already render repr-style. That is what hid it:
            `"%r" % 5` and `"%r" % [1,2]` both looked right
            (bug-nilpy-percent-r-renders-as-str-not-repr).
            pyvar_repr already quotes a string and delegates list/dict/bytes to
            their own repr, so this is one call, not new logic. }
          outS := outS + PyFmtPad(pyvar_repr(cur), width, False, leftAlign);
          Continue;
        end;
    else
      begin
        raise ValueError.Create('unsupported format character "' + conv + '"');
      end;
    end;
    outS := outS + pyformat_of(cur, spec);
  end;
  { LEFTOVER arguments are a TypeError in Python, and this only tested the
    tuple form. `"ab" % 5` -- a format string with no placeholder at all --
    fell through and returned the format unchanged, so a real bug (usually a
    `%` that was meant to be modulo, or a lost specifier) produced plausible
    output instead of an error. nargs is 1 for the single-value form, so the
    same comparison covers both.

    A SUBSCRIPTABLE right-hand side is exempt, and that is CPython's own rule,
    not a shortcut: it skips the check whenever PyMapping_Check passes, which
    is true for a dict AND for a list, so `"ab" % {"k": 1}` and `"ab" % [1, 2]`
    both yield "ab" while `"ab" % (1, 2)` and `"ab" % 5` raise. Measured
    against CPython rather than reasoned from the docs. }
  if (argi < nargs) and
     ((lst <> nil) or (PPyVarRec(@args)^.VType <> 7)) then
    raise TypeError.Create('not all arguments converted during string formatting');
  Result := outS;
end;

{ Insert Python's thousands separators into a already-rendered DECIMAL string:
  groups of three from the RIGHT, with any leading sign left alone.
  (bug-nilpy-thousands-separator-format-spec-unsupported) }
function PyGroupThousands(const s: AnsiString; sep: Char): AnsiString;
var i, n, cnt: Integer; sign, digits, outS: AnsiString;
begin
  sign := '';
  digits := s;
  if (Length(digits) > 0) and ((digits[1] = '-') or (digits[1] = '+')) then
  begin
    sign := Copy(digits, 1, 1);
    digits := Copy(digits, 2, Length(digits) - 1);
  end;
  n := Length(digits);
  outS := '';
  cnt := 0;
  for i := n downto 1 do
  begin
    outS := digits[i] + outS;
    Inc(cnt);
    if (cnt mod 3 = 0) and (i > 1) then outS := sep + outS;
  end;
  Result := sign + outS;
end;

{ The integer format spec, over EITHER a machine int or an arbitrary-precision
  decimal. bigDec = '' means "use i"; otherwise bigDec is the exact decimal of a
  VT_PROMO_INT64 payload and i is unused.

  One body rather than two because the spec grammar (fill/align/sign/#/0/width/
  grouping/type) is the same either way and a second copy would drift. Only the
  DIGIT-PRODUCING step differs, and for a bignum only base 10 can be produced
  here — pylib does not see promocore, so a base conversion is not available and
  is REFUSED rather than answered with a wrapped machine int. }
function PyFormatIntEx(i: Int64; const bigDec: AnsiString; const spec: AnsiString): AnsiString;
var p, width, need, zi: Integer; zero, leftAlign, grouped, alt: Boolean;
    kind, fillCh, align, signCh, groupCh: Char;
    body, altPre, lead, zeros: AnsiString;
begin
  p := 1;
  zero := False;
  leftAlign := False;
  grouped := False;
  width := 0;
  kind := 'd';
  fillCh := ' '; align := #0;
  if (p + 1 <= Length(spec)) and (spec[p + 1] in ['<', '>', '^']) then
  begin
    fillCh := spec[p]; align := spec[p + 1]; leftAlign := align = '<';
    Inc(p, 2);
  end
  else if (p <= Length(spec)) and (spec[p] in ['<', '>', '^']) then
  begin
    align := spec[p]; leftAlign := align = '<';
    Inc(p);
  end;
  { SIGN flag — Python's grammar puts it after [[fill]align] and before the
    zero-pad/width: '+' shows a sign on positive numbers too, '-' is the default
    (negative only), ' ' puts a SPACE where '+' would go. It was unhandled, so
    `f"{n:+d}"` raised "unsupported format spec"
    (bug-nilpy-format-spec-sign-flag-unsupported). }
  signCh := #0;
  if (p <= Length(spec)) and (spec[p] in ['+', '-', ' ']) then
  begin
    signCh := spec[p];
    Inc(p);
  end;
  { '#' — ALTERNATE form: prefix the base, 0x / 0X / 0o / 0b. Grammar position is
    after the sign and before the zero-pad (bug-nilpy-format-spec-alt-form-hash). }
  alt := False;
  if (p <= Length(spec)) and (spec[p] = '#') then
  begin
    alt := True;
    Inc(p);
  end;
  if (p <= Length(spec)) and (spec[p] = '0') then
  begin
    zero := True;
    Inc(p);
  end;
  while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
  begin
    width := width * 10 + (Ord(spec[p]) - Ord('0'));
    Inc(p);
  end;
  { `,` — thousands grouping. Python's spec grammar puts it after the width and
    before any `.precision`/type, so `{:,}`, `{:,d}` and `{:10,d}` are all legal.
    It was not handled at all, and the unsupported-spec path then ABORTED the
    process (bug-nilpy-thousands-separator-format-spec-unsupported). }
  { ',' or '_' — Python allows either as the grouping separator }
  groupCh := ',';
  if (p <= Length(spec)) and (spec[p] in [',', '_']) then
  begin
    grouped := True;
    groupCh := spec[p];
    Inc(p);
  end;
  { a FLOAT spec on an integer value — Python prints `{2:.1f}` as `2.0`, and an
    int is exactly representable, so hand it to the float formatter }
  if (p <= Length(spec)) and (spec[p] = '.') then
  begin
    if bigDec <> '' then
      raise ValueError.Create('float format spec "' + spec +
                              '" on an arbitrary-precision int is not supported');
    Result := pyformat_of(pyfloat_ofint(i), spec);
    Exit;
  end;
  if p <= Length(spec) then
  begin
    kind := spec[p];
    Inc(p);
  end;
  if (kind = 'f') or (kind = 'F') or (kind = 'e') or (kind = 'E') then
  begin
    if bigDec <> '' then
      raise ValueError.Create('float format spec "' + spec +
                              '" on an arbitrary-precision int is not supported');
    Result := pyformat_of(pyfloat_ofint(i), spec);
    Exit;
  end;
  if p <= Length(spec) then
    { CATCHABLE, not Halt. An unsupported spec used to abort the process, so a
      try/except around a format could not run its handler and everything after
      the call was lost — the same "must be catchable" rule already applied to
      missing operators (bug-nilpy-thousands-separator-format-spec-unsupported). }
    raise ValueError.Create('unsupported format spec "' + spec + '"');
  if bigDec <> '' then
  begin
    { base 10 is the only base reachable without promocore; anything else would
      have to narrow first, i.e. print a wrapped value for a number that does
      not fit — exactly the silent-wrong-output case a spec exists to avoid }
    if (kind <> 'd') and (kind <> 's') then
      raise ValueError.Create('format spec "' + spec +
                              '" on an arbitrary-precision int is not supported');
    body := bigDec;
  end
  else
  case kind of
    'd': body := PyFmtBase(i, 10, False);
    'x': body := PyFmtBase(i, 16, False);
    'X': body := PyFmtBase(i, 16, True);
    'o': body := PyFmtBase(i, 8, False);
    'b': body := PyFmtBase(i, 2, False);
    's': body := PyFmtBase(i, 10, False);
    'c': body := Chr(i);        { `{65:c}` is 'A' — the codepoint as a character }
  else
    raise ValueError.Create('unsupported format spec "' + spec + '"');
  end;
  if grouped then body := PyGroupThousands(body, groupCh);
  { Assemble as sign + prefix + zeros + digits, which is the order Python uses:
    `{42:#010x}` is 0x0000002a — the zero padding sits INSIDE the 0x, not before
    it. Doing this here rather than in PyFmtPad keeps every existing caller of
    PyFmtPad on its byte-identical path; PyFmtPad only knows about a ONE-character
    sign, which cannot express a two-character base prefix. }
  altPre := '';
  if alt then
    case kind of
      'x': altPre := '0x';
      'X': altPre := '0X';
      'o': altPre := '0o';
      'b': altPre := '0b';
    end;
  lead := '';
  { the sign comes off the digits AFTER grouping, so it is never grouped with them }
  if (Length(body) > 0) and (body[1] = '-') then
  begin
    lead := '-';
    body := Copy(body, 2, Length(body) - 1);
  end
  else if (signCh <> #0) and (signCh <> '-') then
  begin
    if signCh = '+' then lead := '+' else lead := ' ';
  end;
  lead := lead + altPre;
  if zero and (align = #0) and (fillCh = ' ') and (not leftAlign) then
  begin
    need := width - Length(lead) - Length(body);
    zeros := '';
    for zi := 1 to need do zeros := zeros + '0';
    Result := lead + zeros + body;
    Exit;
  end;
  body := lead + body;
  if align = '^' then Result := PyFmtPadEx(body, width, fillCh, '^')
  else if fillCh <> ' ' then Result := PyFmtPadEx(body, width, fillCh, align)
  else Result := PyFmtPad(body, width, zero, leftAlign);
end;

function pyformat_of(i: Int64; const spec: AnsiString): AnsiString;
begin
  Result := PyFormatIntEx(i, '', spec);
end;

function pyformat_of(const s: AnsiString; const spec: AnsiString): AnsiString; overload;
var p, width, prec: Integer; leftAlign, explicitAlign, hasPrec: Boolean;
    fillCh, align: Char; body: AnsiString;
begin
  p := 1;
  leftAlign := False;
  explicitAlign := False;
  width := 0;
  prec := 0; hasPrec := False;
  fillCh := ' '; align := #0;
  if (p + 1 <= Length(spec)) and (spec[p + 1] in ['<', '>', '^']) then
  begin
    fillCh := spec[p]; align := spec[p + 1]; leftAlign := align = '<';
    explicitAlign := True;
    Inc(p, 2);
  end
  else if (p <= Length(spec)) and (spec[p] in ['<', '>', '^']) then
  begin
    align := spec[p]; leftAlign := align = '<';
    explicitAlign := True;
    Inc(p);
  end;
  while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
  begin
    width := width * 10 + (Ord(spec[p]) - Ord('0'));
    Inc(p);
  end;
  { `.precision` on a STRING TRUNCATES it — `f"{'abcdef':.2}"` is `ab`. Python's
    own rule, and the reason it is a maximum rather than a minimum: for a string
    the precision caps the length while the width sets a floor
    (bug-nilpy-format-spec-string-precision-and-halt). }
  if (p <= Length(spec)) and (spec[p] = '.') then
  begin
    Inc(p);
    hasPrec := True;
    while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
    begin
      prec := prec * 10 + (Ord(spec[p]) - Ord('0'));
      Inc(p);
    end;
  end;
  if (p <= Length(spec)) and (spec[p] = 's') then Inc(p);
  if p <= Length(spec) then
    { CATCHABLE, not Halt. This site was missed when the int and float overloads
      were converted: a bad spec on a STRING still aborted the process, so a
      try/except around the format could not run and everything after it was
      lost (bug-nilpy-format-spec-string-precision-and-halt). }
    raise ValueError.Create('unsupported format spec "' + spec + '" for a string');
  body := s;
  if hasPrec and (prec < Length(body)) then body := Copy(body, 1, prec);
  { a string left-aligns by default, unlike a number, UNLESS an align/fill was
    given explicitly (a bare `{s:>5}` must still right-align) }
  if (not explicitAlign) and (width > Length(body)) then leftAlign := True;
  if align = '^' then Result := PyFmtPadEx(body, width, fillCh, '^')
  else if fillCh <> ' ' then Result := PyFmtPadEx(body, width, fillCh, align)
  else Result := PyFmtPad(body, width, False, leftAlign);
end;

function PyFmtFixed(d: Double; prec: Integer): AnsiString;
{ Fixed-point rendering with `prec` digits after the point — pylib's own, since
  pylib may not pull sysutils in (see the FmtArgStr note above). Half-up
  rounding with carry, which is what Python's `.Nf` prints for the values a
  format spec is used on. }
var neg: Boolean; ip: Int64; fp: Int64; scale: Double; i: Integer; fs: AnsiString;
begin
  if prec < 0 then prec := 0;
  neg := d < 0.0;
  if neg then d := -d;
  scale := 1.0;
  for i := 1 to prec do scale := scale * 10.0;
  ip := Trunc(d);
  fp := Round((d - ip) * scale);
  if fp >= Round(scale) then begin ip := ip + 1; fp := 0; end;
  Result := PyFmtBase(ip, 10, False);
  if prec > 0 then
  begin
    fs := PyFmtBase(fp, 10, False);
    while Length(fs) < prec do fs := '0' + fs;
    Result := Result + '.' + fs;
  end;
  if neg then Result := '-' + Result;
end;

{ `%e`/`%E`: mantissa normalised to [1,10) via the SAME loop FloatToExpStr
  uses, but the digit rule is PyFmtFixed's (exactly `prec` fractional digits,
  half-up rounding) rather than FloatToExpStr's own trimmed natural form --
  `"%.2e" % 1234.5` must print `1.23e+03`, not whatever digit count
  FloatToStr's trim-trailing-zeros rule happens to leave.
  bug-nilpy-percent-e-and-g-silently-render-as-fixed-point. }
function PyFmtExp(v: Double; prec: Integer; upper: Boolean): AnsiString;
var neg: Boolean; e: Integer; ms, es: AnsiString;
begin
  if v <> v then begin Result := 'nan'; Exit; end;
  if v > 1.7976931348623157e308 then begin Result := 'inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin Result := '-inf'; Exit; end;
  neg := v < 0.0;
  if neg then v := -v;
  e := 0;
  if v <> 0.0 then
  begin
    while v >= 10.0 do begin v := v / 10.0; e := e + 1; end;
    while v < 1.0 do begin v := v * 10.0; e := e - 1; end;
  end;
  ms := PyFmtFixed(v, prec);
  { rounding to `prec` digits may have carried the mantissa up to 10.xxx --
    e.g. 9.9999996 at prec=6 rounds to "10.000000" }
  if (Length(ms) >= 2) and (ms[1] = '1') and (ms[2] = '0') then
  begin
    e := e + 1;
    ms := PyFmtFixed(v / 10.0, prec);
  end;
  if e >= 0 then es := PyFmtBase(e, 10, False) else es := PyFmtBase(-e, 10, False);
  while Length(es) < 2 do es := '0' + es;
  if upper then Result := ms + 'E' else Result := ms + 'e';
  if e >= 0 then Result := Result + '+' + es else Result := Result + '-' + es;
  if neg then Result := '-' + Result;
end;

{ Trailing zeros (and a now-bare trailing '.') stripped from a PLAIN decimal
  string -- `%g`'s own rule, applied to whichever of the fixed/exponential
  forms it picked. }
function PyStripTrailingZerosPlain(const s: AnsiString): AnsiString;
var i: Integer;
begin
  if Pos('.', s) = 0 then begin Result := s; Exit; end;
  i := Length(s);
  while (i > 1) and (s[i] = '0') do Dec(i);
  if (i > 1) and (s[i] = '.') then Dec(i);
  Result := Copy(s, 1, i);
end;

{ Same, but for an EXPONENTIAL string -- strip only the mantissa (before
  'e'/'E'), leaving the exponent suffix untouched. }
function PyStripTrailingZerosExp(const s: AnsiString): AnsiString;
var epos: Integer;
begin
  epos := Pos('e', s);
  if epos = 0 then epos := Pos('E', s);
  if epos = 0 then begin Result := PyStripTrailingZerosPlain(s); Exit; end;
  Result := PyStripTrailingZerosPlain(Copy(s, 1, epos - 1)) +
            Copy(s, epos, Length(s) - epos + 1);
end;

{ `%g`/`%G`: C's rule -- `%e` when the decimal exponent is < -4 or >= the
  (significant-digit) precision, else `%f`; trailing zeros stripped either
  way. `prec` is SIGNIFICANT digits (Python defaults it to 6, and 0/absent
  means 1), unlike `%e`/`%f` where it counts digits after the point. }
function PyFmtG(v: Double; prec: Integer; upper: Boolean): AnsiString;
var e: Integer; av: Double; useExp: Boolean;
begin
  if prec <= 0 then prec := 1;
  if v <> v then begin Result := 'nan'; Exit; end;
  if v > 1.7976931348623157e308 then begin Result := 'inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin Result := '-inf'; Exit; end;
  av := v;
  if av < 0.0 then av := -av;
  e := 0;
  if av <> 0.0 then
  begin
    while av >= 10.0 do begin av := av / 10.0; e := e + 1; end;
    while av < 1.0 do begin av := av * 10.0; e := e - 1; end;
  end;
  useExp := (e < -4) or (e >= prec);
  if useExp then
    Result := PyStripTrailingZerosExp(PyFmtExp(v, prec - 1, upper))
  else
    Result := PyStripTrailingZerosPlain(PyFmtFixed(v, prec - 1 - e));
end;

function pyformat_of(d: Double; const spec: AnsiString): AnsiString; overload;
{ `{x:.2f}` and friends. Same grammar as the integer spec plus a `.precision`
  group; `f` is fixed point, `g` is FloatToStr's compact form. }
var p, width, prec, dotAt: Integer; zero, leftAlign, hasPrec, grouped, hasKind: Boolean;
    kind, fillCh, align, signCh, groupCh: Char; body, intPartS, fracPartS: AnsiString;
begin
  p := 1; zero := False; leftAlign := False; width := 0; grouped := False;
  prec := 6; hasPrec := False; hasKind := False; kind := 'f';
  fillCh := ' '; align := #0;
  if (p + 1 <= Length(spec)) and (spec[p + 1] in ['<', '>', '^']) then
  begin
    fillCh := spec[p]; align := spec[p + 1]; leftAlign := align = '<';
    Inc(p, 2);
  end
  else if (p <= Length(spec)) and (spec[p] in ['<', '>', '^']) then
  begin
    align := spec[p]; leftAlign := align = '<';
    Inc(p);
  end;
  { SIGN flag, same grammar position as the integer spec — see there }
  signCh := #0;
  if (p <= Length(spec)) and (spec[p] in ['+', '-', ' ']) then
  begin
    signCh := spec[p];
    Inc(p);
  end;
  if (p <= Length(spec)) and (spec[p] = '0') then begin zero := True; Inc(p); end;
  while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
  begin
    width := width * 10 + (Ord(spec[p]) - Ord('0'));
    Inc(p);
  end;
  { `,` — thousands grouping, between the width and the precision, same as the
    integer spec (bug-nilpy-thousands-separator-format-spec-unsupported). }
  groupCh := ',';
  if (p <= Length(spec)) and (spec[p] in [',', '_']) then
  begin
    grouped := True;
    groupCh := spec[p];
    Inc(p);
  end;
  if (p <= Length(spec)) and (spec[p] = '.') then
  begin
    Inc(p);
    prec := 0; hasPrec := True;
    while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
    begin
      prec := prec * 10 + (Ord(spec[p]) - Ord('0'));
      Inc(p);
    end;
  end;
  if p <= Length(spec) then begin kind := spec[p]; Inc(p); hasKind := True; end;
  if p <= Length(spec) then
    { catchable, not Halt — see the integer overload }
    raise ValueError.Create('unsupported format spec "' + spec + '"');
  { No explicit TYPE and no precision — `{:,}`, `{:10}` — is Python's GENERAL
    form, not fixed-point with 6 decimals: `"{:,}".format(1234.5)` is `1,234.5`,
    not `1,234.500000`. Only reachable once a spec exists but names no type,
    which before the `,` flag could not happen for a float. }
  if (not hasKind) and (not hasPrec) then kind := 'g';
  if (kind = 'f') or (kind = 'F') then body := PyFmtFixed(d, prec)
  else if (kind = 'e') or (kind = 'E') then body := PyFmtExp(d, prec, kind = 'E')
  else if kind = '%' then
    { Python's percentage form: multiply by 100, format fixed with the given
      precision (6 by default, as for `f`), append the sign. `{x:.0%}` is how a
      confidence or agreement ratio is spelled everywhere. }
    body := PyFmtFixed(d * 100.0, prec) + '%'
  else if (kind = 'g') or (kind = 'G') then body := FloatToStr(d)
  else if kind = 's' then body := FloatToStr(d)
  else
    raise ValueError.Create('unsupported format spec "' + spec + '"');
  { group only the INTEGER part: 1234.5 -> 1,234.5 }
  if grouped then
  begin
    dotAt := Pos('.', body);
    if dotAt > 0 then
    begin
      intPartS := Copy(body, 1, dotAt - 1);
      fracPartS := Copy(body, dotAt, Length(body) - dotAt + 1);
      body := PyGroupThousands(intPartS, groupCh) + fracPartS;
    end
    else
      body := PyGroupThousands(body, groupCh);
  end;
  { sign after grouping, before padding — see the integer overload }
  if (signCh <> #0) and (signCh <> '-') and (Length(body) > 0) and (body[1] <> '-') then
  begin
    if signCh = '+' then body := '+' + body else body := ' ' + body;
  end;
  if align = '^' then Result := PyFmtPadEx(body, width, fillCh, '^')
  else if fillCh <> ' ' then Result := PyFmtPadEx(body, width, fillCh, align)
  else Result := PyFmtPad(body, width, zero, leftAlign);
end;

function pyformat_of(const v: Variant; const spec: AnsiString): AnsiString; overload;
var tag: Int64;
begin
  tag := pyvartag(v);
  if tag = 6 then
  begin
    Result := pyformat_of(VariantToStr(v), spec);
    Exit;
  end;
  { Only INTEGER-like tags may go through the integer formatter: VT_INT,
    VT_INT64, VT_BOOL, VT_CHAR. A VT_DOUBLE's payload is IEEE bits, so
    formatting it as an integer would print a plausible but meaningless
    number — the silent-wrong-output case a format spec exists to avoid.
    Float specs are not implemented; say so rather than guess. }
  if (tag = 1) or (tag = 2) or (tag = 4) or (tag = 5) then
  begin
    Result := pyformat_of(PPyVarRec(@v)^.Payload, spec);
    Exit;
  end;
  { VT_DOUBLE: `{score:.1f}` is the single most common spec in real Python, so
    the float formatter runs rather than the old halt. An INTEGER-tagged value
    still gets one when the spec asks for a float form — Python formats `3` as
    `3.0` under `.1f`. }
  if tag = 3 then
  begin
    Result := pyformat_of(pyvar_to_float(v), spec);
    Exit;
  end;
  { VT_PROMO_INT64: an arbitrary-precision int whose payload IS its exact
    decimal. Formatting it as an integer is what `f"{n:d}"` and `"%d" % n` both
    reach; without this arm the latter aborted the process on a value that
    print() rendered perfectly well. }
  if tag = 8193 then
  begin
    Result := PyFormatIntEx(0, PPyAnsiString(@PPyVarRec(@v)^.Payload)^, spec);
    Exit;
  end;
  WriteLn('Nil Python: f-string format spec "', spec,
          '" on a value of variant tag ', tag, ' is not supported');
  Halt(1);
end;


function pystr_of(const s: AnsiString): AnsiString;
begin
  Result := s;
end;

function pystr_of(b: Boolean): AnsiString; overload;
begin
  { Python capitalises them; Pascal's own conversion yields 0/1 }
  if b then Result := 'True' else Result := 'False';
end;

function pystr_of(i: Int64): AnsiString; overload;
begin
  Result := StrInt(i, 0);
end;

{ Python spells the non-finite floats in LOWER case — inf / -inf / nan — while
  Pascal's FloatToStr gives Inf / -Inf / Nan, which is correct for PASCAL and
  must not change. Respelled on the NilPy conversion path only.

  Applied by float SPELLING, never to arbitrary text: a NilPy string whose value
  happens to be "Inf" must survive untouched, so every caller gates on the
  variant tag being a float before routing here
  (bug-nilpy-inf-and-nan-print-pascal-spelled). }
{ Lay `digits` / `decExp` out the way CPython's repr does. The rule is one
  comparison on `decpt`, the position of the decimal point: exponential when
  `decpt <= -4` or `decpt > 16`, fixed otherwise — which is NOT Pascal's window
  ([-3, sig], and dependent on the requested precision), so PyExDecLayout's
  sibling in sysutils cannot be borrowed for it.

  Two details that are part of the format and easy to miss: a fixed-form float
  ALWAYS shows a point (`2.0`, `100.0` — CPython's Py_DTSF_ADD_DOT_0), and the
  exponent is signed with at LEAST two digits (`3e-05`, `1e+16`, but
  `1.5e+300` — no padding past two). }
function PyFloatLayout(const digits: AnsiString; decExp: Integer): AnsiString;
var decpt, i, ae: Integer; s, es: AnsiString;
begin
  decpt := decExp + 1;
  if (decpt <= -4) or (decpt > 16) then
  begin
    s := Copy(digits, 1, 1);
    if Length(digits) > 1 then s := s + '.' + Copy(digits, 2, Length(digits) - 1);
    if decExp < 0 then begin s := s + 'e-'; ae := -decExp; end
    else begin s := s + 'e+'; ae := decExp; end;
    es := StrInt(ae, 0);
    if Length(es) < 2 then es := '0' + es;
    Result := s + es;
  end
  else if decpt <= 0 then
  begin
    s := '0.';
    for i := 1 to -decpt do s := s + '0';
    Result := s + digits;
  end
  else if decpt >= Length(digits) then
  begin
    s := digits;
    for i := Length(digits) + 1 to decpt do s := s + '0';
    Result := s + '.0';
  end
  else
    Result := Copy(digits, 1, decpt) + '.' +
              Copy(digits, decpt + 1, Length(digits) - decpt);
end;

{ Python's `repr` of a float: the SHORTEST decimal string that reads back as the
  same double, laid out by Python's rules. `str` and `repr` are the same function
  in Python 3, so this serves both.

  Shortest is found by trying precisions and CHECKING the round trip, so the
  answer is correct by construction rather than by trusting a digit-count
  heuristic — the same method sysutils' FloatToStrShortest uses, with Python's
  layout instead of Pascal's. 17 significant digits always round-trip a double,
  so the loop terminates.

  The round trip compares BITS, not doubles. It is asking IDENTITY, not
  proximity, so `=` would answer it exactly — but reading the bits says what it
  means, makes -0.0 and NaN fall out correctly instead of needing special cases,
  and is immune to an extended-precision register ever appearing in this path.

  `av` must be finite, positive and nonzero; the caller handles the rest.
  Returns '' if nothing round-tripped, which cannot happen at sig = 17. }
function PyFloatRepr(av: Double): AnsiString;
var sig, tail, decExp: Integer; ds, cand: AnsiString;
begin
  Result := '';
  for sig := 1 to 17 do
  begin
    PyExDecDigits(av, ds, decExp);
    PyExDecRound(ds, decExp, sig);
    tail := Length(ds);
    while (tail > 1) and (ds[tail] = '0') do tail := tail - 1;
    cand := PyFloatLayout(Copy(ds, 1, tail), decExp);
    if PyExDecDoubleToBits(PyStrToFloatDef(cand, 0.0)) =
       PyExDecDoubleToBits(av) then
    begin
      Result := cand;
      Exit;
    end;
  end;
end;

function PyFloatStr(d: Double): AnsiString;
var bits: Int64; av: Double; rep: AnsiString;
begin
  { Python's repr, NOT Pascal's FloatToStr. builtin.pas's FloatToStr is
    Trunc/Frac scaled to fifteen decimal places, with its own fixed/exponential
    window — correct for Pascal and observable by every Pascal program in the
    tree, so it is not changed; NilPy gets its own formatter instead. Six
    measured divergences it removes, all silent: 1/3 lost a digit and stopped
    round-tripping, 0.1+0.2 printed 0.3 (the representation error HIDDEN by
    rounding — the one most likely to be read as correct), 1e-20 printed
    1.000000000000001e-20 (different digits, not fewer), 3.0e-5 printed 0.00003
    instead of 3e-05, and 123456789.123 expanded to 123456789.122999995946884
    (bug-nilpy-float-repr-is-not-pythons-shortest-roundtrip). }
  av := d;
  if av < 0 then av := -av;
  if (d = d) and (av <= 1.7976931348623157e308) and (d <> 0) then
  begin
    rep := PyFloatRepr(av);
    if rep <> '' then
    begin
      if d < 0 then Result := '-' + rep else Result := rep;
      Exit;
    end;
  end;
  Result := FloatToStr(d);
  { NEGATIVE ZERO keeps its sign in Python: `print(-0.0)` is `-0.0`, and so is
    `float("-0.0")`. FloatToStr drops it, so the sign bit is read back from the
    IEEE 754 bits directly — a comparison cannot do this, since -0.0 = 0.0 is
    True. Not a rounding difference: the value is exact either way, only the
    printed text was wrong
    (bug-nilpy-float-print-loses-precision-vs-cpython, item 1 of the
    2026-08-02 sweep). }
  if d = 0 then
  begin
    Move(d, bits, 8);
    if bits <> 0 then Result := '-' + Result;
  end;
  if Result = 'Inf' then Result := 'inf'
  else if Result = '-Inf' then Result := '-inf'
  else if (Result = 'Nan') or (Result = 'NaN') then Result := 'nan'
  else if (Result = '-Nan') or (Result = '-NaN') then Result := 'nan';
end;

function pystr_of(d: Double): AnsiString; overload;
begin
  Result := PyFloatStr(d);
end;

function pystr_of(c: Char): AnsiString; overload;
begin
  Result := c;
end;

{ A container element arrives as a Variant. Booleans still have to come out
  Python-spelled, which VariantToStr does not do, so the tag is checked first
  (VT_BOOL = 4). }
const
  QuoteCh = #39;   { a single quote, by code point — Python's repr uses it }

function PyReprQuote(const s: AnsiString): AnsiString;
var i: Integer; ch: Char; useDq, hasSq, hasDq: Boolean;
begin
  { Python's repr prefers ' but switches to " when the string CONTAINS a single
    quote and NO double quote, so repr("it's") is "it's" and not 'it\'s'.
    When it contains BOTH, ' stays the delimiter and the embedded ' is escaped.
    (bug-nilpy-percent-r-renders-as-str-not-repr, found in the same sweep.)

    Deliberately a Boolean and two explicit branches rather than a `delim: Char`
    variable: a Char VARIABLE does not convert to a string the way a Char CONST
    does — the conversion is keyed on the expression SHAPE, not its type
    (project_string_conversion_shape_blindspot_pattern) — and the first attempt
    at this silently emitted EMPTY delimiters. }
  hasSq := False;
  hasDq := False;
  for i := 1 to Length(s) do
  begin
    if s[i] = QuoteCh then hasSq := True
    else if s[i] = '"' then hasDq := True;
  end;
  useDq := hasSq and (not hasDq);
  if useDq then Result := '"' else Result := QuoteCh;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if ch = '\' then Result := Result + '\\'
    else if ch = #10 then Result := Result + '\n'
    else if ch = #9 then Result := Result + '\t'
    else if ch = #13 then Result := Result + '\r'
    else if useDq then
    begin
      if ch = '"' then Result := Result + '\"' else Result := Result + ch;
    end
    else
    begin
      if ch = QuoteCh then Result := Result + '\' + QuoteCh else Result := Result + ch;
    end;
  end;
  if useDq then Result := Result + '"' else Result := Result + QuoteCh;
end;

function pyrepr_of(const s: AnsiString): AnsiString;
begin
  Result := PyReprQuote(s);
end;

function pyrepr_of(b: Boolean): AnsiString; overload;
begin
  Result := pystr_of(b);
end;

function pyrepr_of(i: Int64): AnsiString; overload;
begin
  Result := pystr_of(i);
end;

function pyrepr_of(d: Double): AnsiString; overload;
begin
  Result := pystr_of(d);
end;

function pyrepr_of(c: Char): AnsiString; overload;
begin
  Result := PyReprQuote(c);
end;

function pyrepr_of(const v: Variant): AnsiString; overload;
begin
  { A STRING payload gains quotes -- and so does a CHAR, which is tag 5 and was
    missing here. Python has no character type: `s[0]` is a str of length 1 and
    reprs with quotes like any other, so `{s[0]: 1}` printed `{a: 1}` where
    CPython prints `{'a': 1}`
    (bug-nilpy-char-vs-string-literal-ordering-compares-an-address). }
  if (pyvartag(v) = 6) or (pyvartag(v) = 5) then
  begin
    Result := PyReprQuote(VariantToStr(v));
    Exit;
  end;
  Result := pystr_of(v);
end;

{ repr() — see the interface. Each forwards to the pyrepr_of overload that
  already spells this type Python's way; the container pair go to the recursive
  container reprs, which is what makes repr([1, 2]) print `[1, 2]` rather than a
  class handle. }
function repr(const s: AnsiString): AnsiString;
begin
  Result := pyrepr_of(s);
end;

function repr(b: Boolean): AnsiString; overload;
begin
  Result := pyrepr_of(b);
end;

function repr(i: Int64): AnsiString; overload;
begin
  Result := pyrepr_of(i);
end;

function repr(d: Double): AnsiString; overload;
begin
  Result := pyrepr_of(d);
end;

function repr(c: Char): AnsiString; overload;
begin
  Result := pyrepr_of(c);
end;

function repr(const v: Variant): AnsiString; overload;
begin
  Result := pyrepr_of(v);
end;

function repr(l: TPyList): AnsiString; overload;
begin
  Result := pylist_repr(l);
end;

function repr(dc: TPyDict): AnsiString; overload;
begin
  Result := pydict_repr(dc);
end;

function pyabs_v(const v: Variant): Variant;
var t: Int64; d: Double; i: Int64;
    ds: AnsiString; pa: array[0..1] of NativeInt;
begin
  t := pyvartag(v);
  { VT_PROMO_INT64: the payload IS the exact decimal, so the absolute value is
    that text without its leading '-'. Reading it as a machine int first would
    narrow mod 2^64 — the whole reason this tag exists. }
  if t = 8193 then
  begin
    ds := PPyAnsiString(@PPyVarRec(@v)^.Payload)^;
    if (Length(ds) > 0) and (ds[1] = '-') then ds := Copy(ds, 2, Length(ds) - 1);
    PXXPromoInit(@pa);
    PXXPromoFromStr(@pa, ds);
    PXXPromoToVariant(@Result, @pa);
    PXXPromoClear(@pa);
    Exit;
  end;
  if t = 3 then           { VT_DOUBLE }
  begin
    d := pyvar_to_float(v);
    if d < 0.0 then d := -d;
    Result := d;
    Exit;
  end;
  if (t = 1) or (t = 2) or (t = 4) then   { VT_INT / VT_INT64 / VT_BOOL }
  begin
    i := pyvar_to_int(v);
    if i < 0 then i := -i;
    Result := i;
    Exit;
  end;
  PyTypeError(t, 'a number');
  Result := 0;
end;

{ list(v) on a variant: a str yields its characters, a list a shallow copy. }
procedure pystar_check_arity(l: TPyList; lo: Integer; hi: Integer);
var n: Integer;
begin
  n := 0;
  if l <> nil then n := l.count;
  if (n < lo) or (n > hi) then
  begin
    raise TypeError.Create('forwarded call got ' + pystr_of(Int64(n)) +
                           ' arguments, expected ' + pystr_of(Int64(lo)) +
                           ' to ' + pystr_of(Int64(hi)));
  end;
end;

procedure pystar_no_kwargs(d: TPyDict);
begin
  if (d <> nil) and (d.count > 0) then
  begin
    raise TypeError.Create('forwarding **kwargs into a callee with named parameters is not supported');
  end;
end;

function pystar_arg(l: TPyList; i: Integer): Variant;
begin
  if (l = nil) or (i < 0) or (i >= l.count) then Result := pynone()
  else Result := l.at(i);
end;

function pydict_v(const v: Variant): TPyDict;
var o: TObject;
begin
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyDict then
    begin
      { The dict INSIDE the variant is handed back as-is (unlike pylist_v, which
        copies), so the reference leaving this function is a second owner: the
        caller releases the temporary when the statement ends, and without this
        retain that release drops the variant's own reference. It freed the live
        dict under `for k, v in outer[key].items()` — a use-after-free that
        corrupted the free list and crashed a later PXXAlloc
        (bug-nilpy-pydict-v-borrowed-reference). }
      PXXObjRetain(Pointer(o));
      Result := TPyDict(o);
      Exit;
    end;
  end;
  PyTypeError(pyvartag(v), 'a dict');
  Result := TPyDict.Create;
end;

function pylist_v(const v: Variant): TPyList;
var o: TObject;
begin
  if pyvartag(v) = 6 then begin Result := list(VariantToStr(v)); Exit; end;
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := list(TPyList(o)); Exit; end;
    { A DICT yields its KEYS — `list(d)` and `for x in d` are both the key
      sequence in Python. Missing here, so iterating a dict that had been
      erased to a variant (a list element, an unannotated parameter, a value
      out of another dict) refused with "expected a str or a list", while the
      identical dict with a static type iterated fine
      (bug-nilpy-two-name-for-over-a-variant-assumes-a-dict). }
    if o is TPyDict then begin Result := TPyDict(o).keylist; Exit; end;
    { bytes erased to a variant — the byte values, same as the static arm. }
    if o is TPyBytes then begin Result := list(TPyBytes(o)); Exit; end;
  end;
  PyTypeError(pyvartag(v), 'a str, a list or a dict');
  Result := TPyList.Create;
end;

{ Python truthiness: 0, 0.0, '', [] and None are false; everything else true. }
function bool(const v: Variant): Boolean;
begin
  Result := pyvar_to_bool(v);
end;

function bool(i: Int64): Boolean; overload;
begin
  Result := i <> 0;
end;

function bool(d: Double): Boolean; overload;
begin
  Result := d <> 0.0;
end;

function bool(const s: AnsiString): Boolean; overload;
begin
  Result := Length(s) > 0;
end;

function bool(l: TPyList): Boolean; overload;
begin
  Result := (l <> nil) and (l.count > 0);
end;

function pynone: Variant;
var p: PPyVarRec;
begin
  p := PPyVarRec(@Result);
  p^.VType := 0;      { VT_EMPTY }
  p^.Payload := 0;
end;

function pystr_rjust_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
var pad: Char; i, need: Integer;
begin
  pad := ' ';
  if Length(fill) > 0 then pad := fill[1];
  need := w - Length(s);
  Result := '';
  if need > 0 then
    for i := 1 to need do Result := Result + pad;
  Result := Result + s;
end;

function pystr_rjust(const s: AnsiString; w: Int64): AnsiString;
begin
  Result := pystr_rjust_c(s, w, ' ');
end;

{ One lower-case hexadecimal digit. }
function HexDigitChar(v: Int64): AnsiString;
begin
  if v < 10 then Result := Chr(Ord('0') + v)
  else Result := Chr(Ord('a') + (v - 10));
end;

function list(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
    for i := 0 to l.count - 1 do r.append(l.at(i));
  Result := r;
end;

function tuple(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  r.FKind := PYSEQ_TUPLE;
  if l <> nil then
    for i := 0 to l.count - 1 do r.append(l.at(i));
  Result := r;
end;

function tuple(const s: AnsiString): TPyList; overload;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  r.FKind := PYSEQ_TUPLE;
  for i := 1 to Length(s) do r.append(pystr_ofchar(s[i]));
  Result := r;
end;

function list(b: TPyBytes): TPyList; overload;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if b <> nil then
    for i := 0 to b.count - 1 do r.append(b.at(i));
  Result := r;
end;

function tuple(b: TPyBytes): TPyList; overload;
var r: TPyList;
begin
  r := list(b);
  r.FKind := PYSEQ_TUPLE;
  Result := r;
end;

function pow(const a: Variant; const b: Variant): Variant;
begin
  Result := pypow_v(a, b);
end;

{ (a * b) mod m without overflowing Int64. A plain `a * b` overflows as soon as
  the operands pass 2^31 even though the RESULT is bounded by m, so the product
  is accumulated by doubling instead — every intermediate stays below 2m, which
  is why m is capped just under 2^62 rather than at Int64's range. }
function PyMulMod(a, b, m: Int64): Int64;
var r: Int64;
begin
  r := 0;
  a := a mod m;
  while b > 0 do
  begin
    if (b and 1) = 1 then r := (r + a) mod m;
    a := (a + a) mod m;
    b := b shr 1;
  end;
  PyMulMod := r;
end;

{ The modular inverse of a mod m, by the extended Euclidean algorithm: the x in
  a*x = 1 (mod m), which exists exactly when gcd(a, m) = 1. Needed by pow()'s
  NEGATIVE exponent form. Kept in plain Int64 rather than PyMulMod because every
  intermediate here is a remainder or a coefficient bounded by m, not a product
  of two of them. }
function PyModInverse(a, m: Int64): Int64;
var oldR, r, oldS, s2, q, t: Int64;
begin
  oldR := a; r := m;
  oldS := 1; s2 := 0;
  while r <> 0 do
  begin
    q := oldR div r;
    t := oldR - q * r; oldR := r; r := t;
    t := oldS - q * s2; oldS := s2; s2 := t;
  end;
  if oldR <> 1 then
    raise ValueError.Create('base is not invertible for the given modulus');
  oldS := oldS mod m;
  if oldS < 0 then oldS := oldS + m;
  PyModInverse := oldS;
end;

function pow(a, b, m: Int64): Int64; overload;
var r, base: Int64; neg: Boolean;
begin
  if m = 0 then
    raise ValueError.Create('pow() 3rd argument cannot be 0');
  neg := m < 0;
  if neg then m := -m;
  if m > (Int64(1) shl 62) then
    raise ValueError.Create('pow() 3rd argument is too large (modulus must be '
      + 'below 2^62)');
  r := 1 mod m;              { m = 1 makes every result 0, including pow(x,0,1) }
  base := a mod m;
  if base < 0 then base := base + m;
  { A NEGATIVE exponent is the modular INVERSE raised to |b| (CPython 3.8+), and
    it exists only when the base is coprime with the modulus — CPython raises
    ValueError when it is not, rather than returning something. }
  if b < 0 then
  begin
    base := PyModInverse(base, m);
    b := -b;
  end;
  while b > 0 do
  begin
    if (b and 1) = 1 then r := PyMulMod(r, base, m);
    base := PyMulMod(base, base, m);
    b := b shr 1;
  end;
  { Python's result carries the sign of the modulus: the mathematical residue
    is in [0, |m|), and a negative modulus shifts it down by |m|. }
  if neg and (r <> 0) then r := r - m;
  pow := r;
end;

{ list(v) where v is a VARIANT — copy the list/str it holds. `list(fb or [])`
  reaches this once `or` returns its operand as a variant. }
function list(const v: Variant): TPyList; overload;
var o: TObject; i: Integer;
begin
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := list(TPyList(o)); Exit; end;
    if o is TPyDict then begin Result := TPyDict(o).keylist; Exit; end;
    if o is TPyBytes then begin Result := list(TPyBytes(o)); Exit; end;
  end;
  if pyvartag(v) = 6 then begin Result := list(pystr_of(v)); Exit; end;
  Result := TPyList.Create;   { None / empty }
end;

function list(const s: AnsiString): TPyList; overload;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  for i := 1 to Length(s) do r.append(pystr_ofchar(s[i]));
  Result := r;
end;

function dict(d: TPyDict): TPyDict; overload;
var r: TPyDict; ks, vs: TPyList; i: Integer;
begin
  r := TPyDict.Create;
  if d <> nil then
  begin
    ks := d.keylist;
    vs := d.vallist;
    for i := 0 to ks.count - 1 do r.store(ks.at(i), vs.at(i));
  end;
  Result := r;
end;

{ dict(v) where v is a VARIANT holding a dict — `dict(vm.attr)` once the field
  read boxes to a variant. A non-dict (None/other) yields an empty dict. }
function dict(const v: Variant): TPyDict; overload;
var o: TObject;
begin
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyDict then begin Result := dict(TPyDict(o)); Exit; end;
  end;
  Result := TPyDict.Create;   { None / non-mapping }
end;

{ dict(pairs): each element is a (key, value) sequence. TPyDict.update(TPyList)
  already walks exactly that shape, so this is the constructor around it rather
  than a second copy of the loop — a fresh dict has FCounterMode false, so it
  takes update's pair branch, not the Counter branch. }
function dict(l: TPyList): TPyDict; overload;
var r: TPyDict;
begin
  r := TPyDict.Create;
  r.update(l);
  Result := r;
end;

function reversed(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  { Carries the tuple flag so `(1,2,3)[::-1]` is `(3, 2, 1)`: the reverse-slice
    form lowers to this very function (see the `[::-1]` arm in pyparser), and a
    slice of a tuple is a tuple. CPython's `reversed()` returns an ITERATOR
    whose repr pxx already does not reproduce, so nothing that currently matches
    the oracle moves — and `list(reversed(t))` still builds a fresh plain list.
    (bug-nilpy-derived-tuple-loses-tupleness) }
  if l <> nil then r.FKind := l.FKind;
  if l <> nil then
    for i := l.count - 1 downto 0 do r.append(l.at(i));
  Result := r;
end;

function reversed(const s: AnsiString): TPyList; overload;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  for i := Length(s) downto 1 do r.append(pystr_ofchar(s[i]));
  Result := r;
end;

function hex(n: Int64): AnsiString;
var m: Int64; d: AnsiString;
begin
  if n = 0 then begin Result := '0x0'; Exit; end;
  m := n;
  if m < 0 then m := -m;
  d := '';
  while m > 0 do
  begin
    d := HexDigitChar(m mod 16) + d;
    m := m div 16;
  end;
  if n < 0 then Result := '-0x' + d else Result := '0x' + d;
end;

function oct(n: Int64): AnsiString;
var m: Int64; d: AnsiString;
begin
  if n = 0 then begin Result := '0o0'; Exit; end;
  m := n;
  if m < 0 then m := -m;
  d := '';
  while m > 0 do
  begin
    d := HexDigitChar(m mod 8) + d;
    m := m div 8;
  end;
  if n < 0 then Result := '-0o' + d else Result := '0o' + d;
end;

function bin(n: Int64): AnsiString;
var m: Int64; d: AnsiString;
begin
  if n = 0 then begin Result := '0b0'; Exit; end;
  m := n;
  if m < 0 then m := -m;
  d := '';
  while m > 0 do
  begin
    d := HexDigitChar(m mod 2) + d;
    m := m div 2;
  end;
  if n < 0 then Result := '-0b' + d else Result := '0b' + d;
end;

{ A list slice is a SHALLOW copy, as in Python: the new list holds the same
  element values (`xs[:]` is the idiomatic shallow copy), so the slots are
  copied through append and a contained object stays shared. }
function pylist_slice(l: TPyList; lo, hi: Integer): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
  begin
    { A slice of a TUPLE is a TUPLE: `(1,2,3)[1:]` is `(2, 3)`, not `[2, 3]`.
      One sequence representation backs both, so the flag has to be carried
      explicitly by every DERIVED sequence — pylist_repeat already did this,
      slice and concat did not
      (bug-nilpy-derived-tuple-loses-tupleness). }
    r.FKind := l.FKind;
    PySliceBounds(l.count, lo, hi);
    for i := lo to hi - 1 do
      r.append(l.at(i));
  end;
  Result := r;
end;

function pylist_slice_step(l: TPyList; lo, hi, step: Integer): TPyList;
var r: TPyList; i, k, cnt: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
  begin
    { a slice of a TUPLE is a TUPLE, extended slices included — so `(1,2,3)[::-1]`
      is `(3, 2, 1)`, not `[3, 2, 1]` (bug-nilpy-derived-tuple-loses-tupleness) }
    r.FKind := l.FKind;
    cnt := PySliceBoundsStep(l.count, lo, hi, step);
    i := lo;
    for k := 1 to cnt do
    begin
      r.append(l.at(i));
      i := i + step;
    end;
  end;
  Result := r;
end;

{ `del l[lo:hi]` — remove that slice from the list IN PLACE (Python's del on a
  list slice), honouring the same PY_SLICE_OMIT bounds. Returns Self so the del
  rewrite can use it as a value node. }
function pylist_del_slice(l: TPyList; lo, hi: Integer): TPyList;
var i, gap: Integer;
begin
  Result := l;
  if l = nil then Exit;
  PySliceBounds(l.count, lo, hi);
  if hi <= lo then Exit;
  gap := hi - lo;
  { shift the tail down over the deleted range }
  for i := hi to l.count - 1 do
    l.put(i - gap, l.at(i));
  l.FLen := l.count - gap;
end;

{ `del l[i]` — remove ONE element in place. Delegates to the slice delete so
  the shifting logic exists once, but takes the index as a single argument: the
  frontend cannot build `[i:i+1]` from the parsed subscript without duplicating
  the index EXPRESSION, which would evaluate `del l[f()]` twice.

  A negative index counts from the end, and an out-of-range one raises
  IndexError — unlike a SLICE, which clamps. That asymmetry is Python's:
  `del l[99]` raises, `del l[99:]` does not
  (bug-nilpy-del-of-a-list-index-is-unsupported). }
function pylist_del_at(l: TPyList; i: Integer): TPyList;
var k: Integer;
begin
  Result := l;
  if l = nil then Exit;
  k := i;
  if k < 0 then k := k + l.count;
  if (k < 0) or (k >= l.count) then
    raise IndexError.Create('list assignment index out of range');
  pylist_del_slice(l, k, k + 1);
end;

{ `l[lo:hi] = src` — replace that slice IN PLACE with src's elements (Python's
  list slice assignment). Rebuilds the list: prefix + src + suffix. }
procedure pylist_setslice(l: TPyList; lo, hi: Integer; src: TPyList);
var keep: TPyList; i: Integer;
begin
  if l = nil then Exit;
  PySliceBounds(l.count, lo, hi);
  keep := TPyList.Create;
  for i := 0 to lo - 1 do keep.append(l.at(i));
  if src <> nil then
    for i := 0 to src.count - 1 do keep.append(src.at(i));
  for i := hi to l.count - 1 do keep.append(l.at(i));
  { copy back into l so the original handle stays valid }
  l.FLen := 0;
  for i := 0 to keep.count - 1 do l.append(keep.at(i));
end;

function pylist_repeat(l: TPyList; n: Int64): TPyList;
var r: TPyList; i, k: Integer;
begin
  r := TPyList.Create;
  { `(1, 2) * 2` is a TUPLE. The variant-dispatch repeat path already carried
    this flag; the statically-typed one did not, so it depended on which path
    the operands took (bug-nilpy-derived-tuple-loses-tupleness). }
  if l <> nil then r.FKind := l.FKind;
  if (l <> nil) and (n > 0) then
    for k := 1 to n do
      for i := 0 to l.count - 1 do
        r.append(l.at(i));
  Result := r;
end;

{ `a + b` list concatenation (Python). A fresh list of a's then b's elements. }
function pylist_concat(a, b: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  { tuple + tuple is a TUPLE; list + list is a list. Python refuses to
    concatenate the two kinds at all, so taking the LEFT operand's flag matches
    wherever the expression is legal (bug-nilpy-derived-tuple-loses-tupleness). }
  if a <> nil then r.FKind := a.FKind
  else if b <> nil then r.FKind := b.FKind;
  if a <> nil then for i := 0 to a.count - 1 do r.append(a.at(i));
  if b <> nil then for i := 0 to b.count - 1 do r.append(b.at(i));
  Result := r;
end;

{ `b * n` — Python bytes repetition (uforth FILL's `bytes([ch]) * u`).
  TPyBytes deliberately has no .append (name-collision note at the class), so
  the result is sized up front and filled with put. }
function pybytes_repeat(b: TPyBytes; n: Int64): TPyBytes;
var r: TPyBytes; i, k, w: Integer;
begin
  if (b = nil) or (n < 0) then n := 0;
  if b = nil then w := 0 else w := b.count;
  r := TPyBytes.Create(w * n);
  for k := 0 to n - 1 do
    for i := 0 to w - 1 do
      r.put(k * w + i, b.at(i));
  Result := r;
end;

{ b1 + b2 — Python bytes concatenation (uforth WRITE-LINE's `data + b'\n'`). }
function pybytes_concat(a, b: TPyBytes): TPyBytes;
var r: TPyBytes; i, na, nb: Integer;
begin
  if a = nil then na := 0 else na := a.count;
  if b = nil then nb := 0 else nb := b.count;
  r := TPyBytes.Create(na + nb);
  for i := 0 to na - 1 do r.put(i, a.at(i));
  for i := 0 to nb - 1 do r.put(na + i, b.at(i));
  Result := r;
end;

{ bytes VALUE equality (`raw == b""`): pointer compare is Python-wrong. }
function pybytes_eq(a, b: TPyBytes): Boolean;
var i, na, nb: Integer;
begin
  Result := False;
  if a = nil then na := 0 else na := a.count;
  if b = nil then nb := 0 else nb := b.count;
  if na <> nb then Exit;
  for i := 0 to na - 1 do
    if a.at(i) <> b.at(i) then Exit;
  Result := True;
end;

function pybytes_cmp(a, b: TPyBytes): Int64;
var i, na, nb, n, x, y: Integer;
begin
  if a = nil then na := 0 else na := a.count;
  if b = nil then nb := 0 else nb := b.count;
  if na < nb then n := na else n := nb;
  for i := 0 to n - 1 do
  begin
    x := a.at(i);
    y := b.at(i);
    if x < y then begin Result := -1; Exit; end;
    if x > y then begin Result := 1; Exit; end;
  end;
  { common prefix equal — the shorter sequence sorts first }
  if na < nb then Result := -1
  else if na > nb then Result := 1
  else Result := 0;
end;

function TPyBytes.endswith(sfx: TPyBytes): Boolean;
var i, n, m: Integer;
begin
  Result := False;
  n := count;
  if sfx = nil then begin Result := True; Exit; end;
  m := sfx.count;
  if m > n then Exit;
  for i := 0 to m - 1 do
    if at(n - m + i) <> sfx.at(i) then Exit;
  Result := True;
end;

{ ---- TPyFile: raw-syscall file handles (x86-64) ---- }

constructor TPyFile.Create;
begin
  FFd := -1;
end;

function pyfile_open(const path, mode: AnsiString): TPyFile;
var flags, fd: Int64; z: AnsiString; i: Integer; wantCreate, wantRW, wantAppend: Boolean;
begin
  wantCreate := False; wantRW := False; wantAppend := False;
  for i := 1 to Length(mode) do
  begin
    if mode[i] = 'w' then wantCreate := True;
    if mode[i] = 'a' then wantAppend := True;
    if mode[i] = '+' then wantRW := True;
  end;
  { 'a' was not checked at all, so append mode fell through to O_RDONLY and
    every write to it failed silently -- `open(p,"a")` then f.write(...) kept
    the earlier content and dropped the new
    (bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory). }
  if wantAppend then
    flags := PYPAL_O_RDWR + PYPAL_O_CREAT + PYPAL_O_APPEND
  else if wantCreate then flags := PYPAL_O_RDWR + PYPAL_O_CREAT + PYPAL_O_TRUNC
  else if wantRW then flags := PYPAL_O_RDWR
  else flags := PYPAL_O_RDONLY;
  z := path + #0;
  fd := PyPalOpen(PChar(z), flags, 420);          { 0644 }
  if fd < 0 then
    { CPython open() raises a CATCHABLE OSError (uforth's OPEN-FILE wraps the
      call in try/except and turns it into a nonzero ior — the Forth-2012
      DELETE-FILE test reopens a deleted file expecting failure, not a halt). }
    raise FileNotFoundError.Create(path);
  Result := TPyFile.Create;
  Result.FFd := fd;
end;

function TPyFile.read(u: Int64): TPyBytes;
var r: TPyBytes; got: Int64;
begin
  if u < 0 then u := 0;
  r := TPyBytes.Create(u);
  got := PyPalRead(FFd, r.FData, u);
  if got < 0 then got := 0;
  r.FLen := got;
  Result := r;
end;

function TPyFile.readline: TPyBytes;
var r: TPyBytes; got: Int64; ch: Byte;
begin
  { one byte at a time — line reads are rare and short in the corpus }
  r := TPyBytes.Create(0);
  while True do
  begin
    got := PyPalRead(FFd, @ch, 1);
    if got <= 0 then Break;
    r.append(ch);
    if ch = 10 then Break;
  end;
  Result := r;
end;

function TPyFile.write(b: TPyBytes): Int64;
begin
  if (b = nil) or (b.FLen = 0) then begin Result := 0; Exit; end;
  Result := PyPalWrite(FFd, b.FData, b.FLen);
end;

function TPyFile.write(const s: AnsiString): Int64;
begin
  { our strings are byte strings, so a text write is the bytes of s -- no
    encode step, matching how pyopen treats latin-1/utf-8 of ASCII as identity }
  if Length(s) = 0 then begin Result := 0; Exit; end;
  Result := PyPalWrite(FFd, @s[1], Length(s));
end;

procedure TPyFile.seek(pos: Int64);
var r: Int64;
begin
  r := PyPalLseek(FFd, pos, 0);   { SEEK_SET }
end;

procedure TPyFile.seek(pos: Int64; whence: Int64);
var r: Int64;
begin
  r := PyPalLseek(FFd, pos, whence);
end;

function TPyFile.tell: Int64;
begin
  Result := PyPalLseek(FFd, 0, 1);   { SEEK_CUR }
end;

procedure TPyFile.truncate(sz: Int64);
var r: Int64;
begin
  r := PyPalFtruncate(FFd, sz);
end;

procedure TPyFile.flush;
begin
  { raw fds are unbuffered — nothing to do }
end;

procedure TPyFile.close;
var r: Int64;
begin
  r := PyPalClose(FFd);
end;

{ repr() dispatching on the RUNTIME tag, so a container element nested inside a
  container is spelled out rather than printed as its object handle. }
{ `<function at 0x...>` for a CALLABLE VALUE. A function value used to render
  as nothing at all: a lifted bound-fn rode as VT_EMPTY (tag 0), which every
  str/print consumer reads as None, and a pyeval closure (tag 9) fell through to
  VariantToStr and produced a blank. So a debug print could not tell a live
  function from None — exactly when you are looking
  (bug-nilpy-repr-of-a-function-value-prints-none).

  CPython spells the NAME too (`<function mk.<locals>.inner at 0x...>`), and
  that is not recoverable here: the payload is a code address or a {code,recv}
  pair, neither of which carries a name at run time. The shape and the address
  are, and they are what distinguishes a function from None. Naming it would
  need the frontend to record one per callable — its own ticket if anyone wants
  byte-parity with CPython. }
function PyCallableStr(const v: Variant): AnsiString;
const HEXD = '0123456789abcdef';
var a: Int64; i: Integer; hx: AnsiString; lead: Boolean;
begin
  a := PPyVarRec(@v)^.Payload;
  hx := '';
  lead := True;
  i := (SizeOf(Pointer) * 8) - 4;
  while i >= 0 do
  begin
    if ((a shr i) and 15) <> 0 then lead := False;
    if not lead then hx := hx + HEXD[Integer((a shr i) and 15) + 1];
    i := i - 4;
  end;
  if hx = '' then hx := '0';
  if pyvartag(v) = 8 then
    Result := '<bound method at 0x' + hx + '>'
  else
    Result := '<function at 0x' + hx + '>';
end;

function pyvar_repr(const v: Variant): AnsiString;
var o: TObject;
begin
  if pyvartag(v) = 0 then begin Result := 'None'; Exit; end;   { VT_EMPTY }
  { a callable VALUE — see PyCallableStr }
  if (pyvartag(v) = 8) or (pyvartag(v) = 9) or (pyvartag(v) = 10) then
  begin Result := PyCallableStr(v); Exit; end;
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := pylist_repr(TPyList(o)); Exit; end;
    if o is TPyDict then begin Result := pydict_repr(TPyDict(o)); Exit; end;
    if o is TPyBytes then begin Result := pybytes_repr(TPyBytes(o)); Exit; end;
  end;
  Result := pyrepr_of(v);
end;

function pyvar_print_of(const v: Variant): AnsiString;
var o: TObject;
begin
  if (pyvartag(v) = 8) or (pyvartag(v) = 9) or (pyvartag(v) = 10) then
  begin Result := PyCallableStr(v); Exit; end;
  { a container prints as its repr; every scalar as plain str (no quotes) }
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := pylist_repr(TPyList(o)); Exit; end;
    if o is TPyDict then begin Result := pydict_repr(TPyDict(o)); Exit; end;
    if o is TPyBytes then begin Result := pybytes_repr(TPyBytes(o)); Exit; end;
  end;
  Result := pystr_of(v);
end;

function pyprint_star(l: TPyList; leadSep: Boolean): AnsiString;
var i: Integer;
begin
  Result := '';
  if l = nil then Exit;
  for i := 0 to l.count - 1 do
  begin
    if (i > 0) or leadSep then Result := Result + ' ';
    Result := Result + pyvar_print_of(l[i]);
  end;
end;

function pylist_mark_tuple(l: TPyList): TPyList;
begin
  if l <> nil then l.FKind := PYSEQ_TUPLE;
  pylist_mark_tuple := l;
end;

function pylist_mark_set(l: TPyList): TPyList;
begin
  if l <> nil then l.FKind := PYSEQ_SET;
  pylist_mark_set := l;
end;

function PySeqKindName(k: Integer): AnsiString;
begin
  if k = PYSEQ_TUPLE then PySeqKindName := 'tuple'
  else if k = PYSEQ_SET then PySeqKindName := 'set'
  else PySeqKindName := 'list';
end;

function pyseq_kind_v(const v: Variant): Integer;
var o: Pointer;
begin
  pyseq_kind_v := -1;
  if pyvartag(v) <> 7 then Exit;          { not an object }
  o := pyvarobj(v);
  if o = nil then Exit;
  if not (TObject(o) is TPyList) then Exit;
  pyseq_kind_v := TPyList(o).FKind;
end;

function pylist_repr(l: TPyList): AnsiString;
var i: Integer;
begin
  if l = nil then begin Result := '[]'; Exit; end;
  { CPython has no empty-set DISPLAY — `{}` is an empty dict — so it reprs an
    empty set as `set()`. Special-cased here for the same reason the one-element
    tuple keeps its comma below: the general form would be ambiguous. }
  if (l.FKind = PYSEQ_SET) and (l.count = 0) then
  begin
    Result := 'set()';
    Exit;
  end;
  if l.FKind = PYSEQ_TUPLE then Result := '('
  else if l.FKind = PYSEQ_SET then Result := '{'
  else Result := '[';
  for i := 0 to l.count - 1 do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + pyvar_repr(l.at(i));
  end;
  { Python's one-element tuple keeps its comma — `(1,)` — because `(1)` is just
    a parenthesised value. }
  if (l.FKind = PYSEQ_TUPLE) and (l.count = 1) then Result := Result + ',';
  if l.FKind = PYSEQ_TUPLE then Result := Result + ')'
  else if l.FKind = PYSEQ_SET then Result := Result + '}'
  else Result := Result + ']';
end;

function pydict_repr(d: TPyDict): AnsiString;
var i: Integer; ks: TPyList; k: Variant;
begin
  if d = nil then begin Result := '{}'; Exit; end;
  Result := '{';
  ks := d.keylist;
  for i := 0 to ks.count - 1 do
  begin
    if i > 0 then Result := Result + ', ';
    k := ks.at(i);
    Result := Result + pyvar_repr(k) + ': ' + pyvar_repr(d.fetch(k));
  end;
  Result := Result + '}';
end;

{ CPython bytes repr: b'...' with printable ASCII kept, \t \n \r named, the
  rest as \xHH. Like CPython, the quote flips to double quotes when the data
  contains a single quote but no double quote. }
function pybytes_repr(b: TPyBytes): AnsiString;
var i, c: Integer; q: Char; hasSq, hasDq: Boolean;
const HexD: array[0..15] of Char = ('0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f');
begin
  hasSq := False; hasDq := False;
  if b <> nil then
    for i := 0 to b.count - 1 do
    begin
      c := b.at(i);
      if c = 39 then hasSq := True
      else if c = 34 then hasDq := True;
    end;
  if hasSq and (not hasDq) then q := '"' else q := '''';
  Result := 'b' + q;
  if b <> nil then
    for i := 0 to b.count - 1 do
    begin
      c := b.at(i);
      if c = 92 then Result := Result + '\\'
      else if c = Ord(q) then Result := Result + '\' + q
      else if c = 9 then Result := Result + '\t'
      else if c = 10 then Result := Result + '\n'
      else if c = 13 then Result := Result + '\r'
      else if (c >= 32) and (c <= 126) then Result := Result + Chr(c)
      else
      begin
        Result := Result + '\x' + HexD[(c shr 4) and 15] + HexD[c and 15];
      end;
    end;
  Result := Result + q;
end;

function pystr_of(const v: Variant): AnsiString; overload;
begin
  { VT_EMPTY is Python's None, not an empty string }
  if pyvartag(v) = 0 then begin Result := 'None'; Exit; end;
  if (pyvartag(v) = 8) or (pyvartag(v) = 9) or (pyvartag(v) = 10) then
  begin Result := PyCallableStr(v); Exit; end;
  if pyvartag(v) = 4 then
  begin
    if PPyVarRec(@v)^.Payload <> 0 then Result := 'True' else Result := 'False';
    Exit;
  end;
  { a FLOAT payload goes through PyFloatStr for the inf/nan spelling; gated on
    the tag so a string reading "Inf" is not rewritten }
  if pyvartag(v) = 3 then
  begin
    Result := PyFloatStr(PPyDouble(@PPyVarRec(@v)^.Payload)^);
    Exit;
  end;
  Result := VariantToStr(v);
end;

end.
