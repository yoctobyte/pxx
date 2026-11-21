---
slug: bug-c-toybox-netcat-listen-hangs
track: C
prio: 50
type: bug
status: done
owner: "claude-pxx"
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "DOES NOT REPRODUCE 2026-11-21: the 2026-11-15 pxx toybox passes toybox's own netcat test in its full-suite run, and 5 of 5 by hand (4098 bytes, rc 0, no hang); the gcc build agrees. Originally: `netcat -lp 1234 wc -c` with `netcat 127.0.0.1 1234` hangs under the pxx-built toybox (gcc build passes). Not yet diagnosed."
---

# toybox netcat hangs

First step: strace both ends; check poll/shutdown handling in crtl.

## 2026-11-21 (claude-pxx): does not reproduce

- toybox's own `tests/netcat.test` (`netcat -lp 1234 wc -c & sleep .1 && cat
  testfile | netcat 127.0.0.1 1234`, 4098 bytes expected) PASSES in the full
  suite run on the pxx build of 2026-11-15 (`~/toybox-wip/build/new.testlog`,
  "PASS: netcat more than buffer bytes left at end"), the same line as the gcc
  reference log.
- By hand, on localhost with that binary: the exact test 5 of 5, 4098 and
  rc 0, and the summary's `netcat -lp N wc -c` / `echo hello | netcat
  127.0.0.1 N` pair answers 6 for both pxx and gcc builds.
- The 11-14 partial suite log (`tpxx.testlog.partial`) ends at chmod, before
  netcat, so it does not show the hang either. The likeliest reading is that
  one of the 11-14/11-15 crtl fixes in the toybox batch removed it; which one
  was not bisected, and that is not worth doing for a hang that no longer
  happens.

Not measured: a toybox built by today's pxx. The remaining suite failures are
bug-c-toybox-test-suite-failures (netcat is not among them).
