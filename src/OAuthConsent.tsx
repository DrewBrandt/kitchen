import { useEffect, useRef, useState } from 'react';
import type { OAuthAuthorizationDetails, Session } from '@supabase/supabase-js';
import { supabase, isSupabaseConfigured } from './lib/supabase';
import { takeAuthCallback } from './lib/auth-callback';
import { approvedRedirect, configuredConsent, pendingConsent, pendingConsentKey, validConsentDetails, type ConsentConfig } from './lib/oauth-consent';

const configuration: ConsentConfig = {
  ownerId: import.meta.env.VITE_KITCHEN_MCP_OWNER_ID ?? '',
  clientId: import.meta.env.VITE_KITCHEN_MCP_CLIENT_ID ?? '',
  redirectUri: import.meta.env.VITE_KITCHEN_MCP_REDIRECT_URI ?? '',
};
const navigate = (url: string) => window.location.assign(url);

export function OAuthConsent({ config = configuration, redirect = navigate }: {
  config?: ConsentConfig; redirect?: (url: string) => void;
}) {
  const [state, setState] = useState<'loading' | 'login' | 'consent' | 'return' | 'error'>('loading');
  const [message, setMessage] = useState('');
  const [details, setDetails] = useState<OAuthAuthorizationDetails | null>(null);
  const [returnUrl, setReturnUrl] = useState('');
  const [busy, setBusy] = useState(false);
  const id = useRef('');
  const start = useRef<Promise<Session | null> | undefined>(undefined);
  const deciding = useRef(false);
  const available = isSupabaseConfigured && configuredConsent(config);

  async function requireOwner() {
    const { data, error } = await supabase.auth.getUser();
    if (error || data.user?.id !== config.ownerId || data.user.is_anonymous !== false || !data.user.email_confirmed_at)
      throw new Error('Owner account required');
    const owner = await supabase.rpc('is_app_owner');
    if (owner.error || owner.data !== true) throw new Error('Owner session required');
  }

  useEffect(() => {
    if (!available) { setState('error'); setMessage('Mise connection setup is incomplete.'); return; }
    let active = true;
    start.current ??= (async () => {
      id.current = pendingConsent(new URL(window.location.href), sessionStorage);
      const callback = takeAuthCallback();
      if (callback.error) throw new Error('Sign-in failed');
      if (callback.code) {
        const result = await supabase.auth.exchangeCodeForSession(callback.code);
        if (result.error) throw new Error('Sign-in failed');
        return result.data.session;
      }
      const result = await supabase.auth.getSession();
      if (result.error) throw new Error('Sign-in failed');
      return result.data.session;
    })();
    void start.current.then(async session => {
      if (!active) return;
      if (!session) { setState('login'); return; }
      await requireOwner();
      if (!active) return;
      const result = await supabase.auth.oauth.getAuthorizationDetails(id.current);
      if (!active) return;
      if (result.error || !result.data) throw new Error('Authorization unavailable');
      if ('redirect_url' in result.data) {
        if (!approvedRedirect(result.data.redirect_url, config.redirectUri)) throw new Error('Unexpected redirect');
        setReturnUrl(result.data.redirect_url); setState('return');
      } else {
        if (!validConsentDetails(result.data, id.current, config)) throw new Error('Unexpected authorization');
        setDetails(result.data); setState('consent');
      }
    }).catch(() => {
      if (active) { setState('error'); setMessage('Could not verify this connection. Use the owner account and restart the connection in ChatGPT.'); }
    });
    return () => { active = false; };
  }, [available, config.ownerId, config.clientId, config.redirectUri]);

  async function signIn() {
    setBusy(true); setMessage('');
    try {
      const { error } = await supabase.auth.signInWithOAuth({ provider: 'google', options: {
        redirectTo: `${window.location.origin}${window.location.pathname}`, queryParams: { prompt: 'select_account' },
      } });
      if (error) throw error;
    } catch { setMessage('Could not start sign-in. Try again with the existing owner account.'); }
    finally { setBusy(false); }
  }

  async function decide(approve: boolean) {
    if (deciding.current) return;
    deciding.current = true; setBusy(true); setMessage('');
    try {
      await requireOwner();
      const result = approve
        ? await supabase.auth.oauth.approveAuthorization(id.current, { skipBrowserRedirect: true })
        : await supabase.auth.oauth.denyAuthorization(id.current, { skipBrowserRedirect: true });
      if (result.error || !result.data || !approvedRedirect(result.data.redirect_url, config.redirectUri)) throw new Error('Consent failed');
      sessionStorage.removeItem(pendingConsentKey);
      redirect(result.data.redirect_url);
    } catch {
      setState('error'); setMessage('Could not complete authorization. Restart the connection in ChatGPT.');
      deciding.current = false; setBusy(false);
    }
  }

  async function returnToChatGPT() {
    setBusy(true);
    try {
      await requireOwner();
      sessionStorage.removeItem(pendingConsentKey);
      redirect(returnUrl);
    } catch { setState('error'); setMessage('Owner session required. Restart the connection in ChatGPT.'); setBusy(false); }
  }

  return <main className="auth-page"><section className="auth-card">
    <div className="eyebrow">PRIVATE MISE</div><h1>Connect Mise to ChatGPT</h1>
    {state === 'loading' && <p role="status">Checking your owner account…</p>}
    {state === 'login' && <><p>Continue with the Google account you already use for Mise.</p>
      <button className="button" disabled={busy} onClick={() => void signIn()}>Continue with Google</button></>}
    {state === 'consent' && <>
      <p>Connect <strong>Mise</strong> using your verified Mise owner account.</p>
      <p>Connected tools can read your records and carry out approved recipe, plan, stock, preparation and consumption updates. Your Supabase login token can also authorize other owner operations, including account or profile changes. This is owner access, not a read-only credential.</p>
      <p>Requested identity scopes: <strong>{details?.scope}</strong>.</p>
      <button className="button" disabled={busy} onClick={() => void decide(true)}>Connect with owner access</button>
      <button className="button" disabled={busy} onClick={() => void decide(false)}>Cancel</button>
    </>}
    {state === 'return' && <><p>This connection already has your consent.</p>
      <button className="button" disabled={busy} onClick={() => void returnToChatGPT()}>Return to ChatGPT</button></>}
    {message && <p role="alert">{message}</p>}
    <a href="./">Return to Mise</a>
  </section></main>;
}
