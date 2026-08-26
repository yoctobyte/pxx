---
slug: bug-p-a-char-array-argument-stopped-binding-a-string-parameter
title: "A char array argument stopped binding a string parameter"
track: P
prio: 70
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
resolved: 2026-08-26
commit: 7074e4e23
summary: "REGRESSION, mine, same day. The array-vs-scalar mismatch guard added for bug-p-overload-resolution-confuses-an-array-with-its-element-type refused an `array[..] of Char` argument to a `const q: string` parameter — a conversion the language defines. Caught by the Track T watcher as test-core#src:test/test_char_array_is_a_string.pas."
---

# What broke

`bug-p-overload-resolution-confuses-an-array-with-its-element-type` added a
mirror guard to `MatchArgRecMismatch`: an ARRAY argument does not bind a
parameter that is neither an array nor a pointer. That is right for the case it
was written for — an array binding a SCALAR parameter, which happened because an
array symbol's `TypeKind` IS its element kind, so a `array of Char` looked like
a `Char`.

It is wrong for the case the language defines: an `array[..] of Char` converts
to a string.

```pascal
function Wrap(const q: string): string;
var a: array[0..7] of Char;
begin a := 'hi'; WriteLn(Wrap(a)); end.
```

```
pascal26:7: error: no overload of Wrap matches these arguments
  argument types: (Char)
  candidates:
    Wrap(AnsiString)
```

The diagnostic betrays the model as well as the bug: the array reports as
`Char`, because that is what its symbol's TypeKind holds.

# Found by

The Track T watcher, in the `full` tier at `d3c1e87dce5b` — `pin-shadow.log`
had been naming it as one of "5 red(s) the current pin does not have" since
`70f6a360f475`, three commits after the guard landed. The quick gate does not
run `test_char_array_is_a_string`, which is why three of my own gated commits
went past it.

# Fix

The guard now exempts a char-array argument bound to a string-kind parameter:

```pascal
not ((MatchArgArrayElemTk[j] = tyChar) and
     (Procs[i].Params[j].TypeKind in [tyString, tyAnsiString, tyShortString,
                                      tyFixedString])) and
```

`MatchArgArrayElemTk` is new, filled beside `MatchArgArray` at the same site,
and holds the argument array's ELEMENT kind (which is its symbol's TypeKind).
An exemption keyed on the element type rather than on "is a string parameter"
generally, so an `array of Integer` still cannot bind a `string` parameter —
which is the defect the guard exists for.

# Verification

- `test/test_char_array_is_a_string.pas`: **86/86**, was refusing to compile.
- The three tests the guard was added for — `test_array_and_scalar_overload_binding`,
  `test_pointer_to_a_dynamic_array`, `test_string_typecast_is_a_cast` — all still
  match their fpc-generated `.expected` byte for byte.
- `tools/gate.sh quick` GREEN; conformance 346 pass / 0 fail, sets unchanged;
  fgl 7/7.

# Lesson

The guard was added as part of a ticket about ARRAY-vs-SCALAR confusion and was
written as "an array does not bind a non-array". Pascal has one standing
exception to that and the ticket's rows did not contain it. Varying the shape
means varying it against the LANGUAGE, not only against the defect.
