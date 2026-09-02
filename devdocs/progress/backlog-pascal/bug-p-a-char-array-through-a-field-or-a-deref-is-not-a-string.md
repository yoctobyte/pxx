---
slug: bug-p-a-char-array-through-a-field-or-a-deref-is-not-a-string
track: P
type: bug
prio: 70
status: backlog
found: 2026-09-02
found-by: frankZ
owner: frankZ
blocked-by: []
summary: "`ASTCharArrayCap` is the ONE oracle the char-array-is-a-string conversion asks, in both directions and at every site, and it answered only for AN_IDENT while its name said NODE. So `r.a := 'abc'` on an `array[0..7] of Char` FIELD never reached the conversion, fell through to the scalar type check and was refused as `cannot assign ShortString to Char` — five of six lvalue shapes rejected, the plain variable the only one that worked. Two lines of synapse's ssfpc.inc are that shape; they took out all three lib_synapse jobs plus the TLS loopback. Fixed by teaching the oracle AN_FIELD and AN_DEREF through the accessors that already know each shape."
---

# A Char array through a FIELD or a DEREF is not a string

Found by attempting the target: three `lib-test lib_synapse` reds were wired to
[[umbrella-one-full-tier-run-with-no-red-tier]] as unreproducible because
`external/synapse` is absent on plexus. Fetched it; all three reproduce, and
all three are one construct.

## The construct

`external/synapse/ssfpc.inc`, inside `WSAStartup`'s `with WSData do`:

```pascal
szDescription  := 'Synsock - Synapse Platform Independent Socket Layer';
szSystemStatus := 'Running on Unix/Linux by FreePascal';
```

Both fields are `array[0..N] of Char` in `TWSAData`. Two lines, two errors,
and the error is the same one in all three jobs:

```
pascal26:0: error: incompatible types: cannot assign ShortString to Char
```

## Root cause — one oracle, one node kind

`ASTCharArrayCap` (`pasparser_lval.inc`) is what every consumer of "a static
`array of Char` IS a string" asks: the AN_ASSIGN arm in `ir.inc` for the store,
`WrapCharArrayToStringExpr` for the read, the argument coercion, the comparison.
Its header said *"the element count if `node` denotes a STATIC Char array"*.
Its body said:

```pascal
if ASTKind[node] <> AN_IDENT then Exit;
```

A field, an element or a deref answered -1, the conversion never fired, and the
assignment fell through to `AssignSideKind`'s AN_FIELD arm — which reads
`ASTTk`, and `ASTTk` on an array field is the ELEMENT kind. So the destination
typed as `Char`, the source as `ShortString`, and the check refused it. **The
check was right; it was answering the question it was given.**

Measured before the fix, seven lvalue shapes:

| shape | before | after |
|---|---|---|
| `a := 'hi'` (plain var) | ok | ok |
| `r.a := 'hi'` (field) | **refused** | ok |
| `r.i.a := 'hi'` (nested field) | **refused** | ok |
| `ra[1].a := 'hi'` (field of an array element) | **refused** | ok |
| `p^ := 'hi'` (deref) | **refused** | ok |
| `r.a := s` (field, from a variable) | **refused** | ok |
| `a[0] := 'hi'` (row of a 2-D array) | refused | refused — [[bug-p-a-char-array-row-of-a-2d-array-is-not-a-string]] |

**Five of six, and the exact mirror of the defect `AssignSideKind`'s own header
records**, where five of six lvalue shapes were UNCHECKED and a string handle
was stored over a record. Same function, same six shapes, opposite sign. A
predicate that answers about an IDENT while its name says NODE is wrong in
whichever direction its caller happens to face — and both faces have now been
paid for.

## The fix

`ASTCharArrayCap` learns AN_FIELD and AN_DEREF, through the accessors that
already know each shape (`RecFieldIsArray`/`ArrLen`/`DynDepth`/`ArrNDims`/
`Type`, and `IsDerefPtrArray`/`DerefPtrArrayInfo`) rather than by re-deriving
the layout. `IsNodeArray` is the sibling predicate and asks exactly these three
node kinds for exactly this reason — its own header names *"writing to one was
rejected as `cannot assign ShortString to Char`"* as one of four faces of one
wrong answer. This is a fifth face of the same one.

Multi-dimensional returns -1 in every arm rather than guessing an extent: a
wrong capacity here is a write past the row, and a loud refusal is the better
failure.

## Verification

- `test/test_char_array_field_is_a_string.pas`, new, wired into `test-core`.
  14 assertions covering all six fixed shapes in BOTH directions, plus the two
  things a compile-only test would miss: the **zero fill** (a shorter value over
  a longer one leaves `ab......`, not `abcdefgh` with two bytes patched) and
  **truncation** at cap, each with a neighbouring field asserted intact.
- **The oracle is FPC 3.2.2**, run on this same file: all 14 rows identical.
- **Positive control:** the pinned v399 compiler (`954adef93a7b0e9e`) REJECTS
  the test at three lines. A green run therefore cannot be a run that did
  nothing.
- All four synapse programs build and produce their Makefile-expected output
  byte for byte, including `lib_synapse_tls_loopback`'s real handshake with the
  verify-rejects arm.
- `converged after 1 round(s)`, binary `090042338fc2deae`.

## What this does NOT close

The three `regression-lib-test-lib-synapse-*` jobs **build with
`$(PXX_STABLE)`**, and the pinned compiler still has the bug. They stay RED
until the owner takes the next pin, and no amount of work in this tree changes
that. Stated on each of the three tickets.
