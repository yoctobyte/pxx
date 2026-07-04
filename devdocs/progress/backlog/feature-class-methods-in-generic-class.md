# `class function` / `class procedure` members inside a generic class

- **Type:** feature (parser — generics, Track A)
- **Status:** backlog
- **Opened:** 2026-07-04 (bisecting the fgl wall; see [[fpc-lcl-compile-probe]])

## Problem

A static (`class`) method works in a normal class but NOT inside a `generic`
class:

```pascal
type
  TB = class class function M: Boolean; virtual; end;    { OK }

  generic TG<T> = class
    class function M: Boolean;                            { pascal26: unexpected token }
  end;
```

Non-generic `class function`/`class procedure` (incl. `virtual`/`override`) parse
fine; only the generic-class member parser chokes on the leading `class` method
qualifier. `fgl.pp`'s `generic TFPGList<T>` has `class Function ItemIsManaged :
Boolean; override;`, so this is one of `fgl`'s walls.

## Fix (Track A, parser.inc)

The generic-class body parser (the buffered-generic path) needs to accept the
`class` prefix on a method member the same way the ordinary class-body parser
does (`isClassMethod`). Mirror that handling into the generic member loop.

## Acceptance

- `class function`/`class procedure` (plain, `virtual`, `override`) inside a
  `generic … = class` compiles and specializes.
- Self-host byte-identical; `make test` green; regression `.pas`.
