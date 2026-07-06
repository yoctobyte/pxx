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
