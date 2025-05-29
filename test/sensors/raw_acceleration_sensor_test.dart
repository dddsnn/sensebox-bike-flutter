import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:sensebox_bike/sensors/raw_acceleration_sensor.dart';

extension AddBigEndianElements on List<int> {
  void addFloat32(double d) {
    final data = ByteData(4);
    data.setFloat32(0, d, Endian.big);
    addAll(Uint8List.view(data.buffer));
  }

  void addUint32(int i) {
    final data = ByteData(4);
    data.setUint32(0, i, Endian.big);
    addAll(Uint8List.view(data.buffer));
  }

  void addUint8(int i) {
    final data = ByteData(1);
    data.setUint8(0, i);
    addAll(Uint8List.view(data.buffer));
  }
}

Matcher rawAccelRecord(int millisSinceDeviceStartup, double z) {
  return allOf(
      isA<RawAccelerationRecord>(),
      predicate((RawAccelerationRecord record) {
        return record.millisSinceDeviceStartup == millisSinceDeviceStartup &&
            record.z == z;
      },
          'acceleration record with millisSinceDeviceStartup = '
          '$millisSinceDeviceStartup and z = $z'));
}

void main() {
  group('decodeRawAccelerationRecords()', () {
    test('decodes empty input to empty output', () {
      expect(decodeRawAccelerationRecords(Uint8List(0)), []);
    });

    test('decodes first value', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      expect(decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([rawAccelRecord(100, 1.5)]));
    });

    test('decodes empty if not enough bytes for first value', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.removeLast();
      expect(decodeRawAccelerationRecords(Uint8List.fromList(bytes)), []);
    });

    test('decodes uses big endian', () {
      final bytes = <int>[];
      final int millis = (1 << 5) + (1 << 12) + (1 << 18) + (1 << 28);
      final z = -7.750000476837158203125;
      bytes.addUint32(millis);
      bytes.addFloat32(z);
      expect(decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([rawAccelRecord(millis, z)]));
    });

    test('decodes multiple values', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(1);
      bytes.addFloat32(-2.0);
      bytes.addUint8(9);
      bytes.addFloat32(3.25);
      expect(
          decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([
            rawAccelRecord(100, 1.5),
            rawAccelRecord(101, -2.0),
            rawAccelRecord(110, 3.25)
          ]));
    });

    test('ignores extraneous bytes', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(1);
      bytes.addFloat32(-2.0);
      bytes.addUint8(9);
      bytes.addFloat32(3.25);
      bytes.removeLast();
      expect(decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([rawAccelRecord(100, 1.5), rawAccelRecord(101, -2.0)]));
    });
  });
}
