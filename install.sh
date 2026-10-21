#!/usr/bin/env bash
# ============================================================
#  install.sh — 一键安装 bashrc / vimrc / vim-plug + 插件
#  用法：
#    bash install.sh              联网安装（vim-plug 从 GitHub 拉第三方插件）
#    bash install.sh --offline    离线安装（用 vim/vendor/ 打包的插件源码）
#  说明：
#    - 全部复制安装，不软链
#    - 已存在的 ~/.bashrc / ~/.vimrc / ~/.vim 先加时间戳备份
#    - 所有插件（包含本仓库自带插件）统一用 vim-plug 管理
#    - 联网失败自动降级为离线模式
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=0
if [ "$1" = "--offline" ] || [ "$1" = "-o" ]; then
    OFFLINE=1
fi

TS="$(date +%Y%m%d-%H%M%S)"

# 备份单个文件：仅当目标与源不同（有用户改动）才备份；与源一致则直接覆盖，避免重复安装 .bak 堆积
backup_file() {
    local src="$1"      # repo 源文件
    local dst="$2"      # 目标（~/.bashrc 等）
    local bak="$dst.bak.$TS"
    if [ -L "$dst" ]; then
        # 软链：解引用备份目标内容；只 unlink 软链本体，不碰 target
        echo "==> 备份软链 $dst → $bak（解引用保留内容）"
        cp -aL "$dst" "$bak" 2>/dev/null || echo "    （悬空软链，无内容可备份）"
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            echo "==> $dst 与源一致，跳过备份（直接覆盖）"
            rm -f "$dst"
        else
            echo "==> 备份 $dst → $bak"
            mv "$dst" "$bak"
        fi
    fi
}

echo "==> 备份已存在的 ~/.bashrc / ~/.vimrc（仅当有用户改动时）"
backup_file "$REPO_DIR/bashrc" "$HOME/.bashrc"
backup_file "$REPO_DIR/vimrc" "$HOME/.vimrc"

# ~/.vim 目录：仅首次（用户自有、无 plug.vim 标记）才整目录备份，此后视为受管目录、跳过备份
if [ -d "$HOME/.vim" ] && [ ! -e "$HOME/.vim/autoload/plug.vim" ]; then
    echo "==> 备份用户自有 ~/.vim → $HOME/.vim.bak.$TS"
    mv "$HOME/.vim" "$HOME/.vim.bak.$TS"
elif [ -L "$HOME/.vim" ]; then
    echo "==> 备份软链 ~/.vim → $HOME/.vim.bak.$TS（解引用保留内容）"
    cp -aL "$HOME/.vim" "$HOME/.vim.bak.$TS" 2>/dev/null || true
    rm -f "$HOME/.vim"
fi

echo "==> 复制 bashrc → ~/.bashrc"
cp "$REPO_DIR/bashrc" "$HOME/.bashrc"

echo "==> 复制 vimrc → ~/.vimrc"
cp "$REPO_DIR/vimrc" "$HOME/.vimrc"

mkdir -p "$HOME/.vim/autoload" "$HOME/.vim/plugged"

# rtl_align 是本仓库自带插件，始终复制（不依赖网络）
echo "==> 复制 rtl_align 插件（本仓库自带）"
rm -rf "$HOME/.vim/plugged/rtl_align"
cp -rf "$REPO_DIR/vim/rtl_align" "$HOME/.vim/plugged/rtl_align"

# 判断安装模式
MODE="online"
if [ "$OFFLINE" = "1" ]; then
    MODE="offline"
else
    echo "==> 下载 vim-plug（插件管理器）"
    if ! curl -fsSL --connect-timeout 8 \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
        -o "$HOME/.vim/autoload/plug.vim"; then
        echo "!! 联网失败，自动切换离线模式"
        MODE="offline"
    fi
fi

if [ "$MODE" = "offline" ]; then
    echo "==> [离线模式] 用 vim/vendor/ 打包的插件"
    cp -f "$REPO_DIR/vim/vendor/plug.vim" "$HOME/.vim/autoload/plug.vim"
    for d in "$REPO_DIR"/vim/vendor/*/; do
        name="$(basename "$d")"
        rm -rf "$HOME/.vim/plugged/$name"
        cp -rf "$d" "$HOME/.vim/plugged/$name"
        echo "    bundled: $name"
    done
else
    echo "==> 联网安装第三方插件（vim-plug）"
    if ! vim +PlugInstall +qa; then
        echo "!! 部分插件安装失败，可稍后在 vim 里重新执行 :PlugInstall"
    fi
fi

echo
echo "==> 完成。重新打开终端或 source ~/.bashrc 让 bash 配置生效"
