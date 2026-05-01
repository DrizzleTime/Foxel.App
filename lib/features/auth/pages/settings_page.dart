import 'dart:async';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/api/foxel_api_exception.dart';
import 'package:foxel/core/models/session.dart';
import 'package:foxel/features/auth/models/qr_login_payload.dart';
import 'package:foxel/features/auth/services/qr_code_decoder.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initialBaseUrl,
    required this.onLoggedIn,
  });

  final String initialBaseUrl;
  final ValueChanged<FoxelSession> onLoggedIn;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _decoder = const QrCodeDecoder();
  final _baseUrlController = TextEditingController();

  CameraController? _cameraController;
  Timer? _scanTimer;
  bool _cameraBootstrapped = false;
  bool _cameraBusy = false;
  bool _scanPaused = false;
  bool _importing = false;
  bool _loggingIn = false;
  bool _loadingCamera = true;
  String? _statusText;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _baseUrlController.text = widget.initialBaseUrl;
    if (_cameraScanSupported) {
      _bootstrapCamera();
    } else {
      _loadingCamera = false;
      _statusText = '当前平台仅支持从图片识别二维码登录';
    }
  }

  bool get _cameraScanSupported {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _baseUrlController.dispose();
    unawaited(_disposeCamera());
    super.dispose();
  }

  Future<void> _bootstrapCamera() async {
    if (_cameraBootstrapped) {
      return;
    }
    _cameraBootstrapped = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loadingCamera = false;
          _statusText = '未检测到可用摄像头';
        });
        return;
      }

      final camera = _pickCamera(cameras);
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _loadingCamera = false;
        _statusText = '摄像头已就绪';
      });
      _startScanning();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCamera = false;
        _statusText = null;
        _errorText = error.toString();
      });
    }
  }

  CameraDescription _pickCamera(List<CameraDescription> cameras) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        return camera;
      }
    }
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.external) {
        return camera;
      }
    }
    return cameras.first;
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller == null) {
      return;
    }
    try {
      await controller.dispose();
    } catch (_) {}
  }

  void _startScanning() {
    _scanTimer?.cancel();
    _scanPaused = false;
    _scanTimer = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _captureAndDecode(),
    );
  }

  void _pauseScanning({String? status}) {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanPaused = true;
    if (!mounted) {
      return;
    }
    setState(() {
      if (status != null) {
        _statusText = status;
      }
    });
  }

  Future<void> _captureAndDecode() async {
    final controller = _cameraController;
    if (controller == null || _cameraBusy || _loggingIn || _scanPaused) {
      return;
    }
    _cameraBusy = true;
    try {
      final shot = await controller.takePicture();
      final raw = _decoder.decodeBytes(await shot.readAsBytes());
      if (raw == null) {
        return;
      }
      _pauseScanning(status: '已识别到二维码');
      await _submitRawValue(raw);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = error.toString();
          _statusText = null;
        });
      }
      _pauseScanning();
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _restartScanning() async {
    if (_loggingIn || _importing) {
      return;
    }
    if (!_cameraScanSupported) {
      setState(() {
        _errorText = null;
        _statusText = '当前平台仅支持从图片识别二维码登录';
      });
      return;
    }
    if (_cameraController == null) {
      await _bootstrapCamera();
      return;
    }
    setState(() {
      _errorText = null;
      _statusText = '重新开始扫描';
    });
    _startScanning();
  }

  Future<void> _pickImageAndDecode() async {
    if (_importing || _loggingIn) {
      return;
    }
    setState(() {
      _importing = true;
      _errorText = null;
      _statusText = '正在识别图片';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) {
        return;
      }
      final raw = _decoder.decodeBytes(await file.xFile.readAsBytes());
      if (raw == null) {
        throw const FoxelApiException('未识别到二维码');
      }
      await _submitRawValue(raw);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
        _statusText = null;
      });
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _submitRawValue(String rawValue) async {
    final payload = QrLoginPayload.parse(rawValue);
    setState(() {
      _baseUrlController.text = payload.baseUrl;
      _statusText = '正在验证登录状态';
      _errorText = null;
    });
    await _loginWithPayload(payload);
  }

  Future<void> _loginWithPayload(QrLoginPayload payload) async {
    if (_loggingIn) {
      return;
    }
    setState(() => _loggingIn = true);
    try {
      final api = FoxelApi(baseUrl: payload.baseUrl, token: payload.token);
      final profile = await api.me();
      final session = FoxelSession(
        baseUrl: api.baseUrl,
        username: profile.username.isEmpty ? '未命名用户' : profile.username,
        token: payload.token,
        email: profile.email,
        avatarUrl: profile.avatarUrl,
      );
      api.close();
      widget.onLoggedIn(session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.toString();
        _statusText = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loggingIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final hasPreview = controller != null && controller.value.isInitialized;
    final cameraScanSupported = _cameraScanSupported;
    return Scaffold(
      appBar: AppBar(title: const Text('Foxel 设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('连接后端', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: '后端地址',
                prefixIcon: Icon(Icons.dns_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _importing ? null : _pickImageAndDecode,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_search_rounded),
              label: Text(_importing ? '识别中' : '从图片识别'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (!cameraScanSupported || _cameraBusy || _loggingIn)
                  ? null
                  : _restartScanning,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(_scanPaused ? '重新开始扫描' : '继续扫描'),
            ),
            const SizedBox(height: 16),
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE1E7EF)),
              ),
              child: hasPreview
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFF276EF1),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: _loadingCamera
                          ? const CircularProgressIndicator()
                          : cameraScanSupported
                          ? const Icon(Icons.camera_alt_outlined, size: 36)
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.image_search_rounded, size: 36),
                                SizedBox(height: 10),
                                Text('请从图片识别二维码'),
                              ],
                            ),
                    ),
            ),
            if (_statusText != null) ...[
              const SizedBox(height: 16),
              _StatusBanner(
                message: _statusText!,
                icon: Icons.info_outline_rounded,
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              _StatusBanner(
                message: _errorText!,
                icon: Icons.error_outline_rounded,
                error: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.icon,
    this.error = false,
  });

  final String message;
  final IconData icon;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFB42318) : const Color(0xFF175CD3);
    final background = error
        ? const Color(0xFFFEE4E2)
        : const Color(0xFFEFF8FF);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
