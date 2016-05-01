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

configuration WebC {

} implementation {
  components MainC, LedsC;
  components WebP;

  WebP.Boot -> MainC;
  WebP.Leds -> LedsC;

  components new TimerMilliC();
  components IPDispatchC;

  WebP.RadioControl -> IPDispatchC;
  
  components IPStackC;
    
  WebP.RadioControl -> IPStackC;
  
  components HttpdP;
  components new LtcpSocket() as TcpWeb;
  HttpdP.Boot -> MainC;
  HttpdP.Leds -> LedsC;
  HttpdP.Tcp -> TcpWeb;
  
  components RandomC;
  WebP.Random -> RandomC;
  
#ifdef PRINTFUART_ENABLED

  components SerialPrintfC;
  //components PrintfC;
  //components SerialStartC;
#endif
  
  
#ifdef RPL_ROUTING
  components RPLRoutingC;
#endif
  
}