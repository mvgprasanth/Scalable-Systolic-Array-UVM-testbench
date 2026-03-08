// ============================================================================
// Systolic Array Level Interface
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
    // These match the systolic_array module port list exactly
    logic signed [2*DIN_WIDTH-1:0] c_din   [0:N-1];
    logic signed [DIN_WIDTH-1:0]   a_din   [0:N-1];
    logic signed [DIN_WIDTH-1:0]   b_din   [0:N-1];
    logic                          in_valid;
    logic signed [2*DIN_WIDTH-1:0] c_dout  [0:N-1];
    logic                          out_valid;
  	logic b_preload_valid;
	logic b_seed_valid;

    // Clocking block for driver (synchronous drive on negedge, sample on posedge)
  clocking driver_cb @(posedge clk);
        default input #1step output #0;
        output c_din;
        output a_din;
        output b_din;
        output in_valid;
    	output b_preload_valid;
		output b_seed_valid;
    endclocking

    // Clocking block for monitor (sample outputs)
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input  c_dout;
        input  out_valid;
        input  in_valid;
        input  a_din;
        input  b_din;
    endclocking

    // Modports
    modport drv_mp  (clocking driver_cb,  input clk, input rst_n);
    modport mon_mp  (clocking monitor_cb, input clk, input rst_n);
    modport dut_mp  (
        output c_dout, output out_valid,
        input  c_din, input a_din, input b_din, input in_valid
    );
      
      // ------------------------------------------------------------
  // Simple protocol assertions
  // ------------------------------------------------------------
      property p_in_valid_one_pulse;
        @(posedge clk) disable iff (!rst_n)
          in_valid |=> !in_valid;
      endproperty

      property p_out_valid_one_pulse;
        @(posedge clk) disable iff (!rst_n)
          out_valid |=> !out_valid;
      endproperty

      property p_preload_not_with_in_valid;
        @(posedge clk) disable iff (!rst_n)
          b_preload_valid |-> !in_valid;
      endproperty

      property p_seed_only_with_in_valid;
        @(posedge clk) disable iff (!rst_n)
          b_seed_valid |-> in_valid;
      endproperty

      property p_seed_preload_mutually_exclusive;
        @(posedge clk) disable iff (!rst_n)
          !(b_seed_valid && b_preload_valid);
      endproperty

      a_in_valid_one_pulse: assert property (p_in_valid_one_pulse)
        else $error("ASSERTION FAILED: in_valid must be a 1-cycle pulse");

      a_out_valid_one_pulse: assert property (p_out_valid_one_pulse)
        else $error("ASSERTION FAILED: out_valid must be a 1-cycle pulse");

      a_preload_not_with_in_valid: assert property (p_preload_not_with_in_valid)
        else $error("ASSERTION FAILED: b_preload_valid cannot be high with in_valid");

      a_seed_only_with_in_valid: assert property (p_seed_only_with_in_valid)
        else $error("ASSERTION FAILED: b_seed_valid must only be high on swap/in_valid cycle");

      a_seed_preload_mutually_exclusive: assert property (p_seed_preload_mutually_exclusive)
        else $error("ASSERTION FAILED: b_seed_valid and b_preload_valid cannot both be high");
endinterface

`endif
