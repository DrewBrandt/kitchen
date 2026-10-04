import { z } from 'zod';

const uuid = z.string().uuid();
const pieces = z.number().positive().multipleOf(0.25);
export const plannedPreparationSchema = z.object({
  requestId: uuid.describe('Stable ID for this exact cooking action. Reuse every argument unchanged after an ambiguous outcome.'),
  recipeId: uuid,
  mealPlanId: uuid.describe('Exact saved recipe plan with intent=prepare; never the later leftover entry.'),
  timestamp: z.string().datetime({ offset: true }).describe('Current cooking-action time with UTC offset. The app records batch creation now; this is not a historical-preparation backfill tool.'),
  location: z.enum(['fridge', 'freezer']),
  servingsMade: z.number().positive().optional().describe('Actual batch yield in servings, independently of pieces. Omit to use saved recipe servings times effective scale. Never infer servings from piece count.'),
  pieceInputs: z.array(z.object({
    ingredientId: uuid,
    lotId: uuid.describe('Exact matching ingredient inventory lot from a complete inventory read.'),
    pieces: pieces.describe('Requested whole/half/quarter pieces. State whether using a saved recipe estimate or verified lot basis; this is not proof of the physical lot count.'),
    expectedRemaining: z.number().positive().describe('Latest returned lot quantity in grams; the transaction rejects stale stock.'),
    weightGrams: z.number().positive().optional().describe('Explicit actual weight of the selected pieces, when known. Requires a saved recipe piece basis. Do not infer that the entire lot contains the requested number of pieces.'),
    scaleRecipe: z.boolean().optional().describe('Only for a saved anchor ingredient: scale the whole recipe to selected weight / recipe anchor grams, overriding the saved plan scale. Otherwise retain the saved plan scale.'),
    useIngredientNutrition: z.boolean().optional().describe('Explicitly use ingredient-derived nutrition for this batch when chosen piece proportions conflict with recipe nutrition overrides.'),
  }).strict()).min(1).max(50).optional(),
}).strict().refine(args => !args.pieceInputs || new Set(args.pieceInputs.map(i => i.ingredientId)).size === args.pieceInputs.length,
  'Select each recipe ingredient at most once.');

export const plannedPreparationTool = {
  name: 'prepare_planned_recipe', rpc: 'prepare_recipe', schema: plannedPreparationSchema,
  description: 'Cook one saved recipe preparation plan now and link the new batch to that exact plan, marking it made. Reads required: complete recipe/ingredient coverage, inventory and plan. Missing ingredients must be resolved; saved recipes or partial inventory pages do not prove stock. Uses the plan scale unless an anchor pieceInput explicitly sets scaleRecipe. Optional selected lot/piece/actual-weight inputs use existing app semantics; no lot piece count is created by this tool. Null lot pieceBasis means physical count is unknown; a recipe estimate of four pieces is not four confirmed pieces in the lot. Yield is recipe servings times effective scale unless servingsMade is explicitly supplied; piece count never equals servings by default. Does not log eating. After success use fulfill_planned_entry for dinner and its linked later leftovers; do not also call prepare_batch for the same cooking event. For unplanned cooking, manual leftovers or historical backfill use prepare_batch. Reuse requestId and identical arguments on ambiguous retry; no automatic retry.',
  params: (input: Record<string, unknown>) => {
    const a = plannedPreparationSchema.parse(input);
    return { p_request_id: a.requestId, p_recipe: a.recipeId, p_meal_plan: a.mealPlanId,
      p_scale: 1, p_servings: a.servingsMade ?? null, p_location: a.location,
      p_eaten_servings: 0, p_occurred_at: a.timestamp,
      ...(a.pieceInputs ? { p_piece_inputs: a.pieceInputs } : {}) };
  },
  result: (data: unknown) => z.object({ prepId: uuid, lotId: uuid, mealPlanId: uuid,
    servingsMade: z.number().positive(), servingsRemaining: z.number().positive(),
    location: z.enum(['fridge', 'freezer']), foodLogId: z.null(),
  }).parse(data),
};
