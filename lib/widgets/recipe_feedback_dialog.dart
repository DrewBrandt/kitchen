import 'package:flutter/material.dart';

import '../models/pantry_models.dart';

class RecipeFeedbackResult {
  const RecipeFeedbackResult({
    this.tasteRating,
    this.easeRating,
    this.actualMinutes,
    this.dontAskAgain = false,
  });

  final int? tasteRating;
  final int? easeRating;
  final int? actualMinutes;
  final bool dontAskAgain;
}

Future<RecipeFeedbackResult?> showRecipeFeedbackDialog(
  BuildContext context,
  Recipe recipe,
) => showDialog<RecipeFeedbackResult>(
  context: context,
  builder: (context) => _RecipeFeedbackDialog(recipe: recipe),
);

class _RecipeFeedbackDialog extends StatefulWidget {
  const _RecipeFeedbackDialog({required this.recipe});

  final Recipe recipe;

  @override
  State<_RecipeFeedbackDialog> createState() => _RecipeFeedbackDialogState();
}

class _RecipeFeedbackDialogState extends State<_RecipeFeedbackDialog> {
  int? taste;
  int? ease;
  bool dontAskAgain = false;
  String? error;
  final minutes = TextEditingController();

  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('How did ${widget.recipe.name} go?'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('This builds a personal average each time you make it.'),
            const SizedBox(height: 20),
            _RatingField(
              label: 'Taste',
              color: const Color(0xFFFFB347),
              value: taste,
              onChanged: (value) => setState(() => taste = value),
            ),
            const SizedBox(height: 16),
            _RatingField(
              label: 'Ease',
              color: const Color(0xFF71E59A),
              value: ease,
              onChanged: (value) => setState(() => ease = value),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual time',
                suffixText: 'minutes',
                helperText: 'Total hands-on and waiting time',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Don't ask again for this recipe"),
              subtitle: const Text(
                'You can turn this back on while editing the recipe.',
              ),
              value: dontAskAgain,
              onChanged: (value) =>
                  setState(() => dontAskAgain = value ?? false),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(
          context,
          RecipeFeedbackResult(dontAskAgain: dontAskAgain),
        ),
        child: const Text('Skip'),
      ),
      FilledButton(
        onPressed: () {
          final rawMinutes = minutes.text.trim();
          final parsedMinutes = rawMinutes.isEmpty
              ? null
              : int.tryParse(rawMinutes);
          if (rawMinutes.isNotEmpty &&
              (parsedMinutes == null || parsedMinutes <= 0)) {
            setState(() => error = 'Time must be a positive whole number.');
            return;
          }
          if (taste == null && ease == null && parsedMinutes == null) {
            setState(() => error = 'Add at least one answer, or choose Skip.');
            return;
          }
          Navigator.pop(
            context,
            RecipeFeedbackResult(
              tasteRating: taste,
              easeRating: ease,
              actualMinutes: parsedMinutes,
              dontAskAgain: dontAskAgain,
            ),
          );
        },
        child: const Text('Save feedback'),
      ),
    ],
  );
}

class _RatingField extends StatelessWidget {
  const _RatingField({
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 62,
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      ...List.generate(5, (index) {
        final rating = index + 1;
        return IconButton(
          tooltip: '$rating out of 5',
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(rating),
          icon: Icon(
            rating <= (value ?? 0) ? Icons.circle : Icons.circle_outlined,
            size: 18,
            color: rating <= (value ?? 0)
                ? color
                : Theme.of(context).colorScheme.outline,
          ),
        );
      }),
      if (value != null)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text('$value/5'),
        ),
    ],
  );
}
