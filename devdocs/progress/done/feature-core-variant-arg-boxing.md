---
track: A
prio: 60
type: feature
---

# IRLowerCallArg: box scalars passed to Variant parameters

Filed by the N-lane agent, self-resolved (sole-A confirmed this session).
`l.append(1)` — an int literal to a `const v: Variant` param — hit
IR_UNSUPPORTED (IRLowerAddress of AN_INT_LIT). Now: hidden variant temp via
the ordinary assignment path (IR_VAR_STORE owns tagging), temp address passed
(variant args always pass by address). Parser's by-ref lvalue check gains a
const-Variant escape at both call-arg sites; class-method param parsing now
persists const-ness (mPConst -> ProcParamIsConst) on both decl paths.
Resolved with [[feature-nilpy-list]].
