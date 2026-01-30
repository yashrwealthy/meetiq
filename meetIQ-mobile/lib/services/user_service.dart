import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage current user session
class UserService {
  static const _keyUserId = 'current_user_id';
  static const _keyPartnerToken = 'partner_token';
  
  // In-memory cache for web (shared_preferences works on web too, but this is faster)
  static String? _cachedUserId;
  static String? _cachedPartnerToken;

  /// Set the current user (call this on login)
  Future<void> setCurrentUser({
    required String userId,
    required String partnerToken,
  }) async {
    _cachedUserId = userId;
    _cachedPartnerToken = partnerToken;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyPartnerToken, partnerToken);
    
    debugPrint('User set: $userId');
  }

  /// Get the current user ID
  Future<String?> getCurrentUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
    
    final prefs = await SharedPreferences.getInstance();
    _cachedUserId = prefs.getString(_keyUserId);
    return _cachedUserId;
  }

  /// Get the current user ID (sync version, returns cached value)
  String? get currentUserId => _cachedUserId;

  /// Get the partner token
  Future<String?> getPartnerToken() async {
    if (_cachedPartnerToken != null) return _cachedPartnerToken;
    
    final prefs = await SharedPreferences.getInstance();
    _cachedPartnerToken = prefs.getString(_keyPartnerToken);
    return _cachedPartnerToken;
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final userId = await getCurrentUserId();
    return userId != null && userId.isNotEmpty;
  }

  /// Clear current user (logout)
  Future<void> logout() async {
    _cachedUserId = null;
    _cachedPartnerToken = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyPartnerToken);
  }

  /// Load cached values from storage (call on app start)
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedUserId = prefs.getString(_keyUserId);
    _cachedPartnerToken = prefs.getString(_keyPartnerToken);
    debugPrint('UserService initialized: userId=$_cachedUserId');
  }
}
