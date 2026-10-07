// Fills in web/app_sw.js's version and file list from a finished web build
// (#34). Run after `flutter build web`:
//
//     dart run tool/stamp_service_worker.dart build/web
//
// The worker caches exactly the files listed, as one version; the version is
// a hash of their contents, so a deploy that changes nothing installs
// nothing new, and one that changes anything is picked up on the next visit.
import 'dart:convert';
import 'dart:io';

/// What the worker never caches as part of the shell.
///
/// CanvasKit comes from Google's CDN, which the worker caches separately,
/// so the local copy (37 MB of variants for every browser) is not wanted.
/// The licences are a megabyte read by almost nobody. The rest are workers
/// and build bookkeeping.
bool isShellFile(String path) {
  if (path.startsWith('canvaskit/')) return false;
  if (path.endsWith('.symbols')) return false;
  const skip = {
    'app_sw.js',
    'firebase-messaging-sw.js',
    'flutter_service_worker.js',
    '.last_build_id',
    'version.json',
    'assets/NOTICES',
  };
  return !skip.contains(path);
}

/// The shell's version: [fnv1a64] over every listed file's path and
/// contents, in order.
///
/// Not cryptographic and not meant to be: it only has to change when a
/// file does, and it keeps this script free of packages.
String shellVersion(List<({String path, List<int> bytes})> files) => fnv1a64([
  for (final f in files) ...[...utf8.encode(f.path), 0, ...f.bytes],
]);

/// FNV-1a, 64 bits, as 16 hex digits.
///
/// In two 32-bit halves rather than relying on 64-bit integers wrapping,
/// which they do on the VM this runs on but not on every platform Dart
/// compiles to.
String fnv1a64(List<int> bytes) {
  var hi = 0xcbf29ce4, lo = 0x84222325;
  for (final byte in bytes) {
    lo ^= byte;
    // Times the FNV prime 0x100000001b3, kept to 64 bits: (hi:lo) times
    // (0x100:0x1b3).
    final loMul = lo * 0x1b3;
    hi = (hi * 0x1b3 + lo * 0x100 + (loMul >> 32)) & 0xffffffff;
    lo = loMul & 0xffffffff;
  }
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return '${hex(hi)}${hex(lo)}';
}

/// The template with [version] and [paths] in place of its placeholders.
String stamp(
  String template, {
  required String version,
  required List<String> paths,
}) {
  const versionMark = "'__APP_VERSION__'";
  const shellMark = '/* __APP_SHELL__ */ []';
  if (!template.contains(versionMark) || !template.contains(shellMark)) {
    throw StateError('app_sw.js has no placeholders to fill — stamped twice?');
  }
  return template
      .replaceFirst(versionMark, "'$version'")
      .replaceFirst(
        shellMark,
        const JsonEncoder.withIndent('  ').convert(paths),
      );
}

void main(List<String> args) {
  final root = Directory(args.isEmpty ? 'build/web' : args.first);
  final worker = File('${root.path}/app_sw.js');
  if (!worker.existsSync()) {
    stderr.writeln('No ${worker.path}: build the web app first.');
    exit(1);
  }

  final files = <({String path, List<int> bytes})>[
    for (final entity in root.listSync(recursive: true))
      if (entity is File)
        if (entity.path.substring(root.path.length + 1).replaceAll(r'\', '/')
            case final path when isShellFile(path))
          (path: path, bytes: entity.readAsBytesSync()),
  ]..sort((a, b) => a.path.compareTo(b.path));

  final version = shellVersion(files);
  final paths = [for (final f in files) f.path];
  worker.writeAsStringSync(
    stamp(worker.readAsStringSync(), version: version, paths: paths),
  );
  final kb = files.fold<int>(0, (sum, f) => sum + f.bytes.length) ~/ 1024;
  stdout.writeln(
    'app_sw.js: version $version, ${paths.length} files, $kb KB to cache.',
  );
}
