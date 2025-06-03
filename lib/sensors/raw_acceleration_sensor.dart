import 'dart:async';
import 'dart:convert';
import 'dart:core'; // TODO remove++++++++++++
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:sensebox_bike/blocs/ble_bloc.dart';
import 'package:sensebox_bike/blocs/geolocation_bloc.dart';
import 'package:sensebox_bike/l10n/app_localizations.dart';
import 'package:sensebox_bike/main.dart';
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

class RawAccelerationSensor extends Sensor<List<RawAccelerationRecord>> {
  static const String sensorCharacteristicUuid =
      'b944af10-f495-4560-968f-2f0d18cab524';

  final _records = <RawAccelerationRecord>[];
  final _recordsChanged = StreamController<void>();
  // String _directory = 'unknown'; // TODO remove=++++++++++++

  RawAccelerationSensor(
      BleBloc bleBloc, GeolocationBloc geolocationBloc, IsarService isarService)
      : super(sensorCharacteristicUuid, "raw acceleration", bleBloc,
            geolocationBloc, isarService);

  @override
  get uiPriority => 25;

  // @override
  // void startListening() async {
  //   _directory = (await getApplicationDocumentsDirectory()).path;

  //   // final a = directory.path;
  //   super.startListening();
  // }

  // Future<String> _saveCsvFile(TrackData track, String csvString) async {
  //   final directory = await getApplicationDocumentsDirectory();

  //   if (track.geolocations.isEmpty) {
  //     throw Exception("Track has no geolocations");
  //   }

  //   String formattedTimestamp = DateFormat('yyyy-MM-dd_HH-mm')
  //       .format(track.geolocations.first.timestamp);

  //   String trackName = "senseBox_bike_$formattedTimestamp";

  //   final filePath = '${directory.path}/$trackName.csv';
  //   final file = File(filePath);

  //   await file.writeAsString(csvString);
  //   return filePath;
  // }
  @override
  void stopListening() async {
    print('raw accel stop listening-----------------------------');
    // REFACTOR is this the right place to write a file?++++++++++
    final List<Map> recordsMap = [
      for (final r in _records)
        {'millisSinceDeviceStartup': r.millisSinceDeviceStartup, 'z': r.z}
    ];
    final encodedRecords = jsonEncode(recordsMap);
    final directory = await getApplicationDocumentsDirectory();
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
    _records.addAll(data);
    _recordsChanged.add(null);
  }

  @override
  void onChangedGeolocation(GeolocationData geolocationData) {}

  @override
  Widget buildWidget() {
    // TODO++++++++++
    return StreamBuilder<void>(
      stream: _recordsChanged.stream,
      initialData: null,
      builder: (context, snapshot) {
        final numRecordsReceived = _records.length;
        return SensorCard(
            title: AppLocalizations.of(context)!.sensorRawAcceleration,
            icon: Icons.vibration,
            color: Colors.greenAccent,
            child: AspectRatio(
                aspectRatio: 1.4,
                child: Text(
                    'path: $asdfDataDir'))); //records received: $numRecordsReceived')));
      },
    );
  }
}
