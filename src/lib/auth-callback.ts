const CALLBACK_KEYS = ['code', 'error', 'error_code', 'error_description', 'error_uri', 'access_token', 'refresh_token', 'provider_token', 'provider_refresh_token', 'token_type', 'expires_in', 'expires_at', 'state'];

export function signInError(code?: string) {
  if (code === 'signup_disabled') return 'That Google account cannot access this private kitchen. Choose a different account and use the account already authorized for Mise.';
  if (code === 'access_denied') return 'Google sign-in was cancelled or access was denied. Try again and choose the account authorized for Mise.';
  return 'Could not complete Google sign-in. Try again and choose the account authorized for Mise.';
}

export class SignInError extends Error {}

// Read the PKCE code before removing callback material from the address bar.
// Never display provider-supplied descriptions, codes, or tokens as error text.
export function takeAuthCallback() {
  const url = new URL(window.location.href);
  const fragment = new URLSearchParams(url.hash.slice(1));
  const value = (key: string) => url.searchParams.get(key) ?? fragment.get(key);
  const code = value('code');
  const hasError = ['error', 'error_code', 'error_description'].some((key) => value(key) !== null);
  const error = hasError ? signInError(value('error_code') ?? value('error') ?? undefined) : null;
  const hasCallback = CALLBACK_KEYS.some((key) => url.searchParams.has(key) || fragment.has(key));
  if (hasCallback) {
    const hasFragmentCallback = CALLBACK_KEYS.some((key) => fragment.has(key));
    for (const key of CALLBACK_KEYS) {
      url.searchParams.delete(key);
      fragment.delete(key);
    }
    if (hasFragmentCallback) url.hash = fragment.toString();
    window.history.replaceState(window.history.state, '', `${url.pathname}${url.search}${url.hash}`);
  }
  return { code, error };
}
