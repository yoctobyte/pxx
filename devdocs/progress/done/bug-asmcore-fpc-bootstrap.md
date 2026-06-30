# FPC bootstrap can't compile the asmcore units the compiler now `uses`

- **Type:** bug (bootstrap / FPC only — NOT the daily self-host gate)
- **Status:** done
- **Track:** A (compiler bootstrap) + B (owns lib/asmcore)
- **Opened:** 2026-06-30, building the .asm MVP frontend (feature-asm-mvp-frontend)

## Symptom

The `.asm` frontend makes `compiler.pas` `uses asmcore_base, asmcore_x64`
(lib/asmcore), compiled INTO the compiler. PXX self-host builds this fine (the
daily `make` / `make test` / `make stabilize` are all green — those are FPC-free).
But the **FPC cold bootstrap** (`make bootstrap`, `make test-fpc`) fails:

```
fpc -O2 -Tlinux -Px86_64 -Fulib/asmcore ... compiler.pas
asmcore_base.pas(94,3) Error: Identifier not found "Result"
... 36 errors
```

The asmcore units have no `{$mode}` directive, so FPC defaults to `{$mode fpc}`
where the `Result` pseudo-variable is off. PXX always allows `Result`, so Track B
never hit it. (`-Fulib/asmcore` is already wired into FPCFLAGS — the unit search
path is fine; only the dialect mode is the problem.)

## Fix (deferred per user — self-host is what matters right now)

Make the two units FPC-clean — add `{$mode objfpc}{$H+}` at the top of
`lib/asmcore/asmcore_base.pas` and `asmcore_x64.pas` (inert for PXX, which already
self-builds them; flips on `Result` + ansistrings for FPC). Verify:
- PXX self-host stays byte-identical after the directive (asmcore is now compiled
  into the compiler, so its bytes affect the binary — re-seed + re-verify).
- `make bootstrap` / `make test-fpc` go green again.

Track B owns lib/asmcore; the directive is a one-line, non-behavioural change but
should be coordinated since the compiler self-host now depends on those files.

## Context

User decision 2026-06-30: ship the .asm frontend on the **self-host** path now
(green), ignore FPC bootstrapping for the moment, file this. The daily gate does
not need FPC (FPC-optional workflow), so this does not block normal work — only a
cold FPC-seeded checkout or the release `test-fpc` compliance step.

## Log
- 2026-06-30 — resolved, commit 5a0dfe54.
