class SharedOutfit {
  final String id;
  final String userId;
  final String username;
  final String imageUrl;
  final String? description;
  final List<String> tags;
  final int likes;
  final bool isLikedByMe;
  final DateTime createdAt;
  final bool faceBlurred;

  SharedOutfit({
    required this.id,
    required this.userId,
    required this.username,
    required this.imageUrl,
    this.description,
    this.tags = const [],
    this.likes = 0,
    this.isLikedByMe = false,
    required this.createdAt,
    this.faceBlurred = false,
  });

  factory SharedOutfit.fromJson(Map<String, dynamic> json, {bool isLikedByMe = false}) {
    return SharedOutfit(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? 'Anonymous',
      imageUrl: json['image_url'] as String,
      description: json['description'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      likes: json['likes'] as int? ?? 0,
      isLikedByMe: isLikedByMe,
      createdAt: DateTime.parse(json['created_at'] as String),
      faceBlurred: json['face_blurred'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'username': username,
    'image_url': imageUrl,
    'description': description,
    'tags': tags,
    'likes': likes,
    'created_at': createdAt.toIso8601String(),
    'face_blurred': faceBlurred,
  };

  SharedOutfit copyWith({
    String? id,
    String? userId,
    String? username,
    String? imageUrl,
    String? description,
    List<String>? tags,
    int? likes,
    bool? isLikedByMe,
    DateTime? createdAt,
    bool? faceBlurred,
  }) {
    return SharedOutfit(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      likes: likes ?? this.likes,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      createdAt: createdAt ?? this.createdAt,
      faceBlurred: faceBlurred ?? this.faceBlurred,
    );
  }
}
