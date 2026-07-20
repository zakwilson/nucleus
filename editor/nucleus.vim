" Vim syntax file for Nucleus
" Language: Nucleus (.nuc)

if exists("b:current_syntax")
  finish
endif

setlocal iskeyword+=-,!,?,.,*

syn keyword nucleusTopLevel defn defn- defvar defvar- defconst defconst-
syn keyword nucleusTopLevel defenum defenum- defstruct defstruct-
syn keyword nucleusTopLevel defunion defunion- defprotocol defprotocol-
syn keyword nucleusTopLevel defmacro defmacro- defcast def-rmacro deferror
syn keyword nucleusTopLevel extend import import-use import-prefixed import-only
syn keyword nucleusTopLevel unsafe-import-private declare extern include
syn keyword nucleusTopLevel exclude-prelude ns set-ir-prefix export

syn keyword nucleusSpecial do let with cond case match make while return
syn keyword nucleusSpecial set! inc! dec! label goto label-addr goto-ptr
syn keyword nucleusSpecial cast addr-of deref ptr-set! ptr+ aref aset! sizeof
syn keyword nucleusSpecial alloca char quote quasiquote compile-time gensym
syn keyword nucleusSpecial some none as-ref unwrap unwrap-or if-some when-some
syn keyword nucleusSpecial move defer fn vfn mfn cfn funcall funcall-void
syn keyword nucleusSpecial funcall-ptr-1 funcall-ptr-i32 funcall-ptr-i64
syn keyword nucleusSpecial funcall-ptr-ptr if when unless and or not _and _or
syn keyword nucleusSpecial zero? null? for dotimes doseq doseq-iter into
syn keyword nucleusSpecial into-iter -> unquote unquote-splice get invoke
" Dot/underscore-prefixed access primitives at head position. syn keyword is
" unreliable for keywords that START with '.' even with 'iskeyword' set, so we
" add explicit syn match rules anchored to a leading '(' -- this also avoids
" swallowing a '.' inside a symbol or number (member access like s.x has no
" leading open paren, so it is unaffected).
syn keyword nucleusSpecial contained . .set!
syn match nucleusSpecial "(\.\%(set!\|&\|\)\>"
syn match nucleusSpecial "(_get\>"

syn keyword nucleusType i1 i8 i16 i32 i64 ui8 ui16 ui32 ui64 f32 f64 int bool
syn keyword nucleusType void ptr usize ssize float double ref raw CStr Char
syn keyword nucleusType StrView Self

syn keyword nucleusConstant null true false none

syn match nucleusConstant "\<[A-Z][A-Z0-9_-]*\>"
syn match nucleusTypeAnnot ":\zs[^ )\n]\+" contained
syn match nucleusDefName "(defn\s\+\zs[^ :)]\+"
syn match nucleusDefName "(defmacro\s\+\zs[^ :)]\+"
syn match nucleusDefName "(defcast\s\+\zs[^ :)]\+"
syn match nucleusDefType "(defstruct\s\+\zs[^ :)]\+"
syn match nucleusDefType "(defenum\s\+\zs[^ :)]\+"
syn match nucleusDefType "(defunion\s\+\zs[^ :)]\+"
syn match nucleusDefType "(defprotocol\s\+\zs[^ :)]\+"
syn match nucleusDefVar "(defvar\s\+\zs[^ :)]\+"
syn match nucleusDefVar "(defconst\s\+\zs[^ :)]\+"
syn match nucleusDefVar "(deferror\s\+\zs[^ :)]\+"

syn match nucleusNumber "\<-\?\d\+\>"
syn match nucleusChar "\\\\."
syn region nucleusString start=+"+ skip=+\\\\"+ end=+"+
syn match nucleusComment ";.*$"

hi def link nucleusTopLevel Keyword
hi def link nucleusSpecial Keyword
hi def link nucleusType Type
hi def link nucleusConstant Constant
hi def link nucleusNumber Number
hi def link nucleusChar Character
hi def link nucleusString String
hi def link nucleusComment Comment
hi def link nucleusDefName Function
hi def link nucleusDefType Type
hi def link nucleusDefVar Identifier

let b:current_syntax = "nucleus"
