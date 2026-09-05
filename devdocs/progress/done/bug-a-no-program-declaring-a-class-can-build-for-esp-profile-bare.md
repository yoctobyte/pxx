---
slug: bug-a-no-program-declaring-a-class-can-build-for-esp-profile-bare
track: A+S
prio: 55
type: bug
status: done
owner: frankS
created: 2026-09-05
found-by: frankS (first ever execution of test-esp-bare)
summary: "FIXED at HEAD 2026-09-05. No program declaring a `class` could build for `--esp-profile=bare`, on esp32c3 OR esp32s3: `error: unresolved forward: PXXClassFinalize`. The BODY sits inside builtinheap.pas's `{$ifndef PXX_ESP}` block while the forward declaration sits unconditionally in the interface list, so the ESP profile declared a procedure it never compiled. A five-line class program reproduces it; `writeln(1)` builds and the same class program builds under `--platform=posix`, so it is the PROFILE, not the arch. Invisible until now because the only suite that compiles for this profile, test-esp-bare, is enrolled in ZERO tiers and had never been executed by anything."
---

# No program declaring a class can build for --esp-profile=bare

## The boundary, measured

Compiler `fe1e9c37d322`. Three programs, `--esp-profile=bare`:

| program | result |
| --- | --- |
| `begin writeln(1) end.` | builds |
| **five lines declaring a `class` with one AnsiString field** | **FAILS, both chips** |
| that same class program, `--platform=posix` | builds |

```
pascal26:2: error: unresolved forward: PXXClassFinalize
  in: ./compiler/builtin/builtinheap.pas
```

So it is the **profile**, not the architecture, and it is **classes**, not
exceptions — which is what the row that exposed it looked like.

## Cause

`PXXClassFinalize`'s body is inside the `{$ifndef PXX_ESP}` block that opens at
`builtinheap.pas:3671` and closes at 4356. Its forward declaration was in the
**interface list**, which is not inside any guard. The ESP profile therefore
declared a procedure whose body it never compiled.

**The file already carried a comment predicting this exactly.** Above
`PXXRecordZeroManaged`:

> *Forward only where the BODY exists — PXXClassFinalize is itself inside
> `{$ifndef PXX_ESP}`, so an unconditional forward left it unresolved on the ESP
> profile (test-emit-obj: "unresolved forward: PXXClassFinalize").*

A later change moved the forward into the interface — *"it is declared in the
interface now, with the rest of the code generator's entry points"* — and
**re-introduced the defect the comment existed to prevent**, because the
interface list is outside the guard. A comment that names its own failure mode,
names the error string, and is tripped anyway is an argument for a guard, not
for better prose.

## Fix

Guard the declaration to match the body. Every caller was already guarded
(`PXXObjFree`'s call is inside `{$ifndef PXX_ESP}`), so nothing under `PXX_ESP`
loses a symbol it uses.

**Inertness proof for the host compiler, which is the part worth quoting:**
`make compiler/pascal26` printed `converged after 1 round(s)` — a real
recompute, not the stamp path — and produced a **byte-identical binary**,
sha256 unchanged at `fe1e9c37d322`. The compiler is not built with `PXX_ESP`,
so the change provably cannot affect it.

## Reaches $(PXX_STABLE) at the NEXT pin, not this one

Pin v404 (`8844c8c42`) landed ~20 minutes before this fix, and `make pin`
freezes `compiler/builtin/**`. **The pinned compiler still carries the
unguarded declaration**, so Track B and E builds — which use `$(PXX_STABLE)` by
rule — keep hitting this until the next pin. Not a reason to pin: the exposed
path is one where no class program could build at all, so there is no working
behaviour being regressed. Recorded so a later reader is not confused by a fix
that works at HEAD and not in a B-lane build.

## Why it was invisible, which is the durable half

`test-esp-bare` is in **zero** testmgr tiers and referenced by no script — see
`bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it`. This defect
was found on that suite's **first ever execution**. The suite is 27 assertions
and `test-esp-softfloat` another 24, and on a box with the Espressif qemu builds
installed **none of them skip**.

A second defect made the diagnosis harder and is fixed alongside:
`tools/esp_run_bare.sh` sent the compile's **stdout** to `/dev/null` while
pascal26 writes diagnostics there, so **a build failure and a program that ran
and printed nothing were the same observation** — empty output, nonzero rc. The
row survived a repro at `ESP_RUN_TIMEOUT=40` and a second chip before a by-hand
compile showed the real error. The runner now prints the compiler's diagnostic
on failure and is unchanged on success.

## If you are hitting this RIGHT NOW, read this first

**Symptom:** `error: unresolved forward: PXXClassFinalize` when building any
program that declares a `class` for `--esp-profile=bare`.

**Discriminator, and it takes one command:** build the same program with
`compiler/pascal26` at HEAD instead of `$(PXX_STABLE)`. If HEAD builds it and
the pinned compiler does not, you are seeing the pin, not a regression.

**Why:** fixed at HEAD in `6758c7ce7`, which lands in `compiler/builtin/
builtinheap.pas`. `make pin` **freezes `compiler/builtin/**`**, and pin v404
(`8844c8c42`) was cut ~20 minutes before the fix. So the pinned compiler still
carries the unguarded declaration and will until the next pin.

**This is not a regression in either direction.** Nothing that used to build
stopped building: no class program could build for this profile at all, on
either chip, for as long as the profile has existed. The pinned compiler is
*correctly older* — the same shape as the `__GNUC__` case in CLAUDE.md's Track B
notes, where a green under the pin was correct about a different compiler.

**Do not work around it** by reshaping the source. Build that program at HEAD,
or wait for the next pin.
