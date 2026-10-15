# my_env

个人开发环境配置：bash、vim（含插件）。跨机器复用，一次配置到处生效。

## 目录

```
my_env/
├── bashrc        # bash 配置（别名 / 历史 / 提示符 / git 别名）
├── vimrc         # vim 配置（基础设置 + vim-plug 插件）
├── install.sh    # 一键安装脚本
└── README.md
```

## 安装

```bash
git clone git@github.com:ttoms/my_env.git
cd my_env
bash install.sh
```

`install.sh` 会：

1. 软链 `bashrc` → `~/.bashrc`
2. 软链 `vimrc` → `~/.vimrc`
3. 下载 vim-plug 插件管理器到 `~/.vim/autoload/`

装完启动 vim，执行 `:PlugInstall` 安装插件。

## 包含的 vim 插件

| 插件 | 用途 |
|------|------|
| `joshdick/onedark.vim` | 主题 |
| `preservim/nerdtree` | 文件树（`Ctrl+n` 开关） |
| `tpope/vim-fugitive` | git 集成 |
| `vim-airline/vim-airline` | 状态栏（onedark 主题） |
| `vhda/verilog_systemverilog.vim` | SystemVerilog 语法 / 缩进 |
| `airblade/vim-gitgutter` | git 改动标记（`]h` / `[h` 跳转） |
| `alpertuna/vim-header` | 自动文件头（`F4` 添加/更新） |
| `junegunn/vim-easy-align` | 对齐（`ga`） |
| `tpope/vim-surround` | 环绕引号/括号（`cs` / `ds` / `ys`） |
| `jiangmiao/auto-pairs` | 自动配对括号 |

## 常用快捷键

- **leader 键 = `,`**（逗号）
- `Ctrl+s`：保存
- `Ctrl+a`：全选
- `Ctrl+c` / `Ctrl+x`：复制 / 剪切（visual 模式）
- `Ctrl+v`：粘贴
- `Ctrl+q`：块选择（原 `Ctrl+v` 被粘贴占用）
- `Ctrl+n`：开关文件树
- `Ctrl+h/j/k/l`：分屏导航
- `,l`：清除搜索高亮
- `F4`：添加/更新文件头（vim-header）

> 系统剪贴板（`Ctrl+c/x/v`）需 vim 编译时含 `+clipboard`；终端里 `Ctrl+s/q` 需 bash 已执行 `stty -ixon`（bashrc 已加）。文件头作者名放 `~/.vimrc_local` 里设 `g:header_field_author`。

## 本机专属配置（不进 git）

`bashrc` 末尾会加载 `~/.bashrc_local`（如果存在）。这个文件**在 home 目录、不进 git**，用来放每台机器各自的东西——本机路径别名、API key 等私密/专属内容。

```bash
# ~/.bashrc_local 示例
alias ob='cd ~/path/to/your/vault'     # 本机某目录快捷跳转（换成你自己的路径）
export MX_APIKEY='xxx'                 # 私密 key
```

建议 `chmod 600 ~/.bashrc_local`（含 key 时只允许本人读）。每台机器自己建一份，随 clone/pull 不会互相覆盖。

## 多机同步

配置是纯文本 + symlink，改完 `git push`，其他机器 `git pull` 后重跑 `install.sh` 即可（`~/.bashrc_local` 各机各自维护，不随仓库同步）。
