/* Stars over a pointer typedef add to its level: `typedef Glyph *Line;
   Line *line` is `Glyph **line`. It was read as one level over a pointer
   element with no pointee, so line[y][x] strode 8 and a Glyph passed by value
   was loaded through as an address (st's draw(), first frame).
   bug-c-a-pointer-to-a-pointer-typedef-loses-the-pointee */
#include <stdio.h>
#include <stdlib.h>
typedef unsigned int Rune;
typedef struct { Rune u; unsigned short mode; unsigned int fg, bg; } Glyph;
typedef Glyph *Line;
typedef int *IP;
typedef struct { Glyph attr; int x, y; char state; } TCursor;
typedef struct { int row, col; Line *line; Line *alt; int *dirty; TCursor c; int ocx, ocy; } Term;
static Term term;

static void cur(int cx, int cy, Glyph g, int ox, int oy, Glyph og)
{
  printf("%d %d %u %u %u | %d %d %u %u %u\n", cx, cy, g.u, g.mode, g.fg, ox, oy, og.u, og.mode, og.bg);
}

int main(void)
{
  int r, c, v[3] = { 4, 5, 6 };
  IP pv = v, *ip = &pv;
  Line *L;
  term.row = 3; term.col = 4;
  term.line = malloc(term.row * sizeof(Line));
  for (r = 0; r < term.row; r++) {
    term.line[r] = malloc(term.col * sizeof(Glyph));
    for (c = 0; c < term.col; c++) {
      term.line[r][c].u = 'a' + r * 10 + c;
      term.line[r][c].mode = r;
      term.line[r][c].fg = c;
      term.line[r][c].bg = 100 + r;
    }
  }
  L = term.line;
  printf("%d %d %d %d %d\n", (int)sizeof(L[0]), (int)sizeof(L[0][0]), (int)sizeof(*L[1]),
         (int)sizeof(ip[0][0]), ip[0][2]);
  term.c.x = 3; term.c.y = 1; term.ocx = 2; term.ocy = 2;
  printf("%d %u\n", term.line[term.ocy][term.ocx].mode, L[2][3].bg);
  cur(term.c.x, term.c.y, term.line[term.c.y][term.c.x], term.ocx, term.ocy,
      term.line[term.ocy][term.ocx]);
  (*L)[1].fg = 77;
  printf("%u %u %u\n", term.line[0][1].fg, (L[0] + 1)->fg, (term.line[2] + 3)->bg);
  {
    /* siblings in one block-scope declaration */
    IP a = v, *b = &a, c = v + 1, *d = &c;
    Line *e = term.line, f = term.line[1];
    printf("%d %d %d %d %u %u %d\n", b[0][2], d[0][1], (int)sizeof(b[0][0]), (int)sizeof(*d[0]),
           e[2][1].u, f[3].u, (int)sizeof(e[0][0]));
  }
  return 0;
}
