---
slug: feature-a-a-tagged-transient-region-for-conversions-that-have-no-handle-to-refcount
track: A
type: feature
prio: 30
status: backlog
owner: ""
created: 2026-09-14
found-by: frank-user
tags: [arc, strings, c-seam, threads, design]
blocked-by: []
summary: "Owner's direction, restated 2026-09-14 from an early-days exchange: `there's no shame in a certain garbage collection ... sometimes it would be easier to just alloc memory, tag it, use it, have it collect after we proven it's no longer in use`, and he names the thread-safe PChar conversion as the typical case. The prior answer -- mine -- was `not needed, procedure exit cleans up temps`, and that was too narrow: IRParkManagedStr IS alloc-tag-use-collect, with a refcount for the tag and lexical scope for the proof. What it cannot serve is a conversion with NO HANDLE to refcount -- one that must BUILD bytes (append a NUL, transcode, format) -- and that case has exactly one answer in the tree today, a file-scope static, which is the bug gtk3's PC() just was. NOT a rewrite of ARC and not a tracing collector: a per-thread bump region, reclaimed at a proven point, for transients at a foreign seam. Thread safety falls out of per-thread rather than being designed in. THE OPEN QUESTION IS THE RECLAIM POINT, not the allocator."
---

# The owner's framing, and why the old answer was too narrow

*"i said — there's no shame in a certain garbage collection. you concluded it
wasn't needed, since — procedure exit — clean up temps. but it's both sides of
the same medal. sometimes it would be easier to just alloc memory, tag it, use
it, have it collect after we proven it's no longer in use. this (thread-safe)
pchar conversion would be a pretty typical use case."* — owner, 2026-09-14

He is right that they are one medal. `IRParkManagedStr` (`compiler/ir.inc:4528`)
allocates, tags, uses and collects: the tag is a refcount, and the proof is the
enclosing scope's exit. That is his scheme with a per-object tag instead of a
per-region one.

**What that choice costs, visible in the code:** ~130 lines across
`IRParkManagedStr` / `IRParkManagedDyn`, seven managed-string-temp seams, and a
whole twin of the mechanism — the comment at `ir.inc:4595` says why the string
park could not see dyn arrays, *"a dyn-array-typed node already reads
tyPointer"*. Most of that complexity answers one question, **who owns this
temp**: `IRParkManagedStr` *"returns val UNCHANGED when the value is ALREADY
OWNED"*, and getting that predicate wrong is a double free in one direction and
a leak in the other. **A region never asks the question.** The region owns it.

# The case refcounting cannot serve at all

A refcount needs a handle. Every conversion that must **build bytes** has none:
append a NUL, transcode to UTF-16, render a format. There is no object to tag,
so the only answer in the tree is a file-scope static — which is what
`lib/pcl/gtk3.pas`'s `PC()` was until 2026-09-14, four 1024-byte slots, and it
had both failure modes a static has: it overran, and it collided with itself
inside one call. See
[[bug-b-gtk3-pc-writes-past-its-buffer-on-a-long-string]].

# What was MEASURED, and it shrinks the case rather than making it

Three probes, 2026-09-14, all NEGATIVE for a hole:

| probe | result |
| --- | --- |
| managed string, lengths 0..4096, 3 construction routes | NUL always present (`builtinheap.pas:2386` reserves it) |
| `PChar(f)` for `f: string[16] := 'abc'` | `strlen` = 3, NUL ok |
| `PChar(a)` for `a: string[16]` filled to **exactly 16** | `strlen` = 16, NUL ok |

So the RTL's own string seams do not currently need this. **The population that
bit is hand-written bindings**, where somebody reached for a static because the
language offered nothing else. That is the honest size of it today, and it is
the number to re-measure before anyone builds anything.

# The open question is the RECLAIM POINT

Not the allocator — a per-thread bump pointer is a morning's work and is
thread-safe by construction, which is the owner's parenthesis and the part that
matters most after the CLONE_SETTLS week.

- **Statement end** is the tight bound and matches what FPC guarantees for
  `PChar` of a temporary. Cheap to prove: the compiler knows where a statement
  ends.
- **Scope exit** is the conservative fallback and is what the park already does.

Either is only sound if nothing captured a pointer into the region — the same
escape question every region scheme has, and the reason this is a ticket and not
a patch. **Do not start with the allocator.** Start by deciding which of the two
bounds is provable with what the compiler already knows, because that decides
whether the thing is worth having.
