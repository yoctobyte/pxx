---
prio: 28  # auto
---

# C11 _Generic selection

- **Type:** feature (cparser). Track C. Low priority (C11, rare in target corpus).
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00219: `#define gen_sw(a) _Generic(a, const char *: 1, default: 8, int: 123)`
  plus assorted controlling-expression type checks. "expected C expression".
  Compile-time type dispatch: pick assoc whose type matches the controlling
  expr (after lvalue conversion), else default.

## Gate
Drop 00219.c from test/c-conformance/pxx.skip; runner green.

## RESOLVED 2026-07-09 (A+B+C agent) — dedicated on-demand CGType descriptor

Implemented without the feared full type-model overhaul. The 2026-07-07 triage
overstated it: most distinctions _Generic needs already live in TTypeKind —
int/long split as tyInt32/tyInt64, char/signed char/unsigned char as
tyChar/tyInt8/tyUInt8, struct via rec id. The only genuinely-missing bits were
**long vs long long** (both collapse to tyInt64 on LP64) and **pointee-const**
(`int*` vs `const int*`).

Approach — a compact structural descriptor (`cgXxx`, defs.inc) built ON DEMAND
only inside `_Generic` (pool resets per call, ~10 slots), never persisted per
symbol:
- `_Generic` desugars at parse time to the selected association's expression; the
  controlling expr and unchosen assocs are parsed then discarded (never lowered),
  so no codegen. (cparser.inc ParseCPrimary + CGAlloc/CExprCG/CGConvControlling/
  ParseCGAssocType/CGMatch helpers.)
- Controlling type = lvalue conversion (strip top const) + array/function decay to
  pointer, then structural match vs each association type-name.
- Two minimal additions: `SymPtrPointeeConst` (per C pointer symbol) captured in
  CAllocDeclVar from a new `CTypeBaseConst` flag; and an l/L/ll integer-literal
  suffix (CAttrFlags bit 16/32) so `17L` types as long (was silently dropped —
  the lexer ate the suffix). `long long` distinguished on the association side via
  `CTypeLongLong`.

All C-mode-gated + additive; the Pascal self-host source never reaches it, so
self-host stayed byte-identical (one-step converge). 00219 byte-identical, dropped
from pxx.skip; conformance 219/0/1; whole-corpus reran with no regression from the
literal-suffix change; test/cgeneric_selection_b209.c -> exit 42, wired into
test-core; stable re-pinned v178->v179. Commit: see resolve.

## Triage note 2026-07-07
Not bounded: 00219 distinguishes types with full C precision — `const char *` vs `int`, `int *` vs `int * const` (const-qualified pointer), `struct a` vs `struct b`, `int[4]`, `int **`, `long` vs `long long` vs `int`, function-pointer types, signed/const int variants. pxx does not track const-qualification, pointer-const, or full integer-width distinctions in its type model, so real _Generic dispatch needs a much richer C type representation + a type-compatibility matcher. Large feature, not a parser-only add.
