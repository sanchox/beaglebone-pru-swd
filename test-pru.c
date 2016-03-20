/*
 * test-pru.c - Test program for pru-swd
 *
 * Copyright (C) 2016  Flying Stone Technology
 * Author: NIIBE Yutaka <gniibe@fsij.org>
 *
 * This file is a part of BBG-SWD, a SWD tool for BeagleBoneGreen.
 *
 * BBG-SWD is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * BBG-SWD is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

#include <prussdrv.h>
#include <pruss_intc_mapping.h>

#define PRU_NUM 	 0

/* 
 * Signal pattern is defined in:
 * ARM Debug Interface Architecture Specification (ADI)
 */
static const uint8_t swd_seq_line_reset[] = {
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x03
};
static const unsigned swd_seq_line_reset_len = 56;

static const uint8_t swd_seq_jtag_to_swd[] = {
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7b, 0x9e,
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x0f,
};
static const unsigned swd_seq_jtag_to_swd_len = 118;

static void
pru_request_cmd (uint32_t *p)
{
  /* Wakeup the PRU0 which sleeps.  */
  prussdrv_pru_send_event (ARM_PRU0_INTERRUPT);

  /* Wait PRU0 response.  */
  prussdrv_pru_wait_event (PRU_EVTOUT_0);
  prussdrv_pru_clear_event (PRU_EVTOUT_0, PRU0_ARM_INTERRUPT);

  printf ("Request (%08x) done\n", *p);
}


int
main (void)
{
  unsigned int r;
  tpruss_intc_initdata pruss_intc_initdata = PRUSS_INTC_INITDATA;
  void *pru_data_ram;
  uint32_t *p;

  puts ("Start testing PRUSS for SWD protocol");

  /* Initialize the PRU.  */
  prussdrv_init ();

  /* Open PRU interrupt to Host.  */
  r = prussdrv_open (PRU_EVTOUT_0);
  if (r)
    {
      printf ("prussdrv_open open failed: %d\n", r);
      exit (1);
    }

  /* Initialize PRU interrupt controller.  */
  prussdrv_pruintc_init (&pruss_intc_initdata);

  /* Initialize PRU memory access from Host.  */
  prussdrv_map_prumem (PRUSS0_PRU0_DATARAM, &pru_data_ram);
  p = pru_data_ram;

  /* Execute example on PRU */
  puts ("Started execution of PRU-SWU program on PRUSS");
  prussdrv_exec_program (PRU_NUM, "./pru-swd.bin");

  /*
   * RESET
   */
  p[0] = 0x05 | (swd_seq_line_reset_len << 8);
  memcpy (&p[1], swd_seq_line_reset, sizeof swd_seq_line_reset);
  pru_request_cmd (p);

  /*
   * JTAG-to-SWD
   */
  p[0] = 0x05 | (swd_seq_jtag_to_swd_len << 8);
  memcpy (&p[1], swd_seq_jtag_to_swd, sizeof swd_seq_jtag_to_swd);
  pru_request_cmd (p);

  /* READ_REG: IDCODE, idle=0 */
  p[0] = 0x06 | (0xa5 << 8) | (0 << 24);
  pru_request_cmd (p);
  printf ("parity-ack= %08x\n", p[16]);
  printf ("value = %08x\n", p[16+1]);

  /* WRITE_REG: ABORT, idle=0 */
  p[0] = 0x07 | (0x81 << 8) | (0 << 16) | (0 << 24);
  p[1] = 0x1e;
  pru_request_cmd (p);
  printf ("ack= %08x\n", p[16]);

  /*
   * IDLE
   */
  p[0] = 0x04;
  p[1] = 8;
  pru_request_cmd (p);

  /* WRITE_REG: SELECT, idle=0 */
  p[0] = 0x07 | (0xb1 << 8) | (0 << 16) | (0 << 24);
  p[1] = 0;
  pru_request_cmd (p);
  printf ("ack= %08x\n", p[16]);

  /* WRITE_REG: STAT, idle=0 */
  p[0] = 0x07 | (0xa9 << 8) | (1 << 16) | (0 << 24);
  p[1] = 0x54000000;
  pru_request_cmd (p);
  printf ("ack= %08x\n", p[16]);

  /* READ_REG: STAT, idle=0 */
  p[0] = 0x06 | (0x8d << 8) | (0 << 24);
  pru_request_cmd (p);
  printf ("parity-ack= %08x\n", p[16]);
  printf ("value = %08x\n", p[16+1]);

  /* Finally, celebrate with USR3 LED blinking.  */
  p[0] = 0x01;
  p[1] = 0x00800000;
  p[2] = 10;
  p[3] = 1<<24;
  pru_request_cmd (p);

  p[0] = 0x00;			/* HALT */
  pru_request_cmd (p);

  /* Disable PRU.  */
  prussdrv_pru_disable (PRU_NUM);
  prussdrv_exit ();

  return 0;
}
/*
 * Local Variables:
 * compile-command: "gcc -Wall -D__DEBUG -O2 -mtune=cortex-a8 -march=armv7-a -o test-pru test-pru.c -lprussdrv"
 * End:
 */
