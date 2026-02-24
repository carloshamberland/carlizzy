import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class RecentPhotosService {
  static const String _key = 'recent_model_photos';
  static const String _allKey = 'all_selfies';
  static const int _maxRecentPhotos = 4;

  /// Get the directory for storing recent photos permanently
  static Future<Directory> _getPhotosDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${appDir.path}/recent_selfies');
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  /// Get the list of recently used model photos (max 4, filters out non-existent files)
  static Future<List<String>> getRecentPhotos() async {
    final allPhotos = await getAllPhotos();
    return allPhotos.take(_maxRecentPhotos).toList();
  }

  /// Get all saved selfies (filters out non-existent files)
  static Future<List<String>> getAllPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_allKey);
    if (jsonStr == null) {
      // Migrate from old key if exists
      final oldJsonStr = prefs.getString(_key);
      if (oldJsonStr != null) {
        await prefs.setString(_allKey, oldJsonStr);
        return _filterValidPaths(oldJsonStr);
      }
      return [];
    }

    return _filterValidPaths(jsonStr);
  }

  static Future<List<String>> _filterValidPaths(String jsonStr) async {
    try {
      final List<dynamic> decoded = json.decode(jsonStr);
      final paths = decoded.cast<String>();

      // Filter out paths that no longer exist
      final validPaths = <String>[];
      for (final path in paths) {
        if (await File(path).exists()) {
          validPaths.add(path);
        }
      }

      return validPaths;
    } catch (_) {
      return [];
    }
  }

  /// Add a photo to recent history, copying to permanent storage if needed
  static Future<void> addPhoto(String photoPath) async {
    final prefs = await SharedPreferences.getInstance();
    final photos = await getAllPhotos();

    String permanentPath = photoPath;

    // Check if the photo is in a temporary directory and copy it
    final file = File(photoPath);
    if (await file.exists()) {
      final photosDir = await _getPhotosDirectory();
      final isInPermanentDir = photoPath.startsWith(photosDir.path);

      if (!isInPermanentDir) {
        // Copy to permanent location
        final fileName = 'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final newPath = '${photosDir.path}/$fileName';
        await file.copy(newPath);
        permanentPath = newPath;
      }
    }

    // Remove if already exists (to move to front)
    photos.remove(permanentPath);
    // Also remove old path if it was different
    photos.remove(photoPath);

    // Add to front
    photos.insert(0, permanentPath);

    // Save all photos (no limit)
    await prefs.setString(_allKey, json.encode(photos));

    // Sync to cloud if authenticated
    if (SupabaseService.isAuthenticated) {
      await _syncToCloud(permanentPath);
    }
  }

  /// Sync a selfie to cloud storage
  static Future<void> _syncToCloud(String photoPath) async {
    try {
      final userId = SupabaseService.currentUserId;
      if (userId == null) return;

      final file = File(photoPath);
      if (!await file.exists()) return;

      final fileName = photoPath.split('/').last;
      final storagePath = '$userId/selfies/$fileName';

      await SupabaseService.uploadFile(
        bucket: 'selfies',
        path: storagePath,
        file: file,
      );

      await SupabaseService.client.from('recent_selfies').upsert({
        'user_id': userId,
        'image_path': storagePath,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Failed to sync selfie to cloud: $e');
    }
  }

  /// Remove a specific photo
  static Future<void> removePhoto(String photoPath) async {
    final prefs = await SharedPreferences.getInstance();
    final photos = await getAllPhotos();

    // Remove from list
    photos.remove(photoPath);

    // Delete the file
    final file = File(photoPath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    // Save updated list
    await prefs.setString(_allKey, json.encode(photos));
  }

  /// Clear all recent photos
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final photos = await getAllPhotos();

    // Delete all photo files
    for (final path in photos) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    await prefs.remove(_key);
    await prefs.remove(_allKey);
  }
}
