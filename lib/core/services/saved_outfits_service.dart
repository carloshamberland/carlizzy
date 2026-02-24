import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'supabase_service.dart';

const _uuid = Uuid();
const String _cloudSyncEnabledKey = 'cloud_sync_enabled';
const String _cloudSyncAskedKey = 'cloud_sync_asked';

/// Model for a saved outfit (generated result)
class SavedOutfit {
  final String id;
  final String imagePath;
  final DateTime createdAt;
  final String? description;
  final bool isSynced;
  final bool isFavorite;

  SavedOutfit({
    required this.id,
    required this.imagePath,
    required this.createdAt,
    this.description,
    this.isSynced = false,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'createdAt': createdAt.toIso8601String(),
        'description': description,
        'isSynced': isSynced,
        'isFavorite': isFavorite,
      };

  factory SavedOutfit.fromJson(Map<String, dynamic> json) => SavedOutfit(
        id: json['id'] as String,
        imagePath: json['imagePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        description: json['description'] as String?,
        isSynced: json['isSynced'] as bool? ?? false,
        isFavorite: json['isFavorite'] as bool? ?? false,
      );

  SavedOutfit copyWith({bool? isSynced, String? imagePath, bool? isFavorite}) => SavedOutfit(
        id: id,
        imagePath: imagePath ?? this.imagePath,
        createdAt: createdAt,
        description: description,
        isSynced: isSynced ?? this.isSynced,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}

/// Model for a saved article (individual clothing item)
class SavedArticle {
  final String id;
  final String imagePath;
  final String category; // 'tops', 'bottoms', 'dresses'
  final DateTime createdAt;
  final String? description;
  final bool isSynced;
  final bool isFavorite;

  SavedArticle({
    required this.id,
    required this.imagePath,
    required this.category,
    required this.createdAt,
    this.description,
    this.isSynced = false,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'description': description,
        'isSynced': isSynced,
        'isFavorite': isFavorite,
      };

  factory SavedArticle.fromJson(Map<String, dynamic> json) => SavedArticle(
        id: json['id'] as String,
        imagePath: json['imagePath'] as String,
        category: json['category'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        description: json['description'] as String?,
        isSynced: json['isSynced'] as bool? ?? false,
        isFavorite: json['isFavorite'] as bool? ?? false,
      );

  SavedArticle copyWith({bool? isSynced, String? imagePath, bool? isFavorite}) => SavedArticle(
        id: id,
        imagePath: imagePath ?? this.imagePath,
        category: category,
        createdAt: createdAt,
        description: description,
        isSynced: isSynced ?? this.isSynced,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}

/// Service for saving and managing outfits and articles
/// Uses Supabase for cloud sync with local cache fallback
class SavedOutfitsService {
  static const String _outfitsKey = 'saved_outfits';
  static const String _articlesKey = 'saved_articles';
  static SavedOutfitsService? _instance;
  static SharedPreferences? _prefs;

  SavedOutfitsService._();

  static Future<SavedOutfitsService> getInstance() async {
    if (_instance == null) {
      _instance = SavedOutfitsService._();
      _prefs = await SharedPreferences.getInstance();
    } else {
      // Refresh prefs in case they were updated
      _prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Reset the singleton instance (call on logout)
  static void reset() {
    _instance = null;
    _prefs = null;
  }

  // ==================== OUTFITS ====================

  Future<Directory> _getOutfitsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final outfitsDir = Directory('${appDir.path}/saved_outfits');
    if (!await outfitsDir.exists()) {
      await outfitsDir.create(recursive: true);
    }
    return outfitsDir;
  }

  Future<SavedOutfit> saveOutfitFromUrl(String imageUrl, {String? description}) async {
    final dio = Dio();
    final outfitsDir = await _getOutfitsDirectory();
    final id = _uuid.v4();
    final fileName = 'outfit_$id.jpg';
    final filePath = '${outfitsDir.path}/$fileName';

    // Download locally first
    await dio.download(imageUrl, filePath);

    final outfit = SavedOutfit(
      id: id,
      imagePath: filePath,
      createdAt: DateTime.now(),
      description: description,
      isSynced: false,
    );

    // Save to local cache
    await _addOutfitToPrefs(outfit);

    // Auto-sync if enabled
    if (SupabaseService.isAuthenticated && await isAutoSyncEnabled()) {
      await _syncOutfitToCloud(outfit);
    }

    return outfit;
  }

  Future<void> _syncOutfitToCloud(SavedOutfit outfit) async {
    await syncSingleOutfit(outfit.id);
  }

  /// Sync a single outfit by ID - can be called from UI
  Future<bool> syncSingleOutfit(String outfitId) async {
    try {
      final userId = SupabaseService.currentUserId;
      if (userId == null) return false;

      final outfits = await _getLocalOutfits();
      final outfit = outfits.firstWhere((o) => o.id == outfitId, orElse: () => throw Exception('Outfit not found'));

      final file = File(outfit.imagePath);
      final storagePath = '$userId/${outfit.id}.jpg';

      // Upload image to storage
      await SupabaseService.uploadFile(
        bucket: 'outfits',
        path: storagePath,
        file: file,
      );

      // Save metadata to database
      await SupabaseService.client.from('outfits').upsert({
        'id': outfit.id,
        'user_id': userId,
        'image_path': storagePath,
        'description': outfit.description,
        'created_at': outfit.createdAt.toIso8601String(),
      });

      // Update local record as synced
      final updatedOutfits = outfits.map((o) {
        if (o.id == outfit.id) {
          return o.copyWith(isSynced: true);
        }
        return o;
      }).toList();
      await _saveOutfitsToPrefs(updatedOutfits);
      return true;
    } catch (e) {
      print('Failed to sync outfit: $e');
      return false;
    }
  }

  Future<List<SavedOutfit>> getSavedOutfits() async {
    // First get local outfits
    final localOutfits = await _getLocalOutfits();

    // If authenticated, merge with cloud data
    if (SupabaseService.isAuthenticated) {
      try {
        final cloudOutfits = await _getCloudOutfits();
        return _mergeOutfits(localOutfits, cloudOutfits);
      } catch (e) {
        print('Failed to fetch cloud outfits: $e');
      }
    }

    return localOutfits;
  }

  Future<List<SavedOutfit>> _getLocalOutfits() async {
    final jsonString = _prefs?.getString(_outfitsKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = jsonDecode(jsonString);
    final outfits = jsonList
        .map((json) => SavedOutfit.fromJson(json as Map<String, dynamic>))
        .toList();

    final validOutfits = <SavedOutfit>[];
    for (final outfit in outfits) {
      if (await File(outfit.imagePath).exists()) {
        validOutfits.add(outfit);
      }
    }

    // Sort: favorites first, then by date
    validOutfits.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return validOutfits;
  }

  Future<List<SavedOutfit>> _getCloudOutfits() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return [];

    final response = await SupabaseService.client
        .from('outfits')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final outfits = <SavedOutfit>[];
    for (final row in response) {
      final signedUrl = await SupabaseService.getSignedUrl(
        bucket: 'outfits',
        path: row['image_path'],
      );
      outfits.add(SavedOutfit(
        id: row['id'],
        imagePath: signedUrl,
        createdAt: DateTime.parse(row['created_at']),
        description: row['description'],
        isSynced: true,
      ));
    }
    return outfits;
  }

  List<SavedOutfit> _mergeOutfits(List<SavedOutfit> local, List<SavedOutfit> cloud) {
    final merged = <String, SavedOutfit>{};

    // Add cloud outfits first
    for (final outfit in cloud) {
      merged[outfit.id] = outfit;
    }

    // Override with local (or add if not in cloud)
    for (final outfit in local) {
      if (!merged.containsKey(outfit.id)) {
        merged[outfit.id] = outfit;
      }
    }

    final result = merged.values.toList();
    // Sort: favorites first, then by date
    result.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  Future<void> deleteOutfit(String id) async {
    final outfits = await _getLocalOutfits();
    final outfit = outfits.firstWhere((o) => o.id == id, orElse: () => throw Exception('Outfit not found'));

    // Delete local file
    final file = File(outfit.imagePath);
    if (await file.exists()) {
      await file.delete();
    }

    // Delete from cloud if authenticated
    if (SupabaseService.isAuthenticated) {
      try {
        final userId = SupabaseService.currentUserId;
        await SupabaseService.deleteFile(
          bucket: 'outfits',
          path: '$userId/$id.jpg',
        );
        await SupabaseService.client.from('outfits').delete().eq('id', id);
      } catch (e) {
        print('Failed to delete from cloud: $e');
      }
    }

    final updatedOutfits = outfits.where((o) => o.id != id).toList();
    await _saveOutfitsToPrefs(updatedOutfits);
  }

  Future<void> _addOutfitToPrefs(SavedOutfit outfit) async {
    final outfits = await _getLocalOutfits();
    outfits.insert(0, outfit);
    await _saveOutfitsToPrefs(outfits);
  }

  Future<void> _saveOutfitsToPrefs(List<SavedOutfit> outfits) async {
    final jsonList = outfits.map((o) => o.toJson()).toList();
    await _prefs?.setString(_outfitsKey, jsonEncode(jsonList));
  }

  Future<void> toggleOutfitFavorite(String id) async {
    final outfits = await _getLocalOutfits();
    final updatedOutfits = outfits.map((o) {
      if (o.id == id) {
        return o.copyWith(isFavorite: !o.isFavorite);
      }
      return o;
    }).toList();
    await _saveOutfitsToPrefs(updatedOutfits);
  }

  // ==================== ARTICLES ====================

  Future<Directory> _getArticlesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final articlesDir = Directory('${appDir.path}/saved_articles');
    if (!await articlesDir.exists()) {
      await articlesDir.create(recursive: true);
    }
    return articlesDir;
  }

  Future<SavedArticle> saveArticleFromUrl(
    String imageUrl, {
    required String category,
    String? description,
  }) async {
    final dio = Dio();
    final articlesDir = await _getArticlesDirectory();
    final id = _uuid.v4();
    final fileName = 'article_${category}_$id.jpg';
    final filePath = '${articlesDir.path}/$fileName';

    await dio.download(imageUrl, filePath);

    final article = SavedArticle(
      id: id,
      imagePath: filePath,
      category: category,
      createdAt: DateTime.now(),
      description: description,
      isSynced: false,
    );

    await _addArticleToPrefs(article);

    // Auto-sync if enabled
    if (SupabaseService.isAuthenticated && await isAutoSyncEnabled()) {
      await _syncArticleToCloud(article);
    }

    return article;
  }

  Future<SavedArticle> saveArticleFromFile(
    File imageFile, {
    required String category,
    String? description,
  }) async {
    final articlesDir = await _getArticlesDirectory();
    final id = _uuid.v4();
    final fileName = 'article_${category}_$id.jpg';
    final filePath = '${articlesDir.path}/$fileName';

    await imageFile.copy(filePath);

    final article = SavedArticle(
      id: id,
      imagePath: filePath,
      category: category,
      createdAt: DateTime.now(),
      description: description,
      isSynced: false,
    );

    await _addArticleToPrefs(article);

    // Auto-sync if enabled
    if (SupabaseService.isAuthenticated && await isAutoSyncEnabled()) {
      await _syncArticleToCloud(article);
    }

    return article;
  }

  Future<void> _syncArticleToCloud(SavedArticle article) async {
    await syncSingleArticle(article.id);
  }

  /// Sync a single article by ID - can be called from UI
  Future<bool> syncSingleArticle(String articleId) async {
    try {
      final userId = SupabaseService.currentUserId;
      if (userId == null) return false;

      final articles = await _getLocalArticles();
      final article = articles.firstWhere((a) => a.id == articleId, orElse: () => throw Exception('Article not found'));

      final file = File(article.imagePath);
      final storagePath = '$userId/${article.id}.jpg';

      await SupabaseService.uploadFile(
        bucket: 'articles',
        path: storagePath,
        file: file,
      );

      await SupabaseService.client.from('articles').upsert({
        'id': article.id,
        'user_id': userId,
        'image_path': storagePath,
        'category': article.category,
        'description': article.description,
        'created_at': article.createdAt.toIso8601String(),
      });

      final updatedArticles = articles.map((a) {
        if (a.id == article.id) {
          return a.copyWith(isSynced: true);
        }
        return a;
      }).toList();
      await _saveArticlesToPrefs(updatedArticles);
      return true;
    } catch (e) {
      print('Failed to sync article: $e');
      return false;
    }
  }

  Future<List<SavedArticle>> getSavedArticles({String? category}) async {
    final localArticles = await _getLocalArticles(category: category);

    if (SupabaseService.isAuthenticated) {
      try {
        final cloudArticles = await _getCloudArticles(category: category);
        return _mergeArticles(localArticles, cloudArticles);
      } catch (e) {
        print('Failed to fetch cloud articles: $e');
      }
    }

    return localArticles;
  }

  Future<List<SavedArticle>> _getLocalArticles({String? category}) async {
    final jsonString = _prefs?.getString(_articlesKey);
    if (jsonString == null) return [];

    final List<dynamic> jsonList = jsonDecode(jsonString);
    final articles = jsonList
        .map((json) => SavedArticle.fromJson(json as Map<String, dynamic>))
        .toList();

    final validArticles = <SavedArticle>[];
    for (final article in articles) {
      if (await File(article.imagePath).exists()) {
        if (category == null || article.category == category) {
          validArticles.add(article);
        }
      }
    }

    // Sort: favorites first, then by date
    validArticles.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return validArticles;
  }

  Future<List<SavedArticle>> _getCloudArticles({String? category}) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return [];

    var query = SupabaseService.client
        .from('articles')
        .select()
        .eq('user_id', userId);

    if (category != null) {
      query = query.eq('category', category);
    }

    final response = await query.order('created_at', ascending: false);

    final articles = <SavedArticle>[];
    for (final row in response) {
      final signedUrl = await SupabaseService.getSignedUrl(
        bucket: 'articles',
        path: row['image_path'],
      );
      articles.add(SavedArticle(
        id: row['id'],
        imagePath: signedUrl,
        category: row['category'],
        createdAt: DateTime.parse(row['created_at']),
        description: row['description'],
        isSynced: true,
      ));
    }
    return articles;
  }

  List<SavedArticle> _mergeArticles(List<SavedArticle> local, List<SavedArticle> cloud) {
    final merged = <String, SavedArticle>{};

    for (final article in cloud) {
      merged[article.id] = article;
    }

    for (final article in local) {
      if (!merged.containsKey(article.id)) {
        merged[article.id] = article;
      }
    }

    final result = merged.values.toList();
    // Sort: favorites first, then by date
    result.sort((a, b) {
      if (a.isFavorite && !b.isFavorite) return -1;
      if (!a.isFavorite && b.isFavorite) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  Future<void> deleteArticle(String id) async {
    final articles = await _getLocalArticles();
    final article = articles.firstWhere((a) => a.id == id, orElse: () => throw Exception('Article not found'));

    final file = File(article.imagePath);
    if (await file.exists()) {
      await file.delete();
    }

    if (SupabaseService.isAuthenticated) {
      try {
        final userId = SupabaseService.currentUserId;
        await SupabaseService.deleteFile(
          bucket: 'articles',
          path: '$userId/$id.jpg',
        );
        await SupabaseService.client.from('articles').delete().eq('id', id);
      } catch (e) {
        print('Failed to delete from cloud: $e');
      }
    }

    final updatedArticles = articles.where((a) => a.id != id).toList();
    await _saveArticlesToPrefs(updatedArticles);
  }

  Future<void> _addArticleToPrefs(SavedArticle article) async {
    final articles = await _getLocalArticles();
    articles.insert(0, article);
    await _saveArticlesToPrefs(articles);
  }

  Future<void> _saveArticlesToPrefs(List<SavedArticle> articles) async {
    final jsonList = articles.map((a) => a.toJson()).toList();
    await _prefs?.setString(_articlesKey, jsonEncode(jsonList));
  }

  Future<void> toggleArticleFavorite(String id) async {
    final articles = await _getLocalArticles();
    final updatedArticles = articles.map((a) {
      if (a.id == id) {
        return a.copyWith(isFavorite: !a.isFavorite);
      }
      return a;
    }).toList();
    await _saveArticlesToPrefs(updatedArticles);
  }

  // ==================== SYNC ====================

  /// Check if user has been asked about cloud sync
  static Future<bool> hasAskedAboutSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cloudSyncAskedKey) ?? false;
  }

  /// Mark that user has been asked about cloud sync
  static Future<void> setAskedAboutSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudSyncAskedKey, true);
  }

  /// Check if auto-sync is enabled
  static Future<bool> isAutoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cloudSyncEnabledKey) ?? false;
  }

  /// Enable or disable auto-sync
  static Future<void> setAutoSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudSyncEnabledKey, enabled);
  }

  /// Get count of unsynced items
  Future<int> getUnsyncedCount() async {
    final outfits = await _getLocalOutfits();
    final articles = await _getLocalArticles();
    return outfits.where((o) => !o.isSynced).length +
        articles.where((a) => !a.isSynced).length;
  }

  /// Sync all unsynced items to cloud
  /// Returns the number of items synced
  Future<int> syncToCloud({
    void Function(int current, int total)? onProgress,
  }) async {
    if (!SupabaseService.isAuthenticated) return 0;

    final outfits = await _getLocalOutfits();
    final unsyncedOutfits = outfits.where((o) => !o.isSynced).toList();

    final articles = await _getLocalArticles();
    final unsyncedArticles = articles.where((a) => !a.isSynced).toList();

    final total = unsyncedOutfits.length + unsyncedArticles.length;
    if (total == 0) return 0;

    int synced = 0;

    for (final outfit in unsyncedOutfits) {
      await _syncOutfitToCloud(outfit);
      synced++;
      onProgress?.call(synced, total);
    }

    for (final article in unsyncedArticles) {
      await _syncArticleToCloud(article);
      synced++;
      onProgress?.call(synced, total);
    }

    return synced;
  }
}
