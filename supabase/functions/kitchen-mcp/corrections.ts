import { z } from 'zod';

const uuid = z.string().uuid();
type Args = Record<string, unknown>;
export const correctionTools = [
  {
    name: 'undo_preparation', rpc: 'undo_prep',
    schema: z.object({ prepId: uuid }).strict(),
    description: 'Undo one whole preparation by prepId from get_prepared_foods or a preparation result, not its batch/lot ID. Restores its ingredient deductions, removes remaining output stock by a reversal event, retains the voided preparation/history, and resets its source preparation plan to planned. Refuses any active inventory event on the produced batch, including eating, waste, adjustment or downstream cooking. Do not automatically cascade reversals or remove plans to bypass a refusal. Future leftovers wait for preparation again; review any exact-lot plans. Repeating the same undo has no additional effect. Read back depleted/voided batches, ingredients and plans before reporting success.',
    params: (a: Args) => ({ p_prep: a.prepId }),
    result: (data: unknown) => { z.union([z.null(), z.literal('')]).parse(data); return { status: 'undone' }; },
    failureHint: 'Preparation undo requires a batch with no active dependent stock events. Read the batch/history and report the dependency; do not cascade other reversals automatically.',
  },
  {
    name: 'undo_grocery_receipt', rpc: 'undo_inventory_receipt',
    schema: z.object({ requestId: uuid, lotId: uuid }).strict(),
    description: 'Undo an untouched inventory lot created by the app receive-shopping-item workflow. This does not undo a generic grocery haul, imported lot or purchase-and-consume log. Use the exact receipt lotId. Requires the source shopping item and unchanged association; refuses active stock events, changed remaining quantity or an exact-lot pending meal plan. Removes received stock through an acquisition reversal, reopens the shopping receipt association, preserves later shopping edits/progress, and conditionally restores only prices seeded by this receipt when unchanged. History is retained. Do not delete plans or cascade dependent reversals. Reuse requestId and identical arguments on an ambiguous retry; read back inventory and groceries.',
    params: (a: Args) => ({ p_request_id: a.requestId, p_lot: a.lotId }),
    result: (data: unknown) => z.object({ lotId: uuid, itemId: uuid.optional(), status: z.enum(['undone', 'already undone']) })
      .refine(result => result.status !== 'undone' || Boolean(result.itemId)).parse(data),
    failureHint: 'Receipt undo supports only app shopping receipts with an intact source item and unused, unadjusted, unassigned stock. Report dependencies or unsupported receipt provenance; do not remove plans or cascade reversals.',
  },
  {
    name: 'correct_consumed_quantity', rpc: 'correct_consumed_quantity',
    schema: z.object({ requestId: uuid, foodLogId: uuid.describe('Exact committed event ID from a successful write in this conversation or an existing meal explicitly identified by the user. Never substitute an older similar log for a pending or unapproved action; clarify ambiguous targets.'),
      expectedQuantity: z.number().positive().describe('Positive magnitude of the current single inventoryEvents[].quantity_delta from get_history, not food-log servings for a raw lot.'),
      quantity: z.number().positive().describe('Replacement consumed quantity in the same canonical unit: g for weight, fl oz for volume, count for discrete lots, servings for prepared batches. Zero is unsupported; use void_consumption to remove eating.'),
    }).strict(),
    description: 'Correct the amount of one active single-lot inventory/prepared consumption. Read get_history first: exactly one active eaten inventory event must identify the source lot and expectedQuantity. Supports increases only within original consumption plus remaining source stock. Refuses manual, purchase-linked, multi-lot, voided/replaced or stale events. Atomically voids the original log/deduction, writes a replacement, adjusts stock, proportionally scales recorded nutrition/cost, and rebinds linked planned consumption without marking another meal eaten. Retains original history and replacement audit; subsequent corrections or voids must use the returned id. Does not edit recipes or acquisition history. Reuse requestId and identical arguments on ambiguous retry; no automatic retry. Use edit_consumption for supported metadata-only changes.',
    params: (a: Args) => ({ p_request_id: a.requestId, p_food_log: a.foodLogId, p_expected_quantity: a.expectedQuantity, p_quantity: a.quantity }),
    result: (data: unknown) => z.object({ status: z.enum(['corrected', 'unchanged']), id: uuid, originalId: uuid, lotId: uuid,
      quantity: z.number().positive(), unit: z.enum(['g', 'fl oz', 'count', 'servings']).optional(),
    }).refine(result => result.status !== 'corrected' || Boolean(result.unit)).parse(data),
    failureHint: 'Read the current single active eaten event and its canonical quantity/unit. Zero, purchase-linked, multi-lot, stale/replaced events and insufficient source stock are unsupported; do not create compensating logs.',
  },
];
