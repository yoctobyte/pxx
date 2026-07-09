---
prio: 55  # auto
---

# C switch: non-compound body + case labels inside nested statements (Duff's device)

- **Type:** bug (cparser statement lowering). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00051: `switch(x) case 0: ;` — switch body is any STATEMENT, not necessarily a
  `{...}` block. Error "Expected: {, but got: case". Also case labels inside a
  nested plain block within the switch braces.
- 00143: Duff's device — `case` labels inside a `do {...} while` nested in the
  switch. Compiles but exit 1 (wrong copy) → dispatch doesn't jump into the loop.

## Root cause
Switch lowered as structured case-list instead of C semantics: `case`/`default`
are LABELS on arbitrarily nested statements inside the switch body; dispatch is
a computed goto to the matching label.

## Gate
Drop 00051.c/00143.c from test/c-conformance/pxx.skip; runner green.

## Attempt 2026-07-07 — non-brace body change reverted (broke self-host)
Tried relaxing ParseCSwitchAST's `Expect('{')` to accept a single-statement
switch body (00051). The change is straightforward Pascal, but building the
edited compiler failed self-host with a spurious "unexpected character" (a parse
desync, not a real bad byte — reverting cleared it). The AN_SWITCH body is
consumed by the seed compiler in a way sensitive to the restructure. Needs the
proper case-as-label rework (per below) done carefully with incremental
self-host checks, not a quick relax of the brace requirement. 00143 (Duff's)
separately: OUTPUT already matches expected but exit code is 1 (a control-flow /
final-return issue, not the copy loop) — investigate that independently.


## Triage 2026-07-07
Confirmed the parser rejects a non-compound switch body outright: `switch(x) case
0: ;` errors "unexpected token" at the `case` after `switch(x)` (expects `{`).
This is the switch-as-labels rework, not a narrow accept — pxx lowers switch as a
structured case-list, but C treats case/default as LABELS on arbitrarily nested
statements with computed-goto dispatch (Duff's device 00143 puts case labels
inside a do-while). Needs: (1) accept any statement as the switch body, (2) a
scan that collects case/default labels from the nested body and emits a dispatch
jump-table/if-chain to those labels, (3) fall-through by label ordering. Focused
rework (peer of bug-c-init-brace-elision-nested). Parked.

## Attempt 2 2026-07-08 (a-agent) — non-compound body works, but destabilizes self-host
Implemented the 00051 half cleanly at the C level: ParseCSwitchAST now accepts a
non-`{` body — when the token after `)` is not `{`, parse statements until one is
not a bare AN_CASE/AN_DEFAULT marker (those don't attach their labelled statement
in the fallthrough model, so the body = the marker(s) + the one real statement).
No braces in the added comments (the earlier "unexpected character" was a
nested-comment brace imbalance, avoided here).

BUT self-host no longer reaches a ONE-STEP fixedpoint: clean master builds
byte-identical in one step; with this change `make all`'s build≠verify (differ at
byte 97), and it only converges on the SECOND iteration (v2==v3, sizes 4.70M vs
4.67M). The change is C-frontend-only yet perturbs how the compiler reproduces
its own (Pascal) binary — the classic codegen-reseed / address-sensitive
convergence. Reverted rather than reseed: a rare idiom (00051) isn't worth
shipping a change that breaks the one-step self-host gate from the current stable.
Next attempt must land it WITH a reseed step (make stabilize→pin) and confirm the
two-step convergence is truly deterministic, or find why restructuring this
C-only function shifts Pascal codegen. 00143 (Duff's) still separate
(output-matches / exit-1 control-flow bug).

## FIXED 2026-07-09 (cfront-agent, combined A+B+C) — both 00051 and 00143
Reworked C switch to the labels-on-statements model. Key: case/default are LABELS
on arbitrarily nested statements (C 6.8.1); dispatch is a jump to the matching
label; fallthrough is natural label ordering.

- **Parser** (cparser.inc): C case/default markers now carry ASTSLen=1 (flag
  distinguishing them from a Pascal AN_CASE statement / the Default(T) node).
  ParseCSwitchAST accepts a NON-COMPOUND body (`switch(x) case 0: stmt;`): when the
  token after `)` is not `{`, collect leading markers + the one real statement.
- **IR** (ir.inc): dispatch scan is now RECURSIVE over the whole switch body (any
  depth), assigning each marker an IR_LABEL + emitting the compare, and stopping at
  a nested AN_SWITCH (its cases are its own). The body is lowered by NORMAL
  IRLowerAST (was a bespoke top-level-only walker), and the AN_CASE/AN_DEFAULT arms
  emit IR_LABEL in place for C markers. This is what makes Duff's device work: the
  case labels buried inside the do-while get their IR_LABELs dropped in the loop
  body and dispatch jumps straight in; subsequent iterations run the full body.

**Self-host: one-step BYTE-IDENTICAL — no reseed needed.** The two prior reverts
blamed a codegen-reseed; the real cause was a `{` literal in an added comment
(`{ consume '{' }`) desyncing the nested-comment lexer. Comment reworded; converges
in one step (see [[project_nested_comment_brace_selfhost_landmine]]).

00051 + 00143 green (exit 0). Repro test/cswitch_noncompound_duff_b207.c (exit 42:
non-compound body + fallthrough + Duff's copy). c-conformance 216 pass / 0 fail /
4 skip, quick tier green. Resolves bug-c-switch-nonblock-and-duffs-device.

## Log
- 2026-07-09 — resolved, commit PENDING.
