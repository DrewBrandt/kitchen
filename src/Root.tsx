import { useCallback, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { App } from './App';
import { isSupabaseConfigured, supabase } from './lib/supabase';
import { consumePreparedLot, cookRecipe, cookRecipes, loadPantryData, logExternalProduct, rebuildShoppingFromPlan, setShoppingItemChecked, voidFoodLog } from './lib/pantry-repository';
import { savePanelAction } from './lib/pantry-actions';
import { PantryDataProvider, type PantryData } from './pantry-data';

let authBootstrap: Promise<Session | null> | undefined;

function getInitialSession() {
  authBootstrap ??= (async () => {
    const code = new URL(window.location.href).searchParams.get('code');
    if (code) {
      const { data, error } = await supabase.auth.exchangeCodeForSession(code);
      if (error) throw error;
      window.history.replaceState({}, document.title, window.location.pathname);
      return data.session;
    }
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    return data.session;
  })();
  return authBootstrap;
}

export function Root() {
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [authError, setAuthError] = useState('');

  useEffect(() => {
    void getInitialSession()
      .then(setSession)
      .catch((cause) => setAuthError(cause instanceof Error ? cause.message : 'Could not complete Google sign-in.'))
      .finally(() => setAuthReady(true));
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      setAuthReady(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  if (!isSupabaseConfigured) return <ConfigurationRequired />;
  if (!authReady) return <FullPageStatus message="Opening your pantry…" />;
  if (authError) return <FullPageStatus message={authError} action="Return to sign in" onAction={() => { window.history.replaceState({}, document.title, '/'); window.location.reload(); }} />;
  if (!session) return <Login />;
  return <AuthenticatedApp />;
}

function AuthenticatedApp() {
  const [data, setData] = useState<PantryData | null>(null);
  const [error, setError] = useState('');

  const refresh = useCallback(async () => {
    try {
      setError('');
      setData(await loadPantryData(supabase));
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load pantry data.');
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  if (error) return <FullPageStatus message={error} action="Try again" onAction={() => void refresh()} />;
  if (!data) return <FullPageStatus message="Loading inventory, recipes, and plans…" />;

  return (
    <PantryDataProvider data={data}>
      <App
        onSignOut={() => void supabase.auth.signOut()}
        onToggleGrocery={async (id, checked) => { await setShoppingItemChecked(supabase, id, checked); await refresh(); }}
        onVoidFoodLog={async (id) => { await voidFoodLog(supabase, id); await refresh(); }}
        onSaveAction={async (kind, form) => { const message = await savePanelAction(supabase, kind, form); await refresh(); return message; }}
        onLogExternal={async (id) => { await logExternalProduct(supabase, id); await refresh(); }}
        onCookRecipe={async (id) => { await cookRecipe(supabase, id); await refresh(); }}
        onCookRecipes={async (ids) => { await cookRecipes(supabase, ids); await refresh(); }}
        onConsumePrepared={async (id) => { await consumePreparedLot(supabase, id); await refresh(); }}
        onRebuildShopping={async () => { const count = await rebuildShoppingFromPlan(supabase); await refresh(); return count; }}
      />
    </PantryDataProvider>
  );
}

function Login() {
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function signInWithGoogle() {
    setBusy(true);
    setMessage('');
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.href.split(/[?#]/)[0] },
    });
    setBusy(false);
    if (error) setMessage(error.message);
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="brand auth-brand"><span className="brand-mark">🫙</span><strong>Pantry</strong></div>
        <div><div className="eyebrow">PRIVATE KITCHEN</div><h1>Welcome back</h1><p>Use your Google account to open inventory, recipes, meals, and nutrition.</p></div>
        {message && <div className="auth-error" role="alert">{message}</div>}
        <button className="button google-button" disabled={busy} onClick={() => void signInWithGoogle()}>
          <span className="google-mark" aria-hidden="true">G</span>
          {busy ? 'Opening Google…' : 'Continue with Google'}
        </button>
        <small>This private app accepts only its configured owner account.</small>
      </section>
    </main>
  );
}

function ConfigurationRequired() {
  return <FullPageStatus message="Supabase is not configured. Copy .env.example to .env.local and add the project publishable key." />;
}

function FullPageStatus({ message, action, onAction }: { message: string; action?: string; onAction?: () => void }) {
  return <main className="auth-page"><div className="auth-card"><div className="brand auth-brand"><span className="brand-mark">🫙</span><strong>Pantry</strong></div><p>{message}</p>{action && <button className="button primary" onClick={onAction}>{action}</button>}</div></main>;
}
