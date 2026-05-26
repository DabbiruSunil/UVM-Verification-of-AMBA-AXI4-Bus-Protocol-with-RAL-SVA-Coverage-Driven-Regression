`include "uvm_macros.svh"
import uvm_pkg::*;

// ============================================================
// PACKAGE — all UVM classes in dependency order
// ============================================================
package axi4_pkg;
  `include "uvm_macros.svh"
  import uvm_pkg::*;

  // ----------------------------------------------------------
  // 1. Transaction
  // ----------------------------------------------------------
  typedef enum logic [1:0] {FIXED, INCR, WRAP} burst_t;

  class axi4_seq_item extends uvm_sequence_item;
    `uvm_object_utils(axi4_seq_item)
    rand logic [31:0] addr;
    rand logic [7:0]  burst_len;   // AWLEN/ARLEN (beats-1)
    rand burst_t      burst_type;
    rand logic [31:0] data[];
    rand logic        is_write;
    rand logic [1:0]  lock;
    rand logic [3:0]  qos;
    logic [1:0]       resp;        // captured response

    constraint c_len  { burst_len inside {0,1,3,7,15}; }
    constraint c_addr { addr[1:0] == 2'b00; }          // word-aligned
    constraint c_data { data.size() == burst_len+1; }
    constraint c_qos  { qos inside {0,4,8,15}; }

    function new(string name="axi4_seq_item");
      super.new(name);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 2. Sequences
  // ----------------------------------------------------------
  // Base
  class axi4_base_seq extends uvm_sequence #(axi4_seq_item);
    `uvm_object_utils(axi4_base_seq)
    function new(string name="axi4_base_seq"); super.new(name); endfunction
  endclass

  // Random write-read
  class axi4_rand_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_rand_seq)
    int unsigned num_txns = 20;
    function new(string name="axi4_rand_seq"); super.new(name); endfunction
    task body();
      axi4_seq_item txn;
      repeat(num_txns) begin
        txn = axi4_seq_item::type_id::create("txn");
        start_item(txn);
        if (!txn.randomize()) `uvm_fatal("RAND","Randomization failed")
        finish_item(txn);
      end
    endtask
  endclass

  // Targeted: error injection (forces DECERR via high address)
  class axi4_error_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_error_seq)
    function new(string name="axi4_error_seq"); super.new(name); endfunction
    task body();
      axi4_seq_item txn;
      txn = axi4_seq_item::type_id::create("err_txn");
      start_item(txn);
      if (!txn.randomize() with {
        addr      == 32'hDEAD_0000;  // out-of-range -> DECERR from slave
        is_write  == 1;
        burst_len == 0;
      }) `uvm_fatal("RAND","Error seq rand failed")
      finish_item(txn);
    endtask
  endclass

  // Exclusive access sequence
  class axi4_exclusive_seq extends axi4_base_seq;
    `uvm_object_utils(axi4_exclusive_seq)
    function new(string name="axi4_exclusive_seq"); super.new(name); endfunction
    task body();
      axi4_seq_item txn;
      // Exclusive read
      txn = axi4_seq_item::type_id::create("excl_rd");
      start_item(txn);
      void'(txn.randomize() with { is_write==0; lock==2'b01; burst_len==0; });
      finish_item(txn);
      // Exclusive write to same address
      txn = axi4_seq_item::type_id::create("excl_wr");
      start_item(txn);
      void'(txn.randomize() with { is_write==1; lock==2'b01; burst_len==0; });
      finish_item(txn);
    endtask
  endclass

  // ----------------------------------------------------------
  // 3. Driver
  // ----------------------------------------------------------
  class axi4_driver extends uvm_driver #(axi4_seq_item);
    `uvm_component_utils(axi4_driver)
    virtual axi4_if #(32,32) vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual axi4_if #(32,32))::get(
            this, "", "vif", vif))
        `uvm_fatal("CFG","No VIF")
    endfunction

    task run_phase(uvm_phase phase);
      axi4_seq_item txn;
      forever begin
        seq_item_port.get_next_item(txn);
        if (txn.is_write) drive_write(txn);
        else               drive_read(txn);
        seq_item_port.item_done();
      end
    endtask

    task drive_write(axi4_seq_item txn);
      @(posedge vif.clk);
      vif.awaddr  <= txn.addr;
      vif.awlen   <= txn.burst_len;
      vif.awburst <= txn.burst_type;
      vif.awlock  <= txn.lock;
      vif.awqos   <= txn.qos;
      vif.awvalid <= 1;
      @(posedge vif.clk iff vif.awready);
      vif.awvalid <= 0;
      foreach(txn.data[i]) begin
        vif.wdata  <= txn.data[i];
        vif.wstrb  <= '1;
        vif.wlast  <= (i == txn.burst_len);
        vif.wvalid <= 1;
        @(posedge vif.clk iff vif.wready);
      end
      vif.wvalid <= 0; vif.wlast <= 0;
      vif.bready <= 1;
      @(posedge vif.clk iff vif.bvalid);
      txn.resp = vif.bresp;
      vif.bready <= 0;
    endtask

    task drive_read(axi4_seq_item txn);
      @(posedge vif.clk);
      vif.araddr  <= txn.addr;
      vif.arlen   <= txn.burst_len;
      vif.arburst <= txn.burst_type;
      vif.arlock  <= txn.lock;
      vif.arqos   <= txn.qos;
      vif.arvalid <= 1;
      @(posedge vif.clk iff vif.arready);
      vif.arvalid <= 0;
      vif.rready  <= 1;
      txn.data = new[txn.burst_len+1];
      for (int i=0; i<=txn.burst_len; i++) begin
        @(posedge vif.clk iff vif.rvalid);
        txn.data[i] = vif.rdata;
        txn.resp    = vif.rresp;
      end
      vif.rready <= 0;
    endtask
  endclass

  // ----------------------------------------------------------
  // 4. Monitor
  // ----------------------------------------------------------
  class axi4_monitor extends uvm_monitor;
    `uvm_component_utils(axi4_monitor)
    virtual axi4_if #(32,32) vif;
    uvm_analysis_port #(axi4_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(virtual axi4_if #(32,32))::get(
            this, "", "vif", vif))
        `uvm_fatal("CFG","Monitor: No VIF")
    endfunction

    task run_phase(uvm_phase phase);
      axi4_seq_item txn;
      forever begin
        txn = axi4_seq_item::type_id::create("mon_txn");
        // Capture write address
        @(posedge vif.clk iff (vif.awvalid && vif.awready));
        txn.addr       = vif.awaddr;
        txn.burst_len  = vif.awlen;
        txn.burst_type = burst_t'(vif.awburst);
        txn.lock       = vif.awlock;
        txn.qos        = vif.awqos;
        txn.is_write   = 1;
        txn.data       = new[vif.awlen+1];
        for (int i=0; i<=txn.burst_len; i++) begin
          @(posedge vif.clk iff (vif.wvalid && vif.wready));
          txn.data[i] = vif.wdata;
        end
        @(posedge vif.clk iff vif.bvalid);
        txn.resp = vif.bresp;
        ap.write(txn);
      end
    endtask
  endclass

// ----------------------------------------------------------
  // 5. Functional Coverage Collector
  // ----------------------------------------------------------
  class axi4_coverage extends uvm_subscriber #(axi4_seq_item);
    `uvm_component_utils(axi4_coverage)

    axi4_seq_item item;  // ← MOVED TO TOP, before covergroup

covergroup axi4_cg with function sample(axi4_seq_item t);
      cp_burst: coverpoint t.burst_type {
        bins burst_fixed  = {FIXED};
        bins burst_incr   = {INCR};
        bins burst_wrap   = {WRAP};
      }
      cp_len: coverpoint t.burst_len {
        bins len_single = {0};
        bins len_short  = {[1:3]};
        bins len_med    = {[4:7]};    // ← was "medium" → renamed
        bins len_long   = {[8:15]};   // ← was "long_b" → renamed
      }
      cp_resp: coverpoint t.resp {
        bins resp_okay   = {2'b00};
        bins resp_slverr = {2'b10};
        bins resp_decerr = {2'b11};
      }
      cp_qos: coverpoint t.qos {
        bins qos_low  = {[0:3]};
        bins qos_mid  = {[4:11]};
        bins qos_high = {[12:15]};
      }
      cp_lock: coverpoint t.lock {
        bins lock_normal    = {2'b00};
        bins lock_exclusive = {2'b01};
      }
      cx_burst_len: cross cp_burst, cp_len;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      axi4_cg = new();
    endfunction

    function void write(axi4_seq_item t);
      item = t;
      axi4_cg.sample(t);  // ← pass t directly into sample()
    endfunction

  endclass
  // ----------------------------------------------------------
  // 6. Scoreboard (with reference memory model)
  // ----------------------------------------------------------
  class axi4_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi4_scoreboard)
    uvm_analysis_imp #(axi4_seq_item, axi4_scoreboard) analysis_export;

    logic [31:0] ref_mem [logic [31:0]];  // associative array = reference model
    int pass_cnt, fail_cnt;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      analysis_export = new("analysis_export", this);
    endfunction

    function void write(axi4_seq_item txn);
      if (txn.is_write) begin
        foreach(txn.data[i])
          ref_mem[txn.addr + i*4] = txn.data[i];
        if (txn.resp == 2'b00) begin
          pass_cnt++;
          `uvm_info("SB", $sformatf("WRITE OK  addr=0x%0h data[0]=0x%0h",
            txn.addr, txn.data[0]), UVM_MEDIUM)
        end else begin
          fail_cnt++;
          `uvm_error("SB", $sformatf("WRITE ERR  resp=0b%02b addr=0x%0h",
            txn.resp, txn.addr))
        end
      end else begin
        foreach(txn.data[i]) begin
          logic [31:0] exp_data;
          if (ref_mem.exists(txn.addr + i*4)) begin
            exp_data = ref_mem[txn.addr + i*4];
            if (txn.data[i] === exp_data) begin
              pass_cnt++;
              `uvm_info("SB", $sformatf("READ  OK  addr=0x%0h got=0x%0h",
                txn.addr, txn.data[i]), UVM_MEDIUM)
            end else begin
              fail_cnt++;
              `uvm_error("SB", $sformatf(
                "READ MISMATCH addr=0x%0h exp=0x%0h got=0x%0h",
                txn.addr, exp_data, txn.data[i]))
            end
          end
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SB", $sformatf(
        "=== Scoreboard Report === PASS:%0d  FAIL:%0d",
        pass_cnt, fail_cnt), UVM_NONE)
    endfunction
  endclass

  // ----------------------------------------------------------
  // 7. RAL Model (Register Abstraction Layer)
  // ----------------------------------------------------------
  class axi4_ctrl_reg extends uvm_reg;
    `uvm_object_utils(axi4_ctrl_reg)
    uvm_reg_field enable;
    uvm_reg_field mode;

    function new(string name="axi4_ctrl_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      enable = uvm_reg_field::type_id::create("enable");
      mode   = uvm_reg_field::type_id::create("mode");
      enable.configure(this, 1, 0, "RW", 0, 1'h0, 1, 1, 0);
      mode.configure(this,   3, 1, "RW", 0, 3'h0, 1, 1, 0);
    endfunction
  endclass

  class axi4_reg_block extends uvm_reg_block;
    `uvm_object_utils(axi4_reg_block)
    rand axi4_ctrl_reg ctrl;

    function new(string name="axi4_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      ctrl = axi4_ctrl_reg::type_id::create("ctrl");
      ctrl.build();
      ctrl.configure(this, null, "ctrl");
      default_map = create_map("default_map", 'h0, 4, UVM_LITTLE_ENDIAN);
      default_map.add_reg(ctrl, 'h0, "RW");
      lock_model();
    endfunction
  endclass

  // ----------------------------------------------------------
  // 8. Agent
  // ----------------------------------------------------------
  class axi4_agent extends uvm_agent;
    `uvm_component_utils(axi4_agent)
    axi4_driver    drv;
    axi4_monitor   mon;
    uvm_sequencer #(axi4_seq_item) seqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv  = axi4_driver::type_id::create("drv", this);
      mon  = axi4_monitor::type_id::create("mon", this);
      seqr = uvm_sequencer #(axi4_seq_item)::type_id::create("seqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 9. Virtual Sequencer
  // ----------------------------------------------------------
  class axi4_virtual_seqr extends uvm_sequencer;
    `uvm_component_utils(axi4_virtual_seqr)
    uvm_sequencer #(axi4_seq_item) master_seqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  // ----------------------------------------------------------
  // 10. Environment
  // ----------------------------------------------------------
  class axi4_env extends uvm_env;
    `uvm_component_utils(axi4_env)
    axi4_agent         master;
    axi4_scoreboard    sb;
    axi4_coverage      cov;
    axi4_virtual_seqr  vseqr;
    axi4_reg_block     ral;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      master = axi4_agent::type_id::create("master", this);
      sb     = axi4_scoreboard::type_id::create("sb", this);
      cov    = axi4_coverage::type_id::create("cov", this);
      vseqr  = axi4_virtual_seqr::type_id::create("vseqr", this);
      ral    = axi4_reg_block::type_id::create("ral");
      ral.build();
      `uvm_info("ENV","RAL model built", UVM_NONE)
    endfunction

    function void connect_phase(uvm_phase phase);
      master.mon.ap.connect(sb.analysis_export);
      master.mon.ap.connect(cov.analysis_export);
      vseqr.master_seqr = master.seqr;
    endfunction
  endclass

  // ----------------------------------------------------------
  // 11. Tests
  // ----------------------------------------------------------
  // Base test
  class axi4_base_test extends uvm_test;
    `uvm_component_utils(axi4_base_test)
    axi4_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = axi4_env::type_id::create("env", this);
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
      `uvm_info("TEST","=== Topology ===", UVM_NONE)
      uvm_top.print_topology();
    endfunction

    function void report_phase(uvm_phase phase);
      uvm_report_server svr = uvm_report_server::get_server();
      if (svr.get_severity_count(UVM_FATAL) +
          svr.get_severity_count(UVM_ERROR) == 0)
        `uvm_info("TEST","*** TEST PASSED ***", UVM_NONE)
      else
        `uvm_info("TEST","*** TEST FAILED ***", UVM_NONE)
    endfunction
  endclass

  // Regression test (random + exclusive + error injection)
  class axi4_regression_test extends axi4_base_test;
    `uvm_component_utils(axi4_regression_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      axi4_rand_seq      rand_seq;
      axi4_exclusive_seq excl_seq;
      axi4_error_seq     err_seq;

      phase.raise_objection(this);

      // Random write-read pairs
      rand_seq = axi4_rand_seq::type_id::create("rand_seq");
      rand_seq.num_txns = 30;
      rand_seq.start(env.master.seqr);

      // Exclusive access
      excl_seq = axi4_exclusive_seq::type_id::create("excl_seq");
      excl_seq.start(env.master.seqr);

      // Error injection
      err_seq = axi4_error_seq::type_id::create("err_seq");
      err_seq.start(env.master.seqr);

      #100;
      phase.drop_objection(this);
    endtask
  endclass

endpackage
// ============================================================
// TOP MODULE
// ============================================================
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi4_pkg::*;          // ← this MUST be here, outside module

module top;

  logic clk, rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
  end

  axi4_if #(32,32) bus (.clk(clk), .rst_n(rst_n));
  axi4_slave_mem #(32,32,256) dut (.bus(bus));

  initial #50000 $finish;

  initial begin
    uvm_config_db #(virtual axi4_if #(32,32))::set(
      null, "uvm_test_top.*", "vif", bus);
    run_test();              // ← remove the string argument entirely
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
  end

endmodule
