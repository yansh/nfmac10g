/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        ibuf2mac.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Sends Ethernet frames.
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

module ibuf2mac # (
    parameter AW = 9,
    parameter DW = 72
    ) (

    input                    clk,
    input                    rst,

    // MAC Tx
    output reg   [63:0]      tdat,
    output reg   [7:0]       tkep,
    output reg               tval,
    output reg               tlst,
    output reg               tusr,
    input                    trdy,

    // ibuf
    output       [AW-1:0]    rd_addr,
    input        [DW-1:0]    rd_data,

    // bwd logic
    output       [AW:0]      committed_cons,
    input        [AW:0]      committed_prod
    );

    // localparam
    localparam s0 = 9'b000000000;
    localparam s1 = 9'b000000001;
    localparam s2 = 9'b000000010;
    localparam s3 = 9'b000000100;
    localparam s4 = 9'b000001000;
    localparam s5 = 9'b000010000;
    localparam s6 = 9'b000100000;
    localparam s7 = 9'b001000000;
    localparam s8 = 9'b010000000;
    localparam s9 = 9'b100000000;

    //-------------------------------------------------------
    // Local ibuf2mac
    //-------------------------------------------------------   
    reg          [8:0]       fsm;
    reg          [AW:0]      rd_addr_i;
    reg          [AW:0]      diff, diff_end;
    reg          [AW:0]      sof_addr;
    reg          [DW-1:0]    ax_rd_data, ax2_rd_data;
    reg          [AW:0]      cons;
    reg                      updt_sof;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign rd_addr = rd_addr_i;
    assign committed_cons = sof_addr;

    ////////////////////////////////////////////////
    // Outbound ethernet frame to mac
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        tusr <= 'b0;

        diff <= committed_prod + (~sof_addr) + 1;
        diff_end <= committed_prod + (~cons);

        if (tval && trdy) begin
            cons <= cons + 1;
        end

        updt_sof <= 1'b0;
        if (updt_sof) begin
            sof_addr <= cons;
        end

        if (rst) begin  // rst
            tval <= 1'b0;
            fsm <= s0;
        end
        
        else begin  // not rst

            case (fsm)

                s0 : begin
                    cons <= 'b0;
                    sof_addr <= 'b0;
                    rd_addr_i <= 'b0;
                    fsm <= s1;
                end

                s1 : begin // update diff
                    fsm <= s2;
                end

                s2 : begin
                    if (diff) begin
                        rd_addr_i <= rd_addr_i + 1;
                        fsm <= s3;
                    end
                end

                s3 : begin
                    rd_addr_i <= rd_addr_i + 1;
                    fsm <= s4;
                end

                s4 : begin
                    tdat <= get_tdata(rd_data);
                    tkep <= get_tkeep(rd_data);
                    tlst <= get_tlast(rd_data);
                    tval <= 1'b1;
                    rd_addr_i <= rd_addr_i + 1;
                    fsm <= s5;
                end

                s5 : begin
                    rd_addr_i <= rd_addr_i + 1;
                    ax_rd_data <= rd_data;
                    if (trdy) begin
                        tdat <= get_tdata(rd_data);
                        tkep <= get_tkeep(rd_data);
                        tlst <= get_tlast(rd_data);
                        if (tlst) begin
                            updt_sof <= 1'b1;
                        end
                        if (tlst && !(diff_end > 1)) begin
                            tval <= 1'b0;
                            fsm <= s9;
                        end
                    end
                    else begin
                        rd_addr_i <= rd_addr_i;
                        fsm <= s6;
                    end
                end

                s6 : begin
                    ax2_rd_data <= rd_data;
                    if (trdy) begin
                        tdat <= get_tdata(ax_rd_data);
                        tkep <= get_tkeep(ax_rd_data);
                        tlst <= get_tlast(ax_rd_data);
                        rd_addr_i <= rd_addr_i + 1;
                        if (tlst) begin
                            updt_sof <= 1'b1;
                        end
                        if (tlst && !(diff_end > 1)) begin
                            tval <= 1'b0;
                            fsm <= s9;
                        end
                        else begin
                            fsm <= s8;
                        end
                    end
                    else begin
                        fsm <= s7;
                    end
                end

                s7 : begin
                    if (trdy) begin
                        tdat <= get_tdata(ax_rd_data);
                        tkep <= get_tkeep(ax_rd_data);
                        tlst <= get_tlast(ax_rd_data);
                        rd_addr_i <= rd_addr_i + 1;
                        if (tlst) begin
                            updt_sof <= 1'b1;
                        end
                        if (tlst && !(diff_end > 1)) begin
                            tval <= 1'b0;
                            fsm <= s9;
                        end
                        else begin
                            fsm <= s8;
                        end
                    end
                end

                s8 : begin
                    if (trdy) begin
                        tdat <= get_tdata(ax2_rd_data);
                        tkep <= get_tkeep(ax2_rd_data);
                        tlst <= get_tlast(ax2_rd_data);
                        rd_addr_i <= rd_addr_i + 1;
                        if (tlst) begin
                            updt_sof <= 1'b1;
                        end
                        if (tlst && !(diff_end > 1)) begin
                            tval <= 1'b0;
                            fsm <= s9;
                        end
                        else begin
                            fsm <= s5;
                        end
                    end
                    else begin
                        ax_rd_data <= ax2_rd_data;
                        fsm <= s6;
                    end
                end

                s9 : begin
                    rd_addr_i <= cons;
                    fsm <= s1;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // get_tdata
    ////////////////////////////////////////////////
    function [63:0] get_tdata (
        input        [DW-1:0]    din
        );
    begin
        get_tdata = din[DW-1:DW-64];
    end
    endfunction // get_tdata

    ////////////////////////////////////////////////
    // get_tkeep
    ////////////////////////////////////////////////
    function [7:0] get_tkeep (
        input        [DW-1:0]    din
        );
    begin
        get_tkeep = {din[8:1], 1'b1};
    end
    endfunction // get_tkeep

    ////////////////////////////////////////////////
    // get_tlast
    ////////////////////////////////////////////////
    function get_tlast (
        input        [DW-1:0]    din
        );
    begin
        get_tlast = din[0];
    end
    endfunction // get_tlast

endmodule // ibuf2mac

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////