# Anonymous nested fixed array `array[..] of array[..] of T`

- **Type:** feature (parser) — Track A
- **Status:** backlog
- **Opened:** 2026-06-23
- **Found by:** differential probe vs FPC.

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
