---
slug: feature-n-there-is-no-wave-module-so-an-unguarded-stdlib-import-walls-tsp
type: feature
track: N
prio: 40
status: open
summary: "`import wave` has no unit and no shim, and TSP imports it UNGUARDED at `tsp/voice.py:29` — so unlike the ctypes seam beside it, no marker module and no application edit routes around this one. The surface TSP actually uses is six calls (`open` as a context manager, `getparams`, `getnframes`, `readframes`, `setparams`, `writeframes`) over plain RIFF/WAVE chunk parsing; `array` is already there (`lib/rtl/mimic_array.pas`). Independent of the ctypes/`_pxx_backend` work and of the `__pxx__` marker — neither waits on it and it waits on neither."
---

# No `wave` module — and TSP's import of it is unguarded

Row 2 of `devdocs/dev/tsp-compile-wall-inventory-2026-09-20.md`. Measured
2026-09-20 against TSP's live tree `a143976` and pxx `45b8571d7`: of the 26
distinct modules TSP imports, 23 resolve; the three that do not are `ctypes`,
`__pxx__` and `wave`.

## Why this one is worth taking on its own

The other two are one story — the platform seam, which is blocked on
application code that does not exist (`tsp/platform/_pxx_backend.py`), and on
the owner. **`wave` is none of that.** It is ours, it is small, it is plain
stdlib, and `tsp/voice.py:29` imports it **unguarded**:

    import wave

So there is no `try:`/`except ImportError:` to fold away at compile time and no
application edit that avoids it. It blocks whether or not the seam is ever
ported.

## The surface TSP actually uses — six calls, both directions

`tsp/voice.py:205-224`, `scaled_copy()`, which rewrites a 16-bit WAV at a lower
volume:

    with wave.open(path, "rb") as w:
        params = w.getparams()
        data = array.array("h", w.readframes(w.getnframes()))
    ...
    with wave.open(tmp, "wb") as w:
        w.setparams(params)
        w.writeframes(data.tobytes())

That is: `wave.open(path, mode)` returning an object usable as a context
manager, `getparams()` / `setparams()` round-tripping the header tuple
(`nchannels, sampwidth, framerate, nframes, comptype, compname`), `getnframes()`,
`readframes(n)` → bytes, `writeframes(bytes)`. Uncompressed PCM only; TSP never
touches the compressed arms and CPython's `wave` barely supports them either.

Underneath it is RIFF chunk walking — a 12-byte header, a `fmt ` chunk and a
`data` chunk. No codec.

`array` is already present as `lib/rtl/mimic_array.pas`, so the `array.array("h",
...)` on both sides of this function is not an additional gap.

## Shape of the fix

Per `devdocs/dev/pxx-crash-course.md`: a `lib/rtl` unit carries a Pascal AND a
Python surface in ONE unit — this does not need a separate `mimic_` wrapper if a
Pascal WAV reader/writer is written with the Python-shaped entries beside it.
Check first whether one already exists under another name (`lib/rtl/image.pas`
is the precedent for "media format, both surfaces, one unit"); **grep before
writing**, this tree has had a library reported as missing while it was present.

## What would retire this

`tsp/voice.py` compiling, and a fixture that writes a WAV and reads it back
with the params round-tripping — including a `sampwidth` other than 2, so the
expected value is not also the default.

## What this ticket does NOT claim

The census instrument reports the FIRST error per file, so clearing `wave` is
not promised to deliver `voice.py`: the module also uses `subprocess`,
`threading` and a generator expression into `array.array`, any of which may wall
behind it. **The count is a direction, not a size.**
