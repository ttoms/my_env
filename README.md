# my_env

个人开发环境：bash、vim（含插件）+ RTL 开发 skill/agent。跨机器复用，一次配置到处生效。

## 目录

```
my_env/
├── bashrc        # bash 配置（别名 / 历史 / 提示符 / git 别名）
├── vimrc         # vim 配置（基础设置 + vim-plug 插件）
├── install.sh    # 一键安装脚本
├── vim/
│   ├── rtl_align/             # rtl_align 对齐插件（autoload/plugin/ftplugin/doc）
│   └── vendor/                # 第三方插件最新源码 + plug.vim（离线安装用）
├── skills/       # Claude Code skill
│   └── rtl-developer/          # RTL 开发编排 skill
│       ├── SKILL.md            # 编排：架构先行 → 开发 → 验证
│       ├── references/rtl-coding-standard.md   # 通用 RTL 编码规范
│       └── scripts/quality_gate.py             # 质量门控脚本
├── agents/       # Claude Code subagent
│   ├── rtl-architect.md        # 架构师（方案）
│   ├── rtl-developer.md        # 开发（实现）
│   └── rtl-verifier.md         # 验证（TB+lint+sim+门控）
└── README.md
```

## 安装

```bash
git clone git@github.com:ttoms/my_env.git
cd my_env
bash install.sh              # 联网安装（vim-plug 从 GitHub 拉插件）
bash install.sh --offline    # 离线安装（用 vim/vendor/ 打包的插件源码）
```

`install.sh` 会：

1. 软链 `bashrc` → `~/.bashrc`、`vimrc` → `~/.vimrc`
2. 联网：下载 vim-plug 并自动执行 `:PlugInstall` 装所有插件
3. 离线（`--offline`，或联网失败自动降级）：直接把 `vim/vendor/` 里的插件源码拷到 `~/.vim/plugged/`

> `vim/vendor/` 保存了所有 vim-plug 插件的**当前最新源码**，离线环境可脱离 GitHub 直接安装。

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

## RTL 对齐插件（rtl_align，内置）

自带的 SystemVerilog / Verilog 代码对齐插件，通过 vim-plug 安装（vimrc 里 `Plug 'ttoms/my_env', { 'rtp': 'vim/rtl_align' }`）。按列对齐 RTL 代码，幂等（重复执行结果不变）。

- **命令**：`:RtlAlign`（对齐整个缓冲区）
- **快捷键**：`,aa`（普通/可视模式，可视模式对齐选中块）
- **标记**：`// @vlog-align`（信号声明块）、`// @inst`（例化块）、`// keep`（跳过该行）
- module 声明（parameter + port 列表）自动对齐
- 逗号行首风格（兼容行尾逗号输入）

详见 `:help rtl_align`。

## RTL 开发 skill + subagent（Claude Code）

通用 RTL 开发体系：一个编排 skill + 3 个 subagent，复杂模块架构先行。

- **skill** `skills/rtl-developer/`：编排「架构师出方案 → 用户确认 → 开发实现 → 验证闭环」，自带编码规范 + 质量门控脚本
- **agent** `agents/rtl-architect.md`（架构方案）/ `rtl-developer.md`（实现）/ `rtl-verifier.md`（验证）
- **编码规范** `skills/rtl-developer/references/rtl-coding-standard.md`：命名/风格/对齐/寄存器例化/可综合性/质量门控

### 安装到 Claude Code

把 skill 和 agents 软链进 Claude Code 配置目录（`~/.claude/`）：

```bash
# skill（目录软链）
ln -sf "$PWD/skills/rtl-developer" ~/.claude/skills/rtl-developer
# agents（文件软链）
ln -sf "$PWD/agents/rtl-architect.md"  ~/.claude/agents/rtl-architect.md
ln -sf "$PWD/agents/rtl-developer.md"  ~/.claude/agents/rtl-developer.md
ln -sf "$PWD/agents/rtl-verifier.md"   ~/.claude/agents/rtl-verifier.md
```

（本仓库用 `CC/skills`、`CC/agents` 软链到 `~/.claude/`，各机器按自己目录结构调整。）

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
- `,aa`：RTL 代码对齐（可视模式对齐选中块）
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
