" indent/nucleus.vim -- indent-expression for the Nucleus language
" Language:    Nucleus (.nuc)
" See:         editor/nucleus.vim for syntax highlighting, and
"              editor/ftdetect-nucleus.vim for filetype detection.
"
" Vim's 'indentexpr' is line-based (no parse tree), so this is a best-effort
" approximation of Nucleus's canonical formatting rules:
"
"   * A continuation line aligns with the previous form at the same nesting
"     level (standard Lisp "indent under the first argument").
"   * Bodies of  defn defmacro defstruct defenum defunion while do compile-time
"     and arms of  match  indent TWO spaces (one 'shiftwidth') past the form's
"     opening paren.
"   * (let (bindings...) body...) / (with (bindings...) body...):
"       - continuation lines INSIDE the binding list align UNDER THE FIRST
"         binding (one space past the binding-list paren);
"       - the body (after the binding list closes) indents +2 past the
"         let/with open paren.
"   * Lines beginning with ')' dedent one level.
"   * cond: tests align under the first test (handled by the generic rule).
"
" Indent convention: 2 spaces.  Set in your vimrc:  filetype plugin indent on
" and  set sw=2 sts=2 et.  This file honors 'shiftwidth'.

if exists("b:did_indent")
  finish
endif
let b:did_indent = 1

setlocal indentexpr=NucleusIndent(v:lnum)
setlocal indentkeys=o,O,0),0]

let s:cpo_save = &cpo
set cpo&vim

" Heads whose body indents one 'shiftwidth' past the form's open paren.
" The trailing '-' (defn-, defmacro-, ...) covers the private variants and is
" allowed via "-\=".  Must be the first token after the open paren.
let s:body_heads = '\%(defn-\=\|defmacro-\=\|defstruct-\=\|defenum-\=\|defunion-\=\|while\|do\|compile-time\|match\)'

" Public entry point. Wrapped so the indent function never throws.
function! NucleusIndent(lnum) abort
  try
    return s:NucleusIndentImpl(a:lnum)
  catch
    let l:pl = prevnonblank(a:lnum - 1)
    return l:pl ? indent(l:pl) : 0
  endtry
endfunction

function! s:NucleusIndentImpl(lnum) abort
  " Current line text, leading whitespace stripped.
  let curline = substitute(getline(a:lnum), '^\s\+', '', '')
  if curline ==# ''
    return -1
  endif

  let prevlnum = prevnonblank(a:lnum - 1)
  if prevlnum == 0
    return 0
  endif
  let prevline = getline(prevlnum)
  let prevind  = indent(prevlnum)

  " Line that begins with ')' dedents one level.
  if curline =~# '^)'
    return max([prevind - shiftwidth(), 0])
  endif

  " Walk back to find the anchor: the most recent line with a still-open '('.
  let anchor = s:FindAnchor(prevlnum)
  if anchor == 0
    " No enclosing form: top level.
    return 0
  endif
  let anchorline = getline(anchor)
  let anchorind  = indent(anchor)
  let stripped   = substitute(anchorline, '^\s\+', '', '')

  " --- body-indents-+2 heads (and match arms) ---
  if stripped =~# '^(' . s:body_heads . '\>'
    return anchorind + shiftwidth()
  endif

  " --- let / with ---
  if stripped =~# '^(\%(let\|with\)\>'
    if s:BindingListOpen(anchor, prevlnum)
      return s:FirstBindingColumn(anchorline, anchorind)
    endif
    " binding list already closed: this is the body.
    return anchorind + shiftwidth()
  endif

  " --- generic Lisp indent: align under first argument of the anchor form ---
  let col = s:FirstArgColumn(anchorline)
  if col > 0
    return col
  endif
  " No first arg visible on the anchor line: indent one level deeper.
  return anchorind + shiftwidth()
endfunction

" Find the most recent line (<= a:startlnum) whose cumulative paren balance
" (from that line through a:startlnum) is positive -- i.e. it opens a form
" still unclosed at a:startlnum. Returns 0 if none.
function! s:FindAnchor(startlnum) abort
  let lnum = a:startlnum
  let bal  = 0
  while lnum > 0
    let bal += s:Delta(getline(lnum))
    if bal > 0
      return lnum
    endif
    let lnum -= 1
  endwhile
  return 0
endfunction

" Net paren delta of a line (opens - closes), ignoring parens inside string
" literals, char literals (\X), and trailing line comments.
function! s:Delta(line) abort
  let s = substitute(a:line, '"\%([^"\\]\|\\.\)*"', '""', 'g')
  let s = substitute(s, '\\.', '', 'g')
  let s = substitute(s, ';.*$', '', '')
  return count(s, '(') - count(s, ')')
endfunction

" Whether the binding-list paren of a (let/(with form opened on a:anchor is
" still open at a:prevlnum.
function! s:BindingListOpen(anchor, prevlnum) abort
  let aline = getline(a:anchor)
  " Position right after "(let"/"(with" and its trailing whitespace; the
  " binding-list '(' should sit there.
  let hend = matchend(aline, '^\s*(\%(let\|with\)\>\s*')
  if hend < 0 || aline[hend :] !~# '^('
    return 0
  endif
  let bparen = hend
  let o = s:CountParens(aline[bparen :], '(')
  let c = s:CountParens(aline[bparen :], ')')
  let lnum = a:anchor + 1
  while lnum <= a:prevlnum
    let pl = getline(lnum)
    let o += s:CountParens(pl, '(')
    let c += s:CountParens(pl, ')')
    let lnum += 1
  endwhile
  return o > c
endfunction

" Count occurrences of a:ch in a:string, ignoring string literals, char
" literals (\X), and trailing comments.
function! s:CountParens(string, ch) abort
  let s = substitute(a:string, '"\%([^"\\]\|\\.\)*"', '""', 'g')
  let s = substitute(s, '\\.', '', 'g')
  let s = substitute(s, ';.*$', '', '')
  return count(s, a:ch)
endfunction

" Column (0-based) of the first binding on a (let/(with line: one space past
" the binding-list paren. Falls back to anchorind + shiftwidth().
function! s:FirstBindingColumn(anchorline, anchorind) abort
  let col = matchend(a:anchorline, '^\s*(\%(let\|with\)\>\s*(\s*')
  return col >= 0 ? col : (a:anchorind + shiftwidth())
endfunction

" For the innermost still-open '(' on a:line, return the 0-based column of the
" first argument after the head. Returns 0 if there is no open paren or the
" head has no following argument on the line. Positions are preserved (string
" literals and comments are skipped via state tracking, not substitution).
function! s:FirstArgColumn(line) abort
  let s = a:line
  let n = len(s)
  let i = 0
  let in_str = 0
  " stack of [phase, argcol]:
  "   0 = after '(', skipping ws before head
  "   1 = reading head
  "   2 = head done (saw ws), skipping ws before first arg
  "   3 = first arg column recorded
  let stack = []
  while i < n
    let ch = s[i]
    if in_str
      if ch ==# '"'
        let in_str = 0
      endif
    elseif ch ==# '"'
      let in_str = 1
    elseif ch ==# ';'
      break
    elseif ch ==# '('
      call add(stack, [0, -1])
    elseif ch ==# ')'
      if !empty(stack)
        call remove(stack, -1)
      endif
    elseif !empty(stack)
      if stack[-1][0] ==# 0 && ch !~# '\s'
        let stack[-1][0] = 1
      endif
      if !empty(stack) && stack[-1][0] ==# 1 && ch =~# '\s'
        let stack[-1][0] = 2
      endif
      if !empty(stack) && stack[-1][0] ==# 2 && ch !~# '\s'
        let stack[-1][1] = i
        let stack[-1][0] = 3
      endif
    endif
    let i += 1
  endwhile
  if !empty(stack) && stack[-1][1] >= 0
    return stack[-1][1]
  endif
  return 0
endfunction

let &cpo = s:cpo_save
unlet s:cpo_save
