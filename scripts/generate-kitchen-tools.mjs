// Keep MCP write arguments tied to the existing domain/OpenAPI contract.
import { readFileSync, writeFileSync } from 'node:fs';
import { parse } from 'yaml';
const contract = parse(readFileSync(new URL('../docs/pantry-gpt-openapi.yaml', import.meta.url), 'utf8'));
const names = {
  reconcilePantryInventory: 'reconcile_inventory', saveFoodDefinition: 'save_food', editFoodDefinition: 'edit_food',
  saveProductDefinition: 'save_product', editProductDefinition: 'edit_product', addGroceryHaul: 'add_grocery_haul',
  saveRecipe: 'save_recipe', editRecipe: 'edit_recipe', editInventoryLot: 'edit_inventory_lot',
  prepareFoodBatch: 'prepare_batch', consumePreparedFood: 'consume_prepared', consumePantryItem: 'consume_inventory',
  consumePurchasedProduct: 'consume_purchased_product', logManualConsumption: 'log_manual_consumption',
  voidConsumptionEvent: 'void_consumption', editConsumptionEvent: 'edit_consumption',
  saveMealPlan: 'save_meal_plan', previewDailyNutrition: 'preview_daily_nutrition', addManualGroceryItem: 'add_grocery_item',
};
const additive = new Set(['save_food', 'save_product', 'add_grocery_haul', 'log_manual_consumption', 'add_grocery_item']);
const tools=[];
for (const [path, methods] of Object.entries(contract.paths)) for (const [method, op] of Object.entries(methods)) {
  const name=names[op.operationId]; if (!name) continue;
  const schema=structuredClone(op.requestBody.content['application/json'].schema);
  if (path.includes('{id}')) { schema.properties={id:{type:'string',format:'uuid',description:'Exact existing record ID returned by a read.'},...schema.properties}; schema.required=[...new Set(['id',...(schema.required??[])])]; }
  const readOnly=name==='preview_daily_nutrition';
  const deduplicated=Boolean(schema.required?.includes('requestId'));
  let description=[op.summary, op.description].filter(Boolean).join('. ');
  description+=readOnly?' Read-only what-if: never saves a plan, food, inventory or history.':deduplicated?' Requires a stable domain requestId UUID for this exact approved action. Reuse it on an ambiguous retry; changed arguments require a new approved action.':' No request-key deduplication is provided. Do not automatically retry after an ambiguous failure; read back first.';
  if(name==='prepare_batch')description+=' Unplanned cooking or manual leftovers only; for a saved preparation plan or selected ingredient lot/piece/weight inputs use prepare_planned_recipe instead. Never call both tools for the same cooking event. Cooking does not mean eating. Use consume_prepared for unplanned eating or fulfill_planned_entry for a saved plan. Use discard_inventory_lot for waste and undo_inventory_adjustment to reverse waste. Preparation undo remains unsupported.';
  if(name==='save_meal_plan')description+=' Append for one addition; replaceWeek only for an explicitly requested complete week replacement. Cook-once and later leftovers require one definite preparation date and enough yield for all portions. Save the recipe preparation first with intent=prepare; read back its exact ID before appending intent=leftover entries with sourceMealPlanId for that same recipe. The preparation must precede leftovers. Do not substitute group IDs or invent IDs, and do not describe a second fresh preparation as leftovers. Already-cooked food uses source=inventoryLot and intent=consume after checking storage/age. Read back get_plan and get_groceries, verifying dates, intents, links and portions.';
  if(name==='void_consumption')description+=' Use the exact event ID and reason. Never create a cancelling event.';
  tools.push({name,path,method:method.toUpperCase(),description,schema,readOnly,destructive:!readOnly&&!additive.has(name),deduplicated});
}
if(tools.length!==Object.keys(names).length)throw new Error('Missing mapped operation');
writeFileSync(new URL('../supabase/functions/kitchen-mcp/operation-schemas.json',import.meta.url),JSON.stringify(tools,null,2)+'\n');
