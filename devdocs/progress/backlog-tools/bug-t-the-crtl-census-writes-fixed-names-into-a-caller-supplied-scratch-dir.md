---
track: T
prio: 40
type: bug
blocked-by: []
summary: "crtl_declaration_census.sh writes FIXED names ($TMP/crtl_census.c, .log and the binary) into a caller-supplied tmpdir, and its verdict is `grep -q 'does not define' $LOG`. Two concurrent invocations sharing TESTTMP have one grepping the other's log and one exec'ing a binary the other is rewriting. NOT the cause of the 2026-09-17 lib-test#55 red -- that was the pinned compiler and is fully explained (red under pin v410, green at HEAD, cleared by pin v411) -- so this is filed as a live hazard on its own evidence, not as a diagnosis of that failure."
status: unfinished
owner: unassigned
---

# The crtl census collides with itself in a shared scratch dir

`test/crtl_declaration_census.sh` takes its tmpdir from the caller
(`Makefile:35714` passes `$(TESTTMP)`) and writes three FIXED names into it:

    SRC=$TMP/crtl_census.c
    BIN=$TMP/crtl_census
    LOG=$TMP/crtl_census.log

No `mktemp`, no per-job suffix, no lock. The verdict is then

    if grep -q 'does not define' $LOG; then

so a second invocation sharing that `$TMP` gives one run's grep the other run's
log, and `$BIN` is executed while the other run may be rewriting it — which
produces "compiled clean, then no stdout", with no error anywhere.

## Why this is filed WITHOUT a reproduction

It would be easy to attach this to the lib-test#55 red of 2026-09-17 and wrong.
**That red is fully explained by something else**: the row runs `$(PXX_STABLE)`,
pin v410 predates `984be7e19`, and the pinned compiler genuinely did not define
`c_pthread_create`. It reproduces **alone, in a fresh `mktemp -d`, with nothing
else running** — so contention had no part in it.

What is claimed here is only what the source shows: fixed names in a
caller-supplied directory, with no exclusion. Whether the tier ever runs this
script twice concurrently is **not measured** and is the first thing to check —
if it does not, this is latent rather than live, and the fix is still cheap.

## Positive control the fix needs

A guard here must be able to FAIL, and the honest control is two deliberately
concurrent invocations against one `$TMP`, asserted to both pass. Run against
the CURRENT script first: if that does not fail, the hazard is latent and the
ticket should say so rather than being closed as fixed.

## The fix

`TMP=$(mktemp -d "$2/crtl_census.XXXXXX")` — keep the caller's directory as the
PARENT so the harness still controls placement and reaping, and make the three
names unique per run. Do not add a lock; there is no reason these runs need to
serialise, only to stop sharing names.
