---
track: U
prio: 55
type: decide
summary: "NilPy strings are BYTES where CPython's are code points: len('héllo')==6, s[1] is half a character, and s[::-1] silently produces invalid UTF-8. Decide the target — full code-point str, UTF-8-aware indexing over the byte buffer, or a documented ASCII-only limit"
---

# Is a NilPy `str` a byte string or a sequence of code points?

- **Type:** decide (design fork) — **Track U**
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`. Escalated rather
  than guessed: the divergence is not in doubt, the *target* is.

## Measured (self-hosted fixedpoint at `8f1852f27`)

```python
s = "héllo"
t = "日本語"
```

| expression | CPython | pxx |
| --- | --- | --- |
| `len(s)` | `5` | `6` |
| `s[1]` | `é` | `\xc3` — **half a character, invalid UTF-8 on stdout** |
| `s.find("l")` | `2` | `3` |
| `s[0:3]` | `hél` | `hé` |
| `s[::-1]` | `olléh` | `oll\xa9\xc3h` — **byte-reversed, invalid UTF-8** |
| `s.upper()` | `HÉLLO` | `HéLLO` (ASCII-only case mapping) |
| `len(t)` / `t[0]` | `3` / `日` | `9` / `\xe6` |
| `ord("€")` | `8364` | `TypeError: ord() expected a character, but string of length 3 found` |

Byte-level and code-point-level answers happen to **agree** for `in`, `count`,
`split`, `==` and `+`, so a probe built only from those is blind to this.

## This is a defect, not a divergence to document

Worth stating plainly because the tuple-mutability precedent in
`devdocs/dev/nilpy-semantics-divergences.md` does not extend here. That page's
test is whether a program CPython *accepts and runs* can observe the
difference. Ordinary working CPython code — anything slicing, indexing, or
measuring text that is not pure ASCII — observes every row above, and `s[::-1]`
does not merely answer differently, it **emits corrupt output**. So the *whether*
is settled by the upward-compatibility rule; only the *what to build* is open,
which is why this is a `decide-` and not a `bug-`.

## The fork

1. **Full code-point `str`.** Match CPython exactly: `str` becomes a sequence of
   code points, with a separate `bytes` type. Correct and complete, and the only
   option that makes `ord`/`chr` and case mapping right in general. Also by far
   the largest: it touches the string representation NilPy shares with the
   Pascal `AnsiString` substrate, so it is not confined to Track N.
2. **UTF-8-aware indexing over the existing byte buffer.** Keep the storage as
   UTF-8 bytes; make `len`, indexing, slicing and `find` count characters by
   decoding. Correct for every row above except case mapping, and confined to
   the NilPy string helpers. Cost: indexing goes O(n), which matters for
   `while i < len(s): s[i]` loops — the shape NilPy code actually writes.
   Mitigable with an ASCII fast path (a flag or a scan), since most strings are
   ASCII and stay O(1).
3. **Document an ASCII-only limit and make the failures loud.** Cheapest, and
   honest, but it leaves working CPython programs unsupported, and the
   corrupting cases (`s[1]`, `s[::-1]`) would need to *raise* rather than emit
   bad bytes to be defensible at all.

## Recommendation

**Option 2**, with an ASCII fast path, and option 1 kept as the long-term shape
if a `bytes` type is ever wanted for its own sake. It fixes everything a real
program hits, stays inside Track N's files, and does not disturb the Pascal
string substrate — where option 1 would land squarely on Track A's shared
ground for a benefit no Pascal program is asking for.

Independent of the choice, the corrupting rows are the urgent part: `s[1]` and
`s[::-1]` writing invalid UTF-8 to stdout is worse than an error, under any of
the three options.

## Whichever way this goes

`ord()` on a multi-byte character should stop reporting *"expected a character,
but string of length 3 found"* — under option 3 that message is at least
truthful about the limit, but under 1 or 2 it is simply the bug.

Related: [[bug-nilpy-a-tuple-returned-from-a-lambda-becomes-a-list]] and
[[bug-nilpy-a-lambda-call-is-not-arity-checked]] came from the same sweep and
are independent of this one.

## RESOLVED 2026-08-07 — superseded, and the answer is recorded elsewhere

This fork is **decided** and the decision lives in
[[feature-nilpy-text-string-kind]], whose header states it:

> a NilPy `str` is a sequence of CODE POINTS; a Pascal `AnsiString` stays
> BYTES; they are two kinds of one representation, not one type.

with the implementation plan (kind word in the managed-block header, character
counting for len/index/slice/find/reverse over the shared byte substrate, ASCII
flag keeping the common case O(1)), and refinements committed the same day —
`s[i]` stays TYPED as UCS4Char rather than becoming an interned 1-char string.

Moved out of the ready queue because it was still being surfaced to the user as
an open question after it had been answered — the ticket that supersedes it did
not close it. **If a decision is superseded by a feature ticket, move it here at
the same time**, or the U queue keeps asking.
