---
track: P
prio: 40
type: feature
blocked-by: []
summary: "`const CN: TNest = (p: (x: 1; y: 2); tag: 'k');` is rejected with `error: not a constant` when a field is itself a RECORD. Array-valued fields and array-of-record constants both work; only a record-typed field is missing. Loud (a compile error, never a wrong value)."
status: backlog
---

# A record-typed FIELD in a typed record constant

Found 2026-08-20 by an FPC differential probe over records. FPC accepts, pxx
rejects:

```pascal
type TPt   = record x, y: Integer; end;
     TNest = record p: TPt; tag: string; n: array[0..2] of Integer; end;
const CN: TNest = (p: (x: 1; y: 2); tag: 'k'; n: (7, 8, 9));
```

`pascal26: error: not a constant` — ConstEval reaches the inner `(x: 1; y: 2)`
and sees the identifier `x`.

It is exactly one shape. These all already work:

| shape | pxx |
| --- | --- |
| `const C: TPt = (x: 3; y: 4)` | works |
| `const C: TArrF = (tag: 'k'; n: (7,8,9))` (array field) | works |
| `const C: TA = ((x:1;y:2),(x:3;y:4))` (array OF record) | works |
| `const C: TNest = (p: (x:1; y:2); ...)` (record field) | **rejected** |
| `const C: TIn = (a: 1; inner: (q: 9))` (inline anon record) | **rejected** |

The parser says so itself, at the head of the record-typed-const branch in
`parser.inc`: *"Nested record/array fields are not handled yet."* The array half
of that sentence was implemented afterwards (the TGuid `D4` path, PendingInit
Kind 7); the record half was not.

## Why it is not a one-liner

A pending init records its target as **one** field-name span (`PendingInitFOff`
/ `FLen`), and the emitter builds a target chain

```
IDENT  ->  [INDEX elem]  ->  [FIELD span]  ->  [INDEX ValAux]
```

from it. A nested record needs a *path* of spans (`C.p.x`), and there is
nowhere to put the second one. Bolting on an `F2Off`/`F2Len` pair would make
one-level nesting work in about ten lines — and would be precisely the second
path that `devdocs/dev/normalise-dont-special-case.md` says stays broken, since
`a.b.c.d` would still be rejected and the next person would add `F3`.

The shape that generalises: give the pending init a **field path** rather than
a field, i.e. a small side table of spans plus a start/count pair in the
parallel arrays, and have the emitter loop the FIELD nodes instead of building
one. The parser side is then genuinely recursive — the record-const branch
calls itself for a record-typed field, pushing a span per level — and the same
loop covers `array of record` elements with nested records for free.

## Priority

Prio 40, not higher, because it fails **loudly**: the program does not compile,
so nothing silently computes a wrong answer. Workaround is a `var` plus an
assignment in the initialisation section.
