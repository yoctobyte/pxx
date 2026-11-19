---
track: C
tags: [crtl, stdio, stdin, mixed-language]
prio: 25
type: bug
blocked-by: []
summary: "In a C+Pascal program, crtl's stdin (getchar/fgetc/fgets/scanf on stdin) reads fd 0 itself and shares no pending bytes with the Pascal readers. A byte Pascal's Eof/Read has peeked is invisible to a following getchar, and a C ungetc on stdin is invisible to ReadLn. Since bd6e6176d3 the two Pascal readers share theirs (PXX_BUILTIN_STDIN_HOOK); crtl is the third reader and isn't on that hook."
status: open
owner:
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
