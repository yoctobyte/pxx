---
slug: bug-p-a-generic-prerequisite-is-emitted-before-the-referenced-template-exists
track: P
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "The mode-Delphi rewrite emits a template's alias declaration right behind THAT template's own declaration, so a prerequisite naming a template declared LATER in the same type section lands before it exists and dies `undefined variable (specialize)`. rtl-generics does exactly this: `TGStringComparer` (~985) has a method body at 3250 naming `TGOrdinalStringComparer`, declared at 1002. This is rung 6's wall in BOTH units now. FPC compiles the 8-line repro and prints 7."
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

## Direction (unmeasured — a direction, not a diagnosis)

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
