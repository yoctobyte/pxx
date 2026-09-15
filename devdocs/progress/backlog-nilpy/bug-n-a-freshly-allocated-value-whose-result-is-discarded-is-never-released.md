---
type: bug
track: N
prio: 70
status: open
slug: bug-n-a-freshly-allocated-value-whose-result-is-discarded-is-never-released
---

# A call whose FRESH result is discarded never releases it -- methods and containers

`local.bump()` where `bump` returns a newly allocated object, with the result
dropped, leaks it. So does `panel_quad(...)` returning a fresh list. Binding the
same value, or passing it as an argument, is free.

Measured by lekkerzeilen-c8, 2026-09-15, at `375dcc647dd1` and `787d20032` --
i.e. AFTER the construction spelling was fixed in
`done/bug-n-a-construction-whose-value-is-discarded-is-never-released`:

| shape | | bytes/call |
|---|---|---|
| `local = local.bump()` | bound, fresh result | 0.11 |
| `h.q = h.q.bump()` | stored to an attribute | 0.10 |
| `local.bump()` | **discarded, FRESH result** | **80.10** |
| `local.same()` | discarded, returns `self` | 0.09 |
| `h.give()` | discarded, returns `self.q` | 0.09 |
| `mesh.update(panel_quad(...))` | fresh list as an ARGUMENT | 0.23 |
| `panel_quad(...)` | **discarded, FRESH list** | **328.23** |
| `note(12.3)` | discarded, fresh STRING | 0.87 |

## THE BOUNDARY IS "FRESH", AND IT IS WHY THE ONE-LINE FIX IS UNSAFE

Two rows return an EXISTING object (`self`, `self.q`) and are already clean --
they hand back a BORROWED reference, and nothing owes a release. A rule that
binds every discarded call returning a class would bind those too, and the
temp's scope-exit release would then release something it never owned.

That is the same mistake as the parked arg-spill patch in
`done/bug-n-a-construction-consumed-as-a-method-receiver-leaks`: it passed all
963 Track N fixtures and killed the demo in 3.0 s. **Do not fix this at the
parser.** The parser cannot tell a fresh result from a borrowed one.

Strings are the third witness: a discarded fresh string does NOT leak, so
AnsiString ownership is already correct here and widening a rule to cover it
would be the same error in a third position.

## WHERE THE FIX BELONGS

`IRNodeOwnsFreshCallResult` (`compiler/ir_codegen.inc`) already answers "does
this node own a fresh managed object" -- it is what `IRNodeOwnsManagedObj` and
`IRNodeOwnsManagedStr` are built on. The discarded-statement path at the IR
level can ask it and emit a release; the parser cannot.

**Check it covers CONTAINERS, not just user-class instances.** A discarded list
costs 328 bytes against 80 for a 40-byte class -- a whole backing buffer, not an
8-byte reference -- so the container case is the expensive half.

## NOT A LEKKERZEILEN FIX, AND THAT WAS CHECKED RATHER THAN ASSUMED

Every discarded call on a hot path in the demo returns None, a bool, or an
existing attribute: `self.rig.update(dt)` (no return), `self.traffic.update(...)`
(no return), `self.boat.step(...)` (returns an existing object),
`self.rig_data()` (existing), `sail.raise_lower(dt)` (bool). Rank this on the
language, not on that demo.

(c8 withdrew a 137-site census of this that resolved "does this callee return a
value" BY METHOD NAME across the package, so one `update` returning something
marked every `update` in every class. The five above were checked individually.)
