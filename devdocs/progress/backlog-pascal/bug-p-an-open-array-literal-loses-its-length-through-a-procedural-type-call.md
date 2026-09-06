---
slug: bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call
track: P
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "Passing an open-array LITERAL through a procedural-type variable silently loses the hidden length. `c := @Show; c([7,8,9])` for `TOpenCb = procedure(const A: array of Integer)` gives `Length(A) = 263845145632`; the same callback typed `of object` gives `Length(A) = 0`. fpc 3.2.2 prints 3 for both, and pxx itself prints 3 for the DIRECT call and for an indirect call passing a VARIABLE -- so the defect is exactly literal-plus-indirect, and the three neighbouring rows that work are what makes it invisible. THIS COMPILES TODAY WITH NO DIAGNOSTIC on ordinary `array of Integer` code, which is why it outranks the parse refusal that led me here. THE `of object` SPELLING ANSWERS 0, A LEGAL LENGTH: a probe passing `[]` sees a correct answer, and so does any caller that only checks Length > 0 before looping. It also explains why bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap could not be fixed in the parser -- `array of const` is called with a literal essentially always, so making the declaration parse just routes it into this. Measured on x86-64 only."
---

# An open-array literal loses its length through a procedural-type call

Measured at `d918976f8`, binary `0207010e859c`, against fpc 3.2.2 (`-Mobjfpc`).

```pascal
type
  TOpenCb = procedure(const A: array of Integer);
  TObjCb  = procedure(const A: array of Integer) of object;
```

| call shape | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `Show([7,8,9])` — literal, direct | 3 | 3 |
| `Show(v)` — variable, direct | 3 | 3 |
| `c([7,8,9])` — literal, **indirect** | **263845145632** | 3 |
| `c(v)` — variable, indirect | 3 | 3 |
| `o([7,8,9])` — literal, **indirect `of object`** | **0** | 3 |
| `o(v)` — variable, indirect `of object` | 3 | 3 |

Four of six rows agree, and the two that do not are the two nobody probes first.

## Why this is worse than a garbage number

**The `of object` row answers 0.** Zero is a legal length. A caller that does
`for i := 0 to Length(A) - 1` simply does nothing, correctly-looking; a probe
that passes `[]` to check the shape works gets the right answer for the wrong
reason. Only a non-empty literal separates them, and only on the plain
procedural type does the wrongness announce itself by being absurd.

**It needs no unusual construct.** `array of Integer` and a callback variable
are ordinary Pascal. Nothing here is a dialect corner.

## It is why the `array of const` parse fix cannot land

[[bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap]]
is a refusal at declaration time. I have now written that parse fix twice and
reverted it twice. The second attempt was made on a specific hypothesis — the
procedural-type arm sets `mIsArr` but never `LastTypeRecId := TVarRecId`, which
`mPTypesRec[i]` reads for the element stride, where the method arm at ~6869 sets
both — and adding it **did** make the declaration parse and did not fix the
call: `Length` came back 0, then 4311000, then a segfault.

That hypothesis was wrong, and the way it was wrong is worth keeping: it named a
mechanism inside the parser for a defect that is not in the parser, and the
symptom it predicted (a wrong length) is the symptom this bug produces anyway.
It would have been indistinguishable from a confirmation if I had stopped at the
first row. What separated them was one probe with no `array of const` in it at
all — a plain `array of Integer` through the same procedural type, which fails
identically. **`array of const` is not the subject; the open-array literal is.**

So the parse fix stays reverted until this lands. `array of const` is called
with a literal essentially always, so parsing the declaration only moves the
failure from a clean refusal to a silent wrong number.

## Where to start

The direct call and the variable-argument indirect call both work, so the
length is computed and passed somewhere. What differs on the failing rows is a
literal materialised at the call site and handed to a callee whose signature is
known only through the procedural type. Compare the argument setup the direct
literal call emits against the indirect one (`PXXDBG=a.ir:<proc>`); the hidden
length is present in one and not the other.

## Not established

- **Target.** x86-64 only. Anything about the hidden length's width or position
  could differ on i386/arm32/riscv32, and that is where the dev loop cannot see.
- Whether an open-array literal through a procedural type in a RECORD or as a
  field behaves the same.
- Whether the `0` and the garbage are two bugs or one — they are different
  wrong answers from two spellings of the same shape.
