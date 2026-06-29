typedef unsigned char u8;
typedef unsigned short u16;

#define OP_Ne 52

const u8 tbl[300] = {1, 2, 3};
const u8 *p = &tbl[256 - OP_Ne];

const u16 wide[300] = {10, 20, 30};
const u16 *wp = &wide[256 - OP_Ne];

int main(void) {
  if ((int)(p - tbl) != 204) return 1;
  if ((int)(wp - wide) != 204) return 2;
  if ((int)((const u8 *)wp - (const u8 *)wide) != 408) return 3;
  return 42;
}
