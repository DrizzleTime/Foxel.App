import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.api,
    required this.path,
    required this.name,
  });

  final FoxelApi api;
  final String path;
  final String name;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  static const double _minScale = 0.5;
  static const double _maxScale = 5;
  static const double _scaleStep = 1.25;

  late final Future<Uint8List> _imageFuture;
  late final TransformationController _transformationController;

  /// 视口尺寸：用于按中心缩放，避免缩放锚点跑到左上角。
  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _imageFuture = widget.api.readFile(widget.path);
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    _setScale(_currentScale * _scaleStep);
  }

  void _zoomOut() {
    _setScale(_currentScale / _scaleStep);
  }

  void _toggleZoom() {
    if (_currentScale > 1.05) {
      _resetZoom();
      return;
    }
    _setScale(2);
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _setScale(double scale) {
    final nextScale = scale.clamp(_minScale, _maxScale).toDouble();
    final matrix = _transformationController.value;
    final current = matrix.getMaxScaleOnAxis();
    if (current <= 0) {
      return;
    }
    final size = _viewerKey.currentContext?.size;
    if (size == null || size.isEmpty) {
      _transformationController.value = Matrix4.identity()
        ..scaleByDouble(nextScale, nextScale, 1, 1);
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final ratio = nextScale / current;
    // 以视口中心为锚点缩放：T(c) · S(ratio) · T(-c) · M，保留已有平移。
    final zoom = Matrix4.translationValues(center.dx, center.dy, 0)
      ..multiply(Matrix4.diagonal3Values(ratio, ratio, 1))
      ..multiply(Matrix4.translationValues(-center.dx, -center.dy, 0));
    _transformationController.value = zoom * matrix;
  }

  double get _currentScale {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      backgroundColor: Colors.black,
      body: FutureBuilder<Uint8List>(
        future: _imageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onDoubleTap: _toggleZoom,
                  child: InteractiveViewer(
                    key: _viewerKey,
                    transformationController: _transformationController,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    child: Center(
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        // 服务端偶尔用 200 返回错误体：解码失败时给提示而不是红屏。
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            '图片解码失败',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: _ImageToolbar(
                    onZoomOut: _zoomOut,
                    onReset: _resetZoom,
                    onZoomIn: _zoomIn,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ImageToolbar extends StatelessWidget {
  const _ImageToolbar({
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '缩小',
                onPressed: onZoomOut,
                icon: const Icon(Icons.remove_rounded),
                color: Colors.white,
              ),
              IconButton(
                tooltip: '重置',
                onPressed: onReset,
                icon: const Icon(Icons.fit_screen_rounded),
                color: Colors.white,
              ),
              IconButton(
                tooltip: '放大',
                onPressed: onZoomIn,
                icon: const Icon(Icons.add_rounded),
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
