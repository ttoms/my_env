#!/usr/bin/env bash
# ============================================================
#  install.sh — 一键安装 bashrc / vimrc / vim-plug + 插件
#  用法：
#    bash install.sh              联网安装（vim-plug 从 GitHub 拉插件）
#    bash install.sh --offline    离线安装（用 vim/vendor/ 打包的插件源码）
#  说明：默认联网，联网失败时自动降级为离线模式
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OFFLINE=0
if [ "$1" = "--offline" ] || [ "$1" = "-o" ]; then
    OFFLINE=1
fi

echo "==> 软链 bashrc → ~/.bashrc"
ln -sf "$REPO_DIR/bashrc" "$HOME/.bashrc"

echo "==> 软链 vimrc → ~/.vimrc"
ln -sf "$REPO_DIR/vimrc" "$HOME/.vimrc"

mkdir -p "$HOME/.vim/autoload" "$HOME/.vim/plugged"

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
    echo "==> 联网安装插件（vim-plug）"
    if ! vim +PlugInstall +qa; then
        echo "!! 部分插件安装失败，可稍后在 vim 里重新执行 :PlugInstall"
    fi
fi

echo
echo "==> 完成。重新打开终端或 source ~/.bashrc 让 bash 配置生效"
