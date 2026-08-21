---
slug: bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file
track: A
prio: 35
type: bug
blocked-by: []
summary: "A parse error inside a `uses`d unit reports a line number that belongs to no file and never names the file. Measured: an error at globtype.pas:800 is reported as line 1103, in a file 843 lines long. The `near:` context is correct, so the token is findable — by grepping, not by navigating."
status: backlog
---

# A parse error in a `uses`d unit reports a line number that exists in no file

## Measured (2026-08-21)

Two independent cases, both found while probing the FPC compiler tree under
`--mimic-fpc-compiler`:

| real location | reported |
| --- | --- |
| `constexp.pas:58` (`operator := (const u:qword):Tconstexprint;`) | `pascal26:360` |
| `globtype.pas:800` (`tmsgstate = (ms_on := 1,`) | `pascal26:1103` |

`globtype.pas` is **843 lines long**, so 1103 is not a line in it — nor in
`cclasses.pas` (3185) at that content, nor in the program that pulled it in
(4 lines). The number identifies nothing.

The `near:` context IS correct in both cases (`const u qword >>> Tconstexprint`
and `type tmsgstate ms_on >>>`), which is the only reason the real sites above
could be pinned down at all — by grepping for the token text.

## Why it costs more than it looks

Neither half of "where" survives: the line is wrong AND the file is never
named. A user compiling a program that `uses` a dozen units gets a number with
no file, and the number does not even bound the search. The `near:` text
rescues it, but grep-for-the-tokens is not error navigation, and it fails
outright when the tokens are common.

This is also a **compat-probing multiplier**: every wall found in a foreign
corpus costs this rediscovery step before it can be filed, which is exactly
when precise locations matter most.

## Where to look

The likely shape is a line counter that is cumulative across the concatenated
unit sources rather than reset per file (1103 and 360 both look like offsets
into a longer stream), and an error path that carries a line but not the file
identity. `dbg_filetable.inc` already maps positions to files for DWARF, so the
mapping the diagnostic wants may already exist.

## Gate

An error inside a `uses`d unit names the unit's file and a line that resolves
inside it. A test with a program using a unit that has a deliberate syntax
error at a known line, asserting file and line. Self-host byte-identical.
