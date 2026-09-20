---
slug: feature-n-there-is-no-wave-module-so-an-unguarded-stdlib-import-walls-tsp
type: feature
track: N
prio: 40
status: done
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

## RESOLVED 2026-09-20 — `lib/rtl/mimic_wave.pas`

Uncompressed RIFF/WAVE, read and write, resolving through the `mimic_` fallback
(`note: wave -> mimic_wave (shim, subset)`). No compiler change: the resolver
already did its half, there was simply no unit behind the name.

Surface implemented: `open`/`openfp`, the context-manager protocol, the six
getters plus `getparams`, the six setters plus `setparams`, `readframes`,
`writeframes`/`writeframesraw`, `rewind`, `tell`, `setpos`, `close`, and
`wave.Error`. `Wave_read`/`Wave_write` are aliases of one class — a Pascal
function has one return type, so two classes would need `open` to return a
common base, and that base is this class. Absent on purpose, and said in the
unit: markers, reading from an open file object, iteration.

### Verification

`test/lib_mimic_wave.npy`, 63 rows, a DIFFERENTIAL that runs unmodified under
CPython — every expectation read off the oracle, not typed from the RIFF
documentation. Green in three places: CPython 3.14.4, pxx at HEAD, and **under
the pinned compiler**, so the row is not inert waiting for a `make pin`. The
file pxx writes is **byte-identical** to the one CPython's own `wave` writes for
the same input, and CPython reads pxx's file back with the right values.

### THE NEGATIVE CONTROL IS THE PART WORTH READING

At 61 rows the test was green under CPython, green at HEAD, green under the
pin, and byte-identical to the oracle's output. **I then broke the shim
deliberately in two places and 61 of 61 stayed green.**

- `byteRate := framerate * blockAlign` changed to `framerate * sampwidth`. Both
  byterate rows were MONO, and on mono `blockAlign == sampwidth` — the two
  expressions are the same number, so no mono row can ever separate them.
- The RIFF chunk-pad skip deleted. The pad byte exists only after an ODD-sized
  chunk and every chunk the fixture wrote was even, so the branch was never
  entered.

Two rows added — `pad.byterate` on the stereo clip, and the hand-built LIST
chunk resized to seven bytes. Both are red on the broken build and green on the
real one. Generalised to the playbook: *two quantities that are equal in your
fixture cannot both be tested by it.*

### WHAT THIS DID NOT DELIVER, which the ticket predicted

`tsp/voice.py` does NOT compile. With `--threadsafe`, its wall moves from
`wave` to **`threading.Condition` at line 79** — `no member Condition came of
the qualifier threading`. That is the RTLEvent/threading hole
(`feature-b-the-rtlevent-family-is-absent-from-the-threading-rtl`), a different
lane and a different ticket. **The wall is cleared; the unit is not delivered**,
exactly as this ticket said would happen.

One correction to this ticket's own framing, for the record: `wave` was found by
the MODULE-SURFACE scan (26 imported, 23 resolve), not by the first-error
census — `voice.py`'s first error was always `threading` at line 26, three lines
above the `wave` import. The census never named `wave` and could not have. That
is the first-failure blindness this tree keeps recording, working in the useful
direction for once: the surface scan sees walls the census cannot.

## Log
- 2026-09-20 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 60d4d96b0.
