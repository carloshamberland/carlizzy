import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

/// Service for managing user credits
///
/// Pricing Structure:
/// - Free trial: 50 credits (with annual subscription)
/// - Small pack: $2.99 for 25 credits
/// - Medium pack: $5.99 for 60 credits
/// - Monthly sub: $6.99 for 75 credits/month
/// - Annual sub: $49.99 for 800 credits/year
/// - Custom: $10+ at annual rate ($0.0625/credit = $0.625/try-on)
///
/// Cost: 1 credit = 1 try-on (API cost ~$0.04/try-on)
class CreditsService {
  static const String _creditsKey = 'user_credits';
  static const String _subscriptionTypeKey = 'subscription_type';
  static const String _trialUsedKey = 'trial_used';

  // Credits per try-on
  static const int creditsPerTryOn = 1;

  // Credit packs (one-time purchase)
  static const int smallPackCredits = 25;
  static const double smallPackPrice = 2.99;
  static const int mediumPackCredits = 60;
  static const double mediumPackPrice = 5.99;

  // Subscriptions
  static const int monthlyCredits = 75;
  static const double monthlyPrice = 6.99;
  static const int annualCredits = 800;
  static const double annualPrice = 49.99;

  // Custom purchase (minimum $10, annual rate)
  static const double customMinimum = 10.0;
  static const double customPricePerCredit = 49.99 / 800; // ~$0.0625

  // Free trial
  static const int freeTrialCredits = 50;
  static const int initialCredits = 0; // No free credits without trial

  static CreditsService? _instance;
  static SharedPreferences? _prefs;

  CreditsService._();

  static Future<CreditsService> getInstance() async {
    if (_instance == null) {
      _instance = CreditsService._();
      _prefs = await SharedPreferences.getInstance();

      // Initialize with 0 credits if first time (user must choose a plan)
      if (!_prefs!.containsKey(_creditsKey)) {
        await _prefs!.setInt(_creditsKey, initialCredits);
      }

      // Sync with cloud if authenticated
      if (SupabaseService.isAuthenticated) {
        await _instance!._syncFromCloud();
      }
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

  /// Check if user has used their free trial
  bool hasUsedTrial() {
    return _prefs?.getBool(_trialUsedKey) ?? false;
  }

  /// Start free trial with annual subscription
  /// Returns true if trial started, false if already used
  Future<bool> startFreeTrial() async {
    if (hasUsedTrial()) {
      return false;
    }

    await _prefs?.setBool(_trialUsedKey, true);
    await _prefs?.setString(_subscriptionTypeKey, 'annual_trial');
    await addCredits(freeTrialCredits);
    return true;
  }

  /// Get current subscription type
  String? getSubscriptionType() {
    return _prefs?.getString(_subscriptionTypeKey);
  }

  /// Set subscription type
  Future<void> setSubscriptionType(String type) async {
    await _prefs?.setString(_subscriptionTypeKey, type);
  }

  /// Calculate credits for custom purchase amount
  static int creditsForCustomAmount(double amount) {
    if (amount < customMinimum) return 0;
    return (amount / customPricePerCredit).floor();
  }

  /// Check if user needs to choose a plan (no credits and no subscription)
  bool needsPlanSelection() {
    return getCredits() == 0 && getSubscriptionType() == null;
  }

  /// Sync credits from cloud
  Future<void> _syncFromCloud() async {
    try {
      final userId = SupabaseService.currentUserId;
      if (userId == null) return;

      final response = await SupabaseService.client
          .from('profiles')
          .select('credits')
          .eq('id', userId)
          .single();

      if (response['credits'] != null) {
        await _prefs?.setInt(_creditsKey, response['credits'] as int);
      }
    } catch (e) {
      print('Failed to sync credits from cloud: $e');
    }
  }

  /// Sync credits to cloud
  Future<void> _syncToCloud(int credits) async {
    try {
      final userId = SupabaseService.currentUserId;
      if (userId == null) return;

      await SupabaseService.client
          .from('profiles')
          .update({'credits': credits, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', userId);
    } catch (e) {
      print('Failed to sync credits to cloud: $e');
    }
  }

  /// Get current credit balance
  int getCredits() {
    return _prefs?.getInt(_creditsKey) ?? 0;
  }

  /// Check if user has enough credits for the given number of articles
  bool hasEnoughCredits(int articleCount) {
    final required = creditsNeeded(articleCount);
    return getCredits() >= required;
  }

  /// Deduct credits for usage
  /// Returns true if successful, false if insufficient credits
  Future<bool> deductCredits(int tryOnCount) async {
    final required = tryOnCount * creditsPerTryOn;
    final current = getCredits();

    if (current < required) {
      return false;
    }

    final newBalance = current - required;
    await _prefs?.setInt(_creditsKey, newBalance);

    // Sync to cloud if authenticated
    if (SupabaseService.isAuthenticated) {
      await _syncToCloud(newBalance);
    }

    return true;
  }

  /// Add credits (for purchases or subscription renewal)
  Future<void> addCredits(int amount) async {
    final current = getCredits();
    final newBalance = current + amount;
    await _prefs?.setInt(_creditsKey, newBalance);

    if (SupabaseService.isAuthenticated) {
      await _syncToCloud(newBalance);
    }
  }

  /// Set credits to a specific amount (for subscription reset)
  Future<void> setCredits(int amount) async {
    await _prefs?.setInt(_creditsKey, amount);

    if (SupabaseService.isAuthenticated) {
      await _syncToCloud(amount);
    }
  }

  /// Refresh credits from cloud
  Future<void> refreshFromCloud() async {
    if (SupabaseService.isAuthenticated) {
      await _syncFromCloud();
    }
  }

  /// Get credits needed for a given count
  int creditsNeeded(int tryOnCount) {
    return tryOnCount * creditsPerTryOn;
  }
}
