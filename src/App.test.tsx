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

    expect(screen.getByText('Includes today’s planned meals')).toBeInTheDocument();
    expect(container.querySelectorAll('.nutrition-card .projection-segment')).toHaveLength(6);

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    expect(screen.getByText("Today's plan")).toBeInTheDocument();
    expect(container.querySelectorAll('.contribution-card .projection-segment').length).toBeGreaterThan(0);
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
    expect(within(workspace).getByText('INGREDIENTS')).toBeInTheDocument();
    expect(within(workspace).getByText('METHOD')).toBeInTheDocument();
    expect(within(workspace).getByText('0 of 8 complete')).toBeInTheDocument();

    await user.click(within(workspace).getByRole('button', { name: /all-purpose flour/i }));
    expect(within(workspace).getByText('1 of 8 complete')).toBeInTheDocument();
  });

  it('shows multiple recipes in a configurable, reorderable on-deck workspace', async () => {
    localStorage.clear();
    localStorage.setItem('mise.recipe-progress.pancakes', JSON.stringify(['i0']));
    localStorage.setItem('mise.recipe-progress.eggs', JSON.stringify(['i0']));
    const user = userEvent.setup();
    render(<App />);

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
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' }));

    await user.click(screen.getAllByRole('button', { name: 'Make batch' })[0]);
    await user.click(within(screen.getByRole('article', { name: 'Simple Pancakes' })).getByRole('button', { name: /all-purpose flour/i }));
    await user.click(within(screen.getByRole('navigation', { name: 'Kitchen' })).getByRole('button', { name: 'Today' }));
    expect(within(screen.getByRole('navigation', { name: 'Pinned cooking' })).getByRole('button', { name: /Simple Pancakes/ })).toBeInTheDocument();
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
    expect(screen.getByText('1.5 servings of Simple Pancakes logged as eaten.')).toBeInTheDocument();
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
    expect(screen.getByText('0.75 servings logged as eaten.')).toBeInTheDocument();
  });

  it('shows planned and actual servings separately after a meal is eaten', async () => {
    const user = userEvent.setup();
    const todayKey = currentDateKey();
    const plannedMeals = [{ ...previewPantryData.plannedMeals[0], id: 'eaten-plan', groupId: 'eaten-group', dateKey: todayKey, status: 'made' as const, plannedServings: 1.5, actualServings: 0.75, consumptionStatus: 'fulfilled' }];
    render(<PantryDataProvider data={{ ...previewPantryData, plannedMeals }}><App /></PantryDataProvider>);

    await user.click(screen.getByRole('button', { name: /This week/ }));
    expect(screen.getByLabelText('Planned servings for Simple Pancakes')).toHaveValue(1.5);
    expect(screen.getByText('servings planned')).toBeInTheDocument();
    expect(screen.getByText('0.75 eaten')).toBeInTheDocument();
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

    await user.click(screen.getByRole('button', { name: /Drew/ }));
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
    const costSegment = costRow.querySelector('.segment-bar i') as HTMLElement;
    expect(Number.parseFloat(costSegment.style.width)).toBeGreaterThan(82);
    expect(costSegment.style.maxWidth).toBe('none');
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
    expect(within(eventDialog).getByText('preview-log-1')).toBeInTheDocument();
  });

  it('describes history spend as an average on logged days', async () => {
    const user = userEvent.setup();
    render(<App />);
    await user.click(screen.getByRole('button', { name: 'History' }));
    expect(screen.getByText(/avg \$\d+\.\d{2} on logged days/)).toBeInTheDocument();
    expect(screen.queryByText(/a logged day/)).not.toBeInTheDocument();
  });
});
