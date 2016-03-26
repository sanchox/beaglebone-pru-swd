/*
 * test-uio_pruss-bug.c - Test program for UIO PRUSS
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

static uint32_t
pru_request_cmd (uint32_t *p, int flush)
{
  uint32_t u;
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
  switch (flush)
    {
    case 0:
      break;
    case 1:
      __clear_cache (p, p+17);
      break;
    case 2:
      cacheflush ();
      break;
    }

  /* Wakeup the PRU0 which sleeps.  */
  prussdrv_pru_send_event (ARM_PRU0_INTERRUPT);
  /*
   * prussdrv_pru_send_event may be buggy, I only see the write access
   * to memory, but no cache flushing.
   */
  switch (flush)
    {
    case 0:
      break;
    case 1:
      __clear_cache (p, p+17);
      break;
    case 2:
      cacheflush ();
      break;
    }

  /* Wait PRU0 response.  */
  prussdrv_pru_wait_event (PRU_EVTOUT_0);
  prussdrv_pru_clear_event (PRU_EVTOUT_0, PRU0_ARM_INTERRUPT);
  asm volatile ("" : : "r" (p[16]) : "memory");

  if (p[0] == 0x0f)
    u = p[16];
  else
    {
      u = p[16];
      asm volatile ("" : : "r" (u) : "memory");
      switch (flush)
	{
	case 0:
	  u = p[16+1];
	  break;
	case 1:
	  __clear_cache (p, p+17);
	  u = p[16+1];
	  break;
	default:
	case 2:
	  cacheflush ();
	  u = p[16+1];
	  break;
	}
    }

  return u;
}

int
main (void)
{
  unsigned int r;
  tpruss_intc_initdata pruss_intc_initdata = PRUSS_INTC_INITDATA;
  void *pru_data_ram;
  uint32_t *p;
  int i, j;

  puts ("Start testing PRUSS with simple request-response communication");

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
  puts ("Started execution of SIMPLE-RR program on PRUSS");
  prussdrv_exec_program (PRU_NUM, "./simple-rr.bin");

  /* Run */
  for (i = 0; i < 3; i++)
    {
      uint32_t u, v;

      switch (i)
	{
	case 0:
	  puts ("Cache not-flushed");
	  break;
	case 1:
	  puts ("Cache flushed by __clear_cache");
	  break;
	case 2:
	  puts ("Cache flushed by mem");
	  break;
	}
      for (j = 0; j < 1000; j++)
	{
	  p[0] = 0x0f;
	  u = pru_request_cmd (p, i);

	  p[0] = 0x03;
	  u = pru_request_cmd (p, i);
	  asm ("ldr	%0, [%1, #68]" : "=r" (v) : "r" (p), "r" (u));

	  p[0] = 0x02;
	  u = pru_request_cmd (p, i);

	  p[0] = 0x03;
	  u = pru_request_cmd (p, i);
	  asm ("ldr	%0, [%1, #68]" : "=r" (v) : "r" (p), "r" (u));

	  p[0] = 0x02;
	  u = pru_request_cmd (p, i);

	  p[0] = 0x03;
	  u = pru_request_cmd (p, i);

	  p[0] = 0x02;
	  u = pru_request_cmd (p, i);
	  cacheflush ();
	  asm ("ldr	%0, [%1, #68]" : "=r" (v) : "r" (p), "r" (u));
	  if (u != v)
	    printf ("!!Read-Again differs: %02x != %02x\n", u&0xff, v&0xff);

	  p[0] = 0x0f;
	  u = pru_request_cmd (p, i);

	  p[0] = 0x02;
	  u = pru_request_cmd (p, i);

	  p[0] = 0x03;
	  u = pru_request_cmd (p, i);
	  cacheflush ();
	  asm ("ldr	%0, [%1, #68]" : "=r" (v) : "r" (p), "r" (u));
	  if (u != v)
	    printf ("!!Read-Again differs: %02x != %02x\n", u&0xff, v&0xff);
	}
    }

  /* Finally, celebrate with USR3 LED blinking.  */
  p[0] = 0x01;
  p[1] = 0x00800000;
  p[2] = 10;
  p[3] = 1<<24;
  pru_request_cmd (p, 2);

  p[0] = 0x00;			/* HALT */
  pru_request_cmd (p, 2);

  /* Disable PRU.  */
  prussdrv_pru_disable (PRU_NUM);
  prussdrv_exit ();

  return 0;
}
/*
 * Local Variables:
 * compile-command: "gcc -Wall -D__DEBUG -O2 -mtune=cortex-a8 -march=armv7-a -o test-uio_pruss-bug test-uio_pruss-bug.c -lprussdrv"
 * End:
 */
