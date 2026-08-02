import 'dart:convert';

/// Persistence for RFC 6578 collection sync tokens.
///
/// Keys are typically absolute collection URLs (see [SyncTokenKeys]).
/// Implementations may be in-memory, JSON-backed, or app-specific
/// (SharedPreferences, secure storage, SQLite, …).
abstract class SyncTokenStore {
  /// Returns the stored token for [collectionKey], or null if none.
  Future<String?> getToken(String collectionKey);

  /// Stores [token] for [collectionKey].
  Future<void> setToken(String collectionKey, String token);

  /// Removes any token for [collectionKey].
  Future<void> removeToken(String collectionKey);

  /// Removes all tokens.
  Future<void> clear();

  /// All known collection keys (optional; default empty).
  Future<List<String>> keys() async => const [];
}

/// Canonical key helpers for collection sync tokens.
class SyncTokenKeys {
  SyncTokenKeys._();

  /// Stable key from a collection [href] (normalized string form).
  static String forHref(Uri href) {
    // Prefer absolute URLs; normalize trailing slash for collections.
    final s = href.toString();
    if (s.endsWith('/') || !href.path.contains('.')) {
      return s.endsWith('/') ? s : '$s/';
    }
    return s;
  }

  /// Key for a calendar collection.
  static String forCalendarHref(Uri href) => forHref(href);

  /// Key for an address book collection.
  static String forAddressBookHref(Uri href) => forHref(href);
}

/// In-memory [SyncTokenStore] (lost when the process exits).
class MemorySyncTokenStore implements SyncTokenStore {
  final Map<String, String> _tokens = {};

  /// Snapshot of current tokens (unmodifiable copy).
  Map<String, String> get snapshot => Map.unmodifiable(_tokens);

  @override
  Future<String?> getToken(String collectionKey) async => _tokens[collectionKey];

  @override
  Future<void> setToken(String collectionKey, String token) async {
    _tokens[collectionKey] = token;
  }

  @override
  Future<void> removeToken(String collectionKey) async {
    _tokens.remove(collectionKey);
  }

  @override
  Future<void> clear() async {
    _tokens.clear();
  }

  @override
  Future<List<String>> keys() async => _tokens.keys.toList(growable: false);
}

/// JSON-serializable token store for easy persistence by the host app.
///
/// ```dart
/// // Load
/// final store = JsonSyncTokenStore.fromJson(prefs.getString('sync') ?? '{}');
///
/// // Save after each change
/// store = JsonSyncTokenStore(
///   initial: ...,
///   onChange: (json) => prefs.setString('sync', json),
/// );
/// ```
class JsonSyncTokenStore implements SyncTokenStore {
  final Map<String, String> _tokens;

  /// Called after any mutating operation with the full JSON document.
  final void Function(String json)? onChange;

  JsonSyncTokenStore({
    Map<String, String>? initial,
    this.onChange,
  }) : _tokens = Map<String, String>.from(initial ?? {});

  /// Parse a JSON object of `collectionKey → token` strings.
  factory JsonSyncTokenStore.fromJson(
    String json, {
    void Function(String json)? onChange,
  }) {
    final decoded = jsonDecode(json);
    final map = <String, String>{};
    if (decoded is Map) {
      decoded.forEach((key, value) {
        if (key is String && value is String) {
          map[key] = value;
        }
      });
    }
    return JsonSyncTokenStore(initial: map, onChange: onChange);
  }

  /// Serialize all tokens to a JSON object string.
  String toJson() => jsonEncode(_tokens);

  /// Snapshot of current tokens.
  Map<String, String> get snapshot => Map.unmodifiable(_tokens);

  void _notify() => onChange?.call(toJson());

  @override
  Future<String?> getToken(String collectionKey) async => _tokens[collectionKey];

  @override
  Future<void> setToken(String collectionKey, String token) async {
    _tokens[collectionKey] = token;
    _notify();
  }

  @override
  Future<void> removeToken(String collectionKey) async {
    _tokens.remove(collectionKey);
    _notify();
  }

  @override
  Future<void> clear() async {
    _tokens.clear();
    _notify();
  }

  @override
  Future<List<String>> keys() async => _tokens.keys.toList(growable: false);
}
