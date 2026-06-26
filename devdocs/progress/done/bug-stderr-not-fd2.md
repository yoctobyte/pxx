# `writeln(StdErr, ...)` goes to stdout — StdErr not connected to fd 2

- **Type:** bug (Track A — codegen write-fd, not RTL after all)
- **Status:** done (x86-64; cross is a documented follow-up)
- **Owner:** —
- **Opened:** 2026-06-23 (found wiring a TUI demo's result to stderr, Track B)
- **Resolved:** 2026-06-24 (Track A)

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

## Fix log

- 2026-06-24 (Track A) — DONE on x86-64. Not an RTL/text-file issue: `StdErr` is
  a const integer (= fd 2, `compiler.pas` `AddConst('StdErr', tyInteger, 2)`) and
  the write parser already special-cased it — but it merely **consumed** the
  `StdErr` token and built an ordinary (fd-1) write. The target fd was never
  threaded to the write syscalls.

  Fix, threading a per-statement target fd:
  1. **parser** (`ParsewriteArgsAST`): on the `StdErr` arg, set
     `ASTIVal[writeNode] := <const value> (2)` instead of just dropping it.
  2. **ir.inc** (`AN_WRITE`/`AN_WRITELN` lowering): read `writeFd` from
     `ASTIVal` (0 ⇒ STDOUT) and pass it in the `ival` slot of every `IR_WRITE`
     and the terminal `IR_WRITELN` (and through `IRLowerBoolWrite`, new `fd`
     param).
  3. **codegen** (x86-64): new global `CurWriteFd` (defaults STDOUT, reset at
     `IREmitMachineCode` entry); `IR_WRITE`/`IR_WRITELN` handlers set it from the
     node's `ival`; every write syscall site reads `CurWriteFd` instead of the
     hardcoded `STDOUT` — the string/char/newline sites (`ir_codegen.inc`,
     `EmitwriteSyscall`) **and** the integer/width/padding helpers
     (`symtab.inc` `EmitwriteInt`/`EmitwriteIntW`/`EmitwriteUInt[W]`/string
     helpers) — otherwise mixed `writeln(StdErr,'n=',42)` split the int onto fd 1.

  Verified: the repro and a mixed string/int/`:width`/Boolean line separate
  cleanly across fds; the self-hosted compiler's own `writeln(StdErr,…)`
  diagnostics now land on fd 2. Test `test/test_stderr_fd.pas` + Makefile
  fd-split assertions. `make test` green, self-host byte-identical.

  `Error()` (`lexer.inc`, the `pascal26:N: error:` line) deliberately still uses
  plain `writeln`→stdout so the test harness keeps capturing diagnostics on
  stdout; only the explicit `writeln(StdErr,…)` calls move to fd 2.

### Follow-up (cross targets)

i386 / arm32 / aarch64 still send `StdErr` writes to fd 1: the IR carries the fd
generically, but only the x86-64 write sites read `CurWriteFd`. Each cross
backend's write helpers (`ir_codegen386.inc` STDOUT sites; the arm32/aarch64
syscall fd loads in `emit.inc`) need the same `CurWriteFd` swap + a
`CurWriteFd := IRIVal` set in their `IR_WRITE`/`IR_WRITELN` handlers. No
regression today (those handlers leave `CurWriteFd` at its STDOUT default).
