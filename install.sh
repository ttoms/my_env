#!/usr/bin/env bash
# ============================================================
#  install.sh — 一键安装 bashrc / vimrc / vim-plug
#  用法：bash install.sh
# ============================================================
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 软链 bashrc → ~/.bashrc"
ln -sf "$REPO_DIR/bashrc" "$HOME/.bashrc"

echo "==> 软链 vimrc → ~/.vimrc"
ln -sf "$REPO_DIR/vimrc" "$HOME/.vimrc"

echo "==> 下载 vim-plug（插件管理器）"
curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

echo
echo "==> 完成。"
echo "    1) 重新打开终端或 source ~/.bashrc 让 bash 配置生效"
echo "    2) 启动 vim 执行 :PlugInstall 安装插件"
