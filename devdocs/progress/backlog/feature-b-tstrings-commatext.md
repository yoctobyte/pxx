# TStrings.CommaText / DelimitedText are missing

- **Type:** feature gap — Track B (library), tag `compat`
- **Status:** backlog
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
