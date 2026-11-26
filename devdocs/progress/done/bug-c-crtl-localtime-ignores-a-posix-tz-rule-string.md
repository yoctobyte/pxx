---
title: "crtl localtime ignored a POSIX TZ rule string ($TZ=EET-2EEST,M3.5.0/3,M10.5.0/4 read as UTC)"
status: done
owner: claude-dupwt
prio: 55
area: crtl
---

busybox's date-@-works test sets TZ=EET-2EEST,M3.5.0/3,M10.5.0/4; the
pxx busybox printed UTC. crtl read only TZif files (from $TZ or
/etc/localtime). A TZ naming no file was UTC. Its comment refused rule
strings because parsing only the offset would be wrong half the year. A
system without a zoneinfo database (Rainyday, the Nodisx installer) can
only be configured with a rule string.

lib/crtl/src/time.c now evaluates the whole rule when $TZ names no readable
file:
- std offset [dst [offset] [,start[/time],end[/time]]], with <quoted>
  names and Mm.w.d, Jn and n dates;
- glibc's default M3.2.0,M11.1.0 when a DST name has no rule;
- southern-hemisphere wraparound.
tzset publishes tzname, timezone and daylight from it. A string that does
not parse is UTC, as before.

Checked against glibc over 8 zones x 8 instants: identical after 1970.
Before 1970 glibc's answers are inverted for every zone tried (it reports
standard time in an EET summer of 1938 and DST in an AEST winter); crtl
keeps the rule's answer. Test row c_optzhost26 (post-1970 instants).
