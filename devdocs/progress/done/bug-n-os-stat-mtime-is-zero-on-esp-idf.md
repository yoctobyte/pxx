---
summary: "RESOLVED 2026-11-25: on ESP-IDF, PyPalStatFull read only st_mode and st_size from newlib's struct stat, so os.stat().st_mtime, st_mtime_ns and os.path.getmtime() were 0 for every file on the board. It now reads st_mtim at offset 40 (8-byte time_t, tv_nsec at +8). The offsets were measured with offsetof under the IDF 15.2 riscv32 and esp32s3 gcc, which agree."
type: bug
track: N
prio: 50
status: done
created: 2026-11-25
found-by: a local /code-review of pin v455
owner: claude-dupwt
tags: [nilpy, esp, idf, os, stat]
blocked-by: []
---

## Cause and fix

compiler/builtin/pypal.pas, IDF arm of PyPalStatFull: `st.mtimeNs` stayed at
its zero initialisation. newlib's `struct stat` (88 bytes) has `st_mode` at 4,
`st_size` at 16 and `st_mtim` at 40. These were measured, not derived, with
both IDF toolchains, and the two existing reads match them. IDF's FAT
`get_fattime` clamps an unset clock to 1980, so a written file never reports 0.

## Test

test/esp_board_files.npy (a board row; you run it on the board) gains
`mtime set True True`, which CPython prints too. It builds for riscv32 and for
Xtensa windowed. **It has not been run on a board.**
