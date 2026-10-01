import { fireEvent, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { App } from './App';
import { MobileAccount } from './MobileAccount';

describe('mobile account access', () => {
  it('places the account control in the page header outside the desktop sidebar', () => {
    const { container } = render(<App ownerName="Owner" ownerEmail="owner@example.test" ownerAvatarUrl="https://example.test/photo.png" />);
    const header = within(container.querySelector('.page-header')! as HTMLElement);
    expect(header.getByRole('button', { name: 'Account: owner@example.test' })).toHaveAttribute('aria-expanded', 'false');
    expect(header.getByRole('img', { name: "Owner's Google profile photo" })).toBeInTheDocument();
    expect(header.getByRole('button', { name: 'Account: owner@example.test' }).closest('.mobile-account')).not.toBeNull();
  });

  it('reveals the full identity and allows sign-out', async () => {
    const onSignOut = vi.fn();
    render(<MobileAccount name="Owner" email="long-account-name@example.test" onProfile={vi.fn()} onSignOut={onSignOut} />);
    await userEvent.click(screen.getByRole('button', { name: 'Account: long-account-name@example.test' }));
    const account = screen.getByRole('group', { name: 'Signed-in account' });
    expect(within(account).getByText('long-account-name@example.test')).toBeVisible();
    await userEvent.click(within(account).getByRole('button', { name: 'Sign out' }));
    expect(onSignOut).toHaveBeenCalledOnce();
    expect(screen.queryByRole('group')).not.toBeInTheDocument();
  });

  it('opens the profile and dismisses with Escape or an outside press', async () => {
    const onProfile = vi.fn();
    render(<MobileAccount name="Owner" onProfile={onProfile} />);
    const toggle = screen.getByRole('button', { name: 'Account: Owner' });
    await userEvent.click(toggle);
    await userEvent.keyboard('{Escape}');
    expect(toggle).toHaveFocus();
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(toggle);
    fireEvent.pointerDown(document.body);
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(toggle);
    await userEvent.click(screen.getByRole('button', { name: 'Routine & food profile' }));
    expect(onProfile).toHaveBeenCalledOnce();
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
  });

  it('retains account access when the photo fails', async () => {
    render(<MobileAccount name="Kitchen Owner" email="owner@example.test" photo="https://example.test/broken.png" onProfile={vi.fn()} />);
    fireEvent.error(screen.getByRole('img'));
    expect(screen.getByText('KO')).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: 'Account: owner@example.test' }));
    expect(screen.getByText('owner@example.test')).toBeVisible();
  });
});
