import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'app_config.dart';
import 'data/inventory_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(
        url: kSupabaseUrl,
        publishableKey: kSupabaseAnonKey,
      );
    }
  } catch (e) {
    kSupabaseStartupError = e.toString();
    debugPrint('Supabase init failed (app will use local data): $e');
  }
  await store.load();
  runApp(const InventoryApp());
}
