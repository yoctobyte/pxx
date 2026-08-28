---
slug: bug-p-a-generic-prerequisite-is-emitted-before-the-referenced-template-exists
track: P
prio: 60
type: bug
status: unfinished
blocked-by: []
summary: "The mode-Delphi rewrite emits a template's alias declaration right behind THAT template's own declaration, so a prerequisite naming a template declared LATER in the same type section lands before it exists and dies `undefined variable (specialize)`. rtl-generics does exactly this: `TGStringComparer` (~985) has a method body at 3250 naming `TGOrdinalStringComparer`, declared at 1002. This is rung 6's wall in BOTH units now. FPC compiles the 8-line repro and prints 7."
owner: frankA
---

# A generic prerequisite is emitted before the referenced template exists

- **Track P** (Pascal frontend — generic specialization ordering).
- Found 2026-08-28 by frankA, immediately behind
  [[bug-p-mutually-referencing-generics-are-rejected-as-circular]].
- Third and last of the ordering family, after that one and
  [[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]].

## Repro (mode Delphi; FPC prints `7`)

```pascal
program m;
{$MODE DELPHI}{$H+}
type
  TEq<T> = class
    class function Make: LongInt;
  end;

  TDel<T> = class(TEq<T>)      // declared AFTER TEq
    class function Val: LongInt;
  end;

class function TEq<T>.Make: LongInt;
begin
  Result := TDel<T>.Val;       // named from a template declared EARLIER
end;

class function TDel<T>.Val: LongInt;
begin
  Result := 7;
end;

type TE1 = TEq<LongInt>;
begin
  WriteLn(TE1.Make);
end.
```

```
pascal26:14: error: undefined variable (specialize)
```

`--debug` shows `SPEC TEq$LongInt = TEq nested=0`: at the moment `TEq`'s alias is
specialized, `TDel` is not yet a template, so its `TDel<T>` has not been rewritten
to `specialize TDel<T>` and the prerequisite scan has nothing to match.

## Cause — placement, not discovery

`DelphiRewriteGenericUses` inserts a template's alias declaration at `insertAt`,
**right behind that template's own declaration** (see its header comment: *"ONE
alias declaration … inserted at insertAt (right after the template declaration,
still inside the type section)"*). Everything that alias's specialization needs
must therefore already exist at that point — and a template declared later in the
same type section does not.

The rewrite itself runs to a fixed point over every template each round and does
eventually rewrite the later body; the specialization simply happens too early to
see it.

## Corpus — this is rung 6's wall, in both units

`generics.defaults.pas:3250`:

| | line |
| --- | --- |
| `TGStringComparer<T, THashFactory>` declared | ~985 |
| `TGOrdinalStringComparer<T, THashFactory>` declared | **1002** |
| `TGStringComparer.Ordinal`'s body names it | 3250 |

`generics.collections.pas` `uses Generics.Defaults` and so dies at the same line
without reaching any of its own — as it has behind every previous wall.

## CORRECTION 2026-08-28 (frankA): the direction below is WRONG, and so is the title

Measured before acting on it, and it does not survive. `--debug` on the repro:

```
failing order:   SPEC TEq$LongInt = TEq nested=0
working order:   SPEC TEq$LongInt = TEq nested=1
                   needs TDel2$LongInt from TDel2
```

**Nothing is emitted in the wrong place, because nothing is found at all.** At the
moment `TEq`'s alias is specialized, `TDel` is not yet a template and its
`TDel<T>` has not been rewritten to `specialize TDel<T>`, so the prerequisite
scan has nothing to match. The information does not exist yet, and no bounded
scan can recover it — the rewrite cannot mark `TDel<T>` until `TDel` is known to
be a template, which requires parsing its declaration.

So "emit at the end of the type section" would move an emission that never
happens. The ticket's own summary — *"lands before it exists"* — describes a
consequence I inferred rather than the mechanism I measured, and the isolating
control confirms the real variable is declaration ORDER: the identical program
with the referenced template declared FIRST compiles and prints 7.

Recorded rather than quietly rewritten, because the wrong direction was
reasoning-shaped and plausible, and a later reader would have spent the same
session rediscovering that it is empty.

## Revised direction (also unmeasured — treat as a direction)

A method-body reference is a **materialisation-time** prerequisite
([[bug-p-mutually-referencing-generics-are-rejected-as-circular]] established
that), so it should be *discovered* at materialisation time too, not at class
specialization time. When a method is streamed for a specialization — via
`BufferGenericMethod`'s tail, or `FlushPendingClassSpecializations` — the parser
is past the type section and **every template in the file is known**. Scanning
the method's range there, and emitting any still-unknown alias before the
streamed body, would put discovery and need at the same point in time.

Discovery is currently split from need: it happens when the CLASS is specialized,
and is used when the METHOD is streamed. The whole ordering family comes from
that gap. This is the third defect in it, so the gap, rather than any one
symptom, is what to close.

## Superseded direction (kept for the record)

Emit materialisation-time prerequisites at the **end of the type section**
rather than immediately after the referencing template, since by then every
template in the section is declared. `FlushPendingClassSpecializations` already
runs at exactly that boundary, for exactly the reason that a `procedure` token
cannot appear mid-type-section — so the machinery and the timing both exist.
Measure before believing it.

**Do not "fix" this by making the rewrite emit aliases at the end of the type
section for everything.** Declaration-time prerequisites — a parent class — must
still precede their dependents, and moving all of them would break the ordering
the deferral path depends on. The two kinds are already distinguished
(`nDeclEdges` in `ParseSpecialization`); this is about where the second kind
lands, not about collapsing the distinction.


## Banked diagnosis 2026-08-28 (frankA) — parked, no code changed

Investigated to the point where the shape of the fix is known and the cheap
version is ruled out. **No code was changed in this pass**; the ticket's own
stated direction was refuted (see the correction above) and the replacement is
larger than it looks. Recording why, so the next session starts from the
constraint rather than rediscovering it.

### The isolating control

Same program, only the declaration ORDER changed:

| | result |
| --- | --- |
| referenced template declared FIRST | compiles, prints `7` (matches FPC) |
| referenced template declared AFTER | `undefined variable (specialize)` |

So the variable really is order, and the failure is not scaffolding — the second
form is byte-identical apart from the swap. (Two earlier repro attempts DID fail
for unrelated reasons — a parenthesised class reference and a method-local type
section, both unsupported generally, the first identically on `pinned`. Check any
new repro against a plain non-generic class before trusting it.)

### Discovery and need happen at different times, and that gap is the family

- A method-body `specialize X<..>` is **discovered** when the CLASS is
  specialized — `ParseSpecialization`, which for mode Delphi runs right behind
  the template declaration.
- It is **needed** when the METHOD is streamed — `BufferGenericMethod`'s tail or
  `FlushPendingClassSpecializations`, long after the type section.

All three ordering defects closed today live in that gap. This one is the case
where discovery is not merely early but **impossible**: at class-specialization
time the referenced template has not been declared, so its `TDel<T>` has not been
rewritten to `specialize TDel<T>`, and no bounded scan can find what is not yet
marked. The rewrite cannot mark it either — marking requires knowing `TDel` is a
template, which requires parsing its declaration.

**So the fix must move DISCOVERY to materialisation time**, where every template
in the file is known. That much is sound.

### The constraint that makes it non-trivial, and the reason to park rather than start

The obvious implementation — at each method-materialisation call site, scan the
method range and emit any unknown alias declarations before streaming — **does
not work as written**, and the reason is one line:

```pascal
function NestedSpecKnown(const nm: AnsiString): Boolean;
begin
  Result := (FindSpecialization(nm) >= 0) or (FindUClass(nm) >= 0);
end;
```

It consults **registered** specializations, not inserted tokens. `SpecializeStream`
collapses `specialize X<..>` to the alias *only if* `NestedSpecKnown` is already
true at collapse time, and inserting a declaration does not register anything —
the parser has to reach it. So:

- Emit the declaration **before** streaming → it is not yet registered when the
  body is collapsed; the literal `specialize` is baked into the emitted body
  anyway. No change.
- Emit it **after** streaming → the body was already collapsed wrong. Too late.

The alias must be registered *between* the two, which means the method's
streaming has to be **deferred and retried** once the declaration is parsed —
a method-level analogue of the class-level deferral in `ParseSpecialization`.
That is a new mechanism in the most delicate machinery in this file, and it
interacts with the invariant `BufferGenericMethod` maintains by a before/after
split (*"each (method, specialization) pair is materialised exactly once"*): a
retry must not become a second materialisation.

**Do not attempt the emit-before/emit-after version.** Both were reasoned
through and both are dead for the reason above; it will look like a five-line
change and produce no behaviour change at all, which is the worst kind of
outcome to debug.

### Where to start next time

1. Re-run the two-line control above to confirm the defect is still live.
2. Decide whether the method-level retry belongs in `BufferGenericMethod`'s
   streaming loop or in `FlushPendingClassSpecializations` — the corpus case
   goes through the former (the methods are reached by the parser), the
   template-in-a-used-unit case through the latter, and they must not both
   materialise the same pair.
3. `test/test_generic_mutual_reference.pas` and `test/test_generic_cycle_fail.pas`
   are the pair that must stay green/red respectively throughout.
