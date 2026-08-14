---
track: A
prio: 60
type: bug
blocked-by: []
summary: "Passing an AnsiString LITERAL to a `const m: Variant` parameter passes the raw string handle where a Variant record is expected, so the callee reads garbage. Assigning the literal to a Variant local first works. Silent wrong value, no diagnostic. Found calling pylib's `Exception.Create(const m: Variant)` from Pascal."
---

# An AnsiString literal passed to a Variant parameter arrives as garbage

Found while measuring [[feature-a-one-exception-class-in-a-shared-unit]], but
nothing about it is specific to exceptions.

## Reproduce

`pylib.Exception.Create` is declared `constructor Create(const m: Variant)`.

```pascal
program c; uses pylib;
var pe: pylib.Exception; v: Variant;
begin
  pe := pylib.Exception.Create('py hi');     { literal -> Variant param }
  WriteLn('literal: [', pe.msg, ']');        { garbage bytes }
  v := 'py hi';
  pe := pylib.Exception.Create(v);           { through a Variant local }
  WriteLn('local:   [', pe.msg, ']');        { py hi }
end.
```

The literal arm prints a short run of junk that reads like a pointer rendered as
text — consistent with the AnsiString HANDLE being passed in the slot where a
Variant record was expected, and the callee then reading the record's tag and
payload out of whatever the handle points at.

## Why this is the shape it is

Same family as [[project_variant_typecast_is_a_reinterpret_in_pxx]]: a Variant
is a record, an AnsiString is a handle, and the conversion between them has to
be an explicit boxing step. The assignment path (`v := 'py hi'`) performs it;
the ARGUMENT path for a literal does not. FPC converts in both positions.

Two arms of one concept, and the second arm is the broken one —
`devdocs/dev/normalise-dont-special-case.md` exactly. So before closing this,
sweep the neighbours rather than fixing the literal case alone:

- a `char` literal, an integer literal, a float literal to a Variant param;
- a typed `AnsiString` VARIABLE (not a literal) to a Variant param;
- a `const` vs a `var` vs a by-value Variant parameter;
- an `array of const` element, which is a different boxing already.

Compare each against FPC — `tools/fpc_diff_probe.sh` is the instrument.

## Severity

Silent wrong value with no diagnostic, in a position ordinary code writes. It is
worth knowing whether a refusal (a compile error on the unconvertible argument)
is cheap, because that would turn this from wrong-and-quiet into loud while the
conversion is built.

## Gate

The repro above prints `py hi` on both lines, an FPC differential over the
sweep list, `make test` + self-host byte-identical.
