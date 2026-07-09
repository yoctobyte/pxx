struct In { int x; int y; };
struct Out { int a; struct In in; int b; };
struct U { int a; struct In s; int b; };
int main(void) {
  int r = 0;
  /* nested CL as positional whole-value element */
  struct Out o1 = {10, (struct In){3,4}, 20};
  r += (o1.a==10 && o1.in.x==3 && o1.in.y==4 && o1.b==20) ? 1 : 0;
  /* nested CL as designated whole-value */
  struct Out o2 = {.a=5, .in=(struct In){7,8}, .b=9};
  r += (o2.a==5 && o2.in.x==7 && o2.in.y==8 && o2.b==9) ? 1 : 0;
  /* struct lvalue as element */
  struct In li = {11,12};
  struct U u1 = {1, li, 2};
  r += (u1.a==1 && u1.s.x==11 && u1.s.y==12 && u1.b==2) ? 1 : 0;
  /* *ptr as element + top-level *ptr */
  struct In *pli = &li;
  struct In li2 = *pli;
  r += (li2.x==11 && li2.y==12) ? 1 : 0;
  struct U u2 = {3, *pli, 4};
  r += (u2.a==3 && u2.s.x==11 && u2.s.y==12 && u2.b==4) ? 1 : 0;
  /* parenthesized struct lvalue */
  struct U u3 = {5, (li), 6};
  r += (u3.s.x==11 && u3.s.y==12) ? 1 : 0;
  /* brace-elision still works (scalars fill In) */
  struct U u4 = {7, 21, 22, 8};
  r += (u4.a==7 && u4.s.x==21 && u4.s.y==22 && u4.b==8) ? 1 : 0;
  return r + 35;  /* 7 checks + 35 = 42 */
}
