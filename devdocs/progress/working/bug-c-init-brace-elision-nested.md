# C brace elision + nested/anonymous-member aggregate initializers

- **Type:** bug (cfront init lowering — hardest slice). Track C. Slice of
  [[bug-c-init-designated-and-nested]].
- **Found:** 2026-07-06 c-testsuite; scoped during that ticket's triage.

## Cases
- 00050 anonymous union inside a braced init `{1, 2, 3, {4, 5}}` (exit 3)
- 00091 `S a[1] = {{1, {2, 3}}};` nested braces array-of-struct-with-subarray
- 00205 brace-ELIDED flat init of `PT cases[]` (J-interpreter snippet): a fully
  flat list filling nested struct/array fields — currently wrong values AND
  wrong element count (315 output lines vs 72; `sizeof(cases)` wrong)

## Symptom
C99 6.7.8p20 brace elision: a flat `{a, b, c, d}` fills nested subaggregates
left-to-right, and inner `{...}` braces bound how many elements a subaggregate
consumes. pxx's init walkers are one-level (fldI/ei flat), so nested/elided
lists mis-distribute values and mis-count top-level elements → wrong `[]` size.

## Needed (the real work)
A recursive initializer walker over the target type tree that consumes tokens
with proper brace-elision semantics (open brace = descend + bound; close =
pop; flat run = keep filling the current leaf sequence). Likely a rework of the
init loops rather than a patch. Do AFTER
[[bug-c-init-struct-designators]] + [[bug-c-init-array-designators]] land, since
it subsumes their cursors.

## Gate
00050/00091/00205 exit 0 + correct `sizeof`; drop from
`test/c-conformance/pxx.skip`; regression tests; `make test` + self-host.
