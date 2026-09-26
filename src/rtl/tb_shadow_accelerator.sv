`timescale 1ns/1ps
`ifndef SHADOW_DUT_MODULE
`define SHADOW_DUT_MODULE shadow_top
`endif
module tb_shadow_accelerator;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic [11:0] awaddr=0, araddr=0;
  logic [31:0] wdata=0,rdata;
  logic [3:0] wstrb=0;
  logic awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
  wire awready,wready,bvalid,arready,rvalid,irq;
  wire [1:0] bresp,rresp;
  `SHADOW_DUT_MODULE dut(.fclk_clk0(clk),.fclk_reset0_n(rst_n),
    .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
    .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),.irq_f2p(irq));
  task automatic wr(input logic [11:0] addr,input logic [31:0] data,
                    input int skew=0,input logic [3:0] strb=15,input logic [1:0] response=0);
    fork
      begin
        repeat(skew==1 ? 3 : 0) @(posedge clk);
        @(negedge clk); awaddr=addr; awvalid=1;
        do @(posedge clk); while(!awready);
        @(negedge clk); awvalid=0;
      end
      begin
        repeat(skew==2 ? 3 : 0) @(posedge clk);
        @(negedge clk); wdata=data; wstrb=strb; wvalid=1;
        do @(posedge clk); while(!wready);
        @(negedge clk); wvalid=0;
      end
    join
    wait(bvalid);
    repeat(2) begin @(negedge clk); if(!bvalid || bresp!==response) $fatal(1,"write response %h addr %h",bresp,addr); end
    bready=1; @(negedge clk); bready=0;
  endtask
  task automatic rd(input logic [11:0] addr,output logic [31:0] value,input logic [1:0] response=0);
    @(negedge clk); araddr=addr; arvalid=1;
    do @(posedge clk); while(!arready);
    @(negedge clk); arvalid=0;
    wait(rvalid); value=rdata;
    repeat(2) begin @(negedge clk); if(!rvalid || rdata!==value || rresp!==response) $fatal(1,"read backpressure/response addr %h",addr); end
    rready=1; @(negedge clk); rready=0;
  endtask
  int fd, count, n, sat, err, scanned, polls;
  logic [63:0] expected_q;
  logic [31:0] ma[576],vx[24],ey[24],word,lo,hi,latency;
  initial begin
    #20000000; $fatal(1,"global simulation timeout");
  end
  initial begin
    repeat(25) @(negedge clk); rst_n=1; 
    rd('h05c,word); if(word!==32'h53484431) $fatal(1,"signature");
    wr('h00c,32'h12345678,1); wr('h00c,32'haabbccdd,2,4'b0101);
    rd('h00c,word); if(word!==32'h12bb56dd) $fatal(1,"WSTRB");
    wr('h00d,32'hffffffff,0,15,2); rd('h00c,word); if(word!==32'h12bb56dd) $fatal(1,"unaligned write");
    rd('hfff,word,2);
    rd('ha80,word,2); 
    fd=$fopen("shadow_vectors.txt","r"); if(!fd) $fatal(1,"missing HLS vectors");
    for(count=0;count<80;count++) begin
      scanned=$fscanf(fd,"%h %h %h %h",n,sat,err,expected_q);
      if(scanned!=4) $fatal(1,"vector header %0d",count);
      for(int i=0;i<576;i++) scanned=$fscanf(fd,"%h",ma[i]);
      for(int i=0;i<24;i++) scanned=$fscanf(fd,"%h",vx[i]);
      for(int i=0;i<24;i++) scanned=$fscanf(fd,"%h",ey[i]);
      for(int i=0;i<576;i++) wr('h100+4*i,ma[i],count%3);
      for(int i=0;i<24;i++) wr('ha00+4*i,vx[i],count%3);
      wr('h008,n); wr('h000,5);
      polls=0; word=0;
      while(!word[2] && polls<1000) begin rd('h004,word); polls++; end
      if(!word[2] || word[3]!==err[0] || word[4]!==sat[0] || !irq) $fatal(1,"status case %0d: %h",count,word);
      for(int i=0;i<24;i++) begin rd('ha80+4*i,word); if(word!==ey[i]) $fatal(1,"y case %0d row %0d got %h expected %h",count,i,word,ey[i]); end
      rd('hb00,lo); rd('hb04,hi); if({hi,lo}!==expected_q) $fatal(1,"quadratic case %0d got %h expected %h",count,{hi,lo},expected_q);
      rd('h058,latency);
      if(latency == 0 || latency > 100000) $fatal(1,"implausible HLS cycle count case %0d: %0d",count,latency);
      $display("PARITY case=%0d dim=%0d cycles=%0d",count,n,latency);
      wr('h000,0); if(irq) $fatal(1,"IRQ did not clear");
    end
    
    wr('h008,24); wr('h000,5); wr('h100,0,0,15,2); wr('h000,2);
    rd('h004,word); if(word!==1 || irq) $fatal(1,"cancel failed");
    $display("PASS: 80 HLS/VHDL parity cases; AXI skew, WSTRB, backpressure, guarded results, invalid access, IRQ clear, cancellation, measured cycles");
    $fclose(fd);
    fd=$fopen("shadow_test_pass.txt","w");
    $fdisplay(fd,"PASS 80 parity cases and AXI protocol tests");
    $fclose(fd);
    $finish;
  end
endmodule
