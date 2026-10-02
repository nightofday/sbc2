import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/order_record.dart';
import '../../models/receipt_text.dart';
import 'business_profile_scope.dart';

/// Copies the receipt as text, so it can be sent to a customer by message
/// while printing is not set up.
class CopyReceiptButton extends StatelessWidget {
  final OrderRecord order;

  const CopyReceiptButton({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        final text = receiptText(order, BusinessProfileScope.of(context));
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Receipt copied.')));
      },
      icon: const Icon(Icons.copy_outlined, size: 17),
      label: const Text('Copy Receipt'),
    );
  }
}
