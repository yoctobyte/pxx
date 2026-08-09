---
prio: 50
track: N
type: bug
blocked-by: []
---

# A name assigned from a CALL, then reused as a for-loop target, SEGFAULTS

- **Type:** bug (NilPy, **crash**) — **Track N**
- **Found:** 2026-08-09, reducing a realistic config-reader program that kept
  crashing after two other bugs in it were fixed.
- **Owner:** claude-AN

```python
D = {"a": "1"}

def merged(s):
    m = dict(D)
    m.update(s)
    return m

cfg = {"w": {"h": "1"}}

for name in sorted(cfg.keys()):
    sec = merged(cfg[name])       # `sec` bound from a CALL
    print(sec["h"])

allkeys = set()
for sec in cfg.values():          # ...and reused as a LOOP TARGET
    allkeys |= set(sec.keys())
print(sorted(allkeys))            # SIGSEGV
```

## Narrowed — three one-line variations settle it

| change | result |
| --- | --- |
| as written | **SIGSEGV** |
| `sec = cfg[name]` instead of `sec = merged(...)` | works |
| rename the first binding to `other` | works |

So it needs BOTH: the name bound from a function CALL, and the same name later
used as a for-loop target. Either alone is fine.

## Why it is worth 50

Reusing a short name like `sec`, `row` or `item` for the same KIND of thing in
two loops is ordinary style, and the failure is a crash with no diagnostic. It
also survived two other fixes in the same program, so it is independent of them.

## Where to look

The first binding types `sec` from `merged`'s return (a `TPyDict` class); the
for-loop target then rebinds it to a variant element. That is the same
"one name, two representations" family as
[[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]] (fixed
2026-08-08, unrelated CLASSES widen to a variant) — but here the two are not
unrelated classes, so that widening does not fire and the loop lowering and the
call result disagree about the slot.

Start with `PXXDBG=n.locals` on the repro to see what `sec` is typed as, and
compare against the working `sec = cfg[name]` variant, which is the control that
removes the call from the picture.

## Gate
`.npy` diffed against CPython: the repro; the same shape with the loop first and
the call-binding second; a def-local version as well as module scope; and the
two one-line variations above as controls, so a fix cannot pass by making only
the reported ordering work.

## 2026-08-09 — measured, not started (claude-AN)

### It is PRE-EXISTING, and the control says so

Reproduced identically on `stable_linux_amd64/default/pinned`, so it is not a
regression from any of tonight's NilPy work. Worth stating because it was found
in the same program as two bugs that WERE fixed tonight, and "the last change
broke it" is the cheap wrong answer.

### It is MEMORY CORRUPTION, not a wrong branch

The manifestation is layout-dependent, which is the tell:

| run | result |
| --- | --- |
| plain | SIGSEGV |
| under `gdb` | no crash, prints `[]` |
| with `-dPXX_OBJTRACE` | no crash, prints `[]` |
| at HEAD after the `|=` fix landed | prints `[]` |

So the fix for `bug-nilpy-set-augmented-union-does-nothing` did not change this
bug at all — it changed which SYMPTOM you see, because `|=` used to do nothing
and now reads a corrupted `sec`.

### `-dPXX_OBJTRACE` names the shape: a premature free

The tail of the trace is

```
objtrace A 0x...e78 1     <- allocated, refcount 1
objtrace r 0x...e78 0     <- released to ZERO
objtrace F 0x...e78 0     <- freed
keys []
```

An object is allocated and immediately released to 0 and freed, and the empty
result follows from reading it afterwards. So this is an ARC/lifetime fault —
someone releases a reference they only borrowed — and NOT a typing or dispatch
bug, which is what the "one name, two representations" guess in the section
above assumed.

That also means the fix must be verified with `-dPXX_OBJTRACE` balance rather
than by a passing test: a lifetime bug that stops crashing has not necessarily
stopped being wrong.

### Where that leaves the ticket

The narrowing above still holds — it needs the name bound from a CALL *and*
reused as a loop target — but the mechanism is a release of a borrowed
reference somewhere in that pair, not a slot-type disagreement. Start from the
`objtrace` output on the six-line repro and identify which allocation `0x...e78`
is (the `sec` binding, the `keys()` list, or the `set()` temp) by swapping the
capture, per [[project_variant_object_tag_list_lives_in_four_places]]'s note
that OBJTRACE can be blind to the object you assume it is showing.

Not started: an ARC lifetime fix at the tail of a long session is how a
double-free ships, which is the same call made for
[[bug-nilpy-lambda-returning-a-call-result-container-yields-none]] earlier
tonight.
