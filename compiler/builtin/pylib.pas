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

  { A file object with the mutable methods uforth's file-VFS words call
    (seek/tell/truncate/read/write/close/flush). These words run only under the
    exec path (stubbed), so the methods are STUBS — the class exists so the
    variant method dispatch resolves `entry["file"].truncate(...)` etc. A real
    file object is feature-lib-pyfile-object. }
  TPyFile = class
  public
    constructor Create;
    procedure seek(offset: Int64); overload;
    procedure seek(offset: Int64; whence: Int64); overload;
    function tell: Int64;
    procedure truncate(size: Int64);
    function read: AnsiString; overload;
    function read(n: Int64): AnsiString; overload;
    function readline: AnsiString;
    function write(const s: AnsiString): Int64;
    procedure close;
    procedure flush;
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
    function count: Integer;
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
    function keylist: TPyList;
    function vallist: TPyList;
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
    constructor Create(const m: AnsiString);
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
    property Items[i: Integer]: Integer read at write put; default;
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
function pydict_repr(d: TPyDict): AnsiString;
function pyvar_repr(const v: Variant): AnsiString;
{ Python's format() for an f-string hole with a spec. The spec arrives as the
  literal text between ':' and the closing brace; this unit is the ONE place
  that interprets it, so the lexer never has to know what "05x" means. }
function pyformat_of(i: Int64; const spec: AnsiString): AnsiString;
function pyformat_of(const s: AnsiString; const spec: AnsiString): AnsiString; overload;
function pyformat_of(const v: Variant; const spec: AnsiString): AnsiString; overload;
{ `bytearray(n)` and `bytes(b)` are spelled as ordinary FUNCTIONS rather than
  recognised by the frontend: neither name is a Pascal keyword, so both
  resolve through the normal call path with no parser hook. (`set()` needed a
  hook only because `set` IS a keyword.) }
function bytearray: TPyBytes; overload;   { bytearray() — an EMPTY buffer }
function bytearray(n: Integer): TPyBytes; overload;
function bytes(b: TPyBytes): TPyBytes;
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
function pyvar_box(const v: Variant): Variant;   { box a value into a variant }
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
{ abs() of a variant: the tag decides int or float, which the static
  __pxxAbsInt/__pxxAbsDbl split cannot (a for-in variable is a variant). }
function pyabs_v(const v: Variant): Variant;
function bool(const v: Variant): Boolean;
function bool(i: Int64): Boolean; overload;
function bool(d: Double): Boolean; overload;
function bool(const s: AnsiString): Boolean; overload;
function bool(l: TPyList): Boolean; overload;
function pylist_repeat(l: TPyList; n: Int64): TPyList;
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
function len(const s: AnsiString): Integer; overload;
function next(c: TPyCounter): Int64;
function pycontains(l: TPyList; const v: Variant): Boolean;
function pyvar_contains(const c: Variant; const v: Variant): Boolean;
{ `sub in s` on a STRING is SUBSTRING containment in Python, not element
  membership. Without a case of its own it reached pycontains, which read the
  string handle as a TPyList and scanned its header words as variant slots —
  a segfault. }
function pystr_contains(const s: AnsiString; const sub: AnsiString): Boolean;
function pyvartag(const v: Variant): Int64;
function pyvarobj(const v: Variant): Pointer;
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
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then
      c := Chr(Ord(c) - 32);
    Result := Result + c;
  end;
end;

function pystr_lower(const s: AnsiString): AnsiString;
var i: Integer;
    c: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then
      c := Chr(Ord(c) + 32);
    Result := Result + c;
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

{ TPyFile — all STUBS (the file-VFS words that use them never run; see the class
  note). Present so the frontend can resolve the method names. }
constructor TPyFile.Create;
begin
end;

procedure TPyFile.seek(offset: Int64);
begin
end;

procedure TPyFile.seek(offset: Int64; whence: Int64);
begin
end;

function TPyFile.tell: Int64;
begin
  Result := 0;
end;

procedure TPyFile.truncate(size: Int64);
begin
end;

function TPyFile.read: AnsiString;
begin
  Result := '';
end;

function TPyFile.read(n: Int64): AnsiString;
begin
  Result := '';
end;

function TPyFile.readline: AnsiString;
begin
  Result := '';
end;

function TPyFile.write(const s: AnsiString): Int64;
begin
  Result := Length(s);
end;

procedure TPyFile.close;
begin
end;

procedure TPyFile.flush;
begin
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
  FLen := 0;
  FCap := 0;
  FItems := nil;
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

procedure PyVarSlotClear(dst: PPyVarRec);
begin
  if dst^.VType = 6 then PPyAnsiString(@dst^.Payload)^ := '';
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
  if src^.VType = 6 then s := PPyAnsiString(@src^.Payload)^;
  PyVarSlotClear(dst);
  dst^.VType := src^.VType;
  if src^.VType = 6 then
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
begin
  Result := False;
  if p^.VType <> q^.VType then Exit;
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
  FLen := 0;
  FCap := 0;
  FKeys := nil;
  FVals := nil;
end;

function TPyDict.count: Integer;
begin
  Result := FLen;
end;

function len(d: TPyDict): Integer; overload;
begin
  Result := d.FLen;
end;

procedure PyDictGrow(d: TPyDict; need: Integer);
var
  newCap, k: Integer;
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
end;

function TPyDict.indexof(const k: Variant): Integer;
var
  i: Integer;
  q: PPyVarRec;
begin
  Result := -1;
  q := PPyVarRec(@k);
  for i := 0 to FLen - 1 do
    if PyVarEq(PPyVarRec(NativeInt(FKeys) + i * 16), q) then
    begin
      Result := i;
      Exit;
    end;
end;

function TPyDict.fetch(const k: Variant): Variant;
var
  i: Integer;
  src, dst: PPyVarRec;
begin
  i := indexof(k);
  if i < 0 then PyKeyError;
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
  i := indexof(k);
  if i < 0 then
  begin
    PyDictGrow(Self, FLen + 1);
    i := FLen;
    src := PPyVarRec(@k);
    dst := PPyVarRec(NativeInt(FKeys) + i * 16);
    PyVarSlotSet(dst, src);
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
begin
  p := PPyVarRec(@v);
  if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) then
    Result := p^.Payload
  else if p^.VType = 3 then
    Result := Trunc(PPyDouble(@p^.Payload)^)   { Python int(float) truncates }
  else
  begin
    { str/object/None: Python will not silently produce a number here.
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
begin
  { Python truthiness -- TOTAL, never an error: 0, 0.0, '', None are false. }
  p := PPyVarRec(@v);
  if p^.VType = 3 then
    Result := PPyDouble(@p^.Payload)^ <> 0.0
  else if p^.VType = 6 then
    Result := PPyAnsiString(@p^.Payload)^ <> ''
  else if p^.VType = 0 then
    Result := False
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
    r^.Payload := pyfloordiv_i(pa^.Payload, pb^.Payload);
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
    r^.Payload := pyfloormod_i(pa^.Payload, pb^.Payload);
  end;
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
var k, base: Integer; sp, dp: PByte;
begin
  if src = nil then Exit;
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
var k: Integer; sp, dp: PByte;
begin
  PySliceBounds(b.FLen, lo, hi);
  if src.FLen <> (hi - lo) then
  begin
    WriteLn('ValueError: byte slice assignment length mismatch (expected ',
            hi - lo, ', got ', src.FLen, ')');
    Halt(1);
  end;
  for k := 0 to src.FLen - 1 do
  begin
    sp := PByte(NativeInt(src.FData) + k);
    dp := PByte(NativeInt(b.FData) + lo + k);
    dp^ := sp^;
  end;
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
    WriteLn('OverflowError: can''t convert negative int to unsigned');
    Halt(1);
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
  r := -1;
{$ifdef CPUX86_64}
  r := __pxxrawsyscall(21, Int64(@cs[1]), 0, 0, 0, 0, 0);
{$endif}
{$ifdef CPUAARCH64}
  r := __pxxrawsyscall(48, -100, Int64(@cs[1]), 0, 0, 0, 0);
{$endif}
{$ifdef CPU_ARM32}
  r := __pxxrawsyscall(33, Int64(@cs[1]), 0, 0, 0, 0, 0);
{$endif}
{$ifdef CPU_I386}
  r := __pxxrawsyscall(33, Int64(@cs[1]), 0, 0, 0, 0, 0);
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  r := __pxxrawsyscall(48, -100, Int64(@cs[1]), 0, 0, 0, 0);
{$endif}
{$endif}
  Result := r = 0;
end;

function pyos_getcwd: AnsiString;
var buf: array[0..4095] of Char; r: Int64; i: Integer;
begin
  Result := '';
  buf[0] := #0;
  r := -1;
{$ifdef CPUX86_64}
  r := __pxxrawsyscall(79, Int64(@buf[0]), 4096, 0, 0, 0, 0);
{$endif}
{$ifdef CPUAARCH64}
  r := __pxxrawsyscall(17, Int64(@buf[0]), 4096, 0, 0, 0, 0);
{$endif}
{$ifdef CPU_ARM32}
  r := __pxxrawsyscall(183, Int64(@buf[0]), 4096, 0, 0, 0, 0);
{$endif}
{$ifdef CPU_I386}
  r := __pxxrawsyscall(183, Int64(@buf[0]), 4096, 0, 0, 0, 0);
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  r := __pxxrawsyscall(17, Int64(@buf[0]), 4096, 0, 0, 0, 0);
{$endif}
{$endif}
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
    nrOpenat, nrRead, nrClose: Integer;
begin
  Result := '';
  ok := False;
  { syscall numbers resolved once, so the read loop below has no ifdefs in it.
    openat(AT_FDCWD) everywhere for portability (aarch64/riscv lack open). }
  nrOpenat := 0; nrRead := 0; nrClose := 0;
{$ifdef CPUX86_64}
  nrOpenat := 257; nrRead := 0; nrClose := 3;
{$endif}
{$ifdef CPUAARCH64}
  nrOpenat := 56; nrRead := 63; nrClose := 57;
{$endif}
{$ifdef CPU_ARM32}
  nrOpenat := 322; nrRead := 3; nrClose := 6;
{$endif}
{$ifdef CPU_I386}
  nrOpenat := 295; nrRead := 3; nrClose := 6;
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  nrOpenat := 56; nrRead := 63; nrClose := 57;
{$endif}
{$endif}
  if nrOpenat = 0 then Exit;   { unsupported target }
  cs := path + #0;
  fd := __pxxrawsyscall(nrOpenat, -100, Int64(@cs[1]), 0, 0, 0, 0);
  if fd < 0 then Exit;
  nread := 8192;
  while nread = 8192 do
  begin
    nread := __pxxrawsyscall(nrRead, fd, Int64(@buf[0]), 8192, 0, 0, 0);
    if nread > 0 then
      for i := 0 to nread - 1 do Result := Result + buf[i];
  end;
  nread := __pxxrawsyscall(nrClose, fd, 0, 0, 0, 0, 0);  { result discarded }
  ok := True;
end;

function pystdin_read(n: Integer): AnsiString;
var nread: Int64; buf: array[0..8191] of Char; i, want: Integer;
    nrRead: Integer; supported: Boolean;
begin
  Result := '';
  if n <= 0 then Exit;
  nrRead := 0; supported := False;
{$ifdef CPUX86_64}
  nrRead := 0; supported := True;
{$endif}
{$ifdef CPUAARCH64}
  nrRead := 63; supported := True;
{$endif}
{$ifdef CPU_ARM32}
  nrRead := 3; supported := True;
{$endif}
{$ifdef CPU_I386}
  nrRead := 3; supported := True;
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  nrRead := 63; supported := True;
{$endif}
{$endif}
  if not supported then Exit;
  want := n;
  if want > 8192 then want := 8192;
  nread := __pxxrawsyscall(nrRead, 0, Int64(@buf[0]), want, 0, 0, 0);
  if nread > 0 then
    for i := 0 to nread - 1 do Result := Result + buf[i];
end;

function pyos_remove(const path: AnsiString): Integer;
var cs: AnsiString; r: Int64; nrUnlinkat: Integer;
begin
  Result := 0;
  nrUnlinkat := 0;
{$ifdef CPUX86_64}
  nrUnlinkat := 263;
{$endif}
{$ifdef CPUAARCH64}
  nrUnlinkat := 35;
{$endif}
{$ifdef CPU_ARM32}
  nrUnlinkat := 328;
{$endif}
{$ifdef CPU_I386}
  nrUnlinkat := 301;
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  nrUnlinkat := 35;
{$endif}
{$endif}
  if nrUnlinkat = 0 then Exit;
  cs := path + #0;
  r := __pxxrawsyscall(nrUnlinkat, -100, Int64(@cs[1]), 0, 0, 0, 0);   { AT_FDCWD }
  Result := Integer(r);
end;

function pyos_rename(const src: AnsiString; const dst: AnsiString): Integer;
var cs, cd: AnsiString; r: Int64; nrRenameat: Integer;
begin
  Result := 0;
  nrRenameat := 0;
{$ifdef CPUX86_64}
  nrRenameat := 264;
{$endif}
{$ifdef CPUAARCH64}
  nrRenameat := 38;
{$endif}
{$ifdef CPU_ARM32}
  nrRenameat := 329;
{$endif}
{$ifdef CPU_I386}
  nrRenameat := 302;
{$endif}
{$ifdef CPU_RISCV32}
{$ifndef PXX_ESP}
  nrRenameat := 38;
{$endif}
{$endif}
  if nrRenameat = 0 then Exit;
  cs := src + #0; cd := dst + #0;
  r := __pxxrawsyscall(nrRenameat, -100, Int64(@cs[1]), -100, Int64(@cd[1]), 0, 0);
  Result := Integer(r);
end;

function pyos_stat(const path: AnsiString): TPyStat;
begin
  { STUB: a zeroed result. The only caller runs under the exec path (stubbed),
    so the value is never observed; the object exists so `.st_mode` compiles. }
  Result := TPyStat.Create;
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

{ Identity that BOXES its argument into a variant: passing a scalar to a Variant
  parameter materialises the box, so `pyvar_box(5)` yields a variant holding 5.
  Used to give a getattr default a variant representation for a variant-typed
  ternary (both branches must be variants). }
function pyvar_box(const v: Variant): Variant;
begin
  Result := v;
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
  if p <= Length(spec) then
  begin
    kind := spec[p];
    Inc(p);
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
  end;
  Result := pyrepr_of(v);
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
