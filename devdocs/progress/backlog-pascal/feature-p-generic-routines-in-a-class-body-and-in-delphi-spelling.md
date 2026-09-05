---
slug: feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling
title: "A generic routine is parsed at top level only — not as a class method, and not in the Delphi spelling"
track: P
prio: 45
type: feature
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "`generic procedure`/`function` at unit level works (71deb21d4). Two adjacent spellings do not parse at all: `generic function Add<T>(...)` declared INSIDE a class body, and the Delphi form `function Add<T>(...)` with no `generic` keyword, both as a free routine and as a method. Eight FPC-testsuite rows, four each, one diagnostic each — measured 2026-09-05, and they are the largest remaining lever in the generics conformance cluster."
---

# Two spellings, four rows each, one diagnostic each

Measured against the whole generics cluster of the FPC test suite, so these are
not guesses about what might be missing.

**A — `generic` before a METHOD, inside a class body** (`expected ':' before
'function'`):

```pascal
type TTest = class
  generic function Add<T>(a, b: T): T;    { <- refused here }
end;
```
rows: `tgenfunc5`, `tgenfunc7`, `tgenfunc9`, `tgenfunc12`

**B — the DELPHI spelling, no `generic` keyword** (`expected ':' before '<'`):

```pascal
function Add<T>(a, b: T): T;              { free routine }
type TTest = class
  class function Add<T>(a, b: T): T;      { and as a method }
end;
```
rows: `tgenfunc2`, `tarray16` (free), `tgenfunc4`, `tgenfunc6` (methods)

Both diagnostics are the parser hitting the `<` where it expects a parameter
list or a return type, so nothing downstream has been exercised — this is a
front-end gap, and what lies behind it is unmeasured.

# Why these two together

`71deb21d4` added `generic procedure` / `generic function` at unit level, and
[[bug-p-a-generic-function-cannot-be-declared-in-a-unit]] closed the unit case.
So the CONCEPT exists and the substitution machinery behind it runs; what is
missing is the two remaining positions the same declaration can occupy. That is
`devdocs/dev/normalise-dont-special-case.md`'s shape exactly — one construct
reachable through several spellings, with the later spellings left behind.

Filed as ONE ticket because the fix is likely one: whatever accepts a type
parameter list after a routine name at unit level has to be reachable from the
class-member declaration parser and from the Delphi spelling. If measurement
says they are genuinely two mechanisms, split it then, not now.

# The trap this area already has

**A `%FAIL` row scores ANY refusal as a pass**, and this cluster is full of
them. Making the parser accept a spelling it used to refuse will turn some rows
RED, and those are missing diagnostics that were always missing rather than
regressions — that is exactly how `tgenfunc17`/`tgenfunc18` and `tgeneric4`
became visible. Read the fail list BY NAME after any change here, and check a
newly-passing `%FAIL` row passes for the reason it states.

# Gate

The eight rows above compiling, and each diffed against **fpc 3.2.2 output**
rather than scored on its exit code — the conformance harness compares exit
codes, so a row that runs printing the wrong thing reads as a pass. Plus the
conformance fail list read by name, `make test`, and the self-host fixedpoint.
