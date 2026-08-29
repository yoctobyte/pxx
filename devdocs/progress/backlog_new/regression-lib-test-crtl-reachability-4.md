---
prio: 70
track: B
type: regression
summary: "NOT the crtl-reachability step, and NOT Track C. tools/lib_units_compile.py compiles every lib unit with NO include flags, so lib/pcl's <gtk/gtk.h> resolves to GTK2 and e8e006c38's version guard correctly #errors. EIGHT PCL units fail, not the three the log shows. Fix: pass the GTK3 include root (the Makefile already computes it as GTK3_INC). Second defect in the same file: failure output is truncated to 3 lines and all 3 are warnings, so the actual #error never reaches any report."
status: backlog
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 32 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py red at b26e7ed366f3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T21:17:12Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +36

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at b26e7ed366f37d1df21bb8595fc2c0d462db0949

## Range
> **The named sha `b26e7ed366f3` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b26e7ed366f3`, last good `9beb2af4946c`, **20 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:9: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
lib-units: FAIL gtk3gl
    pascal26:9: warning: #include <alloca.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:9: warning: #include <dirent.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:9: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
lib-units: FAIL gtk3widgets
    pascal26:88: warning: #include <alloca.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:88: warning: #include <dirent.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:88: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
lib-units: FAIL interfaces
    pascal26:88: warning: #include <alloca.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:88: warning: #include <dirent.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
    pascal26:88: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Triage 2026-08-29 (frankC) — retracked C -> B. Real, reproduced, cause and fix both verified.

Reproduced at HEAD (`805e74884`) against `stable_linux_amd64/default/pinned`, so
the "advanced 32 commits, re-verify" caveat is settled: this is live, not stale.

### It is not the step the job is named after — again

Third time for this job, so it is worth stating flatly: `crtl-reachability`
**passes**. The job is named after its first source file and the red is a later
step, exactly as in [[regression-lib-test-crtl-reachability]] (that one was
`crtl-map`) and [[regression-lib-test-crtl-reachability-3]]. **The `track: C`
guess is derived from that same filename and is wrong for the third time.**
Nothing here touches the C frontend or `lib/crtl`.

### What actually fails

`lib-units`, and not for three units — for **eight**:

```
extctrls  forms  glarea  graphics  gtk3  gtk3gl  gtk3widgets  interfaces
```

Every one of them reaches `lib/pcl/gtk3_c.h`, and every one dies on the same
line:

```
error: #error ... "lib/pcl needs the GTK3 headers, but <gtk/gtk.h> resolved to
GTK2. The link is libgtk-3.so.0 regardless (the stem comes from the unit name),
so this would be a silent header/library ABI mismatch. Pass the GTK3 include
root first: ... `pkg-config --cflags-only-I gtk+-3.0`."
```

**The guard is not the bug — it is working exactly as designed.** `e8e006c38`
(*"assert PCL's GTK version instead of inheriting it from -I"*) added it so this
exact mismatch would be loud instead of silent, and it is being loud. What
changed underneath it is `9396b32c7` (*"migrate lib/pcl off the curated
gtk3_c.h onto the stock GTK3 headers"*), which made `lib/pcl` depend on a
non-default system include root for the first time.

`tools/lib_units_compile.py` builds each probe as

```python
cmd = [pxx] + [-Fu…esp] + EXTRA_ARGS.get(unit, []) + [src, out]
```

— **no include flags at all**, ever. `gtk-2.0` is a default system include root
and `gtk-3.0` is not, so `<gtk/gtk.h>` finds GTK2 and the guard fires. The
Makefile has computed the right root as `GTK3_INC` since `e8e006c38`
(`pkg-config --cflags-only-I gtk+-3.0`, literal path as fallback); this tool
simply never learned about it.

Verified both directions on this box, all eight units:

| probe | result |
| --- | --- |
| `pinned -Fu…esp` (what the tool does today) | 8 FAIL |
| `pinned $GTK3_INC -Fu…esp` | **8 OK** |

### The fix, and why NOT the mechanism the file invites

The file's `EXTRA_ARGS` dict exists for precisely this ("units that legitimately
do not compile as a bare `uses` on the host, each with the reason and the extra
arguments that make them compile"), and eight entries there would work today.

**Recommend against it.** Four of the eight — `extctrls`, `forms`, `graphics`,
`interfaces` — do not name GTK3 anywhere; they reach it transitively through the
widgetset. A hand-maintained list keyed on that is a second path that goes stale
the moment a PCL unit gains or loses a transitive edge, and it goes stale
*silently*, since a missing entry looks exactly like this red. Per
`normalise-dont-special-case`, compute the root once and pass it to **every**
probe:

```python
GTK3_INC = (subprocess.run(["pkg-config", "--cflags-only-I", "gtk+-3.0"],
                           capture_output=True, text=True).stdout.split()
            or ["-I/usr/include/gtk-3.0/"])
...
cmd = [pxx] + GTK3_INC + [...]
```

Extra `-I`s are inert for the units that do not include GTK, the list cannot
drift, and it mirrors the Makefile's existing expression rather than inventing
a second source of truth. A box without GTK3 headers gets the literal fallback
and the guard's own error message, which is the right failure.

### Second defect, same file, and it is why this took three tickets to read

```python
for line in out.strip().splitlines()[:3]:
```

Every failing unit here emits three `#include ... resolved from the host system`
**warnings** before its error, so the three lines the report keeps are three
warnings and the `#error` that explains everything is never printed — in this
ticket's log tail, in the tstate report, or anywhere else. That is why the tail
above looks like a host-header problem and reads as unattributable.

Print the first error-looking line (or the last lines rather than the first, or
filter `warning:`), so a `lib-units` red is diagnosable from the report instead
of only by re-running it locally. Separable from the fix above if whoever takes
it prefers two commits; same file, so folded here.

### Ownership

**Track B.** `tools/lib_units_compile.py` is part of `make lib-test`, B's gate,
and `lib/pcl` is B's. It is not Track T's (T owns `testmgr`/`twatch`/fuzzers,
not this) and not Track C's despite the filename guess.

Raised by frankC because the GTK3 migration chain starts in a Track C ticket
([[feature-c-gtk3-header-final-wiring]] -> the pcl migration -> the version
guard), so this is my blast radius even though the file is not mine. Not fixed
here: `tools/lib_units_compile.py` is outside Track C's lane, and everything
needed to fix it is above — the cause, the eight units, the verified flag, and
the recommended shape.

### Gate for whoever takes it

`python3 tools/lib_units_compile.py` green on a box with GTK3 dev headers
(28s here, no compiler rebuild — it runs against `$(PXX_STABLE)`). No self-host
gate needed: nothing under `compiler/**` changes.
