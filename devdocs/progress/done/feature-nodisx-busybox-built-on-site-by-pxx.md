---
title: Nodisx -- pixix's busybox built on site by pxx; its testsuite equal to gcc's; Rainyday boots with it
status: done
owner: claude-dupwt
prio: 60
area: nodisx
---

Umbrella item 5 (umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx).

tools/nodisx/busybox has record, onsite and test scripts, plus
pixix.config, which is the `.config` busybox-pxx2829 carries (`busybox
bbconfig`).
- On site: 542 units, 523 linked, 396 applets, ~8 min at JOBS=8.
- busybox's own testsuite: pxx 763 PASS / 6 FAIL, gcc 763 / 6; the
  failures are the same ones.
- Rainyday (pxx kernel) boots with it as userland and the on-site rumpnic:
  udhcpc, ip, ping, wget and md5sum PASS.

The first testsuite run had 14 pxx-only failures. They were three crtl
bugs, all fixed:
- bug-c-crtl-getopt-takes-the-next-word-as-an-optional-argument (sed -i
  x7, xargs -e)
- bug-c-crtl-localtime-ignores-a-posix-tz-rule-string (date -@)
- bug-c-crtl-getaddrinfo-resolves-no-names (hostname -d/-i, wget x4)
