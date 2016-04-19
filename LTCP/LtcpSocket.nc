
generic configuration LtcpSocket() {
  provides interface Ltcp;
} implementation {

  components LtcpC;

  Ltcp = LtcpC.Ltcp[unique("TCP_CLIENT")];
  
}
