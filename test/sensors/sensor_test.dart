import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensebox_bike/sensors/sensor.dart';

void main() {
  group('decodeLittleEndianFloat32s()', () {
    test('decodes empty input to empty output', () {
      expect(decodeLittleEndianFloat32s(Uint8List(0)), []);
    });

    void testSingleFloat32(double d) {
      test('decodes a single float32 $d', () {
        final bytes = ByteData(4);
        bytes.setFloat32(0, d, Endian.little);
        expect(decodeLittleEndianFloat32s(bytes.buffer.asUint8List()), [d]);
      });
    }

    testSingleFloat32(0);
    testSingleFloat32(1);
    testSingleFloat32(-1);
    testSingleFloat32(1.5);
    testSingleFloat32(-7.750000476837158203125);

    test('decodes multiple float32', () {
      List<double> ds = [0, -1.5, 13.25];
      final bytes = ByteData(ds.length * 4);
      for (final (i, d) in ds.indexed) {
        bytes.setFloat32(i * 4, d, Endian.little);
      }
      expect(decodeLittleEndianFloat32s(bytes.buffer.asUint8List()), ds);
    });

    test('ignores extraneous bytes', () {
      final bytes = ByteData(7);
      bytes.setFloat32(0, -1.5, Endian.little);
      bytes.setUint8(4, 15);
      bytes.setUint8(5, 115);
      bytes.setUint8(6, 255);
      expect(decodeLittleEndianFloat32s(bytes.buffer.asUint8List()), [-1.5]);
    });
  });
}
