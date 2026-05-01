import 'dart:typed_data';

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
