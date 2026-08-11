---
track: C
prio: 45
type: bug
summary: "Every C program that includes <math.h> now emits 2-3 'disagrees with the Pascal routine' warnings, for symbols crtl DEFINES itself. The warning describes a resolution that is correct — binding the C declaration — so it is pure noise on every math-using compile"
status: done
---

# The mismatch warning fires even when crtl owns the symbol

- **Type:** bug (diagnostic noise) — Track C (C name resolution / diagnostics)
- **Opened:** 2026-08-09
- **Filed by:** Track B. My own change caused the volume, so this is my mess to
  report even though the fix is not in my lane.

## Symptom

```c
#include <math.h>
#include <stdio.h>
int main(void){ printf("%g\n", floor(2.5)); return 0; }
```

```
warning: C declaration of 'floor' disagrees with the Pascal routine 'Floor' on
         the result type (float vs non-float) — binding to the C declaration
warning: C declaration of 'ceil'  disagrees ... — binding to the C declaration
warning: C declaration of 'nan' does not match the Pascal routine 'NaN' which
         takes 0 parameter(s), not 1 — binding to the C declaration
```

Three warnings for a five-line program. A C program that does not include
`<math.h>` is clean, so this is on every math-using C compile — which is most of
the corpus (`lua`, `quickjs`, `cJSON`, `zlib`, `tcc`).

## Why it is noise rather than a signal

The warning is *accurate* and its resolution is *correct*. What it is missing is
that the disagreement is now INTENTIONAL and already resolved properly:

- `lib/rtl/math.pas`'s `Floor`/`Ceil` return `Integer`, because FPC's do
  (`bug-b-fpc-numeric-compat-...`).
- `lib/crtl/src/math.c` defines its OWN `floor`/`ceil` returning `double`,
  because C's do — added when the mismatch first bit
  (`regression-b113-floor-ceil-change-pulls-libm-into-system-libs-c`).

Two languages, two contracts, each implemented on its own side. "Binding to the
C declaration" is exactly right here, and it binds to crtl's body — verified:
that regression test now shows `libc.so.6` present and `libm.so.6` ABSENT.

`nan` is the same shape and predates my change: crtl defines `nan(const char *)`
and the Pascal `NaN` is paramless.

## Suggested fix

Do not warn when the C side has a DEFINITION for the symbol — only when the
mismatch would silently route a call somewhere surprising. The warning exists
for the case where a Pascal routine quietly captures a C call
([[bug-c-pascal-math-names-hijack-libc-through-pxxcio]] is the real hazard, and
notably it is SILENT because those collisions have matching arities). Firing
when crtl owns the body inverts that: it is loud where things are fine and quiet
where they are not.

If suppressing entirely is too broad, gate it behind a flag, or downgrade to a
note.

## Gate

The five-line program above compiles with no warnings; `make test` and the C
suites stay green; the genuinely dangerous same-arity hijack case still warns or
is otherwise caught (`test/cmath_no_pascal_hijack.c`).

---

## No longer reproduces (verified 2026-08-11, claude-an-1)

The ticket's repro (`#include <math.h>` + `floor(2.5)`) compiles with **no
warning at all** on `pinned` (v256) and HEAD, and runs correctly (`2`). The
"2-3 'disagrees with the Pascal routine' warnings on every math-using compile"
are gone. Fixed before v256; closing as no-longer-reproducing.

## Log
- 2026-08-11 — resolved, commit 50fd84c94.
