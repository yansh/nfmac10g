/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mac2ibuf.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Eth frames 2 internal buff
*
*
*    This code is initially developed for the Network-as-a-Service (NaaS) project.
*
*  Copyright notice:
*        Copyright (C) 2014 University of Cambridge
*
*  Licence:
*        This file is part of the NetFPGA 10G development base package.
*
*        This file is free code: you can redistribute it and/or modify it under
*        the terms of the GNU Lesser General Public License version 2.1 as
*        published by the Free Software Foundation.
*
*        This package is distributed in the hope that it will be useful, but
*        WITHOUT ANY WARRANTY; without even the implied warranty of
*        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
*        Lesser General Public License for more details.
*
*        You should have received a copy of the GNU Lesser General Public
*        License along with the NetFPGA source package.  If not, see
*        http://www.gnu.org/licenses/.
*
*/

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
//`default_nettype none

module mac2ibuf # (
    parameter AW = 10,
    parameter DW = 72
    ) (

    input                    clk,
    input                    rst,

    // MAC Rx
    input        [63:0]      tdat,
    input        [7:0]       tkep,
    input                    tval,
    input                    tlst,
    input                    tusr,

    // ibuf
    output reg   [AW-1:0]    wr_addr,
    output reg   [DW-1:0]    wr_data,

    // fwd logic
    output reg   [AW:0]      committed_prod,
    input        [AW:0]      committed_cons,
    output reg   [15:0]      dropped_pkts
    );

    // localparam
    localparam s0 = 8'b00000000;
    localparam s1 = 8'b00000001;
    localparam s2 = 8'b00000010;
    localparam s3 = 8'b00000100;
    localparam s4 = 8'b00001000;
    localparam s5 = 8'b00010000;
    localparam s6 = 8'b00100000;
    localparam s7 = 8'b01000000;
    localparam s8 = 8'b10000000;

    localparam MAX_DIFF = (2**AW) - 10;

    //-------------------------------------------------------
    // Local mac2ibuf
    //-------------------------------------------------------
    reg          [7:0]       fsm;
    reg          [AW:0]      ax_wr_addr;
    reg          [AW:0]      diff;
    wire         [DW-1:0]    din;
    reg                      update_prod;
    reg                      update_dropp;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign din = {tdat, tkep[7:1], tlst};

    ////////////////////////////////////////////////
    // Inbound ethernet frame to ibuf
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        diff <= ax_wr_addr + (~committed_cons) +1;
        wr_data <= din;

        update_prod <= 1'b0;
        if (update_prod) begin
            committed_prod <= ax_wr_addr;
        end

        update_dropp <= 1'b0;
        if (update_dropp) begin
            dropped_pkts <= dropped_pkts +1;
        end

        if (rst) begin  // rst
            fsm <= s0;
        end

        else begin  // not rst

            case (fsm)

                s0 : begin
                    committed_prod <= 'b0;
                    ax_wr_addr <= 'b0;
                    dropped_pkts <= 'b0;
                    fsm <= s1;
                end

                s1 : begin // update diff
                    wr_addr <= committed_prod;
                    ax_wr_addr <= committed_prod + 1;
                    if (tval) begin
                        fsm <= s2;
                    end
                end

                s2 : begin
                    wr_addr <= ax_wr_addr;
                    if (tval) begin
                        ax_wr_addr <= ax_wr_addr + 1;
                    end

                    if (tval && tlst && tusr) begin
                        update_prod <= 1'b1;
                    end

                    if (tval && tlst && !tusr) begin
                        fsm <= s1;
                    end
                    else if (diff > MAX_DIFF) begin           // ibuffer is almost full
                        fsm <= s3;
                    end
                end

                s3 : begin                                  // drop current frame
                    if (tval && tlst) begin
                        update_dropp <= 1'b1;
                        fsm <= s1;
                    end
                end

            endcase
        end     // not rst
    end  //always

endmodule // mac2ibuf

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////