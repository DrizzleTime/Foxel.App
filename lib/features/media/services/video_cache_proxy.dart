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
  final _inFlightChunks = <int, Future<File>>{};

  Stream<List<CachedVideoRange>> get cachedRangesStream =>
      _cachedChunksController.stream;

  Future<Uri> start() async {
    final baseDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${baseDir.path}/video_cache/${_cacheKey()}');
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    await notifyCachedRanges();
    return Uri.parse('http://127.0.0.1:${_server!.port}/video');
  }

  Future<void> close() async {
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
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader));
    final start = range?.start ?? 0;
    final end = range?.end ?? (size > 0 ? size - 1 : null);
    if (size <= 0 || start < 0 || end == null || start > end || end >= size) {
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

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    try {
      await _writeRange(response, start, end);
    } finally {
      await response.close();
    }
  }

  Future<void> _writeRange(HttpResponse response, int start, int end) async {
    var offset = start;
    while (offset <= end) {
      final chunkIndex = offset ~/ _chunkSize;
      final chunkStart = chunkIndex * _chunkSize;
      final chunkEnd = _chunkEnd(chunkIndex);
      final file = await _chunkFile(chunkIndex);
      final readStart = offset - chunkStart;
      final readEnd = end < chunkEnd ? end - chunkStart : chunkEnd - chunkStart;

      final stream = file.openRead(readStart, readEnd + 1);
      await response.addStream(stream);
      offset = chunkStart + readEnd + 1;
    }
  }

  Future<File> _chunkFile(int index) {
    return _inFlightChunks.putIfAbsent(index, () async {
      try {
        final file = File('${_cacheDir.path}/$index.bin');
        final expectedLength = _chunkEnd(index) - index * _chunkSize + 1;
        if (await file.exists() && await file.length() == expectedLength) {
          return file;
        }

        final tempFile = File('${file.path}.part');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        await _downloadChunk(index, tempFile);
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);
        unawaited(notifyCachedRanges());
        return file;
      } finally {
        _inFlightChunks.remove(index);
      }
    });
  }

  Future<void> _downloadChunk(int index, File output) async {
    final start = index * _chunkSize;
    final end = _chunkEnd(index);
    final request = http.Request('GET', api.streamUri(path));
    request.headers.addAll(api.authHeaders());
    request.headers[HttpHeaders.rangeHeader] = 'bytes=$start-$end';

    final response = await request.send();
    if (response.statusCode != HttpStatus.partialContent) {
      throw HttpException('缓存分片失败：${response.statusCode}');
    }

    final sink = output.openWrite();
    try {
      await response.stream.pipe(sink);
    } finally {
      await sink.close();
    }
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
