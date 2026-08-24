import '../models/pantry_models.dart';

class FoodMatchCandidate {
  const FoodMatchCandidate({
    required this.food,
    required this.score,
    required this.matchedName,
    this.product,
    this.exact = false,
  });

  final FoodDefinition food;
  final ProductDefinition? product;
  final double score;
  final String matchedName;
  final bool exact;
}

class FoodMatchResult {
  const FoodMatchResult({required this.candidates});

  final List<FoodMatchCandidate> candidates;

  FoodMatchCandidate? get best => candidates.isEmpty ? null : candidates.first;

  bool get canApplyAutomatically {
    final first = best;
    if (first == null) return false;
    if (first.exact) return true;
    if (first.score < 0.92) return false;
    final competing = candidates
        .where((candidate) => candidate.food.id != first.food.id)
        .firstOrNull;
    return competing == null || first.score - competing.score >= 0.08;
  }
}

/// Resolves store-specific product text to canonical recipe ingredients.
///
/// Exact IDs, barcodes, names, and reviewed aliases are authoritative. Token
/// similarity is deliberately exposed as a ranked suggestion and is only safe
/// to apply automatically for a strong, unambiguous multi-word containment
/// match.
class FoodMatchService {
  const FoodMatchService();

  FoodMatchResult match(
    String input,
    Iterable<FoodDefinition> foods,
    Iterable<ProductDefinition> products,
  ) {
    final query = input.trim();
    if (query.isEmpty) return const FoodMatchResult(candidates: []);
    final byFood = {for (final food in foods) food.id: food};
    final candidates = <FoodMatchCandidate>[];

    void consider(
      FoodDefinition food,
      String candidateName, {
      ProductDefinition? product,
      bool barcode = false,
    }) {
      final exact = barcode || _normalize(candidateName) == _normalize(query);
      final score = exact ? 1.0 : _similarity(query, candidateName);
      if (score < 0.45) return;
      candidates.add(
        FoodMatchCandidate(
          food: food,
          product: product,
          score: score,
          matchedName: candidateName,
          exact: exact,
        ),
      );
    }

    for (final food in byFood.values) {
      consider(food, food.name);
      for (final alias in food.aliases) {
        consider(food, alias);
      }
    }
    for (final product in products) {
      final food = byFood[product.foodId];
      if (food == null) continue;
      if (product.barcode != null && product.barcode == query) {
        consider(food, product.barcode!, product: product, barcode: true);
      }
      consider(food, product.name, product: product);
      final qualifiedName = [
        product.brand,
        product.name,
      ].where((part) => part.trim().isNotEmpty).join(' ');
      if (qualifiedName != product.name) {
        consider(food, qualifiedName, product: product);
      }
      for (final alias in product.aliases) {
        consider(food, alias, product: product);
      }
    }

    candidates.sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      if (left.exact != right.exact) return left.exact ? -1 : 1;
      if ((left.product == null) != (right.product == null)) {
        return left.product == null ? 1 : -1;
      }
      return left.food.name.compareTo(right.food.name);
    });

    final unique = <String, FoodMatchCandidate>{};
    for (final candidate in candidates) {
      final key = '${candidate.food.id}:${candidate.product?.id ?? ''}';
      unique.putIfAbsent(key, () => candidate);
    }
    return FoodMatchResult(candidates: unique.values.take(5).toList());
  }

  double _similarity(String left, String right) {
    final leftTokens = _tokens(left);
    final rightTokens = _tokens(right);
    if (leftTokens.isEmpty || rightTokens.isEmpty) return 0;
    final overlap = leftTokens.intersection(rightTokens).length;
    if (overlap == 0) return 0;
    final candidateCoverage = overlap / rightTokens.length;
    final queryCoverage = overlap / leftTokens.length;
    var score = candidateCoverage * 0.65 + queryCoverage * 0.35;
    if (rightTokens.length > 1 && candidateCoverage == 1) score = 0.94;
    return score;
  }

  Set<String> _tokens(String value) => RegExp(r'[a-z0-9]+')
      .allMatches(value.toLowerCase())
      .map((match) => _singular(match.group(0)!))
      .where((token) => token.isNotEmpty)
      .toSet();

  String _normalize(String value) {
    final tokens = _tokens(value).toList()..sort();
    return tokens.join();
  }

  String _singular(String value) => value.length > 3 && value.endsWith('s')
      ? value.substring(0, value.length - 1)
      : value;
}
