---
track: C
prio: 55
type: feature
blocked-by: []
summary: "STATE 2026-09-24 (frankS): the SILENT-WRONG half is FIXED. setvbuf no longer claims success for a request it ignored: _IONBF returns 0 (every crtl stream really is unbuffered), _IOFBF/_IOLBF and invalid modes return nonzero (C99 7.19.5.6 allows failure), and the caller's buffer is never retained. Guard: test/c_crtl_setvbuf_is_honest.c. Every corpus caller (busybox tee, match, svlogd, mpstat, fsck, od) ignores the return, so nothing that compiles changes behaviour. WHAT REMAINS is performance, not correctness: crtl stdio does one write() per character in putchar/fputc loops. The measured blocker, from the sibling ticket's 2026-09-04 section: Pascal writeln is EMITTED inline by every backend (IR_WRITE/IR_WRITELN), never through lib/rtl, so buffering crtl alone would let a mixed program's writeln overtake its buffered printf, and there is no Pascal call site to flush from. NEXT STEP: route IR_WRITE through a runtime helper that can consult a flush registry (Track A, compiler/ir_codegen*.inc), or buffer only streams that are not stdout/stderr (FILEs from fopen), which cannot interleave with writeln. Measure the putchar-loop win first; it has never been measured.""
status: unfinished
owner: 
---

# Buffered `FILE` writes, a real `setvbuf`, and the flush registry

Implements the C half of
`decided/decide-settextbuf-needs-buffered-text-io-or-stays-missing.md`.

## The two defects

**Unbuffered.** Every write path calls `__pxx_write` directly:

```c
int fputc(int c, FILE *stream) {
  char ch = (char)c;
  if (__pxx_write(stream->fd, &ch, 1) < 0) { stream->err = 1; return -1; }
```

One syscall per character for any `putchar`/`fputc` loop. `fwrite` and `fputs`
pass whole buffers through, so the exposure is loop-shaped code rather than
`printf`-shaped — **the win is unmeasured; measure it before pricing this
higher.**

**A lying stub.** `lib/crtl/src/stdio.c:1051`:

```c
int setvbuf(FILE *stream, char *buf, int mode, size_t size) { (void)stream; (void)buf; (void)mode; (void)size; return 0; }
```

Accepts a caller-supplied buffer, ignores it, reports success. A C caller that
checks the return is told its buffer was adopted when it was not — the lifetime
lie the `SetTextBuf` ruling rejected, already shipped here with the opposite
answer.

## The work

- Give `struct PxxCrtlFile` a buffer (pointer + size + position, so `setvbuf`
  can point it at caller memory), and route `fputc`/`putc`/`putchar`/`fputs`/
  `fwrite`/`printf` through it.
- Buffering policy is C99 §7.19.3p7 and it is normative, not a preference:
  stderr not fully buffered; stdout line-buffered when it refers to an
  interactive device; fully buffered otherwise.
- `setvbuf` honours `_IOFBF`/`_IOLBF`/`_IONBF` and the caller's buffer, and
  returns nonzero when it cannot. `setbuf` follows from it.
- Flush on `fclose`, on `exit`, and on the abnormal-exit path.

## The flush registry — do not skip this half

Today ordering between Pascal `WriteLn` and C `printf` is correct *only*
because both sides are unbuffered. Buffering either side alone reorders output
inside a single program. Register a flusher per destination; before writing into
your own buffer, flush any other registered dirty buffer for that destination.
O(N) in live streams, no direct reference between `lib/crtl` and `lib/rtl`, and
a null check when only one is linked.

With the C policy above, the registry only has to handle the **same-fd** case;
two descriptors onto one terminal would need `fstat` plus `st_dev`/`st_ino`
comparison and the policy removes the need.

Land in step with `feature-b-buffered-text-io-and-settextbuf`.

## Gate

C tests + self-host + cross. Add a mixed-frontend repro: a Pascal `WriteLn` and
a C `printf` alternating into a pipe, asserting order. Nothing covers that
today, and it is the property this pair of tickets can break.

## RELEASE-RISK: SILENT-WRONG

The program compiles, runs, and is WRONG with no diagnostic — so a user cannot
discover it from a message and cannot work around what they cannot see. Marked
2026-09-06 for the beta 0.1 release sweep; a beta may ship known REFUSALS, but
an unenumerated silent-wrong is the class it must not ship.

The SILENT-WRONG half is `setvbuf`, not the missing buffering: `lib/crtl/src/stdio.c` defines it as `{ (void)stream; (void)buf; (void)mode; (void)size; return 0; }` -- it discards every argument and returns 0, which C99 7.19.5.6 defines as SUCCESS. A caller that correctly checks the return is told its buffering request was honoured when nothing happened. Unbuffered output on its own is slow, not wrong; a stub that reports success is the dishonest-stub shape.

## 2026-09-24 (frankS): setvbuf made honest; buffering left, with the reason

Found in working/ held by franks-ab, an earlier incarnation of this checkout's
seat; last touched 2026-09-06. working/ is excluded from every ranked queue, so
it had been invisible for 18 days. Parked back to the backlog with this state.

setvbuf, new behaviour (lib/crtl/src/stdio.c): `_IONBF` gives 0, `_IOFBF`,
`_IOLBF` and invalid modes give -1. Control: with the old stdio.c the fixture
differs. The expected values are crtl's, not gcc's, because glibc buffers and
answers 0 to every valid mode. That is the honest divergence.

The buffering half is NOT done. It needs the Track A writeln hook described
in feature-b-buffered-text-io-and-settextbuf ("WHOEVER TAKES THE WRITE SIDE,
READ THIS FIRST"), or a scope limited to fopen'd FILEs. Either way, measure the
win on a putchar loop first.

## Parked 2026-09-24

setvbuf fixed; buffering needs the Track A writeln hook, see summary

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.
