#!/usr/bin/env python3
"""
RTL 模块质量门控检查

检查项：
  1. 文件 / 模块命名一致
  2. 模块头注释完整性
  3. 断言只在 .sva（按需创建），存在时通过 SVA_ON 在 endmodule 前 include
  4. .sva 中的参数校验
  5. 可综合性禁用项（initial / always @ / casex / force / #delay / fork 等）
  6. case default、always 风格、复位风格
  7. 例化实例名与端口连接规范
  8. 对齐标记禁用
  9. Testbench / Makefile

用法：
  python3 quality_gate.py <rtl_file.sv> [tb_file.sv] [--strict] [--dff-cell NAME]

退出码：
  0 - 无 error（--strict 时还要求无 warning）
  1 - 存在 error，或 --strict 下存在 warning
"""

import argparse
import re
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


def strip_comments(text: str) -> str:
    """移除 // 与 /* */ 注释，保留换行和字符串内容。"""
    out = list(text)
    i, n = 0, len(text)
    in_line = in_block = in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
            else:
                out[i] = " "
        elif in_block:
            if c == "*" and nxt == "/":
                out[i] = out[i + 1] = " "
                i += 1
                in_block = False
            elif c != "\n":
                out[i] = " "
        elif in_str:
            if c == "\\" and i + 1 < n:
                i += 1
            elif c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                out[i] = out[i + 1] = " "
                i += 1
                in_line = True
            elif c == "/" and nxt == "*":
                out[i] = out[i + 1] = " "
                i += 1
                in_block = True
            elif c == '"':
                in_str = True
        i += 1
    return "".join(out)


def mask_strings(text: str) -> str:
    """把字符串字面量内容替换为空格，保留长度与换行。"""
    out = list(text)
    i, n = 0, len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\" and i + 1 < n:
                out[i] = out[i + 1] = " "
                i += 1
            elif c == '"':
                in_str = False
            elif c != "\n":
                out[i] = " "
        elif c == '"':
            in_str = True
        i += 1
    return "".join(out)


def blank(text: str) -> str:
    """用空格替换一段文本，保留换行以维持行号。"""
    return "".join("\n" if ch == "\n" else " " for ch in text)


def skip_balanced(text: str, pos: int) -> int:
    """pos 指向 '('，返回匹配 ')' 的下标；不匹配时返回文本末尾。"""
    depth = 0
    i = pos
    n = len(text)
    while i < n:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n - 1


def remove_param_blocks(text: str) -> str:
    """移除 #(...) 参数块（支持嵌套括号），其余内容保持原位置。"""
    out = []
    i, n = 0, len(text)
    while i < n:
        if text[i] == "#":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] == "(":
                k = skip_balanced(text, j)
                out.append(blank(text[i:k + 1]))
                i = k + 1
                continue
        out.append(text[i])
        i += 1
    return "".join(out)


def find_instances(code: str):
    """返回 [(pos, module_type, instance_name), ...]。

    识别语句首的 `type [#(...)] instance (`，跳过关键字、函数调用、声明。
    """
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
        if not m2:
            continue
        w2 = m2.group(1)
        if w2 in KEYWORDS:
            continue
        end = pos + m2.end()
        while end < n and code[end] in " \t\r\n":
            end += 1
        if end < n and code[end] == "(":
            results.append((m.start(1), w1, w2))
    return results


def expr_is_connection_safe(expr: str) -> bool:
    """端口连接表达式是否只含信号名、参数名或字面常量。"""
    e = expr.strip()
    if not e:
        return True
    e = re.sub(r"\[[^\]]*\]", "", e).strip()
    if re.fullmatch(r"[A-Za-z_]\w*", e):
        return True
    if re.fullmatch(r"[A-Za-z_]\w*::[A-Za-z_]\w*", e):
        return True
    if re.fullmatch(r"-?\s*\d+", e):
        return True
    if re.fullmatch(r"-?\s*\d*'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+", e):
        return True
    if re.fullmatch(r"'[01xXzZ]", e):
        return True
    return False


class QualityGate:
    def __init__(self, rtl_path, tb_path=None, strict=False, dff_cell=None):
        self.rtl_path = Path(rtl_path)
        self.tb_path = Path(tb_path) if tb_path else None
        self.strict = strict
        self.dff_cell = dff_cell
        self.errors = []
        self.warnings = []
        self.passed = []
        self._dff_cache = None

    # ---------- 输出 ----------
    def _fail(self, msg):
        self.errors.append(msg)

    def _warn(self, msg):
        self.warnings.append(msg)

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
        code_comments = strip_comments(raw)
        code = mask_strings(code_comments)

        self._check_file_and_module(code)
        self._check_header(raw, code)
        self._check_sva(raw, code_comments, code)
        self._check_rtl_constructs(code)
        self._check_cases(code)
        self._check_instances(code)
        self._check_port_connections(code)
        self._check_always_style(code)
        self._check_ports(code)
        self._check_markers(raw)
        self._check_tb_makefile()

        print("\n" + "=" * 64)
        print("RESULTS")
        print("=" * 64)
        print(f"  Passed  : {len(self.passed)}")
        print(f"  Warnings: {len(self.warnings)}")
        print(f"  Errors  : {len(self.errors)}")

        if self.warnings:
            print("\nWarnings:")
            for w in self.warnings:
                print(f"  [WARN] {w}")

        if self.errors:
            print("\nErrors:")
            for e in self.errors:
                print(f"  [FAIL] {e}")

        if self.passed:
            print("\nPassed checks:")
            for p in self.passed:
                print(f"  [PASS] {p}")

        failed = bool(self.errors) or (self.strict and bool(self.warnings))
        print("=" * 64)
        if failed:
            suffix = " (STRICT)" if self.strict and not self.errors else ""
            print(f"RESULT: FAILED{suffix}")
            return False
        print("RESULT: PASSED")
        return True

    # ---------- 具体检查 ----------
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
            return
        if mods[0] != stem:
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

    def _has_parameters(self, code):
        m = re.search(r"(?m)^[ \t]*module\s+\w+", code)
        if not m:
            return False
        pos = m.end()
        n = len(code)
        while pos < n and code[pos] in " \t\r\n":
            pos += 1
        if pos >= n or code[pos] != "#":
            return False
        j = pos + 1
        while j < n and code[j] in " \t\r\n":
            j += 1
        if j >= n or code[j] != "(":
            return False
        k = skip_balanced(code, j)
        return bool(re.search(r"\bparameter\b", code[j + 1:k]))

    def _check_sva(self, raw, code_comments, code):
        stem = self.rtl_path.stem
        sva_path = self.rtl_path.with_suffix(".sva")
        has_params = self._has_parameters(code)

        assert_found = bool(re.search(r"\b(assert|assume|cover|restrict)\b", code))
        if assert_found:
            self._fail("模块内不允许写断言，assert/assume/cover 必须放在 .sva")

        includes = list(re.finditer(r'`include\s+"([^"]+)"', code_comments))
        guarded = []
        for m in includes:
            before = code_comments[max(0, m.start() - 400):m.start()]
            after = code_comments[m.end():m.end() + 400]
            if re.search(r"`ifdef\s+SVA_ON\b", before) and re.search(r"`endif\b", after):
                guarded.append(m)

        if includes and not guarded:
            self._fail("`include 必须由 `ifdef SVA_ON 开关控制")

        if not guarded:
            if sva_path.exists():
                self._fail(f"存在 {sva_path.name}，但模块没有用 SVA_ON include 引入")
            else:
                self._pass("无断言文件（按需创建，简单模块可省略）")
            return

        if len(guarded) > 1:
            self._warn("存在多处 SVA_ON include，建议只保留一处")

        inc = guarded[0].group(1)
        if inc != sva_path.name:
            self._fail(f"include 文件名 {inc} 应为 {sva_path.name}")
        target = self.rtl_path.parent / inc
        if not target.exists():
            self._fail(f"include 目标不存在：{inc}")
            return
        self._pass("SVA include 由 SVA_ON 控制")

        endmod = code_comments.rfind("endmodule")
        if endmod > guarded[0].end():
            tail = code_comments[guarded[0].end():endmod]
            if re.sub(r"`endif\b", "", tail).strip():
                self._fail("SVA include 必须放在 endmodule 前的最后一段")
        else:
            self._fail("SVA include 未出现在 endmodule 之前")

        sva_raw = target.read_text(encoding="utf-8", errors="replace")
        sva_code = mask_strings(strip_comments(sva_raw))
        if re.search(r"(?m)^[ \t]*(module|endmodule)\b", sva_code):
            self._fail(f"{inc} 不应包含 module/endmodule，它会被 include 进模块作用域")
        if not re.search(r"\bassert\b|\$(fatal|error|warning)\b", sva_code):
            self._warn(f"{inc} 中没有断言或检查")
        if has_params and not re.search(r"\$(fatal|error)\b", sva_code):
            self._fail(f"参数化模块的 {inc} 缺少参数校验（$fatal/$error）")
        else:
            self._pass("断言文件内容检查通过")

    def _dff_cells(self):
        if self.dff_cell:
            return [self.dff_cell]
        if self._dff_cache is not None:
            return self._dff_cache
        cells = set()
        for pat in ("*.sv", "*.v"):
            for f in self.rtl_path.parent.glob(pat):
                if f.resolve() == self.rtl_path.resolve():
                    continue
                try:
                    text = f.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                mod = re.search(r"(?m)^[ \t]*module\s+(dff\w*)\b",
                                mask_strings(strip_comments(text)))
                if mod:
                    cells.add(mod.group(1))
        self._dff_cache = sorted(cells)
        return self._dff_cache

    def _check_rtl_constructs(self, code):
        checks = [
            (r"\binitial\b", "模块内禁止 initial（仿真检查/断言放 .sva）"),
            (r"\balways\s*@", "禁止 always @(...)，改用 always_ff/always_comb"),
            (r"\balways_latch\b", "禁止 always_latch（避免 latch）"),
            (r"\bforce\b|\brelease\b", "禁止 force/release"),
            (r"\bfork\b|\bjoin(_any|_none)?\b", "禁止 fork-join"),
            (r"\$random\b", "RTL 中禁止 $random"),
            (r"(?<![\w'])#\s*\d", "禁止 #delay"),
        ]
        for pat, msg in checks:
            hits = list(re.finditer(pat, code))
            for m in hits[:3]:
                self._fail(f"L{self._line(code, m.start())}: {msg}")
            if len(hits) > 3:
                self._fail(f"另有 {len(hits) - 3} 处：{msg}")
            if not hits:
                self._pass(f"未发现：{msg.split('（')[0]}")

        ffs = list(re.finditer(r"\balways_ff\b", code))
        cells = self._dff_cells()
        if ffs and cells and not self.rtl_path.stem.startswith("dff"):
            self._fail(f"项目存在统一 DFF 单元（{', '.join(cells)}），业务模块禁止裸 always_ff")
        elif ffs:
            self._pass("使用 always_ff（未发现统一 DFF 单元，允许）")
        elif re.search(r"\balways_comb\b", code):
            self._pass("组合逻辑使用 always_comb")
        elif not re.search(r"\balways\b", code):
            self._pass("纯组合/例化模块，无 always 块")

    def _check_cases(self, code):
        stack = []
        count = 0
        for m in re.finditer(r"\b(case|casez|casex|endcase)\b", code):
            tok = m.group(1)
            if tok in ("case", "casez", "casex"):
                stack.append((m.start(), tok))
            elif stack:
                start, kind = stack.pop()
                body = code[start:m.start()]
                count += 1
                if kind == "casex":
                    self._fail(f"L{self._line(code, start)}: 禁止 casex")
                elif kind == "casez":
                    self._warn(f"L{self._line(code, start)}: 慎用 casez")
                if not re.search(r"\bdefault\b", body):
                    self._fail(f"L{self._line(code, start)}: case 缺少 default 分支")
        if count and not self.errors:
            self._pass("case 语句检查通过")
        elif not count:
            self._pass("无 case 语句")

    def _check_instances(self, code):
        bad = []
        for pos, _type, inst in find_instances(code):
            if not re.fullmatch(r"[A-Z][A-Z0-9_]*", inst):
                bad.append((pos, inst))
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
            closep = skip_balanced(code_np, openp)
            expr = code_np[openp + 1:closep]
            if not expr_is_connection_safe(expr):
                bad.append((m.start(), m.group(1), " ".join(expr.split())))
        for pos, port, expr in bad[:5]:
            self._fail(f"L{self._line(code, pos)}: .{port}({expr}) 含逻辑运算，应外部预处理为信号")
        if len(bad) > 5:
            self._fail(f"另有 {len(bad) - 5} 处端口连接含逻辑运算")
        if not bad:
            self._pass("例化端口连接规范（无逻辑运算式）")

    def _check_always_style(self, code):
        ffs = list(re.finditer(r"always_ff\s*@\s*\(([^)]*)\)", code))
        if not ffs:
            return
        for m in ffs:
            ev = m.group(1)
            if "negedge" in ev:
                self._pass("使用异步复位")
            elif re.search(r"\brst", ev):
                self._warn(f"L{self._line(code, m.start())}: 使用同步复位，确认是否符合需求")
            else:
                self._warn(f"L{self._line(code, m.start())}: 时序逻辑未带复位")

    def _module_port_text(self, code):
        m = re.search(r"(?m)^[ \t]*module\s+\w+", code)
        if not m:
            return ""
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
        if pos < n and code[pos] == "(":
            k = skip_balanced(code, pos)
            return code[pos + 1:k]
        return ""

    def _check_ports(self, code):
        port_text = self._module_port_text(code)
        if port_text.strip() and not re.search(r"\b(input|output|inout|ref)\b", port_text):
            self._warn("使用非 ANSI 端口声明风格")
        else:
            self._pass("端口声明为 ANSI 风格")

        bad = []
        for m in re.finditer(r"(?m)^[ \t]*(?:input|output|inout)\b([^\n;]*)", code):
            names = re.findall(r"([A-Za-z_]\w*)\s*(?=,|\)|$)", m.group(1))
            if names and re.search(r"_(i|o|io)$", names[-1]):
                bad.append((m.start(), names[-1]))
        for pos, name in bad[:5]:
            self._fail(f"L{self._line(code, pos)}: 端口 {name} 不应带方向后缀（_i/_o/_io）")
        if len(bad) > 5:
            self._fail(f"另有 {len(bad) - 5} 处端口带方向后缀")
        if not bad:
            self._pass("端口命名无方向后缀")

    def _check_markers(self, code_comments):
        hits = []
        for pat, name in ((r"@vlog-align", "@vlog-align"),
                          (r"@inst\b", "@inst"),
                          (r"//\s*keep\b", "keep")):
            if re.search(pat, code_comments):
                hits.append(name)
        if hits:
            self._fail(f"代码中不允许对齐标记（{', '.join(hits)}），使用 :RtlAlign 全量对齐")
        else:
            self._pass("无对齐标记")

    def _check_tb_makefile(self):
        if self.tb_path:
            if self.tb_path.exists():
                self._pass("Testbench 存在")
            else:
                self._fail(f"Testbench 文件不存在：{self.tb_path}")
        else:
            stem = self.rtl_path.stem
            dirs = [self.rtl_path.parent,
                    self.rtl_path.parent / "tb",
                    self.rtl_path.parent.parent / "tb",
                    self.rtl_path.parent.parent]
            found = None
            for d in dirs:
                for suffix in (".sv", ".v"):
                    cand = d / f"{stem}_tb{suffix}"
                    if cand.exists():
                        found = cand
                        break
                if found:
                    break
            if found:
                self._pass(f"Testbench 存在（{found.name}）")
            else:
                self._warn(f"未找到 Testbench（期望：{stem}_tb.sv）")

        make_dirs = [self.rtl_path.parent, self.rtl_path.parent.parent]
        if any((d / name).exists() for d in make_dirs for name in ("Makefile", "makefile")):
            self._pass("Makefile 存在")
        else:
            self._warn("未找到 Makefile（建议添加编译仿真脚本）")


def main():
    parser = argparse.ArgumentParser(description="RTL 质量门控检查")
    parser.add_argument("rtl", help="RTL 源文件（.sv）")
    parser.add_argument("tb", nargs="?", help="Testbench 文件（可选）")
    parser.add_argument("--strict", action="store_true", help="warning 也视为失败")
    parser.add_argument("--dff-cell", default=None, help="统一 DFF 单元模块名")
    args = parser.parse_args()

    gate = QualityGate(args.rtl, args.tb, args.strict, args.dff_cell)
    sys.exit(0 if gate.check() else 1)


if __name__ == "__main__":
    main()
