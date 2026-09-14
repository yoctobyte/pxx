---
prio: 70
track: B
---

> **Track guessed as B from the FAILING STEP** — line 1 of 6, `stable_linux_amd64/default/pinned --threadsafe -Fulib/rtl test/lib_thread_handle_reports_exit_on_both_routes.pas /tmp/li`, which names `test/lib_thread_handle_reports_exit_on_both_routes.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: lib-test#src:test/lib_thread_handle_reports_exit_on_both_routes.pas at 06e40fb95b13 in step 1/6, `stable_linux_amd64/default/pinned --threadsafe -Fulib/rtl test/lib_thread_handle_reports_exit_on_both_routes.pas /tmp/l…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T18:57:01Z
- **Test source:** test/lib_thread_handle_reports_exit_on_both_routes.pas tools/expect_same.sh
- **Failing step:** line 1 of 6 of the job's recipe; it names `test/lib_thread_handle_reports_exit_on_both_routes.pas`.
  ```
  stable_linux_amd64/default/pinned --threadsafe -Fulib/rtl test/lib_thread_handle_reports_exit_on_both_routes.pas /tmp/lib_thread_handle_exit
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_thread_handle_reports_exit_on_both_routes.pas'` at 06e40fb95b13af1d28b9ffebe028e26ab10dff26

## Range
bad `06e40fb95b13`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
pascal26:230: error: expected 'begin' before 'weakexternal'
(tail)
pascal26:230: error: expected 'begin' before 'weakexternal'
  in: lib/rtl/palthread.pas
  near: ) : Integer ; cdecl ; >>> weakexternal 'libc.so.6' name 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
