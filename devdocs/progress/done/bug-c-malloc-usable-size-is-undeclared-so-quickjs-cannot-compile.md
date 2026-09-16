---
track: C
prio: 60
type: bug
status: done
owner: frankb-56
created: 2026-09-10
found-by: frank-seven
tags: [c-frontend, crtl, malloc, corpus, quickjs]
blocked-by: []
summary: "RESOLVED 2026-09-16 (frankb-56, Track C) -- the DECLARATION half. malloc_usable_size now exists in crtl and answers the TRUE rounded-up size read from the block's own header, never the requested size. THE TICKET'S DESIGN WORRY WAS RIGHT AND IS DISCHARGED RATHER THAN ACCEPTED: PXXAlloc rounds every allocation up to 8 (`size := (size + 7) and not 7`), so a stub returning the request is wrong for every size that is not already a multiple of 8 -- measured, malloc(1) has 8 usable bytes and malloc(100) has 104. PXXFree ALREADY recovered that size as PMachineWord(addr - 8)^ behind a plausibility guard, so the honest answer was retrievable all along and there was never a choice between a wrong stub and nothing. New builtinheap.PXXUsableSize sits BESIDE PXXFree because the -8 is that allocator's header invariant with exactly one other reader; lib/rtl/pxxcio.__pxx_malloc_usable_size is a pass-through carrying no arithmetic, so the bridge cannot go stale against a header change. NULL and an implausible header answer 0, which is safe HERE in a way it is not for the free path, because quickjs's own portable arm returns 0 on platforms that cannot report a size. The probe asserts a RELATION rather than per-allocator constants (usable == (req+7)&~7, usable >= req, usable 8-aligned) and its req=1 and req=7 rows cannot pass by collision, since a request-returning stub gives 1 and 7. THE TICKET'S CENTRAL CLAIM IS FALSE AND THAT IS THE PART TO CARRY FORWARD: 'this is the ONLY thing standing between test-quickjs and a verdict' was a FIRST-FAILURE reading. With it cleared the target still fails, on `call to undeclared function: __builtin_frame_address` at quickjs.c:1723. A census of every __builtin_ quickjs references says that is the LAST one -- clz, clzll, ctz, ctzll and expect are all known, frame_address alone is missing, at exactly one site. So the job is ONE item away, not zero, and that item is tracked separately rather than folded in here."
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

## RESOLVED 2026-09-16 (frankb-56, Track C) — the declaration half

### The design question, discharged rather than accepted

This ticket was right that a stub would be wrong, and right about the mechanism.
What it did not know is that **the true size was already retrievable**:
`PXXFree` reads it back as `PMachineWord(addr - 8)^` behind a plausibility
guard. So there was never a choice between a wrong stub and nothing.

| req | usable | a request-returning stub would say |
| --- | --- | --- |
| 1 | 8 | 1 |
| 7 | 8 | 7 |
| 100 | 104 | 100 |

The first two rows are why the probe cannot pass by collision with the default.

### Where each piece lives, and why

`PXXUsableSize` is in `builtinheap.pas` beside `PXXFree`, **not** in the bridge,
because the `- 8` is that allocator's header invariant and already has exactly
one other reader. A second copy in `pxxcio.pas` would return garbage through a
bridge with no idea it had gone stale if the header ever moved — and the
plausibility guard would report that as **0** rather than failing, which is the
quiet direction. `__pxx_malloc_usable_size` therefore carries no arithmetic.

### THE CENTRAL CLAIM WAS FALSE — a first-failure reading

This ticket said twice that this was *the ONLY thing* between the job and a
verdict. It is not. With it cleared, the compile reaches
`__builtin_frame_address` at `quickjs.c:1723` and stops.

That is the failure mode CLAUDE.md names: a first-failure census reports the
wall in front and is structurally blind to the ones behind it. **So this
resolution does not repeat it.** Every `__builtin_` quickjs references:

    KNOWN    __builtin_clz  __builtin_clzll  __builtin_ctz  __builtin_ctzll
    KNOWN    __builtin_expect
    MISSING  __builtin_frame_address        <- one site, quickjs.c:1723

The job is **one** item away, not zero. Whoever takes that one should know the
shape before starting: `js_get_stack_pointer()` reaches the builtin only because
we announce `__GNUC__`, and the function's own portable `#else` arm takes the
address of a `char` on the stack with a volatile store to keep it there. So the
semantics wanted are "an address in the current frame" for stack-depth checking
— a parser-level reduction in the `__builtin_expect` / `__builtin_constant_p`
family, not necessarily an IR or backend change. The **argument != 0** case (a
CALLER's frame) has no such reduction and must refuse loudly rather than answer
approximately.

### Claims kept apart

`malloc_usable_size` works and is exact. **The quickjs job is NOT green**, and
this ticket does not claim it is.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
