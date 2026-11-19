---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`@s[i]` on a string variable assigned a STRING LITERAL answers the LITERAL's address, not the variable's. Three variables assigned 'abcd' — two shortstrings and an AnsiString — all report `@x[1]` = the same address, where fpc reports three. The VALUES are independently correct (`f[1] := 'Z'` leaves the others alone), so the storage is separate and only the address is wrong: taking the address of a string element does not uniquify the string. Every consumer that merely READS through it gets the right characters, which is why this has survived; a consumer that WRITES through it corrupts every other variable holding that literal."
status: done
owner: claude-dupwt
---

# The address of a string element is the literal's address

- **Found:** 2026-09-06 (frankS), building the open-array slice `a[lo..hi]`
  ([[feature-pascal-corpus-fpc-testsuite]], tarray7). The slice's `var` copy-out
  WRITES through `@s[lo]`, which is what made a read-only wrong answer visible.
- **Measured at compiler `d52be707f9cd`** against fpc 3.2.2. No slice in the
  repro — this is reachable from plain Pascal.

```pascal
var f: string; g: AnsiString; h: string;
begin
  f := 'abcd';  g := 'abcd';  h := 'abcd';
  WriteLn(PtrUInt(@f[1]), ' ', PtrUInt(@g[1]), ' ', PtrUInt(@h[1]));
  f[1] := 'Z';
  WriteLn(f, ' ', g, ' ', h);
end.
```

|  | `@f[1]` | `@g[1]` | `@h[1]` |
| --- | --- | --- | --- |
| **pxx** | 4265208 | **4265208** | **4265208** |
| fpc 3.2.2 | 4384833 | 4341800 | 4385105 |

Both print `Zbcd abcd abcd` for the values. **The storage is separate and the
address is shared** — a variable assigned a string literal reports the literal's
address as its own.

A string built at runtime rather than from a literal reports correctly
(`f := ''; f := f + Chr(...)` gives two distinct addresses for `f` and `g`), so
the defect is specific to the literal assignment, not to `@` over strings.

## Why it has survived

**Every reader through this address gets the right characters.** `PChar(@f[1])^`
is `'a'`, `StrLen`, `Move` out of it, printing it — all correct, because the
literal holds exactly the characters the variable holds until something writes.
The wrong answer only becomes an observable when someone WRITES, and then it is
not a wrong value at the write site: it is a wrong value in **every other
variable that happens to hold the same literal**, arbitrarily far away.

That is also why an assertion on the string itself cannot catch it. `f` reads
back what was written, because `f` reads through the same wrong pointer. Only a
SECOND variable holding the same literal separates them — which is a fixture
nobody writes unless they already suspect this.

## What it blocks

The string half of the open-array slice: `uppercase(f[1..10])` and its
AnsiString twin, the last two rows of fpc-testsuite `tarray7.pp`. Those are
refused by name in `IRLowerCallArg` and cite this slug; the array, dynamic-array
and typed-pointer bases are landed and correct.

**And it produced a false green on the way.** With the string base enabled,
tarray7 exits 0 — it slices `f[1..10]`, the WHOLE string, so the write went to
the literal and was read back from the literal, self-consistently. `f[2..5]` in
a hand-written test is what separated them. A row that asserts values can still
be asserting them about the one case whose bounds cannot be wrong.

## Gate

Two variables assigned the same literal, `@x[1]` distinct for each, and a write
through one leaving the other unchanged — asserted as a RELATION (`@f[1] <>
@g[1]`) rather than as addresses, so it carries no per-target constant.

## Neighbour

FPC calls `UniqueString` where a string's element address is taken or the string
is passed by reference; the shape of the fix is likely that, at the point `@s[i]`
is lowered, rather than anything about the literal.


# Closed 2026-11-19 (claude-dupwt): not a defect; the repro compared two string models

The repro has no `{$H+}`, so in fpc's default mode `string` is a 256-byte
ShortString. Each variable owns its characters, and fpc reports three addresses.
pxx's bare `string` is the managed string (SizeOf 8), which is the documented,
chosen divergence in devdocs/dev/type-identity-side-channel.md ("the
managed-string model this compiler chose"). So the comparison was ShortString
in fpc against AnsiString in pxx.

Measured at ca6f1a7213 against fpc 3.2.2, one program with
`f: string; g: AnsiString`, both assigned 'abcd', comparing `@g[1] = @f[1]`:

| | SizeOf(f) | @f[1] = @g[1] |
| --- | --- | --- |
| fpc, default mode | 256 | FALSE |
| pxx, default | 8 | TRUE |
| fpc, `{$H+}` | 8 | **TRUE** |
| pxx, `{$H+}` | 8 | TRUE |
| pxx, `{$H-}` | 256 | FALSE |

So pxx and fpc agree whenever they agree on the type. Under `{$H+}` fpc also
returns the shared literal's address, because `@s[i]` does not uniquify an
AnsiString in fpc either. Writing through it (`p := @h[2]; p^ := 'X'`)
crashes fpc with runtime error 216 on the read-only literal, as it does in pxx.
For explicit ShortStrings, `@f[1]` is the variable's own storage (offset 1 from
`@f`) in both compilers, and a write through it changes only that variable.

The string-slice refusal in ir.inc that cites this ticket ("A STRING BASE IS
REFUSED") stays. A slice's `var` copy-out WRITES through `@s[lo]`, and for a
managed string that write would land in a shared literal, so keeping the
refusal is still right. Lifting it would need a uniquify before the copy-out,
which is a separate feature with no caller today.
