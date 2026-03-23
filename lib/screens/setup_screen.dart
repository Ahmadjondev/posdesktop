import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../models/printer_config.dart';
import '../services/printer_service.dart';
import '../services/settings_service.dart';
import 'home_screen.dart';

final _log = Logger('SetupScreen');

/// First-launch setup wizard for SaaS onboarding.
/// 3 steps: Welcome → Store URL → Printer (optional).
class SetupScreen extends StatefulWidget {
  final SettingsService settings;

  const SetupScreen({super.key, required this.settings});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0; // 0=Welcome, 1=URL, 2=Printer

  // URL step
  final _subdomainCtrl = TextEditingController();
  final _customUrlCtrl = TextEditingController();
  bool _useCustomUrl = false;
  final _urlFormKey = GlobalKey<FormState>();

  // Printer step
  final _ipCtrl = TextEditingController(text: '192.168.0.150');
  final _portCtrl = TextEditingController(text: '9100');
  final _nameCtrl = TextEditingController(text: 'Receipt Printer');
  PaperWidth _paperWidth = PaperWidth.mm80;
  int _codepage = 17;
  bool _configurePrinter = false;
  bool _isTesting = false;
  final _printerFormKey = GlobalKey<FormState>();
  final _printer = PrinterService();

  bool _isSaving = false;

  @override
  void dispose() {
    _subdomainCtrl.dispose();
    _customUrlCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _resolvedUrl {
    if (_useCustomUrl) return _customUrlCtrl.text.trim();
    final sub = _subdomainCtrl.text.trim();
    return 'https://$sub.digitex.uz/';
  }

  PrinterConfig _buildConfig() => PrinterConfig(
        name: _nameCtrl.text.trim(),
        ip: _ipCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 9100,
        paperWidth: _paperWidth,
        codepage: _codepage,
      );

  Future<void> _testConnection() async {
    if (!_printerFormKey.currentState!.validate()) return;
    setState(() => _isTesting = true);
    try {
      final config = _buildConfig();
      final ok = await _printer.testConnection(config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? '${config.ip}:${config.port} ga muvaffaqiyatli ulandi!'
              : 'Printerga ulanib bo\'lmadi. IP va portni tekshiring.'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _nextStep() {
    if (_step == 1) {
      if (!_urlFormKey.currentState!.validate()) return;
    }
    setState(() => _step++);
  }

  void _prevStep() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _finish() async {
    if (_configurePrinter && !_printerFormKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await widget.settings.setPosUrl(_resolvedUrl);
      if (_configurePrinter) {
        await widget.settings.setPrinterConfig(_buildConfig());
      }
      await widget.settings.setSetupComplete(true);
      _log.info('Setup complete — URL: $_resolvedUrl');

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(settings: widget.settings),
        ),
      );
    } catch (e) {
      _log.severe('Setup save failed: $e');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              children: [
                // Step indicator
                _StepIndicator(currentStep: _step),
                const SizedBox(height: 40),

                // Step content
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: switch (_step) {
                      0 => _buildWelcome(theme, colorScheme),
                      1 => _buildUrlStep(theme),
                      2 => _buildPrinterStep(theme),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 0: Welcome ──────────────────────────────────────────────────

  Widget _buildWelcome(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      key: const ValueKey(0),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(Icons.point_of_sale_rounded,
              size: 48, color: colorScheme.primary),
        ),
        const SizedBox(height: 24),
        Text('Xush kelibsiz!',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(
          'Digitex POS — savdo nuqtangizni boshqarish uchun '
          'qulay dastur. Boshlash uchun bir necha daqiqa vaqt ajrating.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: _nextStep,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Boshlash'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(200, 48),
          ),
        ),
      ],
    );
  }

  // ── Step 1: Store URL ────────────────────────────────────────────────

  Widget _buildUrlStep(ThemeData theme) {
    return Form(
      key: const ValueKey(1),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Do\'kon manzili',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Digitex tizimidagi subdomen nomingizni kiriting.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            if (!_useCustomUrl)
              Form(
                key: _urlFormKey,
                child: TextFormField(
                  controller: _subdomainCtrl,
                  decoration: InputDecoration(
                    prefixText: 'https://',
                    suffixText: '.digitex.uz',
                    hintText: 'mystore',
                    prefixIcon: const Icon(Icons.store),
                    border: const OutlineInputBorder(),
                    helperText: _subdomainCtrl.text.isNotEmpty
                        ? 'https://${_subdomainCtrl.text.trim()}.digitex.uz/'
                        : null,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Subdomen kiritilishi shart';
                    }
                    if (!RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$')
                        .hasMatch(v.trim())) {
                      return 'Faqat harflar, raqamlar va tire (-)';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
              )
            else
              Form(
                key: _urlFormKey,
                child: TextFormField(
                  controller: _customUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'To\'liq URL',
                    hintText: 'https://mystore.digitex.uz/',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'URL kiritilishi shart';
                    }
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme) {
                      return 'Noto\'g\'ri URL formati';
                    }
                    return null;
                  },
                ),
              ),

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _useCustomUrl = !_useCustomUrl),
                icon: Icon(
                    _useCustomUrl ? Icons.dns : Icons.edit_note),
                label: Text(_useCustomUrl
                    ? 'Subdomen rejimiga qaytish'
                    : 'To\'liq URL kiritish'),
              ),
            ),

            const SizedBox(height: 32),

            // Navigation
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _prevStep,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Orqaga'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _nextStep,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Davom etish'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Printer Setup ────────────────────────────────────────────

  Widget _buildPrinterStep(ThemeData theme) {
    return SingleChildScrollView(
      key: const ValueKey(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Printer sozlash',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Termal printer ulangan bo\'lsa, hozir sozlashingiz mumkin. '
            'Keyinroq ham sozlash imkoni bor.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Toggle
          SwitchListTile(
            title: const Text('Printerni hozir sozlash'),
            value: _configurePrinter,
            onChanged: (v) => setState(() => _configurePrinter = v),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.colorScheme.outline),
            ),
          ),

          if (_configurePrinter) ...[
            const SizedBox(height: 16),
            Form(
              key: _printerFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Printer nomi',
                      prefixIcon: Icon(Icons.print),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        child: TextFormField(
                          controller: _portCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            hintText: '9100',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
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
                                value: PaperWidth.mm57, child: Text('57mm')),
                            DropdownMenuItem(
                                value: PaperWidth.mm80, child: Text('80mm')),
                          ],
                          onChanged: (v) =>
                              setState(() => _paperWidth = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _codepage,
                          decoration: const InputDecoration(
                            labelText: 'Kodlash',
                            prefixIcon: Icon(Icons.translate),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 17, child: Text('CP866 (Kirill)')),
                            DropdownMenuItem(
                                value: 0, child: Text('CP437 (Lotin)')),
                            DropdownMenuItem(
                                value: 46, child: Text('CP1251 (Windows)')),
                          ],
                          onChanged: (v) =>
                              setState(() => _codepage = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cable),
                      label: const Text('Ulanishni tekshirish'),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Navigation
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _prevStep,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Orqaga'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _isSaving ? null : _finish,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_configurePrinter ? 'Saqlash va boshlash' : 'Boshlash'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(180, 48),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Step Indicator ───────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  static const _labels = ['Kirish', 'Manzil', 'Printer'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(top: 15),
                color: i <= currentStep
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
              ),
            ),
          _StepDot(
            label: _labels[i],
            isActive: i == currentStep,
            isCompleted: i < currentStep,
          ),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isCompleted;

  const _StepDot({
    required this.label,
    required this.isActive,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive || isCompleted
        ? colorScheme.primary
        : colorScheme.outlineVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary
                : isCompleted
                    ? colorScheme.primary
                    : colorScheme.surface,
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : Text(
                    label[0],
                    style: TextStyle(
                      color: isActive ? Colors.white : color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
