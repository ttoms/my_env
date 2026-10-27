#!/usr/bin/env bash
# 用 rtl_align 插件全量对齐一个 RTL 文件（agent / CI 可用，无需交互）
# 用法：scripts/align.sh path/to/module.sv
# 可选：RTL_ALIGN_RTP=/path/to/vim/rtl_align scripts/align.sh module.sv
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <rtl.sv>" >&2
    exit 2
fi

VIM=${VIM:-vim}
if readlink -f "$0" >/dev/null 2>&1; then
    SELF=$(readlink -f "$0")
else
    SELF=$0          # macOS 自带 readlink 无 -f；软链场景靠 $HOME 候选兜底
fi
SELF_DIR=$(cd "$(dirname "$SELF")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/../../.." && pwd)     # scripts → rtl-developer → skills → my_env

RTP=${RTL_ALIGN_RTP:-}
if [ -z "$RTP" ]; then
    for cand in "$REPO_ROOT/vim/rtl_align" "$HOME/.vim/plugged/rtl_align"; do
        if [ -f "$cand/plugin/rtl_align.vim" ]; then
            RTP=$cand
            break
        fi
    done
fi
[ -n "$RTP" ] || { echo "rtl_align 未找到，请设置 RTL_ALIGN_RTP=<path>" >&2; exit 3; }

"$VIM" -Nu NONE -N --not-a-term -es \
    -c "set runtimepath^=$RTP" \
    -c "let g:rtl_align_signal_marker = ''" \
    -c "let g:rtl_align_inst_marker = ''" \
    -c "runtime plugin/rtl_align.vim" \
    -c "if !exists(':RtlAlign') | cquit 3 | endif" \
    -c "RtlAlign" \
    -c "wq" "$1"
