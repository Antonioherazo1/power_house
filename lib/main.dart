import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitor de Energía',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: EnergyMonitor(),
    );
  }
}

class EnergyMonitor extends StatefulWidget {
  const EnergyMonitor({super.key});

  @override
  _EnergyMonitorState createState() => _EnergyMonitorState();
}

class _EnergyMonitorState extends State<EnergyMonitor> {
  late MqttServerClient client;
  String status = 'Desconectado';
  String consumo = '0 W';
  List<FlSpot> dataPoints = [];
  double xValue = 0;
  Timer? reconnectTimer;

  @override
  void initState() {
    super.initState();
    connectToBroker();
  }

  Future<void> connectToBroker() async {
    client = MqttServerClient('thinc.site', 'flutter_client');
    client.port = 1883;
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = onSubscribed;
    client.logging(on: false);

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client')
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    client.connectionMessage = connMessage;

    try {
      await client.connect();
    } catch (e) {
      print('Error al conectar: $e');
      scheduleReconnect();
    }
  }

  void scheduleReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = Timer(Duration(seconds: 10), connectToBroker);
  }

  void onDisconnected() {
    setState(() => status = 'Desconectado');
    print('Desconectado del broker');
    scheduleReconnect();
  }

  void onConnected() {
    setState(() => status = 'Conectado');
    print('Conectado al broker');
    client.subscribe('consumo/amps_Total', MqttQos.atMostOnce);
  }

  void onSubscribed(String topic) {
    print('Suscrito a $topic');
    client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage message = c[0].payload as MqttPublishMessage;
      final String payload =
          MqttPublishPayload.bytesToStringAsString(message.payload.message);

      double consumoActual = double.tryParse(payload) ?? 0;
      setState(() {
        consumo = '$consumoActual A';
        dataPoints.add(FlSpot(xValue, consumoActual));
        xValue += 1;
        if (dataPoints.length > 30) {
          dataPoints.removeAt(0);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Monitor de Energía')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Estado: $status',
                style: TextStyle(
                    fontSize: 20,
                    color: status == 'Conectado' ? Colors.green : Colors.red)),
            SizedBox(height: 20),
            Text('Consumo: $consumo',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Expanded(
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: dataPoints,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                    ),
                  ],
                  borderData: FlBorderData(show: true),
                  minX: dataPoints.isNotEmpty ? dataPoints.first.x : 0,
                  maxX: dataPoints.isNotEmpty ? dataPoints.last.x : 30,
                  minY: 0,
                  maxY: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    client.disconnect();
    super.dispose();
  }
}
