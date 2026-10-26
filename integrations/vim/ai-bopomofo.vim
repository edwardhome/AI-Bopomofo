" Copyright (c) 2026 AI-Bopomofo contributors. MIT License.
" Local macOS only. No raw key mappings; use the editor's actual mode.
if exists('g:loaded_ai_bopomofo_modes') || !has('macunix') || !exists('##ModeChanged')
  finish
endif
let g:loaded_ai_bopomofo_modes = 1
let s:helper = get(g:, 'ai_bopomofo_helper', expand('~/.local/bin/ai-bopomofo-input'))
if !executable(s:helper)
  finish
endif
let s:previous = trim(system(shellescape(s:helper) . ' current'))
let s:last = ''
function! s:Apply(mode) abort
  let l:target = a:mode =~# '^[iR]' ? 'insert' : 'normal'
  if l:target !=# s:last
    call system(shellescape(s:helper) . ' ' . shellescape(l:target))
    if v:shell_error == 0
      let s:last = l:target
    endif
  endif
endfunction
function! s:Restore() abort
  let l:current = trim(system(shellescape(s:helper) . ' current'))
  if l:current ==# 'com.apple.keylayout.ABC' || l:current =~# '^org\.aibopomofo\.inputmethod\.'
    if !empty(s:previous)
      call system(shellescape(s:helper) . ' ' . shellescape(s:previous))
    endif
  endif
  let s:last = ''
endfunction
augroup AIBopomofoModes
  autocmd!
  autocmd VimEnter,FocusGained * call <SID>Apply(mode(1))
  autocmd ModeChanged * call <SID>Apply(v:event.new_mode)
  autocmd FocusLost,VimLeavePre * call <SID>Restore()
augroup END
