# Next-session kickoff prompt — Platform Abstraction Layer (PAL)

Paste the block below into a fresh session.

---

Track A first, then hand the layering to Track B. Implement
`docs/progress/backlog/feature-platform-abstraction-layer.md` — read it first;
it has the full design. Summary of what we agreed:

**Goal:** give the RTL a per-platform porting seam so file-IO / networking / time
work across `posix` (hosted) and `esp` (esp32 bare), with portable stdlibs that
(at least partly) run on esp32 as a side effect.

**Two axes (keep them independent):**
- CPU = codegen target (exists: x86_64/i386/aarch64/arm32/xtensa/riscv32).
- Platform = posix vs esp. Do NOT derive platform from CPU.

**Step 1 — the only Track-A piece, do it now (small, foundational):**
Add a platform + capability define axis in the compiler.
- New `--platform=posix|esp` flag in `compiler/compiler.pas` option loop
  (mirror `--target=`). Default derived: esp targets (xtensa/riscv32) or
  `--esp-profile=bare` → esp; else posix. Add a global `TargetPlatform` in
  `compiler/defs.inc`.
- In `PasApplyTargetDefines` (`compiler/lexer.inc`, runs after option parse,
  ~line 471): predefine `PXX_PLATFORM_POSIX`/`PXX_PLATFORM_ESP` and capability
  defines `PXX_HAS_FILES`, `PXX_HAS_SOCKETS`, `PXX_HAS_THREADS`,
  `PXX_HAS_DYNLIB` per platform (posix = all on; esp = none/minimal for now).
  Use `PasDefine`/`PasUndefine` like the existing CPU defines.
- Test: a small program that prints which `PXX_PLATFORM_*` / `PXX_HAS_*` are
  defined (via `{$ifdef}`), wired into `test-core`; assert the posix set. Confirm
  `--platform=esp` (or an esp target) flips them.

**Steps 2-4 are Track B / design** (PAL interface, posix backend, re-home
IO units, esp stub) — see the ticket. Backend selection should ride the
Pascal-`uses` search-path slice of `feature-dynamic-include-paths-config`
(NOT yet implemented — only C `#include` `-I` landed). Interim selection = one
top-level `{$ifdef PXX_PLATFORM_ESP}` include switch in `lib/rtl/platform.pas`.

**Hard rule:** no platform `{$ifdef}` above the PAL layer. A PAL primitive that
can't be implemented on both posix and esp doesn't belong in the PAL.

**Track A gate (for step 1):** `make test` byte-identical self-host fixedpoint +
`--threadsafe`; `make cross-bootstrap` (all 4 byte-identical); i386/aarch64/arm32
cross suites output-identical. Commit in small units; do NOT `git push` without
my OK. When it lands and B needs it: `make stabilize && make pin`, commit
`stable_linux_amd64/`.

**Context / state (as of this handoff):**
- Pinned stable = **v16** (carries: implicit-Self field arc, for-in member-access,
  call-result member access, C `#include` search path `-I` + native-only system
  fallback).
- C `#include` search path done (`-I<dir>`, including-file dir, `/usr/include`
  gated to native). Pascal-`uses` search path NOT done — it's the enabler for
  `lib/rtl/platform/<plat>/` dir selection; tracked in
  `feature-dynamic-include-paths-config`.
- Adventure demo currently blocked on `lib-text-file-io-assign-rewrite` (Track B,
  text-file RTL) — that file-IO API should be written ON the PAL once it exists.

**git landmine:** after `git mv`, never pass the old path to `git add` — a
non-matching pathspec aborts staging ALL and yields a partial commit. Verify
`git show --stat <sha>` after committing. Board checker
(`tools/progress.sh check`) requires each `done/` ticket to log a commit ref.

---
