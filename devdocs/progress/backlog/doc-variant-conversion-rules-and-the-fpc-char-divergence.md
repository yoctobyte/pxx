---
track: D
prio: 45
type: doc
blocked-by: []
summary: "Document the Variant->scalar conversion rules now that they are settled: a boolean variant converts to -1 (OLE VARIANT_TRUE, matching FPC) while Ord(True) stays 1, and Variant->Char answers Chr(n) by default where FPC takes character 1 of the variant's string form ('65' -> '6') — the one row that deliberately diverges, available under --strict-fpc. Also CORRECTS an existing note in docs/language/types.md that is factually wrong."
---

# Document the Variant conversion rules, and fix the wrong note about them

- **Type:** doc — **Track D** (`docs/**` only; prose, no `compiler/**`, no
  `lib/**`)
- **Why now:** the behaviour was undefined-in-practice until 2026-08-13 and is
  now settled and tested, so it can be written down without guessing. Shipped
  in pin **v268**:
  [[bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting]] and
  [[bug-p-variant-to-int-and-char-conversion-diverges-from-fpc]].

## 1. There is a WRONG statement in the docs today — fix it first

`docs/language/types.md` (the `## Variants` section, the `> [!NOTE]` block):

> In this dialect, boolean values stored in a `Variant` print as `0` for
> `False` and `1` for `True` when using `writeln`.

**Both halves are wrong.** Measured against pinned v268 and FPC 3.2.2:

```pascal
var v: Variant; b: Boolean;
v := True;  writeln(v);   { True   — NOT 1 }
v := False; writeln(v);   { False  — NOT 0 }
b := True;  writeln(b);   { TRUE   — a plain Boolean is upper-case }
```

FPC prints exactly the same three lines. So it is not a divergence at all, and
"in this dialect" is doubly misleading. Worth keeping the *real* quirk the note
was probably reaching for: a boolean **variant** prints `True`/`False` while a
plain Boolean prints `TRUE`/`FALSE` — in both compilers.

## 2. Document the conversion rules (the new content)

A `Variant` in a scalar context — `i := v` and `Int64(v)` alike, which are the
SAME operation as of the fix above — converts rather than reinterpreting. Two
rows are worth stating explicitly because they surprise people:

**Boolean -> number is -1, not 1.** A boolean variant converts to OLE's
`VARIANT_TRUE`, matching FPC and every COM/OLE consumer:

| expression | value |
| --- | --- |
| `Int64(v)` with `v := True` | `-1` |
| `Byte(v)` with `v := True` | `255` |
| `Double(v)` with `v := True` | `-1.0` |
| `Ord(True)`, `Integer(someBooleanVar)` | `1` — unchanged |

The contrast in the last row is the point: the `-1` belongs to the VARIANT
conversion, not to booleans generally. Same in FPC.

**Variant -> Char diverges from FPC on purpose.** PXX answers `Chr(n)`; FPC
renders the variant to its string form and takes character 1:

| `v` | PXX (default) | FPC, and PXX under `--strict-fpc` |
| --- | --- | --- |
| `65` | `A` | `6` |
| `122` | `z` | `1` |
| `2.5` | `#0` | `2` |
| `True` | `#1` | `T` |
| `'hi'` | `h` | `h` |

Explain WHY, briefly — it is the rare case where "we differ from FPC" is the
defensible side, and readers porting code deserve the reason:

- FPC contradicts itself here: the same numeric variant converts as a NUMBER
  for `Byte`/`Word`/`Int64` (`Byte(v)` is 65) and as a STRING for `Char`.
- The rule comes from OLE Automation's `VARIANT`, which has no char type, so
  Delphi defined a Char target as "a string of length 1" and FPC inherited it.
- The intermediate is not even writable by hand: `c := someAnsiString` is a
  type error in FPC.

`--strict-fpc` reproduces FPC's rule exactly, including the edges (an empty
string yields `#0`; a `Null` variant raises, with FPC's own message, which names
*String* rather than Char).

## 3. The umbrella's description needs widening

`docs/reference/modes.md` describes `--strict-fpc` as turning on "the strict
**checks**" and lists four (`--strict-case`, `--strict-operator`,
`--strict-visibility`, `--require-forward`). That is now incomplete in kind, not
just in count: the umbrella also changes **semantics** in two places — FPC's
shift widths (`StrictShiftWidth`, see
[[bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths]]) and now the
Variant->Char rule. A reader who takes "checks" literally will not expect
`--strict-fpc` to change a *value*. Same for `docs/reference/cli.md`'s table row
and `docs/reference/directives.md`'s `{$STRICT_FPC}` row.

## Verify, do not assume

Track D's rule: compile every snippet with `$(PXX_STABLE)` (v268 or later — an
older pin predates this behaviour and will show the old wrong answers). The
Char table above is worth pasting into a scratch file and running under both
modes rather than transcribing from this ticket.

## Gate

Docs stay internally consistent; every snippet compiles and produces the stated
output under `$(PXX_STABLE)`. No compiler or library changes.
