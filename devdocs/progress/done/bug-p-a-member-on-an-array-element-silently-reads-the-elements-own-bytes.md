---
track: A
prio: 60
type: bug
blocked-by: []
summary: "FIXED 2026-08-31. `.member` on an ARRAY ELEMENT of a non-record type fell through to a field access at offset 0 and read the element's own bytes: `a[0].NoSuchMember` on an array of AnsiString COMPILED and printed a pointer as an integer, and `ai[0].NoSuch.AndAnother` printed the element itself with the whole selector tail silently dropped. FPC rejects both. The valid reading of the same shape -- a type helper on the element, `a[0].Twice` -- was refused, so one guard fixed both directions. THIRD instance of this hole in three routines; each earlier fix's own comment asserted the sibling was covered."
status: done
owner: frankS
resolved: bd577a8dd
---

# A member on an array element read the element's own bytes

Found 2026-08-31 by frankS while probing the last open item of
[[feature-pascal-type-helpers]], and it is not that item — the ticket's remaining
work is *rvalue* receivers (`'abc'.ToLower`); an array element is an lvalue and
was never on the list.

## Measured, against FPC 3.2.2 in delphi mode

| program | pxx before | FPC |
| --- | --- | --- |
| `a[0].Twice` (`record helper for AnsiString` in scope) | `-1004535776` | `zz` |
| `a[0].NoSuchMember` | compiled, printed a pointer | `Illegal qualifier` |
| `ai[0].NoSuch.AndAnother` (array of Integer) | compiled, printed **7** — the element | `Illegal qualifier` |
| `s[1].NoSuch` | compiled, printed `113` — `Ord('q')` | rejected |
| `ar[0].NoSuch` (record element) | correctly refused | rejected |

The integer row is the quiet one and therefore the worse one: the selector was
**dropped**, so the typo had no observable effect at all.

## Mechanism, and why it is the third time

`ParseLValueAST`'s `tkDot` arm has two guards for exactly this hole, and both are
keyed on `ASTKind[node] = AN_IDENT` — a plain declared variable. `a[0]` is an
`AN_INDEX` node, so neither fires and the fall-through builds `AN_FIELD` at
offset 0.

- `bug-p-a-member-on-a-scalar-silently-reads-the-values-own-bytes` closed the
  `AN_IDENT` arm here.
- `bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes` closed
  it in `ParseClassRecordSelectors`, via `RequireValueHasMembers`.
- This is the third routine.

**Each earlier fix's own comment explains why the sibling is fine.** The array
note above the first guard says: *"Element access `arr[i].field` takes the
bracket branch above, strings take Length() style intrinsics — neither reaches
this check."* It does reach it. That sentence is the whole bug, and it was
written by someone who had just fixed the same defect one line up.

## The fix, and why it is one guard and not two

`AN_INDEX` + `recName = REC_NONE` + a memberless scalar element type →
**ask `TypeHelperOnValue` first**, then error. The shape has a valid reading and
an invalid one, and the same fall-through was serving both:

- `a[0].Twice` materialises the element into a temp, exactly as it already does
  for a call result, and now answers `zz` like FPC.
- `a[0].NoSuch` gets the diagnostic the `AN_IDENT` arm already had.

**Keyed on `AN_INDEX`, deliberately not on `tk`.** The scalar guard's own note
records that a `tk`-keyed refusal refused three working programs, because a
cast-then-deref receiver (`PPyVarRec(@v)^.Payload`) also arrives as a scalar with
`REC_NONE` and is correct. Those are `AN_DEREF`; this arm cannot see them, and
`arr[i]^.Field` over an array of pointer-to-record is untouched
(`test_arr_of_ptr_elemrec_b354`, run and green).

## Coverage, and the half that keeps it honest

`test/test_member_on_array_element.pas` is the **accept** side — a fix that
merely refused everything would pass a refusal-only test. Six lines, all matching
FPC on this exact program: `zz / yy / 14 / 1 / kk / zzzz`, covering a static
array, a non-managed element type, a record element still taking its own path, a
dynamic array element, and a chained `a[0].Twice.Twice`.
`test/refuse/member_on_array_element_{string,int}.pas` are the refusal side, and
FPC rejects both too, so this is parity rather than a rule of our own.
