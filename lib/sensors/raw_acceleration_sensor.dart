import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sensebox_bike/blocs/ble_bloc.dart';
import 'package:sensebox_bike/blocs/geolocation_bloc.dart';
import 'package:sensebox_bike/l10n/app_localizations.dart';
import 'package:sensebox_bike/models/geolocation_data.dart';
import 'package:sensebox_bike/services/isar_service.dart';
import 'package:sensebox_bike/sensors/sensor.dart';
import 'package:sensebox_bike/ui/widgets/sensor/sensor_card.dart';

/// Raised when a ByteDataStream doesn't find enough bytes left in the buffer.
class NotEnoughBytes implements Exception {
  final String valueKind;
  final int valueSize, bytesRemaining;

  NotEnoughBytes(this.valueKind, this.valueSize, this.bytesRemaining);

  @override
  String toString() {
    return 'not enough bytes to read a $valueKind (need $valueSize, have only '
        '$bytesRemaining)';
  }
}

/// A [ByteData]-like wrapper keeping track of its reading position.
///
/// Read typed data with the chosen endian from the input bytes. The position in
/// the buffer is incremented automatically. Check how many bytes remain with
/// [bytesRemaining].
class ByteDataStream {
  final int _length;
  final ByteData _data;
  final Endian _endian;
  int _i = 0;

  ByteDataStream(Uint8List bytes, {Endian endian = Endian.big})
      : _length = bytes.length,
        _data = ByteData.view(bytes.buffer),
        _endian = endian;

  get bytesRemaining => _length - _i;

  int readUint8() {
    return _read<int>('uint8', (i, _) => _data.getUint8(i), 1);
  }

  int readUint32() {
    return _read<int>('uint32', _data.getUint32, 4);
  }

  double readFloat32() {
    return _read<double>('float32', _data.getFloat32, 4);
  }

  T _read<T>(String valueKind, T Function(int offset, Endian endian) getValue,
      int valueSize) {
    try {
      final value = getValue(_i, _endian);
      _i += valueSize;
      return value;
    } on RangeError {
      throw NotEnoughBytes(valueKind, valueSize, bytesRemaining);
    }
  }
}

class RawAccelerationRecord {
  final int millisSinceDeviceStartup;
  final double z;
  RawAccelerationRecord(this.millisSinceDeviceStartup, this.z);
}

List<RawAccelerationRecord> decodeRawAccelerationRecords(Uint8List bytes) {
  List<RawAccelerationRecord> records = [];
  final stream = ByteDataStream(bytes, endian: Endian.big);
  int millis = 0;
  while (stream.bytesRemaining > 0) {
    try {
      if (records.isEmpty) {
        // First record, full uint32 milliseconds timestamp.
        millis = stream.readUint32();
      } else {
        final firstTimestampByte = stream.readUint8();
        if (firstTimestampByte != 0) {
          // Subsequent record short form, uint8 timestamp difference to
          // previous one.
          millis += firstTimestampByte;
        } else {
          // Subsequent record long form, first byte only informed us that the
          // next 4 bytes are a full timestamp again.
          millis = stream.readUint32();
        }
      }
      final z = stream.readFloat32();
      records.add(RawAccelerationRecord(millis, z));
    } on NotEnoughBytes catch (e) {
      print(
          'Unexpected end of input while parsing raw acceleration records: $e');
      break;
    }
  }
  return records;
}

class RawAccelerationRecords {
  final DateTime receiveTime;
  final List<RawAccelerationRecord> records;
  RawAccelerationRecords(this.receiveTime, this.records);
}

class RawAccelerationSensor extends Sensor<List<RawAccelerationRecord>> {
  static const String sensorCharacteristicUuid =
      'b944af10-f495-4560-968f-2f0d18cab524';

  final _accelRecords = <RawAccelerationRecords>[];
  final _geoDatas = <GeolocationData>[];
  final _change = StreamController<void>();

  RawAccelerationSensor(
      BleBloc bleBloc, GeolocationBloc geolocationBloc, IsarService isarService)
      : super(sensorCharacteristicUuid, "raw acceleration", bleBloc,
            geolocationBloc, isarService);

  @override
  get uiPriority => 25;

  @override
  void stopListening() async {
    // TODO Writing a file here is an ugly hack that I did because I didn't want
    // to figure out how to store the data properly.
    final Map recordsMap = {
      'rawAccelerationsRecords': [
        for (final rs in _accelRecords)
          {
            'receiveTime': rs.receiveTime.toIso8601String(),
            'rawAccelerations': [
              for (final r in rs.records)
                {
                  'millisSinceDeviceStartup': r.millisSinceDeviceStartup,
                  'z': r.z
                }
            ]
          }
      ],
      'geoLocationDatas': [
        for (final d in _geoDatas)
          {
            'receiveTime': d.timestamp.toIso8601String(),
            'lon': d.longitude,
            'lat': d.latitude,
            'speed': d.speed
          }
      ]
    };
    final encodedRecords = jsonEncode(recordsMap);
    Directory directory = await getApplicationDocumentsDirectory();
    String tsString = DateTime.now().toIso8601String();
    final file = File('${directory.path}/$tsString.json');
    await file.writeAsString(encodedRecords);
    super.stopListening();
  }

  @override
  List<RawAccelerationRecord> decodeCharacteristicData(Uint8List bytes) {
    return decodeRawAccelerationRecords(bytes);
  }

  @override
  void onDataReceived(List<RawAccelerationRecord> data) {
    _accelRecords.add(RawAccelerationRecords(DateTime.now(), data));
    _change.add(null);
  }

  @override
  void onChangedGeolocation(GeolocationData geolocationData) {
    _geoDatas.add(geolocationData);
    _change.add(null);
  }

  @override
  Widget buildWidget() {
    return StreamBuilder<void>(
      stream: _change.stream,
      initialData: null,
      builder: (context, snapshot) {
        return SensorCard(
            title: AppLocalizations.of(context)!.sensorRawAcceleration,
            icon: Icons.vibration,
            color: Colors.greenAccent,
            child: AspectRatio(
                aspectRatio: 1.4,
                child:
                    Text('record blocks received: ${_accelRecords.length}')));
      },
    );
  }
}
