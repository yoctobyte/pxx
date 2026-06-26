# Anonymous nested fixed array `array[..] of array[..] of T`

- **Type:** feature (parser) — Track A
- **Status:** done
- **Opened:** 2026-06-23
- **Closed:** 2026-06-23
- **Found by:** differential probe vs FPC.

## Resolution (2026-06-23)

Parser fix (front-end only, no codegen). The fixed-array dimension parser now
loops: after `[dims] of`, if the element is itself a fixed `array [` (peek
`Tokens[TokPos] = tkLBrack`), it consumes `array` and merges the inner dims into
the outer dimension list, repeating to any depth. `array[a] of array[b] of T`
thus flattens to the same N-D array as `array[a,b] of T` (identical FPC layout),
reusing the existing `BuildFlatNDIndex` machinery — both `m[i][j]` and `m[i,j]`
indexing work. A dynamic `array of` element stops the merge (unchanged).

Applied in two sites: `ParseVarSection` (the ticket's `var m: …` example) and
`ParseTypeSection` (`type T = array[..] of array[..] of T`). Record fields
(`r.m[i][j]`) and 3-level nesting verified working. Byte-identical to FPC across
the probes. Gate: `make test` (self-host byte-identical, no reseed — front-end
only). Closes feature-nested-anonymous-fixed-array.

## Problem

An inline (anonymous) nested fixed array fails to parse:

```pascal
var m: array[1..3] of array[1..2] of Integer;   // pxx: "Expected begin, but got"
```

The equivalent multidim form `array[1..3,1..2] of Integer` works, and a NAMED
element type (`type R = array[1..2] of Integer; var m: array[1..3] of R`) works —
only the anonymous `of array[...]` element is unhandled.

## Fix

In the fixed-array type parser, when the element type after `of` is itself
`array[...]`, merge its dimensions into the outer array's dimension list (FPC
treats `array[a] of array[b]` as `array[a,b]` — identical layout). Single-point
parser fix; reuse the existing multidim dimension machinery. Gate: `make test`.
