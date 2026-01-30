import 'dart:typed_data';

/// Native (iOS/Android) - blob URLs are not used
/// This function should never be called on native platforms
Future<Uint8List?> fetchBlobBytes(String blobUrl) async {
  // On native platforms, we use file paths directly, not blob URLs
  throw UnsupportedError('fetchBlobBytes is not supported on native platforms');
}
