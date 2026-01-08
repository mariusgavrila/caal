import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/config_service.dart';

/// Full settings screen accessible from welcome screen.
/// Includes server URL (required for mobile) and all agent settings.
class SettingsScreen extends StatefulWidget {
  final ConfigService configService;
  final VoidCallback onSave;

  const SettingsScreen({
    super.key,
    required this.configService,
    required this.onSave,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  String? _error;
  bool _serverConnected = false;

  // Agent settings fields
  String _agentName = 'Cal';
  String _ttsVoice = 'am_puck';
  String _model = 'ministral-3:8b';
  List<String> _wakeGreetings = ["Hey, what's up?", "What's up?", 'How can I help?'];
  double _temperature = 0.7;
  int _numCtx = 8192;
  int _maxTurns = 20;
  int _toolCacheSize = 3;
  bool _wakeWordEnabled = false;
  String _wakeWordModel = 'models/hey_cal.onnx';
  double _wakeWordThreshold = 0.5;
  double _wakeWordTimeout = 3.0;

  // Available options
  List<String> _voices = [];
  List<String> _models = [];
  List<String> _wakeWordModels = [];

  // Text controllers
  final _wakeGreetingsController = TextEditingController();

  String get _webhookUrl {
    final serverUrl = _serverUrlController.text.trim();
    if (serverUrl.isEmpty) return '';
    final uri = Uri.tryParse(serverUrl);
    if (uri == null) return '';
    return 'http://${uri.host}:8889';
  }

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = widget.configService.serverUrl;
    // Try to load settings if server is configured
    if (widget.configService.isConfigured) {
      unawaited(_loadSettings());
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _wakeGreetingsController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final webhookUrl = _webhookUrl;
    if (webhookUrl.isEmpty) {
      setState(() {
        _error = 'Enter a valid server URL first';
        _serverConnected = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.get(Uri.parse('$webhookUrl/settings')).timeout(
            const Duration(seconds: 5),
          );
      if (response.statusCode == 200) {
        setState(() {
          _serverConnected = true;
        });
        await _loadSettings();
      } else {
        setState(() {
          _serverConnected = false;
          _error = 'Server returned ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _serverConnected = false;
        _error = 'Could not connect to server';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final webhookUrl = _webhookUrl;
    if (webhookUrl.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        http.get(Uri.parse('$webhookUrl/settings')),
        http.get(Uri.parse('$webhookUrl/voices')),
        http.get(Uri.parse('$webhookUrl/models')),
        http.get(Uri.parse('$webhookUrl/wake-word/models')),
      ]);

      final settingsRes = results[0];
      final voicesRes = results[1];
      final modelsRes = results[2];
      final wakeWordModelsRes = results[3];

      if (settingsRes.statusCode == 200) {
        final data = jsonDecode(settingsRes.body);
        final settings = data['settings'] ?? {};

        setState(() {
          _serverConnected = true;
          _agentName = settings['agent_name'] ?? _agentName;
          _ttsVoice = settings['tts_voice'] ?? _ttsVoice;
          _model = settings['model'] ?? _model;
          _wakeGreetings = List<String>.from(settings['wake_greetings'] ?? _wakeGreetings);
          _temperature = (settings['temperature'] ?? _temperature).toDouble();
          _numCtx = settings['num_ctx'] ?? _numCtx;
          _maxTurns = settings['max_turns'] ?? _maxTurns;
          _toolCacheSize = settings['tool_cache_size'] ?? _toolCacheSize;
          _wakeWordEnabled = settings['wake_word_enabled'] ?? _wakeWordEnabled;
          _wakeWordModel = settings['wake_word_model'] ?? _wakeWordModel;
          _wakeWordThreshold = (settings['wake_word_threshold'] ?? _wakeWordThreshold).toDouble();
          _wakeWordTimeout = (settings['wake_word_timeout'] ?? _wakeWordTimeout).toDouble();
          _wakeGreetingsController.text = _wakeGreetings.join('\n');
        });
      }

      if (voicesRes.statusCode == 200) {
        final data = jsonDecode(voicesRes.body);
        setState(() {
          _voices = List<String>.from(data['voices'] ?? []);
        });
      }

      if (modelsRes.statusCode == 200) {
        final data = jsonDecode(modelsRes.body);
        setState(() {
          _models = List<String>.from(data['models'] ?? []);
        });
      }

      if (wakeWordModelsRes.statusCode == 200) {
        final data = jsonDecode(wakeWordModelsRes.body);
        setState(() {
          _wakeWordModels = List<String>.from(data['models'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load settings: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Save server URL first
      await widget.configService.setServerUrl(_serverUrlController.text.trim());

      // If connected, save agent settings
      if (_serverConnected) {
        final greetings =
            _wakeGreetingsController.text.split('\n').where((g) => g.trim().isNotEmpty).toList();

        final settings = {
          'agent_name': _agentName,
          'tts_voice': _ttsVoice,
          'model': _model,
          'wake_greetings': greetings,
          'temperature': _temperature,
          'num_ctx': _numCtx,
          'max_turns': _maxTurns,
          'tool_cache_size': _toolCacheSize,
          'wake_word_enabled': _wakeWordEnabled,
          'wake_word_model': _wakeWordModel,
          'wake_word_threshold': _wakeWordThreshold,
          'wake_word_timeout': _wakeWordTimeout,
        };

        final res = await http.post(
          Uri.parse('$_webhookUrl/settings'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'settings': settings}),
        );

        if (res.statusCode != 200) {
          setState(() {
            _error = 'Failed to save agent settings: ${res.statusCode}';
          });
          return;
        }
      }

      widget.onSave();
    } catch (e) {
      setState(() {
        _error = 'Failed to save: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFirstSetup = !widget.configService.isConfigured;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        leading: isFirstSetup
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          isFirstSetup ? 'CAAL Setup' : 'Settings',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF45997C)),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Color(0xFF45997C),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Connection Section
              _buildSectionHeader('Connection', Icons.link),
              _buildCard([
                _buildLabel('Server URL'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _serverUrlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(hint: 'http://192.168.1.100:3000'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Server URL is required';
                          }
                          final uri = Uri.tryParse(value.trim());
                          if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                            return 'Enter a valid URL';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _loading ? null : _testConnection,
                      style: TextButton.styleFrom(
                        backgroundColor:
                            _serverConnected ? const Color(0xFF45997C) : const Color(0xFF2A2A2A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(_serverConnected ? '✓' : 'Test'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _serverConnected ? 'Connected to CAAL server' : 'Your CAAL server address',
                  style: TextStyle(
                    fontSize: 12,
                    color: _serverConnected ? const Color(0xFF45997C) : Colors.white54,
                  ),
                ),
              ]),

              // Agent Settings (only show if connected)
              if (_serverConnected) ...[
                const SizedBox(height: 24),
                _buildSectionHeader('Agent', Icons.smart_toy_outlined),
                _buildCard([
                  _buildTextField(
                    label: 'Agent Name',
                    value: _agentName,
                    onChanged: (v) => setState(() => _agentName = v),
                  ),
                  _buildDropdown(
                    label: 'Voice',
                    value: _ttsVoice,
                    options: _voices.isNotEmpty ? _voices : [_ttsVoice],
                    onChanged: (v) => setState(() => _ttsVoice = v ?? _ttsVoice),
                  ),
                  _buildDropdown(
                    label: 'Model',
                    value: _model,
                    options: _models.isNotEmpty ? _models : [_model],
                    onChanged: (v) => setState(() => _model = v ?? _model),
                  ),
                  _buildLabel('Wake Greetings'),
                  TextFormField(
                    controller: _wakeGreetingsController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(hint: 'One greeting per line'),
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionHeader('LLM Settings', Icons.tune),
                _buildCard([
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(
                          label: 'Temperature',
                          value: _temperature,
                          min: 0.0,
                          max: 2.0,
                          decimals: 1,
                          onChanged: (v) => setState(() => _temperature = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildIntField(
                          label: 'Context Size',
                          value: _numCtx,
                          min: 1024,
                          max: 131072,
                          step: 1024,
                          onChanged: (v) => setState(() => _numCtx = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildIntField(
                          label: 'Max Turns',
                          value: _maxTurns,
                          min: 1,
                          max: 100,
                          onChanged: (v) => setState(() => _maxTurns = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildIntField(
                          label: 'Tool Cache',
                          value: _toolCacheSize,
                          min: 0,
                          max: 10,
                          onChanged: (v) => setState(() => _toolCacheSize = v),
                        ),
                      ),
                    ],
                  ),
                ]),

                const SizedBox(height: 24),
                _buildSectionHeader('Wake Word', Icons.hearing),
                _buildCard([
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Server-Side Wake Word',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Activate with wake phrase',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _wakeWordEnabled,
                        onChanged: (v) => setState(() => _wakeWordEnabled = v),
                        activeTrackColor: const Color(0xFF45997C),
                      ),
                    ],
                  ),
                  if (_wakeWordEnabled) ...[
                    const SizedBox(height: 12),
                    _buildWakeWordModelDropdown(),
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberField(
                            label: 'Threshold',
                            value: _wakeWordThreshold,
                            min: 0.1,
                            max: 1.0,
                            decimals: 1,
                            onChanged: (v) => setState(() => _wakeWordThreshold = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildNumberField(
                            label: 'Timeout (s)',
                            value: _wakeWordTimeout,
                            min: 1.0,
                            max: 30.0,
                            decimals: 1,
                            onChanged: (v) => setState(() => _wakeWordTimeout = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ]),

                const SizedBox(height: 16),
                const Text(
                  'Note: Model, context size, and wake word changes take effect on next session.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ] else if (!isFirstSetup) ...[
                const SizedBox(height: 48),
                const Center(
                  child: Column(
                    children: [
                      Icon(Icons.cloud_off, size: 48, color: Colors.white38),
                      SizedBox(height: 16),
                      Text(
                        'Connect to server to configure agent settings',
                        style: TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF45997C), size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF2A2A2A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        TextFormField(
          initialValue: value,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = options.contains(value) ? value : (options.isNotEmpty ? options.first : value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        DropdownButtonFormField<String>(
          initialValue: safeValue,
          style: const TextStyle(color: Colors.white),
          dropdownColor: const Color(0xFF2A2A2A),
          decoration: _inputDecoration(),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildNumberField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int decimals,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        TextFormField(
          initialValue: value.toStringAsFixed(decimals),
          style: const TextStyle(color: Colors.white),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDecoration(),
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed != null && parsed >= min && parsed <= max) {
              onChanged(parsed);
            }
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildIntField({
    required String label,
    required int value,
    required int min,
    required int max,
    int step = 1,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(label),
        TextFormField(
          initialValue: value.toString(),
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: _inputDecoration(),
          onChanged: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null && parsed >= min && parsed <= max) {
              onChanged(parsed);
            }
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _formatModelName(String path) {
    return path
        .replaceAll('models/', '')
        .replaceAll('.onnx', '')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  Widget _buildWakeWordModelDropdown() {
    final options = _wakeWordModels.isNotEmpty ? _wakeWordModels : [_wakeWordModel];
    final safeValue = options.contains(_wakeWordModel) ? _wakeWordModel : options.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wake Word Model',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: safeValue,
          style: const TextStyle(color: Colors.white),
          dropdownColor: const Color(0xFF2A2A2A),
          decoration: _inputDecoration(),
          items: options
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(_formatModelName(m)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _wakeWordModel = v ?? _wakeWordModel),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
