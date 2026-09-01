import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { App, greetingFor } from './App';

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
    expect(screen.getByText(/~\$4\.72 batch · ~\$1\.18\/serving/)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Food log' }));
    expect(screen.getByText(/~\$13\.25 total/)).toBeInTheDocument();
    expect(screen.getByText('~$8.49')).toBeInTheDocument();
  });

  it('opens recipe detail and tracks cooking steps', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getAllByRole('button', { name: 'Make batch' })[0]);

    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('INGREDIENTS')).toBeInTheDocument();
    expect(within(dialog).getByText('METHOD')).toBeInTheDocument();
    expect(within(dialog).getByText('0 of 8 complete')).toBeInTheDocument();

    await user.click(within(dialog).getByRole('button', { name: /all-purpose flour/i }));
    expect(within(dialog).getByText('1 of 8 complete')).toBeInTheDocument();
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
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /all-purpose flour/i }));
    await user.click(within(screen.getByRole('dialog')).getAllByRole('button', { name: 'Close' }).at(-1)!);
    expect(within(screen.getByRole('navigation', { name: 'Pinned cooking' })).getByRole('button', { name: /Simple Pancakes/ })).toBeInTheDocument();
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
    const days = [...container.querySelectorAll('.week-date strong')].map((day) => day.textContent);
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
});
