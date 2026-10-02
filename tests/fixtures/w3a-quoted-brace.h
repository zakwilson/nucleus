/* A brace inside a character or string literal must not count toward brace
   depth in the signature prescan. GLib's GVariantClass has `'{'` and `'('`;
   miscounting it hid every later type (GObject, GtkWidget) from defn signatures. */
typedef enum
{
  QB_TUPLE = '(',
  QB_DICT_ENTRY = '{',
  QB_ESCAPED = '\''
} QBClass;

static const char qb_brace[] = "{";

typedef struct _QBLater QBLater;
struct _QBLater { int a; };
