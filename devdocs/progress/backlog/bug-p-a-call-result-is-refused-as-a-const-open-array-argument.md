---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`Sum(Copy(a, 1, 3))` and `Sum(MakeArray)` -- a call result given to a `const array of T` open-array parameter -- do not compile. FPC accepts both. A naive relaxation was tried and REVERTED: it compiles `array of Double` and `array of string` into segfaults, so the by-ref check is a symptom and the real defect is that a dynamic-array-valued call is typed inconsistently."
status: backlog
---

# A call result is refused as a `const array of T` argument

Found 2026-08-20 by an FPC differential probe over open arrays. `fpc -O-
-Mobjfpc` 3.2.2 vs pxx at `e18d01cef`:

```pascal
type TIA = array of Integer;
function SumI(const a: array of Integer): Int64;  { ... }
function MkI: TIA;                                { ... }
var dy: TIA;
```

| call | FPC | pxx |
| --- | --- | --- |
| `SumI(dy)` | works | works |
| `SumI([7,8,9])` | works | works |
| `SumI([])` | works | works |
| `SumI(fx)` (fixed array) | works | works |
| `SumI(Copy(dy, 1, 3))` | 9 | **error: by-reference argument must be a variable** |
| `SumI(MkI)` | 6 | **error: by-reference argument must be a variable** |
| `M(Copy(dy, 0, 2))` where `M(var a: array of Integer)` | works | error |

Slicing an array and totalling it is about as ordinary as Pascal gets, and it
does not compile.

## Do NOT just relax the by-ref check — that was tried, and measured

The obvious fix is to let a non-lvalue bind a `const` open-array parameter
(alongside the record / fixed-array-result / promo / variant exemptions already
there). It was implemented, self-hosted, and **reverted**, because the by-ref
check is a symptom rather than the defect. With the check relaxed:

| element type | result |
| --- | --- |
| `array of Integer` | correct — and leak-free: 200k × `SumI(Copy(dy,0,5))` peaks at 392 kB, identical to FPC |
| `array of Char`, `array of Int64` | correct |
| `array of Boolean` | `error: no overload of FB matches: argument types: (Pointer)` |
| `array of Double` | **SEGFAULT** |
| `array of string` | `CatS(MkS)` rejected as `(Pointer)`; `CatS(Copy(sa,0,1))` **SEGFAULT** |
| `array of TRec` | rejected as `(Pointer)` |

Same source shape, five different outcomes. That is not a check that needs one
more exemption; it is a dynamic-array-valued CALL being typed inconsistently
depending on how it was produced and what its element is — sometimes carrying
its element type, sometimes collapsing to `Pointer`. Overload resolution and
the open-array marshaller then disagree about what they were handed, and the
marshaller wins by crashing.

`array of string` also shows what the marshaller is missing: a managed element
needs the copy-in / copy-out temp `IRLowerCallArg` builds for a static-array
source (`ir.inc`, the `oaEligible` block), and a bare handle does not carry it.

So the work is: give a dyn-array-valued expression ONE type, make overload
resolution accept it against an open-array parameter, and route it through the
same temp the other aggregate sources already use — then the by-ref exemption
is a consequence rather than the fix. `devdocs/dev/root-cause-over-microfix.md`
is the relevant note: five outcomes for one shape means several mechanisms are
serving one concept.

## Adjacent, same root

- `SumI(Copy(MkI, 1, 2))` — `Copy` OF a call result — is rejected with `no
  overload of Copy matches: (Pointer, Integer, Integer)`. FPC accepts. Same
  `Pointer` collapse, in `Copy`'s own resolution.
- `M(Copy(dy, 0, 2))` for a `var` open array: **FPC accepts this** (the
  write-back lands in a temp and is discarded). Mentioned so the `var`
  rejection is not read as deliberate parity — it is not.
- The by-ref check exists in TWO copies in `parser.inc` (around lines 16340 and
  24627) with the same message and diverging exemption lists. Whatever lands
  here has to land in both, or should merge them first.

## Not affected

The rest of the open-array / `array of const` / `Format` probe matches FPC line
for line: open arrays from a dynamic array, a fixed array, an array literal and
an empty literal; `Low`/`High`/`Length` on each; `var` open arrays writing back
to all three sources; `array of const` with integer/string/char/boolean
elements; and `Format` with `%d %s %x %X %.4x`, width and left-justify flags,
`%%`, and positional `%1:s`.
