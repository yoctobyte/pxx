---
slug: compat-p-a-library-still-requires-a-begin-end-main-body
track: P
type: compat
prio: 30
status: backlog
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "FPC compiles `library f; ... exports f; end.` with no statement part; pxx answers `expected 'begin' before 'end'`. A library with nothing to initialise is the common shape and writing `begin end.` is the workaround, so this is an acceptance gap and not a wrong answer. Found while documenting `library`/`exports` in docs/reference/objects.md, which now tells readers to write the `begin end.`"
---

# A `library` still requires a `begin`/`end.` main body

Measured 2026-09-05, HEAD `ce19e5482`, binary `9bcfd2b4da30`:

```pascal
library nomain;
function f(n: Integer): Integer; cdecl;
begin f := n; end;
exports f;
end.
```

```
$ ./compiler/pascal26 --shared nomain.pas nomain.so
pascal26:5: error: expected 'begin' before 'end'
  near: ; end ; exports f ; >>> end . unit
```

The FPC oracle takes the same source (3.2.2, `fpc -Px86_64`): *"5 lines
compiled"*, `Linking libfpclib.so`. Adding `begin end.` makes pxx accept it and
the resulting `.so` exports the routine, so this is purely about what the parser
will accept.

## Why it is `compat` and prio 30 rather than a bug

Nothing computes a wrong answer and no program is silently broken — pxx refuses,
loudly, at the right line. Per CLAUDE.md that is *"FPC accepting what we reject
is compat, ranked by how much real code uses it"*.

On the ranking: a library whose main body has nothing to do is the ordinary
case, not an edge — a `.so` that only exposes a few `cdecl` routines has nothing
to initialise, and loading it does not run the main body anyway (see
`docs/reference/objects.md`, "No initialisation runs here either"), so an author
who knows that has an active reason to omit it. Against that, the workaround is
two words and mechanical, and every Delphi-generated `.dpr`-shaped library does
write `begin end.`. Hence 30, not higher.

## Where the fix goes

`ParseProgram` in `compiler/pasparser_prog.inc` — the same place that already
knows `IsLibrary`, which today is read only to gate `exports`. Making the
statement part optional when `IsLibrary` is the narrow form; a program must keep
requiring it.

Not fixed here because I am Track D and `compiler/**` is not mine to edit.
