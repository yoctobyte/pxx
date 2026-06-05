# Evidence Archive — Non-Reproducible Miscompile (2026-06-02)

Companion to [`../anomaly_2026-06-02_2000.md`](../anomaly_2026-06-02_2000.md).
Everything recoverable from the episode is collected here. The original corrupt
binary was overwritten during the trigger-chase before it could be saved, so
parts are reconstructed; the gaps are stated explicitly.

## Files

| File | md5 | What it is |
|------|-----|------------|
| `good-binary.a9f415.elf` | `a9f415e4e45eb8af29889b6f1a0ce548` | A correct build of `test/test_managed_record_exit.pas` (4009 B) — the reference the corrupt build was diffed against (was `/tmp/a1`, byte-identical to the `/tmp/tmre2` used in the surviving `cmp`). |
| `good-binary-trimmed-test.9b5923.elf` | `9b5923d68defcdf423603608da30f6aa` | Correct build of the later *trimmed* test (3912 B), for completeness. |
| `partial-corrupt-reconstruction.elf` | `d8c23d0b821e5aabaad83fcafab7993e` | The good binary with the **10 surviving** corrupt bytes re-applied. **Segfaults (rc 139)** — reproduces the failure mechanism, but is NOT byte-identical to the original corrupt binary (see gap below). |
| `cmp-l-good-vs-corrupt.head10.txt` | — | The only surviving diff record. **Captured with `\| head`, so only the first 10 differing bytes exist.** |
| `disasm-good.txt` / `disasm-corrupt.txt` | — | `objdump` of good vs partial-corrupt (flat binary, vma 0x400000). |
| `disasm-good-vs-corrupt.diff` | — | Instruction-level diff of the two. |
| `system-meta.txt` | — | Host/CPU/RAM/storage/toolchain snapshot at filing. |

## Confirmed failure mechanism

The corrupted logical value is the **output image size, `0x0fa9` (4009)**, which
the compiler emits in several places. In the good binary:

- ELF `LOAD` `p_filesz = 0x0fa9` (file offset 0x60) — equals the real file size.
- ELF `LOAD` `p_memsz  = 0x2071` (offset 0x68) — filesz + 0x10c8 BSS (4296 B).
- Entry instruction at `0x400078`: `48 89 24 25 a9 0f 40 00` =
  `mov %rsp, 0x400fa9` — saves the stack pointer to `base + image-size`
  (the runtime stack/argv slot at end-of-image).
- Two further absolute-address operands (file offsets 0xCC, 0xDE) referencing
  `base + size(+8/+16)`.

In the corrupt build every occurrence of `0x0fa9` became `0x1681` (**+0x06D8**),
and `p_memsz` became `0x2789` (+0x0718). Consequences, each independently fatal:

1. `p_filesz = 0x1681` (5761) **> actual file size (4009)** → the kernel maps the
   LOAD segment past end-of-file → SIGSEGV at exec/load.
2. The entry `mov %rsp, 0x401681` stores to the wrong address.

The partial reconstruction — applying only the 10 known byte changes — already
segfaults, confirming (1).

## Evidence gaps (honest)

- **Only the first 10 differing bytes survive** (the live `cmp -l` was piped
  through `head`). The original corrupt binary (recorded md5
  `d1e2421c1d44b71a647505d8b09dd010`, 4009 B) was overwritten, so the full diff
  cannot be recovered and the reconstruction's md5 differs from the original.
- **No core dump exists.** `ulimit -c` was `0` and `core_pattern` pipes to
  apport, which discards crashes from non-packaged binaries. The shell's
  "core dumped" message notwithstanding, nothing was persisted.
- The on-disk vs page-cache question is undecidable after the fact: the captured
  copy later read back clean ("healed"), consistent with a transient page-cache
  / RAM corruption reloaded from a correct on-disk copy rather than persisted
  disk damage.

## Why not a software bug

No randomness, timestamps, or per-compile threads; the self-host gate requires
byte-identical `build == verify`; compiler md5 was constant (`badd42…`) before,
during, and after; 400 post-event recompiles were byte-identical with zero
crashes; trigger isolation (path, env, overwrite) all produced correct output.
Combined with **non-ECC RAM** (silent flips), the leading explanation is a
transient hardware memory fault, not a compiler defect. The record-`Exit` fix
under test is correct on its own merits.
