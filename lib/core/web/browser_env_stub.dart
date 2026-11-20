import 'browser_env.dart';

/// Off the web, there is no browser to describe.
BrowserEnv? readBrowserEnv() => null;

/// Off the web, nothing to open it in.
void openInNewTab(String url) {}
