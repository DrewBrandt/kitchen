import 'package:web/web.dart' as web;

bool get shouldUseGoogleRedirect =>
    web.window.location.hostname == 'pantry-tracker-4bc45.web.app';
