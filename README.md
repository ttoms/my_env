# my_env

个人开发环境：bash、vim（含插件）+ RTL 开发 skill/agent。跨机器复用，一次配置到处生效。

## 目录

```
my_env/
├── bashrc        # bash 配置（别名 / 历史 / 提示符 / git 别名）
├── vimrc         # vim 配置（基础设置 + vim-plug 插件）
├── install.sh    # 一键安装脚本
├── vim/
│   ├── rtl_align/             # 自带 RTL 对齐插件
│   └── vendor/                # 第三方插件最新源码 + plug.vim（离线安装用）
├── skills/       # Claude Code skill
│   └── rtl-developer/          # RTL 开发 skill（轻量、写前约束优先）
│       ├── SKILL.md            # 写前 checklist + 复杂度分级 + 秒级自检
│       ├── references/rtl-coding-standard.md   # 通用 RTL 编码规范
│       ├── templates/          # DFF/复位同步/CDC/同步 FIFO 参考模板
│       └── scripts/            # quality_gate.py（文本自检）+ align.sh（非交互对齐）
├── agents/       # Claude Code subagent
│   ├── rtl-architect.md        # 架构师（复杂模块方案）
│   ├── rtl-developer.md        # 开发（实现）
│   └── rtl-verifier.md         # 验证（定向 TB + 仿真，按需）
└── README.md
```

## 安装

```bash
git clone git@github.com:ttoms/my_env.git
cd my_env
bash install.sh              # 联网安装（vim-plug 从 GitHub 拉插件）
bash install.sh --offline    # 离线安装（用 vim/vendor/ 打包的插件源码）
```

`install.sh` 会（**全部复制，不软链**，my_env 目录删了也不影响）：

1. 备份已存在的 `~/.bashrc` / `~/.vimrc` / `~/.vim`（加 `.bak.<时间戳>` 后缀）
2. 复制 `bashrc` → `~/.bashrc`、`vimrc` → `~/.vimrc`
3. 复制 `rtl_align` 到 `~/.vim/plugged/`（vim-plug 统一管理，不依赖网络）
4. 联网：下载 vim-plug 并自动执行 `:PlugInstall` 装第三方插件
5. 离线（`--offline`，或联网失败自动降级）：把 `vim/vendor/` 里其余插件源码拷到 `~/.vim/plugged/`

> 所有插件（含自带的 rtl_align）统一用 vim-plug 管理，源码都打包在 `vim/vendor/`，离线环境可脱离 GitHub 直接安装。

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
| `RRethy/vim-illuminate` | 高亮光标下单词的其他出现位置（灰底） |

## RTL 对齐插件（rtl_align，内置）

自带的 SystemVerilog / Verilog 代码对齐插件，通过 vim-plug 安装（vimrc 里 `Plug 'ttoms/my_env', { 'rtp': 'vim/rtl_align' }`）。按列对齐 RTL 代码，幂等（重复执行结果不变）。

- **命令**：`:RtlAlign`（对齐整个缓冲区：module + 信号 + 例化）
- **快捷键**：`,aa`（普通/可视模式，可视模式对齐选中块）
- **无标记**：vimrc 已把 `g:rtl_align_signal_marker` / `g:rtl_align_inst_marker` 设为空，插件自动识别信号声明块和例化块，代码中不写 `@vlog-align` / `@inst`
- module 声明（parameter + port 列表）自动对齐
- 逗号行尾风格；packed 维度逐维拆前缀/后缀

阈值等其余配置项见 `vim/rtl_align/README.md`。

## RTL 开发 skill + subagent（Claude Code）

轻量、正向约束优先的 RTL 开发体系：一个 skill + 3 个 subagent。目标是 80% 写前约束 + 20% 秒级检查，不引入商用 IP 级 EDA flow。

- **skill** `skills/rtl-developer/`：写前 checklist（命名/复位/结构/接口/对齐）→ 按复杂度分级实现/架构先行 → 秒级自检
- **agent** `agents/rtl-architect.md`（仅复杂模块出方案）/ `rtl-developer.md`（实现）/ `rtl-verifier.md`（按需验证）
- **编码规范** `skills/rtl-developer/references/rtl-coding-standard.md`：命名/风格/对齐/寄存器例化/`.sva` 断言/可综合性/质量门控
- **模板库** `skills/rtl-developer/templates/`：`dffr`（控制类复位）、`dff`（数据通路无复位）、`rst_sync`（复位同步释放）、`cdc_2ff`（单 bit CDC）、`fifo_sync`（RTL+TB+SVA）
- **PPA 复位策略**：控制类寄存器（状态/计数/指针/valid）必须复位，数据通路寄存器不复位，减小复位树
- **秒级自检** `scripts/quality_gate.py <rtl.sv>`：纯文本、零依赖、约 0.03 s；默认只有 error 判失败，`--lint` 有 verilator 才跑且仅作 INFO，不要求 TB/Makefile
- **非交互对齐** `scripts/align.sh <rtl.sv>`：内部 `vim -es` 调用 rtl_align，agent 也能执行对齐规范
- **断言约定**：模块 `.sv` 内不写断言；协议/FSM/CDC 才建同名 `<module>.sva`，在 `endmodule` 前由 `SVA_ON` include；代码中不加对齐标记

### 安装到 Claude Code

把 skill 和 agents 软链进 Claude Code 配置目录（`~/.claude/`）：

```bash
bash bootstrap.sh
```

脚本会建立 `~/.claude/skills/rtl-developer` 和三个 `~/.claude/agents/rtl-*.md` 软链；
如果目标已存在且不是软链，会报错退出，不会覆盖真实目录/文件。

（本仓库用 `CC/skills`、`CC/agents` 软链到 `~/.claude/`，各机器按自己目录结构调整。）

## 常用快捷键

- **leader 键 = `,`**（逗号）
- `Ctrl+s`：保存
- `Ctrl+a`：全选
- `Ctrl+c` / `Ctrl+x`：复制 / 剪切（visual 模式）
- `Ctrl+v`：块选择（保留默认）
- `Ctrl+n` / `ff`：开关文件树（NERDTree）
- `,nf`：定位当前文件到文件树
- `,nr`：刷新文件树
- `Ctrl+h/j/k/l`：分屏导航
- `,l`：清除搜索高亮
- `,sv`：重新加载 vimrc
- `,aa`：RTL 代码对齐（可视模式对齐选中块）
- `F4`：添加/更新文件头（vim-header）

> 系统剪贴板（`Ctrl+c/x`）需 vim 编译时含 `+clipboard`；粘贴用 `p`/`"+p`。终端里 `Ctrl+s` 需 bash 已执行 `stty -ixon`（bashrc 已加）。文件头作者名放 `~/.vimrc_local` 里设 `g:header_field_author`。

## 本机专属配置（不进 git）

`bashrc` 末尾会加载 `~/.bashrc_local`（如果存在）。这个文件**在 home 目录、不进 git**，用来放每台机器各自的东西——本机路径别名、API key 等私密/专属内容。

```bash
# ~/.bashrc_local 示例
alias ob='cd ~/path/to/your/vault'     # 本机某目录快捷跳转（换成你自己的路径）
export MX_APIKEY='xxx'                 # 私密 key
```

建议 `chmod 600 ~/.bashrc_local`（含 key 时只允许本人读）。每台机器自己建一份，随 clone/pull 不会互相覆盖。

## 多机同步

配置是纯文本，改完 `git push`，其他机器 `git pull` 后重跑 `install.sh` 即可（`~/.bashrc_local` 各机各自维护，不随仓库同步）。
