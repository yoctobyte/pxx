
---

## RESULT 2026-08-31 (frankB) — 13.8% off a self-compile from two lines, and the call-site plan is WRONG

Landed `4b3d34f74` (verified on origin/master by merge-base, not by a pre-push
`log -1`). **21.650s -> 18.673s**, min-of-5 interleaved, base `101c9a7ea8b0`
vs mod `a5ca167411d8`, load 6.46 start / 6.17 end. Distributions do not overlap:
the *worst* modified run (20.193) beats the *best* baseline run (21.650). Output
byte-identical — both binaries compiled `compiler.pas` and `cmp` says same file.

### The plan in the section above was wrong, and this is how

frankB attributed AppendChar's **callers** instead of converting sites by
density. 70 samples: 18 have `AppendChar` on the stack and **seventeen of the
eighteen come from ONE site** — `GetTokenStr` at `ast_syminfer.inc:183`. Not
`cpreproc`'s 72, not `pyparser`'s 53.

**The density ordering was a census of the SOURCE and would have delivered zero
for a long while**: `cpreproc.inc` is the C preprocessor and does not execute at
all during a Pascal self-compile. That is constraint 1 of this ticket —
*measure, do not count* — firing on the brief that carried it. The brief stated
the rule and then supplied a count-based work order in the next paragraph.
**Recorded rather than quietly corrected, because the failure is more
instructive than the fix.**

### The fix was already written, on the twin

`lexer.inc:641 GetTokenStrFromRaw` is the same function done right — one
`SetLength`, one fill out of `TokChars` — carrying a comment saying it was
changed *because* char-at-a-time was O(n^2) per token. `ast_syminfer.inc:183
GetTokenStr` is its twin and was missed. The arm that got fixed was the cheap
one; the expensive one is what every parser goes through.

Textbook `devdocs/dev/normalise-dont-special-case.md`: **fix one arm of a double
case, grep for the sibling before closing.** That grep was not done, and the
sibling stayed broken for however long — which is precisely the doc's stated
prediction about second paths.

**Not a Pascal-only win:** `GetTokenStr` is how token text is read at 570+ sites
across all frontends, `pyparser` alone calling it 314 times.

Gate: fixedpoint converged 1 round (`49361be30484`), `gate.sh quick` green, plus
one-line canaries for NilPy, C, Rust, Zig and Pascal — correctly, since the
fixedpoint is blind to four of the five and this function serves all of them.

### A method note that is this repo's own failure family

frankB's first aggregation script reported `AppendChar` **nowhere** and
confidently blamed `ParseProgram`. The regex required `funcname ()` and every
`AppendChar` frame carries arguments — so **the instrument structurally could
not see the one symbol it was aimed at, and printed a clean, plausible
ranking.** Same shape as the dotted-`random\.seed` grep that produced a wrong
census earlier the same day: *the instrument was correct about something else.*
Caught only because "AppendChar absent from an AppendChar profile" was too
convenient to believe.

### Corrections to the file list above

- `asmenc.inc` has **42** AppendChar sites — more than `elfwriter.inc`'s 38 —
  and was missing from the density ordering entirely (verified: 42). Hotness
  untested.
- Next candidates from the same 70 samples: `ExpandPasMacros` /
  `ExpandIncludes` / `IncEmitLineMarker` in `elfwriter.inc` (5/70), genuine
  per-char loops that already know their span, so `AppendRange` applies cleanly.
- **Do not start anyone on the cpreproc/pyparser conversion.** It is not
  supported by any measurement and the one measurement taken points elsewhere.
