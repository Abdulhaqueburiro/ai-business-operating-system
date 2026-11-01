import 'package:supabase_flutter/supabase_flutter.dart';

/// Role of the signed-in person in their business: 'owner', 'admin' or
/// 'staff'. Returns null when it cannot be found. The server enforces the
/// real rules; the app only uses this to hide screens a person cannot use.
Future<String?> loadMyRole() async {
  try {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    final rows = await client
        .from('business_members')
        .select('role')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .limit(1);

    if (rows.isEmpty) return null;
    return rows.first['role']?.toString();
  } catch (_) {
    return null;
  }
}

/// Owners and admins manage the business. Everyone else is treated as staff.
bool isManagerRole(String? role) => role == 'owner' || role == 'admin';
