---
track: T
prio: 45
type: feature
status: backlog
found: 2026-09-04
found-by: frankA (closing regression-test-core-test-rtti-reg); framing pushed by frankuser
owner: ""
blocked-by: []
summary: "A type alias copied out of lib/rtl into a test or a demo has no link back to its original, so when the original is migrated the copy silently keeps the old meaning and nothing reports it. MEASURED: lib/rtl/typinfo.pas moved `TRttiStr = string[255]` to `string[256]` on 2026-09-04, deliberately and with a comment predicting the exact symptom if it were not moved -- because `string[N<=255]` was about to become the byte-prefixed tyShortString. test/test_rtti_reg.pas held a duplicate `TRttiStr` and was not moved with it, so a byte-prefix reader was pointed at a word-prefixed blob: length right (the little-endian low byte), name taken from the prefix's own zero bytes. It stayed green for a further day because an unrelated deref bug was reading 8 bytes regardless of the declared kind, and reddened only when THAT was fixed -- so the bisect named the fix, not the cause. Fixed for the one instance with a `SizeOf(TRttiStr) <> 264 -> Halt(1)` guard in the test. THE CLASS IS UNADDRESSED: nothing enumerates aliases that were copied from an RTL declaration, and nothing notices when the two stop agreeing."
---

# A type alias copied from the RTL can drift, and nothing reports it

## What makes this different from ordinary duplication

The copy is not wrong when it is made — it is *identical*. It becomes wrong
when the original moves, and the move is often the CORRECT and carefully
reasoned act. typinfo.pas's comment is a model of its kind: it names the
boundary, explains that the cap is a kind selector rather than a length, and
says "do not tidy this back to 255". **All of that reasoning was written into
the file that did not need it**, because the file that did need it was not
known to be related.

## Why the obvious instruments miss it

- **grep** finds `TRttiStr` in both files and reports agreement — before the
  migration. Nobody greps again afterwards.
- **the compiler** sees two independent, well-formed declarations. Neither is
  an error; they are simply different types with the same name in different
  units, which is legal and often intended.
- **the test suite** is the instrument that should catch it, and here it did
  not for a day, because a second defect was masking the first (see
  `done/regression-test-core-test-rtti-reg`).
- **the bisect** actively misleads: it names the commit that removed the mask.

## Shape of a fix — not decided, and the cheap end may be enough

1. **A declared link.** A convention like `{ COPY-OF lib/rtl/typinfo.pas
   TRttiStr }` above a duplicated alias, plus a checker that re-reads the named
   declaration and compares. Cheap, opt-in, and only as good as the annotation
   rate — but the annotation is written at the moment someone copies, which is
   the moment they know.
2. **A census by shape.** Enumerate `X = <type expression>` in `test/**` and
   `examples/**`, look for the same identifier declared in `lib/rtl/**`, and
   report pairs whose right-hand sides differ. No annotation needed; will have
   false positives where a test deliberately declares a DIFFERENT type of the
   same name, which is a real and legitimate pattern.
3. **Neither, and instead make the property assertable.** The one-instance fix
   was `SizeOf(TRttiStr) <> 264 -> Halt(1)`. That is not a class fix, but it is
   worth noting that the *property* the test depended on was checkable in one
   line and nobody had written it down.

**Do not start with (2) alone.** It reports a set whose members are mostly fine;
per the handbook, a guard that flags everything is as empty as one that never
fires. Whichever way this goes, it needs a POSITIVE CONTROL drawn from this
population: re-run it against the 2026-09-04 tree with `test/test_rtti_reg.pas`
put back to `string[255]`, and require that it names that pair.

## Scope

`test/test_rtti_reg.pas` was the one live instance found. It was found by a
regression, not by looking — **the population has not been enumerated**, and
that enumeration is most of the value here regardless of which fix is chosen.
Do not read "one instance" as "one instance exists".

Related: [[regression-test-core-test-rtti-reg]] (the instance and its guard).
