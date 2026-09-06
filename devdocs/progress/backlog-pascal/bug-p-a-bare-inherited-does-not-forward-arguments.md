---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
---

# A bare `inherited;` does not forward the caller's arguments

`inherited;` with no method name calls the ancestor's method of the same name
and passes THIS method's own parameters to it, unchanged. pxx called it with
zero arguments, so the universal Delphi constructor idiom

```pascal
constructor TMyComponent1.Create(l1: LongInt; l2: ShortString);
begin
  inherited;
end;
```

answered `inherited call argument count mismatch` (fpc testsuite tclass3).

Fixed in `ParseInheritedCallAST` (pasparser_lval.inc): the bare form selects the
parent overload by the CURRENT method's arity and appends one `AN_IDENT` per
parameter, skipping Self, using the caller's own symbols — so a `var` parameter
forwards as the lvalue it already is rather than as a copy.

**Only the bare form, measured rather than assumed.** fpc 3.2.2 refuses
`inherited Create;` against `constructor Create(LongInt; ShortString)` with
*"Wrong number of parameters specified for call to Create"*, while `inherited;`
in the same body compiles and passes the caller's arguments. Naming the method
makes it an ordinary call with an ordinary argument list; leaving it out is what
asks for the forward.

tclass3.pp burned. New test
`test_a_bare_inherited_forwards_the_callers_arguments.pas`, byte-identical to
fpc across a constructor, a destructor, an argumentless virtual, a `var`
parameter, a three-parameter mix and a three-level hierarchy. The
zero-parameter rows are the controls that the case which already worked still
does — a destructor and an argumentless override are where `inherited;` is
written most often, and they take the same new path.
