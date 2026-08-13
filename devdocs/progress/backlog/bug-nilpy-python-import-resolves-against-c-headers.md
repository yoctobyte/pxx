---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A NilPy `import X` is satisfied by a C HEADER from lib/crtl/include: `import string` pulls string.h (and warns about host features.h), `import stdio` compiles clean. So a module that does not exist appears to import, and the failure surfaces later as `undefined variable (ascii_lowercase)` — pointing at the wrong thing entirely."
---

# `import string` in a .npy resolves to crtl's `string.h`

- **Type:** bug (a wrong resolution that reads as success) — **Track N**, with a
  Track C surface (the crtl include path)
- **Found:** 2026-08-13, compiling html5lib for
  [[feature-nilpy-thirdparty-libraries-as-targets]] — `constants.py` opens with
  `import string`.

## Measured

```
$ cat st.npy
import string
print(string.ascii_lowercase[:5])

$ pxx st.npy st
warning: #include <features.h> resolved from the host system (/usr/include),
         not pxx's own headers — ABI/macro mismatches ... may silently misbehave
error: undefined variable (ascii_lowercase)
```

The warning is the tell: a **Python** program has no business including
`features.h`. `import string` found `lib/crtl/include/string.h`, and the C
preprocessor then pulled the host system's `features.h`.

It is not special to `string` — any crtl header name imports:

```
$ printf 'import stdio\nprint(1)\n' > p4.npy && pxx p4.npy p4
warning: #include <features.h> ...          <- and it COMPILES
```

`import stdio` is not a Python module and must be `no module named stdio`.
`import math` takes the same route (same warning) and happens to work anyway,
which is the dangerous half: the wrong resolution is invisible when the names
coincidentally line up.

## Why it matters beyond the noise

1. **A missing module reads as present.** The real error surfaces much later and
   names something else — `undefined variable (ascii_lowercase)` sends the
   reader to the attribute, not to the import.
2. **Host headers enter a NilPy build.** The warning is about exactly the ABI
   hazard the crtl exists to avoid; a Python program should not be able to reach
   `/usr/include` at all.
3. `--no-shims` cannot see it. That flag makes a `mimic_*` substitution an
   error, and this is not a shim substitution — it is a header masquerading as a
   module, so a "compiled with no shims" claim would survive it.

## Fix shape

The import resolver's candidate list should be **language-scoped**: a `.npy`
import may resolve to a NilPy module, a `mimic_*` unit or a Pascal unit, and NOT
to a `.h` in the C include path. The C include path belongs to `#include`, not
to `import`. Worth checking the same question for the Rust and Zig frontends
while in there.

Then `import string` correctly reports no module — at which point it becomes a
`mimic_string` request (`ascii_lowercase`, `ascii_uppercase`, `digits`,
`punctuation`, `whitespace`, `capwords`), which is small and is what
html5lib/constants.py actually wants.

## Gate

`import stdio` in a `.npy` is a compile error naming the module; `import string`
either resolves to a real shim or errors, and neither pulls a host header; a
`.npy` build emits no `features.h` warning; the existing NilPy import tests stay
green.
