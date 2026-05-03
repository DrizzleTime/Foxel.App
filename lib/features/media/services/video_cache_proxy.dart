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

  final FoxelApi api;
  final String path;
  final int size;
  final int mtime;

  HttpServer? _server;
  late final Directory _cacheDir;
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
    _cachedChunksController.add(await cachedRanges());
  }

  Future<List<CachedVideoRange>> cachedRanges() async {
    final ranges = <CachedVideoRange>[];
    if (!await _cacheDir.exists()) {
      return ranges;
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
        ranges.add(CachedVideoRange(start: start, end: end));
      }
    }

    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
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
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/octet-stream',
    );
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
      await response.close();
      return;
    }

    try {
      await _writeRange(response, start, end);
      _log('request complete start=$start end=$end');
    } catch (error, stackTrace) {
      _log('request failed start=$start end=$end error=$error');
      _log('$stackTrace');
      rethrow;
    } finally {
      await response.close();
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

      final file = _chunkFile(chunkIndex);
      final expectedLength = chunkEnd - chunkStart + 1;
      final isCached =
          await file.exists() && await file.length() == expectedLength;
      if (isCached) {
        final readStart = absoluteReadStart - chunkStart;
        final readEnd = absoluteReadEnd - chunkStart;
        _log('cache hit index=$chunkIndex read=$readStart-$readEnd');
        await response.addStream(file.openRead(readStart, readEnd + 1));
      } else if (absoluteReadStart == chunkStart &&
          absoluteReadEnd == chunkEnd) {
        await _streamAndCacheChunk(response, chunkIndex);
      } else {
        await _streamBackendRange(response, absoluteReadStart, absoluteReadEnd);
      }
      offset = absoluteReadEnd + 1;
    }
  }

  Future<void> _streamAndCacheChunk(HttpResponse output, int index) async {
    final start = index * _chunkSize;
    final end = _chunkEnd(index);
    final file = _chunkFile(index);
    final expectedLength = end - start + 1;
    if (await file.exists() && await file.length() == expectedLength) {
      _log('cache completed before stream index=$index');
      await output.addStream(file.openRead());
      return;
    }

    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    _log('stream miss begin index=$index range=$start-$end');
    final backend = await _openBackendRange(start, end, 'chunk index=$index');
    final sink = tempFile.openWrite();
    var written = 0;
    try {
      await for (final bytes in backend.stream) {
        written += bytes.length;
        output.add(bytes);
        sink.add(bytes);
        await output.flush();
      }
    } finally {
      await sink.close();
    }

    if (written == expectedLength) {
      if (await file.exists()) {
        await tempFile.delete();
      } else {
        await tempFile.rename(file.path);
        unawaited(notifyCachedRanges());
      }
      _log('stream miss complete index=$index length=$written cached=true');
    } else {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      _log(
        'stream miss incomplete index=$index length=$written '
        'expected=$expectedLength',
      );
    }
  }

  Future<void> _streamBackendRange(
    HttpResponse output,
    int start,
    int end,
  ) async {
    _log('stream partial begin range=$start-$end');
    final backend = await _openBackendRange(start, end, 'partial');
    var written = 0;
    await for (final bytes in backend.stream) {
      written += bytes.length;
      output.add(bytes);
      await output.flush();
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
