import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sensebox_bike/blocs/ble_bloc.dart';
import 'package:sensebox_bike/secrets.dart';
import 'package:sensebox_bike/blocs/settings_bloc.dart';

class MockBuildContext extends Mock implements BuildContext {}

class MockFlutterBluePlus extends Mock implements FlutterBluePlusMockable {}

class MockBluetoothDevice extends Mock implements BluetoothDevice {}

class MockBluetoothService extends Mock implements BluetoothService {}

class MockBluetoothCharacteristic extends Mock
    implements BluetoothCharacteristic {}

void main() {
  late BleBloc bleBloc;
  late StreamController<List<int>> characteristicController;
  final Guid characteristicGuid = Guid('beef');

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(LogLevel.debug);
  });

  setUp(() async {
    final flutterBluePlus = MockFlutterBluePlus();
    when(() => flutterBluePlus.setLogLevel(any()))
        .thenAnswer((_) async => Future.value());
    when(() => flutterBluePlus.adapterState)
        .thenAnswer((_) => Stream.value(BluetoothAdapterState.on));
    when(() => flutterBluePlus.stopScan())
        .thenAnswer((_) async => Future.value());
    bleBloc = BleBloc(SettingsBloc(), flutterBluePlus);
    final device = MockBluetoothDevice();
    final service = MockBluetoothService();
    final characteristic = MockBluetoothCharacteristic();
    characteristicController = StreamController<List<int>>();
    when(() => characteristic.uuid).thenReturn(characteristicGuid);
    when(() => characteristic.setNotifyValue(any()))
        .thenAnswer((_) async => true);
    when(() => characteristic.onValueReceived)
        .thenAnswer((_) => characteristicController.stream);
    when(() => service.uuid).thenReturn(senseBoxServiceUUID);
    when(() => service.characteristics).thenReturn([characteristic]);
    when(() => device.connect()).thenAnswer((_) async => Future.value());
    when(() => device.connectionState)
        .thenAnswer((_) => Stream.value(BluetoothConnectionState.connected));
    when(() => device.discoverServices()).thenAnswer((_) async => [service]);
    final context = MockBuildContext();
    when(() => context.mounted).thenReturn(true);
    await bleBloc.connectToDevice(device, context);
  });

  Stream<List<double>> characteristicStream() {
    return bleBloc
        .getCharacteristicStream(characteristicGuid.str)
        .stream
        .timeout(Duration(milliseconds: 2), onTimeout: (sink) {
      sink.close();
    });
  }

  group('little endian double value characteristic', () {
    test('emits nothing on no input', () async {
      expect(characteristicStream(), neverEmits(anything));
    });

    void testSingleFloat32Once(double d) {
      test('decodes single float32 $d once', () async {
        final bytes = ByteData(4);
        bytes.setFloat32(0, d, Endian.little);
        characteristicController.add(bytes.buffer.asUint8List());
        expect(
            characteristicStream(),
            emitsInOrder([
              [d]
            ]));
      });
    }

    testSingleFloat32Once(0);
    testSingleFloat32Once(1);
    testSingleFloat32Once(-1);
    testSingleFloat32Once(1.5);
    testSingleFloat32Once(-7.750000476837158203125);

    test('decodes single float32 multiple times', () async {
      for (double d in [0, -1.5, 13.25]) {
        final bytes = ByteData(4);
        bytes.setFloat32(0, d, Endian.little);
        characteristicController.add(bytes.buffer.asUint8List());
      }
      expect(
          characteristicStream(),
          emitsInOrder([
            [0],
            [-1.5],
            [13.25]
          ]));
    });

    test('decodes multiple float32 multiple times', () async {
      List<List<double>> dss = [
        [0, -1.5, 13.25],
        [0],
        [4, 5.5, 6, 7]
      ];
      for (final ds in dss) {
        final bytes = ByteData(ds.length * 4);
        for (final (i, d) in ds.indexed) {
          bytes.setFloat32(i * 4, d, Endian.little);
        }
        characteristicController.add(bytes.buffer.asUint8List());
      }
      expect(characteristicStream(), emitsInOrder(dss));
    });

    test('ignores extraneous bytes', () async {
      final bytes = ByteData(7);
      bytes.setFloat32(0, -1.5, Endian.little);
      bytes.setUint8(4, 15);
      bytes.setUint8(5, 115);
      bytes.setUint8(6, 255);
      characteristicController.add(bytes.buffer.asUint8List());
      expect(
          characteristicStream(),
          emitsInOrder([
            [-1.5]
          ]));
    });
  });
}
