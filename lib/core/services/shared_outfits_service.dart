import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/shared_outfit.dart';
import 'supabase_service.dart';

class SharedOutfitsService {
  static const String _tableName = 'shared_outfits';
  static const String _likesTableName = 'shared_outfit_likes';
  static const String _bucketName = 'shared-outfits';

  final SupabaseClient _client;

  SharedOutfitsService() : _client = SupabaseService.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  /// Share an outfit to the community browse feed
  Future<SharedOutfit?> shareOutfit({
    required String imagePath,
    String? description,
    List<String> tags = const [],
    bool blurFace = false,
    String? username,
  }) async {
    if (_currentUserId == null) {
      throw Exception('Must be logged in to share');
    }

    try {
      // Image is already blurred if user used the manual blur editor
      // Just upload the provided image path directly

      // Upload image to Supabase Storage
      final imageFile = File(imagePath);
      final fileName = '${_currentUserId}/${const Uuid().v4()}.jpg';

      await _client.storage.from(_bucketName).upload(
        fileName,
        imageFile,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );

      // Get the public URL
      final imageUrl = _client.storage.from(_bucketName).getPublicUrl(fileName);

      // Get user display name
      final displayName = username ??
          _client.auth.currentUser?.userMetadata?['full_name'] as String? ??
          _client.auth.currentUser?.email?.split('@').first ??
          'Anonymous';

      // Insert into database
      final id = const Uuid().v4();
      final now = DateTime.now();

      final data = {
        'id': id,
        'user_id': _currentUserId,
        'username': displayName,
        'image_url': imageUrl,
        'description': description,
        'tags': tags,
        'likes': 0,
        'face_blurred': blurFace,
        'created_at': now.toIso8601String(),
      };

      await _client.from(_tableName).insert(data);

      return SharedOutfit.fromJson(data);
    } catch (e) {
      print('Error sharing outfit: $e');
      rethrow;
    }
  }

  /// Get the browse feed (paginated)
  Future<List<SharedOutfit>> getBrowseFeed({
    int page = 0,
    int limit = 20,
    String? searchQuery,
    List<String>? tags,
  }) async {
    try {
      // Build query with filters first, then order/range
      var query = _client.from(_tableName).select();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final lowerSearch = searchQuery.toLowerCase().trim();
        // Search in description, username, OR if tags contain the search term
        query = query.or('description.ilike.%$searchQuery%,username.ilike.%$searchQuery%,tags.cs.{"$lowerSearch"}');
      }

      if (tags != null && tags.isNotEmpty) {
        query = query.contains('tags', tags);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(page * limit, (page + 1) * limit - 1);

      // Get likes for current user
      final likedIds = await _getUserLikedOutfitIds();

      return (response as List)
          .map((json) => SharedOutfit.fromJson(
                json as Map<String, dynamic>,
                isLikedByMe: likedIds.contains(json['id']),
              ))
          .toList();
    } catch (e) {
      print('Error getting browse feed: $e');
      return [];
    }
  }

  /// Get outfits shared by the current user
  Future<List<SharedOutfit>> getMySharedOutfits() async {
    if (_currentUserId == null) return [];

    try {
      final response = await _client
          .from(_tableName)
          .select()
          .eq('user_id', _currentUserId!)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => SharedOutfit.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting my shared outfits: $e');
      return [];
    }
  }

  /// Like an outfit
  Future<bool> likeOutfit(String outfitId) async {
    if (_currentUserId == null) return false;

    try {
      // Add to likes table
      await _client.from(_likesTableName).insert({
        'outfit_id': outfitId,
        'user_id': _currentUserId,
      });

      // Increment likes count
      await _client.rpc('increment_outfit_likes', params: {'outfit_id': outfitId});

      return true;
    } catch (e) {
      print('Error liking outfit: $e');
      return false;
    }
  }

  /// Unlike an outfit
  Future<bool> unlikeOutfit(String outfitId) async {
    if (_currentUserId == null) return false;

    try {
      // Remove from likes table
      await _client
          .from(_likesTableName)
          .delete()
          .eq('outfit_id', outfitId)
          .eq('user_id', _currentUserId!);

      // Decrement likes count
      await _client.rpc('decrement_outfit_likes', params: {'outfit_id': outfitId});

      return true;
    } catch (e) {
      print('Error unliking outfit: $e');
      return false;
    }
  }

  /// Toggle like status
  Future<bool> toggleLike(String outfitId, bool currentlyLiked) async {
    if (currentlyLiked) {
      return await unlikeOutfit(outfitId);
    } else {
      return await likeOutfit(outfitId);
    }
  }

  /// Delete a shared outfit (only owner can delete)
  Future<bool> deleteSharedOutfit(String outfitId) async {
    if (_currentUserId == null) return false;

    try {
      await _client
          .from(_tableName)
          .delete()
          .eq('id', outfitId)
          .eq('user_id', _currentUserId!);
      return true;
    } catch (e) {
      print('Error deleting shared outfit: $e');
      return false;
    }
  }

  /// Get outfit IDs that current user has liked
  Future<Set<String>> _getUserLikedOutfitIds() async {
    if (_currentUserId == null) return {};

    try {
      final response = await _client
          .from(_likesTableName)
          .select('outfit_id')
          .eq('user_id', _currentUserId!);

      return (response as List)
          .map((row) => row['outfit_id'] as String)
          .toSet();
    } catch (e) {
      print('Error getting liked outfits: $e');
      return {};
    }
  }

  /// Report an outfit for inappropriate content
  Future<bool> reportOutfit(String outfitId, String reason) async {
    if (_currentUserId == null) return false;

    try {
      await _client.from('outfit_reports').insert({
        'outfit_id': outfitId,
        'reporter_id': _currentUserId,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error reporting outfit: $e');
      return false;
    }
  }
}
