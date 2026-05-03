import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:foxel/core/api/foxel_api.dart';

class VideoCacheProxy {
  VideoCacheProxy({
    required this.api,
    required this.path,
    required this.size,
    required this.mtime,
  });

  static const _chunkSize = 4 * 1024 * 1024;
  static const _prefetchCount = 6;

  final FoxelApi api;
  final String path;
  final int size;
  final int mtime;

  HttpServer? _server;
  late final Directory _cacheDir;
  final _cachedChunkIndices = <int>{};
  final _inflightChunks = <int, Future<void>>{};
  final _cachedChunksController =
      StreamController<List<CachedVideoRange>>.broadcast();

  Stream<List<CachedVideoRange>> get cachedRangesStream =>
      _cachedChunksController.stream;

  Future<Uri> start() async {
    _log('start path=$path size=$size mtime=$mtime');
    final baseDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${baseDir.path}/video_cache/${_cacheKey()}');
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }
    _log('cache dir=${_cacheDir.path}');
    _cachedChunkIndices.addAll(await _loadCachedChunkIndices());

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    await notifyCachedRanges();
    final url = Uri.parse('http://127.0.0.1:${_server!.port}/video');
    _log('server listening url=$url');
    return url;
  }

  Future<void> close() async {
    _log('close');
    await _server?.close(force: true);
    _server = null;
    await _cachedChunksController.close();
  }

  Future<void> notifyCachedRanges() async {
    if (_cachedChunksController.isClosed) {
      return;
    }
    _cachedChunksController.add(_cachedRangesFromIndices());
  }

  Future<List<CachedVideoRange>> cachedRanges() async {
    final indices = await _loadCachedChunkIndices();
    _cachedChunkIndices
      ..clear()
      ..addAll(indices);
    return _cachedRangesFromIndices();
  }

  Future<Set<int>> _loadCachedChunkIndices() async {
    final indices = <int>{};
    if (!await _cacheDir.exists()) {
      return indices;
    }

    await for (final entity in _cacheDir.list()) {
      if (entity is! File || !entity.path.endsWith('.bin')) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      final index = int.tryParse(name.substring(0, name.length - 4));
      if (index == null) {
        continue;
      }
      final start = index * _chunkSize;
      final end = _chunkEnd(index);
      final expectedLength = end - start + 1;
      if (await entity.length() == expectedLength) {
        indices.add(index);
      }
    }
    return indices;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    _log(
      'request method=${request.method} uri=${request.uri} range=$rangeHeader',
    );
    if (request.method != 'GET' && request.method != 'HEAD') {
      _log('reject method=${request.method}');
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final range = _parseRange(rangeHeader);
    final start = range?.start ?? 0;
    final end = range?.end ?? (size > 0 ? size - 1 : null);
    if (size <= 0 || start < 0 || end == null || start > end || end >= size) {
      _log('reject range start=$start end=$end size=$size');
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$size',
      );
      await request.response.close();
      return;
    }

    final length = end - start + 1;
    final response = request.response;
    response.statusCode = range == null
        ? HttpStatus.ok
        : HttpStatus.partialContent;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
    response.headers.set(HttpHeaders.contentLengthHeader, length.toString());
    if (range != null) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$size',
      );
    }
    _log(
      'respond status=${response.statusCode} start=$start end=$end '
      'length=$length size=$size',
    );

    if (request.method == 'HEAD') {
      _log('head complete start=$start end=$end');
      await _closeResponseSafely(response);
      return;
    }

    try {
      await _writeRange(response, start, end);
      _log('request complete start=$start end=$end');
    } catch (error, stackTrace) {
      if (_isExpectedDisconnect(error)) {
        _log('request aborted start=$start end=$end error=$error');
        return;
      }
      _log('request failed start=$start end=$end error=$error');
      _log('$stackTrace');
      rethrow;
    } finally {
      await _closeResponseSafely(response);
    }
  }

  Future<void> _writeRange(HttpResponse response, int start, int end) async {
    _log('write range start=$start end=$end');
    var offset = start;
    while (offset <= end) {
      final chunkIndex = offset ~/ _chunkSize;
      final chunkStart = chunkIndex * _chunkSize;
      final chunkEnd = _chunkEnd(chunkIndex);
      final absoluteReadStart = offset;
      final absoluteReadEnd = end < chunkEnd ? end : chunkEnd;
      _log(
        'write chunk index=$chunkIndex chunkStart=$chunkStart '
        'chunkEnd=$chunkEnd read=$absoluteReadStart-$absoluteReadEnd',
      );

      if (await _isChunkCached(chunkIndex)) {
        final readStart = absoluteReadStart - chunkStart;
        final readEnd = absoluteReadEnd - chunkStart;
        _log('cache hit index=$chunkIndex read=$readStart-$readEnd');
        await _writeCachedChunk(
          response,
          index: chunkIndex,
          start: absoluteReadStart,
          end: absoluteReadEnd,
        );
      } else if (absoluteReadStart == chunkStart &&
          absoluteReadEnd == chunkEnd) {
        await _cacheChunk(chunkIndex, output: response);
      } else {
        await _streamBackendRange(response, absoluteReadStart, absoluteReadEnd);
      }
      if (absoluteReadEnd == chunkEnd) {
        _schedulePrefetch(chunkIndex + 1);
      }
      offset = absoluteReadEnd + 1;
    }
  }

  void _schedulePrefetch(int index) {
    for (var i = 0; i < _prefetchCount; i++) {
      _prefetchChunk(index + i);
    }
  }

  void _prefetchChunk(int index) {
    if (index < 0 || index * _chunkSize >= size) {
      return;
    }
    if (_cachedChunkIndices.contains(index) ||
        _inflightChunks.containsKey(index)) {
      return;
    }
    unawaited(_cacheChunk(index));
  }

  Future<void> _cacheChunk(int index, {HttpResponse? output}) async {
    final start = index * _chunkSize;
    final end = _chunkEnd(index);
    final file = _chunkFile(index);
    final expectedLength = end - start + 1;
    if (_cachedChunkIndices.contains(index)) {
      if (output != null) {
        await _writeCachedChunk(output, index: index, start: start, end: end);
      }
      return;
    }

    final inflight = _inflightChunks[index];
    if (inflight != null) {
      _log('wait inflight chunk index=$index');
      await inflight;
      if (output != null) {
        await _writeCachedChunk(output, index: index, start: start, end: end);
      }
      return;
    }

    final download = Future<void>(() async {
      final tempFile = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
      );
      final label = output == null ? 'prefetch' : 'chunk';
      _log('$label begin index=$index range=$start-$end');
      final backend = await _openBackendRange(start, end, 'chunk index=$index');
      final sink = tempFile.openWrite();
      var written = 0;
      var clientDisconnected = false;
      try {
        await for (final bytes in backend.stream) {
          written += bytes.length;
          if (output != null && !clientDisconnected) {
            try {
              output.add(bytes);
            } catch (error) {
              if (_isExpectedDisconnect(error)) {
                clientDisconnected = true;
                _log('client disconnected index=$index');
              } else {
                rethrow;
              }
            }
          }
          sink.add(bytes);
        }
      } catch (error) {
        if (!_isExpectedDisconnect(error)) {
          rethrow;
        }
      } finally {
        await sink.close();
      }

      if (written == expectedLength) {
        if (await file.exists()) {
          await tempFile.delete();
        } else {
          await tempFile.rename(file.path);
          _cachedChunkIndices.add(index);
          unawaited(notifyCachedRanges());
        }
        _log('$label complete index=$index length=$written cached=true');
      } else {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        _log(
          '$label incomplete index=$index length=$written expected=$expectedLength',
        );
      }
    });
    _inflightChunks[index] = download;
    try {
      await download;
    } finally {
      if (identical(_inflightChunks[index], download)) {
        _inflightChunks.remove(index);
      }
    }
  }

  Future<void> _streamBackendRange(
    HttpResponse output,
    int start,
    int end,
  ) async {
    final chunkIndex = start ~/ _chunkSize;
    final inflight = _inflightChunks[chunkIndex];
    if (inflight != null) {
      _log('wait inflight partial index=$chunkIndex range=$start-$end');
      await inflight;
      await _writeCachedChunk(
        output,
        index: chunkIndex,
        start: start,
        end: end,
      );
      return;
    }

    _log('stream partial begin range=$start-$end');
    final backend = await _openBackendRange(start, end, 'partial');
    var written = 0;
    try {
      await for (final bytes in backend.stream) {
        written += bytes.length;
        output.add(bytes);
      }
    } catch (error) {
      if (!_isExpectedDisconnect(error)) {
        rethrow;
      }
      _log('stream partial aborted range=$start-$end error=$error');
    }
    _log('stream partial complete range=$start-$end length=$written');
  }

  Future<http.StreamedResponse> _openBackendRange(
    int start,
    int end,
    String label,
  ) async {
    final request = http.Request('GET', api.streamUri(path));
    request.headers.addAll(api.authHeaders());
    request.headers[HttpHeaders.rangeHeader] = 'bytes=$start-$end';

    final response = await request.send();
    _log(
      'backend response $label range=$start-$end status=${response.statusCode} '
      'contentLength=${response.contentLength}',
    );
    if (response.statusCode != HttpStatus.partialContent) {
      throw HttpException('视频分片请求失败：${response.statusCode}');
    }
    return response;
  }

  File _chunkFile(int index) {
    return File('${_cacheDir.path}/$index.bin');
  }

  Future<void> _closeResponseSafely(HttpResponse response) async {
    try {
      await response.close();
    } catch (error) {
      if (!_isExpectedDisconnect(error)) {
        rethrow;
      }
    }
  }

  Future<bool> _isChunkCached(int index) async {
    return _cachedChunkIndices.contains(index);
  }

  List<CachedVideoRange> _cachedRangesFromIndices() {
    if (_cachedChunkIndices.isEmpty) {
      return const [];
    }
    final sorted = _cachedChunkIndices.toList()..sort();
    final ranges = <CachedVideoRange>[];
    var startIndex = sorted.first;
    var previousIndex = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final index = sorted[i];
      if (index != previousIndex + 1) {
        ranges.add(
          CachedVideoRange(
            start: startIndex * _chunkSize,
            end: _chunkEnd(previousIndex),
          ),
        );
        startIndex = index;
      }
      previousIndex = index;
    }
    ranges.add(
      CachedVideoRange(
        start: startIndex * _chunkSize,
        end: _chunkEnd(previousIndex),
      ),
    );
    return ranges;
  }

  Future<void> _writeCachedChunk(
    HttpResponse output, {
    required int index,
    required int start,
    required int end,
  }) async {
    if (!await _isChunkCached(index)) {
      throw StateError('缓存分片未完成：$index');
    }
    final chunkStart = index * _chunkSize;
    final readStart = start - chunkStart;
    final readEnd = end - chunkStart;
    await output.addStream(_chunkFile(index).openRead(readStart, readEnd + 1));
  }

  bool _isExpectedDisconnect(Object error) {
    if (error is HttpException) {
      final message = error.message.toLowerCase();
      return message.contains(
            'no content even though contentlength was specified',
          ) ||
          message.contains('connection closed') ||
          message.contains('broken pipe') ||
          message.contains('connection reset');
    }
    if (error is http.ClientException) {
      final message = error.message.toLowerCase();
      return message.contains('connection closed') ||
          message.contains('broken pipe') ||
          message.contains('connection reset');
    }
    if (error is SocketException) {
      final message = error.message.toLowerCase();
      return message.contains('broken pipe') ||
          message.contains('connection reset');
    }
    return false;
  }

  int _chunkEnd(int index) {
    final end = (index + 1) * _chunkSize - 1;
    return end >= size ? size - 1 : end;
  }

  _RequestRange? _parseRange(String? value) {
    if (value == null || !value.startsWith('bytes=')) {
      return null;
    }
    final parts = value.substring(6).split('-');
    if (parts.length != 2 || parts.first.isEmpty) {
      return null;
    }
    final start = int.tryParse(parts.first);
    final end = parts.last.isEmpty ? null : int.tryParse(parts.last);
    if (start == null) {
      return null;
    }
    return _RequestRange(start: start, end: end);
  }

  String _cacheKey() {
    final raw = '${api.baseUrl}|$path|$size|$mtime';
    return _fnv1a64(utf8.encode(raw));
  }

  String _fnv1a64(List<int> bytes) {
    const mask = 0xFFFFFFFFFFFFFFFF;
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  void _log(String message) {
    stderr.writeln('[VideoCacheProxy] $message');
  }
}

class CachedVideoRange {
  const CachedVideoRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _RequestRange {
  const _RequestRange({required this.start, required this.end});

  final int start;
  final int? end;
}
