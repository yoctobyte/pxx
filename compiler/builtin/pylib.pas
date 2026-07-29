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
uses pypal;

const
  { An omitted slice bound, as emitted by the frontend for `b[:hi]` / `b[lo:]`.
    See the slice functions below for why a sentinel is safe here. }
  PY_SLICE_OMIT = 2147483647;

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
    constructor Create;
    function append(const v: Variant): TPyList;
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
    function pop: Variant; overload;
    function pop(i: Integer): Variant; overload;   { list.pop(index) — Python removes at i }
    function pop_at(i: Integer): Variant;
    procedure insert(i: Integer; const v: Variant);
    { Python's `xs += ys` / xs.extend(ys): IN-PLACE, appending ys's elements.
      `+` on two lists would add the two class HANDLES
      (bug-a-nilpy-list-augmented-add-segfaults). }
    function extend(other: TPyList): TPyList;
    procedure clear;
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
    procedure remove(const k: Variant);
    { dict.pop(key, default): remove the key and return its value, or return
      `default` if absent (never raises in the two-argument form uforth uses). }
    function pop(const k: Variant; const d: Variant): Variant;
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
    procedure update(l: TPyList);
    procedure update(d: TPyDict); overload;
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
  TypeError         = class(Exception) end;
  IndexError        = class(Exception) end;
  KeyError          = class(Exception) end;
  OSError           = class(Exception) end;
  AttributeError    = class(Exception) end;
  EOFError          = class(Exception) end;
  KeyboardInterrupt = class(Exception) end;
  ZeroDivisionError = class(Exception) end;
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
    function write(b: TPyBytes): Int64;
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
{ Python's repr() of a CONTAINER. print(xs) is the most natural debugging line
  in Python, and it used to print the TPyList instance POINTER — the container
  fell through to the integer path (bug-a-nilpy-print-of-a-list-prints-a-pointer).
  Recursive: a nested list/dict element is reprd as a container, not as its
  object tag. }
function pylist_repr(l: TPyList): AnsiString;
function pybytes_repr(b: TPyBytes): AnsiString;
function pydict_repr(d: TPyDict): AnsiString;
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
function bytes(b: TPyBytes): TPyBytes;
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
function pylist_del_slice(l: TPyList; lo, hi: Integer): TPyList;   { del l[lo:hi] in place }
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
function pyos_path_dirname(const p: AnsiString): AnsiString;
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

function pybound_new(code, recv: Pointer): Variant;
function pybound_code(const v: Variant): Pointer;
function pybound_recv(const v: Variant): Pointer;
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
function pymul_v(const a: Variant; const b: Variant): Variant;
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
function pyfile_open(const path, mode: AnsiString): TPyFile;
{ `s.rjust(w)` / `s.rjust(w, fill)` — right-align in a field of w characters.
  Python returns the string UNCHANGED when it is already at least that long
  (it never truncates), and the fill defaults to a space. }
function pystr_rjust(const s: AnsiString; w: Int64): AnsiString;
function pystr_rjust_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
function pyfloordiv_i(a: Int64; b: Int64): Int64;
function pyfloormod_i(a: Int64; b: Int64): Int64;
function pyfloordiv_f(a: Double; b: Double): Double;
function pyfloormod_f(a: Double; b: Double): Double;
function min(a: Int64; b: Int64): Int64;
function min(a: Double; b: Double): Double; overload;
function max(a: Int64; b: Int64): Int64; overload;
function max(a: Double; b: Double): Double; overload;
{ `list(x)` — a shallow COPY, as Python's list() constructor makes. Overloads
  rather than one variant-taking function so the ordinary call path resolves
  them by argument type, like min/max (feature-nilpy-missing-builtins). }
function list(l: TPyList): TPyList;
function list(const s: AnsiString): TPyList; overload;
function list(const v: Variant): TPyList; overload;
{ `dict(x)` — a shallow COPY of a mapping, as Python's dict() constructor makes.
  Same overload-by-argument-type shape as list() (feature-nilpy-missing-builtins).
  uforth uses `dict(vm.dict)` to snapshot word-list state for MARKER. }
function dict(d: TPyDict): TPyDict;
function dict(const v: Variant): TPyDict; overload;

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
{ Python's TWO-argument round(x, ndigits) — a float rounded to that many
  decimals, unlike the one-argument form which yields an int. Half-away-from-
  zero rather than CPython's banker's rounding: the difference shows only on an
  exact .5 at the last digit, and matching it needs decimal arithmetic. }
function pyround_n(x: Double; n: Integer): Double;
function pynext_first(l: TPyList): Variant;
function pynext_first_or(l: TPyList; const dflt: Variant): Variant;
function sum(l: TPyList): Variant;
function max(l: TPyList): Variant; overload;
function min(l: TPyList): Variant; overload;
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
function len(const s: AnsiString): Integer; overload;
{ len() of a VARIANT — a dynamically-typed value (a list element, a dataclass
  field, anything the frontend could not pin to a class). Without it, `len(x)`
  on such a value was a compile error listing only the class and string
  overloads, which is a wall for ordinary Python. }
function len(const v: Variant): Integer; overload;
function next(c: TPyCounter): Int64;
function pyvar_holds(const v: Variant; k: Int64): Boolean;
function pycontains(l: TPyList; const v: Variant): Boolean;
function pyvar_contains(const c: Variant; const v: Variant): Boolean;
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
    writeln('TypeError: ord() expected a character, but string of length ',
            Length(s), ' found');
    Halt(1);
  end;
  Result := Ord(s[1]);
end;

function pystr_at(const s: AnsiString; i: Integer): Char;
var n: Integer;
begin
  n := Length(s);
  if i < 0 then i := n + i;
  if (i < 0) or (i >= n) then
  begin
    writeln('IndexError: string index out of range');
    Halt(1);
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
    writeln('ValueError: empty separator');
    Halt(1);
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
    writeln('ValueError: empty separator');
    Halt(1);
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
var i: Integer;
    v: Variant;
    tag: Int64;
begin
  Result := '';
  for i := 0 to l.count - 1 do
  begin
    v := l.at(i);
    tag := pyvartag(v);
    if (tag <> 6) and (tag <> 5) then
    begin
      writeln('TypeError: sequence item ', i, ': expected str instance');
      Halt(1);
    end;
    if i > 0 then Result := Result + sep;
    Result := Result + VariantToStr(v);
  end;
end;

function pyvarobj(const v: Variant): Pointer;
begin
  Result := Pointer(PPyVarRec(@v)^.Payload);
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
      raise Exception.Create('TypeError: ' + nm + ' is a bound method taking too '
        + 'many arguments to call through a name (max 3)');
    end;
    Result := pybound_code(v);
  end
  else
    Result := Pointer(PPyVarRec(@v)^.Payload);
  if Result = nil then
  begin
    if what = '' then nm := 'object' else nm := what;
    raise Exception.Create('TypeError: ' + nm + ' is not callable — the name is '
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
  if pydynattr_has(obj, name) then
    Result := PyDynAttrStore.fetch(PyDynAttrKey(obj, name))
  else
  begin
    { Python raises AttributeError; None is returned here because uforth always
      guards a dynamic read with hasattr first. }
    PPyVarRec(@Result)^.VType := 0;
    PPyVarRec(@Result)^.Payload := 0;
  end;
end;

function pyvar_getitem(const v: Variant; const key: Variant): Variant;
var o: TObject; ki: Int64;
begin
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
  begin
    WriteLn('TypeError: object is not subscriptable');
    Halt(1);
  end;
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
    begin
      WriteLn('TypeError: object is not subscriptable');
      Halt(1);
    end;
  end
  else
  begin
    WriteLn('TypeError: object is not subscriptable');
    Halt(1);
  end;
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
    WriteLn('TypeError: object does not support item assignment');
    Halt(1);
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
begin
  writeln('IndexError: list index out of range');
  Halt(1);
end;

constructor TPyList.Create;
begin
  { first construction installs the recursive finalizer (slice 3) }
  PXXObjFinalizeHook := @PyObjFinalize;
  FLen := 0;
  FCap := 0;
  FItems := nil;
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
  PyVarSlotIsObj := (t = 7) or (t = 8) or (t = 9);   { 9 = pyeval closure }
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

function TPyList.append(const v: Variant): TPyList;
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

function TPyList.extend(other: TPyList): TPyList;
var
  i, n: Integer;
  src, dst: PPyVarRec;
begin
  Result := Self;
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

procedure TPyList.insert(i: Integer; const v: Variant);
var
  k: Integer;
  src, dst: PPyVarRec;
begin
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
    end;
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
begin
  WriteLn('KeyError');
  Halt(1);
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
var h: NativeUInt; sp: PPyAnsiString; ol: TObject; k: Integer;
begin
  if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) then
    h := NativeUInt(p^.Payload)
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

procedure TPyDict.remove(const k: Variant);
var
  i, j: Integer;
  src, dst: PPyVarRec;
begin
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
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  if ((pa^.VType = 6) or (pa^.VType = 5)) and ((pb^.VType = 6) or (pb^.VType = 5)) then
  begin
    pyvar_gt := PyVarText(pa) > PyVarText(pb);
    Exit;
  end;
  if ((pa^.VType = 6) or (pa^.VType = 5)) or ((pb^.VType = 6) or (pb^.VType = 5)) then
  begin
    WriteLn('TypeError: comparison of a string with a number');
    Halt(1);
  end;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
    pyvar_gt := PyVarAsFloat(pa) > PyVarAsFloat(pb)
  else
    pyvar_gt := pyvar_to_int(a) > pyvar_to_int(b);
end;

function pyround_n(x: Double; n: Integer): Double;
var scale: Double; i: Integer;
begin
  scale := 1.0;
  for i := 1 to n do scale := scale * 10.0;
  if x >= 0.0 then pyround_n := Trunc(x * scale + 0.5) / scale
  else pyround_n := -(Trunc(-x * scale + 0.5) / scale);
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
    pair.append(i);
    pair.append(a.at(i));
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    r.append(pv);
  end;
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

function max(l: TPyList): Variant;
var i: Integer;
begin
  if (l = nil) or (l.count = 0) then
  begin
    WriteLn('ValueError: max() arg is an empty sequence');
    Halt(1);
  end;
  Result := l.at(0);
  for i := 1 to l.count - 1 do
    if pyvar_gt(l.at(i), Result) then Result := l.at(i);
end;

function min(l: TPyList): Variant;
var i: Integer;
begin
  if (l = nil) or (l.count = 0) then
  begin
    WriteLn('ValueError: min() arg is an empty sequence');
    Halt(1);
  end;
  Result := l.at(0);
  for i := 1 to l.count - 1 do
    if pyvar_gt(Result, l.at(i)) then Result := l.at(i);
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
  Result := r;
  if pyvartag(v) = 6 then
  begin
    sv := pystr_of(v);
    for i := 1 to Length(sv) do r.add(pystr_ofchar(sv[i]));
    Exit;
  end;
  if pyvartag(v) <> 7 then
  begin
    WriteLn('TypeError: set() argument must be iterable');
    Halt(1);
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
  WriteLn('TypeError: set() argument must be iterable');
  Halt(1);
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

procedure TPyDict.update(l: TPyList);
var i: Integer; k, pair: Variant; pl: TPyList; o: TObject;
begin
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
procedure TPyDict.update(d: TPyDict);
var ks, vs: TPyList; i: Integer; k: Variant;
begin
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

function PyVarIsFloat(p: PPyVarRec): Boolean;
begin
  PyVarIsFloat := p^.VType = 3;
end;

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

procedure PyTypeError(t: Int64; const want: AnsiString);
begin
  writeln('TypeError: expected ', want, ', got ', PyVarTypeName(t));
  Halt(219);
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
begin
  p := PPyVarRec(@v);
  if p^.VType = 3 then
    Result := PPyDouble(@p^.Payload)^
  else if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) then
    Result := p^.Payload
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
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
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
    PPyDouble(@r^.Payload)^ := PyVarAsFloat(pa) * PyVarAsFloat(pb);
  end
  else
  begin
    r^.VType := 2;
    r^.Payload := pa^.Payload * pb^.Payload;
  end;
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
    dv := pyfloordiv_f(PyVarAsFloat(pa), PyVarAsFloat(pb));
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := dv;
  end
  else
  begin
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
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    dv := pyfloormod_f(PyVarAsFloat(pa), PyVarAsFloat(pb));
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := dv;
  end
  else
  begin
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
begin
  Result := pyvar_of_int(pyvar_to_int(v));
end;

function pyadd_v(const a: Variant; const b: Variant): Variant;
var pa, pb, r: PPyVarRec; concat: AnsiString;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
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
    PPyDouble(@r^.Payload)^ := PyVarAsFloat(pa) + PyVarAsFloat(pb);
  end
  else
  begin
    r^.VType := 2;
    r^.Payload := pyvar_to_int(a) + pyvar_to_int(b);
  end;
end;

function pysub_v(const a: Variant; const b: Variant): Variant;
var pa, pb, r: PPyVarRec;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b); r := PPyVarRec(@Result);
  r^.VType := 0; r^.Payload := 0;
  if PyVarIsFloat(pa) or PyVarIsFloat(pb) then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := PyVarAsFloat(pa) - PyVarAsFloat(pb);
  end
  else
  begin
    r^.VType := 2;
    r^.Payload := pyvar_to_int(a) - pyvar_to_int(b);
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

function pycmp_v(const a: Variant; const b: Variant): Int64;
var pa, pb: PPyVarRec; sa, sb: AnsiString; fa, fb: Double; ia, ib: Int64;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
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
    fa := PyVarAsFloat(pa); fb := PyVarAsFloat(pb);
    if fa < fb then Result := -1
    else if fa > fb then Result := 1
    else Result := 0;
    Exit;
  end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b);
  if ia < ib then Result := -1
  else if ia > ib then Result := 1
  else Result := 0;
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
  if p^.VType <> 6 then
  begin
    writeln('Runtime error: cannot repeat a non-string value');
    Halt(219);
  end;
  { the `PPyAnsiString(@p^.Payload)^` deref arg is owned by the isNilPy arg
    lowering (bug-a-nilpy-managed-deref-to-const-arg-leaks), so no per-site
    bind is needed. }
  Result := pystr_repeat(PPyAnsiString(@p^.Payload)^, n);
end;

function pystr_repeat(const s: AnsiString; n: Int64): AnsiString;
var
  i: Int64;
begin
  Result := '';
  if n <= 0 then Exit;
  for i := 1 to n do
    Result := Result + s;
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
    writeln('Runtime error: int() got a string that is not a number: ', s);
    Halt(219);
  end;
  Result := v;
end;

function pyfloordiv_i(a: Int64; b: Int64): Int64;
var q, r: Int64;
begin
  q := a div b;
  r := a mod b;
  if (r <> 0) and ((r < 0) <> (b < 0)) then q := q - 1;
  Result := q;
end;

function pyfloormod_i(a: Int64; b: Int64): Int64;
var r: Int64;
begin
  r := a mod b;
  if (r <> 0) and ((r < 0) <> (b < 0)) then r := r + b;
  Result := r;
end;

function pyfloordiv_f(a: Double; b: Double): Double;
var q: Double;
begin
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


function pystr_contains(const s: AnsiString; const sub: AnsiString): Boolean;
begin
  { the empty string is contained in everything, as in Python }
  Result := (Length(sub) = 0) or (pystr_find(s, sub) >= 0);
end;

procedure PyBytesIndexError;
begin
  WriteLn('IndexError: bytearray index out of range');
  Halt(1);
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
    WriteLn('ValueError: byte must be in range(0, 256)');
    Halt(1);
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
    WriteLn('ValueError: byte must be in range(0, 256)');
    Halt(1);
  end;
  PyBytesEnsure(Self, FLen + 1);
  p := PByte(NativeInt(FData) + (FLen - 1));
  p^ := v;
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
  WriteLn('TypeError: byte slice assignment requires bytes');
  Halt(1);
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
      WriteLn('OverflowError: can''t convert negative int to unsigned');
      Halt(1);
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
    WriteLn('OverflowError: int too big to convert');
    Halt(1);
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
var i, n, digits: Integer; neg, seenDot, seenExp: Boolean; body: AnsiString;
    intPart, frac, scale, expSign, expVal: Double;
begin
  body := s;
  i := 1; n := Length(body);
  while (i <= n) and ((body[i] = ' ') or (body[i] = #9)) do Inc(i);
  while (n >= i) and ((body[n] = ' ') or (body[n] = #9)) do Dec(n);
  body := Copy(body, i, n - i + 1);
  if Length(body) = 0 then
    raise ValueError.Create('could not convert string to float');

  neg := False;
  i := 1;
  if (body[i] = '-') or (body[i] = '+') then
  begin
    neg := body[i] = '-';
    Inc(i);
  end;

  intPart := 0; frac := 0; scale := 1;
  seenDot := False; seenExp := False; digits := 0;
  expSign := 1; expVal := 0;
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
      begin
        if body[i] = '-' then expSign := -1;
        Inc(i);
      end;
      if (i > Length(body)) or (body[i] < '0') or (body[i] > '9') then
        raise ValueError.Create('could not convert string to float');
      while (i <= Length(body)) and (body[i] >= '0') and (body[i] <= '9') do
      begin
        expVal := expVal * 10 + (Ord(body[i]) - Ord('0'));
        Inc(i);
      end;
      Continue;
    end;
    if (body[i] < '0') or (body[i] > '9') then
      raise ValueError.Create('could not convert string to float');
    Inc(digits);
    if seenDot then
    begin
      scale := scale * 10;
      frac := frac + (Ord(body[i]) - Ord('0')) / scale;
    end
    else
      intPart := intPart * 10 + (Ord(body[i]) - Ord('0'));
    Inc(i);
  end;
  if digits = 0 then
    raise ValueError.Create('could not convert string to float');

  Result := intPart + frac;
  if seenExp then
    while expVal > 0 do
    begin
      if expSign > 0 then Result := Result * 10 else Result := Result / 10;
      expVal := expVal - 1;
    end;
  if neg then Result := -Result;
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
    raise OSError.Create('FileNotFoundError: ' + path);
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
    raise OSError.Create('FileNotFoundError: ' + src);
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
    raise OSError.Create('FileNotFoundError: ' + path);
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
  TPyBoundRec = record Code, Recv: Pointer; end;
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

function pybound_new(code, recv: Pointer): Variant;
var b: PPyBoundRec; r: PPyVarRec;
begin
  { RAW refcounted block (no VMT): rc at [b-16], PXX_OBJ_MAGIC_RAW at [b-8].
    The pair OWNS +1 on its receiver; PyObjFinalize's raw arm drops it when
    the pair dies (feature-nilpy-object-reclamation slice 3). }
  PXXObjFinalizeHook := @PyObjFinalize;
  b := PPyBoundRec(PXXObjAllocRaw(SizeOf(TPyBoundRec)));
  b^.Code := code;
  b^.Recv := recv;
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

function pycallback_is(const cb: Variant): Boolean;
begin
  pycallback_is := PPyVarRec(@cb)^.VType = 8;
end;

function pycallback_call0(const cb: Variant): Int64;
{ NOTE the empty parens on f0(): a bare procedural-variable NAME is not a call
  here, it is the pointer value — `pycallback_call0 := f0` silently assigned the
  code address and never invoked the callback, which is why a zero-argument
  `command=`/`after` handler did nothing at all. }
var code, recv: Pointer; m0: TPyCbM0; f0: TPyCbF0; r: Variant;
begin
  pycallback_call0 := 0;
  r := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  recv := pybound_recv(cb);
  if code = nil then Exit;
  if recv = nil then
  begin
    f0 := TPyCbF0(code);
    r := f0();
  end
  else
  begin
    m0 := TPyCbM0(code);
    r := m0(recv);
  end;
end;

function pycallback_call1(const cb: Variant; const a0: Variant): Int64;
var code, recv: Pointer; m1: TPyCbM1; f1: TPyCbF1; r: Variant;
begin
  pycallback_call1 := 0;
  r := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  recv := pybound_recv(cb);
  if code = nil then Exit;
  if recv = nil then
  begin
    f1 := TPyCbF1(code);
    r := f1(a0);
  end
  else
  begin
    m1 := TPyCbM1(code);
    r := m1(recv, a0);
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
var code, recv: Pointer; m0: TPyCbM0; f0: TPyCbF0;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  if recv = nil then begin f0 := TPyCbF0(code); Result := f0(); end
  else begin m0 := TPyCbM0(code); Result := m0(recv); end;
end;

function pybound_callv1(const cb: Variant; const a0: Variant): Variant;
var code, recv: Pointer; m1: TPyCbM1; f1: TPyCbF1;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  if recv = nil then begin f1 := TPyCbF1(code); Result := f1(a0); end
  else begin m1 := TPyCbM1(code); Result := m1(recv, a0); end;
end;

function pybound_callv2(const cb: Variant; const a0, a1: Variant): Variant;
var code, recv: Pointer; m2: TPyCbM2; f2: TPyCbF2;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  if recv = nil then begin f2 := TPyCbF2(code); Result := f2(a0, a1); end
  else begin m2 := TPyCbM2(code); Result := m2(recv, a0, a1); end;
end;

function pybound_callv3(const cb: Variant; const a0, a1, a2: Variant): Variant;
var code, recv: Pointer; m3: TPyCbM3; f3: TPyCbF3;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  if recv = nil then begin f3 := TPyCbF3(code); Result := f3(a0, a1, a2); end
  else begin m3 := TPyCbM3(code); Result := m3(recv, a0, a1, a2); end;
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

function pyselect_select(const r: Variant; const w: Variant; const x: Variant; const t: Variant): TPyList;
var res: TPyList;
begin
  res := TPyList.Create;
  res.append(TPyList.Create);        { rlist — nothing ready }
  res.append(TPyList.Create);        { wlist }
  res.append(TPyList.Create);        { xlist }
  Result := res;
end;

function pyopen(const path: AnsiString): TPyList;
var content, line: AnsiString; ok: Boolean; i, n: Integer;
begin
  Result := TPyList.Create;
  content := pyfile_slurp(path, ok);
  if not ok then
  begin
    WriteLn('FileNotFoundError: ', path);
    Halt(1);
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

function bytes(b: TPyBytes): TPyBytes;
var k: Integer; src, dst: PByte;
begin
  { A LIST argument binds to this overload too (class-arg overload resolution
    is not identity-precise): hand it to the from-list builder. }
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
  else if zero and (Length(s) > 0) and (s[1] = '-') then
    { zero padding goes AFTER the sign: {-5:04d} is -005, not 0-05 }
    Result := '-' + pad + Copy(s, 2, Length(s) - 1)
  else
    Result := pad + s;
end;

{ Supported spec grammar, deliberately small and checked rather than guessed:
    [ '<' | '>' ] [ '0' ] [ width ] [ 'd' | 'x' | 'X' | 'o' | 'b' | 's' ]
  Anything else halts with the spec quoted, because a format spec decides what
  is PRINTED and silently ignoring one produces wrong output. }
{ The placeholder walk. Two variants rather than an open array: an open array
  of Variant is not marshalled correctly here and crashed on the second
  argument. }
function PyFormatApply(const fmt: AnsiString; const a: Variant; const b: Variant;
                       nArgs: Integer): AnsiString;
var i, j, argi: Integer; spec, outS: AnsiString;
begin
  outS := '';
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
      j := i + 1;
      spec := '';
      while (j <= Length(fmt)) and (fmt[j] <> '}') do
      begin
        if fmt[j] = ':' then
        begin
          Inc(j);
          spec := '';
          while (j <= Length(fmt)) and (fmt[j] <> '}') do
          begin spec := spec + fmt[j]; Inc(j); end;
          Break;
        end;
        Inc(j);
      end;
      if argi >= nArgs then
        raise Exception.Create('str.format: more placeholders than arguments');
      if argi = 0 then
      begin
        if spec = '' then outS := outS + pystr_of(a)
        else outS := outS + pyformat_of(a, spec);
      end
      else
      begin
        if spec = '' then outS := outS + pystr_of(b)
        else outS := outS + pyformat_of(b, spec);
      end;
      Inc(argi);
      i := j + 1;
      Continue;
    end;
    outS := outS + fmt[i];
    Inc(i);
  end;
  PyFormatApply := outS;
end;

function pystr_format(const fmt: AnsiString; const a: Variant): AnsiString;
begin
  pystr_format := PyFormatApply(fmt, a, a, 1);
end;

function pyformat_of(i: Int64; const spec: AnsiString): AnsiString;
var p, width: Integer; zero, leftAlign: Boolean; kind: Char; body: AnsiString;
begin
  p := 1;
  zero := False;
  leftAlign := False;
  width := 0;
  kind := 'd';
  if (p <= Length(spec)) and ((spec[p] = '<') or (spec[p] = '>')) then
  begin
    leftAlign := spec[p] = '<';
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
  { a FLOAT spec on an integer value — Python prints `{2:.1f}` as `2.0`, and an
    int is exactly representable, so hand it to the float formatter }
  if (p <= Length(spec)) and (spec[p] = '.') then
  begin
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
    Result := pyformat_of(pyfloat_ofint(i), spec);
    Exit;
  end;
  if p <= Length(spec) then
  begin
    WriteLn('Nil Python: unsupported f-string format spec "', spec, '"');
    Halt(1);
  end;
  case kind of
    'd': body := PyFmtBase(i, 10, False);
    'x': body := PyFmtBase(i, 16, False);
    'X': body := PyFmtBase(i, 16, True);
    'o': body := PyFmtBase(i, 8, False);
    'b': body := PyFmtBase(i, 2, False);
    's': body := PyFmtBase(i, 10, False);
  else
    begin
      WriteLn('Nil Python: unsupported f-string format spec "', spec, '"');
      Halt(1);
    end;
  end;
  Result := PyFmtPad(body, width, zero, leftAlign);
end;

function pyformat_of(const s: AnsiString; const spec: AnsiString): AnsiString; overload;
var p, width: Integer; leftAlign: Boolean;
begin
  p := 1;
  leftAlign := False;
  width := 0;
  if (p <= Length(spec)) and ((spec[p] = '<') or (spec[p] = '>')) then
  begin
    leftAlign := spec[p] = '<';
    Inc(p);
  end;
  while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
  begin
    width := width * 10 + (Ord(spec[p]) - Ord('0'));
    Inc(p);
  end;
  if (p <= Length(spec)) and (spec[p] = 's') then Inc(p);
  if p <= Length(spec) then
  begin
    WriteLn('Nil Python: unsupported f-string format spec "', spec, '" for a string');
    Halt(1);
  end;
  { a string left-aligns by default, unlike a number }
  if width > Length(s) then leftAlign := leftAlign or (spec = '') or
                                         ((Length(spec) > 0) and (spec[1] <> '>'));
  Result := PyFmtPad(s, width, False, leftAlign);
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

function pyformat_of(d: Double; const spec: AnsiString): AnsiString; overload;
{ `{x:.2f}` and friends. Same grammar as the integer spec plus a `.precision`
  group; `f` is fixed point, `g` is FloatToStr's compact form. }
var p, width, prec: Integer; zero, leftAlign, hasPrec: Boolean;
    kind: Char; body: AnsiString;
begin
  p := 1; zero := False; leftAlign := False; width := 0;
  prec := 6; hasPrec := False; kind := 'f';
  if (p <= Length(spec)) and ((spec[p] = '<') or (spec[p] = '>')) then
  begin
    leftAlign := spec[p] = '<';
    Inc(p);
  end;
  if (p <= Length(spec)) and (spec[p] = '0') then begin zero := True; Inc(p); end;
  while (p <= Length(spec)) and (spec[p] >= '0') and (spec[p] <= '9') do
  begin
    width := width * 10 + (Ord(spec[p]) - Ord('0'));
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
  if p <= Length(spec) then begin kind := spec[p]; Inc(p); end;
  if p <= Length(spec) then
  begin
    WriteLn('Nil Python: unsupported f-string format spec "', spec, '"');
    Halt(1);
  end;
  if (kind = 'f') or (kind = 'F') then body := PyFmtFixed(d, prec)
  else if kind = '%' then
    { Python's percentage form: multiply by 100, format fixed with the given
      precision (6 by default, as for `f`), append the sign. `{x:.0%}` is how a
      confidence or agreement ratio is spelled everywhere. }
    body := PyFmtFixed(d * 100.0, prec) + '%'
  else if (kind = 'g') or (kind = 'G') then body := FloatToStr(d)
  else if kind = 's' then body := FloatToStr(d)
  else
  begin
    WriteLn('Nil Python: unsupported f-string format spec "', spec, '"');
    Halt(1);
  end;
  Result := PyFmtPad(body, width, zero, leftAlign);
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

function pystr_of(d: Double): AnsiString; overload;
begin
  Result := FloatToStr(d);
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
var i: Integer; ch: Char;
begin
  Result := QuoteCh;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if ch = QuoteCh then Result := Result + '\' + QuoteCh
    else if ch = '\' then Result := Result + '\\'
    else if ch = #10 then Result := Result + '\n'
    else if ch = #9 then Result := Result + '\t'
    else if ch = #13 then Result := Result + '\r'
    else Result := Result + ch;
  end;
  Result := Result + QuoteCh;
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
  { only a STRING payload gains quotes; every other tag reprs as it strs }
  if pyvartag(v) = 6 then
  begin
    Result := PyReprQuote(VariantToStr(v));
    Exit;
  end;
  Result := pystr_of(v);
end;

function pyabs_v(const v: Variant): Variant;
var t: Int64; d: Double; i: Int64;
begin
  t := pyvartag(v);
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
    WriteLn('TypeError: forwarded call got ', n, ' arguments, expected ', lo, ' to ', hi);
    Halt(1);
  end;
end;

procedure pystar_no_kwargs(d: TPyDict);
begin
  if (d <> nil) and (d.count > 0) then
  begin
    WriteLn('TypeError: forwarding **kwargs into a callee with named parameters is not supported');
    Halt(1);
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
  end;
  PyTypeError(pyvartag(v), 'a str or a list');
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

function dict(d: TPyDict): TPyDict;
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

function reversed(l: TPyList): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
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

{ A list slice is a SHALLOW copy, as in Python: the new list holds the same
  element values (`xs[:]` is the idiomatic shallow copy), so the slots are
  copied through append and a contained object stays shared. }
function pylist_slice(l: TPyList; lo, hi: Integer): TPyList;
var r: TPyList; i: Integer;
begin
  r := TPyList.Create;
  if l <> nil then
  begin
    PySliceBounds(l.count, lo, hi);
    for i := lo to hi - 1 do
      r.append(l.at(i));
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
var flags, fd: Int64; z: AnsiString; i: Integer; wantCreate, wantRW: Boolean;
begin
  wantCreate := False; wantRW := False;
  for i := 1 to Length(mode) do
  begin
    if mode[i] = 'w' then wantCreate := True;
    if mode[i] = '+' then wantRW := True;
  end;
  if wantCreate then flags := PYPAL_O_RDWR + PYPAL_O_CREAT + PYPAL_O_TRUNC
  else if wantRW then flags := PYPAL_O_RDWR
  else flags := PYPAL_O_RDONLY;
  z := path + #0;
  fd := PyPalOpen(PChar(z), flags, 420);          { 0644 }
  if fd < 0 then
    { CPython open() raises a CATCHABLE OSError (uforth's OPEN-FILE wraps the
      call in try/except and turns it into a nonzero ior — the Forth-2012
      DELETE-FILE test reopens a deleted file expecting failure, not a halt). }
    raise OSError.Create('FileNotFoundError: ' + path);
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
function pyvar_repr(const v: Variant): AnsiString;
var o: TObject;
begin
  if pyvartag(v) = 0 then begin Result := 'None'; Exit; end;   { VT_EMPTY }
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

function pylist_repr(l: TPyList): AnsiString;
var i: Integer;
begin
  if l = nil then begin Result := '[]'; Exit; end;
  Result := '[';
  for i := 0 to l.count - 1 do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + pyvar_repr(l.at(i));
  end;
  Result := Result + ']';
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
  if pyvartag(v) = 4 then
  begin
    if PPyVarRec(@v)^.Payload <> 0 then Result := 'True' else Result := 'False';
    Exit;
  end;
  Result := VariantToStr(v);
end;

end.
