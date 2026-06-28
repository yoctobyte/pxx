# C source frontend — compile C function bodies (statements + expressions)

- **Type:** feature
- **Status:** backlog
- **Track:** C (C frontend)
- **Opened:** 2026-06-17
- **Priority:** next major frontend after the cross-target language work lands
  (per roadmap; C frontend = the agreed next priority)
- **Relation:** the *declaration* half of C is already mature via header import
  (cparser.inc: typedef/struct/union/enum + POD layout, function decls →
  external symbols, integer `#define`/enum → consts). This ticket builds the
  *body* half — actually compiling C statements and expressions to IR — which
  today is a stub. Feeds the embedded north-star in
  devdocs/developer/frontends-and-targets-strategy.md (C frontend = "Valhalla of
  libraries"; with a thin C++ subset later, unlocks Arduino/ESP libs).

## Why "trivial subset, mostly solved" is half-true

Header import solved the DECLARATION half — and that is the hard ABI half
(layout, alignment, calling). It is genuinely mature. But the
STATEMENT/EXPRESSION half — compiling C *code* — is essentially greenfield:

Current body compiler (`ParseCStatementAST` / `ParseCProgram` in cparser.inc):
- compiles **only `main`**; other function bodies are skipped;
- statements handled: **`return`, `printf` (special-cased), `{ }` blocks** —
  everything else is *skipped to the next `;`*;
- expressions: reuses **Pascal** `ParseExpr`, and only for `return`.

So the work is real. Scope it honestly as "the C body frontend", not a polish
pass on header import.

## Key architectural fact (drives the design)

`.h` vs `.c` is naming convention only — after preprocessing it's one token
stream. `#include` is textual paste; the translation unit is one `.c` plus what
it pulls in. The convention (decls in `.h`, definitions in `.c`) exists because
of the One Definition Rule / linker duplicate-symbol constraint, not a language
rule. **Consequence:** the body frontend is the *same parser* as header import,
just with body-skipping turned off. `CHeaderMode` is a pragmatic switch, not a
language boundary — building on the existing parser is correct, not a rewrite.

## Slices

Ordered by dependency. Each its own commit(s) + test.

### A — C lexer fidelity (unblocks everything)
`clexer.inc` currently collapses multi-char C operators, losing information:

| C source | lexed as today | needed |
| --- | --- | --- |
| `++` `+=` | `tkPlus` | distinct inc / `tkPlusEq` |
| `--` `-=` | `tkMinus` | distinct dec / `tkMinusEq` |
| `->` | `tkDot` | ✅ keep (field access) |
| `&&` | `tkAnd` (== bitwise `&`) | distinct logical-and |
| `\|\|` | `tkOr` (== bitwise `\|`) | distinct logical-or |
| `<<` `>>` | two `tkLt`/`tkGt` | shift tokens |
| `^` | — (none) | XOR token |
| `?` `:` | — | ternary tokens |
| `*= /= %= &= \|= ^= <<= >>=` | collapsed | compound-assign tokens |

Add the distinct tokens. **Acceptance:** lexer round-trips every C operator to a
distinct token; existing header import unaffected (regression-test the import
suite).

### B — C expression compiler (C precedence + semantics)
Replace the Pascal-`ParseExpr` borrow with a real C expression parser at C
precedence: assignment + compound-assign, `?:`, `|| && | ^ &`, equality,
relational, shift, additive, multiplicative, unary (`* & ! ~ - + ++ --`
prefix + postfix), cast `(type)expr`, `sizeof`, primary (literal, ident, call,
`[]`, `.`/`->`, `( )`), comma operator. C semantics: integer promotion, usual
arithmetic conversions, array→pointer decay, **pointer arithmetic scaled by
element size**, char/string literals with escapes. Lower to existing IR.
**Acceptance:** arithmetic/pointer/struct-access expression tests match gcc
output (oracle).

### C — statements
`if/else`, `while`, `do..while`, `for`, `switch/case/default` (+ fallthrough),
`break`, `continue`, local declarations **with initializers** (C89 top-of-block
and C99 mid-block), expression statements (assignment, call), `++/--` and
compound-assign as statements. `goto`/labels deferred (rare; note as optional).
**Acceptance:** control-flow + loop programs match gcc output; break/continue
interop with codegen.

### D — multi-function programs + globals
Unify so a `.c` file compiles **all** defined functions (today `ParseCProgram`
only does `main`; `ParseCSubroutine` has a body path used in unit mode — merge
the drivers). Global variable definitions with storage + initializers (today
skipped to `;`); `static`/`extern` linkage; static locals; string/char literal
data. **Acceptance:** multi-function `.c` with globals + inter-function calls
runs; matches gcc output.

### E — function-like macros (embedded needs them)
Preprocessor today surfaces only object-like integer `#define` as consts
(`RegisterCMacroConsts` skips `CPMFunction`). Add function-like macro expansion
(`bitSet(x,b)`, `min(a,b)`, common Arduino idioms), conditional compilation in
body context, project-header `#include` resolution. **Acceptance:** a `.c`
using function-like macros expands + compiles correctly.

### F — embedded layout / ABI (gates real hardware structs)
From c-skipped-features-audit.md, currently stripped — low-priority for desktop
C, **central for Arduino/ESP**:
- `__attribute__((packed))` / `aligned(N)` — HIGH risk: stripped → wrong struct
  offsets → silent corruption. Honor them (audit Phase 1: attach layout flag,
  compute offsets accordingly).
- **bitfields** — skipped → opaque today; hardware register defs are mostly
  bitfields. Lay them out.
- `volatile` — map to a flag; lower to un-optimizable load/store (harmless now,
  required once any opt pass exists; MMIO/registers).
**Acceptance:** a packed + bitfield + volatile hardware-register-style struct
lays out and read/writes at correct offsets.

## Non-goals (explicit)

- **C++ subset (Arduino classes/methods/refs/overloads/namespace)** — separate
  follow-on ticket once C bodies work. Object model already exists PXX-side.
- **Full optimizer** — none today; not in scope.
- **`goto`/labels, VLAs, `_Generic`, full C11 atomics, setjmp/longjmp** — defer;
  rare in the target (embedded/Arduino) code.
- **Windows/other calling conventions** — Linux SysV (and the existing target
  ABIs) only; `stdcall`/`fastcall` attrs remain stripped.

## Testing strategy

- **Oracle = gcc (and/or tcc).** Compile the same `.c` with gcc and with PXX,
  run both, compare stdout — the output-equality pattern already used for cross
  targets. Deterministic integer/string output programs (no float in the oracle
  path, same rule as the chess demo).
- **Per-slice fixtures** in `test/`: `test_c_expr.c`, `test_c_stmt.c`,
  `test_c_multifunc.c`, `test_c_macro.c`, `test_c_layout.c`.
- **Regression-guard header import**: the existing C-import/binding suite must
  stay green after the lexer changes (Slice A is the riskiest for that).
- **Cross-bootstrap**: body codegen lowers through shared IR → run the
  multi-target harness so i386/arm32/aarch64/riscv32/xtensa all get it; the
  generator/for-in work proved x86-64 alone misses cross regressions.

## Landmines / notes

- Slice A touches a lexer shared with header import — collapsed operators are
  currently *relied on* by the const-evaluator (`<<` as two `tkLt`,
  `&`/`|` for bitwise). Update `CEvalConstExpr` to the new tokens in the same
  slice or it breaks enum/macro constant evaluation.
- `->` → `tkDot` mapping is intentional and correct; keep it.
- Keep body lowering in the shared IR (not per-target codegen) to avoid the
  per-target + local-array landmines hit in the generator work
  (cross-codegen-landmines.md).
- Watch MAX_UCLASS / MAX_UFIELD pressure — C structs share the tables with
  Pascal; the opaque-fallback paths already guard this, preserve them.

## Acceptance (overall)

A real, non-trivial `.c` program (multi-function, structs, loops, pointer
arithmetic, function-like macros) compiles with PXX and produces byte-identical
stdout to gcc, on x86-64 and under cross-bootstrap. Slices A–D = "compile real
C"; E–F = "compile real embedded C". C++ subset tracked separately.

## Log
- 2026-06-17 — opened. Analysis found the declaration half (header import) is
  mature but the statement/expression half is a stub (only `main`, only
  return/printf, Pascal ParseExpr borrowed). Scoped as the C body frontend,
  sliced A (lexer) → B (expr) → C (stmt) → D (multi-func/globals) →
  E (fn-macros) → F (embedded layout). Built on the existing parser (no
  rewrite): `.h`/`.c` is convention only, body frontend = same parser with
  body-skipping off. gcc as output-equality oracle.
- 2026-06-20 — Track B regex devtest made the multi-function gap concrete:
  compiling `library_candidates/tiny-regex-c/re.c` against pinned v17 and
  `-Ilib/crtl/include` stops at `undefined variable (re_matchp)` inside
  `re_match`. Header-only regex probes compile; full source needs the planned
  multi-function/body frontend work.
- 2026-06-20 — FreeBSD regex pressure probe now reaches source bodies too:
  `library_candidates/freebsd-regex/regerror.c` with project `lib/crtl/include`
  headers stops at `undefined variable (localbuf)` inside `regatoi`, another
  C-body scope/declaration handling gap after include resolution succeeds.
