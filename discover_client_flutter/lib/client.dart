import 'dart:io';
import 'dart:async';
import 'dart:convert';

class Client {

  final InternetAddress _ipv4Multicast = new InternetAddress("239.255.255.250");
  final InternetAddress _ipv6Multicast = new InternetAddress("FF05::C");
  List<RawDatagramSocket> _sockets = <RawDatagramSocket>[];
  Timer _discoverySearchTimer;

  Future createSocket(void Function(String) fn) async {
    List<NetworkInterface> _interfaces;
    _interfaces = await NetworkInterface.list();
    var wifiAddressPrefix = '192.168.0';
    var bindInterface;
    var bindAddress;

    // search a WiFi interface to bind
    for (var interface in _interfaces) {
      for (var ipInfo in interface.addresses) {
        if (ipInfo.address.startsWith(wifiAddressPrefix)) {
          bindInterface = interface;
          bindAddress = ipInfo.address;
        }
      }
    }

    if (bindAddress == null) {
      print("-- It was not able to find a WiFi interface ");
      return;
    }

    print(
        "-- It was able to find a WiFi interface named $bindInterface at addres $bindAddress");
    RawDatagramSocket _socket = await RawDatagramSocket.bind(bindAddress, 0);
    _socket.broadcastEnabled = true;
    _socket.multicastHops = 50;
    _socket.readEventsEnabled = true;

    _socket.listen((event) {
      print("-- listen(): received event " + event.toString());
      switch (event) {
        case RawSocketEvent.read:
          var packet = _socket.receive();
          _socket.writeEventsEnabled = true;
          _socket.writeEventsEnabled = true;

          if (packet == null) {
            return;
          }

          var data = utf8.decode(packet.data);
          print("-- listen(): data received");
          fn(data);
          break;
      }
    });

    try {
      _socket.joinMulticast(_ipv4Multicast, bindInterface);
    } on OSError {}

    try {
      _socket.joinMulticast(_ipv6Multicast, bindInterface);
    } on OSError {}
    _sockets.add(_socket);
  }

  void stop() {
    if (_discoverySearchTimer != null) {
      _discoverySearchTimer.cancel();
      _discoverySearchTimer = null;
    }
    for (var socket in _sockets) {
      socket.close();
    }
  }

  void request([String searchTarget]) {
    if (searchTarget == null) {
      searchTarget = "ssdp:all";
    }
    var buff = new StringBuffer();
    buff.write("M-SEARCH * HTTP/1.1\r\n");
    buff.write("HOST:239.255.255.250:1900\r\n");
    buff.write('MAN:"ssdp:discover"\r\n');
    buff.write("MX:1\r\n");
    buff.write("ST:$searchTarget\r\n\r\n");
    var data = utf8.encode(buff.toString());

    for (var socket in _sockets) {
      try {
        var res = socket.send(data, _ipv4Multicast, 1900);
        print("-- request(): sended bytes $res");
      } on SocketException {}
    }
  }

  Future<Null> search(query, void Function(String) fn) async {
    Duration searchInterval = const Duration(seconds: 5);
    if (_sockets.isEmpty) {
      await createSocket(fn);
      await new Future.delayed(const Duration(seconds: 1));
    }
    request(query);
    _discoverySearchTimer = new Timer.periodic(searchInterval, (_) {
      request(query);
    });
  }
}
