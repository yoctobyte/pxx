# C desktop path — compile real portable C (tiny-regex → lua → sqlite)

- **Type:** feature (track-D milestone path)
- **Status:** backlog
- **Opened:** 2026-06-25
- **Track:** D (C frontend) — isolated worktree `../frankonpiler-cfront`, branch
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
