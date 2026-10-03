import { StrictMode } from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { OAuthConsent } from './OAuthConsent';
import { approvedRedirect, pendingConsentKey } from './lib/oauth-consent';

const mocks = vi.hoisted(() => ({ getSession: vi.fn(), getUser: vi.fn(), exchangeCodeForSession: vi.fn(),
  signInWithOAuth: vi.fn(), getAuthorizationDetails: vi.fn(), approveAuthorization: vi.fn(), denyAuthorization: vi.fn(), rpc: vi.fn() }));
vi.mock('./lib/supabase', () => ({ isSupabaseConfigured: true, supabase: { auth: { ...mocks, oauth: mocks }, rpc: mocks.rpc } }));
const config = { ownerId: '10000000-0000-4000-8000-000000000001', clientId: '10000000-0000-4000-8000-000000000002', redirectUri: 'https://chatgpt.com/synthetic-callback' };
const authorizationId = 'synthetic-authorization-identifier';
const user = { id: config.ownerId, is_anonymous: false, email_confirmed_at: '2026-10-03T00:00:00Z' };
const details = { authorization_id: authorizationId, client: { id: config.clientId, name: 'Kitchen' }, user: { id: config.ownerId }, redirect_uri: config.redirectUri, scope: 'openid' };
const destination = `${config.redirectUri}?code=synthetic-code&state=synthetic-state`;
const redirect = vi.fn();

beforeEach(() => {
  vi.clearAllMocks(); sessionStorage.clear();
  window.history.replaceState({}, '', `/kitchen/oauth-consent.html?authorization_id=${authorizationId}`);
  mocks.getSession.mockResolvedValue({ data: { session: { user } }, error: null });
  mocks.getUser.mockResolvedValue({ data: { user }, error: null });
  mocks.rpc.mockResolvedValue({ data: true, error: null });
  mocks.getAuthorizationDetails.mockResolvedValue({ data: structuredClone(details), error: null });
  mocks.exchangeCodeForSession.mockResolvedValue({ data: { session: { user } }, error: null });
  mocks.approveAuthorization.mockResolvedValue({ data: { redirect_url: destination }, error: null });
  mocks.denyAuthorization.mockResolvedValue({ data: { redirect_url: `${config.redirectUri}?error=access_denied` }, error: null });
  mocks.signInWithOAuth.mockResolvedValue({ data: {}, error: null });
});
const mount = () => render(<StrictMode><OAuthConsent config={config} redirect={redirect} /></StrictMode>);

describe('Kitchen owner consent', () => {
  it('discloses owner authority and waits for an explicit click before approving', async () => {
    mount(); const button = await screen.findByRole('button', { name: 'Connect with owner access' });
    expect(screen.getByText(/not a read-only credential/)).toBeInTheDocument();
    expect(mocks.approveAuthorization).not.toHaveBeenCalled();
    await userEvent.click(button);
    await waitFor(() => expect(redirect).toHaveBeenCalledExactlyOnceWith(destination));
    expect(mocks.approveAuthorization).toHaveBeenCalledExactlyOnceWith(authorizationId, { skipBrowserRedirect: true });
    expect(sessionStorage.getItem(pendingConsentKey)).toBeNull();
    expect(mocks.getUser).toHaveBeenCalledTimes(2);
  });
  it('cancels without approving', async () => {
    mount(); await userEvent.click(await screen.findByRole('button', { name: 'Cancel' }));
    await waitFor(() => expect(redirect).toHaveBeenCalledWith(`${config.redirectUri}?error=access_denied`));
    expect(mocks.approveAuthorization).not.toHaveBeenCalled();
  });
  it.each([
    { ...user, id: 'other-user' }, { ...user, is_anonymous: true }, { ...user, email_confirmed_at: null },
  ])('rejects an unsuitable live owner (%j)', async (liveUser) => {
    mocks.getUser.mockResolvedValue({ data: { user: liveUser }, error: null }); mount();
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not verify');
    expect(mocks.getAuthorizationDetails).not.toHaveBeenCalled();
  });
  it('preserves the existing live-owner RPC guard', async () => {
    mocks.rpc.mockResolvedValue({ data: false, error: null }); mount();
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not verify');
    expect(mocks.getAuthorizationDetails).not.toHaveBeenCalled();
  });
  it.each([
    { ...details, client: { id: 'other-client' } }, { ...details, scope: 'openid profile' },
    { ...details, user: { id: 'other-user' } }, { ...details, redirect_uri: 'https://other.invalid/callback' },
    { ...details, authorization_id: 'other-authorization' },
  ])('rejects mismatched authorization details (%j)', async (value) => {
    mocks.getAuthorizationDetails.mockResolvedValue({ data: value, error: null }); mount();
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not verify');
    expect(mocks.approveAuthorization).not.toHaveBeenCalled();
  });
  it('rechecks the account at approval time', async () => {
    mount(); const button = await screen.findByRole('button', { name: 'Connect with owner access' });
    mocks.getUser.mockResolvedValue({ data: { user: { ...user, id: 'different-account' } }, error: null });
    await userEvent.click(button);
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not complete');
    expect(mocks.approveAuthorization).not.toHaveBeenCalled(); expect(redirect).not.toHaveBeenCalled();
  });
  it('preserves only the authorization reference through existing Google login', async () => {
    mocks.getSession.mockResolvedValue({ data: { session: null }, error: null }); mount();
    await userEvent.click(await screen.findByRole('button', { name: 'Continue with Google' }));
    expect(mocks.signInWithOAuth).toHaveBeenCalledWith({ provider: 'google', options: {
      redirectTo: `${window.location.origin}/kitchen/oauth-consent.html`, queryParams: { prompt: 'select_account' },
    } });
    expect(JSON.parse(sessionStorage.getItem(pendingConsentKey)!)).toMatchObject({ id: authorizationId });
  });
  it('handles a Google callback once under StrictMode and removes callback material', async () => {
    sessionStorage.setItem(pendingConsentKey, JSON.stringify({ id: authorizationId, createdAt: Date.now() }));
    window.history.replaceState({}, '', '/kitchen/oauth-consent.html?code=synthetic-login-code#access_token=PRIVATE_TOKEN');
    mount(); await screen.findByRole('button', { name: 'Connect with owner access' });
    expect(mocks.exchangeCodeForSession).toHaveBeenCalledExactlyOnceWith('synthetic-login-code');
    expect(window.location.search + window.location.hash).toBe('');
    expect(document.body).not.toHaveTextContent('PRIVATE_TOKEN');
  });
  it('does not follow an unapproved redirect after approval', async () => {
    mocks.approveAuthorization.mockResolvedValue({ data: { redirect_url: 'https://other.invalid/?code=PRIVATE_CODE' }, error: null });
    mount(); await userEvent.click(await screen.findByRole('button', { name: 'Connect with owner access' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Could not complete');
    expect(redirect).not.toHaveBeenCalled(); expect(document.body).not.toHaveTextContent('PRIVATE_CODE');
  });
  it('handles previously granted consent without making another approval call', async () => {
    mocks.getAuthorizationDetails.mockResolvedValue({ data: { redirect_url: destination }, error: null });
    mount(); await userEvent.click(await screen.findByRole('button', { name: 'Return to ChatGPT' }));
    await waitFor(() => expect(redirect).toHaveBeenCalledWith(destination));
    expect(mocks.approveAuthorization).not.toHaveBeenCalled();
  });
  it('fails closed when the public setup identifiers are absent', async () => {
    render(<OAuthConsent config={{ ...config, clientId: '' }} redirect={redirect} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('setup is incomplete');
    expect(mocks.getSession).not.toHaveBeenCalled();
  });
  it('rejects expired pending references and sanitizes provider errors', async () => {
    window.history.replaceState({}, '', '/kitchen/oauth-consent.html');
    sessionStorage.setItem(pendingConsentKey, JSON.stringify({ id: authorizationId, createdAt: Date.now() - 16 * 60000 }));
    mount(); expect(await screen.findByRole('alert')).toHaveTextContent('Could not verify');
    expect(mocks.getSession).not.toHaveBeenCalled();
  });
  it.each(['https://chatgpt.com.evil.invalid/synthetic-callback?code=x', 'https://chatgpt.com/other?code=x',
    'https://chatgpt.com/synthetic-callback#access_token=x', 'https://chatgpt.com/synthetic-callback?access_token=x',
    'javascript:alert(1)'])('rejects unsafe callback %s', value => {
    expect(approvedRedirect(value, config.redirectUri)).toBe(false);
  });
});
