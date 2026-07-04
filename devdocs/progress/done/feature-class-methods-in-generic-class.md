# `class function` / `class procedure` members inside a generic class

- **Type:** feature (parser — generics, Track A)
- **Status:** done
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

## Resolution (2026-07-04)

DONE. Root cause was NOT the class-body member parser (it already handled isClassMethod) — ParseGenericTemplate's depth scan counted the `class` member prefix as a nested body opener and swallowed the unit into the template buffer. Fixed by peeking the following token (function/procedure/var/property/of + soft ctor/dtor/operator = prefix). Second half: BufferGenericMethod now starts the captured range at the `class` token for class-method impls. Regression test/test_generic_class_methods.pas (5/5, incl. virtual/override on generic + class procedure) in test-core. Self-host byte-identical, make test green.
