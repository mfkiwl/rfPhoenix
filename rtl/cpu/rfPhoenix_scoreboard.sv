`timescale 1ns / 1ps
// ============================================================================
//        __
//   \\__/ o\    (C) 2022  Robert Finch, Waterloo
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

import rfPhoenixPkg::*;

module rfPhoenix_scoreboard(rst, clk, db, wb_v, wb_Rt, will_issue, can_issue, rollback, rollback_bitmap);
input rst;
input clk;
input DecodeBus db;
input wb_v;
input Regspec wb_Rt;
input will_issue;
output reg can_issue;
input rollback;
input regs_bitmap_t rollback_bitmap;
localparam ROLLBACK_STAGES = 5;

integer n1;

regs_bitmap_t valid, nxt_valid;
regs_bitmap_t srcs;
regs_bitmap_t tgts;	// targets
regs_bitmap_t wbs;
regs_bitmap_t clr_bm;
regs_bitmap_t set_bm;
regs_bitmap_t rollback_bm;
logic [ROLLBACK_STAGES-1:0] has_wb;
Regspec [ROLLBACK_STAGES-1:0] wb_Rts;

always_comb
begin
	srcs = 'd0;
	if (db.v) begin
		if (db.hasRa)	srcs[db.Ra] = 1'b1;
		if (db.hasRb) srcs[db.Rb] = 1'b1;
		if (db.hasRc) srcs[db.Rc] = 1'b1;
		if (db.hasRm) srcs[db.Rm] = 1'b1;
		if (db.hasRt & db.Rtsrc) srcs[db.Rt] = 1'b1;
	end
end

always_comb
begin
	tgts = 'd0;
	if (db.v)
		if (db.hasRt & ((db.rfwr&~db.Rt.vec)|(db.vrfwr&db.Rt.vec))) tgts[db.Rt] = 1'b1;
end

always_comb
begin
	wbs = 'd0;
	if (wb_v) wbs[wb_Rt] = 1'b1;
end

always_comb
	set_bm = wbs | (rollback ? rollback_bitmap : 'd0);
always_comb
	clr_bm = tgts & {{127{will_issue}},1'b0};	// r0 is always valid
always_comb
	nxt_valid = (valid & ~clr_bm) | set_bm;

always_ff @(posedge clk)
if (rst)
	valid <= {128{1'b1}};
else begin
	valid <= nxt_valid;
end

always_ff @(posedge clk)
if (rst)
	has_wb <= 'd0;
else
	has_wb <= {has_wb,db.hasRt};

// Capture rollback targets
always_ff @(posedge clk)
begin
	if (will_issue & db.hasRt)
		wb_Rts[0] <= db.Rt;
	else
		wb_Rts[0] <= 'd0;
	for (n1 = 1; n1 < ROLLBACK_STAGES; n1 = n1 + 1)
		wb_Rts[n1] <= wb_Rts[n1-1];	
end

always_comb
	can_issue = (nxt_valid[127:1] & srcs[127:1]) == srcs[127:1];

endmodule
