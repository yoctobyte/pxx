---
track: N
prio: 70
type: bug
blocked-by: [feature-n-a-callable-value-carries-its-signature-type]
summary: "A def called through a callable value ignores its own default arguments — `al = g; al(1)` where `g(x, lo=7)` answers empty instead of 7, and passing the def as an argument and calling it with fewer args SEGFAULTS. Not rename-specific and not import-specific: a same-file assignment reproduces it, and only a DIRECT call applies defaults. The box carries a code address and no signature, which is exactly the open decision."
---

## Possible duplicate — the 12-file corpus wall may be this same bug

Added 2026-08-19 by frank3-etree (Track B), from the ladder measurement.

[[bug-n-a-user-classs-decode-method-is-hijacked-losing-its-own-parameters]] — the
**largest** wall on the third-party ladder, 12 of 38 non-compiling files — was
filed as a method-name hijack. That premise is **disconfirmed** (20 builtin
method names all dispatch correctly through both receiver shapes). The real
failing construct is:

```python
decode = decoder.decode          # bound method -> a variable
output = decode(b'', final=True) # keyword arg through a callable value
```

which is this ticket's sentence with one word changed: a call through a callable
value loses part of the callee's declared signature — **defaults** here,
**keyword names** there. And this ticket's own summary already names the
mechanism that would explain both: *"the box carries a code address and no
signature."*

**Correction (same day, frank3-etree): I got the disposition wrong here.**
[[feature-n-a-callable-value-carries-its-signature-type]] is in **`done/`** and
landed — its implementation is inside pin v358 — so it is **not** "work already
in flight" and this wall is **not** waiting on it. I wrote that without checking
which directory the ticket was in, which is the `an-artifact's-existence-says-
nothing-about-its-state` failure in its plainest form: I read a `blocked-by`
edge and inferred a live blocker.

What survives the correction is narrower and still useful: the **carrier** is
shared — a callable value that does not carry the callee's signature — and the
missing field differs (defaults here, parameter *names* in the sibling). frank2
(who owns N) has ruled **do not merge**: same carrier, different missing field,
and this ticket is nearly closed. Cross-reference only.

**Not merged by the reporter.** Track B does not own N, and the adjacent p88
signature-record work is frank2's; the merge call is its to make with this
evidence in hand. One caveat carried over deliberately: the minimal repro of the
`decode` shape produces `undefined variable (final)` while the corpus produces
`decode has no parameter named 'final'`, so the two have **not** been shown to be
the same bug — only to be the same shape.

# A call through a callable value drops the callee's defaults

- **Type:** bug — **Track N**. **Found:** 2026-08-18 by frank2-7e, splitting it
  out of [[bug-n-from-import-with-an-as-rename-loses-what-it-renames]], where it
  had been read as part of the rename fault.
- **Measured at:** HEAD `c3b8fc114`.
- **Blocked** on [[decide-how-a-compiled-def-carries-its-signature-when-boxed]] —
  see below; this is not a guess, it is the same missing thing.

## Repro — no import, no rename

```python
def g(x, lo=7):
    return lo

al = g
print(al(1))      # empty   -- CPython prints 7
print(g(1))       # 7       -- direct call is correct
```

| binding | `al(1)` | want |
| --- | --- | --- |
| `from M import g as al` | empty | 7 |
| `from M import g` then `al = g` | empty | 7 |
| same-file `def g` then `al = g` | empty | 7 |
| **same-file `def g`, DIRECT call** | **7 ✅** | |
| `g` passed as an argument, called with fewer args | **SEGFAULT** | 7 |

The rename is irrelevant — it was the shape it happened to be found in. What
matters is whether the call goes through the **value** or straight to the def.

## Why it is blocked rather than fixable now

A callable value is `pybound_new(<code address>, receiver, isFunc)`. It carries
where to jump and nothing about the signature, so the dispatcher cannot know a
parameter was omitted, let alone what to put there. Supplying every argument
works precisely because nothing has to be filled in.

That is the open decision's subject, so fixing this means implementing whatever
that ruling picks. Do NOT paper over it by having the wrapper hardcode defaults:
the wrapper is arity-fixed at build time and would answer for one call shape
while the others keep failing — the "two paths for one construct" trap.

## Not the neighbouring tickets

- **NOT** [[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]]
  (fixed): that fired on plain qualified calls with no callable value anywhere.
- **NOT** [[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]]:
  that is static rebinding and reproduces with **every argument supplied**.
- **Same blocker** as that ticket and as the boxed-procedural-value crash,
  which makes the pending decision gate **three** items.

---

## 2026-08-19 — SUBSUMED by p88. Do not claim this separately.

frank2 measured the relationship while planning
[[feature-n-a-callable-value-carries-its-signature-type]] (A, p88) and reported:
*"p70 IS this ticket, confirmed by measurement not by reading."* A call through a callable
value cannot honour the callee's defaults because **the value does not carry its
signature** — there is nothing to fill defaults from. Fixing the carrier fixes this; there
is no separate work here.

**`blocked-by` REPOINTED to p88 by the coordinator.** It previously named
[[decide-how-a-compiled-def-carries-its-signature-when-boxed]] — which is RESOLVED, so the
ranker read the blocker as met and surfaced this at the top of Track N as claimable. That
is the resolved-decide-still-cited hazard in its exact form: the decision was correctly
re-filed as p88, but the edge pointing at it was not moved with it. **When a `decide-*` is
re-filed into a lane, repoint every `blocked-by` that names it.**

The edge, so it stops surfacing as claimable at the
top of Track N. That is a routing action, not a judgement on the finding: the bug is real
and the repro stays valid. When p88 lands, verify this repro against it and resolve — do
not assume, since "subsumed" is a prediction until the fix exists.

Ranked #1 in Track N at the time this was written, so without the edge the next worker to
pull from `next --track N` would have re-derived work already underway in another lane.


---

## 2026-08-19 — MOSTLY FIXED by p88. One row remains, and it is re-filed.

[[feature-n-a-callable-value-carries-its-signature-type]] landed
(`e78cc5882`, `9bbbbef6c`, `d95ba7bc0`). Every row of the table above was
re-measured against a self-hosted fixedpoint at that work:

| binding | before | now |
| --- | --- | --- |
| `from M import g as al` | empty | **7** |
| `from M import g` then `al = g` | empty | **7** |
| same-file `def g` then `al = g` | empty | **7** |
| same-file `def g`, DIRECT call | 7 | 7 |
| `map(g, xs)` / `sorted(key=g)` | wrong | **correct** |
| `obj.method` as a value | wrong | **correct** |
| **`g` passed as an argument, called with fewer args** | SEGFAULT | **still SEGFAULT** |

The last row is a DIFFERENT carrier, not a gap in the fix: those values ride
tag 12 (the boundfn carrier), not the tag-8 pair the signature record hangs
off. Measured with `PXXDBG=n.procs` — the call site is `pyvar_callv1`, which
routes only tag 8 into the new dispatcher.

Re-filed with the full diagnosis as
[[bug-n-a-module-level-def-taken-as-a-value-loses-its-defaults-on-the-boundfn-carrier]]
(N, p65). **Do not close this ticket on that row** — close it when the re-filed
one lands, or close this now and let that one carry the remainder. Recommend
the latter: everything this ticket described except one carrier is fixed and
verified against CPython by `test/test_nilpy_callable_value_defaults.npy`.
