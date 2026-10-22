" ============================================================
"  vimrc — 通用 vim 配置
" ============================================================

set nocompatible

" ============================================================
"  插件管理（vim-plug）
" ============================================================
call plug#begin('~/.vim/plugged')

" 主题
Plug 'joshdick/onedark.vim'

" 文件树
Plug 'preservim/nerdtree'
" git 集成（:Gdiffsplit / :Gvdiffsplit 分屏看 diff）
Plug 'tpope/vim-fugitive'
" 状态栏
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
" SystemVerilog 语法/缩进
Plug 'vhda/verilog_systemverilog.vim'
" git 改动标记（gutter，+/- 标记每次保存自动 git diff 慢，已停用）
" Plug 'airblade/vim-gitgutter'
" 自动文件头
Plug 'alpertuna/vim-header'
" 对齐
Plug 'junegunn/vim-easy-align'
" 环绕（引号/括号）
Plug 'tpope/vim-surround'
" 自动配对括号
Plug 'jiangmiao/auto-pairs'
" 高亮光标下单词的其他出现位置
Plug 'RRethy/vim-illuminate'

" rtl_align 对齐插件
Plug '~/.vim/plugged/rtl_align'

" 链式补全（路径→omni→关键词→词典→拼写，Tab 触发）
Plug 'lifepillar/vim-mucomplete'

" 后续可选：
" Plug 'junegunn/fzf.vim'                      " 模糊查找（需 fzf 二进制）
" Plug 'neoclide/coc.nvim'                     " LSP 补全（需 node）

call plug#end()

" ============================================================
"  基础设置
" ============================================================
syntax on
filetype plugin indent on
set encoding=utf-8
set number
" set relativenumber
set cursorline
set wrap
set linebreak
set showcmd
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set wildmenu
set mouse=a
set backspace=indent,eol,start
set scrolloff=3
" truecolor 需终端支持（iTerm2/kitty/alacritty 等会设 $COLORTERM=truecolor）。
" 不支持 truecolor 的终端（如 macOS Terminal.app）强开会导致 onedark 底色异常（全蓝），
" 此时回退 256 色。
if has('termguicolors') && exists('$COLORTERM') && $COLORTERM =~# 'truecolor\|24bit'
    set termguicolors
else
    set notermguicolors
    let g:onedark_termcolors = 256
endif

" ---- 缩进 ----
set autoindent
set smartindent
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4

" ---- 界面 ----
set laststatus=2
set ruler
set showmode
set cmdheight=2
set hidden
" 不生成 .swp 交换文件：消除工作目录里的 .swp 和"swap file exists"提示。
" 代价：崩溃/断连时无法恢复未保存改动（有 git 兜底即可接受）。
" 若想保留崩溃恢复、只是不想 .swp 散落目录，改用：set directory=~/.vim/swap//
set noswapfile

" ---- 文件类型特定缩进 ----
autocmd FileType verilog,systemverilog setlocal tabstop=4 shiftwidth=4 softtabstop=4
autocmd FileType python setlocal tabstop=4 shiftwidth=4 softtabstop=4
autocmd FileType make setlocal noexpandtab tabstop=8 shiftwidth=8
autocmd FileType yaml setlocal tabstop=2 shiftwidth=2 softtabstop=2

" ---- 行尾空格 ----
" 高亮行尾空格（红底）
highlight ExtraWhitespace ctermbg=red guibg=#e06c75
match ExtraWhitespace /\s\+$/

" 保存时自动删除行尾空格（保留光标位置；跳过 markdown/text，行尾两空格=硬换行）
function! TrimTrailingWhitespace()
    if &filetype =~ 'markdown\|text'
        return
    endif
    let l:save = winsaveview()
    keeppatterns %s/\s\+$//e
    call winrestview(l:save)
endfunction
autocmd BufWritePre * call TrimTrailingWhitespace()

" ---- leader 键 ----
let mapleader = ","

" ============================================================
"  GUI 设置（gvim / MacVim）
" ============================================================
if has("gui_running")
    " 去掉工具栏/菜单栏/滚动条，界面更简洁
    set guioptions-=T   " 工具栏
    set guioptions-=m   " 菜单栏
    set guioptions-=r   " 右侧滚动条
    set guioptions-=L   " 左侧滚动条
    set guioptions-=e   " 图形 tab

    " 字体
    if has("gui_macvim")
        set guifont=Menlo:h14
        set linespace=2
        " set macligatures      " 连字（可选，需 MacVim 支持）
    elseif has("gui_gtk3") || has("gui_gtk")
        set guifont=DejaVu\ Sans\ Mono\ 12
    endif

    " GUI 下系统剪贴板可用，Ctrl+C/X/V 直接生效
endif

" ---- 主题 ----
" onedark 未安装时（首次 PlugInstall 前）不报 E185，静默跳过
if !empty(globpath(&rtp, 'colors/onedark.vim'))
    colorscheme onedark
endif

" ============================================================
"  插件配置
" ============================================================

" rtl_align 配置：代码中不写对齐标记，普通模式 :RtlAlign 自动识别全部块
let g:rtl_align_signal_marker     = ''             " 空 = 自动识别信号声明块
let g:rtl_align_inst_marker       = ''             " 空 = 自动识别例化块
let g:rtl_align_keep_marker       = '@keep'        " 代码中不使用；保留插件跳过能力
let g:rtl_align_min_signal_lines  = 3              " 信号块 ≤N 行不处理；设为 0 关闭过滤
let g:rtl_align_min_para_lines    = 3              " 正文参数块 ≤N 行不处理；设为 0 关闭过滤

" rtl_align 快捷键（,aa 全部 / ,am module / ,as 信号 / ,ai 例化）
nnoremap <silent> <leader>aa :RtlAlign<CR>
nnoremap <silent> <leader>am :RtlAlignModule<CR>
nnoremap <silent> <leader>as :RtlAlignSignal<CR>
nnoremap <silent> <leader>ai :RtlAlignInst<CR>
vnoremap <silent> <leader>aa <Plug>(rtl-align-block)
vnoremap <silent> <leader>am <Plug>(rtl-align-module)
vnoremap <silent> <leader>as <Plug>(rtl-align-signal)
vnoremap <silent> <leader>ai <Plug>(rtl-align-inst)

" MUcomplete：链式补全（路径→omni→关键词→词典→拼写），Tab 触发
set completeopt+=menuone

" NERDTree
nnoremap <C-n> :NERDTreeToggle<CR>              " 打开/关闭（Ctrl+n）
nnoremap ff    :NERDTreeToggle<CR>              " 打开/关闭（ff）
nnoremap <leader>nf :NERDTreeFind<CR>           " 定位当前文件到树
nnoremap <leader>nr :NERDTreeRefreshRoot<CR>    " 刷新树

" 只剩 NERDTree 窗口时退出 vim
autocmd BufEnter * if winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" vim-illuminate：默认用 CursorLine 高亮，onedark 下几乎不可见，显式设灰底
highlight IlluminatedWord      guibg=#4b5263 ctermbg=239
highlight IlluminatedWordText  guibg=#4b5263 ctermbg=239

" airline：匹配 onedark
let g:airline_theme = 'onedark'
let g:airline_powerline_fonts = 0

" gitgutter：跳转改动块（已停用）
" nmap ]h <Plug>(GitGutterNextHunk)
" nmap [h <Plug>(GitGutterPrevHunk)

" vim-header：F4 添加/更新文件头
" 作者名等个人信息放 ~/.vimrc_local（不进公开仓库）：
"   let g:header_field_author = 'Your Name'
"   let g:header_field_author_email = 'you@example.com'

" easy-align：ga 对齐
xmap ga <Plug>(EasyAlign)
nmap ga <Plug>(EasyAlign)

" ============================================================
"  文件操作 / 系统剪贴板快捷键（非 vim 习惯）
"  注意：+y/+p 需 vim 编译时含 +clipboard（服务器无，Mac/GUI 有）；
"        终端里 Ctrl+S 需 stty -ixon（bashrc 已加）
" ============================================================

" 保存：Ctrl+S
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>a

" 全选：Ctrl+A
nnoremap <C-a> ggVG
inoremap <C-a> <Esc>ggVG

" 复制/剪切：Ctrl+C / Ctrl+X（visual 模式，走系统剪贴板）
vnoremap <C-c> "+y
vnoremap <C-x> "+d

" 粘贴：p / "+p（Ctrl+V 保留为默认块选择）

" ---- 窗口 / 标签页（浏览器风格）----
" Ctrl+W：关闭当前窗口/文件（:q）。
"   注意：这会覆盖 Vim 默认 <C-w> 窗口命令前缀，<C-w>s / <C-w>v（分屏创建）不再生效；
"   分屏导航仍可用下面的 <C-h/j/k/l>。
nnoremap <C-w> :q<CR>
" Ctrl+T：开空 buffer 并打开 NERDTree 选文件（覆盖 Vim 默认 <C-t> tag 栈回退）。
nnoremap <C-t> :enew<CR>:NERDTreeFocus<CR>
" 分屏创建（替代被覆盖的 <C-w>s / <C-w>v）：,h 横向 / ,v 纵向
nnoremap <silent> <leader>h :split<CR>
nnoremap <silent> <leader>v :vsplit<CR>

" ============================================================
"  其他快捷键
" ============================================================

" 分屏导航（Ctrl + hjkl）
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" 清除搜索高亮（,l）
nnoremap <silent> <leader>l :nohlsearch<CR>

" 重新加载 vimrc（,sv）
nnoremap <silent> <leader>sv :source $MYVIMRC<CR>

" ---- 本机专属配置 ----
if filereadable(expand("~/.vimrc_local"))
    source ~/.vimrc_local
endif
