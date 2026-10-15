" ============================================================
"  rtl_align.vim — SystemVerilog / Verilog RTL 代码对齐
"
"  实现统一列对齐规则：
"    - 标记：// @vlog-align（信号声明块）/ // @inst（例化块）/ // keep（跳过）
"    - 列对齐：所有列左对齐，列起始 = 上一列结束 + 1 → 取整到 4 的倍数
"    - packed 维度 [MSB:LSB] 拆 prefix（左对齐）/ suffix（右对齐）
"    - 逗号行首：块内首项无逗号，其余项行首逗号
"    - 幂等：多次执行结果不变
"
"  用法：
"    :RtlAlign          对齐整个缓冲区
"    <leader>aa（visual）对齐选中块
"============================================================

" ------------------------------------------------------------
" 工具函数
" ------------------------------------------------------------

" 向上取整到 4 的倍数
function! s:ceil4(n) abort
    return a:n + (4 - a:n % 4) % 4
endfunction

" 去掉行尾逗号（逗号行尾 → 行首迁移用）
function! s:strip_trailing_comma(line) abort
    return substitute(a:line, ',\s*$', '', '')
endfunction

" ------------------------------------------------------------
" 通用表格对齐引擎
"   rows: [{indent, cells}]，cells: [{text, align}]（align: 'l'/'r'）
" ------------------------------------------------------------
function! s:align_rows(rows) abort
    if empty(a:rows) | return [] | endif

    let l:cols = 0
    for l:r in a:rows
        if len(l:r.cells) > l:cols | let l:cols = len(l:r.cells) | endif
    endfor
    if l:cols == 0 | return [] | endif

    let l:maxw = repeat([0], l:cols)
    for l:r in a:rows
        let l:i = 0
        for l:c in l:r.cells
            if len(l:c.text) > l:maxw[l:i] | let l:maxw[l:i] = len(l:c.text) | endif
            let l:i += 1
        endfor
    endfor

    let l:pos = repeat([0], l:cols + 1)
    let l:pos[0] = a:rows[0].indent
    for l:k in range(l:cols)
        let l:pos[l:k + 1] = s:ceil4(l:pos[l:k] + l:maxw[l:k] + 1)
    endfor

    let l:out = []
    for l:r in a:rows
        let l:line = repeat(' ', l:r.indent)
        let l:k = 0
        for l:c in l:r.cells
            let l:cur = len(l:line)
            if l:cur < l:pos[l:k]
                let l:line .= repeat(' ', l:pos[l:k] - l:cur)
            endif
            if l:c.align ==# 'r'
                let l:box = l:pos[l:k + 1] - l:pos[l:k]
                let l:line .= repeat(' ', l:box - len(l:c.text))
            endif
            let l:line .= l:c.text
            let l:k += 1
        endfor
        call add(l:out, l:line)
    endfor
    return l:out
endfunction

" ------------------------------------------------------------
" packed 维度解析：[MSB:LSB] → prefix / suffix
" ------------------------------------------------------------
function! s:split_dims(dims) abort
    if a:dims ==# '' | return ['', ''] | endif
    " 多维度 [a:b][c:d]：v1 不做 suffix 右对齐，整体当 prefix
    if match(a:dims, '\[[^\]]*\]\[[^\]]*\]') >= 0
        return [a:dims, '']
    endif
    let l:lb = stridx(a:dims, '[')
    let l:rb = stridx(a:dims, ']', l:lb)
    if l:lb < 0 || l:rb < 0 | return [a:dims, ''] | endif
    let l:inner = a:dims[l:lb + 1 : l:rb - 1]
    let l:dash = stridx(l:inner, '-')
    let l:colon = stridx(l:inner, ':')
    let l:cut = -1
    if l:dash >= 0 && l:colon >= 0
        let l:cut = l:dash < l:colon ? l:dash : l:colon
    elseif l:dash >= 0
        let l:cut = l:dash
    elseif l:colon >= 0
        let l:cut = l:colon
    else
        let l:cut = len(l:inner)
    endif
    " trim 掉分隔符两侧的空格，保证幂等
    let l:prefix = '[' . substitute(l:inner[0 : l:cut - 1], '\s*$', '', '')
    let l:suffix = substitute(l:inner[l:cut : ], '^\s*', '', '') . ']'
    return [l:prefix, l:suffix]
endfunction

" ------------------------------------------------------------
" 信号声明块（// @vlog-align）
" ------------------------------------------------------------
function! s:parse_signal(line) abort
    " <indent><type> <dims?> <name>;
    " dims 用 [^]]* 整体捕获（允许对齐后的内部空格）；\%( 为非捕获组
    let l:m = matchlist(a:line, '^\(\s*\)\([A-Za-z_][A-Za-z0-9_]*\%(\s\+signed\|\s\+unsigned\)\?\)\s*\(\%(\s*\[[^\]]*\]\)*\)\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*;\s*$')
    if empty(l:m) | return {} | endif
    " 去掉维度内部空格，交给 split_dims 重新按 prefix/suffix 对齐
    let l:dims = substitute(l:m[3], '\s', '', 'g')
    let [l:pre, l:suf] = s:split_dims(l:dims)
    return {'indent': strlen(l:m[1]), 'type': l:m[2], 'dims_prefix': l:pre, 'dims_suffix': l:suf, 'name': l:m[4]}
endfunction

function! s:align_signal(lines) abort
    let l:rows = []
    let l:maxpre = 0
    let l:maxsuf = 0
    for l:line in a:lines
        let l:p = s:parse_signal(l:line)
        if empty(l:p) | continue | endif
        if len(l:p.dims_prefix) > l:maxpre | let l:maxpre = len(l:p.dims_prefix) | endif
        if len(l:p.dims_suffix) > l:maxsuf | let l:maxsuf = len(l:p.dims_suffix) | endif
        call add(l:rows, l:p)
    endfor
    if empty(l:rows) | return [] | endif

    for l:r in l:rows
        let l:dims_text = ''
        if l:r.dims_prefix !=# ''
            let l:dims_text = l:r.dims_prefix
                        \ . repeat(' ', l:maxpre - len(l:r.dims_prefix))
                        \ . repeat(' ', l:maxsuf - len(l:r.dims_suffix))
                        \ . l:r.dims_suffix
        endif
        let l:r.cells = [
                    \ {'text': l:r.type, 'align': 'l'},
                    \ {'text': l:dims_text, 'align': 'l'},
                    \ {'text': l:r.name, 'align': 'l'},
                    \ {'text': ';', 'align': 'l'},
                    \ ]
    endfor
    return s:align_rows(l:rows)
endfunction

" ------------------------------------------------------------
" 例化块（// @inst）
" ------------------------------------------------------------
function! s:parse_inst(line) abort
    let l:line = s:strip_trailing_comma(a:line)
    let l:m = matchlist(l:line, '^\(\s*\)\(,\s*\)\?\(\.[A-Za-z_][A-Za-z0-9_]*\)\s*(\(.*\))\s*$')
    if empty(l:m) | return {} | endif
    " 去掉 ( 与 ) 之间的尾随空格，保证幂等
    let l:sig = substitute(l:m[4], '\s*$', '', '')
    return {'indent': strlen(l:m[1]), 'port': l:m[3], 'sig': '(' . l:sig}
endfunction

function! s:align_inst(lines) abort
    let l:rows = []
    for l:line in a:lines
        let l:p = s:parse_inst(l:line)
        if empty(l:p) | continue | endif
        call add(l:rows, l:p)
    endfor
    if empty(l:rows) | return [] | endif

    let l:first = 1
    for l:r in l:rows
        let l:comma = l:first ? '' : ','
        let l:first = 0
        let l:r.cells = [
                    \ {'text': l:comma . l:r.port, 'align': 'l'},
                    \ {'text': l:r.sig, 'align': 'l'},
                    \ {'text': ')', 'align': 'l'},
                    \ ]
    endfor
    return s:align_rows(l:rows)
endfunction

" ------------------------------------------------------------
" module 声明（parameter + port，逗号行首）
" ------------------------------------------------------------
function! s:parse_param(line) abort
    let l:line = s:strip_trailing_comma(a:line)
    let l:ind = matchstr(l:line, '^\s*')
    let l:line = substitute(l:line, '^\s*', '', '')
    let l:line = substitute(l:line, '^parameter\s*', '', '')
    let l:line = substitute(l:line, '^,\s*', '', '')
    let l:m = matchlist(l:line, '^\([A-Za-z_][A-Za-z0-9_]*\)\s*=\s*\(.*\)$')
    if empty(l:m) | return {} | endif
    return {'indent': strlen(l:ind), 'name': l:m[1], 'value': l:m[2]}
endfunction

function! s:parse_port(line) abort
    let l:line = s:strip_trailing_comma(a:line)
    let l:m = matchlist(l:line, '^\(\s*\)\(,\s*\)\?\(input\|output\|inout\)\s\+\(logic\|wire\|reg\|bit\|int\|integer\)\s*\(.*\)$')
    if empty(l:m) | return {} | endif
    let l:rest = l:m[5]
    let l:dims = ''
    let l:name = ''
    let l:dm = matchlist(l:rest, '^\(\(\[[^\]]*\]\)\+\)\s*\([A-Za-z_][A-Za-z0-9_]*\)$')
    if !empty(l:dm)
        let l:dims = l:dm[1]
        let l:name = l:dm[3]
    else
        let l:nm = matchlist(l:rest, '^\s*\([A-Za-z_][A-Za-z0-9_]*\)$')
        if empty(l:nm) | return {} | endif
        let l:name = l:nm[1]
    endif
    let [l:pre, l:suf] = s:split_dims(l:dims)
    return {'indent': strlen(l:m[1]), 'dir': l:m[3], 'type': l:m[4], 'dims_prefix': l:pre, 'dims_suffix': l:suf, 'name': l:name}
endfunction

function! s:align_module_decl(lnum) abort
    let l:i = a:lnum
    let l:max = line('$')
    let l:param_start = -1
    let l:param_end = -1
    let l:port_start = -1
    let l:port_end = -1
    let l:has_param = 0

    while l:i <= l:max
        let l:cur = getline(l:i)
        if l:param_start < 0 && l:cur =~# '#\s*('
            let l:param_start = l:i
            let l:has_param = 1
        elseif l:has_param && l:param_end < 0 && l:cur =~# '^\s*)\s*('
            let l:param_end = l:i
            let l:port_start = l:i
        elseif l:port_start < 0 && l:cur =~# '^\s*('
            let l:port_start = l:i
            let l:param_end = l:i
            let l:param_start = -2
        elseif l:port_start >= 0 && l:port_end < 0 && l:cur =~# ');\?\s*$'
            let l:port_end = l:i
            break
        endif
        let l:i += 1
    endwhile

    if l:param_start >= 0 && l:param_end >= 0
        call s:align_module_params(l:param_start, l:param_end)
    endif
    if l:port_start >= 0 && l:port_end >= 0
        call s:align_module_ports(l:port_start, l:port_end)
    endif
endfunction

function! s:align_module_params(start, end) abort
    let l:rows = []
    let l:lnums = []
    for l:lnum in range(a:start + 1, a:end - 1)
        let l:p = s:parse_param(getline(l:lnum))
        if empty(l:p) | continue | endif
        call add(l:rows, l:p)
        call add(l:lnums, l:lnum)
    endfor
    if empty(l:rows) | return | endif

    let l:i = 0
    for l:r in l:rows
        let l:kw = (l:i == 0) ? 'parameter' : ','
        let l:i += 1
        let l:r.cells = [
                    \ {'text': l:kw, 'align': 'l'},
                    \ {'text': l:r.name, 'align': 'l'},
                    \ {'text': '=', 'align': 'l'},
                    \ {'text': l:r.value, 'align': 'l'},
                    \ ]
    endfor
    let l:out = s:align_rows(l:rows)
    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
endfunction

function! s:align_module_ports(start, end) abort
    let l:rows = []
    let l:lnums = []
    let l:maxpre = 0
    let l:maxsuf = 0
    for l:lnum in range(a:start + 1, a:end - 1)
        let l:p = s:parse_port(getline(l:lnum))
        if empty(l:p) | continue | endif
        if len(l:p.dims_prefix) > l:maxpre | let l:maxpre = len(l:p.dims_prefix) | endif
        if len(l:p.dims_suffix) > l:maxsuf | let l:maxsuf = len(l:p.dims_suffix) | endif
        call add(l:rows, l:p)
        call add(l:lnums, l:lnum)
    endfor
    if empty(l:rows) | return | endif

    let l:i = 0
    for l:r in l:rows
        let l:comma = (l:i == 0) ? '' : ','
        let l:i += 1
        let l:dims_text = ''
        if l:r.dims_prefix !=# ''
            let l:dims_text = l:r.dims_prefix
                        \ . repeat(' ', l:maxpre - len(l:r.dims_prefix))
                        \ . repeat(' ', l:maxsuf - len(l:r.dims_suffix))
                        \ . l:r.dims_suffix
        endif
        let l:r.cells = [
                    \ {'text': l:comma . l:r.dir, 'align': 'l'},
                    \ {'text': l:r.type, 'align': 'l'},
                    \ {'text': l:dims_text, 'align': 'l'},
                    \ {'text': l:r.name, 'align': 'l'},
                    \ ]
    endfor
    let l:out = s:align_rows(l:rows)
    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
endfunction

" ------------------------------------------------------------
" 主入口
" ------------------------------------------------------------

function! rtl_align#align_all() abort
    let l:view = winsaveview()

    let l:lnum = 1
    while l:lnum <= line('$')
        if getline(l:lnum) =~# '^\s*module\s\+\w\+'
            call s:align_module_decl(l:lnum)
        endif
        let l:lnum += 1
    endwhile

    let l:lnum = 1
    while l:lnum <= line('$')
        if getline(l:lnum) =~# '@vlog-align'
            call s:align_marked_block(l:lnum, 'signal')
        endif
        let l:lnum += 1
    endwhile

    let l:lnum = 1
    while l:lnum <= line('$')
        if getline(l:lnum) =~# '@inst'
            call s:align_marked_block(l:lnum, 'inst')
        endif
        let l:lnum += 1
    endwhile

    call winrestview(l:view)
endfunction

function! s:align_marked_block(mark_lnum, kind) abort
    let l:start = a:mark_lnum + 1
    let l:end = l:start
    let l:max = line('$')
    while l:end <= l:max && getline(l:end) !~# '^\s*$'
        let l:end += 1
    endwhile
    let l:end -= 1
    if l:end < l:start | return | endif

    if a:kind ==# 'inst'
        call s:align_inst_block(l:start, l:end)
        return
    endif

    " signal 块
    let l:lines = []
    let l:lnums = []
    for l:lnum in range(l:start, l:end)
        let l:line = getline(l:lnum)
        if l:line =~# '^\s*//' | continue | endif
        call add(l:lines, l:line)
        call add(l:lnums, l:lnum)
    endfor
    if empty(l:lines) | return | endif

    let l:out = s:align_signal(l:lines)
    if empty(l:out) | return | endif

    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
endfunction

" 例化块：参数连接与端口连接分组对齐（各自独立的首项无逗号）
function! s:align_inst_block(start, end) abort
    let l:groups = []
    let l:cur = {'lnums': [], 'rows': []}
    for l:lnum in range(a:start, a:end)
        let l:line = getline(l:lnum)
        if l:line =~# '^\s*//' | continue | endif
        if l:line =~# '^\s*,*\.\w\+\s*('
            let l:p = s:parse_inst(l:line)
            if !empty(l:p)
                call add(l:cur.lnums, l:lnum)
                call add(l:cur.rows, l:p)
            endif
        elseif l:line =~# '('
            " 分组边界：#( 或 ( —— 上一组结束
            if !empty(l:cur.rows)
                call add(l:groups, l:cur)
                let l:cur = {'lnums': [], 'rows': []}
            endif
        endif
    endfor
    if !empty(l:cur.rows)
        call add(l:groups, l:cur)
    endif

    for l:g in l:groups
        let l:first = 1
        for l:r in l:g.rows
            let l:comma = l:first ? '' : ','
            let l:first = 0
            let l:r.cells = [
                        \ {'text': l:comma . l:r.port, 'align': 'l'},
                        \ {'text': l:r.sig, 'align': 'l'},
                        \ {'text': ')', 'align': 'l'},
                        \ ]
        endfor
        let l:out = s:align_rows(l:g.rows)
        let l:idx = 0
        for l:lnum in l:g.lnums
            call setline(l:lnum, l:out[l:idx])
            let l:idx += 1
        endfor
    endfor
endfunction

function! rtl_align#align_range(line1, line2) abort
    let l:view = winsaveview()
    let l:lines = []
    let l:lnums = []
    for l:lnum in range(a:line1, a:line2)
        let l:line = getline(l:lnum)
        if l:line =~# '^\s*$' || l:line =~# '^\s*//' | continue | endif
        call add(l:lines, l:line)
        call add(l:lnums, l:lnum)
    endfor
    if empty(l:lines) | call winrestview(l:view) | return | endif

    let l:is_inst = 1
    for l:line in l:lines
        if l:line !~# '^\s*,*\.\w\+\s*(' | let l:is_inst = 0 | break | endif
    endfor
    let l:out = l:is_inst
                \ ? s:align_inst(l:lines)
                \ : s:align_signal(l:lines)
    if empty(l:out) | call winrestview(l:view) | return | endif

    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
    call winrestview(l:view)
endfunction
