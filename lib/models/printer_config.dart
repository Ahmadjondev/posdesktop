class PrinterConfig {
  final String name;
  final String ip;
  final int port;
  final PaperWidth paperWidth;
  final int codepage;
  final ConnectionType connectionType;
  final UsbMode usbMode;
  final String cupsPrinterName;
  final String devicePath;

  const PrinterConfig({
    this.name = 'Receipt Printer',
    this.ip = '192.168.0.150',
    this.port = 9100,
    this.paperWidth = PaperWidth.mm80,
    this.codepage = 17, // CP866 for Cyrillic
    this.connectionType = ConnectionType.network,
    this.usbMode = UsbMode.cups,
    this.cupsPrinterName = '',
    this.devicePath = '',
  });

  int get charsPerLine => paperWidth == PaperWidth.mm57 ? 32 : 48;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'paperWidth': paperWidth.name,
    'codepage': codepage,
    'connectionType': connectionType.name,
    'usbMode': usbMode.name,
    'cupsPrinterName': cupsPrinterName,
    'devicePath': devicePath,
  };

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
    name: json['name'] as String? ?? 'Receipt Printer',
    ip: json['ip'] as String? ?? '192.168.0.150',
    port: json['port'] as int? ?? 9100,
    paperWidth: PaperWidth.values.firstWhere(
      (e) => e.name == json['paperWidth'],
      orElse: () => PaperWidth.mm80,
    ),
    codepage: json['codepage'] as int? ?? 17,
    connectionType: ConnectionType.values.firstWhere(
      (e) => e.name == json['connectionType'],
      orElse: () => ConnectionType.network,
    ),
    usbMode: UsbMode.values.firstWhere(
      (e) => e.name == json['usbMode'],
      orElse: () => UsbMode.cups,
    ),
    cupsPrinterName: json['cupsPrinterName'] as String? ?? '',
    devicePath: json['devicePath'] as String? ?? '',
  );

  PrinterConfig copyWith({
    String? name,
    String? ip,
    int? port,
    PaperWidth? paperWidth,
    int? codepage,
    ConnectionType? connectionType,
    UsbMode? usbMode,
    String? cupsPrinterName,
    String? devicePath,
  }) => PrinterConfig(
    name: name ?? this.name,
    ip: ip ?? this.ip,
    port: port ?? this.port,
    paperWidth: paperWidth ?? this.paperWidth,
    codepage: codepage ?? this.codepage,
    connectionType: connectionType ?? this.connectionType,
    usbMode: usbMode ?? this.usbMode,
    cupsPrinterName: cupsPrinterName ?? this.cupsPrinterName,
    devicePath: devicePath ?? this.devicePath,
  );
}

enum PaperWidth { mm57, mm80 }

enum ConnectionType { network, usb }

enum UsbMode { cups, file }
