/* Fixture for tests/expected/cheader-struct.out — exercises named C
   struct ingestion (struct Tag {...}), typedef-struct ingestion
   (typedef struct {...} Name), nested-struct fields, and anonymous
   inline struct fields. */

struct CHPoint {
    int x;
    int y;
};

typedef struct {
    int code;
    int detail;
} CHStatus;

struct CHBoxed {
    int tag;
    struct CHPoint p;
};

struct CHWithAnon {
    int kind;
    struct { int a; int b; } point;
};
