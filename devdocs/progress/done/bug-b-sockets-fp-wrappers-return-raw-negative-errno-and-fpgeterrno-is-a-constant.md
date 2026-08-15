---
track: B
prio: 55
type: bug
blocked-by: []
status: done
owner: track-b-bughunt
summary: "lib/rtl/sockets.pas returns the PAL's raw negative errno (-111, -22) from every fp* wrapper where FPC returns -1, and fpGetErrno is a hardcoded `Result := 5 { EIO }`. So `if r = -1` — the FPC/Synapse idiom, and what SOCKET_ERROR compares to — never fires on a failure, and any code that then reads errno gets EIO for every cause. Reduced to two lines; found while re-measuring the dynlib ticket's Synapse item."
---

# `sockets`: `fp*` return raw `-errno`, and `fpGetErrno` always says 5

- **Type:** bug (silent wrong value) — **Track B** (`lib/rtl/sockets.pas`).
- Found 2026-08-15 while re-measuring [[feature-real-dynlib-loader]]'s item (d).
  The Synapse SSL path was blamed on the loader; it is not the loader, and it is
  not SSL — a **plain TCP connect** through Synapse fails the same way.

## Measured, pxx vs FPC 3.2.2, same source

```pascal
fd := fpSocket(AF_INET, SOCK_STREAM, 0);
a.sin_family := AF_INET; a.sin_port := htons(1);
a.sin_addr.s_addr := htonl($7F000001);        { nothing listening }
r := fpConnect(fd, @a, SizeOf(a));
writeln('connect r=', r, ' errno=', fpGetErrno);
r := fpSocket(-1, -1, -1);
writeln('badsocket r=', r, ' errno=', fpGetErrno);
```

| | pxx | FPC |
| --- | --- | --- |
| failing `fpConnect` | `r=-111  errno=5` | `r=-1  errno=111` |
| `fpSocket(-1,-1,-1)` | `r=-22  errno=5` | `r=-1  errno=22` |
| failing `fpRead` | *(not declared)* | `r=-1  errno=9` |

`strace` confirms the syscalls themselves are right — `socket(AF_INET,
SOCK_STREAM, IPPROTO_TCP) = 3`, `connect(...) = -1 EINPROGRESS`. Nothing is
wrong below this unit; the FPC-surface **convention** is wrong in it.

## Why this is the expensive kind of bug

`-111` is not `-1`, so

```pascal
if SockResult = integer(SOCKET_ERROR) then   { Synapse's SockCheck }
```

**does not fire**, and a failed call is read as a success. The value looks
plausible (it is negative, it even encodes the right cause) which is exactly why
it survives review. Where an error IS noticed, `fpGetErrno` hands back `5` for
every cause, so the diagnosis is wrong too: EIO for a connection refused, EIO
for an invalid argument.

Concretely, `TTCPBlockSocket.Connect` with `ConnectionTimeout > 0` — Synapse's
non-blocking connect path, which is what every real client sets — reports
`LastError=5 "Other Winsock error (5)"` against a server that is up and
accepting. Without the timeout it works, because that path never consults
errno. That is the shape the dynlib ticket's item (d) has been stuck behind.

## The cause, and it is documented in the source

```pascal
function fpGetErrno: cint;
begin
  { PAL primitives return negative on error rather than setting a global errno;
    we have no thread-global errno, so report a generic failure. Callers that
    only test "<> 0" (Synapse) are satisfied. }
  Result := 5; { EIO }
end;
```

The comment states the assumption and the assumption is false: Synapse tests
`= SOCKET_ERROR`, not `<> 0`. Every `fp*` body is `Result := cint(PalXxx(...))`,
passing the PAL's `-errno` straight through.

## Fix

Give the unit the FPC contract it advertises:

1. A per-thread errno slot. There is no `threadvar` in this dialect, but the
   established pattern is a tid-keyed table (`lib/rtl/scheduler.pas`'s `CurR`,
   over `PalThreadSelf`). Errno **must** be per-thread — a global would be a
   different silent wrong answer under the thread pool.
2. One helper every wrapper routes through: negative PAL result -> store
   `-r` in the slot, return `-1`; otherwise return the value unchanged.
3. `fpGetErrno` reads the slot. Do **not** clear it on success — FPC's errno is
   only meaningful after a failure, and clearing it would diverge.

`< 0` checks keep working (they always did), `= -1` checks start working, so the
change is compatible with everything in the tree: nothing in `lib/**` calls
these wrappers at all — they exist as the FPC-compat surface for Synapse and
user code, which is why this went unnoticed.

## Gate

The table above matches FPC on every row, `test/lib_sockets.pas` extended with
the failure rows (an errno is only observable when a call FAILS, and the
existing test only exercises success), and `make lib-test` green.

## Resolution (2026-08-15)

Fixed in `lib/rtl/sockets.pas`, gated green, with the failure rows the surface
never had.

- **Per-thread errno slot**, tid-keyed, the shape `lib/rtl/scheduler.pas`
  already uses for its reactors: lock-free scan on the fast path, a CAS
  spinlock only when a thread first claims a slot. gettid is **inlined** rather
  than taken from `palthread` — depending on the thread unit drags in
  `__pxxclone` and would force every single-threaded program that opens a
  socket onto the `--threadsafe` runtime. `scheduler.pas` documents that exact
  trap at its own copy; this is the second instance, not a new idea.
- **One helper (`SockRet`/`SockRetSize`) that every wrapper routes through**:
  a negative PAL result records `-r` and returns `-1`, anything else passes
  through untouched. Twelve wrappers, one rule — the alternative was twelve
  places to get it wrong later.
- **errno is not cleared on success**, matching FPC, and `lib_sockets` pins
  that with `errno-survives-success`.

Both rows of the table above now match FPC exactly (`-1`/111 and `-1`/22).

### It moved the ticket it was found under

With the fix, Synapse's `TTCPBlockSocket.Connect` returns 0 against a loopback
`openssl s_server` where it had reported `LastError=5` — so
[[feature-real-dynlib-loader]] item (d) is past the wall it has been on since
2026-07-31. It now segfaults further in, inside the handshake; that is a
separate finding and does not belong to this ticket.

### Note for whoever extends `test/lib_sockets.pas`

It does **not** compile under FPC (it wants `cint`, `INADDR_LOOPBACK` and
friends from `baseunix`, which it never uses) — pre-existing, and worth knowing
before someone writes a comment claiming FPC-parity by construction. The errno
values it asserts were read off a separate FPC 3.2.2 build of the same three
calls instead.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
