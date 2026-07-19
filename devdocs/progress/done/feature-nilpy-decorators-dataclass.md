---
track: N
prio: 55
type: feature
---

# NilPy: @dataclass v1 (decorator syntax, annotated scalar fields, defaults)

Part of [[feature-nilpy-corpus-uforth]] milestone 1.

- Lexer: `@` -> tkAt.
- Module level: `@dataclass` (with optional `()`) before `class`; any other
  decorator = clean error. Class-level `name: type [= literal]` lines declare
  fields (int/float/bool/str + class-typed); a synthesized `create` ctor takes
  one positional param per field; omitted trailing args fill from literal
  defaults at the call site (kwargs later).
- Class-typed annotations (`p: Point`) now accepted in def/method params and
  return types, with RecName wired for field access.
- str fields register as tyAnsiString (see bug-nilpy-string-class-field).

Fields with container types (List/Dict/Optional/...) still error — next rung
is the list/dict design. field(default_factory=...) not supported.

Regression: test/test_nilpy_dataclass.npy in make test-nilpy.
