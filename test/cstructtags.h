/* Tag namespace: a bare (non-typedef'd) struct used by value via its tag, and a
   self-referential struct that points to itself through its own tag. */
struct Inner { int a; int b; };

typedef struct {
  struct Inner in;   /* bare-tag struct field, by value */
  int c;
} Outer;

typedef struct Node {
  int val;
  struct Node *next; /* self-reference via the tag */
} Node;
