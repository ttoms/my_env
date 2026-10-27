#!/usr/bin/env python3
"""
RTL 轻量质量门控（开发期自检）

只做秒级文本检查，不依赖 EDA 工具；默认只有 error 判失败。

检查项：
  1. 文件 / 模块命名一致，一个文件一个 module
  2. 模块头注释完整
  3. 模块 .sv 内不写断言
  4. 可综合性禁用项（initial / force / #delay / casex / always @）
  5. case 必须有 default
  6. 实例名全大写
  7. 例化端口只连信号名 / 参数 / 常量
  8. 无对齐标记
  9. `default_nettype none / wire
 10. 存在 .sva 时必须由 SVA_ON include

用法：
  python3 quality_gate.py <rtl.sv> [--lint] [--strict]

  --lint    有 verilator 就顺带跑 lint，结果仅作 INFO，不影响 PASS/FAIL
  --strict  warning 也视为失败（默认关闭）

退出码：
  0 - 无 error
  1 - 存在 error（--strict 时 warning 也算）
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

HEADER_FIELDS = ("Module", "Description", "Features", "Parameters", "Limitations")

KEYWORDS = {
    "module", "endmodule", "input", "output", "inout", "ref",
    "parameter", "localparam", "logic", "wire", "reg", "bit", "byte",
    "int", "shortint", "longint", "integer", "time", "real", "shortreal",
    "typedef", "enum", "struct", "union", "packed", "signed", "unsigned",
    "assign", "always", "always_ff", "always_comb", "always_latch",
    "initial", "final", "if", "else", "for", "foreach", "while", "do",
    "repeat", "forever", "wait", "case", "casez", "casex", "randcase",
    "endcase", "unique", "priority", "default", "begin", "end",
    "function", "endfunction", "task", "endtask", "return", "break",
    "continue", "generate", "endgenerate", "genvar", "package",
    "endpackage", "interface", "endinterface", "modport", "import",
    "export", "class", "endclass", "covergroup", "endgroup", "property",
    "endproperty", "assert", "assume", "cover", "restrict", "expect",
    "fork", "join", "join_any", "join_none", "disable", "posedge",
    "negedge", "edge", "and", "or", "not", "nand", "nor", "xor", "xnor",
    "buf", "bind", "virtual", "extern", "static", "const", "var",
}


TOKEN_RE = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/')


def clean(text: str, mask_str: bool = False) -> str:
    """去掉注释；mask_str 时把字符串内容也抹掉，保留换行与位置。"""
    out, last = [], 0
    for m in TOKEN_RE.finditer(text):
        out.append(text[last:m.start()])
        tok = m.group(0)
        if tok.startswith('"'):
            out.append('"' + " " * (len(tok) - 2) + '"' if mask_str else tok)
        else:
            out.append("".join("\n" if c == "\n" else " " for c in tok))
        last = m.end()
    out.append(text[last:])
    return "".join(out)


def skip_balanced(text: str, pos: int) -> int:
    """pos 指向 '('，返回匹配 ')' 的下标；不匹配时返回文本末尾。"""
    depth = 0
    for i in range(pos, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return len(text) - 1


def remove_param_blocks(text: str) -> str:
    """移除 #(...) 参数块（支持嵌套括号），保留原位置。"""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text[i] == "#":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] == "(":
                k = skip_balanced(text, j)
                out.append(re.sub(r"[^\n]", " ", text[i:k + 1]))
                i = k + 1
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def find_instances(code: str):
    """返回 [(pos, module_type, instance_name), ...]。"""
    results = []
    for m in re.finditer(r"(?m)^[ \t]*([A-Za-z_]\w*)", code):
        w1 = m.group(1)
        if w1 in KEYWORDS:
            continue
        pos = m.end()
        n = len(code)
        while pos < n and code[pos] in " \t\r\n":
            pos += 1
        if pos < n and code[pos] == "#":
            j = pos + 1
            while j < n and code[j] in " \t\r\n":
                j += 1
            if j < n and code[j] == "(":
                pos = skip_balanced(code, j) + 1
                while pos < n and code[pos] in " \t\r\n":
                    pos += 1
        m2 = re.match(r"([A-Za-z_]\w*)", code[pos:])
        if not m2 or m2.group(1) in KEYWORDS:
            continue
        end = pos + m2.end()
        while end < n and code[end] in " \t\r\n":
            end += 1
        if end < n and code[end] == "(":
            results.append((m.start(1), w1, m2.group(1)))
    return results


def expr_is_connection_safe(expr: str) -> bool:
    """端口连接表达式是否只含信号名、参数名或字面常量。"""
    e = re.sub(r"\[[^\]]*\]", "", expr.strip()).strip()
    if not e:
        return True
    if re.fullmatch(r"[A-Za-z_]\w*", e):
        return True
    if re.fullmatch(r"[A-Za-z_]\w*::[A-Za-z_]\w*", e):
        return True
    if re.fullmatch(r"-?\s*\d+", e):
        return True
    if re.fullmatch(r"-?\s*\d*'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+", e):
        return True
    return bool(re.fullmatch(r"'[01xXzZ]", e))


class QualityGate:
    def __init__(self, rtl_path, strict=False, lint=False):
        self.rtl_path = Path(rtl_path)
        self.strict = strict
        self.lint = lint
        self.errors = []
        self.warnings = []
        self.infos = []
        self.passed = []

    def _fail(self, msg):
        self.errors.append(msg)

    def _warn(self, msg):
        self.warnings.append(msg)

    def _info(self, msg):
        self.infos.append(msg)

    def _pass(self, msg):
        self.passed.append(msg)

    @staticmethod
    def _line(text, pos):
        return text.count("\n", 0, pos) + 1

    def check(self):
        print("=" * 64)
        print(f"RTL Quality Gate: {self.rtl_path.name}")
        print("=" * 64)
        if not self.rtl_path.exists():
            print(f"ERROR: RTL file not found: {self.rtl_path}")
            return False

        raw = self.rtl_path.read_text(encoding="utf-8", errors="replace")
        code_comments = clean(raw)
        code = clean(raw, mask_str=True)

        self._check_file_and_module(code)
        self._check_header(raw, code)
        self._check_default_nettype(raw)
        self._check_assertions(code)
        self._check_constructs(code)
        self._check_cases(code)
        self._check_instances(code)
        self._check_port_connections(code)
        self._check_markers(raw)
        self._check_sva(code_comments)
        if self.lint:
            self._run_lint()

        print("\n" + "=" * 64)
        print("RESULTS")
        print("=" * 64)
        print(f"  Passed  : {len(self.passed)}")
        print(f"  Warnings: {len(self.warnings)}")
        print(f"  Errors  : {len(self.errors)}")
        for label, items in (("Info", self.infos), ("Warnings", self.warnings),
                             ("Errors", self.errors), ("Passed checks", self.passed)):
            if not items:
                continue
            print(f"\n{label}:")
            tag = {"Info": "INFO", "Warnings": "WARN",
                   "Errors": "FAIL", "Passed checks": "PASS"}[label]
            for item in items:
                print(f"  [{tag}] {item}")

        failed = bool(self.errors) or (self.strict and bool(self.warnings))
        print("=" * 64)
        print("RESULT: FAILED" if failed else "RESULT: PASSED")
        return not failed

    def _check_file_and_module(self, code):
        stem = self.rtl_path.stem
        if self.rtl_path.suffix != ".sv":
            self._warn(f"RTL 文件后缀应为 .sv：{self.rtl_path.suffix}")
        if not re.fullmatch(r"[a-z][a-z0-9_]*", stem):
            self._fail(f"文件名应为小写蛇形：{stem}")
        else:
            self._pass("文件命名规范")

        mods = re.findall(r"(?m)^[ \t]*module\s+([A-Za-z_]\w*)", code)
        if len(mods) != 1:
            self._fail(f"一个文件只能有一个 module，当前 {len(mods)} 个")
        elif mods[0] != stem:
            self._fail(f"模块名 {mods[0]} 与文件名 {stem} 不一致")
        else:
            self._pass("模块名与文件名一致")

    def _check_header(self, raw, code):
        m = re.search(r"(?m)^[ \t]*module\b", code)
        prefix = raw[: m.start()] if m else raw
        if not re.search(r"(?m)^//={5,}\s*$", prefix):
            self._fail("缺少模块头注释块（//====...==== 格式）")
            return
        missing = [f for f in HEADER_FIELDS
                   if not re.search(rf"(?m)^[ \t]*//\s*{f}\b", prefix)]
        if missing:
            self._fail(f"模块头注释缺少字段：{', '.join(missing)}")
        else:
            self._pass("模块头注释完整")

    def _check_default_nettype(self, raw):
        lines = [line.strip() for line in raw.splitlines() if line.strip()]
        if not lines or not lines[0].startswith("`default_nettype none"):
            self._fail("首行缺少 `default_nettype none")
        elif lines[-1] != "`default_nettype wire":
            self._fail("末尾缺少 `default_nettype wire")
        else:
            self._pass("default_nettype 完整")

    def _check_assertions(self, code):
        hits = list(re.finditer(r"\b(assert|assume|cover|restrict)\b", code))
        for m in hits[:3]:
            self._fail(f"L{self._line(code, m.start())}: "
                       "模块内不允许写断言，请放到同名 .sva")
        if len(hits) > 3:
            self._fail(f"另有 {len(hits) - 3} 处断言写在 .sv 内")
        if not hits:
            self._pass(".sv 内无断言")

    def _check_constructs(self, code):
        checks = [
            (r"\binitial\b", "模块内禁止 initial"),
            (r"\bforce\b|\brelease\b", "禁止 force/release"),
            (r"(?<![\w'])#\s*\d", "禁止 #delay"),
            (r"\bcasex\b", "禁止 casex"),
            (r"\balways\s*@", "禁止 always @(...)，改用 always_ff/always_comb"),
            (r"\balways_latch\b", "禁止 always_latch（避免 latch）"),
        ]
        for pat, msg in checks:
            hits = list(re.finditer(pat, code))
            for m in hits[:3]:
                self._fail(f"L{self._line(code, m.start())}: {msg}")
            if len(hits) > 3:
                self._fail(f"另有 {len(hits) - 3} 处：{msg}")
            if not hits:
                self._pass(f"未发现：{msg.split('（')[0]}")

    def _check_cases(self, code):
        stack, count = [], 0
        for m in re.finditer(r"\b(case|casez|casex|endcase)\b", code):
            tok = m.group(1)
            if tok in ("case", "casez", "casex"):
                stack.append((m.start(), tok))
            elif stack:
                start, kind = stack.pop()
                body = code[start:m.start()]
                count += 1
                if kind == "casez":
                    self._warn(f"L{self._line(code, start)}: 慎用 casez")
                if not re.search(r"\bdefault\b", body):
                    self._fail(f"L{self._line(code, start)}: case 缺少 default 分支")
        self._pass("case 语句检查通过" if count else "无 case 语句")

    def _check_instances(self, code):
        bad = [(pos, inst) for pos, _type, inst in find_instances(code)
               if not re.fullmatch(r"[A-Z][A-Z0-9_]*", inst)]
        for pos, inst in bad[:5]:
            self._fail(f"L{self._line(code, pos)}: 实例名 {inst} 应全大写")
        if len(bad) > 5:
            self._fail(f"另有 {len(bad) - 5} 处实例名不是全大写")
        if not bad:
            self._pass("实例名全大写")

    def _check_port_connections(self, code):
        code_np = remove_param_blocks(code)
        bad = []
        for m in re.finditer(r"(?<![\w\]\)])\.\s*([A-Za-z_]\w*)\s*\(", code_np):
            openp = m.end() - 1
            expr = code_np[openp + 1:skip_balanced(code_np, openp)]
            if not expr_is_connection_safe(expr):
                bad.append((m.start(), m.group(1), " ".join(expr.split())))
        for pos, port, expr in bad[:5]:
            self._fail(f"L{self._line(code, pos)}: .{port}({expr}) 含逻辑运算，"
                       "应外部预处理为信号")
        if len(bad) > 5:
            self._fail(f"另有 {len(bad) - 5} 处端口连接含逻辑运算")
        if not bad:
            self._pass("例化端口连接规范（无逻辑运算式）")

    def _check_markers(self, raw):
        hits = [name for pat, name in (
            (r"@vlog-align", "@vlog-align"), (r"@inst\b", "@inst"),
            (r"//\s*keep\b", "keep")) if re.search(pat, raw)]
        if hits:
            self._fail(f"代码中不允许对齐标记（{', '.join(hits)}），"
                       "使用 :RtlAlign 或 scripts/align.sh 全量对齐")
        else:
            self._pass("无对齐标记")

    def _check_sva(self, code_comments):
        sva_path = self.rtl_path.with_suffix(".sva")
        if not sva_path.exists():
            self._pass("无断言文件（按需创建）")
            return

        includes = re.findall(r'`include\s+"([^"]+)"', code_comments)
        if sva_path.name not in includes:
            self._warn(f"存在 {sva_path.name}，但模块没有 include 它")
            return
        guarded = False
        for m in re.finditer(r'`include\s+"' + re.escape(sva_path.name) + r'"',
                             code_comments):
            before = code_comments[max(0, m.start() - 400):m.start()]
            after = code_comments[m.end():m.end() + 400]
            guarded = bool(re.search(r"`ifdef\s+SVA_ON\b", before)
                           and re.search(r"`endif\b", after))
        if not guarded:
            self._warn(f"include {sva_path.name} 没有用 `ifdef SVA_ON 控制")
        else:
            self._pass("SVA include 由 SVA_ON 控制")

    def _run_lint(self):
        exe = shutil.which("verilator")
        if not exe:
            self._info("未找到 verilator，lint 跳过（不影响结果）")
            return
        cmd = [exe, "--lint-only", "-Wall", "-Wno-fatal",
               "--top-module", self.rtl_path.stem,
               f"-I{self.rtl_path.parent}", str(self.rtl_path)]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        except (OSError, subprocess.TimeoutExpired) as exc:
            self._info(f"lint 未完成：{exc}")
            return

        output = (proc.stdout or "") + (proc.stderr or "")
        findings = re.findall(r"%(Warning|Error)-(\w+):\s*(.*)", output)
        for kind, code, detail in findings[:20]:
            self._info(f"LINT {kind}-{code}: {detail}")
        if len(findings) > 20:
            self._info(f"另有 {len(findings) - 20} 条 lint 信息未列出")
        if not findings:
            if proc.returncode == 0:
                self._pass("verilator lint 通过")
            else:
                self._info(f"lint 退出码 {proc.returncode}，仅作参考")


def main():
    parser = argparse.ArgumentParser(description="RTL 轻量质量门控")
    parser.add_argument("rtl", help="RTL 源文件（.sv）")
    parser.add_argument("--strict", action="store_true",
                        help="warning 也视为失败（默认关闭）")
    parser.add_argument("--lint", action="store_true",
                        help="有 verilator 时顺带 lint，结果仅作 INFO")
    args = parser.parse_args()
    gate = QualityGate(args.rtl, args.strict, args.lint)
    sys.exit(0 if gate.check() else 1)


if __name__ == "__main__":
    main()
