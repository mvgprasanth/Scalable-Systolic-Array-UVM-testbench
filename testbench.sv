// ============================================================================
// SA Testbench Top
// ============================================================================
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "matrix_pkg.sv"
`include "sa_if.sv"
`include "sa_pkg.sv"

module sa_tb_top;

  import uvm_pkg::*;
  import matrix_pkg::*;
  import sa_pkg::*;

  parameter int DIN_WIDTH = 8;
  parameter int N         = 4;

  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5ns clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(5) @(negedge clk);
    rst_n = 1;
    `uvm_info("TOP","Reset deasserted",UVM_NONE)
  end

  sa_if #(.DIN_WIDTH(DIN_WIDTH), .N(N)) sa_vif (.clk(clk), .rst_n(rst_n));

  sa_ref_model_sv #(
    .DIN_WIDTH (DIN_WIDTH),
    .N         (N)
) dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .c_din           (sa_vif.c_din),
    .a_din           (sa_vif.a_din),
    .b_din           (sa_vif.b_din),
    .in_valid        (sa_vif.in_valid),
    .b_preload_valid (sa_vif.b_preload_valid),
    .b_seed_valid    (sa_vif.b_seed_valid),
    .c_dout          (sa_vif.c_dout),
    .out_valid       (sa_vif.out_valid)
);

  initial begin
    uvm_config_db#(virtual sa_if#(DIN_WIDTH,N))::set(null, "*", "vif", sa_vif);
    run_test("sa_directed_test_8_4");
  end
  initial begin
        $dumpfile("sa_sim.vcd");
        $dumpvars(0, sa_tb_top);
    end

endmodule