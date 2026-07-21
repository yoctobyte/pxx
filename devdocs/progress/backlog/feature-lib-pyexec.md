---
track: B
prio: 45
type: feature
blocked-by: [feature-rtti-field-reflection]
---

# lib pyexec: a real exec() for Python-subset source (library, two engines)

- **Track:** B (library — language-neutral). Consumer:
  [[feature-nilpy-corpus-uforth]]. Depends on
  [[feature-rtti-field-reflection]] for the host bridge.

`exec(src, env)` as a LIBRARY, semantics matching CPython's explicit-dict
form (which is exactly how uforth calls it): no ambient scope capture, the
host passes name -> value bindings; values are variants (int/float/str/
list/dict/object-ref/bound-method).

## Contract (censused from uforth's 134 PYTHON blocks — all parse)

Statements: assign/augassign, if/elif/else, while/for(+break), def, return,
raise, del, expression statements. Expressions: arith/bit/compare/boolop,
calls, attribute access, subscripts incl. slices, f-strings, isinstance,
ternary, tuple/list/dict literals, len/int/print builtins. Sane
restrictions: NO import, NO class definitions, NO exec-in-exec, explicit
env only.

## Two engines, shared front

1. **Front**: tokenizer + parser -> AST, cached per source string (blocks
   run per-CALL in uforth's inner loop — SWAP executes millions of times in
   the conformance suite; parse exactly once).
2. **Engine 1, tree-walker** (ships first): walks the AST over variants;
   host object access (vm.here, vm.memory[i], push(x)) resolved through
   field/method RTTI. The correctness reference.
3. **Engine 2, JIT** (later, own ticket when phase starts): same AST
   through the in-tree backend (asmcore/obj writer) -> native fn ptr cached
   in the word body. Env types are concrete at block-compile time, so
   attribute access compiles to fixed-offset loads. Forth-native shape:
   native words ARE compiled words.

## Language / porting plan (user policy 2026-07-19)

Start in PASCAL (avoids the chicken-egg on NilPy features; libs are
language-neutral per Track B). Port to NilPy once N is feature-complete
enough — the port is then itself an N corpus exercise. Same public surface
either way so consumers don't care.

Gate: standalone test suite driving the extracted 134-block corpus against
recorded CPython results (no uforth needed); make lib-test green.

## Track B note (2026-07-20 sweep)

Blocked-by edge added for [[feature-rtti-field-reflection]], which the ticket's
own header lists as a dependency ("Depends on feature-rtti-field-reflection for
the host bridge") — the tree-walker resolves `vm.here` / `vm.memory[i]` /
`push(x)` through field and method RTTI, so there is no engine without it.

Also worth flagging for whoever ranks this: it is a **large** umbrella (a
tokenizer + parser + AST cache, then a tree-walking engine, then a JIT), not a
single slice. The one piece that is genuinely startable today and independent of
the RTTI dependency is extracting uforth's 134 PYTHON blocks with their CPython
results into a fixture corpus under `test/` — that is worth doing on its own,
because it pins the contract before any engine exists to argue with.

## 2026-07-21 — architecture confirmed with user; JIT = rainy-day

Reached this ticket by driving uforth to the point where PYTHON-bodied stdlib
words (`/`, `2/`, most of CORE) are the wall (see
[[feature-nilpy-corpus-uforth]] MILESTONE 3 — full STD.UFO now loads). Examined
both engines closely with the user. Decisions:

- **Engine 1 (reflective tree-walker) is THE path** — reaches the goal (uforth
  runs, suite matches CPython), lower risk. Depends on
  [[feature-rtti-field-reflection]] (field get/set by name; method invoke-by-name
  already ships). Novel runtime code = essentially ONE piece: a **generic
  native-call trampoline** (proc addr + N variant args + param types -> marshal +
  indirect call; bounded arity, per-target asm thunk, written once, reused for
  both method-by-name and bound-method values).
- **Engine 2 (JIT) = RAINY-DAY, one of the last things.** Not deferred for code
  size — the hard part is (a) making the AOT compiler REENTRANT (it is a
  single-shot batch tool over pervasive globals) and (b) RUNTIME SYMBOL BINDING
  (serialize the AOT symtab — class layouts, method/global addresses — into the
  binary + a runtime resolver so a snippet binds to the LIVE program's
  vm.*/push/pop) and (c) a mmap+exec loader. Three flavors exist (in-process full
  compiler / small dedicated subset-codegen / subprocess `pascal26`+`.so`+dlopen
  — the last reuses the existing .so writer but is not self-contained). Kept on
  record deliberately: a JIT *with knowledge of the running binary* is a broadly
  useful capability beyond Python (user note). It drops in LATER over the SAME
  cached AST, behind a `speed-vs-size` flag — so it never blocks correctness and
  the reentrancy cost is never paid until perf actually matters. Its own ticket
  when that phase starts.

- **Bound-method values** ([[feature-nilpy-bound-method-value]]) are a sub-piece
  of the host bridge, not a separate general feature: uforth's env is
  `{"push": self.push, ...}`, and capturing `self.push` as a value currently
  SIGSEGVs (drops self). For the tree-walker this reduces to capturing
  `self.m` as `{recv, method-ref}` and dispatching via the method-reflection
  invoke-by-name + the generic-call trampoline above — the interpreter never
  needs the general NilPy `env["push"](x)` dynamic call to work.

Startable-today piece unchanged and still recommended first: extract the PYTHON
block corpus + CPython oracle results into `test/`, pinning the contract.

## 2026-07-21 — corpus extracted, contract pinned, milestones sized

`tools/pyexec_corpus.py` extracts + categorizes the blocks from a uforth checkout
(nothing vendored — uforth stays the user's separate tree). Measured over the
shipped `.UFO` stdlib: **131 blocks — 60 pure-stack, 71 vm-accessing.**

- host FIELDS used: `memory`(25), `vars`(12), `here`(8), `_pic_buf`(7),
  `rstack`(7), `stack`(4), `dict`(3), `base`(3), `trace`(2), `input_pos`(2),
  `current_token_index`(2), + singletons (`xt_table`, `current_def_name`,
  `fstack`, `input_line`). — served by [[feature-rtti-field-reflection]] (LANDED).
- host METHODS used: `define_word`(13), `next_token_strict`(12), `push`(7),
  `next_token`(4), `pop`(4), + `exec_token_runtime`/`run_forth_word`/
  `strip_string_token`/`is_string_token` (1 each). — need method reflection
  (un-gate the RTTI method table + arity/param-kinds in MethInfo) + the generic
  native-call trampoline.
- language features: builtin call `len/int/str/chr/ord/abs/range`(48), bitops(39),
  ternary(24), augassign(24), slice(19), floordiv(13), for(12), while(9),
  f-string(8), if-stmt(7).

**Milestone ladder this yields (each shippable, gated on the corpus subset):**

- **M1 — 60 pure-stack blocks.** Expression + statement tree-walker over
  variants, with only `push`/`pop`/`fpush`/`fpop` bound (bound-method value or a
  stack bridge). NO field/method reflection. This already covers `/`, `2/`,
  arithmetic, bitops, ternary, augassign, floordiv — i.e. the exact PYTHON-bodied
  words that SEGFAULT today. Biggest correctness win for the least machinery;
  build first.
- **M2 — + field-accessing blocks.** Wire field reflection (landed) into the
  walker: `vm.memory[i]`, `vm.here`, `vm.base`, … read/write via GetFieldPtr.
- **M3 — + method-calling blocks.** Method reflection (un-gate + MethInfo sig) +
  the generic native-call trampoline: `vm.define_word(...)`, `vm.next_token_strict()`.
  Bound-method capture ([[feature-nilpy-bound-method-value]]) folds in here.

Front half (tokenizer + parser -> cached AST) is shared by all three and by the
later JIT; build it once at M1.

## 2026-07-21 — host-bridge FOUNDATION landed; interpreter is what remains

The hard/novel keystone of engine-1 is done and tested:
- FIELD reflection (commit e8ebbf0a): GetFieldPtr / GetInstanceRTTI over any field
  with type. [[feature-rtti-field-reflection]] resolved.
- METHOD reflection (commit 73395c74): all methods emitted, MethInfo =
  name/code/arity/retKind(0=proc)/paramKinds; GetMethInfoByName.
- TRAMPOLINE ABI proven (commit 40adbd6e, test_pyexec_trampoline_abi): calling
  push(const Variant)/pop:Variant/fpush(Double)/fpop:Double BY NAME through the
  reflected code pointer round-trips. Because caller and callee share pxx's
  codegen, the trampoline is built from **typed proc-pointer casts** — pxx
  supplies each target's ABI (hidden-dest variant return, variant-by-address
  param, xmm floats), NO hand-rolled asm. A variant arg is passed as its address
  (GP), so the only non-GP shapes are float params/returns + the variant
  hidden-dest return.

Remaining = the interpreter (a laborious but standard tree-walker), build plan:

1. **`compiler/builtin/pyeval.pas`** (new unit; `uses pylib, typinfo`). NOT
   auto-used until solid — build + test standalone via a Pascal driver first, so
   a parse error can't break every NilPy compile. pylib must EXPORT the variant
   ops the evaluator needs (pyvar_to_int/float/bool, pyvarobj, pymul_v,
   pyfloordiv_v already exported; ADD pyadd_v/pysub_v/pymod_v/compare to the
   interface).
2. **Trampoline dispatcher** `PyHostCall(vm, name, args, nargs): Variant` — reflect
   name on vm's class (GetMethInfoByName), marshal each variant arg by paramKinds
   (variant param -> pass @variant; int -> pyvar_to_int; …), dispatch on
   (retKind, arity, float-ness) to the matching typed proc-ptr cast, box the
   result by retKind. M1 needs the 4 stack shapes + a GP-arity family; extend for
   M2/M3 method shapes.
3. **Tokenizer + recursive-descent evaluator** over Variants for the pure-stack
   grammar (assign/augassign, names as locals in a TPyDict, int lits, arith/bit/
   compare/floordiv, ternary, calls). Correctness-first: may re-parse per call;
   cache the AST later (SWAP runs millions of times).
4. **Host-call resolution (M1 convention):** a call `name(args)` or `vm.name(args)`
   -> `PyHostCall(g["vm"], name, args)`. Uses g["vm"]; sidesteps bound-method
   values for M1 (the env's callables are all vm methods of the same name). Proper
   bound-method capture ([[feature-nilpy-bound-method-value]]) folds in at M3.
5. **def/ns wrapper + NilPy wiring (last):** EvalPyStmts sees `def __body__():
   body`; store {body, g} in a single global pending slot, set l["__body__"] to a
   variant whose payload = &PyEvalTrampoline; `ns["__body__"]()` (PyMakeDynCall
   unboxes payload -> indirect call) runs the pending body. Then rename the
   parser.inc `exec()` binding from pyexec to EvalPyStmts and add
   `ParseUsesUnit('pyeval')` after pylib.

Checkpoint tag `checkpoint-pre-exec-arc` marks the pre-arc state for rollback.


## 2026-07-21 — M1 CORE landed (pyeval.pas), standalone-green

`compiler/builtin/pyeval.pas` created: the M1 tree-walker over Variants. Covers
the pure-stack grammar — simple statements (`;`/newline), assignment + augassign,
full expression grammar (ternary, and/or/not, comparisons incl. chains, |^&,
<<>> arithmetic shifts, +-*/ // %, unary -/+/~), int/float/hex literals,
True/False/None, builtins (int/float/abs/bool/len/ord/chr/str/hex/min/max/print),
and the host bridge push/pop/fpush/fpop reflected BY NAME (case-insensitive)
through the trampoline. `test/test_pyeval_m1.pas` drives SWAP/OVER/ROT, bitops,
shifts, ternary min/max, floordiv/mod, augassign, comparisons, float stack — ALL
PASS. pylib gained the variant ops it needs (pyadd_v/pysub_v/pymod_v/pybit*_v/
pyshl_v/pyshr_v/pyinvert_v/pyneg_v/pycmp_v/pyeq_v/pyint_v/pyvar_of_int/bool).

Gate: quick tier green, self-host byte-identical, RTTI-consumer tests + test-nilpy
green. pyeval is NOT auto-used yet (standalone only), so zero blast radius.

### Blockers hit + resolved / filed

- **typinfo⊕pylib `Exception` collision (FIXED).** Both units define
  `Exception = class`; combined, the compiler resolved sysutils's
  `EConvertError.CreateFmt` against pylib's Exception (no CreateFmt) →
  "class method not found". typinfo pulled sysutils only for one `CompareText`
  in GetEnumValue — inlined it (`TiCompareText`) and dropped `uses sysutils`, so
  a program can now use pylib + typinfo together (which pyeval requires).
- **Variant-fn-return-forward NRVO corruption (Track A ticket filed:
  `bug-a-variant-fn-return-forward-nrvo-corruption`).** `function F: Variant;
  begin F := G(...) end` silently corrupts. Forced pyeval's evaluator to be all
  `var res: Variant` PROCEDURES instead of Variant functions. Broad latent
  correctness hole beyond pyeval.
- **open `array of Variant` param silent miscompile (Track A ticket filed:
  `bug-a-open-array-of-variant-silent-miscompile`).** Reads only elem 0. pyeval
  passes args in a TPyList to sidestep.

### M1 deferred tail (next)

- **bignum / unsigned-mask semantics.** `x & 0xFFFFFFFFFFFFFFFF` must yield the
  arbitrary-precision unsigned value; M1 is Int64 so U<, UM*, M*/, D< and the
  double-cell MATH.UFO words are OUT of M1. Needs the promotable-int/bignum path.
- **compound blocks** (if/while/for/def + indentation) for the MATH block form.
- Then M2 (field reflection into the walker) and M3 (method reflection +
  bound-method capture), per the ladder above.
- Corpus-coverage measurement over all 60 pure-stack blocks (grammar accept-rate)
  is the recommended immediate next step.

### M1 coverage measured (corpus-driven, 2026-07-21)

Ran all 60 pure-stack blocks through pyeval against a seeded stub VM:
- **41 RUN OK** — M1 accepts + evaluates without error (68%).
- **16 cleanly M1-rejected** — the deferred tail: 13 bignum double-cell MATH words
  (UM*/M*//D<… with `if`/`def` blocks + `0x10000000000000000`), 2 `import`, 1 f-string.
- **3 unclear** — `print(hex(val)[2:].upper(), …)` etc.: slice/postfix-method on a
  call result; parser reports "expected , or )" instead of a clean M1-reject. Minor
  diagnostic gap; these need M2 subscripts anyway.

So M1 core already runs the arithmetic/stack/bitwise words that segfault today;
the remaining pure-stack blocks are precisely the bignum + compound-block tail
already scheduled after M1.

## 2026-07-21 — compound blocks landed (if/elif/else, while, for, break)

pyeval now handles Python-indented COMPOUND blocks: INDENT/DEDENT in the
tokenizer (offside rule), if/elif/else (inline + block), while (+break), for-in
over range()/lists. Skipped branches walk the grammar with an `Executing` gate
(no side effects); while/for re-walk the body token span each iteration
(correctness-first). `range()` builtin added. test/test_pyeval_compound.pas — 10
cases incl. nested for + if-in-for — ALL PASS; M1 test still green; self-host
byte-identical; quick tier green.

Locals moved OUT of the passed-in TPyDict into pyeval's own name/value arrays:
TPyDict keyed by an AnsiString-boxed Variant is unreliable — store and indexof
box the string inconsistently and a heap key's bytes go stale after the block
returns (the pylib str-into-variant ownership landmine). Owned AnsiString names
compared with `=` are exact. Globals (the `vm` handle) still read from the host
dict, which works. Filed nothing new — this is a pyeval-side choice, though the
underlying TPyDict AnsiString-key boxing inconsistency is worth a Track B look.

Next: M2 — attribute access (vm.here get/set via GetFieldPtr) + subscripts
(vm.memory[i]); then M3 method calls. That unlocks the 71 vm-accessing blocks.
