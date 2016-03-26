//							-*- mode: asm -*-
// simple-rr.p - PRU program to do request-response
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

#define GPIO1_BASE_0100   0x4804c100
// offsets
#define GPIO_OE			0x34
#define GPIO_DATAIN		0x38
#define GPIO_CLEARDATAOUT	0x90
#define GPIO_SETDATAOUT		0x94

// LED
// bit 21: USR0, 22: USR1, 23: USR2, 24: USR3


#define CTBIR_0         0x22020

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
L_010:	// Command RETURN_00
	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	SBCO	r0, CT_PRUDRAM, 64+4, 4
	QBA	COMMAND_DONE
L_011:	// Command RETURN FF
	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	LDI	r0, #0xFF
	SBCO	r0, CT_PRUDRAM, 64+4, 4
	QBA	COMMAND_DONE
L_1xx:  // Command NULL
	LDI	r0, #0
	SBCO	r0, CT_PRUDRAM, 64, 4
	QBA	COMMAND_DONE
///////////////////////////////////////////////////////////////////////////

//
// Local Variables:
// compile-command: "pasm -V3 -l -b simple-rr.p"
// End:
//
