`timescale 1ns/1ps

module mac_pe_tb;

    // ── DUT signals ──────────────────────────────────────────────────────────
    reg         clk;
    reg         reset;
    reg         valid_in;
    reg  [7:0]  a_in;
    reg  [7:0]  b_in;
    wire [15:0] sum_out;
    wire        valid_out;

    integer pass_count;
    integer fail_count;

    // ── DUT instantiation ────────────────────────────────────────────────────
    mac_pe #(.DATA_WIDTH(8), .ACC_WIDTH(16)) dut (
        .clk      (clk),
        .reset    (reset),
        .valid_in (valid_in),
        .a_in     (a_in),
        .b_in     (b_in),
        .sum_out  (sum_out),
        .valid_out(valid_out)
    );

    // ── Clock: 10 ns period ──────────────────────────────────────────────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Helper tasks ─────────────────────────────────────────────────────────

    task apply_reset;
        begin
            reset = 1; valid_in = 0; a_in = 0; b_in = 0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            reset = 0;
        end
    endtask

    // Feed one input pair for exactly one cycle, then clear inputs
    task feed_pair;
        input [7:0] a;
        input [7:0] b;
        begin
            a_in = a; b_in = b; valid_in = 1;
            @(posedge clk); #1;
            a_in = 0; b_in = 0; valid_in = 0;
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk); #1;
            end
        end
    endtask

    task check;
        input [15:0]    expected;
        input [255:0]   label;
        begin
            if (sum_out === expected) begin
                $display("  PASS [%0s]: got %0d, expected %0d", label, sum_out, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL [%0s]: got %0d, expected %0d", label, sum_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ═════════════════════════════════════════════════════════════════════════
    initial begin
        $dumpfile("mac_pe_tb.vcd");
        $dumpvars(0, mac_pe_tb);

        pass_count = 0;
        fail_count = 0;

        // ─────────────────────────────────────────────────────────────────────
        // Test 1: Basic Functionality
        //   A=3, B=4  → 12
        //   A=7, B=1  → 7
        //   A=5, B=0  → 0
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Test 1: Basic Functionality ──────────────────────────");

        apply_reset;
        feed_pair(3, 4);
        wait_cycles(2);
        check(16'd12, "A=3 B=4");

        apply_reset;
        feed_pair(7, 1);
        wait_cycles(2);
        check(16'd7, "A=7 B=1");

        apply_reset;
        feed_pair(5, 0);
        wait_cycles(2);
        check(16'd0, "A=5 B=0");

        // ─────────────────────────────────────────────────────────────────────
        // Test 2: Accumulation over 4 pairs (most important test)
        //   (2*3) + (1*4) + (5*2) + (3*3) = 6 + 4 + 10 + 9 = 29
        //   Verifies acc is actually building a running total, not overwriting.
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Test 2: Accumulation Correctness ─────────────────────");

        apply_reset;
        a_in = 2; b_in = 3; valid_in = 1; @(posedge clk); #1;
        a_in = 1; b_in = 4; valid_in = 1; @(posedge clk); #1;
        a_in = 5; b_in = 2; valid_in = 1; @(posedge clk); #1;
        a_in = 3; b_in = 3; valid_in = 1; @(posedge clk); #1;
        a_in = 0; b_in = 0; valid_in = 0;
        wait_cycles(2);
        check(16'd29, "4-pair dot product");

        // ─────────────────────────────────────────────────────────────────────
        // Test 3: Corner / Boundary Cases
        //   Max: 255*255 = 65025 — fits in 16 bits (max 65535), verify no truncation
        //   All zeros: acc stays 0 across multiple cycles
        //   One max, one zero: result must be 0
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Test 3: Corner Cases ─────────────────────────────────");

        apply_reset;
        feed_pair(8'd255, 8'd255);
        wait_cycles(2);
        check(16'd65025, "max values 255*255");

        apply_reset;
        a_in = 0; b_in = 0; valid_in = 1; @(posedge clk); #1;
        a_in = 0; b_in = 0; valid_in = 1; @(posedge clk); #1;
        a_in = 0; b_in = 0; valid_in = 1; @(posedge clk); #1;
        a_in = 0; b_in = 0; valid_in = 0;
        wait_cycles(2);
        check(16'd0, "all zeros");

        apply_reset;
        feed_pair(8'd255, 8'd0);
        wait_cycles(2);
        check(16'd0, "A=255 B=0");

        // ─────────────────────────────────────────────────────────────────────
        // Test 4: Reset Behavior
        //   Assert reset mid-accumulation → output must clear to 0
        //   After releasing reset → fresh accumulation starts from 0
        //   Reset on the very first cycle before any inputs
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Test 4: Reset Behavior ───────────────────────────────");

        // Reset on first cycle
        reset = 1; valid_in = 0; a_in = 0; b_in = 0;
        @(posedge clk); #1;
        check(16'd0, "reset on first cycle");
        reset = 0;

        // Feed 2 pairs, then assert reset before result is ready
        apply_reset;
        a_in = 10; b_in = 10; valid_in = 1; @(posedge clk); #1;
        a_in = 5;  b_in = 5;  valid_in = 1; @(posedge clk); #1;
        a_in = 0;  b_in = 0;  valid_in = 0;
        reset = 1;                            // reset mid-computation
        @(posedge clk); #1;
        @(posedge clk); #1;
        check(16'd0, "reset mid-accumulation clears");
        reset = 0;

        // After reset, fresh accumulation should start from 0
        feed_pair(3, 3);
        wait_cycles(2);
        check(16'd9, "after reset fresh accumulation");

        // ─────────────────────────────────────────────────────────────────────
        // Test 5: Pipeline Timing
        //   Sample 1 cycle after feeding — result must NOT be present yet
        //   Sample 2 cycles after feeding — result must be correct
        //   Verifies pipeline latency is exactly 2 cycles after last input.
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Test 5: Pipeline Timing ──────────────────────────────");

        apply_reset;
        a_in = 4; b_in = 4; valid_in = 1; @(posedge clk); #1;
        a_in = 0; b_in = 0; valid_in = 0;

        // 1 cycle after feeding: sum_out must still be 0 (pipeline not through yet)
        @(posedge clk); #1;
        if (sum_out !== 16'd16) begin
            $display("  PASS [1 cycle early: not yet valid]: sum_out=%0d", sum_out);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL [1 cycle early: result appeared too soon]: sum_out=%0d", sum_out);
            fail_count = fail_count + 1;
        end

        // 2 cycles after feeding: sum_out must be 16
        @(posedge clk); #1;
        check(16'd16, "A=4 B=4 at correct cycle");

        // ─────────────────────────────────────────────────────────────────────
        // Test 6: Continuous Streaming (8 pairs)
        //   1^2 + 2^2 + 3^2 + 4^2 + 5^2 + 6^2 + 7^2 + 8^2
        //   = 1+4+9+16+25+36+49+64 = 204
        //   Verifies acc keeps growing correctly across more than one matrix worth.
        // ─────────────────────────────────────────────────────────────────────
        $display("\n── Test 6: Continuous Streaming (8 pairs) ───────────────");

        apply_reset;
        a_in = 1; b_in = 1; valid_in = 1; @(posedge clk); #1;
        a_in = 2; b_in = 2; valid_in = 1; @(posedge clk); #1;
        a_in = 3; b_in = 3; valid_in = 1; @(posedge clk); #1;
        a_in = 4; b_in = 4; valid_in = 1; @(posedge clk); #1;
        a_in = 5; b_in = 5; valid_in = 1; @(posedge clk); #1;
        a_in = 6; b_in = 6; valid_in = 1; @(posedge clk); #1;
        a_in = 7; b_in = 7; valid_in = 1; @(posedge clk); #1;
        a_in = 8; b_in = 8; valid_in = 1; @(posedge clk); #1;
        a_in = 0; b_in = 0; valid_in = 0;
        wait_cycles(2);
        check(16'd204, "8-pair running sum");

        // ─────────────────────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────────────────────
        $display("\n─────────────────────────────────────────────────────────");
        $display("Results: %0d passed, %0d failed out of %0d",
                  pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — check waveform in mac_pe_tb.vcd");
        $display("─────────────────────────────────────────────────────────\n");

        $finish;
    end

endmodule
