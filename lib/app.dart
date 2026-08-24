import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/pantry_store.dart';
import 'pages/home_page.dart';

class PantryApp extends StatelessWidget {
  const PantryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pantry',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingPage(message: 'Checking your kitchen…');
        }
        final user = snapshot.data;
        if (user == null || user.isAnonymous) return const _SignInPage();
        return _PantrySession(key: ValueKey(user.uid), user: user);
      },
    ),
  );
}

ThemeData _theme(Brightness brightness) {
  const seed = Color(0xFFD7943B);
  final dark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
    useMaterial3: true,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF11100F)
        : const Color(0xFFF7F5EF),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF1C1A18) : const Color(0xFFFFFDF7),
    ),
    appBarTheme: dark
        ? const AppBarTheme(
            backgroundColor: Color(0xFF11100F),
            surfaceTintColor: Colors.transparent,
          )
        : null,
    navigationRailTheme: dark
        ? const NavigationRailThemeData(backgroundColor: Color(0xFF11100F))
        : null,
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      filled: dark,
      fillColor: dark ? const Color(0xFF24201C) : null,
    ),
    dividerTheme: dark
        ? const DividerThemeData(color: Color(0xFF3A342D))
        : null,
  );
}

class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  bool _working = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error.code) {
          'operation-not-allowed' =>
            'Google sign-in has not been enabled in Firebase yet.',
          'unauthorized-domain' =>
            'This website domain has not been authorized in Firebase yet.',
          'popup-closed-by-user' => 'Sign-in was cancelled.',
          _ => 'Could not sign in (${error.code}).',
        },
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not sign in. Try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🫙', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 16),
                  Text(
                    'Your kitchen, privately tracked',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Sign in with the Google account authorized for this pantry.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _working ? null : _signIn,
                      icon: _working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        _working ? 'Signing in…' : 'Continue with Google',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PantrySession extends StatefulWidget {
  const _PantrySession({super.key, required this.user});

  final User user;

  @override
  State<_PantrySession> createState() => _PantrySessionState();
}

class _PantrySessionState extends State<_PantrySession> {
  late Future<PantryStore> _future;
  PantryStore? _store;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PantryStore> _load() async {
    final store = await PantryStore.loadCloud();
    _store = store;
    return store;
  }

  void _retry() {
    _store?.dispose();
    _store = null;
    setState(() => _future = _load());
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PantryStore>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _LoadingPage(message: 'Opening your pantry…');
      }
      if (snapshot.hasError) {
        return _AccessPage(user: widget.user, onRetry: _retry);
      }
      return PantryHomePage(
        store: snapshot.requireData,
        onSignOut: FirebaseAuth.instance.signOut,
      );
    },
  );
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(message),
        ],
      ),
    ),
  );
}

class _AccessPage extends StatelessWidget {
  const _AccessPage({required this.user, required this.onRetry});

  final User user;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'This account needs pantry access',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Create a Firestore document in the app_access collection using this UID as the document ID. No password or token is needed.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    user.uid,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                      OutlinedButton.icon(
                        onPressed: FirebaseAuth.instance.signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
