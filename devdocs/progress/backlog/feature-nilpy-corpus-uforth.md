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
   **Current wall (uforth.py:190):** attribute access on Any values
   (t.word.name — [[feature-rtti-field-reflection]]) and str methods
   ([[feature-nilpy-str-methods]]); then f-strings, dicts, tuple unpack,
   slices, for-in.
   After that (census): dicts (TPyDict), f-strings, tuple unpack, slices,
   for-in over lists, @property, try/except payloads, nonlocal, del.
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
