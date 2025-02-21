import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      // Para iOS se deshabilita el autoStart (aunque no se usará)
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  service.startService();
}

// Función para iOS en segundo plano (no se usará en este ejemplo Android-only)
bool onIosBackground(ServiceInstance service) {
  return true;
}

void onStart(ServiceInstance service) async {
  // Configura la notificación en primer plano en Android
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Servicio en Segundo Plano",
      content: "El monitor de energía sigue activo",
    );
  }

  // Configura el cliente MQTT
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

  // Suscríbete al tópico deseado
  client.subscribe('consumo/amps_Total', MqttQos.atMostOnce);

  // Recupera el totalizador almacenado
  SharedPreferences prefs = await SharedPreferences.getInstance();
  double energiaTotal = prefs.getDouble('energiaTotal') ?? 0.0;
  double voltaje = 220.0;

  // Escucha las actualizaciones del MQTT
  client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) async {
    final MqttPublishMessage message = c[0].payload as MqttPublishMessage;
    final String payload =
        MqttPublishPayload.bytesToStringAsString(message.payload.message);
    double nuevoConsumo = double.tryParse(payload) ?? 0;
    double nuevaPotencia = nuevoConsumo * voltaje;
    // Calcula el incremento en kWh para un intervalo de 1 segundo
    double incremento = nuevaPotencia / 3600000;
    energiaTotal += incremento;
    await prefs.setDouble('energiaTotal', energiaTotal);
    // Actualiza la notificación
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Servicio en Segundo Plano",
        content: "Energía total: ${energiaTotal.toStringAsFixed(6)} kWh",
      );
    }
    // Envía la actualización a la interfaz
    service.invoke("update", {"energiaTotal": energiaTotal});
  });

  // Actualiza la notificación periódicamente (opcional)
  Timer.periodic(Duration(seconds: 1), (timer) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Servicio en Segundo Plano",
        content: "Energía total: ${energiaTotal.toStringAsFixed(6)} kWh",
      );
    }
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitor de Energía en Segundo Plano',
      home: EnergyMonitorScreen(),
    );
  }
}

class EnergyMonitorScreen extends StatefulWidget {
  @override
  _EnergyMonitorScreenState createState() => _EnergyMonitorScreenState();
}

class _EnergyMonitorScreenState extends State<EnergyMonitorScreen> {
  double energiaTotal = 0.0;

  @override
  void initState() {
    super.initState();
    // Escucha las actualizaciones del servicio en segundo plano
    FlutterBackgroundService().on("update").listen((event) {
      if (event!["energiaTotal"] != null) {
        setState(() {
          energiaTotal = event["energiaTotal"];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Monitor de Energía (Android)"),
      ),
      body: Center(
        child: Text(
          "Energía Total: ${energiaTotal.toStringAsFixed(6)} kWh",
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
