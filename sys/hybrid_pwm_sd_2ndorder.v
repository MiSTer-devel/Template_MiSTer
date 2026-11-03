// Hybrid PWM / Sigma Delta DAC
//
// 16-bit Sigma Delta with 5-bit output, feeding a PWM.

// If rising and falling edges aren't perfectly symmetrical, a significant
// amount of noise can be introduced into a sigma-delta DAC, since the number
// of rising- and falling-edges within a given time period is either directly
// dependent upon the code, or pseudo-random.

// The PWM output stage, on the other hand, results results in a constant
// number of rising- and falling-edges in a given time period, so any edge imbalance
// will result in a DC offset rather than audible noise.

// 2nd order variant with low-pass input filter and high-pass feedback filter.
// Copyright 2021 by Alastair M. Robinson

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that they will
// be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
// of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>
//


module hybrid_pwm_sd_2ndorder #(parameter signalwidth=16, parameter filtersize=2)
(
	input clk,
	input reset,
	input [signalwidth-1:0] d,
	output q
);

reg q_reg;
assign q=q_reg;

// Input filtering - a simple single-pole IIR low-pass filter.
// configurable number of bits.

wire [signalwidth-1:0] infiltered;
reg infilterena;

iirfilter # (.signalwidth(signalwidth),.cbits(filtersize),.immediate(0)) inputfilter
(
	.clk(clk),
	.reset(reset),
	.ena(infilterena),
	.d(d),
	.q(infiltered)
);


// Approximation of reconstruction filter,
// subtracted from the incoming signal to
// steer the first stage of the sigma delta.

// 9 bits for the coefficient (1/512)

wire [signalwidth-1:0] outfiltered;

iirfilter # (.signalwidth(signalwidth),.cbits(9),.immediate(1)) outputfilter
(
	.clk(clk),
	.reset(reset),
	.ena(1'b1),
	.d(q_reg ? {signalwidth{1'b1}} : {signalwidth{1'b0}}),
	.q(outfiltered)
);

reg [6:0] pwmcounter;
wire [6:0] pwmthreshold;
reg [signalwidth+1:0] sigma;
reg [signalwidth+1:0] sigma2;

wire [signalwidth+1:0] sigmanext;

assign sigmanext = sigma+{2'b0,infiltered}-{2'b0,outfiltered};

assign pwmthreshold = sigma2[signalwidth+1:signalwidth-5];


always @(posedge clk, posedge reset)
begin
	if(reset) begin
		q_reg<=1'b0;
		infilterena<=1'b0;
		sigma<={signalwidth+2{1'b0}};
		sigma2={signalwidth+2{1'b0}};
		pwmcounter<=7'b111110;
	end else begin
		infilterena<=1'b0;

		if(pwmcounter==pwmthreshold)
			q_reg<=1'b0;

		if(pwmcounter==7'b11111) // Update threshold just before pwmcounter wraps around
		begin

			infilterena<=1'b1;

			// PWM

			sigma<=sigmanext;
			sigma2=sigmanext+{7'b0010000,sigma2[signalwidth-6:0]};

			if(sigma2[signalwidth+1]==1'b1)
				q_reg<=1'b0;
			else
				q_reg<=1'b1;

		end

		pwmcounter[6:5]<=2'b0;
		pwmcounter[4:0]<=pwmcounter[4:0]+5'b1;

	end
end

endmodule



// Simplistic IIR low-pass filter.
// function is simply y += b * (x - y)
// where b=1/(1<<cbits)

module iirfilter #
(
	parameter signalwidth = 16,
	parameter cbits = 5,	// Bits for coefficient (default 1/32)
	parameter immediate = 0
)
(
	input clk,
	input reset,
	input ena,
	input [signalwidth-1:0] d,
	output [signalwidth-1:0] q
);

localparam [signalwidth-1:0] midpoint = {1'b1,{(signalwidth-1){1'b0}}};

reg [signalwidth+cbits-1:0] acc = {midpoint,{cbits{1'b0}}};
wire [signalwidth+cbits-1:0] acc_new;

wire [signalwidth+cbits:0] delta = {d,{cbits{1'b0}}} - acc;

assign acc_new = acc + {{cbits{delta[signalwidth+cbits]}},delta[signalwidth+cbits-1:cbits]};

always @(posedge clk, posedge reset)
begin
	if(reset)
	begin
		acc<={midpoint,{cbits{1'b0}}};
	end
	else if(ena)
		acc <= acc_new;
end

// Based on the immediate signal, q is either combinational or registered.
assign q=immediate ? acc_new[signalwidth+cbits-1:cbits] : acc[signalwidth+cbits-1:cbits];

endmodule
