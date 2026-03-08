// ============================================================================
// SA Level UVM Package
// Contains: seq_item, sequences, driver, monitor, scoreboard, agent, env, tests
// ============================================================================
`ifndef SA_PKG_SV
`define SA_PKG_SV

`include "uvm_macros.svh"

package sa_pkg;

  import uvm_pkg::*;
  import matrix_pkg::*;

  // =========================================================================
  // Sequence Item
  // =========================================================================
  class sa_seq_item #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_sequence_item;

    `uvm_object_param_utils(sa_seq_item#(DIN_WIDTH,N))

    rand int unsigned                 M;
    rand logic signed [DIN_WIDTH-1:0] A[][];
    rand logic signed [DIN_WIDTH-1:0] B[][];
    logic signed [2*DIN_WIDTH-1:0]    C_exp[][];

    // Back-to-back helper fields
    logic signed [DIN_WIDTH-1:0]      B_next[][];
    logic signed [DIN_WIDTH-1:0]      a_next00;
    bit                               has_bt;
    bit                               next_has_bt;
	logic signed [DIN_WIDTH-1:0]      b_after_next00;
    constraint c_m    { M == N; }
    constraint c_a_sz { A.size() == N; foreach (A[i]) A[i].size() == N; }
    constraint c_b_sz { B.size() == N; foreach (B[i]) B[i].size() == N; }

    constraint c_val {
      foreach (A[i,j]) A[i][j] inside {[-(1<<(DIN_WIDTH/2-1)):(1<<(DIN_WIDTH/2-1))-1]};
      foreach (B[i,j]) B[i][j] inside {[-(1<<(DIN_WIDTH/2-1)):(1<<(DIN_WIDTH/2-1))-1]};
    }

    function new(string name="sa_seq_item");
      super.new(name);
    endfunction

    function void post_randomize();
      longint A_l[][], B_l[][], C_l[][];

      A_l = new[N];
      foreach (A_l[i]) begin
        A_l[i] = new[M];
        foreach (A_l[i][j]) A_l[i][j] = A[i][j];
      end

      B_l = new[M];
      foreach (B_l[i]) begin
        B_l[i] = new[N];
        foreach (B_l[i][j]) B_l[i][j] = B[i][j];
      end

      golden_matmul(N, M, A_l, B_l, C_l);

      C_exp = new[N];
      foreach (C_exp[i]) begin
        C_exp[i] = new[N];
        foreach (C_exp[i][j]) C_exp[i][j] = C_l[i][j];
      end
    endfunction

    function string convert2string();
      string s;
      s = $sformatf("sa_seq_item N=%0d M=%0d\n", N, M);

      foreach (A[i]) begin
        s = {s, $sformatf("  A[%0d]: ", i)};
        foreach (A[i][j]) s = {s, $sformatf("%4d ", A[i][j])};
        s = {s, "\n"};
      end

      foreach (B[i]) begin
        s = {s, $sformatf("  B[%0d]: ", i)};
        foreach (B[i][j]) s = {s, $sformatf("%4d ", B[i][j])};
        s = {s, "\n"};
      end

      if (C_exp.size() > 0) foreach (C_exp[i]) begin
        s = {s, $sformatf("  C_exp[%0d]: ", i)};
        foreach (C_exp[i][j]) s = {s, $sformatf("%6d ", C_exp[i][j])};
        s = {s, "\n"};
      end

      return s;
    endfunction

    function void do_copy(uvm_object rhs);
      sa_seq_item #(DIN_WIDTH,N) rhs_c;
      if (!$cast(rhs_c, rhs)) `uvm_fatal("CAST", "do_copy cast fail")
      super.do_copy(rhs);
      M           = rhs_c.M;
      A           = rhs_c.A;
      B           = rhs_c.B;
      C_exp       = rhs_c.C_exp;
      B_next      = rhs_c.B_next;
      a_next00    = rhs_c.a_next00;
      has_bt      = rhs_c.has_bt;
      next_has_bt = rhs_c.next_has_bt;
      next_has_bt=rhs_c.next_has_bt;
      b_after_next00=rhs_c.b_after_next00;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      sa_seq_item #(DIN_WIDTH,N) rhs_c;
      if (!$cast(rhs_c, rhs)) return 0;
      return super.do_compare(rhs, comparer) && (M == rhs_c.M);
    endfunction

  endclass

  // =========================================================================
  // Sequence
  // =========================================================================
  class sa_rand_seq #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_sequence #(sa_seq_item#(DIN_WIDTH,N));

    `uvm_object_param_utils(sa_rand_seq#(DIN_WIDTH,N))

    int num_trans = 1;
    sa_seq_item #(DIN_WIDTH,N) items[$];

    function new(string name="sa_rand_seq");
      super.new(name);
    endfunction

    task body();
      sa_seq_item #(DIN_WIDTH,N) cur;

      if (items.size() > 0) begin
        foreach (items[i]) begin
          cur = items[i];
          start_item(cur);
          finish_item(cur);
        end
      end else begin
        repeat (num_trans) begin
          cur = sa_seq_item#(DIN_WIDTH,N)::type_id::create("item");
          start_item(cur);
          if (!cur.randomize())
            `uvm_fatal("RAND","Randomization failed")
          finish_item(cur);
        end
      end
    endtask
  endclass

  // =========================================================================
  // Driver
  // =========================================================================
  class sa_driver #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_driver #(sa_seq_item#(DIN_WIDTH,N));

    `uvm_component_param_utils(sa_driver#(DIN_WIDTH,N))

    virtual sa_if #(DIN_WIDTH,N) vif;
    bit d_skip_p12;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual sa_if#(DIN_WIDTH,N))::get(this,"","vif",vif))
        `uvm_fatal("CFG","No vif in sa_driver")
    endfunction

    task run_phase(uvm_phase phase);
      sa_seq_item #(DIN_WIDTH,N) item;

      drive_idle();
      @(posedge vif.clk);
      wait (vif.rst_n === 1'b1);
      @(vif.driver_cb);

      forever begin
        seq_item_port.get_next_item(item);
        `uvm_info("DRV", $sformatf("Driving N=%0d M=%0d", N, item.M), UVM_MEDIUM)
        drive_transaction(item);
        seq_item_port.item_done();
      end
    endtask

    task drive_idle();
      vif.driver_cb.in_valid        <= 1'b0;
      vif.driver_cb.b_preload_valid <= 1'b0;
      vif.driver_cb.b_seed_valid    <= 1'b0;
      for (int i = 0; i < N; i++) begin
        vif.driver_cb.a_din[i] <= '0;
        vif.driver_cb.b_din[i] <= '0;
        vif.driver_cb.c_din[i] <= '0;
      end
    endtask

    task drive_transaction(sa_seq_item #(DIN_WIDTH,N) item);
      automatic int M = item.M;

      // ------------------------------------------------------------
      // Phase 1 + Phase 2
      // ------------------------------------------------------------
      if (!d_skip_p12) begin

        // Phase 1: B preload
        for (int cyc = 0; cyc < (2*N-2); cyc++) begin
          @(vif.driver_cb);
          vif.driver_cb.in_valid        <= 1'b0;
          vif.driver_cb.b_preload_valid <= 1'b1;
          vif.driver_cb.b_seed_valid    <= 1'b0;

          for (int i = 0; i < N; i++) begin
            vif.driver_cb.a_din[i] <= '0;
            vif.driver_cb.c_din[i] <= '0;
          end

          for (int j = 0; j < N; j++) begin
            automatic int row = (N-1) - (cyc - j);
            vif.driver_cb.b_din[j] <=
              (row >= 0 && row < N && row < M && (cyc - j) >= 0)
              ? item.B[row][j] : '0;
          end
        end

        // Phase 2: swap cycle
        begin
          automatic int swap_cyc = 2*N - 2;
          @(vif.driver_cb);
          vif.driver_cb.in_valid        <= 1'b1;
          vif.driver_cb.b_preload_valid <= 1'b0;
          vif.driver_cb.b_seed_valid    <= item.has_bt;

          for (int i = 0; i < N; i++)
            vif.driver_cb.c_din[i] <= '0;

          for (int j = 0; j < N; j++) begin
            automatic int row = (N-1) - (swap_cyc - j);
            if (j == 0 && item.has_bt)
              vif.driver_cb.b_din[0] <= item.B_next[N-1][0];
            else
              vif.driver_cb.b_din[j] <=
                (row >= 0 && row < N && (swap_cyc - j) >= 0)
                ? item.B[row][j] : '0;
          end

          vif.driver_cb.a_din[0] <= item.A[0][0];
          for (int k = 1; k < N; k++)
            vif.driver_cb.a_din[k] <= '0;
        end

      end

      d_skip_p12 = 0;

      // ------------------------------------------------------------
      // Phase 3: A tail
      // ------------------------------------------------------------
      for (int cyc = 1; cyc <= (M + N - 2); cyc++) begin
        @(vif.driver_cb);

        for (int i = 0; i < N; i++)
          vif.driver_cb.c_din[i] <= '0;

        if (item.has_bt && cyc == 2*N - 2) begin
          // overlap / next swap
          vif.driver_cb.in_valid        <= 1'b1;
          vif.driver_cb.b_preload_valid <= 1'b0;
          vif.driver_cb.b_seed_valid    <= item.next_has_bt;

          for (int j = 0; j < N; j++) begin
            automatic int brow = (N-1) - (cyc - j);
            if (j == 0) begin
              if(item.next_has_bt)
                vif.driver_cb.b_din[0] <= item.b_after_next00;
              else
                vif.driver_cb.b_din[0] <= '0;
            end else begin
              vif.driver_cb.b_din[j] <=
                (brow >= 0 && brow < N && (cyc - j) >= 0)
                ? item.B_next[brow][j] : '0;
            end
          end

          vif.driver_cb.a_din[0] <= item.a_next00;

          for (int k = 1; k < N; k++) begin
            automatic int arow = cyc - k;
            vif.driver_cb.a_din[k] <=
              (arow >= 0 && arow < N && k < M) ? item.A[arow][k] : '0;
          end

          d_skip_p12 = 1;
        end
        else begin
          logic preload_en;
          preload_en = (item.has_bt && cyc < 2*N - 2);

          vif.driver_cb.in_valid        <= 1'b0;
          vif.driver_cb.b_seed_valid    <= 1'b0;
          vif.driver_cb.b_preload_valid <= preload_en;

          for (int j = 0; j < N; j++) begin
            if (preload_en) begin
              automatic int brow = (N-1) - (cyc - j);
              vif.driver_cb.b_din[j] <=
                (brow >= 0 && brow < N && (cyc - j) >= 0)
                ? item.B_next[brow][j] : '0;
            end
            else begin
              vif.driver_cb.b_din[j] <= '0;
            end
          end

          for (int k = 0; k < N; k++) begin
            automatic int arow = cyc - k;
            vif.driver_cb.a_din[k] <=
              (arow >= 0 && arow < N && k < M) ? item.A[arow][k] : '0;
          end
        end
      end

      if (!item.has_bt) begin
        @(vif.driver_cb);
        drive_idle();
      end

      `uvm_info("DRV","Transaction drive complete",UVM_HIGH)
    endtask
  endclass

  // =========================================================================
  // Monitor
  // Supports overlapping outputs by spawning a capture thread per out_valid rise.
  // =========================================================================
  class sa_monitor #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_monitor;

    `uvm_component_param_utils(sa_monitor#(DIN_WIDTH,N))

    virtual sa_if #(DIN_WIDTH,N) vif;
    uvm_analysis_port #(sa_seq_item#(DIN_WIDTH,N)) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(virtual sa_if#(DIN_WIDTH,N))::get(this,"","vif",vif))
        `uvm_fatal("CFG","No vif in sa_monitor")
    endfunction

    task run_phase(uvm_phase phase);
      bit prev_out_valid;
      prev_out_valid = 0;

      forever begin
        @(vif.monitor_cb);

        if (!prev_out_valid && vif.monitor_cb.out_valid === 1'b1) begin
          fork
            collect_one_result();
          join_none
        end

        prev_out_valid = vif.monitor_cb.out_valid;
      end
    endtask

    task automatic collect_one_result();
      sa_seq_item #(DIN_WIDTH,N) item;
      logic signed [2*DIN_WIDTH-1:0] c_capture [2*N-1][N];

      item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("mon_item");
      item.C_exp = new[N];
      foreach (item.C_exp[i]) item.C_exp[i] = new[N];
      item.M = 0;
      item.A = new[0];
      item.B = new[0];

      // Beat 0 is on same sampled cycle as out_valid rise
      for (int j = 0; j < N; j++)
        c_capture[0][j] = vif.monitor_cb.c_dout[j];

      for (int cyc = 1; cyc < (2*N-1); cyc++) begin
        @(vif.monitor_cb);
        for (int j = 0; j < N; j++)
          c_capture[cyc][j] = vif.monitor_cb.c_dout[j];
      end

      for (int cyc = 0; cyc < (2*N-1); cyc++) begin
        for (int j = 0; j < N; j++) begin
          automatic int row = cyc - j;
          if (row >= 0 && row < N)
            item.C_exp[row][j] = c_capture[cyc][j];
        end
      end

      `uvm_info("MON", $sformatf("Captured C:\n%0s", item.convert2string()), UVM_HIGH)
      ap.write(item);
    endtask
  endclass

  // =========================================================================
  // Scoreboard
  // =========================================================================
  `uvm_analysis_imp_decl(_expected)
  `uvm_analysis_imp_decl(_actual)

  class sa_scoreboard #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_scoreboard;

    `uvm_component_param_utils(sa_scoreboard#(DIN_WIDTH,N))

    uvm_analysis_imp_expected #(sa_seq_item#(DIN_WIDTH,N), sa_scoreboard#(DIN_WIDTH,N)) ap_exp;
    uvm_analysis_imp_actual   #(sa_seq_item#(DIN_WIDTH,N), sa_scoreboard#(DIN_WIDTH,N)) ap_act;

    sa_seq_item #(DIN_WIDTH,N) exp_q[$];
    int pass_cnt = 0;
    int fail_cnt = 0;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap_exp = new("ap_exp", this);
      ap_act = new("ap_act", this);
    endfunction

    function void write_expected(sa_seq_item #(DIN_WIDTH,N) item);
      sa_seq_item #(DIN_WIDTH,N) cpy;
      $cast(cpy, item.clone());
      exp_q.push_back(cpy);
      `uvm_info("SCB", $sformatf("Expected queued depth=%0d", exp_q.size()), UVM_HIGH)
    endfunction

    function void write_actual(sa_seq_item #(DIN_WIDTH,N) item);
      sa_seq_item #(DIN_WIDTH,N) exp_item;
      bit mismatch = 0;
      string msg;

      if (exp_q.size() == 0) begin
        `uvm_error("SCB","DUT output but no expected in queue!")
        fail_cnt++;
        return;
      end

      exp_item = exp_q.pop_front();
      msg = "--- Matrix Comparison ---\n";

      for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
          if (item.C_exp[i][j] !== exp_item.C_exp[i][j]) begin
            msg = {msg, $sformatf("  MISMATCH C[%0d][%0d]: DUT=%0d EXP=%0d\n",
                                  i, j, item.C_exp[i][j], exp_item.C_exp[i][j])};
            mismatch = 1;
          end
        end
      end

      if (mismatch) begin
        `uvm_error("SCB", {msg, "*** FAIL ***"})
        fail_cnt++;
      end
      else begin
        `uvm_info("SCB", {msg, "*** PASS ***"}, UVM_MEDIUM)
        pass_cnt++;
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", $sformatf({
        "\n===== SA-Level Scoreboard =====\n",
        "PASS: %0d   FAIL: %0d\n",
        "================================"
      }, pass_cnt, fail_cnt), UVM_NONE)

      if (fail_cnt > 0 || exp_q.size() > 0)
        `uvm_error("SCB", $sformatf("FAILED (fail=%0d unmatched_exp=%0d)", fail_cnt, exp_q.size()))
      else
        `uvm_info("SCB", "TEST PASSED", UVM_NONE)
    endfunction
  endclass

  // =========================================================================
  // Agent
  // =========================================================================
  class sa_agent #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_agent;

    `uvm_component_param_utils(sa_agent#(DIN_WIDTH,N))

    sa_driver  #(DIN_WIDTH,N)                      m_drv;
    sa_monitor #(DIN_WIDTH,N)                      m_mon;
    uvm_sequencer #(sa_seq_item#(DIN_WIDTH,N))     m_seqr;
    uvm_analysis_port #(sa_seq_item#(DIN_WIDTH,N)) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      m_drv  = sa_driver #(DIN_WIDTH,N)::type_id::create("m_drv", this);
      m_mon  = sa_monitor#(DIN_WIDTH,N)::type_id::create("m_mon", this);
      m_seqr = uvm_sequencer#(sa_seq_item#(DIN_WIDTH,N))::type_id::create("m_seqr", this);
      ap     = new("ap", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      m_drv.seq_item_port.connect(m_seqr.seq_item_export);
      m_mon.ap.connect(ap);
    endfunction
  endclass

  // =========================================================================
  // Environment
  // =========================================================================
  class sa_env #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_env;

    `uvm_component_param_utils(sa_env#(DIN_WIDTH,N))

    sa_agent      #(DIN_WIDTH,N) m_agent;
    sa_scoreboard #(DIN_WIDTH,N) m_scb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      m_agent = sa_agent     #(DIN_WIDTH,N)::type_id::create("m_agent", this);
      m_scb   = sa_scoreboard#(DIN_WIDTH,N)::type_id::create("m_scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      m_agent.ap.connect(m_scb.ap_act);
    endfunction
  endclass

  // =========================================================================
  // Base Test
  // =========================================================================
  class sa_base_test #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends uvm_test;

    `uvm_component_param_utils(sa_base_test#(DIN_WIDTH,N))

    sa_env #(DIN_WIDTH,N) m_env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      m_env = sa_env#(DIN_WIDTH,N)::type_id::create("m_env", this);
    endfunction

    task push_and_drive(sa_seq_item#(DIN_WIDTH,N) item);
      sa_rand_seq #(DIN_WIDTH,N) seq;
      m_env.m_scb.ap_exp.write(item);
      seq = sa_rand_seq#(DIN_WIDTH,N)::type_id::create("wrap_seq");
      seq.items.push_back(item);
      seq.start(m_env.m_agent.m_seqr);
    endtask
  endclass

  // =========================================================================
  // Directed Test
  // =========================================================================
  class sa_directed_test #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends sa_base_test#(DIN_WIDTH,N);

    `uvm_component_param_utils(sa_directed_test#(DIN_WIDTH,N))

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      sa_seq_item #(DIN_WIDTH,N) item;
      phase.raise_objection(this);

      item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("zero");
      assert(item.randomize() with {
        M == N;
        foreach (A[i,j]) A[i][j] == 0;
        foreach (B[i,j]) B[i][j] == 0;
      }) else `uvm_fatal("RAND","Failed")
      `uvm_info("TEST","--- [1] Zero Matrix ---",UVM_NONE)
      push_and_drive(item); #300ns;

      item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("identity");
      assert(item.randomize() with {
        M == N;
        foreach (A[i,j]) A[i][j] == (i==j ? 1 : 0);
      }) else `uvm_fatal("RAND","Failed")
      `uvm_info("TEST","--- [2] Identity A ---",UVM_NONE)
      push_and_drive(item); #300ns;

      item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("same");
      assert(item.randomize() with {
        M == N;
        foreach (A[i,j]) A[i][j] == 3;
        foreach (B[i,j]) B[i][j] == 3;
      }) else `uvm_fatal("RAND","Failed")
      `uvm_info("TEST","--- [3] All-Same Values ---",UVM_NONE)
      push_and_drive(item); #300ns;

      item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("maxval");
      assert(item.randomize() with {
        M == N;
        foreach (A[i,j]) A[i][j] == (1<<(DIN_WIDTH/2-1))-1;
        foreach (B[i,j]) B[i][j] == (1<<(DIN_WIDTH/2-1))-1;
      }) else `uvm_fatal("RAND","Failed")
      `uvm_info("TEST","--- [4] Max Values ---",UVM_NONE)
      push_and_drive(item); #300ns;

      item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("minneg");
      assert(item.randomize() with {
        M == N;
        foreach (A[i,j]) A[i][j] == -(1<<(DIN_WIDTH/2-1));
        foreach (B[i,j]) B[i][j] == -(1<<(DIN_WIDTH/2-1));
      }) else `uvm_fatal("RAND","Failed")
      `uvm_info("TEST","--- [5] Min Negative Values ---",UVM_NONE)
      push_and_drive(item); #300ns;

      `uvm_info("TEST","--- [6] Random x4 ---",UVM_NONE)
      repeat (4) begin
        item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("rand");
        assert(item.randomize()) else `uvm_fatal("RAND","Failed")
        push_and_drive(item); #300ns;
      end

      `uvm_info("TEST","--- [7] Consecutive x3 (M=N) ---",UVM_NONE)
      begin
        sa_seq_item #(DIN_WIDTH,N) items[$];
        sa_rand_seq #(DIN_WIDTH,N) consec_seq;

        repeat (3) begin
          item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("consec");
          assert(item.randomize() with { M == N; }) else `uvm_fatal("RAND","Failed")
          items.push_back(item);
        end

        // First set has_bt for all items
          items[0].has_bt = 1;
          items[1].has_bt = 1;
          items[2].has_bt = 0;

          // Then wire the back-to-back metadata
          items[0].B_next         = items[1].B;
          items[0].a_next00       = items[1].A[0][0];
          items[0].next_has_bt    = items[1].has_bt;      // now this is 1
          items[0].b_after_next00 = items[2].B[N-1][0];

          items[1].B_next         = items[2].B;
          items[1].a_next00       = items[2].A[0][0];
          items[1].next_has_bt    = items[2].has_bt;      // 0
          items[1].b_after_next00 = '0;

          items[2].next_has_bt    = 0;
          items[2].b_after_next00 = '0;

        foreach (items[i]) m_env.m_scb.ap_exp.write(items[i]);

        consec_seq = sa_rand_seq#(DIN_WIDTH,N)::type_id::create("consec_seq");
        foreach (items[i]) consec_seq.items.push_back(items[i]);
        consec_seq.start(m_env.m_agent.m_seqr);
      end

      #500ns;
      phase.drop_objection(this);
    endtask
  endclass

  // =========================================================================
  // Random Regression Test
  // =========================================================================
  class sa_rand_test #(parameter int DIN_WIDTH=8, parameter int N=4)
    extends sa_base_test#(DIN_WIDTH,N);

    `uvm_component_param_utils(sa_rand_test#(DIN_WIDTH,N))

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      sa_seq_item #(DIN_WIDTH,N) item;
      phase.raise_objection(this);
      repeat (10) begin
        item = sa_seq_item#(DIN_WIDTH,N)::type_id::create("item");
        assert(item.randomize()) else `uvm_fatal("RAND","Failed")
        push_and_drive(item);
        #300ns;
      end
      #500ns;
      phase.drop_objection(this);
    endtask
  endclass

  // =========================================================================
  // Concrete aliases
  // =========================================================================
  class sa_directed_test_8_4 extends sa_directed_test#(8,4);
    `uvm_component_utils(sa_directed_test_8_4)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class sa_rand_test_8_4 extends sa_rand_test#(8,4);
    `uvm_component_utils(sa_rand_test_8_4)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

endpackage

`endif