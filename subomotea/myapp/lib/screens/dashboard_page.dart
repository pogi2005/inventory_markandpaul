import 'package:flutter/material.dart';

import '../app_config.dart';
import '../data/inventory_store.dart';
import '../ui/shared_widgets.dart';
import 'sales_history_page.dart';
// Dashboard
// ---------------------------------------------------------------------------

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  Widget _reportRow(
    List<String> cells, {
    bool header = false,
    bool bold = false,
  }) {
    const flex = [3, 2, 1, 2, 1];
    final style = TextStyle(
      fontSize: header ? 11 : 13,
      fontWeight: (header || bold) ? FontWeight.w700 : FontWeight.w400,
      color: header ? Colors.grey.shade700 : Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(cells.length, (i) {
          return Expanded(
            flex: flex[i],
            child: Text(
              cells[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              style: style,
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final report = store.dailyReport;
        final hasSales = store.todaySales.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Dashboard'),
            actions: [
              IconButton(
                tooltip: 'Sales History',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SalesHistoryPage()),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                'Today • ${formatDate(DateTime.now())}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      icon: Icons.category,
                      color: kBlue,
                      label: 'Total Products',
                      value: '${store.totalProducts}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      icon: Icons.shopping_bag,
                      color: Colors.orange.shade700,
                      label: 'Items Sold Today',
                      value: '${store.itemsSoldToday}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      icon: Icons.payments,
                      color: kGreen,
                      label: 'Daily Revenue',
                      value: peso(store.revenueToday),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      icon: Icons.inventory,
                      color: Colors.purple.shade600,
                      label: 'Remaining Stock',
                      value: '${store.totalRemainingStock}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Daily Sales Report',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              if (report.isEmpty)
                Container(
                  decoration: cardDecoration(),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: const EmptyState(
                    icon: Icons.receipt_long,
                    title: 'No products yet',
                    subtitle:
                        'Add products in the Inventory tab to start tracking sales.',
                  ),
                )
              else
                Container(
                  decoration: cardDecoration(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      _reportRow([
                        'Product',
                        'Price',
                        'Sold',
                        'Sales',
                        'Stock',
                      ], header: true),
                      const Divider(height: 1),
                      if (!hasSales)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No sales recorded yet today.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      for (final line in report)
                        _reportRow([
                          line.name,
                          peso(line.price),
                          '${line.qty}',
                          peso(line.total),
                          line.stock == null ? '—' : '${line.stock}',
                        ]),
                      const Divider(height: 1),
                      _reportRow([
                        'TOTAL',
                        '',
                        '${store.itemsSoldToday}',
                        peso(store.revenueToday),
                        '${store.totalRemainingStock}',
                      ], bold: true),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => resetTodayFlow(context),
                icon: const Icon(Icons.restart_alt),
                label: const Text("Reset Today's Sales"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
