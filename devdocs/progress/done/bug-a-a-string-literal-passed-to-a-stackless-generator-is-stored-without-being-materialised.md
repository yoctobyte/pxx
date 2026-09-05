---
track: A
prio: 45
type: bug
blocked-by: []
status: done
found-by: frankS (boundary-testing the Variant-parameter fix)
summary: "A STRING LITERAL passed as an argument to a `generator; stackless;` routine is stored into the instance slot RAW, without the literal-to-handle materialisation every other call site performs -- so `Length(s)` in the body reads 1073741824 (2^30, a literal's refcount sentinel) instead of the length. An AnsiString VARIABLE argument works, which is the boundary: this is not `AnsiString parameters are broken`, it is `a literal never becomes a handle on this path`. PRE-EXISTING (identical on the pinned compiler), wrong value rather than a crash."
owner: ""
---

# A string literal passed to a stackless generator is stored without being materialised

## Repro and the boundary

```pascal
function Gen(s: AnsiString): Integer; generator; stackless;
begin yield Length(s); end;
```

| argument | pinned | HEAD |
| --- | --- | --- |
| `Gen('abcd')` — a LITERAL | `got=1073741824` | `got=1073741824` |
| `Gen(v)` where `v: AnsiString := 'abcd'` | `got=4` | `got=4` |
| `Gen(v)` where `v` was built by concatenation | `got=4` | `got=4` |

Both columns agree, so this predates `0f6b627d7` and is not caused by it.

**The variable rows are what make this filable as a narrow bug.** The first
measurement looked like "an AnsiString parameter of a stackless generator is
broken", which would have been a much larger and wronger claim.

## Mechanism, measured

The caller stores a pointer that looks entirely plausible:

```
SlSet(g, 48, val=0x429da0)
```

It is not a string handle. Read through it:

```
len at [0x429da0 - 8] = 1073741824      { 2^30 — a literal's refcount sentinel }
bytes at 0x429da0     = ""              { empty }
```

The same literal passed to a plain non-generator function arrives correctly:

```
plain F(s: AnsiString) got handle=0x410520, len at [-8] = 4
```

So the ordinary call path materialises the literal into a handle (the map has
`PXXStrFromLit` for exactly this) and the generator's slot-store path does not —
it stores the literal's own address, whose `[-8]` is the refcount word rather
than a length.

`1073741824` is a value worth recognising on sight here: it is not a corrupted
length, it is the field that sits where the length would be if the pointer were
a handle.

## Why it is separate from the Variant and `var` defects

Those two are one concept answered inconsistently at the two ends of the slot
("value or address?"). This one is not about the slot at all — the slot faithfully
carries the word it was given. The defect is that the ARGUMENT was never
converted into the representation the parameter's type requires, before anyone
stored anything. Fixing either of the others cannot fix this.

## Not verified

- Whether other literal-typed arguments (a set constructor, a `ShortString`
  literal, a char literal widened to a string) have the same gap. Only an
  AnsiString literal was measured.
- Whether the missing step is `PXXStrFromLit` specifically, or a more general
  argument-coercion pass the for-in desugar bypasses. The symptom is consistent
  with either.

## 2026-09-06 (frankS) — FIXED, `5377f1b60`

`GenMakeStrArgTemp` assigns the argument through an AnsiString local of the
function containing the for-in, which does the materialisation the ordinary call
path does — and, because the local is a real managed variable, RETAINS the
string for the whole loop. Storing a bare handle into an untracked slot never
did that; the literal case only ever failed loudly because a literal's refcount
word sits where a length would be.

| argument | pinned | HEAD |
| --- | --- | --- |
| `Gen('abcd')` — LITERAL, read twice | `1073741824 -2147483648` | `4 8` |
| `Gen(v)`, `v: AnsiString := 'abcd'` | `4 8` | `4 8` (unchanged) |
| `Gen(v)`, `v` built by concatenation | `4 8` | `4 8` (unchanged) |
| all five parameter kinds in one signature | crashes before this row | `1 10 4 40 5` |

The two unchanged rows are the point, not padding: they are what makes the fix
narrow. Without them the honest claim would have been "AnsiString parameters are
broken", which is what the first measurement looked like and is false.

**This was the only one of the three group defects that is NOT a slot
disagreement.** The Variant and by-ref rows were both "does this slot hold the
value or its address", answered inconsistently at the two ends and therefore
able to fail in either direction. Here the slot faithfully carried the word it
was handed; the ARGUMENT was never converted into the representation its
parameter's type requires, before anyone stored anything. That is why neither of
the other two fixes touched it and it touched neither of them.

### The row worth keeping

`test_stackless_gen_string_param.pas` ends with a generator taking a Variant, a
record, an AnsiString, a scalar `var` and an ordinal in ONE signature — five
parameter kinds, five different rules about what the slot holds, all of which
the caller and the generator must agree on independently. **That single row
fails on the pinned compiler for all three defects in this group at once.** The
group was found the other way round, one defect at a time, by widening a repro
until it broke differently.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1382b59a1.
