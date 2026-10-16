#!/usr/bin/env bash
# ============================================================
#  install.sh — 一键安装 bashrc / vimrc / vim-plug + 插件
#  用法：
#    bash install.sh              联网安装（vim-plug 从 GitHub 拉第三方插件）
#    bash install.sh --offline    离线安装（用 vim/vendor/ 打包的插件源码）
#  说明：
#    - 全部复制安装，不软链（my_env 目录删了也不影响）
#    - 已存在的 ~/.bashrc / ~/.vimrc / ~/.vim 先加时间戳备份
#    - 所有插件（含自带 rtl_align）统一用 vim-plug 管理
#    - 联网失败自动降级为离线模式
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=0
if [ "$1" = "--offline" ] || [ "$1" = "-o" ]; then
    OFFLINE=1
fi

TS="$(date +%Y%m%d-%H%M%S)"

backup() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        echo "==> 备份 $1 → $1.bak.$TS"
        mv "$1" "$1.bak.$TS"
    fi
}

echo "==> 备份已存在的 ~/.bashrc / ~/.vimrc / ~/.vim（若有）"
backup "$HOME/.bashrc"
backup "$HOME/.vimrc"
backup "$HOME/.vim"

echo "==> 复制 bashrc → ~/.bashrc"
cp "$REPO_DIR/bashrc" "$HOME/.bashrc"

echo "==> 复制 vimrc → ~/.vimrc"
cp "$REPO_DIR/vimrc" "$HOME/.vimrc"

mkdir -p "$HOME/.vim/autoload" "$HOME/.vim/plugged"

# rtl_align 是本仓库自带插件，始终复制（不依赖网络）
echo "==> 复制 rtl_align 插件（本仓库自带）"
rm -rf "$HOME/.vim/plugged/rtl_align"
cp -rf "$REPO_DIR/vim/vendor/rtl_align" "$HOME/.vim/plugged/rtl_align"

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
        [ "$name" = "rtl_align" ] && continue   # 上面已复制
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
