/* A function typedef whose result is an enum (`typedef enum E Processor(...)`)
   declares FUNCTIONS: `static Processor procA;` is a prototype, and procA's
   address is a code address. It registered as an int typedef and procA as a
   4-byte object, so a stored `procA` was 0 (expat's processors: no handler
   ever ran). bug-c-a-function-typedef-returning-an-enum-declares-objects */
#include <stdio.h>
enum E { E_NONE, E_ONE, E_TWO };
typedef struct P *PP;
typedef enum E Processor(PP parser, const char *start, const char *end, const char **endPtr);
typedef enum E (*ProcPtr)(PP parser, const char *start, const char *end, const char **endPtr);
static Processor procA;
static Processor procB, procC;
struct P { Processor *proc; ProcPtr alt; int n; };
static enum E
procA(PP parser, const char *start, const char *end, const char **endPtr)
{ parser->n += 1; parser->proc = procB; *endPtr = end; return E_NONE; }
static enum E
procB(PP parser, const char *start, const char *end, const char **endPtr)
{ parser->n += 10; parser->proc = procC; *endPtr = start + 1; return E_ONE; }
static enum E
procC(PP parser, const char *start, const char *end, const char **endPtr)
{ parser->n += 100; *endPtr = start; return E_TWO; }
int main(void)
{
  struct P p = { procA, procC, 0 };
  const char *s = "abc", *e;
  int r1 = p.proc(&p, s, s + 3, &e), d1 = (int)(e - s);
  int r2 = p.proc(&p, s, s + 3, &e), d2 = (int)(e - s);
  int r3 = p.proc(&p, s, s + 3, &e);
  int r4 = p.alt(&p, s, s + 3, &e);
  printf("%d %d %d %d %d %d %d %d\n", r1, d1, r2, d2, r3, r4, p.n, procA != 0 && procB != procC);
  return 0;
}
