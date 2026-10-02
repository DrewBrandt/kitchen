import type { PlannedMealView } from '../pantry-data';

type DisplayMeal = Pick<PlannedMealView, 'status' | 'consumptionStatus' | 'isLeftover' | 'sourceKind' | 'consumeFromInventory' | 'waitingForPreparation' | 'preparedServingsAvailable' | 'sourceShortfall'>;

/** Leftover preparation state belongs to its live source, not its stored made flag. */
export function planDisplayStatus(meals: DisplayMeal[], past: boolean) {
  const result = (label: string, tone: string, made = false, eaten = false) => ({ label, tone, made, eaten });
  if (meals.every((meal) => meal.consumptionStatus === 'fulfilled')) return result('Eaten', 'eaten', false, true);
  const pending = meals.filter((meal) => meal.consumptionStatus !== 'fulfilled');
  if (pending.some((meal) => meal.sourceShortfall)) return result('Check source', 'planned');
  const blockedLeftovers = pending.filter((meal) => meal.isLeftover && !(Number(meal.preparedServingsAvailable) > 0));
  if (blockedLeftovers.some((meal) => meal.waitingForPreparation !== false)) return result('Waiting for preparation', 'planned');
  if (blockedLeftovers.length) return result('No servings remaining', 'planned');
  if (pending.every((meal) => meal.isLeftover)) return result('Ready · not eaten', 'ready');

  // Preserve ordinary recipe and pantry-plan presentation. A leftover's stored
  // status never contributes to the count of prepared dishes.
  const madeCount = meals.filter((meal) => meal.isLeftover
    ? meal.waitingForPreparation === false
    : meal.status === 'made').length;
  const made = madeCount === meals.length;
  const directFromPantry = meals.every((meal) => meal.sourceKind === 'product' || meal.sourceKind === 'lot');
  if (directFromPantry) return result(meals.every((meal) => meal.consumeFromInventory === false) ? 'No prep' : 'Ready', 'ready');
  if (made) return result('Made · not eaten', 'made', true);
  return result(madeCount ? `${madeCount}/${meals.length} made` : past ? 'Not made' : 'Planned', past ? 'missed' : 'planned');
}
