---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 17 of 35, `if [ ! -f /usr/include/FLAC/stream_decoder.h ]; then \ echo "test_nilpy_a_headers_directory_names_its_library: SKIP - no`, which names `test/test_nilpy_a_headers_directory_names_its_library.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 9 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `test_nilpy_an_unreferenced_header_import_needs_no_library`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `test_nilpy_a_headers_directory_names_its_library`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_an_unreferenced_header_import_needs_no_library.npy at 4fbed6c4157e in step 17/35, `if [ ! -f /usr/include/FLAC/stream_decoder.h ]; then \ echo "test_nilpy_a_headers_directory_names_its_library: SKIP - n…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:54:49Z
- **Test source:** test/test_nilpy_an_unreferenced_header_import_needs_no_library.npy test/test_nilpy_an_unreferenced_header_import_needs_no_library.expected +7
- **Failing step:** line 17 of 35 of the job's recipe; it names `test/test_nilpy_a_headers_directory_names_its_library.npy test/test_nilpy_a_headers_directory_names_its_library.expected`.
  ```
  if [ ! -f /usr/include/FLAC/stream_decoder.h ]; then \ echo "test_nilpy_a_headers_directory_names_its_library: SKIP - no /usr/include/FLAC/stream_decoder.h on this box (needs libflac-dev); the directory-derived soname is NOT covered by this run"; \ else \ ./compiler/pascal26 test/test_nilpy_a_header
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_an_unreferenced_header_import_needs_no_library.npy'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3234959/test_nilpy_ffiunref26  [code=1359323B  data=86220B  bss=67328B  procs=2306  codeseg=1359584B]
test_nilpy_a_header_whose_library_is_not_spelled_like_its_file: DT_NEEDED libGL.so.1 resolves on this loader
test_nilpy_a_headers_directory_names_its_library: FAIL - DT_NEEDED is [eam_decoder_delete], expected the DIRECTORY's libFLAC.so.<n> and not the file stem's libstream_decoder.so

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
