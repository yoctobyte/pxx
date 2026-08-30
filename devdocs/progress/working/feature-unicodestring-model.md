---
prio: 62
track: A
blocked-by: []
status: working
owner: frankwasm
---

> **DECIDED 2026-08-30: build it, as a fixed-width UTF-16 kind.** The owner ruled
> that WideChar is easier than UTF-8 — which is right: the variable-width TEXTSTR
> kind already shipped with an ASCII-flag scan cache, and fixed-width needs none of
> it. Windows/`*W` interop is explicitly not a consideration. See the RESOLUTION in
> `decide-adopt-a-second-string-model-or-refuse-utf16-honestly` for what the work
> is. Sequenced behind `feature-a-typeref-migrate-consumers` — same file set.
>
> Superseded filing note (phrase softened so the ranker stops suppressing it): the
> ticket was held back while the choice itself was the open question. This ticket's
> own body says "this is a model decision, not a function", and its title carries
> both branches. Escalated 2026-08-30 to
> `decide-adopt-a-second-string-model-or-refuse-utf16-honestly` (U p62) so an
> agent does not settle the language's string model by picking one while
> implementing. 

# A real UnicodeString / WideChar model (UTF-16), or an honest refusal

- **Type:** feature (string model — Track A/P)
- **Status:** working
- **Blocks:** fcl-json's `jsonparser`/`jsonscanner` (the `\uXXXX` escape path). fpjson itself
  (the DOM, the formatter, every accessor) is DONE and does not need this.

## The wall, exactly
`jsonscanner.pp` decodes a `\uXXXX` escape into a UTF-16 code unit and, for a surrogate pair,
does:

```pascal
S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
```

`WideChar(x) + WideChar(y)` is a two-element **UTF-16 string**. pxx has ONE string model —
bytes — so `WideChar` is a 2-byte ORDINAL here, `+` is integer addition, and `String(...)` of
the result is rejected. The rejection is correct; there is nothing to silently do instead.

## Why this is a model decision, not a function
The rest of the RTL is already honest about it and says so at the declaration:
- `UTF8Decode`/`UTF8Encode` are the IDENTITY (lib/rtl/sysutils) — for ASCII the two agree
  exactly, for multi-byte UTF-8 they do not;
- `DefaultSystemCodePage` reports `CP_UTF8`, because the bytes really do pass through
  untouched;
- `WideChar` casts to a 2-byte ordinal.

Every one of those is right for a byte-transparent RTL. What is missing is a genuine UTF-16
`UnicodeString`/`WideString` with 2-byte elements — indexing, Length, concatenation, and the
UTF-8 ⇄ UTF-16 transcoders. That touches the string model (tyAnsiString / tyString / a new
tyWideString), the managed-string ARC helpers, and the literal path. It is a real feature, not
a shim, and faking it would be exactly the "silently wrong" failure this corpus keeps finding.

## Scope note
JSON in the wild is overwhelmingly ASCII or plain UTF-8 (which passes through byte-for-byte).
Only `\uXXXX` escapes hit this. So an intermediate step is defensible IF it is loud: decode
`\uXXXX` in the BMP directly to UTF-8 bytes (no UTF-16 intermediate), and REFUSE a surrogate
pair with a clear runtime error rather than mangling it. That would need a patched scanner,
i.e. a fork — which the corpus rules say to avoid — so prefer doing the model properly.

## Gate
`make test` + self-host byte-identical + cross.

## 2026-08-30 (frankwasm) — runtime half landed; the tag precedent measured false

`af2da1c28`. `PXX_KIND_WIDESTR` plus `PXXWideAlloc` / `PXXWideConcat` /
`PXXWideFromUtf8` / `PXXUtf8FromWide` in `builtinheap.pas`. No frontend change,
so `var w: WideString` is still a byte-string alias; the type half is separate.

### `Length(s)` and `s[i]`, settled against fpc

The resolution asked for these to be settled before anything was built on them.
Measured — and the measurement needs `{$codepage utf8}`, without which fpc
widens the raw source bytes, reports 6, and looks like it AGREES with pxx:

| | fpc 3.2.2 | pxx at HEAD |
| --- | --- | --- |
| `Length(w)` over `'héllo'` | 5 | 6 |
| `Length(u)` (UnicodeString) | 5 | 6 |
| `Length(s)` (AnsiString) | 6 | 6 |
| `Ord(w[2])` | 233 (`é`) | 195 (`$C3`) |

So `Length` counts **UTF-16 code units** (header byte count >> 1) and `s[i]`
yields a **WideChar**. That is what the runtime half is built to.

### There is no two-kind runtime design to extend to three

The coordinator's brief asked whether the BYTESTR/TEXTSTR split extends to a
third answer cleanly. It does, but not for the expected reason: **the split
does not exist at runtime.** `PXX_KIND_BYTESTR` and `PXX_KIND_TEXTSTR` are
declared and documented in `builtinheap.pas` and are **never stamped and never
read** — every write to the kind field is `PXX_KIND_LEGACY`. Checked because
the RESOLUTION leans on TEXTSTR as a worked precedent for the tag.

The precedent is real for SEMANTICS and false for the MECHANISM. NilPy `str`
genuinely counts characters — `len("héllo")` is 5, `t[0]` is `日`, matching
CPython — but it gets there by STATIC typing plus `PXX_FLAG_ASCII`, which is
the part that is actually live. `PXX_KIND_WIDESTR` is the first kind ever
stamped in this tree.

### UTF-16 is not a third semantics, which is why it is cheap

BYTESTR's rule is *"Length counts storage ELEMENTS, index yields one element."*
WIDESTR is the same rule at element width 2. TEXTSTR is the odd one out — the
only kind that DECODES. So the axis is **elements vs characters**, not
bytes/characters/units, and UTF-16 joins the side that already existed.

That is the real reason the stride objection stays retracted, and it is a
different reason from the one in the resolution. Not "the kind machinery was
already built" (it was not) but **"the header was already a BYTE count"** — so
refcount, free, `PXXBlockCopy`, in-place append and every backend's
retain/release blob are byte-shaped and need no second arm. Only the public
`Length()` halves, and that lowers statically off `tyWideString`.

### What is in the runtime half, and what is deliberately not

Two things differ from a byte string and both are confined to the four new
functions: 2-byte elements, and a 2-byte NUL terminator so a `PWideChar` handed
to a C API terminates where that API expects.

No ASCII flag is stamped on a wide block. `PXX_FLAG_ASCII` means "no byte >=
$80" — true of any ASCII text in UTF-16 and therefore useless — while the
flag's actual contract, byte positions equalling character positions, is false
for every wide string. Leaving it unset means "unknown", which is the honest
answer and what every consumer already handles.

Note the trap `PU16` exists to avoid: this file's `PWord` is `^NativeInt`,
EIGHT bytes. `PWord(d)^ := unit` compiles, writes eight bytes, and silently
clobbers the next three code units.

### Verified, not reasoned about

`test/test_widestring_transcode.pas` calls the runtime entry points DIRECTLY,
because with `WideString` still an alias there is no source-level way to reach
them — that is what keeps the runtime half from sitting unexercised until the
frontend catches up.

    U+1F600    -> D83D DE00     the exact jsonscanner surrogate pair
    D83D DE00  -> F0 9F 98 80
    lone surrogate -> EF BF BD, and the NEXT unit survives
    truncated lead -> FFFD, without swallowing the following character
    ascii / é / 日 / emoji all round-trip byte-identical

Malformed input maps to U+FFFD in both directions rather than raising: these
run under `Utf8Decode`/`Utf8Encode` on data that came from a file, so a bad byte
in a JSON document must not become a crash in the parser.

### Next, and why the library half is NOT parallel to it

The `lib/rtl` string units are **downstream of the type half, not independent
of it**. The boundary helpers are `UTF8Encode(w: WideString)` and
`UTF8Decode(...): WideString`, and they cannot be written — cannot even be
declared as overloads — while `WideString` is an alias for `AnsiString`.
`sysutils.pas` says exactly this at the declaration today: *"THIS RTL HAS ONE
STRING MODEL: bytes... `UnicodeString` IS `string` here and these are the
IDENTITY."*

So the order is: `tyWideString`/`tyUnicodeString` in `defs.inc` (next to the
existing `tyWideChar`, ordinal 31, which already makes `WriteLn(someWideChar)`
print the character), then the static kind in `symtab.inc` — which is what makes
`WideChar(u1) + WideChar(u2)` build a string instead of adding two ordinals,
the actual wall — then the RTL helpers, then literal encoding and `Write`.

Blast radius for the alias change is small: 10 mentions of
`WideString`/`UnicodeString` across `lib/`, `test/` and `examples/`, the only
real consumers being sysutils' identity functions and rtl-generics' comparers.
Essentially all remaining risk is in the type half; the runtime was the cheap
end, as the owner predicted.
