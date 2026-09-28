---
track: P
prio: 30
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, from a report on x86-64 and wasm32: `WriteLn(Output, 'a')` alone is refused)
tags: [pascal, text-io, fpc-parity, refusal]
summary: "`WriteLn(Output, x)` and `ReadLn(Input, x)` were refused as \"undefined variable\" unless the source also named Text, TextFile, file, IOResult or Flush. Output and Input are declared by the Text RTL, which the driver loads only when a token prescan sees one of those names. `output` and `input` are now on that list. StdErr is deliberately not: bare, it is the builtin fd-2 constant."
owner: ""
---

# `WriteLn(Output, …)` is refused unless the source names Text

```pascal
program p;
begin
  WriteLn(Output, 'a');   { pxx: undefined variable (Output)   FPC: a }
end.
```

It happens on every target where the default RTL is loaded, with v450 and at
HEAD. `ReadLn(Input, x)` is refused the same way. `Flush(Output)` was
accepted, because `flush` was already on the list.

## Cause

`pasparser_prog.inc` loads textfile, where Input, Output, ErrOutput, StdOut and
the Text StdErr are declared, only when a prescan of the token stream finds
`text`, `textfile`, `ioresult`, `file` or `flush`. That saves loading
textfile+builtin for the common program that has no files. `output` and
`input` were not on the list.

## The fix

`output` and `input` join the list, and the length pre-check widens from
{4, 5, 8} to 4..8.

`stderr` is left off on purpose. Without textfile, `WriteLn(StdErr, x)`
resolves to the builtin fd-2 constant and works. Pulling the unit for it would
send every StdErr write through the Text RTL for no reason.

A program with a VARIABLE named `output` or `input` now loads textfile. That is
a size cost only: its own variable still shadows the unit's. It is the same
trade the list already makes for `file`.

## Measured (2026-09-29)

- `test/test_output_and_input_resolve_without_a_text_declaration.pas`
  (`ReadLn(Input, …)`, `Write`/`WriteLn(Output, …)`, a bare `WriteLn(Output)`,
  and nothing that names Text) equals FPC 3.2.2 on x86-64, i386 and wasm32
  (and riscv32 by hand). With the previous compiler it is refused.
- The 267 Pascal tests that contain the word `output` or `input` and none of
  the old trigger words were each built with the previous compiler and with
  this one, then run. 251 give identical stdout and stderr. The other 16 fail
  to build under both.
