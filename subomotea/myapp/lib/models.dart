import 'app_config.dart';

// Models
// ---------------------------------------------------------------------------

class Product {
  final String id;
  String name;
  double price;
  int stock;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'stock': stock,
  };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    stock: (json['stock'] as num).toInt(),
  );
}

/// One recorded sale. The unit price is stored at the time of sale, so later
/// price changes never affect old transactions.
class SaleRecord {
  final String id;
  final String productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  final DateTime timestamp;
  final String? paymentMethod; // e.g. GCash (null for older records)
  final String? paymentId; // links to the document in the 'payments' collection

  SaleRecord({
    required this.id,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.timestamp,
    this.paymentMethod,
    this.paymentId,
  });

  double get amount => roundMoney(unitPrice * quantity);

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'productName': productName,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'timestamp': timestamp.toIso8601String(),
    'paymentMethod': paymentMethod,
    'paymentId': paymentId,
  };

  Map<String, dynamic> toDatabase(String ownerId) => {
    'owner_id': ownerId,
    'id': id,
    'product_id': productId,
    'product_name': productName,
    'unit_price': unitPrice,
    'quantity': quantity,
    'timestamp': timestamp.toIso8601String(),
    'payment_method': paymentMethod,
    'payment_id': paymentId,
  };

  factory SaleRecord.fromJson(Map<String, dynamic> json) => SaleRecord(
    id: json['id'] as String,
    productId: (json['product_id'] ?? json['productId']) as String,
    productName: (json['product_name'] ?? json['productName']) as String,
    unitPrice: ((json['unit_price'] ?? json['unitPrice']) as num).toDouble(),
    quantity: (json['quantity'] as num).toInt(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    paymentMethod: (json['payment_method'] ?? json['paymentMethod']) as String?,
    paymentId: (json['payment_id'] ?? json['paymentId']) as String?,
  );
}

/// One row of a sales report (daily or history).
class ReportLine {
  final String name;
  final double price;
  final int qty;
  final double total;
  final int? stock; // null when the product no longer exists

  const ReportLine({
    required this.name,
    required this.price,
    required this.qty,
    required this.total,
    required this.stock,
  });
}

class DaySummary {
  final DateTime day;
  final int qty;
  final double revenue;
  final List<ReportLine> lines;
  final Map<String, double> byMethod; // payment method -> total paid

  const DaySummary({
    required this.day,
    required this.qty,
    required this.revenue,
    required this.lines,
    this.byMethod = const {},
  });
}

// ---------------------------------------------------------------------------
