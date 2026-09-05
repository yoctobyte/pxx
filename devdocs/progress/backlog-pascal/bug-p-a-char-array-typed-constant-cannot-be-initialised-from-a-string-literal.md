---
slug: bug-p-a-char-array-typed-constant-cannot-be-initialised-from-a-string-literal
title: "`const c: array[1..4] of Char = 'ABCD'` is refused — a char array's initialiser must be a parenthesised element list"
track: P
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-05
found-by: frankA
summary: "A string literal standing in for the element list of an `array[..] of Char` typed constant is refused with `expected '(' before ''ABCD''`. It is ordinary Pascal and FPC accepts it. Nested one level down the same gap reads as `too many array initializer elements`, because the outer list expands the literal's characters at the WRONG level. Blocks conformance rows tarray3 and tforin12."
---

# The two shapes, and why they report differently

```pascal
type CharA4 = array[1..4] of Char;
const car4 : CharA4 = 'ABCD';                        { expected '(' before ''ABCD'' }

type T = array[1..3] of Char;
var  a : array[1..3] of T = ('asd', 'sdf', 'ddf');   { too many array initializer elements }
```

Same missing rule, two diagnostics. In the scalar form the parser wants a `(`
and the literal is not one. In the nested form the outer parenthesised list IS
present, so the literal reaches the element loop — which has no arm for "this
element is itself a char ARRAY, fill it from these characters" and counts the
literal as one element against an array whose elements are arrays. The count
then disagrees with the shape and the error names the count.

The second diagnostic is the more expensive one: it points at the element
COUNT, which is correct, and says nothing about the element TYPE, which is the
question.

# Scope

`array[lo..hi] of Char` initialised from a string literal, at any nesting depth.
FPC pads with spaces when the literal is shorter than the array and rejects it
when longer; `tarray3.pp` asserts both edges plus `{$P+}` openstring and
char-array/string comparison, so it needs more than this rule alone. `tforin12`
needs only the nested form.

Related but NOT the same mechanism:
[[bug-p-a-typed-constant-initialiser-accepts-only-a-string-literal]] — that one
is about a named CONSTANT on the right-hand side, this one about the literal
being spread across an aggregate. A fix for either leaves the other.
