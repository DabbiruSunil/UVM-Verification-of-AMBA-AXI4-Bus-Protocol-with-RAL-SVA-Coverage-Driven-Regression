// ============================================================
// AXI4 Interface
// ============================================================
interface axi4_if #(parameter AW=32, DW=32) (input logic clk, rst_n);
  // Write address channel
  logic [AW-1:0]  awaddr;
  logic [7:0]     awlen;
  logic [2:0]     awsize;
  logic [1:0]     awburst;
  logic [1:0]     awlock;
  logic [3:0]     awqos;
  logic           awvalid, awready;

  // Write data channel
  logic [DW-1:0]  wdata;
  logic [DW/8-1:0] wstrb;
  logic           wlast, wvalid, wready;

  // Write response channel
  logic [1:0]     bresp;
  logic           bvalid, bready;

  // Read address channel
  logic [AW-1:0]  araddr;
  logic [7:0]     arlen;
  logic [2:0]     arsize;
  logic [1:0]     arburst;
  logic [1:0]     arlock;
  logic [3:0]     arqos;
  logic           arvalid, arready;

  // Read data channel
  logic [DW-1:0]  rdata;
  logic [1:0]     rresp;
  logic           rlast, rvalid, rready;

  // ---- SVA Protocol Assertions ----
  // VALID must not deassert before READY
  property aw_stable;
    @(posedge clk) disable iff (!rst_n)
    awvalid && !awready |=> awvalid;
  endproperty
  assert property (aw_stable) else $error("AWVALID deasserted before AWREADY");

  property ar_stable;
    @(posedge clk) disable iff (!rst_n)
    arvalid && !arready |=> arvalid;
  endproperty
  assert property (ar_stable) else $error("ARVALID deasserted before ARREADY");

  property w_stable;
    @(posedge clk) disable iff (!rst_n)
    wvalid && !wready |=> wvalid;
  endproperty
  assert property (w_stable) else $error("WVALID deasserted before WREADY");
endinterface

// ============================================================
// Simple AXI4 Slave Memory DUT (256 locations)
// ============================================================
module axi4_slave_mem #(parameter AW=32, DW=32, DEPTH=256)
  (axi4_if bus);

  logic [DW-1:0] mem [0:DEPTH-1];
  logic [AW-1:0] wr_addr;
  logic [7:0]    wr_len, wr_count;
  logic          wr_active;
  logic [AW-1:0] rd_addr;
  logic [7:0]    rd_len, rd_count;
  logic          rd_active;

  // defaults
  always_ff @(posedge bus.clk or negedge bus.rst_n) begin
    if (!bus.rst_n) begin
      bus.awready<=1; bus.wready<=0; bus.bvalid<=0; bus.bresp<=0;
      bus.arready<=1; bus.rvalid<=0; bus.rlast<=0;
      wr_active<=0; rd_active<=0; wr_count<=0; rd_count<=0;
    end else begin
      // --- Write address ---
      if (bus.awvalid && bus.awready) begin
        wr_addr   <= bus.awaddr;
        wr_len    <= bus.awlen;
        wr_count  <= 0;
        wr_active <= 1;
        bus.awready <= 0;
        bus.wready  <= 1;
      end
      // --- Write data ---
      if (bus.wvalid && bus.wready && wr_active) begin
        mem[wr_addr[$clog2(DEPTH)+1:2] + wr_count] <= bus.wdata;
        wr_count <= wr_count + 1;
        if (bus.wlast) begin
          bus.wready  <= 0;
          bus.bvalid  <= 1;
          bus.bresp   <= 2'b00;
          wr_active   <= 0;
          bus.awready <= 1;
        end
      end
      // --- Write response ---
      if (bus.bvalid && bus.bready) bus.bvalid <= 0;

      // --- Read address ---
      if (bus.arvalid && bus.arready) begin
        rd_addr   <= bus.araddr;
        rd_len    <= bus.arlen;
        rd_count  <= 0;
        rd_active <= 1;
        bus.arready <= 0;
      end
      // --- Read data ---
      if (rd_active && !bus.rvalid) begin
        bus.rdata  <= mem[rd_addr[$clog2(DEPTH)+1:2] + rd_count];
        bus.rresp  <= 2'b00;
        bus.rlast  <= (rd_count == rd_len);
        bus.rvalid <= 1;
      end
      if (bus.rvalid && bus.rready) begin
        if (bus.rlast) begin
          rd_active   <= 0;
          bus.rvalid  <= 0;
          bus.arready <= 1;
        end else begin
          rd_count   <= rd_count + 1;
          bus.rvalid <= 0;
        end
      end
    end
  end
endmodule
