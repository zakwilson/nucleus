/* Typed C pointers (design/stage23-namespaces/typed-c-pointers.md). */
#include <stddef.h>

typedef struct _TpBase { int tag; } TpBase;
typedef struct _TpMid { TpBase parent; int x; } TpMid;
typedef struct _TpLeaf { TpMid parent; int y; } TpLeaf;
typedef struct _TpHidden TpHidden;
typedef TpHidden TpHidden2;
struct tp_node { struct tp_node *next; int v; };

void tp_take_base(TpBase *b);
void tp_take_mid(TpMid *m);
void tp_take_tagged(struct _TpBase *b);
void tp_take_hidden(TpHidden *h);
void tp_take_node(struct tp_node *n);
void tp_take_charp(char *s);
void tp_take_ucharp(unsigned char *s);
void tp_take_intp(int *n);
void tp_take_sizep(size_t *n);
void tp_take_basepp(TpBase **out);
void tp_take_strv(char **v);
void tp_take_voidp(void *p);
void tp_take_voidpp(void **p);
TpLeaf *tp_make_leaf(void);
TpHidden2 *tp_make_hidden2(void);
