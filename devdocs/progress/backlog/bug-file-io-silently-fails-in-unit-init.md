---
prio: 55  # auto — silent wrong behaviour, no diagnostic; unit init is where setup code naturally goes
track: B
---

# Text file I/O silently fails in a unit's initialization section

- **Type:** bug — **Track B** (RTL file layer / startup ordering in `lib/rtl`).
  May turn out to be core startup order rather than the RTL, in which case it
  moves to Track A — see Cause below.
- **Status:** backlog — filed 2026-07-20.
- **Found by:** Track E, building `examples/mandelbrot/mandelkernel.pas`
  ([[feature-demo-mandelbrot-gui-threaded]]) — CPU detection reads
  `/proc/cpuinfo`, and doing it once in the unit's init section (the obvious
  place) silently produced the wrong answer.

## Repro

```pascal
unit uinit;
interface
var GotAtInit: Boolean; GotLater: Boolean;
function ReadProc: Boolean;
implementation
function ReadProc: Boolean;
var f: Text; line: AnsiString; ok: Boolean;
begin
  ok := False;
  {$I-} Assign(f, '/proc/cpuinfo'); Reset(f); {$I+}
  if IOResult <> 0 then begin ReadProc := False; Exit; end;
  while not Eof(f) do
    begin ReadLn(f, line); if Copy(line,1,5)='flags' then begin ok := True; Break; end; end;
  Close(f);
  ReadProc := ok;
end;
begin
  GotAtInit := ReadProc;      { <-- unit initialization section }
end.
```
```pascal
program TInit;
uses uinit;
begin
  GotLater := ReadProc;       { <-- identical call, from main }
  writeln('at init  = ', GotAtInit);
  writeln('at main  = ', GotLater);
end.
```
```
at init  = FALSE
at main  = TRUE
```

Same function, same file, same process. Only the call site differs.

## Why it matters

It is **silent**. `Reset` does not raise, `IOResult` reports a failure the
caller is likely to treat as "file absent" and fall back, and the program runs
on with a wrong answer. A unit initialization section is exactly where one-time
setup belongs — reading a config file, probing the environment, loading a table
— so this is a trap sitting on the idiomatic path. In the case that found it,
the consequence was a CPU-capability probe reporting no SSE2 on a machine with
AVX2, which would have silently selected the slowest kernel forever.

## Cause (to confirm)

Almost certainly ordering: the RTL's file/IO layer is initialized after unit
initialization sections run, so `Assign`/`Reset` operate on state that is not
set up yet. Worth checking:

- Where the Text/file layer's own init happens relative to the unit init chain
  in the startup sequence.
- Whether the same applies to other RTL facilities in a unit init section —
  heap (probably fine, it is needed earlier), `ParamStr`/`ParamCount`, the
  environment, `Randomize`. A quick sweep would tell us whether this is a
  file-layer-specific gap or a general "the RTL is not up yet" hazard.
- Whether `{$I+}` exception mode behaves the same (the repro uses `{$I-}` +
  `IOResult`).

## Two acceptable fixes

1. **Make it work** — initialize the file layer before user unit inits. Best
   outcome: the idiomatic code does the idiomatic thing.
2. **Make it loud** — if there is a real reason the file layer cannot come up
   first, then a file operation before it is ready must be a hard error naming
   the cause, not an `IOResult` a caller will misread as "not found".

Silently returning a plausible wrong answer is the one option that should not
survive.

## Acceptance

- The repro prints `TRUE` / `TRUE` (fix 1), or fails loudly with a diagnostic
  that names the real problem (fix 2).
- A regression test covering file I/O from a unit init section.
- The sweep above is recorded in the ticket, so we know whether other RTL
  facilities share the hazard.

## Links
[[feature-demo-mandelbrot-gui-threaded]] ·
`examples/mandelbrot/mandelkernel.pas` (works around it with an explicit
`InitMandelKernel` the caller invokes from main; the comment there points here).

## Log
- 2026-07-20 — Filed from Track E with the minimal repro above.
