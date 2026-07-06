# C array element designators `[i] = v` + `[]` size inference from designators

- **Type:** bug (cfront init lowering). Track C. Slice of
  [[bug-c-init-designated-and-nested]].
- **Found:** 2026-07-06 c-testsuite; scoped during that ticket's triage.

## Cases
- 00092 `int a[] = {5, [2] = 2, 3};` — designator + size inference (a[1]==0,
  a[3]==3, sizeof = 4 ints)
- 00147 `int arr[3] = {[2] = 2, [0] = 0, [1] = 1};` — out-of-order
- 00148 `struct S arr[2] = {[1] = {3, 4}, [0] = {1, 2}};` — array-of-struct
  designators (composes with [[bug-c-init-struct-designators]])

## Symptom
`[idx] =` designator ignored → sequential fill → wrong slots; and for `[]`,
size = element-count instead of `max designated index + 1`, so both values and
`sizeof` are wrong.

## Fix (a "current element index" cursor)
Before each element, if the stream is `[ constexpr ] =`, evaluate the index,
set the running `ei` to it (consume `[ ] =`); else keep sequential `ei`. Track
`maxEi` and, for an unsized `[]`, set `arrLen = maxEi + 1`.
- **Local:** the array loop in `ParseCLocalDeclAST` ~cparser.inc:2365 and the
  `arrLen`/`recArrInitCount` size logic ~2474.
- **Global:** the flat-int PendingInit array path ~cparser.inc:3731 (uses
  `PendingInitElem = ei`).

## Gate
00092/00147 exit 0 (00148 needs struct designators too); drop from
`test/c-conformance/pxx.skip`; regression test; `make test` + self-host.

## Log
- 2026-07-06 — resolved, commit c0abec31.
