---
track: B
prio: 60
type: bug
---

# On ESP a growing string asks for double its size and runs out of heap

Found 2026-11-01 while measuring append cost after the Copy fix
(bug-b-builtin-copy-builds-its-result-a-char-at-a-time).

PXXStrAppend grew a full block to `need * 2`. On a PC that costs nothing
(untouched capacity is virtual memory), but on ESP it is real RAM. Under
QEMU, one string grown in 1 KB appends died with "out of memory" at about
90 KB on an S3, while the heap had 295 KB free and a 164 KB largest block:
the next growth asked for about 190 KB.

**Fix** (owner's call: no doubling on ESP, a slack of 8-16 KB is plenty because
ESP code is mostly single-threaded and strings die at function return). On
either ESP profile the growth is `need + min(need, 16 KB)`. A short string still
doubles, so it never carries more slack than its own size. A flat 16 KB would
have cost every short string that is appended once and kept in a list. PCs keep
doubling.

Trap on the way: in builtinheap.pas, `PXX_ESP` means the BARE profile only
(line 18), so the first cut under `{$ifdef PXX_ESP}` never reached an IDF
build. The S3 trace was identical to the pin's until the condition became
`defined(PXX_ESP_BARE) or defined(PXX_ESP_IDF)`.

**Measured** (QEMU, IDF 6.0.1): the largest string the S3 reaches went from
~90 KB to ~160 KB. Past that, copy-on-grow needs the old and new blocks at
once, so the old block plus 16 KB must fit beside the old block. The C3
reaches ~120 KB.

**Test.** test/esp_a_string_grows_past_its_doubled_size.pas grows to 112 KB,
in test-esp-idf on C3 and S3. Output identical to x86-64.

Not done: no in-place realloc (heap_caps_realloc could extend without the
copy, which would lift the old+new limit), and no change to string loops
in app or library code (owner: not yet).
