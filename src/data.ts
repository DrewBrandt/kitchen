export type PageId =
  | 'today'
  | 'inventory'
  | 'recipes'
  | 'eating-out'
  | 'food-log'
  | 'history'
  | 'trends'
  | 'week'
  | 'grocery';

export type PanelKind =
  | 'lot'
  | 'groceries'
  | 'food'
  | 'recipe'
  | 'external'
  | 'log'
  | 'item'
  | 'meal'
  | 'targets'
  | 'export'
  | 'scan'
  | 'profile'
  | 'calendar'
  | 'recipe-detail'
  | 'cook'
  | 'combined-meal';

export interface NavItem {
  id: PageId;
  label: string;
  group: 'Kitchen' | 'Eating' | 'Planning';
  badge?: string;
}

export const NAV_ITEMS: NavItem[] = [
  { id: 'today', label: 'Today', group: 'Kitchen' },
  { id: 'inventory', label: 'Inventory', group: 'Kitchen', badge: '6' },
  { id: 'recipes', label: 'Recipes', group: 'Kitchen', badge: '2' },
  { id: 'eating-out', label: 'Eating out', group: 'Kitchen', badge: '3' },
  { id: 'food-log', label: 'Food log', group: 'Eating' },
  { id: 'history', label: 'History', group: 'Eating' },
  { id: 'trends', label: 'Trends', group: 'Eating' },
  { id: 'week', label: 'This week', group: 'Planning', badge: '2' },
  { id: 'grocery', label: 'Grocery list', group: 'Planning', badge: '4' },
];

export const PAGE_META: Record<PageId, { eyebrow: string; title: string; subtitle: string; primary: string; secondary?: string }> = {
  today: { eyebrow: '', title: '', subtitle: 'See what needs attention and what is ready to eat.', primary: 'Add inventory', secondary: 'Look up barcode' },
  inventory: { eyebrow: '6 FOODS · 7 LOTS', title: 'Inventory', subtitle: 'Grouped by grocery department. Lots deduct earliest-expiry first.', primary: 'Add lot' },
  recipes: { eyebrow: '2 RECIPES · 2 COOKABLE NOW', title: 'Recipes', subtitle: 'What is ready to cook, and exactly what a run to the store would unlock.', primary: 'New recipe' },
  'eating-out': { eyebrow: '3 SAVED ITEMS · 2 PLACES', title: 'Eating out', subtitle: 'Restaurant orders and packaged foods. Logging these never touches inventory.', primary: 'Save food' },
  'food-log': { eyebrow: 'TODAY · THU, AUG 27', title: 'Food log', subtitle: 'Calories and nutrients from recipes, pantry items, and food away from home.', primary: 'Log food', secondary: 'Look up barcode' },
  history: { eyebrow: 'LAST 2 WEEKS', title: 'History', subtitle: '9 meals · 6 distinct foods · 1 repeated three times or more.', primary: 'Export range' },
  trends: { eyebrow: 'LAST 30 DAYS', title: 'Trends', subtitle: 'Daily nutrition against targets, and the foods driving each nutrient.', primary: 'Edit targets' },
  week: { eyebrow: 'AUG 24 – AUG 30', title: 'This week', subtitle: '2 meals planned · 4 groceries needed to cook them.', primary: 'Add a meal', secondary: 'Rebuild grocery list' },
  grocery: { eyebrow: 'THIS WEEK', title: 'Grocery list', subtitle: 'Manual items and plan shortages, grouped by grocery department.', primary: 'Add item', secondary: 'Rebuild from plan' },
};

export const INVENTORY_SECTIONS = [
  {
    emoji: '🥬', label: 'Produce & deli meats',
    foods: [
      { emoji: '🧅', name: 'Onions', sub: 'Main ingredient · produce', total: '3 each', due: '6 days', tone: 'warn', lots: ['2 pantry', '1 fridge'] },
      { emoji: '🥬', name: 'Spinach', sub: 'Supporting ingredient · produce', total: '8 oz', due: '2 days', tone: 'urgent', lots: ['1 fridge'] },
    ],
  },
  {
    emoji: '🥚', label: 'Eggs, yogurt, cheese & dough',
    foods: [
      { emoji: '🥚', name: 'Eggs', sub: 'Main ingredient · dairy case', total: '14 each', due: '11 days', tone: 'safe', lots: ['12 fridge', '2 fridge'] },
      { emoji: '🥛', name: 'Whole milk', sub: 'Supporting ingredient · dairy case', total: '1.4 L', due: '3 days', tone: 'warn', lots: ['1.4 L fridge'] },
    ],
  },
  {
    emoji: '🌾', label: 'Baking & pantry staples',
    foods: [
      { emoji: '🌾', name: 'All-purpose flour', sub: 'Staple · baking aisle', total: '1.1 kg', due: 'Unknown', tone: 'muted', lots: ['1 pantry'] },
      { emoji: '🧂', name: 'Kosher salt', sub: 'Staple / seasoning', total: '300 g', due: 'Unknown', tone: 'muted', lots: ['1 pantry'] },
    ],
  },
];

export interface Recipe {
  id: string;
  emoji: string;
  name: string;
  servings: number;
  minutes: number;
  nutrition: string;
  ingredients: { label: string; stock: string }[];
  steps: string[];
  ease: number;
  taste: number;
  cookable?: boolean;
}

export const RECIPES: Recipe[] = [
  {
    id: 'pancakes', emoji: '🥞', name: 'Simple Pancakes', servings: 4, minutes: 24,
    nutrition: '310 cal · 9 g protein per serving', ease: 4, taste: 5, cookable: true,
    ingredients: [
      { label: '1½ cups all-purpose flour', stock: '1.1 kg in stock' },
      { label: '1¼ cups milk', stock: '1.4 L · expires in 3 days' },
      { label: '1 egg', stock: '14 in stock' },
      { label: '2 tbsp butter', stock: '340 g in stock' },
      { label: '½ tsp salt', stock: '300 g in stock' },
    ],
    steps: ['Whisk the dry ingredients.', 'Whisk in milk and egg until just combined.', 'Cook portions in butter on a hot skillet.'],
  },
  {
    id: 'eggs', emoji: '🍳', name: 'Soft Scrambled Eggs', servings: 1, minutes: 9,
    nutrition: '220 cal · 13 g protein per serving', ease: 5, taste: 4, cookable: true,
    ingredients: [
      { label: '2 eggs', stock: '14 in stock' },
      { label: '½ tbsp butter', stock: '340 g in stock' },
      { label: '⅛ tsp salt', stock: '300 g in stock' },
    ],
    steps: ['Beat the eggs with a pinch of salt.', 'Melt butter over medium-low heat.', 'Stir gently until softly set.'],
  },
];

export const GROCERY_SECTIONS = [
  { emoji: '🥬', label: 'Produce & deli meats', items: [{ name: 'Onions', quantity: '2 onions' }, { name: 'Spinach', quantity: '1 bag' }] },
  { emoji: '🥚', label: 'Eggs, yogurt, cheese & dough', items: [{ name: 'Eggs', quantity: '1 dozen' }] },
  { emoji: '🍫', label: 'Snacks, chips & sports drinks', items: [{ name: 'Sports drinks', quantity: '2 bottles' }, { name: 'Tortilla chips', quantity: '1 bag' }] },
];

export const NUTRIENTS = [
  { label: 'Calories', value: '1,180', target: '/ 2,300 cal', pct: 51, color: '#86d7ac' },
  { label: 'Protein', value: '74 g', target: '/ 130 g', pct: 57, color: '#86d7ac' },
  { label: 'Carbs', value: '118 g', target: '/ 260 g', pct: 45, color: '#8fbce6' },
  { label: 'Fat', value: '42 g', target: '/ 75 g', pct: 56, color: '#b0a6e0' },
  { label: 'Fiber', value: '17 g', target: '/ 30 g', pct: 57, color: '#e5c07b' },
  { label: 'Sodium', value: '1,420 mg', target: '/ 2,300 mg', pct: 62, color: '#e88592' },
];

export const WEEK_DAYS = [
  { day: 'MON', date: '25', meals: [] },
  { day: 'TUE', date: '26', meals: [{ slot: 'BREAKFAST', name: 'Soft Scrambled Eggs', emoji: '🍳' }] },
  { day: 'WED', date: '27', today: true, meals: [{ slot: 'DINNER', name: 'Simple Pancakes', emoji: '🥞' }] },
  { day: 'THU', date: '28', meals: [] },
  { day: 'FRI', date: '29', meals: [{ slot: 'DINNER', name: 'Soft Scrambled Eggs', emoji: '🍳' }] },
  { day: 'SAT', date: '30', meals: [] },
  { day: 'SUN', date: '31', meals: [] },
];

export const FOOD_LOG = [
  { emoji: '🥞', label: 'Simple Pancakes', serving: '1 serving', calories: '310 cal', protein: '9 g protein', time: '8:04 AM', color: '#86d7ac' },
  { emoji: '🥣', label: '2× Greek yogurt', serving: '2 containers', calories: '280 cal', protein: '30 g protein', time: '1:15 PM', color: '#8fbce6' },
  { emoji: '🥪', label: 'Chicken sandwich', serving: '1 sandwich · estimated', calories: '590 cal', protein: '35 g protein', time: '6:48 PM', color: '#b0a6e0' },
];

export const HISTORY = [
  { day: 'Thursday', date: 'AUG 27', meals: ['Simple Pancakes', '2× Greek yogurt', 'Chicken sandwich'], totals: '1,180 cal\n74 g protein' },
  { day: 'Wednesday', date: 'AUG 26', meals: ['Soft Scrambled Eggs', 'Chicken sandwich'], totals: '1,640 cal\n102 g protein' },
  { day: 'Monday', date: 'AUG 24', meals: ['Simple Pancakes', 'Greek yogurt'], totals: '1,420 cal\n88 g protein' },
  { day: 'Saturday', date: 'AUG 22', meals: ['Weekend brunch', 'Chicken sandwich'], totals: '1,830 cal\n111 g protein' },
];

export const TREND_VALUES = [72, 88, 131, 96, 140, 64, 102, 118, 126, 80, 134, 90, 110, 148, 70, 96, 122, 86, 138, 104, 92, 128, 76, 116, 142, 88, 98, 120, 84, 68];
