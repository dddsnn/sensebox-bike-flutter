import 'dart:typed_data';

class RawAccelerationRecord {
  final int millisSinceDeviceStartup;
  final double z;
  RawAccelerationRecord(this.millisSinceDeviceStartup, this.z);
}

List<RawAccelerationRecord> decodeRawAccelerationRecords(Uint8List bytes) {
  List<RawAccelerationRecord> records = [];
  if (bytes.length < 8) {
    return records;
  }
  final data = ByteData.view(bytes.buffer);
  int i = 0, millis = 0;
  while (i + 5 <= bytes.length) {
    if (i == 0) {
      // First record, full uint32 milliseconds timestamp.
      millis = data.getUint32(i, Endian.big);
      i += 4;
    } else {
      // Subsequent record, uint8 timestamp difference to previous one.
      millis += data.getUint8(i);
      i += 1;
    }
    final z = data.getFloat32(i, Endian.big);
    i += 4;
    records.add(RawAccelerationRecord(millis, z));
  }
  return records;
}
