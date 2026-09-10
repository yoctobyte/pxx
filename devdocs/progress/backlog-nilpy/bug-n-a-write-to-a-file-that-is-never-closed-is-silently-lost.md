---
slug: bug-n-a-write-to-a-file-that-is-never-closed-is-silently-lost
track: N
type: bug
prio: 70
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, files, silent-wrong-value, data-loss]
blocked-by: []
summary: "`open(p, \"w\").write(\"DATA\")` creates the file and leaves it EMPTY — no error, no warning, the data is gone. With an explicit `.close()` or a `with` block the same write lands correctly, so the buffer exists and nothing drains it when the last reference dies. CPython flushes on deallocation, which is what makes the one-liner a normal idiom rather than a mistake. Not reachable from the lekkerzeilen corpus (it uses `with` everywhere, 0 sites), which is why this is filed rather than urgent — but it is silent data loss on a shape half of Python writes, and a test that reads back what it wrote is the only thing that can see it."
---

# Measured 2026-09-10, compiler `4d3d006cf973`

```python
p = "<tmp>/f.txt"
open(p, "w").write("DATA")
with open(p) as f:
    print(repr(f.read()))          # CPython: 'DATA'   pxx: ''

q = "<tmp>/g.txt"
h = open(q, "w")
h.write("DATA2")
h.close()
with open(q) as f:
    print(repr(f.read()))          # CPython: 'DATA2'  pxx: 'DATA2'
```

Two rows, one difference, and the second row is the control: **the writer
works.** What is missing is the drain when the handle is dropped without a
close.

# Why no existing assertion can see it

Every file test in the tree closes what it opens — a `with` block, or an
explicit `close()` — which is correct style and is exactly why the defect
survives. **A write-then-read-back is the only assertion class that can
observe this**: the write itself succeeds, `open()` succeeds, the file EXISTS
afterwards with the right name and the right mode, and only its CONTENT is
wrong. An assertion on the return value of `write` would pass too.

Same structural blindness as a leak: the operation under test reports success
and the damage is somewhere the success does not look.

# The two candidate fixes

1. **Flush on finalisation.** What CPython does. Needs the file object to have
   a destructor that runs when the last reference goes, which is a question
   about NilPy's object lifetime and not about files.
2. **Write through, no buffer.** `pystdout_write` already does exactly this
   (IR_WRITE emits the syscall inline), so there is precedent — and it makes
   `close()` cheap rather than load-bearing.

Option 2 removes the class instead of catching it, and the performance
argument for a buffer has never been measured here.

# Positive control for whoever takes it

The two-row program above, asserting `'DATA'` on the FIRST row. A control that
only exercises the `with` spelling passes today and certifies the bug.
