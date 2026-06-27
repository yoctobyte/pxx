/* Pointer-field null assignment must clear the full pointer width. Lua's
   luaZ_initbuffer initializes Mbuffer.buffer this way. Exit 42. */
typedef unsigned long size_t;

typedef struct Zio ZIO;

typedef struct Mbuffer {
  char *buffer;
  size_t n;
  size_t buffsize;
} Mbuffer;

typedef struct Vardesc {
  short vd;
} Vardesc;

typedef struct Labellist {
  void *arr;
  int n;
  int size;
} Labellist;

typedef struct Dyndata {
  struct { Vardesc *arr; int n; int size; } actvar;
  Labellist gt;
  Labellist label;
} Dyndata;

#define NULL ((void *)0)
#define initbuffer(L, buff) ((buff)->buffer = NULL, (buff)->buffsize = 123)

struct Parser {
  ZIO *z;
  Mbuffer buff;
  Dyndata dyd;
  const char *mode;
  const char *name;
};

struct Zio {
  size_t n;
  const char *p;
};

int main(void) {
  struct Parser p;
  p.buff.buffer = (char *)0x7fff00000000L;
  initbuffer(0, &p.buff);
  return (p.buff.buffer == 0 && p.buff.buffsize == 123) ? 42 : 1;
}
