# C desktop path — compile real portable C (tiny-regex → lua → sqlite)

- **Type:** feature (track-C milestone path)
- **Status:** backlog (active arc — lua core **15/34 files parse clean**; see logs)
- **Session 2026-06-26 round 6 (Track C), gate-green + byte-identical, lua 14 ->
  15 + VM-core path unblocked:** ROOT-CAUSE fix — multi-declarator pointers
  `T *a, *b;` (5d3bc2f). ParseCLocalDeclAST folded the FIRST declarator's `*` into
  the base type and applied it to every name, so `int *p, *q;` dropped/mistyped q
  and `TValue *io1, *io2;` siblings lost pointer-ness -> deref hit IR_UNSUPPORTED.
  This was the real cause of the round-5 'emergent setobj/setsvalue' VM-core
  failures (every isolated piece compiled; the trigger was simply two pointers in
  one declaration). Now each declarator parses its own stars (a literal star
  redistributes; a typedef pointer applies whole). lapi advanced past setobj to
  varargs. NOTE: the bisection method that finally cracked it — keep shrinking the
  failing snippet (drop macro, drop types, drop block) until a plain-C minimal
  repro remains; here `int *p,*q; *p=*q;` was the whole bug. REMAINING (each deep
  / multi-session): (a) **varargs** `__builtin_va_start` — now the top named
  blocker, 3 files (lapi/lauxlib/ldebug), lua's luaL_error; real va_list ABI =
  Track A. (b) `IRLowerAddress` of rvalue/compound exprs — AN_CALL (liolib/lobject/
  lparser: `localeconv()->decimal_point[0]`, field/index of a call result),
  AN_ASSIGN (ldo), AN_BINOP (ltm), AN_COMMA (luac); general fix = materialise the
  rvalue to a hidden temp and address that (verify each vs gcc; some are UB). (c)
  lvm setobj/lundump setsvalue still 'undeclared' (a genuinely emergent
  macro-expansion case, distinct from the multi-declarator one). (d) multi-file
  linking. lua.c (interpreter main) compiles to an object.
- **Session 2026-06-26 round 5 (Track C), gate-green + byte-identical, lua core
  7 -> 14:** global array decls no longer cascade + balanced-brace aggregate-init
  skip (3843307), `sizeof((l)[0])` balanced-paren operand skip — unblocked the
  whole luaL_newlibtable sizeof cluster, +6 files (ced768d), `signal()` declared
  via a `__sighandler_t` typedef (the function-returning-fn-pointer declarator was
  unparseable) + undeclared-call error now names the function (2f5e285). REMAINING
  blockers: (a) **emergent-combination bugs** — in big files (lapi/lvm/lgc) an
  `IRLowerAddress` hits an int-literal / AN_CALL / AN_ASSIGN where every isolated
  piece (setobj, isvalid, luaC_barrier, the ternary) compiles fine; the failure
  only appears with the whole accumulated file. Smells like STATE ACCUMULATION
  (recycled symtab slots / node-pool — cf. the Alloc* parallel-array landmine),
  NOT a per-construct bug; bisection can't isolate it because the minimal repro
  doesn't carry the accumulated state. Next: instrument which sym/node slot is
  recycled with stale ASTSOffset/Kind when the int-lit address is emitted. (b)
  varargs `__builtin_va_start` (va_list — lua's luaL_error; Track A/ABI). (c)
  setobj/setsvalue undeclared in lvm (same emergent class). (d) multi-file linking.
- **Opened:** 2026-06-25
- **Session 2026-06-25 (Track C) delivered, all gate-green + self-host
  byte-identical, on `feat/cfront`:** function pointers (4d36da6), typedef-of-
  struct-tag record aliasing (b65d617), forward-record field-base re-anchor
  (65f3fcd), ternary `?:` / `AN_TERNARY` (b68c5be), integer literal suffixes
  (a64d316), bitwise-`~` const-eval (cd5996d, closed bug-c-const-eval-bitwise-not).
  lua-5.4.7 staged in `library_candidates/lua` (gitignored). Remaining blockers
  triaged below; lua does NOT compile yet (multi-session, spans Track C + A).
  Session also added: parenthesized declarator names `(name)(params)` (50e1626's
  predecessor d4c9b9f — unblocked the whole lua_* API prototype cluster) and
  **C `switch`/`case`/`default`** with fallthrough + break-only scope (50e1626,
  AN_SWITCH, target-independent IR). lua core: 0 → **4/34 files parse clean**.
  End-of-session error landscape across the 34 core files: 21 `unexpected token`
  (a LONG TAIL of varied expression-parse bugs — NOT one cause; e.g. a string-
  literal/`sizeof` macro expansion in lobject.c, a `+=` on a `->` field in lmem.c,
  a call in lstate.c — each needs individual bisection), 6 `call to undeclared
  function` (residual macros + `__builtin_offsetof` + lstring's deep cast chain
  which bottoms out at `bug-c-const-eval-bitwise-not`-adjacent macro re-scan), 2
  `Unsupported linear node in IR codegen` (ldebug.c, lparser.c — an IR/codegen
  gap to isolate), 1 `expected C expression`. NEXT: pick off the `unexpected
  token` tail incrementally (Track C), isolate the 2 IR-codegen gaps, then
  `setjmp`/`longjmp` (Track A) + multi-file linking for an actual lua build.
- 2026-06-26 (round 4) — **full-file-bisection harness in use; 7 more fixes,
  lua core 5 -> 7 files parse clean**, all gate-green + self-host byte-identical.
  Bisecting lapi.c's `index2value` surfaced a chain of high-leverage bugs:
  array-of-struct element STRIDE (a SILENT miscompile — `a[i]`/`p[i]` used pointer
  size not RecSize; `bug-c-struct-pointer-index-stride` done), `(p+i)->field`
  (`bug-c-field-on-pointer-arithmetic` done), **re-expansion of the same macro
  inside its own arguments** (lua's `check_exp` within `check_exp` via `gco2ccl`;
  the active-macro guard was too aggressive), **multi-line macro/call arguments**
  (the preprocessor was line-based; now joins continuation lines while parens are
  unbalanced), and **`++`/`--` as a VALUE** (new AN_INCDEC: postfix yields the old
  value via a temp, prefix the new; pointer base supported for `s2v(top.p++)`;
  `bug-c-postincrement-as-rvalue` done). Fixtures b23–b27. KEY: the bisection
  harness (build progressively larger prefixes of the real .c with its real
  includes) + the `near:` locator is the working method — minimal repros no longer
  reproduce these emergent/cumulative-state bugs. Current landscape: 9 `Unsupported
  linear node` (IRLowerAddress gaps for compound/rvalue exprs — `&(call)`,
  `&(int-lit)`, etc.; mostly address-of-rvalue, several are UB so verify against
  gcc before "fixing"), 8 `unexpected token`, 7 clean, 5 `expected C expression`,
  4 `call to undeclared function`. setjmp/longjmp (Track A) + multi-file linking
  still remain for a full build.
- 2026-06-25 (round 3) — **6 more Track C fixes**, all gate-green + byte-identical:
  adjacent string-literal concatenation (`"a" "b"`, lua's `lua_pushliteral`);
  string-literal-to-pointer store now lands on char 0 not the Pascal length
  prefix (closed `bug-c-string-literal-to-pointer-prefix`); `sizeof` in constant
  expressions / array dimensions (`char b[3*sizeof(size_t)]`); `&function`
  (AN_PROCADDR in IRLowerAddress); parenthesized comma EXPRESSION `(a,b)` (new
  `AN_COMMA` — lua's `api_check`/`lua_lock` = `((void)l, expr)`); plus the libc
  header growth (math.h + string/stdio/stdlib) and recursive `#if`. Fixtures
  b18–b22. lua core still 5/34 parse-clean by COUNT, but individual files advance
  several blockers each (lapi/lstate/ldo now fail much deeper).
  **KEY FINDING for the next worker:** the remaining `unexpected token` /
  `expected C expression` failures are EMERGENT from the cumulative full-file
  preprocessor/macro state — every construct extracted in isolation (api_check,
  index2stack, the sizeof/comma/cast forms) now COMPILES, but the full file still
  fails. So per-file progress now needs bisection WITHIN the real file (build
  progressively larger prefixes of the actual .c with its real includes), not
  minimal repros. The `near:` locator (cd30d0c) gives the token; pair it with a
  prefix-bisect harness.
- 2026-06-25 (final survey) — **the remaining lua blockers are now predominantly
  CROSS-TRACK, not Track C.** With the type system fixed, the `call to undeclared
  function` cluster resolves to: (a) **libc functions with no crtl declaration** —
  `fabs`/`frexp` (there is NO `lib/crtl/include/math.h` at all), `strerror`
  (string.h doesn't declare it), `fwrite`, `system`, `signal`. Growing the crtl
  header/library surface is **Track B** (`lib/crtl/**`, the M2 milestone). (b) a
  few residual macro re-scan bugs (`cast`/`cast_byte`/`novariant` — Track C, deep
  and context-dependent). The other big remaining gates — **`setjmp`/`longjmp`**
  (codegen; `compiler/exception_emit.inc` has the Pascal exception path but C
  setjmp/longjmp is unverified) and **multi-file linking** — are **Track A** /
  infrastructure. CONCLUSION: Track C has been pushed about as far as it can take
  lua ALONE; reaching a working lua build now needs Track B (libc surface) and
  Track A (setjmp) in tandem, plus the residual Track C parse tail (16
  `unexpected token`, diagnosable via the new `near:` locator).
- 2026-06-25 (even later) — **recursive `#if` macro expansion fixed (0fa88d1) —
  foundational.** `#if` evaluated a macro atom by reading its body as a literal
  number, so a chained object macro resolved wrong: lua's
  `LUA_INT_TYPE → LUA_INT_DEFAULT → LUA_INT_LONGLONG → 3` made
  `#if LUA_INT_TYPE == LUA_INT_LONGLONG` FALSE, so `LUA_INTEGER` / `lua_Integer` /
  `lua_Unsigned` were NEVER defined under the real headers. CPExprAtom now
  recursively evaluates a macro body as a sub-expression (depth-guarded). Also
  added LLONG_MAX/MIN + ULLONG_MAX to `lib/crtl/include/limits.h` (luaconf gates
  the long-long path on `#if defined(LLONG_MAX)`). **lua_Integer/lua_Unsigned now
  register.** NOTE: lua must be compiled WITH `-Ilib/crtl/include` on the path so
  `<limits.h>`/`<stddef.h>` resolve. Post-fix error landscape (with that include
  path): 16 `unexpected token`, 10 `call to undeclared function` (more files now
  reach real libc calls — the M2 crtl/extern surface), 3 `expected C expression`,
  5 parse-clean. The type-system foundation is now correct; the tail is libc
  surface + residual per-file parse bugs + setjmp (Track A) + multi-file linking.
- 2026-06-25 (later) — **session continued; lua core now 5/34 parse clean.**
  Added beyond the above: a permanent readable `near:` source-context on
  unexpected-token errors (cd30d0c — makes the tail diagnosable WITHOUT an
  instrumented rebuild; use it), indirect call through `(*expr)(args)` /
  dereferenced fn-pointer (e4a991a — lua's `(*g->frealloc)(...)`), and an
  IRLowerAddress `&(array-field)` collapse (007d14f — unblocked lmem.c). Filed
  `bug-c-sizeof-string-literal` and `bug-c-addr-of-unsupported-ir` (the latter
  partially fixed; `&s->v[0]` element-via-arrow remains). Current error
  landscape over 34 files: 20 `unexpected token` (still a long tail of DISTINCT
  per-file causes — e.g. ltable's `(lua_Unsigned)i` cast-vs-paren disambiguation,
  lstate's `sizeof(size_t)`; the `near:` context now pinpoints each), 7
  `call to undeclared function`, 2 `expected C expression`. Grind the tail with
  the locator; then `setjmp`/`longjmp` (Track A) + multi-file linking remain for
  an actual lua build.
- 2026-06-25 — **`__builtin_expect` handled** (2f62c2e): reduces to its first arg
  (lua's pervasive l_likely/l_unlikely). **Diverse-tail confirmed by windowed
  bisect:** the 21 `unexpected token` files each have a DIFFERENT context-
  dependent cause that does NOT reproduce in isolation (every minimal repro
  passes) and the lexer SrcPos sits ahead of the parse point, making them slow to
  pin. Concrete findings so far: lobject.c uses `sizeof("string")/sizeof(char)`
  → filed `bug-c-sizeof-string-literal` (pxx returns 8 not len+1; a VALUE bug, not
  the parse blocker); ltable.c fails inside a deeply-nested macro cast chain
  (`(...Integer)( limit + 1)))))->tt_)) & 0x0F)`); lmem.c parses its whole body
  but still errors (SrcPos at end-of-function — the real fault is elsewhere in the
  token stream). RECOMMENDATION for the next session: add a PERMANENT, precise
  C-parse error locator (print the failing token's own source offset + a readable
  window, not the lexer SrcPos) — without it, each `unexpected token` costs an
  instrumented rebuild to locate. Then grind the tail file-by-file.
- **Track:** C (C frontend) — isolated worktree `../frankonpiler-cfront`, branch
  `feat/cfront`. Lands to `master` only when `make test` + self-host fixedpoint
  stay green (C-body codegen edits the compiler binary → reseed).
- **Builds on:** `feature-c-source-frontend` (slices A–F = the *mechanics*:
  lexer fidelity, C expr parser, statements, multi-function/globals, fn-macros,
  embedded layout). This ticket is the *roadmap that drives those slices* toward
  portable desktop C, not embedded/Arduino.
- **Relation:** `feature-c-regex-library-devtest` (tiny-regex-c +
  freebsd-regex staged in `library_candidates/`) = the warmup workload.
  `feature-c-runtime-library` (`lib/crtl`) = the libc surface these need.

## Why a separate path ticket

`feature-c-source-frontend`'s north-star is Arduino/ESP — slices E (function
macros) and F (packed/bitfield/volatile layout) serve hardware structs. The
*desktop* path needs A–D solid, a real libc (`lib/crtl`), and two things the
existing ticket lists as **non-goals**:

- **setjmp/longjmp** — lua's default error model (`LUAI_THROW`/`LUAI_TRY` =
  setjmp/longjmp in plain C; only C++ builds use exceptions). No lua without it.
- **varargs *definition*** — calling `printf` works today (cdecl push). lua
  *defines* vararg functions (`luaL_error`, `lua_pushfstring`) → needs
  `va_list` / `va_start` / `va_arg` / `va_end`. Calling-vararg ≠ defining-vararg.

Embedded layout (slice F) is **deferred** here — desktop structs are
naturally-aligned; packed/bitfield/volatile not on the lua/sqlite path.

## Leverage (why this is tractable)

C frontend emits the **same IR** the Pascal frontend does → all 6 backends,
ELF, ABI come free. C `extern` maps straight to the existing
dynamic-link/external-symbol path → `printf`/`malloc`/`fopen` resolve to libc
(proven: `test/hello.c` compiles + runs against pinned). The declaration half
(header import: typedef/struct/union/enum, POD layout+alignment, extern decls,
integer macros) is **already mature**. Remaining work = the body half.

## Milestones

Each milestone = a runnable workload that proves the prior frontend slices.
gcc/tcc stdout-equality oracle throughout (deterministic int/string output).

### M0 — small fixtures (drives slices A–C)
Per-slice `.c` fixtures in `test/`: expressions (C precedence, pointer
arithmetic scaled by element size, casts, `sizeof`), control flow
(`if/while/do/for/switch` + break/continue/fallthrough), local decls with
initializers. Each matches gcc stdout. **Gate:** `make c-interop-devtest`
fixtures green; header-import regression suite still green (slice A risk).

### M1 — tiny-regex-c warmup (drives slice D)
`library_candidates/tiny-regex-c/re.c` compiles + a small driver matches known
patterns vs a gcc-built oracle. Today stops at `undefined variable (re_matchp)`
inside `re_match` → the multi-function/globals gap. Smallest real multi-function
C program; ideal slice-D proof. Drop-in (no upstream edits) preferred.

### M2 — libc surface (`lib/crtl`)
Grow `lib/crtl` to what lua needs: `string.h` (mem*/str*), `ctype.h`,
`stdlib.h` (malloc/free/realloc/qsort/strtod/atoi), `stdio.h`
(printf-family/f*), `math.h`, `setjmp.h`, `stdarg.h`. Prefer thin wrappers over
the host libc via the extern path; own implementations only where needed
(already have `string.c`, `ctype.c`). **Gate:** crtl header+src smoke green.

### M3 — setjmp/longjmp + varargs-define (the two scoped non-goals)
- `setjmp`/`longjmp`: real save/restore of callee-saved regs + SP + return addr.
  Per-target (start x86-64, then cross). Either intrinsic-lowered or a tiny
  asm crtl primitive — decide at implementation; keep lowering in shared IR
  where possible.
- `va_list`/`va_start`/`va_arg`/`va_end`: SysV varargs ABI on the *callee* side.
  **Gate:** a `.c` that longjmps out of a nested call, and one that defines +
  consumes a vararg fn, both match gcc.

### M4 — lua
Build the lua interpreter (`lua-5.4.x`, C89/C99 portable core) from upstream
source, staged under `library_candidates/lua` first. Run `lua` against its own
test suite where deterministic; smoke `print`, arithmetic, tables, functions,
closures, error handling (the setjmp path). **Gate:** lua REPL + a script set
match a gcc-built lua's stdout. Drop-in preferred; record any edit.

### M5 — sqlite
sqlite amalgamation (`sqlite3.c` single file — no multi-file link, but densest
macro/feature surface). Compile, then run a deterministic SQL script
(`CREATE/INSERT/SELECT`) and diff vs a gcc-built `sqlite3` shell. Expect new
pressure: heavy macros, `VFS`, integer-width assumptions. File follow-ups per
gap rather than bloating this ticket.

## Non-goals

- Embedded layout (packed/bitfield/volatile) — stays in
  `feature-c-source-frontend` slice F.
- C++ subset — separate follow-on.
- Full optimizer; `goto`/labels, VLAs, `_Generic`, C11 atomics — defer unless a
  target forces it (note: sqlite may use `goto` — revisit at M5).
- Non-Linux calling conventions.

## Testing

- Oracle = gcc (and/or tcc) stdout-equality; deterministic int/string output.
- Cross-bootstrap: body lowering goes through shared IR → run the multi-target
  harness (i386/arm32/aarch64/riscv32/xtensa) so cross regressions surface
  (x86-64 alone missed them in the generator/for-in work).
- Header-import regression suite stays green after every lexer change.

## Landmines

- Slice A lexer is shared with header import; collapsed multi-char operators are
  *relied on* by `CEvalConstExpr` (`<<` as two `tkLt`, `&`/`|` bitwise) — update
  the const-evaluator in the same slice.
- `->` → `tkDot` mapping is intentional; keep it.
- MAX_UCLASS / MAX_UFIELD pressure — C structs share Pascal's tables; preserve
  opaque-fallback guards.
- Keep body lowering in shared IR, not per-target codegen (cross landmines).
- lua's error model is a *hard* dependency on setjmp/longjmp — do not start M4
  before M3.

## Log
- 2026-06-25 — opened (Track D, worktree `feat/cfront`). Path = portable desktop
  C: tiny-regex warmup → lua → sqlite. Pulls slices A–D from
  `feature-c-source-frontend`; adds setjmp/longjmp + varargs-define (its
  non-goals) because lua requires both; defers embedded layout (slice F).
- 2026-06-25 — **Slice A (clexer operator fidelity) DONE.** Multi-char C
  operators now lex to distinct tokens: `++ -- += -= *= /= %= &= |= ^= <<= >>=`,
  `<<`=tkShl `>>`=tkShr, `&`=tkAmp(bitwise) vs `&&`=tkAnd(logical),
  `|`=tkPipe vs `||`=tkOr, `^`=tkXor, `?`=tkQuestion, `:`=tkColon (was unlexed →
  also activates the bitfield→opaque guard at CStructBodyIsSimple). `->`→tkDot
  kept. `CEvalConstExpr` rewritten to the new tokens in the same commit (added a
  bit-XOR precedence level) + the RegisterCMacroConsts guard; enum/macro const
  eval unaffected. New enum tokens appended at end of `TTokenKind` (no ordinal
  shift). Self-host byte-identical (`make bootstrap`). Header-import regression:
  c_interop devtest identical to pinned; new fixture `test/cslicea_lib.c` +
  `test_c_slicea.pas` (`<< >> & | ^` + precedence) matches gcc, wired into the
  C-import suite. Filed `bug-c-const-eval-bitwise-not` (pre-existing `~` typing
  quirk, omitted from the fixture). Next: Slice B (real C expression compiler).
- 2026-06-25 — **Slice B (C expression compiler) increment 1 DONE.** Real
  recursive-descent C expression parser in cparser.inc (`ParseCExpr` +
  `ParseCBinExpr` precedence-climber + `ParseCUnary` + `ParseCPrimary`),
  replacing the Pascal-`ParseExpr` borrow in `return`. Emits the shared AST
  (AN_BINOP/AN_NEG/AN_NOT/AN_INT_LIT/AN_IDENT/AN_CALL/AN_ARG/AN_ASSIGN/
  AN_STR_LIT) so all IR/backends apply. Full C precedence: `* / % | + - | << >>
  | rel | eq | & | ^ | bit-| | && | ||`, unary `- + ! ~`, assignment +
  compound-assign (right-assoc), function calls with arg chains, paren grouping,
  int/char/string literals, const-fold of imported enum/#define names.
  C-op -> AST-op mapping: `/`->tkDiv, `>>`->tkIdent(shr), `&`->tkAnd, `|`->tkOr
  (bitwise); `&&`/`||` tagged tyBoolean with operands normalised via `(e!=0)`
  for canonical 0/1. Added distinct `tkLogNot` for `!` (was collapsed with `~`
  -> bitwise); `~` stays tkNot. `return <expr>` from a top-level C main now
  exits with the value (IR: value-bearing CurProc<0 AN_EXIT routes through the
  Halt terminate path; Pascal program Exit never carries a value, so self-host
  byte-identical holds). LANDMINE (cost ~an hour): paramless self-recursion —
  `op := ParseCUnary` reads the function's *own Result* (pxx/FPC bare-funcname
  rule), not a recursive call; must be `ParseCUnary()`. Fixed in ParseCUnary
  (x3) and ParseCExpr. Verified: 20-expr differential sweep + fixture
  `test/cexpr_b.c` (=89) all match gcc; full C-import suite still green;
  self-host byte-identical. Deferred to increment 2: ternary `?:`, comma
  operator, pointer/lvalue unary (`* & ++ --`), cast, sizeof, postfix
  `[] . -> ++ --`. Next: Slice C statements (locals+if/while/for/switch) to
  unlock multi-statement bodies.
- 2026-06-25 — **Slice C (statements) increment 1 DONE.** ParseCStatementAST now
  dispatches: local declarations with initialisers (`int x=…, y=…;` — AllocVar
  per name, init lowered to AN_ASSIGN; main-scope locals land in BSS since
  CurProc<0, function locals get stack slots), expression statements
  (assignment/compound-assign/call), `if/else`, `while`, `for`, `break`,
  `continue`, empty `;`, nested blocks. Prefix + postfix `++`/`--` added
  (lowered to `lv = lv ± 1`, read side CloneAST'd to avoid aliasing). `break`
  keyword remapped tkHalt→tkBreak; added `continue`→tkContinue. `for` desugars
  to a while loop; with a post-expression it uses a first-iteration flag so a
  `continue` still runs `post` before re-checking the condition (the naive
  `init;while(cond){body;post}` desugar HANGS on continue — post is skipped so
  the counter never advances). REGRESSION fix: a stricter body parser broke
  test_c_macro_soup (a deliberately self-referential macro leaves an undefined
  identifier the old parser silently skipped) — an unresolved identifier now
  degrades to a `0` literal (best-effort frontend; undeclared *calls* still
  error). Verified: ~20 Slice-C differential programs (locals/loops/if/break/
  continue/fib/factorial) match gcc exit codes; new fixture `test/cstmt_c.c`
  (=82) wired into the suite; full C-import regression green; self-host
  byte-identical. Next: Slice D (compile ALL functions + globals + inter-fn
  calls) — merge the ParseCProgram/ParseCSubroutine drivers.
- 2026-06-25 — **Slice D (multi-function + globals) DONE.** ParseCProgram is now
  a two-pass driver over the one token stream: pass 1 (CHeaderMode) registers
  EVERY function signature and reserves every global, skipping bodies; pass 2
  compiles each function body via the existing ParseCSubroutine machinery
  (prologue/params/frame/epilogue). Forward + mutual inter-function calls
  resolve through ApplyCallFixups. Entry stub (x86-64, matching the prior
  convention which was already x86-64 machine code): `mov [rsp-save]; call main;
  exit_group(eax)` so main's int return is the process exit code; the call is a
  rel32 patched to main's body once compiled. `CTopLevelIsFunc` peeks
  type+declarator for a `(` and rewinds (TokPos save/restore) to classify
  function vs global. Globals reserved as zero-init BSS (CurProc<0 => skGlobal);
  non-zero/constant global initialisers deferred. LANDMINE: linkage across the
  two passes — added `CProgramMode`; a bodied function in a program is a LOCAL
  definition so pass 1 marks it ProcExternal=False (else a caller compiled
  before the callee's definition emits an EXTERNAL call -> "undefined symbol"),
  and pass 2's prototype `;` path must NOT re-mark external (it would clobber
  pass-1's definition-wins linkage before the body recompiles). Verified:
  forward calls, mutual recursion (even/odd), deep recursion (fib), 6-arg calls,
  shared globals all match gcc; new fixture `test/cmulti_d.c` (=104) wired in;
  full C-import regression green; self-host byte-identical. tiny-regex `re.c`
  now passes the old multi-function blocker (was "undefined variable
  (re_matchp)") — it reaches "main function not found" because it is a library
  (no main), the correct result. M1 (running regex) additionally needs
  pointers/arrays. Next: Slice B increment 2 — pointer/lvalue unary (`* &`),
  postfix `[] . ->`, casts, sizeof — the real blocker for regex/lua/sqlite.
- 2026-06-25 — **Slice B increment 2a (pointers + arrays) DONE.** Unary `*`
  (deref, rvalue+lvalue) and `&` (address-of) in ParseCUnary; postfix subscript
  `[]` in ParseCPostfix (AN_INDEX). Pointer arithmetic `p+i` is scaled by the IR
  automatically (it keys on operand type + IRPointerStride). Local decls now
  carry pointer element type (Syms.PtrElemTk/PtrElemRec from the captured
  CTypeElem* globals) and support fixed arrays `T a[N]` via AllocArray (N is a
  constant expression — literal/enum/#define). LANDMINE: pointer PARAMETERS also
  need their pointed-at type threaded (else `*a`/`a[i]` inside the body use the
  wrong width — `swap(int*,int*)` silently no-ops); added per-param pelemtk/
  pelemrec capture + PtrElemTk set after AllocParam in ParseCSubroutine. All in
  Track D's lane (clexer/cparser only) — reuses existing AN_DEREF/AN_ADDR/
  AN_INDEX, no shared-IR edits. Verified vs gcc: deref read/write, fixed arrays,
  array+pointer subscript, pointer arithmetic, pointer params, char* + string
  literal (`strlen("hello")`=5 — NUL-terminated literals work), `swap` idiom;
  new fixture `test/cptr_b2.c` (=122) wired in; full C-import regression green;
  self-host byte-identical. Deferred: struct field access (`. ->`), casts,
  sizeof, multi-dim arrays, array initialisers, mixed `int *p, q` declarators.
  Next: struct field access + casts (then char-string libc surface toward M1).
- 2026-06-25 — **Slice B increment 2b (struct field access) DONE.** `.` and `->`
  field access (both lex to tkDot since `->`→tkDot is intentional): ParseCPostfix
  builds AN_FIELD, and disambiguates by base type — a pointer base auto-derefs
  (AN_DEREF) so `p->f` = `(*p).f`, a value base takes the field directly. Uses
  the existing ResolveNodeRec (handles AN_DEREF-of-pointer-to-record and AN_FIELD
  chains) + RecFieldType. Struct-by-value locals now set RecName
  (LastTypeRecId := CTypeBaseRec before AllocVar) so AllocVar reserves RecSize
  and fields resolve. KEY FIX: top-level `struct/union/enum/typedef` DEFINITIONS
  were never laid out in program mode (only the header-import path ParseCUnit did
  it) — so every field resolved to offset 0 (`p.x` and `p.y` aliased). Wired the
  existing ParseCTypedef/ParseCEnumDecl/ParseCStructDecl into the program driver:
  pass 1 lays out types (once) + signatures + globals; pass 2 compiles bodies and
  skips type decls/globals via SkipCDeclToSemi (balanced-brace skip to the
  depth-0 `;`). All in Track D's lane (cparser only) — reuses existing AN_FIELD/
  AN_DEREF, no shared-IR edits. Verified vs gcc: value `.`, pointer `->`,
  struct-pointer params, nested structs, typedef structs, linked-list walk; new
  fixture `test/cstruct_b3.c` (=62) wired in; full C-import regression green;
  self-host byte-identical. Deferred: casts, sizeof, struct-by-value params,
  combined `struct X {..} v;`, array/struct initialisers. Next: casts + sizeof,
  then char-string libc surface (M2) toward running tiny-regex (M1).
- 2026-06-25 — **casts + sizeof + do/while + comma DONE** (slice B inc2c/2d).
  `(type)expr` casts (AN_PTR_CAST reinterpret-retag; cast-vs-paren disambiguated
  by peeking a type after `(`), `sizeof(type|expr|var)` -> compile-time int,
  `do/while` (first-iteration-flag desugar so break/continue keep C semantics),
  and the comma operator in statement / for-init / for-post positions. All in
  Track D's lane (cparser only), reusing existing nodes. Fixtures
  test/ccast_b4.c (=102), test/cloop_b5.c (=28). Self-host byte-identical.
- 2026-06-25 — **ROADMAP REFRAMED after empirically probing the frontend.** The
  frontend is more capable than the M0–M4 milestones implied: a bubble-sort over
  an array of structs (struct assignment, `a[j].key`, pointer params, nested
  loops) already matches gcc. The genuine remaining gaps to compile real C
  (lua/sqlite) are mostly C *language* features, NOT "M2 libc surface" (libc
  resolves via the extern/host path that already works — printf):
    - **switch/case (+ fallthrough)** — biggest lua/sqlite user; a fully-correct
      desugar needs break-only scope, but the IR's loop stack couples break and
      continue, so a clean switch likely wants a shared break-only-scope IR
      primitive -> **Track A** candidate. (Common break-terminated switches could
      desugar to do{}while(0)+matched-flag, but continue-in-switch would mis-bind.)
    - **ternary `?:`** — needs an AN_TERNARY node -> **Track A** (already flagged in
      track-a-c-frontend-shared-ir-touchpoints).
    - function pointers (decl + indirect call), global/`static const`
      initialisers (currently zero-init), multi-dim arrays, array/struct
      initialisers — Track C.
    - M3: `setjmp`/`longjmp` needs register-save/restore codegen -> **Track A**;
      varargs *define* (callee SysV ABI) -> Track C.
  Also: **lua/tiny-regex sources are not staged in this worktree**
  (`library_candidates/` is absent here; it lives in the master checkout), so
  M1/M4 cannot be compiled here until staged.
- 2026-06-25 — **PARKED for cross-track merge** (Track A/B/C sync). Branch is in
  steady, green, self-host-byte-identical state. One shared-IR touch
  (ir.inc AN_EXIT->Halt) is documented in
  track-a-c-frontend-shared-ir-touchpoints for the sister agents to reconcile.
- 2026-06-25 — **LUA STAGED + first real blocker located (empirical).**
  Fetched `lua-5.4.7` into `library_candidates/lua` (gitignored — vendor source,
  not committed). The live compiler already parses several core files: `lctype.c`
  reaches "main function not found" = full parse OK (a library, no main, like
  tiny-regex `re.c`). `lzio.c` / `lmem.c` / `lobject.c` fail. Reduced the failure
  to a minimal no-header reproducer: **function pointers.**
    - `BinOp f = add; f(3,4);` → `pascal26: error: call to undeclared function`.
    - `c.op(5,6)` (indirect call through a fn-ptr struct field) — same family.
    - lua hits this immediately: `lua.h` defines `lua_CFunction`/`lua_Reader`/…
      as `ret (*Name)(args)`, and the core calls through fn-ptr fields
      (`z->reader(L, z->data, &size)` in lzio.c is the exact first failure).
  Root cause: C fn-ptr typedefs register as plain `tyPointer` with the **argument
  signature not modelled** (cparser.inc ~2094), so `AN_CALL_IND` has no signature
  `Procs[]` index to marshal with, and a bare function name decays to `0` instead
  of its address. The IR primitives already exist and are proven on the Pascal
  side: `AN_CALL_IND` (parser.inc ParseProcVarCallAST), `AN_PROCADDR`,
  `SymProcSig`/`UFldProcSig` (defs.inc:772, symtab.inc:509), and the C-ABI
  `ProcCdecl` flag. **Next slice (Track C, binary-editing — `make test` +
  self-host + cross gate):** function pointers —
    1. fn-ptr typedef `ret (*Name)(params)` → synthesize a signature `Procs[]`
       entry (`RegisterProc` + `BodyAddr:=-1` + `ProcCdecl:=True`); store its index
       on the typedef (new `CTypedefProcSig` slot).
    2. var/field of that typedef → set `SymProcSig`/`UFldProcSig` from the typedef.
    3. call sites in cparser ParseCPrimary/ParseCPostfix: bare function name (not
       followed by `(`) → `AN_PROCADDR`; `name(args)` where `name` is a var with
       `SymProcSig>=0` → `AN_CALL_IND`; postfix `field(args)` with `UFldProcSig>=0`
       → `AN_CALL_IND`.
  Remaining lua blockers after fn-pointers (from the reframe): switch/case +
  ternary + setjmp/longjmp (**Track A**, shared-IR), varargs-define (Track C),
  and multi-file linking (lua core = 34 `.c`; no upstream amalgamation — build a
  one-unit include shim or add object linking).
- 2026-06-25 — **Function pointers DONE** (Slice B inc3). Typedef'd fn-ptr types,
  indirect calls through a variable / struct field / parameter, and bare
  function-name decay to address — all four forms match gcc. Implementation:
  ParseCDeclType's existing `(*name)(params)` declarator-skip now also captures
  the declarator name + builds a signature `Procs[]` entry (`RegisterProc` +
  `BodyAddr:=-1` + `ProcCdecl:=True` for the System V ABI), exposed via new
  globals `CTypeProcSig`/`CTypeFnPtrName`. ParseCTypedef registers the typedef
  with that signature (`CTypedefProcSig` slot); local-decl / struct-field /
  param sites thread it onto `SymProcSig`/`UFldProcSig`; ParseCPrimary lowers a
  bare function name to `AN_PROCADDR` and `var(args)` to `AN_CALL_IND`, and
  ParseCPostfix lowers `rec.field(args)`/`p->field(args)` to `AN_CALL_IND` via
  the new `RecFieldProcSig` accessor. All shared IR (`AN_CALL_IND`/`AN_PROCADDR`
  already proven on the Pascal side) — no codegen edits. LANDMINE (cost ~30 min):
  the recursive param-type parse must be `ParseCDeclType()` **with parens** — bare
  `ParseCDeclType` reads the function's own Result (pxx bare-funcname rule) →
  infinite loop (the exact landmine this ticket logged for Slice B inc1). Gate:
  `make test` green, self-host byte-identical, all 8 C fixtures match gcc; new
  fixture `test/cfnptr_b6.c` (=91) wired into `c-interop-devtest`. NB this was
  NOT lzio.c's first blocker — lzio/lmem/lobject still stop at an earlier
  `unexpected token (` (a different construct; SrcPos shows a NUL between
  newlines — a preprocessor artifact to investigate next). lua.h's fn-ptr
  typedefs (`lua_CFunction`/`lua_Reader`/…) now model correctly regardless.
- 2026-06-25 — **typedef of a struct tag now aliases the record** (Slice B inc4).
  `typedef struct Zio ZIO;` (no body, with a tag) was registered as an opaque
  `tyPointer`, dropping the record id — so `ZIO *z; z->field` resolved against
  REC_NONE (field offset 0, fn-ptr field calls unrecognised → `unexpected token
  (`). Now the no-body aggregate-typedef branch aliases the tag's (possibly
  forward) record via `FindOrForwardCTag`: `typedef struct T X;` → `X` is the
  record; `typedef struct T *X;` → pointer to it; tagless stays an opaque
  pointer. A later `struct T { ... }` body fills the same forward record, so
  `z->field` (incl. the lua ZIO reader fn-ptr field) resolves. This is the lua
  pattern (`typedef struct Zio ZIO;`, `typedef struct lua_State lua_State;` then
  the body in lstate.h — L->top now resolvable). Gate: `make test` green,
  self-host byte-identical, all C fixtures match gcc; fixture
  `test/ctypedef_struct_b7.c` (=51).
- 2026-06-25 — **forward-record field base re-anchored** (Slice B inc5). The real
  lzio.c `z->reader(...)` still failed after the alias fix; root cause was NOT the
  `#include`/preproc path but a **contiguous-field-range** bug exposed by the
  alias fix. `FindUField` scans a record's fields as a flat block
  `UFldNOff[UClsFBase[ci] .. +UClsFCount[ci]]`. A forward record (`typedef struct
  Zio ZIO;`) had `UClsFBase` fixed at forward-declaration time; lua's lzio.h then
  lays out an intervening `typedef struct Mbuffer {…} Mbuffer;` BEFORE the
  `struct Zio { … }` body, so Zio's body fields land past its recorded base and
  `FindUField('reader')` returns -1 (field — and thus its fn-ptr sig — invisible;
  every other field silently aliased offset 0). Fix: ParseCStructInto re-anchors
  `UClsFBase[ci] := UFldCount` when it begins laying out a body that has no fields
  yet (`UClsFCount[ci]=0`) — a no-op for freshly-created records, correct for
  forward ones. Diagnosis landmine: the symptom looked like a fn-ptr-sig/`#include`
  bug (UFldProcSig read as -1) but was a field-LOOKUP failure (`FindUField`=-1);
  only a minimal bisect (a 3-field intervening struct typedef) exposed it — single
  intervening fields didn't shift the base enough to interleave. Gate: `make test`
  green, self-host byte-identical, all 9 C fixtures match gcc; fixture
  `test/cstruct_fwd_interleave_b8.c` (=42). lzio.c now parses past `luaZ_fill` and
  reaches `luaZ_read`.
- 2026-06-25 — **ternary `?:` DONE** (new `AN_TERNARY` node). Real lzio.c stopped
  in `luaZ_read` at `m = (n <= z->n) ? n : z->n;`. Implemented the C conditional
  operator end-to-end: new `AN_TERNARY` AST node (Left=cond, Right=AN_PAIR(then,
  else), ASTTk=then-branch type); ParseCExpr parses it between logical-or and
  assignment, right-associative; IR lowering is **fully target-independent** —
  a hidden temp (`AllocVar` during lowering, same idiom as IRLowerClassMatch) +
  `IR_JUMP_IF_FALSE`/labels/`IR_STORE_SYM`/`IR_LOAD_SYM`, so only the taken branch
  is evaluated and NO per-backend codegen was needed. Logged in
  `track-a-c-frontend-shared-ir-touchpoints` (a new shared node) for A to
  reconcile. Self-host byte-identical (AN_TERNARY is C-frontend-only; the Pascal
  self-compile never emits it); `make test` green; fixture `test/cternary_b9.c`
  (=37, nested + only-taken-branch side effect proves no double-eval). **lzio.c
  now compiles clean** (full parse — it is a library, no main).
- 2026-06-25 — **LUA CORE SURVEY: 3 / 34 files parse clean** (lctype, lzio, + 1),
  with the remaining blockers triaged by instrumenting the "undeclared call" name:
    - **Function-like macro expansion bugs — the biggest cluster.** `call to
      undeclared function` is mostly an UNEXPANDED function-like macro parsed as a
      call: `cast` (`#define cast(t,exp) ((t)(exp))` in llimits.h), `novariant`,
      etc. IMPORTANT: function-like macros ALREADY work in general (`cpreproc.inc`
      has `CPExpandFunction` + arg parsing) — lzio.c's `cast_uchar(...)` compiled
      clean, AND an isolated repro of the full cast family
      (`cast`/`cast_int`/`cast_uint`/`cast_uchar`, nested) expands correctly and
      runs. So lstring.c's `cast`-reaches-parser failure is **context-specific**,
      NOT one common cause — the cluster is probably several distinct preprocessor
      edge cases (token-paste `##`, stringize `#`, a multi-token type arg in a
      particular position, a `CPMacroIsActive` recursion-guard interaction, or a
      macro that re-defines/undefs). Next step: bisect ONE failing file
      (lstring.c) down to the exact unexpanded use, then widen. Still likely the
      highest-leverage Track C cluster, but expect a handful of small fixes rather
      than a single feature.
      - **UPDATE — first two fixed/traced.** (a) Integer literal SUFFIXES
        (`U/L/UL/LL/ULL`) were never consumed by the C lexer, leaving e.g. `UL` as
        a dangling identifier that broke const expressions like
        `(0xffffffffffffffffUL / sizeof(t))` (DONE — clexer consumes the suffix;
        fixture `test/cint_suffix_b10.c`=42). (b) lstring.c's `cast` failure then
        traced NOT to the suffix but to real `MAX_SIZET = ((size_t)(~(size_t)0))`
        — the `~` bitwise-NOT const-eval, already filed as
        `bug-c-const-eval-bitwise-not` (Track C). So the macro "cluster" is indeed
        several independent small const-eval/lexer bugs, confirmed. Next: fix
        `bug-c-const-eval-bitwise-not`, then re-survey.
    - **`__builtin_offsetof`** (lfunc.c) — gcc builtin for `offsetof`; map to a
      compile-time field offset (Track C).
    - **`switch`/`case`** (lgc.c parses `switch` as a call) — Track A (break-only-
      scope shared-IR primitive per the reframe).
    - **`Unsupported linear node in IR codegen`** (ldebug.c) — an IR/codegen gap
      to isolate (could be Track A).
    - A few `unexpected token (` / `expected C expression` (lparser.c, lobject.c,
      ltable.c) — residual C constructs to bisect after macros land (many may be
      downstream of the missing macro expansion).
  RECOMMENDED ORDER: (1) function-like macro expansion [Track C, big, unblocks
  most], (2) `__builtin_offsetof` [Track C, small], (3) `switch/case` [Track A],
  (4) re-survey, then `setjmp/longjmp` [Track A] + multi-file linking (no upstream
  amalgamation; build a one-unit include shim or add object linking) for M4.
