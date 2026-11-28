/* A function parameter whose declarator is parenthesised whole:
   `R (fn (void *, T *))`, the same parameter as `R fn (void *, T *)` and so a
   pointer to function (C 6.7.6, 6.7.6.3p8). glibc's regcomp.c, bundled by
   git as compat/regex, walks its parse tree with
     preorder (bin_tree_t *root, reg_errcode_t (fn (void *, bin_tree_t *)), void *extra)
   pxx stopped reading the list at the parenthesis, and `fn` and `extra` were
   undeclared in the body. gcc is the reference (both widths).
   bug-c-a-parenthesised-function-parameter-declarator-is-not-read */
#include <stdio.h>

typedef enum { OK = 0, STOP = 1 } err_t;
typedef struct node { struct node *left, *right, *parent; int val; } node_t;

static err_t preorder (node_t *root, err_t (fn (void *, node_t *)), void *extra);
static err_t postorder (node_t *root, err_t (fn (void *, node_t *)), void *extra);

static err_t sum (void *extra, node_t *n) { *(int *) extra += n->val; return OK; }
static err_t trace (void *extra, node_t *n)
{
  char **p = extra;
  *(*p)++ = (char) ('0' + n->val);
  return n->val == 9 ? STOP : OK;
}

/* glibc's two walks, as regcomp.c has them */
static err_t
preorder (node_t *root, err_t (fn (void *, node_t *)), void *extra)
{
  node_t *node;
  for (node = root; ; )
    {
      err_t err = fn (extra, node);
      if (err != OK)
	return err;
      if (node->left)
	node = node->left;
      else
	{
	  node_t *prev = NULL;
	  while (node->right == prev || node->right == NULL)
	    {
	      prev = node;
	      node = node->parent;
	      if (!node)
		return OK;
	    }
	  node = node->right;
	}
    }
}

static err_t
postorder (node_t *root, err_t (fn (void *, node_t *)), void *extra)
{
  node_t *node, *prev;
  for (node = root; ; )
    {
      while (node->left || node->right)
	if (node->left)
	  node = node->left;
	else
	  node = node->right;
      do
	{
	  err_t err = fn (extra, node);
	  if (err != OK)
	    return err;
	  if (node->parent == NULL)
	    return OK;
	  prev = node;
	  node = node->parent;
	}
      while (node->right == prev || node->right == NULL);
      node = node->right;
    }
}

/* the other spellings of one parameter */
static int a1 (int (fn (int)), int x) { return fn (x); }
static int a2 (int ((fn) (int)), int x) { return fn (x) + 1; }
static int a3 (int ((fn (int))), int x) { return fn (x) + 2; }
static int a4 (int (fn (int v)), int x) { return fn (x) + 3; }
static int a5 (int fn (int), int x) { return fn (x) + 4; }
static int a6 (int (fn) (int), int x) { return fn (x) + 5; }
static int a7 (int (*fn) (int), int x) { return fn (x) + 6; }
static int twice (int v) { return 2 * v; }

int
main (void)
{
  node_t n[7] = { { 0 } };
  int i, total = 0;
  char buf[16], *p = buf;
  err_t e;

  /* 0: root with 1, 2; 1 with 3, 4; 2 with 5, 6 (right only: 6) */
  for (i = 0; i < 7; i++) n[i].val = i;
  n[0].left = &n[1]; n[0].right = &n[2];
  n[1].left = &n[3]; n[1].right = &n[4];
  n[2].right = &n[6];
  n[1].parent = n[2].parent = &n[0];
  n[3].parent = n[4].parent = &n[1];
  n[6].parent = &n[2];
  e = preorder (&n[0], sum, &total);
  printf ("preorder sum %d (%d)\n", total, e);
  e = preorder (&n[0], trace, &p); *p = 0;
  printf ("preorder %s (%d)\n", buf, e);
  p = buf;
  e = postorder (&n[0], trace, &p); *p = 0;
  printf ("postorder %s (%d)\n", buf, e);
  n[4].val = 9; p = buf;
  e = postorder (&n[0], trace, &p); *p = 0;
  printf ("postorder stop %s (%d)\n", buf, e);
  printf ("spellings %d %d %d %d %d %d %d\n", a1 (twice, 1), a2 (twice, 1),
	  a3 (twice, 1), a4 (twice, 1), a5 (twice, 1), a6 (twice, 1), a7 (twice, 1));
  return 0;
}
