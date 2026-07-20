---
track: A
prio: 45
type: bug
---

# `test-core` token-growth job takes 77s and gets killed under load

Observed 2026-07-20 running `make test` natively; the same job is what borg's
20260720T091031Z report attributed a NEW-RED to
(`test-core#src:test/test_interface_mainbody_ascast_temp.pas`, log ending in a
bare `Terminated` right after `test_ast_overflow_large26`). That RED is a
TIMEOUT of the following job, not the named test — that test passes on its own,
here and at that SHA.

## Numbers

`/tmp/test_token_growth.pas` (12000 empty procs, ~72k tokens; Makefile:955):

| compiler | wall |
| --- | --- |
| `stable_linux_amd64/default/pinned` | 51.5s |
| HEAD (2026-07-20) | 77.5s |

Both are slow for 12000 empty procedures, and HEAD is ~1.5x the pinned build,
so something between the pin and HEAD made it worse on top of an already-poor
baseline. A 12000-proc file is ~72k tokens — self-host lexes ~1M per build in
far less time, so this is not lexing.

## Suspicion

A per-proc O(n) scan turning the whole file into O(n²) — the shape
`project_pxx_string_concat_in_loop_is_quadratic` warns about. Find it by SCALING
CURVE (3000 / 6000 / 12000 / 24000 procs, pinned vs HEAD), not by reading code.

## Why it matters beyond speed

At this duration the job is a coin flip against the harness timeout on a loaded
box, and when it loses, the report blames whichever test the log stopped near —
so a slow job manufactures phantom REDs in tstate. Track T sees the symptom;
the cause is here.

## Gate

Scaling curve recorded before/after, `make test` green, self-host byte-identical.

## Log

- 2026-07-20 — measured the RSS, and TIME is the smaller half: the compile of
  `/tmp/test_token_growth.pas` (12000 empty procs) climbs past **2.2 GB RSS**
  and is then SIGTERMed under memory pressure, which is what "Terminated"
  in the log means — not a timeout. Standalone on an idle box it completes in
  77s; concurrently with Track T's own testmgr run it dies. So the phantom
  NEW-REDs appear exactly when two runs overlap.
- That reframes the fix: a per-proc allocation that never shrinks (~180 KB per
  EMPTY procedure) rather than only a quadratic scan. Look at what is reserved
  per Proc entry and whether the per-body arrays are sized per procedure.
