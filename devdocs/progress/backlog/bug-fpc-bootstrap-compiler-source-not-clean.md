# FPC bootstrap no longer compiles compiler source

- **Type:** bug (Track A / bootstrap hygiene)
- **Status:** backlog
- **Owner:** —
- **Found / Opened:** 2026-06-27, while validating an unrelated C entry fix.

## Symptom

`make bootstrap` fails when the system FPC compiler compiles
`compiler/compiler.pas`.

Observed command:

```text
make bootstrap
```

First hard errors observed:

```text
symtab.inc(979,27) Error: Identifier not found "TypeSize"
parser.inc(14065,5) Fatal: Syntax error, ";" expected but "IF" found
```

The normal self-host path still fixed-points byte-identically:

```text
make compiler/pascal26
cmp /tmp/pascal26-build /tmp/pascal26-verify
```

## Likely Cause

At least two source constructs are accepted by the self-hosted compiler but not
by FPC 3.2.2:

- `compiler/symtab.inc` calls `TypeSize` before FPC has seen a declaration for
  it.
- `compiler/parser.inc` has an `end` before another statement without the
  semicolon FPC requires.

## Acceptance

- `make bootstrap` succeeds from the checked-in source with FPC 3.2.2.
- The self-host fixedpoint remains byte-identical after the cleanup.
- Add or keep a gate that catches accidental FPC-incompatible compiler-source
  edits when bootstrap hygiene matters.
