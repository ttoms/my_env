#!/usr/bin/env python3
"""
RTL 模块质量门控检查脚本
检查项：
  1. 文件命名规范
  2. 模块头注释完整性
  3. 端口声明规范
  4. 参数合法性检查存在
  5. SVA 断言存在
  6. 代码规范基本检查
  7. Testbench 存在性
  8. Makefile 存在性
用法：
  python3 quality_gate.py <rtl_file.sv> [tb_file.sv]
"""

import re
import sys
import os
from pathlib import Path

class QualityGate:
    def __init__(self, rtl_path, tb_path=None):
        self.rtl_path = Path(rtl_path)
        self.tb_path = Path(tb_path) if tb_path else None
        self.errors = []
        self.warnings = []
        self.passed = []

    def check(self):
        print("=" * 60)
        print(f"RTL Quality Gate: {self.rtl_path.name}")
        print("=" * 60)

        if not self.rtl_path.exists():
            print(f"ERROR: RTL file not found: {self.rtl_path}")
            return False

        content = self.rtl_path.read_text(encoding='utf-8', errors='replace')

        # 运行所有检查
        self._check_file_naming()
        self._check_module_header(content)
        self._check_parameter_validation(content)
        self._check_sva_assertions(content)
        self._check_coding_style(content)
        self._check_register_style(content)
        self._check_inst_connections(content)
        self._check_no_initial(content)
        self._check_port_conventions(content)
        self._check_reset_style(content)
        self._check_naming_style(content)
        self._check_tb_exists()
        self._check_makefile_exists()

        # 输出结果
        print("\n" + "=" * 60)
        print("RESULTS")
        print("=" * 60)
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

        print("=" * 60)
        if self.errors:
            print("RESULT: FAILED")
            return False
        else:
            print("RESULT: PASSED")
            return True

    def _fail(self, msg):
        self.errors.append(msg)

    def _warn(self, msg):
        self.warnings.append(msg)

    def _pass(self, msg):
        self.passed.append(msg)

    def _check_file_naming(self):
        """检查文件命名：小写蛇形，.sv 后缀"""
        name = self.rtl_path.stem
        if name != name.lower():
            self._fail(f"文件名应全小写: {name}")
        elif not re.match(r'^[a-z][a-z0-9_]*$', name):
            self._fail(f"文件名应使用小写蛇形命名: {name}")
        else:
            self._pass("文件命名规范")

        if self.rtl_path.suffix != '.sv':
            self._warn(f"文件后缀应为 .sv: {self.rtl_path.suffix}")

    def _check_module_header(self, content):
        """检查模块头注释完整性"""
        required_fields = ['Module', 'Description', 'Features', 'Parameters', 'Limitations']
        header_match = re.search(r'//=+\s*\n(.*?)\n//=+', content, re.DOTALL)

        if not header_match:
            self._fail("缺少模块头注释块（//===...=== 格式）")
            return

        header = header_match.group(1)
        missing = []
        for field in required_fields:
            if field not in header:
                missing.append(field)

        if missing:
            self._fail(f"模块头注释缺少字段: {', '.join(missing)}")
        else:
            self._pass("模块头注释完整")

    def _check_parameter_validation(self, content):
        """检查参数合法性检查（SVA initial 序列断言或 initial $fatal）"""
        # 支持两种方式：SVA initial 序列断言（推荐）或 initial $fatal（旧方式）
        has_sva_initial = bool(re.search(r'assert\s+property\s*\(\s*initial', content))
        has_initial_fatal = bool(re.search(r'initial\s+begin.*?\$fatal', content, re.DOTALL))
        if has_sva_initial or has_initial_fatal:
            self._pass("存在参数合法性检查")
        else:
            self._warn("建议添加参数合法性检查（SVA initial 序列断言，详见rtl-coding-standard §9）")

    def _check_sva_assertions(self, content):
        """检查 SVA 断言"""
        if re.search(r'assert\s+property', content):
            count = len(re.findall(r'assert\s+property', content))
            self._pass(f"存在 SVA 断言 ({count} 处)")
        else:
            self._warn("建议添加 SVA 断言（接口协议、内部不变量）")

    def _check_coding_style(self, content):
        """检查基本代码规范"""
        issues = []

        # 禁止 always @(*)
        if re.search(r'always\s*@\s*\(\s*\*\s*\)', content):
            issues.append("使用了 always @(*)，应改用 always_comb")

        # 禁止 always @(posedge) 不带 ff/comb
        # 检查是否有 always_ff
        has_always_ff = 'always_ff' in content
        has_always_comb = 'always_comb' in content
        if not has_always_ff and not has_always_comb:
            issues.append("未使用 always_ff/always_comb")

        # 检查非阻塞赋值在时序逻辑中（简单启发式）
        # 检查 case default
        case_blocks = re.findall(r'(unique\s+)?case\s*\(.*?\)\s*(.*?)endcase', content, re.DOTALL)
        for _, body in case_blocks:
            if 'default' not in body:
                issues.append("存在 case 语句缺少 default 分支")
                break

        if issues:
            for issue in issues:
                self._warn(issue)
        else:
            self._pass("代码规范基本检查通过")

    def _check_register_style(self, content):
        """寄存器实现风格：建议统一 DFF 例化，业务模块避免裸 always_ff（rtl-coding-standard §7）"""
        lines = [l for l in content.split('\n') if not l.strip().startswith('//')]
        code = '\n'.join(lines)
        if 'always_ff' in code:
            n = len(re.findall(r'\balways_ff\b', code))
            self._warn(f"{n} 处 always_ff，如有统一 DFF 单元建议例化实现（rtl-coding-standard §7）")
        else:
            self._pass("无裸 always_ff（寄存器例化或纯组合）")

    def _check_inst_connections(self, content):
        """检查例化端口连接是否只连信号，禁止直接写逻辑运算式（详见rtl-coding-standard §8）
        注意：参数块 #(...) 内的常量表达式允许，只检查端口连接。"""
        # 移除注释
        lines = content.split('\n')
        code_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped.startswith('//'):
                continue
            line_no_comment = re.sub(r'//.*$', '', line)
            code_lines.append(line_no_comment)
        code = '\n'.join(code_lines)

        # 移除参数块 #(...) 的内容，只保留端口连接
        # 匹配 #( ... ) 模式（非贪婪），替换为空
        code_no_param = re.sub(r'#\s*\(.*?\)', '', code, flags=re.DOTALL)

        issues = []
        # 匹配 .port( expr ) 形式
        pattern = re.compile(r'\.\w+\s*\(\s*([^)]*)\s*\)')
        for match in pattern.finditer(code_no_param):
            expr = match.group(1).strip()
            if not expr:
                continue
            # 移除位选/索引部分
            expr_no_index = re.sub(r'\[[^\]]*\]', '', expr)
            # 检查是否包含运算符
            if re.search(r'[\^&|~!<>+\-*/%?:]', expr_no_index):
                # 排除字面常量
                if re.match(r"^\d*'[bBdDhHoH][0-9a-fA-F_xXzZ]+$", expr):
                    continue
                if expr in ("'0", "'1", "'x", "'z"):
                    continue
                issues.append(f".port({expr}) 包含逻辑运算式，应外部预处理为信号（详见rtl-coding-standard §8）")

        if issues:
            for issue in issues[:5]:
                self._warn(issue)
            if len(issues) > 5:
                self._warn(f"... 还有 {len(issues)-5} 处类似问题")
        else:
            self._pass("例化端口连接规范（无逻辑运算式）")

    def _check_no_initial(self, content):
        """检查是否存在 initial 过程块（应用 SVA 替代，详见 rtl-coding-standard §9）"""
        lines = content.split('\n')
        code_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped.startswith('//'):
                continue
            line_no_comment = re.sub(r'//.*$', '', line)
            code_lines.append(line_no_comment)
        code = '\n'.join(code_lines)

        if re.search(r'\binitial\s+begin\b', code):
            count = len(re.findall(r'\binitial\s+begin\b', code))
            self._warn(f"存在 {count} 处 initial begin 过程块，应改用 SVA initial 序列断言（详见rtl-coding-standard §9）")
        else:
            self._pass("无 initial 过程块（符合rtl-coding-standard §9）")

    def _check_port_conventions(self, content):
        """检查端口声明规范"""
        # 检查是否有 valid-ready 接口
        has_valid = bool(re.search(r'\bvalid\b', content))
        has_ready = bool(re.search(r'\bready\b', content))

        if has_valid and has_ready:
            self._pass("包含 valid-ready 接口")

        # 检查时钟复位命名
        has_clk = bool(re.search(r'\bclk\b', content))
        has_rst = bool(re.search(r'\brst_n\b|\brst\b', content))
        if has_clk and has_rst:
            self._pass("时钟复位端口存在")
        else:
            self._warn("未检测到标准时钟复位端口（clk/rst_n）")

    def _check_reset_style(self, content):
        """检查复位风格：异步复位同步释放"""
        # 检查异步复位敏感列表
        if re.search(r'always_ff\s*@\s*\(\s*posedge\s+\w+\s+or\s+negedge\s+\w+_n\s*\)', content):
            self._pass("使用异步复位风格")
        elif re.search(r'always_ff\s*@\s*\(\s*posedge\s+\w+\s*\)', content):
            self._warn("使用同步复位，确认是否符合需求（默认异步复位）")

    def _check_naming_style(self, content):
        """检查命名风格（rtl-coding-standard §1）"""
        # 例化实例名应全大写（小写开头、后跟 ( 的标识符，排除关键字/系统函数）
        keywords = {
            'module', 'endmodule', 'function', 'endfunction', 'task', 'endtask',
            'if', 'else', 'for', 'while', 'case', 'endcase', 'always', 'always_ff',
            'always_comb', 'always_latch', 'assert', 'property', 'cover', 'generate',
            'endgenerate', 'begin', 'end', 'assign', 'initial', 'final', 'casez',
        }
        issues = set()
        for m in re.finditer(r'\b([a-z][a-z0-9_]*)\s*(?:#\s*\([^)]*\)\s*)?\(', content):
            inst = m.group(1)
            if inst in keywords or inst.startswith('$'):
                continue
            issues.add(inst)

        if issues:
            for inst in sorted(issues)[:5]:
                self._warn(f"实例名 {inst} 应为全大写（rtl-coding-standard §1.1）")
            if len(issues) > 5:
                self._warn(f"... 还有 {len(issues) - 5} 处")
        else:
            self._pass("实例名全大写")

    def _check_tb_exists(self):
        """检查 Testbench 存在"""
        if self.tb_path:
            if self.tb_path.exists():
                self._pass("Testbench 存在")
            else:
                self._fail(f"Testbench 文件不存在: {self.tb_path}")
        else:
            # 自动查找
            tb_name = self.rtl_path.stem + "_tb.sv"
            tb_candidate = self.rtl_path.parent / tb_name
            if tb_candidate.exists():
                self._pass("Testbench 存在")
            else:
                self._warn(f"未找到 Testbench（期望: {tb_name}）")

    def _check_makefile_exists(self):
        """检查 Makefile 存在"""
        makefile = self.rtl_path.parent / "Makefile"
        if makefile.exists():
            self._pass("Makefile 存在")
        else:
            self._warn("未找到 Makefile（建议添加编译仿真脚本）")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 quality_gate.py <rtl_file.sv> [tb_file.sv]")
        sys.exit(1)

    rtl_file = sys.argv[1]
    tb_file = sys.argv[2] if len(sys.argv) > 2 else None

    gate = QualityGate(rtl_file, tb_file)
    success = gate.check()
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
