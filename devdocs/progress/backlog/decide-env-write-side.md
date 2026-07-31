---
summary: "Policy: does pxx support WRITING the environment (setenv/putenv, os.environ[k]=v) — and does a write reach a child?"
type: idea
track: U
prio: 40
---

# decide: the environment's write side

- **Type:** decision (Track U — human policy call, escalate-don't-guess)
- **Status:** backlog
- **Opened:** 2026-07-31, closing out
  [[feature-rtl-environment-variables]] — the READ side is done on all three
  surfaces (Pascal `GetEnvironmentVariable`, NilPy `os.environ.get` / `os.getenv`,
  C `getenv`), and the ticket itself says the write side is a separate question
  that should be decided rather than half-answered.

## The fork

All three read surfaces load `/proc/self/environ` into a process-local buffer.
That was the right call for reading — no codegen, no per-target entry stub, and
every target with `/proc` gets it free. It also means the environment we hold is
a **snapshot of a copy**, which is exactly what makes writing a question:

```c
setenv("TZ", "UTC", 1);      /* who is supposed to see this? */
```
```python
os.environ["SONGFORMATTER_DEBUG"] = "1"
```

The reference implementations differ from us in a way that matters: glibc's
`environ` **is** the array the kernel handed the process, and `execve(argv, environ)`
is how a child inherits it. Our buffer is not that array, so a write is visible
to us and to nobody else unless the spawn path is taught to pass it.

## Options

1. **Don't support writing.** `setenv`/`putenv` stay absent; `os.environ[k] = v`
   raises. Honest, and nothing silently does the wrong thing. Costs us any real
   program that configures a library through the environment (`TZ`, `LC_ALL`,
   `PYTHONHASHSEED`-shaped flags) — and "compile real-world code as-is" is the
   mission, so a raise here is an app-side edit by another name.
2. **Process-local write only.** Mutate our buffer; our own `getenv` sees it, a
   spawned child does not. Matches the reference for the common
   read-your-own-write case and is a few dozen lines. The trap is the case it gets
   WRONG SILENTLY — `setenv` then `fork`/`exec` expecting the child to see it —
   which is precisely the class of bug this project treats as worse than a
   missing feature.
3. **Process-local write, and the spawn path passes our buffer.** Option 2 plus
   `lib/rtl`'s process/exec surface handing the mutated environment to `execve`
   instead of inheriting the kernel's. Correct for both cases; the work is
   bounded and lands in code we already own.

## Recommendation

**Option 3**, staged: land option 2 and the `execve` hand-off in the SAME change
so the silent-divergence window never exists. If that turns out to be more than
it looks, option 1 is a better resting place than option 2 alone — an absent
feature is a diagnostic, a wrong one is a Tuesday afternoon.

## What unblocks

Nothing is blocked on this today; it is the open half of a closed ticket, filed
so the question survives rather than being rediscovered from
`stdlib.c`'s comments.
