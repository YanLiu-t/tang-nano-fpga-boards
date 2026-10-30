/*
 *  SVO - Simple Video Out FPGA Core
 *
 *  Copyright (C) 2014  Clifford Wolf <clifford@clifford.at>
 *  
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *  
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

//============================================================================
// REARCHITECTED FOR HARD REAL-TIME (2026-10-02)
//============================================================================
//
// The upstream SVO encoder is a "raster-lockstep" design: the control raster
// generator (hcursor/vcursor) is back-pressured by ctrl_fifo, whose consumer
// is in turn gated by pixel availability. That is only correct if the output
// stage can always stop. It cannot: top.v drives OSER10, which shifts exactly
// ONE symbol per clk_p and COMPLETELY IGNORES tvalid (see svo_tmds / OSER10 -
// only de/ctrl/din are consumed). So whenever the consumer stalls (pixel
// starvation, or the pixel FSM's frame-boundary gap where fb_tvalid drops),
// the raster generator stops while the serialiser keeps clocking -> EXTRA
// SYMBOLS are injected into the TMDS symbol stream. The monitor re-derives
// line/frame timing from those symbols, so the injected symbols stretch the
// line and the frame -> the whole picture drifts left/right AND up/down and
// flickers. This was the actual, structural root cause of the instability;
// every consumer-side patch only changed how often the raster stalled.
//
// The invariant a video encoder MUST hold is therefore:
//
//     the raster is free-running and NEVER back-pressured, and the output
//     stage emits exactly one valid symbol every clk (no gaps, ever).
//
// The SECOND half of the invariant is equally important:
//
//     the encoder consumes EXACTLY ONE pixel per ACTIVE raster pixel, and
//     EXACTLY ZERO pixels during h-blank and v-blank.
//
// The pixel streamer in top.v emits exactly 640*480 = 307200 pixels per frame
// (gx/gy wrap after 160*480 groups of 4). Over one raster frame the active
// region is also exactly 640*480 = 307200 pixels. So if - and only if - the
// encoder consumes nothing during blanking, production == consumption every
// frame and the FSM's frame boundary stays locked to the raster's.
//
// Any EXTRA consumption during blanking (e.g. "discarding stale pixels" while
// !v_active) makes the FSM run ahead by that many pixels EVERY frame: with
// 45 blank lines * 800 = 36000 extra pixels/frame the FSM advances 36000 px
// = 56 lines of phase per frame, i.e. the whole picture shifts/rolls and
// flickers. That was the actual cause of the instability.
//
// Consequences of the design below:
//   * Every frame contains exactly SVO_HOR_TOTAL * SVO_VER_TOTAL symbols,
//     so TMDS line/frame timing is absolutely constant -> no drift.
//   * A missing pixel can only blank ONE pixel; it can never move anything.
//   * Vertical/horizontal blanking consumes no pixel, so the pixel FSM stays
//     in exact lock-step with the raster; the picture is fixed.
//
//============================================================================

`timescale 1ns / 1ps
`include "svo_defines.vh"

module svo_enc #( `SVO_DEFAULT_PARAMS ) (
	input clk, resetn,

	// input stream
	//   tuser[0] ... start of frame
	input in_axis_tvalid,
	output reg in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [0:0] in_axis_tuser,

	// output stream
	//   tuser[0] ... start of frame
	//   tuser[1] ... hsync
	//   tuser[2] ... vsync
	//   tuser[3] ... blank
	output reg out_axis_tvalid,
	input out_axis_tready,
	output reg [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output reg [3:0] out_axis_tuser
);
	`SVO_DECLS

	//--------------------------------------------------------------------
	// FREE-RUNNING RASTER (never back-pressured)
	//   exactly one increment per clk, forever. No FIFO level, no bus
	//   state and no pixel availability may ever influence it.
	//--------------------------------------------------------------------
	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;

	localparam [`SVO_XYBITS-1:0] H_ACT_START =
	    SVO_HOR_FRONT_PORCH + SVO_HOR_SYNC + SVO_HOR_BACK_PORCH;
	localparam [`SVO_XYBITS-1:0] V_ACT_START =
	    SVO_VER_FRONT_PORCH + SVO_VER_SYNC + SVO_VER_BACK_PORCH;

	always @(posedge clk) begin
		if (!resetn) begin
			hcursor <= 0;
			vcursor <= 0;
		end else if (hcursor == SVO_HOR_TOTAL-1) begin
			hcursor <= 0;
			vcursor <= (vcursor == SVO_VER_TOTAL-1) ? 0 : vcursor + 1;
		end else begin
			hcursor <= hcursor + 1;
		end
	end

	wire h_active = (hcursor >= H_ACT_START);
	wire v_active = (vcursor >= V_ACT_START);
	wire is_active = h_active && v_active;

	wire is_hsync = (hcursor >= SVO_HOR_FRONT_PORCH) &&
	                (hcursor <  SVO_HOR_FRONT_PORCH + SVO_HOR_SYNC);
	wire is_vsync = (vcursor >= SVO_VER_FRONT_PORCH) &&
	                (vcursor <  SVO_VER_FRONT_PORCH + SVO_VER_SYNC);
	wire sof = !hcursor && !vcursor;

	//--------------------------------------------------------------------
	// INPUT PIXEL FIFO (same handshake as before)
	//   stores {tuser[0], tdata}; the SOF bit is bit SVO_BITS_PER_PIXEL.
	//--------------------------------------------------------------------
	reg [SVO_BITS_PER_PIXEL:0] pixel_fifo [0:7];
	reg [2:0] pixel_fifo_wraddr, pixel_fifo_rdaddr;

	always @(posedge clk) begin
		if (!resetn) begin
			pixel_fifo_wraddr <= 0;
			in_axis_tready    <= 0;
		end else begin
			if (in_axis_tvalid && in_axis_tready) begin
				pixel_fifo[pixel_fifo_wraddr] <= {in_axis_tuser, in_axis_tdata};
				pixel_fifo_wraddr <= pixel_fifo_wraddr + 1;
			end
			in_axis_tready <= pixel_fifo_wraddr + 3'd2 != pixel_fifo_rdaddr &&
			                  pixel_fifo_wraddr + 3'd1 != pixel_fifo_rdaddr;
		end
	end

	//--------------------------------------------------------------------
	// OUTPUT STAGE: one symbol every clk, ALWAYS valid.
	//   - blanking symbol : from the raster only, consumes no pixel.
	//   - active symbol   : next pixel, or black if none is buffered yet.
	//   - out_axis_tvalid is never lowered once running: dropping a symbol
	//     would make OSER10 re-serialise the previous one (extra symbol).
	//--------------------------------------------------------------------
	reg [SVO_BITS_PER_PIXEL-1:0] tdata_n;
	reg [3:0] tuser_n;

	always @(*) begin
		tdata_n = {SVO_BITS_PER_PIXEL{1'b0}};
		tuser_n = {!is_active, is_vsync, is_hsync, sof};
		if (is_active && pixel_fifo_rdaddr != pixel_fifo_wraddr) begin
			tdata_n  = pixel_fifo[pixel_fifo_rdaddr][SVO_BITS_PER_PIXEL-1:0];
			tuser_n[0] = pixel_fifo[pixel_fifo_rdaddr][SVO_BITS_PER_PIXEL];
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			pixel_fifo_rdaddr <= 0;
			out_axis_tvalid   <= 1'b0;
			out_axis_tdata    <= {SVO_BITS_PER_PIXEL{1'b0}};
			out_axis_tuser    <= 4'b0;
		end else begin
			out_axis_tvalid <= 1'b1;
			out_axis_tdata  <= tdata_n;
			out_axis_tuser  <= tuser_n;

			// Consume exactly ONE pixel per ACTIVE raster pixel, and NOTHING
			// during h-blank / v-blank. This is what keeps the pixel FSM's
			// frame boundary locked to the raster: over one raster frame the
			// encoder consumes 640*480 = 307200 pixels, exactly what the FSM
			// emits per frame. Consuming during blanking would make the FSM
			// drift ahead by that many pixels every frame -> shifting/flicker.
			if (is_active && pixel_fifo_rdaddr != pixel_fifo_wraddr)
				pixel_fifo_rdaddr <= pixel_fifo_rdaddr + 3'd1;
		end
	end

endmodule