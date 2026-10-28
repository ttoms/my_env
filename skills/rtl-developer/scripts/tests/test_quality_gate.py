#!/usr/bin/env python3
"""quality_gate.py 回归测试（不依赖 iverilog / verilator）。"""

import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

GATE = Path(__file__).resolve().parents[1] / "quality_gate.py"
ALIGN = Path(__file__).resolve().parents[1] / "align.sh"
TEMPLATES = Path(__file__).resolve().parents[2] / "templates"
PLUGIN = Path(__file__).resolve().parents[4] / "vim" / "rtl_align"

HEADER = """\
`default_nettype none
//==============================================================================
// Module : {name}
// Description : test module
// Features : none
// Parameters : {params}
// Limitations : none
//==============================================================================
"""

TAIL = """\
endmodule

`default_nettype wire
"""


def write(path: Path, text: str):
    path.write_text(textwrap.dedent(text).lstrip(), encoding="utf-8")


def run_gate(rtl: Path, strict: bool = False, lint: bool = False, env=None):
    cmd = [sys.executable, str(GATE), str(rtl)]
    if strict:
        cmd.append("--strict")
    if lint:
        cmd.append("--lint")
    return subprocess.run(cmd, capture_output=True, text=True, env=env)


class GateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def make_module(self, name="simple_sync", body="assign dout = din;",
                    with_sva=False, include_sva=False, ports=None,
                    params="parameter   W = 8"):
        ports = ports or """
            input   logic         clk,
            input   logic         rst_n,
            input   logic [W-1:0] din,
            output  logic [W-1:0] dout
            """
        include_block = f"""
            `ifdef SVA_ON
            `include "{name}.sva"
            `endif
            """ if include_sva else ""
        write(self.dir / f"{name}.sv", HEADER.format(name=name, params="W - width") + f"""
            module {name} #(
                {params}
            ) (
                {ports}
            );
            {body}
            {include_block}
            """ + TAIL)
        if with_sva:
            write(self.dir / f"{name}.sva", """\
                initial begin
                    if (!(W > 0)) begin
                        $fatal(1, "[%m] W must be > 0");
                    end
                end
                """)

    def test_compliant_module_passes_without_tb_or_makefile(self):
        self.make_module()
        r = run_gate(self.dir / "simple_sync.sv")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("RESULT: PASSED", r.stdout)
        self.assertNotIn("[WARN]", r.stdout)

    def test_assertion_in_module_fails(self):
        self.make_module(body="assert property (@(posedge clk) din == '0);")
        r = run_gate(self.dir / "simple_sync.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("模块内不允许写断言", r.stdout)

    def test_hard_violations_fail(self):
        self.make_module(name="bad_rtl", body="""\
            initial begin
                dout = 4'h0;
            end

            always @(*) begin
                casex (din)
                    4'b1xxx: dout = 4'h1;
                endcase
            end

            assign #2 dout = din;
            """)
        r = run_gate(self.dir / "bad_rtl.sv")
        self.assertNotEqual(r.returncode, 0)
        for msg in ("initial", "always @(", "casex", "default", "#delay"):
            self.assertIn(msg, r.stdout)

    def test_software_types_fail(self):
        for name, body in (("string_sig", "string note;"),
                           ("real_sig", "real ratio;")):
            with self.subTest(case=name):
                self.make_module(name=name, body=body)
                r = run_gate(self.dir / f"{name}.sv")
                self.assertNotEqual(r.returncode, 0)
                self.assertIn("软件类型", r.stdout)

    def test_dynamic_array_and_while_fail(self):
        self.make_module(name="dyn_mod", body="logic [7:0] q[$];")
        r = run_gate(self.dir / "dyn_mod.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("动态数组/队列", r.stdout)

        self.make_module(
            name="while_mod",
            body="always_comb begin while (1'b1) begin dout = din; end end")
        r = run_gate(self.dir / "while_mod.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("禁止 while", r.stdout)

    def test_latch_exemption_line(self):
        body = """\
            logic en_l;
            always_latch begin  // gate: allow-latch
                if (!clk) begin
                    en_l = din[0];
                end
            end
            assign dout = {W{en_l}};
            """
        self.make_module(name="latch_mod", body=body)
        sv = self.dir / "latch_mod.sv"
        r = run_gate(sv)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("已按行豁免", r.stdout)

        sv.write_text(sv.read_text(encoding="utf-8").replace(
            "  // gate: allow-latch", ""), encoding="utf-8")
        r = run_gate(sv)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("禁止 always_latch", r.stdout)

    def test_nonconst_div_is_warning_only(self):
        self.make_module(name="div_mod", body="assign dout = din % din;")
        r = run_gate(self.dir / "div_mod.sv")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("[WARN]", r.stdout)
        self.assertIn("除法/取模", r.stdout)
        r = run_gate(self.dir / "div_mod.sv", strict=True)
        self.assertNotEqual(r.returncode, 0)

    def test_simple_module_without_sva_passes(self):
        self.make_module(with_sva=False, include_sva=False)
        r = run_gate(self.dir / "simple_sync.sv")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("无断言文件", r.stdout)

    def test_orphan_sva_is_warning_only(self):
        self.make_module(with_sva=True, include_sva=False)
        r = run_gate(self.dir / "simple_sync.sv")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("没有 include 它", r.stdout)
        r = run_gate(self.dir / "simple_sync.sv", strict=True)
        self.assertNotEqual(r.returncode, 0)

    def test_missing_sva_include_target_fails(self):
        self.make_module(name="no_sva", include_sva=True)
        r = run_gate(self.dir / "no_sva.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("找不到文件", r.stdout)

    def test_split_sva_layout_passes(self):
        name = "split_mod"
        (self.dir / "rtl" / "basic").mkdir(parents=True)
        (self.dir / "sva" / "basic").mkdir(parents=True)
        write(self.dir / "rtl" / "basic" / f"{name}.sv",
              HEADER.format(name=name, params="none") + f"""\
                  module {name} (
                      input  logic a,
                      output logic y
                  );
                  assign y = a;
                  `ifdef SVA_ON
                  `include "{name}.sva"
                  `endif
                  endmodule
                  `default_nettype wire
                  """)
        write(self.dir / "sva" / "basic" / f"{name}.sva",
              'initial begin if (1\'b0) $fatal(1, "x"); end\n')
        r = run_gate(self.dir / "rtl" / "basic" / f"{name}.sv")
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("SVA include 由 SVA_ON 控制", r.stdout)

    def test_missing_default_nettype_fails(self):
        self.make_module()
        sv = self.dir / "simple_sync.sv"
        write(sv, sv.read_text(encoding="utf-8").replace(
            "`default_nettype none", "// no nettype").replace(
            "`default_nettype wire", "// tail"))
        r = run_gate(sv)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("default_nettype none", r.stdout)

    def test_leading_comment_before_default_nettype_passes(self):
        self.make_module()
        sv = self.dir / "simple_sync.sv"
        sv.write_text("// Copyright (c) 2026\n" + sv.read_text(encoding="utf-8"),
                      encoding="utf-8")
        r = run_gate(sv)
        self.assertEqual(r.returncode, 0, r.stdout)

    def test_lint_findings_are_info_only(self):
        self.make_module()
        bindir = self.dir / "bin"
        bindir.mkdir()
        fake = bindir / "verilator"
        fake.write_text(
            "#!/bin/sh\n"
            "echo '%Warning-WIDTH: simple_sync.sv:10:5: width mismatch'\n"
            "exit 0\n", encoding="utf-8")
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir))
        r = run_gate(self.dir / "simple_sync.sv", lint=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("[INFO] LINT Warning-WIDTH", r.stdout)

    def test_lint_error_without_code_is_reported(self):
        self.make_module()
        bindir = self.dir / "bin"
        bindir.mkdir()
        fake = bindir / "verilator"
        fake.write_text(
            "#!/bin/sh\n"
            "echo '%Error: Cannot find file: missing.sv'\n"
            "exit 1\n", encoding="utf-8")
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir))
        r = run_gate(self.dir / "simple_sync.sv", lint=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("[INFO] LINT Error: Cannot find file", r.stdout)

    def test_lint_missing_tool_is_skipped(self):
        self.make_module()
        empty_bin = self.dir / "empty_bin"
        empty_bin.mkdir()
        env = dict(os.environ, PATH=str(empty_bin))
        r = run_gate(self.dir / "simple_sync.sv", lint=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("lint 跳过", r.stdout)

    def test_lint_clean_passes(self):
        self.make_module()
        bindir = self.dir / "bin"
        bindir.mkdir()
        fake = bindir / "verilator"
        fake.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(bindir))
        r = run_gate(self.dir / "simple_sync.sv", lint=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("verilator lint 通过", r.stdout)

    def test_nested_param_allowed_but_port_expr_fails(self):
        self.make_module(name="inst_test", body="""\
            dffr #(
                .W        ($clog2(8)   ),
                .RESET_VAL('0          )
            ) U_X (
                .clk    (clk             ),
                .rst_n  (rst_n           ),
                .en     (din[0] ^ din[1] ),
                .d      (din             ),
                .q      (dout            )
            );
            """)
        r = run_gate(self.dir / "inst_test.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(".en(din[0] ^ din[1])", r.stdout)
        self.assertNotIn("$clog2", r.stdout.split("Errors:")[-1])

    def test_module_name_mismatch_and_marker_fail(self):
        write(self.dir / "bar_mod.sv", HEADER.format(name="bar_mod", params="none") + """\
            module another_name (
                input   logic clk,
                input   logic rst_n
            );
            // @inst
            """ + TAIL)
        r = run_gate(self.dir / "bar_mod.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("模块名 another_name 与文件名 bar_mod 不一致", r.stdout)
        self.assertIn("不允许对齐标记", r.stdout)

    @unittest.skipUnless(shutil.which("vim") and
                         (PLUGIN / "plugin" / "rtl_align.vim").is_file(),
                         "vim / rtl_align 插件不可用")
    def test_align_script_restores_template(self):
        src = TEMPLATES / "fifo_sync.sv"
        dst = self.dir / "fifo_sync.sv"
        source_text = src.read_text(encoding="utf-8")
        scrambled = source_text.replace("input   logic", "input logic", 1)
        self.assertNotEqual(scrambled, source_text)
        dst.write_text(scrambled, encoding="utf-8")

        env = dict(os.environ, HOME=str(self.dir / "home"))
        env.pop("RTL_ALIGN_RTP", None)
        r = subprocess.run(["bash", str(ALIGN), str(dst)],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        self.assertEqual(dst.read_text(encoding="utf-8"), source_text)

    def test_templates_pass_light_gate(self):
        for sv in sorted(TEMPLATES.glob("*.sv")):
            if sv.name.endswith("_tb.sv"):
                continue
            with self.subTest(template=sv.name):
                r = run_gate(sv)
                self.assertEqual(r.returncode, 0, r.stdout)


if __name__ == "__main__":
    unittest.main()
