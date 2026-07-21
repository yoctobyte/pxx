---
track: N
prio: 55
type: feature
---

# NilPy corpus: uforth — a real Python Forth system as Track N's forcing target

- **Track:** N (Nil-Python frontend) umbrella; spawns A/B/U work.
- **Opened:** 2026-07-19 (user decision). Source: ~/projects/uforth (user's
  own project, not yet on GitHub — vendor/fetch story TBD when it lands
  there; until then treat the local checkout as upstream).

## Why this target

uforth = 4344-line single-file Python Forth VM (uforth.py) + layered .UFO
stdlib + the bundled Forth-2012 conformance suite as a ready-made oracle.
Self-contained (os/sys/select/textwrap/itertools/dataclasses only), heavy on
real data structures (heterogeneous Any stacks, dicts of words, byte
memory, isinstance dispatch) — deliberately chosen to DRIVE NilPy feature
development (the P-corpus role fpjson played). Goal: uforth runs UNMODIFIED
under pxx-NilPy, suite output matching CPython's.

## Architecture decisions (settled 2026-07-19 session)

- **exec() becomes a real library** ([[feature-lib-pyexec]]), NOT a
  precompile hack: uforth's 126+ native words are `"..." PYTHON` blocks in
  the .UFO files, exec'd per CALL (hot path!). pyexec = parse-once-cached
  AST + two engines: tree-walker (correctness reference) and, later, an
  in-process pxx-backend JIT (blocks are native-word definitions — Forth
  tradition compiles those; env types are concrete at block-compile time so
  field access burns to fixed offsets). Sane restrictions: explicit env
  dict only (exactly the exec(src, env) form uforth uses), no import/class
  in exec'd code.
- **Host binding via RTTI**: interpreted (and JIT'd) code reaches
  vm.here/vm.memory/push through class RTTI — method reflection exists
  (VMT-8); field get/set by name is [[feature-rtti-field-reflection]].
- **Bignum**: uforth leans on Python arbitrary-precision ints (128-bit
  (hi<<64)|lo composites, selectively masked) — fork filed as
  [[decide-nilpy-bigint-vs-64bit-cells]].
- **Mixed-language libs are policy**: some libs Python, some Pascal, some
  Pascal-then-ported-to-NilPy once N matures (the port itself then becomes
  an N corpus test). Track B's language-neutral principle applies.

## Measured feature census (what N must grow)

uforth.py: 12 @dataclass (+field), @property/setters, 39 f-strings, 17
comprehensions, 9 generator expressions, 123 slice uses, dicts/sets/tuples
throughout, nonlocal, del, exception payloads (ForthThrow), List[Any]
variant stacks, isinstance dispatch, select.select stdin polling (KEY —
needs a PAL primitive), file IO. PYTHON blocks (134, all statically
parseable): imperative subset only — if/while/for, def, calls, subscripts,
slices, f-strings, raise, isinstance, augassign.

## Milestone ladder (each lands green independently)

0. Oracle green — **DONE** (2026-07-19, uforth commit 9f9b45a): full suite
   `cd tests && python3 ../uforth.py runtests.fth` under CPython reports
   **Total 0 errors** across all 12 word sets (Core, Core ext, Block,
   Double, Exception, Facility, File-access, Locals, Memory-alloc,
   Programming-tools, Search-order, String). The 9f9b45a lexer fix
   (standalone-`\` token) closed both the core.fr:429 red and the
   utilities.fth `\?` wall. This CPython run is the byte-diff oracle for
   milestones 1-3.
1. N features by need, ranked by what blocks uforth.py's PARSE first
   (dataclass, dict, slice, f-string, ...) — each = own N ticket hung off
   this umbrella; CPython remains the oracle for every increment.
   **Progress 2026-07-19 (session 2):** landed green, in wall order —
   lexer literals (hex/oct/bin/_ , triple-quoted, line counting);
   def/method params past 4 (internal ABI: 6 regs, >6 all-stack);
   @dataclass v1 (scalar fields, defaults, synthesized ctor; + fixed two
   latent field bugs: bool-spill width clobber, str-field string[N]
   semantics); bitwise ops + augassign (Python precedence chain, boolean
   guard) with a Track A PyExprMode tkShl/tkXor suppression; `/` = true
   division; from-imports + annotated assignments + module-scope
   inference fixes; annotation grammar (Optional/Callable/Any/forward
   refs; Optional[int] None==0 sentinel CAVEAT); stdlib imports
   consume-and-defer (sys/os/textwrap/select/itertools);
   **list v1** — pylib TPyList builtin (variant slots, default indexed
   property, len()), [..] literal desugar, plus Track A: scalar->Variant
   call boxing, Variant-returning functions (hidden-dest ABI),
   EmitWriteVariant True/False (x86-64 only — cross variant writers still
   print ints); field(default_factory=list).
   **Landed since:** classvar/counter/lambda-factory chain (Word.xt_id),
   is/is-not, in/not-in + {set} literals + class inheritance headers,
   rich def-param annotations (Any params by-ref const, Any returns via
   hidden dest), isinstance() (VT_OBJECT boxing + RTTI for .npy + ctor
   calls in expression positions).
   **Progress 2026-07-19 (session 3, overnight):** landed green, in wall
   order — AST-based local typing ([[feature-n-nilpy-ast-based-typing]],
   which also gave methods the widening they never had); ctor fields via
   the annotated `self.x: T = ...` form plus richer initialisers, with real
   line numbers on the pre-pass diagnostics; **dict v1**
   ([[feature-nilpy-dict]] — TPyDict, literals, subscript, .get, in, del);
   **set v1** (TPyList-backed, `set()` and dedup add); method parameters
   taking the full annotation grammar; `-> None` on non-ctor methods;
   **constant parameter defaults** on defs, methods and ctors (the ctor path
   was a segfault); **f-strings** ([[feature-nilpy-fstrings]] — plain holes,
   escapes, !r/!s).

   **Current wall picture.** The corpus is now blocked mostly on TRACK A,
   not on frontend syntax:
   - [[bug-a-nilpy-variant-element-not-usable-as-scalar]] (p85) — `return
     xs[0]` is silent garbage. List-wide, predates dict, and it is the one
     that matters most: uforth reads from vm.stack / vm.dict / vm.xt_table on
     almost every line. **Now the binding constraint on for-in too**: the loop
     variable is a variant, so `for v in xs: acc = acc + v` — iterate a list
     of strings, build a string, the most ordinary loop there is — produces
     GARBAGE BYTES. for-in landed usable for printing and passing along, not
     for consuming.
   - [[bug-a-str-boxed-into-variant-does-not-own-bytes]] (p80) — a str boxed
     into a variant has frame lifetime, so same-length keys collide.
   - [[bug-nilpy-method-returning-str-garbage]] — VM has many `-> str`
     methods; per the user's 2026-07-19 call this waits for
     [[feature-a-abi-oracle]] rather than a ninth copy of the return rule.
   - [[feature-rtti-field-reflection]] — `t.word.name` on an Any (uforth.py:190).
   - [[bug-nilpy-string-local-truncates-at-255]] (p65) — a string local is
     the FROZEN kind, so anything built past 255 characters is silently cut.
     uforth's token buffers and assembled output lines go well past that.
     Gated on the same Track A boxing bug: making string locals managed is
     what corrupted the heap when it was tried.

   **Also landed session 3, after the wall picture above was written:**
   f-string conversions and format specs (the whole 67-hole census);
   class-returning top-level defs keeping their class identity (was silent
   garbage); top-level def SIGNATURES registered up front, which also makes
   FORWARD CALLS work; module-level names typed from the AST; **for-in over
   list / set / dict / str**, and `break` / `continue`, which had never been
   parsed at all — not even inside a plain `while`.

   Still frontend, still ours, and independent of the Track A blockers:
   [[feature-nilpy-bytes-and-slices]] (bytearray + slices + to_bytes; 99
   slice sites, and vm.memory IS the Forth data space) — but note both
   slices and `int.to_bytes(..., signed=True)` need a shared-parser hook, so
   that one is not purely ours after all.

   **Sweeping NilPy's operators and builtins against CPython (2026-07-20)
   turned up more than the feature work did** — three SILENT wrong answers
   and a segfault that no feature test would have found, because they are in
   constructs nobody thought to re-check: `not <non-zero int>` was the
   BITWISE complement (fixed, 8f18dba4), `in` on a string segfaulted (fixed,
   c49064af), `int("42")` returns a pointer
   ([[bug-a-nilpy-int-of-string-returns-a-pointer]], Track A), and `s * 2`
   returns a pointer ([[bug-nilpy-string-repeat-returns-a-pointer]]). Worth
   repeating the sweep after each feature wave.

   Biggest newly-measured gap: **[[feature-nilpy-nested-defs]] — 214 sites**.
   The word-registration functions define their natives inline, so this is
   the structure of uforth's second half, not an occasional idiom.

   The rest of the census is now characterised and filed rather than left as
   a list: [[feature-nilpy-exceptions]] (p60 — `raise` / `try` / `except`
   have NO statement rule at all, and exceptions are uforth's control flow,
   not its error path), [[feature-nilpy-tuple-unpack]] (p55 — the enabler for
   `for k, v in d.items()`), and, still unfiled because neither blocks as
   early: `@property` (only `@dataclass` is accepted as a decorator),
   comprehensions, `nonlocal` (1 site), and **lambda as a VALUE** — 3 sites,
   all `vm.define_word("X", native=lambda vm: ...)`, which is a real closure
   passed as a Callable parameter rather than the dataclass default-factory
   form already handled. Small in count, not small in scope.
2. [[feature-rtti-field-reflection]] + [[feature-lib-pyexec]] (walker) —
   independently tested against the 134-block corpus extracted standalone.
3. uforth boots STD/CORE.UFO, then prelim tests (57), then full suite,
   under pxx-NilPy — byte-diff vs CPython run.
4. (Optimization, later) pyexec JIT engine via the in-tree obj/asmcore
   backend.

## Non-goals

- No uforth rewrite-to-subset: the design (UFO-resident PYTHON natives) is
  intentional and stays. N grows to meet it, not vice versa.
- No full CPython emulation in pyexec — the censused block subset is the
  contract.



## Session 2026-07-21 (session 3, continued) — 267 -> ~3830 (~88%)

An extended run took the first parse error from 1290 (the exec boundary) to
~3830 (88% of the file), landing (each green, gated, pushed): dynamic call
through a variant callable, class-in-variant widen + subscript/slice, decode
keyword arg, ternary/genexpr as method/call arguments, and/or returning the
operand (Python value semantics), range() with a step, lambda parse-stub,
optional parameter annotations, user-class-over-container variant dispatch,
method-call ';' statements, bytes literals + bytes.find, str-method chaining
after a class-value method, and DYNAMIC INSTANCE ATTRIBUTES (get/set/+=/hasattr
on variants and class instances, via a pointer-keyed store). ~40 commits.

Current wall uforth.py:3829 — a closure-captured parameter default. Remaining:
[[feature-nilpy-closure-default-and-remaining]] then [[feature-lib-pyexec]] for
actual execution. The file parses ~88% of the way; exec() is a stub, so native
words do not run yet.

## Wall progression — session 2026-07-20 (session 3)

uforth.py's first parse error, tracked as each gap closed. Each step is a
landed, gated, pushed commit with a CPython-diffed test in `test-nilpy`:

| wall | what blocked | resolved by |
| --- | --- | --- |
| 267 | `bytearray` | (session 2) |
| 271 | slice assign `mem[a:b] = ...` | [[feature-nilpy-bytes-and-slices]] |
| 271 | `to_bytes` keyword arg | same ticket, second half |
| 308 | `print(..., file=sys.stderr, flush=True)` | [[feature-nilpy-print-kwargs]] |
| 311 | `os.path.*` | os/sys shim table |
| 331 | one-line suite `if not t: return None` | `PyParseSuite` |
| 359 | `int(s, base)` + `except ValueError` | [[feature-nilpy-builtin-exceptions]] |
| 362 | conditional expression `a if c else b` | same commit (32 sites) |
| 373 | `res = None` then `res = <int>` | [[bug-nilpy-none-assign-to-plain-local]] |
| 377 | `float(token)` | float() conversion, raises ValueError |
| 384 | `@property` / `@x.setter` | property decorator, via AddUProperty |
| 428 | variant bitwise `v & mask` | EmitVarBinOp bitwise ops |
| 431 | `RuntimeError` | pylib exception tree |
| 458 | keyword args in `Word(...)` | ctor keyword binding by FIELD index |
| 460 | `dict.setdefault` | pylib |
| 471 | ambiguous `.get` on a variant | renamed TPyList/TPyBytes `.get` -> `.at` |
| 476 | statement after a `for` in a def | [[bug-nilpy-statement-after-for-in-a-def]] |
| 494 | `hasattr` / `getattr` | resolved against declared fields |
| 516 | `xs.append(a + b)` | expression arg to a const (by-ref) param |
| 538 | `x in ("a","b")` | tuple on the `in` RHS |
| 585 | `.find(sub, start)` | pylib |
| 766 | def without `-> ret` | [[feature-nilpy-optional-return-annotation]] |
| 772 | `for p in (tuple)` | tuple iteration |
| 774 | `return (a, b)` | tuples as values + return-type inference |
| 777 | `bytes` annotation | maps to TPyBytes |
| 778 | `bytearray()` | zero-arg overload |
| 783 | `out.extend(ch.encode(...))` | TPyBytes.extend + str.encode |
| 789 | `out.append(ord(ch))` | TPyBytes.append (+ the list/bytes name collision) |
| 840 | `word.is_native()` after `Optional[Word]` | full annotation grammar for RETURN types |
| 841 | `word.native(self)` — procedural FIELD on a class local | @dataclass Callable field keeps its signature |
| 849 | `pfx, content = cs` | unpack a single sequence value into several names |
| 883 | `isinstance(num, list)` | container type names -> pylib classes |
| 884 | `for n in num` (num is Any) | unbox variant to TPyList |
| 1039 | multi-line `self.trace_log(...,)` | trailing comma in a method call |
| 1079 | four adjacent f-strings | implicit string concatenation |
| 1228 | `with open(...)` + file iteration | with/open + pyopen + list comprehensions |
| 1263 | `raise X(...) from e` | exception chaining (from-clause dropped) |
| 1272 | `dict.pop(k, default)` | pylib |
| 1284 | `textwrap.dedent` | stdlib shim |
| 1286 | `join(EXPR for x in it)` genexpr arg | [[feature-nilpy-generator-expression-arg]] (OPEN) |
| 1286 | `join(EXPR for x in it)` genexpr arg | expression comprehensions + hoisting |
| 1289 | `exec(wrapper, env, ns)` | compiles via pylib stub; real engine = [[feature-lib-pyexec]] |
| 1290 | `r = ns["__body__"]()` | **CURRENT** — a DYNAMIC call through a variant callable (the function exec created); needs the dynamic-dispatch machinery that is part of [[feature-lib-pyexec]] |

Wall moved 267 -> 1290 on 2026-07-20/21 (session 3), across ~48 landed commits.
From 1290 on the code is the exec EXECUTION MODEL: `ns["__body__"]()` calls the
function `exec()` was meant to build, so it cannot be meaningfully compiled
without the pyexec evaluator (a synthetic dynamic-call that crashes at runtime
under the stub is not real progress). Remaining VM methods past the exec block
(1294+) are independent, but reaching them means compiling a call through a
variant callable first. This is the [[feature-lib-pyexec]] boundary: the file
parses through exec, and running the exec'd PYTHON blocks (uforth's native
words) is the next subsystem.

 —
roughly the first 30% of the 4357-line file, and past every class definition,
the VM core, the dictionary, number parsing, the tokenizer, and file I/O
(with/open, comprehensions, strip(chars), raise-from, dict.pop, dedent). The
next wall is `exec()` — the pyexec interpreter library, a genuine multi-session
subsystem.

Wall moved 267 -> 1228 on 2026-07-20 (session 3), across ~30 landed commits —
roughly the first quarter of the 4357-line file, and past every class
definition, the VM core, the dictionary, number parsing, and the tokenizer.
The remaining walls are large feature CLUSTERS (file I/O, comprehensions,
generators, sys.stdin+select), each multiple sessions.



Bugs found UNDER this work, all silent-wrong-behaviour rather than parse
errors, all filed and fixed: [[bug-nilpy-call-returning-class-loses-identity]]
(a call returning a class dropped which class — `len()` on a bytearray field
segfaulted) and [[bug-nilpy-not-on-string-always-true]] (`not s` was True for
every string; `if s:` and `bool(s)` were both correct, which hid it).

## Measured remaining scope (2026-07-20)

Counted in uforth.py, so this is the real distance to milestone 2, not an
estimate. Roughly in wall order:

| construct | sites | note |
| --- | --- | --- |
| f-strings | 42 | expander exists; needs verifying against these |
| `@property` + setter | 2 (x2 accessors) | the current wall |
| decorators | 15 | `@property`/setters beyond the landed `@dataclass` |
| `getattr(o, "n", default)` | 16 | needs [[feature-rtti-field-reflection]] |
| comprehensions | 4 | list comprehensions |
| `lambda` | 4 | |
| `del` | 4 | |
| `select.select` on stdin | 2 | needs a PAL primitive AND a stdin file object |
| `with` | 1 | |
| `nonlocal` | 1 | |
| builtin exception classes | 6 | the current wall |

`sys.stdin` is the awkward one: 8 sites needing `.isatty()`, `.readline()`,
`.read(1)` and membership in `select.select([...])` — i.e. a real file-object
model, not another shim function. Worth its own ticket when reached.
