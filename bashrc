# ============================================================
#  bashrc — 通用开发环境配置
#  由 install.sh 复制安装到 ~/.bashrc
# ============================================================

# ---- 编辑器 / 语言 ----
export EDITOR=vim
export VISUAL=vim
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 禁用终端流控（让 vim 的 Ctrl+S/Ctrl+Q 生效，而非挂起输出）
stty -ixon 2>/dev/null

# ---- 历史记录 ----
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T  "
shopt -s histappend          # 追加而非覆盖
shopt -s cmdhist             # 多行命令存为一条
shopt -s checkwinsize        # 换行自适应

# ---- 常用别名 ----
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -pv'

# 防止误操作（覆盖/删除需确认）
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# grep 高亮
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# git
alias g='gvim'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -20'
alias gd='git diff'
alias gdc='git diff --cached'
alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gco='git checkout'
alias gb='git branch'

# 磁盘 / 大小（人类可读）
alias df='df -h'
alias du='du -h'

# vim 相关
alias v='vim'
alias vi='vim'
alias vc='vim ~/.bashrc'       # 编辑 bashrc
alias sc='source ~/.bashrc'    # 重新加载 bashrc
alias vrc='vim ~/.vimrc'       # 编辑 vimrc

# cd 后自动 ls
cd() {
    builtin cd "$@" && ls
}

# ---- 提示符（git 感知）----
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/\* \(.*\)/ (\1)/'
}
export PS1='\[\033[32m\][\u@\h\[\033[00m\] \[\033[38;5;81m\]\w\[\033[33m\]$(parse_git_branch)\[\033[00m\]]\n\[\033[32m\]>\[\033[00m\] '

# ---- PATH ----
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

# ---- 补全 ----
if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
    . /etc/bash_completion
fi

# ---- 本机专属配置（不进 git，每台机器各自维护 ~/.bashrc_local）----
# 放本机路径别名、API key 等私密/专属内容
if [ -f ~/.bashrc_local ]; then
    . ~/.bashrc_local
fi
