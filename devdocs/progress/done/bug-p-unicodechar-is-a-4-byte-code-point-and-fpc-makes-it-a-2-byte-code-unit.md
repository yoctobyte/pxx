---
slug: bug-p-unicodechar-is-a-4-byte-code-point-and-fpc-makes-it-a-2-byte-code-unit
track: P
prio: 40
type: bug
blocked-by: []
status: done
created: 2026-08-31
summary: "`UnicodeChar` maps to tyUCS4Char (4 bytes, a code POINT) where FPC makes it an alias of WideChar (2 bytes, a UTF-16 code UNIT). Both pxx tables agree, so it is NOT a two-table split -- it is one entry that is probably wrong, sharing a line with `ucs4char`, whose 4-byte mapping IS correct and must not move. Zero in-tree declarations use the name (measured), so the change is cheap here; the decision is about out-of-tree code and about Write/string-conversion behaviour, which differs between the two kinds beyond SizeOf."
owner: frankB
---

# `UnicodeChar` is 4 bytes here and 2 in FPC

Found 2026-08-31 by the full builtin-scalar audit in
[[bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets]] — a
by-product, not its subject.

## Measured (x86-64, binary `cf1d5398838a`, vs fpc 3.2.2 `-Mobjfpc`)

| name | pxx `SizeOf(T)` | pxx `SizeOf(v)` | fpc |
| --- | ---: | ---: | ---: |
| `WideChar` | 2 | 2 | 2 |
| `UCS4Char` | 4 | 4 | 4 |
| **`UnicodeChar`** | **4** | **4** | **2** |

pxx is self-consistent: both its paths say 4. This is not the two-table split
the parent ticket was about — it is one table with one entry to argue about.

## Where

`compiler/pasparser_lval.inc`, `BuiltinScalarTypeKind`:

```pascal
else if CaseEqual(nm, 'ucs4char') or CaseEqual(nm, 'unicodechar') then Result := tyUCS4Char
```

The two names share a line. **`ucs4char` on that line is right and must not
move**: `UCS4Char` really is a code POINT (FPC: `UCS4Char = type LongWord`), and
the note in `defs.inc` explains why it has its own kind — it converts to a
string as UTF-8, unlike `WideChar`. Only `unicodechar` looks misplaced. In FPC
`UnicodeChar = WideChar`, a UTF-16 code UNIT.

## Why it is a bug and not a compat item

The two differ in KIND, not just width. A `UnicodeChar` here holds any code
point and stringifies as UTF-8; in FPC it is one UTF-16 unit, and a character
above the BMP takes two of them. So a record or array of `UnicodeChar` has both
a different stride and different contents than the same declaration under FPC,
and code that walks a UTF-16 buffer through the name is reading the wrong width
with no diagnostic — the ordinary silent-wrong-values shape.

## Why it is filed rather than fixed

The one-word change (`unicodechar` -> `tyWideChar`) is not obviously right, and
that is the whole reason this is a ticket:

- If any in-tree code declares `UnicodeChar` expecting a code point, narrowing
  it to 2 bytes truncates silently — the same class of damage, aimed the other
  way.
- `tyWideChar` and `tyUCS4Char` differ in how `Write`/string conversion treat
  them, so this changes behaviour beyond `SizeOf`.
- It touches the UTF-16 story, which has its own open work.

**The grep is done, and the answer is zero.** Measured 2026-08-31 over `lib/`,
`examples/`, `compiler/` (`.pas` and `.inc`): **no declaration anywhere in the
tree uses the name** — `: UnicodeChar` and `of UnicodeChar` both return nothing.
So the first bullet above is not a live risk in-tree, and the change is cheap
here. What it cannot tell us is what OUT-of-tree code expects, which is the
whole content of the decision: FPC's answer is 2, and matching it is the
default unless someone wants the code-point meaning kept under this spelling.

Leaving that as an instruction to the next reader would have been the wrong
shape — it is one command, and a ticket that asks its reader to run a
measurement its author could have run is a ticket that will be read and not
acted on.

## Gate

`make compiler/pascal26`, plus the row above added to
`test/test_sizeof_builtin_type_names.pas`, which already pins the other two.

## FIXED 2026-09-04 (frankB) — `unicodechar` moves to the widechar line

`compiler/pasparser_lval.inc`, both tables: `OrdinalNameToTk` and
`BuiltinScalarTypeKind`. `ucs4char` stays where it was and keeps `tyUCS4Char`,
which is the constraint this ticket was most careful about.

Measured after, against fpc 3.2.2 `-Mobjfpc`, every row identical:

| | pxx before | pxx after | fpc |
| --- | ---: | ---: | ---: |
| `SizeOf(UnicodeChar)` / `SizeOf(v)` | 4 / 4 | **2 / 2** | 2 / 2 |
| `SizeOf(array[0..3] of UnicodeChar)` | 16 | **8** | 8 |
| `s := uc` (stringify) | `A` | `A` | `A` |
| `SizeOf(WideChar)`, `SizeOf(UCS4Char)` | 2, 4 | 2, 4 | 2, 4 |

## Two corrections to this ticket's own text

**"the row above added to `test/test_sizeof_builtin_type_names.pas`, which
already pins the other two"** — it pinned NEITHER. That file had no `WideChar`
and no `UCS4Char` row before today; its only near miss was `PWideChar`. All
three rows are added now, both halves each (type name and variable), plus a
widths line asserting `2 4 2`. The pre-fix answer was `2 4 4`, so the row is
aimed.

**"one entry that is probably wrong, sharing a line with `ucs4char`"** — TWO
entries, one in each of the two tables, on a line each. The ticket's larger
point survives and is the reason this was cheap: they AGREED with each other, so
this was never the two-table split its parent audit was about. It is one
decision spelled twice.

## The pin cannot be the control here

`stable_linux_amd64/default/pinned` cannot compile
`test_sizeof_builtin_type_names.pas` at all — it predates
bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size
and answers `SizeOf: unknown type or variable` at line 86. The before-number
`2 4 4` is from this session's own pre-change build, not from a revert cycle.

## Controls run on the kind that must NOT move

`test_ucs4char`, `test_variant_widechar_store` (whose `u-emoji` row stores
`UCS4Char($1F600)` into a Variant and still prints 😀 — the above-BMP code point
this ticket said must keep working), `test_pwidechar_cast`,
`test_widechar_no_cast_in_program`, `test_widechar_to_utf8_b319`,
`test_widechar_var_concat`, `test_widechar_var_to_string` and
`test_widechar_var_to_string_arg`. All green.

The RTL-pull prescan in `pasparser_prog.inc` needed no change: it pulls
`builtin` on any mention of `unicodechar`, and `widechar` is on the same list for
the same helpers.

## Gate

`make compiler/pascal26` converged; `tools/gate.sh quick` GREEN with the FPC seed
canary CONCURRENT.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
