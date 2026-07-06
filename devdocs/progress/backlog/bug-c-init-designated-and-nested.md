---
prio: 90  # auto
---

# C initializers: designated + nested/brace-elided initializers give SILENT wrong values

- **Type:** bug (miscompile — compiles clean, runs wrong). Track C (cparser init lowering).
- **Priority:** HIGH — silent wrong data, biggest c-testsuite failure cluster (9 tests).
- **Found:** 2026-07-06, c-testsuite conformance run (tools/run_c_conformance.sh), baseline 178/220.

## Failing tests (library_candidates/c-testsuite/tests/single-exec)
- 00048 `struct S s = { .b = 2, .a = 1 };` — designated struct init, exit 1 (s.a != 1)
- 00049 `struct S s = { .p = &x, .a = 1 };` — designator + address-of global
- 00050 anonymous union inside braced init `{1, 2, 3, {4, 5}}` — exit 3
- 00091 `S a[1] = {{1, {2, 3}}};` nested braces array-of-struct — exit 1
- 00092 `int a[] = {5, [2] = 2, 3};` array designator + size inference — exit 1
- 00147 `int arr[3] = {[2] = 2, [0] = 0, [1] = 1};` out-of-order — exit 2
- 00148 `struct S arr[2] = {[1] = {3, 4}, [0] = {1, 2}};` — exit 1
- 00205 brace-ELIDED flat init of `PT cases[]` (J interpreter snippet) — wrong values AND wrong element count (output 315 lines vs 72 expected → sizeof(cases) wrong too)
- 00216 sundry init battery (also needs compound literals — see feature-c-compound-literals)

## Symptom
Designators (`.field =`, `[idx] =`) apparently parsed but values land in wrong
slots (declaration-order assignment, designator ignored?). Brace elision
(C99 6.7.8p20: `{ {1}, 2 }` and fully flat lists) mis-distributes values and
mis-counts elements for `[]` size inference.

## Fix site
cparser.inc global/local braced-init path (same region as the v185 block-scope
`char buf[]="lit"` fix). Needs: designator cursor (current field/index that
designators reset), brace-elision descent, size inference = max index + 1.

## Gate
Remove the 9 lines from test/c-conformance/pxx.skip; tools/run_c_conformance.sh green.
