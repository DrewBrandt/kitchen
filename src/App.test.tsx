import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App, greetingFor } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';

const scannerMocks = vi.hoisted(() => ({ decodeFromStream: vi.fn() }));

vi.mock('@zxing/browser', () => ({
  BarcodeFormat: { UPC_A: 1, UPC_E: 2, EAN_8: 3, EAN_13: 4, CODE_128: 5 },
  BrowserMultiFormatReader: class {
    possibleFormats: number[] = [];
    decodeFromStream = scannerMocks.decodeFromStream;
  },
}));

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  scannerMocks.decodeFromStream.mockReset();
});

const currentDateKey = (timeZone = previewPantryData.settings.timeZone) => {
  const parts = new Intl.DateTimeFormat('en-US', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).formatToParts(new Date());
  const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? '';
  return `${value('year')}-${value('month')}-${value('day')}`;
};

describe('Pantry web UI', () => {
  it('corrects only the chosen consumption in a grouped food log', async () => {
    localStorage.clear();
    const save = vi.fn().mockResolvedValue('replacement');
    const snapshot = { quantity: 2, canonicalUnit: 'servings', displayUnit: 'servings', displayPerBase: 1, calories: 400, protein: null, cost: null, estimated: false };
    const entry = { ...previewPantryData.foodLog[0], eventIds: ['first', 'second'], events: ['first', 'second'].map((id) => ({ id, label: 'Lunch', portion: '2 servings', time: 'Time not specified', cost: null, costIsEstimated: false, quantityCorrection: snapshot })) };
    render(<PantryDataProvider data={{ ...previewPantryData, foodLog: [entry] }}><App onCorrectQuantity={save} /></PantryDataProvider>);
    await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
    await userEvent.click(screen.getByRole('button', { name: `View ${entry.label} consumption event` }));
    await userEvent.click(screen.getByRole('button', { name: 'Correct quantity for consumption 2' }));
    const input = screen.getByLabelText('Correct amount eaten (servings)');
    await waitFor(() => expect(input).toBeEnabled());
    await userEvent.clear(input); await userEvent.type(input, '1');
    await userEvent.click(screen.getByRole('button', { name: 'Save quantity correction' }));
    expect(save).toHaveBeenCalledExactlyOnceWith('second', 2, 1);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
  it('shows unknown detail nutrients distinctly from known zero', async () => {
    const entry = { ...previewPantryData.foodLog[0], nutrition: { Calories: 100, Protein: null, Carbs: 0, Fat: null, Fiber: null, Sodium: null }, nutritionStatus: 'partial' as const };
    render(<PantryDataProvider data={{ ...previewPantryData, foodLog: [entry] }}><App /></PantryDataProvider>);
    await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
    await userEvent.click(screen.getByRole('button', { name: `View ${entry.label} consumption event` }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('Protein').parentElement).toHaveTextContent('Unknown');
    expect(within(dialog).getByText('Carbs').parentElement).toHaveTextContent('0 g');
    expect(within(dialog).getByText('Calories').parentElement).toHaveTextContent('100 cal');
  });

  it('stages Today recipe-detail Make batch in the workspace without cooking', async () => {
    localStorage.clear();
    const onCook = vi.fn();
    const recipe = previewPantryData.recipes[0];
    render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [] }}><App onCookRecipe={onCook} /></PantryDataProvider>);
    await userEvent.click(screen.getByRole('button', { name: new RegExp(recipe.name) }));
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Make batch' }));
    expect(onCook).not.toHaveBeenCalled();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    const card = screen.getByRole('article', { name: recipe.name });
    expect(within(card).getByLabelText(`Recipe multiplier for ${recipe.name}`)).toBeInTheDocument();
    expect(within(card).getByRole('button', { name: 'Finish cooking' })).toBeInTheDocument();
  });
  it('opens an individual manual event editor from the food log', async () => {
    const save = vi.fn().mockResolvedValue(undefined);
    const manual = { label: 'Manual lunch', portionLabel: '2 portions', note: null, nutrition: { calories: null, proteinG: null, carbsG: null, fatG: null, fiberG: null, sugarG: null, sodiumMg: null, estimated: false, source: null } };
    const entry = { ...previewPantryData.foodLog[0], label: manual.label, id: 'manual-event', eventIds: ['manual-event'], events: [{ id: 'manual-event', label: manual.label, portion: '2 portions', time: 'Time not specified', cost: null, costIsEstimated: false, manual }] };
    render(<PantryDataProvider data={{ ...previewPantryData, foodLog: [entry] }}><App onUpdateFoodLog={save} /></PantryDataProvider>);
    await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
    await userEvent.click(screen.getByRole('button', { name: 'View Manual lunch consumption event' }));
    await userEvent.click(screen.getByRole('button', { name: 'Edit consumption 1' }));
    await userEvent.clear(screen.getByLabelText('Portion description'));
    await userEvent.type(screen.getByLabelText('Portion description'), '1 portion');
    await userEvent.click(screen.getByRole('button', { name: 'Save correction' }));
    expect(save).toHaveBeenCalledExactlyOnceWith('manual-event', { portionLabel: '1 portion' });
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
  it('removes only the selected event from a grouped consumption', async () => {
    const onVoidFoodLog = vi.fn().mockResolvedValue(undefined);
    const entry = { ...previewPantryData.foodLog[0], id: 'event-one', eventIds: ['event-one', 'event-two'], events: [
      { id: 'event-one', label: 'Snack', portion: '1 serving', time: '1:00 PM', cost: 1, costIsEstimated: false },
      { id: 'event-two', label: 'Snack', portion: 'half serving', time: '1:20 PM', cost: 0.5, costIsEstimated: false },
    ] };
    render(<PantryDataProvider data={{ ...previewPantryData, foodLog: [entry] }}><App onVoidFoodLog={onVoidFoodLog} /></PantryDataProvider>);
    await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
    await userEvent.click(screen.getByRole('button', { name: 'Choose ' + entry.label + ' event to remove' }));
    expect(onVoidFoodLog).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: 'Remove consumption 2' }));
    expect(onVoidFoodLog).toHaveBeenCalledExactlyOnceWith('event-two');
    expect(screen.getByRole('button', { name: 'Remove consumption 1' })).toBeEnabled();
  });

  it('renders the mockup-inspired dashboard and complete navigation', () => {
    render(<App />);

    expect(screen.getByRole('heading', { name: /Good (morning|afternoon|evening), Drew/ })).toBeInTheDocument();
    expect(screen.getByText('Ready to eat')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Inventory' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Grocery list/ })).toBeInTheDocument();
    expect(screen.getByText('Routine & food profile')).toBeInTheDocument();
  });

  it('uses the owner time zone for the greeting', () => {
    expect(greetingFor(new Date('2026-08-31T13:00:00Z'), 'America/New_York')).toBe('morning');
    expect(greetingFor(new Date('2026-08-31T19:00:00Z'), 'America/New_York')).toBe('afternoon');
    expect(greetingFor(new Date('2026-08-31T23:00:00Z'), 'America/New_York')).toBe('evening');
  });

  it('uses centered dialogs, removes dead overflow controls, and closes with Escape', async () => {
    const user = userEvent.setup();
    const { container } = render(<App />);

    expect(screen.queryByRole('button', { name: 'More actions' })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Add inventory' }));
    expect(screen.getByRole('dialog')).toHaveClass('action-panel');
    expect(container.querySelector('.panel-layer')).toBeInTheDocument();
    await user.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('searches and filters the inventory', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Inventory' }));
    expect(screen.getByText('All-purpose flour')).toBeInTheDocument();

    await user.type(screen.getByPlaceholderText('Search foods, brands, lots…'), 'spinach');
    expect(screen.getByText('Spinach')).toBeInTheDocument();
    expect(screen.queryByText('All-purpose flour')).not.toBeInTheDocument();
  });

  it('edits inventory lots in their displayed unit and converts actions to the canonical quantity', async () => {
    const user = userEvent.setup();
    const displayPerBase = 16 / 453.59237;
    const templateSection = previewPantryData.inventorySections[0];
    const templateFood = templateSection.foods[0];
    const food = {
      ...templateFood,
      name: 'Unit-aware flour',
      total: '1 lb',
      lots: ['1 lb pantry'],
      lotDetails: [{
        ...templateFood.lotDetails![0],
        id: 'unit-aware-lot',
        quantity: '1 lb',
        remainingBase: 453.59237,
        remainingDisplay: 16,
        displayUnit: 'oz',
        displayPerBase,
      }],
    };
    const data = { ...previewPantryData, inventorySections: [{ ...templateSection, foods: [food] }] };
    const onConsume = vi.fn().mockResolvedValue('food-log');
    const onSetQuantity = vi.fn().mockResolvedValue('inventory-event');
    render(<PantryDataProvider data={data}><App onConsumeInventoryLot={onConsume} onSetInventoryLotQuantity={onSetQuantity} /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: 'Inventory' }));
    await user.click(screen.getByRole('button', { name: /Unit-aware flour/ }));
    const consume = screen.getByLabelText('Consume (oz)');
    const remaining = screen.getByLabelText('Set remaining (oz)');
    expect(consume).toHaveValue(1);
    expect(remaining).toHaveValue(16);

    await user.clear(consume);
    await user.type(consume, '8');
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Consume' }));
    await waitFor(() => expect(onConsume).toHaveBeenCalledWith('unit-aware-lot', 226.796185));

    await user.click(screen.getByRole('button', { name: /Unit-aware flour/ }));
    const adjustedRemaining = screen.getByLabelText('Set remaining (oz)');
    await user.clear(adjustedRemaining);
    await user.type(adjustedRemaining, '4');
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Adjust' }));
    await waitFor(() => expect(onSetQuantity).toHaveBeenCalledWith('unit-aware-lot', 113.3980925, false));
  });

  it('carries estimated costs through inventory, recipes, and the food log', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Inventory' }));
    expect(screen.getAllByText('~$3.18').length).toBeGreaterThan(0);

    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    // Per-serving is derived from the batch, not stored: $4.72 over 4 servings.
    expect(screen.getByText(/~\$4\.72 batch/)).toBeInTheDocument();
    expect(screen.getByText('~$1.18/serving')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    expect(screen.getByText(/3 entries · ~\$13\.25/)).toBeInTheDocument();
    expect(screen.getByText('~$8.49')).toBeInTheDocument();
  });

  it('shows planned nutrition as patterned projections in the food log and Today', async () => {
    const user = userEvent.setup();
    const { container } = render(<App />);

    expect(screen.getByText(/Includes items planned for today/)).toBeInTheDocument();
    expect(container.querySelectorAll('.nutrition-card .projection-segment')).toHaveLength(7);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    expect(screen.getByText('Planned for today')).toBeInTheDocument();
    expect(container.querySelectorAll('.contribution-card .projection-segment').length).toBeGreaterThan(0);
  });

  it('labels outside-pantry product plans without implying stock or prep', async () => {
    const user = userEvent.setup();
    const dateKey = currentDateKey();
    const plannedMeals = [{
      id: 'restaurant-plan', groupId: 'restaurant-plan', dateKey, slot: 'DINNER',
      name: 'Chipotle burrito', emoji: '🌯', productId: 'chipotle-burrito',
      sourceKind: 'product' as const, consumeFromInventory: false,
      status: 'planned' as const, isLeftover: false, plannedServings: 1,
      consumptionStatus: 'planned', cost: 11.25, costIsEstimated: true,
    }];
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals }}><App /></PantryDataProvider>);

    expect(screen.getByText(/dinner · outside pantry · ~\$11\.25/i)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'This week' }));
    expect(screen.getByText(/dinner · outside pantry/i)).toBeInTheDocument();
    expect(screen.getByText('No prep')).toBeInTheDocument();
  });

  it('does not present one priced recipe as a complete grouped-meal total', async () => {
    const user = userEvent.setup();
    const dateKey = currentDateKey();
    const plannedMeals = [
      { id: 'plan-priced', groupId: 'group-1', dateKey, slot: 'DINNER', name: 'Priced main', emoji: '🍔', recipeId: 'recipe-main', status: 'planned' as const, isLeftover: false, plannedServings: 1, consumptionStatus: 'planned', cost: 6.5, costIsEstimated: false },
      { id: 'plan-unpriced', groupId: 'group-1', dateKey, slot: 'DINNER', name: 'Unpriced side', emoji: '🥦', recipeId: 'recipe-side', status: 'planned' as const, isLeftover: false, plannedServings: 1, consumptionStatus: 'planned', cost: null, costIsEstimated: true },
    ];
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals }}><App /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: 'This week' }));
    expect(screen.getAllByText('Price unavailable').length).toBeGreaterThan(0);
    expect(screen.getByText(/\$6\.50 known/)).toBeInTheDocument();
    expect(screen.getByLabelText('Planned servings for Priced main')).toHaveValue(1);
  });

  it('opens recipe detail and tracks cooking steps', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getAllByRole('button', { name: 'Make batch' })[0]);

    expect(screen.getByRole('heading', { name: 'On deck' })).toBeInTheDocument();
    const workspace = screen.getByRole('article', { name: 'Simple Pancakes' });
    expect(within(workspace).getByText('Ingredients', { selector: 'summary' })).toBeInTheDocument();
    expect(within(workspace).getByText('Method', { selector: 'summary' })).toBeInTheDocument();
    expect(within(workspace).getByText('0 of 8 complete')).toBeInTheDocument();

    await user.click(within(workspace).getByRole('button', { name: /all-purpose flour/i }));
    expect(within(workspace).getByText('1 of 8 complete')).toBeInTheDocument();
  });

  it('shows multiple recipes in a configurable, reorderable on-deck workspace', async () => {
    localStorage.clear();
    localStorage.setItem('mise.recipe-progress.pancakes', JSON.stringify(['i0']));
    localStorage.setItem('mise.recipe-progress.eggs', JSON.stringify(['i0']));
    const user = userEvent.setup();
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals: [] }}><App /></PantryDataProvider>);

    const pinned = screen.getByRole('navigation', { name: 'Pinned cooking' });
    await user.click(within(pinned).getByRole('button', { name: /Simple Pancakes/ }));

    const pancakes = screen.getByRole('article', { name: 'Simple Pancakes' });
    const eggs = screen.getByRole('article', { name: 'Soft Scrambled Eggs' });
    expect(within(pancakes).getByText('1½ cups all-purpose flour')).toBeInTheDocument();
    expect(within(eggs).getByText('⅛ tsp salt')).toBeInTheDocument();
    expect(within(eggs).getByText('1 of 6 complete')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Four corners' }));
    expect(screen.getByRole('button', { name: 'Four corners' })).toHaveAttribute('aria-pressed', 'true');
    expect(document.querySelector('.on-deck-board')).toHaveClass('layout-quad');

    await user.click(screen.getByRole('button', { name: 'Side by side' }));
    expect(document.querySelector('.on-deck-board')).toHaveClass('layout-split');

    await user.type(within(pancakes).getByRole('button', { name: /Drag Simple Pancakes panel/ }), '{ArrowRight}');
    const panelNames = [...document.querySelectorAll('.on-deck-card')].map((panel) => panel.getAttribute('aria-label'));
    expect(panelNames).toEqual(['Soft Scrambled Eggs', 'Simple Pancakes']);
  });

  it('edits recipes and pins started cooking to the sidebar', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getAllByRole('button', { name: 'Edit recipe' })[0]);
    expect(within(screen.getByRole('dialog')).getByLabelText('Recipe name')).toHaveValue('Simple Pancakes');
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Close' }));

    await user.click(screen.getAllByRole('button', { name: 'Make batch' })[0]);
    await user.click(within(screen.getByRole('article', { name: 'Simple Pancakes' })).getByRole('button', { name: /all-purpose flour/i }));
    await user.click(within(screen.getByRole('navigation', { name: 'Kitchen' })).getByRole('button', { name: 'Today' }));
    expect(within(screen.getByRole('navigation', { name: 'Pinned cooking' })).getByRole('button', { name: /Simple Pancakes/ })).toBeInTheDocument();
  });

  it('waits for every uneaten leftover dish and enables only available linked portions', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const onConsume = vi.fn().mockResolvedValue([]);
    const meals = ['Rice', 'Chicken'].map((name, i) => ({ ...previewPantryData.plannedMeals[0], id: `leftover-${i}`, name, groupId: 'leftovers', dateKey: currentDateKey(), isLeftover: true, status: 'planned' as const, consumptionStatus: 'planned', preparedServingsAvailable: i === 0 ? 2 : 0, waitingForPreparation: i === 1 }));
    const { rerender } = render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals: meals }}><App onConsumePlannedMeals={onConsume} /></PantryDataProvider>);
    await user.click(screen.getByRole('button', { name: /This week/ }));
    expect(screen.getByText(/Chicken: waiting for its planned preparation/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Log eaten' })).not.toBeInTheDocument();
    rerender(<PantryDataProvider data={{ ...previewPantryData, plannedMeals: meals.map((meal) => ({ ...meal, preparedServingsAvailable: 2, waitingForPreparation: false })) }}><App onConsumePlannedMeals={onConsume} /></PantryDataProvider>);
    const rice = screen.getByRole('spinbutton', { name: 'Servings of Rice eaten now' });
    await user.clear(rice); await user.type(rice, '3');
    expect(screen.getByRole('button', { name: 'Log eaten' })).toBeDisabled();
    await user.clear(rice); await user.type(rice, '1');
    await user.click(screen.getByRole('button', { name: 'Log eaten' }));
    expect(onConsume).toHaveBeenCalledWith([{ mealPlanId: 'leftover-0', servings: 1 }, { mealPlanId: 'leftover-1', servings: meals[1].plannedServings }]);
  });

  it('does not let an already eaten component block the remaining ready dish', async () => {
    localStorage.clear();
    const meals = ['Rice', 'Chicken'].map((name, i) => ({ ...previewPantryData.plannedMeals[0], id: `leftover-${i}`, name, groupId: 'leftovers', dateKey: currentDateKey(), isLeftover: true, status: 'planned' as const, consumptionStatus: i === 0 ? 'fulfilled' : 'planned', preparedServingsAvailable: i === 0 ? 0 : 2, waitingForPreparation: false }));
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals: meals }}><App onConsumePlannedMeals={vi.fn()} /></PantryDataProvider>);
    await userEvent.click(screen.getByRole('button', { name: /This week/ }));
    expect(screen.getByRole('button', { name: 'Log eaten' })).toBeEnabled();
    expect(screen.queryByRole('spinbutton', { name: 'Servings of Rice eaten now' })).not.toBeInTheDocument();
  });

  it('opens and jumps to the method without unmounting ingredient controls', async () => {
    localStorage.clear();
    const scroll = vi.fn();
    const previous = HTMLElement.prototype.scrollIntoView;
    HTMLElement.prototype.scrollIntoView = scroll;
    try {
      render(<App />);
      await userEvent.click(screen.getByRole('button', { name: 'Recipes' }));
      await userEvent.click(screen.getAllByRole('button', { name: 'Make batch' })[0]);
      const card = screen.getByRole('article', { name: previewPantryData.recipes[0].name });
      const method = card.querySelectorAll('details')[1];
      method.open = false;
      await userEvent.click(within(card).getByRole('button', { name: 'Method' }));
      expect(method.open).toBe(true);
      expect(scroll).toHaveBeenCalledWith({ block: 'start', behavior: 'smooth' });
      expect(within(card).getByRole('spinbutton', { name: /Servings of .* made/ })).toBeInTheDocument();
    } finally { HTMLElement.prototype.scrollIntoView = previous; }
  });

  it('starts a combined meal with no recipes selected', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const onCookRecipes = vi.fn();
    const onCookRecipe = vi.fn();
    render(<App onCookRecipes={onCookRecipes} onCookRecipe={onCookRecipe} />);
    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getByRole('button', { name: 'Choose recipes' }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByRole('button', { name: 'Add to On deck' })).toBeDisabled();
    await user.click(within(dialog).getByRole('button', { name: /Simple Pancakes/ }));
    expect(within(dialog).getByRole('button', { name: 'Add to On deck' })).toBeEnabled();
    expect(within(dialog).getByRole('button', { name: /Simple Pancakes/ })).toHaveAttribute('aria-pressed', 'true');
    expect(within(dialog).getByRole('button', { name: /Simple Pancakes/ })).not.toHaveClass('checked');
    await user.click(within(dialog).getByRole('button', { name: /Soft Scrambled Eggs/ }));
    await user.click(within(dialog).getByRole('button', { name: 'Add to On deck' }));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.getByRole('article', { name: 'Simple Pancakes' })).toBeInTheDocument();
    expect(screen.getByRole('article', { name: 'Soft Scrambled Eggs' })).toBeInTheDocument();
    expect(onCookRecipes).not.toHaveBeenCalled();
    expect(onCookRecipe).not.toHaveBeenCalled();
  });

  it('keeps repeated planned recipes independent and scales ingredients without changing yield semantics', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const recipe = { ...previewPantryData.recipes[0], ingredients: [{ label: '2 cups flour', stock: 'In stock', quantity: 2, unit: 'cups', name: 'flour', availableQuantity: 3 }] };
    const plans = [1, 2].map((n) => ({ ...previewPantryData.plannedMeals[0], id: `plan-${n}`, groupId: `group-${n}`, dateKey: currentDateKey(), recipeId: recipe.id, status: 'planned' as const, isLeftover: false, scaleFactor: n, plannedServings: 1 }));
    const onCook = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'lot', mealPlanId: 'plan-2', servingsMade: 3, servingsRemaining: 3, location: 'fridge', foodLogId: null });
    render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: plans }}><App onCookRecipe={onCook} /></PantryDataProvider>);
    await user.click(screen.getByRole('button', { name: 'On deck' }));
    const cards = screen.getAllByRole('article', { name: recipe.name });
    expect(cards).toHaveLength(2);
    expect(within(cards[0]).getByText('2 cups flour')).toBeInTheDocument();
    expect(within(cards[1]).getByText('4 cups flour')).toBeInTheDocument();
    const linkedMultiplier = within(cards[1]).getByLabelText('Recipe multiplier for ' + recipe.name);
    expect(linkedMultiplier).toHaveAttribute('readonly');
    await user.type(linkedMultiplier, '3');
    expect(linkedMultiplier).toHaveValue(2);
    expect(within(cards[1]).getByText(/Edit the plan to change its recipe multiplier/)).toBeInTheDocument();
    expect(within(cards[0]).getByText('3 cups in stock')).toBeInTheDocument();
    expect(within(cards[1]).getByText('3 cups in stock · short')).toBeInTheDocument();
    await user.click(within(cards[0]).getByRole('button', { name: /2 cups flour/ }));
    expect(within(cards[1]).getByText(`0 of ${recipe.steps.length + 1} complete`)).toBeInTheDocument();
    const yieldInput = within(cards[1]).getByLabelText(`Servings of ${recipe.name} made`);
    await user.clear(yieldInput);
    await user.type(yieldInput, '3');
    await user.click(within(cards[1]).getByRole('button', { name: 'Finish cooking' }));
    await waitFor(() => expect(onCook).toHaveBeenCalledWith(recipe.id, { scale: 2, servingsMade: 3, location: 'fridge', mealPlanId: 'plan-2', servingsEaten: 0 }));
    expect(screen.getAllByRole('article', { name: recipe.name })).toHaveLength(1);
  });

  it('cooks explicit whole or fractional pieces using an estimated lot weight without changing the recipe', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const recipe = { ...previewPantryData.recipes[0], ingredients: [{ id: 'ingredient', label: '600 g chicken', name: 'chicken', stock: '900 g in stock', quantity: 600, unit: 'g', pieceLots: [{ id: 'chicken-lot', label: 'Chicken package · 900 g', remainingBase: 900 }] }] };
    const onCook = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'lot', servingsMade: 4, servingsRemaining: 4, location: 'fridge', foodLogId: null });
    render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [] }}><App onCookRecipe={onCook} /></PantryDataProvider>);
    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getByRole('button', { name: 'Make batch' }));
    const card = screen.getByRole('article', { name: recipe.name });
    await user.click(within(card).getByText('Adjust ingredient quantities'));
    await user.selectOptions(within(card).getByLabelText('Ingredient to adjust'), 'ingredient');
    expect(within(card).getByRole('button', { name: 'Finish cooking' })).toBeDisabled();
    await user.type(within(card).getByLabelText('Pieces currently in this package'), '6');
    await user.click(within(card).getByRole('button', { name: 'Half' }));
    expect(within(card).getByText(/Approximately 75 g/)).toBeInTheDocument();
    expect(within(card).getByText(/Original recipe requirement: 600 g chicken.*replaced by pieces/)).toBeInTheDocument();
    expect(within(card).getByText(/Adjusted nutrition and cost preview unavailable/)).toBeInTheDocument();
    await user.click(within(card).getByRole('button', { name: 'Quarter' }));
    expect(within(card).getByLabelText('Pieces to cook')).toHaveValue(0.25);
    await user.click(within(card).getByRole('button', { name: 'Whole' }));
    await user.click(within(card).getByRole('button', { name: 'Finish cooking' }));
    await waitFor(() => expect(onCook).toHaveBeenCalledWith(recipe.id, expect.objectContaining({ pieceInputs: [{ ingredientId: 'ingredient', lotId: 'chicken-lot', pieces: 1, lotPieces: 6, expectedRemaining: 900 }] })));
  });

  it('uses the linked plan multiplier for normal ingredients alongside explicit piece quantities', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const recipe = { ...previewPantryData.recipes[0], ingredients: [
      { id: 'chicken', label: '600 g chicken', name: 'chicken', stock: '900 g in stock', quantity: 600, unit: 'g', pieceLots: [{ id: 'lot', label: 'Chicken package', remainingBase: 900, remainingPieces: 6 }] },
      { id: 'rice', label: '100 g rice', name: 'rice', stock: 'In stock', quantity: 100, unit: 'g' },
    ] };
    const plan = { ...previewPantryData.plannedMeals[0], id: 'piece-plan', groupId: 'piece-group', dateKey: currentDateKey(), recipeId: recipe.id, status: 'planned' as const, isLeftover: false, scaleFactor: 2, plannedServings: 1 };
    const onCook = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'result', servingsMade: 3, servingsRemaining: 3, location: 'fridge', foodLogId: null });
    render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [plan] }}><App onCookRecipe={onCook} /></PantryDataProvider>);
    await user.click(screen.getByRole('button', { name: 'On deck' }));
    const card = screen.getByRole('article', { name: recipe.name });
    const multiplier = within(card).getByLabelText('Recipe multiplier for ' + recipe.name);
    expect(multiplier).toHaveAttribute('readonly');
    await user.type(multiplier, '3');
    expect(multiplier).toHaveValue(2);
    expect(within(card).getByText('200 g rice')).toBeInTheDocument();
    await user.click(within(card).getByRole('button', { name: 'Choose pieces instead for chicken' }));
    await user.click(within(card).getByRole('button', { name: 'Half' }));
    expect(within(card).getByText(/Original recipe requirement: 1200 g chicken.*replaced by pieces/)).toBeInTheDocument();
    expect(within(card).getByText(/Approximately 75 g/)).toBeInTheDocument();
    const yieldInput = within(card).getByLabelText('Servings of ' + recipe.name + ' made');
    await user.clear(yieldInput);
    await user.type(yieldInput, '3');
    expect(within(card).getByText('200 g rice')).toBeInTheDocument();
    await user.click(within(card).getByRole('button', { name: 'Finish cooking' }));
    await waitFor(() => expect(onCook).toHaveBeenCalledWith(recipe.id, expect.objectContaining({ scale: 2, mealPlanId: 'piece-plan', servingsMade: 3, pieceInputs: [{ ingredientId: 'chicken', lotId: 'lot', pieces: 0.5, expectedRemaining: 900 }] })));
  });

  it('scales recipe ingredients separately from actual batch yield', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const recipe = { ...previewPantryData.recipes[0], ingredients: [{ id: 'flour', label: '200 g flour', name: 'flour', quantity: 200, unit: 'g', stock: 'In stock' }] };
    const onCook = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'lot', servingsMade: 3, servingsRemaining: 3, location: 'fridge', foodLogId: null });
    render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [] }}><App onCookRecipe={onCook} /></PantryDataProvider>);
    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getByRole('button', { name: 'Make batch' }));
    const card = screen.getByRole('article', { name: recipe.name });
    const multiplier = within(card).getByLabelText('Recipe multiplier for ' + recipe.name);
    await user.clear(multiplier);
    expect(within(card).getByRole('button', { name: 'Finish cooking' })).toBeDisabled();
    await user.type(multiplier, '2');
    expect(within(card).getByText('400 g flour')).toBeInTheDocument();
    const yieldInput = within(card).getByLabelText('Servings of ' + recipe.name + ' made');
    await user.clear(yieldInput);
    await user.type(yieldInput, '3');
    expect(within(card).getByText('400 g flour')).toBeInTheDocument();
    await user.click(within(card).getByRole('button', { name: 'Finish cooking' }));
    await waitFor(() => expect(onCook).toHaveBeenCalledWith(recipe.id, expect.objectContaining({ scale: 2, servingsMade: 3 })));
  });

  it('finishes a planned recipe as one linked batch and removes it from on deck', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    const todayKey = currentDateKey();
    const plannedMeals = [{ ...previewPantryData.plannedMeals[0], id: 'plan-linked', groupId: 'group-linked', dateKey: todayKey, recipeId: 'pancakes', name: 'Simple Pancakes', status: 'planned' as const, scaleFactor: 1, plannedServings: 1, consumptionStatus: 'planned' }];
    const onCook = vi.fn().mockResolvedValue({ prepId: 'prep-linked', lotId: 'lot-linked', mealPlanId: 'plan-linked', servingsMade: 4, servingsRemaining: 3, location: 'fridge', foodLogId: 'log-linked' });
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals }}><App onCookRecipe={onCook} /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: 'On deck' }));
    const workspace = screen.getByRole('article', { name: 'Simple Pancakes' });
    expect(within(workspace).getByText(/1 serving planned to eat/)).toBeInTheDocument();
    await user.clear(within(workspace).getByLabelText('Servings of Simple Pancakes eaten now'));
    await user.type(within(workspace).getByLabelText('Servings of Simple Pancakes eaten now'), '1');
    await user.click(within(workspace).getByRole('button', { name: 'Finish cooking' }));

    await waitFor(() => expect(onCook).toHaveBeenCalledWith('pancakes', { scale: 1, servingsMade: 4, location: 'fridge', mealPlanId: 'plan-linked', servingsEaten: 1 }));
    expect(screen.queryByRole('article', { name: 'Simple Pancakes' })).not.toBeInTheDocument();
    expect(screen.getByText(/Made 4 servings of Simple Pancakes; 3 stored in fridge and 1 logged as eaten/)).toBeInTheDocument();
  });

  it('logs an explicit quantity from a prepared batch', async () => {
    const user = userEvent.setup();
    const consume = vi.fn().mockResolvedValue('prepared-log');
    render(<App onConsumePrepared={consume} />);

    const quantity = screen.getByLabelText('Servings of Simple Pancakes eaten');
    await user.clear(quantity);
    await user.type(quantity, '1.5');
    await user.click(within(quantity.closest('.prepared-row')!).getByRole('button', { name: 'Log eaten' }));

    await waitFor(() => expect(consume).toHaveBeenCalledWith('preview-prep-1', 1.5));
    expect(screen.getByText('1½ servings of Simple Pancakes logged as eaten.')).toBeInTheDocument();
  });

  it('logs an editable actual serving amount without changing the planned amount', async () => {
    const user = userEvent.setup();
    const todayKey = currentDateKey();
    const plannedMeals = [{ ...previewPantryData.plannedMeals[0], id: 'made-plan', groupId: 'made-group', dateKey: todayKey, status: 'made' as const, plannedServings: 1.5, consumptionStatus: 'planned', prepId: 'made-prep', preparedLotId: 'made-lot' }];
    const consume = vi.fn().mockResolvedValue(['made-log']);
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals }}><App onConsumePlannedMeals={consume} /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: /This week/ }));
    expect(screen.getByText('Made · not eaten')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Log it' })).not.toBeInTheDocument();
    const amount = screen.getByLabelText('Servings of Simple Pancakes eaten now');
    expect(amount).toHaveValue(1.5);
    await user.clear(amount);
    await user.type(amount, '0.75');
    const button = screen.getByRole('button', { name: 'Log eaten' });
    expect(button).toBeEnabled();
    expect(button).toHaveClass('primary');
    expect(button.closest('.week-meal-card')).toHaveClass('ready-to-eat');
    await user.click(button);

    await waitFor(() => expect(consume).toHaveBeenCalledWith([{ mealPlanId: 'made-plan', servings: 0.75 }]));
    expect(screen.getByText('¾ servings logged as eaten.')).toBeInTheDocument();
  });

  it('shows planned and actual servings separately after a meal is eaten', async () => {
    const user = userEvent.setup();
    const todayKey = currentDateKey();
    const plannedMeals = [{ ...previewPantryData.plannedMeals[0], id: 'eaten-plan', groupId: 'eaten-group', dateKey: todayKey, status: 'made' as const, plannedServings: 1.5, actualServings: 0.75, consumptionStatus: 'fulfilled' }];
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals }}><App /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: /This week/ }));
    expect(screen.getByLabelText('Planned servings for Simple Pancakes')).toHaveValue(1.5);
    expect(screen.getByText('1½ servings planned')).toBeInTheDocument();
    expect(screen.getByText('¾ servings eaten')).toBeInTheDocument();
  });

  it('checks grocery rows and updates the shopping summary', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: /Grocery list/ }));
    expect(screen.getByText('4 items left')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Onions/ }));
    expect(screen.getByText('3 items left')).toBeInTheDocument();
  });

  it('opens the retained profile and calendar surface', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: /Drew.*Routine & food profile/ }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('Food constraints')).toBeInTheDocument();
    expect(within(dialog).getByText('Google Calendar')).toBeInTheDocument();
    expect(within(dialog).getByLabelText('Allergies and intolerances')).toBeInTheDocument();
  });

  it('navigates food-log days and keeps nutrition targets aligned', async () => {
    const user = userEvent.setup();
    const { container } = render(<App />);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    const previous = screen.getByRole('button', { name: 'Previous day' });
    const next = screen.getByRole('button', { name: 'Next day' });
    expect(next).toBeDisabled();

    await user.click(previous);
    expect(container.querySelector('.date-switcher strong')).not.toHaveTextContent('Today');
    expect(next).toBeEnabled();
    expect([...container.querySelectorAll<HTMLElement>('.segment-bar b')].every((marker) => {
      const position = Number.parseFloat(marker.style.left);
      return position > 0 && position <= 100;
    })).toBe(true);

    await user.click(next);
    expect(container.querySelector('.date-switcher strong')).toHaveTextContent('Today');
    expect(next).toBeDisabled();
  });

  it('shows this week from Monday through Sunday', async () => {
    const user = userEvent.setup();
    const { container } = render(<App />);

    await user.click(screen.getByRole('button', { name: /This week/ }));
    const days = [...container.querySelectorAll('.week-row-date strong')].map((day) => day.textContent);
    expect(days).toEqual(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']);
  });

  it('submits grocery form data through the live action boundary', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('Grocery item added.');
    render(<App onSaveAction={save} />);

    await user.click(screen.getByRole('button', { name: /Grocery list/ }));
    await user.click(screen.getByRole('button', { name: 'Add item' }));
    const dialog = screen.getByRole('dialog');
    await user.type(within(dialog).getByLabelText('Item'), 'Fresh basil');
    await user.type(within(dialog).getByLabelText('Quantity'), '1 bunch');
    await user.click(within(dialog).getByRole('button', { name: 'Add item' }));

    await waitFor(() => expect(save).toHaveBeenCalledOnce());
    const [kind, form] = save.mock.calls[0] as [string, FormData];
    expect(kind).toBe('item');
    expect(form.get('name')).toBe('Fresh basil');
    expect(form.get('quantity_label')).toBe('1 bunch');
  });

  it('captures a partially consumed purchase and the remainder location', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('Purchase recorded and consumed portion logged.');
    render(<App onSaveAction={save} />);

    await user.click(screen.getByRole('button', { name: 'Products' }));
    await user.click(screen.getAllByRole('button', { name: 'Consume' })[0]);
    const dialog = screen.getByRole('dialog');
    await user.clear(within(dialog).getByLabelText('Quantity consumed now'));
    await user.type(within(dialog).getByLabelText('Quantity consumed now'), '0.5');
    await user.type(within(dialog).getByLabelText('Full price (USD)'), '4.79');
    await user.type(within(dialog).getByLabelText('You paid (USD)'), '4.79');
    await user.type(within(dialog).getByLabelText('Cost source'), 'Receipt');
    await user.selectOptions(within(dialog).getByLabelText('Remaining item location'), 'fridge');
    await user.click(within(dialog).getByRole('button', { name: 'Acquire & consume' }));

    await waitFor(() => expect(save).toHaveBeenCalledOnce());
    const [kind, form] = save.mock.calls[0] as [string, FormData];
    expect(kind).toBe('log');
    expect(form.get('purchased_quantity')).toBe('1');
    expect(form.get('consumed_quantity')).toBe('0.5');
    expect(form.get('quantity_unit')).toBe('ct');
    expect(form.get('acquisition_type')).toBe('grocery');
    expect(form.get('total_cost')).toBe('4.79');
    expect(form.get('out_of_pocket_cost')).toBe('4.79');
    expect(form.get('cost_source')).toBe('Receipt');
    expect(form.get('location')).toBe('fridge');
  });

  it('labels product history as consumed servings rather than use occasions', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Products' }));

    expect(screen.getByRole('combobox', { name: 'Sort products' })).toHaveValue('used');
    expect(screen.getByText('Consumed')).toBeInTheDocument();
    await user.click(screen.getAllByRole('button', { name: 'Open' })[0]);
    expect(within(screen.getByRole('dialog')).getByText('Servings consumed')).toBeInTheDocument();
  });

  it('logs a one-off meal without requiring a product or complete nutrition', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('Food logged without changing inventory.');
    render(<App onSaveAction={save} />);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    await user.click(screen.getByRole('button', { name: 'Log food' }));
    const dialog = screen.getByRole('dialog');
    expect(within(dialog).queryByLabelText('Product')).not.toBeInTheDocument();
    await user.type(within(dialog).getByLabelText('Meal or food'), "Spaghetti at Mom's");
    await user.type(within(dialog).getByLabelText('Portion'), '1 large plate');
    await user.type(within(dialog).getByLabelText('Calories'), '750');
    await user.click(within(dialog).getByRole('checkbox', { name: /Nutrition is estimated/ }));
    await user.click(within(dialog).getByRole('button', { name: 'Log food' }));

    await waitFor(() => expect(save).toHaveBeenCalledOnce());
    const [kind, form] = save.mock.calls[0] as [string, FormData];
    expect(kind).toBe('manual-log');
    expect(form.get('label')).toBe("Spaghetti at Mom's");
    expect(form.get('portion_label')).toBe('1 large plate');
    expect(form.get('kcal')).toBe('750');
    expect(form.get('product')).toBeNull();
  });

  it('scans and submits a barcode without the native BarcodeDetector API', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('Found Oikos · Vanilla Greek yogurt.');
    const stop = vi.fn();
    const stopTrack = vi.fn();
    const stream = { getTracks: () => [{ stop: stopTrack }] } as unknown as MediaStream;
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: vi.fn().mockResolvedValue(stream) } });
    vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
    scannerMocks.decodeFromStream.mockImplementationOnce(async (_stream, _video, callback) => {
      const controls = { stop };
      callback({ getText: () => '036632032093' }, undefined, controls);
      return controls;
    });
    render(<App onSaveAction={save} />);

    await user.click(screen.getAllByRole('button', { name: 'Look up barcode' })[0]);
    const dialog = screen.getByRole('dialog');
    await user.click(within(dialog).getByRole('button', { name: 'Enable camera' }));

    await waitFor(() => expect(within(dialog).getByLabelText('UPC / EAN')).toHaveValue('036632032093'));
    expect(within(dialog).getByText('Found 036632032093')).toBeInTheDocument();
    expect(stop).toHaveBeenCalled();

    await user.click(within(dialog).getByRole('button', { name: 'Look up' }));
    await waitFor(() => expect(save).toHaveBeenCalledOnce());
    const [kind, form] = save.mock.calls[0] as [string, FormData];
    expect(kind).toBe('scan');
    expect(form.get('barcode')).toBe('036632032093');
  });

  it('explains when Firefox denies mobile camera permission', async () => {
    const user = userEvent.setup();
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia: vi.fn().mockRejectedValue(new DOMException('Denied', 'NotAllowedError')) } });
    render(<App onSaveAction={vi.fn()} />);

    await user.click(screen.getAllByRole('button', { name: 'Look up barcode' })[0]);
    const dialog = screen.getByRole('dialog');
    await user.click(within(dialog).getByRole('button', { name: 'Enable camera' }));

    expect(await within(dialog).findByRole('status')).toHaveTextContent('Firefox blocked the camera');
    expect(within(dialog).getByRole('button', { name: 'Enable camera' })).toBeEnabled();
  });

  it('collects known package counts and unknown barcodes in the mobile bulk scanner', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('2 packages added to inventory.');
    render(<App onSaveAction={save} />);

    const scanButtons = screen.getAllByRole('button', { name: 'Look up barcode' });
    await user.click(scanButtons[scanButtons.length - 1]);
    const dialog = screen.getByRole('dialog');
    const barcode = within(dialog).getByLabelText('UPC / EAN');

    await user.type(barcode, '036632032093');
    await user.click(within(dialog).getByRole('button', { name: 'Add typed barcode' }));
    await user.type(barcode, '036632032093');
    await user.click(within(dialog).getByRole('button', { name: 'Add typed barcode' }));
    expect(within(dialog).getByLabelText('Quantity of Oikos · Vanilla Greek yogurt')).toHaveValue(2);

    await user.type(barcode, '999999999999');
    await user.click(within(dialog).getByRole('button', { name: 'Add typed barcode' }));
    expect((within(dialog).getByLabelText('Unknown barcode lookup list') as HTMLTextAreaElement).value).toContain('999999999999');

    await user.click(within(dialog).getByRole('button', { name: 'Add 2 packages' }));
    await waitFor(() => expect(save).toHaveBeenCalledOnce());
    const [kind, form] = save.mock.calls[0] as [string, FormData];
    expect(kind).toBe('bulk-import');
    expect(JSON.parse(String(form.get('entries')))).toEqual([{ productId: 'preview-product-3', packages: 2, bestBy: null }]);
    expect(within(dialog).getByLabelText('Unknown barcode lookup list')).toBeInTheDocument();
  });

  it('offers undo on a reversible action and runs the compensating call', async () => {
    const user = userEvent.setup();
    const onVoidFoodLog = vi.fn().mockResolvedValue(undefined);
    const onRestoreFoodLog = vi.fn().mockResolvedValue(undefined);
    const { container } = render(<App onVoidFoodLog={onVoidFoodLog} onRestoreFoodLog={onRestoreFoodLog} />);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    const row = container.querySelectorAll('.log-row')[0] as HTMLElement;
    await user.click(within(row).getByRole('button', { name: 'Remove Simple Pancakes' }));

    const toast = await screen.findByRole('status');
    expect(within(toast).getByText(/removed from the food log/)).toBeInTheDocument();
    expect(onVoidFoodLog).toHaveBeenCalledWith('preview-log-1');

    await user.click(within(toast).getByRole('button', { name: 'Undo' }));
    expect(onRestoreFoodLog).toHaveBeenCalledWith('preview-log-1');
  });

  it('does not offer undo on an action that cannot be reversed', async () => {
    localStorage.clear();
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getAllByRole('button', { name: 'Make batch' })[0]);
    const workspace = screen.getByRole('article', { name: 'Simple Pancakes' });
    await user.click(within(workspace).getByRole('button', { name: /all-purpose flour/i }));

    expect(screen.queryByRole('button', { name: 'Undo' })).not.toBeInTheDocument();
  });

  it('derives the history stat strip and heat strip from real logged days', async () => {
    const user = userEvent.setup();
    const { container } = render(<App />);

    await user.click(screen.getByRole('button', { name: 'History' }));

    // One cell per day in range, not one per logged day.
    expect(container.querySelectorAll('.heat-strip i')).toHaveLength(30);
    // Only the days that were actually logged are coloured.
    const lit = [...container.querySelectorAll('.heat-strip i')].filter((cell) => !(cell as HTMLElement).style.background.includes('26, 32, 30'));
    expect(lit.length).toBe(container.querySelectorAll('.history-row').length);

    const strip = container.querySelector('.stat-strip')!;
    expect(within(strip as HTMLElement).getByText('6 of 30')).toBeInTheDocument();
    // 6 logged days averaging (1180+1640+1420+1830+1290+1710)/6 = 1,512
    expect(within(strip as HTMLElement).getByText('1,512')).toBeInTheDocument();
  });

  it('keeps a separate record of what was made, stored, and left', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'History' }));

    const card = screen.getByRole('heading', { name: 'What I made' }).closest('.card') as HTMLElement;
    expect(within(card).getByText('4 servings')).toBeInTheDocument();
    expect(within(card).getAllByText('fridge')).toHaveLength(2);
    expect(within(card).getByText('2', { selector: 'strong' })).toBeInTheDocument();
  });

  it('switches Trends between nutrition and spend without making spend a macro', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getAllByRole('button', { name: 'Trends' })[0]);
    expect(screen.queryByText('Lost to waste')).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /^Spend$/ }));
    expect(screen.getByText('Lost to waste')).toBeInTheDocument();
    // The daily target line reads from the one weekly budget: 150 / 7.
    expect(screen.getByText('$21.43 a day')).toBeInTheDocument();
    // Spend is a view, not a seventh nutrient chip.
    const tabs = screen.getAllByRole('button', { name: /^Spend$/ });
    expect(tabs.every((tab) => tab.closest('.driver-tabs') === null)).toBe(true);
  });

  it('fills an over-budget cost bar and labels the overage', async () => {
    const user = userEvent.setup();
    const foodLog = [{ ...previewPantryData.foodLog[0], cost: 10.9, costIsEstimated: false }];
    const todayKey = currentDateKey();
    const data = { ...previewPantryData, foodLog, foodLogByDate: { ...previewPantryData.foodLogByDate, [todayKey]: { nutrients: previewPantryData.nutrients, foodLog, nutritionIncompleteEntries: 0 } }, settings: { ...previewPantryData.settings, weeklyFoodBudget: 70 } };
    const { container } = render(<PantryDataProvider data={data}><App /></PantryDataProvider>);

    expect(screen.getByText('$0.90 OVER')).toBeInTheDocument();
    const progress = container.querySelector('.spend-metric .progress') as HTMLElement;
    expect(progress).toHaveAttribute('data-value', '100');
    expect(progress.querySelector('span')).toHaveStyle({ width: '100%' });

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    const costRow = screen.getByText('Cost', { selector: 'strong' }).closest('.contribution-row')!;
    const costSegments = [...costRow.querySelectorAll('.segment-bar i')] as HTMLElement[];
    expect(costSegments.reduce((total, segment) => total + Number.parseFloat(segment.style.width), 0)).toBeGreaterThan(82);
    expect(costSegments.every((segment) => segment.style.maxWidth === 'none')).toBe(true);
  });

  it('shows every planned meal and every use-soon item on Today, with day arrows', async () => {
    const user = userEvent.setup();
    const todayKey = currentDateKey();
    const plannedMeals = [
      { id: 'plan-pancakes', groupId: 'plan-pancakes', dateKey: todayKey, slot: 'BREAKFAST', name: 'Simple Pancakes', emoji: '🥞', recipeId: 'pancakes', status: 'planned' as const, isLeftover: false, plannedServings: 1, consumptionStatus: 'unlogged', cost: 4.72, costIsEstimated: true },
      { id: 'plan-eggs', groupId: 'plan-eggs', dateKey: todayKey, slot: 'DINNER', name: 'Soft Scrambled Eggs', emoji: '🍳', recipeId: 'eggs', status: 'planned' as const, isLeftover: false, plannedServings: 1, consumptionStatus: 'unlogged', cost: 1.14, costIsEstimated: true },
    ];
    const data = { ...previewPantryData, plannedMeals };
    const { container } = render(<PantryDataProvider data={data}><App /></PantryDataProvider>);

    expect(container.querySelectorAll('.today-plan-row')).toHaveLength(2);
    expect(container.querySelectorAll('.soon-row')).toHaveLength(3);
    await user.click(screen.getByRole('button', { name: 'Previous day' }));
    expect(container.querySelector('.today-date-switcher strong')).not.toHaveTextContent('Today');
    expect(screen.getByRole('button', { name: 'Next day' })).toBeEnabled();
  });

  it('opens recipe composition from a planned meal and details from a consumption event', async () => {
    const user = userEvent.setup();
    const todayKey = currentDateKey();
    const data = { ...previewPantryData, plannedMeals: [{ id: 'plan-pancakes', groupId: 'plan-pancakes', dateKey: todayKey, slot: 'DINNER', name: 'Simple Pancakes', emoji: '🥞', recipeId: 'pancakes', status: 'planned' as const, isLeftover: false, plannedServings: 1, consumptionStatus: 'unlogged', cost: 4.72, costIsEstimated: true }] };
    render(<PantryDataProvider data={data}><App /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: /This week/ }));
    await user.click(screen.getByRole('button', { name: 'View Simple Pancakes details' }));
    expect(within(screen.getByRole('dialog')).getByText('INGREDIENTS')).toBeInTheDocument();
    await user.click(within(screen.getByRole('dialog')).getAllByRole('button', { name: 'Close' }).at(-1)!);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    await user.click(screen.getByRole('button', { name: 'View Simple Pancakes consumption event' }));
    const eventDialog = screen.getByRole('dialog');
    expect(within(eventDialog).getByText('Consumption event')).toBeInTheDocument();
    expect(within(eventDialog).getByText('Individual events')).toBeInTheDocument();
  });

  it('plans a pantry item from a source-first composer without duplicate close actions', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('Pantry item added to the day.');
    render(<App onSaveAction={save} />);

    await user.click(screen.getByRole('button', { name: /This week/ }));
    await user.click(screen.getByRole('button', { name: 'Add to day' }));
    const dialog = screen.getByRole('dialog', { name: 'Add to day' });
    expect(within(dialog).queryByRole('button', { name: 'Cancel' })).not.toBeInTheDocument();
    expect(within(dialog).getAllByRole('button', { name: 'Close' })).toHaveLength(1);

    await user.click(within(dialog).getByRole('tab', { name: /Pantry item/ }));
    await user.click(within(dialog).getByRole('option', { name: /Bailey's/ }));
    expect(within(dialog).getByText('147 cal')).toBeInTheDocument();
    expect(within(dialog).getAllByText('1.5 fl oz')).toHaveLength(2);
    await user.click(within(dialog).getByRole('radio', { name: /pantry · 9.3 servings/ }));
    await user.click(within(dialog).getByRole('button', { name: 'Add to day' }));

    await waitFor(() => expect(save).toHaveBeenCalledTimes(1));
    const [kind, form] = save.mock.calls[0] as [string, FormData];
    expect(kind).toBe('meal');
    expect(form.get('intent')).toBe('consume');
    expect(form.get('inventory_lot')).toBe('preview-baileys-lot');
    expect(form.get('product')).toBe('');
  });

  it('lets the Food Log try a drink before adding it to today', async () => {
    const user = userEvent.setup();
    const save = vi.fn().mockResolvedValue('Pantry item added to the day.');
    render(<App onSaveAction={save} />);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    await user.click(screen.getByRole('button', { name: /What if I ate something else/ }));
    expect(screen.getByText(/Nothing changes until you plan or log it/)).toBeInTheDocument();
    await user.click(screen.getByRole('option', { name: /Bailey's/ }));
    expect(screen.getByText(/1 serving adds 147 calories/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Log eaten now' })).toBeDisabled();
    await user.click(screen.getByRole('button', { name: 'Add to today' }));

    await waitFor(() => expect(save).toHaveBeenCalledTimes(1));
    const [, form] = save.mock.calls[0] as [string, FormData];
    expect(form.get('product')).toBe('preview-product-4');
    expect(form.get('planned_servings')).toBe('1');
  });

  it('describes history spend as an average on logged days', async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(screen.getByRole('button', { name: 'History' }));
    expect(screen.getByText(/avg \$\d+\.\d{2} on logged days/)).toBeInTheDocument();
    expect(screen.queryByText(/a logged day/)).not.toBeInTheDocument();
  });
});

describe('food cost uncertainty in Trends', () => {
  it('labels partial totals and does not claim zero waste when prices are missing', async () => {
    const user = userEvent.setup();
    const date = new Date();
    const dateKey = date.getFullYear() + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
    render(<PantryDataProvider data={{ ...previewPantryData, spendHistory: [{ dateKey, spend: 4.75, waste: 0, away: 0, spendMissingCost: 1, wasteMissingCost: 1, costIsEstimated: true }] }}><App /></PantryDataProvider>);
    await user.click(screen.getAllByRole('button', { name: 'Trends' })[0]);
    await user.click(screen.getByRole('button', { name: /^Spend$/ }));
    expect(screen.getByText(/known subtotals, not complete food costs/)).toBeInTheDocument();
    expect(screen.getAllByText('~$4.75 + unknown').length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText(/discarded items have unknown prices/)).toBeInTheDocument();
    expect(screen.queryByText(/Nothing discarded/)).not.toBeInTheDocument();
    expect(screen.getByText('Share unavailable: incomplete prices')).toBeInTheDocument();
  });
});
