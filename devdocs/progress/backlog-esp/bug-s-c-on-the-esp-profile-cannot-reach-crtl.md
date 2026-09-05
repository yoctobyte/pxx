---
slug: bug-s-c-on-the-esp-profile-cannot-reach-crtl
track: S
type: bug
prio: 45
status: backlog
owner: ""
created: 2026-09-05
blocked-by: []
summary: "A C source that reaches crtl does not build on the ESP profile: `#include <stdio.h>` plus a printf stops with `compiler error: PXXMemZero not found` under --target=xtensa --emit-obj, on BOTH the default profile and --esp-profile=bare. The 2x2 says the discriminator is the PROFILE, not the output mode -- the same source builds with --platform=posix as an executable AND as an object. PXXMemZero is defined unconditionally in compiler/builtin/builtinheap.pas:4561 (only its fast paths are CPUX86_64-guarded), so the symbol EXISTS and the lookup is not reaching it: the builtin heap unit is not being pulled into a C compilation on PLATFORM_ESP. Bounds decide-should-a-c-main-exist-on-the-esp-profile-at-all, which established that --emit-obj is the shipping path for C here -- true for FREESTANDING C and not yet for C that calls into crtl."
---

# C on the ESP profile cannot reach crtl

- **Type:** bug — Track S (ESP), primary target xtensa
- **Found:** 2026-09-05 (frankS), bounding my own claim after frankC measured it
- **Compiler:** `b67962cb78fa`

## The 2×2, which is the whole diagnosis

Source is `#include <stdio.h>` plus `int main(void) { printf("hello\n"); return 0; }`.

| | `--platform=posix` | ESP profile (default and `--esp-profile=bare`) |
| --- | --- | --- |
| `--emit-obj` | **BUILDS** | `pascal26:11: error: compiler error: PXXMemZero not found` |
| executable | **BUILDS** | refuses earlier, at the C entry stub (correct, by design) |

**The discriminator is the PROFILE, not the output mode.** That matters because
the obvious reading — "the object path is less complete than the executable
path" — is wrong, and it is the reading someone will reach for.

A freestanding C source is fine on both ESP profiles: `int main(void)` with no
includes builds to an object exporting `GLOBAL app_main`. So the entry
machinery works and it is specifically the crtl reach that does not.

## Why "not found" is misleading, and what it is not

`PXXMemZero` is declared at `compiler/builtin/builtinheap.pas:468` and defined at
`:4561`. The body is **unconditional** — only its fast paths carry
`{$ifdef CPUX86_64}` — and it sits after the `{$ifndef PXX_ESP}` block (3671–4356)
closes, so it is not guarded out on ESP.

**So the symbol exists and the lookup is not reaching it.** This is not a missing
implementation; it is the builtin heap unit not being pulled into a C
compilation on `PLATFORM_ESP`. The `compiler error:` spelling is an internal
assertion — one of fifteen identical `PXXMemZero not found` sites across six
backends (`symtab.inc` plus five `ir_codegen_*`), so the message says which
symbol and nothing about which of the six asked.

**Do not "fix" this by defining PXXMemZero somewhere.** It is defined. The
question is unit reachability on this profile, and a second definition would
make the symptom go away while leaving every other builtin in the same unit
just as unreachable — the next one would surface as a different name and read
as an unrelated bug.

## Where this came from, and what it bounds

`decide-should-a-c-main-exist-on-the-esp-profile-at-all` (decided today)
established that `--emit-obj` is how C ships to an ESP32 and that the standalone
refusal is correct. **That is true for freestanding C and I wrote it without the
bound**, which frankC caught by noticing its own `c_va_arg_every_target.sh`
`--emit-obj` row builds only a trivial `main` and a stdarg program and never
reaches printf. The diagnostic in `cparser.inc` now carries the bound and names
this ticket.

## Next step for whoever takes it

The cheap first measurement is which of the six backends raises it here —
`PXXDBG` or a temporary distinct string per site — because `symtab.inc` raising
it means the symbol is absent from the table entirely, while an `ir_codegen_*`
site raising it means the table was built and the unit was still not in it.
Those are different bugs with the same message.
