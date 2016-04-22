/* "Copyright (c) 2016 
 * Leon Tan 
 * Georg-August University of Goettingen
 * All rights reserved"
 * 
 * Permission to use, copy, modify, and distribute this software and its
 * documentation for any purpose, without fee, and without written agreement is
 * hereby granted, provided that the above copyright notice, the following
 * two paragraphs and the author appear in all copies of this software.
 *
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR
 * DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT
 * OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR 
 * HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.  THE SOFTWARE PROVIDED HEREUNDER IS
 * ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATION TO
 * PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS."
 * 
 */
 
#include <lib6lowpan/6lowpan.h>
#include <Ltcp.h>

configuration SerialTCPC {
} implementation {
  components MainC, LedsC;
  components SerialTCPP;
  
  SerialTCPP.Boot -> MainC;
  SerialTCPP.Leds -> LedsC;
  
  components new TimerMilliC();
  components IPStackC;
  
  SerialTCPP.RadioControl -> IPStackC;
  
  components new LtcpSocket() as Connection;
  
  SerialTCPP.Connection -> Connection;
  SerialTCPP.Timer0 -> TimerMilliC;
  
  components LtcpC, IPDispatchC;
  
#ifdef RPL_ROUTING
    components RPLRoutingC;
#endif

#ifndef  IN6_PREFIX
    components DhcpCmdC;
#endif

#ifdef PRINTFUART_ENABLED

    components SerialPrintfC;
    /* This is the alternative printf implementation which puts the
    * output in framed tinyos serial messages.  This lets you operate
    * alongside other users of the tinyos serial stack.
    */
    //components PrintfC;
    //components SerialStartC;
#endif

}