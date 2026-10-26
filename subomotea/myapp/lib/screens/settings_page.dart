import 'package:flutter/material.dart';

import '../app_config.dart';
import '../data/inventory_store.dart';
import '../ui/shared_widgets.dart';
import 'sales_history_page.dart';
// Settings
// ---------------------------------------------------------------------------

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _upload(BuildContext context) async {
    showSnack(context, 'Syncing to Supabase…');
    final error = await store.syncAllToSupabase();
    if (!context.mounted) return;
    if (error != null) {
      showSnack(context, error, error: true);
    } else {
      showSnack(context, 'All data synced to Supabase.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                decoration: cardDecoration(),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        store.cloudEnabled ? Icons.cloud_done : Icons.cloud_off,
                        color: store.cloudEnabled ? kGreen : Colors.grey,
                      ),
                      title: const Text('Supabase database'),
                      subtitle: Text(
                        store.cloudEnabled
                            ? 'Connected. Products, sales and payments are stored in Supabase.'
                            : 'Not configured. Data is currently saved on this device only.',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.cloud_upload, color: kBlue),
                      title: const Text('Sync all data now'),
                      subtitle: const Text(
                        'Send every product and sale to Supabase',
                      ),
                      onTap: () => _upload(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.history, color: kBlue),
                      title: const Text('Sales History'),
                      subtitle: const Text('View sales for previous days'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SalesHistoryPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.restart_alt,
                        color: Colors.red.shade700,
                      ),
                      title: Text(
                        "Reset Today's Sales",
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                      subtitle: const Text(
                        "Clears today's report. Products and stock stay unchanged.",
                      ),
                      onTap: () => resetTodayFlow(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: cardDecoration(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'About',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Simple Inventory & Daily Sales Monitoring\n'
                      'Products: ${store.totalProducts}\n'
                      'Recorded transactions: ${store.totalTransactions}\n'
                      '${store.cloudEnabled ? 'Data is saved in Supabase and cached on this device.' : 'Data is saved on this device only (Supabase not configured).'}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.5,
                      ),
                    ),
                  ],
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
