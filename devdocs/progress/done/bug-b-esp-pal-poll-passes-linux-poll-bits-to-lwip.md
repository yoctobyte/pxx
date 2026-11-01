---
slug: bug-b-esp-pal-poll-passes-linux-poll-bits-to-lwip
title: "ESP PAL: PalPoll/PalPollSet hand Linux poll bits to lwip_poll, whose POLLOUT/ERR/HUP/NVAL differ — POLLOUT never fires, POLLERR reads back as POLLOUT"
track: B
prio: 55
type: bug
blocked-by: []
status: done
summary: "lib/rtl/platform/esp/platform_backend.pas PalBackendPoll passes `events` straight to lwip_poll and returns revents untranslated. PAL_POLL_* are Linux values (IN 1, OUT 4, ERR 8, HUP $10, NVAL $20); lwIP's sockets.h has IN 1, OUT 2, ERR 4, NVAL 8, HUP $200. Only POLLIN coincides, which is why the UDP net-c3 smoke passes. Measured 2026-09-30 under Espressif QEMU (esp32c3): PalPoll(connected TCP socket, PAL_POLL_OUT, 2000) returns 0 every time."
---

# ESP PAL poll: Linux poll bits sent to lwIP

- **Type:** bug — **Track B**, tag **S** (`lib/rtl/platform/esp/platform_backend.pas`).
- **Filed:** 2026-09-30 from `~/museum_landkaart` (ESP32-C3 LED controller whose
  HTTP server runs on the PAL). Found by an on-target self-test under QEMU.

## Evidence

| bit | PAL / Linux | lwIP (`components/lwip/lwip/src/include/lwip/sockets.h:504-514`) |
| --- | --- | --- |
| POLLIN | `$001` | `0x1` |
| POLLOUT | `$004` | `0x2` |
| POLLERR | `$008` | `0x4` |
| POLLNVAL | `$020` | `0x8` |
| POLLHUP | `$010` | `0x200` |

`PalBackendPoll` (≈ line 840) does `pfd[1] := events and $FFFF; lwip_poll(...)`
and returns `(pfd[1] shr 16) and $FFFF` raw. So:

- asking for `PAL_POLL_OUT` asks lwIP for POLLERR: a connected socket never
  reports writable (measured: `PalPoll(c, PAL_POLL_OUT, 2000) = 0` after a
  successful loopback `connect`);
- an lwIP POLLERR (`4`) comes back as `PAL_POLL_OUT`, i.e. a failed socket
  looks writable;
- POLLHUP `$200` is outside every PAL mask.

`PalBackendPollSet` has the same issue: it passes the caller's `pollfd` array
through unchanged. The existing comment says the layouts match, and the struct
layout does; the bit values don't.

## Fix

Translate in both directions in the ESP backend: PAL→lwIP on `events`,
lwIP→PAL on `revents` (and in PollSet, translate per entry before and after).
Positive control: the net-c3 smoke plus a TCP connect + `PAL_POLL_OUT` check,
which fails today.

## Resolution (2026-11-01)

Fixed already, in 3aeb046212 (2026-09-25, measured on an S3). That fix predates
this ticket, which was filed against v398 and never committed. **The table
above is the wrong one to copy.** It is vanilla lwIP's numbering, but IDF builds
lwIP against esp_libc's <sys/poll.h> (lwipopts.h includes it first, so
sockets.h's own block is skipped): IN 1, OUT 8, ERR $20, HUP $40, NVAL $80. The
backend translates to those values, and OUT 2 would have been RDNORM.

What was missing was the acceptance check. examples/esp32/net-c3 now also
connects a loopback TCP socket and requires PalPoll(c, PAL_POLL_OUT, 2000) to
report PAL_POLL_OUT (status bit 128). The test-esp-idf row already requires
`PXX-net-smoke status=0`. QEMU esp32c3: `tcp-poll-out=4`, status 0. Control,
with the translation removed from PalBackendPoll: `tcp-poll-out=0`, status 128.
