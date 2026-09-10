---
track: C
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frank-seven
tags: [c-frontend, crtl, malloc, corpus, quickjs]
blocked-by: []
summary: "`malloc_usable_size` is not declared by crtl, so quickjs-ng fails to compile: `pascal26:558: error: call to undeclared function: malloc_usable_size` in library_candidates/quickjs/cutils.c. This is the ONLY thing standing between test-quickjs and a verdict -- the job is otherwise wired, the source tree is present, and the target reaches the compile step in 4s. Measured 2026-09-10 at 89f5a6c8d on seven with the Track T watcher STOPPED, so the 4s is a clean number. UNLIKE the duktape builtin, this one has a design question in it: malloc_usable_size reports the ACTUAL usable size of an allocation, which only the allocator can answer, so a stub returning the requested size is a plausible-looking answer that is wrong whenever the allocator rounds up -- and quickjs uses it for memory accounting, so it would under-report rather than crash."
---

# `malloc_usable_size` is undeclared, so quickjs cannot compile

```
$ make test-quickjs
compiling quickjs runner ...
test-quickjs: FAIL — compile
pascal26:558: error: call to undeclared function: malloc_usable_size
  in: library_candidates/quickjs/cutils.c
```

`malloc_usable_size(void *)` is a glibc extension declared in `<malloc.h>`, not
ISO C. It returns the number of bytes actually usable in an allocation, which is
`>=` the requested size because allocators round up.

# The trap, and why this is not the same shape as the duktape builtin

[[bug-c-builtin-inf-is-undeclared-so-duktape-cannot-compile]] wants a value that
is fixed by IEEE-754. This one wants a value only pxx's own allocator knows.

quickjs calls it for **memory accounting** — `js_malloc_usable_size` feeds the
engine's allocated-bytes counter. So a stub that returns the requested size
compiles, links, runs, and produces a plausible number that is silently wrong
whenever the allocator rounds up. It would not crash; it would under-report, and
the failure would surface as an engine memory limit behaving oddly under load,
a long way from here.

So the options are worth stating before someone picks the easy one:

- **Answer it honestly from the allocator** — the correct fix, and the only one
  that makes the returned number mean what its callers think it means.
- **Do not declare it, and let the corpus fail** — which is the state today, and
  is at least honest.
- A stub returning the requested size is the option that looks like progress and
  is not; if it is taken deliberately as a stopgap, it needs to say so at the
  definition, because the caller cannot tell.

# Provenance and what this does NOT say

Measured on seven at `89f5a6c8d`, watcher stopped, as part of enrolling the six
never-run real-program jobs. A green here would say the curated quickjs-ng smoke
compiles, evaluates `smoke.js` and is byte-exact against `smoke.expected`.

**It is not related to the `test-sqlite-threads-*` or other passing corpus rows**,
and a green here would not re-prove any of them.

`test-quickjs` is currently in NO tier, so nothing re-measures this. Enrollment of
the four GREEN jobs proceeds separately; this job and `test-duktape` are held
pending an owner decision on whether they enroll visible-but-not-blocking (a
`pin-allowlist.tsv` entry naming this ticket) or wait until this lane clears them.
Auto-pin is armed, so an unallowlisted red here would stop pins firing at all.
