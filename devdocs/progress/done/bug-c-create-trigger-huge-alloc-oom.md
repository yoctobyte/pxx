# CREATE TRIGGER → spurious "out of memory" (huge bad-size alloc)

- **Type:** bug (C frontend / codegen miscompile) — Track A (shared codegen) /
  Track C (C→IR). Found by the broad SQLite feature suite (test/csqlite_suite.c).
- **Status:** backlog — characterized, not yet root-caused to the emitting op.
- **Opened:** 2026-07-06
- **Target:** x86-64 (reproduces there — so NOT a cross-only ABI gap).

## Symptom

Any `CREATE TRIGGER` on our compiled SQLite (3.46 amalgamation, libc-free) fails
with `rc=7 SQLITE_NOMEM ("out of memory")`. All step types (INSERT/UPDATE/DELETE
body) fail; even a trivial `BEGIN INSERT INTO b VALUES('x'); END`. The trigger is
never created, so trigger-dependent queries downstream return empty.

Repro (x86-64):
```
CREATE TABLE a(id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE b(msg TEXT);
CREATE TRIGGER t1 AFTER INSERT ON a BEGIN INSERT INTO b VALUES('x'); END;   -- rc=7
```

## Root cause (characterized, not fully localized)

The NOMEM comes from a **garbage ~3.2 GB allocation request**, not a genuinely
exhausted heap. `sqlite3Malloc`/`sqlite3DbMallocRawNN` receive `n ≈ 3210540000`
(> SQLITE_MAX_ALLOCATION_SIZE) and return NULL → `db->mallocFailed`.

Traced to a call of `sqlite3DbStrNDup(db, z, n)` during CREATE TRIGGER where the
arguments are **corrupt**: the instrumented values were
```
DbStrNDup n=3210540125 z=0x5245544641203174
```
`z = 0x5245544641203174` is not a pointer — it decodes (LE) to the ASCII bytes
**`"t1 AFTER"`**, i.e. the trigger definition *text content* is being passed
*as the pointer argument*, and `n` (the length) is garbage. So the CREATE TRIGGER
SQL-text storage path calls `DbStrNDup` with a `Token`'s `{z,n}` fields flattened
into the wrong argument slots (string value where the pointer should be).

The obvious candidates are ruled out:
- `sqlite3DbSpanDup` computes the right span length (n=25/30/…); its own
  `DbStrNDup(zStart, n)` is fine.
- `triggerStepAllocate`'s `sqlite3DbMallocZero(sizeof(TriggerStep)+pName->n+1)`
  is fine (pName->n=1, alloc=98).
- `sqlite3NameFromToken` takes `const Token*` (by pointer), works elsewhere.
- A minimal `int`→`u64` argument widening repro works.

So the failing call is the **full-statement SQL-text storage** in
`sqlite3FinishTrigger` (the `Token *pAll` span → schema `sqlite_master.sql`),
where a `Token`/large-text argument is passed in a way our codegen mis-lowers.
Smells like a **struct/Token argument-passing** edge case (cf. the v180
struct-by-value `IsRef` fix — this may be a sibling case not covered).

## Next steps

1. Instrument `sqlite3FinishTrigger` (sqlite3.c ~151820+) to find the exact
   `DbStrNDup`/`sqlite3MPrintf`/`sqlite3NestedParse` call storing the trigger SQL;
   print the `Token*`/args just before it.
2. Reduce to a no-SQLite C repro: a function taking a `struct {const char* z;
   unsigned n;}` (by value AND by pointer) forwarded into a
   `f(x, tok.z, tok.n)`-style call; compare pxx vs gcc arg values. The v180 fix
   (RegisterProc Params[].IsRef for tyRecord) is the place to check first.
3. Fix in the C→IR arg lowering / struct-by-value ABI; verify CREATE TRIGGER +
   the full test/csqlite_suite.c battery matches a **same-version** gcc-built
   3.46 oracle (the system sqlite3 is 3.45 → ROUND(75.125) etc differ; build the
   amalgamation with `gcc -no-pie -D_GNU_SOURCE` for a clean oracle).

## Related (fixed this session, same suite run)

- Local `char[] = "literal"` block-scope init sized to 1 with no data
  (cparser.inc) — broke `LEFT JOIN` (sqlite3JoinType's block-scope
  `static const char zKeyText[]`). FIXED.
- Large float literal `9223372036854775808.0` decoded as 0 (StrToDoubleBits
  i64 overflow, lexer.inc) — broke every REAL-vs-INT SQL comparison
  (sqlite3IntFloatCompare's 2^63 guard). FIXED.

## COPY-PASTE KICKOFF PROMPT (fresh session)

You are Track A/C (compiler + C frontend), master. Hunt a real cfront/codegen bug:
CREATE TRIGGER on our libc-free SQLite fails with spurious "out of memory".
sqlite3.c is gitignored scratch — instrument freely, revert when done, do NOT commit it.

Reproduce first (x86-64, ~30s build):
  cd /home/rene/frankonpiler
  cat > /tmp/trg.c <<'C'
  #define SQLITE_THREADSAFE 0
  #define SQLITE_OMIT_LOAD_EXTENSION 1
  #include <stdio.h>
  #include "sqlite3.h"
  #include "sqlite3.c"
  static void t(sqlite3*db,const char*s){char*e=0;int rc=sqlite3_exec(db,s,0,0,&e);printf("rc=%d %s | %.40s\n",rc,e?e:"ok",s);}
  int main(void){sqlite3*db;sqlite3_open(":memory:",&db);
   t(db,"CREATE TABLE a(id INTEGER PRIMARY KEY,name TEXT)");
   t(db,"CREATE TABLE b(msg TEXT)");
   t(db,"CREATE TRIGGER t1 AFTER INSERT ON a BEGIN INSERT INTO b VALUES('x'); END");
   return 0;}
  C
  ./compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/sqlite /tmp/trg.c /tmp/trg && /tmp/trg
  # CREATE TRIGGER -> rc=7 out of memory. Oracle (system sqlite3) creates it fine.

Established (do NOT re-derive — see this ticket body above):
- NOMEM is a garbage ~3.2GB alloc, not a full heap. It reaches sqlite3Malloc/
  sqlite3DbMallocRawNN via sqlite3DbStrNDup(db, z, n) with CORRUPT args:
  z = 0x5245544641203174 = ASCII "t1 AFTER" (the trigger TEXT passed AS the
  pointer), n = garbage. So a Token/large-text arg lands in the wrong slot.
- Order per trigger (instrument sqlite3Malloc + DbStrNDup + sqlite3DbSpanDup with
  fprintf on n>1e6): triggerStepAllocate (fine, pName->n=1, 98B) -> SpanDup (fine,
  n=25) -> the bad DbStrNDup. So the bad call is in sqlite3FinishTrigger's
  SQL-text storage (~sqlite3.c 151820+), AFTER the step is built.
- RULED OUT: SpanDup length, triggerStepAllocate, sqlite3NameFromToken (Token* by
  pointer), a minimal int->u64 arg widening (works standalone).

First steps:
1. Instrument sqlite3FinishTrigger to find the exact call storing the trigger SQL
   (grep DbStrNDup / sqlite3MPrintf / sqlite3NestedParse there); print the Token*
   and its ->z/->n right before it. Confirm which arg is corrupted and how the
   Token reaches that call (by value? via a helper that takes Token by value?).
2. Reduce to a NO-SQLite C repro: a `struct Token {const char* z; unsigned n;}`
   forwarded into `f(db, tok.z, tok.n)` and/or a helper `g(db, Token t)` (by
   value). Compare pxx-emitted arg values vs gcc. Start from the v180 struct-by-
   value fix (RegisterProc Params[].IsRef for tyRecord in symtab/parser) — this
   is likely a sibling case (a specific by-value struct or mixed ptr+len arg
   shape it doesn't cover). See [[project_cross_sqlite_libcfree_v180]].
3. Fix in the C->IR arg lowering / struct-by-value ABI (Track A shared codegen).
   Gate: the /tmp/trg.c repro creates the trigger, then the FULL
   test/csqlite_suite.c battery matches a SAME-VERSION oracle
   (`gcc -no-pie -D_GNU_SOURCE -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION=1
   -I library_candidates/sqlite test/csqlite_suite.c -o /tmp/oracle -lm`), plus
   make test + self-host byte-identical + test-lua-cross 24/24. Reduce+commit a
   regression test. USER HUNCH: "smells like recursion / unhandled trigger path"
   — weigh it, but the ASCII-as-pointer evidence says argument passing.

## RESOLUTION (2026-07-06, Track A/C)

FIXED — three compiler bugs, none of them in argument passing (the ASCII-as-
pointer evidence pointed one level earlier: a struct COPY, not a call):

1. **Ternary with struct-valued arms (ir.inc AN_TERNARY)** — root cause of the
   CREATE TRIGGER NOMEM. The lowering yielded `IR_LOAD_SYM` for the record
   hidden temp; `EmitLoadVar` on a record local takes the scalar path and loads
   the record's FIRST 8 BYTES, but `IR_COPY_REC` consumes source ADDRESSES. So
   `c = cond ? a : b` copied 16 bytes from `*(a.z)`. The corrupting site was the
   sqlite grammar's A-overwrites-T Token copy
   (`yymsp[-10].minor.yy0 = (yymsp[-6].minor.yy0.n==0 ? T : D)`), which filled
   the Token with SQL text bytes ("t1 AFTER" as .z, " INS" as .n); FinishTrigger
   then passed those to DbStrNDup. Fix: record-typed ternary yields `IR_LEA`
   (target-independent, fixes all backends).

2. **ResolveNodeRec had no AN_TERNARY case (symtab.inc)** — a NESTED struct
   ternary resolved REC_NONE → outer temp had no RecName → garbage copy size.
   Fix: recurse into the arms.

3. **Float-literal decode imprecision (lexer.inc StrToDoubleBits)** — found by
   the suite's remaining ROUND diffs vs a SAME-VERSION gcc oracle
   (ROUND(2.5,0)=2.0, ROUND(75.125,2)=75.12). Two defects: (a) mantissa was
   truncated, never rounded → EVERY inexact literal 1 ulp low (0.1 = ...999);
   (b) the negative-exponent loop shed a whole decimal digit of N per step once
   D capped → 1.0e-100 decoded to 0. sqlite's Dekker double-double kernels
   (AtoF, FpDecode) depend on exactly-decoded compensation constants, so runtime
   REAL parsing was silently off (invisible at %.15g, visible at ROUND halfway
   cases). Fix: round-to-nearest-even final rounding + round-to-odd (sticky) on
   all lossy intermediate steps + exact power-of-2 rescaling of N before lossy
   divs; also made the mantissa-extraction loop overflow-safe for D > 2^62.
   Result: exponent sweep e-307..e+308 is 94% bit-exact vs gcc, residual worst
   case 1 ulp on sparse |e| ≳ 130 literals (Int64 precision ceiling; a 128-bit
   intermediate would finish the job if ever needed). All sqlite constants
   decode exactly.

Regression tests: test/cternary_struct_value_b141.c,
test/cfloat_literal_precise_b142.c (wired into make test).
Gates: /tmp trg repro rc=0; FULL test/csqlite_suite.c byte-identical vs
same-version gcc oracle (build oracle with an extra TU defining
`const char sqlite3_version[]` — the vendored amalgamation's line-498 edit
drops the definition when sqlite3.h is pre-included); make test + self-host
fixedpoint; test-lua-cross 24/24.
