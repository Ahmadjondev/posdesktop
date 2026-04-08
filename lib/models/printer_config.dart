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
    this.ip = '',
    this.port = 9100,
    this.paperWidth = PaperWidth.mm80,
    this.codepage = 17, // CP866 for Cyrillic
    this.connectionType = ConnectionType.usb,
    this.usbMode = UsbMode.cups,
    this.cupsPrinterName = '',
    this.devicePath = '',
  });

  int get charsPerLine => paperWidth == PaperWidth.mm57 ? 32 : 48;

  /// Whether the printer has been explicitly configured by the user.
  bool get isConfigured {
    if (connectionType == ConnectionType.network) {
      return ip.isNotEmpty;
    }
    // USB mode
    if (usbMode == UsbMode.cups) {
      return cupsPrinterName.isNotEmpty;
    }
    return devicePath.isNotEmpty;
  }

  /// Human-readable label for the active connection target.
  String get connectionLabel {
    if (connectionType == ConnectionType.network) {
      return 'LAN $ip:$port';
    }
    if (usbMode == UsbMode.cups) {
      return 'USB "$cupsPrinterName"';
    }
    return 'USB $devicePath';
  }

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
    ip: json['ip'] as String? ?? '',
    port: json['port'] as int? ?? 9100,
    paperWidth: PaperWidth.values.firstWhere(
      (e) => e.name == json['paperWidth'],
      orElse: () => PaperWidth.mm80,
    ),
    codepage: json['codepage'] as int? ?? 17,
    connectionType: ConnectionType.values.firstWhere(
      (e) => e.name == json['connectionType'],
      orElse: () => ConnectionType.usb,
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

/// Configuration for a thermal barcode label printer (e.g. Xprinter XP-365B).
/// Uses TSPL protocol instead of ESC/POS.
class BarcodePrinterConfig {
  final String name;
  final String ip;
  final int port;
  final ConnectionType connectionType;
  final UsbMode usbMode;
  final String cupsPrinterName;
  final String devicePath;
  final int labelWidth; // mm
  final int labelHeight; // mm
  final int speed; // TSPL SPEED (1-10)
  final int density; // TSPL DENSITY (0-15)

  const BarcodePrinterConfig({
    this.name = 'Barcode Printer',
    this.ip = '',
    this.port = 9100,
    this.connectionType = ConnectionType.usb,
    this.usbMode = UsbMode.cups,
    this.cupsPrinterName = '',
    this.devicePath = '',
    this.labelWidth = 57,
    this.labelHeight = 40,
    this.speed = 4,
    this.density = 8,
  });

  bool get isConfigured {
    if (connectionType == ConnectionType.network) {
      return ip.isNotEmpty;
    }
    if (usbMode == UsbMode.cups) {
      return cupsPrinterName.isNotEmpty;
    }
    return devicePath.isNotEmpty;
  }

  String get connectionLabel {
    if (connectionType == ConnectionType.network) {
      return 'LAN $ip:$port';
    }
    if (usbMode == UsbMode.cups) {
      return 'USB "$cupsPrinterName"';
    }
    return 'USB $devicePath';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'connectionType': connectionType.name,
    'usbMode': usbMode.name,
    'cupsPrinterName': cupsPrinterName,
    'devicePath': devicePath,
    'labelWidth': labelWidth,
    'labelHeight': labelHeight,
    'speed': speed,
    'density': density,
  };

  factory BarcodePrinterConfig.fromJson(Map<String, dynamic> json) =>
      BarcodePrinterConfig(
        name: json['name'] as String? ?? 'Barcode Printer',
        ip: json['ip'] as String? ?? '',
        port: json['port'] as int? ?? 9100,
        connectionType: ConnectionType.values.firstWhere(
          (e) => e.name == json['connectionType'],
          orElse: () => ConnectionType.usb,
        ),
        usbMode: UsbMode.values.firstWhere(
          (e) => e.name == json['usbMode'],
          orElse: () => UsbMode.cups,
        ),
        cupsPrinterName: json['cupsPrinterName'] as String? ?? '',
        devicePath: json['devicePath'] as String? ?? '',
        labelWidth: json['labelWidth'] as int? ?? 57,
        labelHeight: json['labelHeight'] as int? ?? 40,
        speed: json['speed'] as int? ?? 4,
        density: json['density'] as int? ?? 8,
      );

  BarcodePrinterConfig copyWith({
    String? name,
    String? ip,
    int? port,
    ConnectionType? connectionType,
    UsbMode? usbMode,
    String? cupsPrinterName,
    String? devicePath,
    int? labelWidth,
    int? labelHeight,
    int? speed,
    int? density,
  }) => BarcodePrinterConfig(
    name: name ?? this.name,
    ip: ip ?? this.ip,
    port: port ?? this.port,
    connectionType: connectionType ?? this.connectionType,
    usbMode: usbMode ?? this.usbMode,
    cupsPrinterName: cupsPrinterName ?? this.cupsPrinterName,
    devicePath: devicePath ?? this.devicePath,
    labelWidth: labelWidth ?? this.labelWidth,
    labelHeight: labelHeight ?? this.labelHeight,
    speed: speed ?? this.speed,
    density: density ?? this.density,
  );
}
