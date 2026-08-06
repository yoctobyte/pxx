---
summary: "Copy(a) on a dynamic array — FPC's whole-array shorthand — does not parse; pxx demands Copy(a, 0, Length(a)). It is the escape hatch users need once assignment aliases, so it blocks the dynamic-array semantics change"
type: bug
track: P
prio: 55
status: done
---

# `Copy(a)` on a dynamic array does not parse

- **Type:** bug — missing FPC surface. Track P (Pascal frontend).
- **Opened:** 2026-08-06, from the dynamic-array semantics review with the user.

## Symptom

```pascal
var a, b: array of Integer;
b := Copy(a);
```

    pascal26:5: error: unexpected token  (Expected: ,)

pxx requires the three-argument form. FPC accepts both.

## Measured, and narrower than it first looked

| form | FPC | pxx |
| --- | --- | --- |
| `Copy(a)` — dynamic array | ✅ | ❌ parse error |
| `Copy(a, 0, Length(a))` — dynamic array | ✅ | ✅ **deep-copies correctly** |
| `Copy(s)` — string | ❌ *rejected* | ❌ |
| `Copy(s, 1, 5)` — string | ✅ | ✅ |

Two things worth pinning down, because the obvious statement of this bug is
wrong in both directions:

- it is **not** "single-argument Copy is missing" — FPC rejects `Copy(s)` on a
  *string* too (measured: 4 errors). The shorthand is a dynamic-array feature
  only, and pxx matches FPC on strings already;
- the copying machinery is **not** missing. `Copy(a, 0, Length(a))` already
  produces a genuinely independent array (mutating the result leaves the source
  at `a[0]=1`). Only the whole-array shorthand is absent.

So the fix is a parse-level default: `Copy(a)` ≡ `Copy(a, 0, Length(a))` when
the single argument is a dynamic array.

## Why this is a prerequisite, not a nicety

[[decide-dynamic-array-value-vs-reference-semantics]] resolves toward FPC
reference semantics — assignment aliases, and `Copy` is how you ask for a
duplicate. **`Copy` is therefore the entire escape hatch.** Flipping x86-64 to
alias without this would remove the natural way to copy an array in the same
change that stops assignment from copying, which is a silent data-sharing
hazard for existing code.

Note the four cross targets (i386, arm32, aarch64, riscv32) **already alias**,
so they are in exactly that state today: FPC assignment semantics, no
`Copy(a)`.

## Gate

`Copy(a)` compiles and yields an independent array on every target; the 3-arg
form is unchanged; `Copy(s)` on a string still errors, matching FPC.

## Log
- 2026-08-06 — resolved, commit a855d1d5f.
