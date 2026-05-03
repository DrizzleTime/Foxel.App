import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/features/media/services/video_cache_proxy.dart';
import 'package:foxel/features/media/services/video_playback_store.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.api,
    required this.path,
    required this.name,
    required this.size,
    required this.mtime,
  });

  final FoxelApi api;
  final String path;
  final String name;
  final int size;
  final int mtime;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  static const _seekStep = Duration(seconds: 10);
  static const _hideControlsDelay = Duration(seconds: 3);
  static const _savePositionInterval = Duration(seconds: 5);
  static const _playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  VideoPlayerController? _controller;
  late final Future<void> _initFuture;
  late final VideoCacheProxy _cacheProxy;
  final _playbackStore = VideoPlaybackStore();

  Timer? _hideControlsTimer;
  Timer? _savePositionTimer;
  StreamSubscription<List<CachedVideoRange>>? _cachedRangesSubscription;
  List<CachedVideoRange> _cachedRanges = const [];
  bool _showControls = true;
  bool _isFullScreen = false;
  bool _isLandscape = false;
  bool _isDraggingProgress = false;
  double _dragProgress = 0;
  double _volume = 1;
  double _playbackSpeed = 1;
  String? _lastControllerLogSignature;

  @override
  void initState() {
    super.initState();
    _cacheProxy = VideoCacheProxy(
      api: widget.api,
      path: widget.path,
      size: widget.size,
      mtime: widget.mtime,
    );
    _initFuture = _initializePlayer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _savePositionTimer?.cancel();
    _cachedRangesSubscription?.cancel();
    unawaited(_savePlaybackPosition());
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_handleControllerChanged);
      controller.dispose();
    }
    unawaited(_cacheProxy.close());
    _restoreSystemSettings();
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    _log(
      'initialize start path=${widget.path} name=${widget.name} '
      'size=${widget.size} mtime=${widget.mtime}',
    );
    try {
      _cachedRangesSubscription = _cacheProxy.cachedRangesStream.listen((
        ranges,
      ) {
        _log('cached ranges updated count=${ranges.length}');
        if (mounted) {
          setState(() => _cachedRanges = ranges);
        }
      });
      final url = await _cacheProxy.start();
      _log('cache proxy url=$url');
      final controller = VideoPlayerController.networkUrl(url);
      _controller = controller;
      controller.addListener(_handleControllerChanged);
      _log('controller initialize begin');
      await controller.initialize();
      _logControllerValue('controller initialized', controller.value);
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(_playbackSpeed);
      await _restorePlaybackPosition();
      await controller.play();
      _logControllerValue('play requested', controller.value);
      _startPositionTimer();
      _scheduleControlsHide();
    } catch (error, stackTrace) {
      _log('initialize failed: $error');
      debugPrintStack(
        label: '[VideoPlayer] initialize stack',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _handleControllerChanged() {
    final controller = _controller;
    if (controller != null) {
      final value = controller.value;
      final signature = [
        value.isInitialized,
        value.isPlaying,
        value.isBuffering,
        value.hasError,
        value.errorDescription,
        value.duration.inMilliseconds,
        value.position.inMilliseconds ~/ 1000,
        value.size.width,
        value.size.height,
      ].join('|');
      if (signature != _lastControllerLogSignature) {
        _lastControllerLogSignature = signature;
        _logControllerValue('controller changed', value);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    final controller = _controller;
    if (controller == null || !controller.value.isPlaying || !_showControls) {
      return;
    }
    _hideControlsTimer = Timer(_hideControlsDelay, () {
      if (mounted && controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _scheduleControlsHide();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleControlsHide();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
      _showControlsTemporarily();
    } else {
      controller.play();
      _scheduleControlsHide();
    }
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final value = controller.value;
    final target = value.position + offset;
    await _seekToAndPlay(target);
    _showControlsTemporarily();
  }

  Future<void> _seekTo(Duration target) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final duration = controller.value.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > duration
        ? duration
        : target;
    await controller.seekTo(clamped);
  }

  Future<void> _seekToAndPlay(Duration target) async {
    await _seekTo(target);
    await _controller?.play();
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    await _controller?.setPlaybackSpeed(speed);
    _showControlsTemporarily();
  }

  Future<void> _setVolume(double volume) async {
    setState(() => _volume = volume);
    await _controller?.setVolume(volume);
    _showControlsTemporarily();
  }

  Future<void> _toggleMute() async {
    await _setVolume(_volume == 0 ? 1 : 0);
  }

  Future<void> _toggleFullScreen() async {
    final next = !_isFullScreen;
    setState(() {
      _isFullScreen = next;
      _showControls = true;
    });
    if (next) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await _restoreSystemUi();
    }
    _scheduleControlsHide();
  }

  Future<void> _toggleOrientation() async {
    final next = !_isLandscape;
    setState(() {
      _isLandscape = next;
      _isFullScreen = next;
      _showControls = true;
    });

    if (next) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await _restoreSystemUi();
    }
    _scheduleControlsHide();
  }

  Future<void> _restoreSystemUi() {
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _restoreSystemSettings() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await _restoreSystemUi();
  }

  Future<void> _restorePlaybackPosition() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final saved = await _playbackStore.load(api: widget.api, path: widget.path);
    final duration = controller.value.duration;
    if (saved == null ||
        saved <= const Duration(seconds: 3) ||
        duration <= Duration.zero ||
        duration - saved <= const Duration(seconds: 10)) {
      _log('skip restore position saved=$saved duration=$duration');
      return;
    }
    _log('restore position saved=$saved duration=$duration');
    await controller.seekTo(saved);
  }

  void _logControllerValue(String event, VideoPlayerValue value) {
    _log(
      '$event initialized=${value.isInitialized} playing=${value.isPlaying} '
      'buffering=${value.isBuffering} duration=${value.duration} '
      'position=${value.position} size=${value.size.width}x${value.size.height} '
      'aspect=${value.aspectRatio} error=${value.errorDescription}',
    );
  }

  void _log(String message) {
    debugPrint('[VideoPlayer] $message');
  }

  void _startPositionTimer() {
    _savePositionTimer?.cancel();
    _savePositionTimer = Timer.periodic(
      _savePositionInterval,
      (_) => unawaited(_savePlaybackPosition()),
    );
  }

  Future<void> _savePlaybackPosition() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final position = controller.value.position;
    final duration = controller.value.duration;
    if (duration > Duration.zero &&
        duration - position <= const Duration(seconds: 10)) {
      await _playbackStore.clear(api: widget.api, path: widget.path);
      return;
    }
    if (position > const Duration(seconds: 3)) {
      await _playbackStore.save(
        api: widget.api,
        path: widget.path,
        position: position,
      );
    }
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (_, _) {
        _restoreSystemSettings();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error.toString());
            }
            return _buildPlayer();
          },
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final value = controller.value;
    final duration = value.duration;
    final position = _isDraggingProgress
        ? duration * _dragProgress
        : value.position;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          if (_showControls)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
            ),
          if (_showControls) _buildTopBar(),
          if (_showControls)
            Center(
              child: IconButton.filled(
                onPressed: _togglePlay,
                iconSize: 48,
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ),
          if (_showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomControls(
                position: position,
                duration: duration,
                bufferedRanges: value.buffered,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                tooltip: '返回',
              ),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls({
    required Duration position,
    required Duration duration,
    required List<DurationRange> bufferedRanges,
  }) {
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final cachedRanges = _cachedDurationRanges(duration);
    final bufferedProgress = _bufferedProgress([
      ...bufferedRanges,
      ...cachedRanges,
    ], duration);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: _VideoSeekBar(
                    progress: progress,
                    bufferedProgress: bufferedProgress,
                    onChangeStart: (value) {
                      _hideControlsTimer?.cancel();
                      setState(() {
                        _isDraggingProgress = true;
                        _dragProgress = value;
                      });
                    },
                    onChanged: (value) {
                      setState(() => _dragProgress = value);
                    },
                    onChangeEnd: (value) async {
                      setState(() {
                        _isDraggingProgress = false;
                        _dragProgress = value;
                      });
                      await _seekToAndPlay(duration * value);
                      _scheduleControlsHide();
                    },
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 430;
                if (compact) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _playbackButtons(),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SpeedMenu(
                            value: _playbackSpeed,
                            speeds: _playbackSpeeds,
                            onSelected: _setPlaybackSpeed,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _toggleMute,
                            icon: Icon(
                              _volume == 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                            ),
                            color: Colors.white,
                            tooltip: _volume == 0 ? '恢复音量' : '静音',
                          ),
                          _orientationButton(),
                          _fullScreenButton(),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    ..._playbackButtons(),
                    const Spacer(),
                    _SpeedMenu(
                      value: _playbackSpeed,
                      speeds: _playbackSpeeds,
                      onSelected: _setPlaybackSpeed,
                    ),
                    const SizedBox(width: 12),
                    _VolumeControl(
                      value: _volume,
                      onChanged: _setVolume,
                      onMute: _toggleMute,
                    ),
                    const SizedBox(width: 4),
                    _orientationButton(),
                    const SizedBox(width: 4),
                    _fullScreenButton(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  double _bufferedProgress(List<DurationRange> ranges, Duration duration) {
    if (duration.inMilliseconds <= 0 || ranges.isEmpty) {
      return 0;
    }
    final maxBuffered = ranges
        .map((range) => range.end.inMilliseconds)
        .fold<int>(0, (max, value) => value > max ? value : max);
    return (maxBuffered / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  List<DurationRange> _cachedDurationRanges(Duration duration) {
    if (widget.size <= 0 || duration.inMilliseconds <= 0) {
      return const [];
    }
    return _cachedRanges.map((range) {
      final start = duration * (range.start / widget.size);
      final end = duration * ((range.end + 1) / widget.size).clamp(0.0, 1.0);
      return DurationRange(start, end);
    }).toList();
  }

  List<Widget> _playbackButtons() {
    final isPlaying = _controller?.value.isPlaying ?? false;
    return [
      IconButton(
        onPressed: () => _seekBy(-_seekStep),
        icon: const Icon(Icons.replay_10_rounded),
        color: Colors.white,
        tooltip: '快退 10 秒',
      ),
      IconButton.filled(
        onPressed: _togglePlay,
        iconSize: 30,
        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        tooltip: isPlaying ? '暂停' : '播放',
      ),
      IconButton(
        onPressed: () => _seekBy(_seekStep),
        icon: const Icon(Icons.forward_10_rounded),
        color: Colors.white,
        tooltip: '快进 10 秒',
      ),
    ];
  }

  Widget _orientationButton() {
    return IconButton(
      onPressed: _toggleOrientation,
      icon: Icon(
        _isLandscape
            ? Icons.stay_current_portrait_rounded
            : Icons.stay_current_landscape_rounded,
      ),
      color: Colors.white,
      tooltip: _isLandscape ? '切换竖屏' : '切换横屏',
    );
  }

  Widget _fullScreenButton() {
    return IconButton(
      onPressed: _toggleFullScreen,
      icon: Icon(
        _isFullScreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
      ),
      color: Colors.white,
      tooltip: _isFullScreen ? '退出全屏' : '全屏',
    );
  }
}

class _VideoSeekBar extends StatefulWidget {
  const _VideoSeekBar({
    required this.progress,
    required this.bufferedProgress,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double progress;
  final double bufferedProgress;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  static const _trackHeight = 3.0;
  static const _thumbRadius = 6.0;

  @override
  State<_VideoSeekBar> createState() => _VideoSeekBarState();
}

class _VideoSeekBarState extends State<_VideoSeekBar> {
  double? _dragValue;

  double get _paintProgress => _dragValue ?? widget.progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double valueFromPosition(double dx) {
            if (constraints.maxWidth <= 0) {
              return 0;
            }
            return (dx / constraints.maxWidth).clamp(0.0, 1.0);
          }

          void update(Offset localPosition, ValueChanged<double> callback) {
            final value = valueFromPosition(localPosition.dx);
            setState(() => _dragValue = value);
            callback(value);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final value = valueFromPosition(details.localPosition.dx);
              widget.onChangeStart(value);
              widget.onChangeEnd(value);
            },
            onHorizontalDragStart: (details) {
              update(details.localPosition, widget.onChangeStart);
            },
            onHorizontalDragUpdate: (details) {
              update(details.localPosition, widget.onChanged);
            },
            onHorizontalDragEnd: (_) {
              final value = _paintProgress;
              setState(() => _dragValue = null);
              widget.onChangeEnd(value);
            },
            child: CustomPaint(
              painter: _VideoSeekBarPainter(
                progress: _paintProgress,
                bufferedProgress: widget.bufferedProgress,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _VideoSeekBarPainter extends CustomPainter {
  const _VideoSeekBarPainter({
    required this.progress,
    required this.bufferedProgress,
  });

  final double progress;
  final double bufferedProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackRect = Rect.fromLTWH(
      0,
      centerY - _VideoSeekBar._trackHeight / 2,
      size.width,
      _VideoSeekBar._trackHeight,
    );
    final radius = Radius.circular(_VideoSeekBar._trackHeight / 2);
    final backgroundPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22);
    final bufferedPaint = Paint()..color = Colors.white.withValues(alpha: 0.36);
    final playedPaint = Paint()..color = const Color(0xFFE53935);
    final thumbPaint = Paint()..color = Colors.white;

    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      backgroundPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          trackRect.width * bufferedProgress,
          trackRect.height,
        ),
        radius,
      ),
      bufferedPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          trackRect.width * progress,
          trackRect.height,
        ),
        radius,
      ),
      playedPaint,
    );
    canvas.drawCircle(
      Offset(trackRect.width * progress, centerY),
      _VideoSeekBar._thumbRadius,
      thumbPaint,
    );
  }

  @override
  bool shouldRepaint(_VideoSeekBarPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        bufferedProgress != oldDelegate.bufferedProgress;
  }
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({
    required this.value,
    required this.speeds,
    required this.onSelected,
  });

  final double value;
  final List<double> speeds;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      initialValue: value,
      tooltip: '倍速',
      onSelected: onSelected,
      itemBuilder: (context) {
        return speeds
            .map(
              (speed) =>
                  PopupMenuItem<double>(value: speed, child: Text('${speed}x')),
            )
            .toList();
      },
      child: Container(
        height: 40,
        width: 72,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}x',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.value,
    required this.onChanged,
    required this.onMute,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onMute,
          icon: Icon(
            value == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          ),
          color: Colors.white,
          tooltip: value == 0 ? '恢复音量' : '静音',
        ),
        SizedBox(
          width: 96,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
