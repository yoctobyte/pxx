---
slug: bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument
title: "fpRecv/fpSend/fpSendTo/fpRecvFrom accept a flags argument and discard it — MSG_PEEK hangs the caller"
track: B
prio: 55
type: bug
blocked-by: []
status: done
created: 2026-08-31
owner: franks-ab
summary: "FIXED 2026-09-04, and the ticket named HALF the defect. The Pascal arm was as reported -- fpSend/fpRecv/fpSendTo/fpRecvFrom took `flags: cint` and never read it. The SIBLING it did not name is `lib/crtl/src/netinet/in.c`, whose send/recv/sendto/recvfrom said `(void)flags;` for the same reason: the PAL primitives had no flags slot, so both public surfaces dropped the argument. A `flags` parameter (defaulting to 0, so ~90 existing call sites keep their meaning) now runs through platform.pas and all three backends, and the posix backend`s PalBackendRecv moved from read(2) -- which has no flags slot at all -- to recvfrom(2). THE PAL CARRIES ITS OWN FLAG NUMBERS, not Linux`s, because lwIP MSG_PEEK is 1 where Linux`s is 2 and lwIP`s 2 is MSG_WAITALL, which its own header marks Unimplemented: passing Linux numbers to ESP would have reproduced this exact bug on another target with a different cause. Each backend translates and REFUSES a bit it does not carry rather than masking it off. New tests both arms, peek-twice on TCP and UDP, C diffed against glibc on five targets; both positive controls HANG (exit 124 under timeout), so both Makefile rows run under `timeout`."
---

# What was measured

`lib/rtl/sockets.pas` — all four bodies take `flags` and ignore it:

    function fpSend(s: cint; msg: Pointer; len: cint; flags: cint): ssize_t;
    begin Result := SockRetSize(PalSend(s, msg, len)); end;      { flags unread }

Same shape at `fpRecv`, `fpSendTo`, `fpRecvFrom`. `MSG_OOB`/`MSG_PEEK`/
`MSG_NOSIGNAL` are declared at `sockets.pas:108` and no call site can make any of
them take effect.

## Repro — the failure is a HANG

Send 8 bytes, then peek twice on the receiving socket:

    n1 := fpRecv(cli, @r1[0], 8, MSG_PEEK);   { -> 8, bytes correct }
    n2 := fpRecv(cli, @r2[0], 8, MSG_PEEK);   { blocks forever }

`peek1 returned -> 8  first byte 100`, then nothing; `timeout 20` kills it (124).
The first peek consumed the data, so the second waits for bytes that will never
come. A caller doing the standard "peek at the header, then read the whole
message" gets a deadlock, not a wrong value.

## Why it is not fixable at the sockets.pas layer

`PalSend(handle, buf, len)` / `PalRecv` / `PalSendToIpv4` / `PalRecvFromIpv4`
have no flags slot in their signatures. Threading one through means touching
`lib/rtl/platform.pas` plus all three backends
(`platform/{posix,esp,wasi}/platform_backend.pas`) and every caller — coordination
and memory, hence a ticket.

Note the posix send primitives now pass `MSG_NOSIGNAL` unconditionally
(`bug-b-fpsend-to-a-closed-peer-kills-the-process-msg-nosignal-is-never-passed`).
A flags parameter must OR that in rather than replace it, or the SIGPIPE bug
returns for every caller that passes 0 — which is most of them.

## FPC parity

FPC's `Sockets` passes flags straight to the syscall. This is a genuine parity
gap in a unit whose header claims the FPC surface, not a deliberate divergence.

## Resolution (2026-09-04)

### The ticket named one arm of a double case

`lib/rtl/sockets.pas` was reported and was exactly as described. **The sibling
is `lib/crtl/src/netinet/in.c`**, where `send`, `recv`, `sendto` and `recvfrom`
each said `(void)flags;` — the same defect, from the same cause, on the surface
that busybox and every C consumer actually use. Neither could be fixed alone:
both sit on the same PAL primitives, and those had no flags slot.
`devdocs/dev/normalise-dont-special-case.md` is explicit that the arm nobody
fixes is the one that stays broken, so both go through one plumbing change.

### What changed

- **`platform_types.pas`** gains `PAL_MSG_PEEK/OOB/DONTWAIT/WAITALL` and
  `PAL_ERR_INVALID`. They live there rather than in `platform.pas` because a
  flag *number* means nothing unless the facade and every backend agree on it.
- **`platform.pas`**: `flags: Integer = 0` on `PalRecv`, `PalSend`,
  `PalSendToIpv4/6`, `PalRecvFromIpv4/6`. The default is what keeps ~90
  existing call sites meaning what they meant; a second `*WithFlags` entry
  point was the alternative and is the shape that rots.
  It also carries `PalMsgFromPosix`, the Linux→PAL conversion, because **both**
  public surfaces publish Linux's numbers and would otherwise each grow a copy.
- **posix backend**: `PalBackendRecv` moved from `read(2)` to `recvfrom(2)`.
  read has no flags argument, so MSG_PEEK could not have been carried at all —
  the same reason `PalBackendSend` had already moved off `write(2)` to carry
  MSG_NOSIGNAL. MSG_NOSIGNAL is **ORed in, never replaced**: most callers pass
  0, and a flags argument that overwrote it would hand every one of them back
  the SIGPIPE death that
  `bug-b-fpsend-to-a-closed-peer-kills-the-process-msg-nosignal-is-never-passed`
  fixed.
- **esp backend**: translates to lwIP's numbers and refuses OOB and WAITALL.
- **wasi backend**: signature only; it refuses sockets entirely.
- **crtl**: the four wrappers pass `flags` through; `<sys/socket.h>` gains
  `MSG_WAITALL`.

### The finding that changed the design — measured, not reasoned

**Linux and lwIP use the same small bits for different flags.** From
`/home/neo/esp/esp-idf/components/lwip/lwip/src/include/lwip/sockets.h:269-274`,
read on the box:

| | Linux | lwIP |
| --- | --- | --- |
| MSG_PEEK | 2 | **1** |
| MSG_WAITALL | 0x100 | **2** |
| MSG_OOB | 1 | **4** |
| MSG_DONTWAIT | 0x40 | **8** |

So a PAL that passed Linux's flag word through to lwIP would deliver
`MSG_WAITALL` where the caller asked for `MSG_PEEK` — and lwIP's own header
marks WAITALL *"Unimplemented"*, i.e. it would be ignored and the data
consumed. **That is this exact bug, on another target, with a different
cause.** Hence PAL-neutral numbers plus a per-backend translation.

The PAL's values sit at `$00100000`..`$00800000`, a range neither OS uses. Had
they matched Linux's, the posix backend would work *by accident* with the
translation missing, and the mistake would be invisible on the only targets
that run the test.

**An unknown bit is REFUSED, not masked.** Masking is how the original bug
looked like success. `MSG_TRUNC` is declared by both surfaces and carried by no
backend, so a call passing it now answers -1/EINVAL instead of succeeding with
the flag dropped.

### Acceptance, measured

- `test/lib_sock_flags.pas` — 20 rows, fp* surface, TCP peek-twice + UDP
  peek-twice + `MSG_DONTWAIT` on an empty queue + the EINVAL refusal.
- `test/c_crtl_sock_flags.c` — 9 rows, byte-identical to the **gcc oracle's own
  run** on **x86-64, i386, arm32, aarch64 and riscv32**. i386 matters here
  beyond the usual: it reaches the kernel through `socketcall`, so it is a
  second, differently-shaped path to the same syscall.
- **`peek2` is the assertion and `peek1` is not.** A single peek returns 8
  bytes with the right contents whether or not the flag arrived — an ordinary
  recv does exactly that. Only the second peek separates them, which is why the
  ticket's own repro needed two.
- **Both positive controls HANG.** Restoring the dropped flag in `fpRecv`
  alone, and separately in crtl's `recv` alone, each produce exit 124 under
  `timeout 20`, having printed `peek1` and nothing after it. Both Makefile rows
  therefore run under `timeout`: a regression here would otherwise stop the
  build, and a hung build gets read as infrastructure rather than as a test
  saying something.
- Regression: `lib_sockets`, `lib_platform_net`, `lib_platform_net_udp`,
  `lib_sock_closedpeer`, `lib_dns_{resolve,tcp,async,facade}`, `lib_net_v6only`
  unchanged; the C socket tests (`cmsg_and_socket_levels`, `net_headers`,
  `netdb_and_exec`, `netlink`, `rtnetlink`, `inet6`) still byte-identical to
  gcc. All four PAL backends compile (posix on five targets, esp for the IDF
  and non-IDF arms, wasi via wasm32). `make compiler/pascal26` converged;
  `gate.sh quick` GREEN.

### Not done here

`sendmsg`/`recvmsg` pass their flags down to `send`/`recv` and so inherit the
fix, but they still ignore `msg_name` and control data — that is a separate,
pre-existing limitation recorded in their own comment, not part of this ticket.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 38a0992b0.
