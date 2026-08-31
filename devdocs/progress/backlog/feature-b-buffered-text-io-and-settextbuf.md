---
track: B
prio: 55
type: feature
blocked-by: []
summary: "Make lib/rtl/textfile.pas's read buffer caller-supplyable and add write buffering, so SetTextBuf can exist with FPC's exact semantics. The read buffer already exists (4096 bytes, inline in the Text record); the only structural blocker is that it is an inline array where FPC has a pointer, so SetTextBuf cannot point it at the caller's memory. Write side buffers under C99 7.19.3p7's policy, NOT FPC's — measured: FPC's destroys stdout/stderr ordering whenever stdout is not a tty."
---

# Buffered Text I/O and `SetTextBuf`

Implements the ruling in
`decided/decide-settextbuf-needs-buffered-text-io-or-stays-missing.md`. Read
that for the measurements; this is the work list.

## Read side

`Text` today ends in an inline array:

```pascal
Buffered: Boolean; BufPos: Integer; BufLen: Integer;
Buf: array[0..TF_BUFSIZE - 1] of Byte;    { TF_BUFSIZE = 4096 }
```

Change to `BufPtr: PByte; BufSize: Integer`, plus a default inline array that
`BufPtr` points at on `Assign`, so the common case still allocates nothing and
the record stays self-contained. Then `SetTextBuf` is FPC's four assignments:
set pointer, set size, zero `BufPos`, zero `BufLen`.

Match FPC exactly on all three observable side effects — they are the contract,
not accidents:

1. Read-ahead leaves the fd ahead of the logical position. Do not seek back.
2. Mid-stream `SetTextBuf` discards pending buffered bytes. No copy, no reseek.
3. The buffer is caller-owned and retained. Do not copy it, do not track it.

**One deliberate divergence, ruled:** keep the existing guard

```pascal
f.Buffered := (f.Handle >= 0) and (PalSeek(f.Handle, 0, PAL_SEEK_CUR) >= 0);
```

as the *default* — we do not read ahead on pipes and terminals, where the
position is unrecoverable and FPC gets it wrong — but let an explicit
`SetTextBuf` override it. A caller naming a buffer is a different signal from us
choosing to buffer.

## Write side

Writes go straight to the fd today (`PalWrite` per `Write`). Add buffering under
**C99 §7.19.3p7's policy, not FPC's**: stderr not fully buffered; stdout
line-buffered when it refers to an interactive device; fully buffered otherwise.
Flush on `Close` and on normal *and* abnormal exit — FPC's runtime-error path
flushes and ours must too (measured: FPC's segfault run exited 216 with all
output intact).

`Flush` becomes real; its comment at `lib/rtl/textfile.pas:143` ("PXX text
writes go straight to the fd (no RTL-side buffer), so Flush only…") must be
rewritten in the same commit.

## Cross-RTL ordering

Coordinate with `feature-c-crtl-stdio-buffering-and-setvbuf`: both sides
register a flusher per destination, and each flushes any *other* dirty
registered buffer for that destination before writing into its own. Neither RTL
names the other. **Do not land write buffering on only one side** — that is the
one combination that reorders output in a program that mixes `WriteLn` and
`printf`, which is exactly what pxx exists to link together.

## Gate

`make lib-test`. Carry a repro that writes to stdout and stderr with stdout on a
pipe and asserts the interleaving is preserved — that is the property FPC fails
and the whole reason for the policy divergence, and no existing test covers it.
