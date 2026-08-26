---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_char_array_is_a_string.pas red at 357217a73608 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T13:01:56Z
- **Test source:** test/test_char_array_is_a_string.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_char_array_is_a_string.pas'` at 357217a73608b10ffa0eb976c126a691c790c4eb

## Range
> **The named sha `357217a73608` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `357217a73608`, last good `902e53050f07`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:111: error: no overload of Wrap matches these arguments
pascal26:111: error: no overload of ChkS matches these arguments
pascal26:112: error: no overload of WrapV matches these arguments
(tail)
pascal26:111: error: no overload of Wrap matches these arguments
  argument types: (Char)
  candidates:
    Wrap(AnsiString)
  near: const param  Wrap  a  >>>  <hi>  
pascal26:111: error: no overload of ChkS matches these arguments
  argument types: (ShortString, Integer, ShortString)
  candidates:
    ChkS(AnsiString, AnsiString, AnsiString)
  near:  a   <hi>  >>>  Chk  
pascal26:112: error: no overload of WrapV matches these arguments
  argument types: (Char)
  candidates:
    WrapV(AnsiString)
  near: value param  WrapV  a  >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution — 2026-08-26

Fixed. Root cause and full write-up: [[bug-p-a-char-array-argument-stopped-binding-a-string-parameter]].

The array-vs-scalar overload guard refused an `array[..] of Char` bound to a `string` parameter — a conversion the language defines. Verified GREEN by the watcher's own repro: `tools/testmgr.py --tier native --job 'test-core#src:test/test_char_array_is_a_string.pas'` → 1/1 pass.

This stub and its siblings are ONE defect each seen from a different tier —
`progress.sh dupes` scores the two `parallel_for_capture_aggr` stubs at 82%
against each other, which is the first thing that command found when it was
built (bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance).
Kept as separate rows only because the watcher files per failing JOB; they close
together because they were always one bug.
- 2026-08-26 — resolved, commit cd5d54964.
