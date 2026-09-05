---
slug: bug-p-a-char-array-typed-constant-cannot-be-initialised-from-a-string-literal
title: "`const c: array[1..4] of Char = 'ABCD'` is refused — a char array's initialiser must be a parenthesised element list"
track: P
prio: 35
type: bug
status: done
owner: frankB
created: 2026-09-05
found-by: frankA
summary: "FIXED. A string literal may now stand in for the element list of an `array[..] of Char`, in both the const and the var spelling, 1-D bare and as a ROW inside a parenthesised N-D list. Zero-padded when short, refused when long, byte-identical to fpc 3.2.2. The nested shape could not be fixed on its own: the const declaration path was the one of three that never merged a NAMED array element's dimensions, so `const a: array[1..3] of T` reported SizeOf 12 for a 9-byte object at HEAD, silently -- there is no row to fill if the compiler does not know the row is three chars wide."
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


# Resolved

Four parse sites, two routines, one rule -- and a prerequisite that was a
separate and worse defect than the refusal this ticket reports.

## The prerequisite, which was silent

`const a: array[1..3] of T` with `T = array[1..3] of Char` answered
**SizeOf 12** against fpc's 9, at HEAD, with no diagnostic and a wrong-sized,
wrong-strided store. Three declaration paths merge a named FIXED array type's
dimensions into the enclosing dimension list -- var, type, const -- and the
branch had a hand-written copy in the first two and was simply ABSENT from the
third, so `ParseTypeKind` resolved `T` to its bare base scalar. That is what a
fourth site looks like when a rule is spelled out per caller instead of named
once: not a divergent copy, a MISSING one, which no amount of reading the three
copies against each other would surface.

It is also why the ticket's nested shape could not be fixed alone. Spreading
`'asd'` across row 1 requires knowing row 1 is three chars.

`ArrTypeDimList` now names the rule (normalised: N entries for an N-D type, one
synthesised entry for a 1-D one) and the three callers each keep their own
append loop, which is the part that genuinely differs.

## The rule itself

Measured against fpc 3.2.2, both edges:

- 1-D bare literal accepted, in `const` and `var` alike.
- N-D bare literal REFUSED (`"(" expected`) -- the shorthand is one-dimensional.
- Inside a parenthesised list, a literal at a depth BELOW the last dimension is
  one ROW; at the innermost depth an element is a single Char and the ordinal
  path is right. The guard is the DEPTH, not the token.
- Short literals pad with **#0**, not spaces. A terminal renders `[AB\0\0]`
  exactly like `[AB  ]`; the first oracle read here was wrong, and only
  `cat -A` on the raw bytes separated them. The test is a `diff -u`, not a grep,
  for that reason.
- Long literals refused, with fpc's own wording.

## The two diagnostics were the tell

`const` said `expected '(' before ''ABCD''` and `var` said
`array initializer must be parenthesised`. Two messages, one missing rule, in
two routines -- a double case that does not look like one, because the sibling
does not share a line of code with its twin, only a sentence of Pascal.

## Not fixed here, and it is the next construct

`writeln(a[1])` where `a` is an N-D char array prints ONE character; fpc prints
the row. Reproduced on a plain `var` with no initialiser at all, so it is
independent of this change and predates it. It is the read direction of
[[bug-p-a-char-array-row-of-a-2d-array-is-not-a-string]] (`a[0] := 'hi'`), and
the two are one mechanism: a partially-subscripted N-D char array is a scalar
where it should be a row. The test here prints ELEMENTS throughout rather than
rows, so that open defect puts no known-red row in a file about initialisers.
