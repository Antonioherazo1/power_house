// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/db_helper.dart';
import '../models/energy_record.dart';
import 'dart:math';

class HistoryScreen extends StatefulWidget {
  final String viewType; // 'day' o 'hour'
  const HistoryScreen({Key? key, required this.viewType}) : super(key: key);

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime selectedDate = DateTime.now();
  int selectedHour = DateTime.now().hour;
  List<EnergyRecord> _records = [];
  List<FlSpot> _resampledPoints = [];
  List<DateTime> _xTimestamps = [];
  double _scale = 1.0; // Factor de zoom (1.0 = base)

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  // Obtiene los registros (para el día o para la hora) y luego los remuestrea
  Future<void> fetchData() async {
    List<EnergyRecord> rec;
    if (widget.viewType == 'day') {
      rec = await DatabaseHelper.instance.getRecordsByDay(selectedDate);
    } else {
      rec = await DatabaseHelper.instance
          .getRecordsByHour(selectedDate, selectedHour);
    }
    setState(() {
      _records = rec;
    });
    _resampleData();
  }

  // Remuestrea los datos para obtener 20 puntos en función de la resolución actual.
  // La resolución se calcula a partir del período total y el factor de zoom.
  void _resampleData() {
    if (_records.isEmpty) return;

    // Definir el período total en segundos según la vista
    int windowSeconds = widget.viewType == 'day' ? 86400 : 3600;
    // Resolución base: el período dividido entre 20 puntos
    double baseResolution = windowSeconds / 20.0;
    // Resolución actual en segundos (zoom in reduce la resolución, zoom out la aumenta)
    double resolutionSeconds = baseResolution / _scale;
    resolutionSeconds = max(1, resolutionSeconds); // no menor a 1 segundo

    // Definir el tiempo inicial de la gráfica.
    // Para 'day' usamos la medianoche; para 'hour', el inicio de la hora seleccionada.
    DateTime startTime = widget.viewType == 'day'
        ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day)
        : DateTime(selectedDate.year, selectedDate.month, selectedDate.day,
            selectedHour);

    _resampledPoints.clear();
    _xTimestamps.clear();
    // Generar 20 puntos.
    for (int i = 0; i < 20; i++) {
      int targetMillis = startTime.millisecondsSinceEpoch +
          (resolutionSeconds * i * 1000).toInt();
      // Buscar el registro cuya marca de tiempo sea la más cercana al tiempo objetivo.
      EnergyRecord chosen = _records.first;
      for (var rec in _records) {
        if ((rec.timestamp - targetMillis).abs() <
            (chosen.timestamp - targetMillis).abs()) {
          chosen = rec;
        }
      }
      _resampledPoints.add(FlSpot(i.toDouble(), chosen.consumption));
      _xTimestamps.add(DateTime.fromMillisecondsSinceEpoch(chosen.timestamp));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Fijar un ancho fijo para 20 puntos (por ejemplo, 40 píxeles por punto)
    double chartWidth = 20 * 40.0;
    // Calcular el valor máximo del eje Y redondeado al siguiente múltiplo de 0.2
    double maxY = 1;
    if (_resampledPoints.isNotEmpty) {
      double m =
          _resampledPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b);
      maxY = (m / 0.2).ceil() * 0.2;
    }

    final lineChartData = LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: _resampledPoints,
          isCurved: true,
          color: Colors.green,
          barWidth: 3,
          belowBarData: BarAreaData(show: false),
        ),
      ],
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 0.2,
            getTitlesWidget: (value, meta) {
              return Text(value.toStringAsFixed(1));
            },
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 0.2,
            getTitlesWidget: (value, meta) {
              return Text(value.toStringAsFixed(1));
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              int index = value.toInt();
              if (index < 0 || index >= _xTimestamps.length) return Container();
              DateTime dt = _xTimestamps[index];
              return RotatedBox(
                quarterTurns:
                    3, // Rota 270° (equivalente a -90°) para leer de abajo a arriba
                child: Text(
                  "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}",
                  style: TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ),
      minX: 0,
      maxX: 20,
      minY: 0,
      maxY: maxY,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("Historial - ${widget.viewType == 'day' ? 'Día' : 'Hora'}"),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime.now().subtract(Duration(days: 30)),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  selectedDate = picked;
                });
                fetchData();
              }
            },
            child: Text(
                "Seleccionar fecha: ${selectedDate.toLocal().toString().split(' ')[0]}"),
          ),
          if (widget.viewType == 'hour')
            DropdownButton<int>(
              value: selectedHour,
              items: List.generate(24, (index) => index)
                  .map((hour) => DropdownMenuItem(
                        value: hour,
                        child: Text("$hour:00"),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  selectedHour = val!;
                });
                fetchData();
              },
            ),
          Expanded(
            child: InteractiveViewer(
              panEnabled: true,
              scaleEnabled: true,
              minScale: 0.5,
              maxScale: 5.0,
              constrained: false,
              onInteractionUpdate: (details) {
                setState(() {
                  _scale = details.scale;
                  _resampleData();
                });
              },
              child: Container(
                width: chartWidth,
                height: 300,
                child: LineChart(lineChartData),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
