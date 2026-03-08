// ============================================================================
// Golden reference model function
// ============================================================================
`ifndef MATRIX_PKG_SV
`define MATRIX_PKG_SV

package matrix_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    function automatic void golden_matmul(
        input  int      N,
        input  int      M,
        input  longint  A[][],   // A[N][M]
        input  longint  B[][],   // B[M][N]
        output longint  C[][]    
    );
        C = new[N];
        for (int i = 0; i < N; i++) begin
            C[i] = new[N];
            for (int j = 0; j < N; j++) begin
                C[i][j] = 0;
                for (int k = 0; k < M; k++)
                    C[i][j] += A[i][k] * B[k][j];
            end
        end
    endfunction

endpackage

`endif
