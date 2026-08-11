---
track: N
prio: 70
type: bug
status: done
owner: claude-an-1
summary: "exec()'s `__body__` trampoline is boxed with PyBoxObj, which stamps VT_OBJECT on a CODE ADDRESS. Dormant for as long as it existed; the moment the callee guard asked a tag-7 receiver for its `__call__`, GetInstanceRTTI read a class pointer out of the bytes before the trampoline and walked garbage. This is test-uforth#00."
---

# The exec() `__body__` trampoline is boxed as an OBJECT

Closes Track T's open regression **test-uforth#00** (plexus), bad
`6590c700cbca`, last good `c5ed9a8311c2`.

## The bisect is right and the conclusion it invites is wrong

Both sides reproduced directly, building each commit:

| commit | uforth smoke |
| --- | --- |
| `c5ed9a8311c2` | prints `3 3` |
| `6590c700cbca` (the callee guard) | **SIGSEGV**, no output at all |

So the guard commit is genuinely where it starts — but the guard is not the
defect and **must not be reverted**. It exposed a mis-tag that had been sitting
in `pyeval.pas` harmlessly:

```pascal
l.store(MakeStr('__body__'), PyBoxObj(Pointer(@PyBodyTramp)));
```

`PyBoxObj` stamps `VT_OBJECT` (7) — the tag that asserts "my payload is a
headered heap instance" — onto a **code address**. Nothing in the runtime ever
inspected a tag-7 payload *as an instance*, so the claim was never tested and
the lie stayed inert. The guard then added, for a tag-7 receiver:

```pascal
if PyFindMethCI(GetInstanceRTTI(Pointer(...Payload)), '__call__') = nil then
```

`GetInstanceRTTI` reads the class pointer at `[p-8]`. For the trampoline that is
whatever bytes precede its entry point, so `PyFindMethCI` walked a garbage
`ParentRTTI` chain and the process died — with uforth's output still in the
buffer, which is why the test log showed nothing rather than a partial run.

## Fix

`pyvar_of_callable` instead of `PyBoxObj`. It stamps `VT_CALLABLE` (12) for a
bare code address — the tag added by
[[feature-nilpy-a-callable-value-needs-its-own-variant-tag]] for exactly this
shape — and takes no phantom reference (`PyBoxObj` also called `PXXObjRetain`
on a static address; magic-guarded, so a no-op, but it was asserting ownership
of something it could not own).

Dispatch is unchanged: `pyvar_callv<n>` sees tag 12, the guard allows it,
`PyCallableObj` finds neither closure nor bound-fn magic, and the payload is
called as the code address it always was.

## Sibling sweep

Every other `PyBoxObj` call site was checked and boxes a genuine object — an
instance, a `TPyBytes`, a `TPyList`. This was the only one handing it code.

## Two measurement traps this hit, recorded because both nearly won

- **The gdb backtrace was corrupt.** Frame #2 was raw code bytes and frame #1
  symbolized to `__pxx_run_finalizers`, which read as "crashes at exit". A
  breakpoint on that function was never reached, so the attribution was false.
  `.map` files carry no symbol sizes, so nearest-preceding-symbol lookup will
  name a function that merely sits below the address.
- **The first control did not remove the variable.** Disabling `PyNotCallable`
  at HEAD left uforth still crashing, which looked like it cleared the guard of
  suspicion. It did not: `PyCallDunder` (added the same day) makes the identical
  unguarded `GetInstanceRTTI` call, so one caller was still live. What settled it
  was the cheapest possible probe — print the tag-7 payload, symbolize it
  against the `.map`: `PyBodyTramp`.

## Gate

`make test-uforth` (smoke + the differential corpora + the ANS suite) and
`tools/gate.sh quick` + self-host byte-identical.

## Verified

- `make test-uforth`: **PASS — smoke + 17/17 corpora byte-identical to CPython**
  (was: SIGSEGV with no output at all).
- `tools/gate.sh quick` GREEN, self-host fixedpoint.
- Both bisect endpoints rebuilt and run by hand to confirm the range before
  touching anything: `c5ed9a8311c2` prints `3 3`, `6590c700cbca` cores.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
