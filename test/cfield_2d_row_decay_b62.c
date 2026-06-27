typedef struct Item {
  int v;
} Item;

typedef struct G {
  Item *cache[4][2];
  Item *mem;
} G;

int main(void) {
  G g;
  Item item;
  Item **p;
  int i;

  item.v = 42;
  g.mem = &item;
  for (i = 0; i < 4; i++) {
    g.cache[i][0] = g.mem;
    g.cache[i][1] = g.mem;
  }

  p = g.cache[2];
  if (p[0]->v != 42) return 1;
  if (p[1]->v != 42) return 2;

  return 42;
}
