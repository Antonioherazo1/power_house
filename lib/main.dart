import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db_helper.dart';
import 'HistoryScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(MyApp());
}

/// Inicializa el servicio en segundo plano (configurado para Android, con mínima configuración para iOS)
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

/// Función mínima para iOS (no se utilizará en este ejemplo Android-only)
bool onIosBackground(ServiceInstance service) {
  return true;
}

/// Esta función se ejecuta en segundo plano en Android.
/// Se conecta al broker MQTT, suscribe al tópico y, por cada mensaje:
///   - Calcula la potencia (W) a partir del consumo (A)
///   - Incrementa el totalizador de energía (kWh) usando un muestreo de 1 segundo
///   - Guarda el totalizador en SharedPreferences
///   - Envía a la UI los valores: consumo, potencia y energía total
/// Además, escucha el comando "reset" enviado desde la UI para reiniciar el totalizador.
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Servicio en Segundo Plano",
      content: "Monitor de energía activo",
    );
  }

  // Declara la variable para llevar la energía total en el servicio.
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

    // Incremento en kWh para 1 segundo de muestreo.
    double incremento = nuevaPotencia / 3600000;
    _serviceEnergyTotal += incremento;
    await prefs.setDouble('energiaTotal', _serviceEnergyTotal);

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

    int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
    EnergyRecord record = EnergyRecord(
      timestamp: currentTimestamp,
      consumption: nuevoConsumo,
      power: nuevaPotencia,
      energyTotal: _serviceEnergyTotal,
    );
    await DatabaseHelper.instance.insertEnergyRecord(record);
  });

  // Actualiza la notificación periódicamente (opcional)
  Timer.periodic(Duration(seconds: 1), (timer) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Servicio en Segundo Plano",
        content: "Monitor de energía activo",
      );
    }
  });
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitor de Energía',
      home: EnergyMonitorScreen(),
    );
  }
}

/// Pantalla principal que muestra:
/// - Consumo en amperios.
/// - Potencia en vatios.
/// - Totalizador de energía (kWh).
/// - Una gráfica en tiempo real (corriente en A).
/// - Un TextField para establecer el valor inicial del totalizador.
class EnergyMonitorScreen extends StatefulWidget {
  @override
  _EnergyMonitorScreenState createState() => _EnergyMonitorScreenState();
}

class _EnergyMonitorScreenState extends State<EnergyMonitorScreen> {
  double energiaTotal = 0.0;
  double consumo = 0.0;
  double potencia = 0.0;
  List<FlSpot> dataPoints = [];
  double xValue = 0;

  @override
  void initState() {
    super.initState();
    FlutterBackgroundService().on("update").listen((event) {
      if (event != null && event["energiaTotal"] != null) {
        setState(() {
          energiaTotal = (event["energiaTotal"] as num).toDouble();
          consumo = (event["consumo"] as num).toDouble();
          potencia = (event["potencia"] as num).toDouble();
          dataPoints.add(FlSpot(xValue, consumo));
          xValue += 1;
          if (dataPoints.length > 30) {
            dataPoints.removeAt(0);
          }
        });
      }
    });
  }

  /// Permite establecer un valor inicial para el totalizador.
  /// Actualiza la pantalla, SharedPreferences y envía el comando al servicio en segundo plano.
  void setEnergiaInicial(double valor) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('energiaTotal', valor);
    setState(() {
      energiaTotal = valor;
      dataPoints = [];
      xValue = 0;
    });
    // Envía el comando de reinicio al servicio utilizando invoke.
    FlutterBackgroundService().invoke("reset", {"reset": valor});
  }

  @override
  Widget build(BuildContext context) {
    final lineChartData = LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: dataPoints,
          isCurved: true,
          color: Colors.blue,
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      ],
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true),
        ),
      ),
      minX: dataPoints.isNotEmpty ? dataPoints.first.x : 0,
      maxX: dataPoints.isNotEmpty ? dataPoints.last.x : 30,
      minY: 0,
      maxY: dataPoints.isNotEmpty
          ? dataPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b) + 1
          : 1,
    );

    return Scaffold(
      // Dentro del Scaffold en EnergyMonitorScreen, por ejemplo:
      appBar: AppBar(
        title: Text("Monitor de Energía (Android)"),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_today),
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => HistoryScreen(viewType: 'day')));
            },
          ),
          IconButton(
            icon: Icon(Icons.access_time),
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => HistoryScreen(viewType: 'hour')));
            },
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "Consumo: ${consumo.toStringAsFixed(2)} A",
              style: TextStyle(fontSize: 20),
            ),
            Text(
              "Potencia: ${potencia.toStringAsFixed(2)} W",
              style: TextStyle(fontSize: 20),
            ),
            Text(
              "Energía Total: ${energiaTotal.toStringAsFixed(6)} kWh",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            TextField(
              decoration: InputDecoration(
                labelText: "Establecer energía inicial (kWh)",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (value) {
                double valor = double.tryParse(value) ?? 0;
                setEnergiaInicial(valor);
              },
            ),
            SizedBox(height: 20),
            Expanded(
              child: LineChart(lineChartData),
            ),
          ],
        ),
      ),
    );
  }
}
