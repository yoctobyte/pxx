---
slug: bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce
title: "feature-emission-size-dce is done, and `WriteLn('hello')` still emits 63,760 bytes"
track: A
prio: 30
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-08-25
summary: "Raised out of decide-how-much-string-machinery-the-basic-frontend-gets, decided 2026-08-25. That decision accepted ~100 KB BASIC binaries on the grounds that binary size is a GENERAL problem with a general answer (reachability-gated emission), not a per-frontend one. But feature-emission-size-dce is marked done while a Pascal hello-world is still 63,760 bytes -- so either the pass is not reaching this, or the done ticket's scope was narrower than its title."
---

# The measurement

| program | size |
| --- | --- |
| `10 PRINT "hello"` (.bas, no USES) | 559 B |
| `WriteLn('hello')` (.pas) | **63,760 B** |
| `test_basic_comprehensive.bas` (has USES) | 103,935 B |

The mechanism is known and is not subtle: `DetectPascalRuntimeNeeds` sets
`needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING')`, and
`PasApplyDefaults` defines that symbol **unconditionally** — so every Pascal
program pulls `builtinheap`, always, whether or not it touches a managed string.

# Why this is filed as a bug rather than an optimisation

[[feature-emission-size-dce]] is in `done/` and its stated goal is *"emit only
reachable code ... emit a unit routine only if reached from the program entry"*,
with `hello.pas` named in its own text at ~31.6 KB against a ~29 KB reachable
baseline. The current 63,760 bytes is worse than the number the done ticket was
arguing about. Something regressed, or the pass never covered the
unconditional-`PXX_MANAGED_STRING` door, or the ticket closed on a narrower
slice than its title. `root-cause-over-microfix.md` applies: find out which
before writing anything — the answer changes what the fix is.

# What depends on it

[[decide-how-much-string-machinery-the-basic-frontend-gets]] deferred BASIC's
559-byte unit-free binary to this ticket rather than building a BASIC-only
conditional runtime pull. If this lands, that property comes back on its own,
for every frontend, instead of for one.

# Do not

Fix it by making `PXX_MANAGED_STRING` conditional on a source scan in the Pascal
driver. That is the per-frontend special case the BASIC decision rejected, one
language over. The general mechanism is reachability, and it already has a home.

---

## 2026-08-30 — an EMPTY program is 61,279 B, so the hello is ~2 KB of it

Measured at HEAD `4039216a7f25` while building the size canary for
[[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]]:

```
$ printf 'program e;\nbegin\nend.\n' > empty.pas
$ pxx empty.pas out
ok: out  [code=61279B  data=1960B  bss=42452B  procs=129]
```

Against this ticket's 63,760 B for `WriteLn('hello')`, the whole of
`WriteLn('hello')` — the call, the literal, the string machinery it drags in —
is about **2.5 KB on top of a 61.3 KB floor that a program with no statements
already pays.**

That reframes the question the ticket asks. "Either the pass is not reaching
this, or the done ticket's scope was narrower than its title" — the measurement
says it is not about reaching *this program*, because there is no program here
to reach. Whatever is being emitted is emitted for a unit with an empty body, so
the subject is the RTL/startup floor, not the DCE pass's treatment of
`WriteLn`. Anyone starting from the hello-world will spend the first hour
looking at string machinery that accounts for 4% of the number.

`x86_64-empty` is now a **watched** subject: `tools/size_canary.py`, baseline in
`tools/size_baseline.json`, running in native/limited/full as `size-canary#00`.
It is a delta gate — it freezes 61,279 B rather than blessing it — so when this
ticket is fixed the canary reports the shrink out loud and asks to be
re-baselined, and it reds if the floor grows again meanwhile.

*(Measurement and instrument: Track T. The 61 KB itself is this ticket, and
still Track A's.)*

## Re-measured 2026-08-30 — the subject of this ticket is 0.1% of the number

Measured by frank-coordinator against `stable_linux_amd64/default/pinned`
(`1d69760deabe`), after the size canary added an empty-program row nobody had asked for:

| program | code |
| --- | --- |
| `program e; begin end.` | **61,276 B** |
| `program h; begin WriteLn('hello'); end.` | **61,350 B** |

**`WriteLn('hello')` costs 74 bytes on a 61,276-byte floor.**

This ticket's own open question — *"either the pass is not reaching this, or the
done ticket's scope was narrower than its title"* — has a third answer, and it is
the right one: **there is no *this* to reach.** The body is empty and the number
is unchanged. The subject is the **RTL/startup floor**, not emission-size DCE's
treatment of `WriteLn` or of string machinery.

Anyone starting from the hello-world spends their first hour on the ~0.1% and
concludes DCE is broken. It is not this ticket's fault — a hello-world is the
obvious probe, and *the obvious probe put the entire mass in the part that
varies*. The fix is to re-scope onto the floor, or to close this and open one
named for it.

`x86_64-empty` is now a watched subject in `tools/size_canary.py`, so a genuine
reduction arrives as a reported shrink against a frozen baseline rather than as
prose in a ticket. Note it is **advisory**: it reports and files, it does not fail
a tier.
