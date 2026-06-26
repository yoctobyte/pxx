# C: 2D array struct field — partial-index row decay broken

- **Type:** bug (Track A/C — C frontend multidim array field + shared-IR index model).
- **Found:** 2026-06-26 lua bring-up (`luaS_new` / `g->strcache[i]`).

## Symptom
A single index into a 2-D array struct field returns the *element value* at
`[i][0]` instead of the *row address* (`&field[i][0]`, i.e. C array decay to a
pointer). Crashes / corrupts as soon as the "row" is indexed again.

Minimal repro:
```c
struct G { char* cache[4][2]; };
static struct G g;
int main(void){
  g.cache[1][0] = "hello";
  char** p = g.cache[1];   /* p SHOULD be &g.cache[1][0] */
  /* actual: p == g.cache[1][0]  (the stored char*, not the row addr) */
  char* q = p[0];          /* then deref-garbage -> SIGSEGV */
  return 0;
}
```
Instrumented: `P = value of cache[1][0]`, not the row address; `p[0]` then reads
4 bytes (movslq) from inside the "hello" string.

This is the live blocker for a printing `lua`: `lua_State`'s
`TString *strcache[STRCACHE_N][STRCACHE_M]` is read row-wise in `luaS_new`
(`TString **p = G(L)->strcache[i]; ... p[j]`). After the round-18 fixes (array
field decay, array-init materialization, `*const`) lua runs through string
interning + `luaT_init`; this is the next crash (in `luaS_new`).

## What works / what doesn't
- **Full 2-D indexing `cache[i][j]` is correct** (verified with 4 distinct
  rows/cols — store/load agree, no aliasing). The field is laid out as a flat
  `outer*inner` array (`cparser.inc` field-array parse multiplies the dims into
  one `arrLen`).
- **Partial index `cache[i]` (row decay) is wrong** — it loads the element
  rather than yielding the row address. C requires the decay; Pascal's flat N-D
  path does NOT (it *errors* on a wrong subscript count — `parser.inc` ~1425
  `nIdx <> NDInfoNDims`), so there is no existing path to reuse.

## Cause
1. The C struct-field parse (`cparser.inc` ~3099) flattens `[N][M]` into a
   single `arrLen = N*M` and never records `UFldArrNDims` / per-dim spans
   (stays 0). So the frontend cannot tell a 2-D field from a 1-D one.
2. The C indexer (`ParseCPostfix`, `cparser.inc` ~711) builds one `AN_INDEX`
   per subscript and tags it `CNodePointeeTk(base)` — for a multidim field a
   single subscript should yield a **row pointer** (`&field + i*innerSpan*elem`,
   typed pointer-to-element), not a loaded element.

## Fix sketch (multi-session — do NOT half-land; self-host gate risk)
- Record `UFldArrNDims` + `UFldArrDimLo/Span` for C array fields (mirror the
  Pascal field parse at `parser.inc` ~10366), capturing each `[dim]` count
  (macro-expanded constants — STRCACHE_N/M are `#define`d ints, arrive as
  `tkInteger`).
- Make a single subscript of an `NDims>=2` field produce the row address as a
  proper pointer-to-element value: `&field + i*(product(inner spans)*elemSize)`,
  so that both `char** p = cache[i]` AND `cache[i][j]` (= row-ptr then pointer
  index) work uniformly. The clean build is `(char*)&field + i*rowStride` (stride
  1) then re-tag the result pointer-to-element so a following `[j]` scales by the
  element size.
- **Blocker for the clean version:** the C frontend's expression type model is
  thin (`ASTTk` + a few sym lookups; `CNodePointeeTk` only handles AN_IDENT /
  AN_INDEX). A row-pointer is a *pointer-to-pointer* (`char**`) carried by an
  `AN_BINOP`/synthetic node; there is no per-node `PtrElemTk` for expression
  results, so a subsequent `[j]` re-derives `tyInteger` and does a 4-byte load.
  Needs either a per-node pointee channel for C, or a dedicated "row-index" AST
  node whose IR lowering computes the row address with `rowStride` and tags the
  result pointer-to-element.

## Related
- Round-18 landed fixes (commit d84d9164): array-field decay, array brace-init
  materialization, `*const` declarator — all byte-identical, in
  `feature-c-desktop-lua-sqlite-path` log.
- Multidim **local** C arrays (`int m[3][4]` in a function body) are *also* not
  parsed (only the first `[dim]`, `cparser.inc` ~1340) — same feature family,
  fix together.
- Sibling lua run blockers: `bug-c-vararg-overflow-area` (6+ varargs),
  global array-of-struct init (luaL_Reg openlibs tables, still BSS).
