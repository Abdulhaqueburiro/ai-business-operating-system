import 'package:supabase_flutter/supabase_flutter.dart';

/// Name of the signed-in person's business, or null if it cannot be found.
Future<String?> loadBusinessName() async {
  try {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    final rows = await client
        .from('business_members')
        .select('business_id, businesses(name)')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .limit(1);

    if (rows.isEmpty) return null;

    final raw = rows.first['businesses'];
    Map? business;
    if (raw is Map) {
      business = raw;
    } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
      business = raw.first as Map;
    }
    final name = business?['name']?.toString().trim();
    return (name == null || name.isEmpty) ? null : name;
  } catch (_) {
    return null;
  }
}
