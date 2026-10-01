import { mutationError } from './lib/mutation-feedback';
import { useCallback, useEffect, useRef, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { App } from './App';
import { isSupabaseConfigured, supabase } from './lib/supabase';
import { consumeInventoryLot, consumePlannedMeals, consumePreparedLot, cookRecipe, cookRecipes, loadPantryData, rebuildShoppingFromPlan, removePlannedMeals, removeShoppingItem, restoreFoodLog, savePrepFeedback, setInventoryLotQuantity, setPlannedConsumptionServings, setShoppingItemChecked, undoInventoryAdjustment, undoPrep, voidFoodLog } from './lib/pantry-repository';
import { savePanelAction } from './lib/pantry-actions';
import { PantryDataProvider, previewPantryData, type PantryData } from './pantry-data';
import { SignInError, signInError, takeAuthCallback } from './lib/auth-callback';

let authBootstrap: Promise<Session | null> | undefined;

function getInitialSession() {
  authBootstrap ??= (async () => {
    const { code, error: callbackError } = takeAuthCallback();
    if (callbackError) throw new SignInError(callbackError);
    if (code) {
      const { data, error } = await supabase.auth.exchangeCodeForSession(code);
      if (error) throw new SignInError(signInError(error.code));
      return data.session;
    }
    const { data, error } = await supabase.auth.getSession();
    if (error) throw new SignInError(signInError(error.code));
    return data.session;
  })();
  return authBootstrap;
}

export function Root() {
  const [session, setSession] = useState<Session | null>(null);
  const [authReady, setAuthReady] = useState(false);
  const [authError, setAuthError] = useState('');
  const preview = import.meta.env.DEV && new URL(window.location.href).searchParams.has('preview');

  useEffect(() => {
    if (preview || !isSupabaseConfigured) { setAuthReady(true); return; }
    void getInitialSession()
      .then(setSession)
      .catch((cause) => setAuthError(cause instanceof SignInError ? cause.message : signInError()))
      .finally(() => setAuthReady(true));
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (nextSession) setAuthError('');
      setAuthReady(true);
    });
    return () => data.subscription.unsubscribe();
  }, [preview]);

  if (preview) return <PantryDataProvider data={previewPantryData}><App /></PantryDataProvider>;
  if (!isSupabaseConfigured) return <ConfigurationRequired />;
  if (!authReady) return <FullPageStatus message="Opening Mise…" />;
  if (authError || !session) return <Login initialMessage={authError} />;
  return <AuthenticatedApp session={session} />;
}

function AuthenticatedApp({ session }: { session: Session }) {
  const [data, setData] = useState<PantryData | null>(null);
  const [error, setError] = useState('');
  const [syncStatus, setSyncStatus] = useState<'connecting' | 'synced' | 'error'>('connecting');

  const refreshVersion = useRef(0);
  const refresh = useCallback(async () => {
    const version = ++refreshVersion.current;
    try {
      setError('');
      const next = await loadPantryData(supabase);
      if (version !== refreshVersion.current) return;
      setData(next);
      setSyncStatus('synced');
    } catch (cause) {
      if (version !== refreshVersion.current) return;
      setError(mutationError(cause, 'Could not load pantry data.'));
      setSyncStatus('error');
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    let refreshTimer: number | undefined;
    const scheduleRefresh = () => {
      window.clearTimeout(refreshTimer);
      refreshTimer = window.setTimeout(() => void refresh(), 150);
    };
    const refreshWhenVisible = () => { if (document.visibilityState === 'visible') scheduleRefresh(); };
    const channel = supabase.channel('pantry-live-data')
      .on('postgres_changes', { event: '*', schema: 'public' }, scheduleRefresh)
      .subscribe((status) => setSyncStatus(status === 'SUBSCRIBED' ? 'synced' : status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' ? 'error' : 'connecting'));
    window.addEventListener('focus', scheduleRefresh);
    document.addEventListener('visibilitychange', refreshWhenVisible);
    return () => {
      window.clearTimeout(refreshTimer);
      window.removeEventListener('focus', scheduleRefresh);
      document.removeEventListener('visibilitychange', refreshWhenVisible);
      void supabase.removeChannel(channel);
    };
  }, [refresh]);

  if (error && !data) return <FullPageStatus message={error} action="Try again" onAction={() => void refresh()} />;
  if (!data) return <FullPageStatus message="Loading inventory, recipes, and plans…" />;

  return (
    <PantryDataProvider data={data}>
      {error && <div role="alert">The latest pantry data could not be loaded. Completed saves are retained. <button onClick={() => void refresh()}>Refresh data</button></div>}
      <App
        ownerName={String(session.user.user_metadata.full_name ?? session.user.user_metadata.name ?? session.user.email?.split('@')[0] ?? 'Drew').split(' ')[0]}
        ownerEmail={session.user.email}
        ownerAvatarUrl={session.user.user_metadata.avatar_url ?? session.user.user_metadata.picture}
        syncStatus={syncStatus}
        onSignOut={() => void supabase.auth.signOut()}
        onToggleGrocery={async (id, checked) => { await setShoppingItemChecked(supabase, id, checked); await refresh(); }}
        onVoidFoodLog={async (id) => { await voidFoodLog(supabase, id); await refresh(); }}
        onSaveAction={async (kind, form) => { const message = await savePanelAction(supabase, kind, form); await refresh(); return message; }}
        onCookRecipe={async (id, options) => { const result = await cookRecipe(supabase, id, options); await refresh(); return result; }}
        onSavePrepFeedback={async (prepId, ease, taste, minutes) => { await savePrepFeedback(supabase, prepId, ease, taste, minutes); await refresh(); }}
        onCookRecipes={async (ids) => { await cookRecipes(supabase, ids); await refresh(); }}
        onConsumePrepared={async (id, quantity) => { const logId = await consumePreparedLot(supabase, id, quantity); await refresh(); return logId; }}
        onConsumePlannedMeals={async (consumptions) => { const logIds = await consumePlannedMeals(supabase, consumptions); await refresh(); return logIds; }}
        onRebuildShopping={async () => { const count = await rebuildShoppingFromPlan(supabase); await refresh(); return count; }}
        onRemovePlannedMeals={async (ids) => { await removePlannedMeals(supabase, ids); await refresh(); }}
        onSetPlannedConsumptionServings={async (id, servings) => { await setPlannedConsumptionServings(supabase, id, servings); await refresh(); }}
        onRemoveGrocery={async (id) => { await removeShoppingItem(supabase, id); await refresh(); }}
        onConsumeInventoryLot={async (id, quantity) => { const logId = await consumeInventoryLot(supabase, id, quantity); await refresh(); return logId; }}
        onSetInventoryLotQuantity={async (id, remaining, discard) => { const eventId = await setInventoryLotQuantity(supabase, id, remaining, discard); await refresh(); return eventId; }}
        onRestoreFoodLog={async (id) => { await restoreFoodLog(supabase, id); await refresh(); }}
        onUndoInventoryAdjustment={async (eventId) => { await undoInventoryAdjustment(supabase, eventId); await refresh(); }}
        onUndoPrep={async (prepId) => { await undoPrep(supabase, prepId); await refresh(); }}
      />
    </PantryDataProvider>
  );
}

function Login({ initialMessage = '' }: { initialMessage?: string }) {
  const [message, setMessage] = useState(initialMessage);
  const [busy, setBusy] = useState(false);
  useEffect(() => setMessage(initialMessage), [initialMessage]);

  async function signInWithGoogle() {
    setBusy(true);
    setMessage('');
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: window.location.href.split(/[?#]/)[0],
          queryParams: { prompt: 'select_account' },
        },
      });
      if (error) setMessage(signInError(error.code));
    } catch {
      setMessage(signInError());
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="brand auth-brand"><span className="brand-mark">🫙</span><strong>Mise</strong></div>
        <div><div className="eyebrow">PRIVATE KITCHEN</div><h1>Welcome back</h1><p>Use your Google account to open inventory, recipes, meals, and nutrition.</p></div>
        {message && <div className="auth-error" role="alert">{message}</div>}
        <button className="button google-button" disabled={busy} onClick={() => void signInWithGoogle()}>
          <span className="google-mark" aria-hidden="true">G</span>
          {busy ? 'Opening Google…' : message ? 'Choose a Google account' : 'Continue with Google'}
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
  return <main className="auth-page"><div className="auth-card"><div className="brand auth-brand"><span className="brand-mark">🫙</span><strong>Mise</strong></div><p>{message}</p>{action && <button className="button primary" onClick={onAction}>{action}</button>}</div></main>;
}
