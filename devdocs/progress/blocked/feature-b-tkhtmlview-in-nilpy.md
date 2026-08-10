---
track: B
prio: 50
type: feature
blocked-by: [feature-nilpy-import-a-py-module-from-the-library-path, bug-nilpy-text-class-name-binds-the-rtl-file-record]
summary: "Rewrite lib/pcl/tkhtmlview (398 lines of Pascal that has never compiled) in NilPy, where keyword arguments already exist and the library's own consumers already live. Decided over adding named parameters to the Pascal dialect"
status: working
owner: claude-B
---

# Rewrite `tkhtmlview` in NilPy

- **Type:** feature (library) — **Track B** file ownership
- **Decided:** 2026-08-10 by the repo owner, over the alternative of adding
  named parameters to the Pascal dialect
  ([[idea-p-named-parameters-in-the-pascal-dialect]], parked to rainy-day).
- **Replaces:** [[bug-b-tkhtmlview-uses-named-arguments-pascal-does-not-have]] —
  do not fix that file in place; it is being replaced, not repaired.

## Why NilPy rather than fixing the Pascal

`lib/pcl/tkhtmlview.pas` was written as though Pascal had keyword arguments
(`text_.configure(yscrollcommand := bar.set_)`), which it does not, so the unit
has **never compiled** — identically on `pinned`, so this is not a regression.
The two options were to give Pascal named parameters, or to write the file in a
language that already has them.

The decisive argument: named parameters are not standard Pascal, so **no
existing Pascal code will ever use them** — the only consumers would be
pxx-authored wrappers of Python-shaped APIs, and those can simply be Python.
Reinforcing it: Pascal has its own GUI RTL that works entirely differently, so
the typical consumer of a Tk-shaped API is Python code anyway.

Secondary benefits: it is a real test case for NilPy as a **library** language
(as opposed to a program language, which is all it is exercised as today), and
the module's identity is Python — its own header quotes
`from tkhtmlview import HTMLScrolledText`.

## Scope

398 lines. No Pascal consumer exists: the only mentions of `tkhtmlview` outside
the file are **comments** in `lib/pcl/tkinter.pas` and `lib/rtl/markdown.pas`.
Its sole consumer is a NilPy `import`, which is what makes the swap clean.

Verified available for the port:
- NilPy can **subclass a Pascal facade class** — `class E(tk.Frame):` compiles,
  and `HTMLScrolledText` is exactly a Frame subclass;
- NilPy multi-module programs already work (songformatter imports its own
  `settings.py` / `convertrawtext.py`).

## Blocked on one prerequisite

[[feature-nilpy-import-a-py-module-from-the-library-path]]. A `.py` shipped in
`lib/**` is currently **unreachable** — NilPy finds a `.py` module only as a
SIBLING of the importing file; the fall-through chain resolves `.pas` only.
Measured, with the identical file working as a sibling and failing from
`lib/pcl/`. Without that fix the port would land and not be importable, so the
"pure Track B, zero surprises" framing holds only *after* it.

## Guidance for the port

- **Platonic code, no compiler-appeasement workarounds.** This is the standing
  cross-track rule and it matters more than usual here, because the point of the
  exercise is to find NilPy's library-shaped gaps. Write it the way the Python
  would be written; when something does not compile or misbehaves, **file a
  ticket in the owning lane and leave the natural code in place** (`blocked-by:`
  it if truly stuck). Do not reshape the library to dodge a compiler bug — that
  hides exactly what this port exists to surface.
- **Expect gaps, and treat them as output.** Found on 2026-08-10 alone, any of
  which a 398-line library could plausibly hit:
  `bug-nilpy-method-chained-on-open-result-fails-to-parse`,
  `bug-nilpy-dunders-not-dispatched-through-containers` (the `__getitem__`
  half), `bug-nilpy-del-on-a-plain-variable-silently-does-nothing`,
  `bug-nilpy-text-mode-read-n-returns-bytes-not-str`,
  `bug-nilpy-object-dict-key-with-eq-but-no-hash-is-accepted-then-misses`.
- **Keep the header prose.** The existing file's "THE SUBSET, stated plainly"
  paragraph — what it renders and what it ignores — is good documentation and
  should survive the rewrite verbatim.
- **Delete the `.pas` only once the `.py` is in the build**, and check the two
  comment references in `tkinter.pas` / `markdown.pas` still read correctly.

## Gate

`make lib-test` / `make demos` green; a NilPy program importing
`HTMLScrolledText` compiles and renders; `pascal26 SongFormatter.py` builds
(its Track N half is already fixed, so this is the last blocker — see
[[bug-nilpy-songformatter-no-longer-compiles-set-callback-and-get-arity]]).
Build with `$(PXX_STABLE)`; never rebuild the compiler under Track B.

## 2026-08-10 (Track B) — port ATTEMPTED; blocked at its core, on a second thing

Claimed and started. The prerequisite this ticket already names
([[feature-nilpy-import-a-py-module-from-the-library-path]]) was re-verified by
probe first, not read off the board: a `.py` in `lib/pcl/` still fails `import`
while the identical file as a sibling prints `from-lib-pcl`. So placement is
still blocked — but that one was known, and it only stops the file from being
*shipped*, not from being *written*. Development proceeded as a sibling, which
works.

**A second blocker was found, and this one stops the code itself:**
[[bug-nilpy-text-class-name-binds-the-rtl-file-record]]. NilPy binds the class
name `Text` to `lib/rtl/textfile.pas`'s `Text = record` — Pascal's FILE type —
in exactly the two positions a widget library needs: an instance attribute and a
base class. `Canvas` and `Scrollbar` in the same positions are fine, which is
the control that makes it a name collision rather than a façade defect.

**Both candidate designs die on it, which is why this is not writable around:**

- *Frame containing a Text* (the old `.pas`'s shape): the attribute falls back
  to dynamic, so `self.bar.config(command=self.text.yview)` — the canonical
  scrollbar wiring — raises `AttributeError` at run time. Direct calls work;
  passing a bound method as a VALUE does not.
- *Subclassing Text* (real tkhtmlview's actual shape,
  `HTMLScrolledText(ScrolledText)` → `Text`): `class H(tk.Text)` inherits the
  file record, so `H` has no `insert`. `class G(tk.Canvas)` works.

Per the platonic-code rule the natural spelling stays and the ticket is filed;
**no half-port was committed**. A one-way-wired scrollbar would look finished and
scroll wrongly, which is the silent-failure trade this repo keeps refusing.

`blocked-by:` now carries both.

### Banked so the port is short once unblocked

- **`from tkinter import Text` is NOT the fix.** It silences the compile error
  and leaves the attribute dynamic, i.e. it converts a loud failure into the
  run-time one. Do not reach for it.
- **A real façade gap was found and FIXED on the way** (Track B, `lib/pcl`,
  independent of the above): `Text` had no `yview` / `xview` / `yview_scroll` at
  all, though `Canvas` has carried them since it was written — so the canonical
  scrolled-**text** pair could never have worked even without the name
  collision. Verified from Pascal, where a missing method is a hard compile
  error, with a bogus-method control to prove the check was not blind.
- **The error message points at the wrong widget.** The failure reads
  `AttributeError: 'Scrollbar' object has no attribute 'set'` when the offending
  expression is `self.text.yview` in the other argument of the same statement.
  `Scrollbar.set` is healthy. Recorded on the bug ticket; expect to lose time to
  it otherwise.
- The renderer itself (the 398 lines of entity/whitespace/tag handling) is a
  straight transliteration and hit **no** gaps — the blockers are all in the
  three lines that build and wire the widget.
