---
prio: 45  # auto
---

# C99 designated initializers + compound literals unsupported

- **Type:** feature (C99 parser gap)
- **Track:** C — cfront (`compiler/cparser.inc`, initializer-list parsing)
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B probing untested C-frontend surface for
  `feature-demo-chess`/general C coverage.

## Problem

Three related C99 initializer forms all fail to parse with `expected C
expression`:

**1. Designated struct-field initializers:**
```c
struct Point { int x, y, z; };
struct Point p = { .y = 5, .x = 1, .z = 9 };   /* order-independent, by name */
```

**2. Designated array-index initializers:**
```c
int arr[5] = { [2] = 7, [4] = 9 };             /* sparse, by index */
```

**3. Compound literals:**
```c
int total = sum((struct Point){ 3, 4 });       /* anonymous struct value */
int *p = (int[]){ 1, 2, 3 };                   /* anonymous array value */
```

All three are ordinary, reasonably common C99 constructs (designated
initializers especially so — they're idiomatic for sparse tables, opt-in
struct fields, and self-documenting initialization order). None currently
parse; each is a separate `expected C expression` error at the `.field =` /
`[idx] =` / `(Type){...}` token.

## Scope

Plain brace-list initializers (`{ 1, 2, 3 }`, nested `{ {1,2}, {3,4} }`) and
`static`/global initializer lists already work elsewhere in the test suite —
this ticket is specifically the three designator/compound-literal forms above.

## Acceptance

- The two designated-initializer repros above compile and print the correct
  values (`1 5 9` and `0 0 7 0 9`).
- The compound-literal repros compile and print the correct values (`7` and
  `2`).
- Existing plain-brace-list C init tests stay green.

## Log
- 2026-07-02 — Filed by Track B. All three forms isolated via minimal repros;
  no code touched — test/repro only.
- 2026-07-09 (A+B+C) — **Designated initializers (both forms) DONE.** Designated
  STRUCT-field init `{.y=5,.x=1,.z=9}` already worked (local record init routes
  through the recursive brace-elision walker, which handles `.name`). Designated
  ARRAY-index init `{[2]=7,[4]=9}` was the gap: the LOCAL scalar-array brace path
  (ParseCLocalDeclAST) parsed positionally only and errored on `[`. Now handles
  `[k]=`, unsized-array sizing to the max touched index, mixed
  designated+positional, and GNU range `[lo ... hi]=`. gcc-verified,
  test/carray_designated_init_b211.c → exit 42, self-host byte-identical,
  conformance 219/0/1. (v181; also see [[feature-c-compound-literals]] range work.)
  **Remaining for this ticket: compound literals `(struct P){3,4}` / `(int[]){1,2,3}`
  as expressions** — the ParseCUnary `(T){...}` hook + anonymous-object
  materialization (block-scope automatic, file-scope static). That is the
  self-host-fragile keystone tracked in [[feature-c-compound-literals]] (also the
  last blocker for c-testsuite 00216). Designated-init acceptance met; compound-
  literal acceptance still open.
- 2026-07-09 (A+B+C) — **RECORD compound literals DONE** (base + postfix + nested/
  whole-value + file-scope-global-array; AN_COMPOUND_LITERAL node, defs.inc=81).
  `sum((struct Point){3,4})` → 7, gcc-verified, tests b216-b219, self-host byte-
  identical, conformance 219/0/1. Full detail in [[feature-c-compound-literals]].
  **Remaining for this ticket: ARRAY compound literals `(int[]){1,2,3}`** — a
  distinct path (array-type cast `(int[])` isn't recognised by ParseCDeclType/
  CIsCastAhead; needs an array temp, not a record temp). No conformance test
  isolates it; 00216 does not use it. Record-CL acceptance met; array-CL open.
