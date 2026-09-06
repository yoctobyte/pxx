{ `override; abstract;` in the middle of a chain must INHERIT the parent's VMT
  slot, not mint a new one.

  For A -> B -> C where B redeclares a virtual as `override; abstract;` and C
  supplies a real body, a call through an A-typed reference to a C instance ran
  A's body. fpc runs C's. No diagnostic — the program ran and printed a
  plausible wrong answer.

  THE CAUSE WAS A PRECEDENCE, AND THE COMMENT ABOVE IT WAS TRUE. `abstract`
  sets isVirtual ("abstract implies virtual" — correct, an abstract method IS
  dispatched), the slot test was a bare `if isVirtual`, and the abstract row
  therefore took the ALLOCATE arm ahead of the override arm. "Abstract implies
  virtual" is right; "therefore allocate a slot" does not follow, because
  `virtual` and `override` differ in exactly one respect — whether the slot is
  NEW — and abstract says nothing about that.

  THE TWO SPELLINGS THAT LOOK HARDER WERE THE ONES THAT WORKED. `TB(a).Say` and
  `TC(a).Say` both reached C, because they dispatch through the slot B minted;
  only the base-typed reference, which is the ordinary way to use a hierarchy,
  read the stale slot. A test exercising the derived spellings passes under the
  bug.

  ROW A IS THE CONTROL THAT MUST NOT MOVE: `virtual; abstract;` at the ROOT
  still allocates, because isOverride is False there, and it was correct before
  the fix. Rows D and E are the slot-numbering consequence — a second virtual
  declared after an abstract override must keep its own slot, which a
  fix that merely reused the parent slot unconditionally would disturb.

  Every row is fpc 3.2.2 -Mobjfpc's own output for this program.
  bug-p-an-abstract-override-in-the-middle-of-a-chain-hides-the-concrete-override-below-it }
program test_an_abstract_override_keeps_its_parents_vmt_slot;
{$mode objfpc}
type
  TRoot  = class procedure Say; virtual; abstract; end;
  TRoot2 = class(TRoot) procedure Say; override; end;

  TA = class procedure F; virtual; end;
  TB = class(TA) procedure F; override; abstract; end;
  TC = class(TB) procedure F; override; end;
  TD = class(TC) procedure F; override; end;

  TE = class procedure G; virtual; end;
  TF = class(TE) procedure G; override; abstract; end;
  TG = class(TF) procedure G; override; abstract; end;
  TH = class(TG) procedure G; override; end;

  TI = class procedure P1; virtual; procedure P2; virtual; end;
  TJ = class(TI) procedure P1; override; abstract; procedure P2; override; end;
  TK = class(TJ) procedure P1; override; end;

var fails: Integer = 0;
    last: string;

procedure Chk(const what, want: string);
begin
  if last <> want then
  begin
    WriteLn('FAIL ', what, ': got ', last, ' want ', want);
    Inc(fails);
  end;
end;

procedure TRoot2.Say; begin last := 'R2'; end;
procedure TA.F; begin last := 'A'; end;
procedure TC.F; begin last := 'C'; end;
procedure TD.F; begin last := 'D'; end;
procedure TE.G; begin last := 'E'; end;
procedure TH.G; begin last := 'H'; end;
procedure TI.P1; begin last := 'I.P1'; end;
procedure TI.P2; begin last := 'I.P2'; end;
procedure TJ.P2; begin last := 'J.P2'; end;
procedure TK.P1; begin last := 'K.P1'; end;

var r: TRoot; a: TA; e: TE; i: TI; c: TC;
begin
  { A — the control: a ROOT `virtual; abstract;` still allocates its own slot }
  r := TRoot2.Create; r.Say;  Chk('A root virtual;abstract', 'R2');

  { B — the defect: abstract override in the middle, base-typed reference }
  a := TC.Create;     a.F;    Chk('B abstract in the middle', 'C');

  { C — one level deeper, so the fix is not "off by one level" }
  a := TD.Create;     a.F;    Chk('C four levels', 'D');

  { D — TWO stacked abstract overrides between the virtual and the body }
  e := TH.Create;     e.G;    Chk('D stacked abstracts', 'H');

  { E/F — slot NUMBERING: a sibling virtual declared beside the abstract
    override must keep its own slot and not be displaced }
  i := TK.Create;     i.P1;   Chk('E sibling slot P1', 'K.P1');
                      i.P2;   Chk('F sibling slot P2', 'J.P2');

  { G — the derived-typed spellings, which passed UNDER the bug and must
    keep passing: they dispatch through the slot the abstract row minted }
  c := TC.Create;     c.F;    Chk('G derived-typed receiver', 'C');
  TB(c).F;                    Chk('H mid-cast receiver', 'C');

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('ABSTRACTOVERRIDE OK');
end.
