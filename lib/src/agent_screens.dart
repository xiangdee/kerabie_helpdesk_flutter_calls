import 'package:flutter/material.dart';

import 'agent_options.dart';

/// The screens the SDK can show without help: a list to tap, a yes/no confirmation and a box to type an address.
/// Screens that need your data (saved addresses) or your design (a date picker, opening a screen) are passed in by your app.
///
/// [context] returns the context to show dialogs over, evaluated when a screen is asked for, because the call screen is
/// on top of the app while the agent talks.
Map<String, KerabieScreenHandler> builtInAgentScreens(BuildContext Function() context) => {
      'show_items': (payload) => _showItems(context(), payload),
      'confirm_action': (payload) => _confirm(context(), payload),
      'request_address_input': (payload) => _typeAddress(context()),
    };

Future<String> _showItems(BuildContext context, Map<String, dynamic> payload) async {
  final items = (payload['items'] as List? ?? const []).whereType<Map>().toList();
  final answer = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(payload['title']?.toString() ?? 'Choose one'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: item['image'] is String && (item['image'] as String).isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(item['image'] as String, width: 48, height: 48, fit: BoxFit.cover))
                    : null,
                title: Text(item['name']?.toString() ?? ''),
                subtitle: item['subtitle'] == null ? null : Text(item['subtitle'].toString()),
                trailing: item['price'] == null ? null : Text(item['price'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.of(ctx).pop(item['id']?.toString()),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop('none'), child: const Text('Close'))],
    ),
  );
  return answer ?? 'none';
}

Future<String> _confirm(BuildContext context, Map<String, dynamic> payload) async {
  final answer = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Please confirm'),
      content: Text(payload['summary']?.toString() ?? ''),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
      ],
    ),
  );
  return answer == true ? 'yes' : 'no';
}

Future<String> _typeAddress(BuildContext context) async {
  final answer = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => const _AddressDialog(),
  );
  return answer == null || answer.trim().isEmpty ? 'none' : answer.trim();
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Type your address'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'House number, street, area, city'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop('none'), child: const Text('Cancel')),
        FilledButton(
          onPressed: _controller.text.trim().length < 5 ? null : () => Navigator.of(context).pop(_controller.text),
          child: const Text('Use this address'),
        ),
      ],
    );
  }
}
