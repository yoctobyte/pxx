---
slug: feature-n-subprocess-run-has-no-cwd-parameter-and-adding-one-is-a-pal-signature-change
type: feature
track: N
prio: 40
status: open
summary: "`subprocess.run(argv, cwd=...)` refuses with `run has no parameter named 'cwd'` — TSP's menu.py uses it twice. The MECHANISM is one line in the child and the COST is the signature: `cwd` has to travel through `run`, `Popen.Create`, `PalVforkAndExec` and all three PAL backends (posix, esp, wasi), interface and implementation. Characterised, not started. The load-bearing correction to the first reading: `PalBackendVforkAndExec` does a REAL fork despite its name, and the child runs a Pascal path before `execve`, so the chdir belongs in the CHILD and there is no thread-safety hazard — the parent-chdir-and-restore hack that a reader would reach for first is both unnecessary and wrong."
---

# `subprocess.run` has no `cwd`, and the cost is the PAL signature

Row 6 of `devdocs/dev/tsp-compile-wall-inventory-2026-09-20.md`; mechanism
worked out in `devdocs/dev/tsp-rows-4-8-what-shares-a-cause.md`. Reproduced
2026-09-21 at pxx `8e60c44be`:

    pascal26:141: error: Nil Python: run has no parameter named 'cwd'

TSP, `tsp/menu.py`:

    141:  subprocess.run([sys.executable, "-m", "tsp", "view"], cwd=HERE)
    161:  if subprocess.run(argv, cwd=HERE).returncode != 0:

`lib/rtl/subprocess.pas` declares `function run(const argv: Variant): Popen` —
argv and nothing else.

## THE CORRECTION THAT DECIDES THE IMPLEMENTATION

The obvious cheap fix is for the PARENT to `chdir`, spawn, and `chdir` back.
**Do not.** It is racy — a concurrent thread sees the moved cwd — and it is not
needed, because the first reading of the spawn path is wrong in the helpful
direction:

`PalBackendVforkAndExec` is named for `vfork` and **does a real `fork`**. Its
own comment says so:

> *Real fork (not vfork): the child gets its own copy-on-write address space,
> so it can safely run this Pascal child path (dup2/close/execve) without
> clobbering the parent's stack.*

So the child already executes Pascal between fork and `execve` — that is where
the `dup2`/`close` work happens — and a `chdir` there affects the child only.
`SYS_chdir` is already present in the posix backend (7 uses), so the actual
mechanism is **one syscall in an arm that already exists**.

## Why it is filed rather than done

The mechanism is one line; the SIGNATURE is the work. `cwd` has to travel:

- `run` and `call` (`lib/rtl/subprocess.pas`)
- `Popen.Create` (same unit) — note its existing comment, that an omitted
  defaulted Variant parameter hits
  `bug-nilpy-omitted-variant-default-segfaults`, so the redirections are passed
  EXPLICITLY. A new defaulted parameter must respect that.
- `PalVforkAndExec` (`lib/rtl/platform.pas`, interface and body)
- `PalBackendVforkAndExec` in **posix**, **esp** and **wasi**, interface and
  body — six more sites, of which only posix does anything with it.

That is shared PAL surface across three targets, so the honest gate is a cross
build and not `test-nilpy`. Track A's territory by file, Track N's by topic;
whoever takes it should say so before starting rather than after.

## The arms that are NOT posix

esp and wasi should refuse a non-empty `cwd` rather than ignore it. Ignoring it
runs the child in the wrong directory and the program cannot tell — the same
silent-wrong-value shape as row 7 in the companion note. `PAL_ERR_UNSUPPORTED`
is the established answer there (33 PAL entries already refuse deliberately).

## What would retire this

`tsp/menu.py` past line 141, and a fixture that spawns a child which prints its
own cwd, asserting it is the requested directory and **not** the parent's — with
the requested directory chosen so it differs from the parent's, or the row
cannot fail. Plus a row asserting the parent's own cwd is unchanged afterwards,
which is what catches the parent-chdir implementation if someone writes it.
