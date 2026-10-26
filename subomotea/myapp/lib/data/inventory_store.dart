import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_config.dart';
import '../models.dart';
// Supabase persistence
// ---------------------------------------------------------------------------

class CloudSync {
  SupabaseClient? _db;
  bool get enabled => _db != null;
  bool get authenticated => _db?.auth.currentUser != null;
  String get _ownerId => _db!.auth.currentUser!.id;

  void init() {
    if (kSupabaseUrl.isEmpty || kSupabaseAnonKey.isEmpty) {
      kSupabaseStartupError ??= 'Supabase URL or publishable key is missing.';
      return;
    }
    try {
      _db = Supabase.instance.client;
    } catch (e) {
      // Keep the original Supabase.initialize error from main() when it exists.
      // The instance lookup error here is only a follow-on symptom.
      kSupabaseStartupError ??= e.toString();
      debugPrint('Supabase is not available: $e');
      _db = null;
    }
  }

  Future<void> ensureSignedIn() async {
    final db = _db;
    if (db == null) return;
    if (db.auth.currentUser == null) await db.auth.signInAnonymously();
  }

  Future<List<Product>> loadProducts() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db
        .from('products')
        .select()
        .eq('owner_id', _ownerId)
        .order('name');
    return rows
        .map((row) => Product.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<List<SaleRecord>> loadSales() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db
        .from('sales')
        .select()
        .eq('owner_id', _ownerId)
        .order('timestamp');
    return rows
        .map((row) => SaleRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Map<String, dynamic>?> loadState() async {
    final db = _db;
    if (db == null) return null;
    final row = await db
        .from('app_state')
        .select()
        .eq('owner_id', _ownerId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> upsertProduct(Product product) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.from('products').upsert({
        ...product.toJson(),
        'owner_id': _ownerId,
      }, onConflict: 'owner_id,id');
    } catch (e) {
      debugPrint('Supabase product write failed: $e');
    }
  }

  Future<void> deleteProduct(String id) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.from('products').delete().eq('owner_id', _ownerId).eq('id', id);
    } catch (e) {
      debugPrint('Supabase product delete failed: $e');
    }
  }

  Future<Map<String, dynamic>> createXenditInvoice(
    Map<String, int> items,
  ) async {
    final db = _db;
    if (db == null) {
      final detail = kSupabaseStartupError;
      throw StateError(
        detail == null
            ? 'Supabase is not initialized. Check the Flutter startup log.'
            : 'Supabase initialization failed: $detail',
      );
    }
    if (!authenticated) {
      final detail = kSupabaseStartupError;
      throw StateError(
        detail == null
            ? 'No Supabase user session. Enable Anonymous Sign-Ins in Supabase Authentication.'
            : 'Supabase sign-in or data loading failed: $detail',
      );
    }
    final response = await db.functions.invoke(
      'create-xendit-invoice',
      body: {
        'items': [
          for (final entry in items.entries)
            {'product_id': entry.key, 'quantity': entry.value},
        ],
      },
    );
    if (response.status >= 300) {
      throw StateError('Invoice creation failed: ${response.data}');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<String?> getPaymentStatus(String paymentId) async {
    final db = _db;
    if (db == null || !authenticated) return null;
    final row = await db
        .from('payment_logs')
        .select('status')
        .eq('owner_id', _ownerId)
        .eq('id', paymentId)
        .maybeSingle();
    return row?['status'] as String?;
  }

  Future<void> setResetAt(DateTime? resetAt) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.from('app_state').upsert({
        'owner_id': _ownerId,
        'reset_at': resetAt?.toIso8601String(),
      }, onConflict: 'owner_id');
    } catch (e) {
      debugPrint('Supabase settings write failed: $e');
    }
  }

  Future<void> syncAll(
    List<Product> products,
    List<SaleRecord> sales,
    DateTime? resetAt,
  ) async {
    final db = _db;
    if (db == null) throw StateError('Supabase is not configured');
    if (products.isNotEmpty) {
      await db
          .from('products')
          .upsert(
            products
                .map((product) => {...product.toJson(), 'owner_id': _ownerId})
                .toList(),
            onConflict: 'owner_id,id',
          );
    }
    if (sales.isNotEmpty) {
      await db
          .from('sales')
          .upsert(
            sales.map((sale) => sale.toDatabase(_ownerId)).toList(),
            onConflict: 'owner_id,id',
          );
    }
    await db.from('app_state').upsert({
      'owner_id': _ownerId,
      'reset_at': resetAt?.toIso8601String(),
    }, onConflict: 'owner_id');
  }
}

// ---------------------------------------------------------------------------
// Store: inventory logic, sales calculations and local persistence
// ---------------------------------------------------------------------------

class InventoryStore extends ChangeNotifier {
  static const String _kProducts = 'products_v1';
  static const String _kSales = 'sales_v1';
  static const String _kResetAt = 'reset_at_v1';
  static const String _kSeeded = 'seeded_v1';

  final List<Product> _products = [];
  final List<SaleRecord> _sales = [];
  final CloudSync cloud = CloudSync();
  DateTime? _resetAt;

  SharedPreferences? _prefs;
  Timer? _dayTimer;
  DateTime _lastDay = DateTime.now();
  int _idCounter = 0;

  List<Product> get products => List.unmodifiable(_products);
  int get totalTransactions => _sales.length;
  bool get cloudEnabled => cloud.authenticated;

  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Product? findProduct(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ----- Loading and saving -----

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    cloud.init();

    try {
      final productsJson = prefs.getString(_kProducts);
      if (productsJson != null) {
        final list = jsonDecode(productsJson) as List<dynamic>;
        _products.addAll(
          list.map((e) => Product.fromJson(e as Map<String, dynamic>)),
        );
      }
      final salesJson = prefs.getString(_kSales);
      if (salesJson != null) {
        final list = jsonDecode(salesJson) as List<dynamic>;
        _sales.addAll(
          list.map((e) => SaleRecord.fromJson(e as Map<String, dynamic>)),
        );
      }
      final resetAt = prefs.getString(_kResetAt);
      if (resetAt != null) _resetAt = DateTime.tryParse(resetAt);
    } catch (e) {
      debugPrint('Could not read saved data: $e');
    }

    final seeded = prefs.getBool(_kSeeded) ?? false;
    if (!seeded) {
      if (_products.isEmpty) {
        _products.addAll([
          Product(id: _newId(), name: 'Apple', price: 3.00, stock: 40),
          Product(id: _newId(), name: 'Ball', price: 1.50, stock: 20),
          Product(id: _newId(), name: 'Book', price: 1.00, stock: 50),
          Product(id: _newId(), name: 'Shampoo', price: 2.00, stock: 40),
        ]);
      }
      await prefs.setBool(_kSeeded, true);
      await _save();
    }

    if (cloud.enabled) {
      try {
        await cloud.ensureSignedIn();
        final state = await cloud.loadState();
        final remoteProducts = await cloud.loadProducts();
        final remoteSales = await cloud.loadSales();
        if (state == null && remoteProducts.isEmpty && remoteSales.isEmpty) {
          await cloud.syncAll(_products, _sales, _resetAt);
        } else if (state == null) {
          await cloud.syncAll(remoteProducts, remoteSales, _resetAt);
          _products
            ..clear()
            ..addAll(remoteProducts);
          _sales
            ..clear()
            ..addAll(remoteSales);
        } else {
          _products
            ..clear()
            ..addAll(remoteProducts);
          _sales
            ..clear()
            ..addAll(remoteSales);
          final resetAt = state['reset_at'] as String?;
          _resetAt = resetAt == null ? null : DateTime.tryParse(resetAt);
        }
        await _save();
      } catch (e) {
        kSupabaseStartupError = e.toString();
        debugPrint('Could not load Supabase data: $e');
      }
    }

    // Start a fresh daily report automatically when the calendar date changes.
    _dayTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      if (!sameDay(now, _lastDay)) {
        _lastDay = now;
        notifyListeners();
      }
    });
  }

  Future<bool> _save() async {
    final prefs = _prefs;
    if (prefs == null) return false;
    try {
      await prefs.setString(
        _kProducts,
        jsonEncode(_products.map((p) => p.toJson()).toList()),
      );
      await prefs.setString(
        _kSales,
        jsonEncode(_sales.map((s) => s.toJson()).toList()),
      );
      if (_resetAt != null) {
        await prefs.setString(_kResetAt, _resetAt!.toIso8601String());
      } else {
        await prefs.remove(_kResetAt);
      }
      return true;
    } catch (e) {
      debugPrint('Could not save data: $e');
      return false;
    }
  }

  /// Manual "upload everything" from Settings. Returns null on success.
  Future<String?> syncAllToSupabase() async {
    if (!cloud.authenticated) {
      return 'Supabase is not configured or signed in. Check the project URL, anon key, and anonymous sign-in setting.';
    }
    try {
      await cloud
          .syncAll(_products, _sales, _resetAt)
          .timeout(const Duration(seconds: 12));
      return null;
    } on TimeoutException {
      return 'No connection right now. Try the Supabase sync again when online.';
    } catch (e) {
      return 'Supabase sync failed: $e';
    }
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    super.dispose();
  }

  // ----- Product management -----

  Future<void> addProduct(String name, double price, int stock) async {
    final p = Product(id: _newId(), name: name, price: price, stock: stock);
    _products.add(p);
    notifyListeners();
    await cloud.upsertProduct(p);
    await _save();
  }

  /// Editing a product never touches its past sales records.
  Future<void> updateProduct(
    String id,
    String name,
    double price,
    int stock,
  ) async {
    final p = findProduct(id);
    if (p == null) return;
    p.name = name;
    p.price = price;
    p.stock = stock;
    notifyListeners();
    await cloud.upsertProduct(p);
    await _save();
  }

  Future<void> setStock(String id, int stock) async {
    final p = findProduct(id);
    if (p == null) return;
    p.stock = stock;
    notifyListeners();
    await cloud.upsertProduct(p);
    await _save();
  }

  /// Deleting a product keeps its historical sales transactions.
  Future<void> deleteProduct(String id) async {
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
    await cloud.deleteProduct(id);
    await _save();
  }

  // ----- Selling -----

  Future<Map<String, dynamic>> createXenditInvoice(Map<String, int> items) =>
      cloud.createXenditInvoice(items);

  Future<String?> getPaymentStatus(String paymentId) async {
    final status = await cloud.getPaymentStatus(paymentId);
    if (status == 'paid' || status == 'failed') {
      final products = await cloud.loadProducts();
      final sales = await cloud.loadSales();
      final state = await cloud.loadState();
      _products
        ..clear()
        ..addAll(products);
      _sales
        ..clear()
        ..addAll(sales);
      final resetAt = state?['reset_at'] as String?;
      _resetAt = resetAt == null ? null : DateTime.tryParse(resetAt);
      await _save();
      notifyListeners();
    }
    return status;
  }

  // ----- Today's statistics -----

  List<SaleRecord> get todaySales {
    final now = DateTime.now();
    return _sales.where((s) {
      if (!sameDay(s.timestamp, now)) return false;
      if (_resetAt != null && !s.timestamp.isAfter(_resetAt!)) return false;
      return true;
    }).toList();
  }

  int get totalProducts => _products.length;

  int get itemsSoldToday {
    int total = 0;
    for (final s in todaySales) {
      total += s.quantity;
    }
    return total;
  }

  double get revenueToday {
    double total = 0;
    for (final s in todaySales) {
      total += s.amount;
    }
    return roundMoney(total);
  }

  int get totalRemainingStock {
    int total = 0;
    for (final p in _products) {
      total += p.stock;
    }
    return total;
  }

  ReportLine _lineFrom(List<SaleRecord> list, {Product? product}) {
    int qty = 0;
    double total = 0;
    for (final s in list) {
      qty += s.quantity;
      total += s.amount;
    }
    return ReportLine(
      name: product?.name ?? (list.isNotEmpty ? list.last.productName : '?'),
      price: product?.price ?? (list.isNotEmpty ? list.last.unitPrice : 0),
      qty: qty,
      total: roundMoney(total),
      stock: product?.stock,
    );
  }

  /// One line per current product (even with zero sales), plus lines for
  /// deleted products that still sold something today.
  List<ReportLine> get dailyReport {
    final byId = <String, List<SaleRecord>>{};
    for (final s in todaySales) {
      byId.putIfAbsent(s.productId, () => []).add(s);
    }
    final lines = <ReportLine>[];
    for (final p in _products) {
      final list = byId.remove(p.id) ?? const <SaleRecord>[];
      lines.add(_lineFrom(list, product: p));
    }
    for (final entry in byId.entries) {
      lines.add(_lineFrom(entry.value));
    }
    return lines;
  }

  // ----- Manual reset -----

  /// Clears today's monitoring only. Products, prices and stock are untouched
  /// (sold items are NOT restocked). Old transactions stay in Sales History.
  Future<void> resetToday() async {
    _resetAt = DateTime.now();
    notifyListeners();
    await cloud.setResetAt(_resetAt);
    await _save();
  }

  // ----- History -----

  List<DaySummary> get history {
    final byDay = <String, List<SaleRecord>>{};
    for (final s in _sales) {
      byDay.putIfAbsent(dayKey(s.timestamp), () => []).add(s);
    }
    final keys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((k) {
      final list = byDay[k]!;
      final byProduct = <String, List<SaleRecord>>{};
      final byMethod = <String, double>{};
      int qty = 0;
      double revenue = 0;
      for (final s in list) {
        byProduct.putIfAbsent(s.productId, () => []).add(s);
        qty += s.quantity;
        revenue += s.amount;
        final m = s.paymentMethod ?? 'Not recorded';
        byMethod[m] = roundMoney((byMethod[m] ?? 0) + s.amount);
      }
      return DaySummary(
        day: list.first.timestamp,
        qty: qty,
        revenue: roundMoney(revenue),
        lines: byProduct.values.map((l) => _lineFrom(l)).toList(),
        byMethod: byMethod,
      );
    }).toList();
  }
}

/// One shared store used by every screen.
final InventoryStore store = InventoryStore();

// ---------------------------------------------------------------------------
