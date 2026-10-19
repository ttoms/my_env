" ============================================================
"  rtl_align.vim — SystemVerilog / Verilog RTL 代码对齐
"
"  对齐规则（逗号行尾）：
"    - 普通列 4 格网格；packed 维度链内部单空格紧凑
"    - packed 维度逐维拆 prefix（左）/ suffix（右对齐）
"    - 逗号行尾，末项无逗号
"    - 幂等
"
"  用法：
"    :RtlAlign          对齐整个缓冲区
"    <leader>aa（visual）对齐选中块
"============================================================

" 向上取整到 4 的倍数
function! s:ceil4(n) abort
    return a:n + (4 - a:n % 4) % 4
endfunction

" 提取行内注释：返回 [code, comment]
function! s:extract_comment(line) abort
    let l:idx = stridx(a:line, '//')
    if l:idx < 0 | return [a:line, ''] | endif
    return [a:line[0 : l:idx - 1], a:line[l:idx : ]]
endfunction

" 该行是否带 keep 标记（行尾注释里含 g:rtl_align_keep_marker）
function! s:is_keep(line) abort
    let l:idx = stridx(a:line, '//')
    if l:idx < 0 | return 0 | endif
    let l:marker = get(g:, 'rtl_align_keep_marker', 'keep')
    return stridx(a:line[l:idx : ], l:marker) >= 0
endfunction

" ------------------------------------------------------------
" 通用表格对齐引擎
"   rows: [{indent, cells}]
"   cells: [{text, align, gap}]
"     align: 'l' 左对齐 / 'r' 右对齐（右边界 = 列起点 + 列宽）
"     gap:   'grid' 4格 / 'compact' 单空格（该 cell 与前一 cell 的间隔）
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
    for l:k in range(1, l:cols - 1)
        let l:gap = get(get(a:rows[0].cells, l:k, {}), 'gap', 'grid')
        if l:gap ==# 'compact'
            let l:pos[l:k] = l:pos[l:k - 1] + l:maxw[l:k - 1] + 1
        else
            let l:pos[l:k] = s:ceil4(l:pos[l:k - 1] + l:maxw[l:k - 1] + 1)
        endif
    endfor

    let l:out = []
    for l:r in a:rows
        let l:line = repeat(' ', l:r.indent)
        let l:k = 0
        for l:c in l:r.cells
            while len(l:line) < l:pos[l:k]
                let l:line .= ' '
            endwhile
            if l:c.align ==# 'r'
                while len(l:line) < l:pos[l:k] + l:maxw[l:k] - len(l:c.text)
                    let l:line .= ' '
                endwhile
            endif
            let l:line .= l:c.text
            let l:k += 1
        endfor
        call add(l:out, substitute(l:line, '\s*$', '', ''))
    endfor
    return l:out
endfunction

" ------------------------------------------------------------
" packed 维度拆分
" ------------------------------------------------------------

" 单个维度 '[WIDTH-1:0]' → ['[WIDTH', '-1:0]'
" 拆分点：第一个紧贴数字的 '-' 或 ':'（即 [-:]\d）
function! s:split_dim(dim) abort
    let l:inner = substitute(a:dim, '^\[\|\]$', '', 'g')
    let l:cut = match(l:inner, '[-:]\d')
    if l:cut < 0 | return ['', ''] | endif
    let l:prefix = '[' . substitute(l:inner[0 : l:cut - 1], '\s*$', '', '')
    let l:suffix = substitute(l:inner[l:cut : ], '^\s*', '', '') . ']'
    return [l:prefix, l:suffix]
endfunction

" 维度串 '[3:0][15:0]' → [{prefix, suffix}, ...]
function! s:split_dims(dims) abort
    let l:result = []
    if a:dims ==# '' | return l:result | endif
    let l:rest = a:dims
    while l:rest =~# '^\s*\['
        let l:end = stridx(l:rest, ']')
        if l:end < 0 | break | endif
        let l:seg = l:rest[0 : l:end]
        let [l:pre, l:suf] = s:split_dim(l:seg)
        call add(l:result, {'prefix': l:pre, 'suffix': l:suf})
        let l:rest = l:rest[l:end + 1 :]
    endwhile
    return l:result
endfunction

" 把多行维度列表统一成 cells（逐维 prefix/suffix，紧凑单空格）
"   dims_list: 每行一个 [{prefix, suffix}, ...]
function! s:build_dims_cells(dims_list) abort
    let l:maxd = 0
    for l:dl in a:dims_list
        if len(l:dl) > l:maxd | let l:maxd = len(l:dl) | endif
    endfor
    if l:maxd == 0 | return repeat([[]], len(a:dims_list)) | endif

    let l:maxpre = repeat([0], l:maxd)
    let l:maxsuf = repeat([0], l:maxd)
    for l:dl in a:dims_list
        let l:i = 0
        for l:d in l:dl
            if len(l:d.prefix) > l:maxpre[l:i] | let l:maxpre[l:i] = len(l:d.prefix) | endif
            if len(l:d.suffix) > l:maxsuf[l:i] | let l:maxsuf[l:i] = len(l:d.suffix) | endif
            let l:i += 1
        endfor
    endfor

    let l:result = []
    for l:dl in a:dims_list
        let l:cells = []
        for l:i in range(l:maxd)
            let l:pre = ''
            let l:suf = ''
            if l:i < len(l:dl)
                let l:pre = l:dl[l:i].prefix
                let l:suf = l:dl[l:i].suffix
            endif
            " 前缀右补、后缀左补（后缀右对齐）
            call add(l:cells, {'text': l:pre . repeat(' ', l:maxpre[l:i] - len(l:pre)), 'align': 'l', 'gap': 'compact'})
            call add(l:cells, {'text': repeat(' ', l:maxsuf[l:i] - len(l:suf)) . l:suf, 'align': 'l', 'gap': 'compact'})
        endfor
        call add(l:result, l:cells)
    endfor
    return l:result
endfunction

" ------------------------------------------------------------
" 解析器
" ------------------------------------------------------------

" 端口：direction type [dims] name [,] [// comment]
function! s:parse_port(line) abort
    if s:is_keep(a:line) | return {} | endif
    let [l:code, l:comment] = s:extract_comment(a:line)
    let l:code = substitute(l:code, ',\s*$', '', '')
    let l:indent = matchstr(l:code, '^\s*')
    let l:tokens = split(substitute(l:code, '^\s*', '', ''))
    if len(l:tokens) < 2 | return {} | endif
    if l:tokens[0] !~# '^\(input\|output\|inout\|ref\)$' | return {} | endif
    let l:dir = l:tokens[0]
    let l:i = 1
    let l:type = l:tokens[l:i]
    let l:i += 1
    if l:i < len(l:tokens) && l:tokens[l:i] =~# '^\(signed\|unsigned\)$'
        let l:type .= ' ' . l:tokens[l:i]
        let l:i += 1
    endif
    if l:i >= len(l:tokens) | return {} | endif
    let l:name = l:tokens[-1]
    if l:name =~# '^\[.*\]$' | return {} | endif
    let l:dims = substitute(join(l:tokens[l:i : -2], ''), '\s', '', 'g')
    return {'indent': strlen(l:indent), 'dir': l:dir, 'type': l:type, 'dims': s:split_dims(l:dims), 'name': l:name, 'comment': l:comment}
endfunction

" 参数：parameter|localparam [type] name = value [,] [// comment]
" 类型作为整体字段（packed 位宽不拆列）
function! s:parse_param(line) abort
    if s:is_keep(a:line) | return {} | endif
    let [l:code, l:comment] = s:extract_comment(a:line)
    let l:code = substitute(l:code, ',\s*$', '', '')
    let l:indent = matchstr(l:code, '^\s*')
    let l:body = substitute(l:code, '^\s*', '', '')
    let l:m = matchlist(l:body, '^\(parameter\|localparam\)\s\+\(.*\)$')
    if empty(l:m) | return {} | endif
    let l:kw = l:m[1]
    let l:rest = l:m[2]
    let l:eq = stridx(l:rest, '=')
    if l:eq < 0 | return {} | endif
    let l:lhs = substitute(l:rest[0 : l:eq - 1], '\s*$', '', '')
    let l:value = substitute(substitute(l:rest[l:eq + 1 : ], '^\s*', '', ''), '\s*$', '', '')
    let l:lhs_tokens = split(l:lhs)
    if empty(l:lhs_tokens) | return {} | endif
    let l:name = l:lhs_tokens[-1]
    let l:type = join(l:lhs_tokens[0 : -2], ' ')
    return {'indent': strlen(l:indent), 'kw': l:kw, 'type': l:type, 'name': l:name, 'value': l:value, 'comment': l:comment}
endfunction

" 信号声明：type [dims] name ; [// comment]（packed 维度，暂不含初始化/unpacked）
function! s:parse_signal(line) abort
    if s:is_keep(a:line) | return {} | endif
    let [l:code, l:comment] = s:extract_comment(a:line)
    let l:indent = matchstr(l:code, '^\s*')
    let l:body = substitute(l:code, '^\s*', '', '')
    if l:body !~# ';\s*$' | return {} | endif
    let l:body = substitute(l:body, ';\s*$', '', '')
    let l:tokens = split(l:body)
    if empty(l:tokens) | return {} | endif
    let l:type = l:tokens[0]
    let l:i = 1
    if l:i < len(l:tokens) && l:tokens[l:i] =~# '^\(signed\|unsigned\)$'
        let l:type .= ' ' . l:tokens[l:i]
        let l:i += 1
    endif
    if l:i >= len(l:tokens) | return {} | endif
    let l:name = l:tokens[-1]
    if l:name =~# '^\[.*\]$' | return {} | endif
    let l:dims = substitute(join(l:tokens[l:i : -2], ''), '\s', '', 'g')
    return {'indent': strlen(l:indent), 'type': l:type, 'dims': s:split_dims(l:dims), 'name': l:name, 'tail': ';', 'comment': l:comment}
endfunction

" 例化连接：.name (expr) [,] [// comment]
function! s:parse_inst(line) abort
    if s:is_keep(a:line) | return {} | endif
    let [l:code, l:comment] = s:extract_comment(a:line)
    let l:code = substitute(l:code, ',\s*$', '', '')
    let l:m = matchlist(l:code, '^\(\s*\)\(\.[A-Za-z_][A-Za-z0-9_]*\)\s*(\(.*\))\s*$')
    if empty(l:m) | return {} | endif
    let l:sig = substitute(l:m[3], '\s*$', '', '')
    return {'indent': strlen(l:m[1]), 'port': l:m[2], 'sig': '(' . l:sig, 'comment': l:comment}
endfunction

" ------------------------------------------------------------
" 对齐函数
" ------------------------------------------------------------

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

    let l:n = len(l:rows) - 1
    let l:i = 0
    for l:r in l:rows
        let l:r.cells = [
                    \ {'text': l:r.kw, 'align': 'l', 'gap': 'grid'},
                    \ {'text': l:r.type, 'align': 'l', 'gap': 'grid'},
                    \ {'text': l:r.name, 'align': 'l', 'gap': 'grid'},
                    \ {'text': '=', 'align': 'l', 'gap': 'grid'},
                    \ {'text': l:r.value, 'align': 'l', 'gap': 'grid'},
                    \ {'text': (l:i < l:n) ? ',' : '', 'align': 'l', 'gap': 'grid'},
                    \ ]
        if l:r.comment !=# ''
            call add(l:r.cells, {'text': l:r.comment, 'align': 'l', 'gap': 'grid'})
        endif
        let l:i += 1
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
    for l:lnum in range(a:start + 1, a:end - 1)
        let l:p = s:parse_port(getline(l:lnum))
        if empty(l:p) | continue | endif
        call add(l:rows, l:p)
        call add(l:lnums, l:lnum)
    endfor
    if empty(l:rows) | return | endif

    let l:dims_list = map(copy(l:rows), 'v:val.dims')
    let l:dims_cells = s:build_dims_cells(l:dims_list)

    let l:n = len(l:rows) - 1
    let l:i = 0
    for l:r in l:rows
        let l:cells = [
                    \ {'text': l:r.dir, 'align': 'l', 'gap': 'grid'},
                    \ {'text': l:r.type, 'align': 'l', 'gap': 'grid'},
                    \ ]
        let l:first = 1
        for l:dc in l:dims_cells[l:i]
            if l:first
                call add(l:cells, {'text': l:dc.text, 'align': 'l', 'gap': 'compact'})
                let l:first = 0
            else
                call add(l:cells, l:dc)
            endif
        endfor
        call add(l:cells, {'text': l:r.name, 'align': 'l', 'gap': 'grid'})
        call add(l:cells, {'text': (l:i < l:n) ? ',' : '', 'align': 'l', 'gap': 'grid'})
        if l:r.comment !=# ''
            call add(l:cells, {'text': l:r.comment, 'align': 'l', 'gap': 'grid'})
        endif
        let l:r.cells = l:cells
        let l:i += 1
    endfor

    let l:out = s:align_rows(l:rows)
    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
endfunction

function! s:align_signal_lines(lines) abort
    let l:rows = []
    for l:line in a:lines
        let l:p = s:parse_signal(l:line)
        if empty(l:p) | continue | endif
        call add(l:rows, l:p)
    endfor
    if empty(l:rows) | return [] | endif

    let l:dims_list = map(copy(l:rows), 'v:val.dims')
    let l:dims_cells = s:build_dims_cells(l:dims_list)

    let l:i = 0
    for l:r in l:rows
        let l:cells = [
                    \ {'text': l:r.type, 'align': 'l', 'gap': 'grid'},
                    \ ]
        let l:first = 1
        for l:dc in l:dims_cells[l:i]
            if l:first
                call add(l:cells, {'text': l:dc.text, 'align': 'l', 'gap': 'compact'})
                let l:first = 0
            else
                call add(l:cells, l:dc)
            endif
        endfor
        call add(l:cells, {'text': l:r.name, 'align': 'l', 'gap': 'grid'})
        call add(l:cells, {'text': l:r.tail, 'align': 'l', 'gap': 'grid'})
        if l:r.comment !=# ''
            call add(l:cells, {'text': l:r.comment, 'align': 'l', 'gap': 'grid'})
        endif
        let l:r.cells = l:cells
        let l:i += 1
    endfor
    return s:align_rows(l:rows)
endfunction

" 例化：参数连接与端口连接各自成组（不共享列宽）
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
        let l:n = len(l:g.rows) - 1
        for l:r in l:g.rows
            let l:r.cells = [
                        \ {'text': l:r.port, 'align': 'l', 'gap': 'grid'},
                        \ {'text': l:r.sig, 'align': 'l', 'gap': 'grid'},
                        \ {'text': ')', 'align': 'r', 'gap': 'grid'},
                        \ ]
        endfor
        let l:out = s:align_rows(l:g.rows)
        let l:idx = 0
        for l:lnum in l:g.lnums
            if l:idx < l:n
                call setline(l:lnum, l:out[l:idx] . ',')
            else
                call setline(l:lnum, l:out[l:idx])
            endif
            let l:idx += 1
        endfor
    endfor
endfunction

" ------------------------------------------------------------
" 主入口
" ------------------------------------------------------------

function! rtl_align#align_all() abort
    let l:view = winsaveview()

    " module 声明（参数 + 端口）
    let l:lnum = 1
    while l:lnum <= line('$')
        if getline(l:lnum) =~# '^\s*module\s\+\w\+'
            call s:align_module_decl(l:lnum)
        endif
        let l:lnum += 1
    endwhile

    " 信号块标记（可配 g:rtl_align_signal_marker）
    let l:sig_marker = get(g:, 'rtl_align_signal_marker', '@vlog-align')
    let l:lnum = 1
    while l:lnum <= line('$')
        if getline(l:lnum) =~# l:sig_marker
            call s:align_marked_block(l:lnum, 'signal')
        endif
        let l:lnum += 1
    endwhile

    " 例化块标记（可配 g:rtl_align_inst_marker）
    let l:inst_marker = get(g:, 'rtl_align_inst_marker', '@inst')
    let l:lnum = 1
    while l:lnum <= line('$')
        if getline(l:lnum) =~# l:inst_marker
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

    " signal 块：只收集能解析为声明的行（endmodule/assign 等非声明行不参与）
    let l:lines = []
    let l:lnums = []
    for l:lnum in range(l:start, l:end)
        let l:line = getline(l:lnum)
        if l:line =~# '^\s*//' | continue | endif
        if !empty(s:parse_signal(l:line))
            call add(l:lines, l:line)
            call add(l:lnums, l:lnum)
        endif
    endfor
    if empty(l:lines) | return | endif

    " 信号声明块 ≤ 阈值行数不处理（可配 g:rtl_align_min_signal_lines）
    if len(l:lines) <= get(g:, 'rtl_align_min_signal_lines', 3)
        return
    endif

    let l:out = s:align_signal_lines(l:lines)
    if empty(l:out) | return | endif

    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
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
    let l:out = l:is_inst ? s:align_inst_lines(l:lines) : s:align_signal_lines(l:lines)
    if empty(l:out) | call winrestview(l:view) | return | endif

    let l:idx = 0
    for l:lnum in l:lnums
        call setline(l:lnum, l:out[l:idx])
        let l:idx += 1
    endfor
    call winrestview(l:view)
endfunction

" 手动选区里的例化连接对齐（单组）
function! s:align_inst_lines(lines) abort
    let l:rows = []
    for l:line in a:lines
        let l:p = s:parse_inst(l:line)
        if empty(l:p) | continue | endif
        call add(l:rows, l:p)
    endfor
    if empty(l:rows) | return [] | endif
    let l:n = len(l:rows) - 1
    for l:r in l:rows
        let l:r.cells = [
                    \ {'text': l:r.port, 'align': 'l', 'gap': 'grid'},
                    \ {'text': l:r.sig, 'align': 'l', 'gap': 'grid'},
                    \ {'text': ')', 'align': 'r', 'gap': 'grid'},
                    \ ]
    endfor
    let l:out = s:align_rows(l:rows)
    for l:i in range(l:n)
        let l:out[l:i] .= ','
    endfor
    return l:out
endfunction
