---
track: C
prio: 55
type: feature
blocked-by: []
summary: "lib/crtl/src/stdio.c is entirely unbuffered — fputc is one write() syscall per character — and setvbuf at :1051 is a stub that ignores its arguments and returns SUCCESS, which is the dishonest-stub shape the SetTextBuf ruling exists to reject, and worse here because C callers check the return. Add FILE write buffering under C99 7.19.3p7's policy, make setvbuf real, and share a flush registry with lib/rtl so mixed WriteLn/printf output keeps its order."
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
