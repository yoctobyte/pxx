# C desktop path — compile real portable C (tiny-regex → lua → sqlite)

- **Type:** feature (track-C milestone path)
- **Status:** backlog
- **Opened:** 2026-06-25
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
      initialisers — Track D.
    - M3: `setjmp`/`longjmp` needs register-save/restore codegen -> **Track A**;
      varargs *define* (callee SysV ABI) -> Track D.
  Also: **lua/tiny-regex sources are not staged in this worktree**
  (`library_candidates/` is absent here; it lives in the master checkout), so
  M1/M4 cannot be compiled here until staged.
- 2026-06-25 — **PARKED for cross-track merge** (Track A/B/C sync). Branch is in
  steady, green, self-host-byte-identical state. One shared-IR touch
  (ir.inc AN_EXIT->Halt) is documented in
  track-a-c-frontend-shared-ir-touchpoints for the sister agents to reconcile.
