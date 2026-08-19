---
title: Language reference
order: 40
---

# Language reference

PXX implements a traditional Object Pascal dialect. This section documents the
language surface as the compiler actually accepts it.

> **Status:** in progress. Pages are added as features are documented and
> verified against the compiler. Each example here compiles on the pinned
> compiler.

## Pages

- [Pascal basics](./pascal-basics.md) — program structure, declarations,
  statements, routines, and units.
- [Types](./types.md) — ordinals, floats, strings, records, dynamic and fixed
  arrays, enumerations, sets, pointers, and variants.
- [Classes & interfaces](./classes.md) — fields, methods, virtual/override,
  constructors, and properties (including indexed and default properties).
- [Generics](./generics.md) — generic functions, generic classes, and explicit
  named specialization.
- [Exceptions](./exceptions.md) — try/except/finally blocks, raising, and unwinding.
- [PXX dialect](./dialect.md) — extensions and deliberate PXX-specific surface.
- [Name resolution](./name-resolution.md) — which file an import loads, which
  declaration a name binds to, and what happens when Pascal, C and Nil Python
  share a name.
- [Name collisions](./name-collisions.md) — two languages, one name, and the
  `as` escape that says which you mean.
- [FPC compatibility](./fpc-compatibility.md) — what matches FPC, what does not,
  and how to write portable code.
