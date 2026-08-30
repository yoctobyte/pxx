---
prio: 70
track: P
---

> **CONSOLIDATED by frank-coordinator, 2026-08-30 — these FIVE tickets are one cause.**
> All five gtk regressions carry the **same** red sha `bfec13534396`, the **same**
> last-good `f8b0eea0049c`, and the **same** 3-commit range. Triaging them five times
> is five times the work for one defect; take them as a set.
>
> **The range contains exactly TWO code commits** — everything else is docs/tstate:
> `eefa85d70 fix(C): a static defined in a used header keeps its body` and
> `1a7658326 fix(A): --emit-obj and --shared honour external name, via one resolver`.
> `1a7658326` is already root-caused elsewhere (a self-contradicting emit-obj recipe,
> since fixed), which leaves one candidate touching the path these programs use — they
> are Pascal programs binding gtk3 through `gtk3_c.h`, i.e. the **C header import path**.
>
> **That is a bounded range, NOT a diagnosis. Do not act on it as a cause.** The named
> sha `bfec13534396` cannot itself be the trigger — it touches only docs, tickets and
> tstate, so it is the upper bound of an untested range. Confirm by building
> `eefa85d70^` and running one of the five before attributing anything.
>
> **Track stays P and the watcher's guess was RIGHT.** The coordinator nearly retracked
> all five to C on the `test_c_` prefix, and the bounded fact refutes that: every one of
> these sources is a **Pascal** file whose name merely begins `test_c_`. That prefix
> means *C-interop*, not *C-language*. But the likely cause is C-lane work, so P owns the
> ticket while **frankC has been asked to check the header path** — read this as "two
> lanes, one defect", not as a re-lane.

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk_types.pas red at bfec13534396 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T00:34:41Z
- **Test source:** test/test_c_gtk_types.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk_types.pas'` at bfec135343961cc33559d058bccc63e4c871eceb

## Range
> **The named sha `bfec13534396` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `bfec13534396`, last good `f8b0eea0049c`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:90: error: undeclared identifier passed as argument 2 of '__pxx_read', where a pointer is expected — this would call/dereference through NULL
(tail)
pascal26:2: warning: #include <alloca.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <dirent.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <linux/limits.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:86: warning: undeclared identifier 'pxx_env_loaded' used as value (treated as 0)
pascal26:87: warning: undeclared identifier 'pxx_env_loaded' used as value (treated as 0)
pascal26:90: warning: undeclared identifier 'pxx_env_buf' used as value (treated as 0)
pascal26:90: error: undeclared identifier passed as argument 2 of '__pxx_read', where a pointer is expected — this would call/dereference through NULL
  near: fd  pxx_env_buf    >>>  __pxx_close  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
