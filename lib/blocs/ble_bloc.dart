import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:sensebox_bike/blocs/settings_bloc.dart';
import 'package:sensebox_bike/secrets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart'; // Assuming you're using Provider for state management
import 'package:sensebox_bike/blocs/recording_bloc.dart';
import 'package:sensebox_bike/services/custom_exceptions.dart';
import 'package:vibration/vibration.dart'; // Import the RecordingBloc

class BleBloc with ChangeNotifier {
  final SettingsBloc settingsBloc;
  final FlutterBluePlusMockable flutterBluePlus;

  // Add a ValueNotifier to track Bluetooth status
  final ValueNotifier<bool> isBluetoothEnabledNotifier = ValueNotifier(false);

  final List<BluetoothDevice> devicesList = [];
  final StreamController<List<BluetoothDevice>> _devicesListController =
      StreamController.broadcast();
  Stream<List<BluetoothDevice>> get devicesListStream =>
      _devicesListController.stream;

  BluetoothDevice? selectedDevice;
  bool _isConnected = false; // Track the connection status
  bool _userInitiatedDisconnect =
      false; // Track if disconnect was user-initiated
  final Map<String, StreamController<Uint8List>> _characteristicStreams = {};

  final Map<String, StreamController<List<String>>>
      _characteristicStringStreams = {};

  // create a value notifier that stores the available characteristics
  final ValueNotifier<List<BluetoothCharacteristic>> availableCharacteristics =
      ValueNotifier([]);

  // ValueNotifier to notify about the selected device's connection state
  final ValueNotifier<BluetoothDevice?> selectedDeviceNotifier =
      ValueNotifier(null);

  bool get isConnected => _isConnected; // Expose the connection status

  final ValueNotifier<bool> isConnectingNotifier = ValueNotifier(false);

  final ValueNotifier<bool> isReconnectingNotifier = ValueNotifier(false);

  BleBloc(this.settingsBloc, this.flutterBluePlus) {
    flutterBluePlus.setLogLevel(LogLevel.error);

    // Listen for Bluetooth adapter state changes
    flutterBluePlus.adapterState.listen((state) {
      updateBluetoothStatus(state == BluetoothAdapterState.on);
    });

    // Initialize the Bluetooth status
    _initializeBluetoothStatus();
  }

  Future<void> _initializeBluetoothStatus() async {
    // Get the current adapter state
    BluetoothAdapterState currentState =
        await flutterBluePlus.adapterState.first;
    updateBluetoothStatus(currentState == BluetoothAdapterState.on);
  }

  // Update Bluetooth status when it changes
  void updateBluetoothStatus(bool isEnabled) {
    isBluetoothEnabledNotifier.value = isEnabled;
    notifyListeners();
  }

  Future<void> startScanning() async {
    disconnectDevice(); // Disconnect if there's a current connection

    try {
      await flutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      throw ScanPermissionDenied();
    }

    flutterBluePlus.scanResults.listen((results) {
      devicesList.clear();
      for (ScanResult result in results) {
        if (result.device.platformName.startsWith("senseBox")) {
          devicesList.add(result.device);
        }
      }
      _devicesListController.add(devicesList);
      notifyListeners();
    });
  }

  void disconnectDevice() {
    _userInitiatedDisconnect = true; // Mark this as a user-initiated disconnect
    selectedDevice?.disconnect();
    _isConnected = false; // Mark the device as disconnected
    selectedDevice = null;
    selectedDeviceNotifier.value = null; // Notify disconnection
    availableCharacteristics.value = [];
    notifyListeners();
  }

  Future<void> connectToId(String id, BuildContext context) async {
    await flutterBluePlus.startScan(withNames: [id]);
    flutterBluePlus.scanResults.listen((results) async {
      for (ScanResult result in results) {
        if (result.device.advName.toString() == id) {
          await connectToDevice(result.device, context);
          break;
        }
      }
    });
  }

  Future<void> connectToDevice(
      BluetoothDevice device, BuildContext context) async {
    try {
      isConnectingNotifier.value = true; // Notify that we're connecting
      notifyListeners();

      await flutterBluePlus.stopScan();
      await device.connect();
      _isConnected = true; // Mark as connected
      _userInitiatedDisconnect =
          false; // Reset this since it's a new connection

      await _discoverAndListenToCharacteristics(device);

      selectedDevice = device;
      selectedDeviceNotifier.value = selectedDevice; // Notify connection
      notifyListeners();

      // Handle reconnection if the connection is lost
      if (context.mounted) {
        _handleDeviceReconnection(device, context);
      } else {
        throw Exception('Context is not mounted, cannot handle reconnection');
      }
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      // Handle connection error
    } finally {
      isConnectingNotifier.value = false; // Notify that we're done connecting
    }
    notifyListeners();
  }

  Future<void> _discoverAndListenToCharacteristics(
      BluetoothDevice device) async {
    _characteristicStreams.clear();
    availableCharacteristics.value = [];

    int maxAttempts = 5;

    int attempts = 0;
    while (attempts < maxAttempts) {
      try {
        List<BluetoothService> services = await device.discoverServices();

        // find senseBox service
        var senseBoxService = services.firstWhere(
            (service) => service.uuid == senseBoxServiceUUID,
            orElse: () => throw Exception('Service not found'));

        availableCharacteristics.value = senseBoxService.characteristics;

        notifyListeners();

        for (var characteristic in senseBoxService.characteristics) {
          await _listenToCharacteristic(characteristic);
        }

        // var deviceInfoService = services.firstWhere(
        //     (service) => service.uuid == deviceInfoServiceUUID,
        //     orElse: () => throw Exception('Device Info Service not found'));

        // for (var characteristic in deviceInfoService.characteristics) {
        //   await _listenToDeviceInfoCharacteristic(characteristic);
        // }

        break; // Exit the loop if successful
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          // Handle the error after max attempts
          print('Failed to discover services after $attempts attempts: $e');
          break;
        }
        print('Error discovering services, attempt $attempts: $e');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  void _handleDeviceReconnection(BluetoothDevice device, BuildContext context) {
    bool hasVibrated = false; // Flag to track vibration
    int reconnectionAttempts = 0; // Track the number of reconnection attempts
    const int maxReconnectionAttempts = 5;

    device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.disconnected &&
          !_userInitiatedDisconnect) {
        _isConnected = false; // Mark as disconnected

        // Set isReconnecting to true and notify listeners
        isReconnectingNotifier.value = true;

        // Vibrate only once after the disconnection
        if (!hasVibrated && settingsBloc.vibrateOnDisconnect) {
          Vibration.vibrate();
          hasVibrated = true; // Set the flag to prevent repeated vibration
        }

        // Attempt to reconnect the device (up to maxReconnectionAttempts)
        while (
            reconnectionAttempts < maxReconnectionAttempts && !_isConnected) {
          try {
            reconnectionAttempts++;
            print('Reconnection attempt $reconnectionAttempts');

            await device.connect(timeout: const Duration(seconds: 10));

            // Check if the device is successfully connected
            if (await device.connectionState.first ==
                BluetoothConnectionState.connected) {
              _isConnected = true; // Mark as connected
              hasVibrated = false; // Reset the flag on successful reconnection
              reconnectionAttempts =
                  0; // Reset attempts on successful reconnection
              await _discoverAndListenToCharacteristics(device);
              break; // Exit the loop if reconnected
            }
          } catch (e) {
            // If reconnection fails, log the error and continue
            print('Reconnection attempt $reconnectionAttempts failed: $e');
          }
          // Add a delay between reconnection attempts
          await Future.delayed(const Duration(seconds: 5));
        }

        // Once done, set isReconnecting to false and notify listeners
        isReconnectingNotifier.value = false;

        if (!_isConnected && reconnectionAttempts >= maxReconnectionAttempts) {
          debugPrint(
              'Failed to reconnect after $maxReconnectionAttempts attempts');
          selectedDeviceNotifier.value = null; // Notify disconnection
          notifyListeners();

          if (!context.mounted) return;
          // Notify RecordingBloc to stop recording if Bluetooth disconnects
          try {
            RecordingBloc? recordingBloc =
                Provider.of<RecordingBloc>(context, listen: false);
            if (recordingBloc.isRecording) {
              recordingBloc.stopRecording();
            }
          } catch (e) {
            debugPrint('RecordingBloc not found in the widget tree: $e');
          }
        }
      }
    });
  }

  Future<void> _listenToCharacteristic(
      BluetoothCharacteristic characteristic) async {
    final controller = StreamController<Uint8List>();
    // REFACTOR can we just store the characteristicstream mapped to
    // Uint8List.fromList? but what about closing the controllers on dispose?++++++++
    _characteristicStreams[characteristic.uuid.toString()] = controller;

    await characteristic.setNotifyValue(true);
    characteristic.onValueReceived.listen((value) {
      controller.add(Uint8List.fromList(value));
    });
  }

  Future<void> _listenToDeviceInfoCharacteristic(
      BluetoothCharacteristic characteristic) async {
    final controller = StreamController<List<String>>();
    _characteristicStringStreams[characteristic.uuid.toString()] = controller;

    await characteristic.setNotifyValue(true);
    characteristic.onValueReceived.listen((value) {
      print('Received value: $value');
      print('Decoded value: ${utf8.decode(value)}');
      List<String> parsedData = [utf8.decode(value)];
      controller.add(parsedData);
    });
  }

  Stream<Uint8List> getCharacteristicStream(String characteristicUuid) {
    if (!_characteristicStreams.containsKey(characteristicUuid)) {
      throw Exception('Characteristic stream not found');
    }
    return _characteristicStreams[characteristicUuid]!.stream;
  }

  @override
  void dispose() {
    _devicesListController.close();
    for (var controller in _characteristicStreams.values) {
      controller.close();
    }
    selectedDeviceNotifier.dispose();
    isBluetoothEnabledNotifier.dispose();
    super.dispose();
  }
}

/// Wrapper for FlutterBluePlus in order to easily mock it
/// Wraps all static calls for testing purposes
class FlutterBluePlusMockable {
  Future<void> startScan({
    List<Guid> withServices = const [],
    List<String> withRemoteIds = const [],
    List<String> withNames = const [],
    List<String> withKeywords = const [],
    List<MsdFilter> withMsd = const [],
    List<ServiceDataFilter> withServiceData = const [],
    Duration? timeout,
    Duration? removeIfGone,
    bool continuousUpdates = false,
    int continuousDivisor = 1,
    bool oneByOne = false,
    bool androidLegacy = false,
    AndroidScanMode androidScanMode = AndroidScanMode.lowLatency,
    bool androidUsesFineLocation = false,
    List<Guid> webOptionalServices = const [],
  }) {
    return FlutterBluePlus.startScan(
        withServices: withServices,
        withRemoteIds: withRemoteIds,
        withNames: withNames,
        withKeywords: withKeywords,
        withMsd: withMsd,
        withServiceData: withServiceData,
        timeout: timeout,
        removeIfGone: removeIfGone,
        continuousUpdates: continuousUpdates,
        continuousDivisor: continuousDivisor,
        oneByOne: oneByOne,
        androidLegacy: androidLegacy,
        androidScanMode: androidScanMode,
        androidUsesFineLocation: androidUsesFineLocation,
        webOptionalServices: webOptionalServices);
  }

  Stream<BluetoothAdapterState> get adapterState {
    return FlutterBluePlus.adapterState;
  }

  Stream<List<ScanResult>> get scanResults {
    return FlutterBluePlus.scanResults;
  }

  bool get isScanningNow {
    return FlutterBluePlus.isScanningNow;
  }

  Stream<bool> get isScanning {
    return FlutterBluePlus.isScanning;
  }

  Future<void> stopScan() {
    return FlutterBluePlus.stopScan();
  }

  Future<void> setLogLevel(LogLevel level, {color = true}) {
    return FlutterBluePlus.setLogLevel(level, color: color);
  }

  LogLevel get logLevel {
    return FlutterBluePlus.logLevel;
  }

  Future<bool> get isSupported {
    return FlutterBluePlus.isSupported;
  }

  Future<String> get adapterName {
    return FlutterBluePlus.adapterName;
  }

  Future<void> turnOn({int timeout = 60}) {
    return FlutterBluePlus.turnOn(timeout: timeout);
  }

  List<BluetoothDevice> get connectedDevices {
    return FlutterBluePlus.connectedDevices;
  }

  Future<List<BluetoothDevice>> systemDevices(List<Guid> withServices) {
    return FlutterBluePlus.systemDevices(withServices);
  }

  Future<PhySupport> getPhySupport() {
    return FlutterBluePlus.getPhySupport();
  }

  Future<List<BluetoothDevice>> get bondedDevices {
    return FlutterBluePlus.bondedDevices;
  }
}
