---
track: A
prio: 40
type: bug
summary: "The caller side now follows the C ABI for 64-bit arguments to external functions, but a pxx routine CALLED FROM C still spills them with the internal packed convention — so on xtensa, where the C ABI skips to an even register, a C caller and a pxx callee would disagree. Latent: nothing crosses that way today."
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
