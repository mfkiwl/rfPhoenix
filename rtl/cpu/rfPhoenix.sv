`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2013-2022  Robert Finch, Waterloo
//    \  __ /    All rights reserved.
//     \/_//     robfinch<remove>@finitron.ca
//       ||
//
// BSD 3-Clause License
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//                                                                          
// ============================================================================

`define IS_SIM	1'b1

import rfPhoenixPkg::*;

module rfPhoenix(hartid_i, rst_i, clk_i, clk2x_i, clk2d_i, wc_clk_i, clock,
		nmi_i, irq_i, icause_i,
		vpa_o, vda_o, bte_o, cti_o, bok_i, cyc_o, stb_o, lock_o, ack_i,
    err_i, we_o, sel_o, adr_o, dat_i, dat_o, cr_o, sr_o, rb_i, state_o, trigger_o,
    wcause);
input [63:0] hartid_i;
input rst_i;
input clk_i;
input clk2x_i;
input clk2d_i;
input wc_clk_i;
input clock;					// MMU clock algorithm
input nmi_i;
(* MARK_DEBUG="TRUE" *)
input [2:0] irq_i;
(* MARK_DEBUG="TRUE" *)
input [8:0] icause_i;
output vpa_o;
output vda_o;
output [1:0] bte_o;
output [2:0] cti_o;
input bok_i;
output cyc_o;
output stb_o;
output reg lock_o;
input ack_i;
input err_i;
output we_o;
output [15:0] sel_o;
output [31:0] adr_o;
input [127:0] dat_i;
output [127:0] dat_o;
output cr_o;
output sr_o;
input rb_i;
output [5:0] state_o;
output reg trigger_o;
output CauseCode wcause;

parameter IC_LATENCY = 2;

wire clk_g = clk_i;
ExecuteBuffer [NTHREADS-1:0] eb;
ExecuteBuffer ebq [0:NTHREADS-1];

// The following var indicates that r0 has been written for the thread.
// Only one write of r0 is allowed, to set the value to zero.
reg [NTHREADS-1:0] rz;
reg [NTHREADS-1:0] gie;
Tid xrid,mc_rid,mc_rid1,mc_rid2,mc_rido;
wire dcndx_v,exndx_v,oundx_v,wbndx_v,itndx1_v;
reg itndx2_v,itndx_v;
reg [NTHREADS-1:0] rfndx1_v, rfndx2_v;
Tid dcndx,rfndx,itndx,itndx1,itndx2,exndx,oundx,wbndx,rfndx1,rfndx2;
reg xrid_v;
reg [NTHREADS-1:0] rfndx_v;
Tid mcv_ridi, mcv_rido;
Tid ithread, rthread, dthread, xthread, commit_thread;
reg rthread_v, dthread_v;
reg commit_wr, commit_wrv;
reg [15:0] commit_mask;
Regspec commit_tgt;
VecValue commit_bus;
Tid ip_thread, ip_thread1, ip_thread2, ip_thread3, ip_thread4, ip_thread5;
ThreadInfo_t [NTHREADS-1:0] thread;
ThreadInfo_t [NTHREADS-1:0] thread_hist [0:3];
reg [31:0] ip, ip2, ip3, ip4;
reg [NTHREADS-1:0] thread_busy;
CodeAddress iip, dip, ip_icline, ip_insn, ip1;
Instruction ir,dir,xir,mir,insn,mir1,mir2;
Instruction rf_insn;
Postfix pfx,irpfx,rf_pfx;
DecodeBus deco;
DecodeBus [NTHREADS-1:0] dco;
Regspec ra0,ra1,ra2,ra3,ra4;
Value rfo0, rfo1, rfo2, rfo3, rfo4;
Value ximm,mcimm;
ASID xasid;
VecValue vrfo0, vrfo1, vrfo2, vrfo3, vrfo4;
VecValue xa,xb,xc,xt,xm;
reg xta,xtb,xtt;
VecValue mca,mcb,mcc,mct,mcm;
VecValue mca1,mcb1,mcc1,mct1,mcm1;
VecValue mca2,mcb2,mcc2,mct2,mcm2;
reg [2:0] mca_busy;
Value res,mc_res,mc_res1,mc_res2;
VecValue vres,mc_vres,mc_vres1,mc_vres2;
wire mc_done, mcv_done;
wire mc_done1, mcv_done1;
wire mc_done2, mcv_done2;
wire ihit;
reg ihit2;
MemoryRequest memreq;
MemoryResponse memresp;
wire memreq_full;
reg memresp_fifo_rd;
wire memresp_fifo_empty;
wire memresp_fifo_v;
wire [pL1ICacheLineSize:0] ic_line;
reg [pL1ICacheLineSize:0] ic_line2;
wire ic_valid;
//reg [31:0] ptbr;
wire ipage_fault;
reg clr_ipage_fault;
wire itlbmiss;
reg clr_itlbmiss;
wire dce;
//reg [9:0] asid;
reg [1:0] omode [0:NTHREADS-1];
reg [NTHREADS-1:0] Usermode;
reg [NTHREADS-1:0] MUsermode;
wire takb;
wire [NTHREADS-1:0] ififo_almost_full;
reg [2:0] sp_sel [0:NTHREADS-1];
reg [2:0] sp_sel2;
reg [2:0] ic_sp_sel [0:NTHREADS-1];
reg [2:0] istk_depth [0:NTHREADS-1];
Instruction [NTHREADS-1:0] exc_bucket;
CodeAddress [NTHREADS-1:0] exc_ip;
CauseCode icause,dcause;
reg [7:0] tid;
CodeAddress last_adr;
reg [15:0] exv;
wire [25:0] ic_tag;
reg [25:0] ic_tag2;
ExecuteBuffer [NTHREADS-1:0] dcbuf;
ExecuteBuffer [NTHREADS-1:0] mceb;
reg [NTHREADS-1:0] mem_rollback, ou_rollback, rollback, rolledback1, rolledback2;
wire [127:0] mem_rollback_bitmaps [0:NTHREADS-1];
reg [127:0] ou_rollback_bitmaps [0:NTHREADS-1];
reg [127:0] rollback_bitmaps [0:NTHREADS-1];
CodeAddress [NTHREADS-1:0] rollback_ip;
reg [NTHREADS-1:0] rollback_ipv;
reg [NTHREADS-1:0] sb_will_issue, sb_issue;
wire [NTHREADS-1:0] sb_can_issue;
reg [NTHREADS-1:0] clr_ififo;
wire [NTHREADS-1:0] ififo_empty;
InstructionFetchbuf ic_ifb;
InstructionFetchbuf [NTHREADS-1:0] dc_ifb, dc1_ifb;

// CSRs
reg [31:0] cr0;
reg [31:0] ptbr [0:NTHREADS-1];
reg [9:0] asid [0:NTHREADS-1];
reg [31:0] hmask,xhmask;
Address badaddr [0:NTHREADS-1][0:3];
CauseCode cause [0:NTHREADS-1][0:3];
CodeAddress tvec [0:3];
reg [63:0] plStack [0:NTHREADS-1];
reg [63:0] pmStack [0:NTHREADS-1];
reg [255:0] ipStack [0:NTHREADS-1];
reg [31:0] status;
reg [31:0] tick;
reg [63:0] wc_time;
reg [31:0] wc_time_dat;
reg ld_time, clr_wc_time_irq;

genvar g;

function [5:0] fnSpSel;
input [3:0] thread;
input [5:0] i;
begin
	if (i==6'd31)
		case(sp_sel[thread])
		3'd1:	fnSpSel = 6'd44;
		3'd2:	fnSpSel = 6'd45;
		3'd3:	fnSpSel = 6'd46;
		3'd4:	fnSpSel = 6'd47;
		default:	fnSpSel = 6'd31;
		endcase
	else
		fnSpSel = i;
end
endfunction


wire [16:0] lfsr_o;
lfsr ulfs1
(	
	.rst(rst_i),
	.clk(clk_g),
	.ce(1'b1),
	.cyc(1'b0),
	.o(lfsr_o)
);

integer n5;
always_comb
	for (n5 = 0; n5 < NTHREADS; n5 = n5 + 1) begin
		omode[n5] = pmStack[n5][7:6];
		Usermode[n5] = omode[n5]==2'b00;
		MUsermode[n5] = omode[n5]==2'b00;
	end

integer n;
initial begin
	tid = 8'd1;
	rz = 'd0;
	gie = 'd0;
	ip = RSTIP;
	iip = RSTIP;
	ir = NOP;//_INSN;
	xir = NOP;//_INSN;
	mir = NOP;//_INSN;
	for (n = 0; n < NLANES; n = n + 1) begin
		xa[n] = 'd0;
		xb[n] = 'd0;
		xc[n] = 'd0;
		mca[n] = 'd0;
		mcb[n] = 'd0;
		mcc[n] = 'd0;
	end
	ximm = 'd0;
	mcimm = 'd0;
	ithread = 'd0;
	ip_thread = 'd0;
	mca_busy = 'd0;
	thread_busy = 'd0;
	for (n = 0; n < NTHREADS; n = n + 1)
		eb[n] = 'd0;
	rthread_v = 'd0;
	dthread_v = 'd0;
	memreq = 'd0;
end

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

wire memreq_wack;

rfPhoenixBiu ubiu
(
	.rst(rst_i),
	.clk(clk_g),
	.tlbclk(clk2x_i),
	.clock(clock),
	.UserMode(Usermode[0]),	// fix these
	.MUserMode(MUsermode[0]),
	.omode(omode[0]),
	.bounds_chk(),
	.pe(pe),
	.ip(ip),
	.ip_o(ip_icline),
	.ihit(ihit),
	.ifStall(1'b0),
	.ic_line(ic_line),
	.ic_valid(ic_valid),
	.ic_tag(ic_tag),
	.fifoToCtrl_i(memreq),
	.fifoToCtrl_full_o(memreq_full),
	.fifoToCtrl_wack(memreq_wack),
	.fifoFromCtrl_o(memresp),
	.fifoFromCtrl_rd(memresp_fifo_rd),
	.fifoFromCtrl_empty(memresp_fifo_empty),
	.fifoFromCtrl_v(memresp_fifo_v),
	.bok_i(bok_i),
	.bte_o(bte_o),
	.cti_o(cti_o),
	.vpa_o(vpa_o),
	.vda_o(vda_o),
	.cyc_o(cyc_o),
	.stb_o(stb_o),
	.ack_i(ack_i),
	.we_o(we_o),
	.sel_o(sel_o),
	.adr_o(adr_o),
	.dat_i(dat_i),
	.dat_o(dat_o),
	.sr_o(sr_o),
	.cr_o(cr_o),
	.rb_i(rb_i),
	.dce(dce),
	.keys(),//keys),
	.arange(),
	.ptbr(ptbr[0]),
	.ipage_fault(ipage_fault),
	.clr_ipage_fault(clr_ipage_fault),
	.itlbmiss(itlbmiss),
	.clr_itlbmiss(clr_itlbmiss),
	.rollback(mem_rollback),
	.rollback_bitmaps(mem_rollback_bitmaps)
);


rfPhoenix_decoder udec1
(
	.ifb(ic_ifb),
	.sp_sel(ic_ifb.sp_sel),
	.rz(rz[ip_thread5]),
	.deco(deco)
);


wire [3:0] mrt, ort;
ffo12 ufo9 (.i({11'd0,mem_rollback}), .o(mrt));
ffo12 ufo10 (.i({11'd0,ou_rollback}), .o(ort));
assign mem_rollback_thread = mrt;
assign ou_rollback_thread = ort;

generate begin : gScoreboard
for (g = 0; g < NTHREADS; g = g + 1) begin
	always_comb
	begin
		rollback[g] <= 'd0;
		rollback_bitmaps[g] <= 'd0;
		if (mem_rollback[g]) begin
			rollback[g] <= 1'b1;
			rollback_bitmaps[g] <= mem_rollback_bitmaps[g];
		end
		else if (ou_rollback[g]) begin
			rollback[g] <= 1'b1;
			rollback_bitmaps[g] <= ou_rollback_bitmaps[g];
		end
	end

	rfPhoenix_scoreboard uscb1
	(
		.rst(rst_i),
		.clk(clk_g),
		.db(dco[g]),
		.wb_v(eb[g].dec.rfwr),
		.wb_Rt(eb[g].dec.Rt),
		.will_issue(sb_will_issue[g]),
		.can_issue(sb_can_issue[g]),
		.rollback(rollback[g]),
		.rollback_bitmap(rollback_bitmaps[g])
	);

end
end
endgenerate
always_ff @(posedge clk_g)
	rolledback1 <= rollback;
always_ff @(posedge clk_g)
	rolledback2 <= rolledback1;

rfPhoenix_branch_eval ube1
(
	.ir(xir),
	.a(xa[0]),
	.b(xt[0]),
	.o(takb)
);

rfPhoenix_gp_regfile ugprs1
(
	.rst(rst_i),
	.clk(clk_g),
	.wr(commit_wr),
	.wthread(commit_thread),
	.wa(commit_tgt),
	.i(commit_bus[0]),
	.rthread(rfndx1),
	.ra0(ra0),
	.ra1(ra1),
	.ra2(ra2),
	.ra3(ra3),
	.ra4(ra4),
	.o0(rfo0),
	.o1(rfo1),
	.o2(rfo2),
	.o3(rfo3),
	.o4(rfo4)
);

rfPhoenix_vec_regfile ugprs2
(
	.rst(rst_i),
	.clk(clk_g),
	.wr(commit_wrv),
	.wthread(commit_thread),
	.wmask(commit_mask),
	.wa(commit_tgt),
	.i(commit_bus),
	.rthread(rthread),
	.ra0(ra0),
	.ra1(ra1),
	.ra2(ra2),
	.ra3(ra3),
	.ra4(ra4),
	.o0(vrfo0),
	.o1(vrfo1),
	.o2(vrfo2),
	.o3(),				// mask register port not needed here
	.o4(vrfo4)
);

rfPhoenixVecAlu uvalu1 (
	.ir(xir),
	.a(xa),
	.b(xb),
	.c(xc),
	.imm(ximm),
	.Ta(xta),
	.Tb(xtb),
	.Tt(xtt),
	.asid(xasid),
	.hmask(xhmask),
	.o(vres)
);

rfPhoenixMcVecAlu uvalu2 (
	.rst(rst_i),
	.clk(clk_g),
	.ir(mir),
	.a(mca),
	.b(mcb),
	.c(mcc),
	.imm(mcimm),
	.o(mc_vres),
	.done(mcv_done),
	.ridi(mcv_ridi),
	.rido(mcv_rido)
);

task tDisplayRegs;
integer n;
begin
`ifdef IS_SIM
	// The heirarchical reference to the register file here prevents synthsis
	// from using RAM resources to implement the register file. So this block
	// is enabled only for simulation.
	$display("GPRs");
	for (n = 0; n < NTHREADS*NREGS; n = n + 8) begin
		if ((n % NREGS)==0)
			$display("  Thread:%d", n / NREGS);
		$display("%s:%h  %s:%h  %s:%h  %s:%h  %s:%h  %s:%h  %s:%h  %s:%h  ",
			fnRegName(n), ugprs1.ugpr0.mem[n],
			fnRegName(n+1), ugprs1.ugpr0.mem[n+1],
			fnRegName(n+2), ugprs1.ugpr0.mem[n+2],
			fnRegName(n+3), ugprs1.ugpr0.mem[n+3],
			fnRegName(n+4), ugprs1.ugpr0.mem[n+4],
			fnRegName(n+5), ugprs1.ugpr0.mem[n+5],
			fnRegName(n+6), ugprs1.ugpr0.mem[n+6],
			fnRegName(n+7), ugprs1.ugpr0.mem[n+7]
			);
	end
	$display("");
`endif
end
endtask

task tDisplayEb;
integer n;
begin
	$display("  ExecuteBuffer:");
	for (n = 0; n < NTHREADS; n = n + 1) begin
		$display("  %d: %c%c%c%c%c ip=%h ir=%h oc=%0s res=%h a=%h b=%h c=%h t=%h i=%h", n[3:0],
			eb[n].v ? "v":"-",
			eb[n].decoded ? "d" : "-",
			eb[n].regfetched ? "r": "-",
			eb[n].out ? "o" : "-",
			eb[n].executed ? "x" : "-",
			eb[n].ifb.ip,
			eb[n].ifb.insn,
			eb[n].ifb.insn.any.opcode.name(),
			eb[n].res,
			eb[n].a,
			eb[n].b,
			eb[n].c,
			eb[n].t,
			eb[n].dec.imm
		);
	end
end
endtask

always_ff @(posedge clk_g)
begin
	/*
	if (rollback_ipv[ip_thread5]) begin//|rolledback1[ip_thread5]|rolledback2[ip_thread5]) begin
		ic_ifb.pfx <= NOP;
		ic_ifb.insn <= NOP;
		ic_ifb.ip <= thread[ip_thread5].ip;
		ic_ifb.sp_sel <= sp_sel[ip_thread5];
		ic_ifb.v <= 1'b0;
		ic_ifb.thread <= ip_thread5;
	end
	else
	*/
	begin
		{ic_ifb.pfx,ic_ifb.insn} <= ic_line >> {ip_icline[5:0],3'b0};
		ic_ifb.ip <= ip_icline;
		ic_ifb.v <= ihit2;
		ic_ifb.sp_sel <= sp_sel[ip_thread2];
		ic_ifb.thread <= ip_thread2;
	end
	if (irq_i > pmStack[ip_thread2][3:1] && gie[ip_thread2])
		ic_ifb.cause <= CauseCode'({irq_i,8'h00}|FLT_BRK);
	else
		ic_ifb.cause <= FLT_NONE;
end

always_ff @(posedge clk_g)
	ic_line2 <= ic_line;
always_ff @(posedge clk_g)
	ip_insn <= ip_icline;
always_ff @(posedge clk_g)
	ihit2 <= ihit;
always_ff @(posedge clk_g)
	ic_tag2 <= ic_tag;
reg [NTHREADS-1:0] wr_ififo;
generate begin
for (g = 0; g < NTHREADS; g = g + 1) begin
	always_comb
		clr_ififo[g] <= rollback[g];
	always_comb
		sb_will_issue[g] = g==dcndx && dcndx_v && !ififo_empty[g] && !sb_issue[g];
	always_ff @(posedge clk_g)
		sb_issue[g] <= sb_will_issue[g];
	always_comb
		wr_ififo[g] <= ic_ifb.thread==g;

	rfPhoenix_insn_fifo #(.DEP(16)) ufifo1
	(
		.rst(rst_i|rollback[g]),
		.clk(clk_g),
		.wr(wr_ififo[g]),
		.decin(rollback[g] ? 'd0 : deco),
		.ifbin(rollback[g] ? 'd0 : ic_ifb),
		.rd(sb_will_issue[g]),
		.decout(dco[g]),
		.ifbout(dc_ifb[g]),
		.cnt(),
		.full(),
		.almost_full(ififo_almost_full[g]),
		.empty(ififo_empty[g]),
		.v()
	);
	
end
end
endgenerate

wire [3:0] issue_num;
ffo12 uffo1 (.i({12'd0,sb_will_issue}), .o(issue_num));
assign rthread = issue_num[2:0];

integer n10;
task tDecode;
begin
	for (n10 = 0; n10 < NTHREADS; n10 = n10 + 1)
		rfndx1_v[n10] <= 1'b0;
	if (issue_num != 4'd15) begin
		if (rollback[rthread]) begin
			eb[rthread].v <= 1'b0;
			eb[rthread].ifb <= 'd0;
			eb[rthread].dec <= 'd0;
			eb[rthread].decoded <= 1'b0;
			eb[rthread].regfetched <= 1'b0;
			eb[rthread].executed <= 1'b0;
			ra0 <= 'd0;
			ra1 <= 'd0;
			ra2 <= 'd0;
			ra3 <= 'd0;
			ra4 <= 'd0;
			rfndx1 <= rthread;
			rfndx1_v[rthread] <= 1'b0;
		end
		else begin
			eb[rthread].v <= dc_ifb[rthread].v;
			eb[rthread].thread <= rthread;
			eb[rthread].ifb <= dc_ifb[rthread];
			$display("Decode %d:", rthread);
			$display("  dc_ifb[%d]=%h ra0=%d",rthread,dc_ifb[rthread], fnSpSel(rthread,dco[rthread].Ra.num));
			eb[rthread].dec <= dco[rthread];
			eb[rthread].decoded <= dc_ifb[rthread].v;
			eb[rthread].regfetched <= 1'b0;
			eb[rthread].executed <= 1'b0;
			ra0 <= fnSpSel(rthread,dco[rthread].Ra.num);
			ra1 <= fnSpSel(rthread,dco[rthread].Rb.num);
			ra2 <= fnSpSel(rthread,dco[rthread].Rc.num);
			ra3 <= dco[rthread].Rm.num;
			ra4 <= fnSpSel(rthread,dco[rthread].Rt.num);
			rfndx1 <= rthread;
			rfndx1_v[rthread] <= 1'b1;
		end
	end
end
endtask

always_ff @(posedge clk_g)
if (rst_i)
	itndx2 <= 'd0;
else
	itndx2 <= itndx1;
always_ff @(posedge clk_g)
if (rst_i)
	itndx2_v <= 1'b0;
else	
	itndx2_v <= itndx1_v;
/*
always_ff @(posedge clk_g)
if (rst_i) begin
	itndx <= 'd0;
	itndx_v <= 1'b0;
end
else begin
	if (!((itndx==itndx1 || itndx==itndx2) && itndx1_v && itndx2_v)) begin
		itndx <= itndx2;
		itndx_v <= itndx2_v;
	end
	else
		itndx_v <= 1'b0;
end
*/
always_comb
	itndx <= itndx1;
always_comb
	itndx_v <= itndx1_v;

always_ff @(posedge clk_g)
	rfndx2 <= rfndx1;
always_ff @(posedge clk_g)
	rfndx <= rfndx2;
always_ff @(posedge clk_g)
	rfndx2_v <= rfndx1_v;
always_ff @(posedge clk_g)
	rfndx_v <= rfndx2_v;

always_ff @(posedge clk_g)
if (rst_i) begin
	tReset();
end
else begin
	$display("=======================================");
	$display("=======================================");
	$display("Time %d", $time);
	$display("=======================================");
	$display("=======================================");
	$display("  exndx=%d exv=%h", exndx, exv);
	tDisplayRegs();
	tDisplayEb();
	tOnce();
	tInsnFetch();
	tDecode();
	tRegfetch();
	tExecute();
	tOut();
	tMemory();
	tWriteback();
end

task tReset;
integer n;
begin
	tid <= 8'd1;
	rz <= 'd0;
	gie <= 'd0;
	ip <= RSTIP;
	ip1 <= RSTIP;
	ip2 <= RSTIP;
	ip3 <= RSTIP;
	iip <= RSTIP;
	ir <= NOP;//_INSN;
	xir <= NOP;//_INSN;
	mir <= NOP;//_INSN;

	ximm <= 'd0;
	mcimm <= 'd0;
	for (n = 0; n < NLANES; n = n + 1) begin
		xa[n] <= 'd0;
		xb[n] <= 'd0;
		xc[n] <= 'd0;
		mca[n] <= 'd0;
		mcb[n] <= 'd0;
		mcc[n] <= 'd0;
	end
	for (n = 0; n < NTHREADS; n = n + 1) begin
		cause[n][0] <= FLT_NONE;
		cause[n][1] <= FLT_NONE;
		cause[n][2] <= FLT_NONE;
		cause[n][3] <= FLT_NONE;
		exc_bucket[n] <= 'd0;
		plStack[n] <= 64'hFFFFFFFFFFFFFFFF;
		pmStack[n] <= 64'hCECECECECECECECE;
		ipStack[n] <= {8{RSTIP}};
		sp_sel[n] <= 3'd3;
		ou_rollback_bitmaps[n] <= 'd0;
	end
	ithread <= 'd0;
	ip_thread <= 'd0;
	mca_busy <= 'd0;
	thread_busy <= 'd0;
	for (n = 0; n < NTHREADS; n = n + 1)
		eb[n] <= 'd0;
	rthread_v <= 'd1;
	dthread_v <= 'd1;
	memreq <= 'd0;
	last_adr <= 'd0;
	xrid <= 'd15;
	mc_rid <= 'd15;
	commit_thread <= 0;
	commit_mask <= 16'h0000;
	commit_wr <= 1'b0;
	commit_wrv <= 1'b0;
	commit_tgt <= 6'b0;
	for (n10 = 0; n10 < NLANES; n10 = n10 + 1)
		commit_bus[n10] <= 'd0;
	for (n10 = 0; n10 < NTHREADS; n10 = n10 + 1) begin
		thread[n10].imiss <= 1'b1;
		thread[n10].ip <= RSTIP;
		thread[n10].miss_ip <= RSTIP;
		rfndx1_v[n10] <= 1'b0;
	end
	ra0 <= 'd0;
	ra1 <= 'd0;
	ra2 <= 'd0;
	ra3 <= 'd0;
	ra4 <= 'd0;
	ip_thread1 <= 'd0;
	ip_thread2 <= 'd0;
	ip_thread3 <= 'd0;
	ip_thread4 <= 'd0;
	ip_thread5 <= 'd0;
end
endtask

task tOnce;
integer n;
begin
	memreq.wr <= 1'b0;
	memresp_fifo_rd <= 1'b1;
	for (n = 0; n < NTHREADS; n = n + 1) begin
		mem_rollback[n] <= 1'b0;
		ou_rollback[n] <= 1'b0;
		if (ou_rollback[n])
			ou_rollback_bitmaps[n] <= 'd0;
	end
end
endtask

task tSpSel;
input [3:0] thread;
input [5:0] i;
output [5:0] o;
begin
	if (i==6'd31)
		case(sp_sel[thread])
		3'd1:	o <= 6'd44;
		3'd2:	o <= 6'd45;
		3'd3:	o <= 6'd46;
		3'd4:	o <= 6'd47;
		default:	o <= 6'd31;
		endcase
	else
		o <= i;
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Schedulers
//
// The following selectors use round-robin selection.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

reg [NTHREADS-1:0] itsel;
generate begin : gItsel
	for (g = 0; g < NTHREADS; g = g + 1)
		always_comb
			itsel[g] = ~ififo_almost_full[g];// & ~thread[g].imiss;
end
endgenerate

rfPhoenix_round_robin_select rr1
(
	.rst(rst_i),
	.clk(clk_g),
	.i(itsel),
	.o(itndx1),
	.ov(itndx1_v)
);

reg [NTHREADS-1:0] dcsel;
generate begin : gDcsel
	for (g = 0; g < NTHREADS; g = g + 1)
		always_comb
			dcsel[g] = sb_can_issue[g] & ~eb[g].decoded & ~eb[g].v;
end
endgenerate

rfPhoenix_round_robin_select rr2
(
	.rst(rst_i),
	.clk(clk_g),
	.i(dcsel),
	.o(dcndx),
	.ov(dcndx_v)
);

reg [NTHREADS-1:0] exsel;
generate begin : gExsel
	for (g = 0; g < NTHREADS; g = g + 1)
		always_comb
			exsel[g] = eb[g].regfetched & ~eb[g].out;
end
endgenerate

rfPhoenix_round_robin_select rr3
(
	.rst(rst_i),
	.clk(clk_g),
	.i(exsel),
	.o(exndx),
	.ov(exndx_v)
);

// Pick an rob entry thats out.

// Copy into a bus, just wires.
reg [NTHREADS-1:0] ebout;
generate begin : gEbout
	for (g = 0; g < NTHREADS; g = g + 1)
		always_comb
			ebout[g] = eb[g].out;
end
endgenerate

rfPhoenix_round_robin_select rr4
(
	.rst(rst_i),
	.clk(clk_g),
	.i(ebout),
	.o(oundx),
	.ov(oundx_v)
);


// Pick a finished rob entry.

// Copy into a bus, just wires.
reg [NTHREADS-1:0] ebfin;
generate begin : gEbfin
	for (g = 0; g < NTHREADS; g = g + 1)
		always_comb
			ebfin[g] = eb[g].executed;
end
endgenerate

rfPhoenix_round_robin_select rr5
(
	.rst(rst_i),
	.clk(clk_g),
	.i(ebfin),
	.o(wbndx),
	.ov(wbndx_v)
);


// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// IF Stage
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

task tInsnFetch;
integer n;
begin
	begin
		// 2 cycle pipeline delay reading the I$.
		// 1 for tag lookup and way determination
		// 1 for cache line lookup
		if (itndx_v) begin
			ip <= thread[itndx].ip;
			ip1 <= ip;
			//thread[itndx].ip <= thread[itndx].ip + 4'd5;
			thread_hist[0][itndx] <= thread[itndx];
			for (n = 1; n < 4; n = n + 1)
				thread_hist[n][itndx] <= thread_hist[n-1][itndx];
			thread[itndx].ip <= thread[itndx].ip + 4'd5;
		end
		ip_thread1 <= itndx;			// tag lookup ip_thread1 lined up with ip
		ip_thread2 <= ip_thread1;	// data fetch
		ip_thread3 <= ip_thread2;	// ip_thread3 lined up with ip_icline
		ip_thread4 <= ip_thread3;
		ip_thread5 <= ip_thread4;

		$display("Insn Fetch %d:", ip_thread4);
		$display("  ip_insn=%h  insn=%h postfix=%h", ic_ifb.ip, ic_ifb.insn, ic_ifb.pfx);
		$display("  ip_thread4=%h", ip_thread4);
		for (n = 0; n < NTHREADS; n = n + 1)
			$display("  thread[%d].ip=%h", n[3:0], thread[n].ip);
		if (!ihit) begin
			$display("Miss %d ip=%h", ip_thread2, ip1);
			if (!thread[ip_thread2].imiss) begin
				thread[ip_thread2].imiss <= 1'b1;
				thread[ip_thread2].miss_ip <= ip1;
				thread[ip_thread2].ip <= ip1;
			end
			else
				thread[ip_thread2].ip <= thread[ip_thread2].miss_ip;
		end
		else begin
			if (thread[ip_thread2].imiss) begin
				thread[ip_thread2].ip <= thread[ip_thread2].miss_ip;
				thread[ip_thread2].imiss <= 1'b0;
				ic_ifb.v <= 1'b0;
			end	
			//if (thread[ip_thread3].imiss)
			$display(" thread2 ip=%h, ip1=%h", thread[ip_thread2].ip, ip1);
		end
		// On a miss, request a cache line load from the memory system. This
		// should eventually cause a hit for the thread.
		// The old cache line is passed back for the victim buffer.
		if (!ihit2) begin
			if (!memreq_full) begin
			//if (ip_icline[31:6] != last_adr[31:6])
				last_adr <= ip_icline;
				tid <= tid + 2'd1;
				memreq.tid <= tid;
				memreq.thread <= ip_thread3;
				memreq.wr <= 1'b1;
				memreq.func <= MR_ICACHE_LOAD;
				memreq.adr <= {ip_icline[31:6],6'd0};
				memreq.vcadr <= {ic_tag,6'b0};
				memreq.dat <= ic_line;
				memreq.sz <= ic_valid ? tetra : nul;
			end
		end
	end
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// DC Stage
// - decoding is handled by a decode module above.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// RF Stage
// Forces instructions to be ignored until the rollback target address is seen.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Value csro;
always_comb
	tReadCSR(csro,rfndx,eb[rfndx].dec.imm[13:0]);
	
task tRegf;
begin
	$display("Regfetch %d:", rfndx);
	$display("  ip=%h Ra%d=%h Rb=%d", eb[rfndx].ifb.ip, eb[rfndx].dec.Ra, rfo0, eb[rfndx].dec.Rb);
	//eb[rfndx].cause <= dcause;
	eb[rfndx].a <= eb[rfndx].dec.Ra.vec ? vrfo0 : {NLANES{rfo0}};
	eb[rfndx].b <= eb[rfndx].dec.Rb.vec ? vrfo1 : {NLANES{rfo1}};
	if (eb[rfndx].dec.csr)
		eb[rfndx].c <= {NLANES{csro}};
	else
		eb[rfndx].c <= eb[rfndx].dec.Rc.vec ? vrfo2 : {NLANES{rfo2}};
	eb[rfndx].mask <= rfo3;
	eb[rfndx].t <= eb[rfndx].dec.Rt.vec ? vrfo4 : {NLANES{rfo4}};
	eb[rfndx].regfetched <= eb[rfndx].v & ~rollback[rfndx];
	ou_rollback_bitmaps[rfndx][eb[rfndx].dec.Rt] <= 1'b1;
end
endtask

task tRegfetch;
begin
	if (rfndx_v[rfndx]) begin
		if (rollback_ipv[rfndx] && eb[rfndx].ifb.ip != rollback_ip[rfndx]) begin
			eb[rfndx].v <= 1'b0;
			eb[rfndx].dec.rfwr <= 1'b0;
			eb[rfndx].dec.vrfwr <= 1'b0;
			eb[rfndx].executed <= 1'b0;
		end
		else if (rollback_ipv[rfndx] && eb[rfndx].ifb.ip == rollback_ip[rfndx]) begin
			rollback_ipv <= 1'b0;
			tRegf();
		end
		else if ((eb[rfndx].decoded && !eb[rfndx].regfetched) || 1'b1) begin
			tRegf();
		end
	end
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// EX stage 
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

task tExLoad;
begin
	if (eb[exndx].dec.load) begin
		tid <= tid + 2'd1;
		memreq.tid <= tid;
		memreq.wr <= 1'b1;
		memreq.func <= eb[exndx].dec.loadu ? MR_LOADZ : MR_LOAD;
		if (eb[exndx].dec.ldr)
			memreq.func2 <= MR_LDR;
		memreq.sz <= eb[exndx].dec.memsz;
		memreq.asid = asid[exndx];
		case(eb[exndx].dec.memsz)
		byt:	memreq.sel <= 64'h1;
		wyde:	memreq.sel <= 64'h3;
		tetra:	memreq.sel <= 64'hF;
		vect:	memreq.sel <= 64'hFFFFFFFFFFFFFFFF;
		default:	memreq.sel <= 64'hF;
		endcase
		if (eb[exndx].dec.memsz==vect) begin
			if (eb[exndx].dec.loadr) begin
				memreq.func2 <= MR_LDV;
				memreq.sel <= 64'hFFFFFFFFFFFFFFFF;
				memreq.adr <= eb[exndx].a[0] + eb[exndx].dec.imm;
			end
			else begin
				memreq.sel <= 64'hF;
				memreq.adr <= eb[exndx].a[0] + eb[exndx].b[eb[exndx].step];
				if (eb[exndx].step != NLANES-1 && eb[exndx].dec.loadn)
					eb[exndx].step <= eb[exndx].step + 2'd1;
			end
		end
		else
			memreq.adr <= eb[exndx].dec.loadr ? eb[exndx].a[0] + eb[exndx].dec.imm : eb[exndx].a[0] + eb[exndx].b[0];
	end
end
endtask

task tExStore;
begin
	if (eb[exndx].dec.store) begin
		tid <= tid + 2'd1;
		memreq.tid <= tid;
		memreq.wr <= 1'b1;
		memreq.func <= MR_STORE;
		if (eb[exndx].dec.stc)
			memreq.func2 <= MR_STC;
		memreq.sz <= eb[exndx].dec.memsz;
		memreq.asid = asid[exndx];
		memreq.dat <= eb[exndx].t;
		case(eb[exndx].dec.memsz)
		byt:	memreq.sel <= 64'h1;
		wyde:	memreq.sel <= 64'h3;
		tetra:	memreq.sel <= 64'hF;
		default:	memreq.sel <= 64'hF;
		endcase
		// BIU works with 128-bit chunks for stores.
		if (eb[exndx].dec.memsz==vect) begin
			memreq.sel <= eb[exndx].ifb.insn.r2.m ? (
				{	{4{eb[exndx].mask[15]}},
					{4{eb[exndx].mask[14]}},
					{4{eb[exndx].mask[13]}},
					{4{eb[exndx].mask[12]}},
					{4{eb[exndx].mask[11]}},
					{4{eb[exndx].mask[10]}},
					{4{eb[exndx].mask[9]}},
					{4{eb[exndx].mask[8]}},
					{4{eb[exndx].mask[7]}},
					{4{eb[exndx].mask[6]}},
					{4{eb[exndx].mask[5]}},
					{4{eb[exndx].mask[4]}},
					{4{eb[exndx].mask[3]}},
					{4{eb[exndx].mask[2]}},
					{4{eb[exndx].mask[1]}},
					{4{eb[exndx].mask[0]}}} >> {eb[exndx].step,2'h0}) & 64'hFFFF
				 	: 64'hFFFF;
			if (eb[exndx].dec.storen)
				memreq.sz <= tetra;
			memreq.adr <= eb[exndx].dec.storer ? 
				eb[exndx].a[0] + eb[exndx].dec.imm + {eb[exndx].step,5'b0} :
				eb[exndx].a[0] + eb[exndx].b[eb[exndx].step];
			// For a scatter store select the current vector element, otherwise select entire vector (set above).
			if (eb[exndx].dec.storen) begin
				memreq.sel <= 64'h000000000000000F;	// 32 bit at a time
				// Dont bother storing if masked
				if (eb[exndx].ifb.insn.r2.m && !eb[exndx].mask[eb[exndx].step])
					memreq.wr <= 1'b0;
				memreq.dat <= eb[exndx].t[eb[exndx].step];
			end
			if (eb[exndx].step!=NLANES-4 && eb[exndx].dec.storer)
				eb[exndx].step <= eb[exndx].step + 2'd4;
			// For scatter increment step
			if (eb[exndx].step!=NLANES-1 && eb[exndx].dec.storen)
				eb[exndx].step <= eb[exndx].step + 2'd1;
		end
		else
			memreq.adr <= eb[exndx].dec.storer ? eb[exndx].a[0] + eb[exndx].dec.imm : eb[exndx].a[0] + eb[exndx].b[0];
	end
end
endtask

task tExecute;
begin
	xrid_v <= 1'b0;
	if (exndx_v) begin
		eb[exndx].decoded <= 1'b0;
		eb[exndx].regfetched <= 1'b0;
		eb[exndx].out <= 1'b1;
		if (eb[exndx].dec.multicycle) begin
			mc_rid <= exndx;
			mcv_ridi <= exndx;
			mir <= eb[exndx].ifb.insn;
			mca <= eb[exndx].a;
			mcb <= eb[exndx].b;
			mcc <= eb[exndx].c;
			mct <= eb[exndx].t;
			mcimm <= eb[exndx].dec.imm;
			mcm <= eb[exndx].mask;
		end
		else begin
			xrid <= exndx;
			xrid_v <= 1'b1;
			xir <= eb[exndx].ifb.insn;
			xa <= eb[exndx].a;
			xb <= eb[exndx].b;
			xc <= eb[exndx].c;
			xt <= eb[exndx].t;
			xta <= eb[exndx].dec.Ta;
			xtb <= eb[exndx].dec.Tb;
			xtt <= eb[exndx].dec.Tt;
			xm <= eb[exndx].ifb.insn.r2.m ? eb[exndx].mask : 16'hFFFF;
			ximm <= eb[exndx].dec.imm;
			xasid <= asid[exndx];
			xhmask <= hmask;
			$display("Execute %d:", exndx);
			$display("  insn=%h a=%h b=%h c=%h i=%h", eb[exndx].ifb.insn, eb[exndx].a, eb[exndx].b, eb[exndx].c, eb[exndx].dec.imm);
			if (!memreq_full && ihit) begin
				tExLoad();
				tExStore();
			end
			// If the load/store could not be queued backout the decoded and out
			// indicators so the instruction will be reselected for execution.
			else begin
				if (eb[exndx].dec.load|eb[exndx].dec.store) begin
					eb[exndx].decoded <= 1'b1;
					eb[exndx].regfetched <= 1'b1;
					eb[exndx].out <= 1'b0;
				end
			end
		end
	end
	if (mcv_rido < NTHREADS) begin
		eb[mcv_rido].res <= mc_vres;
		eb[mcv_rido].out <= 1'b0;
		eb[mcv_rido].executed <= 1'b1;
	end
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// OU stage 
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

task tOuCall;
begin
	if (xrid_v) begin
		if (eb[xrid].out) begin
			eb[xrid].out <= 1'b0;
			eb[xrid].executed <= 1'b1;
			case(eb[xrid].ifb.insn.any.opcode)
			NOP:				thread[eb[xrid].thread].ip <= thread[eb[xrid].thread].ip - 4'd4;
			CALLA:
				begin
					thread[eb[xrid].thread].ip <= eb[xrid].ifb.insn.call.target;
					rollback_ip[xrid] <= eb[xrid].ifb.insn.call.target;
					rollback_ipv[xrid] <= 1'b1;
					eb[xrid].res <= eb[xrid].ifb.ip + 4'd5;
					ou_rollback[xrid] <= 1'b1;
					ou_rollback_bitmaps[xrid][eb[xrid].dec.Rt] <= 1'b1;
				end
			CALLR:
				begin
					thread[eb[xrid].thread].ip <= eb[xrid].ifb.insn.call.target + eb[xrid].ifb.ip;
					rollback_ip[xrid] <= eb[xrid].ifb.insn.call.target;
					rollback_ipv[xrid] <= 1'b1;
					eb[xrid].res <= eb[xrid].ifb.ip + 4'd5;
					ou_rollback[xrid] <= 1'b1;
					ou_rollback_bitmaps[xrid][eb[xrid].dec.Rt] <= 1'b1;
				end
			default:	;
			endcase
		end
	end
end
endtask

task tOuBranch;
begin
	if (xrid_v) begin
		if (eb[xrid].out) begin
			eb[xrid].out <= 1'b0;
			eb[xrid].executed <= 1'b1;
			if (eb[xrid].dec.br) begin
				if (takb) begin
					thread[eb[xrid].thread].ip <= eb[xrid].ifb.ip + eb[xrid].dec.imm;
					rollback_ip[xrid] <= eb[xrid].ifb.ip + eb[xrid].dec.imm;
					rollback_ipv[xrid] <= 1'b1;
					ou_rollback[xrid] <= 1'b1;
				end
			end
		end
	end
end
endtask

task tOut;
begin
	tOuCall();
	tOuBranch();
	if (xrid_v) begin
		eb[xrid].out <= 1'b0;
		eb[xrid].executed <= 1'b1;
		if (eb[xrid].dec.storen && eb[xrid].dec.memsz==vect) begin
			if (eb[xrid].step!=NLANES-1) begin
				eb[xrid].out <= 1'b1;
				eb[xrid].executed <= 1'b0;
			end
		end
		eb[xrid].res <= vres;
		$display("Out %d:", xrid);
		$display("  res=%h",vres);
	end
	if (mc_rid < NTHREADS) begin
		if (eb[mc_rid].dec.is_vector ? mcv_done : mc_done) begin
			mca_busy[0] <= 1'b0;
			eb[mc_rid].out <= 1'b0;
			eb[mc_rid].executed <= 1'b1;
//			if (eb[mc_rid].dec.Tt)
				eb[mc_rid].res <= mc_vres;
//			else
//				eb[mc_rid].res <= mc_res;
		end
	end
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// MEM stage 
// - process responses coming back from the BIU for requests sent by EX stage.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

task tMemory;
integer n;
begin
	if (memresp_fifo_v) begin
		// Clear the imiss status. The thread might still miss again if the I$
		// has not updated before the thread is selected again, but at least
		// it can be prevented from being selected for a few cycles while the
		// imiss request is processed.
		if (memresp.func==MR_ICACHE_LOAD)
			for (n = 0; n < NTHREADS; n = n + 1)
				thread[n].imiss <= 1'b0;
		else begin
			eb[memresp.thread].out <= 1'b0;
			if (eb[memresp.thread].out) begin
				eb[memresp.thread].executed <= 1'b1;
				// If a gather load
				if (eb[memresp.thread].dec.loadn && eb[memresp.thread].dec.memsz==vect) begin
					if (eb[memresp.thread].step!=NLANES-1) begin
						eb[memresp.thread].out <= 1'b1;
						eb[memresp.thread].executed <= 1'b0;
					end
					eb[memresp.thread].res[memresp.step] <= memresp.res;
				end
				// Other load
				else if (eb[memresp.thread].dec.load) begin
					eb[memresp.thread].res <= memresp.res;
				end
				// Scatter store
				else if (eb[memresp.thread].dec.storen && eb[memresp.thread].dec.memsz==vect) begin
					if (eb[memresp.thread].step!=NLANES-1) begin
						eb[memresp.thread].out <= 1'b1;
						eb[memresp.thread].executed <= 1'b0;
					end
				end
				else if (eb[memresp.thread].dec.storer && eb[memresp.thread].dec.memsz==vect) begin
					if (eb[memresp.thread].step!=NLANES-4) begin
						eb[memresp.thread].out <= 1'b1;
						eb[memresp.thread].executed <= 1'b0;
					end
				end
				// Other store / Other Op
			end
		end
	end
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// WB Stage
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

// RTI processing at the WB stage.
task tWbRti;
begin
	if (|istk_depth[wbndx]) begin
		pmStack[wbndx] <= {8'hCE,pmStack[wbndx][63:8]};	// restore operating mode, irq level
		plStack[wbndx] <= {8'hFF,plStack[wbndx][63:8]};	// restore privilege level
		ipStack[wbndx] <= {RSTIP,ipStack[wbndx][255:32]};
		thread[wbndx].ip <= ipStack[wbndx][31:0];
		istk_depth[wbndx] <= istk_depth[wbndx] - 2'd1;
		case(pmStack[wbndx][15:14])
		2'd0:	sp_sel[wbndx] <= 3'd0;
		2'd1:	sp_sel[wbndx] <= 3'd1;
		2'd2:	sp_sel[wbndx] <= 3'd2;
		2'd3:	sp_sel[wbndx] <= 3'd3;
		endcase
	end
	else
		tWbException(eb[wbndx].ifb.ip,FLT_RTI);
end
endtask

task tWbException;
input CodeAddress ip;
input CauseCode cc;
begin
	if (istk_depth[wbndx] < 3'd7) begin
		pmStack[wbndx] <= pmStack[wbndx] << 8;
		pmStack[wbndx][7:6] <= 2'b11;		// select machine operating mode
		pmStack[wbndx][3:1] <= cause[wbndx][omode[wbndx]][10:8];
		pmStack[wbndx][0] <= 1'b0;			// disable all irqs
		plStack[wbndx] <= plStack[wbndx] << 8;
		plStack[wbndx][7:0] <= 8'hFF;		// select max priv level
		ipStack[wbndx] <= ipStack[wbndx] << 32;
		ipStack[wbndx][31:0] <= ip;
		istk_depth[wbndx] <= istk_depth[wbndx] + 2'd1;
		thread[wbndx].ip <= tvec[2'd3];
		cause[wbndx][omode[wbndx]] <= cc;
		badaddr[wbndx][omode[wbndx]] <= eb[wbndx].badAddr;
		eb[wbndx].cause <= FLT_NONE;
		if (eb[wbndx].cause & 12'h8FF==FLT_IRQ)
			sp_sel[wbndx] <= 3'd4;
		else
			sp_sel[wbndx] <= 3'd3;
	end
	if (eb[wbndx].dec.mem) begin
		mem_rollback[wbndx] <= 1'b1;
		ou_rollback[wbndx] <= 1'b1;
	end
	else begin
		ou_rollback[wbndx] <= 1'b1;
	end
end
endtask

task tWriteback;
begin
	if (wbndx_v) begin
		$display("Writeback %d:", wbndx);
		if (|eb[wbndx].cause)
			tWbException(eb[wbndx].ifb.ip,eb[wbndx].cause);
		else begin
			$display("  ip=%h ir=%h", eb[wbndx].ifb.ip, eb[wbndx].ifb.insn);
			if (eb[wbndx].dec.rfwr)
				$display("  %s=%h", fnRegName(eb[wbndx].dec.Rt), eb[wbndx].res);
			commit_thread <= wbndx;
			commit_mask <= eb[wbndx].ifb.insn.r2.m ? eb[wbndx].mask : 16'hFFFF;
			commit_wr <= eb[wbndx].dec.rfwr;
			commit_wrv <= eb[wbndx].dec.vrfwr;
			commit_tgt <= eb[wbndx].dec.Rt;
			commit_bus <= eb[wbndx].res;
			case(1'b1)
			eb[wbndx].dec.brk:	tWbException(eb[wbndx].ifb.ip + 4'd5,eb[wbndx].cause);	// BRK instruction
			eb[wbndx].dec.irq: tWbException(eb[wbndx].ifb.ip,eb[wbndx].cause);	// hardware irq
			eb[wbndx].dec.flt: tWbException(eb[wbndx].ifb.ip,eb[wbndx].cause);	// processing fault (divide by zero, tlb miss, ...)
			eb[wbndx].dec.rti:	tWbRti();
			eb[wbndx].dec.csrrw:	tWriteCSR(eb[wbndx].a,wbndx,eb[wbndx].dec.imm[13:0]);
			eb[wbndx].dec.csrrc:	tClrbitCSR(eb[wbndx].a,wbndx,eb[wbndx].dec.imm[13:0]);
			eb[wbndx].dec.csrrs:	tSetbitCSR(eb[wbndx].a,wbndx,eb[wbndx].dec.imm[13:0]);
			endcase
			if (eb[wbndx].dec.Rt=='d0 && eb[wbndx].dec.rfwr)
				rz[wbndx] <= 1'b1;
		end
		if (wbndx != rthread)
			eb[wbndx] <= 'd0;
	end
	ou_rollback_bitmaps[commit_thread][commit_tgt] <= 1'b0;
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// CSR Read / Update tasks
//
// Important to use the correct assignment type for the following, otherwise
// The read won't happen until the clock cycle.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

task tReadCSR;
output Value res;
input Tid thread;
input [13:0] regno;
begin
	if (regno[13:12] <= omode[thread]) begin
		casez({2'b00,regno[13:0]})
		CSR_MHARTID: res = {hartid_i[31:3],thread};
//		CSR_MCR0:	res = cr0|(dce << 5'd30);
		CSR_PTBR:	res = ptbr[thread];
//		CSR_HMASK:	res = hmask;
//		CSR_KEYS:	res = keys2[regno[0]];
//		CSR_FSTAT:	res = fpscr;
		CSR_ASID:	res = asid[thread];
		CSR_MBADADDR:	res = badaddr[thread][regno[13:12]];
		CSR_TICK:	res = tick;
		CSR_CAUSE:	res = cause[thread][regno[13:12]];
		CSR_MTVEC:	res = tvec[regno[1:0]];
		CSR_MEIP:		res = ipStack[thread][31:0];
		CSR_MPLSTACK:	res = plStack[thread];
		CSR_MPMSTACK:	res = pmStack[thread];
		CSR_TIME:	res = wc_time[31:0];
		CSR_MSTATUS:	res = status[3];
		default:	res = 'd0;
		endcase
	end
	else
		res = 'd0;
end
endtask

task tWriteCSR;
input Value val;
input Tid thread;
input [13:0] regno;
begin
	if (regno[13:12] <= omode[thread]) begin
		casez({2'b00,regno[13:0]})
		CSR_MCR0:		cr0 <= val;
		CSR_PTBR:		ptbr[thread] <= val;
//		CSR_HMASK:	hmask <= val;
//		CSR_SEMA:		sema <= val;
//		CSR_KEYS:		keys2[regno[0]] <= val;
//		CSR_FSTAT:	fpscr <= val;
		CSR_ASID: 	asid[thread] <= val;
		CSR_MBADADDR:	badaddr[thread][regno[13:12]] <= val;
		CSR_CAUSE:	cause[thread][regno[13:12]] <= CauseCode'(val[11:0]);
		CSR_MTVEC:	tvec[regno[1:0]] <= val;
		CSR_MPLSTACK:	plStack[thread] <= val;
		CSR_MPMSTACK:	pmStack[thread] <= val;
		CSR_MTIME:	begin wc_time_dat <= val; ld_time <= 1'b1; end
		CSR_MSTATUS:	status[3] <= val;
		default:	;
		endcase
	end
end
endtask

task tSetbitCSR;
input Value val;
input Tid thread;
input [13:0] regno;
begin
	if (regno[13:12] <= omode[thread]) begin
		casez({2'b00,regno[13:0]})
		CSR_MCR0:			cr0[val[5:0]] <= 1'b1;
		CSR_MPMSTACK:	pmStack[thread] <= pmStack[thread] | val;
		CSR_MSTATUS:	status[3] <= status[3] | val;
		default:	;
		endcase
	end
end
endtask

task tClrbitCSR;
input Value val;
input Tid thread;
input [13:0] regno;
begin
	if (regno[13:12] <= omode[thread]) begin
		casez({2'b00,regno[13:0]})
		CSR_MCR0:			cr0[val[5:0]] <= 1'b0;
		CSR_MPMSTACK:	pmStack[thread] <= pmStack[thread] & ~val;
		CSR_MSTATUS:	status[3] <= status[3] & ~val;
		default:	;
		endcase
	end
end
endtask

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// Disassembler for debugging. It helps to have some output to allow 
// visual tracking in the simulation run.
// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function [31:0] fnRegName;
input [5:0] Rn;
begin
	case(Rn)
	6'd0:	fnRegName = "zero";
	6'd1:	fnRegName = "a0";
	6'd2:	fnRegName = "a1";
	6'd3:	fnRegName = "t0";
	6'd4:	fnRegName = "t1";
	6'd5:	fnRegName = "t2";
	6'd6:	fnRegName = "t3";
	6'd7:	fnRegName = "t4";
	6'd8:	fnRegName = "t5";
	6'd9:	fnRegName = "t6";
	6'd10:	fnRegName = "t7";
	6'd11:	fnRegName = "s0";
	6'd12:	fnRegName = "s1";
	6'd13:	fnRegName = "s2";
	6'd14:	fnRegName = "s3";
	6'd15:	fnRegName = "s4";
	6'd16:	fnRegName = "s5";
	6'd17:	fnRegName = "s6";
	6'd18:	fnRegName = "s7";
	6'd19:	fnRegName = "s8";
	6'd20:	fnRegName = "s9";
	6'd21:	fnRegName = "a2";
	6'd22:	fnRegName = "a3";
	6'd23:	fnRegName = "a4";
	6'd24:	fnRegName = "a5";
	6'd25:	fnRegName = "a6";
	6'd26:	fnRegName = "a7";
	6'd27:	fnRegName = "gp3";
	6'd28:	fnRegName = "gp2";
	6'd29:	fnRegName = "gp";
	6'd30:	fnRegName = "fp";
	6'd31:	fnRegName = "sp";
	6'd32:	fnRegName = "vm0";
	6'd33:	fnRegName = "vm1";
	6'd34:	fnRegName = "vm2";
	6'd35:	fnRegName = "vm3";
	6'd36:	fnRegName = "vm4";
	6'd37:	fnRegName = "vm5";
	6'd38:	fnRegName = "vm6";
	6'd39:	fnRegName = "vm7";
	6'd40:	fnRegName = "lc";
	6'd41:	fnRegName = "lk1";
	6'd42:	fnRegName = "lk2";
	6'd43:	fnRegName = "r43";
	6'd44:	fnRegName = "ssp";
	6'd45:	fnRegName = "hsp";
	6'd46:	fnRegName = "msp";
	6'd47:	fnRegName = "isp";
	6'd48:	fnRegName = "t8";
	6'd49:	fnRegName = "t9";
	6'd50:	fnRegName = "t10";
	6'd51:	fnRegName = "t11";
	6'd52:	fnRegName = "s10";
	6'd53:	fnRegName = "s11";
	6'd54:	fnRegName = "s12";
	6'd55:	fnRegName = "s13";
	6'd56:	fnRegName = "f0";
	6'd57:	fnRegName = "f1";
	6'd58:	fnRegName = "f2";
	6'd59:	fnRegName = "f3";
	6'd60:	fnRegName = "f4";
	6'd61:	fnRegName = "f5";
	6'd62:	fnRegName = "f6";
	6'd63:	fnRegName = "f7";
	endcase
end
endfunction

endmodule
