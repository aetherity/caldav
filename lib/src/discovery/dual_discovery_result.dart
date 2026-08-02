import '../exceptions/caldav_exception.dart';
import 'discovery_result.dart';

/// Result of discovering both CalDAV and CardDAV on a shared endpoint.
///
/// Either service may fail independently; inspect [caldavError] / [carddavError]
/// and use [hasCalDav] / [hasCardDav] before accessing the nested results.
class DualDiscoveryResult {
  /// CalDAV discovery when successful.
  final DiscoveryResult? caldav;

  /// CardDAV discovery when successful.
  final CardDavDiscoveryResult? carddav;

  /// Error from CalDAV discovery, if any.
  final Object? caldavError;

  /// Error from CardDAV discovery, if any.
  final Object? carddavError;

  const DualDiscoveryResult({
    this.caldav,
    this.carddav,
    this.caldavError,
    this.carddavError,
  });

  bool get hasCalDav => caldav != null;
  bool get hasCardDav => carddav != null;

  /// True when at least one protocol discovered successfully.
  bool get hasAny => hasCalDav || hasCardDav;

  /// Throws if neither protocol was discovered.
  void ensureAny() {
    if (!hasAny) {
      final calMsg = caldavError?.toString() ?? 'not attempted';
      final cardMsg = carddavError?.toString() ?? 'not attempted';
      throw DiscoveryException(
        'Neither CalDAV nor CardDAV discovery succeeded. '
        'CalDAV: $calMsg; CardDAV: $cardMsg',
      );
    }
  }

  @override
  String toString() {
    return 'DualDiscoveryResult(hasCalDav: $hasCalDav, hasCardDav: $hasCardDav)';
  }
}
