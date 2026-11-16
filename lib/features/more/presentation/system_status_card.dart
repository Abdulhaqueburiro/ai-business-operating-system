import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:flutter/material.dart';

enum _ConnectionTestState { notTested, testing, connected, failed }

/// Shows the backend status message and lets the person check that the
/// sign-in service can be reached.
class SystemStatusCard extends StatefulWidget {
  const SystemStatusCard({
    super.key,
    required this.backendStatusMessage,
    this.testSupabaseConnection,
  });

  final String backendStatusMessage;
  final Future<SupabaseConnectionResult> Function()? testSupabaseConnection;

  @override
  State<SystemStatusCard> createState() => _SystemStatusCardState();
}

class _SystemStatusCardState extends State<SystemStatusCard> {
  _ConnectionTestState _state = _ConnectionTestState.notTested;
  String? _message;

  Future<void> _test() async {
    setState(() {
      _state = _ConnectionTestState.testing;
      _message = null;
    });

    final checker = widget.testSupabaseConnection;
    if (checker == null) {
      setState(() {
        _state = _ConnectionTestState.failed;
        _message =
            'Auth service check is unavailable because the project URL is not configured.';
      });
      return;
    }

    final result = await checker();
    if (!mounted) return;

    setState(() {
      _state = result.isConnected
          ? _ConnectionTestState.connected
          : _ConnectionTestState.failed;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final testing = _state == _ConnectionTestState.testing;
    final statusText = switch (_state) {
      _ConnectionTestState.notTested => 'Not tested',
      _ConnectionTestState.testing => 'Testing',
      _ConnectionTestState.connected => 'Connected',
      _ConnectionTestState.failed => 'Connection failed',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_outlined, color: colors.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.backendStatusMessage,
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auth service availability: $statusText',
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (_message case final message?) ...[
                  const SizedBox(height: 6),
                  Text(
                    message,
                    style: textTheme.bodyMedium?.copyWith(
                      color: _state == _ConnectionTestState.failed
                          ? colors.error
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: testing ? null : _test,
                    icon: testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text('Check Auth Service Availability'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
