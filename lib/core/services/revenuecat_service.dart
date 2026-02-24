import 'dart:io';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// Service for managing in-app purchases via RevenueCat
class RevenueCatService {
  static const String _apiKey = 'test_KOJxzMpUkUPSMmftrzGrBvOksth';

  // Entitlement IDs
  static const String entitlementPro = 'pro';

  // Product IDs (configure these in RevenueCat dashboard)
  static const String monthlyProductId = 'muse_monthly';
  static const String annualProductId = 'muse_annual';
  static const String smallPackId = 'muse_credits_25';
  static const String mediumPackId = 'muse_credits_60';

  static bool _isInitialized = false;

  /// Initialize RevenueCat SDK
  static Future<void> initialize() async {
    if (_isInitialized) return;

    await Purchases.configure(
      PurchasesConfiguration(_apiKey),
    );

    _isInitialized = true;
  }

  /// Check if user has active subscription
  static Future<bool> hasActiveSubscription() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.active.containsKey(entitlementPro);
    } catch (e) {
      print('Error checking subscription: $e');
      return false;
    }
  }

  /// Get current customer info
  static Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      print('Error getting customer info: $e');
      return null;
    }
  }

  /// Get available packages/offerings
  static Future<Offerings?> getOfferings() async {
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      print('Error getting offerings: $e');
      return null;
    }
  }

  /// Purchase a package
  static Future<CustomerInfo?> purchasePackage(Package package) async {
    try {
      final result = await Purchases.purchasePackage(package);
      return result.customerInfo;
    } catch (e) {
      print('Error purchasing package: $e');
      return null;
    }
  }

  /// Restore purchases
  static Future<CustomerInfo?> restorePurchases() async {
    try {
      return await Purchases.restorePurchases();
    } catch (e) {
      print('Error restoring purchases: $e');
      return null;
    }
  }

  /// Present the RevenueCat paywall
  static Future<PaywallResult> presentPaywall() async {
    return await RevenueCatUI.presentPaywall();
  }

  /// Present paywall if user doesn't have entitlement
  static Future<PaywallResult> presentPaywallIfNeeded() async {
    return await RevenueCatUI.presentPaywallIfNeeded(entitlementPro);
  }

  /// Login user (for syncing across devices)
  static Future<void> login(String userId) async {
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      print('Error logging in to RevenueCat: $e');
    }
  }

  /// Logout user
  static Future<void> logout() async {
    try {
      await Purchases.logOut();
    } catch (e) {
      print('Error logging out of RevenueCat: $e');
    }
  }
}
