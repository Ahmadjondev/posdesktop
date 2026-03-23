import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../models/printer_config.dart';
import '../services/printer_service.dart';
import '../services/settings_service.dart';

final _log = Logger('SettingsScreen');

/// Settings screen: configure POS URL, printer IP/port, paper width, and auto-start.
class SettingsScreen extends StatefulWidget {
  final SettingsService settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _printer = PrinterService();

  late final TextEditingController _urlCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _devicePathCtrl;

  late PaperWidth _paperWidth;
  late int _codepage;
  late bool _autoStart;
  late ConnectionType _connectionType;
  late UsbMode _usbMode;
  String? _selectedCupsPrinter;
  List<String> _availablePrinters = [];
  bool _isLoadingPrinters = false;

  String? _selectedUsbPort;
  List<String> _availableUsbPorts = [];
  bool _isLoadingUsbPorts = false;

  bool _isTesting = false;
  bool _isSaving = false;
  bool _urlChanged = false;

  @override
  void initState() {
    super.initState();
    final config = widget.settings.printerConfig;
    _urlCtrl = TextEditingController(text: widget.settings.posUrl);
    _ipCtrl = TextEditingController(text: config.ip);
    _portCtrl = TextEditingController(text: config.port.toString());
    _nameCtrl = TextEditingController(text: config.name);
    _devicePathCtrl = TextEditingController(text: config.devicePath);
    _paperWidth = config.paperWidth;
    _codepage = config.codepage;
    _autoStart = widget.settings.autoStart;
    _connectionType = config.connectionType;
    _usbMode = config.usbMode;
    _selectedCupsPrinter = config.cupsPrinterName.isNotEmpty
        ? config.cupsPrinterName
        : null;
    _selectedUsbPort = config.devicePath.isNotEmpty
        ? config.devicePath
        : null;

    // Auto-load CUPS printers if in USB+CUPS mode
    if (_connectionType == ConnectionType.usb && _usbMode == UsbMode.cups) {
      _loadPrinters();
    }
    // Auto-load USB ports if in USB+file mode on Windows
    if (_connectionType == ConnectionType.usb &&
        _usbMode == UsbMode.file &&
        Platform.isWindows) {
      _loadUsbPorts();
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    _devicePathCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrinters() async {
    setState(() => _isLoadingPrinters = true);
    try {
      final printers = await _printer.listCupsPrinters();
      if (!mounted) return;
      setState(() {
        _availablePrinters = printers;
        // Keep selection if still valid
        if (_selectedCupsPrinter != null &&
            !printers.contains(_selectedCupsPrinter)) {
          _selectedCupsPrinter = printers.isNotEmpty ? printers.first : null;
        }
      });
    } finally {
      if (mounted) setState(() => _isLoadingPrinters = false);
    }
  }

  Future<void> _loadUsbPorts() async {
    setState(() => _isLoadingUsbPorts = true);
    try {
      final ports = await _printer.listWindowsUsbPorts();
      if (!mounted) return;
      setState(() {
        _availableUsbPorts = ports;
        if (_selectedUsbPort != null &&
            !ports.contains(_selectedUsbPort)) {
          _selectedUsbPort = ports.isNotEmpty ? ports.first : null;
        }
        if (_selectedUsbPort != null) {
          _devicePathCtrl.text = _selectedUsbPort!;
        }
      });
    } finally {
      if (mounted) setState(() => _isLoadingUsbPorts = false);
    }
  }

  PrinterConfig _buildConfig() => PrinterConfig(
    name: _nameCtrl.text.trim(),
    ip: _ipCtrl.text.trim(),
    port: int.tryParse(_portCtrl.text.trim()) ?? 9100,
    paperWidth: _paperWidth,
    codepage: _codepage,
    connectionType: _connectionType,
    usbMode: _usbMode,
    cupsPrinterName: _selectedCupsPrinter ?? '',
    devicePath: _devicePathCtrl.text.trim(),
  );

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      final config = _buildConfig();
      final ok = await _printer.testConnection(config);
      if (!mounted) return;

      String message;
      if (ok) {
        if (config.connectionType == ConnectionType.network) {
          message =
              'Printer ${config.ip}:${config.port} ga muvaffaqiyatli ulandi!';
        } else if (config.usbMode == UsbMode.cups) {
          message = 'CUPS printer "${config.cupsPrinterName}" topildi!';
        } else {
          message = 'Qurilma "${config.devicePath}" mavjud!';
        }
      } else {
        if (config.connectionType == ConnectionType.network) {
          message = 'Printerga ulanib bo\'lmadi. IP va portni tekshiring.';
        } else if (config.usbMode == UsbMode.cups) {
          message = 'CUPS printer "${config.cupsPrinterName}" topilmadi.';
        } else {
          message = 'Qurilma "${config.devicePath}" topilmadi.';
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _printTestPage() async {
    setState(() => _isTesting = true);
    try {
      final config = _buildConfig();
      final result = await _printer.printTestPage(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? 'Test sahifa chop etildi!'
                : 'Xatolik: ${result.error}',
          ),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final newUrl = _urlCtrl.text.trim();
      _urlChanged = newUrl != widget.settings.posUrl;

      await widget.settings.setPosUrl(newUrl);
      await widget.settings.setPrinterConfig(_buildConfig());
      await widget.settings.setAutoStart(_autoStart);

      // Handle auto-start on Windows
      await _updateAutoStart(_autoStart);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sozlamalar saqlandi!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(_urlChanged);
    } catch (e) {
      _log.severe('Save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saqlashda xatolik: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateAutoStart(bool enable) async {
    if (!Platform.isWindows) return;

    try {
      final exe = Platform.resolvedExecutable;
      if (enable) {
        await Process.run('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'DigitexPOS',
          '/t',
          'REG_SZ',
          '/d',
          '"$exe"',
          '/f',
        ]);
        _log.info('Auto-start enabled');
      } else {
        await Process.run('reg', [
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'DigitexPOS',
          '/f',
        ]);
        _log.info('Auto-start disabled');
      }
    } catch (e) {
      _log.warning('Failed to update auto-start: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sozlamalar'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Saqlash'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── POS URL ───────────────────────────────────────────
              Text(
                'POS Web Manzil',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://demo.digitex.uz/',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'URL kiritilishi shart';
                  final uri = Uri.tryParse(v.trim());
                  if (uri == null || !uri.hasScheme)
                    return 'Noto\'g\'ri URL formati';
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // ── Printer ───────────────────────────────────────────
              Text(
                'Printer Sozlamalari',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Printer nomi',
                  prefixIcon: Icon(Icons.print),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // ── Connection type toggle ────────────────────────────
              SegmentedButton<ConnectionType>(
                segments: const [
                  ButtonSegment(
                    value: ConnectionType.network,
                    label: Text('Tarmoq (LAN)'),
                    icon: Icon(Icons.router),
                  ),
                  ButtonSegment(
                    value: ConnectionType.usb,
                    label: Text('USB'),
                    icon: Icon(Icons.usb),
                  ),
                ],
                selected: {_connectionType},
                onSelectionChanged: (v) {
                  setState(() => _connectionType = v.first);
                  if (v.first == ConnectionType.usb &&
                      _usbMode == UsbMode.cups &&
                      _availablePrinters.isEmpty) {
                    _loadPrinters();
                  }
                },
              ),
              const SizedBox(height: 12),

              // ── Network fields ────────────────────────────────────
              if (_connectionType == ConnectionType.network) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _ipCtrl,
                        decoration: const InputDecoration(
                          labelText: 'IP manzil',
                          hintText: '192.168.0.150',
                          prefixIcon: Icon(Icons.router),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (_connectionType != ConnectionType.network) {
                            return null;
                          }
                          if (v == null || v.trim().isEmpty) {
                            return 'IP kiritilishi shart';
                          }
                          final parts = v.trim().split('.');
                          if (parts.length != 4 ||
                              parts.any((p) => int.tryParse(p) == null)) {
                            return 'Noto\'g\'ri IP format';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _portCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '9100',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (_connectionType != ConnectionType.network) {
                            return null;
                          }
                          final port = int.tryParse(v ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return 'Port: 1-65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],

              // ── USB fields ────────────────────────────────────────
              if (_connectionType == ConnectionType.usb) ...[
                SegmentedButton<UsbMode>(
                  segments: [
                    ButtonSegment(
                      value: UsbMode.cups,
                      label: Text(
                        Platform.isWindows
                            ? 'Windows Printer'
                            : 'Tizim printeri (CUPS)',
                      ),
                      icon: const Icon(Icons.print),
                    ),
                    ButtonSegment(
                      value: UsbMode.file,
                      label: Text(
                        Platform.isWindows
                            ? 'Port (COM/USB)'
                            : 'Qurilma (to\'g\'ridan)',
                      ),
                      icon: const Icon(Icons.settings_ethernet),
                    ),
                  ],
                  selected: {_usbMode},
                  onSelectionChanged: (v) {
                    setState(() => _usbMode = v.first);
                    if (v.first == UsbMode.cups && _availablePrinters.isEmpty) {
                      _loadPrinters();
                    }
                    if (v.first == UsbMode.file &&
                        Platform.isWindows &&
                        _availableUsbPorts.isEmpty) {
                      _loadUsbPorts();
                    }
                  },
                ),
                const SizedBox(height: 12),

                if (_usbMode == UsbMode.cups) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedCupsPrinter,
                          decoration: const InputDecoration(
                            labelText: 'Printer tanlang',
                            prefixIcon: Icon(Icons.print),
                            border: OutlineInputBorder(),
                          ),
                          items: _availablePrinters
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedCupsPrinter = v),
                          validator: (v) {
                            if (_connectionType != ConnectionType.usb ||
                                _usbMode != UsbMode.cups) {
                              return null;
                            }
                            if (v == null || v.isEmpty) {
                              return 'Printerni tanlang';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _isLoadingPrinters ? null : _loadPrinters,
                        icon: _isLoadingPrinters
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Printerlarni yangilash',
                      ),
                    ],
                  ),
                  if (_availablePrinters.isEmpty && !_isLoadingPrinters)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Hech qanday printer topilmadi. Printerni USB orqali ulang va "Yangilash" tugmasini bosing.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],

                if (_usbMode == UsbMode.file && Platform.isWindows) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedUsbPort,
                          decoration: const InputDecoration(
                            labelText: 'USB port tanlang',
                            prefixIcon: Icon(Icons.usb),
                            border: OutlineInputBorder(),
                          ),
                          items: _availableUsbPorts
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selectedUsbPort = v);
                            if (v != null) _devicePathCtrl.text = v;
                          },
                          validator: (v) {
                            if (_connectionType != ConnectionType.usb ||
                                _usbMode != UsbMode.file) {
                              return null;
                            }
                            if (v == null || v.isEmpty) {
                              return 'USB portni tanlang';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _isLoadingUsbPorts ? null : _loadUsbPorts,
                        icon: _isLoadingUsbPorts
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'USB portlarni yangilash',
                      ),
                    ],
                  ),
                  if (_availableUsbPorts.isEmpty && !_isLoadingUsbPorts)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'USB port topilmadi. Printerni ulang va "Yangilash" tugmasini bosing.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],

                if (_usbMode == UsbMode.file && !Platform.isWindows)
                  TextFormField(
                    controller: _devicePathCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Qurilma yo\'li',
                      hintText: '/dev/usb/lp0',
                      prefixIcon: Icon(Icons.folder_open),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (_connectionType != ConnectionType.usb ||
                          _usbMode != UsbMode.file) {
                        return null;
                      }
                      if (v == null || v.trim().isEmpty) {
                        return 'Qurilma yo\'lini kiriting';
                      }
                      return null;
                    },
                  ),
              ],
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<PaperWidth>(
                      initialValue: _paperWidth,
                      decoration: const InputDecoration(
                        labelText: 'Qog\'oz kengligi',
                        prefixIcon: Icon(Icons.straighten),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: PaperWidth.mm57,
                          child: Text('57mm'),
                        ),
                        DropdownMenuItem(
                          value: PaperWidth.mm80,
                          child: Text('80mm'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _paperWidth = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _codepage,
                      decoration: const InputDecoration(
                        labelText: 'Kodlash (Codepage)',
                        prefixIcon: Icon(Icons.translate),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 17,
                          child: Text('CP866 (Kirill)'),
                        ),
                        DropdownMenuItem(
                          value: 0,
                          child: Text('CP437 (Lotin)'),
                        ),
                        DropdownMenuItem(
                          value: 46,
                          child: Text('CP1251 (Windows)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _codepage = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cable),
                    label: const Text('Ulanishni tekshirish'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _isTesting ? null : _printTestPage,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Test sahifa chop etish'),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Auto-start ────────────────────────────────────────
              Text(
                'Qo\'shimcha',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Windows ishga tushganda avtomatik ochilsin'),
                subtitle: const Text(
                  'Dastur kompyuter yoqilganda avtomatik ishga tushadi',
                ),
                value: _autoStart,
                onChanged: (v) => setState(() => _autoStart = v),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: theme.colorScheme.outline),
                ),
              ),

              const SizedBox(height: 32),

              // ── Keyboard shortcuts help ───────────────────────────
              Text(
                'Klaviatura Tugmalari',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _shortcutRow('Ctrl + ,', 'Sozlamalarni ochish'),
              _shortcutRow('F5', 'Sahifani yangilash'),
              _shortcutRow('F12', 'Ishlab chiqaruvchi asboblar'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcutRow(String key, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              key,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(desc),
        ],
      ),
    );
  }
}
