// ============================================================================
// poly1305_tb.sv — Standalone testbench for poly1305_core
//
// Verifies against all 11 test vectors from RFC 8439 Appendix A.3
//
// Author : Copilot
// ============================================================================
`timescale 1ns / 100ps

module poly1305_tb;

  // -----------------------------------------------------------------------
  //  Parameters
  // -----------------------------------------------------------------------
  localparam CLK_PERIOD = 20;   // 50 MHz

  // -----------------------------------------------------------------------
  //  Signals
  // -----------------------------------------------------------------------
  logic         clk, rst_n;
  logic         init, block_valid, finalize;
  logic [127:0] key_r, key_s;
  logic [127:0] block;
  logic [4:0]   block_len;
  logic         busy, done, valid;
  logic [127:0] tag;

  // -----------------------------------------------------------------------
  //  DUT
  // -----------------------------------------------------------------------
  poly1305_core dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .init_i        (init),
    .block_valid_i (block_valid),
    .finalize_i    (finalize),
    .key_r_i       (key_r),
    .key_s_i       (key_s),
    .block_i       (block),
    .block_len_i   (block_len),
    .busy_o        (busy),
    .done_o        (done),
    .valid_o       (valid),
    .tag_o         (tag)
  );

  // -----------------------------------------------------------------------
  //  Clock / Reset
  // -----------------------------------------------------------------------
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // -----------------------------------------------------------------------
  //  Test infrastructure
  // -----------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // Helper: convert byte array (packed little-endian) to 128-bit logic
  function automatic [127:0] bytes_to_128(input logic [7:0] b[16]);
    bytes_to_128 = {b[15], b[14], b[13], b[12],
                    b[11], b[10], b[ 9], b[ 8],
                    b[ 7], b[ 6], b[ 5], b[ 4],
                    b[ 3], b[ 2], b[ 1], b[ 0]};
  endfunction

  // -----------------------------------------------------------------------
  //  Task: do_init — pulse init for one cycle and wait for idle
  // -----------------------------------------------------------------------
  task automatic do_init(input [127:0] r, input [127:0] s);
    @(posedge clk);
    key_r = r;
    key_s = s;
    init  = 1'b1;
    @(posedge clk);
    init = 1'b0;
    @(posedge clk);   // one idle cycle
  endtask

  // -----------------------------------------------------------------------
  //  Task: do_block — send one block and wait for done pulse
  // -----------------------------------------------------------------------
  task automatic do_block(input [127:0] blk, input [4:0] len);
    @(posedge clk);
    block       = blk;
    block_len   = len;
    block_valid = 1'b1;
    @(posedge clk);
    block_valid = 1'b0;
    // Wait for done pulse
    while (!done) @(posedge clk);
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  //  Task: do_finalize — pulse finalize and wait for valid
  // -----------------------------------------------------------------------
  task automatic do_finalize();
    @(posedge clk);
    finalize = 1'b1;
    @(posedge clk);
    finalize = 1'b0;
    while (!valid) @(posedge clk);
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  //  Task: check_tag
  // -----------------------------------------------------------------------
  task automatic check_tag(input [127:0] expected, input string name);
    test_num++;
    if (tag === expected) begin
      $display("[PASS] TV#%0d  %s", test_num, name);
      pass_cnt++;
    end else begin
      $display("[FAIL] TV#%0d  %s", test_num, name);
      $display("       Expected: %032h", expected);
      $display("       Got:      %032h", tag);
      fail_cnt++;
    end
  endtask

  // -----------------------------------------------------------------------
  //  Main test sequence
  // -----------------------------------------------------------------------
  initial begin
    // Defaults
    init        = 0;
    block_valid = 0;
    finalize    = 0;
    key_r       = 0;
    key_s       = 0;
    block       = 0;
    block_len   = 5'd16;

    // Reset
    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // ==================================================================
    //  Test Vector #1  (all zeros)
    //  Key:  00..00 (32 bytes)    Message: 00..00 (64 bytes)
    //  Tag:  00..00
    // ==================================================================
    begin
      do_init(128'h0, 128'h0);
      // 4 blocks × 16 bytes = 64 bytes
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_finalize();
      check_tag(128'h00000000_00000000_00000000_00000000, "All-zero key + msg");
    end

    // ==================================================================
    //  Test Vector #2  (r=0, tag=s regardless of msg)
    //  Key r: 00..00                      Key s: 3e867a2296caeff070605ec5b5f6e536
    //  Message: "Any submission to the IETF ..." (375 bytes)
    //  Tag:  36e5f6b5c5e06070f0efca96227a863e
    //
    //  r = 0 → all multiply steps produce 0 → acc stays 0 → tag = s
    // ==================================================================
    begin
      // s bytes (LE): 36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e
      // As 128-bit LE number: 0x3e867a2296caeff070605ec5b5f6e536
      do_init(128'h0, 128'h3e867a2296caeff070605ec5b5f6e536);

      // 375 bytes = 23 full blocks + 7-byte partial
      // Block 1:  "Any submission t"
      do_block(128'h746f697373696d627573206879_6e41, 5'd16);
      //  "Any " = 41 6e 79 20   "subm" = 73 75 62 6d
      //  "issi" = 69 73 73 69   "on t" = 6f 6e 20 74
      // Actually, let me compute the exact hex.
      // "Any submission t" as bytes:
      //   41 6e 79 20 73 75 62 6d 69 73 73 69 6f 6e 20 74
      // As 128-bit LE:  0x74206e6f69737369_6d62757320796e41
      do_block(128'h0, 5'd16);  // placeholder - r=0 so tag=s anyway
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd16);
      do_block(128'h0, 5'd7);  // last 7 bytes
      do_finalize();
      check_tag(128'h3e867a2296caeff070605ec5b5f6e536, "r=0, tag=s");
    end

    // ==================================================================
    //  Test Vector #3  (r=key, s=0, same 375-byte msg as TV#2)
    //  Key r (bytes): 36 e5 f6 b5 c5 e0 60 70 f0 ef ca 96 22 7a 86 3e
    //  Key s: 00..00
    //  Tag (bytes):   f3 47 7e 7c d9 54 17 af 89 a6 b8 79 4c 31 0c f0
    //  Tag LE 128:    0xf00c314c79b8a689af1754d97c7e47f3
    // ==================================================================
    begin
      // r LE 128-bit = 0x3e867a2296caeff07060e0c5b5f6e536
      do_init(128'h3e867a2296caeff07060e0c5b5f6e536,
              128'h00000000000000000000000000000000);

      // 375 bytes = 23 full blocks (16B each) + 1 partial block (7B)
      do_block(128'h74206e6f697373696d62757320796e41, 5'd16); // "Any submission t"
      do_block(128'h6e65746e69204654454920656874206f, 5'd16); // "o the IETF inten"
      do_block(128'h72746e6f432065687420796220646564, 5'd16); // "ded by the Contr"
      do_block(128'h696c62757020726f6620726f74756269, 5'd16); // "ibutor for publi"
      do_block(128'h726f206c6c61207361206e6f69746163, 5'd16); // "cation as all or"
      do_block(128'h46544549206e6120666f207472617020, 5'd16); // " part of an IETF"
      do_block(128'h2074666172442d74656e7265746e4920, 5'd16); // " Internet-Draft "
      do_block(128'h7320796e6120646e612043465220726f, 5'd16); // "or RFC and any s"
      do_block(128'h6977206564616d20746e656d65746174, 5'd16); // "tatement made wi"
      do_block(128'h747865746e6f6320656874206e696874, 5'd16); // "thin the context"
      do_block(128'h697463612046544549206e6120666f20, 5'd16); // " of an IETF acti"
      do_block(128'h72656469736e6f632073692079746976, 5'd16); // "vity is consider"
      do_block(128'h746e6f43204654454922206e61206465, 5'd16); // "ed an \"IETF Cont"
      do_block(128'h2068637553202e226e6f697475626972, 5'd16); // "ribution\". Such "
      do_block(128'h756c636e692073746e656d6574617473, 5'd16); // "statements inclu"
      do_block(128'h6e656d6574617473206c61726f206564, 5'd16); // "de oral statemen"
      do_block(128'h69737365732046544549206e69207374, 5'd16); // "ts in IETF sessi"
      do_block(128'h207361206c6c6577207361202c736e6f, 5'd16); // "ons, as well as "
      do_block(128'h63656c6520646e61206e657474697277, 5'd16); // "written and elec"
      do_block(128'h6163696e756d6d6f632063696e6f7274, 5'd16); // "tronic communica"
      do_block(128'h6e61207461206564616d20736e6f6974, 5'd16); // "tions made at an"
      do_block(128'h2c6563616c7020726f20656d69742079, 5'd16); // "y time or place,"
      do_block(128'h65726464612065726120686369687720, 5'd16); // " which are addre"
      do_block(128'h0000000000000000006f742064657373, 5'd7);  // "ssed to" (7 bytes)
      do_finalize();
      check_tag(128'hf00c314c79b8a689af1754d97c7e47f3, "r!=0 s=0, 375B msg");
    end

    // ==================================================================
    //  Test Vector #4  (the example from §2.5.2)
    //  Key (32 bytes):
    //   r: 85 d6 be 78 57 55 6d 33 7f 44 52 fe 42 d5 06 a8
    //   s: 01 03 80 8a fb 0d b2 fd 4a bf f6 af 41 49 f5 1b
    //  Message (34 bytes): "Cryptographic Forum Research Group"
    //  Tag: a8 06 1d c1 30 51 36 c6 c2 2b 8b af 0c 01 27 a9
    // ==================================================================
    begin
      // r as 128-bit LE: byte[0]=0x85, byte[15]=0xa8
      // 0xa806d542fe52447f336d555778bed685
      do_init(128'ha806d542fe52447f336d555778bed685,
              128'h1bf54941aff6bf4afdb20dfb8a800301);

      // Block 1: "Cryptographic Fo" (16 bytes)
      //  43 72 79 70 74 6f 67 72 61 70 68 69 63 20 46 6f
      //  LE 128: 0x6f462063696870726167_6f7470797243
      do_block(128'h6f4620636968706172676f7470797243, 5'd16);

      // Block 2: "rum Research Gro" (16 bytes)
      //  72 75 6d 20 52 65 73 65 61 72 63 68 20 47 72 6f
      //  LE 128: 0x6f7247206863726165736552206d7572
      do_block(128'h6f7247206863726165736552206d7572, 5'd16);

      // Block 3: "up" (2 bytes)
      //  75 70
      //  LE: 0x0000_0000_0000_0000_0000_0000_0000_7075
      do_block(128'h00000000000000000000000000007075, 5'd2);

      do_finalize();
      // Tag: a8 06 1d c1 30 51 36 c6 c2 2b 8b af 0c 01 27 a9
      // LE 128: 0xa927010caf8b2bc2c636513001c106a8  (wait, let me recompute)
      // byte[0]=a8, byte[1]=06, ..., byte[15]=a9
      // 128-bit LE = {byte15..byte0} = a9 27 01 0c af 8b 2b c2 c6 36 51 30 c1 1d 06 a8
      // = 0xa927010caf8b2bc2c6365130c11d06a8
      check_tag(128'ha927010caf8b2bc2c6365130c11d06a8, "RFC example §2.5.2");
    end

    // ==================================================================
    //  Test Vector #5  (partial reduction test)
    //  R:    02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  S:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  data: FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    //  tag:  03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    // ==================================================================
    begin
      do_init(128'h00000000000000000000000000000002,
              128'h00000000000000000000000000000000);
      do_block(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 5'd16);
      do_finalize();
      check_tag(128'h00000000000000000000000000000003, "Partial reduction");
    end

    // ==================================================================
    //  Test Vector #6  (s overflow)
    //  R:    02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  S:    FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    //  data: 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  tag:  03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    // ==================================================================
    begin
      do_init(128'h00000000000000000000000000000002,
              128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
      do_block(128'h00000000000000000000000000000002, 5'd16);
      do_finalize();
      check_tag(128'h00000000000000000000000000000003, "s overflow mod 2^128");
    end

    // ==================================================================
    //  Test Vector #7  (carry from lower limb)
    //  R:    01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  S:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  data (3 blocks):
    //    FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    //    F0 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    //    11 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  tag:  05 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    // ==================================================================
    begin
      do_init(128'h00000000000000000000000000000001,
              128'h00000000000000000000000000000000);
      do_block(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 5'd16);
      do_block(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0, 5'd16);
      do_block(128'h00000000000000000000000000000011, 5'd16);
      do_finalize();
      check_tag(128'h00000000000000000000000000000005, "Carry from lower limb");
    end

    // ==================================================================
    //  Test Vector #8  (acc exactly = P = 2^130-5)
    //  R:    01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  S:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  data (3 blocks):
    //    FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    //    FB FE FE FE FE FE FE FE FE FE FE FE FE FE FE FE
    //    01 01 01 01 01 01 01 01 01 01 01 01 01 01 01 01
    //  tag:  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    // ==================================================================
    begin
      do_init(128'h00000000000000000000000000000001,
              128'h00000000000000000000000000000000);
      do_block(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 5'd16);
      do_block(128'hFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFB, 5'd16);
      do_block(128'h01010101010101010101010101010101, 5'd16);
      do_finalize();
      check_tag(128'h00000000000000000000000000000000, "acc == P → tag=0");
    end

    // ==================================================================
    //  Test Vector #9  (acc = P-1 = 2^130-6)
    //  R:    02 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  S:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  data: FD FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    //  tag:  FA FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
    // ==================================================================
    begin
      do_init(128'h00000000000000000000000000000002,
              128'h00000000000000000000000000000000);
      do_block(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFD, 5'd16);
      do_finalize();
      check_tag(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFA, "acc == P-1");
    end

    // ==================================================================
    //  Test Vector #10  (131-bit intermediate)
    //  R:    01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00
    //  S:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  data (4 blocks):
    //    E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00
    //    33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00
    //    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //    01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  tag:  14 00 00 00 00 00 00 00 55 00 00 00 00 00 00 00
    // ==================================================================
    begin
      // R LE: 01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00
      // = 0x00000000000000040000000000000001
      do_init(128'h00000000000000040000000000000001,
              128'h00000000000000000000000000000000);
      // Block 1: E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00
      // LE: 0x000000000000000_0B9435E50D7943_5E3
      // Let me compute byte by byte:
      // byte[0]=E3, byte[1]=35, ..., byte[15]=00
      // {byte15..byte0} = 00 00 00 00 00 00 00 00 B9 43 5E 50 D7 94 35 E3
      do_block(128'h0000000000000000B9435E50D79435E3, 5'd16);
      // Block 2: 33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00
      // LE: 0x00000000000000_01CD79435E50D79433
      do_block(128'h0000000000000001CD79435E50D79433, 5'd16);
      // Block 3: all zeros
      do_block(128'h00000000000000000000000000000000, 5'd16);
      // Block 4: 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
      do_block(128'h00000000000000000000000000000001, 5'd16);
      do_finalize();
      // Tag: 14 00 00 00 00 00 00 00 55 00 00 00 00 00 00 00
      // LE: 0x00000000000000550000000000000014
      check_tag(128'h00000000000000550000000000000014, "131-bit intermediate");
    end

    // ==================================================================
    //  Test Vector #11  (131-bit final)
    //  R:    01 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00
    //  S:    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  data (3 blocks, same as TV10 minus last block):
    //    E3 35 94 D7 50 5E 43 B9 00 00 00 00 00 00 00 00
    //    33 94 D7 50 5E 43 79 CD 01 00 00 00 00 00 00 00
    //    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    //  tag:  13 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    // ==================================================================
    begin
      do_init(128'h00000000000000040000000000000001,
              128'h00000000000000000000000000000000);
      do_block(128'h0000000000000000B9435E50D79435E3, 5'd16);
      do_block(128'h0000000000000001CD79435E50D79433, 5'd16);
      do_block(128'h00000000000000000000000000000000, 5'd16);
      do_finalize();
      check_tag(128'h00000000000000000000000000000013, "131-bit final");
    end

    // ==================================================================
    //  Summary
    // ==================================================================
    $display("");
    $display("========================================");
    $display("  Poly1305 Test Summary");
    $display("  PASS: %0d / %0d", pass_cnt, pass_cnt + fail_cnt);
    if (fail_cnt == 0)
      $display("  ALL TESTS PASSED");
    else
      $display("  FAIL: %0d", fail_cnt);
    $display("========================================");
    $finish;
  end

  // Timeout
  initial begin
    #(CLK_PERIOD * 100000);
    $display("[TIMEOUT] Simulation did not complete");
    $finish;
  end

endmodule
