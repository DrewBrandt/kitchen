import '../models/pantry_models.dart';

class GroceryImportLine {
  const GroceryImportLine({
    required this.lineNumber,
    required this.name,
    required this.amount,
    required this.unit,
    required this.location,
    this.foodId,
    this.bestBy,
    this.error,
  });

  final int lineNumber;
  final String name;
  final double amount;
  final String unit;
  final StorageLocation location;
  final String? foodId;
  final DateTime? bestBy;
  final String? error;

  bool get isValid => error == null && foodId != null;
}

class GroceryImportService {
  const GroceryImportService();

  List<GroceryImportLine> parse(
    String text,
    Iterable<FoodDefinition> foods, {
    DateTime? today,
  }) {
    final definitions = foods.toList();
    final lines = text.split(RegExp(r'\r?\n'));
    final result = <GroceryImportLine>[];
    for (var index = 0; index < lines.length; index++) {
      final raw = lines[index].trim();
      if (raw.isEmpty || raw.startsWith('#')) continue;
      final values = _split(raw);
      if (index == 0 &&
          values.isNotEmpty &&
          values.first.toLowerCase() == 'food') {
        continue;
      }
      result.add(
        _parseLine(index + 1, values, definitions, today ?? DateTime.now()),
      );
    }
    return result;
  }

  GroceryImportLine _parseLine(
    int lineNumber,
    List<String> values,
    List<FoodDefinition> foods,
    DateTime today,
  ) {
    if (values.length < 3) {
      return GroceryImportLine(
        lineNumber: lineNumber,
        name: values.isEmpty ? '' : values.first,
        amount: 0,
        unit: '',
        location: StorageLocation.pantry,
        error: 'Expected food, amount, and unit',
      );
    }
    final name = values[0].trim();
    final amount = double.tryParse(values[1].trim());
    final unit = values[2].trim().toLowerCase();
    final food = _matchFood(name, foods);
    final location = values.length > 3 && values[3].trim().isNotEmpty
        ? _parseLocation(values[3])
        : food?.defaultLocation ?? StorageLocation.pantry;
    final bestByText = values.length > 4 ? values[4].trim() : '';
    final bestBy = bestByText.isEmpty ? null : _parseDate(bestByText, today);
    String? error;
    if (amount == null || amount <= 0) {
      error = 'Amount must be a positive number';
    } else if (food == null) {
      error = 'Food is not defined yet';
    } else {
      try {
        food.conversionFor(unit);
      } on ArgumentError {
        error = 'Unit "$unit" is not configured for ${food.name}';
      }
    }
    if (location == null) {
      error = 'Unknown location';
    }
    if (bestByText.isNotEmpty && bestBy == null) {
      error = 'Use YYYY-MM-DD or +days for best by';
    }
    return GroceryImportLine(
      lineNumber: lineNumber,
      name: name,
      amount: amount ?? 0,
      unit: unit,
      location: location ?? StorageLocation.pantry,
      foodId: food?.id,
      bestBy: bestBy,
      error: error,
    );
  }

  FoodDefinition? _matchFood(String input, List<FoodDefinition> foods) {
    final wanted = _normalize(input);
    for (final food in foods) {
      final name = _normalize(food.name);
      if (name == wanted || _singular(name) == _singular(wanted)) return food;
    }
    return null;
  }

  List<String> _split(String line) {
    final separator = line.contains('\t')
        ? '\t'
        : line.contains('|')
        ? '|'
        : ',';
    return line.split(separator).map((item) => item.trim()).toList();
  }

  StorageLocation? _parseLocation(String value) {
    final normalized = value.trim().toLowerCase();
    for (final location in StorageLocation.values) {
      if (location.name == normalized) return location;
    }
    return null;
  }

  DateTime? _parseDate(String value, DateTime today) {
    if (value.startsWith('+')) {
      final days = int.tryParse(value.substring(1));
      return days == null
          ? null
          : DateTime(
              today.year,
              today.month,
              today.day,
            ).add(Duration(days: days));
    }
    return DateTime.tryParse(value);
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  String _singular(String value) =>
      value.endsWith('s') ? value.substring(0, value.length - 1) : value;
}
