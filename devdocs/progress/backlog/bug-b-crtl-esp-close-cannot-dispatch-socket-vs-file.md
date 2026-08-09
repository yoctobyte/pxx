---
summary: "On ESP-IDF, close() cannot serve both file and socket fds — PalClose is fclose(ptr), PalSocketClose is lwip_close. crtl now has one close() (the file one), so socket close is wrong there"
type: bug
track: B
prio: 30
---

# crtl `close()` cannot dispatch socket vs file on ESP

- **Type:** bug — Track B (`lib/crtl`), tagged S (ESP)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** the C duplicate-definition warning
  ([[bug-c-string-h-compiles-stdlib-c-twice]]).

## What was fixed already

`lib/crtl/src/netinet/in.c` defined a **second** `int close(int fd)` that routed
through `__pxx_socket_close`, on top of `lib/crtl/src/unistd.c`'s file `close`.
Any TU that pulled both (any program doing sockets *and* file I/O — e.g.
`test/cerrno_strings.c`) sent **every** close through whichever module was
pulled last. The duplicate was removed; `unistd.c` is now the single `close`.

On POSIX that is provably a no-op: `PalBackendSocketClose` calls
`PalBackendClose` (`lib/rtl/platform/posix/platform_backend.pas:847`), both are
`SYS_close`, and the errno handling is identical (`__crtl_sock_fail` sets
`errno = -rc; return -1`, same as unistd's `close`).

## What remains

On **ESP-IDF** the two PAL entries are genuinely different code:

| | `lib/rtl/platform/esp/platform_backend.pas` |
| --- | --- |
| `PalBackendClose` | `fclose(Pointer(handle))` (a FILE\* cast) |
| `PalBackendSocketClose` | `lwip_close(handle)` (an lwip fd) |

One `close(int fd)` body cannot serve both, because crtl has no way to tell a
FILE\*-derived handle from an lwip fd. Before the dedup this was *already* broken
— just broken in whichever direction the pull order happened to pick, silently.
Now it is deterministically the file one, so C socket close on ESP-IDF calls
`fclose` on an lwip fd.

Note the C socket path on ESP is not a working configuration today anyway (see
the 33 refused PAL entry points in `CLAUDE.md`'s Track S note); this ticket is
about not leaving the hazard undocumented.

## Options

1. **fd registry in crtl** — `socket()` records the fd in a small table,
   `close()` consults it and picks the PAL entry. Self-contained in `lib/crtl`;
   costs a table and is wrong across `dup`/inherited fds.
2. **Unify in the PAL** — make ESP's `PalBackendClose` recognise a socket handle
   (lwip fds and IDF `FILE*` values are distinguishable in practice) and
   dispatch there. Track A/S change, but then every language gets it right, not
   just C.

Option 2 is the recommendation — it puts the knowledge where the handle
namespace is actually owned. Confirm the two handle spaces really are
distinguishable on IDF before committing to it.

## Gate

A C program that opens a file and a socket and closes both behaves correctly on
POSIX (already true) and on ESP-IDF; `test/cerrno_strings.c` stays silent.

## 2026-08-09 (Track B): hazard defanged; the dispatch itself still needs hardware

**Not fixed as written, and deliberately so.** The ticket's own precondition for
option 2 is *"confirm the two handle spaces really are distinguishable on IDF
before committing to it"*, and that cannot be confirmed here — there is no ESP32
on this box. Reasoning from the ESP32 address map (a `FILE*` lands in DRAM
around `0x3F…`, an lwip fd is a small VFS integer) is exactly the kind of
plausible-sounding inference this repo's debugging playbook says not to write
into code.

Option 1 (an fd registry in crtl) was also rejected on inspection: `poll()`
hands `PalPollSet` the caller's `struct pollfd` array untouched, straight to
`lwip_poll`, so any tagging or remapping of fd values has to be undone there
too — the registry is not self-contained the way the ticket assumed.

**What DID change** — `PalBackendClose` on IDF used to `fclose(Pointer(handle))`
anything above `PAL_STDERR`, so reaching it with an lwip fd dereferenced a
null-page address: undefined behaviour from a call that looks fine. It now
refuses a handle below 4096 with `PAL_ERR_UNSUPPORTED`.

That is not a guess about WHICH space a handle belongs to — it is the fact that
no platform puts a valid pointer in the first page. So the outcome for a C
socket close on ESP-IDF becomes the deliberate Track S refusal
(`PAL_ERR_UNSUPPORTED`, like the other 33 entry points) rather than memory
corruption. The bug the ticket describes is still open; its worst consequence is
not.

**Still to do, and it needs a device:** confirm the handle spaces are separable
on real IDF, then implement option 2 in the PAL so every language gets it right,
remembering the `PalPollSet` pass-through above.

