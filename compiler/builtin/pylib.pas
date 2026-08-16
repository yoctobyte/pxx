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
{ `builtin` is pxx's System unit and it is where FloatToStr lives, which
  PyFloatStr and the `{x:g}` / `{x:s}` format specs call. It was reached only
  because it happens to be loaded into most compilations — measured under
  --strict-uses (bug-pascal-uses-is-transitive): in a Pascal program that pulls
  pylib indirectly and does NOT trigger builtin's conditional injection, the only
  FloatToStr in scope was SYSUTILS', which pylib must never depend on (it drags
  the whole RTL into every .npy). Naming it makes the dependency real. }
uses builtin, exceptions, pypal, promocore, typinfo;

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
  PYSEQ_FROZENSET = 3;   { a frozenset: the same value as a set, its own kind because repr, type() and isinstance all SHOW the difference }

  { A BUILTIN TYPE used as a VALUE — `t = str`, `string_types = (str,)`,
    `isinstance(s, text_type)`. The payload of a VT_BTYPE (13) variant is one of
    these codes; the tag is mirrored from defs.inc's VT_BTYPE_TAG the same way
    PYSEQ_* above is.

    A small CODE rather than a synthesized RTTI blob riding VT_CLASSREF: a `str`
    VALUE is variant tag 6, not an object with an RTTI pointer, so the ancestry
    walk a fake blob would buy cannot be reached for the scalar types anyway —
    the isinstance arm has to switch on the variant tag whatever the payload is.
    A blob would only have bought repr, at the price of a record that looks like
    a class to every consumer that walks one. bug-n-a-type-name-is-not-a-first-class-value }
  PYBT_STR       = 1;
  PYBT_INT       = 2;
  PYBT_FLOAT     = 3;
  PYBT_BOOL      = 4;
  PYBT_BYTES     = 5;
  PYBT_LIST      = 6;
  PYBT_DICT      = 7;
  PYBT_SET       = 8;
  PYBT_TUPLE     = 9;
  PYBT_BYTEARRAY = 10;
  PYBT_FROZENSET = 11;
  { `type` itself — `class_types = (type,)` (six's line 43) and
    `isinstance(X, type)`, Python's "is this a class?". Its instances are the
    other TYPE objects, so it is the one code whose isinstance arm asks about
    the tag rather than about the value's Python type name. }
  PYBT_TYPE      = 12;
  { `type(None)` is `<class 'NoneType'>` in CPython, and NoneType is a real type
    object there — so it needs a code even though no one writes `NoneType`. }
  PYBT_NONETYPE  = 13;
  PYBT_LAST      = 13;

  { Which cursor a TPyIter is — see TPyIter. The kind decides where the next
    value comes from, so it is the whole of the object's behaviour; there is no
    per-kind subclass, because the frontend has to name ONE class in the AST. }
  PYITER_LIST   = 0;   { a list, walked forward, LIVE (mutation is visible) }
  PYITER_STR    = 1;
  PYITER_REV    = 2;   { reversed(list) }
  PYITER_REVSTR = 3;
  PYITER_MAP    = 4;
  PYITER_FILTER = 5;
  PYITER_ENUM   = 6;
  PYITER_ZIP    = 7;
  { a RANGE cursor holds no source object at all — FStart is the next value,
    FStep the stride and FPos the number of values left, which is why a
    range of a billion costs the same as a range of three. }
  PYITER_RANGE  = 8;
  { a USER object implementing the iterator protocol — `__iter__` once, then
    `__next__` per step, terminating on StopIteration. FObj holds the object
    `__iter__` answered (which for the ordinary `return self` IS the source).
    bug-nilpy-iterator-protocol-on-a-user-class }
  PYITER_USEROBJ = 9;
  { an N-WAY zip, whose stream count is a RUN-TIME fact: `zip(*rows)`, the
    transpose idiom. FSrc holds the cursors (object-tagged variants) instead of
    a leaf list, because four FUp fields cannot hold a count nobody knows until
    the call runs. The fixed two/three/four-way forms above are unchanged — a
    pair still yields a PAIR, and the common case pays nothing for this.
    bug-nilpy-star-unpack-into-a-fixed-arity-builtin }
  PYITER_ZIPN   = 10;

type
  TPyVarRec = record
    VType: Int64;
    Payload: Int64;
  end;
  PPyVarRec = ^TPyVarRec;
  { rawKind=2 (a pyeval closure object) forwards through this hook; installed
    by pyeval, which owns the closure registry. nil until pyeval initializes. }
  TPyClosureFinalize = procedure(objp: Pointer);
  { pyeval's PyCallKey1, installed into PyIterCallHook: the one entry point
    that knows all four callable representations. See that variable. }
  TPyIterCall = function(key: Pointer; const a0: Variant): Variant;
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
    { set.update / `s |= other` — add every element of `other` that is not
      already present, IN PLACE. In place, not a rebind, because CPython's `|=`
      mutates: an alias taken before the statement must see the new elements,
      exactly as `+=` on a list extends rather than rebinding.
      bug-nilpy-set-augmented-union-does-nothing }
    function setupdate(other: TPyList): Variant;
    { ...and the three REMOVING in-place set ops: `&=`, `^=`, `-=`. Each is the
      same contract — mutate Self, return None — and each takes a SNAPSHOT of
      the side it iterates before removing, because removal renumbers the
      elements under an index walk. }
    function setintersect(other: TPyList): Variant;
    function setsymdiff(other: TPyList): Variant;
    function setdiff(other: TPyList): Variant;
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
    { set.symmetric_difference / set.isdisjoint — the last two of the set
      protocol, thin over the operator forms that already exist (pyset_xor,
      and intersection for the disjoint test).
      feature-nilpy-stdlib-coverage-gaps-measured }
    function symmetric_difference(other: TPyList): TPyList;
    function isdisjoint(other: TPyList): Boolean;
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
    { ...and a VARIANT argument, which is what an unannotated PARAMETER is.
      Neither typed overload can be chosen for one, and the pair was resolved to
      the TPyList arm — so `def f(sec): m.update(sec)` read a TPyDict as a
      TPyList and SEGFAULTED. `m.update({"k": v})` with a literal was fine,
      because a literal has a static type to match on.
      Dispatches on the runtime tag and delegates to whichever typed arm the
      value actually is. bug-nilpy-dict-update-with-a-variant-argument-segfaults }
    function update(const v: Variant): Variant; overload;
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

    PyEnsureExceptionClass creates the root only when it is MISSING, so it now
    finds this one and the whole tree shares a root — which is what makes a bare
    `except Exception:` catch a ValueError.

    NAMED `Exception`, and descending from `ExceptionBase` in the shared
    `exceptions` unit — which is how it can carry that name while sysutils'
    class carries it too. They are SIBLINGS, not one class with two hats.

    That matters for more than tidiness. `ClassName` reports the DECLARED name,
    so this one answers `Exception` and Python's `repr(e)` /
    `type(e).__name__` come out right with no renaming anywhere in the
    frontend. The previous arrangement named it `Exception` and had
    pylexer.inc map the bare identifier on the way IN but never on the way out,
    and that asymmetry is exactly what made repr print `Exception('x')`.

    It also lifts the old constraint: pylib may now add any member sysutils
    lacks, because the two are different rows. `msg` and `argsv` are inherited
    from the shared root at one offset for every descendant of either tree,
    which is what lets a bare `except Exception:` catch an RTL exception and
    still read `.msg` off it. }
  Exception = class(ExceptionBase)
  public
    { A VARIANT, not an AnsiString. Every exception below this one used to take
      a string message, so the frontend rendered a non-string argument through
      pyexc_msgstr at the construction site and its TYPE was gone —
      `ValueError(42).args` was ('42',) where CPython says (42,), so
      `e.args[0] == 42` was False and `e.args[0] + 1` raised. KeyError already
      escaped that by declaring its own Variant ctor; this widens the base so
      every exception does. The frontend needs NO change: it already branches on
      the ctor's declared parameter type and boxes the argument when it is a
      Variant (pyparser.inc, the single-argument arm).
      This was blocked while pylib's root SHADOWED sysutils' Exception — every
      RTL `raise EConvertError.Create('..')` would have recompiled against the
      new signature. Exception shares its name with nothing, so the blast
      radius is pylib's own tree.
      bug-nilpy-non-keyerror-exception-args-loses-the-argument-type }
    constructor Create(const m: Variant);
    { FMessage and Message are PROPERTIES over `msg`, not fields: one storage,
      so a Python `raise ValueError("mine")` and a read through `Message` see
      the same place. Two synchronised fields were tried first and lost the
      message on the read path — print(e) reads the `msg` FIELD directly (the
      frontend synthesises that access), so `msg` must stay the field and
      everything else a view on it. }
    constructor CreateFmt(const m: AnsiString; const args: array of const);
    { Python's `e.args`. A PROPERTY rather than a field, and derived rather than
      stored, because a pxx Exception carries one Message string: `args` is
      what the constructor was given, and for every raise this dialect emits
      that is exactly the message. So it answers `()` for an empty message and
      `(msg,)` otherwise — CPython's own relationship between args and str(e)
      for the one-argument case, which is every builtin raise and almost all
      user code.
      A MULTI-argument raise (`raise MyErr("no such user", 404)`) is folded to
      the rendered string `('no such user', 404)` at the construction site, so
      its args would come back as a 1-tuple of that text. That is why the fold
      stashes the real tuple in argsv when it runs, and why this reads argsv
      first.
      bug-nilpy-exception-args-attribute-missing }
    { argsv itself lives on ExceptionBase as an untyped TObject, so that a
      NilPy `except Exception:` can read `.args` off an RTL exception too and
      get nil rather than a short object's neighbouring bytes. Everything in
      here casts it; pylib is the only code that ever stores into it. }
    function GetArgs: TPyList;
    property args: TPyList read GetArgs;
  end;
  ValueError        = class(Exception) end;
  { Python raises this for x/0, x//0 and x%0. It had no class at all, so the
    integer paths fell through to the Pascal runtime's error 200 (which no
    `except` can see) and true division produced garbage
    (bug-nilpy-runtime-raised-errors-bypass-try-except). }
  ZeroDivisionError = class(Exception) end;
  TypeError         = class(Exception) end;
  IndexError        = class(Exception) end;
  { CPython's KeyError is the one builtin whose str() is the REPR of its
    argument — `str(KeyError('inner'))` is "'inner'", with the quotes, which is
    why every "key not found" line in a real log looks like that. So the repr
    happens HERE, at construction, and the raw argument is kept for `args`:
    one place, so the raise path and a user's own `raise KeyError(k)` cannot
    disagree — which they did, the raise path being correct because PyKeyError
    pre-repr'd its message and a user raise not.
    bug-nilpy-exception-str-and-repr-diverge-from-cpython }
  KeyError          = class(Exception)
    { A VARIANT, not a string: `raise KeyError(42)` is ordinary Python, and an
      integer arriving at a `const m: AnsiString` parameter was read as a string
      handle and SEGFAULTED at the raise — no diagnostic, a dead process
      (bug-nilpy-raise-keyerror-with-a-non-string-argument-segfaults). Taking
      the variant also makes both halves right at once: the repr keeps an int
      key unquoted, and `args` keeps the key's own TYPE rather than its text. }
    constructor Create(const m: Variant);
    { …and the form for a raise site that has already rendered the key —
      PyKeyError, which reprs the VARIANT so an int key stays unquoted. Passing
      that text through Create would repr it a second time and report '7' for a
      missing 7. }
    constructor CreateRendered(const shown: AnsiString);
  end;
  OSError           = class(Exception) end;
  AttributeError    = class(Exception) end;
  EOFError          = class(Exception) end;
  KeyboardInterrupt = class(Exception) end;
  RuntimeError      = class(Exception) end;
  NotImplementedError = class(RuntimeError) end;
  StopIteration     = class(Exception) end;
  OverflowError     = class(Exception) end;
  { CPython 3 makes IOError and EnvironmentError ALIASES of OSError, and
    FileNotFoundError / PermissionError subclasses of it. Real code catches
    them by name — songformatter has `except IOError:` around a file read.

    ALIAS, not subclass, and the distinction is the whole bug: declaring
    `IOError = class(OSError)` made it a SIBLING of FileNotFoundError, so
    `except IOError:` did not catch a missing file — the single most common
    spelling of exactly that guard. In CPython `IOError is OSError` is True.
    bug-nilpy-ioerror-is-a-sibling-of-filenotfounderror-not-an-alias }
  IOError           = OSError;
  EnvironmentError  = OSError;
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
    { `bytes` and `bytearray` are ONE class here, exactly as list/tuple/set are
      one TPyList — so, exactly like those, the Python TYPE has to be a runtime
      tag rather than a class name. Without it `print(bytearray([1]))` rendered
      `b'\x01'` and `type(b).__name__` answered `bytes`, both silently wrong for
      a working CPython program.
      False (a plain `bytes`) is the default, so a TPyBytes built by any of the
      ~30 other construction sites keeps today's behaviour and only the
      `bytearray(...)` constructors stamp it.
      NOT about mutability: NilPy lets you mutate either, which is accepting
      what CPython REJECTS and therefore laxity rather than a defect — see the
      ticket. bug-nilpy-bytearray-and-bytes-are-the-same-type }
    FIsByteArray: Boolean;
    constructor Create(n: Integer);
    function count: Integer;
    { see TPyList.at — bytearrays have no Python .get either }
    function at(i: Integer): Integer;
    procedure put(i: Integer; v: Integer);
    { bytearray.extend / .append — uforth builds output buffers byte by byte }
    procedure extend(src: TPyBytes);
    { bytearray.append. This comment used to say "NO .append here on purpose",
      because a second class declaring the name made every `.append(...)` on a
      dynamically typed receiver ambiguous — and then the method was added
      anyway, leaving the two contradicting each other.
      Settled 2026-08-09: the receiver's class is now decided at RUN time
      (feature-nilpy-runtime-method-dispatch-on-variant), with TPyList as the
      fallback arm, so the collision this warned about is handled rather than
      avoided. }
    procedure append(v: Integer);
    { bytes.hex() — the lowercase two-digit-per-byte form, '' for empty. }
    function hex: AnsiString;
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
    { ---- the rest of the ASCII-shaped `bytes` contract ----------------------

      Added as a SET, not one at a time. This class grew a method whenever
      something needed one, which is how it ended up carrying `endswith` and
      not `startswith` — and a bytes method CPython defines and pxx omits is a
      hard compile error, so every missing one is a wall in front of an
      ordinary Python library (`webencodings`'s label normaliser is
      `s.encode('utf8').lower().decode('utf8')`, and `_detect_bom` needs
      `startswith` on the next line).
      bug-a-bytes-has-almost-none-of-its-python-methods

      ASCII-only where CPython is ASCII-only: `b'\xc3\xa9'.lower()` is
      unchanged in CPython too, because a bytes object has no encoding to case
      map through. That is the whole of what could have been subtle here.

      Every method that BUILDS a buffer carries FIsByteArray across, or the
      bytes/bytearray tag is lost at the first transformation — the same rule
      pybytes_slice already states. }
    function startswith(pfx: TPyBytes): Boolean;
    function lower: TPyBytes;
    function upper: TPyBytes;
    function title: TPyBytes;
    function capitalize: TPyBytes;
    function swapcase: TPyBytes;
    { .strip() with no argument strips ASCII WHITESPACE; with a bytes argument
      it strips any byte in that SET (not a prefix), exactly as CPython does. }
    function strip: TPyBytes; overload;
    function strip(chars: TPyBytes): TPyBytes; overload;
    function lstrip: TPyBytes; overload;
    function lstrip(chars: TPyBytes): TPyBytes; overload;
    function rstrip: TPyBytes; overload;
    function rstrip(chars: TPyBytes): TPyBytes; overload;
    function replace(old_, new_: TPyBytes): TPyBytes;
    { .index is .find that RAISES instead of answering -1 — CPython's own
      distinction, and the reason both exist. }
    function index(sub: TPyBytes): Integer;
    function rfind(sub: TPyBytes): Integer;
    function rindex(sub: TPyBytes): Integer;
    { .split() with no argument splits on RUNS of whitespace and drops empty
      fields; with a separator it keeps them. Same split as str's, which is why
      the two rules are described the same way in pystr_split_ws/_sep. }
    function split: TPyList; overload;
    function split(sep: TPyBytes): TPyList; overload;
    function rsplit: TPyList; overload;
    function splitlines: TPyList;
    { b'-'.join([b'a', b'b']) — Self is the SEPARATOR, as for str. }
    function join(parts: TPyList): TPyBytes;
    { .translate(table): table is 256 bytes mapping each byte value. A table of
      any other length is a ValueError in CPython. }
    function translate(table: TPyBytes): TPyBytes;
    function isdigit: Boolean;
    function isalpha: Boolean;
    function isalnum: Boolean;
    function isspace: Boolean;
    function isupper: Boolean;
    function islower: Boolean;
    property Items[i: Integer]: Integer read at write put; default;
  end;

  { A real OS file (raw x86-64 syscalls, no libc) backing NilPy's open(path,
    mode) — uforth's CREATE-FILE/OPEN-FILE/READ-LINE/WRITE-FILE/... words. }
  TPyFile = class
  public
    FFd: Int64;
    { WHICH of the two string types this file's reads yield — the one fact that
      decides it, held once instead of hard-coded four times.

      CPython picks str or bytes from the MODE, which is a run-time value, so no
      accessor can answer it from its own static return type. Four of them tried
      and four got it wrong in one direction or the other: text read(n) and
      readline() answered bytes, binary read() and readlines() answered str.
      Every reader now branches on this field and returns a Variant, which is
      how NilPy carries any value whose type is not known until run time.
      bug-nilpy-text-mode-read-n-returns-bytes-not-str }
    FBinary: Boolean;
    constructor Create;
    function read(u: Int64): Variant; overload;
    { CPython's `f.read()` with NO argument: everything from the current
      position to EOF, as TEXT. The read-slurp model gave this to TPyList and
      TPyFile never had it, which is the whole reason open() answered two
      different classes by mode (bug-nilpy-open-returns-two-different-classes-by-mode).
      Text, not TPyBytes, because that is what `print(f.read())` must produce —
      our strings are byte strings, the same identity TPyFile.write relies on. }
    function read: Variant; overload;
    { the mode-blind slurp both readers are built on }
    function readall: AnsiString;
    { CPython's readlines(): the rest of the file split into lines, each KEEPING
      its trailing newline, exactly as TPyList's version yielded them so that
      joining reproduces the file byte for byte. }
    function readlines: TPyList;
    function readline: Variant;
    function write(b: TPyBytes): Int64; overload;
    { Python's TEXT-mode write takes a str, and that is how every ordinary
      program spells it. Without this overload `f.write("hello")` resolved to
      the TPyBytes one, passed the string's handle as a buffer and wrote ZERO
      bytes -- the file was created and left empty, with no error
      (bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory). }
    function write(const s: AnsiString): Int64; overload;
    { The argument's STATIC type is unknown — `def wr(t): h.write(t)`, an
      unannotated parameter, a concatenation, a `%` format, anything held in a
      variant. The call site picks a method overload by name and ARITY, so
      without a variant-typed entry a dynamic argument landed on whichever
      overload was declared first (TPyBytes), passed the string's handle as a
      buffer and raised "expected an object argument, got str" — for the
      ordinary Python spelling, with `str(...)` around it as the only
      workaround. Dispatches on the runtime TAG instead, the same shape
      pystr_startswith_any uses for the same reason.
      bug-nilpy-file-write-picks-the-bytes-overload-for-a-non-str-argument }
    function write(const v: Variant): Int64; overload;
    { f.writelines(seq) — CPython adds NO separator; the caller's strings carry
      their own newlines. Takes the same variant the write() row above takes,
      for the same reason, and accepts any iterable through pyseq_of_obj.
      (bug-nilpy-file-writelines-is-absent) }
    procedure writelines(const v: Variant);
    procedure seek(pos: Int64); overload;
    procedure seek(pos: Int64; whence: Int64); overload;
    function tell: Int64;
    procedure truncate(sz: Int64);
    procedure flush;
    procedure close;
  end;

  { A CURSOR — CPython's `map` / `filter` / `enumerate` / `zip` / `reversed`
    object, and what `iter(x)` hands back. Not a sequence: it holds a SOURCE, a
    POSITION and a rule for producing the next value, so constructing one costs
    nothing, breaking a loop parks it, and resuming continues from where it
    stopped. NilPy returned eager lists (Python 2's `map`), which made a
    program CPython runs fine crash here — `f` ran for every element even when
    the loop broke at 3, so a raise past the break point escaped
    (decide-nilpy-eager-map-filter-reversed-enumerate).

    The protocol is TWO calls, not one, because that is what fits the desugared
    `for`: `pyiter_has` PREFETCHES one value into FBox and answers whether
    there was one; `pyiter_take` hands that value over and clears the prefetch.
    A single `next`-plus-exhausted-flag cannot sit in a while CONDITION without
    either losing the value or fetching twice. The call counts match CPython
    exactly: one prefetch per body run, none after the break.

    FBox is a one-slot TPyList rather than a `Variant` FIELD deliberately — no
    class in this unit has a variant field, and the container path is the
    tested one for holding a variant that may own an object.

    Ownership is EXPLICIT (PXXObjRetain in the constructors, released in
    PyObjFinalize's TPyIter arm): a cursor outlives the expression that built
    its source — `for v in map(f, [1, 2, 3])` has nothing else holding that
    list once the header has run. }
  TPyIter = class
  public
    FKind: Integer;          { PYITER_* below }
    FSrc: TPyList;           { leaf list source (LIST, REV) }
    FStr: AnsiString;        { leaf str source (STR, REVSTR) }
    FUp: TPyIter;            { upstream cursor (MAP, FILTER, ENUM, ZIP left) }
    FUp2: TPyIter;           { ZIP right }
    { …and the third and fourth streams of an N-way zip. `zip(rows, labels,
      values)` is ordinary Python and did not PARSE; two more fields cover the
      arities real code writes, and the advance below appends a stream only
      when its field is non-nil, so a two-way zip still yields a PAIR and not a
      2-tuple padded with None. bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep item 2 }
    FUp3: TPyIter;           { ZIP third — nil for a two-way zip }
    FUp4: TPyIter;           { ZIP fourth — nil below four }
    FKey: Pointer;           { the stored callable (MAP, FILTER) — see PyIterCallHook }
    FPos: Integer;           { leaf position / ENUM counter / RANGE values left }
    FStart: Int64;           { enumerate(xs, START) / RANGE next value }
    FStep: Int64;            { RANGE stride }
    FObj: TObject;           { the user iterator object (USEROBJ) }
    FBox: TPyList;           { the one-slot prefetch }
    FHas: Boolean;           { FBox holds a prefetched value }
    FEnd: Boolean;           { the source is exhausted — never restarts }
    { A GENERATOR EXPRESSION bound to a name. It walks a materialised list, so
      its ADVANCE is a list cursor's and nothing about the machinery changes —
      only what it CALLS itself, which `type(g).__name__` and every error
      message read. A separate flag rather than a PYITER_GEN kind precisely
      because the behaviour is identical: a new kind would have to be added to
      every site that tests FKind, and the one that got missed is where the bug
      would live. }
    FIsGen: Boolean;
    constructor Create;
  end;

  { CPython's `range` — a lazy SEQUENCE, not a cursor, and the distinction is
    the whole reason it is its own class beside TPyIter. A range is
    RE-ITERABLE (iterating one twice yields the same values twice), INDEXABLE,
    len-able and sliceable; a cursor is none of those and is consumed once.
    Both are lazy, and that shared word is what made the two look like one
    problem — they are not.

    Three Int64 fields and no storage: `range(1000000000)` costs 24 bytes and
    `r[999999999]` is one multiply. NilPy used to have no range VALUE at all —
    it existed only as the counted-loop lowering in a `for` header, so
    `r = range(3)` was `undefined variable (range)` and `list(range(3))` needed
    a hard-coded whitelist of "callees that only iterate their argument"
    (PyRangeIterConsumer, now deleted). feature-nilpy-range-as-a-value. }
  TPyRange = class
  public
    FStart: Int64;
    FStop: Int64;
    FStep: Int64;
    constructor Create;
    { r[i] — one multiply, no storage. Spelled `at` and exposed as the DEFAULT
      property for the same reason TPyList and TPyBytes are: that is the shape
      the frontend's subscript path already knows how to call, so indexing a
      range needs no new mechanism. }
    function at(i: Int64): Int64;
    property Items[i: Int64]: Int64 read at; default;
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
{ ...and a USER class instance, which had NO overload at all: a class handle
  matched the AnsiString one and was read as a managed string, so `repr(c)`
  answered the EMPTY string — silently, and only for a STATICALLY class-typed
  argument. `repr([c])` was already right, because a boxed element reaches
  pyvar_repr, and `str(c)` / `print(c)` were right because those have their own
  class arm in the frontend. An overload rather than a frontend intrinsic, per
  the note above: the ordinary resolution machinery does the dispatch, and
  TPyList/TPyDict keep their exact-match overloads.
  bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash }
function repr(o: TObject): AnsiString; overload;
{ Python's repr() of a CONTAINER. print(xs) is the most natural debugging line
  in Python, and it used to print the TPyList instance POINTER — the container
  fell through to the integer path (bug-a-nilpy-print-of-a-list-prints-a-pointer).
  Recursive: a nested list/dict element is reprd as a container, not as its
  object tag. }
{ Mark a list as a TUPLE / a SET — the frontend calls these on the temp the
  corresponding display builds. Not "for rendering only" any more: the kind is
  what `type(x).__name__` and `isinstance` answer from, so a display that fails
  to stamp it is a wrong TYPE, not just wrong brackets. }
{ The STARRED target of an unpack is ALWAYS a list, even when the source was a
  tuple — `a, *b = (1,2,3)` gives b == [2, 3], not (2, 3). The slice that
  produces it copies the source's kind (correct for an ordinary slice, where a
  slice of a tuple IS a tuple), so the result has to be re-marked.
  feature-nilpy-starred-and-nested-unpacking }
function pylist_mark_list(l: TPyList): TPyList;
function pyvar_mark_list(const v: Variant): Variant;
{ `a, b, *c = xs` with too FEW values raises ValueError in CPython, naming how
  many were expected. Without the check the indexed stores raise IndexError
  instead — a different exception type, so an `except ValueError` around the
  unpack does not catch it. }
function pyunpack_check(have, need: Integer): Integer;
function pylist_mark_tuple(l: TPyList): TPyList;
function pylist_mark_set(l: TPyList): TPyList;
function pylist_mark_frozenset(l: TPyList): TPyList;   { ...and the frozenset stamp }
{ The Python type name of a sequence kind: 'list' / 'tuple' / 'set'. }
function PySeqKindName(k: Integer): AnsiString;
{ The sequence kind of a VARIANT, or -1 when it does not hold a TPyList. The
  shape isinstance() asks: it must distinguish the three kinds that share the
  row, which a class test cannot do. }
{ 0 = a plain `bytes`, 1 = a `bytearray`, -1 = not a TPyBytes at all. The
  bytes/bytearray twin of pyseq_kind_v, and it exists for the same reason:
  isinstance cannot answer from the CLASS when two Python types share one.
  bug-nilpy-bytearray-and-bytes-are-the-same-type }
function pybytes_kind_v(const v: Variant): Integer;
function pyseq_kind_v(const v: Variant): Integer;
function pylist_repr(l: TPyList): AnsiString;
function pybytes_repr(b: TPyBytes): AnsiString;
function pydict_repr(d: TPyDict): AnsiString;
function PyCallableStr(const v: Variant): AnsiString;
function PyClassRefStr(const v: Variant): AnsiString;
{ `==`/`!=` TRY for two variant slots by address, in PXXPromoVarCmpTry's
  protocol (0 = not handled, 1 = False, 2 = True). Answers only when an OBJECT
  is involved, so a user __eq__ is reached; declines everything else. Must stay
  in the interface — ir.inc calls it by name. }
function pyraise_check(const v: Variant): Variant;
function pyvar_eqv(a, b: Pointer; neq: Int64): Int64;
function pyvar_repr(const v: Variant): AnsiString;
{ The message text for `raise SomeError(x)` where x is NOT a string. Every
  builtin exception below KeyError takes `const m: AnsiString`, so a bare
  integer arrived as a string handle and the raise SEGFAULTED; the frontend
  boxes the argument and routes it through here instead. `str()`, because
  CPython's `str(ValueError(42))` is `42` — KeyError is the one exception that
  reprs, and it has its own variant ctor for exactly that reason.
  ONE signature on purpose: pystr_of is overloaded per type and FindProc
  resolves by NAME without consulting overloads
  (project_findproc_by_name_ignores_overloads), so calling pystr_of from the
  frontend would hand the integer to the AnsiString arm — the same crash, one
  frame further in. }
{ The MULTI-ARGUMENT exception pair. `raise MyErr("no such user", 404)` has to
  end up with BOTH the rendered message CPython prints and the real argument
  tuple, and the arguments must be evaluated exactly ONCE — anything with a
  side effect would otherwise run twice.

  So the tuple is the only thing built at the construction site: the message is
  derived FROM it at run time (pyexc_tuplemsg), and the tuple is stashed into
  argsv afterwards (pyexc_setargs). The fold used to render the arguments into
  one string at the call site and hand THAT to the one-parameter ctor, so
  `e.args` came back as a 1-tuple of the rendered text and `len(e.args)` was 1
  for every multi-argument exception in the language.
  bug-nilpy-multi-arg-exception-args-is-a-1-tuple-of-rendered-text }
function pyexc_tuplemsg(t: TPyList): AnsiString;
function pyexc_setargs(e: TObject; t: TPyList): TObject;
function pyexc_msgstr(const v: Variant): AnsiString;
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
{ The builtin `format(v[, spec])` behind the f-string grammar, which was
  `undefined variable` while every spec it takes already worked inside an
  f-string (bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep item
  4). One implementation shared with the f-strings, so the two spellings cannot
  drift; an EMPTY spec is `str(v)`, which is CPython's own definition of the
  one-argument form.

  Named pyformat_v and reached through a FRONTEND intercept rather than being
  declared as `format`: sysutils declares `Format(fmt, [args])`, and a later
  unit's declaration SHADOWS the whole name rather than joining its overload
  set — measured, with the pylib arms absent from the candidate list — so
  `format(7.5, ".1f")` compiled until the program said `import json` and then
  stopped compiling. A builtin that works only until you import something is
  worse than one that is missing. }
function pyformat_v(const v: Variant; const spec: AnsiString): AnsiString;
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
{ str.encode([encoding [, errors]]) -> bytes. The encoding is HONOURED — it used
  to be accepted and dropped, so every encoding produced UTF-8 bytes and
  `"he".encode("latin-1")` returned 3 bytes where CPython gives 2. Supported:
  utf-8, ascii, latin-1/iso-8859-1, utf-16le/be, utf-32le/be, and utf-16/utf-32
  with a BOM; anything else raises LookupError BY NAME, because returning UTF-8
  bytes labelled big5 is a wrong answer while refusing is a missing feature.
  errors= is 'strict' (raise), 'replace' or 'ignore'.
  bug-n-str-encode-and-bytes-decode-ignore-the-encoding }
function pystr_encode(const s: AnsiString): TPyBytes;
function pystr_encode_enc(const s: AnsiString; const enc: AnsiString): TPyBytes;
function pystr_encode_enc_err(const s: AnsiString; const enc: AnsiString;
                              const errors: AnsiString): TPyBytes;
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
{ TARGET is a variant: `vm.memory[a:b] = src` where the receiver has no static
  class (a dynamically-typed parameter, a container element). Unboxes the target
  and dispatches to the bytes or list setter by its runtime type — the mirror of
  pybytes_setslice_v, which handles a variant on the other side. }
procedure pyvar_setslice(const dst: Variant; lo, hi: Integer; const src: Variant);
{ `v.to_bytes(n, "little", signed=s)` and `int.from_bytes(b, "little",
  signed=s)`. Recognised by the frontend as INTRINSICS with a fixed argument
  shape rather than real methods, because their Python spelling carries a
  KEYWORD argument and NilPy has no keyword arguments — 36 sites in uforth,
  one spelling, so the intrinsic is far cheaper than the language feature.
  Byte order is not a parameter: every censused use is little-endian, and the
  frontend REJECTS anything else rather than silently ignoring it. }
function pyint_to_bytes(v: Int64; n: Integer; signed: Boolean): TPyBytes;
function pyint_from_bytes(b: TPyBytes; signed: Boolean): Int64;
{ The BIG-endian half of both, as one reversal rather than a second conversion:
  to_bytes(..., 'big') is the little-endian image reversed, and from_bytes(b,
  'big') is from_bytes(reverse(b), 'little'). Two byte orders, one extra
  routine, and the conversions above stay the single source of the arithmetic.
  bug-nilpy-to-bytes-refuses-big-endian-and-demands-the-signed-keyword }
function pybytes_reversed(b: TPyBytes): TPyBytes;
{ `n.bit_length()` / `n.bit_count()`. Both are defined on the MAGNITUDE — the
  sign is ignored, so (-8) answers as 8 — and both take a Variant rather than
  an Int64 so an arbitrary-precision receiver stays exact: `(2**70)` is outside
  Int64, and an Int64 parameter would narrow it mod 2^64 and answer confidently
  wrong, which is the trap pyvar_to_float records. }
function pyint_bit_length(const v: Variant): Int64;
function pyint_bit_count(const v: Variant): Int64;
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
{ float's own methods — see the implementations for the formats. }
function pyfloat_is_integer(x: Double): Boolean;
function pyfloat_conjugate(x: Double): Double;
function pyfloat_hex(x: Double): AnsiString;
function pyfloat_as_integer_ratio(x: Double): TPyList;
{ int's three methods of the same NAMES. An int is not a float here: CPython's
  (3).as_integer_ratio() is (3, 1) and (3).conjugate() is 3 — ints, not 3.0 —
  so routing an int receiver through the float versions would answer a wrong
  TYPE rather than a missing method. int has no .hex(); that name belongs to
  float and bytes only. }
function pyint_is_integer(x: Int64): Boolean;
function pyint_conjugate(x: Int64): Int64;
function pyint_as_integer_ratio(x: Int64): TPyList;
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
{ os.path.split(p) -> (head, tail), the pair os.path.dirname/basename already
  answer separately. A TUPLE, like splitext beside it.
  feature-nilpy-stdlib-coverage-gaps-measured }
function pyos_path_split(const p: AnsiString): TPyList;
{ os.path.normpath — collapse '.', '..' and repeated slashes, textually and
  without touching the filesystem, exactly as CPython's does. }
function pyos_path_normpath(const p: AnsiString): AnsiString;
{ os.path.getsize — st_size, raising the same FileNotFoundError pyos_stat does
  for a missing path rather than answering 0. }
function pyos_path_getsize(const p: AnsiString): Int64;
{ os.path.expanduser — a leading '~' becomes $HOME. Any other shape (including
  '~user') is returned unchanged, which is also what CPython does when it cannot
  resolve the user. }
function pyos_path_expanduser(const p: AnsiString): AnsiString;
function pyos_path_splitext(const p: AnsiString): TPyList;
function pyos_path_exists(const p: AnsiString): Boolean;
function pyos_path_abspath(const p: AnsiString): AnsiString;
function pyos_getcwd: AnsiString;
procedure pysys_exit(code: Integer);
{ os.remove / os.rename: unlink / rename via syscall, returning 0 (Python returns
  None; the value is unused). os.stat: a stubbed TPyStat — see the class note. }
{ Raise CPython's OSError for a failed syscall: the right SUBCLASS for the
  errno, wearing CPython's own message. See the body. }
procedure pyos_raise_ioerror(err: Int64; const path: AnsiString; const path2: AnsiString);
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
  { map/filter cursors must CALL the callable they stored, and the callable
    dispatch (PyCallKey1, which knows all four representations a NilPy callable
    has) lives in pyeval — which USES this unit, so it cannot be called from
    here. pyeval installs itself through this hook, exactly as the closure
    finaliser above does. A cursor whose hook is unset raises rather than
    silently yielding the unmapped element. }
  PyIterCallHook: TPyIterCall;

{ ---- cursors (TPyIter) -------------------------------------------------
  The two-call protocol: `pyiter_has` prefetches, `pyiter_take` consumes. See
  TPyIter's declaration for why it is two calls and not one. }
function pyiter_of_list(l: TPyList): TPyIter;
function pyiter_of_str(const s: AnsiString): TPyIter;
{ A generator expression bound to a NAME. The elements are materialised, but
  the VALUE is a cursor over them, because single consumption is the observable
  half of laziness: `g = (x for x in [1, 2]); next(g); list(g)` must answer [2],
  and while g held the list itself both consumers walked it from the start.
  bug-nilpy-a-generator-expression-is-not-consumed-once }
function pyiter_gen(l: TPyList): TPyIter;
{ `iter(x)` over a value whose type is only known at run time — a list, a str,
  a dict (its KEYS, as Python iterates one), bytes, or a cursor, which answers
  ITSELF because CPython's iter() is idempotent on an iterator. }
function pyiter_v(const v: Variant): TPyIter;
{ reversed(): a leaf cursor walking the source BACKWARDS. Its source is already
  materialised, so the only thing laziness buys here is the exhaustion rule. }
function pyiter_rev_list(l: TPyList): TPyIter;
function pyiter_rev_str(const s: AnsiString): TPyIter;
{ enumerate(xs[, start]) and zip(a, b) over any iterable, yielding PAIRS (a
  two-element TPyList, the same shape d.items() and the tuple literal build). }
function pyiter_enum(const v: Variant; start: Int64): TPyIter;
function pyiter_zip(const a: Variant; const b: Variant): TPyIter;
{ ...and the forms the frontend actually builds. Both take CURSORS, so the
  arm converts each iterable once (PyMakeIterOf) instead of needing one entry
  per combination of argument types — zip alone would otherwise want nine. }
function pyiter_enum_i(up: TPyIter; start: Int64): TPyIter;
function pyiter_zip_ii(a: TPyIter; b: TPyIter): TPyIter;
{ …and the three- and four-way forms. Separate entries rather than an
  open-array: the frontend builds these calls with a fixed argument chain, and
  the arity is known at the call site. }
function pyiter_zip_iii(a: TPyIter; b: TPyIter; c: TPyIter): TPyIter;
function pyiter_zip_iiii(a: TPyIter; b: TPyIter; c: TPyIter; d: TPyIter): TPyIter;
{ …and the N-way form, whose streams arrive as a LIST of iterables — `zip(*rows)`
  and any zip past four. Each element is converted with pyiter_v, so a row may be
  a list, a str, a range, a cursor or a user iterable, exactly as a written
  operand may. }
function pyiter_zip_n(items: TPyList): TPyIter;
{ map(f, xs) / filter(f, xs). `key` is a callable in any of its four
  representations; filter's `key` may be nil, which is Python's own
  `filter(None, xs)` "keep the truthy elements" shorthand. }
function pyiter_map(key: Pointer; const v: Variant): TPyIter;
function pyiter_filter(key: Pointer; const v: Variant): TPyIter;
{ `map(int|str|float, xs)` — the CONVERSION forms, which is what real code
  writes (`w, h = map(int, s.split("x"))`). They carry no callable at all, so
  rather than manufacturing one they ride the MAP kind with FKey nil and the
  conversion code in FStart: 1 = int, 2 = str, 3 = float. Same laziness, no
  dependency on pyeval's callable dispatch. }
function pyiter_map_conv(conv: Int64; const v: Variant): TPyIter;
{ The forms the frontend builds: ONE entry each, taking a cursor, because the
  frontend converts the iterable once (PyMakeIterOf). There used to be a
  spelling per argument type (`_l`, `_s`, the variant one) picked by a helper,
  since these calls go through FindProc and it is not overload-aware — that
  collapsed when `range` arrived as a fourth iterable shape and made the
  per-type dispatch plainly the wrong mechanism. }
function pyiter_map_i(key: Pointer; up: TPyIter): TPyIter;
function pyiter_filter_i(key: Pointer; up: TPyIter): TPyIter;
function pyiter_map_conv_i(conv: Int64; up: TPyIter): TPyIter;
function pyiter_has(it: TPyIter): Boolean;
function pyiter_take(it: TPyIter): Variant;
{ `next(it)` / `next(it, default)`: advance one step. Exhaustion RAISES
  StopIteration for the one-argument form and answers the default otherwise,
  as CPython does. }
function pyiter_next(it: TPyIter): Variant;
function pyiter_next_or(it: TPyIter; const dflt: Variant): Variant;
{ Consume the REST of a cursor into a list — what list()/sorted()/sum()/`in`
  and a tuple-unpack target do with one. Leaves the cursor exhausted, which is
  the CPython-visible half of single consumption. }
function pyiter_drain(it: TPyIter): TPyList;
{ A star OPERAND as a real list. `f(*xs)` where xs is a VARIANT — an
  unannotated parameter, a dict entry, a container element — cannot be decided
  at compile time, and the frontend used to hard-CAST the variant to TPyList:
  a str handle read as a list object, i.e. a segfault on the commonest spelling
  of the construct. The conversion is pyiter_v's, so a str spreads its
  characters, a dict its keys, a range and a user __iter__ their elements, and
  anything non-iterable raises — one normalisation, every star path.
  bug-nilpy-a-star-operand-in-a-variant-is-cast-not-converted }
function pystar_as_list(const v: Variant): TPyList;
{ The iterable `max(*xs)` / `min(*xs)` actually compares. The frontend rewrites
  those two to the single-argument iterable form, which is right for two or
  more elements — comparing the elements IS comparing the list — but wrong for
  exactly ONE: `max(*[[4, 9, 2]])` is CPython's `max([4, 9, 2])` = 9, over the
  element's CONTENTS, and the rewrite compared a one-element list of lists and
  answered `[4, 9, 2]`. The count is a run-time fact, so the choice lives here.
  bug-nilpy-max-and-min-of-a-starred-list-pick-the-wrong-overload }
function pystar_iterable(l: TPyList): TPyList;
{ `g(*xs)` where g declares fixed parameters BEFORE its *args: the operand has
  to cover them, and how many it covers is a run-time fact. Raises CPython's
  wording when it is too short, rather than reading past the end.
  bug-nilpy-star-unpack-that-would-fill-a-fixed-parameter }
procedure pystar_check_min(l: TPyList; lo: Integer; const fname: AnsiString;
                           const pnames: AnsiString);
{ Was element i supplied? The positional half of pystar_has, without the
  kwargs dict — the reach-back distribution has no dict to pass, and
  synthesising a nil one as an argument node is exactly the kind of
  hand-built literal that goes wrong quietly. }
function pystar_has1(l: TPyList; i: Integer): Boolean;
{ True when the variant holds a cursor — the run-time half of the static
  `is TPyIter` test, for the consumption sites that take a Variant. }
function pyiter_is(const v: Variant): Boolean;
{ `<map object at 0x...>` — CPython prints the cursor's CLASS and address, and
  a doctest or a logged debug line sees it. }
function pyiter_repr(it: TPyIter): AnsiString;
function pyiter_typename(it: TPyIter): AnsiString;

{ ---- range (TPyRange) --------------------------------------------------
  A lazy SEQUENCE. See the class. Everything here is arithmetic on three
  Int64s — nothing is ever materialised, so the cost does not depend on the
  range's length. }
function pyrange1(stop: Int64): TPyRange;
function pyrange2(start: Int64; stop: Int64): TPyRange; overload;
function pyrange3(start: Int64; stop: Int64; step: Int64): TPyRange; overload;
{ How many values the range yields — CPython's own formula, clamped at 0, so
  range(5, 0) is empty rather than negative. }
function pyrange_len(r: TPyRange): Int64;
{ r[i], with Python's negative indexing and an IndexError past the end. }
function pyrange_at(r: TPyRange; i: Int64): Int64;
{ `x in r` in CONSTANT time: membership is one modulo, not a scan, which is
  what makes `999999999 in range(10 ** 9)` finish. }
function pyrange_contains(r: TPyRange; const v: Variant): Boolean;
{ r[lo:hi:step] — CPython answers a RANGE, not a list, so slicing composes. }
function pyrange_slice(r: TPyRange; lo: Int64; hi: Int64; step: Int64): TPyRange;
{ Two ranges are equal when they yield the same SEQUENCE, so range(0) equals
  range(2, 2, 3) and range(0, 3, 2) equals range(0, 4, 2). CPython's rule. }
function pyrange_eq(a: TPyRange; b: TPyRange): Boolean;
function pyrange_repr(r: TPyRange): AnsiString;
{ Iterating one yields a CURSOR — a fresh one each time, which is what makes a
  range re-iterable where a cursor is not. }
function pyiter_of_range(r: TPyRange): TPyIter;
function pyrange_is(const v: Variant): Boolean;
{ `len(map(...))` — CPython's TypeError, word for word. A FUNCTION returning
  Int64 so it can stand in for the whole len() expression at the call site, the
  same shape PyIndexTypeError uses; and a RUNTIME raise rather than a compile
  error, so `try: len(m) / except TypeError:` still compiles and runs. }
function pyiter_no_len(it: TPyIter): Int64;
{ The CONSUMING builtins over a cursor — sum/tuple/any/all here, sorted/min/max
  in pyeval — are declared BESIDE their existing overloads further down, NOT
  here. Declaration ORDER decides which class overload a VARIANT argument binds
  to, and declaring the cursor entry first made `sum(v)` (v a variant holding a
  list) unwrap into the TPyIter parameter and segfault — a crash in code that
  never mentions cursors. See each of them below.

  NO `pycontains(it: TPyIter; …)` overload anywhere, deliberately: the frontend
  builds `x in c` through FindProc('pycontains'), which answers ONE proc by bare
  name and never consults overloads, so adding one made `2 in [1, 2, 3]`
  resolve to the cursor entry and segfault
  ([[project_findproc_by_name_ignores_overloads]]). A cursor receiver is
  drained at the `in` site instead (PyDrainIfCursor).

  `len` deliberately has no cursor arm either: CPython raises
  `TypeError: object of type 'map' has no len()` and going lazy is what makes
  that answer available (the umbrella's one behaviour removal). }

function pybound_new(code, recv: Pointer; isFunc: Boolean): Variant;
{ The same pair for a callee that COLLECTS its surplus arguments — `def h(*a)`
  taken as a value. starIdx is the USER-space parameter index of the `*args`
  slot (Self excluded; -1 = no star), and the dynamic bridge below packs
  everything from that position into the TPyList the compiled body declares
  there. Without it pybound_callv3 handed the callee three loose Variants where
  its signature says one list pointer: `k = h; k(1,2,3)` answered 1 for
  `len(a)`, and richer bodies segfaulted
  (bug-nilpy-a-star-args-def-taken-as-a-value-is-called-with-loose-arguments). }
function pybound_new_star(code, recv: Pointer; isFunc: Boolean;
                          starIdx: Int64): Variant;
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
function pybound_callv4(const cb: Variant; const a0, a1, a2, a3: Variant): Variant;
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
{ The RESOLVED path of the running executable — /proc/self/exe, not argv[0].
  argv[0] is whatever the exec caller passed: a PATH lookup ('myapp'), a
  relative path, or an outright lie. This is what `sys.executable` is, what
  `__file__` is for the main module, and what every imported module's virtual
  __file__ hangs off. Falls back to argv[0] where /proc is absent. }
function pysys_executable: AnsiString;
function pysys_file: AnsiString;   { the __file__ dunder — the executable }
{ __file__ for an IMPORTED module: <exe_dir>/<basename>, a VIRTUAL path — no
  file is there. Deterministic, leaks no build environment, and makes
  os.path.dirname(os.path.abspath(__file__)) — the only form real code uses —
  the executable's directory for every module, which is the freezer convention
  (PyInstaller/cx_Freeze) this dialect follows.
  decide-nilpy-dunder-file-for-a-compiled-program }
function pysys_module_file(const modBase: AnsiString): AnsiString;
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
function pyopen(const path: AnsiString): TPyFile;
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
{ Python's hash(x) — the dict's own key hash, exposed. Equal values hash equal;
  the NUMBERS are not CPython's and must not be asserted (it salts strings per
  process). bug-n-hash-builtin-is-not-implemented }
function pyhash_v(const v: Variant): Int64;
function pylen_v(const v: Variant): Int64;
function pyord_v(const v: Variant): Int64;
function pyord_s(const s: AnsiString): Int64;
function pychr_s(n: Int64): AnsiString;
function pymul_v_inplace(const a: Variant; const b: Variant): Variant;
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
{ `isinstance(x, t)` with t a VALUE — a class object or a tuple of them —
  rather than a literal type name. See the body.
  bug-n-a-type-name-is-not-a-first-class-value }
function pyisinstance_v(const x: Variant; const t: Variant): Boolean;
{ A BUILTIN TYPE as a VALUE (`t = str`). The frontend lowers a bare `str` /
  `int` / `list` ... in value position to pybtype(<code>), so a type binds to a
  name, rides in a tuple or a dict, and reaches isinstance exactly as a user
  class object already does. bug-n-a-type-name-is-not-a-first-class-value }
function pybtype(code: Int64): Variant;
function pybtype_is(const v: Variant): Boolean;
function pybtype_code(const v: Variant): Int64;
{ `str`, `int`, ... — the Python spelling, which is both what repr shows and
  what type(x).__name__ answers, so there is one table. }
function pybtype_name(code: Int64): AnsiString;
{ `<class 'str'>` — CPython's repr of a builtin type object. No `__main__.`
  prefix: a builtin is not in the main module, which is exactly the difference
  PyClassRefStr's comment records for user classes. }
function pybtype_repr(const v: Variant): AnsiString;
{ The code the VALUE x is an instance of, or 0 when it is nothing this table
  names. The one place variant tags are mapped onto Python type identity. }
function pybtype_of_value(const x: Variant): Int64;
{ `type(x)` as a VALUE — the type OBJECT, which is a builtin type object for a
  builtin value and a class object (VT_CLASSREF) for a user instance. The
  frontend keeps its own cheap lowering for `type(x).__name__`; every other
  shape (`type(x) == int`, `print(type(x))`, `type(x) is str`) comes here.
  bug-n-a-type-name-is-not-a-first-class-value }
function pytype_of_v(const x: Variant): Variant;
{ `t = str` then `t(5)` — calling a builtin type held as a VALUE, which in
  Python is the CONVERSION. The dynamic-call sites route here for a VT_BTYPE
  callee exactly as they route a VT_CLASSREF one to PyClassRefNew. }
procedure pybtype_call1(const t: Variant; const a0: Variant; var res: Variant);
{ ...and the zero-argument form, `list()` / `str()` / `int()` through a name:
  Python's empty value of that type. }
procedure pybtype_call0(const t: Variant; var res: Variant);
{ The same conversion as a ONE-ARGUMENT FUNCTION, one per type, so a builtin
  type can be handed to a CALLBACK slot — `sorted(xs, key=str)`,
  `min(xs, key=int)`. Those slots are a raw code Pointer (PyCallKey1), and a
  type held as a value is a VARIANT: coerced into the pointer parameter it
  passed the variant's TAG WORD as a code address and the program jumped to
  address 13 (bug-nilpy-a-builtin-type-as-a-key-callback-segfaults). The
  frontend rewrites the argument to one of these instead. }
function pyconv_str(const a0: Variant): Variant;
function pyconv_int(const a0: Variant): Variant;
function pyconv_float(const a0: Variant): Variant;
function pyconv_bool(const a0: Variant): Variant;
function pyconv_list(const a0: Variant): Variant;
function pyconv_dict(const a0: Variant): Variant;
function pyconv_set(const a0: Variant): Variant;
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
{ THE one chain that turns an OBJECT into a materialised sequence: a list, a
  dict's keys, a bytes' values, a drained cursor, a range, or a user class
  implementing `__iter__`. Answers nil when `o` is none of those, so each
  caller keeps its OWN refusal (set() and list() word it differently) and its
  own kind stamping, while the chain itself exists once.

  It exists because that chain had been written out FIVE times — pylist_v,
  list(Variant), tuple(Variant), pyset_of and pyeval's sorted(Variant) — and the copies had drifted: only
  pylist_v had grown the user-`__iter__` arm, so `list(bag)`, `tuple(bag)` and
  `sorted(bag)` answered [] while the same object iterated correctly in a `for`
  (bug-nilpy-builtins-over-a-user-iterable-answer-empty). pyset_of had drifted
  further still and knew neither cursors nor ranges.

  Always a FRESH list: `list(xs)` copies, and every caller here wants to own
  its result. }
function pyseq_of_obj(o: TObject): TPyList;
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
function pystar_argc(l: TPyList; d: TPyDict): Integer;
function pystar_has(l: TPyList; d: TPyDict; i: Integer; const nm: AnsiString): Boolean;
function pystar_arg_kw(l: TPyList; d: TPyDict; i: Integer; const nm: AnsiString): Variant;
procedure pystar_check_arity_kw(l: TPyList; d: TPyDict; lo: Integer; hi: Integer);
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
function pylist_repeat_inplace(l: TPyList; n: Int64): TPyList;
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
{ min()/max() of ONE argument that is a VARIANT — a loop element, a dict value,
  an unannotated parameter. Without these the only single-argument overload in
  this unit was the AnsiString one, so a variant holding a LIST was read as a
  STRING: `for row in grid: max(row)` raised "max() arg is an empty sequence"
  while `sum(row)`, `len(row)` and `sorted(row)` on the same value were all
  correct. Dispatches on the runtime tag, and compares with pyvar_gt so a list
  of user objects honours __gt__/__lt__ exactly as sorted() does.
  Declared HERE in the top block rather than beside the implementation: a
  forward declaration dropped into the middle of the implementation section
  disturbs this unit's resolution order, and unrelated long-standing forward
  uses (PySliceBounds, PyVarText) started failing when it was.
  bug-nilpy-min-max-of-a-variant-list-reads-it-as-a-string }
function max(const v: Variant): Variant; overload;
function min(const v: Variant): Variant; overload;
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
{ `list(<cursor>)` — CONSUMES it, leaving it exhausted, which is CPython's
  single-consumption rule. See pyiter_drain. }
function list(it: TPyIter): TPyList; overload;
{ `list(range(3))` — the shape that used to need a hard-coded whitelist of
  "callees that only iterate their argument", because range was not a value. }
function list(r: TPyRange): TPyList; overload;
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
{ tuple(<variant>) — a VARIANT receiver, which is what a list element or an
  unannotated parameter is. Without it the call bound the TPyList overload and
  the compiler inserted an unchecked unwrap, so a variant holding a STRING was
  reinterpreted as a list instance and `for x in ["cab"]: tuple(x)` SEGFAULTED.
  `list` never had the bug precisely because it has this overload.
  bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked }
function tuple(const v: Variant): TPyList; overload;
function tuple(it: TPyIter): TPyList; overload;
function tuple(r: TPyRange): TPyList; overload;
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
{ dict(<cursor>): the pairs a cursor yields — dict(zip(a, b)). }
function dict(it: TPyIter): TPyDict; overload;
function dict(l: TPyList): TPyDict; overload;

{ dict.fromkeys(iterable): a dict with those keys, values None, insertion order
  preserved. `list(dict.fromkeys(xs))` is the standard order-preserving dedupe. }
{ The parameter is a VARIANT, not a TPyList, and that is the fix rather than a
  style choice: the stdlib call site builds this call BY NAME and cannot
  resolve overloads by type, so `dict.fromkeys("ab")` handed a str straight
  into a TPyList parameter and SEGFAULTED. pylist_v is the one bridge that
  turns any Python iterable into a list, so it belongs here.
  bug-nilpy-dict-fromkeys-of-a-str-segfaults }
function pydict_fromkeys(const src: Variant): TPyDict;
function pydict_fromkeys(const src: Variant; const v: Variant): TPyDict; overload;
{ `set(iterable)` — Python's set constructor. A set is a TPyList here (see
  PyAnnTypeAt and TPyList.add), so this is "copy, skipping duplicates". The
  iterable may be a list/tuple/set, a dict (its KEYS, like CPython) or a string
  (its characters); anything else is a loud TypeError rather than a guess. }
function pyset_of(const v: Variant): TPyList;
{ `{**a, **b}` — copy src's pairs into dst, later keys winning, which is
  Python's merge rule. The frontend emits one call per `**` in a dict literal. }
{ `d.update(m, c=2)`'s SEED merge: the positional argument is whatever
  dict.update itself accepts — a mapping or an iterable of pairs — and which one
  it is is a RUN-TIME fact, so it is taken as a Variant and dispatched on the
  object's class, exactly as TPyDict.update(const v: Variant) does. Merging it
  with the typed pydict_merge instead compiled a list seed happily and then
  SEGFAULTED reading a TPyList through a TPyDict — a silent wrong answer where
  the unfixed compiler had a clean refusal, which is the one outcome worse than
  the bug. bug-nilpy-dict-update-mixed-positional-and-keyword-args }
procedure pydict_merge_any(dst: TPyDict; const src: Variant);
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
{ `<`, checked in SOURCE operand order — see PyOrdRefuse. Every caller that
  means "a is less than b" uses this rather than pyvar_gt with the arguments
  swapped, so an unorderable pair is refused with CPython's wording. }
function pyvar_lt(const a: Variant; const b: Variant): Boolean;
procedure PyOrdCheck(const a: Variant; const b: Variant; const op: AnsiString);
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
{ `round(x, ndigits)` where x's INTNESS must survive: an int in is an int out,
  whatever ndigits is, and a variant is the shape that carries either. The
  frontend hands the RAW argument here (it defers its own unbox for the
  two-argument form) so a promotable int keeps its precision instead of being
  flattened to a double on the way in.
  bug-nilpy-two-argument-round-of-an-int-returns-a-float }
function pyround_v(const x: Variant; n: Int64): Variant;
{ The ONE-argument `round(x)` over a variant: an int stays itself, an
  arbitrary-precision int stays EXACT (the float path narrowed 2**70 to
  -9223372036854775808), and a float rounds half-to-EVEN into an int, as
  CPython does. }
function pyround1_v(const x: Variant): Variant;
function pyround_int(x: Int64; n: Int64): Int64;
{ Python's math.floor/math.ceil return an int, unlike the RTL Math unit's
  Floor/Ceil (Double->Double, shared with the Pascal frontend and left alone
  here) -- these are the NilPy-specific int-returning shims, dispatched by
  name ahead of ordinary qualified-call resolution so `import math` never
  reaches the RTL's own Floor/Ceil for these two names. }
function pymath_floor(x: Double): Int64;
function pymath_ceil(x: Double): Int64;
function pymath_fabs(x: Double): Double;
{ math.trunc — the SAME int/float contract mismatch that put floor/ceil here,
  and the reason a Double->Double `Trunc` was deliberately NOT added to
  lib/rtl/math.pas: it would resolve ahead of everything and hand every caller
  the wrong type quietly. Rounds toward ZERO, which is floor only for
  positives (trunc(-2.5) is -2, floor(-2.5) is -3).
  bug-n-math-trunc-and-log-need-frontend-intercepts }
function pymath_trunc(x: Double): Int64;
{ math.copysign — cannot live in lib/rtl/math.pas under this name at all: a
  Pascal `copysign` there hijacks libc's in every C program through pxxcio
  (bug-c-pascal-math-names-hijack-libc-through-pxxcio, measured — copysign(3,-1)
  answered atan2's result). The sign is read from the BIT PATTERN, not from
  `y < 0`, so copysign(3, -0.0) is -3.0 as CPython has it. }
function pymath_copysign(x, y: Double): Double;
{ The remaining math names that need a CONTAINER or an exact algorithm, so they
  cannot be a plain intercept onto an RTL routine the way asin/acos/atan/log do.
  None of them needs a transcendental, which is what keeps them buildable inside
  a BUILTIN unit (see the note on math.log above for why that matters).
  bug-nilpy-math-surface-remaining-gaps-and-degrees-association }
{ CPython's math domain refusals, as ARGUMENT guards: each returns its argument
  unchanged or raises `ValueError: math domain error`, so the frontend can wrap
  the argument of the RTL routine it already calls. Checking the ARGUMENT and
  not the result is what keeps `sqrt(nan)` answering nan, as CPython does — a
  NaN fails every comparison and passes straight through.
  bug-n-math-pow-domain-error-raises-the-wrong-exception }
function pymath_dom_nonneg(x: Double): Double;
function pymath_dom_pos(x: Double): Double;
function pymath_dom_unit(x: Double): Double;
function pymath_dom_pow(b: Double; e: Double): Double;
{ the `**` OPERATOR's guard — a DIFFERENT refusal from math.pow's; see the body }
function pymath_range(v: Double; a: Double; b: Double): Double;
function pypow_range(v: Double; a: Double; b: Double): Double;
function pymath_range1(v: Double; a: Double): Double;
function pypow_dom(b: Double; e: Double): Double;
type
  { The correctly-rounded pow the FLOAT `**` should use. It lives in
    lib/rtl/math.pas as `Power`, and pylib is a BUILTIN unit that cannot reach
    it: `uses math` compiles, and then the RTL's `Abs` overload set hides
    pylib's own, so `abs(2.5)` stops resolving (measured 2026-08-16). A hook is
    the way around that wall — the frontend pulls `math` whenever it sees `**`
    and installs `@Power` here, exactly as builtinheap takes its object
    finalizer from pylib without being able to name it.
    nil = nothing installed (no math unit in this program): the series below
    still answers, as it always did.
    bug-a-nilpy-star-star-has-its-own-low-precision-pow }
  TPyPowFn = function(b, e: Double): Double;
var
  PyPowHook: TPyPowFn;
function pymath_modf(x: Double): TPyList;
function pymath_prod(l: TPyList): Variant;
function pymath_fsum(l: TPyList): Double;
function pymath_perm(n, k: Int64): Int64;
{ ---- random ------------------------------------------------------------
  `import random` had nothing behind it at all — `random.random()` was
  `undefined variable`, and it is one of the first imports a script reaches
  for. A SplitMix64 generator: 64 bits of state, one multiply-xor step, and
  good enough for the shuffling and sampling a script does.

  The SEQUENCE is deliberately not CPython's. CPython uses Mersenne Twister and
  its exact stream is an implementation detail even there; what a program can
  legitimately depend on is the CONTRACT — random() in [0, 1), randint(a, b)
  inclusive at both ends, choice() an element of the sequence, shuffle() a
  permutation — and that a given seed repeats. Those are what the test asserts.
  bug-nilpy-math-surface-remaining-gaps-and-degrees-association }
procedure pyrandom_seed(n: Int64);
function pyrandom_random: Double;
function pyrandom_randint(a, b: Int64): Int64;
function pyrandom_randrange(n: Int64): Int64;
function pyrandom_uniform(a, b: Double): Double;
function pyrandom_choice(l: TPyList): Variant;
procedure pyrandom_shuffle(l: TPyList);
function pynext_first(l: TPyList): Variant;
function pynext_first_or(l: TPyList; const dflt: Variant): Variant;
{ `next(x)` / `next(x, default)` where x is whatever the argument turned out to
  be — a CURSOR (which must ADVANCE, so the next call sees the next element), a
  list, a range, a user iterable. The two above take a TPyList and read element
  0, which was right while every genexpr materialised into one; once a genexpr
  bound to a name became a cursor, the same written call handed a TPyIter to a
  TPyList parameter and answered the default (bug filed with
  bug-nilpy-a-generator-expression-is-not-consumed-once). One entry point per
  arity, deciding at run time, rather than a static pick the frontend cannot
  always make. }
function pynext_v(const v: Variant): Variant;
function pynext_or_v(const v: Variant; const dflt: Variant): Variant;
function sum(l: TPyList): Variant;
function sum(r: TPyRange): Variant; overload;
{ ...and over a CURSOR, declared after the list forms on purpose — see the note
  in the cursor block above. Drains, then the routine that already exists. }
function sum(it: TPyIter): Variant; overload;
function sum(it: TPyIter; const start: Variant): Variant; overload;
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
function any(it: TPyIter): Boolean; overload;
function all(it: TPyIter): Boolean; overload;
function any(r: TPyRange): Boolean; overload;
function all(r: TPyRange): Boolean; overload;
{ …and over a VARIANT, which is what an unannotated parameter, a dict entry and
  a container element all are. Without these arms the call fell to the TPyList
  one and the variant was hard-CAST: `def s(v): return sum(v)` answered 0 for a
  range and SEGFAULTED for a map cursor, while the identical `sum(range(4))`
  written inline was right. max/min/len/tuple already had the arm — these four
  are the ones that did not, which is the whole shape of the bug.
  pylist_v decides on the run-time tag (a str spreads, a dict gives its keys, a
  cursor DRAINS, a user __iter__ is walked). }
function sum(const v: Variant): Variant; overload;
function sum(const v: Variant; const start: Variant): Variant; overload;
function any(const v: Variant): Boolean; overload;
function all(const v: Variant): Boolean; overload;

{ collections.Counter(...) — a TPyDict in Counter mode; see TPyDict. }
function Counter: TPyDict;
function Counter(l: TPyList): TPyDict; overload;
function Counter(const s: AnsiString): TPyDict; overload;
{ `reversed(x)` — a CURSOR walking the source backwards, which is what CPython
  returns (`list_reverseiterator`). It used to be the reversed COPY, on the
  grounds that NilPy's `for` was a counted-loop desugar with no iterator
  concept; TPyIter is that concept (feature-nilpy-lazy-iterator-objects), and
  the only thing laziness buys HERE is the exhaustion rule, since the source is
  already materialised. `[::-1]` does NOT come through this any more — it goes
  to pylist_slice_step, which is what carries tupleness across
  (bug-nilpy-derived-tuple-loses-tupleness). }
function reversed(l: TPyList): TPyIter;
function reversed(const s: AnsiString): TPyIter; overload;
{ reversed(<variant>) — a VARIANT receiver, same shape and same crash as
  tuple(<variant>) above. Declared AFTER the two typed forms, like every other
  cursor overload here: order decides which one a variant unwraps into. }
function reversed(r: TPyRange): TPyIter; overload;
function reversed(const v: Variant): TPyIter; overload;
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
{ `len(range(...))` is legal and cheap — a range knows its length without
  producing a single value. This is exactly where a range differs from a
  cursor, whose len() is a TypeError. }
function len(r: TPyRange): Integer; overload;
function next(c: TPyCounter): Int64;
{ Python's `iter(x)` and `next(it[, default])` — the two builtins the cursor
  family finally gives somewhere to live
  (bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep). Spelled as
  ordinary OVERLOADED pylib functions rather than parser arms, exactly as
  list()/sorted()/min()/max() are: neither name is a Pascal keyword, so the
  normal call path resolves them by argument type and a user `def iter(...)`
  shadows them for free. `next` already had a TPyCounter overload above — an
  itertools.count advance — and the two coexist because the ARGUMENT tells
  them apart. }
function iter(l: TPyList): TPyIter;
function iter(it: TPyIter): TPyIter; overload;
function iter(d: TPyDict): TPyIter; overload;
function iter(b: TPyBytes): TPyIter; overload;
function iter(const s: AnsiString): TPyIter; overload;
function iter(const v: Variant): TPyIter; overload;
function iter(r: TPyRange): TPyIter; overload;
function next(it: TPyIter): Variant; overload;
function next(it: TPyIter; const dflt: Variant): Variant; overload;
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
{ ---- FORWARD DECLARATIONS for helpers used ABOVE their definitions --------
  Each of these was called from a routine EARLIER in this unit with no
  declaration of any kind. That does not fail to compile — it links to a
  plausible wrong address
  (project_bodyless_procaddr_links_to_entry_minus_one) — and it is a tripwire
  twice over: such a call can pass its tests, and an unrelated declaration
  added elsewhere can make it start failing to compile in code nobody touched
  (PySliceBounds and PyVarText both did, 2026-08-09).
  Declared HERE, in the top block, rather than beside each implementation: a
  declaration dropped into the middle of the implementation section is what
  disturbed the resolution order in the first place.
  chore-nilpy-pylib-forward-uses-are-a-build-tripwire }
procedure PySliceBounds(n: Integer; var lo, hi: Integer); forward;
function PyVarIsFloat(p: PPyVarRec): Boolean; forward;
function PyVarAsFloat(p: PPyVarRec): Double; forward;
function PyVarText(p: PPyVarRec): AnsiString; forward;
procedure PyPromoteIntArith(dst: Pointer; x, y: Int64; op: Integer); forward;
function PyIntOpOverflows(x, y, r: Int64; op: Integer): Boolean; forward;
function PyFmtExp(v: Double; prec: Integer; upper: Boolean): AnsiString; forward;
function PyFmtG(v: Double; prec: Integer; upper: Boolean): AnsiString; forward;

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
{ pyvarobj for an ARGUMENT that is binding a CLASS-typed parameter, CHECKED.

  Overload resolution lets a Variant argument bind a class parameter and the
  compiler inserts an unwrap to make it fit (IRLowerCallArg, ir.inc). Unwrapping
  with plain pyvarobj hands back the raw payload, so a variant holding a STRING
  was reinterpreted as an instance pointer and the callee dereferenced it —
  `tuple(v)`, `sorted(v)`, `bytes(v)`, `reversed(v)` and `sum(v)` all SEGFAULTED
  on an ordinary `for x in ["cab"]` receiver
  (bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked).

  Deliberately a SEPARATE entry point rather than a check inside pyvarobj: the
  runtime dispatch arms call `pyvarobj(v) is C ? ... : ...` with variants holding
  strings and ints ON PURPOSE and need the test to come back False. Making
  pyvarobj raise would turn every one of those chains into an exception on its
  first non-matching arm.

  None unwraps to nil, which is legitimate — passing None where a class is
  expected is ordinary Python. }
function pyvarobj_arg(const v: Variant): Pointer;
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
function pyvar_callable_ptr_opt(const v: Variant; const what: AnsiString): Pointer;   { ...for a parameter whose default is nil: None means "not given", not an error }
{ Python's `callable(x)`. It was simply absent (`undefined variable`), while the
  predicate it needs — PyVarIsCallable, the same "callable" this dialect
  already commits to for min/max's key detection — has been in this unit all
  along, just not in its interface. Declared by its PYTHON name so ordinary
  name resolution finds it; no frontend intercept.
  bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep }
function callable(const v: Variant): Boolean;
{ `v[key]` / `v[key] = val` where v is a VARIANT holding a container — a dict
  entry that was itself a `.get()` result, so its container type is only known
  at run time. Dispatch on the boxed object: dict fetch/store by key, list index
  by an integer key. }
function pyvar_getitem(const v: Variant; const key: Variant): Variant;
{ str()/print() of a user class instance; 'None' for a nil handle. }
function pyobj_str_of(o: TObject): AnsiString;
{ `del v[k]` on a variant receiver — see the implementation. }
function pyvar_delitem(const v: Variant; const key: Variant): Variant;
procedure pyvar_setitem(const v: Variant; const key: Variant; const val: Variant);
{ DYNAMIC instance attributes: `obj.name = v` / `obj.name` where `name` is not a
  declared field (Python adds them freely). Stored in one global dict keyed by
  the object's address and the attribute name, so no per-class field is needed.
  uforth uses this for lazy state (`if not hasattr(vm, '_trans_ptr'): vm._trans_ptr = ...`). }
function pydynattr_get(obj: Pointer; const name: AnsiString): Variant;
{ `__getattr__` — the LAST step of CPython's attribute lookup, after the
  instance dict and the declared members have both missed. Declared here rather
  than forward-declared in the implementation because all three attribute-miss
  sites sit above its body. bug-nilpy-getattr-dunder-not-supported }
function PyUserObjGetattr(o: TObject; const name: AnsiString;
                          var res: Variant): Boolean;
{ ...and the same call with an AttributeError refusal turned into False, which
  is what a PRESENCE question (hasattr, getattr-with-a-default) needs. }
function PyUserObjGetattrTry(o: TObject; const name: AnsiString;
                             var res: Variant): Boolean;
function pydynattr_has_any_v(const v: Variant; const name: AnsiString): Boolean;   { hasattr for a COMPUTED name: the dynamic store PLUS declared fields and methods, matching what pydynattr_get_v resolves }
procedure pydynattr_set(obj: Pointer; const name: AnsiString; const val: Variant);
function pydynattr_has(obj: Pointer; const name: AnsiString): Boolean;
{ hasattr's wider question for a class-typed receiver — store, declared members,
  methods, then __getattr__. pydynattr_has above is the STORE only, because
  pydynattr_get uses it to decide whether to fetch. }
function pydynattr_hasattr(obj: Pointer; const name: AnsiString): Boolean;
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
{ `T = TypeVar("T")` — typing's run-time constructor for a type parameter.
  `typing` is a consumed-and-ignored import (what it exports is annotation
  metadata, read statically by PyAnnTypeAt and never evaluated), which is right
  for `List`/`Optional`/`Dict` and wrong for the few names that are CALLED at
  run time: the name was simply unbound and the module died at the call with
  `undefined variable (TypeVar)`, naming the call rather than the import that
  dropped it.

  NilPy erases generics, and an annotation naming the result is degraded to Any
  (bug-n-an-uninterpretable-annotation-refuses-the-program), so the VALUE is
  never inspected — returning CPython's own `~T` spelling keeps a debug print
  byte-identical. The extra keyword forms (`bound=`, `covariant=`) are not modelled;
  they change nothing that survives erasure.
  bug-n-typevar-call-is-an-undefined-variable }
function TypeVar(const name: AnsiString): AnsiString;
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
{ `s.isascii()` — every byte below 128. NilPy strings ARE byte strings, so this
  is a plain scan and needs no codepoint model (unlike encode/decode, which is
  parked on one — bug-nilpy-encode-ignores-the-codec). CPython answers True for
  the EMPTY string, unlike isspace/isdigit/isalpha which answer False, because
  "all characters are ascii" is vacuously true where "is a digit" is not.
  feature-nilpy-str-surface-gaps-2026-08-09 }
function pystr_isascii(const s: AnsiString): Boolean;
{ str.maketrans(frm, to) — CPython's table is a DICT keyed by the ORDINAL of
  each source character, valued by the ordinal of its replacement. Modelled
  exactly, so `print(str.maketrans("lo","01"))` shows `{108: 48, 111: 49}` like
  CPython and a hand-written dict literal works as a table too.
  feature-nilpy-str-surface-gaps-2026-08-09 }
function pystr_maketrans(const frm: AnsiString; const t: AnsiString): TPyDict;
{ str.translate(table) — map each byte through the table. A missing key leaves
  the character alone; an INT value is a replacement ordinal, a STRING value is
  substituted whole (CPython allows a multi-character replacement), and None
  DELETES the character. }
function pystr_translate(const s: AnsiString; t: TPyDict): AnsiString;
function pystr_isspace(const s: AnsiString): Boolean;
{ CPython: "".isdigit()/.isalpha()/.isupper()/.islower() are all FALSE — the
  all-quantifier does not hold vacuously for any of them. }
function pystr_isdigit(const s: AnsiString): Boolean;
function pystr_isnumeric(const s: AnsiString): Boolean;
function pystr_istitle(const s: AnsiString): Boolean;
function pystr_isalpha(const s: AnsiString): Boolean;
function pystr_isupper(const s: AnsiString): Boolean;
function pystr_islower(const s: AnsiString): Boolean;
function pystr_ofchar(c: Char): AnsiString;
function pystr_at(const s: AnsiString; i: Integer): Char;
{ `s[i]` as Python means it: a whole CHARACTER, as a 1-character str. Python has
  no char type, so this — not pystr_at — is what a subscript, an iteration
  variable and list(s) all lower to. Keeping pystr_at (a lead BYTE) beside it
  would be two mechanisms for one concept; it survives only for callers that
  genuinely want a byte. }
function pystr_charat(const s: AnsiString; i: Integer): AnsiString;
{ Length() as a real Proc. The for-in desugar builds its AST directly and so
  needs a callable, not the shared parser's intrinsic path. }
function pystr_len(const s: AnsiString): Integer;
function pystr_join(const sep: AnsiString; l: TPyList): AnsiString;
function pystr_split_ws(const s: AnsiString): TPyList;
function pystr_split_sep(const s: AnsiString; const sep: AnsiString): TPyList;
function pystr_split_sep_max(const s: AnsiString; const sep: AnsiString; maxsplit: Integer): TPyList;
{ str.split(None, maxsplit) / str.rsplit(None, maxsplit) — an EXPLICIT None
  separator means whitespace runs, exactly like the no-argument form. }
function pystr_split_ws_max(const s: AnsiString; maxsplit: Integer): TPyList;
function pystr_rsplit_ws_max(const s: AnsiString; maxsplit: Integer): TPyList;
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
{ `s.startswith(("a", "b"))` — Python accepts a TUPLE of prefixes and answers
  True if ANY matches. The argument arrives as a Variant so one entry point
  covers a tuple literal, a tuple-typed local and a variant that only turns out
  to hold one at run time; a plain string still answers as the ordinary form
  does. Used only when the argument is NOT statically a string, so the common
  `sys.platform.startswith("win")` path is unchanged.
  bug-nilpy-startswith-endswith-ignore-a-tuple-argument }
function pystr_startswith_any(const s: AnsiString; const v: Variant): Boolean;
function pystr_endswith_any(const s: AnsiString; const v: Variant): Boolean;
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

{ Case mapping for ONE code point, the simple (1:1) part of Unicode's rules.

  ASCII plus the European blocks whose case pairs are pure arithmetic:
  Latin-1 Supplement, Latin Extended-A, Greek and Cyrillic. That is a few
  ranges of code, not a Unicode database, and it covers essentially all
  European text — which is the "256-entry table" the ticket asks for, done at
  code-point level because NilPy strings are UTF-8 and character-indexed
  (they stopped being byte-indexed 2026-08-14).

  Deliberately NOT here: any mapping that changes the code-point COUNT.
  `'ß'.upper()` is `'SS'` and `'ﬁ'.upper()` is `'FI'` in CPython, which a 1:1
  mapper cannot express — that is its own ticket
  (bug-nilpy-case-mapping-cannot-change-code-point-count), and leaving those
  characters ALONE is the honest answer here rather than a wrong single
  character. bug-nilpy-non-ascii-string-surface-measured }
function PyCpUpper(cp: Int64): Int64;
begin
  PyCpUpper := cp;
  if (cp >= 97) and (cp <= 122) then begin PyCpUpper := cp - 32; Exit; end;
  if cp < 128 then Exit;
  { Latin-1 Supplement: à-þ -> À-Þ, minus ÷ (which is not a letter) and ß }
  if (cp >= $E0) and (cp <= $FE) and (cp <> $F7) then
  begin PyCpUpper := cp - 32; Exit; end;
  if cp = $FF then begin PyCpUpper := $178; Exit; end;   { ÿ -> Ÿ }
  if cp = $B5 then begin PyCpUpper := $39C; Exit; end;   { µ MICRO SIGN -> Μ }
  if cp = $17F then begin PyCpUpper := $53; Exit; end;   { ſ long s -> S }
  { The Turkish dotted/dotless I is NOT the adjacent pair its code points look
    like: `'ı'.upper()` is ASCII `I`, and `'İ'.lower()` is `i` plus a COMBINING
    DOT — two code points, so it is left alone rather than answered wrongly.
    Taken as a pair (which the surrounding Extended-A band would do) this
    produced İ for upper('ı') and ı for lower('İ'), the only two characters in
    a 0..$500 sweep where we answered a DIFFERENT character rather than none. }
  if cp = $131 then begin PyCpUpper := $49; Exit; end;
  if cp = $130 then Exit;
  { Latin Extended-A comes in adjacent PAIRS, but which half is the capital
    flips twice across the block: even-upper through $137, ODD-upper for
    $139-$148 (that is where Ł/ł live — reading the whole block as even-upper
    left `'łódź'.upper()` with one letter unchanged), even-upper again to $177,
    then odd-upper for $179-$17E (Ź/Ż/Ž). $138 and $149 have no pair. }
  if (cp >= $100) and (cp <= $137) and ((cp and 1) = 1) then
  begin PyCpUpper := cp - 1; Exit; end;
  if (cp >= $139) and (cp <= $148) and ((cp and 1) = 0) then
  begin PyCpUpper := cp - 1; Exit; end;
  if (cp >= $14A) and (cp <= $177) and ((cp and 1) = 1) then
  begin PyCpUpper := cp - 1; Exit; end;
  if (cp >= $17A) and (cp <= $17E) and ((cp and 1) = 0) then
  begin PyCpUpper := cp - 1; Exit; end;
  { Greek: α-ω -> Α-Ω, with final sigma folding onto Σ like every other sigma }
  if cp = $3C2 then begin PyCpUpper := $3A3; Exit; end;
  if (cp >= $3B1) and (cp <= $3C9) then begin PyCpUpper := cp - 32; Exit; end;
  { ...and the ACCENTED Greek vowels, whose capitals sit in a separate block —
    scattered, so listed rather than derived. Without these `'αθήνα'.upper()`
    left the one accented letter alone, which is the same one-character-wrong
    failure the Latin block had. }
  if cp = $3AC then begin PyCpUpper := $386; Exit; end;
  if (cp >= $3AD) and (cp <= $3AF) then begin PyCpUpper := cp - 37; Exit; end;
  if cp = $3CA then begin PyCpUpper := $3AA; Exit; end;
  if cp = $3CB then begin PyCpUpper := $3AB; Exit; end;
  if cp = $3CC then begin PyCpUpper := $38C; Exit; end;
  if (cp >= $3CD) and (cp <= $3CE) then begin PyCpUpper := cp - 63; Exit; end;
  { Cyrillic: а-я -> А-Я, and the separate ё-џ block }
  if (cp >= $430) and (cp <= $44F) then begin PyCpUpper := cp - 32; Exit; end;
  if (cp >= $450) and (cp <= $45F) then begin PyCpUpper := cp - 80; Exit; end;
  { Armenian: ա-ֆ -> Ա-Ֆ, offset 48. Reached by ordinary Armenian text and also
    by the title form of the և ligature, whose expansion's second letter has to
    lower. }
  if (cp >= $561) and (cp <= $586) then begin PyCpUpper := cp - 48; Exit; end;
end;

function PyCpLower(cp: Int64): Int64;
begin
  PyCpLower := cp;
  if (cp >= 65) and (cp <= 90) then begin PyCpLower := cp + 32; Exit; end;
  if cp < 128 then Exit;
  if (cp >= $C0) and (cp <= $DE) and (cp <> $D7) then
  begin PyCpLower := cp + 32; Exit; end;
  if cp = $178 then begin PyCpLower := $FF; Exit; end;
  { see PyCpUpper: `'İ'.lower()` is two code points, so this one stays put }
  if (cp = $130) or (cp = $131) then Exit;
  if (cp >= $100) and (cp <= $137) and ((cp and 1) = 0) then
  begin PyCpLower := cp + 1; Exit; end;
  if (cp >= $139) and (cp <= $148) and ((cp and 1) = 1) then
  begin PyCpLower := cp + 1; Exit; end;
  if (cp >= $14A) and (cp <= $177) and ((cp and 1) = 0) then
  begin PyCpLower := cp + 1; Exit; end;
  if (cp >= $179) and (cp <= $17D) and ((cp and 1) = 1) then
  begin PyCpLower := cp + 1; Exit; end;
  if (cp >= $391) and (cp <= $3A9) then begin PyCpLower := cp + 32; Exit; end;
  if cp = $386 then begin PyCpLower := $3AC; Exit; end;
  if (cp >= $388) and (cp <= $38A) then begin PyCpLower := cp + 37; Exit; end;
  if cp = $38C then begin PyCpLower := $3CC; Exit; end;
  if (cp >= $38E) and (cp <= $38F) then begin PyCpLower := cp + 63; Exit; end;
  if cp = $3AA then begin PyCpLower := $3CA; Exit; end;
  if cp = $3AB then begin PyCpLower := $3CB; Exit; end;
  if (cp >= $531) and (cp <= $556) then begin PyCpLower := cp + 48; Exit; end;
  if (cp >= $410) and (cp <= $42F) then begin PyCpLower := cp + 32; Exit; end;
  if (cp >= $400) and (cp <= $40F) then begin PyCpLower := cp + 80; Exit; end;
end;

{ The case mappings that CHANGE THE CODE-POINT COUNT — `'ß'.upper()` is `'SS'`,
  not a single character. A 1:1 mapper cannot express these at all, which is why
  they were left alone until PyStrMapCase gained a code-point cursor and a
  growable result; now they are a table.

  Answers '' when the code point has no multi-character upper mapping, so the
  caller falls through to the ordinary PyCpUpper. The TITLE form CPython uses
  for capitalize()/title() is this same string with only its first character
  upper ('Ss', 'Ffi'), which is derived rather than tabulated.
  bug-nilpy-case-mapping-cannot-change-code-point-count }
function PyCpUpperStr(cp: Int64): AnsiString;
begin
  PyCpUpperStr := '';
  if cp = $DF then PyCpUpperStr := 'SS'                     { ß }
  else if cp = $149 then PyCpUpperStr := #$CA#$BC + 'N'     { ŉ -> ʼN }
  else if cp = $1F0 then PyCpUpperStr := 'J' + #$CC#$8C     { ǰ -> J + caron }
  else if cp = $587 then PyCpUpperStr := #$D4#$B5#$D5#$92   { և -> ԵՒ }
  else if cp = $1E96 then PyCpUpperStr := 'H' + #$CC#$B1    { ẖ }
  else if cp = $1E97 then PyCpUpperStr := 'T' + #$CC#$88    { ẗ }
  else if cp = $1E98 then PyCpUpperStr := 'W' + #$CC#$8A    { ẘ }
  else if cp = $1E99 then PyCpUpperStr := 'Y' + #$CC#$8A    { ẙ }
  else if cp = $FB00 then PyCpUpperStr := 'FF'
  else if cp = $FB01 then PyCpUpperStr := 'FI'
  else if cp = $FB02 then PyCpUpperStr := 'FL'
  else if cp = $FB03 then PyCpUpperStr := 'FFI'
  else if cp = $FB04 then PyCpUpperStr := 'FFL'
  else if cp = $FB05 then PyCpUpperStr := 'ST'
  else if cp = $FB06 then PyCpUpperStr := 'ST';
end;

{ …and the one in the other direction: `'İ'.lower()` is `i` plus a COMBINING
  DOT ABOVE, two code points. Its 1:1 sibling is deliberately absent (see
  PyCpUpper's note on the Turkish dotted/dotless I). }
function PyCpLowerStr(cp: Int64): AnsiString;
begin
  PyCpLowerStr := '';
  if cp = $130 then PyCpLowerStr := 'i' + #$CC#$87;
end;

{ An expansion in TITLE form: first character upper, the rest lower — 'Ss' from
  'SS'. Derived from the upper table rather than tabulated beside it, so the two
  cannot drift. }
function PyTitleFormOf(const up: AnsiString): AnsiString;
var i: Integer; cp: Int64; seenCased: Boolean;
begin
  PyTitleFormOf := '';
  i := 1;
  seenCased := False;
  while i <= Length(up) do
  begin
    cp := PyUtf8CpAt(up, i);
    { lowercase everything after the first CASED character, not after the first
      character: `'ŉ'.title()` is `ʼN`, whose leading modifier apostrophe is
      uncased, so the N is the one that stays upper. Lowering by position gave
      `ʼn`. }
    if seenCased then cp := PyCpLower(cp)
    else if (PyCpUpper(cp) <> cp) or (PyCpLower(cp) <> cp) then seenCased := True;
    PyCpToUtf8(PyTitleFormOf, cp);
  end;
end;

{ Walk a UTF-8 string, mapping each code point. `mode` 0 = upper, 1 = lower,
  2 = capitalize (first character up, rest down), 3 = swapcase, 4 = title.
  ONE walker for all five, because five copies of "decode, map, re-encode" is
  how the next case-mapping gap gets fixed in four places and missed in the
  fifth. }
function PyStrMapCase(const s: AnsiString; mode: Integer): AnsiString;
var i, n: Integer; cp, mapped: Int64; first, prevAlnum: Boolean;
    wantUp, wantTitle: Boolean;
begin
  Result := '';
  n := Length(s);
  i := 1;
  first := True;
  prevAlnum := False;
  while i <= n do
  begin
    cp := PyUtf8CpAt(s, i);
    mapped := cp;
    { does this position want the UPPER mapping, the TITLE one, or LOWER? One
      decision, so the count-changing table below is consulted once rather than
      per mode. }
    wantUp := False; wantTitle := False;
    if mode = 0 then wantUp := True
    else if mode = 2 then
    begin
      if first then wantTitle := True;
    end
    else if mode = 3 then
      { …including a character whose only upper mapping is a multi-character
        one: `'ß'.swapcase()` is `'SS'`, and asking PyCpUpper alone said "no
        mapping, so it must already be uppercase" and left it alone }
      wantUp := (PyCpUpper(cp) <> cp) or (PyCpUpperStr(cp) <> '')
    else if mode = 4 then
    begin
      if not prevAlnum then wantTitle := True;
      { a character is "in a word" when it has a case mapping either way or is
        an ASCII digit — CPython's title() rule, near enough for this block }
      prevAlnum := (PyCpUpper(cp) <> cp) or (PyCpLower(cp) <> cp) or
                   ((cp >= 48) and (cp <= 57)) or (PyCpUpperStr(cp) <> '');
    end;
    { …and a swapcase of an already-uppercase character with a multi-character
      LOWER mapping }
    if (mode = 3) and (not wantUp) and (PyCpLowerStr(cp) <> '') then
    begin
      Result := Result + PyCpLowerStr(cp);
      first := False;
      Continue;
    end;
    if (mode = 1) and (PyCpLowerStr(cp) <> '') then
    begin
      Result := Result + PyCpLowerStr(cp);
      first := False;
      Continue;
    end;
    if (wantUp or wantTitle) and (PyCpUpperStr(cp) <> '') then
    begin
      if wantTitle then Result := Result + PyTitleFormOf(PyCpUpperStr(cp))
      else Result := Result + PyCpUpperStr(cp);
      first := False;
      Continue;
    end;
    if wantUp or wantTitle then mapped := PyCpUpper(cp)
    else if mode <> 0 then mapped := PyCpLower(cp);
    PyCpToUtf8(Result, mapped);
    first := False;
  end;
end;

function pystr_upper(const s: AnsiString): AnsiString;
begin
  Result := PyStrMapCase(s, 0);
end;

function TypeVar(const name: AnsiString): AnsiString;
begin
  { CPython prints a TypeVar as `~T` — matched exactly rather than approximated,
    because it costs one character and a program that logs the value would
    otherwise diverge for no reason. }
  Result := '~' + name;
end;

function pystr_lower(const s: AnsiString): AnsiString;
begin
  Result := PyStrMapCase(s, 1);
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

{ --- CHARACTER coordinates over a UTF-8 byte substrate ----------------------
  A NilPy `str` counts CODE POINTS; a Pascal AnsiString counts BYTES; both are
  the same block. So every NilPy-visible offset — len, indexing, find, slice —
  is a CHARACTER offset, and these three helpers are the ONLY place the two
  coordinate systems meet. Nothing else in pylib does UTF-8 arithmetic: the
  search, strip, split and justify routines all compose on top of pystr_slice /
  pystr_find / PyWindowStart, so converting those converts them too.

  A continuation byte is $80..$BF, so a code point is exactly one
  non-continuation byte plus whatever follows it — counting LEAD bytes is the
  whole algorithm and it needs no validation pass. Malformed input therefore
  degrades to "some character count" rather than raising, which is what the byte
  model did as well; a decoder that REJECTS is a separate decision and not this
  ticket's.

  ASCII takes the byte-identical fast path, so the overwhelmingly common string
  is exactly as fast and exactly as correct as before this change. Non-ASCII
  pays an O(n) walk per offset conversion, which makes a STEPPED slice over a
  non-ASCII string O(n*k). Correctness first: PXX_FLAG_ASCII (already stamped by
  PXXStrFromLit and PXXStrConcat) is the O(1) answer for the pystr_isascii scan,
  but reading the meta word of a block that may never have carried a header is a
  claim that has to be MEASURED, and a false positive there is a silent wrong
  answer — so the flag is deliberately a separate change.
  feature-nilpy-text-string-kind }

function PyStrCharLen(const s: AnsiString): Integer;
var i, n: Integer;
begin
  if pystr_isascii(s) then begin PyStrCharLen := Length(s); Exit; end;
  n := 0;
  for i := 1 to Length(s) do
    if (Ord(s[i]) and $C0) <> $80 then Inc(n);
  PyStrCharLen := n;
end;

{ 1-based BYTE index at which 0-based CHARACTER ci begins; Length(s)+1 for any
  ci at or past the end. That one-past-the-end answer is deliberate — every
  slice asks for its exclusive upper boundary this way. }
function PyStrByteOfChar(const s: AnsiString; ci: Integer): Integer;
var i, n, c: Integer;
begin
  n := Length(s);
  if ci <= 0 then begin PyStrByteOfChar := 1; Exit; end;
  if pystr_isascii(s) then
  begin
    if ci > n then PyStrByteOfChar := n + 1 else PyStrByteOfChar := ci + 1;
    Exit;
  end;
  c := 0;
  for i := 1 to n do
    if (Ord(s[i]) and $C0) <> $80 then
    begin
      if c = ci then begin PyStrByteOfChar := i; Exit; end;
      Inc(c);
    end;
  PyStrByteOfChar := n + 1;
end;

{ 0-based CHARACTER index of the character containing 1-based BYTE bi. }
function PyStrCharOfByte(const s: AnsiString; bi: Integer): Integer;
var i, c: Integer;
begin
  if pystr_isascii(s) then begin PyStrCharOfByte := bi - 1; Exit; end;
  c := 0;
  for i := 1 to bi - 1 do
    if (Ord(s[i]) and $C0) <> $80 then Inc(c);
  PyStrCharOfByte := c;
end;

function pystr_len(const s: AnsiString): Integer;
begin
  Result := PyStrCharLen(s);
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
var n, b, i, cp, extra: Integer;
begin
  { "one character" is now counted in CHARACTERS, so ord("€") is 8364 rather
    than a TypeError about a string of length 3. }
  n := PyStrCharLen(s);
  if n <> 1 then
  begin
    raise TypeError.Create('ord() expected a character, but string of length ' +
                           pystr_of(Int64(n)) + ' found');
  end;
  b := Ord(s[1]);
  if b < $80 then begin Result := b; Exit; end;
  { UTF-8: the lead byte says how many continuation bytes follow and carries the
    top bits of the code point; each continuation contributes six more. A byte
    that is not a lead byte cannot be decoded, so it answers as itself rather
    than raising — the same "degrade, do not reject" rule the offset helpers
    follow, and the byte model never raised here either. }
  if (b and $E0) = $C0 then begin cp := b and $1F; extra := 1; end
  else if (b and $F0) = $E0 then begin cp := b and $0F; extra := 2; end
  else if (b and $F8) = $F0 then begin cp := b and $07; extra := 3; end
  else begin Result := b; Exit; end;
  for i := 2 to 1 + extra do
  begin
    if i > Length(s) then begin Result := b; Exit; end;
    cp := (cp shl 6) or (Ord(s[i]) and $3F);
  end;
  Result := cp;
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
function pychr_s(n: Int64): AnsiString;
var k: Integer;
begin
  if (n < 0) or (n > $10FFFF) then
    raise ValueError.Create('chr() arg not in range(0x110000)');
  k := Integer(n);
  if k < $80 then Result := Chr(k)
  else if k < $800 then
  begin
    SetLength(Result, 2);
    Result[1] := Chr($C0 or ((k shr 6) and $1F));
    Result[2] := Chr($80 or (k and $3F));
  end
  else if k < $10000 then
  begin
    SetLength(Result, 3);
    Result[1] := Chr($E0 or ((k shr 12) and $0F));
    Result[2] := Chr($80 or ((k shr 6) and $3F));
    Result[3] := Chr($80 or (k and $3F));
  end
  else
  begin
    SetLength(Result, 4);
    Result[1] := Chr($F0 or ((k shr 18) and $07));
    Result[2] := Chr($80 or ((k shr 12) and $3F));
    Result[3] := Chr($80 or ((k shr 6) and $3F));
    Result[4] := Chr($80 or (k and $3F));
  end;
end;

function pystr_at(const s: AnsiString; i: Integer): Char;
var n: Integer;
begin
  { i is a CHARACTER offset now, so `s[i]` agrees with len(s), s.find(...) and
    slicing on one coordinate system. The Char RESULT is still the character's
    LEAD byte, which for a multi-byte character is not the character — widening
    it to tyUCS4Char is the other half of feature-nilpy-text-string-kind and is
    a frontend/IR change, not an offset one. Splitting there is what keeps this
    commit free of any silent regression: a non-ASCII subscript was already
    yielding a lone byte before it. }
  n := PyStrCharLen(s);
  if i < 0 then i := n + i;
  if (i < 0) or (i >= n) then
  begin
    raise IndexError.Create('string index out of range');
  end;
  Result := s[PyStrByteOfChar(s, i)];
end;

function pystr_charat(const s: AnsiString; i: Integer): AnsiString;
var n, b0, b1: Integer;
begin
  n := PyStrCharLen(s);
  if i < 0 then i := n + i;
  if (i < 0) or (i >= n) then
  begin
    raise IndexError.Create('string index out of range');
  end;
  if pystr_isascii(s) then begin Result := s[i + 1]; Exit; end;
  b0 := PyStrByteOfChar(s, i);
  b1 := PyStrByteOfChar(s, i + 1);
  Result := Copy(s, b0, b1 - b0);
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
    { i is a 1-based BYTE; Python answers a 0-based CHARACTER offset. UTF-8 is
      self-synchronising, so a byte-level match of a well-formed needle can only
      land on a character boundary and this map is exact. }
    if hit then begin Result := PyStrCharOfByte(s, i); Exit; end;
  end;
  Result := -1;
end;

function pystr_find_from(const s: AnsiString; const sub: AnsiString; start: Integer): Integer;
var tail: AnsiString; r, n, b: Integer;
begin
  { `start` is a CHARACTER offset. The tail begins on a character boundary, so
    the offset pystr_find reports inside it simply ADDS to start. }
  n := PyStrCharLen(s);
  if start < 0 then start := start + n;
  if start < 0 then start := 0;
  if start > n then begin Result := -1; Exit; end;
  b := PyStrByteOfChar(s, start);
  tail := Copy(s, b, Length(s) - b + 1);
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

function pystr_isnumeric(const s: AnsiString): Boolean;
{ For the ASCII range this is str.isdigit's answer; the two differ only on
  characters NilPy has no representation for anyway (Unicode fractions, Roman
  numerals and the like), and pxx strings are bytes. Kept as its own routine
  rather than aliased at the call site so the divergence has one place to be
  recorded — and fixed — when wide strings arrive.
  Empty string is False, as in CPython. }
begin
  pystr_isnumeric := pystr_isdigit(s);
end;

function pystr_istitle(const s: AnsiString): Boolean;
{ Titlecase: every run of letters starts with an uppercase and continues
  lowercase, and there is at least one letter. Non-letters separate runs, so
  "Hello, World" and "A1b"->False are the cases that pin it. CPython answers
  False for a string with no cased characters at all. }
var i: Integer; prevCased, seenCased: Boolean;
begin
  prevCased := False;
  seenCased := False;
  for i := 1 to Length(s) do
  begin
    if s[i] in ['A'..'Z'] then
    begin
      if prevCased then begin pystr_istitle := False; Exit; end;
      prevCased := True;
      seenCased := True;
    end
    else if s[i] in ['a'..'z'] then
    begin
      if not prevCased then begin pystr_istitle := False; Exit; end;
      seenCased := True;
    end
    else
      prevCased := False;
  end;
  pystr_istitle := seenCased;
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

function pystr_isascii(const s: AnsiString): Boolean;
var i: Integer; cached: Int64; found: Boolean;
begin
  { EMPTY is True here — CPython's rule, and the opposite of the sibling
    predicates above, so it is stated rather than inherited. }
  { ANSWER ONCE PER STRING, not once per call. PyStrCharLen and pystr_charat
    both open with this predicate, so a full scan here made `s[i]` O(n) and an
    indexing loop O(n^2) — measured at 2476x CPython for n=160k, and the reason
    a compiled language was losing to a bytecode interpreter
    (bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython).
    The block header carries the answer; PXXStrUnique forgets it whenever bytes
    are about to change, which is the one place they can. }
  cached := PXXStrAsciiCached(Pointer(s));
  if cached >= 0 then
  begin
    Result := (cached = 1);
    Exit;
  end;
  found := True;
  for i := 1 to Length(s) do
    if Ord(s[i]) > 127 then begin found := False; Break; end;
  PXXStrSetAscii(Pointer(s), found);
  Result := found;
  Exit;
end;
function pystr_maketrans(const frm: AnsiString; const t: AnsiString): TPyDict;
var d: TPyDict; i, n: Integer;
begin
  d := TPyDict.Create;
  n := Length(frm);
  { CPython raises when the two arguments differ in length; matching that keeps
    a silently truncated table from being built. }
  if n <> Length(t) then
    raise ValueError.Create(
      'the first two maketrans arguments must have equal length');
  for i := 1 to n do
    d.store(Ord(frm[i]), Ord(t[i]));
  Result := d;
end;

function pystr_translate(const s: AnsiString; t: TPyDict): AnsiString;
var i: Integer; k, v: Variant; tag: Int64;
begin
  Result := '';
  if t = nil then begin Result := s; Exit; end;
  for i := 1 to Length(s) do
  begin
    k := Ord(s[i]);
    if not pydictcontains(t, k) then
    begin
      Result := Result + s[i];        { absent: unchanged }
      Continue;
    end;
    v := t.fetch(k);
    tag := pyvartag(v);
    if tag = 0 then Continue;         { None: DELETE the character }
    if tag = 6 then                   { a string replacement, possibly >1 char }
      Result := Result + VariantToStr(v)   { not PyVarText — see pystr_startswith_any }
    else
      Result := Result + Chr(pyvar_to_int(v) and 255);
  end;
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

{ s.split(None, maxsplit): whitespace RUNS as the separator, at most maxsplit
  splits. Not expressible with pystr_split_sep_max — the separator is a run of
  any width, leading whitespace is skipped entirely rather than producing an
  empty first field, and the remainder keeps whatever whitespace is inside it.
  An all-whitespace remainder contributes no field at all, so
  "a  ".split(None, 1) is ["a"].
  bug-nilpy-split-with-an-explicit-none-separator-does-not-split }
function pystr_split_ws_max(const s: AnsiString; maxsplit: Integer): TPyList;
var i, n, st, done: Integer;
begin
  if maxsplit < 0 then begin Result := pystr_split_ws(s); Exit; end;
  Result := TPyList.Create;
  n := Length(s);
  i := 1;
  done := 0;
  while (i <= n) and (done < maxsplit) do
  begin
    while (i <= n) and PyIsSpaceCh(s[i]) do Inc(i);
    if i > n then Break;
    st := i;
    while (i <= n) and not PyIsSpaceCh(s[i]) do Inc(i);
    Result.append(Copy(s, st, i - st));
    Inc(done);
  end;
  while (i <= n) and PyIsSpaceCh(s[i]) do Inc(i);
  if i <= n then Result.append(Copy(s, i, n - i + 1));
end;

{ s.rsplit(None, maxsplit): the same, anchored at the RIGHT end —
  "a b  c d".rsplit(None, 1) is ["a b  c", "d"]. }
function pystr_rsplit_ws_max(const s: AnsiString; maxsplit: Integer): TPyList;
var i, n, en, done, k: Integer; parts: TPyList;
begin
  if maxsplit < 0 then begin Result := pystr_split_ws(s); Exit; end;
  n := Length(s);
  parts := TPyList.Create;
  i := n;
  done := 0;
  while (i >= 1) and (done < maxsplit) do
  begin
    while (i >= 1) and PyIsSpaceCh(s[i]) do Dec(i);
    if i < 1 then Break;
    en := i;
    while (i >= 1) and not PyIsSpaceCh(s[i]) do Dec(i);
    parts.append(Copy(s, i + 1, en - i));
    Inc(done);
  end;
  while (i >= 1) and PyIsSpaceCh(s[i]) do Dec(i);
  Result := TPyList.Create;
  if i >= 1 then Result.append(Copy(s, 1, i));
  for k := parts.count - 1 downto 0 do Result.append(parts.at(k));
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
  { "".count in CPython is one hit per CHARACTER boundary, so the empty needle
    answers the CHARACTER length plus one. The match loop below stays on bytes:
    it counts occurrences, and an occurrence count is coordinate-free. }
  if m = 0 then begin Result := PyStrCharLen(s) + 1; Exit; end;
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
  if m = 0 then begin Result := PyStrCharLen(s); Exit; end;   { CPython: "abc".rfind("") = 3 }
  i := n - m + 1;
  while i >= 1 do
  begin
    { scan by BYTE, answer in CHARACTERS — see pystr_find }
    if PyStrMatchAt(s, i, sub) then begin Result := PyStrCharOfByte(s, i); Exit; end;
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
  if Result >= 0 then Result := Result + PyWindowStart(PyStrCharLen(s), a);
end;

function pystr_index_range(const s, sub: AnsiString; a, b: Integer): Integer;
begin
  Result := pystr_find_range(s, sub, a, b);
  if Result < 0 then raise ValueError.Create('substring not found');
end;

function pystr_rfind_from(const s, sub: AnsiString; a: Integer): Integer;
begin
  Result := pystr_rfind(pystr_slice(s, a, PY_SLICE_OMIT), sub);
  if Result >= 0 then Result := Result + PyWindowStart(PyStrCharLen(s), a);
end;

function pystr_rfind_range(const s, sub: AnsiString; a, b: Integer): Integer;
begin
  Result := pystr_rfind(pystr_slice(s, a, b), sub);
  if Result >= 0 then Result := Result + PyWindowStart(PyStrCharLen(s), a);
end;

function pystr_startswith_any(const s: AnsiString; const v: Variant): Boolean;
var p: PPyVarRec; o: TObject; k: Integer; e: Variant;
begin
  Result := False;
  p := PPyVarRec(@v);
  if (p^.VType = 7) and (p^.Payload <> 0) then
  begin
    o := TObject(Pointer(NativeInt(p^.Payload)));
    if o is TPyList then
    begin
      for k := 0 to TPyList(o).count - 1 do
      begin
        e := TPyList(o).at(k);
        if pystr_startswith(s, VariantToStr(e)) then
        begin
          Result := True;
          Exit;
        end;
      end;
      Exit;
    end;
    Exit;
  end;
  { not a sequence: an ordinary single prefix.
    VariantToStr, NOT PyVarText: PyVarText is defined ~3000 lines below and a
    forward use in this unit does not fail to compile — it links to a plausible
    wrong address (project_bodyless_procaddr_links_to_entry_minus_one). These
    three sites were added earlier the same night and passed their tests by
    luck; adding an unrelated forward declaration later made the compiler
    finally reject them, which is how the latent bug surfaced. }
  Result := pystr_startswith(s, VariantToStr(v));
end;

function pystr_endswith_any(const s: AnsiString; const v: Variant): Boolean;
var p: PPyVarRec; o: TObject; k: Integer; e: Variant;
begin
  Result := False;
  p := PPyVarRec(@v);
  if (p^.VType = 7) and (p^.Payload <> 0) then
  begin
    o := TObject(Pointer(NativeInt(p^.Payload)));
    if o is TPyList then
    begin
      for k := 0 to TPyList(o).count - 1 do
      begin
        e := TPyList(o).at(k);
        if pystr_endswith(s, VariantToStr(e)) then
        begin
          Result := True;
          Exit;
        end;
      end;
      Exit;
    end;
    Exit;
  end;
  Result := pystr_endswith(s, VariantToStr(v));   { see startswith's note }
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

{ CPython: the first cased character of each run of word characters is upper,
  the rest lower. Digits count as word characters but are not cased. }
function pystr_title(const s: AnsiString): AnsiString;
begin
  Result := PyStrMapCase(s, 4);
end;

function pystr_capitalize(const s: AnsiString): AnsiString;
begin
  Result := PyStrMapCase(s, 2);
end;

function pystr_swapcase(const s: AnsiString): AnsiString;
begin
  Result := PyStrMapCase(s, 3);
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
var n, nb, pad, i: Integer; f: Char;
begin
  { the WIDTH is in characters; the BUFFER is in bytes, and for a non-ASCII s
    those differ }
  n := PyStrCharLen(s);
  if (w <= n) or (Length(fill) = 0) then begin Result := s; Exit; end;
  f := fill[1];
  nb := Length(s);
  pad := Integer(w) - n;
  SetLength(Result, nb + pad);
  for i := 1 to nb do Result[i] := s[i];
  for i := nb + 1 to nb + pad do Result[i] := f;
end;

function pystr_ljust(const s: AnsiString; w: Int64): AnsiString;
begin
  Result := pystr_ljust_c(s, w, ' ');
end;

function pystr_center_c(const s: AnsiString; w: Int64; const fill: AnsiString): AnsiString;
var n, nb, i, left: Integer; f: Char;
begin
  n := PyStrCharLen(s);   { the width is in CHARACTERS }
  if (w <= n) or (Length(fill) = 0) then begin Result := s; Exit; end;
  f := fill[1];
  { CPython's exact rule (Objects/unicodeobject.c pad()):
      marg = width - len;  left = marg div 2 + (marg and width and 1)
    — so the odd extra pad lands on the LEFT only when both marg and width are
    odd. "ab".center(5) = "  ab ", "abc".center(6) = " abc  ". }
  left := (Integer(w) - n) div 2 + ((Integer(w) - n) and Integer(w) and 1);
  nb := Length(s);
  SetLength(Result, nb + (Integer(w) - n));
  for i := 1 to left do Result[i] := f;
  for i := 1 to nb do Result[left + i] := s[i];
  for i := left + nb + 1 to nb + (Integer(w) - n) do Result[i] := f;
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
var n, nb, i, pad, signLen: Integer;
begin
  n := PyStrCharLen(s);   { the width is in CHARACTERS }
  if w <= n then begin Result := s; Exit; end;
  nb := Length(s);
  signLen := 0;
  if (nb > 0) and ((s[1] = '-') or (s[1] = '+')) then signLen := 1;
  pad := Integer(w) - n;
  SetLength(Result, nb + pad);
  for i := 1 to signLen do Result[i] := s[i];
  for i := signLen + 1 to signLen + pad do Result[i] := '0';
  for i := signLen + 1 to nb do Result[i + pad] := s[i];
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

function pyvarobj_arg(const v: Variant): Pointer;
begin
  { tag 7 = VT_OBJECT; tag 0 = VT_EMPTY, i.e. None, which unwraps to nil }
  if (pyvartag(v) = 7) or (pyvartag(v) = 0) then
  begin
    Result := Pointer(PPyVarRec(@v)^.Payload);
    Exit;
  end;
  raise TypeError.Create('expected an object argument, got ' + pytype_name_v(v));
end;

function pyvar_callable_ptr(const v: Variant; const what: AnsiString): Pointer;
var nm: AnsiString;
begin
  if what = '' then nm := 'this argument' else nm := 'parameter ' + what;
  { A BOUND METHOD (VType 8 with a receiver) hands over the {code, recv} PAIR
    pointer, not the bare code address. Every consumer of a Pointer-typed
    callable parameter here dispatches through PyCallKey1 (sorted/min/max via
    its own call, map/filter through PyIterCallHook), and PyCallKey1's FIRST
    test is PXXObjIsBoundPair on exactly this pointer — so the pair is what it
    wants. This used to raise a TypeError saying the receiver could not travel,
    which was true of the bare address and not of the pair:
    `sorted(xs, key=obj.method)` was refused for a shape the dispatcher on the
    other side already handled (bug-nilpy-map-over-a-bound-method-segfaults). }
  Result := Pointer(PPyVarRec(@v)^.Payload);
  if Result = nil then
    raise TypeError.Create(nm + ' is not callable — the value '
      + 'is None (an import that did not resolve, or a name never assigned)');
end;

function pyvar_callable_ptr_opt(const v: Variant; const what: AnsiString): Pointer;
{ The same coercion for a Pointer parameter that DECLARES a default of nil —
  `sorted(l; key: Pointer = nil)` and its min/max siblings. There, nil already
  means "no key function", which is CPython's own definition of `key=None`, so
  passing None explicitly is legal and ordinary: it is what an optional key
  threaded through a helper (`def show(xs, key=None)`) hands over. The strict
  form above kept raising a TypeError on it, which was right for a parameter
  with no default (map/filter, where CPython also refuses None) and wrong here.
  Chosen by the CALLEE's declared default rather than by the parameter's name —
  the name is not what makes nil meaningful.
  Same signature as the strict form on purpose: the one call site picks between
  them and builds one argument chain.
  bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep }
begin
  if what = '' then ;      { same shape as its strict twin; nothing to report }
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
  { STORE ONLY, deliberately: pydynattr_get asks this to decide whether to
    FETCH from the store, so a wider answer here sends it to fetch a key that
    is not there. hasattr's wider question is pydynattr_hasattr below — the two
    look like one predicate and are not. }
  Result := (PyDynAttrStore <> nil) and
            (PyDynAttrStore.indexof(PyDynAttrKey(obj, name)) >= 0);
end;

{ hasattr(o, "name") for a statically CLASS-typed receiver: the dynamic store,
  then the declared members, then __getattr__ — the same four the getter
  resolves, in the getter's own order. The object twin of
  pydynattr_has_any_v, and the reason it exists is the same: asking the store
  alone reported False for something the very next read returns.
  bug-nilpy-getattr-dunder-not-supported }
type
  { A @property GETTER, reached by NAME at run time. The frontend name-mangles
    the accessors (`@property def double` becomes the method
    `__prop_get_double` and a real Pascal PROPERTY keeps the plain name), and
    the RTTI blob carries methods and fields — not properties. So a COMPUTED
    attribute name found nothing: `hasattr(w, nm)` answered False and
    `getattr(w, nm, d)` handed back the default, for a property the LITERAL
    form reads correctly, because the two forms take different routes by
    construction (frontend vs RTTI).
    bug-nilpy-a-computed-attribute-name-cannot-see-a-property }
  TPyPropV = function(recv: Pointer): Variant;
  TPyPropI = function(recv: Pointer): Int64;
  TPyPropD = function(recv: Pointer): Double;
  TPyPropS = function(recv: Pointer): AnsiString;
  TPyPropB = function(recv: Pointer): Boolean;

function PyPropertyGet(obj: Pointer; const name: AnsiString;
                       var found: Boolean): Variant;
{ The getter is CALLED, because a property has no storage of its own — its
  value is whatever the body computes now.

  Only the return kinds whose ABI is spelled out here are served; anything else
  answers "not found", which is exactly today's behaviour and never a wrong
  value read through the wrong convention (the failure PyDefUsedAsValue's note
  records). An unannotated NilPy getter returns a Variant, which is the common
  case by a wide margin. }
var mi: PMethInfo; fv: TPyPropV; fi_: TPyPropI; fd: TPyPropD;
    fs: TPyPropS; fb: TPyPropB;
begin
  found := False;
  Result := pynone;
  if obj = nil then Exit;
  mi := PyFindMethByName(GetInstanceRTTI(obj), '__prop_get_' + name);
  if (mi = nil) or (mi^.Code = nil) then Exit;
  case mi^.RetKind of
    22: begin fv := TPyPropV(mi^.Code); Result := fv(obj); found := True; end;
    13, 11, 1: begin fi_ := TPyPropI(mi^.Code); Result := pyvar_of_int(fi_(obj)); found := True; end;
    19: begin fd := TPyPropD(mi^.Code); Result := fd(obj); found := True; end;
    23: begin fs := TPyPropS(mi^.Code); Result := fs(obj); found := True; end;
    2:  begin fb := TPyPropB(mi^.Code); Result := pyvar_of_bool(fb(obj)); found := True; end;
  end;
end;

function pydynattr_hasattr(obj: Pointer; const name: AnsiString): Boolean;
var declFound: Boolean; dummy: Variant;
begin
  Result := pydynattr_has(obj, name);
  if Result then Exit;
  if obj = nil then Exit;
  dummy := PyDeclaredAttrGet(obj, name, declFound);
  if declFound then begin Result := True; Exit; end;
  { a @property, whose getter is name-mangled and whose PROPERTY the RTTI does
    not carry — see PyPropertyGet }
  dummy := PyPropertyGet(obj, name, declFound);
  if declFound then begin Result := True; Exit; end;
  if PyFindMethByName(GetInstanceRTTI(obj), name) <> nil then
  begin
    Result := True;
    Exit;
  end;
  Result := PyUserObjGetattrTry(TObject(obj), name, dummy);
end;

type
  PPyF8  = ^Int64;
  PPyF4  = ^Integer;
  PPyU4  = ^Cardinal;
  PPyF2  = ^SmallInt;
  PPyU2  = ^Word;
  PPyF1  = ^ShortInt;
  PPyU1  = ^Byte;
  PPyFB  = ^Boolean;
  PPyFC  = ^Char;
  PPyFS  = ^Single;
  PPyFD  = ^Double;
  PPyFP  = ^Pointer;
  PPyFN  = ^NativeInt;
  PPyFV  = ^Variant;

function PyEqAttrCI(const a, b: AnsiString): Boolean;
{ Case-insensitive name compare. pyeval has the same helper, but pyeval USES
  pylib and not the reverse, so it cannot be borrowed from there. }
var i, n: Integer; ca, cb: Char;
begin
  n := Length(a);
  if n <> Length(b) then begin PyEqAttrCI := False; Exit; end;
  for i := 1 to n do
  begin
    ca := a[i]; cb := b[i];
    if (ca >= 'A') and (ca <= 'Z') then ca := Chr(Ord(ca) + 32);
    if (cb >= 'A') and (cb <= 'Z') then cb := Chr(Ord(cb) + 32);
    if ca <> cb then begin PyEqAttrCI := False; Exit; end;
  end;
  PyEqAttrCI := True;
end;

function PyFindFieldCI(cls: PClassRTTI; const name: AnsiString): PFieldInfo;
{ The DECLARED field of that name, anywhere up the class hierarchy. Mirrors
  pyeval's PyFindMethCI, which walks the same blob for methods. }
var curr: PClassRTTI; flds: PFieldInfo; i: Integer;
begin
  PyFindFieldCI := nil;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.FieldCount > 0 then
    begin
      flds := curr^.FieldsPtr;
      for i := 0 to Integer(curr^.FieldCount) - 1 do
        if PyEqAttrCI(flds[i].NamePtr^, name) then
        begin
          PyFindFieldCI := @flds[i];
          Exit;
        end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

function PyFindMethByName(cls: PClassRTTI; const nm: AnsiString): PMethInfo;
{ The method of that name, anywhere up the class hierarchy — the method twin of
  PyFindFieldCI above. Case-SENSITIVE, as Python is. PyFindDunder further down
  is this same walk and now calls it. }
var curr: PClassRTTI; meths: PMethInfo; i: Integer;
begin
  PyFindMethByName := nil;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
    begin
      meths := curr^.MethsPtr;
      for i := 0 to Integer(curr^.MethCount) - 1 do
        if meths[i].NamePtr^ = nm then
        begin
          PyFindMethByName := @meths[i];
          Exit;
        end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

function PyBoxByKind(a: Pointer; k: Int64; var found: Boolean): Variant;
{ The value at `a`, read as the pxx TypeKind `k` and boxed into a Variant.

  Shared by every reflective read: an instance FIELD reached through the class
  RTTI (PyDeclaredAttrGet below) and a CLASS ATTRIBUTE reached through a class
  REFERENCE (PyClsAttrRefGet). One chain, because the two differ only in where
  the address comes from — and a second copy of it is how one kind ends up
  supported on one route and silently wrong on the other. }
begin
  found := True;
  if k = 23 then Result := PPyAnsiString(a)^          { AnsiString }
  else if k = 19 then Result := PPyFD(a)^             { Double }
  else if k = 18 then Result := PPyFS(a)^             { Single }
  else if k = 2 then Result := PPyFB(a)^              { Boolean }
  else if k = 3 then Result := PPyFC(a)^              { Char }
  else if (k = 13) or (k = 14) then Result := PPyF8(a)^        { Int64/QWord }
  else if (k = 1) or (k = 11) then Result := PPyF4(a)^         { Integer/LongInt }
  else if k = 12 then Result := PPyU4(a)^                       { Cardinal }
  else if k = 9 then Result := PPyF2(a)^                        { SmallInt }
  else if k = 10 then Result := PPyU2(a)^                       { Word }
  else if k = 7 then Result := PPyF1(a)^                        { ShortInt }
  else if k = 8 then Result := PPyU1(a)^                        { Byte }
  else if (k = 15) or (k = 16) then Result := PPyFN(a)^         { NativeInt/UInt }
  else if k = 22 then Result := PPyFV(a)^                       { Variant: copy }
  else if k = 6 then Result := TObject(PPyFP(a)^)               { class instance }
  else
    { a kind with no Python value shape yet (a record, a set, a frozen string,
      a static array). Answering with SOMETHING would be a wrong value; report
      it as not-found so the caller raises, which is at least loud. }
    found := False;
end;

function PyStoreByKind(a: Pointer; k: Int64; const v: Variant): Boolean;
{ The write twin of PyBoxByKind: unbox `v` into the slot at `a` as kind `k`.
  False for a kind with no Python value shape, so the caller raises rather than
  writing a plausible pattern over memory it does not understand. }
{ ASSIGNED out of the variant into a typed local, never cast — `Int64(v)` is a
  hard cast of the variant RECORD and stores its tag word, which wrote 1 where
  the program said 9. Same trap as PyClsAttrSlotOf's fetch. }
var iv: Int64; dv: Double; bv: Boolean; cv: Char;
begin
  Result := True;
  if k = 23 then PPyAnsiString(a)^ := pystr_of(v)
  else if k = 19 then begin dv := v; PPyFD(a)^ := dv; end
  else if k = 18 then begin dv := v; PPyFS(a)^ := dv; end
  else if k = 2 then begin bv := v; PPyFB(a)^ := bv; end
  else if k = 3 then begin cv := v; PPyFC(a)^ := cv; end
  else if (k = 13) or (k = 14) then begin iv := v; PPyF8(a)^ := iv; end
  else if (k = 1) or (k = 11) then begin iv := v; PPyF4(a)^ := iv; end
  else if k = 12 then begin iv := v; PPyU4(a)^ := iv; end
  else if k = 9 then begin iv := v; PPyF2(a)^ := iv; end
  else if k = 10 then begin iv := v; PPyU2(a)^ := iv; end
  else if k = 7 then begin iv := v; PPyF1(a)^ := iv; end
  else if k = 8 then begin iv := v; PPyU1(a)^ := iv; end
  else if (k = 15) or (k = 16) then begin iv := v; PPyFN(a)^ := iv; end
  else if k = 22 then PPyFV(a)^ := v
  else if k = 6 then PPyFP(a)^ := pyvarobj(v)
  else Result := False;
end;

function PyDeclaredAttrGet(obj: Pointer; const name: AnsiString;
                           var found: Boolean): Variant;
{ A field DECLARED by the class, read out of the instance through its RTTI and
  boxed by TypeKind.

  The dynamic-attribute store below only knows attributes created by ASSIGNMENT
  or setattr; a field the class declares is invisible to it. That was fine while
  every attribute read the frontend could not resolve statically was a dynamic
  one — but a chained receiver (`mk(3).v`) has no symbol for the frontend to key
  on, so it must ask at run time, and the answer has to include the declared
  fields or it is a false AttributeError for a field that plainly exists.

  `found` distinguishes "not a declared field" from "a declared field whose
  value is None" — a Result of None means the latter.
  bug-nilpy-a-bare-attribute-on-a-call-result-is-refused }
var cls: PClassRTTI; fi: PFieldInfo; a: Pointer; k: Int64;
begin
  found := False;
  if obj = nil then Exit;
  cls := GetInstanceRTTI(obj);
  if cls = nil then Exit;
  fi := PyFindFieldCI(cls, name);
  if fi = nil then Exit;
  a := Pointer(NativeInt(obj) + NativeInt(fi^.Offset));
  k := fi^.TypeKind;
  Result := PyBoxByKind(a, k, found);
end;

var
  { A CLASS ATTRIBUTE's one shared slot, keyed "<class RTTI blob>:<name>".
    Filled at class-definition time by pyclsattr_bind (pyparser emits one call
    per attribute), because the slot itself is a hidden GLOBAL whose name only
    the frontend knows — the RTTI blob carries methods and instance fields, and
    nothing in it could name this. The three compile-time access routes (`C.attr`,
    bare `attr` in a method, `inst.attr`) resolve that global directly and never
    consult this; it exists for the one route that has no class index at compile
    time, a class held as a VALUE.
    bug-nilpy-class-attribute-through-a-class-reference-reads-garbage }
  PyClsAttrAddrStore: TPyDict;   { key -> the hidden global's address, as Int64 }
  PyClsAttrKindStore: TPyDict;   { key -> Ord(TTypeKind) of that global }

procedure pyclsattr_bind(cls: Pointer; const name: AnsiString;
                         addr: Pointer; kind: Int64);
begin
  if PyClsAttrAddrStore = nil then
  begin
    PyClsAttrAddrStore := TPyDict.Create;
    PyClsAttrKindStore := TPyDict.Create;
  end;
  PyClsAttrAddrStore.store(PyDynAttrKey(cls, name), Int64(NativeInt(addr)));
  PyClsAttrKindStore.store(PyDynAttrKey(cls, name), kind);
end;

function PyClsAttrSlotOf(cls: Pointer; const name: AnsiString;
                         var kind: Int64): Pointer;
{ The bound slot for `name` on `cls` or any ancestor — the same parent walk
  PyFindFieldCI does for fields, so an inherited class attribute is reachable
  through a reference to the SUBCLASS. }
var curr: PClassRTTI; k: AnsiString; av, kv: Variant; ai: Int64;
begin
  Result := nil;
  kind := 0;
  if PyClsAttrAddrStore = nil then Exit;
  curr := PClassRTTI(cls);
  while curr <> nil do
  begin
    k := PyDynAttrKey(Pointer(curr), name);
    if PyClsAttrAddrStore.indexof(k) >= 0 then
    begin
      { ASSIGNED out of the variant, never `Int64(v)` — that spelling is a hard
        CAST of the variant RECORD and yields the address of the temporary, so
        both the slot address and the kind came back as stack pointers. }
      av := PyClsAttrAddrStore.fetch(k);
      kv := PyClsAttrKindStore.fetch(k);
      ai := av;
      kind := kv;
      Result := Pointer(NativeInt(ai));
      Exit;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

function PyClsAttrRefGet(const v: Variant; const name: AnsiString;
                         var found: Boolean): Variant;
{ `cls.attr` where `cls` holds a VT_CLASSREF variant. }
var a: Pointer; k: Int64;
begin
  found := False;
  a := PyClsAttrSlotOf(Pointer(NativeInt(PPyVarRec(@v)^.Payload)), name, k);
  if a = nil then Exit;
  Result := PyBoxByKind(a, k, found);
end;

function pyclsattr_inst_get(obj: Pointer; const name: AnsiString): Variant;
{ A class ATTRIBUTE read through an INSTANCE, resolved on the receiver's RUNTIME
  class. The compile-time route resolves it on the class that declares the
  METHOD, so `self.kind` inside a base method answered the BASE's value for a
  Derived instance -- the template-method pattern silently using the wrong
  constant. Walks ParentRTTI from the instance's own class, which is the same
  walk `Derived.kind` does and the reason that spelling was always right.
  bug-nilpy-self-class-attribute-in-an-inherited-method-reads-the-base-value }
var a: Pointer; k: Int64; found: Boolean;
begin
  Result := pynone;
  if obj = nil then Exit;
  a := PyClsAttrSlotOf(Pointer(GetInstanceRTTI(obj)), name, k);
  if a = nil then
  begin
    { __getattr__ answers here too — a class-attribute read is an attribute
      read. bug-nilpy-getattr-dunder-not-supported }
    if PyUserObjGetattr(TObject(obj), name, Result) then Exit;
    raise AttributeError.Create('''' + TObject(obj).ClassName +
      ''' object has no attribute ''' + name + '''');
  end;
  Result := PyBoxByKind(a, k, found);
  if not found then
    raise AttributeError.Create('class attribute ''' + name +
      ''' has a type this read cannot box');
end;

function PyClsRefName(const v: Variant): AnsiString;
{ The class's own name out of the blob a VT_CLASSREF points at — for the
  AttributeError message, which names the TYPE and not an instance. PyClassRefStr
  below builds CPython's `<class '__main__.A'>` from the same word, but it is
  declared far past the attribute routes that need this. }
var cls: PClassRTTI;
begin
  cls := PClassRTTI(Pointer(NativeInt(PPyVarRec(@v)^.Payload)));
  if cls = nil then Result := 'type' else Result := cls^.NamePtr^;
end;

function PyClsAttrRefSet(const v: Variant; const name: AnsiString;
                         const val: Variant): Boolean;
{ `cls.attr = x` through a class reference — writes the ONE shared slot, so the
  class name, every instance and every other reference see it. That is only true
  because a class used as a value has its attributes lowered to the shared slot
  (pyparser's PyClassUsedAsValue gate); under the copy-at-construction lowering
  an already-built instance would keep its own copy. }
var a: Pointer; k: Int64;
begin
  Result := False;
  a := PyClsAttrSlotOf(Pointer(NativeInt(PPyVarRec(@v)^.Payload)), name, k);
  if a = nil then Exit;
  Result := PyStoreByKind(a, k, val);
end;

function pydynattr_get(obj: Pointer; const name: AnsiString): Variant;
var declFound: Boolean; gaRes: Variant;
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
  begin
    { ...then the fields the class DECLARES. A dynamic attribute shadows one of
      the same name, which is the CPython order (instance __dict__ first).
      bug-nilpy-a-bare-attribute-on-a-call-result-is-refused }
    Result := PyDeclaredAttrGet(obj, name, declFound);
    if declFound then Exit;
    { ...then a @property, CALLED, since it has no storage of its own }
    Result := PyPropertyGet(obj, name, declFound);
    if declFound then Exit;
    { ...and LAST, the class's own __getattr__, which is defined precisely to
      answer for names that are not there. CPython's order is instance dict,
      class, then this. bug-nilpy-getattr-dunder-not-supported }
    if PyUserObjGetattr(TObject(obj), name, gaRes) then
    begin
      Result := gaRes;
      Exit;
    end;
    raise AttributeError.Create('''' + TObject(obj).ClassName +
      ''' object has no attribute ''' + name + '''');
  end;
end;

function PyVarTypeName(t: Int64): AnsiString; forward;

function pydynattr_get_v(const v: Variant; const name: AnsiString): Variant;
var obj: Pointer; tg: Int64; cn: AnsiString; declFound: Boolean; mi: PMethInfo;
    gaRes: Variant;
begin
  { Reached with a receiver that is a VARIANT — a for-loop element, `d.get(k)`,
    a plain unannotated parameter — whose runtime tag is NOT known at compile
    time. Unlike pydynattr_get above, `pyvarobj(v)`'s raw payload is only a
    real object pointer when the tag says so (VT_OBJECT); for any other tag
    (str/int/float/bool) it is scalar bits reinterpreted as an address, and
    ClassName on that would dereference garbage. Check the tag first. }
  tg := pyvartag(v);
  { A CLASS held as a value (VT_CLASSREF) — its payload is an RTTI blob address,
    not an instance, so the object routes below would read at a field's offset
    INSIDE the blob and answer a plausible integer for what was stored as 7.
    Ask the class-attribute registry first and never fall through to them.
    bug-nilpy-class-attribute-through-a-class-reference-reads-garbage }
  if tg = 11 then
  begin
    Result := PyClsAttrRefGet(v, name, declFound);
    if declFound then Exit;
    { `cls.__name__` where cls is a class held in a VARIABLE. The compile-time
      route answers the static spelling (`MyErr.__name__`), and a class object
      reaching this one knows its name just as well — the AttributeError below
      was already printing it. AFTER the attribute registry, because CPython
      lets a class that declares `__name__ = 'x'` shadow the real one.
      bug-n-pyexception-leaks-through-name-and-repr }
    if name = '__name__' then begin Result := PyClsRefName(v); Exit; end;
    raise AttributeError.Create('type object ''' + PyClsRefName(v)
      + ''' has no attribute ''' + name + '''');
  end;
  obj := pyvarobj(v);
  if pydynattr_has(obj, name) then
  begin
    Result := PyDynAttrStore.fetch(PyDynAttrKey(obj, name));
    Exit;
  end;
  if tg = 7 then
  begin
    { a declared field of the object the variant holds — same fallback the
      statically-typed getter above does, and the reason a chained receiver
      (`mk(3).v`) resolves at all.
      bug-nilpy-a-bare-attribute-on-a-call-result-is-refused }
    Result := PyDeclaredAttrGet(obj, name, declFound);
    if declFound then Exit;
    { ...then a @property, on the variant-receiver route as well: one concept,
      two getters, and the one not maintained with the other is where the bug
      lives (devdocs/dev/normalise-dont-special-case.md). }
    Result := PyPropertyGet(obj, name, declFound);
    if declFound then Exit;
    { ...and a METHOD read as a VALUE — `f = obj.scale`, `map(obj.scale, xs)`
      where the receiver is a variant. CALLING it already worked (the frontend
      resolves the call), so only the value form reached here, and it raised
      AttributeError for a method that plainly exists. The pair carries the
      receiver, which is the whole reason a bound method is not just a code
      address (bug-nilpy-map-over-a-bound-method-segfaults).

      The RTTI Code address is safe to bind because a method whose name is read
      as a value is normalised to the all-variant function ABI by the frontend
      (PyMethodUsedAsValue), which keys on exactly this spelling. }
    if obj <> nil then
    begin
      mi := PyFindMethByName(GetInstanceRTTI(obj), name);
      if (mi <> nil) and (mi^.Code <> nil) then
      begin
        { the star index rides the meth Flags word in SIGNATURE space (Self at
          0); the bridge wants it in the callee's OWN space, hence the -1 on
          top of the +1 the encoding adds to keep 0 meaning "none". }
        Result := pybound_new_star(mi^.Code, obj, mi^.RetKind <> 0,
                    Integer((mi^.Flags shr 8) and 255) - 2);
        Exit;
      end;
    end;
    { LAST, as above: the class's own __getattr__. Both getters need the arm —
      one concept, two receivers, and a fix on one of them only is the shape
      this repo keeps meeting. bug-nilpy-getattr-dunder-not-supported }
    if PyUserObjGetattr(TObject(obj), name, gaRes) then
    begin
      Result := gaRes;
      Exit;
    end;
    if obj = nil then cn := 'NoneType' else cn := TObject(obj).ClassName;
  end
  else
    cn := PyVarTypeName(tg);
  raise AttributeError.Create('''' + cn + ''' object has no attribute ''' + name + '''');
end;

function pydynattr_has_any_v(const v: Variant; const name: AnsiString): Boolean;
{ Does this value have this attribute AT ALL — the predicate `pydynattr_get_v`
  itself uses, and therefore the only honest partner for it.

  `pydynattr_has_v` below answers the DYNAMIC-attribute store (plus the
  class-attribute registry for a class held as a value). That is the right
  question for the literal `hasattr(o, "x")` path, which asks the compile-time
  field check first and only falls through to the store. A COMPUTED name has no
  compile-time half at all, so asking the store alone reported False for a
  method and for a declared field the very next getattr would return —
  `hasattr(self, "do_" + verb)` was False for a method that plainly exists.
  So this asks all four the way the getter resolves them, in the getter's own
  order.
  feature-nilpy-getattr-with-a-computed-attribute-name }
var obj: Pointer; tg: Int64; declFound: Boolean; dummy: Variant;
begin
  Result := pydynattr_has_v(v, name);
  if Result then Exit;
  tg := pyvartag(v);
  if tg <> 7 then Exit;                  { a class ref is fully answered above }
  obj := pyvarobj(v);
  if obj = nil then Exit;
  dummy := PyDeclaredAttrGet(obj, name, declFound);
  if declFound then begin Result := True; Exit; end;
  { a @property — its getter is name-mangled and the RTTI carries no property
    table, so neither of the two questions above can see it. THIS is the
    predicate a computed name reaches (PyMakeDynAttrByExpr), which is why the
    literal form saw the property and `hasattr(w, nm)` did not.
    bug-nilpy-a-computed-attribute-name-cannot-see-a-property }
  dummy := PyPropertyGet(obj, name, declFound);
  if declFound then begin Result := True; Exit; end;
  Result := PyFindMethByName(GetInstanceRTTI(obj), name) <> nil;
  if Result then Exit;
  { __getattr__ last, in the getter's own order — this predicate's whole
    contract is to answer what pydynattr_get_v resolves.
    bug-nilpy-getattr-dunder-not-supported }
  Result := PyUserObjGetattrTry(TObject(obj), name, dummy);
end;

function pydynattr_has_v(const v: Variant; const name: AnsiString): Boolean;
{ hasattr's twin of pydynattr_get_v: a CLASS held as a value keeps its
  attributes in the bind registry, not in the per-object dynamic store the
  unwrapped-pointer form asks — `hasattr(cls, "name")` answered False for an
  attribute the very next line read fine.
  bug-nilpy-class-attribute-through-a-class-reference-reads-garbage }
var k: Int64;
begin
  if pyvartag(v) = 11 then
    { `__name__` must answer here too, or hasattr(cls, '__name__') says False
      about something the read above returns — the exact split this routine
      exists to close. }
    Result := (name = '__name__') or
              (PyClsAttrSlotOf(Pointer(NativeInt(PPyVarRec(@v)^.Payload)), name, k) <> nil)
  else
    Result := pydynattr_has(pyvarobj(v), name);
end;

procedure pydynattr_set_v(const v: Variant; const name: AnsiString;
                          const val: Variant);
{ The write twin of pydynattr_get_v, for a receiver whose runtime tag decides
  what it is. Only a CLASS REFERENCE needs telling apart here: its payload is an
  RTTI blob, so the dynamic store below would key the write on the blob's
  address and the value would then be invisible to the class, to its instances
  and to every other reference — which is what `c.num = 9` did.
  bug-nilpy-class-attribute-through-a-class-reference-reads-garbage }
begin
  if pyvartag(v) = 11 then
  begin
    if PyClsAttrRefSet(v, name, val) then Exit;
    raise AttributeError.Create('type object ''' + PyClsRefName(v)
      + ''' has no attribute ''' + name + '''');
  end;
  pydynattr_set(pyvarobj(v), name, val);
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
  else if o is TPyBytes then
  begin
    if TPyBytes(o).FIsByteArray then Result := 'bytearray' else Result := 'bytes';
  end
  { one class, eight cursor kinds — `type(map(f, xs)).__name__` is 'map' and
    `type(reversed(xs)).__name__` is 'list_reverseiterator', so the NAME comes
    from the kind, not from ClassName (which would answer 'TPyIter'). }
  else if o is TPyIter then Result := pyiter_typename(TPyIter(o))
  else if o is TPyRange then Result := 'range'
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

{ True iff v holds a FLOAT (VT_DOUBLE, tag 3) — the twin of pyvar_is_strtag,
  and used the same way: the runtime method dispatcher widens its objtag guard
  by this and grows a float arm, so `for v in [2.0, 0.1]: v.hex()` reaches
  pyfloat_hex instead of raising AttributeError. Deliberately tag 3 ALONE and
  not "any number": an int receiver's is_integer/as_integer_ratio/conjugate
  answer INT-flavoured values in CPython ((3, 1), 3 — not 3.0), so routing an
  int through the float arm would be a wrong answer rather than a missing one.
  bug-nilpy-float-methods-are-invisible-to-the-runtime-dispatcher }
function pyvar_is_floattag(const v: Variant): Boolean;
begin
  Result := pyvartag(v) = 3;
end;

{ True iff v holds an INT (VT_INT / VT_INT64). Its partner: the three methods
  int and float SHARE — is_integer, conjugate, as_integer_ratio — pick their
  implementation between the two at RUN time, because only the tag says which
  the variant holds. Bools are excluded on purpose (VT_BOOL is its own tag);
  CPython does answer True.is_integer(), but a bool receiver is not what any of
  this was filed for and guessing at it here would be inventing behaviour. }
function pyvar_is_inttag(const v: Variant): Boolean;
begin
  Result := pyvartag(v) in [1, 2];
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

{ Forward: the arity-2 dunder dispatcher, declared far below. A variant-held
  user object needs it HERE, where the receiver has no static class. }
function PyUserArithCall1(selfObj, otherObj: TObject; const otherV: Variant;
                          const dunder: AnsiString; var res: Variant): Boolean; forward;

function pyvar_getitem(const v: Variant; const key: Variant): Variant;
var o: TObject; ki: Int64; tg: Int64; uv: Variant; nilo: TObject;
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
  nilo := nil;                       { the dispatcher's unused `other` operand }
  tg := pyvartag(v);
  if (tg = 6) or (tg = 5) then
  begin
    ki := PPyVarRec(@key)^.Payload;
    { pystr_charat, NOT pystr_at: both apply Python's negative-index rule and
      raise IndexError out of range, but pystr_at returns a Char — the
      character's LEAD BYTE — so `s[i]` on an unannotated parameter handed back
      one byte of a multi-byte character and printed as mojibake. The typed
      `s: str` path has used pystr_charat since text strings landed; this was
      the variant arm of the same question left behind.
      bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
    Result := pystr_charat(pystr_of(v), ki);
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
  else if o is TPyRange then
    { r[i] on a range held in a variant — arithmetic, not a lookup }
    Result := pyvar_of_int(pyrange_at(TPyRange(o), PPyVarRec(@key)^.Payload))
  else if o is TPyBytes then
  begin
    { bytes/bytearray index -> the integer byte value. Missing this case made
      `b[i]` on a VARIANT holding bytes (e.g. after `x = None; x = readline()`)
      raise 'not subscriptable' even though len(x) worked. }
    ki := PPyVarRec(@key)^.Payload;
    if ki < 0 then ki := ki + TPyBytes(o).count;
    Result := pyvar_of_int(TPyBytes(o).at(ki));
  end
  { A USER class arriving as a bare variant handle. A statically-typed receiver
    dispatches __getitem__ in the frontend; this one has no static class, so
    `xs[0][3]` over a list of objects raised "not subscriptable" for a class
    that plainly declares the member. The arity-2 dispatcher already covers
    every RetKind the frontend emits, and a class without __getitem__ answers
    False and keeps the TypeError.
    bug-nilpy-a-chained-subscript-does-not-see-getitem }
  else if PyUserArithCall1(o, nilo, key, '__getitem__', uv) then
    Result := uv
  else
    raise TypeError.Create('object is not subscriptable');
end;

{ `del v[k]` where v is a VARIANT — the runtime twin of pyvar_getitem, and for
  the same reason: an unannotated dict/list PARAMETER is a variant, so a helper
  that removes a key from a dict handed to it (`def drop(d, k): del d[k]`, a
  recursion guard's `del seen[node]`) could not be written at all. The frontend
  refused it at compile time, with a message that listed the very form being
  used, because the del lowering dispatched on the receiver's STATIC type.

  Returns a Variant so the frontend can drop it in place of the pyvar_getitem
  call the read already lowered to — the del statement rewrites that node's
  proc, exactly as it does for TPyList.at and TPyDict.fetch.
  bug-nilpy-del-on-a-variant-receiver-is-refused }
{ str()/print() of a USER CLASS INSTANCE that carries no frontend rendering of
  its own — the arm that used to fall through to the integer path and print the
  HANDLE (`134298980057`) where CPython prints `<__main__.N object at 0x...>`,
  and printed a class-typed None as `0`.

  nil FIRST: a method with `return self` on one path and `return None` on
  another has a CLASS return type, so its None is a nil handle. `is None`
  already answers True for it; only the rendering was wrong.
  bug-nilpy-str-of-a-plain-instance-prints-the-handle-and-a-class-typed-none-prints-zero }
function pyobj_str_of(o: TObject): AnsiString;
var v: Variant;
begin
  if o = nil then begin Result := 'None'; Exit; end;
  { boxed INLINE with a retain, for the reasons spelled out on repr(TObject):
    PyObjAsVar is a forward use from here, and the local `v` releases its
    object-tagged slot on scope exit. }
  PPyVarRec(@v)^.VType := 7;
  PPyVarRec(@v)^.Payload := Int64(NativeInt(Pointer(o)));
  PXXObjRetain(Pointer(o));
  Result := pyvar_print_of(v);
end;

function pyvar_delitem(const v: Variant; const key: Variant): Variant;
var o: TObject; ki: Int64;
begin
  Result := pyvar_of_int(0);
  if pyvartag(v) <> 7 then
    raise TypeError.Create('object does not support item deletion');
  o := TObject(pyvarobj(v));
  if o is TPyDict then
  begin
    TPyDict(o).remove(key);
    Exit;
  end;
  if o is TPyList then
  begin
    ki := PPyVarRec(@key)^.Payload;
    pylist_del_at(TPyList(o), ki);
    Exit;
  end;
  { a USER class arriving as a bare variant handle keeps the RUNTIME TypeError.
    A statically-typed receiver already dispatches __delitem__ in the frontend,
    and routing this one through the RTTI dunder table needs a two-argument
    dispatcher that does not exist yet — loud beats a silent no-op. }
  raise TypeError.Create('object does not support item deletion');
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

function iter(l: TPyList): TPyIter;
begin
  Result := pyiter_of_list(l);
end;

function iter(it: TPyIter): TPyIter; overload;
begin
  { iter() of an iterator is that iterator — CPython's rule, and what lets a
    consumption site call iter() unconditionally on whatever it was handed }
  Result := it;
end;

function iter(d: TPyDict): TPyIter; overload;
begin
  if d = nil then Result := pyiter_of_list(TPyList.Create)
  else Result := pyiter_of_list(d.keylist);
end;

function iter(b: TPyBytes): TPyIter; overload;
begin
  Result := pyiter_of_list(list(b));
end;

function iter(const s: AnsiString): TPyIter; overload;
begin
  Result := pyiter_of_str(s);
end;

function iter(const v: Variant): TPyIter; overload;
begin
  Result := pyiter_v(v);
end;

function next(it: TPyIter): Variant; overload;
begin
  Result := pyiter_next(it);
end;

function next(it: TPyIter; const dflt: Variant): Variant; overload;
begin
  Result := pyiter_next_or(it, dflt);
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
  { CHARACTERS, as Python counts them — see PyStrCharLen. This is the overload
    `len(s)` actually resolves to; pystr_len is the method-call spelling of the
    same question, and BOTH had to move or one of them stayed byte-flavoured. }
  Result := PyStrCharLen(s);
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

function TPyList.setupdate(other: TPyList): Variant;
var i: Integer;
begin
  Result := pynone;                  { Python's set.update returns None }
  if (Self = nil) or (other = nil) then Exit;
  for i := 0 to other.count - 1 do
    Self.add(other.at(i));
end;

function TPyList.setintersect(other: TPyList): Variant;
var i: Integer; snap: TPyList; v: Variant;
begin
  Result := pynone;
  if (Self = nil) or (other = nil) then Exit;
  { snapshot Self's elements first: removing renumbers them, so a straight
    index walk over Self would skip the element after every removal }
  snap := TPyList.Create;
  for i := 0 to Self.count - 1 do snap.append(Self.at(i));
  for i := 0 to snap.count - 1 do
  begin
    v := snap.at(i);
    if not pycontains(other, v) then Self.remove(v);
  end;
end;

function TPyList.setsymdiff(other: TPyList): Variant;
var i: Integer; snapSelf, snapOther: TPyList; v: Variant;
begin
  Result := pynone;
  if (Self = nil) or (other = nil) then Exit;
  { BOTH sides are snapshotted: the common elements leave Self and the
    other-only ones join it, and each decision must be made against the sets as
    they were, not as they are becoming. `s ^= s` must end EMPTY, which is the
    case that catches doing it in one pass. }
  snapSelf := TPyList.Create;
  for i := 0 to Self.count - 1 do snapSelf.append(Self.at(i));
  snapOther := TPyList.Create;
  for i := 0 to other.count - 1 do snapOther.append(other.at(i));
  for i := 0 to snapSelf.count - 1 do
  begin
    v := snapSelf.at(i);
    if pycontains(snapOther, v) then Self.remove(v);
  end;
  for i := 0 to snapOther.count - 1 do
  begin
    v := snapOther.at(i);
    if not pycontains(snapSelf, v) then Self.add(v);
  end;
end;

function TPyList.setdiff(other: TPyList): Variant;
var i: Integer; snapOther: TPyList; v: Variant;
begin
  Result := pynone;
  if (Self = nil) or (other = nil) then Exit;
  { snapshot the OTHER side, so `s -= s` (same object) does not shrink the list
    it is iterating }
  snapOther := TPyList.Create;
  for i := 0 to other.count - 1 do snapOther.append(other.at(i));
  for i := 0 to snapOther.count - 1 do
  begin
    v := snapOther.at(i);
    if pycontains(Self, v) then Self.remove(v);
  end;
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

{ Both pops CLEAR the slot they vacate. Lowering FLen over a slot that still
  holds a reference leaves an alias nothing counts, and the next append writes
  exactly there — PyVarSlotSet releases whatever the slot held on its way in.
  For pop() that was merely a leak the next append happened to collect; for
  pop_at() it was CORRUPTION, because the raw shift below moved a LIVE element
  into the list while leaving its unbacked duplicate at the tail. The next
  append then released a live element: `[A, B]` -> `pop(0)` -> `append(x)` gave
  `[(), x]`, and uforth's CS-ROLL turned a control-flow entry into an empty
  tuple mid-compile (bug-nilpy-list-pop-index-destroys-a-surviving-tuple-element). }
function TPyList.pop: Variant;
begin
  Result := at(FLen - 1);                  { the caller's +1 }
  PyVarSlotClear(PPyVarRec(NativeInt(FItems) + (FLen - 1) * 16));
  FLen := FLen - 1;
end;

function TPyList.pop(i: Integer): Variant;
begin
  Result := pop_at(i);
end;

function TPyList.pop_at(i: Integer): Variant;
var
  k: Integer;
begin
  i := PyListFix(Self, i);
  Result := at(i);                         { the caller's +1 }
  { A COUNTED shift, the same idiom pylist_del_slice uses: put/at retain the
    value into its new slot and release the old occupant, so no slot is ever
    an alias the refcount does not know about. The raw VType/Payload copy this
    replaced was the whole bug. }
  for k := i to FLen - 2 do
    put(k, at(k + 1));
  PyVarSlotClear(PPyVarRec(NativeInt(FItems) + (FLen - 1) * 16));
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
        swapped := pyvar_lt(Self.at(j), Self.at(j - 1));
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

function TPyList.symmetric_difference(other: TPyList): TPyList;
begin
  Result := pyset_xor(Self, other);
end;

function TPyList.isdisjoint(other: TPyList): Boolean;
var r: TPyList;
begin
  { "no element in common" — the intersection being empty. Python accepts ANY
    iterable here, and a list IS the set representation, so no kind check. }
  r := pyset_and(Self, other);
  Result := (r = nil) or (r.count = 0);
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
{ `a.__eq__(b)` on a USER class instance reached only as a boxed handle. Same
  runtime dunder lookup PyUserObjStr uses for __repr__/__str__; implemented
  beside it and forward-declared here because PyVarEq is the only caller and
  sits far above it. Answers False in `handled` when the class defines no usable
  __eq__, so PyVarEq keeps its identity result.
  bug-nilpy-container-membership-ignores-the-eq-dunder }
function PyUserObjEq(pobj, qobj: TObject; const qv: Variant;
                     var res: Boolean): Boolean; forward;
{ `a.__hash__()` on the same boxed handle — the consistency partner of the
  above. False when the class defines no usable __hash__, leaving the caller's
  identity hash. }
function PyUserObjHash(o: TObject; var h: NativeUInt): Boolean; forward;
{ The NO-ARGUMENT dunder call — `__next__`, `__iter__`. Defined beside the other
  runtime dunder dispatchers (PyUserObjBoolDunder and friends); forward-declared
  here because the cursor machinery above calls it.
  bug-nilpy-iterator-protocol-on-a-user-class }
function PyUserObjNoArgDunder(o: TObject; const dunder: AnsiString;
                              var res: Variant): Boolean; forward;
function PyUserObjHasDunder(o: TObject; const dunder: AnsiString): Boolean; forward;
{ Is this object UNHASHABLE the way CPython means it — its class defines
  __eq__ and does NOT define __hash__? Defining __eq__ says "compare these by
  content, not identity"; using the same class as a dict key asks for identity.
  The two requests contradict, and CPython refuses rather than resolve the
  contradiction silently (it sets __hash__ to None on purpose).

  NilPy honoured NEITHER: it stored under the identity hash, so a
  content-equal lookup missed — the entry went in and never came out, with no
  diagnostic. This is the probe that turns that into CPython's TypeError.

  Keys on __eq__ being PRESENT, so it cannot reach a class with no __eq__ at
  all: those are identity-hashable in both implementations, and are the real
  use case (an imported Pascal/C object held by pointer as a key).
  bug-n-object-dict-key-with-eq-and-no-hash-silently-loses-the-entry }
function PyUserObjUnhashable(o: TObject): Boolean; forward;
{ `a > b` for two user objects, via __gt__ or the reflected __lt__ — what
  .sort()/sorted() need. False when neither exists, leaving pyvar_gt's existing
  numeric path (and its TypeError) alone.
  bug-nilpy-list-sort-ignores-lt-dunder-on-objects }
function PyUserObjGt(pobj, qobj: TObject; const qv: Variant;
                     var res: Boolean): Boolean; forward;
{ `a < b` for two user objects: __lt__, or the reflected __gt__. }
function PyUserObjLt(pobj, qobj: TObject; const qv: Variant;
                     var res: Boolean): Boolean; forward;
{ `divmod(a, b)` via __divmod__ / the reflected __rdivmod__, answering the
  2-tuple. False when neither exists. }
function PyUserObjDivmod(pobj, qobj: TObject; const pv, qv: Variant;
                         var res: TObject): Boolean; forward;
{ `a <op> b` for two user objects via an arithmetic dunder and its reflected
  form — what a VARIANT-typed operand needs, since the compile-time dispatch
  keys on a static class the operand does not have.
  bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
function PyUserObjArith(pobj, qobj: TObject; const pv, qv: Variant;
                        const dunder, rdunder: AnsiString;
                        var res: Variant): Boolean; forward;

function PyVarEq(p, q: PPyVarRec): Boolean;
var
  k: Integer;
  la, lb: Int64;
  a, b: PChar;
  pl, ql: TObject;
  userEq: Boolean;
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
      { pylist_eq, not a second positional walk. This arm used to carry its own
        copy of that loop, so when pylist_eq learned that a SET compares by
        MEMBERSHIP the operator agreed and every container route did not:
        `{1, 2} == {2, 1}` was True while `[{1, 2}] == [{2, 1}]` and
        `{1, 2} in [{2, 1}]` stayed False. One comparison, one place — the
        sibling-of-a-double-case rule
        (devdocs/dev/normalise-dont-special-case.md). }
      Result := pylist_eq(TPyList(pl), TPyList(ql))
    else if (pl is TPyDict) and (ql is TPyDict) then
      { …and two DICTS by contents, for the same reason. This is what makes a
        NESTED dict compare correctly: the outer pydict_eq reaches its values
        through PyVarEq, so without this arm `{"n": {"m": 1}} == {"n": {"m": 1}}`
        was False while the list-valued `{"n": [1, 2]}` form was already True.
        Mutually recursive with pydict_eq, which is why that one is
        forward-declared. }
      Result := pydict_eq(TPyDict(pl), TPyDict(ql))
    else if (pl is TPyBytes) and (ql is TPyBytes) then
      { …and two BYTES by contents — the third of this unit's containers, and
        the arm that was missing while list and dict had theirs. `b"ab" ==
        b"ab"` answered False (identity) where CPython says True, and
        `b"ab" in [b"ab"]` with it. pybytes_eq already existed; only this line
        was absent. The sibling-of-a-double-case check
        (devdocs/dev/normalise-dont-special-case.md) found it the moment `==`
        started routing here. }
      Result := pybytes_eq(TPyBytes(pl), TPyBytes(ql))
    else
      { Neither is one of this unit's containers, so they may be USER class
        instances with an `__eq__`. Identity above already settled the equal
        case; without this arm an equal-but-DISTINCT pair reported False, so
        `H(3) in [H(1), H(3)]` was False while the bare `H(3) == H(3)` was True
        — the operator path dispatches at COMPILE time on the static class, and
        a container element has no static class for that to key on.

        Every value comparison in this unit funnels through PyVarEq, so fixing
        it here is what also fixes .index(), .count(), .remove() and `not in`.
        bug-nilpy-container-membership-ignores-the-eq-dunder }
      if PyUserObjEq(pl, ql, PVariant(q)^, userEq) then Result := userEq;
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

{ A `TRY` for `==` / `!=` on two variant SLOTS, taken by address and answering
  in PXXPromoVarCmpTry's exact protocol: **0 = not handled**, 1 = False,
  2 = True. It is one more link in that same chain in ir.inc, and deliberately
  nothing more.

  It handles ONE case: an OBJECT (tag 7) on either side, which it answers with
  PyVarEq — the only equality in this unit that reaches a user `__eq__` (via
  PyUserObjEq) and compares lists/dicts/tuples by CONTENT. Everything else
  returns 0 and the caller's own comparison runs completely unchanged
  (bug-nilpy-eq-dunder-skipped-when-either-operand-is-a-variant).

  "Answer nothing you were not asked" is the whole design, and it was learned
  by breaking three things that were not asked. Earlier cuts REPLACED the
  fallback, on the assumption that PyVarEq covers what it covered. It does not:
  it wants equal tags outside the numeric family (a CHAR against a
  one-character STRING went False), and the fallback is not even a routine — on
  x86-64 `IR_VAR_BINOP` is INLINE-EMITTED code with its own None arm, so
  `0 == None` became True when the call went to builtinheap's PXXVarBinOp
  instead. A try that declines cannot regress a case it never sees.

  The PROMOTABLE-INT family never reaches here — PXXPromoVarCmpTry runs first
  and answers before this. }
{ `raise <variant>` — CPython raises `TypeError: exceptions must derive from
  BaseException` for anything that is not an exception object, and pxx used to
  SEGFAULT on the whole shape (the variant's 16-byte slot reached IR_RAISE where
  an instance POINTER belongs, so it jumped through the tag word). The frontend
  unboxes a variant operand to a pointer; this is the check in front of that, so
  a non-object tag becomes the diagnostic instead of a wild jump. The value
  passes through so the two compose in one expression.
  bug-nilpy-raising-a-variant-segfaults }
function pyraise_check(const v: Variant): Variant;
var o: TObject;
begin
  o := nil;
  if pyvartag(v) = 7 then o := TObject(pyvarobj(v));
  { `is Exception`, not merely "is an object": a LIST is tag 7 too, and
    `raise [1]` must be the TypeError CPython gives, not a raised TPyList that
    an `except Exception:` arm then catches as if it were one. }
  if (o = nil) or (not (o is Exception)) then
    raise TypeError.Create('exceptions must derive from BaseException');
  Result := v;
end;

function pyvar_eqv(a, b: Pointer; neq: Int64): Int64;
var eq: Boolean;
begin
  if (PPyVarRec(a)^.VType <> 7) and (PPyVarRec(b)^.VType <> 7) then
  begin
    Result := 0;                      { not ours — the caller's own compare stands }
    Exit;
  end;
  eq := PyVarEq(PPyVarRec(a), PPyVarRec(b));
  if neq <> 0 then eq := not eq;
  if eq then Result := 2 else Result := 1;
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
{ The four set operators are DEFINED ONLY BETWEEN SETS. `-`, `&`, `|` and `^`
  over lists are a TypeError in Python, and pxx computed an answer for them
  because a set and a list share the TPyList row — `[1] - [2]` returned
  `[1]`, which is set difference wearing a list's clothes.

  The FKind tag (decide-nilpy-set-as-a-distinct-type-or-a-list, since
  implemented) makes the question answerable at run time, which is exactly what
  that decision left behind as ordinary work. Checked HERE rather than in the
  frontend because the kinds are a RUNTIME property: `a - b` over two variants
  cannot know statically which rows it will be handed.

  A nil operand counts as a set: that is how an empty literal reaches here, and
  refusing it would break `s - set()`.
  bug-nilpy-same-kind-undefined-operators-still-compute }
procedure PySetRequireSets(a, b: TPyList; const op: AnsiString);
var ka, kb: AnsiString;
begin
  if ((a = nil) or (a.FKind = PYSEQ_SET)) and
     ((b = nil) or (b.FKind = PYSEQ_SET)) then Exit;
  if a = nil then ka := 'set' else ka := PySeqKindName(a.FKind);
  if b = nil then kb := 'set' else kb := PySeqKindName(b.FKind);
  raise TypeError.Create('unsupported operand type(s) for ' + op + ': '''
    + ka + ''' and ''' + kb + '''');
end;

function pyset_and(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  PySetRequireSets(a, b, '&');
  Result := TPyList.Create;
  Result.FKind := PYSEQ_SET;      { set & set is a SET, not a list }
  if (a = nil) or (b = nil) then Exit;
  for i := 0 to a.count - 1 do
    if pycontains(b, a.at(i)) then Result.add(a.at(i));
end;

function pyset_or(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  PySetRequireSets(a, b, '|');
  Result := TPyList.Create;
  Result.FKind := PYSEQ_SET;
  if a <> nil then
    for i := 0 to a.count - 1 do Result.add(a.at(i));
  if b <> nil then
    for i := 0 to b.count - 1 do Result.add(b.at(i));
end;

function pyset_sub(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  PySetRequireSets(a, b, '-');
  Result := TPyList.Create;
  Result.FKind := PYSEQ_SET;
  if a = nil then Exit;
  for i := 0 to a.count - 1 do
    if (b = nil) or not pycontains(b, a.at(i)) then Result.add(a.at(i));
end;

function pyset_xor(a: TPyList; b: TPyList): TPyList;
var i: Integer;
begin
  PySetRequireSets(a, b, '^');
  Result := TPyList.Create;
  Result.FKind := PYSEQ_SET;
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
    else if o is TPyList then Result := pycontains(TPyList(o), v)
    { a range answers membership in CONSTANT time — one modulo, no scan }
    else if o is TPyRange then Result := pyrange_contains(TPyRange(o), v)
    else if o is TPyIter then Result := pycontains(pyiter_drain(TPyIter(o)), v);
  end
  else if pyvartag(c) = 6 then
    Result := pystr_contains(pystr_of(c), pystr_of(v));
end;

function pyexc_msgstr(const v: Variant): AnsiString;
begin
  Result := pystr_of(v);
end;

procedure PyKeyError;
{ RAISE — see PyIndexError. The keyless form, for callers with no key to hand. }
begin
  raise KeyError.Create('key not found');
end;

procedure PyKeyError(const k: Variant); overload;
{ The same, naming the KEY — which is the entire content of a KeyError. The
  fixed text 'key not found' said nothing: every real "which key?" question had
  to be answered by adding a print.

  pyvar_repr, not pystr_of, and that is not a detail: CPython's KeyError is the
  one builtin exception whose str() is the REPR of its argument, so a missing
  string key reports 'nope' WITH the quotes. Using the repr here makes the
  message match CPython's for free, and keeps an int key unquoted the way
  CPython does. }
var e: KeyError; kargs: TPyList;
begin
  { …and the KEY ITSELF goes into `args`, not the repr'd message. CPython's
    KeyError('nope').args is ('nope',) — unquoted — while its str() is the
    quoted repr, so the two genuinely differ for this one exception and the
    derive-from-message default would hand back the quoted form.
    bug-nilpy-exception-args-attribute-missing }
  { The ctor reprs the message now, so the raw TEXT goes in; argsv is then
    overwritten with the raw VARIANT, so an int key's args is (42,) and not
    ('42',). }
  e := KeyError.CreateRendered(pyvar_repr(k));
  { argsv is TObject on the shared root (so an RTL exception has the slot too),
    so build the tuple in a typed local and store the upcast. }
  kargs := TPyList.Create;
  kargs.FKind := PYSEQ_TUPLE;
  kargs.append(k);
  e.argsv := kargs;
  raise e;
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
          PyUserObjUnhashable(TObject(Pointer(NativeInt(p^.Payload)))) then
    { A class with __eq__ and no __hash__ is UNHASHABLE. Refused HERE, at the
      one place a key is turned into a bucket, so the store and every lookup
      form (`d[k]`, `.get`, `in`, `.pop`) refuse alike — which is what CPython
      does. Hashing it by IDENTITY instead, as this used to, put the entry in a
      bucket no content-equal lookup would ever probe: data in, nothing out, no
      diagnostic.

      NOT repaired by synthesising a content hash. That reintroduces the same
      class of bug in a subtler form — mutate the object after insertion and
      its hash changes, so the entry silently vanishes from the dict. It is the
      trap CPython itself backed away from.
      bug-n-object-dict-key-with-eq-and-no-hash-silently-loses-the-entry }
    raise TypeError.Create('unhashable type: ''' +
      TObject(Pointer(NativeInt(p^.Payload))).ClassName + '''')
  else if (p^.VType = 7) and (p^.Payload <> 0) and
          PyUserObjHash(TObject(Pointer(NativeInt(p^.Payload))), h) then
  begin
    { a USER class's own __hash__. Required for consistency the moment PyVarEq
      started consulting __eq__: equal keys MUST hash equal, and two distinct
      but __eq__-equal objects hashed by their HANDLES land in different
      buckets, so `d[K(1)]` missed the key `K(1)` inserted. A class defining
      __eq__ and NOT __hash__ is UNHASHABLE in CPython (TypeError), so the only
      programs affected are the ones that define both — which is exactly the
      pair this reads.
      bug-nilpy-container-membership-ignores-the-eq-dunder }
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

function pyhash_v(const v: Variant): Int64;
{ Python's `hash(x)`.

  PyVarHashKey is already exactly this — the dict's own key hash, written to
  mirror PyVarEq arm for arm (ints by value across tags, strings by content,
  tuples by element, a user object through its __hash__). It simply was not
  reachable from the language, so a program could not ask what a value hashes
  to — which is part of why an ignored __hash__ dunder was hard to narrow.

  Answers a SIGNED Int64, as CPython does. The numbers are not CPython's and
  must never be asserted: CPython salts string hashing per process, so its own
  hash("ab") differs between two runs. What holds, and what a test may rely on,
  is the INVARIANT: equal values hash equal within one run.
  bug-n-hash-builtin-is-not-implemented }
begin
  pyhash_v := Int64(PyVarHashKey(PPyVarRec(@v)));
end;

{ `max(xs, default=D)` / `min(xs, default=D)` — CPython's empty-sequence guard.
  Two routines rather than an overload of max/min: a second Variant parameter is
  exactly the shape the two-argument NUMERIC overload already claims, and that
  mis-resolution is what made `min(xs, key=f)` compare a list against a function
  (PyMinMaxByKey) and `min(xs, key=None)` compare it against None
  (PyMinMaxNoneKey). Adding a third meaning to that one slot would be a fourth
  arm of a distinction the call site cannot make.
  bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep }
function pymax_default(const c: Variant; const d: Variant): Variant;
begin
  if pylen_v(c) = 0 then pymax_default := d else pymax_default := max(c);
end;

function pymin_default(const c: Variant; const d: Variant): Variant;
begin
  if pylen_v(c) = 0 then pymin_default := d else pymin_default := min(c);
end;

function pyid_v(const v: Variant): Int64;
begin
  pyid_v := PPyVarRec(@v)^.Payload;
end;

function pyascii_v(const v: Variant): AnsiString;
var r, hexd, acc: AnsiString; i, b: Integer;
begin
  r := pyvar_repr(v);
  hexd := '0123456789abcdef';
  acc := '';
  for i := 1 to Length(r) do
  begin
    b := Ord(r[i]);
    if b < 128 then
      acc := acc + r[i]
    else
      acc := acc + '\x' + hexd[(b div 16) + 1] + hexd[(b mod 16) + 1];
  end;
  pyascii_v := acc;
end;

function TPyDict.indexof(const k: Variant): Integer;
var
  i: Integer;
  q: PPyVarRec;
  mask, pos, hk: NativeUInt;
  idx: Integer;
begin
  Result := -1;
  q := PPyVarRec(@k);
  { Hash BEFORE the empty short-circuit. An unhashable key (a class with
    __eq__ and no __hash__) must be refused whatever the dict holds — CPython
    raises for `V(1) in {}` too — and returning "absent" for an empty dict was
    a right answer reached by a route that skipped the question, so the
    diagnostic appeared or not depending on FLen. One hash on an empty lookup
    is not a cost worth an inconsistency.
    bug-n-object-dict-key-with-eq-and-no-hash-silently-loses-the-entry }
  hk := PyVarHashKey(q);
  if FLen = 0 then Exit;
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
  pos := hk and mask;
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
    PyKeyError(k);
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
  if i < 0 then PyKeyError(k);
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
  if i < 0 then PyKeyError(k);
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

{ ORDERING REFUSAL — the one place that decides a pair cannot be ordered, and
  the one place that words it. CPython:

    '<' not supported between instances of 'NoneType' and 'int'

  The operand names are in SOURCE order, so every caller that implements `<` by
  swapping into a `>` primitive must check BEFORE it swaps — that is what
  pyvar_lt below exists for. bug-nilpy-comparing-none-with-a-number-answers-
  instead-of-raising. }
procedure PyOrdRefuse(const a: Variant; const b: Variant; const op: AnsiString);
begin
  raise TypeError.Create('''' + op + ''' not supported between instances of ''' +
    pytype_name_v(a) + ''' and ''' + pytype_name_v(b) + '''');
end;

{ None wears VT_EMPTY, but an object slot with a nil payload reads as NoneType
  too (pytype_name_v answers 'NoneType' for both), so the predicate takes both
  rather than leaving one spelling ordered as 0. }
function PyOrdIsNone(p: PPyVarRec): Boolean;
begin
  PyOrdIsNone := (p^.VType = 0) or ((p^.VType = 7) and (p^.Payload = 0));
end;

{ Is this pair orderable at all? Raises if not; returns silently if it is.
  Ordering-only — `None == 3` is False in CPython, not an error, and `==`/`!=`
  never come here. }
procedure PyOrdCheck(const a: Variant; const b: Variant; const op: AnsiString);
var pa, pb: PPyVarRec; sa, sb: Boolean;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  if PyOrdIsNone(pa) or PyOrdIsNone(pb) then PyOrdRefuse(a, b, op);
  sa := (pa^.VType = 5) or (pa^.VType = 6);
  sb := (pb^.VType = 5) or (pb^.VType = 6);
  { a str against a non-str. The arm inside pyvar_gt raised 'comparison of a
    string with a number' for this, which is both differently worded and wrong
    about a list; CPython names the two types. }
  if sa <> sb then PyOrdRefuse(a, b, op);
end;

{ `a < b`, as CPython's sort/min actually spell it. Delegates to the `>`
  primitive with the operands swapped — but checks orderability FIRST, so the
  refusal names the operator and the operand order the source wrote. }
function pyvar_lt(const a: Variant; const b: Variant): Boolean;
begin
  PyOrdCheck(a, b, '<');
  pyvar_lt := pyvar_gt(b, a);
end;


function pyvar_gt(const a: Variant; const b: Variant): Boolean;
var pa, pb: PPyVarRec;
    la, lb, k, n: Int64;
    ea, eb: Variant;
    oa, ob: TObject;
    pg: Integer;
    pg2: Boolean;
begin
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  { None orders against nothing, and a str orders against no non-str. Before
    this the tag-0 payload fell through to pyvar_to_int and compared as 0, so
    `min(3, None)` answered None where CPython raises. }
  PyOrdCheck(a, b, '>');
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
    { Two USER objects: their own __gt__, or the reflected __lt__. Without this
      both fell through to pyvar_to_int and `pts.sort()` over a class defining
      __lt__ died with "expected a number, got object" — a runtime TypeError for
      the single most idiomatic way to make a class sortable.
      The bare `Point(1,1) < Point(1,2)` EXPRESSION already dispatched, because
      that path keys on the operands' static class at compile time; a sort
      compares two boxed variants with no static class to key on.
      bug-nilpy-list-sort-ignores-lt-dunder-on-objects }
    if PyUserObjGt(oa, ob, b, pg2) then
    begin
      pyvar_gt := pg2;
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

function pymath_trunc(x: Double): Int64;
begin
  { Pascal's Trunc already rounds toward zero AND yields an integer type, so
    the whole fix is that this returns Int64 rather than Double. }
  Result := Trunc(x);
end;

{ math.modf(x) -> (fractional, integral), BOTH floats and both carrying x's
  sign, which is CPython's contract — modf(-2.5) is (-0.5, -2.0), not
  (0.5, -2.0). A tuple, so it belongs here rather than in the RTL. }
{ `math.sqrt(-1)` and friends. CPython raises ValueError('math domain error')
  where IEEE — and therefore the Pascal RTL these lower to — answers a quiet NaN
  or -Inf. The guard sits on the ARGUMENT so a NaN input still answers NaN.
  bug-n-math-pow-domain-error-raises-the-wrong-exception }
function pymath_dom_nonneg(x: Double): Double;
begin
  if x < 0.0 then raise ValueError.Create('math domain error');
  pymath_dom_nonneg := x;
end;

{ log/log2/log10: zero is out of domain too, and gives -Inf rather than NaN. }
function pymath_dom_pos(x: Double): Double;
begin
  if x < 0.0 then raise ValueError.Create('math domain error');
  if x = 0.0 then raise ValueError.Create('math domain error');
  pymath_dom_pos := x;
end;

{ asin/acos: [-1, 1]. }
function pymath_dom_unit(x: Double): Double;
begin
  if (x < -1.0) or (x > 1.0) then raise ValueError.Create('math domain error');
  pymath_dom_unit := x;
end;

{ math.pow(b, e): CPython refuses a negative base with a non-integral exponent —
  the result is complex, and math is the real-only module. Returns the BASE, so
  the frontend wraps argument 0 and the exponent reaches both. 0 ** negative is
  the other refusal and wears the same message. }
{ The `**` OPERATOR's domain guard, distinct from math.pow's above on purpose.
  CPython's `(-8.0) ** (1/3)` is a COMPLEX number, not a math domain error, so
  the refusal has to say what it actually is — the message pypow_v has raised
  all along, kept verbatim now that the float path goes to the RTL's Power
  instead (bug-a-nilpy-star-star-has-its-own-low-precision-pow). Dropping this
  guard would have turned a named refusal into a silent NaN, which is the one
  direction not worth trading precision for.
  Complex support is filed as bug-nilpy-no-complex-number-type. }
function pypow_dom(b: Double; e: Double): Double;
begin
  if (b < 0.0) and (e - Int(e) <> 0.0) then
    raise ValueError.Create(
      'a negative number raised to a fractional power is complex, '
      + 'which NilPy does not have');
  { `0.0 ** -1` is a ZeroDivisionError in CPython, not an infinity — and the
    RTL's Power answers IEEE's +inf. pypow_v raises it on the dynamic path, so
    without this line the two spellings of one expression disagreed. }
  if (b = 0.0) and (e < 0.0) then
    raise ZeroDivisionError.Create(
      '0.0 cannot be raised to a negative power');
  pypow_dom := b;
end;

function pymath_dom_pow(b: Double; e: Double): Double;
var t: Double;
begin
  if b < 0.0 then
  begin
    t := e - Int(e);
    if t <> 0.0 then raise ValueError.Create('math domain error');
  end;
  if (b = 0.0) and (e < 0.0) then raise ValueError.Create('math domain error');
  pymath_dom_pow := b;
end;

{ OVERFLOW, which in CPython is a per-CALL rule and not a per-OPERATION one.
  `1e300 * 1e300` is `inf` in CPython exactly as it is here — IEEE, no error —
  but `2.0 ** 10000`, `math.exp(1000)` and `math.pow(10, 400)` all raise
  OverflowError, because CPython checks errno/ERANGE on the C library calls it
  wraps and on float pow. So the guard belongs on the RESULT of those calls and
  nowhere near `*`, `/` or `+`.

  Both operands are passed because an INFINITE input is not an overflow:
  `math.exp(float('inf'))` is `inf` in CPython, and `float('inf') ** 2` is too.
  Only a finite input producing an infinite result is the error. Underflow is
  NOT an error on either side — `2.0 ** -10000` is 0.0 in both.

  Two spellings of the message because CPython has two: the math module says
  `math range error`, float pow reports the raw errno.
  bug-nilpy-float-overflow-answers-inf-where-cpython-raises }
function pyfloat_isinf(x: Double): Boolean;
begin
  pyfloat_isinf := (x > 1.7e308) or (x < -1.7e308);
end;

function pyfloat_range_overflowed(v: Double; a: Double; b: Double): Boolean;
begin
  pyfloat_range_overflowed := False;
  if not pyfloat_isinf(v) then Exit;
  if pyfloat_isinf(a) or pyfloat_isinf(b) then Exit;
  pyfloat_range_overflowed := True;
end;

function pymath_range(v: Double; a: Double; b: Double): Double;
begin
  if pyfloat_range_overflowed(v, a, b) then
    raise OverflowError.Create('math range error');
  pymath_range := v;
end;

function pypow_range(v: Double; a: Double; b: Double): Double;
begin
  if pyfloat_range_overflowed(v, a, b) then
    raise OverflowError.Create('(34, ''Numerical result out of range'')');
  pypow_range := v;
end;

function pymath_range1(v: Double; a: Double): Double;
{ the one-argument shape (math.exp / sinh / cosh): the same argument twice }
begin
  pymath_range1 := pymath_range(v, a, a);
end;

function pymath_modf(x: Double): TPyList;
var ip: Double; pb: PInt64;
begin
  ip := Int(x);          { truncate toward zero — Int, not Floor }
  { ...and the integral part keeps x's sign even when it is ZERO: CPython's
    modf(-0.25) is (-0.25, -0.0), and Int() hands back a positive zero. Read
    from the SIGN BIT, not from `x < 0`, for the same reason copysign does. }
  pb := PInt64(@x);
  if (pb^ < 0) and (ip = 0.0) then ip := -0.0;
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  Result.append(x - ip);
  Result.append(ip);
end;

{ math.prod — the product, and an INT when every element is an int (CPython
  keeps the type: prod([2, 3]) is 6, not 6.0). The variant arithmetic already
  carries that rule, so this is a plain fold over it. }
function pymath_prod(l: TPyList): Variant;
var i: Integer; acc: Variant;
begin
  acc := 1;
  if l <> nil then
    for i := 0 to l.count - 1 do acc := acc * l.at(i);
  Result := acc;
end;

{ math.fsum — Neumaier compensated summation, which is what makes
  fsum([0.1] * 10) exactly 1.0 where a naive sum gives 0.9999999999999999.
  Same algorithm bug-nilpy-sum-of-floats-has-no-compensated-summation wants for
  sum(); when that lands the two should share THIS routine rather than grow a
  second copy of it. }
function pymath_fsum(l: TPyList): Double;
var i: Integer; sum, c, t, v: Double;
begin
  sum := 0.0;
  c := 0.0;
  if l <> nil then
    for i := 0 to l.count - 1 do
    begin
      v := pyvar_to_float(l.at(i));
      t := sum + v;
      { the compensation term is the part of the smaller operand the addition
        dropped, so which side is smaller decides where to read it from }
      if Abs(sum) >= Abs(v) then c := c + ((sum - t) + v)
      else c := c + ((v - t) + sum);
      sum := t;
    end;
  Result := sum + c;
end;

{ math.perm(n, k) — ordered arrangements, n!/(n-k)!, computed as the falling
  factorial so no intermediate n! overflows on its way to a small answer. }
function pymath_perm(n, k: Int64): Int64;
var i, r: Int64;
begin
  if (n < 0) or (k < 0) then
    raise ValueError.Create('perm() not defined for negative values');
  if k > n then begin Result := 0; Exit; end;
  r := 1;
  for i := 0 to k - 1 do r := r * (n - i);
  Result := r;
end;

{ SplitMix64 — see the block comment on the declarations. The state starts at a
  fixed value rather than a clock reading: a program that never calls seed()
  then reproduces exactly, which is what makes a failure reportable. CPython
  seeds from entropy instead, and a program that DEPENDS on the difference is
  depending on the stream, which neither implementation promises. }
var
  PyRandState: Int64 = Int64($9E3779B97F4A7C15);

function PyRandNext: Int64;
var z: Int64;
begin
  PyRandState := PyRandState + Int64($9E3779B97F4A7C15);
  z := PyRandState;
  z := (z xor (z shr 30)) * Int64($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * Int64($94D049BB133111EB);
  Result := z xor (z shr 31);
end;

{ the top 53 bits, scaled — the same construction CPython uses to land in
  [0, 1) with every representable double of that precision reachable }
function pyrandom_random: Double;
var u: Int64;
begin
  u := PyRandNext;
  u := (u shr 11) and Int64($1FFFFFFFFFFFFF);     { 53 bits, non-negative }
  Result := u / 9007199254740992.0;               { / 2^53 }
end;

procedure pyrandom_seed(n: Int64);
begin
  PyRandState := n;
end;

{ CPython's randint is inclusive at BOTH ends, unlike randrange. Reduced with a
  modulo over the width, which is fine for the widths a script uses. }
function pyrandom_randint(a, b: Int64): Int64;
var w, r: Int64;
begin
  if b < a then
    raise ValueError.Create('empty range for randint()');
  w := b - a + 1;
  if w <= 0 then begin Result := a; Exit; end;
  r := PyRandNext;
  if r < 0 then r := -r;
  if r < 0 then r := 0;              { the one value -(-2^63) cannot negate }
  Result := a + (r mod w);
end;

function pyrandom_randrange(n: Int64): Int64;
begin
  if n <= 0 then
    raise ValueError.Create('empty range for randrange()');
  Result := pyrandom_randint(0, n - 1);
end;

function pyrandom_uniform(a, b: Double): Double;
begin
  Result := a + (b - a) * pyrandom_random;
end;

function pyrandom_choice(l: TPyList): Variant;
begin
  if (l = nil) or (l.count = 0) then
    raise IndexError.Create('Cannot choose from an empty sequence');
  Result := l.at(Integer(pyrandom_randint(0, l.count - 1)));
end;

{ Fisher-Yates, in place — `random.shuffle(xs)` returns None and mutates, which
  is the half of the contract a caller most often gets wrong. }
procedure pyrandom_shuffle(l: TPyList);
var i, j: Integer; tmp: Variant;
begin
  if l = nil then Exit;
  for i := l.count - 1 downto 1 do
  begin
    j := Integer(pyrandom_randint(0, i));
    tmp := l.at(i);
    l.put(i, l.at(j));
    l.put(j, tmp);
  end;
end;

function pymath_copysign(x, y: Double): Double;
var m: Double; pb: PInt64;
begin
  m := Abs(x);
  { The SIGN BIT, not `y < 0`: negative zero compares equal to zero, so a
    comparison would answer +3.0 for copysign(3, -0.0) where CPython answers
    -3.0. Reading the double's bits as Int64 makes the sign bit the sign of
    that integer. }
  pb := PInt64(@y);
  if pb^ < 0 then Result := -m else Result := m;
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
var i, n, b0, b1: Integer;
begin
  Result := TPyList.Create;
  if pystr_isascii(s) then
  begin
    for i := 1 to Length(s) do Result.append(pystr_ofchar(s[i]));
    Exit;
  end;
  { list("héllo") is five one-CHARACTER strings, and each of those is a whole
    character — unlike pystr_at, which still hands back a lead byte. This path
    can be whole because its element type is already a string. }
  n := PyStrCharLen(s);
  for i := 0 to n - 1 do
  begin
    b0 := PyStrByteOfChar(s, i);
    b1 := PyStrByteOfChar(s, i + 1);
    Result.append(Copy(s, b0, b1 - b0));
  end;
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

function pynext_v(const v: Variant): Variant;
var o: TObject;
begin
  if (pyvartag(v) = 7) and (pyvarobj(v) <> nil) then
  begin
    o := TObject(pyvarobj(v));
    { a CURSOR advances — that is the whole difference between next() and
      "read element 0", and it is what single consumption means }
    if o is TPyIter then
    begin
      if not pyiter_has(TPyIter(o)) then
        raise StopIteration.Create('next() on an exhausted iterator');
      pynext_v := pyiter_next(TPyIter(o));
      Exit;
    end;
  end;
  pynext_v := pynext_first(pylist_v(v));
end;

function pynext_or_v(const v: Variant; const dflt: Variant): Variant;
var o: TObject;
begin
  if (pyvartag(v) = 7) and (pyvarobj(v) <> nil) then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyIter then
    begin
      pynext_or_v := pyiter_next_or(TPyIter(o), dflt);
      Exit;
    end;
  end;
  pynext_or_v := pynext_first_or(pylist_v(v), dflt);
end;

{ Is every element of this list a plain int/bool/float, with at least one
  FLOAT among them? That is exactly the case sum() compensates — see
  PySumNeumaier. A promo (arbitrary-precision) element, a str, a list, an
  object: all answer False, and the ordinary variant accumulation runs. }
function PySumAllFloatish(l: TPyList; var sawFloat: Boolean): Boolean;
var i, t: Integer;
begin
  Result := False;
  sawFloat := False;
  if (l = nil) or (l.count = 0) then Exit;
  for i := 0 to l.count - 1 do
  begin
    t := pyvartag(l.at(i));
    if t = 3 then sawFloat := True
    else if (t <> 1) and (t <> 2) and (t <> 4) then Exit;   { VT_INT/INT64/BOOL }
  end;
  Result := sawFloat;
end;

{ NEUMAIER compensated summation — the algorithm CPython's sum() has used for
  floats since 3.12, and the reason sum([1e16, 1.0, -1e16]) is 1.0 there and
  was 0.0 here: a naive accumulator loses the 1.0 against the 1e16 term and
  never gets it back. The compensation term c collects exactly what each
  addition dropped, and is added once at the end.

  Neumaier rather than plain Kahan because the running total can be SMALLER
  than the term being added (that is the 1e16 case in reverse), which is the
  branch below.
  bug-nilpy-sum-of-floats-has-no-compensated-summation }
function PySumNeumaier(l: TPyList; s: Double): Double;
var i: Integer; c, x, t: Double;
begin
  c := 0.0;
  for i := 0 to l.count - 1 do
  begin
    x := pyvar_to_float(l.at(i));
    t := s + x;
    if Abs(s) >= Abs(x) then c := c + ((s - t) + x)
    else c := c + ((x - t) + s);
    s := t;
  end;
  PySumNeumaier := s + c;
end;

function sum(l: TPyList): Variant;
var i: Integer; sawFloat: Boolean;
begin
  Result := pyvar_of_int(0);
  if l = nil then Exit;
  if PySumAllFloatish(l, sawFloat) then
  begin
    Result := PySumNeumaier(l, 0.0);
    Exit;
  end;
  for i := 0 to l.count - 1 do Result := pyadd_v(Result, l.at(i));
end;

function sum(l: TPyList; const start: Variant): Variant; overload;
var i, st: Integer; sawFloat: Boolean;
begin
  Result := start;
  if l = nil then Exit;
  { the START joins the float path only when it is itself a plain number —
    otherwise (a promo start, a str) the ordinary accumulation decides }
  st := pyvartag(start);
  if ((st = 1) or (st = 2) or (st = 3) or (st = 4)) and
     PySumAllFloatish(l, sawFloat) then
  begin
    Result := PySumNeumaier(l, pyvar_to_float(start));
    Exit;
  end;
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
var i, n: Integer; best, c: AnsiString;
begin
  { CHARACTERS, not bytes: iterating a str is `for c in s`, which yields whole
    characters everywhere else, so this walked a different sequence than the
    rest of the language and answered a lone lead byte for a non-ASCII winner
    (`max("cafÃ© â¢")` printed one third of the bullet). Comparing the UTF-8
    substrings directly is the right order too — UTF-8 sorts byte-lexicographically
    exactly as its code points sort.
    bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
  n := PyStrCharLen(s);
  if n = 0 then raise ValueError.Create('max() iterable argument is empty');
  best := pystr_charat(s, 0);
  for i := 1 to n - 1 do
  begin
    c := pystr_charat(s, i);
    if c > best then best := c;
  end;
  Result := best;
end;
{ max()/min() over ANY iterable. The element walk is the whole of these; what
  counts as iterable is `pylist_v`'s question, not theirs.

  These used to carry their own o-is-TPyRange / o-is-TPyIter chain and refuse
  everything else, which is why `max(d)` over a DICT raised while `for k in d`,
  `list(d)` and `sorted(d)` all answered its keys — an inconsistency inside
  NilPy rather than a divergence from CPython. Routing through the one
  normaliser fixes the dict, bytes and USER-iterable rows at once and cannot
  drift from the other consumers again.
  bug-nilpy-max-and-min-do-not-iterate-a-dict }
function max(const v: Variant): Variant; overload;
var l: TPyList; i: Integer; e: Variant; n: Integer;
begin
  if (pyvartag(v) <> 6) and (pyvartag(v) <> 7) then
    raise TypeError.Create('max() argument is not iterable');
  l := pylist_v(v);
  n := 0;
  if l <> nil then n := l.count;
  if n = 0 then raise ValueError.Create('max() iterable argument is empty');
  Result := l.at(0);
  for i := 1 to n - 1 do
  begin
    e := l.at(i);
    if pyvar_gt(e, Result) then Result := e;
  end;
end;

function min(const v: Variant): Variant; overload;
var l: TPyList; i: Integer; e: Variant; n: Integer;
begin
  if (pyvartag(v) <> 6) and (pyvartag(v) <> 7) then
    raise TypeError.Create('min() argument is not iterable');
  l := pylist_v(v);
  n := 0;
  if l <> nil then n := l.count;
  if n = 0 then raise ValueError.Create('min() iterable argument is empty');
  Result := l.at(0);
  for i := 1 to n - 1 do
  begin
    e := l.at(i);
    if pyvar_lt(e, Result) then Result := e;
  end;
end;


function min(const s: AnsiString): AnsiString;
var i, n: Integer; best, c: AnsiString;
begin
  { CHARACTERS, not bytes: iterating a str is `for c in s`, which yields whole
    characters everywhere else, so this walked a different sequence than the
    rest of the language and answered a lone lead byte for a non-ASCII winner
    (`min("cafÃ© â¢")` printed one third of the bullet). Comparing the UTF-8
    substrings directly is the right order too — UTF-8 sorts byte-lexicographically
    exactly as its code points sort.
    bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
  n := PyStrCharLen(s);
  if n = 0 then raise ValueError.Create('min() iterable argument is empty');
  best := pystr_charat(s, 0);
  for i := 1 to n - 1 do
  begin
    c := pystr_charat(s, i);
    if c < best then best := c;
  end;
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

procedure pydict_merge_any(dst: TPyDict; const src: Variant);
var o: TObject;
begin
  if dst = nil then Exit;
  if pyvartag(src) <> 7 then
    raise TypeError.Create('dict.update expects a mapping or an iterable of pairs');
  o := TObject(pyvarobj(src));
  if o = nil then Exit;
  if o is TPyDict then pydict_merge(dst, TPyDict(o))
  else if o is TPyList then dst.update(TPyList(o))
  else
    raise TypeError.Create('dict.update expects a mapping or an iterable of pairs');
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
  { the shared chain — a list, a dict's keys, bytes, a cursor, a range or a
    user `__iter__`. Added ONE BY ONE rather than adopted wholesale, because a
    set DEDUPLICATES on add: `set([1, 1, 2])` is {1, 2}. Before this, pyset_of
    knew only lists and dicts, so set(range(3)) and set(bag) refused. }
  kl := pyseq_of_obj(o);
  if kl <> nil then
  begin
    for i := 0 to kl.count - 1 do r.add(kl.at(i));
    Exit;
  end;
  raise TypeError.Create('set() argument must be iterable');
end;

function pydict_fromkeys(const src: Variant): TPyDict;
var d: TPyDict; l: TPyList; i: Integer;
begin
  d := TPyDict.Create;
  l := pylist_v(src);
  if l <> nil then
    for i := 0 to l.count - 1 do
      d.store(l.at(i), pynone());
  Result := d;
end;

{ dict.fromkeys(iterable, value) — the two-argument form, which fills every key
  with the SAME value rather than None. A genuine Pascal OVERLOAD: the stdlib
  call site re-targets by ARITY via FindProcArity, which is exactly the route
  its own comment recommends ("declare a 3-argument overload like any Pascal
  routine"). Type-based selection would still not be reachable that way, but
  arity is all this needs.
  Note CPython shares ONE value object across all the keys — it does not copy
  it — so a mutable fill is aliased by every key. Storing the same variant is
  exactly that behaviour, not a shortcut. }
function pydict_fromkeys(const src: Variant; const v: Variant): TPyDict; overload;
var d: TPyDict; l: TPyList; i: Integer;
begin
  d := TPyDict.Create;
  l := pylist_v(src);
  if l <> nil then
    for i := 0 to l.count - 1 do
      d.store(l.at(i), v);
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
      { pyvar_to_int, NOT the Pascal VariantToInt64: NilPy code must not reach
        the Pascal helper set at all. The lowering seam
        (IRLowerVariantAsScalar) already routes NilPy to pylib's helpers, but a
        DIRECT call here walks around that seam — and the Pascal helper is
        about to read a boolean variant as OLE's -1, which would make
        Counter(...) over booleans count DOWN and break CPython's True == 1.
        pyvar_to_int reads VT_BOOL as its payload (1) and raises a Python
        TypeError for a str/object, which is what CPython's Counter arithmetic
        does. bug-p-variant-to-int-and-char-conversion-diverges-from-fpc }
      store(k, pyvar_to_int(fetch(k)) + 1);
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

function TPyDict.update(const v: Variant): Variant;
var o: TObject;
begin
  Result := pynone;
  if Self = nil then Exit;
  if pyvartag(v) <> 7 then
    raise TypeError.Create('dict.update expects a mapping or an iterable of pairs');
  o := TObject(pyvarobj(v));
  if o = nil then Exit;
  if o is TPyDict then Result := Self.update(TPyDict(o))
  else if o is TPyList then Result := Self.update(TPyList(o))
  else
    raise TypeError.Create('dict.update expects a mapping or an iterable of pairs');
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
      { pyvar_to_int on BOTH sides — see the note in the list arm above. The
        VALUE side matters most here: `Counter.update(someDict)` merges the
        other dict's values, which may be booleans. }
      store(k, pyvar_to_int(fetch(k)) + pyvar_to_int(vs.at(i)))
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
          (pyvar_to_int(vs.at(idx[j])) > pyvar_to_int(vs.at(idx[j - 1]))) do
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
    c.store(s[i], pyvar_to_int(c.fetch(s[i])) + 1);
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
  i, j: Integer;
  found: Boolean;
begin
  Result := False;
  if a = b then begin Result := True; Exit; end;
  if (a = nil) or (b = nil) then Exit;
  if a.FLen <> b.FLen then Exit;
  { A SET compares by MEMBERSHIP, not by position: CPython's {1, 2} == {2, 1}
    is True and this answered False, because a set is a TPyList here and the
    positional walk below is the LIST rule (which is correct for lists — Python
    list equality really is ordered). FKind is the tag that tells them apart;
    it exists now, which is what makes this cheap.
    A set is also never equal to a sequence: {1, 2} == [1, 2] is False in
    CPython and answered True. Only the SET side of the kind check is enforced
    here — tuple-vs-list is the same root cause and is filed separately, since
    tightening it moves code that sets no explicit kind.
    feature-nilpy-set-needs-runtime-tag-for-display-and-equality }
  { A TUPLE is never equal to a LIST either — `(1, 2) == [1, 2]` is False in
    CPython and answered True here, the same tag-blind positional walk that made
    a set equal to a list. Held back when the set half landed because the guard
    fires for every value whose kind was never stamped; the constructors were
    then swept (dict items, zip, divmod, tuple()/list(), slices, concatenation,
    comprehensions, all three literals) and `type(x).__name__` agrees with
    CPython for every one, so there is no unstamped population to protect.
    bug-nilpy-a-tuple-compares-equal-to-a-list }
  if (a.FKind = PYSEQ_TUPLE) <> (b.FKind = PYSEQ_TUPLE) then Exit;
  if (a.FKind = PYSEQ_SET) or (b.FKind = PYSEQ_SET) or
     (a.FKind = PYSEQ_FROZENSET) or (b.FKind = PYSEQ_FROZENSET) then
  begin
    { a frozenset and a set with the same elements ARE equal in CPython —
      frozenset is a different TYPE, not a different value — so the kind check
      here is set-likeness, not kind identity. }
    if (a.FKind = PYSEQ_LIST) or (b.FKind = PYSEQ_LIST) or
       (a.FKind = PYSEQ_TUPLE) or (b.FKind = PYSEQ_TUPLE) then Exit;
    { equal lengths and no duplicates on either side (add() dedups), so
      "every element of a is in b" is enough }
    for i := 0 to a.FLen - 1 do
    begin
      found := False;
      for j := 0 to b.FLen - 1 do
        if PyVarEq(PPyVarRec(NativeInt(a.FItems) + i * 16),
                   PPyVarRec(NativeInt(b.FItems) + j * 16)) then
        begin found := True; Break; end;
      if not found then Exit;
    end;
    Result := True;
    Exit;
  end;
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
  { the callable / class-object tags. They used to fall through to '<unknown>'
    — except a plain def, which wore VT_INT64 and so answered 'int', so
    `type(add).__name__` said int and `isinstance(add, int)` said True. Both are
    consequences of the tag collision VT_CALLABLE closed; naming the tags here
    is what turns the new tag into the right ANSWER rather than just a
    different wrong one. CPython spells a bound method 'method' and everything
    else callable 'function'. }
  else if t = 8 then Result := 'method'
  else if (t = 9) or (t = 10) or (t = 12) then Result := 'function'
  else if (t = 11) or (t = 13) then Result := 'type'   { a class object, and a builtin type object }
  { An ARBITRARY-PRECISION int, VT_PROMO_INT64 and anything else at or above
    VT_PROMO_BASE (8192): to Python it is just an `int`, and answering
    '<unknown>' made a program that branches on type(x).__name__ take the wrong
    arm for exactly the values NilPy is proudest of. Tested as a RANGE because
    that is how the promo tags are laid out — see the contiguity note on
    VT_PROMO_BASE in defs.inc.
    bug-nilpy-type-of-a-big-int-answers-unknown }
  else if t >= 8192 then Result := 'int'
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
function PyNotSubscriptable(const clsName: AnsiString): Int64;
{ `w["x"]` on a class that declares no __getitem__. CPython raises TypeError at
  RUN time, so this must too — a compile error would reject the ordinary
  `try: obj[k] / except TypeError:` probe, which is valid Python.

  A FUNCTION returning Int64 for the same reason PyIndexTypeError is one: it
  stands in for the whole subscript EXPRESSION at the call site.
  bug-nilpy-subscript-read-without-getitem-yields-garbage }
begin
  raise TypeError.Create('''' + clsName + ''' object is not subscriptable');
  PyNotSubscriptable := 0;   { unreachable }
end;

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
{ A statically PROVEN operand clash, worded as CPython words it. The compiler
  knows both types here — that is why it took this arm — so it passes them as
  small codes and this composes the message; no IR-level string constants, and
  no second copy of Python's type vocabulary.
  op:  1 '+'  2 '-'  3 '*'  4 '/'  5 '//'  6 '%'  7 '<'  8 '<='  9 '>'  10 '>='
  kind: 0 str  1 int  2 float  3 bool  4 unknown
  bug-nilpy-statically-clashing-operands-refuse-without-naming-the-types }
procedure PyOperandClashError(op: Int64; lk: Int64; rk: Int64); forward;

{ The operand type as Python spells it, from the compiler's small code. }
function PyClashKindName(k: Int64): AnsiString;
begin
  if k = 0 then PyClashKindName := 'str'
  else if k = 1 then PyClashKindName := 'int'
  else if k = 2 then PyClashKindName := 'float'
  else if k = 3 then PyClashKindName := 'bool'
  else PyClashKindName := 'object';
end;

function PyClashOpName(op: Int64): AnsiString;
begin
  if op = 1 then PyClashOpName := '+'
  else if op = 2 then PyClashOpName := '-'
  else if op = 3 then PyClashOpName := '*'
  else if op = 4 then PyClashOpName := '/'
  else if op = 5 then PyClashOpName := '//'
  else if op = 6 then PyClashOpName := '%'
  else if op = 7 then PyClashOpName := '<'
  else if op = 8 then PyClashOpName := '<='
  else if op = 9 then PyClashOpName := '>'
  else PyClashOpName := '>=';
end;

{ CPython does not use ONE shape for this: comparisons name the operator and
  both instances, arithmetic names the operator and both types, and `str` has
  two messages of its own for `+` and `*` that mention neither in that form.
  All four are reproduced, because a program that greps a message is the only
  reason the wording matters at all. }
procedure PyOperandClashError(op: Int64; lk: Int64; rk: Int64);
var ln, rn, q: AnsiString;
begin
  q := Chr(39);
  ln := PyClashKindName(lk);
  rn := PyClashKindName(rk);
  if op >= 7 then
    raise TypeError.Create(q + PyClashOpName(op) + q +
      ' not supported between instances of ' + q + ln + q + ' and ' + q + rn + q);
  { `'a' + 3` and `'a' * 'b'` — str's own wording, and note the DOUBLE quotes
    around the type in the concatenate message. CPython's, not a typo here. }
  if (op = 1) and (lk = 0) then
    raise TypeError.Create('can only concatenate str (not "' + rn + '") to str');
  if (op = 3) and ((lk = 0) or (rk = 0)) then
  begin
    if lk = 0 then
      raise TypeError.Create('can' + q + 't multiply sequence by non-int of type ' + q + rn + q)
    else
      raise TypeError.Create('can' + q + 't multiply sequence by non-int of type ' + q + ln + q);
  end;
  raise TypeError.Create('unsupported operand type(s) for ' + PyClashOpName(op) +
    ': ' + q + ln + q + ' and ' + q + rn + q);
end;

procedure PyUnsupportedOperandError;
begin
  raise TypeError.Create('unsupported operand type(s) for this operator');
end;

{ `obj[i] = v` where obj's class defines `__getitem__` but not `__setitem__`
  -- CPython's own error shape, class name and all:
  `'ReadOnly' object does not support item assignment`.

  It used to say "object does not support item assignment (no __setitem__)",
  naming the DUNDER instead of the class — implementation-facing, and backwards
  for a diagnostic a user meets while debugging a write. Its own sibling on the
  READ side already named the class, so the two halves of one feature disagreed
  and the worse-reading half was the one a write reached
  (bug-nilpy-nosetitem-error-does-not-name-the-class). }
procedure PyNoSetitemError(const cls: AnsiString);
begin
  if cls = '' then
    raise TypeError.Create('object does not support item assignment');
  raise TypeError.Create('''' + cls + ''' object does not support item assignment');
end;

{ `del obj[i]` where obj's class defines no `__delitem__` -- CPython's own error
  shape. A raise rather than a compile error, so a try/except around it builds,
  same reasoning as PyNoSetitemError above.
  bug-nilpy-delitem-dunder-not-supported }
procedure PyNoDelitemError(const cls: AnsiString);
begin
  if cls = '' then
    raise TypeError.Create('object does not support item deletion');
  raise TypeError.Create('''' + cls + ''' object does not support item deletion');
end;

{ `int(obj)` / `float(obj)` where obj's class declares no `__int__` /
  `__float__` — CPython's own message shapes. A raise, not a compile error, for
  the same reason as the two above: a try/except around it must still build.
  Without them the conversion handed the intrinsic an object HANDLE and the
  program printed the POINTER (bug-nilpy-int-and-float-ignore-their-dunders). }
procedure PyNoIntError(const cls: AnsiString);
begin
  if cls = '' then
    raise TypeError.Create('int() argument must be a string, a bytes-like object or a real number');
  raise TypeError.Create('int() argument must be a string, a bytes-like object or a real number, not '''
                         + cls + '''');
end;

procedure PyNoFloatError(const cls: AnsiString);
begin
  if cls = '' then
    raise TypeError.Create('float() argument must be a string or a real number');
  raise TypeError.Create('float() argument must be a string or a real number, not '''
                         + cls + '''');
end;

function pyvar_to_int(const v: Variant): Int64;
var
  p: PPyVarRec;
  ds: AnsiString;
  i: Integer;
  r: Int64;
begin
  p := PPyVarRec(@v);
  { 12 = VT_CALLABLE, a compiled routine's code address. Here for the
    machine-word readings the internals do — a callable variant read back into a
    tyPointer to be called through — NOT because Python would coerce a function
    to an int. It arrived as VT_INT64 and landed in this arm by accident of the
    tag collision the callable tag closed, so keeping it is what makes that
    retagging behaviour-preserving. VT_CLASSREF (11) is deliberately NOT here:
    it has always had its own tag and has always raised. }
  if (p^.VType = 1) or (p^.VType = 2) or (p^.VType = 4) or (p^.VType = 12) then
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
    { pyord_s, not a byte read: it counts in CHARACTERS and decodes the UTF-8
      lead byte, so ord() of a str reaching here as a VARIANT — an unannotated
      parameter, a for-loop variable, an element out of a container — answers
      8226 for a bullet rather than 226, its first byte, and rather than a
      TypeError about "a str of length 1" for a string Python calls length 1.
      The typed arm has answered this way since text strings landed.
      bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
    Result := pyord_s(PPyAnsiString(@p^.Payload)^)
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
    { CHARACTERS, not bytes. This is the helper `len(x)` on an UNANNOTATED
      parameter actually reaches — ir.inc rewrites len(<variant>) to pylen_v —
      so it answered the UTF-8 BYTE count while `s[i]` on the same value was
      bounds-checked in characters. `while i < len(s): out += s[i]` over any
      text with an accent then raised IndexError, and a program that only asked
      len(s) got a plausible number silently too large. `s: str` and a local
      were right all along, which is why it survived.
      bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
    Result := PyStrCharLen(PPyAnsiString(@p^.Payload)^)
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

function pymul_v_inplace(const a: Variant; const b: Variant): Variant;
{ The AUGMENTED product, `xs *= n`, where the target reads as a VARIANT — an
  unannotated parameter, a dict value, a list element. A mutable LIST is
  repeated IN PLACE and the same handle answered, so an alias taken beforehand
  sees the new contents, which is what Python does; everything else is the
  ordinary product, computed by pymul_v itself rather than re-implemented here.

  A tuple and a frozenset are immutable and take the ordinary path — the kind
  check lives in pylist_repeat_inplace, which is the one place that knows it.
  bug-nilpy-augmented-repeat-on-a-variant-target-still-rebinds }
var o: TObject;
begin
  { BOTH integer tags: a boxed literal wears VT_INT (1) and a boxed Int64
    VT_INT64 (2), and testing only one is how the arm silently never fired. }
  if (pyvartag(a) = 7) and (pyvarobj(a) <> nil) and
     ((pyvartag(b) = 1) or (pyvartag(b) = 2) or (pyvartag(b) = 4)) then
  begin
    o := TObject(pyvarobj(a));
    if (o is TPyList) and (TPyList(o).FKind = PYSEQ_LIST) then
    begin
      pylist_repeat_inplace(TPyList(o), pyvar_to_int(b));
      Result := a;
      Exit;
    end;
  end;
  Result := pymul_v(a, b);
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
  { A USER class operand: its own __mul__, or the reflected __rmul__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__mul__', '__rmul__', Result) then Exit;
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
  { A DOMAIN GUARD, and it is what stops an infinite loop rather than merely
    reporting one: the normalising loop below is `while m < 1.0 do m := m * 2.0`,
    and for any x <= 0 that condition can never become false — 0 doubles to 0
    and a negative doubles away from 1 forever. So `math.log(0)` and every
    caller that reaches here with a non-positive value HUNG, producing no
    output and no diagnostic.
    CPython raises ValueError('math domain error') for log of a non-positive,
    and this is the same message.
    bug-nilpy-pow-and-log-hang-on-a-non-positive-base }
  if x <= 0.0 then
    raise ValueError.Create('math domain error');
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
  { A USER class operand: its own __pow__, or the reflected __rpow__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__pow__', '__rpow__', Result) then Exit;
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
  { ZERO to a POSITIVE power is 0.0 — CPython's answer, and it has to be
    settled HERE because the fractional-exponent path below goes through
    PyMathLn, whose normalising loop never terminates for a non-positive
    argument. `0 ** 0.5` therefore HUNG: no output, no diagnostic, and about as
    ordinary an expression as there is.
    bug-nilpy-pow-and-log-hang-on-a-non-positive-base }
  if (fbase = 0.0) and (fexp > 0.0) then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := 0.0;
    Exit;
  end;
  { A NEGATIVE base with a FRACTIONAL exponent is a COMPLEX number in CPython
    ((-8) ** (1/3) is 1.0000000000000002+1.7320508075688772j). NilPy has no
    complex type, so the honest answer is a named refusal rather than a real
    number that is not the answer — and certainly rather than the hang this
    used to be, for the same PyMathLn reason as above. An INTEGER exponent is
    unaffected and still goes down the repeated-squaring path below, which is
    where every ordinary `(-2) ** 3` lands.
    Complex support is filed as bug-nilpy-no-complex-number-type. }
  if (fbase < 0.0) and (Frac(fexp) <> 0.0) then
    raise ValueError.Create(
      'a negative number raised to a fractional power is complex, '
      + 'which NilPy does not have');
  { The RTL's correctly-rounded pow, when the program has it (see PyPowHook).
    BOTH float paths below are worth replacing, not just the fractional one:
    the integer-exponent path is repeated squaring in plain doubles, and that
    is where `1.0001 ** 10000` accumulated 1282 ulp — wrong in the 12th
    significant digit of the ordinary compound-interest shape. }
  { OVERFLOW: CPython raises OverflowError for float `**`, and this is the
    DYNAMIC path — a variant receiver, a loop variable, a list element — so it
    needs the same guard the static route applies at the call site or the two
    spellings of one expression disagree again.
    bug-nilpy-float-overflow-answers-inf-where-cpython-raises }
  if PyPowHook <> nil then
  begin
    r^.VType := 3;
    PPyDouble(@r^.Payload)^ := pypow_range(PyPowHook(fbase, fexp), fbase, fexp);
    Exit;
  end;
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
  PPyDouble(@r^.Payload)^ := pypow_range(fr, fbase, fexp);
end;

function pydivmod_v(const a: Variant; const b: Variant): TPyList;
var pa, pb: PPyVarRec; oa, ob, r: TObject;
begin
  { A USER class first: `divmod(M(7), M(3))` used to reach pyfloordiv_v with two
    object handles and die with runtime error 219 (a bad cast) rather than
    calling __divmod__ or raising. Both operands must be objects for the dunder
    to be the right answer; a mixed pair falls through to the numeric path, and
    CPython's own reflected rule is covered by trying __rdivmod__ on b.
    feature-nilpy-arithmetic-dunders-full-protocol }
  pa := PPyVarRec(@a); pb := PPyVarRec(@b);
  oa := nil; ob := nil;
  if (pa^.VType = 7) and (pa^.Payload <> 0) then oa := TObject(Pointer(NativeInt(pa^.Payload)));
  if (pb^.VType = 7) and (pb^.Payload <> 0) then ob := TObject(Pointer(NativeInt(pb^.Payload)));
  { EITHER side being a user object is enough. Requiring BOTH meant
    `divmod(D(17), 5)` — a user class and a plain number, which is what code
    actually writes — never reached __divmod__ at all and fell into the numeric
    path, where the object handle was cast and the program died with runtime
    error 219 (bug-nilpy-divmod-on-a-user-class-dies-with-runtime-error-219).
    A dunder taking `other` as a Variant has always been able to receive the
    number; only this gate said otherwise. }
  if ((oa <> nil) and not ((oa is TPyList) or (oa is TPyDict) or (oa is TPyBytes))) or
     ((ob <> nil) and not ((ob is TPyList) or (ob is TPyDict) or (ob is TPyBytes))) then
  begin
    begin
      if PyUserObjDivmod(oa, ob, a, b, r) then
      begin
        pydivmod_v := TPyList(r);
        Exit;
      end;
      { an object with no __divmod__ is a TypeError in CPython, and used to be
        a runtime-219 crash here }
      raise TypeError.Create(
        'unsupported operand type(s) for divmod() (no __divmod__/__rdivmod__)');
    end;
  end;
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
  { A USER class operand: its own __floordiv__, or the reflected __rfloordiv__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__floordiv__', '__rfloordiv__', Result) then Exit;
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
  { A USER class operand: its own __mod__, or the reflected __rmod__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__mod__', '__rmod__', Result) then Exit;
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
    oa, ob: TObject; joined: TPyList; ji: Integer; jb: TPyBytes;
    ia, ib, ir: Int64;   { machine-word result, checked for overflow }
begin
  { A USER class operand: its own __add__, or the reflected __radd__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__add__', '__radd__', Result) then Exit;
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
    { bytes + bytes -> a NEW bytes, the sibling of the list arm above and of the
      str arm below. It was missing, so a variant-held bytes fell through to the
      NUMERIC path and raised "expected a number, got object" — every other
      container concatenation had an arm and this one did not. Reachable from
      any bytes that arrives as a variant: an element of a list, an unannotated
      parameter, and (since the mode-aware readers) `f.read(n)` in binary mode.
      bug-nilpy-text-mode-read-n-returns-bytes-not-str }
    if (oa is TPyBytes) and (ob is TPyBytes) then
    begin
      jb := TPyBytes.Create(TPyBytes(oa).FLen + TPyBytes(ob).FLen);
      jb.FIsByteArray := TPyBytes(oa).FIsByteArray;
      jb.FLen := 0;
      jb.extend(TPyBytes(oa));
      jb.extend(TPyBytes(ob));
      Result := jb;
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
  { A str against a NON-str. Falling through to the numeric arms reached
    pyvar_to_float's generic "expected a number, got str" — a message about a
    coercion, from an operator the user wrote, naming neither the operator nor
    the other operand. CPython has two specific messages here and they are
    asymmetric, because `str + x` is a failed CONCATENATION and `x + str` is a
    failed addition.
    bug-nilpy-statically-clashing-operands-refuse-without-naming-the-types }
  if (pa^.VType = 6) or (pa^.VType = 5) then
    raise TypeError.Create('can only concatenate str (not "' +
                           pytype_name_v(b) + '") to str');
  if (pb^.VType = 6) or (pb^.VType = 5) then
    raise TypeError.Create('unsupported operand type(s) for +: ' + Chr(39) +
                           pytype_name_v(a) + Chr(39) + ' and ' + Chr(39) +
                           'str' + Chr(39));
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
  { A USER class operand: its own __sub__, or the reflected __rsub__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__sub__', '__rsub__', Result) then Exit;
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
  { A USER class operand: its own __mod__, or the reflected __rmod__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__mod__', '__rmod__', Result) then Exit;
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
    oa, ob: TObject; pc: Integer; cmpB: Boolean;
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
    { a USER class's own ordering. pycmp_v owes -1/0/1, so BOTH directions are
      asked: `__lt__` (or the reflected `__gt__`) decides less-than, and only if
      that is False is greater-than asked. A class declaring just one of the two
      still answers correctly, because each helper falls back to the other
      operand's mirror dunder — which is the common case, since Python's
      ordering protocol only requires __lt__.
      Without this, `lhs < p` on two VARIANT-typed operands raised while the
      statically-typed spelling worked.
      bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
    if PyUserObjLt(oa, ob, b, cmpB) then
    begin
      if cmpB then begin Result := -1; Exit; end;
      if PyUserObjGt(oa, ob, b, cmpB) then
        if cmpB then begin Result := 1; Exit; end;
      Result := 0;
      Exit;
    end;
    if PyUserObjGt(oa, ob, b, cmpB) then
    begin
      if cmpB then Result := 1 else Result := 0;
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
  { A USER class operand: its own __truediv__, or the reflected __rtruediv__. The
    compile-time dispatch in the parser keys on a STATIC class, which a variant
    operand does not have, so without this the operands fell through to the
    numeric path and raised "expected a number, got object" for a dunder the
    program plainly declares. Placed FIRST so a user class can override even the
    list/str arms below, matching Python's own precedence.
    bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
  if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and
     (PPyVarRec(@a)^.Payload <> 0) and (PPyVarRec(@b)^.Payload <> 0) then
    if PyUserObjArith(TObject(pyvarobj(a)), TObject(pyvarobj(b)), a, b,
                      '__truediv__', '__rtruediv__', Result) then Exit;
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

{ The four ORDERING operators on a variant operand. Each checks orderability
  first, in the operand order the source wrote and naming its own operator, so
  `3 < None` reports `'<' ... 'int' and 'NoneType'` exactly as CPython does
  rather than ordering the tag-0 payload as 0 and answering False.
  bug-nilpy-comparing-none-with-a-number-answers-instead-of-raising.
  `==`/`!=` are pyeq_v's business and stay total — `None == 3` is False. }
function pylt_v(const a: Variant; const b: Variant): Boolean;
begin
  PyOrdCheck(a, b, '<');
  Result := pycmp_v(a, b) < 0;
end;

function pyle_v(const a: Variant; const b: Variant): Boolean;
begin
  PyOrdCheck(a, b, '<=');
  Result := pycmp_v(a, b) <= 0;
end;

function pygt_v(const a: Variant; const b: Variant): Boolean;
begin
  PyOrdCheck(a, b, '>');
  Result := pycmp_v(a, b) > 0;
end;

function pyge_v(const a: Variant; const b: Variant): Boolean;
begin
  PyOrdCheck(a, b, '>=');
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

{ TIES GO TO THE FIRST ARGUMENT, in min and max alike — CPython's documented
  rule, and the reason min(-0.0, 0.0) is -0.0 there and max(-0.0, 0.0) is -0.0
  too. Each test is therefore written against the SECOND operand: `b < a`
  rather than `a < b`, so an equal pair falls through to a. Negative zero only
  makes it visible; the case that bites real code is min(items, key=...) over
  equal-scoring objects, where CPython guarantees the first and handing back a
  different object is silent.
  bug-nilpy-abs-keeps-the-sign-of-negative-zero-and-min-max-break-ties-backwards }
function min(a: Int64; b: Int64): Int64;
begin
  if b < a then Result := b else Result := a;
end;

function min(a: Double; b: Double): Double; overload;
begin
  if b < a then Result := b else Result := a;
end;

function max(a: Int64; b: Int64): Int64; overload;
begin
  if b > a then Result := b else Result := a;
end;

function max(a: Double; b: Double): Double; overload;
begin
  if b > a then Result := b else Result := a;
end;

function PyVarIsCallable(const v: Variant): Boolean;
{ Any of the callable TAGS a NilPy function value can wear — a bound method or
  a bare def (8), a pyeval closure (9), a lifted bound-fn (10), a callable
  object (12). The same set PyVarTypeName answers 'method'/'function' for, which
  is the definition of "callable" this dialect already commits to. }
var t: Int64;
begin
  t := pyvartag(v);
  PyVarIsCallable := (t = 8) or (t = 9) or (t = 10) or (t = 12);
end;

function PyCallKeyVar(const key: Variant; const a0: Variant): Variant;
{ Call a callable VARIANT of any of the four shapes with one argument. A bound
  pair (tag 8) is callable from here; a closure, a lifted bound-fn and a
  callable object are pyeval's to dispatch, and pyeval publishes PyCallKey1 into
  PyIterCallHook for exactly that reason. }
begin
  if (pyvartag(key) = 8) or (PyIterCallHook = nil) then
    PyCallKeyVar := pybound_callv1(key, a0)
  else
    PyCallKeyVar := PyIterCallHook(pyvar_callable_ptr(key, 'key'), a0);
end;

function PyMinMaxByKey(const c: Variant; const key: Variant;
                       wantMax: Boolean): Variant;
{ `min(xs, key=f)` / `max(xs, key=f)` where the KEY is a callable held in a
  VARIABLE. Those spellings picked THIS two-argument numeric overload — a
  variant argument matches `b: Variant` exactly while the intended
  `key: Pointer` candidate needs a coercion the resolver applies only after a
  proc is chosen — and the numeric compare then raised
  "expected a number, got object" while comparing the LIST against the
  FUNCTION. `key=<def name>` and `key=lambda ...` were unaffected because those
  are pointer-typed nodes.

  Answered here rather than by widening overload resolution: comparing a
  function is a TypeError in CPython too, so a callable second argument can
  only ever have meant the key form, and this is the one place both receiver
  shapes (a static list boxed into a variant, and a variant container) arrive
  at. bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload }
var i, n: Integer; cur, curK, bestK: Variant; better: Boolean; l: TPyList;
begin
  { through pylist_v, not pyvar_getitem on the container: a DICT indexed by 0
    is a KEY LOOKUP, so `max(d, key=len)` raised KeyError: 0 where CPython
    walks the keys. Same one normaliser the plain max/min arms use.
    bug-nilpy-max-and-min-do-not-iterate-a-dict }
  l := pylist_v(c);
  n := 0;
  if l <> nil then n := l.count;
  if n = 0 then
  begin
    { the message names the builtin the caller wrote — this arm serves both, and
      answering `min()` for a `max(xs, key=f)` was a small lie in a diagnostic }
    if wantMax then raise ValueError.Create('max() iterable argument is empty')
    else raise ValueError.Create('min() iterable argument is empty');
  end;
  Result := l.at(0);
  bestK := PyCallKeyVar(key, Result);
  for i := 1 to n - 1 do
  begin
    cur := l.at(i);
    curK := PyCallKeyVar(key, cur);
    if wantMax then better := pyvar_gt(curK, bestK)
    else better := pyvar_lt(curK, bestK);
    if better then
    begin
      bestK := curK;
      Result := cur;
    end;
  end;
end;

function callable(const v: Variant): Boolean;
var o: TObject; cls: PClassRTTI;
begin
  callable := PyVarIsCallable(v);
  if callable then Exit;
  { ...and an INSTANCE of a class that declares __call__, which Python calls
    callable too. PyVarIsCallable answers from the variant TAG alone, and such
    an instance is an ordinary VT_OBJECT — indistinguishable there from a plain
    object, so the question has to be asked of its class. }
  if pyvartag(v) <> 7 then Exit;
  if PPyVarRec(@v)^.Payload = 0 then Exit;
  o := TObject(Pointer(NativeInt(PPyVarRec(@v)^.Payload)));
  if (o is TPyList) or (o is TPyDict) or (o is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  callable := PyFindDunder(cls, '__call__') <> nil;
end;

function PyMinMaxNoneKey(const a: Variant; const b: Variant): Boolean;
{ `min(xs, key=None)` — CPython DEFINES key=None as "no key function", so it is
  the documented default and passing it explicitly is ordinary, most often when
  an optional key is threaded through a helper's own `key=None` parameter.

  It lands on the two-argument NUMERIC overload for exactly the reason a
  callable key did (see PyMinMaxByKey above): the value is variant-typed, so
  `b: Variant` matches exactly while the intended `key: Pointer` candidate needs
  a coercion applied only after a proc is chosen. The numeric compare then
  raised "expected a number, got object", comparing the LIST against None.

  Same escape as the callable case, and the same argument justifies it:
  comparing None with a container is a TypeError in CPython too, so a None
  second argument beside a SEQUENCE can only ever have meant the key form. A
  program CPython accepts cannot observe the difference — `min(x, None)` is
  rejected there — so answering it is laxity in the direction this dialect
  takes deliberately, not a silently wrong answer.
  Restricted to a SEQUENCE first argument on purpose: `min(3, None)` keeps
  raising, because that one really is a comparison someone wrote by mistake.
  bug-nilpy-builtin-surface-gaps-found-by-the-2026-08-12-sweep item 1 }
var o: TObject;
begin
  PyMinMaxNoneKey := False;
  if pyvartag(b) <> 0 then Exit;          { not None }
  if pyvartag(a) = 6 then begin PyMinMaxNoneKey := True; Exit; end;   { a str }
  if pyvartag(a) <> 7 then Exit;
  if PPyVarRec(@a)^.Payload = 0 then Exit;
  o := TObject(Pointer(NativeInt(PPyVarRec(@a)^.Payload)));
  { the same set pylist_v accepts — a DICT and a BYTES are containers too, and
    `min(d, key=None)` is ordinary Python }
  PyMinMaxNoneKey := (o is TPyList) or (o is TPyIter) or (o is TPyRange) or
                     (o is TPyDict) or (o is TPyBytes);
end;

function min(const a: Variant; const b: Variant): Variant; overload;
begin
  if PyVarIsCallable(b) then begin Result := PyMinMaxByKey(a, b, False); Exit; end;
  if PyMinMaxNoneKey(a, b) then begin Result := min(a); Exit; end;
  if pyvar_lt(b, a) then Result := b else Result := a;
end;

function max(const a: Variant; const b: Variant): Variant; overload;
begin
  if PyVarIsCallable(b) then begin Result := PyMinMaxByKey(a, b, True); Exit; end;
  if PyMinMaxNoneKey(a, b) then begin Result := max(a); Exit; end;
  if pyvar_gt(b, a) then Result := b else Result := a;
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
begin
  Result := decode(encoding, 'strict');
end;

function TPyBytes.decode(const encoding: AnsiString; const errors: AnsiString): AnsiString; overload;
var code, eh, k, n, seqLen: Integer; p: PByte; cp, lead, trail: Int64;
    bswap: Boolean;

  function ByteAt(idx: Integer): Int64;
  var q: PByte;
  begin
    q := PByte(NativeInt(FData) + idx);
    ByteAt := q^;
  end;

  procedure BadInput(const what: AnsiString; at: Integer);
  begin
    if eh = 0 then
      raise UnicodeDecodeError.Create(
        what + ' codec cannot decode byte at position ' + pystr_of(Int64(at)) +
        ': invalid data');
  end;

begin
  code := PyEncCode(encoding);
  PyEncRequire(encoding, code);
  eh := PyErrCode(errors);
  Result := '';

  if code = PYENC_LATIN1 then
  begin
    { every byte is its own code point — the one encoding that cannot fail }
    for k := 0 to FLen - 1 do PyCpToUtf8(Result, ByteAt(k));
    Exit;
  end;

  if code = PYENC_ASCII then
  begin
    for k := 0 to FLen - 1 do
    begin
      cp := ByteAt(k);
      if cp > $7F then
      begin
        BadInput('ascii', k);
        if eh = 2 then Continue;
        cp := $FFFD;
      end;
      PyCpToUtf8(Result, cp);
    end;
    Exit;
  end;

  if code = PYENC_UTF8 then
  begin
    { The internal form IS utf-8, so a VALID input is a byte-for-byte copy —
      but it must be VALIDATED now, because strict decode is exactly what
      encoding-sniffing code relies on to reject a wrong guess. Substituting
      U+FFFD unconditionally, as this used to, made every guess look right. }
    k := 0;
    while k < FLen do
    begin
      cp := ByteAt(k);
      if cp < $80 then seqLen := 0
      else if (cp and $E0) = $C0 then begin seqLen := 1; cp := cp and $1F; end
      else if (cp and $F0) = $E0 then begin seqLen := 2; cp := cp and $0F; end
      else if (cp and $F8) = $F0 then begin seqLen := 3; cp := cp and $07; end
      else seqLen := -1;
      if (seqLen < 0) or (k + seqLen >= FLen) then
      begin
        BadInput('utf-8', k);
        Inc(k);
        if eh = 2 then Continue;
        PyCpToUtf8(Result, $FFFD);
        Continue;
      end;
      for n := 1 to seqLen do
      begin
        if (ByteAt(k + n) and $C0) <> $80 then begin seqLen := -1; Break; end;
        cp := (cp shl 6) or (ByteAt(k + n) and $3F);
      end;
      if seqLen < 0 then
      begin
        BadInput('utf-8', k);
        Inc(k);
        if eh = 2 then Continue;
        PyCpToUtf8(Result, $FFFD);
        Continue;
      end;
      PyCpToUtf8(Result, cp);
      k := k + seqLen + 1;
    end;
    Exit;
  end;

  if (code = PYENC_UTF16LE) or (code = PYENC_UTF16BE) or (code = PYENC_UTF16) then
  begin
    k := 0;
    bswap := (code = PYENC_UTF16BE);
    if code = PYENC_UTF16 then
    begin
      { honour a BOM; CPython's bare `utf-16` defaults to LE without one }
      if (FLen >= 2) and (ByteAt(0) = $FF) and (ByteAt(1) = $FE) then k := 2
      else if (FLen >= 2) and (ByteAt(0) = $FE) and (ByteAt(1) = $FF) then
      begin k := 2; bswap := True; end;
    end;
    while k + 1 < FLen do
    begin
      if bswap then lead := (ByteAt(k) shl 8) or ByteAt(k + 1)
      else lead := ByteAt(k) or (ByteAt(k + 1) shl 8);
      k := k + 2;
      if (lead >= $D800) and (lead <= $DBFF) then
      begin
        if k + 1 >= FLen then begin BadInput('utf-16', k); Break; end;
        if bswap then trail := (ByteAt(k) shl 8) or ByteAt(k + 1)
        else trail := ByteAt(k) or (ByteAt(k + 1) shl 8);
        k := k + 2;
        lead := $10000 + ((lead - $D800) shl 10) + (trail - $DC00);
      end;
      PyCpToUtf8(Result, lead);
    end;
    if k < FLen then BadInput('utf-16', k);
    Exit;
  end;

  { utf-32 }
  k := 0;
  bswap := (code = PYENC_UTF32BE);
  if code = PYENC_UTF32 then
  begin
    if (FLen >= 4) and (ByteAt(0) = $FF) and (ByteAt(1) = $FE) and
       (ByteAt(2) = 0) and (ByteAt(3) = 0) then k := 4
    else if (FLen >= 4) and (ByteAt(0) = 0) and (ByteAt(1) = 0) and
            (ByteAt(2) = $FE) and (ByteAt(3) = $FF) then
    begin k := 4; bswap := True; end;
  end;
  while k + 3 < FLen do
  begin
    if bswap then
      cp := (ByteAt(k) shl 24) or (ByteAt(k + 1) shl 16) or
            (ByteAt(k + 2) shl 8) or ByteAt(k + 3)
    else
      cp := ByteAt(k) or (ByteAt(k + 1) shl 8) or
            (ByteAt(k + 2) shl 16) or (ByteAt(k + 3) shl 24);
    k := k + 4;
    PyCpToUtf8(Result, cp);
  end;
  if k < FLen then BadInput('utf-32', k);
end;

function bytearray: TPyBytes; overload;
begin
  Result := TPyBytes.Create(0);
  Result.FIsByteArray := True;
end;

function bytearray(n: Integer): TPyBytes; overload;
begin
  Result := TPyBytes.Create(n);
  Result.FIsByteArray := True;
end;

function bytearray(b: TPyBytes): TPyBytes; overload;
var i: Integer;
begin
  if b = nil then
  begin
    Result := TPyBytes.Create(0);
    Result.FIsByteArray := True;
    Exit;
  end;
  Result := TPyBytes.Create(b.FLen);
  Result.FIsByteArray := True;
  for i := 0 to b.FLen - 1 do Result.put(i, b.at(i));
end;

function bytearray(l: TPyList): TPyBytes; overload;
var i: Integer; v: Int64;
begin
  if l = nil then
  begin
    Result := TPyBytes.Create(0);
    Result.FIsByteArray := True;
    Exit;
  end;
  Result := TPyBytes.Create(l.count);
  Result.FIsByteArray := True;
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
var i, j, k, cnt, p, b0, b1: Integer; r: AnsiString;
begin
  cnt := PySliceBoundsStep(PyStrCharLen(s), lo, hi, step);
  { SetLength once and index, never `Result := Result + ch` — that idiom is
    QUADRATIC here (project_pxx_string_concat_in_loop_is_quadratic). }
  if pystr_isascii(s) then
  begin
    SetLength(Result, cnt);
    i := lo;
    for k := 1 to cnt do
    begin
      Result[k] := s[i + 1];      { Python is 0-based, Pascal strings 1-based }
      i := i + step;
    end;
    Exit;
  end;
  { A character is at most 4 bytes, so one allocation covers the worst case and
    the trim at the end is what makes it exact. }
  SetLength(r, cnt * 4);
  p := 0;
  i := lo;
  for k := 1 to cnt do
  begin
    b0 := PyStrByteOfChar(s, i);
    b1 := PyStrByteOfChar(s, i + 1);
    for j := b0 to b1 - 1 do begin Inc(p); r[p] := s[j]; end;
    i := i + step;
  end;
  SetLength(r, p);
  Result := r;
end;

function pybytes_slice_step(b: TPyBytes; lo, hi, step: Integer): TPyBytes;
var i, k, cnt: Integer; src, dst: PByte;
begin
  cnt := PySliceBoundsStep(b.FLen, lo, hi, step);
  Result := TPyBytes.Create(cnt);
  if b <> nil then Result.FIsByteArray := b.FIsByteArray;   { see pybytes_slice }
  i := lo;
  for k := 0 to cnt - 1 do
  begin
    src := PByte(NativeInt(b.FData) + i);
    dst := PByte(NativeInt(Result.FData) + k);
    dst^ := src^;
    i := i + step;
  end;
end;


{ ===== Codecs: str.encode / bytes.decode HONOUR their encoding argument =====

  Both used to ignore it and always do UTF-8 — a byte-for-byte copy in each
  direction — so `"hé".encode("latin-1")` returned 3 UTF-8 bytes where CPython
  gives 2, `encode("ascii")` silently succeeded on non-ASCII, and `decode` never
  raised. It LOOKS right on ASCII, which is why it survived: every encoding
  agrees there, and most test strings are ASCII.

  Internally a NilPy str is UTF-8, so both directions go through code points:
  decode the source to code points, encode them to the target. That is also what
  makes ONE place decide what an encoding name means, so a future codecs.lookup
  can delegate here instead of becoming a second mechanism that disagrees.

  An unknown encoding RAISES LookupError by name. Returning UTF-8 bytes labelled
  big5 is a wrong answer; refusing is a missing feature.
  bug-n-str-encode-and-bytes-decode-ignore-the-encoding }

const
  PYENC_UNKNOWN  = 0;
  PYENC_UTF8     = 1;
  PYENC_ASCII    = 2;
  PYENC_LATIN1   = 3;
  PYENC_UTF16LE  = 4;
  PYENC_UTF16BE  = 5;
  PYENC_UTF32LE  = 6;
  PYENC_UTF32BE  = 7;
  PYENC_UTF16    = 8;   { BOM: emits one on encode, honours one on decode }
  PYENC_UTF32    = 9;

{ Normalise the way CPython does: case-insensitive, and '-'/'_'/' ' are all the
  same separator, so 'UTF_8', 'utf-8' and 'Utf 8' are one encoding. }
function PyEncNormalize(const enc: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  Result := '';
  for i := 1 to Length(enc) do
  begin
    c := enc[i];
    if (c = '_') or (c = ' ') then c := '-'
    else if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    Result := Result + c;
  end;
end;

function PyEncCode(const enc: AnsiString): Integer;
var n: AnsiString;
begin
  n := PyEncNormalize(enc);
  if (n = 'utf-8') or (n = 'utf8') or (n = 'u8') then PyEncCode := PYENC_UTF8
  else if (n = 'ascii') or (n = 'us-ascii') or (n = '646') then PyEncCode := PYENC_ASCII
  else if (n = 'latin-1') or (n = 'latin1') or (n = 'iso-8859-1') or
          (n = 'iso8859-1') or (n = '8859') or (n = 'cp819') or
          (n = 'latin') or (n = 'l1') then PyEncCode := PYENC_LATIN1
  else if (n = 'utf-16le') or (n = 'utf16le') then PyEncCode := PYENC_UTF16LE
  else if (n = 'utf-16be') or (n = 'utf16be') then PyEncCode := PYENC_UTF16BE
  else if (n = 'utf-32le') or (n = 'utf32le') then PyEncCode := PYENC_UTF32LE
  else if (n = 'utf-32be') or (n = 'utf32be') then PyEncCode := PYENC_UTF32BE
  else if (n = 'utf-16') or (n = 'utf16') or (n = 'u16') then PyEncCode := PYENC_UTF16
  else if (n = 'utf-32') or (n = 'utf32') or (n = 'u32') then PyEncCode := PYENC_UTF32
  else PyEncCode := PYENC_UNKNOWN;
end;

procedure PyEncRequire(const enc: AnsiString; code: Integer);
begin
  if code = PYENC_UNKNOWN then
    raise LookupError.Create('unknown encoding: ' + enc);
end;

{ errors=: 0 strict (raise), 1 replace, 2 ignore. Anything else is a
  LookupError in CPython too. }
function PyErrCode(const errors: AnsiString): Integer;
var n: AnsiString;
begin
  n := PyEncNormalize(errors);
  if (n = '') or (n = 'strict') then PyErrCode := 0
  else if n = 'replace' then PyErrCode := 1
  else if n = 'ignore' then PyErrCode := 2
  else raise LookupError.Create('unknown error handler name ' + errors);
end;

{ Append one code point to an internal (UTF-8) NilPy string. }
procedure PyCpToUtf8(var out_: AnsiString; cp: Int64);
begin
  if cp < $80 then
    out_ := out_ + Chr(cp)
  else if cp < $800 then
  begin
    out_ := out_ + Chr($C0 or (cp shr 6));
    out_ := out_ + Chr($80 or (cp and $3F));
  end
  else if cp < $10000 then
  begin
    out_ := out_ + Chr($E0 or (cp shr 12));
    out_ := out_ + Chr($80 or ((cp shr 6) and $3F));
    out_ := out_ + Chr($80 or (cp and $3F));
  end
  else
  begin
    out_ := out_ + Chr($F0 or (cp shr 18));
    out_ := out_ + Chr($80 or ((cp shr 12) and $3F));
    out_ := out_ + Chr($80 or ((cp shr 6) and $3F));
    out_ := out_ + Chr($80 or (cp and $3F));
  end;
end;

{ Read the code point starting at 1-based byte i of an internal UTF-8 string;
  advances i past it. A malformed byte yields itself, which is what the rest of
  this unit's UTF-8 walkers already do — the internal form is our own output, so
  this is a robustness path, not a decoder. }
function PyUtf8CpAt(const s: AnsiString; var i: Integer): Int64;
var b, n, k, cp: Int64;
begin
  b := Ord(s[i]);
  if b < $80 then begin Inc(i); PyUtf8CpAt := b; Exit; end;
  if (b and $E0) = $C0 then begin n := 1; cp := b and $1F; end
  else if (b and $F0) = $E0 then begin n := 2; cp := b and $0F; end
  else if (b and $F8) = $F0 then begin n := 3; cp := b and $07; end
  else begin Inc(i); PyUtf8CpAt := b; Exit; end;
  if i + n > Length(s) then begin Inc(i); PyUtf8CpAt := b; Exit; end;
  for k := 1 to n do
    cp := (cp shl 6) or (Ord(s[i + k]) and $3F);
  i := i + Integer(n) + 1;
  PyUtf8CpAt := cp;
end;

procedure PyBytesPut(b: TPyBytes; var at: Integer; v: Int64);
var p: PByte;
begin
  p := PByte(NativeInt(b.FData) + at);
  p^ := Byte(v and $FF);
  Inc(at);
end;

function pystr_encode(const s: AnsiString): TPyBytes;
var k: Integer; p: PByte;
begin
  { the no-argument form is utf-8, and the internal representation IS utf-8, so
    this stays the byte-for-byte copy it always was }
  Result := TPyBytes.Create(Length(s));
  for k := 1 to Length(s) do
  begin
    p := PByte(NativeInt(Result.FData) + (k - 1));
    p^ := Ord(s[k]);
  end;
end;

function pystr_encode_enc(const s: AnsiString; const enc: AnsiString): TPyBytes;
begin
  Result := pystr_encode_enc_err(s, enc, 'strict');
end;

function pystr_encode_enc_err(const s: AnsiString; const enc: AnsiString;
                              const errors: AnsiString): TPyBytes;
var code, eh, i, at, wide: Integer; cp: Int64; outp: AnsiString; nb: Integer;
begin
  code := PyEncCode(enc);
  PyEncRequire(enc, code);
  eh := PyErrCode(errors);
  if code = PYENC_UTF8 then begin Result := pystr_encode(s); Exit; end;

  { Walk code points once, building the target bytes in an AnsiString (the
    length is not known up front for the variable-width targets), then copy in.
    A BOM-bearing form emits its BOM first, as CPython's utf-16/utf-32 do. }
  outp := '';
  if code = PYENC_UTF16 then outp := outp + Chr($FF) + Chr($FE)
  else if code = PYENC_UTF32 then
    outp := outp + Chr($FF) + Chr($FE) + Chr(0) + Chr(0);
  i := 1;
  while i <= Length(s) do
  begin
    cp := PyUtf8CpAt(s, i);
    if (code = PYENC_ASCII) and (cp > $7F) then
    begin
      if eh = 0 then
        raise UnicodeEncodeError.Create(
          'ascii codec cannot encode character ' + pystr_of(cp) +
          ': ordinal not in range(128)');
      if eh = 2 then Continue;
      cp := Ord('?');
    end
    else if (code = PYENC_LATIN1) and (cp > $FF) then
    begin
      if eh = 0 then
        raise UnicodeEncodeError.Create(
          'latin-1 codec cannot encode character ' + pystr_of(cp) +
          ': ordinal not in range(256)');
      if eh = 2 then Continue;
      cp := Ord('?');
    end;
    if (code = PYENC_ASCII) or (code = PYENC_LATIN1) then
      outp := outp + Chr(cp and $FF)
    else if (code = PYENC_UTF32LE) or (code = PYENC_UTF32) then
      outp := outp + Chr(cp and $FF) + Chr((cp shr 8) and $FF) +
                     Chr((cp shr 16) and $FF) + Chr((cp shr 24) and $FF)
    else if code = PYENC_UTF32BE then
      outp := outp + Chr((cp shr 24) and $FF) + Chr((cp shr 16) and $FF) +
                     Chr((cp shr 8) and $FF) + Chr(cp and $FF)
    else
    begin
      { utf-16: a code point above the BMP becomes a surrogate PAIR }
      if cp > $FFFF then
      begin
        cp := cp - $10000;
        wide := $D800 or Integer((cp shr 10) and $3FF);
        if code = PYENC_UTF16BE then
          outp := outp + Chr((wide shr 8) and $FF) + Chr(wide and $FF)
        else
          outp := outp + Chr(wide and $FF) + Chr((wide shr 8) and $FF);
        cp := $DC00 or (cp and $3FF);
      end;
      if code = PYENC_UTF16BE then
        outp := outp + Chr((cp shr 8) and $FF) + Chr(cp and $FF)
      else
        outp := outp + Chr(cp and $FF) + Chr((cp shr 8) and $FF);
    end;
  end;

  nb := Length(outp);
  Result := TPyBytes.Create(nb);
  at := 0;
  for i := 1 to nb do PyBytesPut(Result, at, Ord(outp[i]));
end;

function pystr_slice(const s: AnsiString; lo, hi: Integer): AnsiString;
var b0, b1: Integer;
begin
  PySliceBounds(PyStrCharLen(s), lo, hi);
  { Copy is 1-based and takes a COUNT; Python's bounds are 0-based CHARACTERS,
    so both ends go through the character->byte map. strip, split, partition,
    count(a,b), startswith(a,b) and the find/rfind windows all compose on this
    one function, which is why they need no change of their own. }
  b0 := PyStrByteOfChar(s, lo);
  b1 := PyStrByteOfChar(s, hi);
  Result := Copy(s, b0, b1 - b0);
end;

function pybytes_slice(b: TPyBytes; lo, hi: Integer): TPyBytes;
var k: Integer; src, dst: PByte;
begin
  PySliceBounds(b.FLen, lo, hi);
  Result := TPyBytes.Create(hi - lo);
  { a slice of a bytearray is a BYTEARRAY, of bytes is bytes — the tag has to
    travel with every operation that builds a new buffer from an old one, or it
    is lost at the first slice. bug-nilpy-bytearray-and-bytes-are-the-same-type }
  if b <> nil then Result.FIsByteArray := b.FIsByteArray;
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


procedure pyvar_setslice(const dst: Variant; lo, hi: Integer; const src: Variant);
var d, o: TObject;
begin
  if pyvartag(dst) <> 7 then
    raise TypeError.Create('object does not support slice assignment');
  d := TObject(pyvarobj(dst));
  if d is TPyBytes then
  begin
    { the RHS may be a bytes OBJECT or a variant carrying one — pybytes_setslice_v
      already answers that question, so ask it rather than repeating the test }
    pybytes_setslice_v(TPyBytes(d), lo, hi, src);
    Exit;
  end;
  if d is TPyList then
  begin
    if pyvartag(src) = 7 then
    begin
      o := TObject(pyvarobj(src));
      if o is TPyList then begin pylist_setslice(TPyList(d), lo, hi, TPyList(o)); Exit; end;
    end;
    raise TypeError.Create('can only assign an iterable to a list slice');
  end;
  raise TypeError.Create('object does not support slice assignment');
end;

{ Little-endian, two's complement — the same layout the machine already uses,
  so the loop is a plain byte peel rather than anything arithmetic. Python
  raises OverflowError when the value does not fit in n bytes; that check is
  kept, because uforth stores fixed-width Forth cells and a silent truncation
  there would corrupt the data space rather than fail. }
{ The binary digits of a heap-tier promotable int's MAGNITUDE, no '0b' prefix
  and no sign. PXXPromoToBase spells it Python's way ('0b1010', '-0b1010'), so
  the digits are simply everything after the 'b' — counting '0'/'1' characters
  instead would also count the prefix's own leading '0'. }
function PromoMagBits(const v: Variant): AnsiString;
var pslot: array[0..1] of NativeInt;
    s: AnsiString;
    i: Integer;
begin
  PXXPromoInit(@pslot);
  PXXPromoFromVariant(@pslot, @v);
  s := PXXPromoToBase(@pslot, 2);
  PXXPromoClear(@pslot);
  for i := 1 to Length(s) do
    if (s[i] = 'b') or (s[i] = 'B') then
    begin
      PromoMagBits := Copy(s, i + 1, Length(s) - i);
      Exit;
    end;
  PromoMagBits := s;   { no prefix seen — take it as already bare }
end;

{ Is this variant a heap-tier promotable int, i.e. a value that may be outside
  Int64 and must not be read through pyvar_to_int? }
function VarIsPromo(const v: Variant): Boolean;
begin
  VarIsPromo := PPyVarRec(@v)^.VType = 8193;
end;

function pyint_bit_length(const v: Variant): Int64;
var m: Int64; n: Integer; s: AnsiString;
begin
  if VarIsPromo(v) then
  begin
    s := PromoMagBits(v);
    { PXXPromoToBase renders zero as '0b0'; bit_length(0) is 0, not 1. A
      heap-tier promo is never zero in practice, but the guard costs nothing
      and keeps the two paths agreeing. }
    if (Length(s) = 1) and (s[1] = '0') then pyint_bit_length := 0
    else pyint_bit_length := Length(s);
    Exit;
  end;
  m := pyvar_to_int(v);
  { Low(Int64) has no positive counterpart, so negating it overflows. Its
    magnitude is 2^63, whose bit_length is 64. }
  if m = Low(Int64) then begin pyint_bit_length := 64; Exit; end;
  if m < 0 then m := -m;
  n := 0;
  while m <> 0 do begin Inc(n); m := m shr 1; end;
  pyint_bit_length := n;
end;

function pyint_bit_count(const v: Variant): Int64;
var m: Int64; n, i: Integer; s: AnsiString;
begin
  if VarIsPromo(v) then
  begin
    s := PromoMagBits(v);
    n := 0;
    for i := 1 to Length(s) do
      if s[i] = '1' then Inc(n);
    pyint_bit_count := n;
    Exit;
  end;
  m := pyvar_to_int(v);
  { see pyint_bit_length: 2^63 has exactly one set bit. }
  if m = Low(Int64) then begin pyint_bit_count := 1; Exit; end;
  if m < 0 then m := -m;
  n := 0;
  while m <> 0 do
  begin
    if (m and 1) <> 0 then Inc(n);
    m := m shr 1;
  end;
  pyint_bit_count := n;
end;

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

function pybytes_reversed(b: TPyBytes): TPyBytes;
var k, n: Integer; src, dst: PByte;
begin
  if b = nil then n := 0 else n := b.FLen;
  Result := TPyBytes.Create(n);
  if b <> nil then Result.FIsByteArray := b.FIsByteArray;
  for k := 0 to n - 1 do
  begin
    src := PByte(NativeInt(b.FData) + k);
    dst := PByte(NativeInt(Result.FData) + (n - 1 - k));
    dst^ := src^;
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
function pyround_v(const x: Variant; n: Int64): Variant;
{ The variant twin: an int-tagged value (int, bool, or an arbitrary-precision
  int) keeps its intness, a float rounds as a float. Reached whenever the
  argument's static type is a variant or a promo int — a list element, an
  unannotated parameter, `2 ** 70`. }
var t: Int64;
begin
  t := pyvartag(x);
  { arbitrary precision: a non-negative ndigits cannot change it, and flattening
    it to a double to "round" it is what lost 2**70 entirely }
  if t >= 8192 then
  begin
    if n >= 0 then pyround_v := x
    else
      raise TypeError.Create('round() of an arbitrary-precision int with a '
        + 'negative ndigits is not supported yet');
    Exit;
  end;
  if (t = 1) or (t = 2) or (t = 4) then         { int / int64 / bool }
    pyround_v := pyvar_of_int(pyround_int(pyvar_to_int(x), n))
  else
    pyround_v := pyround_n(pyvar_to_float(x), Integer(n));
end;

function pyround1_v(const x: Variant): Variant;
var t: Int64; d, fl: Double; iv: Int64;
begin
  t := pyvartag(x);
  if (t >= 8192) or (t = 1) or (t = 2) then begin pyround1_v := x; Exit; end;
  if t = 4 then begin pyround1_v := pyvar_of_int(pyvar_to_int(x)); Exit; end;
  d := pyvar_to_float(x);
  iv := Trunc(d);
  if (d < 0) and (d <> iv) then iv := iv - 1;     { floor, not truncation }
  fl := iv;
  d := d - fl;
  { half-to-EVEN, which is what Python rounds with: 2.5 -> 2, 3.5 -> 4 }
  if (d > 0.5) or ((d = 0.5) and ((iv and 1) = 1)) then iv := iv + 1;
  pyround1_v := pyvar_of_int(iv);
end;

function pyround_int(x: Int64; n: Int64): Int64;
{ CPython's `round(int, ndigits)`: an int in, an int out, whatever ndigits is.
  A non-negative ndigits cannot change an integer, so it is the identity; a
  NEGATIVE one really does round — `round(1234, -2)` is 1200, an INT, and pxx
  answered 1200.0. Banker's rounding at the half, as CPython does.
  bug-nilpy-two-argument-round-of-an-int-returns-a-float }
var p, half, r, q: Int64; i: Integer; neg: Boolean;
begin
  if n >= 0 then begin pyround_int := x; Exit; end;
  p := 1;
  for i := 1 to -n do
  begin
    { past 19 zeros every int64 rounds to 0 — stop rather than overflow p }
    if p > 922337203685477580 then begin pyround_int := 0; Exit; end;
    p := p * 10;
  end;
  neg := x < 0;
  if neg then x := -x;
  q := x div p;
  r := x - q * p;
  half := p div 2;
  if (r > half) or ((r = half) and ((q and 1) = 1)) then q := q + 1;
  pyround_int := q * p;
  if neg then pyround_int := -pyround_int;
end;

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

{ ---- float's own methods ------------------------------------------------
  A `float` carried NONE of them: not is_integer, not hex, not
  as_integer_ratio, not conjugate. `x.is_integer()` in particular is ordinary
  modern Python and is what a library reaches for instead of `x == int(x)` —
  and it did not fail at COMPILE time, it built a call to None and raised
  "object is not callable" at run time, which is worse.
  bug-a-bytes-has-almost-none-of-its-python-methods }

function pyfloat_is_integer(x: Double): Boolean;
begin
  { Infinity and NaN are not integral, and Int() of either is not either — but
    Int(inf) = inf compares equal to inf, so the class has to be excluded
    explicitly rather than left to the comparison. }
  Result := False;
  if x <> x then Exit;                                  { NaN }
  if (x > 1.7e308) or (x < -1.7e308) then Exit;         { +-inf }
  Result := Int(x) = x;
end;

function pyfloat_conjugate(x: Double): Double;
{ A real number is its own conjugate. Present because CPython's float has it
  (the numeric tower's `complex` interface), and a library that walks that
  interface calls it on real values. }
begin
  Result := x;
end;

function PyHexDigitOf(v: Int64): Char;
begin
  if v < 10 then PyHexDigitOf := Chr(48 + v) else PyHexDigitOf := Chr(87 + v);
end;

function pyfloat_hex(x: Double): AnsiString;
{ CPython's float.hex(): the EXACT value, `[-]0x1.<13 hex digits>p<+|->exp`.
  Exact because a double's mantissa is 52 bits = 13 hex digits with nothing
  left over, which is the whole point of the format — it round-trips where
  decimal does not.

  Three shapes, from the exponent field:
    2047        -> 'inf' / '-inf' / 'nan' (CPython prints these unprefixed)
    0, mant 0   -> '0x0.0p+0' — the ONE case with a single fraction digit
    0, mant<>0  -> subnormal: leading digit 0 and the exponent PINNED at -1022,
                   not the -1023 the raw field would suggest
    otherwise   -> leading digit 1, exponent = field - 1023
  No trailing-zero stripping: (2.0).hex() is '0x1.0000000000000p+1'. }
var bits, expo, mant, e, d: Int64; neg: Boolean; k: Integer; lead: Char;
begin
  bits := PyExDecDoubleToBits(x);
  neg := bits < 0;
  expo := (bits shr 52) and 2047;
  mant := bits and $000FFFFFFFFFFFFF;
  if expo = 2047 then
  begin
    if mant <> 0 then begin Result := 'nan'; Exit; end;
    if neg then Result := '-inf' else Result := 'inf';
    Exit;
  end;
  if (expo = 0) and (mant = 0) then
  begin
    if neg then Result := '-0x0.0p+0' else Result := '0x0.0p+0';
    Exit;
  end;
  if expo = 0 then begin lead := '0'; e := -1022; end
  else begin lead := '1'; e := expo - 1023; end;
  Result := '';
  if neg then Result := '-';
  Result := Result + '0x' + lead + '.';
  for k := 12 downto 0 do
  begin
    d := (mant shr (k * 4)) and 15;
    Result := Result + PyHexDigitOf(d);
  end;
  Result := Result + 'p';
  if e < 0 then begin Result := Result + '-'; e := -e; end
  else Result := Result + '+';
  Result := Result + pystr_of(e);
end;

function pyfloat_as_integer_ratio(x: Double): TPyList;
{ The EXACT rational the double stands for, in lowest terms — the denominator
  is always a power of two, so "lowest terms" just means shifting until the
  numerator is odd.

  NilPy's ints are 64-bit, and CPython's are not, so a value whose exact
  numerator does not fit — |x| >= 2^63, and every subnormal, whose denominator
  is 2^1074 — RAISES rather than answering a truncated pair. A silently wrong
  ratio is the outcome worth avoiding here; the range that does fit is exactly
  the range NilPy's ints describe anyway. }
var num, den, bits, expo, mant: Int64; neg: Boolean;
begin
  bits := PyExDecDoubleToBits(x);
  neg := bits < 0;
  expo := (bits shr 52) and 2047;
  mant := bits and $000FFFFFFFFFFFFF;
  if expo = 2047 then
  begin
    if mant <> 0 then
      raise ValueError.Create('cannot convert NaN to integer ratio');
    raise OverflowError.Create('cannot convert Infinity to integer ratio');
  end;
  if (expo = 0) and (mant = 0) then
  begin
    Result := TPyList.Create;
    Result.FKind := PYSEQ_TUPLE;
    Result.append(Int64(0));
    Result.append(Int64(1));
    Exit;
  end;
  if expo = 0 then
    raise OverflowError.Create(
      'as_integer_ratio: a subnormal needs a denominator of 2^1074, which does'
      + ' not fit a 64-bit int');
  { value = (2^52 + mant) * 2^(expo-1023-52) }
  num := Int64($0010000000000000) + mant;
  expo := expo - 1023 - 52;
  den := 1;
  { shift the numerator UP while the exponent is positive — overflowing here is
    exactly the |x| >= 2^63 case }
  while expo > 0 do
  begin
    if num > $3FFFFFFFFFFFFFFF then
      raise OverflowError.Create(
        'as_integer_ratio: the exact numerator does not fit a 64-bit int');
    num := num * 2;
    expo := expo - 1;
  end;
  { ...and reduce: a trailing zero bit in the numerator halves both sides }
  while (expo < 0) and ((num and 1) = 0) do
  begin
    num := num div 2;
    expo := expo + 1;
  end;
  while expo < 0 do
  begin
    if den > $3FFFFFFFFFFFFFFF then
      raise OverflowError.Create(
        'as_integer_ratio: the exact denominator does not fit a 64-bit int');
    den := den * 2;
    expo := expo + 1;
  end;
  if neg then num := -num;
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  Result.append(num);
  Result.append(den);
end;

{ int's three. Trivial by definition — an int IS an integer, its complex
  conjugate is itself, and its exact ratio is n/1 — but they have to exist as
  entry points because the frontend intercepts the NAME, and because their
  results are int-flavoured where float's are not. }
function pyint_is_integer(x: Int64): Boolean;
begin
  Result := True;
end;

function pyint_conjugate(x: Int64): Int64;
begin
  Result := x;
end;

function pyint_as_integer_ratio(x: Int64): TPyList;
begin
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  Result.append(x);
  Result.append(Int64(1));
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

constructor KeyError.Create(const m: Variant);
var kargs: TPyList;
begin
  { `KeyError()` with no argument at all: the frontend fills an unsupplied
    variant slot with None (an empty variant is the only addressable "not
    supplied" this dialect has), and CPython's str(KeyError()) is the empty
    string, not 'None'. So an empty tag means the no-argument form — and
    argsv is left nil, so GetArgs derives `()` the way it does for every other
    empty exception. The cost is that an EXPLICIT `KeyError(None)` renders as
    '' rather than 'None'; the no-argument spelling is much the commoner, and
    this is the same call already made for `ValueError('')`. }
  if pyvartag(m) = 0 then
  begin
    { pass `m` ITSELF, not '': the base now stores args, and an empty STRING is
      a real one-element tuple ('',) while an empty TAG is the no-argument form
      whose args CPython gives as (). Handing down a literal '' turned
      `KeyError()` into `('',)`. }
    inherited Create(m);
    Exit;
  end;
  { The base stores the REPR'D text it was handed; KeyError's args must be the
    RAW key (CPython's KeyError is the one builtin whose str() is the repr of
    its argument). Reuse the tuple the base just built instead of allocating a
    second one over it. }
  inherited Create(pyvar_repr(m));
  if argsv = nil then
  begin
    kargs := TPyList.Create;
    kargs.FKind := PYSEQ_TUPLE;
    argsv := kargs;
  end
  else
  begin
    kargs := TPyList(argsv);
    kargs.clear;
  end;
  kargs.append(m);
end;

constructor KeyError.CreateRendered(const shown: AnsiString);
begin
  inherited Create(shown);
end;

function pyexc_tuplemsg(t: TPyList): AnsiString;
begin
  { CPython's str(e) for a multi-argument exception IS repr(args) — `('no such
    user', 404)` — which is exactly what a PYSEQ_TUPLE list reprs as, so this
    reuses the one renderer rather than growing a second one that can drift. }
  Result := pylist_repr(t);
end;

function pyexc_setargs(e: TObject; t: TPyList): TObject;
begin
  { argsv is the untyped root slot (see exceptions.pas): pylib is the only code
    that stores into it, and this is one of the two places that does. Returns
    the exception so the frontend can WRAP the construction in it and keep the
    whole thing one expression — there is no statement position between
    building the object and raising it. }
  Result := e;
  if e = nil then Exit;
  ExceptionBase(e).argsv := t;
end;

function Exception.GetArgs: TPyList;
begin
  if argsv <> nil then
  begin
    Result := TPyList(argsv);
    Exit;
  end;
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  if Length(msg) > 0 then Result.append(msg);
end;

constructor Exception.Create(const m: Variant);
var cargs: TPyList;
begin
  { An EMPTY tag is the no-argument form — the frontend fills an unsupplied
    variant slot with None, which is the only addressable "not supplied" this
    dialect has. Leave msg '' and argsv nil, and GetArgs derives `()`; the same
    call KeyError.Create already makes. }
  if pyvartag(m) = 0 then Exit;
  msg := pyexc_msgstr(m);
  cargs := TPyList.Create;
  cargs.FKind := PYSEQ_TUPLE;
  cargs.append(m);
  argsv := cargs;
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

{ A CreateFmt of pylib's own. It cannot simply call Format(): pylib is pulled
  into every .npy and must not depend on sysutils (which is what drags the whole
  RTL in), so the substitution is done here over the same
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

function pyos_path_split(const p: AnsiString): TPyList;
begin
  Result := TPyList.Create;
  Result.FKind := PYSEQ_TUPLE;
  Result.append(pyos_path_dirname(p));
  Result.append(pyos_path_basename(p));
end;

function pyos_path_normpath(const p: AnsiString): AnsiString;
var parts: array[0..255] of AnsiString; n, i, st: Integer;
    seg: AnsiString; absPath: Boolean;
begin
  if p = '' then begin Result := '.'; Exit; end;
  absPath := p[1] = '/';
  n := 0; st := 1;
  for i := 1 to Length(p) + 1 do
    if (i > Length(p)) or (p[i] = '/') then
    begin
      seg := Copy(p, st, i - st);
      st := i + 1;
      if (seg = '') or (seg = '.') then Continue;
      if seg = '..' then
      begin
        { pop, except past the root of an ABSOLUTE path (where '..' is the root
          itself) and except a leading run of '..' in a RELATIVE one, which
          cannot be collapsed without knowing the cwd }
        if (n > 0) and (parts[n - 1] <> '..') then Dec(n)
        else if not absPath then
        begin
          if n <= High(parts) then begin parts[n] := seg; Inc(n); end;
        end;
        Continue;
      end;
      if n <= High(parts) then begin parts[n] := seg; Inc(n); end;
    end;
  Result := '';
  for i := 0 to n - 1 do
  begin
    if Result <> '' then Result := Result + '/';
    Result := Result + parts[i];
  end;
  if absPath then Result := '/' + Result
  else if Result = '' then Result := '.';
end;

function pyos_path_getsize(const p: AnsiString): Int64;
var stx: TPyStat;
begin
  stx := pyos_stat(p);          { raises FileNotFoundError when absent }
  Result := stx.st_size;
end;

function pyos_path_expanduser(const p: AnsiString): AnsiString;
var home: Variant; hs: AnsiString;
begin
  Result := p;
  if p = '' then Exit;
  if p[1] <> '~' then Exit;
  { only a bare '~' or '~/...' — '~user' needs a passwd lookup this has no PAL
    entry for, and CPython also returns it unchanged when it cannot resolve. }
  if (Length(p) > 1) and (p[2] <> '/') then Exit;
  home := pyos_getenv('HOME');
  if pyvartag(home) <> 6 then Exit;         { unset: unchanged, as CPython does }
  hs := PyVarText(PPyVarRec(@home));
  if hs = '' then Exit;
  if Length(p) = 1 then Result := hs
  else Result := hs + Copy(p, 2, Length(p) - 1);
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
var i, j, k, p, n: Integer; r: AnsiString;
begin
  n := Length(s);
  if pystr_isascii(s) then
  begin
    SetLength(r, n);
    for i := 1 to n do r[i] := s[n + 1 - i];
    pystr_reverse := r;
    Exit;
  end;
  { `s[::-1]` reverses CHARACTERS, not bytes — reversing bytes is what produced
    malformed UTF-8 on stdout, the worst row of this ticket's defect table.
    Walk backwards to each character's LEAD byte and copy the character
    forwards, which is O(n) and needs no offset map. }
  SetLength(r, n);
  p := 0;
  i := n;
  while i >= 1 do
  begin
    j := i;
    while (j > 1) and ((Ord(s[j]) and $C0) = $80) do Dec(j);
    for k := j to i do begin Inc(p); r[p] := s[k]; end;
    i := j - 1;
  end;
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

{ Every failed file syscall in CPython raises an OSError SUBCLASS chosen by
  errno, and its str() is `[Errno N] <strerror>: '<path>'` — with `-> '<dst>'`
  appended for the two-path calls. Both halves are load-bearing:

  - the CLASS, because `except FileNotFoundError:` and `except PermissionError:`
    are how real code tells "not there" from "not allowed", and answering
    FileNotFoundError for every failure makes the second one silently take the
    first's branch;
  - the MESSAGE, because it is what a program PRINTS. Found by the uforth
    corpus, which is diffed against CPython byte for byte: a missing include
    printed the bare path where CPython prints the whole sentence.

  __pxxrawsyscall hands back the raw kernel return, so a failure is -errno and
  the mapping is direct. An errno with no dedicated class is a plain OSError,
  which is also what CPython does.
  bug-nilpy-a-failed-file-syscall-loses-both-its-class-and-its-message }
procedure pyos_raise_ioerror(err: Int64; const path: AnsiString; const path2: AnsiString);
var e: Int64; txt, msg: AnsiString;
begin
  e := err;
  if e < 0 then e := -e;
  if e = 2 then txt := 'No such file or directory'
  else if e = 13 then txt := 'Permission denied'
  else if e = 17 then txt := 'File exists'
  else if e = 20 then txt := 'Not a directory'
  else if e = 21 then txt := 'Is a directory'
  else if e = 4 then txt := 'Interrupted system call'
  else if e = 9 then txt := 'Bad file descriptor'
  else txt := 'OS error';
  msg := '[Errno ' + StrInt(e, 0) + '] ' + txt + ': ''' + path + '''';
  if path2 <> '' then msg := msg + ' -> ''' + path2 + '''';
  if e = 2 then raise FileNotFoundError.Create(msg);
  if e = 13 then raise PermissionError.Create(msg);
  if e = 17 then raise FileExistsError.Create(msg);
  if e = 20 then raise NotADirectoryError.Create(msg);
  if e = 21 then raise IsADirectoryError.Create(msg);
  if e = 4 then raise InterruptedError.Create(msg);
  raise OSError.Create(msg);
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
    pyos_raise_ioerror(r, path, '');
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
    pyos_raise_ioerror(r, src, dst);
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
    pyos_raise_ioerror(r, path, '');
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

{ ======================= cursors (TPyIter) ==============================
  See TPyIter's declaration for the model and for why the protocol is two
  calls (has/take) rather than one. }

constructor TPyIter.Create;
begin
  { first construction installs the recursive finalizer, exactly as TPyList's
    does — a cursor can be the first pylib object a program builds }
  PXXObjFinalizeHook := @PyObjFinalize;
  FBox := TPyList.Create;
  { the one prefetch slot, allocated once. Spelled `pynone()` WITH parens: a
    bare parameterless function name used as an ARGUMENT reads as a variable in
    the Pascal expression parser and fails with "undefined variable (pynone)" —
    which only shows up when a .pas program `uses pylib` directly, never on the
    NilPy path. The `Result := pynone` assignment form below is fine. }
  FBox.append(pynone());
  PXXObjRetain(Pointer(FBox));
  FPos := 0;
  FStart := 0;
  FHas := False;
  FEnd := False;
  FIsGen := False;
end;

function pyiter_of_list(l: TPyList): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_LIST;
  Result.FSrc := l;
  PXXObjRetain(Pointer(l));
end;

function pyiter_of_str(const s: AnsiString): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_STR;
  Result.FStr := s;
end;

function pyiter_gen(l: TPyList): TPyIter;
begin
  Result := pyiter_of_list(l);
  Result.FIsGen := True;
end;

function pyiter_rev_list(l: TPyList): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_REV;
  Result.FSrc := l;
  PXXObjRetain(Pointer(l));
  { CPython's list_reverseiterator holds a DESCENDING index seeded at
    len(seq) - 1 when it is built, so a list that grows afterwards is not
    re-walked from its new end. }
  if l = nil then Result.FPos := -1 else Result.FPos := l.count - 1;
end;

function pyiter_rev_str(const s: AnsiString): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_REVSTR;
  Result.FStr := s;
  Result.FPos := Length(s);      { 1-based, walked down to 1 }
end;

function pyiter_is(const v: Variant): Boolean;
var o: TObject;
begin
  Result := False;
  if pyvartag(v) <> 7 then Exit;
  o := TObject(pyvarobj(v));
  Result := o is TPyIter;
end;

function pyiter_v(const v: Variant): TPyIter;
var o: TObject;
begin
  if pyvartag(v) = 6 then begin Result := pyiter_of_str(VariantToStr(v)); Exit; end;
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    { iter() of an ITERATOR is that same iterator in CPython — idempotent, and
      relied on by every `for` that calls iter() on whatever it was given. }
    if o is TPyIter then begin Result := TPyIter(o); Exit; end;
    if o is TPyList then begin Result := pyiter_of_list(TPyList(o)); Exit; end;
    { a dict iterates its KEYS, as `for k in d` and `list(d)` both do }
    if o is TPyDict then begin Result := pyiter_of_list(TPyDict(o).keylist); Exit; end;
    if o is TPyBytes then begin Result := pyiter_of_list(list(TPyBytes(o))); Exit; end;
    if o is TPyFile then begin Result := pyiter_of_list(TPyFile(o).readlines); Exit; end;
    { a RANGE hands back a FRESH cursor every time — that is what re-iterable
      means, and it is why range is not itself a cursor }
    if o is TPyRange then begin Result := pyiter_of_range(TPyRange(o)); Exit; end;
    { a USER class implementing the iterator protocol. Here rather than only in
      the `for` lowering, so iter(), list(), sorted(), sum(), `in` and a
      tuple-unpack all reach it too — one site, every consumer.
      bug-nilpy-iterator-protocol-on-a-user-class }
    if PyUserObjHasDunder(o, '__iter__') then
    begin
      Result := pyiter_of_userobj(o);
      Exit;
    end;
  end;
  PyTypeError(pyvartag(v), 'an iterable');
  Result := pyiter_of_list(TPyList.Create);
end;

function pyiter_enum(const v: Variant; start: Int64): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_ENUM;
  Result.FUp := pyiter_v(v);
  PXXObjRetain(Pointer(Result.FUp));
  Result.FStart := start;
end;

function pyiter_enum_i(up: TPyIter; start: Int64): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_ENUM;
  Result.FUp := up;
  PXXObjRetain(Pointer(up));
  Result.FStart := start;
end;

function pyiter_zip_ii(a: TPyIter; b: TPyIter): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_ZIP;
  Result.FUp := a;
  PXXObjRetain(Pointer(a));
  Result.FUp2 := b;
  PXXObjRetain(Pointer(b));
end;

function pyiter_zip_iii(a: TPyIter; b: TPyIter; c: TPyIter): TPyIter;
begin
  Result := pyiter_zip_ii(a, b);
  Result.FUp3 := c;
  PXXObjRetain(Pointer(c));
end;

function pyiter_zip_iiii(a: TPyIter; b: TPyIter; c: TPyIter; d: TPyIter): TPyIter;
begin
  Result := pyiter_zip_iii(a, b, c);
  Result.FUp4 := d;
  PXXObjRetain(Pointer(d));
end;

function pyiter_zip_n(items: TPyList): TPyIter;
var i, n: Integer; cur: TPyIter; pv: Variant;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_ZIPN;
  Result.FSrc := TPyList.Create;
  PXXObjRetain(Pointer(Result.FSrc));
  n := 0;
  if items <> nil then n := len(items);
  i := 0;
  while i < n do
  begin
    { pyiter_v is the one iterable-to-cursor conversion, so a row that is itself
      a str/range/dict/user object works without a per-shape arm here. }
    cur := pyiter_v(items.at(i));
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(cur)));
    PXXObjRetain(Pointer(cur));
    Result.FSrc.append(pv);
    Inc(i);
  end;
end;

function pyiter_zip(const a: Variant; const b: Variant): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_ZIP;
  Result.FUp := pyiter_v(a);
  PXXObjRetain(Pointer(Result.FUp));
  Result.FUp2 := pyiter_v(b);
  PXXObjRetain(Pointer(Result.FUp2));
end;

function pyiter_map(key: Pointer; const v: Variant): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_MAP;
  Result.FUp := pyiter_v(v);
  PXXObjRetain(Pointer(Result.FUp));
  Result.FKey := key;
  PXXObjRetain(key);     { a lifted lambda / bound pair is refcounted; a bare
                           code address no-ops }
end;

function pyiter_map_conv(conv: Int64; const v: Variant): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_MAP;
  Result.FUp := pyiter_v(v);
  PXXObjRetain(Pointer(Result.FUp));
  Result.FKey := nil;        { no callable — the code in FStart says what to do }
  Result.FStart := conv;
end;

function pyiter_map_i(key: Pointer; up: TPyIter): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_MAP;
  Result.FUp := up;
  PXXObjRetain(Pointer(up));
  Result.FKey := key;
  PXXObjRetain(key);
end;

function pyiter_filter_i(key: Pointer; up: TPyIter): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_FILTER;
  Result.FUp := up;
  PXXObjRetain(Pointer(up));
  Result.FKey := key;
  PXXObjRetain(key);
end;

function pyiter_map_conv_i(conv: Int64; up: TPyIter): TPyIter;
begin
  Result := pyiter_map_i(nil, up);
  Result.FStart := conv;
end;

function pyiter_filter(key: Pointer; const v: Variant): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_FILTER;
  Result.FUp := pyiter_v(v);
  PXXObjRetain(Pointer(Result.FUp));
  Result.FKey := key;    { nil is filter(None, xs) — Python's own shorthand }
  PXXObjRetain(key);
end;

{ Prefetch ONE value into FBox. Idempotent: calling it twice without an
  intervening take() does not advance, which is what lets it sit in a while
  CONDITION. Every source is consulted LIVE — a list that grows during the
  loop is seen, exactly as the eager index loop saw it. }
function pyiter_has(it: TPyIter): Boolean;
var l: TPyList; pair: TPyList; ev, mv: Variant; pv: Variant; kept: Boolean;
    zc: TPyIter; zi, zn: Integer;   { the N-way zip's cursor walk }
    b0, b1: Integer;                { the str cursors' UTF-8 character span }
begin
  Result := False;
  if it = nil then Exit;
  if it.FHas then begin Result := True; Exit; end;
  { exhaustion is PERMANENT — a CPython iterator never restarts, and this is
    what makes a second pass over a bound cursor yield the remainder }
  if it.FEnd then Exit;
  if it.FKind = PYITER_LIST then
  begin
    l := it.FSrc;
    if (l = nil) or (it.FPos >= l.count) then begin it.FEnd := True; Exit; end;
    it.FBox.put(0, l.at(it.FPos));
    Inc(it.FPos);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_STR then
  begin
    { FPos stays a BYTE cursor and steps over a whole UTF-8 character, so this
      yields what `for c in s` and `list(s)` yield — one CHARACTER — instead of
      one byte, and stays linear (a character-index cursor would rescan the
      string per step, which is how string work here goes quadratic).
      bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
    if it.FPos >= Length(it.FStr) then begin it.FEnd := True; Exit; end;
    b0 := it.FPos + 1;
    b1 := b0 + 1;
    while (b1 <= Length(it.FStr)) and ((Ord(it.FStr[b1]) and $C0) = $80) do Inc(b1);
    it.FBox.put(0, Copy(it.FStr, b0, b1 - b0));
    it.FPos := b1 - 1;
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_REV then
  begin
    l := it.FSrc;
    if (l = nil) or (it.FPos < 0) then begin it.FEnd := True; Exit; end;
    { a shrunk list must not be indexed past its end }
    if it.FPos >= l.count then it.FPos := l.count - 1;
    if it.FPos < 0 then begin it.FEnd := True; Exit; end;
    it.FBox.put(0, l.at(it.FPos));
    Dec(it.FPos);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_REVSTR then
  begin
    { …and backwards, over the same character span: `reversed("aÃ©â¢z")` handed
      back the bytes of the multi-byte characters one at a time. }
    if it.FPos < 1 then begin it.FEnd := True; Exit; end;
    b1 := it.FPos;
    b0 := b1;
    while (b0 > 1) and ((Ord(it.FStr[b0]) and $C0) = $80) do Dec(b0);
    it.FBox.put(0, Copy(it.FStr, b0, b1 - b0 + 1));
    it.FPos := b0 - 1;
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_MAP then
  begin
    if not pyiter_has(it.FUp) then begin it.FEnd := True; Exit; end;
    ev := pyiter_take(it.FUp);
    if it.FKey = nil then
    begin
      { a CONVERSION map — see pyiter_map_conv. int()/float() PARSE a str, as
        CPython's do, which is the whole reason map(int, s.split(...)) works. }
      if it.FStart = 1 then
      begin
        if pyvartag(ev) = 6 then mv := pystr_to_int(pystr_of(ev))
        else mv := pyvar_to_int(ev);
      end
      else if it.FStart = 2 then mv := pystr_of(ev)
      else if it.FStart = 3 then
      begin
        if pyvartag(ev) = 6 then mv := pyfloat_parse(pystr_of(ev))
        else mv := pyvar_to_float(ev);
      end
      else mv := ev;
    end
    else
    begin
      if PyIterCallHook = nil then
        raise TypeError.Create('map(): callable dispatch is unavailable');
      mv := PyIterCallHook(it.FKey, ev);
    end;
    it.FBox.put(0, mv);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_FILTER then
  begin
    while pyiter_has(it.FUp) do
    begin
      ev := pyiter_take(it.FUp);
      if it.FKey = nil then kept := pyvar_to_bool(ev)
      else
      begin
        if PyIterCallHook = nil then
          raise TypeError.Create('filter(): callable dispatch is unavailable');
        kept := pyvar_to_bool(PyIterCallHook(it.FKey, ev));
      end;
      if kept then
      begin
        it.FBox.put(0, ev);
        it.FHas := True;
        Result := True;
        Exit;
      end;
    end;
    it.FEnd := True;
    Exit;
  end;
  if it.FKind = PYITER_ENUM then
  begin
    if not pyiter_has(it.FUp) then begin it.FEnd := True; Exit; end;
    ev := pyiter_take(it.FUp);
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;      { enumerate() yields (index, value) tuples }
    pair.append(it.FStart + it.FPos);
    pair.append(ev);
    Inc(it.FPos);
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    it.FBox.put(0, pv);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_USEROBJ then
  begin
    { the user iterator protocol: `__next__` per step, terminating on
      StopIteration. The exception is caught HERE and never reaches the loop —
      which is exactly what CPython's `for` does with it, and why the signal
      cannot simply propagate. Any OTHER exception is the user's and propagates
      untouched, so a raise inside `__next__` still escapes the loop.
      bug-nilpy-iterator-protocol-on-a-user-class }
    try
      if not PyUserObjNoArgDunder(it.FObj, '__next__', pv) then
      begin
        it.FEnd := True;
        Exit;
      end;
    except
      on E: StopIteration do
      begin
        it.FEnd := True;
        Exit;
      end;
    end;
    it.FBox.put(0, pv);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_RANGE then
  begin
    if it.FPos <= 0 then begin it.FEnd := True; Exit; end;
    it.FBox.put(0, it.FStart);
    it.FStart := it.FStart + it.FStep;
    Dec(it.FPos);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_ZIPN then
  begin
    { Same shortest-wins rule and same left-to-right consumption order as the
      fixed forms: each stream is asked in turn and the first exhausted one ends
      the zip, having already consumed the ones to its left. The tuple is built
      only once a stream has answered, so the ordinary end-of-zip step (stream 0
      exhausted) allocates nothing. }
    zn := 0;
    if it.FSrc <> nil then zn := len(it.FSrc);
    pair := nil;
    zi := 0;
    while zi < zn do
    begin
      zc := TPyIter(pyvarobj(it.FSrc.at(zi)));
      if not pyiter_has(zc) then begin it.FEnd := True; Exit; end;
      if pair = nil then
      begin
        pair := TPyList.Create;
        pair.FKind := PYSEQ_TUPLE;
      end;
      pair.append(pyiter_take(zc));
      Inc(zi);
    end;
    if pair = nil then begin it.FEnd := True; Exit; end;   { zip() of nothing }
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    it.FBox.put(0, pv);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  if it.FKind = PYITER_ZIP then
  begin
    { the LEFT element is consumed before the right is even asked for, which is
      CPython's order and is observable when the two sides have side effects }
    if not pyiter_has(it.FUp) then begin it.FEnd := True; Exit; end;
    ev := pyiter_take(it.FUp);
    if not pyiter_has(it.FUp2) then begin it.FEnd := True; Exit; end;
    pair := TPyList.Create;
    pair.FKind := PYSEQ_TUPLE;
    pair.append(ev);
    pair.append(pyiter_take(it.FUp2));
    { the third and fourth streams, when this is an N-way zip. Same
      shortest-wins rule: CPython stops at the first exhausted stream, having
      already consumed the ones to its left. }
    if it.FUp3 <> nil then
    begin
      if not pyiter_has(it.FUp3) then begin it.FEnd := True; Exit; end;
      pair.append(pyiter_take(it.FUp3));
      if it.FUp4 <> nil then
      begin
        if not pyiter_has(it.FUp4) then begin it.FEnd := True; Exit; end;
        pair.append(pyiter_take(it.FUp4));
      end;
    end;
    PPyVarRec(@pv)^.VType := 7;
    PPyVarRec(@pv)^.Payload := Int64(NativeInt(Pointer(pair)));
    PXXObjRetain(Pointer(pair));
    it.FBox.put(0, pv);
    it.FHas := True;
    Result := True;
    Exit;
  end;
  it.FEnd := True;
end;

function pyiter_take(it: TPyIter): Variant;
begin
  Result := pynone;
  if it = nil then Exit;
  if not it.FHas then
    if not pyiter_has(it) then Exit;
  Result := it.FBox.at(0);
  it.FHas := False;
end;

function pyiter_next(it: TPyIter): Variant;
begin
  Result := pynone;
  if (it = nil) or (not pyiter_has(it)) then
    raise StopIteration.Create('next() on an exhausted iterator');
  Result := pyiter_take(it);
end;

function pyiter_next_or(it: TPyIter; const dflt: Variant): Variant;
begin
  if (it = nil) or (not pyiter_has(it)) then begin Result := dflt; Exit; end;
  Result := pyiter_take(it);
end;

function pyiter_drain(it: TPyIter): TPyList;
begin
  Result := TPyList.Create;
  if it = nil then Exit;
  while pyiter_has(it) do
    Result.append(pyiter_take(it));
end;

function pystar_as_list(const v: Variant): TPyList;
var o: TObject;
begin
  { a list (or a tuple, which is the same object) is handed straight back —
    the packing only READS it, so a copy would be pure cost }
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin pystar_as_list := TPyList(o); Exit; end;
  end;
  pystar_as_list := pyiter_drain(pyiter_v(v));
end;

function pystar_iterable(l: TPyList): TPyList;
begin
  pystar_iterable := l;
  if (l <> nil) and (l.count = 1) then
    { ONE starred element: the star supplies it as the sole argument, so the
      comparison runs over ITS contents. pystar_as_list, not a cast — the
      element may be a str (`max(*["abc"])` is CPython's max("abc") = 'c'),
      a dict, or any other iterable. }
    pystar_iterable := pystar_as_list(l.at(0));
end;

procedure pystar_check_min(l: TPyList; lo: Integer; const fname: AnsiString;
                           const pnames: AnsiString);
var n, miss, i, j, start, shown: Integer;
    names: AnsiString; msg: AnsiString; one: AnsiString;
begin
  n := 0;
  if l <> nil then n := l.count;
  if n >= lo then Exit;
  miss := lo - n;
  { CPython names them: "g() missing 1 required positional argument: 'x'" and
    "h() missing 2 required positional arguments: 'a' and 'b'". pnames is the
    required slots' names in order, '|'-separated, so the missing ones are the
    tail from index n. }
  names := '';
  shown := 0;
  start := 1;
  j := 0;
  for i := 1 to Length(pnames) + 1 do
    if (i > Length(pnames)) or (pnames[i] = '|') then
    begin
      if j >= n then
      begin
        one := '''' + Copy(pnames, start, i - start) + '''';
        if shown = 0 then names := one
        else if j = lo - 1 then names := names + ' and ' + one
        else names := names + ', ' + one;
        Inc(shown);
      end;
      Inc(j);
      start := i + 1;
    end;
  if miss = 1 then msg := fname + '() missing 1 required positional argument'
  else msg := fname + '() missing ' + pystr_of(Int64(miss)) +
              ' required positional arguments';
  if names <> '' then msg := msg + ': ' + names;
  raise TypeError.Create(msg);
end;

function pystar_has1(l: TPyList; i: Integer): Boolean;
begin
  pystar_has1 := (l <> nil) and (i >= 0) and (i < l.count);
end;

constructor TPyRange.Create;
begin
  PXXObjFinalizeHook := @PyObjFinalize;
  FStart := 0;
  FStop := 0;
  FStep := 1;
end;

function TPyRange.at(i: Int64): Int64;
begin
  Result := pyrange_at(Self, i);
end;

function pyrange3(start: Int64; stop: Int64; step: Int64): TPyRange; overload;
begin
  if step = 0 then
    raise ValueError.Create('range() arg 3 must not be zero');
  Result := TPyRange.Create;
  Result.FStart := start;
  Result.FStop := stop;
  Result.FStep := step;
end;

function pyrange1(stop: Int64): TPyRange;
begin
  Result := pyrange3(0, stop, 1);
end;

function pyrange2(start: Int64; stop: Int64): TPyRange; overload;
begin
  Result := pyrange3(start, stop, 1);
end;

function pyrange_len(r: TPyRange): Int64;
var span, st: Int64;
begin
  Result := 0;
  if r = nil then Exit;
  if r.FStep > 0 then
  begin
    if r.FStop <= r.FStart then Exit;
    span := r.FStop - r.FStart;
    st := r.FStep;
  end
  else
  begin
    if r.FStop >= r.FStart then Exit;
    span := r.FStart - r.FStop;
    st := -r.FStep;
  end;
  { ceil(span / st) without floating point — the last value is start + (n-1)*step }
  Result := (span + st - 1) div st;
end;

function pyrange_at(r: TPyRange; i: Int64): Int64;
var n: Int64;
begin
  n := pyrange_len(r);
  if i < 0 then i := i + n;      { Python counts back from the end }
  if (i < 0) or (i >= n) then
    raise IndexError.Create('range object index out of range');
  Result := r.FStart + i * r.FStep;
end;

function pyrange_contains(r: TPyRange; const v: Variant): Boolean;
var x, off: Int64; t: Int64;
begin
  Result := False;
  if r = nil then Exit;
  t := pyvartag(v);
  { CPython falls back to iterating for a non-number, which answers False for
    anything a range cannot hold. A FLOAT that happens to be integral IS a
    member (`2.0 in range(3)` is True), so it is converted and compared, not
    rejected. }
  if (t <> 1) and (t <> 2) and (t <> 3) and (t <> 4) then Exit;
  if t = 4 then
  begin
    { a float: only an exact integer value can be in a range }
    if pyvar_to_float(v) <> Int64(Trunc(pyvar_to_float(v))) then Exit;
  end;
  x := pyvar_to_int(v);
  off := x - r.FStart;
  { in range, on the grid, and on the right side — one modulo, no scan }
  if r.FStep > 0 then
  begin
    if (x < r.FStart) or (x >= r.FStop) then Exit;
  end
  else
  begin
    if (x > r.FStart) or (x <= r.FStop) then Exit;
  end;
  Result := (off mod r.FStep) = 0;
end;

function pyrange_slice(r: TPyRange; lo: Int64; hi: Int64; step: Int64): TPyRange;
var n, a, b: Int64;
begin
  n := pyrange_len(r);
  if step = 0 then raise ValueError.Create('slice step cannot be zero');
  { normalise the bounds against the range's LENGTH, exactly as a list slice
    does, then map them back onto the underlying arithmetic }
  a := lo;
  b := hi;
  if a = PY_SLICE_OMIT then begin if step > 0 then a := 0 else a := n - 1; end
  else
  begin
    if a < 0 then a := a + n;
    if a < 0 then begin if step > 0 then a := 0 else a := -1; end;
    if a > n then begin if step > 0 then a := n else a := n - 1; end;
    if (a = n) and (step < 0) then a := n - 1;
  end;
  if b = PY_SLICE_OMIT then begin if step > 0 then b := n else b := -1; end
  else
  begin
    if b < 0 then b := b + n;
    if b < -1 then b := -1;
    if b > n then b := n;
  end;
  Result := pyrange3(r.FStart + a * r.FStep,
                     r.FStart + b * r.FStep,
                     r.FStep * step);
end;

function pyrange_eq(a: TPyRange; b: TPyRange): Boolean;
var na, nb: Int64;
begin
  Result := False;
  if (a = nil) or (b = nil) then Exit;
  na := pyrange_len(a);
  nb := pyrange_len(b);
  if na <> nb then Exit;
  { an EMPTY range equals every other empty one whatever its bounds, and a
    one-element range ignores the step — CPython compares the SEQUENCE }
  if na = 0 then begin Result := True; Exit; end;
  if a.FStart <> b.FStart then Exit;
  if na = 1 then begin Result := True; Exit; end;
  Result := a.FStep = b.FStep;
end;

function pyrange_repr(r: TPyRange): AnsiString;
begin
  if r = nil then begin Result := 'None'; Exit; end;
  { CPython always prints start and stop, and the step only when it is not 1 }
  Result := 'range(' + pystr_of(r.FStart) + ', ' + pystr_of(r.FStop);
  if r.FStep <> 1 then Result := Result + ', ' + pystr_of(r.FStep);
  Result := Result + ')';
end;

{ `for x in obj` over a USER class that implements the iterator protocol.
  CPython calls `__iter__` once and then `__next__` per step; so does this. The
  object `__iter__` answers is what gets stepped — the ordinary `return self`
  makes that the source itself, and a class returning a separate iterator object
  works for free.

  A class with `__iter__` whose result has no `__next__` is CPython's TypeError,
  raised here with CPython's own wording rather than answered as an empty
  sequence. bug-nilpy-iterator-protocol-on-a-user-class }
function pyiter_of_userobj(o: TObject): TPyIter;
var itv: Variant; ito: TObject;
begin
  ito := o;
  if o <> nil then
    if PyUserObjNoArgDunder(o, '__iter__', itv) then
    begin
      if pyvartag(itv) = 7 then ito := TObject(pyvarobj(itv));
    end;
  { `def __iter__(self): return iter(self.items)` — the most common way to
    write __iter__ at all — hands back a pylib CURSOR, which IS an iterator.
    The __next__ probe below only recognises a USER class, so it refused with
    "iter() returned non-iterator of type 'TPyIter'": a correct CPython program
    rejected by the check that exists to catch an incorrect one.
    bug-nilpy-builtins-over-a-user-iterable-answer-empty }
  if (ito <> nil) and (ito is TPyIter) then
  begin
    Result := TPyIter(ito);
    Exit;
  end;
  Result := TPyIter.Create;
  Result.FKind := PYITER_USEROBJ;
  if o = nil then begin Result.FEnd := True; Exit; end;
  if not PyUserObjHasDunder(ito, '__next__') then
    raise TypeError.Create('iter() returned non-iterator of type ''' +
                           TObject(ito).ClassName + '''');
  Result.FObj := ito;
  PXXObjRetain(Pointer(ito));
end;

function pyiter_of_range(r: TPyRange): TPyIter;
begin
  Result := TPyIter.Create;
  Result.FKind := PYITER_RANGE;
  if r = nil then Exit;
  Result.FStart := r.FStart;
  Result.FStep := r.FStep;
  { the count is taken ONCE, here — a range is immutable, so unlike the list
    cursor there is nothing live to re-read }
  Result.FPos := Integer(pyrange_len(r));
end;

function pyrange_is(const v: Variant): Boolean;
var o: TObject;
begin
  Result := False;
  if pyvartag(v) <> 7 then Exit;
  o := TObject(pyvarobj(v));
  Result := o is TPyRange;
end;

function pyiter_typename(it: TPyIter): AnsiString;
begin
  Result := 'iterator';
  if it = nil then Exit;
  if it.FIsGen then begin Result := 'generator'; Exit; end;
  if it.FKind = PYITER_LIST then Result := 'list_iterator'
  else if it.FKind = PYITER_STR then Result := 'str_iterator'
  else if it.FKind = PYITER_REV then Result := 'list_reverseiterator'
  else if it.FKind = PYITER_REVSTR then Result := 'reversed'
  else if it.FKind = PYITER_MAP then Result := 'map'
  else if it.FKind = PYITER_FILTER then Result := 'filter'
  else if it.FKind = PYITER_ENUM then Result := 'enumerate'
  else if (it.FKind = PYITER_ZIP) or (it.FKind = PYITER_ZIPN) then Result := 'zip'
  else if it.FKind = PYITER_RANGE then Result := 'range_iterator';
end;

function pyiter_repr(it: TPyIter): AnsiString;
var a: NativeInt; d: Integer; hx: AnsiString;
begin
  if it = nil then begin Result := 'None'; Exit; end;
  a := NativeInt(Pointer(it));
  hx := '';
  if a = 0 then hx := '0';
  while a > 0 do
  begin
    d := a mod 16;
    if d < 10 then hx := Chr(Ord('0') + d) + hx
    else hx := Chr(Ord('a') + d - 10) + hx;
    a := a div 16;
  end;
  Result := '<' + pyiter_typename(it) + ' object at 0x' + hx + '>';
end;

function pyiter_no_len(it: TPyIter): Int64;
begin
  raise TypeError.Create('object of type ' + Chr(39) + pyiter_typename(it) +
                         Chr(39) + ' has no len()');
  Result := 0;   { unreachable }
end;

function sum(it: TPyIter): Variant; overload;
begin
  Result := sum(pyiter_drain(it));
end;

{ The RANGE consumers. Each drains a fresh cursor, so consuming a range does
  not consume the range — it stays re-iterable, which is the property that
  separates it from a cursor. }
function sum(r: TPyRange): Variant; overload;
begin
  Result := sum(pyiter_drain(pyiter_of_range(r)));
end;

function tuple(r: TPyRange): TPyList; overload;
begin
  Result := tuple(pyiter_drain(pyiter_of_range(r)));
end;

function any(r: TPyRange): Boolean; overload;
begin
  Result := any(pyiter_drain(pyiter_of_range(r)));
end;

function all(r: TPyRange): Boolean; overload;
begin
  Result := all(pyiter_drain(pyiter_of_range(r)));
end;

function list(r: TPyRange): TPyList; overload;
begin
  Result := pyiter_drain(pyiter_of_range(r));
end;

function len(r: TPyRange): Integer; overload;
begin
  Result := Integer(pyrange_len(r));
end;

function iter(r: TPyRange): TPyIter; overload;
begin
  Result := pyiter_of_range(r);
end;

function reversed(r: TPyRange): TPyIter; overload;
begin
  { CPython gives a range_iterator walking backwards. Built as the equivalent
    range rather than a materialised list, so reversed(range(10 ** 9)) is
    still three fields. }
  if pyrange_len(r) = 0 then Result := pyiter_of_range(pyrange3(0, 0, 1))
  else Result := pyiter_of_range(pyrange3(r.FStart + (pyrange_len(r) - 1) * r.FStep,
                                          r.FStart - r.FStep,
                                          -r.FStep));
end;

function sum(it: TPyIter; const start: Variant): Variant; overload;
begin
  Result := sum(pyiter_drain(it), start);
end;

function tuple(it: TPyIter): TPyList; overload;
begin
  Result := tuple(pyiter_drain(it));
end;

function any(it: TPyIter): Boolean; overload;
begin
  Result := any(pyiter_drain(it));
end;

function all(it: TPyIter): Boolean; overload;
begin
  Result := all(pyiter_drain(it));
end;

function sum(const v: Variant): Variant; overload;
begin
  Result := sum(pylist_v(v));
end;

function sum(const v: Variant; const start: Variant): Variant; overload;
begin
  Result := sum(pylist_v(v), start);
end;

function any(const v: Variant): Boolean; overload;
begin
  Result := any(pylist_v(v));
end;

function all(const v: Variant): Boolean; overload;
begin
  Result := all(pylist_v(v));
end;

type
  TPyBoundRec = record Code, Recv: Pointer; IsFunc: Boolean; StarIdx: Integer; end;
  PPyBoundRec = ^TPyBoundRec;

procedure PyObjFinalize(objp: Pointer; rawKind: NativeInt);
var
  k: Integer;
  l: TPyList;
  d: TPyDict;
  by: TPyBytes;
  it: TPyIter;
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
  { a CURSOR owns its source, its upstream(s) and its prefetch box — every one
    of them taken with an explicit PXXObjRetain in the constructor, because a
    cursor routinely outlives the expression that built its source
    (`for v in map(f, [1, 2, 3])` has nothing else holding that list). The
    stored callable is released too: a lifted lambda / bound pair is a
    refcounted block, and PXXObjRelease no-ops on a plain code address. }
  if o is TPyIter then
  begin
    it := TPyIter(objp);
    PXXObjRelease(Pointer(it.FSrc));
    PXXObjRelease(Pointer(it.FUp));
    PXXObjRelease(Pointer(it.FUp2));
    PXXObjRelease(Pointer(it.FUp3));
    PXXObjRelease(Pointer(it.FUp4));
    PXXObjRelease(Pointer(it.FBox));
    PXXObjRelease(Pointer(it.FObj));
    PXXObjRelease(it.FKey);
    it.FSrc := nil; it.FUp := nil; it.FUp2 := nil; it.FBox := nil; it.FKey := nil;
    it.FObj := nil;
    it.FUp3 := nil; it.FUp4 := nil;
    it.FStr := '';
    Exit;
  end;
  { user class / anything else: release managed + variant fields via the
    class layout descriptor walker (kind 5 = variant slots, which recurses
    back through PXXObjRelease for held containers) }
  PXXClassFinalize(objp);
end;

function pybound_new(code, recv: Pointer; isFunc: Boolean): Variant;
begin
  pybound_new := pybound_new_star(code, recv, isFunc, -1);
end;

function pybound_new_star(code, recv: Pointer; isFunc: Boolean;
                          starIdx: Int64): Variant;
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
  b^.StarIdx := Integer(starIdx);
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
  TPyCbM4 = function(recv: Pointer; const a0, a1, a2, a3: Variant): Variant;
  TPyCbF0 = function: Variant;
  TPyCbF1 = function(const a0: Variant): Variant;
  TPyCbF2 = function(const a0, a1: Variant): Variant;
  TPyCbF3 = function(const a0, a1, a2: Variant): Variant;
  TPyCbF4 = function(const a0, a1, a2, a3: Variant): Variant;
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
  TPyCbMP4 = procedure(recv: Pointer; const a0, a1, a2, a3: Variant);
  TPyCbFP0 = procedure;
  TPyCbFP1 = procedure(const a0: Variant);
  TPyCbFP2 = procedure(const a0, a1: Variant);
  TPyCbFP3 = procedure(const a0, a1, a2: Variant);
  TPyCbFP4 = procedure(const a0, a1, a2, a3: Variant);
  { A callee that COLLECTS. `def h(a, *rest)` compiles to one Variant parameter
    and ONE TPyList — the surplus arguments are packed by the CALL SITE
    (PyPackStarArgs), which a dynamic call through a function value has no
    chance to do. So the packing moves here, and the signature the callee
    really has gets its own family: fixed Variants up to the star position,
    then the list. `*args` keeps its container type even under the
    function-object ABI (PyDefUsedAsValue widens every OTHER parameter), which
    is what makes this shape predictable enough to declare. }
  TPyCbFS0 = function(l: TPyList): Variant;
  TPyCbFS1 = function(const a0: Variant; l: TPyList): Variant;
  TPyCbFS2 = function(const a0, a1: Variant; l: TPyList): Variant;
  TPyCbFS3 = function(const a0, a1, a2: Variant; l: TPyList): Variant;
  TPyCbFSP0 = procedure(l: TPyList);
  TPyCbFSP1 = procedure(const a0: Variant; l: TPyList);
  TPyCbFSP2 = procedure(const a0, a1: Variant; l: TPyList);
  TPyCbFSP3 = procedure(const a0, a1, a2: Variant; l: TPyList);
  TPyCbMS0 = function(recv: Pointer; l: TPyList): Variant;
  TPyCbMS1 = function(recv: Pointer; const a0: Variant; l: TPyList): Variant;
  TPyCbMS2 = function(recv: Pointer; const a0, a1: Variant; l: TPyList): Variant;
  TPyCbMS3 = function(recv: Pointer; const a0, a1, a2: Variant; l: TPyList): Variant;
  TPyCbMSP0 = procedure(recv: Pointer; l: TPyList);
  TPyCbMSP1 = procedure(recv: Pointer; const a0: Variant; l: TPyList);
  TPyCbMSP2 = procedure(recv: Pointer; const a0, a1: Variant; l: TPyList);
  TPyCbMSP3 = procedure(recv: Pointer; const a0, a1, a2: Variant; l: TPyList);

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

function pybound_star(const v: Variant): Integer;
begin
  pybound_star := PPyBoundRec(NativeInt(PPyVarRec(@v)^.Payload))^.StarIdx;
end;

function PyBoundCallStar(code, recv: Pointer; isFn: Boolean;
                         si, nargs: Integer;
                         const a0, a1, a2, a3: Variant): Variant;
{ The packing half of a dynamic call into a variadic callee. si is the callee's
  own `*args` position (Self already excluded), so arguments si..nargs-1 are the
  ones it never declared a slot for. They become the TUPLE the body sees — a
  tuple, not a list, exactly as PyPackStarArgs marks it at a written call site,
  or `print(args)` renders brackets and `type(args).__name__` answers 'list'. }
var star: TPyList; av: array[0..3] of Variant; i: Integer;
    fs0: TPyCbFS0; fs1: TPyCbFS1; fs2: TPyCbFS2; fs3: TPyCbFS3;
    ps0: TPyCbFSP0; ps1: TPyCbFSP1; ps2: TPyCbFSP2; ps3: TPyCbFSP3;
    ms0: TPyCbMS0; ms1: TPyCbMS1; ms2: TPyCbMS2; ms3: TPyCbMS3;
    qs0: TPyCbMSP0; qs1: TPyCbMSP1; qs2: TPyCbMSP2; qs3: TPyCbMSP3;
begin
  PyBoundCallStar := pynone;
  if (si < 0) or (si > 3) then
    raise TypeError.Create('calling a function value whose *args parameter is at '
      + 'position ' + pystr_of(Int64(si))
      + ' is past what the dynamic bridge can pack');
  av[0] := a0; av[1] := a1; av[2] := a2; av[3] := a3;
  star := TPyList.Create;
  for i := si to nargs - 1 do star.append(av[i]);
  pylist_mark_tuple(star);
  if recv = nil then
  begin
    if isFn then
      case si of
        0: begin fs0 := TPyCbFS0(code); PyBoundCallStar := fs0(star); end;
        1: begin fs1 := TPyCbFS1(code); PyBoundCallStar := fs1(av[0], star); end;
        2: begin fs2 := TPyCbFS2(code); PyBoundCallStar := fs2(av[0], av[1], star); end;
        3: begin fs3 := TPyCbFS3(code); PyBoundCallStar := fs3(av[0], av[1], av[2], star); end;
      end
    else
      case si of
        0: begin ps0 := TPyCbFSP0(code); ps0(star); end;
        1: begin ps1 := TPyCbFSP1(code); ps1(av[0], star); end;
        2: begin ps2 := TPyCbFSP2(code); ps2(av[0], av[1], star); end;
        3: begin ps3 := TPyCbFSP3(code); ps3(av[0], av[1], av[2], star); end;
      end;
  end
  else
  begin
    if isFn then
      case si of
        0: begin ms0 := TPyCbMS0(code); PyBoundCallStar := ms0(recv, star); end;
        1: begin ms1 := TPyCbMS1(code); PyBoundCallStar := ms1(recv, av[0], star); end;
        2: begin ms2 := TPyCbMS2(code); PyBoundCallStar := ms2(recv, av[0], av[1], star); end;
        3: begin ms3 := TPyCbMS3(code); PyBoundCallStar := ms3(recv, av[0], av[1], av[2], star); end;
      end
    else
      case si of
        0: begin qs0 := TPyCbMSP0(code); qs0(recv, star); end;
        1: begin qs1 := TPyCbMSP1(code); qs1(recv, av[0], star); end;
        2: begin qs2 := TPyCbMSP2(code); qs2(recv, av[0], av[1], star); end;
        3: begin qs3 := TPyCbMSP3(code); qs3(recv, av[0], av[1], av[2], star); end;
      end;
  end;
  { the temp's own +1, dropped like the hidden local a written call site gets:
    a body that KEEPS the tuple (returns it, stores it) has retained it by now }
  PXXObjRelease(Pointer(star));
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
  if pybound_star(cb) >= 0 then
  begin
    Result := PyBoundCallStar(code, recv, isFn, pybound_star(cb), 0,
                              pynone, pynone, pynone, pynone);
    Exit;
  end;
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
  if pybound_star(cb) >= 0 then
  begin
    Result := PyBoundCallStar(code, recv, isFn, pybound_star(cb), 1,
                              a0, pynone, pynone, pynone);
    Exit;
  end;
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
  if pybound_star(cb) >= 0 then
  begin
    Result := PyBoundCallStar(code, recv, isFn, pybound_star(cb), 2,
                              a0, a1, pynone, pynone);
    Exit;
  end;
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
  if pybound_star(cb) >= 0 then
  begin
    Result := PyBoundCallStar(code, recv, isFn, pybound_star(cb), 3,
                              a0, a1, a2, pynone);
    Exit;
  end;
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

function pybound_callv4(const cb: Variant; const a0, a1, a2, a3: Variant): Variant;
{ The FOUR-argument twin. `f = some_def` binds a callback pair (code + nil
  receiver) even for a plain def, so every dynamic call at this arity comes
  through here — and there was no arity-4 member, which is why the arity-4
  dispatcher had to exist at all.
  bug-nilpy-a-four-parameter-lambda-segfaults-when-called }
var code, recv: Pointer; m4: TPyCbM4; f4: TPyCbF4; mp4: TPyCbMP4; fp4: TPyCbFP4;
    isFn: Boolean;
begin
  Result := pynone;
  if not pycallback_is(cb) then Exit;
  code := pybound_code(cb);
  if code = nil then Exit;
  recv := pybound_recv(cb);
  isFn := pybound_isfunc(cb);
  if pybound_star(cb) >= 0 then
  begin
    Result := PyBoundCallStar(code, recv, isFn, pybound_star(cb), 4, a0, a1, a2, a3);
    Exit;
  end;
  if recv = nil then
  begin
    if isFn then begin f4 := TPyCbF4(code); Result := f4(a0, a1, a2, a3); end
    else begin fp4 := TPyCbFP4(code); fp4(a0, a1, a2, a3); Result := pynone; end;
  end
  else
  begin
    if isFn then begin m4 := TPyCbM4(code); Result := m4(recv, a0, a1, a2, a3); end
    else begin mp4 := TPyCbMP4(code); mp4(recv, a0, a1, a2, a3); Result := pynone; end;
  end;
end;

{ input(): read one line from stdin and drop the trailing newline, as Python's
  input() does. (A prompt argument is printed by the caller, then ignored here.)

  EOF RAISES EOFError, it does not return ''. This is what terminates the
  canonical `while True: line = input()` REPL — CPython's loop leaves through
  the exception, so returning '' forever turns the standard shape into an
  infinite busy-loop. uforth's repl() is exactly that shape and SPUN (state R,
  PC in PyPalPoll/PyPalRead) at the end of the Forth-2012 core.fr word set,
  whose ACCEPT test eats the trailing BYE and leaves stdin at EOF:
  regression-test-uforth-00. Output was byte-identical to CPython right up to
  the hang, which is why it read as a timeout rather than a wrong answer.

  '' and EOF are distinguishable HERE and nowhere above: pystdin_readline
  KEEPS the newline, so a blank line is #10 and only a true EOF is ''. The
  check therefore has to happen before the newline is stripped. }
function pyinput: AnsiString;
var raw: AnsiString;
begin
  raw := pystdin_readline;
  if raw = '' then
    raise EOFError.Create('EOF when reading a line');
  Result := raw;
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

function pysys_executable: AnsiString;
var buf: array[0..4095] of Char; n: Int64; i: Integer; p: AnsiString;
begin
  { /proc/self/exe is the kernel's own answer and needs no guessing. readlink
    does NOT null-terminate, so the length comes from the return value —
    reading to a NUL here would append whatever was on the stack. }
  p := '/proc/self/exe';
  n := PyPalReadlink(@p[1], @buf[0], 4096);
  if n > 0 then
  begin
    Result := '';
    for i := 0 to Integer(n) - 1 do Result := Result + buf[i];
    Exit;
  end;
  { no /proc (a bare target, or a chroot without it): argv[0] is all there is,
    and saying so plainly beats inventing a path. }
  Result := ParamStr(0);
end;

function pysys_file: AnsiString;
begin
  { __file__ for the MAIN module IS the executable, so os.path.exists(__file__)
    is True — which is the property that makes the freezer convention usable.
    It used to be raw ParamStr(0). }
  Result := pysys_executable;
end;

function pysys_module_file(const modBase: AnsiString): AnsiString;
var exe: AnsiString; i, cut: Integer;
begin
  exe := pysys_executable;
  cut := 0;
  for i := 1 to Length(exe) do
    if exe[i] = '/' then cut := i;
  if cut > 0 then Result := Copy(exe, 1, cut) + modBase
  else Result := modBase;
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

{ `open(path)` with no mode. Python's default mode IS "r", so this is now just
  the two-argument form — it used to slurp the file into a TPyList of lines
  instead, which is what made open() answer a different CLASS depending on the
  mode string and cost a data-losing .write dispatch when one name held both
  (bug-nilpy-open-returns-two-different-classes-by-mode). The read-slurp
  conveniences it existed for now live on TPyFile itself: read(), readlines(),
  and for-in over its lines.

  The missing-file behaviour is preserved deliberately: pyfile_open raises
  FileNotFoundError the same way, which test_nilpy_typeerror_is_catchable
  depends on catching. }
function pyopen(const path: AnsiString): TPyFile;
begin
  Result := pyfile_open(path, 'r');
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
  { CHARACTERS, not bytes — the same question `len(const s: AnsiString)` above
    answers with PyStrCharLen, and the LAST byte-flavoured `len` left in pylib.
    A str reaching len as a VARIANT is the ordinary shape of an UNANNOTATED
    parameter (`def f(s): return len(s)`), so `len` answered the UTF-8 byte
    count there while `s[i]` was still bounds-checked in characters — the
    canonical `while i < len(s): out += s[i]` scan then raised IndexError on any
    text with an accent, and a program that only asked len(s) got a plausible
    number silently too large.
    bug-nilpy-len-of-a-str-parameter-counts-bytes-not-characters }
  if (t = 5) or (t = 6) then begin Result := 777; Exit; end;
  if t = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := TPyList(o).count; Exit; end;
    if o is TPyDict then begin Result := TPyDict(o).count; Exit; end;
    if o is TPyBytes then begin Result := TPyBytes(o).count; Exit; end;
    { ...but a RANGE does have one, and cheaply: this is the line where the
      lazy-SEQUENCE / cursor distinction pays. }
    if o is TPyRange then begin Result := len(TPyRange(o)); Exit; end;
    { a cursor has no length — CPython's own answer, word for word, and the one
      row this change deliberately makes STRICTER. Allowed because CPython
      REJECTS the code, so no working CPython program can depend on it. }
    if o is TPyIter then
      raise TypeError.Create('object of type ' + Chr(39) +
        pyiter_typename(TPyIter(o)) + Chr(39) + ' has no len()');
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
    conv: Char;
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
      conv := ' ';
      while (j <= Length(fmt)) and (fmt[j] <> '}') and (fmt[j] <> ':') do
      begin fld := fld + fmt[j]; Inc(j); end;
      { A `!r` / `!s` CONVERSION is part of the field text as scanned above, so
        it used to end up in `fld`, make it non-numeric, and be silently
        DROPPED: `"{!r}".format("s")` printed s where Python prints 's'. Split
        it off before the field is interpreted — and note it also has to leave
        `fld` empty rather than the literal '!r', or the automatic index would
        be skipped. bug-nilpy-str-format-drops-the-r-conversion }
      if (Length(fld) = 2) and (fld[1] = '!') and
         ((fld[2] = 'r') or (fld[2] = 's')) then
      begin
        conv := fld[2];
        fld := '';
      end
      else if (Length(fld) > 2) and (fld[Length(fld) - 1] = '!') and
              ((fld[Length(fld)] = 'r') or (fld[Length(fld)] = 's')) then
      begin
        conv := fld[Length(fld)];
        fld := Copy(fld, 1, Length(fld) - 2);
      end;
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
      { pyvar_print_of, NOT pystr_of: pystr_of answers '' for a CONTAINER
        payload, so `"{}".format([1, 2])` produced an EMPTY string — silent, and
        the value vanished rather than looking wrong. pyvar_print_of is the same
        rendering print() uses, which is what str() means here. }
      if conv = 'r' then outS := outS + pyvar_repr(args.at(useIdx))
      else if spec = '' then outS := outS + pyvar_print_of(args.at(useIdx))
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
    outS, spec, mapKey: AnsiString;
    conv, signCh: Char;
    lst: TPyList;
    dct: TPyDict;
    hasMapKey: Boolean;
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
  { MAPPING form — `"%(k)s" % {...}`. The right-hand side is a dict and each
    placeholder names its key instead of consuming the next positional
    argument, which is why logging and templating code uses it: the format
    string can be reordered without touching the arguments.
    Previously `%(` reached the conversion switch as the character `(` and
    raised `unsupported format character "("`. }
  dct := nil;
  if PPyVarRec(@args)^.VType = 7 then
    if TObject(pyvarobj(args)) is TPyDict then dct := TPyDict(pyvarobj(args));
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
    { the KEY comes first, before the flags — `%(name)-10s` }
    hasMapKey := False;
    mapKey := '';
    if (i <= Length(fmt)) and (fmt[i] = '(') then
    begin
      if dct = nil then
        raise TypeError.Create('format requires a mapping');
      Inc(i);
      while (i <= Length(fmt)) and (fmt[i] <> ')') do
      begin mapKey := mapKey + fmt[i]; Inc(i); end;
      if i > Length(fmt) then
        raise ValueError.Create('incomplete format key');
      Inc(i);                      { past the ')' }
      hasMapKey := True;
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
    { `*` takes the width from an ARGUMENT instead of the format string —
      `"%-*s" % (w, s)`, which is how a report lays out a column whose width is
      computed. It raised `unsupported format character "*"`, so the whole
      idiom was unavailable. The starred argument is consumed HERE, before the
      value, exactly as CPython consumes it.
      A NEGATIVE starred width means left-align in CPython, with the magnitude
      as the width — the same as writing the '-' flag. }
    if (i <= Length(fmt)) and (fmt[i] = '*') then
    begin
      if lst <> nil then
      begin
        if argi >= nargs then
          raise TypeError.Create('not enough arguments for format string');
        width := Integer(pyvar_to_int(lst.at(argi)));
      end
      else
      begin
        if argi >= 1 then
          raise TypeError.Create('not enough arguments for format string');
        width := Integer(pyvar_to_int(args));
      end;
      Inc(argi);
      if width < 0 then
      begin
        leftAlign := True;
        width := -width;
      end;
      Inc(i);
    end
    else
      while (i <= Length(fmt)) and (fmt[i] >= '0') and (fmt[i] <= '9') do
      begin
        width := width * 10 + (Ord(fmt[i]) - Ord('0'));
        Inc(i);
      end;
    if (i <= Length(fmt)) and (fmt[i] = '.') then
    begin
      hasPrec := True;
      Inc(i);
      { `.*` — the precision from an argument too, `"%.*f" % (3, x)` }
      if (i <= Length(fmt)) and (fmt[i] = '*') then
      begin
        if lst <> nil then
        begin
          if argi >= nargs then
            raise TypeError.Create('not enough arguments for format string');
          prec := Integer(pyvar_to_int(lst.at(argi)));
        end
        else
        begin
          if argi >= 1 then
            raise TypeError.Create('not enough arguments for format string');
          prec := Integer(pyvar_to_int(args));
        end;
        Inc(argi);
        if prec < 0 then prec := 0;   { CPython treats a negative as absent }
        Inc(i);
      end
      else
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
    if hasMapKey then
    begin
      { fetch RAISES KeyError naming the key, which is what CPython does for a
        missing mapping key — and it now names it properly (see
        bug-nilpy-exception-str-and-repr-diverge-from-cpython). A mapping
        placeholder consumes no positional argument, so argi is left alone. }
      cur := dct.fetch(mapKey);
    end
    else if lst <> nil then
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
    if not hasMapKey then Inc(argi);
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
  pylib may not pull sysutils in (see the FmtArgStr note above). Rounding is
  half-to-EVEN, which is what CPython (and glibc's printf) do.

  NO FLOAT ARITHMETIC. Every earlier version scaled the value — by the whole
  power of ten, or (to dodge that) by splitting off the integer part first —
  and scaling is what MANUFACTURES ties: `0.15 * 10` is exactly 1.5 as a
  double, so the formatter was asked to break a tie that the value does not
  have, and answered 0.2 where CPython says 0.1. The error runs BOTH ways —
  `0.45` is just ABOVE its midpoint and flattened to 4.5 rounds down to 0.4
  where CPython says 0.5 — which is why no tie-break rule could have fixed it.
  bug-nilpy-float-formatting-manufactures-ties-by-scaling

  So the digits come from the exact binary value. PyExDecDigits expands the
  double's mantissa and exponent into its full decimal expansion (that is what
  the ExDec family exists for — it is the same machinery that reads decimals
  back correctly rounded), and PyExDecRound rounds that DIGIT STRING half-even
  on an exact remainder, so a tie is a tie only when the value really sits on
  one. This is what CPython and glibc do, for the same reason. }
var neg: Boolean; ds, ip, fs: AnsiString; decExp, sig, i: Integer;
begin
  if prec < 0 then prec := 0;
  if d <> d then begin Result := 'nan'; Exit; end;
  { the SIGN BIT, not `d < 0.0` — CPython prints `-0.00` for a negative zero,
    and -0.0 is not less than 0.0 }
  neg := PyExDecDoubleToBits(d) < 0;
  if neg then d := -d;
  if d = 0.0 then
  begin
    Result := '0';
    if prec > 0 then
    begin
      Result := Result + '.';
      for i := 1 to prec do Result := Result + '0';
    end;
    if neg then Result := '-' + Result;
    Exit;
  end;

  PyExDecDigits(d, ds, decExp);
  { digits to KEEP: everything down to the 10^-prec place. `decExp` is the
    power of ten the FIRST digit stands for, so that count is decExp+1+prec. }
  sig := decExp + 1 + prec;
  { A value below the last kept place — 0.04 at prec 1 — has no kept digit to
    round against. Prepending a leading zero gives the rounder the position it
    needs and costs nothing: 0.04 becomes 0.04 with the point one place left,
    and the half-even rule then answers 0.0 or 0.1 exactly as CPython does for
    0.04 and for 0.05. }
  while sig < 1 do
  begin
    ds := '0' + ds;
    decExp := decExp + 1;
    sig := sig + 1;
  end;
  PyExDecRound(ds, decExp, sig);
  { a carry out of the leading digit (999 -> 100) moved decExp, so re-derive }
  while Length(ds) < decExp + 1 + prec do ds := ds + '0';

  if decExp >= 0 then
  begin
    ip := Copy(ds, 1, decExp + 1);
    fs := Copy(ds, decExp + 2, Length(ds) - decExp - 1);
  end
  else
  begin
    ip := '0';
    fs := ds;
    for i := 1 to -(decExp + 1) do fs := '0' + fs;
  end;
  while Length(fs) < prec do fs := fs + '0';
  fs := Copy(fs, 1, prec);
  { strip a leading-zero run the expansion may carry (`0` prefixes added above
    are only there to give the rounder a place to stand) }
  while (Length(ip) > 1) and (ip[1] = '0') do ip := Copy(ip, 2, Length(ip) - 1);
  Result := ip;
  if prec > 0 then Result := Result + '.' + fs;
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

function pyformat_v(const v: Variant; const spec: AnsiString): AnsiString;
begin
  if spec = '' then Result := pystr_of(v)
  else Result := pyformat_of(v, spec);
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

function PyHexByte(b: Integer): AnsiString;
{ two LOWER-case hex digits — CPython's \xNN escapes are lower case, and a repr
  that differs by case is a diff nobody wants to read twice. }
const hexd: AnsiString = '0123456789abcdef';
begin
  Result := hexd[(b div 16) + 1] + hexd[(b mod 16) + 1];
end;

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
    { …and every OTHER non-printable as \xNN, which is what makes a repr
      round-trippable and safe to put in a log. They were emitted RAW: a
      formfeed or a vertical tab simply vanished on a terminal, and repr of a
      string containing #0 embedded a NUL that truncates whatever consumes it
      downstream — an invisible failure in the one function whose entire job is
      to be unambiguous. CPython escapes the same set: everything below space
      that is not \n / \t / \r, plus DEL.
      Found while writing mimic_string, whose `whitespace` constant is six
      characters and repr'd as four. }
    else if (ch < ' ') or (ch = #127) then
      Result := Result + '\x' + PyHexByte(Ord(ch))
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
  { ONE implementation, and it is pyvar_repr's. This is the hole an f-string's
    `!r` lowers to (PyFStrSwapLastCall swaps pystr_of( for pyrepr_of(), and it
    used to quote a string and hand everything else to pystr_of — which answers
    '' for a user instance, so `f"{obj!r}"` printed nothing while `repr([obj])`
    printed it correctly.
    The string/char quoting that used to live here now lives at pyvar_repr's
    tail, so the two cannot drift.
    bug-nilpy-repr-of-a-variant-holding-an-object-is-empty }
  Result := pyvar_repr(v);
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
  { pyvar_repr, NOT pyrepr_of. Two variant reprs exist and only one knows about
    objects: pyvar_repr handles None, callables, the pylib containers and a USER
    class's __repr__, then falls back to pyrepr_of for scalars and strings.
    pyrepr_of on its own quotes a string and hands everything else to pystr_of,
    which answers '' for a user instance — so `repr(xs[0])` on a list ELEMENT
    printed nothing while `repr(xs)` printed the elements correctly, because the
    container path goes through pyvar_repr.
    pyvar_repr is now the single implementation and pyrepr_of(Variant) forwards
    to it, so either name works here; this one is spelled out.
    bug-nilpy-repr-of-a-variant-holding-an-object-is-empty }
  Result := pyvar_repr(v);
end;

function repr(l: TPyList): AnsiString; overload;
begin
  Result := pylist_repr(l);
end;

function repr(dc: TPyDict): AnsiString; overload;
begin
  Result := pydict_repr(dc);
end;

function repr(o: TObject): AnsiString; overload;
var v: Variant;
begin
  { straight to pyvar_repr, the same renderer a boxed element already used —
    so `repr(c)` and `repr([c])[1:-1]` cannot disagree, and a class with no
    __repr__ gets CPython's `<__main__.C object at 0x..>` shape for free
    instead of a second, divergent default.

    The boxing is INLINE, not a call to PyObjAsVar: that helper is defined ~900
    lines below with no entry in this unit's top declaration block, so calling
    it from here is a forward use — which does not fail to compile, it links to
    a plausible-looking wrong address and crashes far away. pyvar_repr itself
    IS declared up top, so that call is fine.

    The RETAIN matters for the same reason it does there: `v` is a local, so
    its scope exit releases the object-tagged slot, and without the retain
    `repr(c)` would hand back a net release of the caller's `c`. }
  { a NIL handle is a class-typed None — `repr(None)` is 'None', and without
    this it boxed as a VT_OBJECT with a nil payload and rendered EMPTY. Same
    first line as pyobj_str_of, for the same reason. }
  if o = nil then begin Result := 'None'; Exit; end;
  PPyVarRec(@v)^.VType := 7;
  PPyVarRec(@v)^.Payload := Int64(NativeInt(Pointer(o)));
  PXXObjRetain(Pointer(o));
  Result := pyvar_repr(v);
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
    { -0.0 is not < 0.0, so this used to hand back the negative zero unchanged;
      CPython's abs(-0.0) is 0.0. Same rule as __pxxAbsDbl, which the static
      path uses. }
    if d < 0.0 then d := -d
    else if d = 0.0 then d := 0.0;
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

{ The three routines the FORWARDED-call desugaring needs once **kwargs may
  actually be BOUND (feature-nilpy-star-args-kwargs, its last rung): the
  effective argument count is positional PLUS keyword, and a slot past the
  positional run is fetched by the parameter's NAME.
  A slot that is neither positional nor present by name RAISES rather than
  quietly passing None. The arity check has already established that this many
  arguments were supplied, so a missing name means one of them was a keyword
  the callee does not declare — CPython's "unexpected keyword argument",
  reported at the point where it is detectable. }
function pystar_argc(l: TPyList; d: TPyDict): Integer;
begin
  Result := 0;
  if l <> nil then Result := l.count;
  if d <> nil then Result := Result + d.count;
end;

function pystar_has(l: TPyList; d: TPyDict; i: Integer;
                   const nm: AnsiString): Boolean;
{ Was this parameter actually SUPPLIED — positionally at i, or by name? With
  keywords the argument COUNT no longer says WHICH parameters are filled
  (`f(1, c=9)` fills a and c and skips b), so the desugaring passes every
  parameter and asks this per slot, falling back to the callee's own default
  where the answer is no. }
begin
  Result := (l <> nil) and (i >= 0) and (i < l.count);
  if Result then Exit;
  Result := (d <> nil) and (d.indexof(nm) >= 0);
end;

function pystar_arg_kw(l: TPyList; d: TPyDict; i: Integer;
                       const nm: AnsiString): Variant;
begin
  if (l <> nil) and (i >= 0) and (i < l.count) then
  begin
    Result := l.at(i);
    Exit;
  end;
  if (d <> nil) and (d.indexof(nm) >= 0) then
  begin
    Result := d.fetch(nm);
    Exit;
  end;
  { Past the supplied count this is a DEFAULTED parameter the chosen arm will
    not pass, and the slot reads are eager — every slot the widest arity could
    use is read before the arm is picked — so it must answer None rather than
    raise, exactly as pystar_arg does.
    WITHIN the supplied count it is a genuine error: that many arguments were
    given, this parameter got none of them, so one of the keywords names a
    parameter the callee does not have. CPython's "unexpected keyword
    argument", caught at the only point it is detectable here. }
  if i < pystar_argc(l, d) then
    raise TypeError.Create('forwarded call has no value for parameter ''' + nm +
      ''' — an unexpected keyword argument was passed');
  Result := pynone;
end;

procedure pystar_check_arity_kw(l: TPyList; d: TPyDict; lo: Integer; hi: Integer);
var n: Integer;
begin
  n := pystar_argc(l, d);
  if (n < lo) or (n > hi) then
    raise TypeError.Create('forwarded call got ' + pystr_of(Int64(n)) +
                           ' arguments, expected ' + pystr_of(Int64(lo)) +
                           ' to ' + pystr_of(Int64(hi)));
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

function pyseq_of_obj(o: TObject): TPyList;
begin
  Result := nil;
  if o = nil then Exit;
  if o is TPyList then begin Result := list(TPyList(o)); Exit; end;
  { A DICT yields its KEYS — `list(d)` and `for x in d` are both the key
    sequence in Python. }
  if o is TPyDict then begin Result := TPyDict(o).keylist; Exit; end;
  { bytes — the byte VALUES, same as the static arm. }
  if o is TPyBytes then begin Result := list(TPyBytes(o)); Exit; end;
  { a cursor DRAINS, leaving it exhausted, which is CPython's
    single-consumption rule. Every caller of this wants a materialised
    sequence, so laziness cannot survive here — the lazy path for a `for`
    header is the cursor loop in PyParseForIn, which never reaches this. }
  if o is TPyIter then begin Result := pyiter_drain(TPyIter(o)); Exit; end;
  if o is TPyRange then begin Result := list(TPyRange(o)); Exit; end;
  { a USER class implementing the iterator protocol, drained the same way a
    cursor is. This is the arm the three copies of this chain were missing. }
  if PyUserObjHasDunder(o, '__iter__') then
    Result := pyiter_drain(pyiter_of_userobj(o));
end;

function pylist_v(const v: Variant): TPyList;
var o: TObject;
begin
  if pyvartag(v) = 6 then begin Result := list(VariantToStr(v)); Exit; end;
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    Result := pyseq_of_obj(o);
    if Result <> nil then Exit;
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
  need := w - PyStrCharLen(s);   { the width is in CHARACTERS }
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

function tuple(const v: Variant): TPyList; overload;
var o: TObject;
begin
  { mirrors list(const v: Variant), with the tuple flag stamped on the result —
    the same shared chain, so a user iterable and a cursor arrive here too }
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    Result := pyseq_of_obj(o);
    if Result <> nil then
    begin
      Result.FKind := PYSEQ_TUPLE;
      Exit;
    end;
  end;
  if pyvartag(v) = 6 then begin Result := tuple(pystr_of(v)); Exit; end;
  Result := TPyList.Create;      { None / empty }
  Result.FKind := PYSEQ_TUPLE;
end;

function reversed(const v: Variant): TPyIter; overload;
var o: TObject;
begin
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := reversed(TPyList(o)); Exit; end;
    { reversed(<cursor>) is a TypeError in CPython — an iterator has no known
      end to walk back from — but NilPy is allowed to be laxer where CPython
      REJECTS the code: drain and reverse what came out. }
    if o is TPyRange then begin Result := reversed(TPyRange(o)); Exit; end;
    if o is TPyIter then begin Result := reversed(pyiter_drain(TPyIter(o))); Exit; end;
    if o is TPyDict then begin Result := reversed(TPyDict(o).keylist); Exit; end;
  end;
  if pyvartag(v) = 6 then begin Result := reversed(pystr_of(v)); Exit; end;
  Result := pyiter_of_list(TPyList.Create);
end;

function tuple(const s: AnsiString): TPyList; overload;
begin
  { through the ONE exploder, like list(const s) — a private byte walk here made
    `tuple("béa")` four elements where `list("béa")` was three, which is the
    "one exploder, not two" note on pystr_charlist arriving a third time.
    bug-nilpy-non-ascii-string-surface-measured }
  Result := pystr_charlist(s);
  Result.FKind := PYSEQ_TUPLE;
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
var o: TObject;
begin
  { one chain, shared with pylist_v / tuple / set — see pyseq_of_obj. A cursor
    is consumed, not copied, which is what makes a lazy map indistinguishable
    from the eager one it replaced. }
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    Result := pyseq_of_obj(o);
    if Result <> nil then Exit;
  end;
  if pyvartag(v) = 6 then begin Result := list(pystr_of(v)); Exit; end;
  Result := TPyList.Create;   { None / empty }
end;

function list(it: TPyIter): TPyList; overload;
begin
  Result := pyiter_drain(it);
end;

function list(const s: AnsiString): TPyList; overload;
begin
  { one exploder, not two: this used to walk BYTES while pystr_charlist (the
    zip/enumerate path) walked the same string its own way, so `list(s)` and
    `zip(s, s)` could disagree about how many elements a string has. }
  Result := pystr_charlist(s);
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
var o: TObject; seq: TPyList;
begin
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyDict then begin Result := dict(TPyDict(o)); Exit; end;
    { ANY other iterable is a sequence of (key, value) PAIRS, which is the
      other half of Python's dict() constructor: `dict(zip(names, values))` is
      the idiom, and zip answers a cursor. With only the TPyDict arm here that
      call boxed its cursor, matched this overload and answered {} — silently,
      on the commonest way to build a dict at all
      (bug-nilpy-dict-of-a-zip-or-any-cursor-is-empty). The pair walk itself is
      dict(TPyList), which is TPyDict.update. }
    seq := pyseq_of_obj(o);
    if seq <> nil then begin Result := dict(seq); Exit; end;
  end;
  Result := TPyDict.Create;   { None / non-mapping }
end;

{ dict(<cursor>) with a STATIC cursor type — the same rule one level up, so the
  call does not have to be boxed into a variant to find its meaning. }
function dict(it: TPyIter): TPyDict; overload;
begin
  Result := dict(pyiter_drain(it));
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

function reversed(l: TPyList): TPyIter;
begin
  Result := pyiter_rev_list(l);
end;

function reversed(const s: AnsiString): TPyIter; overload;
begin
  Result := pyiter_rev_str(s);
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

function pylist_repeat_inplace(l: TPyList; n: Int64): TPyList;
{ `xs *= 2` — Python MUTATES the list and rebinds the same object, so an alias
  taken beforehand sees the new contents. Building a fresh list (pylist_repeat)
  and assigning it back gives the right value under the name and the OLD one
  through every alias — silent, and it made `*=` disagree with `+=`, which has
  always mutated (TPyList.extend). This is `+=`'s missing twin.

  The original elements are snapshotted first: appending to the list being read
  would feed on its own output. n <= 0 clears it, which is CPython's answer for
  `xs *= 0`. }
var i, k, n0: Integer; snap: TPyList;
begin
  Result := l;
  if l = nil then Exit;
  { A TUPLE (and a frozenset) is IMMUTABLE — `t *= 2` rebinds a fresh one there,
    which is the semantics, and mutating in place would make an alias see a
    change Python guarantees it cannot. The two share this class, so the
    question is asked once here rather than at the call site, which cannot know
    the run-time kind. }
  if l.FKind <> PYSEQ_LIST then
  begin
    Result := pylist_repeat(l, n);
    Exit;
  end;
  n0 := l.count;
  if n <= 0 then
  begin
    l.clear;
    Exit;
  end;
  if (n = 1) or (n0 = 0) then Exit;
  snap := TPyList.Create;
  for i := 0 to n0 - 1 do snap.append(l.at(i));
  for k := 2 to n do
    for i := 0 to n0 - 1 do l.append(snap.at(i));
  PXXObjRelease(Pointer(snap));
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
  { the LEFT operand decides, as it does in CPython: bytearray + bytes is a
    bytearray, bytes + bytearray is bytes. }
  if a <> nil then r.FIsByteArray := a.FIsByteArray
  else if b <> nil then r.FIsByteArray := b.FIsByteArray;
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

{ ---- the rest of the ASCII-shaped `bytes` contract ------------------------
  See the block comment on the class declaration for why these land as a SET.
  All of them are byte-wise loops; the only rule worth stating twice is that a
  method BUILDING a buffer copies FIsByteArray, or `bytearray(...).lower()`
  silently becomes a `bytes`. }

{ A new buffer OF THE SAME PYTHON TYPE as `src` — the tag-carrying Create every
  transformation below goes through, so the rule lives in one place instead of
  in fifteen. }
function PyBytesLike(src: TPyBytes; n: Integer): TPyBytes;
begin
  Result := TPyBytes.Create(n);
  if src <> nil then Result.FIsByteArray := src.FIsByteArray;
end;

{ Store one byte at an ABSOLUTE index. Deliberately NOT named PyBytesPut: that
  name is taken by the ENCODER's cursor-advancing form
  `PyBytesPut(b; var at: Integer; v: Int64)`, and a same-named three-argument
  overload beside it silently won the encoder's own call sites — every byte of
  `"hi".encode("latin-1")` landed at the same index and the string came back as
  `b'i\x00'`. Pascal overload resolution had two plausible candidates and no
  reason to prefer the right one. }
procedure PyBytesSet(b: TPyBytes; i: Integer; v: Integer);
var p: PByte;
begin
  p := PByte(NativeInt(b.FData) + i);
  p^ := v;
end;

{ CPython's bytes whitespace set: space, tab, newline, CR, vertical tab, form
  feed. NOT locale-dependent and NOT the Unicode set — a bytes object has no
  encoding to consult. }
function PyByteIsSpace(v: Integer): Boolean;
begin
  PyByteIsSpace := (v = 32) or (v = 9) or (v = 10) or (v = 13) or (v = 11) or (v = 12);
end;

function PyByteLower(v: Integer): Integer;
begin
  PyByteLower := v;
  if (v >= 65) and (v <= 90) then PyByteLower := v + 32;
end;

function PyByteUpper(v: Integer): Integer;
begin
  PyByteUpper := v;
  if (v >= 97) and (v <= 122) then PyByteUpper := v - 32;
end;

function PyByteIsAlpha(v: Integer): Boolean;
begin
  PyByteIsAlpha := ((v >= 65) and (v <= 90)) or ((v >= 97) and (v <= 122));
end;

function PyByteIsDigit(v: Integer): Boolean;
begin
  PyByteIsDigit := (v >= 48) and (v <= 57);
end;

function TPyBytes.startswith(pfx: TPyBytes): Boolean;
var i, m: Integer;
begin
  Result := False;
  if pfx = nil then begin Result := True; Exit; end;
  m := pfx.count;
  if m > count then Exit;
  for i := 0 to m - 1 do
    if at(i) <> pfx.at(i) then Exit;
  Result := True;
end;

function TPyBytes.lower: TPyBytes;
var i: Integer;
begin
  Result := PyBytesLike(Self, FLen);
  for i := 0 to FLen - 1 do PyBytesSet(Result, i, PyByteLower(at(i)));
end;

function TPyBytes.upper: TPyBytes;
var i: Integer;
begin
  Result := PyBytesLike(Self, FLen);
  for i := 0 to FLen - 1 do PyBytesSet(Result, i, PyByteUpper(at(i)));
end;

{ CPython's title(): every RUN of letters gets an upper-case first byte and
  lower-case rest, and a non-letter (including a digit or an apostrophe) ends
  the run — b"they're".title() is b"They'Re". }
function TPyBytes.title: TPyBytes;
var i, v: Integer; inWord: Boolean;
begin
  Result := PyBytesLike(Self, FLen);
  inWord := False;
  for i := 0 to FLen - 1 do
  begin
    v := at(i);
    if PyByteIsAlpha(v) then
    begin
      if inWord then v := PyByteLower(v) else v := PyByteUpper(v);
      inWord := True;
    end
    else
      inWord := False;
    PyBytesSet(Result, i, v);
  end;
end;

{ CPython's capitalize(): first byte upper, EVERY other byte lower — not
  title()'s per-word rule. }
function TPyBytes.capitalize: TPyBytes;
var i, v: Integer;
begin
  Result := PyBytesLike(Self, FLen);
  for i := 0 to FLen - 1 do
  begin
    v := at(i);
    if i = 0 then v := PyByteUpper(v) else v := PyByteLower(v);
    PyBytesSet(Result, i, v);
  end;
end;

function TPyBytes.swapcase: TPyBytes;
var i, v: Integer;
begin
  Result := PyBytesLike(Self, FLen);
  for i := 0 to FLen - 1 do
  begin
    v := at(i);
    if (v >= 65) and (v <= 90) then v := v + 32
    else if (v >= 97) and (v <= 122) then v := v - 32;
    PyBytesSet(Result, i, v);
  end;
end;

{ Is byte value v in the strip SET? `chars = nil` means the no-argument form,
  i.e. whitespace. CPython's strip argument is a SET of bytes, not a prefix —
  b"xyxhixy".strip(b"xy") is b"hi". }
function PyBytesInSet(chars: TPyBytes; v: Integer): Boolean;
var k: Integer;
begin
  if chars = nil then begin PyBytesInSet := PyByteIsSpace(v); Exit; end;
  PyBytesInSet := False;
  for k := 0 to chars.FLen - 1 do
    if chars.at(k) = v then begin PyBytesInSet := True; Exit; end;
end;

function PyBytesStrip(b: TPyBytes; chars: TPyBytes; doL, doR: Boolean): TPyBytes;
var lo, hi, i: Integer;
begin
  lo := 0;
  hi := b.FLen;
  if doL then
    while (lo < hi) and PyBytesInSet(chars, b.at(lo)) do Inc(lo);
  if doR then
    while (hi > lo) and PyBytesInSet(chars, b.at(hi - 1)) do Dec(hi);
  Result := PyBytesLike(b, hi - lo);
  for i := 0 to (hi - lo) - 1 do PyBytesSet(Result, i, b.at(lo + i));
end;

{ The no-argument forms want a NIL `chars`, which a bare `nil` literal cannot
  carry into a class-typed parameter through overload resolution — so the nil
  is named once here rather than cast at six call sites. }
function PyBytesStripWS(b: TPyBytes; doL, doR: Boolean): TPyBytes;
var none: TPyBytes;
begin
  none := nil;
  Result := PyBytesStrip(b, none, doL, doR);
end;

function TPyBytes.strip: TPyBytes; overload;
begin
  Result := PyBytesStripWS(Self, True, True);
end;

function TPyBytes.strip(chars: TPyBytes): TPyBytes; overload;
begin
  Result := PyBytesStrip(Self, chars, True, True);
end;

function TPyBytes.lstrip: TPyBytes; overload;
begin
  Result := PyBytesStripWS(Self, True, False);
end;

function TPyBytes.lstrip(chars: TPyBytes): TPyBytes; overload;
begin
  Result := PyBytesStrip(Self, chars, True, False);
end;

function TPyBytes.rstrip: TPyBytes; overload;
begin
  Result := PyBytesStripWS(Self, False, True);
end;

function TPyBytes.rstrip(chars: TPyBytes): TPyBytes; overload;
begin
  Result := PyBytesStrip(Self, chars, False, True);
end;

{ CPython replaces EVERY occurrence, left to right, and never rescans what the
  replacement produced: b"aaa".replace(b"aa", b"a") is b"aa", not b"a". }
function TPyBytes.replace(old_, new_: TPyBytes): TPyBytes;
var i, k, n, hits, outLen, w: Integer;
begin
  if (old_ = nil) or (old_.FLen = 0) then begin Result := PyBytesLike(Self, FLen);
    for i := 0 to FLen - 1 do PyBytesSet(Result, i, at(i)); Exit; end;
  n := old_.FLen;
  hits := 0;
  i := 0;
  while i + n <= FLen do
    if pybytes_find(Self, old_, i) = i then begin Inc(hits); i := i + n; end
    else Inc(i);
  if hits = 0 then
  begin
    Result := PyBytesLike(Self, FLen);
    for i := 0 to FLen - 1 do PyBytesSet(Result, i, at(i));
    Exit;
  end;
  outLen := FLen - hits * n;
  if new_ <> nil then outLen := outLen + hits * new_.FLen;
  Result := PyBytesLike(Self, outLen);
  i := 0;
  w := 0;
  while i < FLen do
  begin
    if (i + n <= FLen) and (pybytes_find(Self, old_, i) = i) then
    begin
      if new_ <> nil then
        for k := 0 to new_.FLen - 1 do begin PyBytesSet(Result, w, new_.at(k)); Inc(w); end;
      i := i + n;
    end
    else
    begin
      PyBytesSet(Result, w, at(i));
      Inc(w);
      Inc(i);
    end;
  end;
end;

function TPyBytes.index(sub: TPyBytes): Integer;
begin
  Result := pybytes_find(Self, sub, 0);
  if Result < 0 then raise ValueError.Create('subsection not found');
end;

function TPyBytes.rfind(sub: TPyBytes): Integer;
var i, j, m: Integer; hit: Boolean;
begin
  Result := -1;
  if sub = nil then Exit;
  m := sub.FLen;
  if m = 0 then begin Result := FLen; Exit; end;
  i := FLen - m;
  while i >= 0 do
  begin
    hit := True;
    for j := 0 to m - 1 do
      if at(i + j) <> sub.at(j) then begin hit := False; Break; end;
    if hit then begin Result := i; Exit; end;
    Dec(i);
  end;
end;

function TPyBytes.rindex(sub: TPyBytes): Integer;
begin
  Result := rfind(sub);
  if Result < 0 then raise ValueError.Create('subsection not found');
end;

function PyBytesSlice(b: TPyBytes; lo, hi: Integer): TPyBytes;
var i: Integer;
begin
  if hi < lo then hi := lo;
  Result := PyBytesLike(b, hi - lo);
  for i := 0 to (hi - lo) - 1 do PyBytesSet(Result, i, b.at(lo + i));
end;

{ .split() with no separator: split on RUNS of whitespace and DROP the empty
  fields, so b"  a  b ".split() is [b"a", b"b"] and b"".split() is []. }
function PyBytesSplitWS(b: TPyBytes): TPyList;
var i, st: Integer;
begin
  Result := TPyList.Create;
  i := 0;
  while i < b.FLen do
  begin
    while (i < b.FLen) and PyByteIsSpace(b.at(i)) do Inc(i);
    if i >= b.FLen then Break;
    st := i;
    while (i < b.FLen) and not PyByteIsSpace(b.at(i)) do Inc(i);
    Result.append(PyBytesSlice(b, st, i));
  end;
end;

function TPyBytes.split: TPyList; overload;
begin
  Result := PyBytesSplitWS(Self);
end;

{ .split(sep): an EXACT separator, KEEPING empty fields — b"a,,b".split(b",")
  is [b"a", b"", b"b"] and b"".split(b",") is [b""]. Contrast the no-argument
  form above. An empty separator is a ValueError in CPython. }
function TPyBytes.split(sep: TPyBytes): TPyList; overload;
var i, st, hit: Integer;
begin
  if (sep = nil) or (sep.FLen = 0) then
    raise ValueError.Create('empty separator');
  Result := TPyList.Create;
  st := 0;
  i := 0;
  while i + sep.FLen <= FLen do
  begin
    hit := pybytes_find(Self, sep, i);
    if (hit < 0) then Break;
    Result.append(PyBytesSlice(Self, st, hit));
    i := hit + sep.FLen;
    st := i;
  end;
  Result.append(PyBytesSlice(Self, st, FLen));
end;

{ rsplit() with no argument is split() with no argument: whitespace runs, empty
  fields dropped, and the result is the same list read either way. The
  separator and maxsplit forms are where the two differ, and neither is
  implemented here rather than answered wrongly. }
function TPyBytes.rsplit: TPyList;
begin
  Result := PyBytesSplitWS(Self);
end;

{ .splitlines(): breaks on \n, \r and \r\n, DROPS the terminator, and does NOT
  produce a trailing empty field for a final newline — the three ways it
  differs from split(b'\n'). }
function TPyBytes.splitlines: TPyList;
var i, st, v: Integer;
begin
  Result := TPyList.Create;
  i := 0;
  st := 0;
  while i < FLen do
  begin
    v := at(i);
    if (v = 10) or (v = 13) then
    begin
      Result.append(PyBytesSlice(Self, st, i));
      if (v = 13) and (i + 1 < FLen) and (at(i + 1) = 10) then Inc(i);
      Inc(i);
      st := i;
    end
    else
      Inc(i);
  end;
  if st < FLen then Result.append(PyBytesSlice(Self, st, FLen));
end;

{ b'-'.join(parts) — Self is the SEPARATOR, as for str.join. }
function TPyBytes.join(parts: TPyList): TPyBytes;
var i, k, w, total: Integer; part: TPyBytes; o: TObject;
begin
  if (parts = nil) or (parts.count = 0) then begin Result := PyBytesLike(Self, 0); Exit; end;
  total := 0;
  for i := 0 to parts.count - 1 do
  begin
    o := TObject(pyvarobj(parts.at(i)));
    if not (o is TPyBytes) then
      raise TypeError.Create('sequence item: expected a bytes-like object');
    total := total + TPyBytes(o).FLen;
  end;
  total := total + FLen * (parts.count - 1);
  Result := PyBytesLike(Self, total);
  w := 0;
  for i := 0 to parts.count - 1 do
  begin
    if i > 0 then
      for k := 0 to FLen - 1 do begin PyBytesSet(Result, w, at(k)); Inc(w); end;
    part := TPyBytes(TObject(pyvarobj(parts.at(i))));
    for k := 0 to part.FLen - 1 do begin PyBytesSet(Result, w, part.at(k)); Inc(w); end;
  end;
end;

function TPyBytes.translate(table: TPyBytes): TPyBytes;
var i: Integer;
begin
  { CPython accepts None for "no mapping" (the delete-only form); a table of
    any length other than 256 is a ValueError. }
  if table = nil then
  begin
    Result := PyBytesLike(Self, FLen);
    for i := 0 to FLen - 1 do PyBytesSet(Result, i, at(i));
    Exit;
  end;
  if table.FLen <> 256 then
    raise ValueError.Create('translation table must be 256 characters long');
  Result := PyBytesLike(Self, FLen);
  for i := 0 to FLen - 1 do PyBytesSet(Result, i, table.at(at(i)));
end;

{ The is* predicates are all FALSE on an empty bytes in CPython — "at least one
  byte, and every byte qualifies". isupper/islower additionally need at least
  one CASED byte, so b"123".isupper() is False while b"A1".isupper() is True. }
function TPyBytes.isdigit: Boolean;
var i: Integer;
begin
  Result := False;
  if FLen = 0 then Exit;
  for i := 0 to FLen - 1 do
    if not PyByteIsDigit(at(i)) then Exit;
  Result := True;
end;

function TPyBytes.isalpha: Boolean;
var i: Integer;
begin
  Result := False;
  if FLen = 0 then Exit;
  for i := 0 to FLen - 1 do
    if not PyByteIsAlpha(at(i)) then Exit;
  Result := True;
end;

function TPyBytes.isalnum: Boolean;
var i: Integer;
begin
  Result := False;
  if FLen = 0 then Exit;
  for i := 0 to FLen - 1 do
    if not (PyByteIsAlpha(at(i)) or PyByteIsDigit(at(i))) then Exit;
  Result := True;
end;

function TPyBytes.isspace: Boolean;
var i: Integer;
begin
  Result := False;
  if FLen = 0 then Exit;
  for i := 0 to FLen - 1 do
    if not PyByteIsSpace(at(i)) then Exit;
  Result := True;
end;

function TPyBytes.isupper: Boolean;
var i, v: Integer; cased: Boolean;
begin
  Result := False;
  cased := False;
  for i := 0 to FLen - 1 do
  begin
    v := at(i);
    if (v >= 97) and (v <= 122) then Exit;
    if (v >= 65) and (v <= 90) then cased := True;
  end;
  Result := cased;
end;

function TPyBytes.islower: Boolean;
var i, v: Integer; cased: Boolean;
begin
  Result := False;
  cased := False;
  for i := 0 to FLen - 1 do
  begin
    v := at(i);
    if (v >= 65) and (v <= 90) then Exit;
    if (v >= 97) and (v <= 122) then cased := True;
  end;
  Result := cased;
end;

{ ---- TPyFile: raw-syscall file handles (x86-64) ---- }

constructor TPyFile.Create;
begin
  FFd := -1;
  FBinary := False;
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
    pyos_raise_ioerror(fd, path, '');
  Result := TPyFile.Create;
  Result.FFd := fd;
  { 'b' anywhere in the mode is CPython's own test for a binary stream }
  for i := 1 to Length(mode) do
    if mode[i] = 'b' then Result.FBinary := True;
end;

function TPyFile.read(u: Int64): Variant;
{ `f.read(n)`. TEXT mode yields a str, binary yields bytes — see FBinary. This
  arity used to yield bytes unconditionally, so `print(f.read(3))` on a text
  file printed b'one' where CPython prints one, and `f.read(3) + "x"` was a type
  error against working Python. Its own zero-argument sibling was already
  correct for text, so the two arities of one method disagreed.
  bug-nilpy-text-mode-read-n-returns-bytes-not-str }
var r: TPyBytes; got: Int64; s: AnsiString; i: Integer;
begin
  if u < 0 then u := 0;
  r := TPyBytes.Create(u);
  got := PyPalRead(FFd, r.FData, u);
  if got < 0 then got := 0;
  r.FLen := got;
  if FBinary then
  begin
    Result := r;
    Exit;
  end;
  s := '';
  for i := 0 to Integer(got) - 1 do s := s + Chr(PByte(NativeInt(r.FData) + i)^);
  Result := s;
end;

{ Read to EOF from the current position. Chunked rather than byte-at-a-time
  (readline's excuse — "line reads are rare and short" — does not hold for a
  whole file), and it leaves the position at EOF like CPython. }
function TPyFile.readall: AnsiString;
{ the slurp itself, mode-blind — both public readers are built on it }
var buf: array[0..8191] of Char; got: Int64; res: AnsiString;
    rlen, rcap, i: Integer;
begin
  res := ''; rlen := 0; rcap := 0;
  while True do
  begin
    got := PyPalRead(FFd, @buf[0], 8192);
    if got <= 0 then Break;
    if rlen + Integer(got) > rcap then
    begin
      rcap := (rlen + Integer(got)) * 2;
      if rcap < 8192 then rcap := 8192;
      SetLength(res, rcap);
    end;
    for i := 0 to Integer(got) - 1 do
      res[rlen + i + 1] := buf[i];
    rlen := rlen + Integer(got);
  end;
  SetLength(res, rlen);
  Result := res;
end;

function TPyFile.read: Variant;
{ `f.read()`. Binary mode must yield BYTES — it answered a str, so
  `open(p,"rb").read()` printed 'one\n' where CPython prints b'one\n'. The
  mirror of the read(n) bug, in the other direction.
  bug-nilpy-text-mode-read-n-returns-bytes-not-str }
var s: AnsiString; b: TPyBytes; i: Integer;
begin
  s := Self.readall;
  if not FBinary then
  begin
    Result := s;
    Exit;
  end;
  b := TPyBytes.Create(Length(s));
  for i := 1 to Length(s) do PByte(NativeInt(b.FData) + i - 1)^ := Ord(s[i]);
  b.FLen := Length(s);
  Result := b;
end;

function TPyFile.readlines: TPyList;
{ ...and its ELEMENTS follow the mode too: binary readlines() is a list of
  bytes in CPython, and answering a list of str is the same divergence one
  level down. bug-nilpy-text-mode-read-n-returns-bytes-not-str }
var content, line: AnsiString; i, n, k: Integer; lb: TPyBytes;
begin
  Result := TPyList.Create;
  content := Self.readall;
  { each line KEEPS its trailing newline -- Python's file iteration yields them
    that way, and a final unterminated line is still a line }
  i := 1; n := Length(content); line := '';
  while i <= n do
  begin
    line := line + content[i];
    if content[i] = #10 then
    begin
      if FBinary then
      begin
        lb := TPyBytes.Create(Length(line));
        for k := 1 to Length(line) do PByte(NativeInt(lb.FData) + k - 1)^ := Ord(line[k]);
        lb.FLen := Length(line);
        Result.append(lb);
      end
      else
        Result.append(line);
      line := '';
    end;
    Inc(i);
  end;
  if line <> '' then
  begin
    if FBinary then
    begin
      lb := TPyBytes.Create(Length(line));
      for k := 1 to Length(line) do PByte(NativeInt(lb.FData) + k - 1)^ := Ord(line[k]);
      lb.FLen := Length(line);
      Result.append(lb);
    end
    else
      Result.append(line);
  end;
end;

function TPyFile.readline: Variant;
{ TEXT mode yields a str here too — it answered bytes, so `f.readline()` on a
  text file printed b'one\n'. bug-nilpy-text-mode-read-n-returns-bytes-not-str }
var r: TPyBytes; got: Int64; ch: Byte; s: AnsiString;
begin
  { one byte at a time — line reads are rare and short in the corpus }
  r := TPyBytes.Create(0);
  s := '';
  while True do
  begin
    got := PyPalRead(FFd, @ch, 1);
    if got <= 0 then Break;
    if FBinary then r.append(ch) else s := s + Chr(ch);
    if ch = 10 then Break;
  end;
  if FBinary then Result := r else Result := s;
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

function TPyFile.write(const v: Variant): Int64;
var o: Pointer;
begin
  if pyvar_is_strtag(v) then
    Result := Self.write(pystr_of(v))
  else if pyvar_is_objtag(v) then
  begin
    o := pyvarobj(v);
    if (o <> nil) and (TObject(o) is TPyBytes) then
      Result := Self.write(TPyBytes(o))
    else
      raise TypeError.Create('write() argument must be str or bytes');
  end
  else
    { an int/float/bool/None argument is a TypeError in CPython too, and saying
      so beats writing its decimal spelling and looking like it worked }
    raise TypeError.Create('write() argument must be str or bytes');
end;

procedure TPyFile.writelines(const v: Variant);
var seq: TPyList; i: Integer; o: Pointer;
begin
  seq := nil;
  if pyvar_is_objtag(v) then
  begin
    o := pyvarobj(v);
    if o <> nil then seq := pyseq_of_obj(TObject(o));
  end;
  if seq = nil then
    raise TypeError.Create('writelines() argument must be an iterable of str');
  for i := 0 to seq.count - 1 do
    Self.write(seq.at(i));
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
function PyVarIsCallableTag(const v: Variant): Boolean;
{ Does this variant hold a CALLABLE VALUE (rather than a class, a container or a
  scalar)? VT_BOUNDMETHOD 8, VT_PYCLOSURE 9, VT_BOUNDFN 10 and VT_CALLABLE 12 —
  the last being a plain compiled code address, which before it had a tag of its
  own wore VT_INT64 and so rendered as a DECIMAL INTEGER.

  ONE predicate because value->text has THREE entry points here (pystr_of,
  pyvar_repr, pyvar_print_of) and each carried its own copy of the tag list; a
  tag added to two of the three is a rendering that is right in print() and
  wrong in an f-string. }
begin
  PyVarIsCallableTag := (pyvartag(v) = 8) or (pyvartag(v) = 9) or
                        (pyvartag(v) = 10) or (pyvartag(v) = 12);
end;

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

{ ---- A BUILTIN TYPE as a VALUE ------------------------------------------
  bug-n-a-type-name-is-not-a-first-class-value }

function pybtype(code: Int64): Variant;
var r: PPyVarRec;
begin
  r := PPyVarRec(@Result);
  r^.VType := 13;                     { VT_BTYPE_TAG }
  r^.Payload := code;
end;

function pybtype_is(const v: Variant): Boolean;
begin
  Result := pyvartag(v) = 13;
end;

function pybtype_code(const v: Variant): Int64;
begin
  if pyvartag(v) = 13 then Result := PPyVarRec(@v)^.Payload else Result := 0;
end;

function pybtype_name(code: Int64): AnsiString;
begin
  case code of
    PYBT_STR:       Result := 'str';
    PYBT_INT:       Result := 'int';
    PYBT_FLOAT:     Result := 'float';
    PYBT_BOOL:      Result := 'bool';
    PYBT_BYTES:     Result := 'bytes';
    PYBT_LIST:      Result := 'list';
    PYBT_DICT:      Result := 'dict';
    PYBT_SET:       Result := 'set';
    PYBT_TUPLE:     Result := 'tuple';
    PYBT_BYTEARRAY: Result := 'bytearray';
    PYBT_FROZENSET: Result := 'frozenset';
    PYBT_TYPE:      Result := 'type';
    PYBT_NONETYPE:  Result := 'NoneType';
  else
    Result := '?';
  end;
end;

function pybtype_repr(const v: Variant): AnsiString;
begin
  Result := '<class ' + Chr(39) + pybtype_name(pybtype_code(v)) + Chr(39) + '>';
end;

function pybtype_of_value(const x: Variant): Int64;
var nm: AnsiString; i: Int64;
begin
  { Deliberately NOT a second tag->code switch. `pytype_name_v` is already the
    one place that decides what Python type a value has, and it knows the things
    a tag cannot: list/tuple/set share one class and differ by FKind, bytes and
    bytearray share TPyBytes and differ by a flag. A parallel switch here would
    be a second mechanism for one concept and would drift the first time a kind
    was added — the shape devdocs/dev/normalise-dont-special-case.md describes.
    So ask that function and map its answer back through the same name table
    this unit hands to repr. }
  Result := 0;
  nm := pytype_name_v(x);
  for i := 1 to PYBT_LAST do
    if pybtype_name(i) = nm then
    begin
      Result := i;
      Exit;
    end;
end;

procedure pybtype_call1(const t: Variant; const a0: Variant; var res: Variant);
{ A PROCEDURE with a var result, not a Variant-returning function: this value is
  forwarded straight into the Result of pyvar_callv1, which is itself a Variant
  function, and that forward is the NRVO shape that corrupts
  (project_variant_fn_return_forward_nrvo_corruption). Measured, not assumed —
  as a function, `list("abc")` came back tagged int and printed empty while the
  scalar arms happened to survive. }
var code: Int64; tmp: Variant;
begin
  code := pybtype_code(t);
  case code of
    PYBT_STR:       res := pystr_of(a0);
    PYBT_INT:       res := pyint_v(a0);
    PYBT_FLOAT:     res := pyfloat_any(a0);   { parses a str too, as float() does }
    PYBT_BOOL:      res := pyvar_of_bool(pyvar_to_bool(a0));
    { through a LOCAL, never straight into Result: a Variant function result
      handed to a `var` parameter is the NRVO shape that corrupts
      (project_variant_fn_return_forward_nrvo_corruption — measured here as
      `list("abc")` printing an empty line). }
    PYBT_LIST:      begin PyObjAsVar(pylist_v(a0), tmp); res := tmp; end;
    PYBT_DICT:      begin PyObjAsVar(pydict_v(a0), tmp); res := tmp; end;
    PYBT_SET:       begin PyObjAsVar(pyset_of(a0), tmp); res := tmp; end;
  else
    { bytes / bytearray / tuple / frozenset through a NAME are not wired yet.
      Refused by name rather than silently answering something else — the same
      call the str-method-as-a-value arm makes for an arity it cannot express. }
    raise TypeError.Create(pybtype_name(code)
      + '() through a type held as a value is not supported yet');
  end;
end;

function pyconv_str(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_STR), a0, tmp);
  Result := tmp;
end;

function pyconv_int(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_INT), a0, tmp);
  Result := tmp;
end;

function pyconv_float(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_FLOAT), a0, tmp);
  Result := tmp;
end;

function pyconv_bool(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_BOOL), a0, tmp);
  Result := tmp;
end;

function pyconv_list(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_LIST), a0, tmp);
  Result := tmp;
end;

function pyconv_dict(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_DICT), a0, tmp);
  Result := tmp;
end;

function pyconv_set(const a0: Variant): Variant;
var tmp: Variant;
begin
  pybtype_call1(pybtype(PYBT_SET), a0, tmp);
  Result := tmp;
end;

procedure pybtype_call0(const t: Variant; var res: Variant);
var tmp: Variant;
begin
  { the empty value of the type — `list()`, `str()`, `int()`, spelled through a
    binding. Built by handing the conversion an empty value of its own shape,
    so there is no second table of "what is empty for this type". }
  case pybtype_code(t) of
    PYBT_STR:   res := '';
    PYBT_INT:   res := pyvar_of_int(0);
    PYBT_FLOAT: res := Double(0.0);
    PYBT_BOOL:  res := pyvar_of_bool(False);
    PYBT_LIST:  begin PyObjAsVar(TPyList.Create, tmp); res := tmp; end;
    PYBT_DICT:  begin PyObjAsVar(TPyDict.Create, tmp); res := tmp; end;
  else
    raise TypeError.Create(pybtype_name(pybtype_code(t))
      + '() through a type held as a value is not supported yet');
  end;
end;

function pytype_of_v(const x: Variant): Variant;
{ A FUNCTION, unlike pybtype_call0/1 beside it: this one is called straight from
  generated user code into an ordinary temp, which is the shape every other
  Variant-returning pylib entry (pyint_v, pyadd_v) already uses. The var-out
  form is only needed where the value is forwarded into ANOTHER Variant
  function's Result, which is the NRVO hazard. }
var code: Int64; o: Pointer;
begin
  { a builtin value answers with its builtin type object }
  code := pybtype_of_value(x);
  if code > 0 then begin Result := pybtype(code); Exit; end;
  { a user INSTANCE answers with its class object — the same VT_CLASSREF a
    class name binds to, so `type(a) == A` and `isinstance(a, A)` agree by
    construction rather than by two tables saying the same thing. }
  if (pyvartag(x) = 7) and (PPyVarRec(@x)^.Payload <> 0) then
  begin
    o := Pointer(NativeInt(PPyVarRec(@x)^.Payload));
    PPyVarRec(@Result)^.VType := 11;
    PPyVarRec(@Result)^.Payload := Int64(NativeInt(GetInstanceRTTI(o)));
    Exit;
  end;
  { None, and anything else with no type object of its own }
  Result := pybtype(PYBT_NONETYPE);
end;

function pyisinstance_v(const x: Variant; const t: Variant): Boolean;
{ `isinstance(x, t)` where t is a VALUE rather than a literal type name.

  The compile-time lowering resolves the second argument by NAME, which cannot
  see through a binding: `A = B` then `isinstance(x, A)` reported "unknown type
  in isinstance: A" even though `A(3)` had just constructed one — the alias is a
  perfectly good class OBJECT, it simply is not a class NAME. A tuple of types
  held in a name (`string_types = (str,)`, the six idiom) has the same shape.

  t may be a class object (VT_CLASSREF, payload = the RTTI blob) or a TUPLE of
  them, which CPython accepts anywhere a type is expected. Anything else answers
  False rather than raising: the literal-name path still handles every builtin
  type, so a non-class here means the program passed something that was never a
  type, and CPython raises TypeError for that — worth doing once the builtin
  types are values too, which is the other half of the ticket.
  bug-n-a-type-name-is-not-a-first-class-value }
var
  xo: TObject;
  want, curr: PClassRTTI;
  tl: TObject;
  i: Integer;
begin
  pyisinstance_v := False;
  { a TUPLE of types: True when ANY member matches, like CPython }
  if (pyvartag(t) = 7) and (PPyVarRec(@t)^.Payload <> 0) then
  begin
    tl := TObject(Pointer(NativeInt(PPyVarRec(@t)^.Payload)));
    if tl is TPyList then
    begin
      for i := 0 to TPyList(tl).count - 1 do
        if pyisinstance_v(x, TPyList(tl).at(i)) then
        begin
          pyisinstance_v := True;
          Exit;
        end;
      Exit;
    end;
  end;
  { t is a BUILTIN type held as a value — `text_type = str` then
    `isinstance(s, text_type)`, which is six's whole idiom. }
  if pyvartag(t) = 13 then                        { VT_BTYPE }
  begin
    { `isinstance(X, type)` — X is a class if it is a class OBJECT (tag 11) or
      a builtin type object (tag 13). Asked of the TAG, not of
      pybtype_of_value: `type`'s instances are the type objects themselves, and
      pytype_name_v already answers 'type' for both tags, so routing it through
      the name table would be the same test spelled indirectly. }
    if pybtype_code(t) = PYBT_TYPE then
    begin
      Result := (pyvartag(x) = 11) or (pyvartag(x) = 13);
      Exit;
    end;
    Result := pybtype_of_value(x) = pybtype_code(t);
    { `bool` is a SUBCLASS of `int` in Python, so isinstance(True, int) is True
      while type(True) is bool. The only subclass relation among the builtins
      here, and the one real program actually depend on. }
    if (not Result) and (pybtype_code(t) = PYBT_INT) and
       (pybtype_of_value(x) = PYBT_BOOL) then
      Result := True;
    Exit;
  end;
  if pyvartag(t) <> 11 then Exit;                 { VT_CLASSREF }
  want := PClassRTTI(Pointer(NativeInt(PPyVarRec(@t)^.Payload)));
  if want = nil then Exit;
  if pyvartag(x) <> 7 then Exit;                  { only an object can be an instance }
  if PPyVarRec(@x)^.Payload = 0 then Exit;
  xo := TObject(Pointer(NativeInt(PPyVarRec(@x)^.Payload)));
  curr := GetInstanceRTTI(Pointer(xo));
  { walk the instance's ancestry — isinstance is True for a DESCENDANT too }
  while curr <> nil do
  begin
    if curr = want then
    begin
      pyisinstance_v := True;
      Exit;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

{ `<class '__main__.A'>` — CPython's str()/repr() of a CLASS OBJECT, which is
  what a VT_CLASSREF variant holds (feature-nilpy-class-as-a-value). Unlike the
  function case above the name IS recoverable: the payload is the class's RTTI
  blob and its first word is the name pointer. `__main__` is spelled literally
  because a NilPy program IS the main module — a class reached as a value out of
  an imported module would want that module's name, and nothing records one. }
function PyClassRefStr(const v: Variant): AnsiString;
var cls: PClassRTTI; nm: AnsiString;
begin
  cls := PClassRTTI(Pointer(NativeInt(PPyVarRec(@v)^.Payload)));
  if cls = nil then nm := '?' else nm := '__main__.' + cls^.NamePtr^;
  Result := '<class ' + Chr(39) + nm + Chr(39) + '>';
end;

{ `__repr__` / `__str__` on a USER class instance that arrives only as a bare
  Variant handle — an element of a list, a dict value, a tuple slot.

  `print(p)` on a statically class-typed local renders correctly, because the
  frontend rewrites it to a direct call at COMPILE time keyed on the receiver's
  class. A container element has no static class for that rewrite to key on, so
  the element fell through to pyrepr_of, which knows nothing about user classes
  and produced the EMPTY string: `[p1, p2]` printed `[, ]`.

  The dispatch itself is not new machinery — the class RTTI carries the method
  table, and pyeval already finds a method by NAME in it and calls it through a
  typed pointer (PyFindMethCI/PyHostCall). This is the same lookup, made from
  the renderer that needed it. Only the ZERO-ARGUMENT, AnsiString-returning
  shape is accepted, which is what `def __repr__(self) -> str` compiles to; any
  other shape is left to the existing fallback rather than called through a
  pointer whose ABI has not been checked.

  Returns False when the class defines no such dunder, so the caller keeps its
  old behaviour — CPython prints `<module.Class object at 0x...>` there, which
  carries an address and so is not reproducible anyway.
  bug-nilpy-list-of-custom-objects-loses-repr-str }
type
  TPyDunderFn = function(self: Pointer): AnsiString;

function PyFindDunder(cls: PClassRTTI; const nm: AnsiString): PMethInfo;
begin
  PyFindDunder := PyFindMethByName(cls, nm);
end;

{ The __eq__ half of the same dispatch — see the forward declaration above
  PyVarEq for why it lives here.

  Only the shape `def __eq__(self, other) -> bool` is called, verified against
  the RTTI rather than assumed: Arity 2, RetKind tyBoolean (2), and the second
  ParamKind tyVariant (22). That IS what the frontend emits — measured with
  `PXXDBG=a.ir:H.__eq__`, whose `other` arrives as a `const Variant` (an `lea`
  of the slot). Anything else falls through to the caller's identity answer
  rather than being called through a pointer whose ABI has not been checked.

  CPython tries `a.__eq__(b)` and then the REFLECTED `b.__eq__(a)` when the
  first returns NotImplemented. There is no NotImplemented here, so the
  reflection is used only when `a`'s class has no __eq__ at all — which is what
  makes `plain_obj == H(3)` still consult H's. }
type
  TPyEqFn = function(self: Pointer; const other: Variant): Boolean;
  { ...and the shape a @dataclass-GENERATED __eq__ has, whose `other` is a bare
    class pointer rather than a variant. Two shapes, measured with
    `PXXDBG=a.ir:<Class>.__eq__`: a hand-written `def __eq__(self, other)`
    leaves `other` unannotated, so it arrives tk=22 (Variant), while the
    generated one is emitted class-typed, tk=6. Checking only the first shape
    fixed hand-written classes and left every dataclass still comparing by
    handle. }
  TPyEqObjFn = function(self: Pointer; other: Pointer): Boolean;
  TPyHashFn  = function(self: Pointer): Int64;
  { ...and the shape an UNANNOTATED `def __hash__(self)` actually has. NilPy
    types an unannotated def's result as a Variant (RetKind 22), which is the
    ordinary way to write the dunder — `-> int` is the exception, not the rule.
    Only the Int64 shape was declared, so the guard below rejected every plain
    `def __hash__` and the key silently fell back to an identity hash.
    bug-nilpy-a-user-hash-dunder-is-ignored-for-dict-keys }
  TPyHashVFn = function(self: Pointer): Variant;
  TPyObjDunderFn    = function(self: Pointer; const other: Variant): Pointer;
  TPyObjDunderObjFn = function(self: Pointer; other: Pointer): Pointer;
  { An ARITHMETIC dunder returns whatever the body returns, so the call has to
    be typed by the method's RetKind rather than assumed. Only the
    Variant-`other` shape is declared: a hand-written `def __add__(self, q)`
    leaves `q` unannotated, which is tk=22, and unlike __eq__ there is no
    dataclass-GENERATED arithmetic dunder to produce the class-pointer shape.
    Any other parameter shape falls through to the caller's existing path. }
  TPyArithV = function(self: Pointer; const other: Variant): Variant;
  TPyArithS = function(self: Pointer; const other: Variant): AnsiString;
  TPyArithI = function(self: Pointer; const other: Variant): Int64;
  TPyArithD = function(self: Pointer; const other: Variant): Double;
  TPyArithB = function(self: Pointer; const other: Variant): Boolean;
  TPyArithO = function(self: Pointer; const other: Variant): Pointer;

{ ONE dunder call, shared by every boolean binary dunder this unit dispatches
  at run time. Looks `dunder` up on selfObj's class and calls it with otherObj,
  answering False when the class has no method of that name in a shape whose ABI
  has been checked. The reflection rules differ per operator, so they live in
  the callers; this only does the lookup and the call.

  Written as one routine deliberately: the __eq__ version was the third copy of
  "find a dunder in the RTTI and call it" in this file, and adding __gt__/__lt__
  would have made a fourth. See
  refactor-nilpy-three-places-decide-a-locals-class-identity for the same
  lesson one level up. }
function PyUserObjBoolDunder(selfObj, otherObj: TObject; const otherV: Variant;
                             const dunder: AnsiString; var res: Boolean): Boolean;
var cls: PClassRTTI; mi: PMethInfo; fn: TPyEqFn; fnObj: TPyEqObjFn; pk: PInt64;
begin
  PyUserObjBoolDunder := False;
  if (selfObj = nil) or (otherObj = nil) then Exit;
  { this unit's own containers have their own value rules and must not come here
    (PyRecIsPylibOwnClass's runtime equivalent) }
  if (selfObj is TPyList) or (selfObj is TPyDict) or (selfObj is TPyBytes) then Exit;
  if (otherObj is TPyList) or (otherObj is TPyDict) or (otherObj is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(selfObj));
  if cls = nil then Exit;
  mi := PyFindDunder(cls, dunder);
  if mi = nil then Exit;
  if mi^.Arity <> 2 then Exit;
  if mi^.RetKind <> 2 then Exit;              { Boolean }
  if mi^.ParamKinds = nil then Exit;
  pk := PInt64(mi^.ParamKinds);
  if pk[1] = 22 then                          { `other` is a Variant }
  begin
    fn := TPyEqFn(mi^.Code);
    res := fn(Pointer(selfObj), otherV);
    PyUserObjBoolDunder := True;
    Exit;
  end;
  if pk[1] = 6 then                           { `other` is a class pointer }
  begin
    { A class-typed `other` is only safe to pass an instance of THAT class: the
      body reads its fields at fixed offsets and would otherwise read an
      unrelated layout — the same wrong-offset failure as
      bug-nilpy-local-reassigned-across-classes-keeps-one-static-class.
      Requiring the EXACT class is also what CPython's own dataclass __eq__
      does (`if other.__class__ is self.__class__`), returning NotImplemented
      otherwise — which falls back to identity, i.e. exactly the False the
      caller is left with. So `P(3) == "x"` and `P(3) == Q(3)` stay False
      instead of reading a Q as a P. }
    if GetInstanceRTTI(Pointer(selfObj)) <> GetInstanceRTTI(Pointer(otherObj)) then Exit;
    fnObj := TPyEqObjFn(mi^.Code);
    res := fnObj(Pointer(selfObj), Pointer(otherObj));
    PyUserObjBoolDunder := True;
    Exit;
  end;
end;

{ `o.<dunder>()` with no arguments, answering the result as a Variant. The
  return SHAPE is read from the RTTI rather than assumed, exactly as the binary
  dunders do: an unannotated `def __next__(self)` is RetKind 22 (Variant), which
  is how the dunder is ordinarily written, but `-> int` and `-> str` are both
  ordinary too and each has its own ABI. Anything else is declined (False)
  rather than called through a pointer whose shape has not been checked.

  A procedure (RetKind 0) is declined as well: `__next__` that returns nothing
  is not the protocol, and calling it as a function would read a garbage
  register. }
type
  { the shapes a no-argument dunder can have — declared at unit level beside the
    binary-dunder shapes above, not inside the routine }
  TNoArgV = function(self: Pointer): Variant;
  TNoArgO = function(self: Pointer): Pointer;
  TNoArgI = function(self: Pointer): Int64;
  TNoArgS = function(self: Pointer): AnsiString;
  TNoArgB = function(self: Pointer): Boolean;
  TNoArgD = function(self: Pointer): Double;
  { ...and the one-STRING-argument / one-VARIANT-argument shapes, for
    __getattr__. Same return fan: the dunder is usually unannotated (Variant),
    but `-> str` is just as ordinary a way to write it. }
  TStrArgV = function(self: Pointer; const a: AnsiString): Variant;
  TStrArgO = function(self: Pointer; const a: AnsiString): Pointer;
  TStrArgI = function(self: Pointer; const a: AnsiString): Int64;
  TStrArgS = function(self: Pointer; const a: AnsiString): AnsiString;
  TStrArgB = function(self: Pointer; const a: AnsiString): Boolean;
  TStrArgD = function(self: Pointer; const a: AnsiString): Double;
  TVarArgV = function(self: Pointer; const a: Variant): Variant;
  TVarArgO = function(self: Pointer; const a: Variant): Pointer;
  TVarArgI = function(self: Pointer; const a: Variant): Int64;
  TVarArgS = function(self: Pointer; const a: Variant): AnsiString;
  TVarArgB = function(self: Pointer; const a: Variant): Boolean;
  TVarArgD = function(self: Pointer; const a: Variant): Double;

{ `o.__getattr__(name)` — the LAST step of CPython's attribute lookup, reached
  only after the instance dict and the declared members have both missed. The
  name argument is a str, but an unannotated `def __getattr__(self, name)` types
  it as a Variant, which is how the dunder is ordinarily written, so both
  parameter shapes are dispatched; the return shape comes from the RTTI exactly
  as PyUserObjNoArgDunder reads it. bug-nilpy-getattr-dunder-not-supported }
function PyUserObjGetattr(o: TObject; const name: AnsiString;
                          var res: Variant): Boolean;
var cls: PClassRTTI; mi: PMethInfo; pk: PInt64; nv: Variant;
    gv: TStrArgV; go: TStrArgO; gi: TStrArgI; gs: TStrArgS;
    gb: TStrArgB; gd: TStrArgD;
    vv: TVarArgV; vo: TVarArgO; vi: TVarArgI; vs: TVarArgS;
    vb: TVarArgB; vd: TVarArgD;
    pkind: Int64;
begin
  PyUserObjGetattr := False;
  if o = nil then Exit;
  { this unit's own containers resolve their attributes themselves }
  if (o is TPyList) or (o is TPyDict) or (o is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  mi := PyFindDunder(cls, '__getattr__');
  if mi = nil then Exit;
  if mi^.Arity <> 2 then Exit;               { self + name }
  if mi^.ParamKinds = nil then Exit;
  pk := PInt64(mi^.ParamKinds);
  pkind := pk[1];
  if pkind = 22 then
  begin
    nv := name;               { VT_STRING by ordinary variant assignment }
    if mi^.RetKind = 22 then begin vv := TVarArgV(mi^.Code); res := vv(Pointer(o), nv); end
    else if mi^.RetKind = 6 then begin vo := TVarArgO(mi^.Code); res := TObject(vo(Pointer(o), nv)); end
    else if (mi^.RetKind = 13) or (mi^.RetKind = 1) or (mi^.RetKind = 15) or
            (mi^.RetKind = 11) then begin vi := TVarArgI(mi^.Code); res := vi(Pointer(o), nv); end
    else if mi^.RetKind = 23 then begin vs := TVarArgS(mi^.Code); res := vs(Pointer(o), nv); end
    else if mi^.RetKind = 2 then begin vb := TVarArgB(mi^.Code); res := vb(Pointer(o), nv); end
    else if mi^.RetKind = 19 then begin vd := TVarArgD(mi^.Code); res := vd(Pointer(o), nv); end
    else Exit;
    PyUserObjGetattr := True;
    Exit;
  end;
  if pkind = 23 then
  begin
    if mi^.RetKind = 22 then begin gv := TStrArgV(mi^.Code); res := gv(Pointer(o), name); end
    else if mi^.RetKind = 6 then begin go := TStrArgO(mi^.Code); res := TObject(go(Pointer(o), name)); end
    else if (mi^.RetKind = 13) or (mi^.RetKind = 1) or (mi^.RetKind = 15) or
            (mi^.RetKind = 11) then begin gi := TStrArgI(mi^.Code); res := gi(Pointer(o), name); end
    else if mi^.RetKind = 23 then begin gs := TStrArgS(mi^.Code); res := gs(Pointer(o), name); end
    else if mi^.RetKind = 2 then begin gb := TStrArgB(mi^.Code); res := gb(Pointer(o), name); end
    else if mi^.RetKind = 19 then begin gd := TStrArgD(mi^.Code); res := gd(Pointer(o), name); end
    else Exit;
    PyUserObjGetattr := True;
    Exit;
  end;
end;

{ The PRESENCE question for __getattr__, which CPython answers by CALLING it
  and catching AttributeError — `hasattr` is defined as "getattr does not
  raise", and a __getattr__ that refuses some names (the ordinary way to write
  one) must therefore be run to find out. bug-nilpy-getattr-dunder-not-supported }
function PyUserObjGetattrTry(o: TObject; const name: AnsiString;
                             var res: Variant): Boolean;
begin
  PyUserObjGetattrTry := False;
  try
    PyUserObjGetattrTry := PyUserObjGetattr(o, name, res);
  except
    on AttributeError do PyUserObjGetattrTry := False;
  end;
end;

function PyUserObjNoArgDunder(o: TObject; const dunder: AnsiString;
                              var res: Variant): Boolean;
var cls: PClassRTTI; mi: PMethInfo;
    fv: TNoArgV; fo: TNoArgO; fi: TNoArgI; fs: TNoArgS; fb: TNoArgB; fd: TNoArgD;
    ro: TObject;
begin
  PyUserObjNoArgDunder := False;
  if o = nil then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  mi := PyFindDunder(cls, dunder);
  if mi = nil then Exit;
  if mi^.Arity <> 1 then Exit;             { `self` only }
  if mi^.RetKind = 22 then
  begin
    fv := TNoArgV(mi^.Code);
    res := fv(Pointer(o));
    PyUserObjNoArgDunder := True;
    Exit;
  end;
  if mi^.RetKind = 6 then
  begin
    fo := TNoArgO(mi^.Code);
    ro := fo(Pointer(o));
    if ro <> nil then PXXObjRetain(Pointer(ro));
    res := TObject(ro);
    PyUserObjNoArgDunder := True;
    Exit;
  end;
  if (mi^.RetKind = 13) or (mi^.RetKind = 1) or (mi^.RetKind = 15) or
     (mi^.RetKind = 11) then
  begin
    fi := TNoArgI(mi^.Code);
    res := fi(Pointer(o));
    PyUserObjNoArgDunder := True;
    Exit;
  end;
  if mi^.RetKind = 23 then
  begin
    fs := TNoArgS(mi^.Code);
    res := fs(Pointer(o));
    PyUserObjNoArgDunder := True;
    Exit;
  end;
  if mi^.RetKind = 2 then
  begin
    fb := TNoArgB(mi^.Code);
    res := fb(Pointer(o));
    PyUserObjNoArgDunder := True;
    Exit;
  end;
  if mi^.RetKind = 19 then
  begin
    fd := TNoArgD(mi^.Code);
    res := fd(Pointer(o));
    PyUserObjNoArgDunder := True;
    Exit;
  end;
end;

{ Does this object's class declare the dunder at all? The presence question,
  separate from the call: `iter()` has to tell "no `__next__`" (a TypeError)
  from "`__next__` in a shape we decline", and the two need different words. }
function PyUserObjHasDunder(o: TObject; const dunder: AnsiString): Boolean;
var cls: PClassRTTI;
begin
  PyUserObjHasDunder := False;
  if o = nil then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  PyUserObjHasDunder := PyFindDunder(cls, dunder) <> nil;
end;

{ The object-RETURNING sibling of PyUserObjBoolDunder, for a dunder whose result
  is a value rather than a flag (`__divmod__` returns a 2-tuple, i.e. a TPyList).
  Same two `other` shapes and the same exact-class guard on the class-pointer
  one; the return must be a class (RetKind 6), and the caller checks what class
  it actually got. }
function PyUserObjObjDunder(selfObj, otherObj: TObject; const otherV: Variant;
                            const dunder: AnsiString; var res: TObject): Boolean;
var cls: PClassRTTI; mi: PMethInfo; fn: TPyObjDunderFn; fnObj: TPyObjDunderObjFn;
    pk: PInt64;
begin
  PyUserObjObjDunder := False;
  if (selfObj = nil) or (otherObj = nil) then Exit;
  if (selfObj is TPyList) or (selfObj is TPyDict) or (selfObj is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(selfObj));
  if cls = nil then Exit;
  mi := PyFindDunder(cls, dunder);
  if mi = nil then Exit;
  if mi^.Arity <> 2 then Exit;
  if mi^.RetKind <> 6 then Exit;              { returns a class (the tuple) }
  if mi^.ParamKinds = nil then Exit;
  pk := PInt64(mi^.ParamKinds);
  if pk[1] = 22 then
  begin
    fn := TPyObjDunderFn(mi^.Code);
    res := TObject(fn(Pointer(selfObj), otherV));
    PyUserObjObjDunder := True;
    Exit;
  end;
  if pk[1] = 6 then
  begin
    if GetInstanceRTTI(Pointer(selfObj)) <> GetInstanceRTTI(Pointer(otherObj)) then Exit;
    fnObj := TPyObjDunderObjFn(mi^.Code);
    res := TObject(fnObj(Pointer(selfObj), Pointer(otherObj)));
    PyUserObjObjDunder := True;
    Exit;
  end;
end;

{ Call ONE arithmetic dunder, converting its result to a Variant by the RetKind
  the RTTI declares. Every kind the frontend actually emits for a `return` is
  covered — measured with `PXXDBG=a.ir:<Class>.__add__` over bodies returning a
  str, an int, a float, a bool, a list and a mixed pair — and an unrecognised
  kind answers False so the caller keeps its existing behaviour rather than
  calling through a pointer whose ABI has not been checked. }
function PyUserArithCall1(selfObj, otherObj: TObject; const otherV: Variant;
                          const dunder: AnsiString; var res: Variant): Boolean;
var cls: PClassRTTI; mi: PMethInfo; pk: PInt64; rk: Int64;
    fv: TPyArithV; fs: TPyArithS; fi: TPyArithI; fd: TPyArithD;
    fb: TPyArithB; fo: TPyArithO;
    sres: AnsiString; ores: Pointer; r: PPyVarRec;
begin
  PyUserArithCall1 := False;
  { `otherObj` is NOT required, and never was used: the only parameter shape
    this accepts is a Variant (the pk[1] test below), so the other operand
    travels as `otherV` and may be an int, a str or anything else. Demanding an
    object here made `divmod(D(17), 5)` — a user class and a plain number, the
    ordinary spelling — fall through to the numeric path and die with runtime
    error 219 (bug-nilpy-divmod-on-a-user-class-dies-with-runtime-error-219).
    The parameter stays for the reflected call sites' symmetry. }
  if selfObj = nil then Exit;
  if (selfObj is TPyList) or (selfObj is TPyDict) or (selfObj is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(selfObj));
  if cls = nil then Exit;
  mi := PyFindDunder(cls, dunder);
  if mi = nil then Exit;
  if mi^.Arity <> 2 then Exit;
  if mi^.ParamKinds = nil then Exit;
  pk := PInt64(mi^.ParamKinds);
  if pk[1] <> 22 then Exit;               { `other` must be a Variant }
  rk := mi^.RetKind;
  r := PPyVarRec(@res);
  if rk = 22 then
  begin
    fv := TPyArithV(mi^.Code); res := fv(Pointer(selfObj), otherV);
  end
  else if (rk = 23) or (rk = 4) then
  begin
    fs := TPyArithS(mi^.Code); sres := fs(Pointer(selfObj), otherV);
    r^.VType := 6; PPyAnsiString(@r^.Payload)^ := sres;
  end
  else if (rk = 13) or (rk = 1) or (rk = 11) or (rk = 15) then
  begin
    fi := TPyArithI(mi^.Code);
    r^.VType := 2; r^.Payload := fi(Pointer(selfObj), otherV);
  end
  else if (rk = 19) or (rk = 18) then
  begin
    fd := TPyArithD(mi^.Code);
    r^.VType := 3; PPyDouble(@r^.Payload)^ := fd(Pointer(selfObj), otherV);
  end
  else if rk = 2 then
  begin
    fb := TPyArithB(mi^.Code);
    r^.VType := 4;
    if fb(Pointer(selfObj), otherV) then r^.Payload := 1 else r^.Payload := 0;
  end
  else if rk = 6 then
  begin
    fo := TPyArithO(mi^.Code); ores := fo(Pointer(selfObj), otherV);
    if ores = nil then Exit;
    r^.VType := 7; r^.Payload := Int64(NativeInt(ores));
    PXXObjRetain(ores);
  end
  else
    Exit;
  PyUserArithCall1 := True;
end;

{ Box an object handle as a VT_OBJECT variant, for handing the REFLECTED operand
  to a Variant-shaped dunder.

  It RETAINS. The first version did not — "the variant is only a borrowed view
  for the call below it" — and that is wrong, because the variant is a LOCAL:
  its scope exit runs PXXVarClear, which releases an object-tagged slot. So
  boxing without a retain hands back a net release of the CALLER's object.
  Measured as `repr(c)` followed by `repr([c])` on the same variable —
  the first call freed `c` and the second read freed memory (SIGSEGV). Each on
  its own was fine, which is what makes this shape easy to ship. }
procedure PyObjAsVar(o: TObject; var v: Variant);
begin
  PPyVarRec(@v)^.VType := 7;
  PPyVarRec(@v)^.Payload := Int64(NativeInt(Pointer(o)));
  PXXObjRetain(Pointer(o));
end;

function PyUserObjEq(pobj, qobj: TObject; const qv: Variant;
                     var res: Boolean): Boolean;
var pv: Variant;
begin
  { a.__eq__(b), then the REFLECTED b.__eq__(a). There is no NotImplemented
    here, so the reflection fires only when a's class has no __eq__ at all —
    which is what makes `plain_obj == H(3)` still consult H's. }
  PyUserObjEq := PyUserObjBoolDunder(pobj, qobj, qv, '__eq__', res);
  if PyUserObjEq then Exit;
  PyObjAsVar(pobj, pv);
  PyUserObjEq := PyUserObjBoolDunder(qobj, pobj, pv, '__eq__', res);
end;

{ `a > b` for two user objects, which is what `.sort()` / `sorted()` ask for
  through pyvar_gt. CPython tries `a.__gt__(b)` and then the reflected
  `b.__lt__(a)` — and the reflected arm is the one that matters in practice,
  because the idiomatic class defines ONLY __lt__ (that is all Python's sort
  requires) and so has no __gt__ to find.
  bug-nilpy-list-sort-ignores-lt-dunder-on-objects }
function PyUserObjGt(pobj, qobj: TObject; const qv: Variant;
                     var res: Boolean): Boolean;
var pv: Variant;
begin
  PyUserObjGt := PyUserObjBoolDunder(pobj, qobj, qv, '__gt__', res);
  if PyUserObjGt then Exit;
  PyObjAsVar(pobj, pv);
  PyUserObjGt := PyUserObjBoolDunder(qobj, pobj, pv, '__lt__', res);
end;

{ `a <op> b` on two user objects: the direct dunder, then the REFLECTED one on
  the other operand — CPython's own order. This is the runtime twin of the
  compile-time dispatch in the parser, which cannot fire when an operand's
  static type is a variant: a module global bound to a scalar BEFORE the class
  instance is one ordinary way to get one (`other = 0` then `other = V(1)`),
  and the symptom was a bare `TypeError: expected a number, got object` on an
  `__add__` the program plainly declares.
  bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch }
function PyUserObjArith(pobj, qobj: TObject; const pv, qv: Variant;
                        const dunder, rdunder: AnsiString;
                        var res: Variant): Boolean;
begin
  PyUserObjArith := PyUserArithCall1(pobj, qobj, qv, dunder, res);
  if PyUserObjArith then Exit;
  PyUserObjArith := PyUserArithCall1(qobj, pobj, pv, rdunder, res);
end;

{ `a < b`, the mirror of PyUserObjGt: __lt__ direct, then the reflected __gt__.
  Needed on its own because pycmp_v owes a THREE-way answer, so "not greater"
  is not the same question as "less". }
function PyUserObjLt(pobj, qobj: TObject; const qv: Variant;
                     var res: Boolean): Boolean;
var pv: Variant;
begin
  PyUserObjLt := PyUserObjBoolDunder(pobj, qobj, qv, '__lt__', res);
  if PyUserObjLt then Exit;
  PyObjAsVar(pobj, pv);
  PyUserObjLt := PyUserObjBoolDunder(qobj, pobj, pv, '__gt__', res);
end;

{ `divmod(a, b)`: a.__divmod__(b), then the reflected b.__rdivmod__(a). The
  result must be a TPyList (Python's contract is "a pair"); anything else is
  left to the caller's fallback rather than cast to a tuple it is not. }
function PyUserObjDivmod(pobj, qobj: TObject; const pv, qv: Variant;
                         var res: TObject): Boolean;
var rv: Variant; o: TObject;
begin
  { Through PyUserArithCall1, the dispatcher that covers every RetKind the
    frontend emits, rather than PyUserObjObjDunder, which demanded RetKind 6 (a
    declared class). An unannotated `def __divmod__(self, o): return (a, b)`
    returns a VARIANT — RetKind 22 — so the guard rejected the method, the
    caller's fallback cast a value that was not a TPyList, and the program died
    with a bare runtime error 219 naming neither divmod nor the class. Same
    guard, same symptom, as the __hash__ one below.

    The pair is unboxed here and RETAINED: `rv` is a LOCAL variant, so its scope
    exit runs PXXVarClear and releases an object-tagged slot — see PyObjAsVar's
    note. Anything that is not a TPyList answers False and leaves the caller its
    fallback, which is Python's contract ("a pair") kept rather than cast. }
  PyUserObjDivmod := PyUserArithCall1(pobj, qobj, qv, '__divmod__', rv);
  if not PyUserObjDivmod then
    PyUserObjDivmod := PyUserArithCall1(qobj, pobj, pv, '__rdivmod__', rv);
  if not PyUserObjDivmod then Exit;
  PyUserObjDivmod := False;
  if pyvartag(rv) <> 7 then Exit;
  o := TObject(pyvarobj(rv));
  if not (o is TPyList) then Exit;
  PXXObjRetain(Pointer(o));
  res := o;
  PyUserObjDivmod := True;
end;

{ See the forward declaration above PyVarEq. Only `def __hash__(self) -> int`
  is called: Arity 1 and an integer RetKind (tyInt64 13, or tyInteger 1 /
  tyNativeInt 15 should the frontend ever narrow it). CPython truncates a
  __hash__ result to Py_hash_t, and this hash is avalanched by the caller
  afterwards, so any int width is fine to take verbatim here. }
function PyUserObjHash(o: TObject; var h: NativeUInt): Boolean;
var cls: PClassRTTI; mi: PMethInfo; fn: TPyHashFn; vfn: TPyHashVFn; hv: Variant;
begin
  PyUserObjHash := False;
  if o = nil then Exit;
  if (o is TPyList) or (o is TPyDict) or (o is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  mi := PyFindDunder(cls, '__hash__');
  if mi = nil then Exit;
  if mi^.Arity <> 1 then Exit;
  { RetKind 22 = Variant, which is what an UNANNOTATED `def __hash__(self)`
    returns — the ordinary spelling. Rejecting it meant the dunder was never
    called and the key hashed by IDENTITY, so two __eq__-equal objects landed in
    different buckets and `k2 in d` was False for a key the dict held. It was
    also NONDETERMINISTIC, which is the tell: whether two identity hashes
    collide is a property of the run's memory layout and nothing else. Adding
    `-> int` to the same dunder made the whole repro pass, which is what
    isolated this guard.
    CPython requires __hash__ to return an int; a variant that is not int-valued
    folds through pyvar_to_int the same way any other integer context does.
    bug-nilpy-a-user-hash-dunder-is-ignored-for-dict-keys }
  if mi^.RetKind = 22 then
  begin
    vfn := TPyHashVFn(mi^.Code);
    hv := vfn(Pointer(o));
    h := NativeUInt(pyvar_to_int(hv));
    PyUserObjHash := True;
    Exit;
  end;
  if (mi^.RetKind <> 13) and (mi^.RetKind <> 1) and (mi^.RetKind <> 15) then Exit;
  fn := TPyHashFn(mi^.Code);
  h := NativeUInt(fn(Pointer(o)));
  PyUserObjHash := True;
end;

function PyUserObjUnhashable(o: TObject): Boolean;
var cls: PClassRTTI;
begin
  PyUserObjUnhashable := False;
  if o = nil then Exit;
  { the pylib containers are not user classes; a TPyList doubles as the tuple
    key type and hashes by its elements }
  if (o is TPyList) or (o is TPyDict) or (o is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  if PyFindDunder(cls, '__eq__') = nil then Exit;      { identity-hashable }
  if PyFindDunder(cls, '__hash__') <> nil then Exit;   { both halves supplied }
  PyUserObjUnhashable := True;
end;

function PyUserObjStr(o: TObject; wantRepr: Boolean; var outS: AnsiString): Boolean;
var cls: PClassRTTI; mi: PMethInfo; fn: TPyDunderFn;
begin
  PyUserObjStr := False;
  if o = nil then Exit;
  { pylib's OWN containers have their own renderers and must not come here }
  if (o is TPyList) or (o is TPyDict) or (o is TPyBytes) then Exit;
  cls := GetInstanceRTTI(Pointer(o));
  if cls = nil then Exit;
  mi := nil;
  { CPython: str() prefers __str__ and falls back to __repr__; repr() uses
    __repr__ only. Inside a CONTAINER both render with repr, which is why the
    callers below pass wantRepr = True. }
  if not wantRepr then mi := PyFindDunder(cls, '__str__');
  if mi = nil then mi := PyFindDunder(cls, '__repr__');
  { An EXCEPTION with no __repr__ of its own: CPython prints `ValueError('v')`,
    not an address. That is what appears in a log or a `%r`, and an address there
    is useless. Only for repr() — str(e) is the message, which already works.

    TWO documented approximations, because a pxx Exception carries a single
    Message string rather than Python's `args` tuple:

      - an EMPTY message renders as `ValueError()`, the zero-argument form.
        `ValueError('')` is indistinguishable from `ValueError()` here and takes
        the same rendering; the zero-argument spelling is much the commoner.
    KEYERROR IS DELIBERATELY EXCLUDED and keeps the address form. It cannot be
    rendered correctly from a Message alone: CPython's KeyError is the one
    builtin whose str() is repr(arg), and PyKeyError stores the message ALREADY
    REPR'D so that str() matches. Quoting that again gives
    `KeyError("'nope'")`; not quoting it gives `KeyError(k)` for a
    user-constructed `KeyError("k")`. Both are wrong, in opposite cases, and
    which one you hit depends on who raised it — so neither is shipped. The real
    fix is `e.args`, which is its own open item; guessing here would be worse
    than the address, because an address is obviously unhelpful while a wrongly
    quoted key looks authoritative.
    bug-nilpy-exception-str-and-repr-diverge-from-cpython }
  { str() of an exception is its MESSAGE. A CAUGHT exception already reached
    that through another path; one that was CONSTRUCTED and never raised
    (`str(ValueError("v"))`, or an exception held in a list) fell through to the
    address form here — two paths disagreeing about the same object.

    KeyError comes out right for free on the raise path, because PyKeyError
    stores its message already repr'd, which is exactly what CPython's
    str(KeyError) is. A user-CONSTRUCTED `KeyError("k")` still loses the quotes;
    that is the `e.args` gap, and the message is a strict improvement on an
    address either way. }
  if (mi = nil) and (not wantRepr) and (o is Exception) then
  begin
    { KeyError is the one builtin whose str() is the REPR of its argument —
      `str(KeyError('inner'))` is "'inner'", with the quotes. That used to come
      out right only on the RAISE path, because PyKeyError stores the message
      already repr'd, and wrong for a user-constructed KeyError. Now that
      `args` exists, both are the same question asked of the same place: repr
      the single argument. A KeyError carrying zero or several arguments falls
      through to the message, as CPython's own __str__ does.
      bug-nilpy-exception-args-attribute-missing }
    if (o is KeyError) and (Exception(o).GetArgs <> nil) and
       (Exception(o).GetArgs.count = 1) then
      outS := pyvar_repr(Exception(o).GetArgs.at(0))
    else
      outS := Exception(o).Message;
    PyUserObjStr := True;
    Exit;
  end;
  { KeyError is no longer excluded here. It was, because its message is stored
    already repr'd on the raise path and quoting that again gives
    KeyError("'nope'") while not quoting it gives KeyError(k) for a
    user-constructed one — both wrong, in opposite cases, depending on who
    raised. `args` settles it: repr the ARGUMENT, whoever built the exception,
    and the two cases agree.
    bug-nilpy-exception-args-attribute-missing }
  if (mi = nil) and wantRepr and (o is KeyError) and
     (Exception(o).GetArgs <> nil) and (Exception(o).GetArgs.count = 1) then
  begin
    outS := TObject(o).ClassName + '(' + pyvar_repr(Exception(o).GetArgs.at(0)) + ')';
    PyUserObjStr := True;
    Exit;
  end;
  if (mi = nil) and wantRepr and (o is Exception) and (not (o is KeyError)) then
  begin
    if Exception(o).Message = '' then
      outS := TObject(o).ClassName + '()'
    else
      outS := TObject(o).ClassName + '(' + pyrepr_of(Exception(o).Message) + ')';
    PyUserObjStr := True;
    Exit;
  end;
  if mi = nil then
  begin
    { No dunder: CPython's DEFAULT object repr, `<__main__.Cls object at 0x..>`.
      Not matchable line-for-line by a test (it carries an address), but it is
      the right shape and strictly better than the EMPTY string this used to
      render — an object silently vanishing out of a printed container is the
      failure this ticket is about. }
    outS := '<__main__.' + TObject(o).ClassName
             + ' object at ' + hex(Int64(NativeInt(Pointer(o)))) + '>';
    PyUserObjStr := True;
    Exit;
  end;
  if mi^.Arity <> 1 then Exit;          { Self only }
  if mi^.RetKind <> 23 then Exit;       { AnsiString }
  fn := TPyDunderFn(mi^.Code);
  outS := fn(Pointer(o));
  PyUserObjStr := True;
end;

function pyvar_repr(const v: Variant): AnsiString;
var o: TObject; us: AnsiString;
begin
  if pyvartag(v) = 0 then begin Result := 'None'; Exit; end;   { VT_EMPTY }
  { a callable VALUE — see PyCallableStr }
  if PyVarIsCallableTag(v) then
  begin Result := PyCallableStr(v); Exit; end;
  { a CLASS reached as a value renders as CPython's class object }
  if pyvartag(v) = 11 then begin Result := PyClassRefStr(v); Exit; end;
  { ...and a BUILTIN type reached as a value, the same way }
  if pyvartag(v) = 13 then begin Result := pybtype_repr(v); Exit; end;
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := pylist_repr(TPyList(o)); Exit; end;
    if o is TPyDict then begin Result := pydict_repr(TPyDict(o)); Exit; end;
    if o is TPyBytes then begin Result := pybytes_repr(TPyBytes(o)); Exit; end;
    { a cursor reprs as CPython's `<map object at 0x...>` — it does NOT render
      its contents, because reading them would CONSUME it }
    if o is TPyIter then begin Result := pyiter_repr(TPyIter(o)); Exit; end;
    { a range reprs as `range(0, 3)` — it does NOT print its values, which is
      the visible half of being lazy }
    if o is TPyRange then begin Result := pyrange_repr(TPyRange(o)); Exit; end;
    if PyUserObjStr(o, True, us) then begin Result := us; Exit; end;
  end;
  { the scalar/string tail, INLINE rather than delegating to pyrepr_of. The two
    used to call each other in the wrong direction — pyrepr_of was the entry
    point everything reached and it knew nothing about objects, while pyvar_repr
    knew about objects and then handed the rest back. Now pyvar_repr is the ONE
    implementation and pyrepr_of(Variant) forwards to it, which is what makes
    an f-string's `!r` hole render a user instance instead of ''.
    A STRING and a CHAR gain quotes: Python has no character type, so `s[0]`
    reprs like any other one-character str.
    bug-nilpy-repr-of-a-variant-holding-an-object-is-empty }
  if (pyvartag(v) = 6) or (pyvartag(v) = 5) then
    Result := PyReprQuote(VariantToStr(v))
  else
    Result := pystr_of(v);
end;

function pyvar_print_of(const v: Variant): AnsiString;
var o: TObject; us: AnsiString;
begin
  if PyVarIsCallableTag(v) then
  begin Result := PyCallableStr(v); Exit; end;
  { a CLASS reached as a value renders as CPython's class object }
  if pyvartag(v) = 11 then begin Result := PyClassRefStr(v); Exit; end;
  { ...and a BUILTIN type reached as a value, the same way }
  if pyvartag(v) = 13 then begin Result := pybtype_repr(v); Exit; end;
  { a container prints as its repr; every scalar as plain str (no quotes) }
  if pyvartag(v) = 7 then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyList then begin Result := pylist_repr(TPyList(o)); Exit; end;
    if o is TPyDict then begin Result := pydict_repr(TPyDict(o)); Exit; end;
    if o is TPyBytes then begin Result := pybytes_repr(TPyBytes(o)); Exit; end;
    if o is TPyIter then begin Result := pyiter_repr(TPyIter(o)); Exit; end;
    if o is TPyRange then begin Result := pyrange_repr(TPyRange(o)); Exit; end;
    { a bare print() of an instance prefers __str__, like CPython's str() }
    if PyUserObjStr(o, False, us) then begin Result := us; Exit; end;
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
function pylist_mark_list(l: TPyList): TPyList;
begin
  if l <> nil then l.FKind := PYSEQ_LIST;
  Result := l;
end;

function pyvar_mark_list(const v: Variant): Variant;
var o: TObject;
begin
  Result := v;
  if pyvartag(v) <> 7 then Exit;
  o := TObject(pyvarobj(v));
  if (o <> nil) and (o is TPyList) then TPyList(o).FKind := PYSEQ_LIST;
end;

function pyunpack_check(have, need: Integer): Integer;
begin
  if have < need then
    raise ValueError.Create('not enough values to unpack (expected at least '
      + pystr_of(Int64(need)) + ', got ' + pystr_of(Int64(have)) + ')');
  Result := have;
end;


function pylist_mark_set(l: TPyList): TPyList;
begin
  if l <> nil then l.FKind := PYSEQ_SET;
  pylist_mark_set := l;
end;

function pylist_mark_frozenset(l: TPyList): TPyList;
begin
  if l <> nil then l.FKind := PYSEQ_FROZENSET;
  pylist_mark_frozenset := l;
end;

function PySeqKindName(k: Integer): AnsiString;
begin
  if k = PYSEQ_TUPLE then PySeqKindName := 'tuple'
  else if k = PYSEQ_SET then PySeqKindName := 'set'
  else if k = PYSEQ_FROZENSET then PySeqKindName := 'frozenset'
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
function pybytes_kind_v(const v: Variant): Integer;
var o: Pointer;
begin
  pybytes_kind_v := -1;
  if pyvartag(v) <> 7 then Exit;
  o := pyvarobj(v);
  if o = nil then Exit;
  if not (TObject(o) is TPyBytes) then Exit;
  if TPyBytes(TObject(o)).FIsByteArray then pybytes_kind_v := 1
  else pybytes_kind_v := 0;
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
  { ...and CPython's empty frozenset is `frozenset()`, its non-empty one
    `frozenset({1, 2})` — the braces are the SET display with the type name
    wrapped round it, which is why this is a prefix/suffix rather than a third
    bracket pair. }
  if l.FKind = PYSEQ_FROZENSET then
  begin
    if l.count = 0 then begin Result := 'frozenset()'; Exit; end;
    Result := 'frozenset({';
  end
  else if l.FKind = PYSEQ_TUPLE then Result := '('
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
  if l.FKind = PYSEQ_FROZENSET then Result := Result + '})'
  else if l.FKind = PYSEQ_TUPLE then Result := Result + ')'
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
function TPyBytes.hex: AnsiString;
const HexD = '0123456789abcdef';
var k, v: Integer; p: PByte;
begin
  Result := '';
  if (Self = nil) or (Self.FLen <= 0) then Exit;
  SetLength(Result, Self.FLen * 2);
  p := PByte(Self.FData);
  for k := 0 to Self.FLen - 1 do
  begin
    v := PByte(NativeInt(p) + k)^;
    { LOWERCASE, and always two digits — CPython's bytes.hex() pads, so
      b'\x01'.hex() is '01' and not '1'. }
    Result[k * 2 + 1] := HexD[(v shr 4) + 1];
    Result[k * 2 + 2] := HexD[(v and 15) + 1];
  end;
end;

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
  { CPython renders a bytearray as `bytearray(b'..')` — the same bytes literal
    wrapped in its type name — so the wrap goes on AFTER the escaping above and
    reuses all of it rather than duplicating the quoting rules.
    bug-nilpy-bytearray-and-bytes-are-the-same-type }
  if (b <> nil) and b.FIsByteArray then
    Result := 'bytearray(' + Result + ')';
end;

function pystr_of(const v: Variant): AnsiString; overload;
begin
  { VT_EMPTY is Python's None, not an empty string }
  if pyvartag(v) = 0 then begin Result := 'None'; Exit; end;
  if PyVarIsCallableTag(v) then
  begin Result := PyCallableStr(v); Exit; end;
  { a CLASS reached as a value renders as CPython's class object }
  if pyvartag(v) = 11 then begin Result := PyClassRefStr(v); Exit; end;
  { ...and a BUILTIN type reached as a value, the same way }
  if pyvartag(v) = 13 then begin Result := pybtype_repr(v); Exit; end;
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
  { an OBJECT — a list, dict, set, bytes, or a user instance — renders the way
    print renders it. Without this arm it fell through to VariantToStr, which
    is builtin.pas's LOW-LEVEL scalar formatter and knows nothing about pylib's
    objects, so it answered the EMPTY STRING: `map(str, [(1,2), [3]])` gave
    ['', ''] while the identical `[str(x) for x in ...]` was correct, because
    the comprehension reaches the frontend's own str lowering and only the
    DYNAMIC path comes here (bug-nilpy-str-of-a-container-through-a-callback-
    is-empty). The three rendering paths again —
    project_nilpy_three_rendering_paths_print_str_fstring. }
  if pyvartag(v) = 7 then
  begin
    Result := pyvar_print_of(v);
    Exit;
  end;
  Result := VariantToStr(v);
end;

end.
