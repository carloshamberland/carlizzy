class Product {
  final String id;
  final String name;
  final String brand;
  final double price;
  final String imageUrl;
  final String category;
  final String? color;
  final String affiliateUrl;
  final String network; // 'cj', 'shareasale', 'mock'

  Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.price,
    required this.imageUrl,
    required this.category,
    this.color,
    required this.affiliateUrl,
    this.network = 'mock',
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        brand: json['brand'] as String,
        price: (json['price'] as num).toDouble(),
        imageUrl: json['image_url'] as String,
        category: json['category'] as String,
        color: json['color'] as String?,
        affiliateUrl: json['affiliate_url'] as String,
        network: json['network'] as String? ?? 'mock',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'price': price,
        'image_url': imageUrl,
        'category': category,
        'color': color,
        'affiliate_url': affiliateUrl,
        'network': network,
      };
}
