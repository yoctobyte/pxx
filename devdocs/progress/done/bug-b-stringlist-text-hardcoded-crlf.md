# TStrings.Text hardcoded CRLF, so SaveToFile wrote DOS line endings on Linux

- **Type:** bug — Track B (library), tag `compat` (FPC parity)
- **Status:** done
- **Resolved:** 2026-08-04 in `622a8a055` (verified on origin/master after the rebase)
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh`, new `sl-text` case, after widening it
  into classes/TStringList.

## Symptom

    l.Add('p'); l.Add('q');  l.Text

    FPC:  'p' LF 'q' LF          (4 bytes)
    pxx:  'p' CR LF 'q' CR LF    (6 bytes)

`TStrings.GetText` built its result with a literal `#13#10`.

## Why it survived

Three separate things hid it, which is worth recording because each is a
general trap:

1. **The two forms print identically.** The probe's own DIFF line showed
   `fpc=[p\nq] pxx=[p\nq]` — visibly the same string, reported as a divergence.
   Only `Length` and the character codes distinguish them. Eyeballing the
   probe output would have dismissed this as noise.
2. **`SetText` accepts either form** (it strips a trailing CR), so the
   round-trip `Text -> SetText -> Text` passes under the bug. Any test written
   as a round-trip — the natural way to test this property — proves nothing.
3. It is a *write*-side defect only, and nothing in-tree read the bytes back.

## Blast radius

`SaveToStream` (and so `SaveToFile`) is implemented as `buf := GetText`, so
every file written through a TStringList on this Unix host got DOS line
endings. That is the part that actually mattered; `Text` in memory was mostly
cosmetic.

## Fix

`lib/rtl/classes.pas` — use `LineEnding`, the compiler-known platform constant
(LF here, and it follows the target), matching FPC's `GetTextStr`.

## Test

`test/lib_strings_text.pas` — 11 byte-level assertions: length, a rendered
`<CR>`/`<LF>` form, absence of CR, the terminator after the *last* line, the
empty and single-line cases, and SetText's tolerance of both forms in both
directions. It compiles under FPC and every expectation was read off an FPC
build rather than reasoned about. 4 fail without the fix.

The round-trip case is kept deliberately and labelled as a **control**: it
passes under the old behaviour too, so it is there to show what the byte
assertions add.

## Filed while here

`bug-p-index-getter-backed-string-property` — `l.Text[i]` (indexing a
getter-backed string property) does not compile; the test uses a temporary.
Compiler gap, so filed rather than fixed.
