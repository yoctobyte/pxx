---
slug: bug-c-toybox-netcat-listen-hangs
track: C
prio: 50
type: bug
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "`netcat -lp 1234 wc -c` with `netcat 127.0.0.1 1234` hangs under the pxx-built toybox (gcc build passes). Not yet diagnosed."
---

# toybox netcat hangs

First step: strace both ends; check poll/shutdown handling in crtl.
