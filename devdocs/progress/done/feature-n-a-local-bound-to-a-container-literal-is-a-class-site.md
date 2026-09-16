---
track: N
prio: 65
type: feature
blocked-by: []
summary: "A local bound exactly once to a list or dict literal (`out = []`, `seen = {}`) is a certain class site for call-site parameter typing (the runtime TPyList/TPyDict class), the same claim the field typer makes for `self.items = []` and an annotation `out: list` makes by hand. Lekkerzeilen seat's Arm E: 33 parameters / 148 sites in the demo were exactly this asymmetry; seven annotated by hand measured net -5617 B. Fixture: test_nilpy_a_local_bound_to_a_container_literal_is_a_class_site."
status: done
---

# A local bound to a container literal is a class site

Found by the lekkerzeilen seat (2026-09-16) while confirming that a field
bound to `[]` gives a parameter a TPyList claim: `_adopt(verts, ...)`'s three
sites all pass a local bound once to `[]`, and annotating it by hand took the
function from 2898 to 1167 B. `PyStaticReceiverClass`'s once-bound-local arm
recognised only a construction `Cls(...)`; it now also takes a list or dict
literal that is the whole statement (`PyDictLiteralAt` tells a dict from a
set; a set literal is left alone), naming the runtime class. Every other rule
is unchanged: a second binding, an augmented step, a `for`/`as`/`global`
binding, or a disagreeing site still vetoes.

**A claim is a bet** (the seat's observation across three arms, recorded
here because this lever is where it was sharpest): the same TPyList claim
made `_adopt` 60% smaller and `_push` 64% larger on the same binary, and
nothing available before codegen predicts the direction. The full-map diff
is the standing instrument; the census only says which claims moved.

## Log

- 2026-09-16 frankuser (Fable): built on a scratch binary while the subscript-fix tier ran; fixture green, commit d2c4bf4d9.
