import '../models/pantry_models.dart';
import 'food_match_service.dart';

class GroceryImportLine {
  const GroceryImportLine({
    required this.lineNumber,
    required this.name,
    required this.amount,
    required this.unit,
    required this.location,
    this.foodId,
    this.productId,
    this.suggestions = const [],
    this.matchCandidates = const [],
    this.createProduct = false,
    this.bestBy,
    this.error,
  });

  final int lineNumber;
  final String name;
  final double amount;
  final String unit;
  final StorageLocation location;
  final String? foodId;
  final String? productId;
  final List<String> suggestions;
  final List<FoodMatchCandidate> matchCandidates;
  final bool createProduct;
  final DateTime? bestBy;
  final String? error;

  bool get isValid => error == null && foodId != null;

  GroceryImportLine withMatch(FoodMatchCandidate candidate) {
    String? selectedError;
    if (candidate.product?.conversionFor(unit) == null) {
      try {
        candidate.food.conversionFor(unit);
      } on ArgumentError {
        selectedError =
            'Unit "$unit" is not configured for ${candidate.food.name}';
      }
    }
    return GroceryImportLine(
      lineNumber: lineNumber,
      name: name,
      amount: amount,
      unit: unit,
      location: location,
      foodId: candidate.food.id,
      productId: candidate.product?.id,
      bestBy: bestBy,
      error: selectedError,
      suggestions: suggestions,
      matchCandidates: matchCandidates,
      createProduct: candidate.product == null && !candidate.exact,
    );
  }
}

class GroceryImportService {
  const GroceryImportService({this.matcher = const FoodMatchService()});

  final FoodMatchService matcher;

  List<GroceryImportLine> parse(
    String text,
    Iterable<FoodDefinition> foods, {
    Iterable<ProductDefinition> products = const [],
    DateTime? today,
  }) {
    final definitions = foods.toList();
    final productDefinitions = products.toList();
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
        _parseLine(
          index + 1,
          values,
          definitions,
          productDefinitions,
          today ?? DateTime.now(),
        ),
      );
    }
    return result;
  }

  GroceryImportLine _parseLine(
    int lineNumber,
    List<String> values,
    List<FoodDefinition> foods,
    List<ProductDefinition> products,
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
    final match = matcher.match(name, foods, products);
    final selected =
        match.best?.exact == true ||
            (match.canApplyAutomatically && match.best?.product != null)
        ? match.best
        : null;
    final food = selected?.food;
    final product = selected?.product;
    final location = values.length > 3 && values[3].trim().isNotEmpty
        ? _parseLocation(values[3])
        : food?.defaultLocation ?? StorageLocation.pantry;
    final bestByText = values.length > 4 ? values[4].trim() : '';
    final bestBy = bestByText.isEmpty ? null : _parseDate(bestByText, today);
    String? error;
    if (amount == null || amount <= 0) {
      error = 'Amount must be a positive number';
    } else if (food == null) {
      final suggestion = match.best;
      error = suggestion == null
          ? 'Food is not defined yet'
          : 'Review suggested match: ${suggestion.food.name}';
    } else {
      final productConversion = product?.conversionFor(unit);
      if (productConversion == null) {
        try {
          food.conversionFor(unit);
        } on ArgumentError {
          error = 'Unit "$unit" is not configured for ${food.name}';
        }
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
      productId: product?.id,
      suggestions: match.candidates
          .map((candidate) => candidate.product?.name ?? candidate.food.name)
          .toList(),
      matchCandidates: match.candidates,
      bestBy: bestBy,
      error: error,
    );
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
}
