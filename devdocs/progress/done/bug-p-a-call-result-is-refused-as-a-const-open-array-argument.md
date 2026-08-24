---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`Sum(Copy(a, 1, 3))` and `Sum(MakeArray)` -- a call result given to a `const array of T` open-array parameter -- do not compile. FPC accepts both. A naive relaxation was tried and REVERTED: it compiles `array of Double` and `array of string` into segfaults, so the by-ref check is a symptom and the real defect is that a dynamic-array-valued call is typed inconsistently."
status: done
owner: claude-A
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

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.

---

# Resolution (2026-08-25)

Two defects, both on the ticket's own line — *give the expression one type, then
route it through the same temp* — and neither was the by-ref check the ticket
warned against relaxing.

**1. The expression had no type that overload resolution could read.** Both
`argTypes[i]` construction sites (`pasparser_expr.inc`, `pasparser_stmt.inc`)
described a dyn-array-valued CALL or `Copy()` by its handle — `(Pointer)` — while
the identical dyn-array VARIABLE was reported by its ELEMENT kind. So `CatS(MkS)`
came back "no overload matches: (Pointer)" and `SumI(Copy(MkI,1,2))` was refused
inside `Copy`'s own resolution. Both sites now normalise a dyn-array-valued node to
its element kind, which needed `NodeDynDepth` / `NodeDynBaseTk` / `NodeDynBaseRec`
in `ast_arena.inc` to grow arms for the four call kinds and for `AN_DYN_COPY`, and
needed the call kinds to have somewhere to read from — hence `ProcRetDynDepth`,
written at all three `ProcRetIsDynArray` sinks in `pasparser_proc.inc`.

That is the fifth ticket in this family whose fix was **"the metadata was there
and the reader was missing"** — `ProcRetIsDynArray` had been set for as long as
dyn-array results existed; nothing on the argument path had ever asked.

**2. The float rows did not merely refuse — they SEGFAULTED, and that was the
real find.** `const a: array of Double` records the ELEMENT kind, `tyDouble`, in
`Procs[].Params[].TypeKind`. The "integer argument to a float parameter" coercion
in `ir.inc` tests exactly that field, and the argument it saw was the dyn-array
HANDLE — `tyPointer`, an ordinal. So it allocated a Double temp, ran the handle
through `cvtsi2sd`, and handed the callee a float where a pointer belonged:

```
0: call a=129 tk=17            <- MkD, result is a dyn-array HANDLE (tyPointer)
1: store_sym a=93 b=0 tk=19    <- into a hidden temp typed tyDouble
2: load_sym a=93 tk=19
3: arg a=2 tk=17
4: call a=128 b=3 tk=19        <- SumD receives garbage
```

`SumD(dd)` on a VARIABLE was fine, because only the call form reached that arm.
The guard is one clause — `and (not Procs[cpi].Params[pathIdx].IsArray)` — an
open-array parameter's TypeKind is the element's, so it must never drive a scalar
coercion of the argument.

# Measurement

22 rows across two differentials, `fpc -Mobjfpc -O1` as oracle: every element
kind (Integer, Int64, Double, Single, Char, AnsiString, Boolean, a record),
every source shape (call result, `Copy(var)`, `Copy(call)`, static array,
`[literal]`, mixed-numeric literal, empty result, two calls in one expression),
both `const` and by-value open arrays. **22/22 match fpc** on x86-64, aarch64,
arm32 and riscv32. Before: int worked, double segfaulted, str/bool/rec were
"no overload matches: (Pointer)".

Landed as `test/test_call_result_as_open_array_argument.pas` in `test-core`,
`.expected` being fpc's own output.

# Spun off

**i386 was already broken here and stays broken:** `LenD(dd)` — a dyn array of
Double, a plain VARIABLE, a body that only calls `Length` — segfaults on
`--target=i386` on the PINNED compiler exactly as on HEAD, while arm32 and
riscv32 (also 32-bit) are fine. Filed as
`bug-a-an-open-array-of-double-segfaults-on-i386`. The new test is native-only
for that reason; adding it to a cross list would land a known red.

Gate: `make compiler/pascal26` fixedpoint converged in 1 round,
`tools/gate.sh quick` GREEN.
