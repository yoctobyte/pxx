---
summary: "PCL: compile-time widgetset selection (--widgetset=) + sparse widgetset×OS matrix that HARD-FAILS unsupported cells with a clear reason (copy LCL -ws)"
type: feature
prio: 40
---

# PCL — compile-time widgetset selection + sparse-matrix hard-fail

- **Type:** feature (**Track B** — `lib/pcl` + a small compiler CLI/define touch).
  Gate = `make lib-test` green; the default (gtk3/linux) unchanged.
- **Status:** backlog. Child of [[feature-pcl-cross-platform-gui]]. Best after
  [[feature-pcl-seam-seal]] (so there's a real seam to select against), but the CLI +
  matrix scaffolding can land alongside.
- **Owner:** —
- **Opened:** 2026-07-21, GUI-scope session.

## Problem

Widgetset is **hardwired**: `lib/pcl/interfaces.pas:6` does `uses gtk3widgets`
unconditionally. There is no `--widgetset`, no OS×widgetset matrix, and nothing stops a
nonsensical combination — it would just fail deep in the build with a confusing error.

LCL solved this: `-ws gtk3` selects the widgetset at **compile time**, baked into the
one binary (matches pxx's zero-dep, no-runtime-plugin identity). Copy that.

## Shape

- **`--widgetset=<gtk3|win32|...>`** selects the backend; drives which widgetset unit
  `interfaces.pas` pulls in (via a define the compiler sets, e.g. `WIDGETSET_GTK3`).
  Default = `gtk3` (today's behaviour, unchanged).
- **Sparse matrix, enforced at compile time.** A small table of supported
  (widgetset × target-OS) cells; an unsupported/untested cell is a **hard compile error
  with a reason**, never a silent broken build:

  ```
  --widgetset=qt --target=x86_64-windows
    → error: widgetset 'qt' not supported/tested on target 'windows'
             (no bundled Qt DLLs). supported on 'windows': win32.
  --widgetset=gtk3 --target=x86_64-windows
    → error: gtk3 on windows means a 30-40 MB DLL bundle; refused by design.
             use --widgetset=win32.
  ```

- Starting matrix (grows by adding a table row, not rewiring):

  | widgetset | linux | windows |
  |---|---|---|
  | gtk3 | ✅ | ❌ refuse (DLL swarm) |
  | win32 | ❌ n/a | ⚠️ best-effort (see [[feature-pcl-win32-widgetset]]) |
  | qt | 🔜 future | ❌ not delivered |

## Acceptance

- `--widgetset=gtk3` (or omitted) on linux = today's build, byte-unchanged; `make
  lib-test`/`demos` green.
- Every unsupported cell above fails at **compile time** with the shown reason.
- Adding a future widgetset = one matrix row + one `TWidgetSet` subclass, no changes to
  the selection machinery.

## Note
The compiler touch is tiny (parse `--widgetset`, set a define, thread it to the OS×ws
guard). If that guard is cleaner as a Track A CLI addition, file the CLI slice as a
small Track A ticket per lane rules; the `lib/pcl` side stays Track B.
