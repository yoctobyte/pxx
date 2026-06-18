# Xtensa Call0 / non-windowed frame >128 bytes silently truncates

- **Type:** bug
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-18 (noted during the windowed constant-sp fix)

## Symptom

The xtensa prologue lowers the local-frame reservation with a single `ADDI
sp, sp, -frame`. `ADDI`'s immediate is 8-bit signed (±128), so a frame larger
than 128 bytes silently wraps (`-frame & 0xFF`) instead of erroring — e.g. a
272-byte frame would encode as a tiny offset, corrupting the stack.

## Status

- The **windowed** ABI path was fixed in commit 8152eac: it rounds the frame
  to 256 and uses a single `ADDMI` (imm8<<8, ±32768), so windowed frames up to
  ~32 KB are fine.
- The **Call0** path (bare-metal, `--xtensa-abi=call0`, the default for
  non-IDF) still uses the patchable `ADDI` and therefore still truncates frames
  over 128 bytes. Procs with large local arrays / many locals on Call0 xtensa
  would miscompile.

## Fix

Apply the same ADDMI (or ADDMI + ADDI remainder) treatment to the Call0
prologue patch in `PatchProcPrologue` (symtab.inc), or at minimum raise a clear
compiler error when a Call0 xtensa frame exceeds 128 bytes instead of wrapping.

## Notes

- Low practical impact today: ESP work runs the **windowed** ABI (IDF), which
  is fixed; Call0 is only the bare-metal/no-IDF path and stage-1 procs have
  small frames. Filed so the silent-wrap doesn't bite later.
- Related: feature-esp32-bare-boot (the Call0 / bare profile).
