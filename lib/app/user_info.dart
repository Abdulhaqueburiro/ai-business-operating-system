import 'package:ai_business_os/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in person's name: the name they gave when signing up, or the
/// first part of their email. Null when nobody is signed in.
String? currentUserName() {
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final given = user.userMetadata?['display_name']?.toString().trim();
    if (given != null && given.isNotEmpty) return given;
    final email = user.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// First word of the name, with a capital letter ("ali raza" -> "Ali").
String? currentFirstName() {
  final name = currentUserName();
  if (name == null) return null;
  final first = name.split(RegExp(r'\s+')).first;
  if (first.isEmpty) return null;
  return first[0].toUpperCase() + first.substring(1);
}

String? currentUserEmail() {
  try {
    return Supabase.instance.client.auth.currentUser?.email;
  } catch (_) {
    return null;
  }
}

/// A round green badge with the first letter of the person's name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final name = currentFirstName();
    final letter = (name == null || name.isEmpty) ? '?' : name[0];

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
