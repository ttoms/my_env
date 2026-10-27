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
ARGS=(-es)
if [ -n "${RTL_ALIGN_RTP:-}" ]; then
    ARGS+=(-c "set runtimepath^=$RTL_ALIGN_RTP")
fi

"$VIM" "${ARGS[@]}" \
    -c "set nocompatible" \
    -c "let g:rtl_align_signal_marker = ''" \
    -c "let g:rtl_align_inst_marker = ''" \
    -c "runtime plugin/rtl_align.vim" \
    -c "RtlAlign" \
    -c "wq" "$1"
