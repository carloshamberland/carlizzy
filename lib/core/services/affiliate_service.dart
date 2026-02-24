import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/product.dart';

/// Base class for affiliate network integrations
abstract class AffiliateNetwork {
  Future<List<Product>> searchProducts({
    required String query,
    String? category,
    double? minPrice,
    double? maxPrice,
    int limit = 20,
  });
}

/// CJ Affiliate (Commission Junction) API integration
///
/// To get your API credentials:
/// 1. Sign up at https://www.cj.com/
/// 2. Get approved as a publisher
/// 3. Go to developers.cj.com > Authentication
/// 4. Generate your Personal Access Token
///
/// API Docs: https://developers.cj.com/
class CJAffiliateService implements AffiliateNetwork {
  final Dio _dio;
  final String? apiKey;
  final String? websiteId;
  final String? companyId;

  // CJ GraphQL Product API
  static const String _graphqlUrl = 'https://ads.api.cj.com/query';

  CJAffiliateService({
    String? apiKey,
    String? websiteId,
    String? companyId,
    Dio? dio,
  }) : apiKey = apiKey ?? dotenv.env['CJ_API_TOKEN'],
       websiteId = websiteId ?? dotenv.env['CJ_WEBSITE_ID'],
       companyId = companyId ?? dotenv.env['CJ_COMPANY_ID'],
       _dio = dio ?? Dio();

  bool get isConfigured => apiKey != null && apiKey!.isNotEmpty;

  @override
  Future<List<Product>> searchProducts({
    required String query,
    String? category,
    double? minPrice,
    double? maxPrice,
    int limit = 20,
  }) async {
    if (!isConfigured) {
      print('CJ Affiliate not configured - using mock data');
      return _getMockProducts(query: query, category: category);
    }

    try {
      // GraphQL query for shopping products
      // Docs: https://developers.cj.com/docs/graphql-api/product-feed
      final graphqlQuery = '''
        query {
          shoppingProducts(
            companyId: "$companyId"
            keywords: "${query.isNotEmpty ? query : 'clothing'}"
            limit: $limit
          ) {
            resultList {
              id
              title
              description
              price {
                amount
                currency
              }
              salePrice {
                amount
              }
              imageLink
              link
              advertiserName
              advertiserCountry
              productType
              availability
            }
            count
          }
        }
      ''';

      final response = await _dio.post(
        _graphqlUrl,
        data: {'query': graphqlQuery},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final products = <Product>[];
      final data = response.data['data'];

      if (data != null && data['shoppingProducts'] != null) {
        final resultList = data['shoppingProducts']['resultList'] as List? ?? [];

        for (final item in resultList) {
          final priceData = item['price'];
          final salePriceData = item['salePrice'];
          double price = 0;

          // Use sale price if available, otherwise regular price
          if (salePriceData != null && salePriceData['amount'] != null) {
            price = double.tryParse(salePriceData['amount'].toString()) ?? 0;
          } else if (priceData != null && priceData['amount'] != null) {
            price = double.tryParse(priceData['amount'].toString()) ?? 0;
          }

          // Filter by price range if specified
          if (minPrice != null && price < minPrice) continue;
          if (maxPrice != null && price > maxPrice) continue;

          products.add(Product(
            id: item['id']?.toString() ?? '',
            name: item['title'] ?? '',
            brand: item['advertiserName'] ?? '',
            price: price,
            imageUrl: item['imageLink'] ?? '',
            category: item['productType'] ?? category ?? 'clothing',
            affiliateUrl: item['link'] ?? '',
            network: 'cj',
          ));
        }
      }

      // If API returns products, use them; otherwise fall back to mock
      if (products.isNotEmpty) {
        return products;
      }
      return _getMockProducts(query: query, category: category);
    } catch (e) {
      print('CJ API error: $e');
      return _getMockProducts(query: query, category: category);
    }
  }

  /// Mock products for testing before CJ approval
  List<Product> _getMockProducts({String? query, String? category}) {
    final allProducts = [
      // Tops
      Product(
        id: 'mock_1',
        name: 'Classic White T-Shirt',
        brand: 'Nike',
        price: 35.00,
        imageUrl: 'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400',
        category: 'tops',
        color: 'white',
        affiliateUrl: 'https://nike.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_2',
        name: 'Striped Button Down',
        brand: 'Zara',
        price: 49.90,
        imageUrl: 'https://images.unsplash.com/photo-1596755094514-f87e34085b2c?w=400',
        category: 'tops',
        color: 'blue',
        affiliateUrl: 'https://zara.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_3',
        name: 'Oversized Hoodie',
        brand: 'H&M',
        price: 39.99,
        imageUrl: 'https://images.unsplash.com/photo-1556821840-3a63f95609a7?w=400',
        category: 'tops',
        color: 'gray',
        affiliateUrl: 'https://hm.com',
        network: 'mock',
      ),
      // Bottoms
      Product(
        id: 'mock_4',
        name: 'Slim Fit Jeans',
        brand: 'Levi\'s',
        price: 89.50,
        imageUrl: 'https://images.unsplash.com/photo-1542272604-787c3835535d?w=400',
        category: 'bottoms',
        color: 'blue',
        affiliateUrl: 'https://levis.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_5',
        name: 'Chino Pants',
        brand: 'Gap',
        price: 59.95,
        imageUrl: 'https://images.unsplash.com/photo-1473966968600-fa801b869a1a?w=400',
        category: 'bottoms',
        color: 'khaki',
        affiliateUrl: 'https://gap.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_6',
        name: 'Athletic Shorts',
        brand: 'Adidas',
        price: 45.00,
        imageUrl: 'https://images.unsplash.com/photo-1591195853828-11db59a44f6b?w=400',
        category: 'bottoms',
        color: 'black',
        affiliateUrl: 'https://adidas.com',
        network: 'mock',
      ),
      // Dresses
      Product(
        id: 'mock_7',
        name: 'Summer Floral Dress',
        brand: 'ASOS',
        price: 65.00,
        imageUrl: 'https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?w=400',
        category: 'dresses',
        color: 'floral',
        affiliateUrl: 'https://asos.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_8',
        name: 'Little Black Dress',
        brand: 'Nordstrom',
        price: 120.00,
        imageUrl: 'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=400',
        category: 'dresses',
        color: 'black',
        affiliateUrl: 'https://nordstrom.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_9',
        name: 'Midi Wrap Dress',
        brand: 'Reformation',
        price: 218.00,
        imageUrl: 'https://images.unsplash.com/photo-1496747611176-843222e1e57c?w=400',
        category: 'dresses',
        color: 'red',
        affiliateUrl: 'https://reformation.com',
        network: 'mock',
      ),
      // Outerwear
      Product(
        id: 'mock_10',
        name: 'Denim Jacket',
        brand: 'Levi\'s',
        price: 98.00,
        imageUrl: 'https://images.unsplash.com/photo-1551028719-00167b16eac5?w=400',
        category: 'outerwear',
        color: 'blue',
        affiliateUrl: 'https://levis.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_11',
        name: 'Puffer Jacket',
        brand: 'North Face',
        price: 199.00,
        imageUrl: 'https://images.unsplash.com/photo-1539533018447-63fcce2678e3?w=400',
        category: 'outerwear',
        color: 'black',
        affiliateUrl: 'https://thenorthface.com',
        network: 'mock',
      ),
      Product(
        id: 'mock_12',
        name: 'Trench Coat',
        brand: 'Banana Republic',
        price: 249.00,
        imageUrl: 'https://images.unsplash.com/photo-1544923246-77307dd628b6?w=400',
        category: 'outerwear',
        color: 'beige',
        affiliateUrl: 'https://bananarepublic.com',
        network: 'mock',
      ),
    ];

    var filtered = allProducts;

    // Filter by search query
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.brand.toLowerCase().contains(q) ||
        p.category.toLowerCase().contains(q) ||
        (p.color?.toLowerCase().contains(q) ?? false)
      ).toList();
    }

    // Filter by category
    if (category != null && category.isNotEmpty && category != 'all') {
      filtered = filtered.where((p) => p.category == category).toList();
    }

    return filtered;
  }
}

/// Product search service that aggregates results from multiple networks
class ProductSearchService {
  final CJAffiliateService cjService;
  // Add more networks here:
  // final ShareASaleService shareASaleService;
  // final RakutenService rakutenService;

  ProductSearchService({
    CJAffiliateService? cjService,
  }) : cjService = cjService ?? CJAffiliateService();

  Future<List<Product>> search({
    required String query,
    String? category,
    String? brand,
    double? minPrice,
    double? maxPrice,
    int limit = 20,
  }) async {
    final results = <Product>[];

    // Search CJ
    final cjResults = await cjService.searchProducts(
      query: query,
      category: category,
      minPrice: minPrice,
      maxPrice: maxPrice,
      limit: limit,
    );
    results.addAll(cjResults);

    // Add more networks here:
    // final shareASaleResults = await shareASaleService.search(...);
    // results.addAll(shareASaleResults);

    // Filter by brand if specified
    if (brand != null && brand.isNotEmpty) {
      return results.where((p) =>
        p.brand.toLowerCase().contains(brand.toLowerCase())
      ).toList();
    }

    // Filter by price range
    var filtered = results;
    if (minPrice != null) {
      filtered = filtered.where((p) => p.price >= minPrice).toList();
    }
    if (maxPrice != null) {
      filtered = filtered.where((p) => p.price <= maxPrice).toList();
    }

    return filtered;
  }

  /// Get all available brands from current products
  Future<List<String>> getAvailableBrands() async {
    final products = await search(query: '');
    final brands = products.map((p) => p.brand).toSet().toList();
    brands.sort();
    return brands;
  }
}
