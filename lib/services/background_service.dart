// lib/services/background_service.dart
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/db_helper.dart';
import '../models/energy_record.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  service.startService();
}

bool onIosBackground(ServiceInstance service) {
  return true;
}

void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Servicio en Segundo Plano",
      content: "Monitor de energía activo",
    );
  }

  double _serviceEnergyTotal = 0.0;
  SharedPreferences prefs = await SharedPreferences.getInstance();
  _serviceEnergyTotal = prefs.getDouble('energiaTotal') ?? 0.0;

  // Escucha el comando "reset" enviado desde la UI.
  service.on("reset").listen((data) async {
    if (data != null && data.containsKey("reset")) {
      double resetValue = (data["reset"] as num).toDouble();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('energiaTotal', resetValue);
      _serviceEnergyTotal = resetValue;
    }
  });

  double voltaje = 220.0;

  // Configura el cliente MQTT.
  MqttServerClient client =
      MqttServerClient('thinc.site', 'flutter_background_client');
  client.port = 1883;
  client.keepAlivePeriod = 20;
  client.logging(on: false);

  final connMessage = MqttConnectMessage()
      .withClientIdentifier('flutter_background_client')
      .startClean()
      .withWillQos(MqttQos.atMostOnce);
  client.connectionMessage = connMessage;

  try {
    await client.connect();
  } catch (e) {
    print('Error en conexión MQTT: $e');
    client.disconnect();
  }

  // Suscríbete al tópico de consumo (en amperios)
  client.subscribe('consumo/amps_Total', MqttQos.atMostOnce);

  // Escucha las actualizaciones del MQTT.
  client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) async {
    final MqttPublishMessage message = c[0].payload as MqttPublishMessage;
    final String payload =
        MqttPublishPayload.bytesToStringAsString(message.payload.message);

    double nuevoConsumo = double.tryParse(payload) ?? 0; // en A
    double nuevaPotencia = nuevoConsumo * voltaje; // en W
    double incremento = nuevaPotencia / 3600000; // kWh para 1 segundo

    _serviceEnergyTotal += incremento;
    await prefs.setDouble('energiaTotal', _serviceEnergyTotal);

    // Inserta el registro en la base de datos.
    int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    EnergyRecord record = EnergyRecord(
      timestamp: currentTimestamp,
      consumption: nuevoConsumo,
      power: nuevaPotencia,
      energyTotal: _serviceEnergyTotal,
    );
    await DatabaseHelper.instance.insertEnergyRecord(record);

    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Servicio en Segundo Plano",
        content:
            "Consumo: ${nuevoConsumo.toStringAsFixed(2)} A, Potencia: ${nuevaPotencia.toStringAsFixed(2)} W, Energía: ${_serviceEnergyTotal.toStringAsFixed(6)} kWh",
      );
    }

    // Envía la actualización a la UI.
    service.invoke("update", {
      "energiaTotal": _serviceEnergyTotal,
      "consumo": nuevoConsumo,
      "potencia": nuevaPotencia,
    });
  });

  Timer.periodic(Duration(seconds: 1), (timer) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Servicio en Segundo Plano",
        content: "Monitor de energía activo",
      );
    }
  });
}
