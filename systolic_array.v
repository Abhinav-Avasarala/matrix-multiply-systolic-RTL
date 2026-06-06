`timescale 1ns/1ps

module systolic_array #(
    parameter N          = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 16
)(
    input  logic                  clk,
    input  logic                  reset,

    // A matrix: one input per row, fed from the left edge.
    // Testbench must skew: row i starts being fed at cycle i.
    // During the skew period drive zeros so 0*0=0 doesn't corrupt the accumulator.
    input  logic [DATA_WIDTH-1:0] a_in [0:N-1],

    // B matrix: one input per column, fed from the top edge.
    // Testbench must skew: column j starts being fed at cycle j.
    // During the skew period drive zeros so 0*0=0 doesn't corrupt the accumulator.
    input  logic [DATA_WIDTH-1:0] b_in [0:N-1],

    // C matrix: PE[i][j] holds C[i][j] = dot product of A row i and B col j.
    // Valid after K + (N-1) + 3 cycles from the first non-skewed input
    // (K = inner-dimension length, N-1 = max skew, 3 = mac_pe pipeline depth).
    output logic [ACC_WIDTH-1:0]  c_out [0:N-1][0:N-1]
);

    // -------------------------------------------------------------------------
    // A wire array: a_wire[i][j] is the A value PE[i][j] receives.
    //
    // a_wire[i][0]   = a_in[i]              (left edge, direct)
    // a_wire[i][j+1] = a_wire[i][j] delayed (shifts right each cycle)
    //
    // j spans 0..N so the array has N+1 columns.
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] a_wire [0:N-1][0:N];

    // -------------------------------------------------------------------------
    // B wire array: b_wire[i][j] is the B value PE[i][j] receives.
    //
    // b_wire[0][j]   = b_in[j]              (top edge, direct)
    // b_wire[i+1][j] = b_wire[i][j] delayed (shifts down each cycle)
    //
    // i spans 0..N so the array has N+1 rows.
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] b_wire [0:N][0:N-1];

    genvar i, j;

    // -------------------------------------------------------------------------
    // Connect input edges
    // -------------------------------------------------------------------------
    generate
        for (i = 0; i < N; i++) begin : edge_connect
            assign a_wire[i][0] = a_in[i];
            assign b_wire[0][i] = b_in[i];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Shift A values rightward.
    // PE[i][j] sees a_in[i] delayed by j cycles, so A[i][k] reaches PE[i][j]
    // at cycle (i + k + j) when the testbench skews row i by i cycles.
    // -------------------------------------------------------------------------
    generate
        for (i = 0; i < N; i++) begin : a_shift_row
            for (j = 0; j < N; j++) begin : a_shift_col
                always_ff @(posedge clk) begin
                    if (reset)
                        a_wire[i][j+1] <= '0;
                    else
                        a_wire[i][j+1] <= a_wire[i][j];
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Shift B values downward.
    // PE[i][j] sees b_in[j] delayed by i cycles, so B[k][j] reaches PE[i][j]
    // at cycle (j + k + i) — same arrival cycle as A[i][k]. ✓
    // -------------------------------------------------------------------------
    generate
        for (j = 0; j < N; j++) begin : b_shift_col
            for (i = 0; i < N; i++) begin : b_shift_row
                always_ff @(posedge clk) begin
                    if (reset)
                        b_wire[i+1][j] <= '0;
                    else
                        b_wire[i+1][j] <= b_wire[i][j];
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // PE grid: PE[i][j] computes C[i][j] = sum_k A[i][k] * B[k][j].
    // valid_in is tied high — mac_pe always accumulates; reset clears the acc.
    // -------------------------------------------------------------------------
    generate
        for (i = 0; i < N; i++) begin : pe_row
            for (j = 0; j < N; j++) begin : pe_col
                mac_pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) pe_inst (
                    .clk      (clk),
                    .reset    (reset),
                    .valid_in (1'b1),
                    .a_in     (a_wire[i][j]),
                    .b_in     (b_wire[i][j]),
                    .sum_out  (c_out[i][j]),
                    .valid_out()              // unused — user waits K+(N-1)+3 cycles
                );
            end
        end
    endgenerate

endmodule
