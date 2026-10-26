import 'package:flutter/material.dart';

import '../app_config.dart';
import '../data/inventory_store.dart';
import '../models.dart';
import '../ui/shared_widgets.dart';
import 'checkout_page.dart';
// Inventory (with + / - selling and live total)
// ---------------------------------------------------------------------------

enum SortMode { name, price, stock }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  SortMode _sort = SortMode.name;
  final Map<String, int> _cart = {};

  List<Product> _sorted() {
    final list = [...store.products];
    switch (_sort) {
      case SortMode.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case SortMode.price:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case SortMode.stock:
        list.sort((a, b) => a.stock.compareTo(b.stock));
        break;
    }
    return list;
  }

  /// Cart quantity, never more than the stock currently available.
  int _qty(Product p) {
    final wanted = _cart[p.id] ?? 0;
    return wanted > p.stock ? p.stock : wanted;
  }

  void _change(Product p, int delta) {
    final next = _qty(p) + delta;
    setState(() {
      if (next <= 0) {
        _cart.remove(p.id);
      } else if (next <= p.stock) {
        _cart[p.id] = next;
      }
    });
  }

  Future<void> _confirmSale(List<Product> products) async {
    final items = <String, int>{};
    double total = 0;
    int count = 0;
    for (final p in products) {
      final q = _qty(p);
      if (q > 0) {
        items[p.id] = q;
        count += q;
        total += p.price * q;
      }
    }
    if (items.isEmpty) {
      showSnack(
        context,
        'Add at least one item with the + button.',
        error: true,
      );
      return;
    }

    // Open the checkout screen. It returns true only when the payment is paid
    // and the sale was recorded.
    final paid = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => CheckoutPage(items: items)));
    if (!mounted) return;
    if (paid == true) {
      setState(() => _cart.clear());
      showSnack(
        context,
        'Payment received: $count item(s) • ${peso(roundMoney(total))}',
      );
    } else {
      showSnack(context, 'Not paid yet. Your items are still in the cart.');
    }
  }

  Future<void> _updateStock(Product product) async {
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => StockDialog(product: product),
    );
    if (value == null) return;
    await store.setStock(product.id, value);
    if (!mounted) return;
    showSnack(context, '${product.name} stock set to $value');
  }

  Future<void> _delete(Product product) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${product.name}?',
      message:
          'The product will be removed from your inventory. Its past sales records will be kept.',
      confirmText: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _cart.remove(product.id));
    await store.deleteProduct(product.id);
    if (!mounted) return;
    showSnack(context, '${product.name} deleted');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final products = _sorted();

        int itemCount = 0;
        double total = 0;
        for (final p in products) {
          final q = _qty(p);
          itemCount += q;
          total += p.price * q;
        }
        total = roundMoney(total);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventory'),
            actions: [
              PopupMenuButton<SortMode>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (mode) => setState(() => _sort = mode),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: SortMode.name,
                    child: Text('Sort by name'),
                  ),
                  PopupMenuItem(
                    value: SortMode.price,
                    child: Text('Sort by price (high first)'),
                  ),
                  PopupMenuItem(
                    value: SortMode.stock,
                    child: Text('Sort by stock (low first)'),
                  ),
                ],
              ),
            ],
          ),
          body: products.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products yet',
                  subtitle: 'Tap the + button to add your first product.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final product = products[i];
                    return ProductCard(
                      key: ValueKey(product.id),
                      product: product,
                      qty: _qty(product),
                      onIncrement: () => _change(product, 1),
                      onDecrement: () => _change(product, -1),
                      onEdit: () => showProductForm(context, product: product),
                      onUpdateStock: () => _updateStock(product),
                      onDelete: () => _delete(product),
                    );
                  },
                ),
          // Live total: goes up with + and down with -.
          bottomNavigationBar: products.isEmpty
              ? null
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 8,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$itemCount item(s)',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  peso(total),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: kGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: itemCount > 0
                              ? () => setState(() => _cart.clear())
                              : null,
                          child: const Text('Clear'),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          onPressed: itemCount > 0
                              ? () => _confirmSale(products)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: kBlue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm Sale'),
                        ),
                      ],
                    ),
                  ),
                ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add product',
            backgroundColor: kBlue,
            foregroundColor: Colors.white,
            onPressed: () => showProductForm(context),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
