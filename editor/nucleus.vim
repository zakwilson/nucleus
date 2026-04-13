" Vim syntax file for Nucleus
" Language: Nucleus (.nuc)

if exists("b:current_syntax")
  finish
endif

setlocal iskeyword+=-,!,?,.,*

syn keyword nucleusTopLevel defn defvar defconst defenum defstruct include extern defmacro
syn keyword nucleusSpecial let cond while do return set! inc!
syn keyword nucleusSpecial cast sizeof alloca char addr-of deref
syn keyword nucleusSpecial ptr-set! ptr+ aref aset! and or not
syn keyword nucleusSpecial quote quasiquote compile-time funcall-void funcall-ptr-1 gensym
syn keyword nucleusSpecial contained . .set!
syn keyword nucleusType i1 i8 i16 i32 i64 ptr void int bool
syn keyword nucleusConstant null true false

syn match nucleusConstant "\<[A-Z][A-Z0-9_-]*\>"
syn match nucleusTypeAnnot ":\zs[^ )\n]\+" contained
syn match nucleusDefName "(defn\s\+\zs[^ :)]\+"
syn match nucleusDefName "(defmacro\s\+\zs[^ :)]\+"
syn match nucleusDefType "(defstruct\s\+\zs[^ :)]\+"
syn match nucleusDefType "(defenum\s\+\zs[^ :)]\+"
syn match nucleusDefVar "(defvar\s\+\zs[^ :)]\+"
syn match nucleusDefVar "(defconst\s\+\zs[^ :)]\+"

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
