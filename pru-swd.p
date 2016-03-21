//							-*- mode: asm -*-
// pru-swd.p - PRU program to handle SWD protocol
//
// Copyright (C) 2016  Flying Stone Technology
// Author: NIIBE Yutaka <gniibe@fsij.org>
//
// This file is a part of BBG-SWD, a SWD tool for BeagleBoneGreen.
//
// BBG-SWD is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// BBG-SWD is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

.origin 0
.entrypoint START

#define PRU0_ARM_INTERRUPT	19

// Constant Table
#define CT_PRUCFG	C4
#define CT_PRUDRAM	C24

//  PRU Control register
#define PRU0_CTRL 0x00022000	// address
#define WAKEUP_EN 8		// offset

// PRU CFG registers
#define SYSCFG		4 // offset
#define STANDBY_INIT	4 // bit

// P8_11 GPIO1_13 GPIO_45 SWD_DIO
// P8_12 GPIO1_12 GPIO_44 SWD_CLK
// P8_15 GPIO1_15 GPIO_47 nRST
#define SWD_DIO_BIT 13
#define SWD_CLK_BIT 12
#define SWD_DIO (1<<SWD_DIO_BIT)
#define SWD_CLK (1<<SWD_CLK_BIT)

#define GPIO1_BASE_0100   0x4804c100
// offsets
#define GPIO_OE			0x34
#define GPIO_DATAIN		0x38
#define GPIO_CLEARDATAOUT	0x90
#define GPIO_SETDATAOUT		0x94

// LED
// bit 21: USR0, 22: USR1, 23: USR2, 24: USR3

// No operation but delay
#define NOP	OR	r0, r0, r0

#define CTBIR_0         0x22020

//
//	DRIVE_CLK_HIGH - Macro to drive SWD_CLK "High"
//
.macro	DRIVE_CLK_HIGH
	SBBO	r7, r5, GPIO_SETDATAOUT, 4
.endm

//
//	DRIVE_CLK_LOW - Macro to drive SWD_CLK "Low"
//
.macro	DRIVE_CLK_LOW
	SBBO	r7, r5, GPIO_CLEARDATAOUT, 4
.endm

//
//	DRIVE_DIO_HIGH - Macro to drive SWD_DIO "High"
//
.macro	DRIVE_DIO_HIGH
	SBBO	r6, r5, GPIO_SETDATAOUT, 4
.endm

//
//	DRIVE_DIO_LOW - Macro to drive SWD_DIO "Low"
//
.macro	DRIVE_DIO_LOW
	SBBO	r6, r5, GPIO_CLEARDATAOUT, 4
.endm

//
//	TRN_INPUT - Macro to do TRN-bit for preparing input
//
.macro	TRN_INPUT
	SET_DIO_INPUT r2
	NOP
	NOP
	DRIVE_CLK_LOW
	NOP
	NOP
	DRIVE_CLK_HIGH
	NOP
	NOP
.endm

//
//	TRN_OUTPUT - Macro to do TRN-bit for preparing output
//
.macro	TRN_OUTPUT
	DRIVE_CLK_LOW
	NOP
	NOP
	DRIVE_CLK_HIGH
	NOP
	NOP
	SET_DIO_OUTPUT r2
.endm

START:
	// Enable OCP master port to access GPIO
	LBCO	r0, CT_PRUCFG, SYSCFG, 4
	CLR	r0, r0, STANDBY_INIT
	SBCO	r0, CT_PRUCFG, SYSCFG, 4

	// Configure C24 to 0x00000000 (PRU0 DRAM)
	LDI	r0, #0
	MOV	r1, CTBIR_0
	SBBO	r0, r1, 0, 4

	// Registers for constant values
	MOV	r5, #GPIO1_BASE_0100
	LDI	r6, #SWD_DIO
	LDI	r7, #SWD_CLK

	// Initialize SWD_DIO and SWD_CLK pins
	DRIVE_DIO_HIGH
	DRIVE_CLK_HIGH
	// SWD_DIO_oe <= Output, SWD_CLK_oe <= Output
	LBBO	r0, r5, GPIO_OE, 4
	CLR	r0, SWD_DIO_BIT
	CLR	r0, SWD_CLK_BIT
	SBBO	r0, r5, GPIO_OE, 4

	// Wakeup control configuration
	MOV	r0, #PRU0_CTRL
	MOV	r1, #0xffffffff
	SBBO	r1, r0, WAKEUP_EN, 4
	QBA	COMMAND_LOOP

//
//	BLINK - Blink LED
//
BLINK:
	LBCO	r0, CT_PRUDRAM, 4, 12
	//
	// R0 = delay
	// R1 = number of loops
	// R2 = LED bit value
	//
LOOP0:
	SBBO	r2, r5, GPIO_SETDATAOUT, 4
	MOV	r3, r0
LOOP1:
	SUB	r3, r3, 1
	QBNE	LOOP1, r3, 0

	SBBO	r2, r5, GPIO_CLEARDATAOUT, 4
	MOV	r3, r0
LOOP2:
	SUB	r3, r3, 1
	QBNE	LOOP2, r3, 0

	SUB	r1, r1, 1
	QBNE	LOOP0, r1, 0

	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	QBA	COMMAND_DONE


//
//	GPIO_OUT - Output to GPIO pin
//
GPIO_OUT:
	//
	// R0 = bit-value
	// R1 = value
	//
	LBCO	r0, CT_PRUDRAM, 4, 8
	//
	QBBS	L_GPIO_OUT_1, r1.t0
	SBBO	r0, r5, GPIO_CLEARDATAOUT, 4
	QBA	L_GPIO_OUT_DONE
L_GPIO_OUT_1:
	SBBO	r0, r5, GPIO_SETDATAOUT, 4
	NOP
L_GPIO_OUT_DONE:
	//
	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	QBA	COMMAND_DONE


//
//	GPIO_IN - Input from GPIO pin
//
GPIO_IN:
	LBBO	r0, r5, GPIO_DATAIN, 4
	//
	// RETURN: Value
	SBCO	r0, CT_PRUDRAM, 64, 4
	QBA	COMMAND_DONE


//
//	SET_DIO_OUTPUT - Macro to set mode of SWD_DIO to output
//
.macro	SET_DIO_OUTPUT
.mparam	rx
	// SWD_DIO_oe <= Output
	LBBO	rx, r5, GPIO_OE, 4
	CLR	rx, SWD_DIO_BIT
	SBBO	rx, r5, GPIO_OE, 4
.endm
	
//
//	SET_DIO_INPUT - Macro to set mode of SWD_DIO to input
//
.macro	SET_DIO_INPUT
.mparam	rx
	// SWD_DIO_oe <= Input
	LBBO	rx, r5, GPIO_OE, 4
	SET	rx, SWD_DIO_BIT
	SBBO	rx, r5, GPIO_OE, 4
.endm

DO_SIG_IDLE:
L_SIG_IDLE:
	DRIVE_CLK_LOW
	NOP
	NOP
	NOP
	NOP
	NOP
	DRIVE_CLK_HIGH
	NOP
	NOP
	NOP
	SUB	r0, r0, 1
	QBNE	L_SIG_IDLE, r0, 0
	RET

//
//	SIG_IDLE - Park SWD_DIO = Low and strobe SWD_CLK
//
SIG_IDLE:
	//
	// R0 = count
	//
	LBCO	r0, CT_PRUDRAM, 4, 4
	LSL	r0, r0, 5
	//
	DRIVE_DIO_LOW
	//
	JAL	r30.w0, DO_SIG_IDLE
	//
	DRIVE_DIO_HIGH
	//
	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	QBA	COMMAND_DONE

//
//	SIG_GEN - Generate signal pattern on SWD_DIO with SWD_CLK strobe
//
SIG_GEN:
	//
	// R0 = bit-count
	//
	LDI	r0, #0
	LBCO	r0.b0, CT_PRUDRAM, 1, 1
	//
	// R16..R23: Bit pattern (256-bit maximum)
	//
	LBCO	r16, CT_PRUDRAM, 4, 32
	//
	// Start with r16, from LSB
	MOV	r1.b0, &r16
	LDI	r2, #1
	MVID	r3, *r1.b0++
L_GEN_LOOP:
	SUB	r0, r0, 1
	LSL	r2, r2, 1
	QBBS	L_GEN_BIT1, r3.t0
	LSR	r3, r3, 1
	DRIVE_CLK_LOW
	DRIVE_DIO_LOW
	QBA	L_GEN_BIT_DONE
	//
L_NO_LOAD:
	NOP
	QBA	L_NEXT_BIT
	//
L_GEN_BIT1:
	LSR	r3, r3, 1
	DRIVE_CLK_LOW
	DRIVE_DIO_HIGH
	NOP
L_GEN_BIT_DONE:
	//
	QBNE	L_NO_LOAD, r2, 0
	MVID	r3, *r1.b0++
	LDI	r2, #1
L_NEXT_BIT:
	DRIVE_CLK_HIGH
	QBNE	L_GEN_LOOP, r0, 0
	//
L_SIG_GEN_DONE:
	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	//
	DRIVE_DIO_HIGH
	QBA	COMMAND_DONE

///////////////////////////////////////////////////////////////////////////
COMMAND_DONE:
	MOV	r31.b0, PRU0_ARM_INTERRUPT+16
	//
COMMAND_LOOP:
	// Wait until host wakes up PRU0
	SLP	1

	// Load values from data RAM into register R0
	LBCO	r0, CT_PRUDRAM, 0, 1

	QBBS	L_1xx, r0.t2
	QBBS	L_01x, r0.t1
	QBBS	L_001, r0.t0
L_000:	// Command HALT
	MOV	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	MOV	r31.b0, PRU0_ARM_INTERRUPT+16
	HALT
L_001:	// Command BLINK
	QBA	BLINK
L_01x:
	QBBS	L_011, r0.t0
L_010:	// Command GPIO_OUT
	QBA	GPIO_OUT
L_011:	// Command GPIO_IN
	QBA	GPIO_IN
L_1xx:
	QBBS	L_11x, r0.t1
	QBBS	L_101, r0.t0
L_100:	// Command SIG_IDLE
	QBA	SIG_IDLE
L_101:	// Command SIG_GEN
	QBA	SIG_GEN
L_11x:
	QBBS	L_111, r0.t0
L_110:	// Command READ_REG
	QBA	READ_REG
L_111:	// Command WRITE_REG
	QBA	WRITE_REG
///////////////////////////////////////////////////////////////////////////


//
// WRITE_SWD_DIO_BIT - Macro writing SWD_DIO bit
//
.macro	WRITE_SWD_DIO_BIT
.mparam	src_bit, label_bit1, label_done
	QBBS	label_bit1, src_bit
	DRIVE_CLK_LOW
	DRIVE_DIO_LOW
	QBA	label_done
label_bit1:
	DRIVE_CLK_LOW
	DRIVE_DIO_HIGH
	NOP
label_done:
	DRIVE_CLK_HIGH // <---- Target read
	NOP
.endm
//
// READ_SWD_DIO_BIT - Macro reading SWD_DIO bit onto register Rx
//
.macro	READ_SWD_DIO_BIT
.mparam	rx, ry, label_1, label_done, shift=1
	DRIVE_CLK_LOW
	LSR	rx, rx, shift
	LBBO	ry, r5, GPIO_DATAIN, 4
	DRIVE_CLK_HIGH // <---- Host ack
	QBBS	label_1, ry, SWD_DIO_BIT
	QBA	label_done
label_1:
	SET	rx, 31
label_done:
.endm
//
//	READ_REG - execute READ_REG transaction
//
READ_REG:
	//
	// R0 = command
	//
	LDI	r0, #0
	LBCO	r0.b0, CT_PRUDRAM, 1, 1
	LBCO	r0.b2, CT_PRUDRAM, 3, 1
	//
	//
	//
	WRITE_SWD_DIO_BIT r0.t0, L_RRC0_BIT1, L_RRC0_DONE
	WRITE_SWD_DIO_BIT r0.t1, L_RRC1_BIT1, L_RRC1_DONE
	WRITE_SWD_DIO_BIT r0.t2, L_RRC2_BIT1, L_RRC2_DONE
	WRITE_SWD_DIO_BIT r0.t3, L_RRC3_BIT1, L_RRC3_DONE
	WRITE_SWD_DIO_BIT r0.t4, L_RRC4_BIT1, L_RRC4_DONE
	WRITE_SWD_DIO_BIT r0.t5, L_RRC5_BIT1, L_RRC5_DONE
	WRITE_SWD_DIO_BIT r0.t6, L_RRC6_BIT1, L_RRC6_DONE
	WRITE_SWD_DIO_BIT r0.t7, L_RRC7_BIT1, L_RRC7_DONE
	//
	TRN_INPUT
	// Read ACK bits onto R3
	READ_SWD_DIO_BIT r3, r2, L_RRD0_1, L_RRD0_F
	READ_SWD_DIO_BIT r3, r2, L_RRD1_1, L_RRD1_F
	READ_SWD_DIO_BIT r3, r2, L_RRD2_1, L_RRD2_F
	// Read RDATA bits onto R4
	READ_SWD_DIO_BIT r4, r2, L_RRD3_1, L_RRD3_F
	READ_SWD_DIO_BIT r4, r2, L_RRD4_1, L_RRD4_F
	READ_SWD_DIO_BIT r4, r2, L_RRD5_1, L_RRD5_F
	READ_SWD_DIO_BIT r4, r2, L_RRD6_1, L_RRD6_F
	READ_SWD_DIO_BIT r4, r2, L_RRD7_1, L_RRD7_F
	READ_SWD_DIO_BIT r4, r2, L_RRD8_1, L_RRD8_F
	READ_SWD_DIO_BIT r4, r2, L_RRD9_1, L_RRD9_F
	READ_SWD_DIO_BIT r4, r2, L_RRDa_1, L_RRDa_F
	//
	READ_SWD_DIO_BIT r4, r2, L_RRDb_1, L_RRDb_F
	READ_SWD_DIO_BIT r4, r2, L_RRDc_1, L_RRDc_F
	READ_SWD_DIO_BIT r4, r2, L_RRDd_1, L_RRDd_F
	READ_SWD_DIO_BIT r4, r2, L_RRDe_1, L_RRDe_F
	READ_SWD_DIO_BIT r4, r2, L_RRDf_1, L_RRDf_F
	READ_SWD_DIO_BIT r4, r2, L_RRDg_1, L_RRDg_F
	READ_SWD_DIO_BIT r4, r2, L_RRDh_1, L_RRDh_F
	READ_SWD_DIO_BIT r4, r2, L_RRDi_1, L_RRDi_F
	//
	READ_SWD_DIO_BIT r4, r2, L_RRDj_1, L_RRDj_F
	READ_SWD_DIO_BIT r4, r2, L_RRDk_1, L_RRDk_F
	READ_SWD_DIO_BIT r4, r2, L_RRDl_1, L_RRDl_F
	READ_SWD_DIO_BIT r4, r2, L_RRDm_1, L_RRDm_F
	READ_SWD_DIO_BIT r4, r2, L_RRDn_1, L_RRDn_F
	READ_SWD_DIO_BIT r4, r2, L_RRDo_1, L_RRDo_F
	READ_SWD_DIO_BIT r4, r2, L_RRDp_1, L_RRDp_F
	READ_SWD_DIO_BIT r4, r2, L_RRDq_1, L_RRDq_F
	//
	READ_SWD_DIO_BIT r4, r2, L_RRDr_1, L_RRDr_F
	READ_SWD_DIO_BIT r4, r2, L_RRDs_1, L_RRDs_F
	READ_SWD_DIO_BIT r4, r2, L_RRDt_1, L_RRDt_F
	READ_SWD_DIO_BIT r4, r2, L_RRDu_1, L_RRDu_F
	READ_SWD_DIO_BIT r4, r2, L_RRDv_1, L_RRDv_F
	READ_SWD_DIO_BIT r4, r2, L_RRDw_1, L_RRDw_F
	READ_SWD_DIO_BIT r4, r2, L_RRDx_1, L_RRDx_F
	READ_SWD_DIO_BIT r4, r2, L_RRDy_1, L_RRDy_F
	// Parity bit
	READ_SWD_DIO_BIT r3, r2, L_RRDz_1, L_RRDz_F, 29
	//
	DRIVE_DIO_LOW
	TRN_OUTPUT
	//
	LSR	r0, r0, 16
	QBEQ	L_SKIP_IDLE_R, r0, 0
	LSL	r0, r0, 3
	JAL	r30.w0, DO_SIG_IDLE
	//
L_SKIP_IDLE_R:
	DRIVE_DIO_HIGH
	// RETURN: Parity|Ack, Value
	SBCO	r3, CT_PRUDRAM, 64, 8
	QBA	COMMAND_DONE

//
//	WRITE_REG - execute WRITE_REG transaction
//
WRITE_REG:
	//
	// R0 = command + parity_as_t8
	// R1 = value
	//
	LDI	r0, #0
	LBCO	r0.b0, CT_PRUDRAM, 1, 1
	LBCO	r0.b1, CT_PRUDRAM, 2, 1
	LBCO	r0.b2, CT_PRUDRAM, 3, 1
	LBCO	r1, CT_PRUDRAM, 4, 8
	//
	//
	WRITE_SWD_DIO_BIT r0.t0, L_WRC0_BIT1, L_WRC0_DONE
	WRITE_SWD_DIO_BIT r0.t1, L_WRC1_BIT1, L_WRC1_DONE
	WRITE_SWD_DIO_BIT r0.t2, L_WRC2_BIT1, L_WRC2_DONE
	WRITE_SWD_DIO_BIT r0.t3, L_WRC3_BIT1, L_WRC3_DONE
	WRITE_SWD_DIO_BIT r0.t4, L_WRC4_BIT1, L_WRC4_DONE
	WRITE_SWD_DIO_BIT r0.t5, L_WRC5_BIT1, L_WRC5_DONE
	WRITE_SWD_DIO_BIT r0.t6, L_WRC6_BIT1, L_WRC6_DONE
	WRITE_SWD_DIO_BIT r0.t7, L_WRC7_BIT1, L_WRC7_DONE
	//
	TRN_INPUT
	// Read ACK bits onto R3
	READ_SWD_DIO_BIT r3, r2, L_WRA0_1, L_WRA0_F
	READ_SWD_DIO_BIT r3, r2, L_WRA1_1, L_WRA1_F
	READ_SWD_DIO_BIT r3, r2, L_WRA2_1, L_WRA2_F
	//
	TRN_OUTPUT
	//
	WRITE_SWD_DIO_BIT r1.t0, L_WRD0_BIT1, L_WRD0_DONE
	WRITE_SWD_DIO_BIT r1.t1, L_WRD1_BIT1, L_WRD1_DONE
	WRITE_SWD_DIO_BIT r1.t2, L_WRD2_BIT1, L_WRD2_DONE
	WRITE_SWD_DIO_BIT r1.t3, L_WRD3_BIT1, L_WRD3_DONE
	WRITE_SWD_DIO_BIT r1.t4, L_WRD4_BIT1, L_WRD4_DONE
	WRITE_SWD_DIO_BIT r1.t5, L_WRD5_BIT1, L_WRD5_DONE
	WRITE_SWD_DIO_BIT r1.t6, L_WRD6_BIT1, L_WRD6_DONE
	WRITE_SWD_DIO_BIT r1.t7, L_WRD7_BIT1, L_WRD7_DONE
	WRITE_SWD_DIO_BIT r1.t8, L_WRD8_BIT1, L_WRD8_DONE
	WRITE_SWD_DIO_BIT r1.t9, L_WRD9_BIT1, L_WRD9_DONE
	WRITE_SWD_DIO_BIT r1.t10, L_WRDa_BIT1, L_WRDa_DONE
	WRITE_SWD_DIO_BIT r1.t11, L_WRDb_BIT1, L_WRDb_DONE
	WRITE_SWD_DIO_BIT r1.t12, L_WRDc_BIT1, L_WRDc_DONE
	WRITE_SWD_DIO_BIT r1.t13, L_WRDd_BIT1, L_WRDd_DONE
	WRITE_SWD_DIO_BIT r1.t14, L_WRDe_BIT1, L_WRDe_DONE
	WRITE_SWD_DIO_BIT r1.t15, L_WRDf_BIT1, L_WRDf_DONE
	WRITE_SWD_DIO_BIT r1.t16, L_WRDg_BIT1, L_WRDg_DONE
	WRITE_SWD_DIO_BIT r1.t17, L_WRDh_BIT1, L_WRDh_DONE
	WRITE_SWD_DIO_BIT r1.t18, L_WRDi_BIT1, L_WRDi_DONE
	WRITE_SWD_DIO_BIT r1.t19, L_WRDj_BIT1, L_WRDj_DONE
	WRITE_SWD_DIO_BIT r1.t20, L_WRDk_BIT1, L_WRDk_DONE
	WRITE_SWD_DIO_BIT r1.t21, L_WRDl_BIT1, L_WRDl_DONE
	WRITE_SWD_DIO_BIT r1.t22, L_WRDm_BIT1, L_WRDm_DONE
	WRITE_SWD_DIO_BIT r1.t23, L_WRDn_BIT1, L_WRDn_DONE
	WRITE_SWD_DIO_BIT r1.t24, L_WRDo_BIT1, L_WRDo_DONE
	WRITE_SWD_DIO_BIT r1.t25, L_WRDp_BIT1, L_WRDp_DONE
	WRITE_SWD_DIO_BIT r1.t26, L_WRDq_BIT1, L_WRDq_DONE
	WRITE_SWD_DIO_BIT r1.t27, L_WRDr_BIT1, L_WRDr_DONE
	WRITE_SWD_DIO_BIT r1.t28, L_WRDs_BIT1, L_WRDs_DONE
	WRITE_SWD_DIO_BIT r1.t29, L_WRDt_BIT1, L_WRDt_DONE
	WRITE_SWD_DIO_BIT r1.t30, L_WRDu_BIT1, L_WRDu_DONE
	WRITE_SWD_DIO_BIT r1.t31, L_WRDv_BIT1, L_WRDv_DONE
	WRITE_SWD_DIO_BIT r0.t8, L_WRDw_BIT1, L_WRDw_DONE
	LSR	r3, r3, 29
	//
	LSR	r0, r0, 16
	QBEQ	L_SKIP_IDLE_W, r0, 0
	LSL	r0, r0, 3
	DRIVE_DIO_LOW
	JAL	r30.w0, DO_SIG_IDLE
	//
L_SKIP_IDLE_W:
	DRIVE_DIO_HIGH
	// RETURN: Ack
	SBCO	r3, CT_PRUDRAM, 64, 4
	JMP	COMMAND_DONE
//
// Local Variables:
// compile-command: "pasm -V3 -l -b pru-swd.p"
// End:
//
