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
static const unsigned swd_seq_line_reset_len = 52;

static const uint8_t swd_seq_jtag_to_swd[] = {
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7b, 0x9e,
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x0f,
};
static const unsigned swd_seq_jtag_to_swd_len = 118;

uint32_t my_mem[65536];

static void
cacheflush (void)
{
  int i;

  /*
   * __clear_cache doesn't work with unknown reason.
   * So, I write this function to invalidate data cache.
   */
  asm volatile ("" : : "r" (my_mem) : "memory"); /* my_mem is in use */
  for (i = 0; i < 65536; i++)
    my_mem[i] = my_mem[(i+1)&65536];
}

static void
pru_request_cmd (uint32_t *p)
{
  /* 
   * Memory is shared between Main CPU and PRUs.
   * 
   * (1) We need to avoid confusing the compiler as if the memory is
   *     usual one.  To do so, we put asm with "memory" clobber.
   *     This is to ensure register value to be on the memory.
   *
   * (2) In case data could be on cache and not yet onto the memory,
   *     we place calling to cacheflush function.
   */
  asm volatile ("" : : : "memory");
  cacheflush ();

  /* Wakeup the PRU0 which sleeps.  */
  prussdrv_pru_send_event (ARM_PRU0_INTERRUPT);
  /*
   * prussdrv_pru_send_event may be buggy, I only see the write access
   * to memory, but no cache flushing.
   */
  cacheflush ();

  /* Wait PRU0 response.  */
  prussdrv_pru_wait_event (PRU_EVTOUT_0);
  prussdrv_pru_clear_event (PRU_EVTOUT_0, PRU0_ARM_INTERRUPT);

  printf ("Request (%08x:%08x) done\n", p[0], p[1]);
  cacheflush ();
}

static void
idle_cycle (uint32_t *p, int n)
{
  p[0] = 0x04;
  p[1] = 8;
  pru_request_cmd (p);
}

static const uint8_t even_parity_table[] = {
  0x00, 0x10, 0x10, 0x00, 0x10, 0x00, 0x00, 0x10,
  0x10, 0x00, 0x00, 0x10, 0x00, 0x10, 0x10, 0x00
};

static int
parity_32 (uint32_t v)
{
  uint8_t e;

  e = (v & 0xff);
  e ^= ((v >> 8) & 0xff);
  e ^= ((v >> 16) & 0xff);
  e ^= ((v >> 24) & 0xff);
  e ^= (e >> 4);
  return even_parity_table[e&0x0f] != 0;
}


#define DAP_IDCODE_RD           0x02
#define DAP_ABORT_WR            0x00
#define DAP_CTRLSTAT_RD         0x06
#define DAP_CTRLSTAT_WR         0x04
#define DAP_SELECT_WR           0x08
#define DAP_RDBUFF_RD           0x0E

static uint8_t
req_byte (uint8_t dap_addr)
{
  uint8_t req;

  req = dap_addr & 0x0f;
  req |= even_parity_table[req];
  req <<= 1;
  req |= 0x81;
  return req;
}

static int
ap_access (uint8_t dap_addr)
{
  return (dap_addr & 0x02) == 0;
}

static void
submit_write_cmd (uint32_t *p, uint8_t dap_addr, uint32_t value)
{
  uint8_t delay = ap_access (dap_addr) ? 8 : 0;
  uint8_t parity = parity_32 (value);

  p[0] = 0x07 | (req_byte (dap_addr) << 8) | (parity << 16) | (delay << 24);
  p[1] = value;
  pru_request_cmd (p);
  printf ("submit_write_cmd: ack= %08x\n", p[16]);
}

static uint32_t
submit_read_cmd (uint32_t *p, uint8_t dap_addr)
{
  uint8_t delay = ap_access (dap_addr) ? 8 : 0;

  p[0] = 0x06 | (req_byte (dap_addr) << 8) | (0 << 16) | (delay << 24);
  pru_request_cmd (p);
  printf ("submit_read_cmd: parity-ack= %08x, value=%08x\n", p[16], p[16+1]);
  return p[16+1];
}

/* MEM-AP register addresses */
#define MEM_AP_CSW  0x01
#define MEM_AP_TAR  0x05
#define MEM_AP_DRW_WR  0x0D
#define MEM_AP_DRW_RD  0x0F

/* Cortex M3 Debug Registers (AHB addresses) */
#define DDFSR   0xE000ED30 /* Debug Fault StatusRegister                   */
#define DHCSR   0xE000EDF0 /* Debug Halting Control and Status Register    */
#define DCRSR   0xE000EDF4 /* Debug Core Register Selector Register        */
#define DCRDR   0xE000EDF8 /* Debug Core Register Data Register            */
#define DEMCR   0xE000EDFC /* Debug Exception and Monitor Control Register */
#define AIRCR   0xE000ED0C /* The Application Interrupt and Reset Control Register */

#define CPUID	0xE000ED00 /* CPU Identification Register */

static void
mcu_halt (uint32_t *p)
{
  puts ("Halting MCU...");

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* DHCSR.C_DEBUGEN = 1, C_HALT =1 */
  submit_write_cmd (p, MEM_AP_TAR, DHCSR);
  submit_write_cmd (p, MEM_AP_DRW_WR, 0xA05F0003);

  puts ("Halting MCU...done");
}

static void
mcu_reset (uint32_t *p)
{
  puts ("Reseting MCU...");

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* Reset the core */
  submit_write_cmd (p, MEM_AP_TAR, AIRCR);
  submit_write_cmd (p, MEM_AP_DRW_WR, 0x05FA0004);

  puts ("Reseting MCU...done");
}

static uint32_t 
read_cpuid (uint32_t *p)
{
  uint32_t v;

  puts ("Reading MCU ID...");

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* Read the value from CPUID */
  submit_write_cmd (p, MEM_AP_TAR, CPUID);
  v = submit_read_cmd (p, MEM_AP_DRW_RD);

  puts ("Reading MCU ID...done");
  return v;
}

static uint32_t 
read_arm_reg (uint32_t *p, int n)
{
  uint32_t v;

  printf ("Reading register %d on MCU...\n", n);

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* Write the register number to DCRSR */
  submit_write_cmd (p, MEM_AP_TAR, DCRSR);
  submit_write_cmd (p, MEM_AP_DRW_WR, n);

  /* Read the value from DCRDR */
  submit_write_cmd (p, MEM_AP_TAR, DCRDR);
  v = submit_read_cmd (p, MEM_AP_DRW_RD);

  printf ("Reading register %d on MCU...done\n", n);
  return v;
}

static void
write_arm_reg  (uint32_t *p, int n, uint32_t value)
{
  printf ("Writing register %d on MCU...\n", n);

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* Write the value to DCRDR */
  submit_write_cmd (p, MEM_AP_TAR, DCRDR);
  submit_write_cmd (p, MEM_AP_DRW_WR, value);

  /* Write the register number to DCRSR */
  submit_write_cmd (p, MEM_AP_TAR, DCRSR);
  submit_write_cmd (p, MEM_AP_DRW_WR, n | 0x10000);

  printf ("Writing register %d on MCU...done\n", n);
}


static uint32_t 
read_mem (uint32_t *p, uint32_t addr)
{
  uint32_t v;

  printf ("Reading memory %08x...\n", addr);

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* Read from ADDR */
  submit_write_cmd (p, MEM_AP_TAR, addr);
  v = submit_read_cmd (p, MEM_AP_DRW_RD);

  printf ("Reading memory %08x...done\n", addr);
  return v;
}

static void
write_mem  (uint32_t *p, uint32_t addr, uint32_t value)
{
  printf ("Writing memory %08x on MCU...\n", addr);

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Specify 32 bit memory access, auto increment */
  submit_write_cmd (p, MEM_AP_CSW, 0x23000002);

  /* Write the value to ADDR */
  submit_write_cmd (p, MEM_AP_TAR, addr);
  submit_write_cmd (p, MEM_AP_DRW_WR, value);

  printf ("Writing memory %08x on MCU...\n", addr);
}


int
main (void)
{
  unsigned int r;
  tpruss_intc_initdata pruss_intc_initdata = PRUSS_INTC_INITDATA;
  void *pru_data_ram;
  uint32_t *p;
  uint32_t u;

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
   * LINE RESET
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

  u = submit_read_cmd (p, DAP_IDCODE_RD);
  printf ("DAP ID: %08x\n", u);

  puts ("Abort (clear errors)");
  submit_write_cmd (p, DAP_ABORT_WR, 0x0000001e);
  idle_cycle (p, 8);

  /* Select memory access port bank 0 */
  submit_write_cmd (p, DAP_SELECT_WR, 0x00000000);

  /* Enable the debug hardware */
  submit_write_cmd (p, DAP_CTRLSTAT_WR, 0x54000000);
  u = submit_read_cmd (p, DAP_CTRLSTAT_RD);
  printf ("STAT: %08x\n", u);

  mcu_halt (p);

  u = read_cpuid (p);
  printf ("CPUID = %08x\n", u);

  puts ("Read/Write register.");
  u = read_arm_reg (p, 0); 
  printf ("R0 value = %08x\n", u);
  write_arm_reg (p, 0, 0xdeadbeaf);
  u = read_arm_reg (p, 0); 
  printf ("R0 value = %08x\n", u);

  puts ("Read/Write SRAM at 0x20000000.");
  u = read_mem (p, 0x20000000);
  printf ("Value = %08x\n", u);
  write_mem (p, 0x20000000, 0x12345678);
  u = read_mem (p, 0x20000000);
  printf ("Value = %08x\n", u);

  puts ("Read flash memory at 0x08000000.");
  u = read_mem (p, 0x08000000);
  printf ("Value = %08x\n", u);

  mcu_reset (p);

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
