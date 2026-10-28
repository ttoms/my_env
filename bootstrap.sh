#!/usr/bin/env bash
# 把本仓库的 skill / agents 注册到 Claude Code（软链）。
# 用法：bash bootstrap.sh
set -euo pipefail

if readlink -f "$0" >/dev/null 2>&1; then
    SELF=$(readlink -f "$0")
else
    SELF=$0          # macOS 自带 readlink 无 -f
fi
REPO_DIR=$(cd "$(dirname "$SELF")" && pwd)

SKILLS_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.claude/agents"
mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

SKILL_LINK="$SKILLS_DIR/rtl-developer"
if [ -e "$SKILL_LINK" ] && [ ! -L "$SKILL_LINK" ]; then
    echo "error: $SKILL_LINK 已存在且不是软链，请先备份/移走" >&2
    exit 1
fi
ln -sfn "$REPO_DIR/skills/rtl-developer" "$SKILL_LINK"

for a in rtl-architect rtl-developer rtl-verifier; do
    dst="$AGENTS_DIR/$a.md"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "error: $dst 已存在且不是软链，请先备份/移走" >&2
        exit 1
    fi
    ln -sfn "$REPO_DIR/agents/$a.md" "$dst"
done

echo "registered:"
ls -l "$SKILL_LINK"
ls -l "$AGENTS_DIR"/rtl-architect.md "$AGENTS_DIR"/rtl-developer.md \
      "$AGENTS_DIR"/rtl-verifier.md
