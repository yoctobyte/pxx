/* Test C header for struct field access (axis 3) and typed pointer fields
   (axis 2). Pure type declarations; no functions, so nothing is linked. */
typedef struct {
  int x;
  int y;
} Point;

typedef struct {
  int id;
  char *name;
  Point origin;
} Item;
