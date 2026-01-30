// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Web - fetch blob bytes from a blob URL using the browser's XMLHttpRequest
Future<Uint8List?> fetchBlobBytes(String blobUrl) async {
  try {
    final completer = Completer<Uint8List?>();
    
    // Use XMLHttpRequest to fetch the blob as ArrayBuffer
    final xhr = html.HttpRequest();
    xhr.open('GET', blobUrl);
    xhr.responseType = 'arraybuffer';
    
    xhr.onLoad.listen((event) {
      if (xhr.status == 200 || xhr.status == 0) {  // status 0 is ok for blob URLs
        final response = xhr.response;
        if (response != null) {
          // Convert ArrayBuffer to Uint8List
          final bytes = (response as dynamic).asUint8List() as Uint8List;
          completer.complete(bytes);
        } else {
          completer.complete(null);
        }
      } else {
        print('XHR failed with status: ${xhr.status}');
        completer.complete(null);
      }
    });
    
    xhr.onError.listen((event) {
      print('XHR error fetching blob');
      completer.complete(null);
    });
    
    xhr.send();
    
    return await completer.future;
  } catch (e) {
    print('Error fetching blob bytes: $e');
    return null;
  }
}
