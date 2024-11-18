class AudioBook {
  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String audioUrl;
  final Duration duration;
  Duration position;

  AudioBook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.audioUrl,
    required this.duration,
    this.position = Duration.zero,
  });
}
