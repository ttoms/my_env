" ============================================================
"  ftplugin/systemverilog.vim — SystemVerilog 缓冲区本地配置
" ============================================================

if exists('b:did_ftplugin')
    finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s

" 对齐快捷键
nnoremap <buffer><silent> <leader>aa :RtlAlign<CR>
vnoremap <buffer><silent> <leader>aa <Plug>(rtl-align-block)
