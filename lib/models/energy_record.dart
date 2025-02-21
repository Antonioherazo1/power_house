// lib/models/energy_record.dart
class EnergyRecord {
  final int? id;
  final int timestamp; // Unix timestamp en milisegundos.
  final double consumption;
  final double power;
  final double energyTotal;

  EnergyRecord({
    this.id,
    required this.timestamp,
    required this.consumption,
    required this.power,
    required this.energyTotal,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'consumption': consumption,
      'power': power,
      'energyTotal': energyTotal,
    };
  }

  factory EnergyRecord.fromMap(Map<String, dynamic> map) {
    return EnergyRecord(
      id: map['id'],
      timestamp: map['timestamp'],
      consumption: map['consumption'],
      power: map['power'],
      energyTotal: map['energyTotal'],
    );
  }
}
