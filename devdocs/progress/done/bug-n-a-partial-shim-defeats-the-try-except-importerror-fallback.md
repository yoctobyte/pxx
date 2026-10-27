---
track: N
prio: 60
type: bug
---

# A partial shim defeats the `try: from X import a, b / except ImportError` fallback

Found building songformatter (2026-10-27, peer session). convertrawtext.py
guards PIL like this:

    try: from PIL import Image, ImageEnhance, ImageFilter, ImageDraw
    except ImportError: HAVE_PIL = False

In July PIL did not resolve, so the handler ran. lib/rtl/pil.pas now serves
`Image` only. The module resolved, the handler was skipped, and the build died
at `ImageDraw.Draw` with "an import that bound nothing". Every app with an
optional dependency breaks this way as soon as a partial shim lands.

**Fix.** In a soft (guarded) import run, a from-imported name that the resolved
unit does not serve sets SoftUnitMissed, as a missing module does. A served
name is a class, class alias, routine, symbol, string, set or enum const, type
alias, or package submodule (PyUnitServesName, matched case-insensitively so it
can only over-answer "served"). Outside a guard the use-site diagnostic is
unchanged. This matches CPython, which raises ImportError for the missing name.

Test: test/test_nilpy_a_partial_module_import_raises_importerror_in_a_guard.npy
(configparser plus a name it lacks, CPython oracle). Pin v452 fails to compile it.
