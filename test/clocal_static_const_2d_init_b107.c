typedef unsigned char u8;

int main(void) {
  u8 state;
  u8 token;
  static const u8 trans[8][8] = {
    { 1, 0, 2, 3, 4, 2, 2, 2, },
    { 1, 1, 2, 3, 4, 2, 2, 2, },
    { 2, 2, 2, 3, 2, 2, 2, 2, },
    { 3, 3, 3, 3, 3, 3, 3, 3, },
    { 4, 4, 4, 4, 4, 4, 4, 4, },
    { 5, 5, 5, 3, 5, 5, 5, 5, },
    { 6, 6, 6, 3, 6, 6, 6, 6, },
    { 7, 7, 7, 3, 7, 7, 7, 7, },
  };

  state = 0;
  token = 4;
  state = trans[state][token];
  token = 3;
  state = trans[state][token];
  return state == 4 ? 42 : 1;
}
