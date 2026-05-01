import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class QrCodeDecoder {
  const QrCodeDecoder();

  String? decodeBytes(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      return null;
    }
    final grayscale = img.grayscale(img.bakeOrientation(image));
    return _decodeLuminance(_ImageLuminanceSource(grayscale));
  }

  String? decodeCameraImage(CameraImage image) {
    if (image.planes.isEmpty) {
      return null;
    }
    final plane = image.planes.first;
    final source = _YPlaneLuminanceSource(
      _compactRows(plane.bytes, image.width, image.height, plane.bytesPerRow),
      image.width,
      image.height,
    );
    final cropped = _centerCrop(source);
    return _decodeLuminance(cropped) ?? _decodeLuminance(source);
  }

  String? _decodeLuminance(LuminanceSource source) {
    try {
      final result = QRCodeReader().decode(
        BinaryBitmap(HybridBinarizer(source)),
      );
      return result.text;
    } on ReaderException {
      return null;
    }
  }
}

class _YPlaneLuminanceSource extends LuminanceSource {
  _YPlaneLuminanceSource(this._bytes, int width, int height)
    : super(width, height);

  final Int8List _bytes;

  @override
  Int8List getRow(int y, Int8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    final width = this.width;
    row ??= Int8List(width);
    if (row.length < width) {
      row = Int8List(width);
    }
    final offset = y * width;
    row.setRange(0, width, _bytes, offset);
    return row;
  }

  @override
  Int8List getMatrix() {
    return _bytes;
  }

  @override
  bool get isCropSupported => true;

  @override
  LuminanceSource crop(int left, int top, int width, int height) {
    if (left < 0 ||
        top < 0 ||
        left + width > this.width ||
        top + height > this.height) {
      throw ArgumentError('Crop rectangle does not fit within image data.');
    }
    return _CroppedYPlaneLuminanceSource(
      _bytes,
      this.width,
      left,
      top,
      width,
      height,
    );
  }
}

class _CroppedYPlaneLuminanceSource extends LuminanceSource {
  _CroppedYPlaneLuminanceSource(
    this._bytes,
    this._dataWidth,
    this._left,
    this._top,
    int width,
    int height,
  ) : super(width, height);

  final Int8List _bytes;
  final int _dataWidth;
  final int _left;
  final int _top;

  @override
  Int8List getRow(int y, Int8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    final width = this.width;
    row ??= Int8List(width);
    if (row.length < width) {
      row = Int8List(width);
    }
    final offset = (_top + y) * _dataWidth + _left;
    row.setRange(0, width, _bytes, offset);
    return row;
  }

  @override
  Int8List getMatrix() {
    final width = this.width;
    final height = this.height;
    final matrix = Int8List(width * height);
    var outputOffset = 0;
    var inputOffset = _top * _dataWidth + _left;
    for (var y = 0; y < height; y++) {
      matrix.setRange(outputOffset, outputOffset + width, _bytes, inputOffset);
      outputOffset += width;
      inputOffset += _dataWidth;
    }
    return matrix;
  }

  @override
  bool get isCropSupported => true;

  @override
  LuminanceSource crop(int left, int top, int width, int height) {
    if (left < 0 ||
        top < 0 ||
        left + width > this.width ||
        top + height > this.height) {
      throw ArgumentError('Crop rectangle does not fit within image data.');
    }
    return _CroppedYPlaneLuminanceSource(
      _bytes,
      _dataWidth,
      _left + left,
      _top + top,
      width,
      height,
    );
  }
}

class _ImageLuminanceSource extends LuminanceSource {
  _ImageLuminanceSource(this._image) : super(_image.width, _image.height);

  final img.Image _image;

  @override
  Int8List getRow(int y, Int8List? row) {
    if (y < 0 || y >= height) {
      throw ArgumentError('Requested row is outside the image: $y');
    }
    final width = this.width;
    row ??= Int8List(width);
    if (row.length < width) {
      row = Int8List(width);
    }
    for (var x = 0; x < width; x++) {
      row[x] = _image.getPixel(x, y).luminance.round();
    }
    return row;
  }

  @override
  Int8List getMatrix() {
    final matrix = Int8List(width * height);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        matrix[offset++] = _image.getPixel(x, y).luminance.round();
      }
    }
    return matrix;
  }
}

Int8List _compactRows(Uint8List bytes, int width, int height, int bytesPerRow) {
  if (bytesPerRow == width && bytes.lengthInBytes >= width * height) {
    return Int8List.view(bytes.buffer, bytes.offsetInBytes, width * height);
  }
  final luminance = Int8List(width * height);
  var outputOffset = 0;
  var inputOffset = 0;
  for (var y = 0; y < height; y++) {
    luminance.setRange(outputOffset, outputOffset + width, bytes, inputOffset);
    outputOffset += width;
    inputOffset += bytesPerRow;
  }
  return luminance;
}

LuminanceSource _centerCrop(LuminanceSource source) {
  final cropWidth = (source.width * 0.8).round();
  final cropHeight = (source.height * 0.8).round();
  if (cropWidth <= 0 ||
      cropHeight <= 0 ||
      cropWidth >= source.width ||
      cropHeight >= source.height) {
    return source;
  }
  final left = (source.width - cropWidth) ~/ 2;
  final top = (source.height - cropHeight) ~/ 2;
  return source.crop(left, top, cropWidth, cropHeight);
}
