---
track: P
prio: 40
type: bug
status: done
blocked-by: []
owner: frankO
summary: "The implicit Self injected at parameter slot 0 shifts every per-param array with it -- except FIVE, at the three injection sites. `puntyped` was the first found: a method's untyped-param flag sat one slot LEFT of its parameter, and because IsUntypedVarParamSym matches the NAME at slot i against the FLAG at slot i, the one omission failed in BOTH directions -- method `Integer(b) := 99` REFUSED where the byte-identical free routine is accepted, and method `Int64(a) := 99` ACCEPTED, an 8-byte store into a 4-byte parameter slot with no diagnostic. A concept-driven audit (difference the declared array[0..MAX_PROC_PARAMS-1] locals against what each shift loop carries) then found four more: pFixedLen/pFixedLo, a fixed-array param's length and LOW BOUND -- a silent out-of-bounds WRITE, `0 10 20` with the 30 past the end where free and fpc give `10 20 30`; and ptypesFileRecSize/ptypesFileElemTk, a `file of T` param's width and kind, which needs TWO file params of different widths to show and then fails the method body's COMPILE. The __genself site was additionally missing the whole pdefault* family and ptypesStrCap, which the twin loop already shifted -- the sibling arm that bug-pascal-method-default-param-self-shift never reached. All measured on pin fe1e9c37d322. Fixed at all sites; two relation-asserted tests."
---

# The Self shift forgets `puntyped`, so a method parameter is mislabelled

`pnames`, `ptypes`, `pconst`, `pout`, `pdefault*`, `pDynDepth`, `pDim*` all
shift when Self is injected at slot 0. `puntyped` did not, at any of the three
sites: two in `pasparser_proc.inc` (the method-impl shift and its `__genself`
twin) and one in `pasparser_decl.inc`.

`IsUntypedVarParamSym` (`pasparser_stmt.inc`) matches the parameter NAME at slot
`i` against the FLAG at slot `i`. Moving one and not the other therefore
mislabels **both** ends at once — which is why one omission produced two
opposite defects.

## Measured, and both halves pre-date the fix

Byte-identical parameter lists, free routine vs method. Pin `fe1e9c37d322` and
HEAD agreed, so this is not a recent regression:

| construct | free routine | method | correct |
| --- | --- | --- | --- |
| `Integer(b) := 99`, `b` untyped | accepted | **REFUSED** | accepted |
| `Int64(a) := 99`, `a` a 4-byte Integer | refused | **ACCEPTED** | refused |

The cast-as-lvalue arm is legal on an untyped parameter precisely because such a
parameter has no declared width for the cast to disagree with. The second row is
the dangerous direction: an 8-byte store into a 4-byte slot, accepted with no
diagnostic.

## How it stayed invisible

Nothing asked a *method* parameter whether it was untyped. The construct that
does — the cast-as-lvalue arm — is rare, and the overload-matching readers of
`ProcParamUntyped` are reached for methods only on a path that, at HEAD, does
not type-check single-candidate method arguments at all.

**A probe I built for this first could not fail**, and the controls caught it:
an interface method binding a string to an `Integer` parameter was accepted —
but so was the same call with *no untyped parameter anywhere*, so the probe was
measuring the missing check, not the shift. The discriminating pair had to be
the two cast-as-lvalue directions, where free and method spellings differ.

## Fix

`puntyped[i] := puntyped[i-1]` in both `pasparser_proc.inc` shift loops and
`mPUntyped` in the `pasparser_decl.inc` one, plus `[0] := False` beside the
existing `pconst[0] := False` (Self always has a type).

`test/test_method_untyped_param_self_shift.pas`, wired into `test-core`, asserts
that the method matches the byte-identical free routine **and** that both give
the right value — an equality-only check would pass on two identical zeros. It
carries no per-target constant. Positive control: the pinned compiler refuses to
compile it, at the method, `cast-as-lvalue: the cast type must be the same size
as the variable`.

Found while diagnosing the single-candidate gate widening in
`refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes`: two of
that experiment's regressions were this bug becoming visible once the gate
started reading `ProcParamUntyped` for methods.


---

## The concept-driven audit, and the four it found that a caller census could not

`puntyped` was found by tripping over it. That is not a method, so afterwards I
asked the question the other way round: **which arrays are indexed by parameter
slot?** — enumerate every declared `array[0..MAX_PROC_PARAMS-1]` local and
difference it against what each shift loop actually carries.

```
per-param arrays declared            37
site A (method impl) shifts          33   missing: pFixedLen pFixedLo
                                              ptypesFileRecSize ptypesFileElemTk
site B (__genself)   shifts          25   ...plus pdefault* (7) and ptypesStrCap
```

**A census of any one array's CALLERS cannot find these**, and I nearly ran one:
it returns only the sites that already reached the helper, and the defect is a
site that never did. The population has to come from the concept, never from a
call graph. (frankD reached the same conclusion the same night from the
opposite direction — a tidy "three sites, all covered" that was wrong by two.)

### Both new rows measured, on the pin

**`pFixedLen` / `pFixedLo`** — a named fixed-array parameter's element count and
low bound. For `W(n: Integer; var arr: array[1..3] of Integer)` assigning
`arr[1..3]`:

| | result |
| --- | --- |
| free routine | `10 20 30` |
| fpc 3.2.2, both spellings | `10 20 30` |
| method | `0 10 20` — **and the 30 landed past the end of the array** |

The low bound lands on the Integer slot and the array slot reads an unset 0, so
every index is off by `lo`. A silent out-of-bounds write, no diagnostic.

**`ptypesFileRecSize` / `ptypesFileElemTk`** — a `file of T` parameter's element
width and kind. **One file parameter shows nothing**: both arms answer
`FileSize = 1`, because the expected value collides with the answer a
mis-sized slot happens to give. Two file parameters of *different* widths
discriminate, and then the method body fails to compile outright:

```
pascal26:22: error: read/write(file): the variable is 4 bytes
                    and the file's element type is 20
```

— the first file parameter wearing the second's record size. Fail-closed here,
unlike the array row.

### The `__genself` site was a sibling arm of an already-fixed bug

Site B never shifted `pdefault*` at all, though it clears `pdefault[0]`. The
twin loop's own comment records what that cost when it was missing there:
*"a method impl that repeats its defaults silently gave `M(a: Integer = 1;
b: Integer = 2)` a=2 on a defaulted call"* —
`bug-pascal-method-default-param-self-shift`. That fix landed on one arm and
the sibling kept the defect, which is the shape
`normalise-dont-special-case.md` names.

### Verification

Census 1874 files, **1 row differs and it is the new test file itself**.
Conformance 384 pass / 1 fail, unchanged. fgl 7/7.
`test/test_method_param_self_shift_family.pas` asserts both new rows as
relations against the byte-identical free routine, so it carries no per-target
width; the pin refuses to compile it.
