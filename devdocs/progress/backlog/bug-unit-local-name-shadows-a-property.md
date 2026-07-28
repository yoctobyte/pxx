---
track: A
prio: 55
type: bug
---

# A unit's LOCAL variable name breaks a property access with the same name

Pre-existing, reproduces on `stable_linux_amd64/default/pinned`:

```python
from pathlib import Path
import html
print(Path("/a/b").name)
```

```
pascal26:3: error: unexpected token   near:  Path  /a/b  >>>  name
Expected: ), but got: (Kind: 81, Line: 3)
```

Without `import html` it compiles and prints `b`. `lib/rtl/pathlib.pas` declares
`property name: AnsiString read GetName`, and `lib/rtl/html.pas` has a routine
whose LOCAL variable is called `name` (`var i, j, v, d: Integer; r, name:
AnsiString`). Pulling that unit in makes the property access stop parsing.

A routine's local must not be visible outside it, and certainly must not change
how a member of an unrelated class parses. Two things to establish:

1. whether the local's symbol survives past its routine (a rollback that does
   not happen, or happens after the name is interned), and
2. why a *symbol* participates in resolving what is syntactically a MEMBER name
   after a dot — a property access should be looked up on the receiver's class,
   full stop.

The second is the one with reach: any unit that happens to use a common word as
a local (`name`, `value`, `text`, `size`) could be shadowing members elsewhere,
silently changing which overload or path is taken rather than erroring, in
programs nobody has tried yet.

## Where it turned up

songformatter's `convertrawtext.py` imports both `html` and `pathlib`.

## Gate

`make test` + a regression case pairing a unit with a local named `name`
against a class exposing `name` as a property.
