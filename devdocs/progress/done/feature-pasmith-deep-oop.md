---
summary: "pasmith OOP is one linear chain: no interfaces, no is/as, no method pointers, no properties"
type: feature
prio: 60
---

# pasmith: widen OOP beyond the single inheritance chain

- **Type:** feature (fuzzer coverage — Track T owns the tool; findings file into the
  owning lane as always: IR/codegen → A, dialect/frontend → P, RTL → B).
- **Status:** done
- **Opened:** 2026-07-14, user question after [[feature-pasmith-widen-grammar]] landed:
  "does our fuzzer test complex OOP?" It does not. It tests **one axis of OOP, deeply**.
- **Related:** [[feature-pasmith-pascal-program-generator]] (the tool),
  [[feature-pasmith-widen-grammar]] (the non-OOP rungs — records, enums, sets,
  exceptions, parameter modes), [[feature-pasmith-multi-unit-programs]] (the other
  structural gap).

## What the OOP rung tests today (and tests well)

`--classes N` builds a **linear chain** `TC0 < TC1 < ... < TCn`. Every class overrides
its parent's `Calc` / `Name` / `Create` / `Destroy` and calls `inherited`, so a single
call through a base-typed reference walks the whole chain. Objects are declared as the
**base** type and instantiated as **random derived** types, so no call site is statically
resolvable — a devirtualising optimiser that gets it wrong surfaces as an `-O`-level
self-contradiction. Destructors fold into the checksum, making dtor **count and order**
observable. Fields include an ansistring, so refcount/COW interacts with object lifetime.

So: virtual dispatch, vtable construction, `inherited` chains, ctor/dtor ordering. Real
coverage, and the part Csmith structurally cannot reach. It is just **one shape**.

## The holes, ranked by expected yield

The ranking is not arbitrary: the top three are all **silently-wrong-pointer** classes —
the program keeps running and produces a plausible number — which is exactly what a
checksum oracle catches and what a hand-written suite misses.

1. **Interfaces.** No `IUnknown`, no refcounted interface lifetime, no interface-vs-class
   dispatch, no class implementing *two* interfaces (which forces distinct interface
   vtables and an offset-adjusting thunk). Interface refcounting is a lifetime system as
   tricky as ansistring's, and **nothing tests it at all**. Biggest single hole.
2. **`is` / `as`.** No type tests, no checked downcasts. A wrong `as` yields the wrong
   object, silently. Needs a branching hierarchy (below) to be worth anything — casting
   down a linear chain barely exercises the check.
3. **Method pointers** (`procedure of object`). A two-word closure: code pointer + `Self`.
   Mispairing the halves is a classic ABI bug, and it is invisible today.
4. **Properties.** No getters/setters, no indexed or default properties. A property read
   that bypasses its getter is silent — the value is just stale.
5. **Branching hierarchies.** The chain is *linear*, so there are no sibling classes and
   no case where two subclasses of a common base must get distinct vtables. This one is
   also a **prerequisite** for `is`/`as` being meaningful.
6. **Class methods, class vars, abstract methods**, virtual class methods.
7. **Objects in containers / polymorphic collections.** Only fixed `o0..oN` slots exist;
   an array of base-typed refs holding mixed derived types is the ordinary real shape.
8. **Exceptions crossing a method or a destructor.** The exception rung and the class
   rung never interact today: a `raise` inside a virtual call, with a live object needing
   cleanup, is untested — and that intersection is where b339-shaped bugs live.
9. **Overloads / operator overloading, generics, class helpers, nested classes,
   visibility** (`private` is reportedly not enforced at all — 13 of 17 conformance
   reds, per [[feature-pasmith-widen-grammar]]).

## Invariants any of this must keep

Non-negotiable, and they are what makes a finding believable (see the generator's
four invariants):

- **Every object freed exactly once, never touched after.** Interfaces make this
  harder, not easier: an interface reference frees *itself* by refcount, so an object
  held by BOTH an interface and a class reference must not be double-freed by the
  generator's own bookkeeping. Get this wrong and every "double free" the fuzzer reports
  is its own fault.
- **`is`/`as` must be checked or guaranteed.** A failing `as` raises — fine, but it must
  land inside a `try/except`, or the program exits non-zero and the oracle sees a crash
  that is nobody's bug.
- **Terminates by construction.** Method pointers must not be able to form a cycle
  (keep the call graph a DAG, as the free functions already do).
- **UB-free:** no uninitialised field, no abstract method actually called.

## Acceptance

Each rung ships independently and is gated the same way the last widening was:

- `pasmith --check N` — FPC accepts 100% of generated programs (the generator's
  contract). Run after every touch.
- Each new rung is clean **in isolation** against the pxx / FPC / `-O`-level
  differential before it is turned on with the others (that is how the last widening
  attributed three bugs to three causes instead of arguing about a pile).
- Anything found is **deduplicated through the ledger** (`tstate/fuzz/LEDGER.json`) and
  filed into the owning lane, one ticket per distinct cause — never a pile of stub
  reports.
- Log the run here, clean or not. A clean run is a valid result.

## Note on order

Do **interfaces** and the **branching hierarchy** first: the hierarchy is a prerequisite
for `is`/`as` and for polymorphic containers being worth anything, and interfaces are the
one lifetime system in the dialect that has zero fuzz coverage today.

## Log
- 2026-07-15 (opus-trackT) — **Interface rung landed (`--intfs N`); found a real,
  silent pxx bug on first run.** N COM interfaces (GUID'd — FPC requires one for
  `as`/QueryInterface; pxx is lax and accepts a GUID-less `as`, a compat note not a
  bug), one `TInterfacedObject`-derived class implementing all N (>=2 forces distinct
  interface vtables). Objects are held only through interface refs — refcount owns
  their lifetime, the generator never Frees them, and the destructor folds into the
  checksum so Release count/order is observable. Dual-interface thunk is exercised
  via INLINE `(iw as IPasM).IcM(..)` dispatch (temp released in-statement) — NOT a
  stored `as`-alias, whose temporary lifetime is implementation-defined (FPC keeps it
  to end-of-scope) and would fold destruction timing at a moment neither compiler is
  obliged to agree on. That distinction was found the hard way: a stored-alias first
  cut produced FPC=2-of-3 dtors vs the naive 3, the eval-order false-positive class —
  removed.
  Gate: `--check 60 --intfs 3` and `--check 40 --intfs 3 --wide`, 0 FPC rejects.
  Soundness: on interface seeds FPC is self-consistent across `-O`, pxx is
  self-consistent across `-O`, and they cross-diverge on every seed — the
  single-real-bug fingerprint, not generator noise.
  **Finding filed:** [[bug-a-interface-release-on-last-ref-not-destroyed]] — dropping
  the last interface reference (`:= nil`) does not run the destructor on pxx (FPC runs
  it synchronously). Interface RAII silently broken. Airtight 20-line repro in the
  ticket. Per user: don't chase it, file it — that's what the fuzzer is for.
  **Remaining deep-oop rungs** (unstarted): branching hierarchy (prereq for meaningful
  is/as), `is`/`as` type tests + checked downcasts, method pointers (`procedure of
  object`), properties, class methods/vars, polymorphic containers, exceptions
  crossing a destructor.
- 2026-07-15 (opus-trackT) — **Branching-hierarchy + is/as rung landed (`--hier N`);
  CLEAN.** The `--classes` chain is linear (no siblings); `--hier` builds a TREE
  (each node's parent a random earlier node), objects declared as the root and
  instantiated as random nodes so no call site is statically resolvable. Statements:
  `is` type tests (both branches reachable), `as` checked downcasts — every downcast
  guarded by its `is` so none can raise (the checked-or-guaranteed invariant) — and
  virtual dispatch through the root ref. Destructors fold (manual Free, no interface-
  refcount interaction). In `--wide` (clean rung, unlike --intfs).
  Gate: `--check 60 --hier 5` and `--check 40 --wide`, 0 FPC rejects. Differential:
  25 hier-only seeds, **0 divergences** — FPC and pxx agree on sibling vtables, `is`,
  and checked `as`. A clean run is a valid result: this shape is correct on pxx.
  **Remaining deep-oop rungs:** method pointers (`procedure of object`), properties
  (getters/setters, indexed/default), class methods/vars/abstract, polymorphic
  containers (array of base-typed refs), exceptions crossing a destructor.
- 2026-07-15 (opus-trackT) — **Method-pointer rung landed (`--mptrs N`); found a
  second real, silent pxx bug.** A base + derived class with N virtual methods of a
  common signature and a `function(a): longint of object` type; objects held through
  the base type (some derived); random `@obj.Mm` pairings called through a var AND an
  array (the two-word code+Self closure, plus the array/loop store the ABI can botch).
  Non-virtual method pointers already worked (hand-checked); the rung targets the
  virtual-through-base-ref case and found it broken.
  Gate: `--check 50 --mptrs 3` and `--check 20 --wide --mptrs 2 --intfs 2`, 0 FPC
  rejects. FPC self-consistent, pxx self-consistent, cross-diverge every seed.
  **Finding filed:** [[bug-a-method-pointer-virtual-captures-static-address]] —
  `@baseref.VirtualMethod` on a derived instance binds the STATIC base method address,
  not the virtual override; pxx contradicts its own direct virtual dispatch (via ptr
  6, direct 1005). Airtight repro in the ticket.
  Kept `--mptrs` opt-in / out of `--wide` (like `--intfs`): both diverge on ~100% of
  seeds against a known bug, so including them would mask other rungs via
  `--stop-on-new`. Restore to `--wide` once fixed.
  **Remaining deep-oop rungs:** properties (getters/setters, indexed/default), class
  methods/vars/abstract, polymorphic containers, exceptions crossing a destructor.
- 2026-07-15 (opus-trackT) — **Property rung landed (`--props N`); CLEAN.** N scalar
  read/write properties plus one indexed default property. Each getter is a
  NON-IDENTITY pure transform (fp*k) so a getter bypass (raw-field read) shows in the
  checksum; getters/setters are side-effect-free (a getter fires mid-expression where
  Pascal fixes no operand order — a Mix inside would be an eval-order false positive).
  Writes are statements, reads fold the getter result, `o[i]` uses the default
  property. In `--wide` (clean rung).
  Gate: `--check 60 --props 3` and `--check 40 --wide`, 0 FPC rejects. Differential:
  25 props-only seeds, 0 divergences — pxx computes getters/setters, indexed and
  default properties correctly.
  **Remaining deep-oop rungs:** class methods/vars/abstract, polymorphic containers
  (array of base-typed refs, mixed derived), exceptions crossing a destructor.
- 2026-07-15 (opus-trackT) — **Polymorphic-container + exceptions-crossing-destructor
  rungs landed; both CLEAN.**
  *Polymorphic container* (folded into `--hier`): an array of base-typed refs holding
  the mixed derived instances, dispatched virtually in a loop; aliases the owned
  objects (never freed through the array). 0 rejects / 0 divergences.
  *Exceptions crossing a destructor* (`--exdtor N`): own EXd0<EXd1<... chain (from
  Exception) + a class whose virtual method raises a derived EXd while an object is
  live; the object is Freed in `finally` on BOTH the normal and unwinding path,
  exactly once, its destructor folding — the b339-shaped intersection the exception
  and class rungs never touched before. Catch-all Exception handler keeps every
  program exit-0. In `--wide` (rides the existing `uses sysutils`). Gate: `--check 50
  --exdtor 3` and `--check 40 --wide`, 0 rejects; 25 seeds, 0 divergences — pxx
  unwinds through `try/finally` cleanup and base-catches-derived correctly.
  **Deep-oop status:** interfaces (bug), is/as + branching hierarchy (clean), method
  pointers (bug), properties (clean), polymorphic containers (clean), exceptions×dtor
  (clean) all done. Only remaining ranked hole: class methods / class vars / abstract
  methods (#6) — lower yield, left for a follow-up.
- 2026-07-15 (opus-trackT) — **Class-method rung landed (`--clsm N`); CLEAN. Last
  ranked hole — ticket complete.** Class vars (shared state), class methods (implicit
  Self = metaclass), a VIRTUAL class method dispatched three ways (instance, `class
  of` metaclass var, static ref -- all must agree with the runtime type), and abstract
  methods reached only through an override (never called on the abstract base). N
  derived siblings each override the virtual class method + abstract method. In
  `--wide`. Gate: `--check 50 --clsm 3` and `--check 40 --wide`, 0 rejects; 25 seeds,
  0 divergences -- pxx handles metaclass dispatch (the known-landmine path,
  project_fpcunit_green_metaclass_self), class vars, and abstract methods correctly.

  **All ranked deep-oop holes now covered** (interfaces, is/as + branching hierarchy,
  method pointers, properties, polymorphic containers, exceptions × destructor, class
  methods/vars/abstract). Two silent pxx bugs found and filed to Track A (interface
  release; virtual method pointer). Ticket resolved.
- 2026-07-15 — resolved, commit 591f57ef.
