---
track: B
prio: 55
type: feature
blocked-by: []
summary: "Make lib/rtl/textfile.pas's read buffer caller-supplyable and add write buffering, so SetTextBuf can exist with FPC's exact semantics. The read buffer already exists (4096 bytes, inline in the Text record); the only structural blocker is that it is an inline array where FPC has a pointer, so SetTextBuf cannot point it at the caller's memory. Write side buffers under C99 7.19.3p7's policy, NOT FPC's — measured: FPC's destroys stdout/stderr ordering whenever stdout is not a tty. DO NOT LAND THE WRITE SIDE ALONE: this is one half of an interlock with feature-c-crtl-stdio-buffering-and-setvbuf, and the two share a flush registry. Ordering between Pascal WriteLn and C printf is correct TODAY only because both sides are unbuffered; buffering either side by itself reorders output inside a single program that mixes them, which is the case pxx exists to support. crtl's setvbuf is also a stub that ignores its arguments and returns SUCCESS -- worse in C than a missing SetTextBuf is in Pascal, because C callers check the return, so it turns a missing feature into a wrong answer. The READ side (BufPtr/BufSize + SetTextBuf) is self-contained and may land on its own."
status: working
owner: franks-ab
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

## 2026-09-04 — READ SIDE LANDED. Write side and the registry are still open.

`Text` now carries `BufPtr: PByte` / `BufSize: Integer` / `BufForced: Boolean`
over an inline `DefBuf`, and `SetTextBuf` exists. The write side, the C99
buffering policy and the flush registry are **not** in this change and the
ticket stays open for them.

### What the read side does, and where it deliberately differs

- `Assign` resets `BufPtr` to the record's own buffer, **as FPC's does** — which
  is why the documented order is `Assign; SetTextBuf; Reset`. Copying the order
  matters more than it looks: a caller that gets it backwards reads with the
  default buffer under FPC, and if we kept the pointer here the same program
  would behave *differently* on pxx while looking correct on both.
- `TFEnsureBuf` points a nil `BufPtr` at `DefBuf` on every read path. `var f:
  Text` is legal to declare and a caller who forgets `Assign` hands us a
  zero-initialised record; dereferencing nil there would turn a diagnosable
  "file not open" into a segfault.
- **The divergence the ruling asked for:** `BufForced` lets an explicit
  `SetTextBuf` turn read-ahead on for a non-seekable handle, which `TFOpened`'s
  default still refuses. It is a separate field from `Buffered` because the two
  answer different questions — "did the caller ask us to" versus "are we reading
  ahead right now" — and folding them would leave `TFOpened` unable to tell a
  caller's instruction from its own last verdict.

### Acceptance — byte-identical to FPC 3.2.2's own run

`test/lib_settextbuf.pas`, seven rows, compared against the **oracle's output**
rather than literals, because the read-ahead positions are FPC's contract and
hardcoding them would be the test asserting our implementation back at itself:

```
small-line=line1....   small-pos=16
big-line=line1....     big-pos=100
count=20 last=line20...
midstream-first=line1....   midstream-next=line11...
```

**THE POSITION IS THE INSTRUMENT AND THE TEXT IS NOT.** A reader using the
default buffer returns exactly the same lines, so a content-only test passes
against a `SetTextBuf` that does nothing at all. The two sizes are 16 and 100 —
neither is `TF_BUFSIZE` (4096) nor FPC's default (256) — so no row can be
satisfied by a default value. `midstream-next=line11` is the discarded-bytes
contract, measured under FPC and copied on purpose.

**The positive control is a SEGFAULT, not a mismatch.** With the read size taken
from `TF_BUFSIZE` again instead of from `f.BufSize`, and nothing else changed,
`PalRead` writes 4096 bytes into the caller's 16-byte array and the binary dies.
So "ignoring the size" is not a benign no-op here — it is a stack smash, which
is a stronger reason to honour `BufSize` than parity is.

`make compiler/pascal26` converged (the compiler reads its own sources through
this record, so the fixedpoint is a real consumer of the change).

### Still to do — and the interlock

Write buffering, the C99 §7.19.3p7 policy, a real `Flush`, and the flush
registry shared with `feature-c-crtl-stdio-buffering-and-setvbuf`.
**Do not land the write side alone.** `Flush`'s comment at `textfile.pas` and
the interface comment above it both still say writes are unbuffered; they are
true today and must be rewritten in the same commit that stops being true.
