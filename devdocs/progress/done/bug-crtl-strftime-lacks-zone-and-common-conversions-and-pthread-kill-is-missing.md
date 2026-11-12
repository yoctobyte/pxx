---
track: B
tags: [C, crtl]
prio: 40
type: bug
blocked-by: []
summary: "crtl's strftime was the subset Lua's os.date emits, so busybox `date` printed a literal \"%Z\". It now has %Z %z %T %D %F %R %r %c %x %X %C %u %U %W %k %l %P %n %t %s as glibc writes them, and %e is space-padded. pthread_kill was missing under --threadsafe; a pxx pthread_t is the kernel tid, so it is tgkill(getpid(), tid, sig). Both came from the Gibux peer's userland. Also: busybox_diff turns on FEATURE_STAT_FORMAT with `stat` (stat -c) and has an opt-in --usage for applet usage text."
status: done
owner: unassigned
---

# strftime lacks the zone and common conversions; pthread_kill is missing

Both requests came from the Gibux peer's userland work.

## strftime (lib/crtl/src/time.c)

- **%Z and %z** read `tm_zone` and `tm_gmtoff` from the struct tm, as glibc
  does. gmtime and localtime fill both.
- **Shorthand conversions** (%T %D %F %R %r %c %x %X) expand through
  strftime into a scratch buffer, so the C99 overflow rule (return 0) holds
  for them too.
- **Space padding:** %e %k %l pad with a space. %e used to print an unpadded
  "3" where glibc prints " 3".
- **%s** is mktime() of the fields. glibc does not adjust it by tm_gmtoff and
  uses the local zone, and crtl's local zone is UTC, so the oracle runs under
  TZ=UTC.

## pthread_kill (lib/crtl/src/signal.c, declared in signal.h)

`tgkill(getpid(), thread, sig)`. It returns the error number, as the pthread_*
calls do. compiler/crtl_names.inc is regenerated (639 functions).

## busybox_diff

- FEATURE_STAT_FORMAT comes on with `stat`.
- `--usage` turns on SHOW_USAGE and FEATURE_VERBOSE_USAGE. A refused
  invocation (switch_root's "NEW_ROOT must be a mountpoint") otherwise exits 1
  without a word. It is opt-in, because it costs size.

## Test

test/c_crtl_strftime_zone_and_pthread_kill.c (--threadsafe) covers every new
conversion on gmtime and on a hand-set CEST struct, truncation, and
pthread_kill with signal 0, SIGUSR1 and a bad signal. Its output matches gcc
under TZ=UTC. The d9a0d9a599 compiler refuses it: "call to undeclared
function: pthread_kill".
