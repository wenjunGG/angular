import 'package:args/args.dart';
import 'package:build/build.dart' as build;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

const _argDebugMode = 'debug';
const _argProfileFor = 'profile';
const _argLegacyStyle = 'use_legacy_style_encapsulation';
const _argLegacyWhitespace = 'use_legacy_preserve_whitespace';

/// Compiler-wide configuration (flags) to allow opting in/out.
///
/// In some build environments flags are only configurable at the application
/// level, in others they occur at the package level. This class is not
/// opinionated and allows anything to be set, but has reasonable defaults set
/// with an option to use defaults set by bazel or pub's build systems.
class CompilerFlags {
  static final _argParser = new ArgParser()
    ..addFlag(
      _argDebugMode,
      defaultsTo: null,
      help: ''
          'Whether to run the code generator in debug mode. This is '
          'useful for local development but should be disabled for '
          'production builds.',
    )
    ..addFlag(
      _argLegacyStyle,
      defaultsTo: null,
      help: ''
          'Enables the use of deprecated Shadow DOM CSS selectors, and '
          'cause shadow host selectors to prevent a series of selectors '
          'from being properly scoped to their component',
    )
    ..addOption(
      _argProfileFor,
      valueHelp: '"build" or "binding"',
      defaultsTo: null,
      help: ''
          'Whether to emit additional code that may be used by tooling '
          'in order to profile performance or other runtime information.',
    )
    ..addFlag(
      _argLegacyWhitespace,
      defaultsTo: null,
      help: 'Whether to opt-in/out of the new preserveWhitespace: false',
      // It's not clear we will keep this flag through the 5.x final release.
      hide: true,
    );

  /// Whether to emit extra code suitable for testing and local development.
  final bool genDebugInfo;

  /// May emit extra code suitable for profiling or tooling.
  final Profile profileFor;

  /// Whether to opt-in to supporting a legacy mode of style encapsulation.
  ///
  /// If `true`, shadow host selectors prevent the following selectors from
  /// being scoped to their component much like a shadow piercing combinator.
  /// It also allows the use of the following _deprecated_ selectors:
  /// * `::content`
  /// * `::shadow`
  /// * polyfill-next-selector
  /// * polyfill-unscoped-rule
  final bool useLegacyStyleEncapsulation;

  /// Whether internationalization of templates is supported.
  ///
  /// This flag is currently used to disable support while the feature is
  /// developed.
  @experimental
  final bool i18nEnabled;

  /// Whether to look for a file to determine if `.template.dart` will exist.
  ///
  /// **NOTE**: This is an _internal_ flag that is currently only supported for
  /// use with the golden file testing, and may be removed at some point in the
  /// future.
  @experimental
  final bool ignoreNgPlaceholderForGoldens;

  /// Whether to use a new implementation of `preserveWhitespace: false`.
  @experimental
  final bool useNewPreserveWhitespace;

  const CompilerFlags({
    this.genDebugInfo: false,
    this.i18nEnabled: false,
    this.ignoreNgPlaceholderForGoldens: false,
    this.profileFor: Profile.none,
    this.useLegacyStyleEncapsulation: false,
    this.useNewPreserveWhitespace: true,
  });

  /// Creates flags by parsing command-line arguments.
  ///
  /// Failures are reported to [logger].
  factory CompilerFlags.parseArgs(
    List<String> args, {
    CompilerFlags defaultTo: const CompilerFlags(genDebugInfo: false),
    Logger logger,
    Level severity: Level.WARNING,
  }) {
    final results = _argParser.parse(args);
    return new CompilerFlags.parseRaw(
      results,
      defaultTo,
      logger: logger,
      severity: severity,
    );
  }

  /// Parses a raw map of flags into [CompilerFlags].
  ///
  /// Failures are reported to [logger].
  factory CompilerFlags.parseRaw(
    // Untyped because 'argResults' doesn't expose a Map interface.
    dynamic options,
    CompilerFlags defaultTo, {
    Logger logger,
    Level severity: Level.WARNING,
  }) {
    // Use the default package:build logger if not specified, otherwise throw.
    logger ??= build.log;
    void log(dynamic message) {
      if (logger == null) throw message;
      logger.log(severity, message);
    }

    // Check for invalid (unknown) arguments when possible.
    if (options is Map) {
      final knownArgs = const [
        _argDebugMode,
        _argProfileFor,
        _argLegacyStyle,
        _argLegacyWhitespace,
        // TODO(matanl): A better strategy for negatable options.
        'no-$_argLegacyWhitespace',
      ].toSet();
      final unknownArgs = options.keys.toSet().difference(knownArgs);
      if (unknownArgs.isNotEmpty) {
        final message = 'Invalid arguments passed to the transformer: \n'
            '  - ${unknownArgs.join('\n  - ')}\n\n'
            'You may be providing flags that are no longer valid or supported '
            'for AngularDart 5.x. See "compiler_flags.md" in the AngularDart '
            'repository for a list of supported flags.';
        throw new ArgumentError(message);
      }
    }

    var debugMode = options[_argDebugMode];
    if (debugMode != null && debugMode is! bool) {
      log('Invalid value "$_argDebugMode": $debugMode');
      debugMode = null;
    }
    var profileFor = options[_argProfileFor];
    if (profileFor != null && profileFor is! String) {
      log('Invalid value "$_argProfileFor": $profileFor');
      profileFor = null;
    }
    var useLegacyStyle = options[_argLegacyStyle];
    if (useLegacyStyle != null && useLegacyStyle is! bool) {
      log('Invalid value for "$_argLegacyStyle": $useLegacyStyle');
      useLegacyStyle = null;
    }
    var useLegacyWhitespace = options[_argLegacyWhitespace];
    if (useLegacyWhitespace != null && useLegacyWhitespace is! bool) {
      log('Invalid value for "$_argLegacyWhitespace": $useLegacyWhitespace');
      useLegacyWhitespace = null;
    }
    return new CompilerFlags(
      genDebugInfo: debugMode ?? defaultTo.genDebugInfo,
      profileFor: _toProfile(profileFor, log) ?? defaultTo.profileFor,
      useLegacyStyleEncapsulation:
          useLegacyStyle ?? defaultTo.useLegacyStyleEncapsulation,
      useNewPreserveWhitespace: useLegacyWhitespace != null
          ? !useLegacyWhitespace
          : defaultTo.useNewPreserveWhitespace,
    );
  }
}

/// Optional configuration for emitting additional code for profiling.
///
/// See [CompilerFlags.profileFor].
enum Profile {
  /// No profiling is enabled.
  none,

  /// Profile component view construction performance.
  build,

  /// Profile component bindings (accessed methods and getters in components).
  binding,
}

Profile _toProfile(dynamic profile, void log(dynamic message)) {
  if (profile == null) return null;
  switch (profile) {
    case '':
      return Profile.none;
    case 'build':
      return Profile.build;
    case 'binding':
      return Profile.binding;
    default:
      log('Invalid flag for "$_argProfileFor": $profile.');
      return Profile.none;
  }
}
