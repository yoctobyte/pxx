---
summary: "33 skip-listed pascal-conformance tests now exit-code-pass after the 2026-07-14/15 night arcs — per-test re-triage to unskip the genuinely green ones"
type: task
prio: 40
---

# Re-triage: 33 skipped conformance tests now pass by exit code

- **Type:** task (conformance bookkeeping — Track A/P follow-up of the
  2026-07-14/15 night session). Per the skip-file header, unskipping is
  deliberate per-test review: the runner checks EXIT CODES and the %FAIL
  contract only, so an "exit 0" can still print wrong output (tforin24's
  skip reason documents exactly that trap — it is in this list).
- **Opened:** 2026-07-15 (night), from a skip-list-emptied sweep at 86c34639:
  curated 295 pass/0 fail; without the skip list 328 pass — 33 listed tests
  no longer fail.

## Candidates (verify OUTPUT against FPC before unskipping each)

tarray1, tclass10c, tclass12a, terecs16, texception2, tforin14,
tforin24 (KNOWN wrong-output trap), tforin25, tgeneric9, tgeneric28,
tgeneric34, tgeneric35, tgeneric37, tgeneric38, tgeneric39, tgeneric40,
tgeneric41, tgeneric43, tgeneric44, tgeneric45, tgeneric46, tgeneric47,
tgeneric80, tgeneric81, tgeneric82, tgeneric89, tgeneric90, toperator12,
toperator93, tprop, tsealed4, tstatic1, tstatic5

Likely green-lit by tonight's arcs: record value-typecast offsets, bitwise
`not` family, qword domain/conversion fixes, {$Q+} + catchable
EIntOverflow/EDivByZero, ValQWord + qword text I/O, `on E do` w/o var name,
type-helper work from the prior session.

## Method

For each: compile + run under pxx AND FPC, diff stdout byte-for-byte
(the tint642 method); a {%FAIL} test must be REJECTED with the sweep's
strict flags. Unskip only on a clean diff; else update the reason with the
real residual. Expect several tgeneric* to be one shared fix — cluster.
