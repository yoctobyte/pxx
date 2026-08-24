---
track: A
prio: 40
type: bug
blocked-by: []
status: backlog
owner: ""
summary: "`procedure P(v: Integer); var b: array[0..3] of Byte absolute v;` compiles, runs, and writes SOMEWHERE ELSE: v is unchanged. A by-value parameter's slot lives in the parameter space, so copying its Offset onto a local-kind symbol aliases a LOCAL slot at the same number. Silent wrong value, present on `pinned`, and the naive fix (copy the target's Kind too, which is what fixed the by-REF case) segfaults."
---

# An `absolute` overlay of a by-VALUE parameter writes to the wrong slot

Found 2026-08-24 by varying the shape while fixing
[[bug-a-absolute-cannot-overlay-an-untyped-var-parameter]] — the by-ref case was
a loud refusal, this one is the silent sibling.

## Measured

```pascal
procedure ByValue(v: Integer; var outv: Integer);
var b: array[0..3] of Byte absolute v;
begin b[0] := 5; outv := v; end;

procedure ByValueScalar(v: Integer; var outv: Integer);
var w: Byte absolute v;
begin w := 5; outv := v; end;

var i, j: Integer;
begin
  i := $01020304; ByValue(i, j);       WriteLn('arr    ', j);
  i := $01020304; ByValueScalar(i, j); WriteLn('scalar ', j);
end.
```

| | arr | scalar |
| --- | --- | --- |
| fpc 3.2.2 | `16909061` | `16909061` |
| pxx HEAD | `16909060` | `16909060` |
| pxx `pinned` | `16909060` | `16909060` |

The write to the overlay is simply lost. Both the array and the scalar spelling,
so it is the overlay's storage that is wrong, not one lowering.

## Why

`absolute` gives the new symbol the target's storage by copying its `Offset`:

```pascal
Syms[idx].Offset := Syms[absTarget].Offset;
```

An offset is meaningless without the space it is measured in, and the
declaration code already knows that for one pair — it refuses a local
overlaying a global with *"a local cannot overlay a global"*, on exactly this
reasoning. A by-VALUE parameter is a third space: its slot is in the parameter
area, while the freshly-allocated overlay symbol is `skLocal`. Same number,
different frame region.

## The obvious fix segfaults — measured, not assumed

The by-ref case above was fixed by copying the target's addressing mode as well
as its offset (`Kind` and `IsRef`), which makes the alias faithful for every
access path at once. Doing the same for a by-value target — `Syms[idx].Kind :=
Syms[absTarget].Kind` with `IsRef` False — **segfaults at runtime** on both the
array and the scalar spelling. So `skParam` addressing is not simply "the same
space with a different sign" for a non-ref parameter, and whatever the extra
ingredient is has to be found before this can be written.

Start by printing what the two symbols actually record —
`PXXDBG=a.symptr:<name>` is the existing topic for a pointer decl and the
nearest thing; a symbol-layout dump may be worth adding beside it, since this
ticket and its sibling both turned on "what does the symbol table actually say"
(`devdocs/dev/debugging-playbook.md`).

## Why it is a real bug and not a corner

It is the one arm of `absolute` that is neither correct nor refused. The other
three are settled: a local/global overlay works, a by-ref parameter works as of
today, a dynamic array is refused by name, and a local-over-global is refused by
name. This one compiles and lies.

## Gate

Track A's, plus the program above matching fpc 3.2.2 on x86-64 and one cross
target, and the by-value row added back to
`test/test_absolute_over_a_var_parameter.pas`, which deliberately omits it today
so the wrong answer is not frozen into a test.
