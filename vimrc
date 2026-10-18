" ============================================================
"  vimrc — 通用 vim 配置
"  由 install.sh 复制安装到 ~/.vimrc；插件用 :PlugInstall 安装
" ============================================================

set nocompatible

" ============================================================
"  插件（vim-plug，放在最前面）
" ============================================================
call plug#begin('~/.vim/plugged')

" 主题
Plug 'joshdick/onedark.vim'

" 文件树
Plug 'preservim/nerdtree'
" git 集成
Plug 'tpope/vim-fugitive'
" 状态栏
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
" SystemVerilog 语法/缩进
Plug 'vhda/verilog_systemverilog.vim'
" git 改动标记（gutter）
Plug 'airblade/vim-gitgutter'
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

" rtl_align 对齐插件（本仓库自带，install.sh 复制到 ~/.vim/plugged/rtl_align）
Plug '~/.vim/plugged/rtl_align'

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
set relativenumber
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

" NERDTree
nnoremap <C-n> :NERDTreeToggle<CR>              " 打开/关闭（Ctrl+n）
nnoremap ff    :NERDTreeToggle<CR>              " 打开/关闭（ff）
nnoremap <leader>nf :NERDTreeFind<CR>           " 定位当前文件到树
nnoremap <leader>nr :NERDTreeRefreshRoot<CR>    " 刷新树

" 只剩 NERDTree 窗口时退出 vim
autocmd BufEnter * if winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" airline：匹配 onedark
let g:airline_theme = 'onedark'
let g:airline_powerline_fonts = 0

" gitgutter：跳转改动块
nmap ]h <Plug>(GitGutterNextHunk)
nmap [h <Plug>(GitGutterPrevHunk)

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
"        终端里 Ctrl+S/Ctrl+Q 需 stty -ixon（bashrc 已加）
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

" 粘贴：Ctrl+V
nnoremap <C-v> "+p
inoremap <C-v> <C-r>+
vnoremap <C-v> "+p

" 块选择（原 Ctrl+V 被粘贴占用，改用 Ctrl+Q）
nnoremap <C-q> <C-V>

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

" ---- 本机专属配置（不进 git）----
if filereadable(expand("~/.vimrc_local"))
    source ~/.vimrc_local
endif
