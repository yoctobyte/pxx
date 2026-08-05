---
owner: claude-A
---

# Indexing a getter-backed string property fails to lower (IR_UNSUPPORTED)

- **Type:** bug — Track P (Pascal frontend); the fix likely lands in shared
  AST->IR lowering, which is Track A ground
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, writing a byte-level test for
  `TStrings.Text` (bug-b-stringlist-text-hardcoded-crlf). `l.Text[1]` would not
  compile.
- **prio:** 40

## Symptom

    pascal26: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 8)
              — a frontend gap, would miscompile

for indexing a string property whose read specifier is a **method**:

```pascal
type
  TC = class
  private
    FS: string;
    function GetS: string;
  public
    property PF: string read FS;      { field-backed  }
    property PG: string read GetS;    { getter-backed }
  end;
...
  writeln(c.PF[1]);   { OK   }
  writeln(c.PG[1]);   { IR_UNSUPPORTED }
```

FPC compiles both and prints `a` for each.

## Narrowing (measured, not reasoned)

| construct | result |
| --- | --- |
| field-backed property, indexed — `c.PF[1]` | OK |
| **getter-backed property, indexed — `c.PG[1]`** | **IR_UNSUPPORTED** |
| getter-backed property, whole — `writeln(c.PG)` | OK |
| getter-backed property via temp — `s := c.PG; s[1]` | OK |
| string **function** result, indexed — `F[1]` | OK |
| plain string variable, indexed — `s[1]` | OK |
| record string field, indexed — `r.s[1]` | OK |

So it is specific to the combination *property + method read specifier +
index*. Indexing a function result already works, and a getter-backed property
read is a call, so the two paths must be converging somewhere the index does
not follow — the property read appears to survive as its own AST node (kind 8)
into lowering instead of being rewritten into the call the non-indexed case
clearly does produce.

## Severity

**Low-risk as bugs go: it is a hard error, not a silent wrong value.** The
compiler refuses rather than miscompiling, and the message says so. The cost is
expressiveness — `TStringList.Text[i]`, `SomeObj.Caption[1]` and similar
idiomatic reads have to be spelled through a temporary.

## Workaround in use

Assign to a local first:

```pascal
s := c.PG;
writeln(s[1]);
```

`test/lib_strings_text.pas` does this, with a comment pointing here.

## Repro

```
printf 'program g; type TC=class private FS: string; function GetS: string; public property PG: string read GetS; end; function TC.GetS: string; begin GetS:=FS; end; var c: TC; begin c:=TC.Create; c.FS:=%s; writeln(c.PG[1]); end.' "'ab'" > /tmp/g.pas
./stable_linux_amd64/default/pinned /tmp/g.pas /tmp/g_out
```

## Resolution (2026-08-05) — the shape is wider than the ticket, and simpler

**Not property-specific.** `c.GetS[1]` — indexing any METHOD call result —
fails identically:

| construct | before |
| --- | --- |
| `c.PG[1]` getter-backed property | IR_UNSUPPORTED |
| **`c.GetS[1]` method call, no property involved** | **IR_UNSUPPORTED** |
| `Plain()[1]` explicit plain call | OK |
| `WithArg(1)[1]` plain call with an argument | OK |

The narrowing table above lists *"string function result, indexed — `F[1]` — OK"*,
and that row is what made properties look special. It is not the same
construct: a bare paramless function name in a value context is the **result
variable**, not a call, so `F[1]` never exercised the failing path. Comparing
`Plain()[1]` instead shows plain calls were always fine and the divergence is
the METHOD call.

### Cause — one condition

`IRLowerAddress` accepted a call in address position only for `tyRecord` /
`tyVariant` (the `RetViaHiddenDest` kinds), so a string-returning call fell
through to the `IR_UNSUPPORTED` tail. Extended to `tyAnsiString` and the frozen
kinds:

- **managed string** — the call's value is the HANDLE, and a handle is exactly
  what an index base wants (the same thing `IR_LEA` yields for a string variable
  in read position), so lowering the call gives the right base;
- **frozen string** — already returns a hidden-destination ADDRESS, so it fits
  the original rule unchanged.

### Verified

Byte-identical to FPC on: field-backed and getter-backed properties, a direct
method call, bare-name and explicit plain calls, an INDEXED property chained
into a char index (`c.PI[0][3]`), a `for` loop indexing the getter every
iteration, and `Length`/whole-value reads alongside.

`testmgr --tier native` **1165/1165 pass**. Locked in as
`test/test_index_getter_string_property.pas`.

### Workaround can be retired

`test/lib_strings_text.pas` assigns to a local first with a comment pointing
here. That is now unnecessary — `lib/**` is Track B's lane, so it is left for
them rather than edited from here.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
