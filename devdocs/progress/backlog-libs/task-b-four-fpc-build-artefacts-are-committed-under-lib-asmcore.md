---
slug: task-b-four-fpc-build-artefacts-are-committed-under-lib-asmcore
track: B
type: task
prio: 20
status: backlog
found: 2026-09-06
found-by: frank-coordinator
owner: ""
blocked-by: []
summary: "`lib/asmcore/asmcore_base.{o,ppu}` and `lib/asmcore/asmcore_x64.{o,ppu}` are TRACKED IN GIT -- four FPC build artefacts committed at 3d3ed9ab3, in a directory `compiler/compiler.pas` uses and `make bootstrap` compiles with fpc. They are INERT TODAY and that is measured, not assumed: fpc records the source timestamp inside a ppu and rebuilds on any mismatch in either direction, so any checkout makes the .pas disagree with the recorded time and the unit is recompiled. What they are is two committed .ppu in a source tree that nobody knows are there, in the one directory where an fpc-side compile happens. The live version of the hazard is an OPTION change, which the source-time check cannot see: a ppu built with -dFOO is silently reused by a compile without it. Remove them and add the extensions to .gitignore; verify with `make bootstrap` plus the FPC seed canary, which is the consumer that would notice."
---

# Four fpc build artefacts are committed under `lib/asmcore/`

Found by `tools/stray_fpc_artefacts.py` on its first live run.

```
lib/asmcore/asmcore_base.o     lib/asmcore/asmcore_base.ppu
lib/asmcore/asmcore_x64.o      lib/asmcore/asmcore_x64.ppu
```

All four landed in `3d3ed9ab3` (2026-08-27), a NilPy float-repr commit — so they
were swept in, not placed. `asmcore` is used by `compiler/compiler.pas`,
`compiler/asmenc.inc`, `compiler/asmfront.inc`, `compiler/x64enc.inc` and the
`Makefile`, and `asmcore_base.pas` has changed since (`8b89a201d`), so the
committed `.ppu` is built from source the tree no longer has.

## Why this is prio 20 and not higher — the harmless direction is measured

The reflex reading is *"a stale `.ppu` will be believed over the changed
`.pas`"*. **That is false**, measured 2026-09-06 on these exact files: fpc
records the source's timestamp inside the ppu and rebuilds on any mismatch, in
either direction. A copy of `asmcore_base.pas` touched to an *older* time still
produces `File asmcore_base.pas is newer than the one used for creating PPU file`
and a recompile. The message says newer; the behaviour is *not identical, so
rebuild*. Any checkout gives the `.pas` a fresh mtime, so the recorded time never
matches and the unit is always rebuilt.

## Why it is still worth removing

**The mechanism that IS silent is an option change**, and the source-time check
cannot see it:

```
fpc -dFOO t.pas ; ./t   ->  1     (writes uk.ppu)
fpc       t.pas ; ./t   ->  1     SAME DIRECTORY -- the ppu is reused
fpc       t.pas ; ./t   ->  2     clean directory
```

`lib/asmcore/` is the one directory in this tree where an fpc-side compile
happens against tracked sources (`make bootstrap`, and the `gate.sh` FPC seed
canary), and the flags there are not constant across targets. A committed `.ppu`
in that directory is a loaded version of the above waiting on the first run whose
defines differ from 2026-08-27's.

## The work

`git rm` the four literal paths, add `*.ppu` / `*.o` under `lib/` to
`.gitignore`, and verify with `make bootstrap` and the FPC seed canary — that
canary is the consumer that would notice, so a green from it is the receipt.
Do not verify by "nothing changed": nothing changing is the expected outcome
either way, which is why this row states what would have to fail instead.
