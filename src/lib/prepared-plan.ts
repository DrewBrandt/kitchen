// Mirror the consumption RPC's source binding. Never substitute another batch
// merely because it has the same recipe, or add several small batches together.
export function preparedPlanAvailability(
  plan: { id: string; recipe: string | null; inventory_lot: string | null; intent: string; source_meal_plan: string | null; leftover_of_group_id: string | null },
  plans: Array<{ id: string; recipe: string | null; group_id: string | null }>,
  preps: Array<{ id: string; recipe: string | null; meal_plan: string | null; voided_at: string | null }>,
  lots: Array<{ id: string; prep: string | null; remaining_qty: number }>,
) {
  const matching = preps.filter((prep) => {
    if (prep.voided_at) return false;
    if (plan.inventory_lot) return lots.some((lot) => lot.id === plan.inventory_lot && lot.prep === prep.id);
    if (plan.intent !== 'leftover') return prep.meal_plan === plan.id;
    const source = plans.find((candidate) => candidate.id === prep.meal_plan);
    return Boolean(source && source.recipe === plan.recipe && (plan.source_meal_plan
      ? source.id === plan.source_meal_plan
      : plan.leftover_of_group_id && source.group_id === plan.leftover_of_group_id));
  });
  const matchingIds = new Set(matching.map((prep) => prep.id));
  const available = lots.filter((lot) => lot.prep && matchingIds.has(lot.prep) && (!plan.inventory_lot || lot.id === plan.inventory_lot));
  return {
    preparedServingsAvailable: Math.max(0, ...available.map((lot) => Number(lot.remaining_qty))),
    waitingForPreparation: matching.length === 0,
  };
}
