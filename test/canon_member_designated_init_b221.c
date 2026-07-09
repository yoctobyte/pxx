/* Anonymous struct/union member init (C11 6.7.2.1 / -fms-extensions).
   A promoted anon member re-groups for an inner brace: positional {{6,5}},
   designated {{.b=7,.a=8}}, and union-level promoted designators {.b,.a}. -> 42. */
typedef unsigned char u8;
struct S { u8 a, b; u8 c[2]; };
union UV { struct { u8 a, b; }; struct S s; };
union UV g_pos = {{6, 5}};
union UV g_des = {{.b = 7, .a = 8}};
union UV g_top = {.b = 8, .a = 7};
int main(void) {
  union UV l = {{.b = 3, .a = 4}};
  int ok = (g_pos.a==6 && g_pos.b==5)
        && (g_des.a==8 && g_des.b==7)
        && (g_top.a==7 && g_top.b==8)
        && (l.a==4 && l.b==3);
  return ok ? 42 : 1;
}
