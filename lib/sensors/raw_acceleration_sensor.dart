import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:sensebox_bike/blocs/ble_bloc.dart';
import 'package:sensebox_bike/blocs/geolocation_bloc.dart';
import 'package:sensebox_bike/l10n/app_localizations.dart';
import 'package:sensebox_bike/models/geolocation_data.dart';
import 'package:sensebox_bike/services/isar_service.dart';
import 'package:sensebox_bike/sensors/sensor.dart';
import 'package:sensebox_bike/ui/widgets/sensor/sensor_card.dart';
import 'package:sensebox_bike/utils/sensor_utils.dart';

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
  void onDataReceived(List<RawAccelerationRecord> data) {}

  @override
  void onChangedGeolocation(GeolocationData geolocationData) {}

  @override
  Widget buildWidget() {
    return StreamBuilder<List<double>>(
      stream: Stream.value([0, 0, 0]),
      initialData: [0, 0, 0],
      builder: (context, snapshot) {
        List<double> displayValues = snapshot.data ?? [0, 0, 0];

        return SensorCard(
            title: AppLocalizations.of(context)!.sensorAcceleration,
            icon: getSensorIcon(title),
            color: getSensorColor(title),
            child: AspectRatio(
                aspectRatio: 1.4,
                child: BarChart(
                  BarChartData(
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(enabled: false),
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, _) {
                              switch (value.toInt()) {
                                case 0:
                                  return const Text(
                                    'X',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  );
                                case 1:
                                  return const Text(
                                    'Y',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  );
                                case 2:
                                  return const Text(
                                    'Z',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [
                            BarChartRodData(
                              toY: displayValues[0],
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: 20,
                                color: Colors.grey.shade100,
                              ),
                            )
                          ],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [
                            BarChartRodData(
                              toY: displayValues[1],
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: 20,
                                color: Colors.grey.shade100,
                              ),
                            )
                          ],
                        ),
                        BarChartGroupData(
                          x: 2,
                          barRods: [
                            BarChartRodData(
                              toY: displayValues[2],
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: 20,
                                color: Colors.grey.shade100,
                              ),
                            )
                          ],
                        ),
                      ]),
                  swapAnimationDuration:
                      const Duration(milliseconds: 250), // Optional
                  swapAnimationCurve: Curves.easeOut, // Optional
                )));
      },
    );
  }
}
