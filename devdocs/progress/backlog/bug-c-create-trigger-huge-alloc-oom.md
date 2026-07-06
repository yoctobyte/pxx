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
