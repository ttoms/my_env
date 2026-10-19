" ============================================================
"  rtl_align.vim — 命令定义（实现见 autoload/rtl_align.vim）
" ============================================================

if exists('g:loaded_rtl_align') || &cp
    finish
endif
let g:loaded_rtl_align = 1

" ---- 可配置项（在 .vimrc 里覆盖，需放在插件加载前）----
if !exists('g:rtl_align_signal_marker')
    let g:rtl_align_signal_marker = '@vlog-align'   " 信号声明块标记
endif
if !exists('g:rtl_align_inst_marker')
    let g:rtl_align_inst_marker = '@inst'           " 例化块标记
endif
if !exists('g:rtl_align_keep_marker')
    let g:rtl_align_keep_marker = 'keep'            " 跳过该行标记（行尾注释里）
endif
if !exists('g:rtl_align_min_signal_lines')
    let g:rtl_align_min_signal_lines = 3            " 信号声明块 ≤ 此行数不处理
endif

command! RtlAlign call rtl_align#align_all()
command! RtlAlignModule call rtl_align#align_module_all()
command! RtlAlignSignal call rtl_align#align_signal_all()
command! RtlAlignInst call rtl_align#align_inst_all()

" 视觉模式下按类型对齐选中块（auto 自动判断 / module / signal / inst）
vnoremap <Plug>(rtl-align-block)  :<C-u>call rtl_align#align_range(line("'<"), line("'>"))<CR>
vnoremap <Plug>(rtl-align-module) :<C-u>call rtl_align#align_range(line("'<"), line("'>"), 'module')<CR>
vnoremap <Plug>(rtl-align-signal) :<C-u>call rtl_align#align_range(line("'<"), line("'>"), 'signal')<CR>
vnoremap <Plug>(rtl-align-inst)   :<C-u>call rtl_align#align_range(line("'<"), line("'>"), 'inst')<CR>
