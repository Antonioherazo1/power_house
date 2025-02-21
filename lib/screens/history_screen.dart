// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/db_helper.dart';
import '../models/energy_record.dart';

class HistoryScreen extends StatefulWidget {
  final String viewType; // 'day' o 'hour'
  const HistoryScreen({Key? key, required this.viewType}) : super(key: key);

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime selectedDate = DateTime.now();
  int selectedHour = DateTime.now().hour;
  List<EnergyRecord> records = [];
  List<FlSpot> chartData = [];

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    List<EnergyRecord> rec;
    if (widget.viewType == 'day') {
      rec = await DatabaseHelper.instance.getRecordsByDay(selectedDate);
    } else {
      rec = await DatabaseHelper.instance
          .getRecordsByHour(selectedDate, selectedHour);
    }
    List<FlSpot> spots = [];
    for (int i = 0; i < rec.length; i++) {
      spots.add(FlSpot(i.toDouble(), rec[i].consumption));
    }
    setState(() {
      records = rec;
      chartData = spots;
    });
  }

  @override
  Widget build(BuildContext context) {
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
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: chartData,
                      isCurved: true,
                      color: Colors.green,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
