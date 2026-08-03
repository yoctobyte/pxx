---
track: A
prio: 40
type: bug
summary: "The caller side now follows the C ABI for 64-bit arguments to external functions, but a pxx routine CALLED FROM C still spills them with the internal packed convention — so on xtensa, where the C ABI skips to an even register, a C caller and a pxx callee would disagree. Latent: nothing crosses that way today."
status: done
owner: claude-AC
---

# A pxx routine called from C reads 64-bit parameters at the internal positions

- **Type:** bug (latent — no caller exercises it yet) — **Track A** (callee
  parameter spill), Track S campaign
- **Opened:** 2026-08-02, as the deliberate remainder of
  [[bug-esp-timer-callback-never-dispatched]]

## The asymmetry

That bug fixed the **caller** side: pxx now marshals a 64-bit argument to an
`external` C function the way the target's C ABI wants it — consecutive
registers on riscv32, an even-aligned pair on xtensa (measured from each
target's gcc).

The **callee** side did not change. `parser.inc`'s xtensa/riscv32 parameter
spill assigns word indices with no padding, because that is the internal
convention and both halves of an internal call agree on it. So a routine that C
calls with a 64-bit argument reads:

| | C caller puts it at | pxx callee reads it at |
| --- | --- | --- |
| riscv32 | consecutive words | consecutive words — **agree** |
| xtensa | next EVEN word | next word — **disagree when the index is odd** |

Only xtensa, and only when a 64-bit parameter follows an odd number of preceding
words.

## Why it is not urgent

Nothing crosses that boundary today. `app_main` takes no arguments; the
esp_timer callback signature is `void (*)(void*)`; the PAL's exported entry
points are called from Pascal. It becomes real the moment a pxx routine is
registered as an SDK callback with a 64-bit parameter — a gptimer alarm
callback carrying a `uint64_t` count, say.

## The fix, and why it should wait for a decision

Guessing from `ProcExternal` is not available here: the callee is a pxx routine,
so nothing marks it as "C calls this". The honest signal is an explicit
`cdecl;` (or `export;`) marker on the declaration, which would then drive:

- the parameter spill's word alignment (this bug), and
- the caller side symmetrically, replacing the `ProcExternal` test with the same
  marker.

That is a small language-surface decision rather than a code change, so it wants
a [[decide-cdecl-marker-drives-abi]] answer first if it is not obvious.

## Acceptance

- A pxx routine declared `cdecl` with a 64-bit parameter, called from a C shim
  in the IDF project, receives the right value on esp32s3 (windowed) and
  esp32c3.
- The existing internal calls stay byte-identical (self-host fixedpoint) —
  nothing about the internal convention changes.

## FIXED (2026-08-03) — no marker; xtensa just uses the xtensa C ABI

### The decision, from the user

The ticket wanted [[decide-cdecl-marker-drives-abi]] answered first. It is
answered, and it removes the marker from the design rather than adding it:

> "we just treat any calling definition as pure decoration. so on windows —
> stdcall, on linux cdecl as calling convention, no questions asked, invalid
> decorators just ignored. so, any calling convention is host specific by
> definition."

So `cdecl`/`stdcall` on a pxx routine are DECORATION, and a target has exactly
one convention: its own. The fix follows directly — **apply the xtensa C ABI's
even-word rule unconditionally, on both sides**, instead of keeping a packed
internal layout and a C layout that can disagree. No flag, no per-routine
divergence, and the asymmetry cannot come back.

The marker-driven alternative was measured and is worse than it looks: setting
`ProcCdecl` on a bodied Pascal routine is already enough to make x86-64
miscompile, because that flag switches the CALLER to SysV while the callee
prologue has no C-ABI spill. A 9-parameter `cdecl` routine printed
`1398329043 0.00 140721706815082 SHELL=/bin/bash …` — it was reading the
process environment. Honouring the keyword for real is a multi-backend feature,
not this ticket. (`cdecl` on a routine with a body stays inert, as it is today.)

### Measured — the gcc oracle

`xtensa-esp32s3-elf-gcc`, both ABIs, on `f(int a, long long b)`:

| | a | b |
| --- | --- | --- |
| gcc call0 | a2 | **a4:a5** (a3 skipped) |
| gcc windowed | a10 | **a12:a13** (a11 skipped) |
| pxx callee, before | a2 | **a3:a4** — one register early |
| pxx callee, after | a2 | **a4:a5** — agrees |

### Verified by RUNNING it, not just disassembling

`test/test_esp_bare_arg64.pas` puts a 64-bit argument at word indices 1, 3 and 5
(index 5 straddles a7 into the caller's stack area) plus an even control case,
and runs on **real xtensa and riscv32 under qemu** via the existing bare-boot
harness: UART output byte-identical to the x86-64 oracle on both chips. The
whole `test-esp-bare` suite stays green, which is what proves the internal calls
moved in lockstep (both sides changed together — they must always be changed
together). Wired into `test-esp-bare`.

That closes acceptance line 2 (internal calls unaffected) and gets line 1 as far
as it can go without hardware: the callee now reads exactly the registers gcc
writes, verified against the IDF's own compiler.

### Not covered, deliberately

An actual C→pxx call still cannot be written: pxx exports only `app_main` from
an object (every other routine is LOCAL), so an SDK callback with a 64-bit
parameter has no way to name a pxx routine yet. That export mechanism is a
separate gap — worth its own ticket if the callback story is picked up. What
this ticket was about, the register disagreement, is gone.

## Log
- 2026-08-03 — resolved, commit PENDING.
