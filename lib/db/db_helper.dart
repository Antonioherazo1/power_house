// lib/db/db_helper.dart
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/energy_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'energy_data.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE energy_data(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER,
        consumption REAL,
        power REAL,
        energyTotal REAL
      )
    ''');
  }

  Future<int> insertEnergyRecord(EnergyRecord record) async {
    Database db = await instance.database;
    return await db.insert('energy_data', record.toMap());
  }

  Future<List<EnergyRecord>> getRecordsByDay(DateTime day) async {
    Database db = await instance.database;
    int start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    int end = DateTime(day.year, day.month, day.day, 23, 59, 59)
        .millisecondsSinceEpoch;
    final records = await db.query('energy_data',
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start, end],
        orderBy: 'timestamp ASC');
    return records.map((e) => EnergyRecord.fromMap(e)).toList();
  }

  Future<List<EnergyRecord>> getRecordsByHour(DateTime day, int hour) async {
    Database db = await instance.database;
    int start =
        DateTime(day.year, day.month, day.day, hour).millisecondsSinceEpoch;
    int end = DateTime(day.year, day.month, day.day, hour, 59, 59)
        .millisecondsSinceEpoch;
    final records = await db.query('energy_data',
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start, end],
        orderBy: 'timestamp ASC');
    return records.map((e) => EnergyRecord.fromMap(e)).toList();
  }
}
