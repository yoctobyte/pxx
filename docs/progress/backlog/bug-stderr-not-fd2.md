# `writeln(StdErr, ...)` goes to stdout — StdErr not connected to fd 2

- **Type:** bug (RTL / runtime text-file wiring) — likely Track B RTL, possibly a
  runtime-init boundary with Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-23 (found wiring a TUI demo's result to stderr, Track B)

## Symptom

`writeln(StdErr, 'x')` is written to **stdout (fd 1)**, not stderr (fd 2). The
standard `StdErr` text file is not bound to fd 2.

## Minimal repro

```pascal
program se;
begin
  writeln('to-stdout');
  writeln(StdErr, 'to-stderr');
end.
```

```
$ ./se 2>/dev/null      # stderr discarded
to-stdout
to-stderr               # <-- StdErr line still appears: it went to fd 1
$ ./se 2>&1 1>/dev/null  # capture only stderr
                        # <-- empty: nothing went to fd 2
```

Expected: `to-stderr` on fd 2, absent from fd 1.

## Why it matters

- Programs (and the compiler itself — `compiler.pas` uses `writeln(StdErr, ...)`
  for diagnostics) cannot separate errors/logs from normal output; piping stdout
  also captures things meant for stderr.
- A program cannot emit a clean result on one stream while writing escapes/markup
  on the other (the concrete case: a TUI demo writing its result to stderr while
  the alt-screen escapes go to stdout — had to fall back to a stdout newline +
  `tail -1`).

## Likely cause

The RTL/runtime initialises the `Output` text file to fd 1 but does not bind
`StdErr` (and probably `ErrOutput`) to fd 2 — so writes to it fall back to fd 1.
Check where `Output`/`Input` are set up at program start and add the fd-2 binding
for `StdErr`.

## Acceptance

- The repro puts `to-stderr` on fd 2 only; `./se 2>/dev/null` prints just
  `to-stdout`.
- Existing tests stay green.
