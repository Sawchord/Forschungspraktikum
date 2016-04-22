/* Coypright 2016 Leon Tan
 * Licensed unser GPLv2
 */
#include <lib6lowpan/6lowpan.h>
#include <Ltcp.h>

configuration TCPEchoC {

} implementation {
    components MainC, LedsC;
    components TCPEchoP;
    
    TCPEchoP.Boot -> MainC;
    TCPEchoP.Leds -> LedsC;
    
    //TCPEchoP.Init -> MainC;
    
    components new TimerMilliC();
    components IPStackC;
    
    TCPEchoP.RadioControl -> IPStackC;
    
    components new LtcpSocket() as Echo;
    
    TCPEchoP.Echo -> Echo;
    
    TCPEchoP.StatusTimer -> TimerMilliC;
    
    components LtcpC, IPDispatchC;
    //TCPEchoP.IPStats -> IPDispatchC;
    //TCPEchoP.TCPStats -> TcpC;
    
#ifdef RPL_ROUTING
    components RPLRoutingC;
#endif

    components RandomC;
    TCPEchoP.Random -> RandomC;

    // UDP shell on port 2000 FIXME: Works?
    // components UDPShellC;

    // prints the routing table
    //components RouteCmdC;
#ifndef  IN6_PREFIX
    components DhcpCmdC;
#endif

    //components PrintfC;
    //components SerialStartC;
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
