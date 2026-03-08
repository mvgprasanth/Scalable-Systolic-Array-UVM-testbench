`ifndef SA_REF_MODEL_SV_SV
`define SA_REF_MODEL_SV_SV

module sa_ref_model_sv #(
    parameter int DIN_WIDTH = 8,
    parameter int N         = 4
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic signed [2*DIN_WIDTH-1:0] c_din           [0:N-1],
    input  logic signed [DIN_WIDTH-1:0]   a_din           [0:N-1],
    input  logic signed [DIN_WIDTH-1:0]   b_din           [0:N-1],
    input  logic                          in_valid,
    input  logic                          b_preload_valid,
    input  logic                          b_seed_valid,
    output logic signed [2*DIN_WIDTH-1:0] c_dout          [0:N-1],
    output logic                          out_valid
);

    localparam int CQUEUE_DEPTH = 4;
    localparam int ACAP_COLS    = 256;

    logic in_valid_prev;
    logic in_valid_rise;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) in_valid_prev <= 1'b0;
        else        in_valid_prev <= in_valid;
    end

    assign in_valid_rise = in_valid & ~in_valid_prev;

    logic signed [63:0] B_preload [0:N-1][0:N-1];
    logic signed [63:0] B_active  [0:N-1][0:N-1];
    logic signed [63:0] A_cap     [0:N-1][0:ACAP_COLS-1];
    logic signed [63:0] C_queue   [0:CQUEUE_DEPTH-1][0:N-1][0:N-1];

    int   out_cyc_arr    [0:N-1];
    int   out_qslot_arr  [0:N-1];
    logic out_active_arr [0:N-1];

    int   b_preload_cyc;
    int   a_cyc;
    int   trig_thresh;
    int   C_q_wr;
    int   C_q_rd;
    logic a_capturing;
    logic b_preloading;
    logic b_just_swapped;
    int   b_idle_ctr;

    task automatic capture_b_lane(input int pcyc);
        int row;
        for (int j = 0; j < N; j++) begin
            row = (N - 1) - (pcyc - j);
            if (row >= 0 && row < N && (pcyc - j) >= 0) begin
                B_preload[row][j] =
                    $signed({{(64-DIN_WIDTH){b_din[j][DIN_WIDTH-1]}}, b_din[j]});
            end
        end
    endtask

    task automatic do_matmul(
        input int q_slot,
        input int M_loc
    );
        logic signed [63:0] acc;
        for (int ci = 0; ci < N; ci++) begin
            for (int cj = 0; cj < N; cj++) begin
                acc = 64'sd0;
                for (int ck = 0; ck < M_loc; ck++) begin
                    acc = acc + A_cap[ci][ck] * B_active[ck][cj];
                end
                C_queue[q_slot][ci][cj] = acc;
            end
        end
        `ifndef SYNTHESIS
        $display("[REF %0t] C[0][0..N-1] = %0d %0d  C[1][0..N-1] = %0d %0d",
                 $time,
                 C_queue[q_slot][0][0],   C_queue[q_slot][0][N-1],
                 C_queue[q_slot][N-1][0], C_queue[q_slot][N-1][N-1]);
        `endif
    endtask

    task automatic start_output_stream(input int q_slot);
        for (int si = 0; si < N; si++) begin
            if (!out_active_arr[si]) begin
                out_active_arr[si] = 1'b1;
                out_cyc_arr[si]    = 0;
                out_qslot_arr[si]  = q_slot;
                `ifndef SYNTHESIS
                $display("[REF %0t] Output stream %0d started for C_queue[%0d]",
                         $time, si, q_slot);
                `endif
                break;
            end
        end
    endtask

    task automatic finish_old_capture();
        int row, m_loc, q_slot;
        for (int k = 0; k < N; k++) begin
            row = a_cyc - k;
            if (row >= 0 && row < N) begin
                A_cap[row][k] =
                    $signed({{(64-DIN_WIDTH){a_din[k][DIN_WIDTH-1]}}, a_din[k]});
            end
        end

        if (a_cyc >= trig_thresh) begin
            m_loc  = trig_thresh - N + 2;
            q_slot = C_q_wr % CQUEUE_DEPTH;
            `ifndef SYNTHESIS
            $display("[REF %0t] Compute (overlap-finish): M=%0d q_slot=%0d",
                     $time, m_loc, q_slot);
            `endif
            do_matmul(q_slot, m_loc);
            start_output_stream(q_slot);
            C_q_wr = C_q_wr + 1;
        end
    endtask

    task automatic capture_a_lane(input int cyc_val);
        int row;
        for (int k = 0; k < N; k++) begin
            row = cyc_val - k;
            if (row >= 0 && row < N) begin
                A_cap[row][k] =
                    $signed({{(64-DIN_WIDTH){a_din[k][DIN_WIDTH-1]}}, a_din[k]});
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin : ref_main
        if (!rst_n) begin
            b_preload_cyc  <= 0;
            a_cyc          <= 0;
            trig_thresh    <= 0;
            C_q_wr         <= 0;
            C_q_rd         <= 0;
            a_capturing    <= 1'b0;
            b_preloading   <= 1'b0;
            b_just_swapped <= 1'b0;
            b_idle_ctr     <= 0;
            out_valid      <= 1'b0;

            for (int i = 0; i < N; i++) begin
                c_dout[i] <= '0;
            end

            for (int i = 0; i < N; i++) begin
                for (int j = 0; j < N; j++) begin
                    B_preload[i][j] = '0;
                    B_active[i][j]  = '0;
                end
            end

            for (int i = 0; i < N; i++) begin
                for (int k = 0; k < ACAP_COLS; k++) begin
                    A_cap[i][k] = '0;
                end
            end

            for (int q = 0; q < CQUEUE_DEPTH; q++) begin
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        C_queue[q][i][j] = '0;
                    end
                end
            end

            for (int s = 0; s < N; s++) begin
                out_active_arr[s] = 1'b0;
                out_cyc_arr[s]    = 0;
                out_qslot_arr[s]  = 0;
            end

        end else begin
            // ------------------------------------------------------------
            // Section 0: overlap finish
            // ------------------------------------------------------------
            if (in_valid_rise && a_capturing) begin
                `ifndef SYNTHESIS
                $display("[REF %0t] Section 0: overlap finish a_cyc=%0d trig_thresh=%0d",
                         $time, a_cyc, trig_thresh);
                `endif
                finish_old_capture();
                a_capturing <= 1'b0;
                a_cyc       <= 0;
            end

            // ------------------------------------------------------------
            // Section 1a: regular B preload
            // Use explicit control, not data value.
            // ------------------------------------------------------------
            if (!in_valid_rise) begin : s1a
                automatic logic idle_reset = 1'b0;

                b_just_swapped <= 1'b0;

                if (b_idle_ctr > 0) begin
                    b_idle_ctr <= b_idle_ctr - 1;
                    if (b_idle_ctr == 1)
                        idle_reset = 1'b1;
                end

                if (idle_reset) begin
                    b_preload_cyc <= 0;
                    b_preloading  <= 1'b0;
                end
                else if (b_preload_valid) begin
                    if (!b_preloading && !b_just_swapped)
                        b_preload_cyc = 0;
                    capture_b_lane(b_preload_cyc);
                    b_preload_cyc <= b_preload_cyc + 1;
                    b_preloading  <= 1'b1;
                end
                else begin
                    b_preloading <= 1'b0;
                end
            end

            // ------------------------------------------------------------
            // Section 1b: B swap
            // ------------------------------------------------------------
            if (in_valid_rise) begin : s1b
                // Capture final preload diagonal of the current B
                capture_b_lane(b_preload_cyc);

                // Swap preload -> active
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        B_active[i][j] = B_preload[i][j];
                    end
                end

                `ifndef SYNTHESIS
                $display("[REF %0t] B swap -> B_active[0][0]=%0d [0][%0d]=%0d [%0d][0]=%0d",
                         $time, B_active[0][0], N-1, B_active[0][N-1], N-1, B_active[N-1][0]);
                `endif

                // Clear preload buffer
                for (int i = 0; i < N; i++) begin
                    for (int j = 0; j < N; j++) begin
                        B_preload[i][j] = '0;
                    end
                end

                // Optional seed for the next-next transaction
                if (b_seed_valid) begin
                    automatic int rnew = N - 1;
                    B_preload[rnew][0] =
                        $signed({{(64-DIN_WIDTH){b_din[0][DIN_WIDTH-1]}}, b_din[0]});
                end

                trig_thresh    <= 2*N - 2;
                b_preload_cyc  <= b_seed_valid ? 1 : 0;
                b_preloading   <= b_seed_valid;
                b_just_swapped <= 1'b1;
                b_idle_ctr     <= 2*N - 1;
            end

            // ------------------------------------------------------------
            // Section 2a: A capture start
            // ------------------------------------------------------------
            if (in_valid_rise) begin : s2a
                for (int i = 0; i < N; i++) begin
                    for (int k = 0; k < ACAP_COLS; k++) begin
                        A_cap[i][k] = '0;
                    end
                end

                A_cap[0][0] =
                    $signed({{(64-DIN_WIDTH){a_din[0][DIN_WIDTH-1]}}, a_din[0]});

                a_cyc       <= 1;
                a_capturing <= 1'b1;

                `ifndef SYNTHESIS
                $display("[REF %0t] A capture start. A[0][0]=%0d",
                         $time, $signed({{(64-DIN_WIDTH){a_din[0][DIN_WIDTH-1]}}, a_din[0]}));
                `endif
            end

            // ------------------------------------------------------------
            // Section 2b: A capture running
            // ------------------------------------------------------------
            if (a_capturing && !in_valid_rise) begin : s2b
                automatic int q_slot_loc;
                automatic int m_loc_loc;

                capture_a_lane(a_cyc);
                a_cyc <= a_cyc + 1;

                if (!in_valid && a_cyc >= trig_thresh) begin
                    q_slot_loc = C_q_wr % CQUEUE_DEPTH;
                    m_loc_loc  = trig_thresh - N + 2;
                    `ifndef SYNTHESIS
                    $display("[REF %0t] Compute (normal): M=%0d q_slot=%0d",
                             $time, m_loc_loc, q_slot_loc);
                    `endif
                    do_matmul(q_slot_loc, m_loc_loc);
                    start_output_stream(q_slot_loc);
                    C_q_wr      = C_q_wr + 1;
                    a_capturing <= 1'b0;
                    a_cyc       <= 0;
                end
            end

            // ------------------------------------------------------------
            // Section 3: output driver
            // out_valid is a 1-cycle pulse on the first beat of each matrix.
            // ------------------------------------------------------------
            begin : s3
                automatic logic signed [63:0] lane_acc [0:N-1];
                automatic logic any_active;
                automatic logic first_beat;

                for (int j = 0; j < N; j++) lane_acc[j] = '0;
                any_active = 1'b0;
                first_beat = 1'b0;

                for (int s = 0; s < N; s++) begin
                    if (out_active_arr[s]) begin
                        any_active = 1'b1;
                        if (out_cyc_arr[s] == 0)
                            first_beat = 1'b1;

                        for (int j = 0; j < N; j++) begin
                            automatic int row = out_cyc_arr[s] - j;
                            if (row >= 0 && row < N)
                                lane_acc[j] = lane_acc[j] + C_queue[out_qslot_arr[s]][row][j];
                        end
                    end
                end

                for (int j = 0; j < N; j++) begin
                    c_dout[j] <= any_active ? lane_acc[j][2*DIN_WIDTH-1:0] : '0;
                end

                out_valid <= first_beat;

                for (int s = 0; s < N; s++) begin
                    if (out_active_arr[s]) begin
                        if (out_cyc_arr[s] >= 2*N - 2) begin
                            `ifndef SYNTHESIS
                            $display("[REF %0t] Output done stream=%0d slot=%0d",
                                     $time, s, out_qslot_arr[s]);
                            `endif
                            out_active_arr[s] <= 1'b0;
                            out_cyc_arr[s]    <= 0;
                            C_q_rd            <= C_q_rd + 1;
                        end
                        else begin
                            out_cyc_arr[s] <= out_cyc_arr[s] + 1;
                        end
                    end
                end
            end
        end
    end

endmodule

`endif