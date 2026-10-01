import { StrictMode } from 'react';
import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { previewPantryData } from './pantry-data';

const mocks = vi.hoisted(() => ({
  configured: true,
  getSession: vi.fn(), exchangeCodeForSession: vi.fn(), signInWithOAuth: vi.fn(), signOut: vi.fn(),
  onAuthStateChange: vi.fn(), unsubscribe: vi.fn(), loadPantryData: vi.fn(),
}));
vi.mock('./lib/supabase', () => ({
  get isSupabaseConfigured() { return mocks.configured; },
  supabase: {
    auth: mocks,
    channel: () => ({ on() { return this; }, subscribe() { return this; } }),
    removeChannel: vi.fn(),
  },
}));
vi.mock('./lib/pantry-repository', async (importOriginal) => ({
  ...await importOriginal<typeof import('./lib/pantry-repository')>(), loadPantryData: mocks.loadPantryData,
}));
vi.mock('./App', () => ({ App: (props: { ownerName: string; ownerEmail: string; ownerAvatarUrl: string; onSignOut: () => void }) =>
  <div><span>{props.ownerName}</span><span>{props.ownerEmail}</span><span>{props.ownerAvatarUrl}</span><button onClick={props.onSignOut}>Sign out</button></div>,
}));

const session = { user: { email: 'owner@example.test', user_metadata: { full_name: 'Kitchen Owner', picture: 'https://example.test/photo.png' } } };
async function renderRoot(strict = false) {
  const { Root } = await import('./Root');
  return render(strict ? <StrictMode><Root /></StrictMode> : <Root />);
}

beforeEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  mocks.configured = true;
  window.history.replaceState({}, '', '/kitchen/');
  mocks.getSession.mockResolvedValue({ data: { session: null }, error: null });
  mocks.exchangeCodeForSession.mockResolvedValue({ data: { session }, error: null });
  mocks.signInWithOAuth.mockResolvedValue({ data: {}, error: null });
  mocks.onAuthStateChange.mockReturnValue({ data: { subscription: { unsubscribe: mocks.unsubscribe } } });
  mocks.loadPantryData.mockResolvedValue(previewPantryData);
});

describe('Google sign-in recovery', () => {
  it.each(['?', '#'])('shows a safe rejected-account error from %s and removes callback material', async (separator) => {
    window.history.replaceState({}, '', `/kitchen/${separator}error=access_denied&error_code=signup_disabled&error_description=PRIVATE_DESCRIPTION&access_token=PRIVATE_TOKEN`);
    await renderRoot();
    expect(await screen.findByRole('alert')).toHaveTextContent('That Google account cannot access this private kitchen');
    expect(document.body).not.toHaveTextContent('PRIVATE_');
    expect(window.location.pathname).toBe('/kitchen/');
    expect(window.location.search + window.location.hash).toBe('');
    expect(mocks.exchangeCodeForSession).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: 'Choose a Google account' }));
    expect(mocks.signInWithOAuth).toHaveBeenCalledWith({ provider: 'google', options: {
      redirectTo: `${window.location.origin}/kitchen/`, queryParams: { prompt: 'select_account' },
    } });
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    await act(async () => mocks.onAuthStateChange.mock.calls[0][0]('SIGNED_IN', session));
    expect(await screen.findByText('owner@example.test')).toBeInTheDocument();
  });

  it('requests the chooser on ordinary sign-in and recovers from a thrown network error', async () => {
    mocks.signInWithOAuth.mockRejectedValueOnce(new Error('PRIVATE_PROVIDER_DETAILS'));
    await renderRoot();
    await userEvent.click(await screen.findByRole('button', { name: 'Continue with Google' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not complete Google sign-in');
    expect(document.body).not.toHaveTextContent('PRIVATE_PROVIDER_DETAILS');
    const retry = screen.getByRole('button', { name: 'Choose a Google account' });
    expect(retry).toBeEnabled();
    await userEvent.click(retry);
    expect(mocks.signInWithOAuth).toHaveBeenCalledTimes(2);
    expect(mocks.signInWithOAuth.mock.calls.every(([args]) => args.options.queryParams.prompt === 'select_account')).toBe(true);
  });

  it('exchanges a PKCE code once in Strict Mode, cleans tokens and preserves the site path and unrelated URL state', async () => {
    window.history.replaceState({}, '', '/kitchen/?code=test-code&view=week#provider_token=PRIVATE_TOKEN');
    await renderRoot(true);
    expect(await screen.findByText('owner@example.test')).toBeInTheDocument();
    expect(screen.getByText('https://example.test/photo.png')).toBeInTheDocument();
    expect(mocks.exchangeCodeForSession).toHaveBeenCalledExactlyOnceWith('test-code');
    expect(window.location.pathname + window.location.search + window.location.hash).toBe('/kitchen/?view=week');
  });

  it('cleans failed PKCE callbacks and offers a fresh sign-in without rendering provider errors', async () => {
    window.history.replaceState({}, '', '/kitchen/?code=expired-code');
    mocks.exchangeCodeForSession.mockResolvedValue({ data: { session: null }, error: { message: 'PRIVATE_CODE_DETAILS', code: 'bad_code_verifier' } });
    await renderRoot();
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not complete Google sign-in');
    expect(window.location.search).toBe('');
    expect(document.body).not.toHaveTextContent('PRIVATE_CODE_DETAILS');
    await userEvent.click(screen.getByRole('button', { name: 'Choose a Google account' }));
    expect(mocks.signInWithOAuth).toHaveBeenCalledTimes(1);
  });

  it('handles cancelled sign-in and returned OAuth errors safely', async () => {
    window.history.replaceState({}, '', '/kitchen/#error=access_denied&error_description=PRIVATE_CANCEL');
    mocks.signInWithOAuth.mockResolvedValue({ error: { code: 'signup_disabled', message: 'PRIVATE_RESPONSE' } });
    await renderRoot();
    expect(await screen.findByRole('alert')).toHaveTextContent('cancelled or access was denied');
    await userEvent.click(screen.getByRole('button', { name: 'Choose a Google account' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('cannot access this private kitchen');
    expect(document.body).not.toHaveTextContent('PRIVATE_');
  });

  it('retains existing sessions and returns to sign-in after sign-out', async () => {
    mocks.getSession.mockResolvedValue({ data: { session }, error: null });
    await renderRoot();
    expect(await screen.findByText('owner@example.test')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Sign out' }));
    expect(mocks.signOut).toHaveBeenCalledTimes(1);
    await act(async () => mocks.onAuthStateChange.mock.calls[0][0]('SIGNED_OUT', null));
    expect(await screen.findByRole('button', { name: 'Continue with Google' })).toBeInTheDocument();
  });

  it('does not bootstrap auth when configuration is missing', async () => {
    mocks.configured = false;
    await renderRoot();
    expect(screen.getByText(/Supabase is not configured/)).toBeInTheDocument();
    expect(mocks.getSession).not.toHaveBeenCalled();
    expect(mocks.onAuthStateChange).not.toHaveBeenCalled();
  });
});
