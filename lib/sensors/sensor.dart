import 'dart:async';
import 'dart:typed_data';
import 'package:sensebox_bike/blocs/ble_bloc.dart';
import 'package:sensebox_bike/blocs/geolocation_bloc.dart';
import 'package:sensebox_bike/models/sensor_data.dart';
import 'package:sensebox_bike/models/geolocation_data.dart';
import 'package:sensebox_bike/services/isar_service.dart';
import 'package:flutter/material.dart';

List<double> decodeLittleEndianFloat32s(Uint8List value) {
  // This method converts the incoming data from a characteristic to a list of
  // doubles, assuming little endian byte order.
  List<double> parsedValues = [];
  for (int i = 0; i < value.length; i += 4) {
    if (i + 4 <= value.length) {
      parsedValues.add(
          ByteData.sublistView(value, i, i + 4).getFloat32(0, Endian.little));
    }
  }
  return parsedValues;
}

abstract class Sensor<DataType> {
  final String characteristicUuid;
  final String title;

  final BleBloc bleBloc;
  final GeolocationBloc geolocationBloc;
  final IsarService isarService;
  StreamSubscription<DataType>? _subscription;

  Sensor(
    this.characteristicUuid,
    this.title,
    this.bleBloc,
    this.geolocationBloc,
    this.isarService,
  );

  int get uiPriority;

  /// Decodes characteristic bytes into a useful data type.
  DataType decodeCharacteristicData(Uint8List value);

  /// Called whenever new  sensor data comes in.
  void onDataReceived(DataType data);

  /// Called whenever a new geolocation is available.
  void onChangedGeolocation(GeolocationData geolocationData);

  /// Builds a UI representation of the sensor.
  Widget buildWidget();

  void dispose() {
    stopListening();
  }

  void startListening() async {
    try {
      // Listen to the sensor data stream.
      _subscription = bleBloc
          .getCharacteristicStream(characteristicUuid)
          .map(decodeCharacteristicData)
          .listen(onDataReceived);

      // REFACTOR instead of watching for changes and then querying the new
      // location, watch the query and get the new location immediately+++++++++
      // Listen to geolocation updates.
      (await isarService.geolocationService.getGeolocationStream())
          .listen((_) async {
        GeolocationData? geolocationData = await isarService.geolocationService
            .getLastGeolocationData(); // Get the latest geolocation data
        if (geolocationData != null) {
          onChangedGeolocation(geolocationData);
        }
      });
    } catch (e) {
      print('Error starting sensor: $e');
    }
  }

  void stopListening() {
    _subscription?.cancel();
  }
}

/// A sensor aggregating data to geolocation updates.
///
/// A sensor whose data type is a list of doubles, i.e. each time new sensor
/// data comes in, the byte sequence is decoded as a sequence of little endian
/// float32s. New data is stored in a buffer. Whenever a geolocation update is
/// available, all buffered data is aggregated using the abstract
/// [aggregateData], saved as a [SensorData], and the buffer reset.
abstract class LocationAggregatingSensor extends Sensor<List<double>> {
  final List<String> attributes;
  final StreamController<List<double>> _valueController =
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get valueStream => _valueController.stream;

  final List<List<double>> _valueBuffer = [];

  LocationAggregatingSensor(
    characteristicUuid,
    title,
    this.attributes,
    bleBloc,
    geolocationBloc,
    isarService,
  ) : super(
          characteristicUuid,
          title,
          bleBloc,
          geolocationBloc,
          isarService,
        );

  /// Aggregates many sensor data points into a single one.
  List<double> aggregateData(List<List<double>> valueBuffer);

  @override
  List<double> decodeCharacteristicData(Uint8List value) {
    return decodeLittleEndianFloat32s(value);
  }

  @override
  void onDataReceived(List<double> data) {
    if (data.isNotEmpty) {
      _valueBuffer.add(data); // Buffer the sensor data
      _valueController.add(data); // Emit the latest sensor value to the stream
    }
  }

  @override
  void onChangedGeolocation(GeolocationData geolocationData) {
    if (_valueBuffer.isNotEmpty) {
      _aggregateAndStoreData(
          geolocationData); // Aggregate and store sensor data
      _valueBuffer.clear(); // Clear the list after aggregation
    }
  }

  // Aggregate sensor data and store it with the latest geolocation
  void _aggregateAndStoreData(GeolocationData geolocationData) {
    if (_valueBuffer.isEmpty) {
      return;
    }

    List<double> aggregatedValues = aggregateData(_valueBuffer);

    if (attributes.isEmpty) {
      _saveSensorData(aggregatedValues[0], null, geolocationData);
    } else {
      if (attributes.length != aggregatedValues.length) {
        throw Exception(
            'Number of attributes does not match the number of aggregated values');
      }

      for (int i = 0; i < attributes.length; i++) {
        _saveSensorData(aggregatedValues[i], attributes[i], geolocationData);
      }
    }
  }

  // Helper method to save sensor data
  void _saveSensorData(
      double value, String? attribute, GeolocationData geolocationData) {
    isarService.geolocationService.saveGeolocationData(geolocationData);

    if (value.isNaN) {
      return;
    }

    final sensorData = SensorData()
      ..characteristicUuid = characteristicUuid
      ..title = title
      ..value = value
      ..attribute = attribute
      ..geolocationData.value = geolocationData;

    isarService.sensorService.saveSensorData(sensorData);
  }

  @override
  void dispose() {
    super.dispose();
    _valueController
        .close(); // Close the stream controller to prevent memory leaks
  }
}
