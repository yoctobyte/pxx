---
track: N
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-11
found-by: frankuser
tags: [nilpy, imports, case]
blocked-by: []
summary: "`from . import MyMod` fails with `no unit named mymod` -- the name is LOWERCASED before lookup -- while `import pkg.MyMod` on the same file resolves correctly and prints the right value. Measured 2026-09-11 at c53cb51926a2. Python module names are case-sensitive, so a package with any capital in a module name is reachable through one import door and not the other. Found incidentally: my own test harness named a scratch module `m_bigV` and the diagnostic said `m_bigv`."
---

# `from . import MyMod` lowercases; `import pkg.MyMod` does not

Measured 2026-09-11, compiler `c53cb51926a2`. One package, one file
`pkg/MyMod.py` containing `VAL = 7`, three spellings:

| spelling | CPython | pxx |
| --- | ---: | --- |
| `import pkg.MyMod` then `pkg.MyMod.VAL` | 7 | **7** |
| `from . import MyMod` (inside `pkg/`) | 7 | `error: import: no unit named mymod and no shim mimic_mymod` |
| `from pkg import MyMod` | 7 | `error: import: no unit named pkg ...` — a DIFFERENT bug, see below |

**The asymmetry is the finding, not the failure.** The absolute door preserves
case and the relative door folds it, so the two doors disagree about what a
module is called. A reader who hits the relative arm sees a missing-module error
naming a file that is right there on disk with different capitalisation, and the
message reports the folded name, which is what makes it puzzling rather than
obvious.

Pascal is case-insensitive and pxx units are looked up accordingly, so folding is
presumably deliberate somewhere in the unit path. **That is why this is a ticket
rather than a fix:** whether NilPy module names should be case-sensitive is a
policy question about where the Python surface stops and the Pascal unit table
starts, and `decide-own-language-first-vs-explicit-import-in-a-case-insensitive-language`
(decided) is about a different question — precedence, not spelling — so it does
not settle this one.

**Not the same as the third row.** `from pkg import MyMod` failing with
`no unit named pkg` is the absolute-package-import gap, unrelated to case; it
fails identically for an all-lowercase module name. It is mentioned only so a
fixer does not read this ticket as covering it. Nearest relative:
[[bug-n-from-package-import-submodule-binds-the-parent-package]], which is about
a real package binding the PARENT and is also not this.

**Same mechanism, different surface:**
[[bug-n-a-c-header-import-lowercases-the-library-name-so-gl-does-not-link]] is
the C-header path folding a library name. Worth fixing together if the fold turns
out to be one helper; worth knowing about either way, because a fixer who finds
the fold site will be looking at both callers.

**Prio 35 and the reason is exposure, not severity:** it is a loud compile error,
never a silent wrong value, and **no module in the lekkerzeilen corpus has a
capital in its name**, so it blocks nothing ranked today. It will bite the first
corpus that ships a `CamelCase.py`, which in Python is common enough for class-per-module
layouts.
