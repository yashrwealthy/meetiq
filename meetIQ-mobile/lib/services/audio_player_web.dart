import 'dart:html' as html;

html.AudioElement? _audioElement;

Future<void> playAudio(String url, {required void Function() onComplete}) async {
  // Stop any existing playback
  await stopAudio();
  
  // Create new audio element
  _audioElement = html.AudioElement(url);
  _audioElement!.onEnded.listen((_) {
    onComplete();
  });
  _audioElement!.onError.listen((e) {
    print('Audio error: $e');
    onComplete();
  });
  
  await _audioElement!.play();
}

Future<void> stopAudio() async {
  if (_audioElement != null) {
    _audioElement!.pause();
    _audioElement!.currentTime = 0;
    _audioElement = null;
  }
}
