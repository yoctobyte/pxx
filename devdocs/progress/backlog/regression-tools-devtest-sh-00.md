---
prio: 70
track: T
---

> **Track T from the job NAME `tools-devtest-sh`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`none`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest-sh#00 at 24a4733f5bff in step 1/1, `n=0; bad=0; failed=''; \ : > /tmp/tools_devtest_sh_reds.log; \ for f in tools/*devtest*.sh; do \ case "$f" in \ *c_inte…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-11T02:09:28Z
- **Test source:** unknown (see repro commands)
- **Failing step:** line 1 of 1 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  n=0; bad=0; failed=''; \ : > /tmp/tools_devtest_sh_reds.log; \ for f in tools/*devtest*.sh; do \ case "$f" in \ *c_interop_devtest.sh|*tls_openssl_devtest.sh|*tls13_handshake_devtest.sh) continue ;; \ *truststore_devtest.sh|*tls_native_seam_devtest.sh) continue ;; \ esac; \ printf ' tools-devtest-sh
  ```

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest-sh#00'` at 24a4733f5bff72ccd9c98860fd4f179702fe1f7c

## Range
> **The named sha `24a4733f5bff` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `24a4733f5bff`, last good `4c7c88d3614b`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
fatal: unable to auto-detect email address (got 'seven@seven.(none)')
(tail)
lobal user.name "Your Name"

to set your account's default identity.
Omit --global to set the identity only in this repository.

fatal: unable to auto-detect email address (got 'seven@seven.(none)')
  row2 PASS  refused (rc=3), origin unmoved, original body intact
  row3 FAIL  rc=128 body=ORIGINAL BODY — frankH diagnosis, must not vanish
       Preparing worktree (detached HEAD 52918ce)
       Author identity unknown
       
       *** Please tell me who you are.
       
       Run
       
         git config --global user.email "you@example.com"
         git config --global user.name "Your Name"
       
       to set your account's default identity.
       Omit --global to set the identity only in this repository.
       
       fatal: unable to auto-detect email address (got 'seven@seven.(none)')
file_ticket_clobber_devtest: FAILED
  tools-devtest-sh: tools/selfhost_stamp_devtest.sh
  ---- the 1 failing script(s), repeated so the log TAIL names them
  FAIL: tools/file_ticket_clobber_devtest.sh

  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"

to set your account's default identity.
Omit --global to set the identity only in this repository.

fatal: unable to auto-detect email address (got 'seven@seven.(none)')
  row2 PASS  refused (rc=3), origin unmoved, original body intact
  row3 FAIL  rc=128 body=ORIGINAL BODY — frankH diagnosis, must not vanish
       Preparing worktree (detached HEAD 52918ce)
       Author identity unknown
       
       *** Please tell me who you are.
       
       Run
       
         git config --global user.email "you@example.com"
         git config --global user.name "Your Name"
       
       to set your account's default identity.
       Omit --global to set the identity only in this repository.
       
       fatal: unable to auto-detect email address (got 'seven@seven.(none)')
file_ticket_clobber_devtest: FAILED
  tools-devtest-sh: 2 green, 1 RED -- tools/file_ticket_clobber_devtest.sh

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
