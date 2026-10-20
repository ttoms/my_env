#!/usr/bin/env python3
"""quality_gate.py 回归测试（不依赖 iverilog / verilator）。"""

import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

GATE = Path(__file__).resolve().parents[1] / "quality_gate.py"

HEADER = """\
//==============================================================================
// Module : {name}
// Description : test module
// Features : none
// Parameters : {params}
// Limitations : none
//==============================================================================
"""


def write(path: Path, text: str):
    path.write_text(textwrap.dedent(text).lstrip(), encoding="utf-8")


def run_gate(rtl: Path, strict: bool = False):
    cmd = [sys.executable, str(GATE), str(rtl)]
    if strict:
        cmd.append("--strict")
    return subprocess.run(cmd, capture_output=True, text=True)


class GateTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def make_good(self, name="simple_sync", with_sva=True, include_sva=True):
        header = HEADER.format(name=name, params="W - width")
        include_block = f"""\
            `ifdef SVA_ON
            `include "{name}.sva"
            `endif
            """ if include_sva else ""
        write(self.dir / f"{name}.sv", header + f"""\
            module {name} #(
                parameter   W = 8
            ) (
                input   logic         clk,
                input   logic         rst_n,
                input   logic [W-1:0] din,
                output  logic [W-1:0] dout
            );
            assign dout = din;

            {include_block}
            endmodule
            """)
        if with_sva:
            write(self.dir / f"{name}.sva", """\
                initial begin
                    if (!(W > 0)) begin
                        $fatal(1, "[%m] W must be > 0");
                    end
                end
                """)
        write(self.dir / f"{name}_tb.sv", f"module {name}_tb;\nendmodule\n")
        write(self.dir / "Makefile", "all:\n\techo build\n")

    def test_compliant_module_passes_strict(self):
        self.make_good()
        r = run_gate(self.dir / "simple_sync.sv", strict=True)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("RESULT: PASSED", r.stdout)
        self.assertNotIn("[WARN]", r.stdout)

    def test_assertion_in_module_fails(self):
        self.make_good()
        sv = self.dir / "simple_sync.sv"
        text = sv.read_text(encoding="utf-8").replace(
            "endmodule",
            "assert property (@(posedge clk) din == '0);\n\nendmodule")
        write(sv, text)
        r = run_gate(sv)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("模块内不允许写断言", r.stdout)

    def test_hard_violations_fail(self):
        name = "bad_rtl"
        header = HEADER.format(name=name, params="none")
        write(self.dir / f"{name}.sv", header + f"""\
            module {name} (
                input   logic       clk,
                input   logic       rst_n,
                input   logic [3:0] din,
                output  logic [3:0] dout
            );
            initial begin
                dout = 4'h0;
            end

            always @(*) begin
                casex (din)
                    4'b1xxx: dout = 4'h1;
                endcase
            end

            assign #2 dout = din;

            endmodule
            """)
        r = run_gate(self.dir / f"{name}.sv")
        self.assertNotEqual(r.returncode, 0)
        for msg in ("initial", "always @(", "casex", "default", "#delay"):
            self.assertIn(msg, r.stdout)

    def test_missing_sva_include_target_fails(self):
        self.make_good(with_sva=False)
        r = run_gate(self.dir / "simple_sync.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("include 目标不存在", r.stdout)

    def test_simple_module_without_sva_passes_strict(self):
        self.make_good(with_sva=False, include_sva=False)
        r = run_gate(self.dir / "simple_sync.sv", strict=True)
        self.assertEqual(r.returncode, 0, r.stdout)
        self.assertIn("无断言文件", r.stdout)

    def test_orphan_sva_without_include_fails(self):
        self.make_good(with_sva=True, include_sva=False)
        r = run_gate(self.dir / "simple_sync.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("没有用 SVA_ON include 引入", r.stdout)

    def test_nested_param_allowed_but_port_expr_fails(self):
        name = "inst_test"
        header = HEADER.format(name=name, params="none")
        write(self.dir / f"{name}.sv", header + f"""\
            module {name} (
                input   logic       clk,
                input   logic       rst_n,
                input   logic [7:0] din,
                output  logic [7:0] dout
            );
            dffr #(
                .W        ($clog2(8)   ),
                .RESET_VAL('0          )
            ) U_X (
                .clk    (clk    ),
                .rst_n  (rst_n  ),
                .en     (din[0] ^ din[1]),
                .d      (din    ),
                .q      (dout   )
            );
            endmodule
            """)
        r = run_gate(self.dir / f"{name}.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(".en(din[0] ^ din[1])", r.stdout)
        self.assertNotIn("$clog2", r.stdout.split("Errors:")[-1])

    def test_module_name_mismatch_and_marker_fail(self):
        name = "bar_mod"
        header = HEADER.format(name=name, params="none")
        write(self.dir / "bar_mod.sv", header + """\
            module another_name (
                input   logic clk,
                input   logic rst_n
            );
            // @inst
            endmodule
            """)
        r = run_gate(self.dir / "bar_mod.sv")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("模块名 another_name 与文件名 bar_mod 不一致", r.stdout)
        self.assertIn("不允许对齐标记", r.stdout)


if __name__ == "__main__":
    unittest.main()
