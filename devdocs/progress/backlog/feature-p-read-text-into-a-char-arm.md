---
track: P
prio: 50
type: feature
summary: "the RTL half (textfile.TextReadChar) has landed, so ParseTextReadRest can now route read(f, c) to it and drop the 'not supported yet' error"
---

# `read(f, c)` still errors, but the thing it was waiting for now exists

- **Type:** feature — Track P (`compiler/parser.inc`, shared with A)
- **Opened:** 2026-08-09
- **Filed by:** Track B, finishing
  [[feature-b-textreadchar-with-pushback]] — the RTL side is Track B's file, the
  lowering is not, so it is handed over rather than done in place (the same
  split that filed the RTL half in the first place).

## State

`compiler/parser.inc:18735` still says:

    error: read(Text): reading into a Char is not supported yet — read into a
           string and index it

The comment two lines above it names exactly what was missing — *"a
TextReadChar with pushback in the textfile RTL (Track B's file)"*. That now
exists:

```pascal
procedure TextReadChar(var f: Text; var c: Char);
```

It consumes one byte, drains `f.Peek` first so it shares a cursor with
`TextReadLn`, and matches FPC on the details that were measured rather than
assumed: the newline is a character, CR is not swallowed (unlike `TextReadLn`),
and reading at or past end of file yields `#26` with no I/O error.

## The work

Add the Char arm in `ParseTextReadRest` routing to `TextReadChar`, and delete
the error. `bug-p-writeln-text-rejects-char` (done) has the write-side twin's
arm shape.

## Gate

`test/lib_textreadchar.pas` already asserts the RTL semantics through direct
calls and runs in `make lib-test`. The arm needs the same cases through the
KEYWORD form — `read(f, c)` four times, `read` then `readln`, a
`while not Eof(f)` loop — which is what `tools/fpc_diff_probe.sh` compares
against FPC directly.
