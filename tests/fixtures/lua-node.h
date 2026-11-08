/* nuc-lua ISSUE-034: a header type that shares a prelude type's name, as Lua's Node. */
typedef union Node { struct NodeKey { int key; int next; } u; double val; } Node;
