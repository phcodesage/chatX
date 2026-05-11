/// Data model for link preview metadata returned by the backend OG endpoint.
class LinkPreview {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;   // maps from backend "image" field
  final String? siteName;
  final String? faviconUrl; // maps from backend "favicon" field

  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    return LinkPreview(
      url: json['url'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image'] as String?,
      siteName: json['site_name'] as String?,
      faviconUrl: json['favicon'] as String?,
    );
  }

  /// Returns true when this preview represents a YouTube video.
  bool get isYouTube => siteName == 'youtube';
}
