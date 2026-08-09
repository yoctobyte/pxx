---
owner: claude-B
---

# TStrings.CommaText / DelimitedText are missing

- **Type:** feature gap — Track B (library), tag `compat`
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh`, `sl-commatext` case.
- **prio:** 30

## Symptom

    error: "CommaText": no such member on this record/class

FPC's `TStrings` has `CommaText`, `DelimitedText`, `Delimiter`,
`QuoteChar` and `StrictDelimiter`. pxx's has none of them.

## Notes for whoever takes it

The quoting rules are the whole job and they are not obvious — FPC quotes a
value that contains the delimiter, whitespace or the quote char, doubles an
embedded quote, and `StrictDelimiter` changes whether whitespace alone
triggers quoting. Read them off an FPC build case by case rather than
implementing from the description; `tools/fpc_diff_probe.sh` is set up for
exactly that and already has the `sl-commatext` case waiting.

Round-tripping (`l.CommaText := l.CommaText`) is the property worth testing,
but note it can pass while both directions are wrong in matching ways — assert
the literal string too, as `test/lib_strings_text.pas` does for `Text`.

## Resolution 2026-08-09 (Track B)

`Delimiter`, `QuoteChar`, `StrictDelimiter`, `DelimitedText` and `CommaText` on
`TStrings`, over one shared engine that takes the delimiter/quote/strictness as
parameters — `CommaText` is that engine pinned to `,` / `"` / non-strict, which
is why reading or writing it does not disturb the properties (measured: after a
`CommaText` get, `Delimiter` was still `;`).

**The ticket's warning was exactly right, and the round-trip caveat it adds is
the part that earned its keep.** Written from the description, two rules came out
wrong:

    "a"b   ->  FPC gives TWO items <a> <b>   — the closing quote ENDS the item
    a"b"   ->  FPC gives ONE item <a"b">     — a quote mid-item is a literal

Both produced `<ab>` instead, **and both round-trip cleanly**, so
`l.CommaText := l.CommaText` passes while both directions are wrong in matching
ways — precisely the failure the ticket predicted. Only the adversarial inputs
caught it. The rule is: the quote is special ONLY at the start of an item.

Other rules that are not guessable and are now pinned:

- an empty item writes as nothing (`a,,b`), EXCEPT a list of exactly one empty
  string, which writes `""` so it stays distinguishable from an empty list;
- unless `StrictDelimiter`, WHITESPACE ALSO SEPARATES — `a b,c d` parses to
  four items — and a run of whitespace plus at most one delimiter is a single
  separator, which is what makes `a, b` two items rather than three;
- `CommaText` ignores `StrictDelimiter` even when it is set.

Verified by diffing three probe programs against an FPC build until byte
identical, then folding all 43 lines into `test/lib_commatext.pas` (in
`make lib-test`) as literal expected output. Re-introducing the description-level
bug in a scratch RTL makes the test report those two lines and nothing else,
so it is pinned rather than merely passing.


## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
