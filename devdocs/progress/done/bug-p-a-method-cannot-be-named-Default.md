---
prio: 70
track: P
owner: frankA
status: done
---

# A method cannot be NAMED `Default`

- **Type:** bug — compile error on valid code, with a diagnostic that points at
  the wrong thing.
- **Track P** (Pascal frontend, name resolution).
- **Pre-existing:** identical on **pinned**. Oracle: FPC 3.2.2 accepts it.
- **Nothing to do with generics**, despite where it was found.

## The defect

```pascal
type
  TCmp = class
    class function Default: LongInt; static;
  end;
```

```
pascal26:5: error: expected method name
```

`default` lexes as its own token kind (`tkDefault`) because the word is also a
property modifier and an array default, and `IsMethodNameTok` did not accept it.
Those are MODIFIER positions, never a method-name position, so accepting it in
name position cannot reinterpret them.

## Why it hid, and why the message made it worse

Found while chasing
[[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]],
where it presented as the third of three stacked failures and was recorded there
as *"a third thing, not understood"*. It looked like a generics bug for one
reason: the name it collides with is the one `TComparer<T>.Default` uses, so
every occurrence was inside generic code. **A plain non-generic class hit it just
as hard** — that control case is what collapsed it from a generics mystery to an
eight-line bug.

The diagnostic actively pointed away: `expected method name` on the declaration
line reads as a syntax error in the surrounding class, not as a reserved-word
collision, so the surrounding construct gets suspected first.

Measured scope: of `Default`, `Message`, `Name`, `Read`, `Write`, `Index`,
`Stored`, `Implements`, `Result`, `Create` and `Free`, **only `Default`**
collided. `Read`/`Write` were already handled — the existing `IsMemberNameTok`
comment explains exactly this class of problem for them, and `Default` was
simply never added.

## Fix

`IsMethodNameKind` is now the single list, with `tkDefault` in it.
`IsMethodNameTokAt` — whose comment claimed it shared the predicate *"so the two
cannot drift"* while carrying a private copy of the set — now genuinely shares
it. `default` was the drift that comment was written to prevent.

Pinned in `test/test_method_named_default.{pas,expected}`, which exercises the
property `default` **modifier** alongside the method name, because that is the
construct a too-eager fix would break. Fails on `pinned`; expectations from the
FPC oracle.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
