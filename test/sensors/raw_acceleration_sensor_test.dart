import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

import 'package:sensebox_bike/sensors/raw_acceleration_sensor.dart';

extension AddBigEndianElements on List<int> {
  void addFloat32(double d, {Endian endian = Endian.big}) {
    final data = ByteData(4);
    data.setFloat32(0, d, endian);
    addAll(Uint8List.view(data.buffer));
  }

  void addUint32(int i, {Endian endian = Endian.big}) {
    final data = ByteData(4);
    data.setUint32(0, i, endian);
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
  group('ByteDataStream', () {
    test('has zero remaining on empty buffer', () {
      final bytes = <int>[];
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(stream.bytesRemaining, 0);
    });

    test('raises on read from empty buffer', () {
      final bytes = <int>[];
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(() => stream.readUint8(), throwsA(isA<NotEnoughBytes>()));
      expect(() => stream.readUint32(), throwsA(isA<NotEnoughBytes>()));
      expect(() => stream.readFloat32(), throwsA(isA<NotEnoughBytes>()));
    });

    test('reads single uint8', () {
      final bytes = <int>[];
      bytes.addUint8(100);
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(stream.readUint8(), 100);
    });

    test('reads single uint32', () {
      final bytes = <int>[];
      final int i = (1 << 5) + (1 << 12) + (1 << 18) + (1 << 28);
      bytes.addUint32(i);
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(stream.readUint32(), i);
    });

    test('reads single float32', () {
      final bytes = <int>[];
      final f = -7.750000476837158203125;
      bytes.addFloat32(f);
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(stream.readFloat32(), f);
    });

    test('reads consecutive values', () {
      final bytes = <int>[];
      bytes.addUint8(100);
      bytes.addUint32(1000);
      bytes.addUint8(101);
      bytes.addFloat32(1000.5);
      bytes.addUint8(102);
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(stream.readUint8(), 100);
      expect(stream.readUint32(), 1000);
      expect(stream.readUint8(), 101);
      expect(stream.readFloat32(), 1000.5);
      expect(stream.readUint8(), 102);
    });

    test('raises on read from insufficient remaining', () {
      final bytes = <int>[1, 2, 3];
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(() => stream.readUint32(), throwsA(isA<NotEnoughBytes>()));
      expect(() => stream.readFloat32(), throwsA(isA<NotEnoughBytes>()));
      stream.readUint8();
      stream.readUint8();
      stream.readUint8();
      expect(() => stream.readUint8(), throwsA(isA<NotEnoughBytes>()));
    });

    test('can also do little endian', () {
      final bytes = <int>[];
      final int i = (1 << 5) + (1 << 12) + (1 << 18) + (1 << 28);
      final f = -7.750000476837158203125;
      bytes.addUint32(i, endian: Endian.little);
      bytes.addFloat32(f, endian: Endian.little);
      final stream =
          ByteDataStream(Uint8List.fromList(bytes), endian: Endian.little);
      expect(stream.readUint32(), i);
      expect(stream.readFloat32(), f);
    });

    test('tracks bytes remaining', () {
      final bytes = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final stream = ByteDataStream(Uint8List.fromList(bytes));
      expect(stream.bytesRemaining, 10);
      stream.readUint8();
      expect(stream.bytesRemaining, 9);
      stream.readUint32();
      expect(stream.bytesRemaining, 5);
      stream.readFloat32();
      expect(stream.bytesRemaining, 1);
      stream.readUint8();
      expect(stream.bytesRemaining, 0);
    });
  });

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

    test('decodes multiple values with all short ts diffs', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(1);
      bytes.addFloat32(-2.0);
      bytes.addUint8(255);
      bytes.addFloat32(3.25);
      expect(
          decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([
            rawAccelRecord(100, 1.5),
            rawAccelRecord(101, -2.0),
            rawAccelRecord(356, 3.25)
          ]));
    });

    test('decodes multiple values with some long ts diffs', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(0);
      bytes.addUint32(356);
      bytes.addFloat32(-2.0);
      bytes.addUint8(4);
      bytes.addFloat32(3.25);
      expect(
          decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([
            rawAccelRecord(100, 1.5),
            rawAccelRecord(356, -2.0),
            rawAccelRecord(360, 3.25)
          ]));
    });

    test('decodes multiple values with some zero ts diffs', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(0);
      bytes.addUint32(100);
      bytes.addFloat32(-2.0);
      bytes.addUint8(12);
      bytes.addFloat32(3.25);
      expect(
          decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([
            rawAccelRecord(100, 1.5),
            rawAccelRecord(100, -2.0),
            rawAccelRecord(112, 3.25)
          ]));
    });

    test('decodes multiple values with some negative ts diffs', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(0);
      bytes.addUint32(99);
      bytes.addFloat32(-2.0);
      bytes.addUint8(13);
      bytes.addFloat32(3.25);
      expect(
          decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([
            rawAccelRecord(100, 1.5),
            rawAccelRecord(99, -2.0),
            rawAccelRecord(112, 3.25)
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

    test('ignores extraneous bytes that are supposed to be a long ts diff', () {
      final bytes = <int>[];
      bytes.addUint32(100);
      bytes.addFloat32(1.5);
      bytes.addUint8(0);
      bytes.addUint32(99);
      bytes.addFloat32(-2.0);
      bytes.removeLast();
      expect(decodeRawAccelerationRecords(Uint8List.fromList(bytes)),
          orderedEquals([rawAccelRecord(100, 1.5)]));
    });
  });
}
