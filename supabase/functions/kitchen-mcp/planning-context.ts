// Recommendation context only: never infer physical safety or mutate stale records.
export const stockPlanningContext = {
  assessment: 'Recorded stock; physical availability and storage history are unverified.',
  beforeRecommendation: 'Before recommending stock, compare its recorded dates and storage with the intended eating date. Surface stale, missing or conflicting facts FIRST. Records may be stale or test data. Positive quantity and a missing bestBy do not establish usability; a date label alone does not establish safety or spoilage. Offer fresh cooking or verified alternatives when uncertain. Never silently discard or edit records.',
};

export const preparedPlanningContext = {
  ...stockPlanningContext,
  statusMeaning: 'available means nonvoided stock remains, not that the food is safe to eat. Inspect preparedAt, timePrecision, location and bestBy before proposing this batch.',
  refrigeratedMeatGuidance: 'FoodSafety.gov lists 3-4 refrigerated days at 40 F / 4 C or below for cooked meat/poultry leftovers. Do not recommend an older fridge batch by default or offer eating it merely if it is still present or seems fine. Prefer a fresh batch; clarify actual freezing/thawing history if the record may be wrong. Do not apply this meat/poultry threshold indiscriminately to every food.',
  frozenGuidance: 'Freezer duration guidance concerns quality when food was continuously held at 0 F / -18 C or below. Age alone does not make a frozen batch unsafe, and a current freezer location does not prove continuous freezing. Unknown storage or thawing history remains unknown.',
  sourceUrl: 'https://www.foodsafety.gov/food-safety-charts/cold-food-storage-charts',
};

export const leftoverPlanningGuidance = 'For cook-once dinner plus later leftovers, choose one definite preparation date and enough yield for both meals; distinguish servings made from servings eaten. Save the recipe entry with intent=prepare first, then read back its exact plan ID. Append later recipe entries with intent=leftover and sourceMealPlanId referencing that preparation (same recipe, before the leftover meal). Never invent the source ID, use a group ID as the link, or schedule another fresh preparation while calling it leftovers. Already-cooked food uses source=inventoryLot and intent=consume with its exact batchId after the storage check. Read back dates, intents, source links and portions before claiming the plan is saved.';
