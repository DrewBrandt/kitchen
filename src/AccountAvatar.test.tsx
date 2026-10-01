import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { AccountAvatar } from './AccountAvatar';
import { App } from './App';

describe('signed-in account identity', () => {
  it('shows the photo and accessible email in the existing account control', () => {
    render(<App ownerName="Kitchen Owner" ownerEmail="owner@example.test" ownerAvatarUrl="https://example.test/photo.png" />);
    expect(screen.getByRole('img', { name: "Kitchen Owner's Google profile photo" })).toHaveAttribute('src', 'https://example.test/photo.png');
    expect(screen.getByRole('button', { name: 'Kitchen Owner (owner@example.test) — Routine & food profile' })).toHaveAttribute('title', 'Signed in as owner@example.test');
    expect(screen.getByText('owner@example.test')).toBeVisible();
  });

  it('falls back to initials for a broken photo and retries a changed account photo', () => {
    const { rerender } = render(<AccountAvatar name="Kitchen Owner" url="https://example.test/broken.png" />);
    fireEvent.error(screen.getByRole('img'));
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
    expect(screen.getByText('KO')).toBeVisible();
    rerender(<AccountAvatar name="Other Owner" url="https://example.test/other.png" />);
    expect(screen.getByRole('img', { name: "Other Owner's Google profile photo" })).toHaveAttribute('src', 'https://example.test/other.png');
  });

  it.each([undefined, '', 'not-a-url', 'javascript:alert(1)', 'http://example.test/photo.png'])('uses initials when the photo is missing or invalid: %s', (url) => {
    render(<AccountAvatar name="Kitchen Owner" url={url} />);
    expect(screen.queryByRole('img')).not.toBeInTheDocument();
    expect(screen.getByText('KO')).toBeVisible();
  });
});
