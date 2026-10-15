" ============================================================
"  rtl_align.vim — 命令定义（实现见 autoload/rtl_align.vim）
" ============================================================

if exists('g:loaded_rtl_align') || &cp
    finish
endif

command! RtlAlign call rtl_align#align_all()

" 视觉模式下对齐选中块
vnoremap <Plug>(rtl-align-block) :<C-u>call rtl_align#align_range(line("'<"), line("'>"))<CR>
