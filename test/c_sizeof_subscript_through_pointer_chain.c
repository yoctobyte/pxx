/* `sizeof(p2[0][0])` on a `struct big **` answered 8 -- the pointer size --
   where gcc says 40, and so did `sizeof(p3[0][0][0])`.

   THE GENERAL EXPRESSION PATH ALWAYS TYPED THESE CORRECTLY. The measurement
   that shows it is one pair of parentheses: `sizeof((p2[0])[0])`, the identical
   operand, answered 40, because the leading `(` stops CSizeofDescriptorWalk
   from claiming the operand. So this was never a missing capability in the
   type machinery -- it was the token walk peeling one pointer level per
   subscript while carrying only ONE level of pointee (PtrElemTk/PtrElemRec).
   The first peel consumed the last thing it knew; the second ended at
   tyUnknown, whose slot size is 8 -- identical to the correct answer for
   `p2[0]`, which is why it read as working.

   The walk now follows SymPtrDepth/SymPtrBaseTk/SymPtrBaseRec, the carriers
   the `**p` arm already used.

   Assertions are derived: each size is compared against the object actually
   pointed at, and the one-subscript-short rows must equal a POINTER while the
   full-depth rows must not -- a chain that collapses to one default would fail
   both directions. The `**`/`*p[0]` spellings are the control for the route
   that was already correct. */
#include <stdio.h>

struct big { char pad[40]; int n; };

struct big   b0;
struct big  *p1 = &b0;
struct big **p2 = &p1;
struct big ***p3 = &p2;

int main(void) {
  int fails = 0;

  /* full depth reaches the pointed-at object */
  if (sizeof(p2[0][0])    != sizeof(b0)) { printf("FAIL p2[0][0] %zu\n",    sizeof(p2[0][0]));    fails++; }
  if (sizeof(p3[0][0][0]) != sizeof(b0)) { printf("FAIL p3[0][0][0] %zu\n", sizeof(p3[0][0][0])); fails++; }
  if (sizeof(p1[0])       != sizeof(b0)) { printf("FAIL p1[0] %zu\n",       sizeof(p1[0]));       fails++; }

  /* one short of full depth is still a pointer -- the rows that must NOT move */
  if (sizeof(p2[0])    != sizeof(p1)) { printf("FAIL p2[0] %zu\n",    sizeof(p2[0]));    fails++; }
  if (sizeof(p3[0][0]) != sizeof(p1)) { printf("FAIL p3[0][0] %zu\n", sizeof(p3[0][0])); fails++; }
  if (sizeof(p3[0])    != sizeof(p1)) { printf("FAIL p3[0] %zu\n",    sizeof(p3[0]));    fails++; }

  /* the object and the pointer must not be the same number, or the rows above
     are satisfied by a single collapsed default rather than by two answers */
  if (sizeof(b0) == sizeof(p1)) { printf("FAIL struct and pointer sizes coincide\n"); fails++; }

  /* controls: the spellings that reached the expression path all along */
  if (sizeof(**p2)      != sizeof(b0)) { printf("FAIL **p2\n");      fails++; }
  if (sizeof(*p2[0])    != sizeof(b0)) { printf("FAIL *p2[0]\n");    fails++; }
  if (sizeof(*(*p2))    != sizeof(b0)) { printf("FAIL *(*p2)\n");    fails++; }
  if (sizeof((p2[0])[0])!= sizeof(b0)) { printf("FAIL (p2[0])[0]\n");fails++; }

  /* the parenthesised and bare spellings of one operand must agree; they are
     different code paths and disagreeing is how this family was found */
  if (sizeof(p2[0][0]) != sizeof p2[0][0]) { printf("FAIL paren vs bare\n"); fails++; }

  /* a field reached THROUGH the peeled pointer: the chain has to survive the
     subscript for `->` to find the record at all (this answered 1) */
  if (sizeof(p2[0]->pad) != sizeof(b0.pad)) { printf("FAIL p2[0]->pad %zu\n", sizeof(p2[0]->pad)); fails++; }
  if (sizeof(p2[0]->n)   != sizeof(b0.n))   { printf("FAIL p2[0]->n\n");   fails++; }
  if (sizeof(p2[0][0].n) != sizeof(b0.n))   { printf("FAIL p2[0][0].n\n"); fails++; }

  if (fails == 0) printf("PTR CHAIN OK %zu %zu\n", sizeof(p2[0][0]), sizeof(p2[0]));
  return fails;
}
