// ============================================================================
// Systolic Array Interface
// ============================================================================
`ifndef SA_IF_SV
`define SA_IF_SV

interface sa_if #(
    parameter int DIN_WIDTH = 8,
    parameter int N         = 4
)(
    input logic clk,
    input logic rst_n
);

    logic signed [2*DIN_WIDTH-1:0] c_din   [0:N-1];
    logic signed [DIN_WIDTH-1:0]   a_din   [0:N-1];
    logic signed [DIN_WIDTH-1:0]   b_din   [0:N-1];
    logic                          in_valid;
    logic signed [2*DIN_WIDTH-1:0] c_dout  [0:N-1];
    logic                          out_valid;
  	logic b_preload_valid;
	logic b_seed_valid;

  clocking driver_cb @(negedge clk);
        default input #1step output #0;
        output c_din;
        output a_din;
        output b_din;
        output in_valid;
    	output b_preload_valid;
		output b_seed_valid;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;
        input  c_dout;
        input  out_valid;
        input  in_valid;
        input  a_din;
        input  b_din;
    endclocking

    modport drv_mp  (clocking driver_cb,  input clk, input rst_n);
    modport mon_mp  (clocking monitor_cb, input clk, input rst_n);
    modport dut_mp  (
        output c_dout, output out_valid,
        input  c_din, input a_din, input b_din, input in_valid
    );
endinterface

`endif
