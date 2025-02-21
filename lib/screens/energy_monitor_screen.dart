// lib/screens/energy_monitor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_screen.dart';

class EnergyMonitorScreen extends StatefulWidget {
  const EnergyMonitorScreen({Key? key}) : super(key: key);

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

  /// Reinicia el totalizador.
  void setEnergiaInicial(double valor) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('energiaTotal', valor);
    setState(() {
      energiaTotal = valor;
      dataPoints = [];
      xValue = 0;
    });
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
      appBar: AppBar(
        title: Text("Monitor de Energía (Android)"),
        actions: [
          IconButton(
            icon: Icon(Icons.calendar_today),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HistoryScreen(viewType: 'day')),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.access_time),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HistoryScreen(viewType: 'hour')),
              );
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
