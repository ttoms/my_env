" ============================================================
"  ftplugin/systemverilog.vim — SystemVerilog 缓冲区本地配置
" ============================================================

if exists('b:did_ftplugin')
    finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s

" 对齐快捷键
"   ,aa 全部 / ,am module 声明 / ,as 信号声明块 / ,ai 例化块
"   普通模式 = 整个缓冲区；可视模式 = 选中区域
nnoremap <buffer><silent> <leader>aa :RtlAlign<CR>
nnoremap <buffer><silent> <leader>am :RtlAlignModule<CR>
nnoremap <buffer><silent> <leader>as :RtlAlignSignal<CR>
nnoremap <buffer><silent> <leader>ai :RtlAlignInst<CR>
vnoremap <buffer><silent> <leader>aa <Plug>(rtl-align-block)
vnoremap <buffer><silent> <leader>am <Plug>(rtl-align-module)
vnoremap <buffer><silent> <leader>as <Plug>(rtl-align-signal)
vnoremap <buffer><silent> <leader>ai <Plug>(rtl-align-inst)
