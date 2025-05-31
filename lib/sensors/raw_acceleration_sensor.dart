import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:sensebox_bike/blocs/ble_bloc.dart';
import 'package:sensebox_bike/blocs/geolocation_bloc.dart';
import 'package:sensebox_bike/l10n/app_localizations.dart';
import 'package:sensebox_bike/models/geolocation_data.dart';
import 'package:sensebox_bike/services/isar_service.dart';
import 'package:sensebox_bike/sensors/sensor.dart';
import 'package:sensebox_bike/ui/widgets/sensor/sensor_card.dart';

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

class RawAccelerationSensor extends Sensor<List<RawAccelerationRecord>> {
  static const String sensorCharacteristicUuid =
      'b944af10-f495-4560-968f-2f0d18cab524';

  int _numRecordsReceived = 0;
  final _numRecordsStreamController = StreamController<int>();

  RawAccelerationSensor(
      BleBloc bleBloc, GeolocationBloc geolocationBloc, IsarService isarService)
      : super(sensorCharacteristicUuid, "raw acceleration", bleBloc,
            geolocationBloc, isarService);

  @override
  get uiPriority => 25;

  @override
  List<RawAccelerationRecord> decodeCharacteristicData(Uint8List bytes) {
    return decodeRawAccelerationRecords(bytes);
  }

  @override
  void onDataReceived(List<RawAccelerationRecord> data) {
    _numRecordsReceived += data.length;
    _numRecordsStreamController.add(_numRecordsReceived);
  }

  @override
  void onChangedGeolocation(GeolocationData geolocationData) {}

  @override
  Widget buildWidget() {
    return StreamBuilder<int>(
      stream: _numRecordsStreamController.stream,
      initialData: 0,
      builder: (context, snapshot) {
        final numRecordsReceived = snapshot.data;
        return SensorCard(
            title: AppLocalizations.of(context)!.sensorRawAcceleration,
            icon: Icons.vibration,
            color: Colors.greenAccent,
            child: AspectRatio(
                aspectRatio: 1.4,
                child: Text('records received: $numRecordsReceived')));
      },
    );
  }
}
