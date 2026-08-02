/// WebDAV Depth header values (RFC 4918 §10.2).
enum DavDepth {
  /// Affects only the target resource.
  zero,

  /// Affects the target resource and its immediate children.
  one,

  /// Affects the target resource and all descendants.
  infinity;

  /// Value for the HTTP `Depth` header.
  String get headerValue => switch (this) {
        DavDepth.zero => '0',
        DavDepth.one => '1',
        DavDepth.infinity => 'infinity',
      };

  /// Parse a Depth header value (case-insensitive for `infinity`).
  static DavDepth? tryParse(String? value) {
    if (value == null) return null;
    return switch (value.trim().toLowerCase()) {
      '0' => DavDepth.zero,
      '1' => DavDepth.one,
      'infinity' => DavDepth.infinity,
      _ => null,
    };
  }
}
