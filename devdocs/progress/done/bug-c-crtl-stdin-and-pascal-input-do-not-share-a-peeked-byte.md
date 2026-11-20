---
track: C
tags: [crtl, stdio, stdin, mixed-language]
prio: 25
type: bug
blocked-by: []
summary: "In a C+Pascal program, crtl's stdin (getchar/fgetc/fgets/scanf on stdin) reads fd 0 itself and shares no pending bytes with the Pascal readers. A byte Pascal's Eof/Read has peeked is invisible to a following getchar, and a C ungetc on stdin is invisible to ReadLn. Since bd6e6176d3 the two Pascal readers share theirs (PXX_BUILTIN_STDIN_HOOK); crtl is the third reader and isn't on that hook."
status: done
owner: claude-dupwt
---

# crtl stdin and Pascal Input do not share a peeked byte

Reported by frank-user with bd6e6176d3, which made Pascal's builtin
console reader and textfile's Input share their pending stdin byte.

## Shape

    { Pascal }  if not Eof(Input) then ...   // peeks one byte from fd 0
    /* C */     c = getchar();               // reads fd 0: the peeked byte is gone

The reverse is the same: `ungetc(c, stdin)` pushes onto crtl's own stack,
which ReadLn never consults.

## Why it is not urgent

- No known program mixes C stdin and Pascal stdin reads.
- crtl's stdin is deliberately UNbuffered (done/feature-c-crtl-stdio-read-
  buffer.md) so it never parks more than its own ungetc stack. The exposure
  is the one peeked byte, not a buffer.

## Fix direction

Put crtl's stdin on the same hook: fgetc(stdin) first takes the Pascal side's
pending byte if there is one, and ungetc(c, stdin) / a C-side peek hands it
over. The hook's form is whatever PXX_BUILTIN_STDIN_HOOK settles into once
the guard is dropped at the next pin. Test: a mixed program that peeks with
Eof, then getchar, then ReadLn.

## Fixed 2026-11-20 (claude-dupwt)

crtl's stdin is now the third reader on the handshake:

- `fgetc`/`fread` on fd 0 first take Pascal's held bytes through pxxcio's new
  `__pxx_stdin_take`: textfile's byte (PXXStdinTakeHook), then the console's
  line or peek byte. That happens after crtl's own pushback and read buffer,
  which are always older. `fgets`/`getchar`/`scanf` ride fgetc.
- `ungetc(c, stdin)` with nothing of crtl's own ahead of it goes to
  `__pxx_stdin_unget`, which calls builtinheap's new PXXStdinUngetConsole.
  That reclaims textfile's byte, then puts c in front: in the peek slot when
  the line is spent and the slot is free, else in the slot just read in a line
  still being read. When neither is free (a spent line AND a held peek byte),
  crtl keeps c on its own stack: C still reads it first, and only a Pascal
  reader misses it. Writing it over a spent line's #10 slot was tried; ReadLn
  then returned '', because that slot is past PXXLineTextLen.
- pxxcio's references sit under the new PXX_BUILTIN_STDIN_UNGET define, the
  PXX_BUILTIN_STDIN_HOOK pattern, so the pin (whose builtin lacks the function)
  still builds lib/rtl. The functions always exist and answer -1/0 there.

This needed bug-c-a-pascal-units-initialization-never-runs-under-a-c-main
(done, same commit): textfile's initialization, which installs the hook,
never ran under a C main.

Row c_stdin_shared26 (test/c_stdin_shared_with_pascal.c + its unit): Pascal
Eof / bare ReadLn / Eof(Input) / ReadLn(Input) interleaved with getchar,
ungetc and fgets, on a pipe. latest-97b51d1032 printed `getchar=b, P:ac,
getchar=X, fgets=Xef, PI:dghi, P:k, end=90`. Now every step sees the byte it
names (the .expected file), and the output from a file equals the output from
a pipe.

Verified: gate quick GREEN; test-core and test-c-conformance both ran to their end with 0 failures.
