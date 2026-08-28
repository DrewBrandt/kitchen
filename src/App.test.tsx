import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { App } from './App';

describe('Pantry web UI', () => {
  it('renders the mockup-inspired dashboard and complete navigation', () => {
    render(<App />);

    expect(screen.getByRole('heading', { name: 'Good evening, Drew' })).toBeInTheDocument();
    expect(screen.getByText('Ready to eat')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Inventory' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Grocery list/ })).toBeInTheDocument();
    expect(screen.getByText('Routine & food profile')).toBeInTheDocument();
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

  it('opens recipe detail and tracks cooking steps', async () => {
    const user = userEvent.setup();
    render(<App />);

    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getAllByRole('button', { name: 'View recipe' })[0]);

    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('INGREDIENTS')).toBeInTheDocument();
    expect(within(dialog).getByText('METHOD')).toBeInTheDocument();
    expect(within(dialog).getByText('0 of 8 complete')).toBeInTheDocument();

    await user.click(within(dialog).getByRole('button', { name: /all-purpose flour/i }));
    expect(within(dialog).getByText('1 of 8 complete')).toBeInTheDocument();
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
});
