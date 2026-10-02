import 'business_profile.dart';
import 'order_record.dart';
import 'reporting.dart';

/// The receipt as plain text, for sending to a customer by message or
/// pasting into a note. It carries the same lines as the on-screen receipt.
String receiptText(OrderRecord order, BusinessProfile business) {
  final lines = <String>[
    business.tradeName,
    ...business.receiptLines,
    '',
    '${order.id} · ${order.dateTimeLabel}',
    if (order.invoiceNumber.isNotEmpty) 'Invoice ${order.invoiceNumber}',
    '${order.type} · ${order.customerOrTable}',
    'Handled by ${order.employee}',
    '',
    for (final item in order.items) ...[
      '${item.quantity} × ${item.productName}   '
          '${formatReportMoney(item.lineTotal)}',
      if (item.options.isNotEmpty) '   ${item.options.join(', ')}',
      if (item.note.trim().isNotEmpty) '   Note: ${item.note.trim()}',
    ],
    '',
    if (order.discountAmount > 0) ...[
      'Subtotal: ${formatReportMoney(order.subtotal)}',
      '${order.discountName.isEmpty ? 'Discount' : 'Discount (${order.discountName})'}: '
          '${formatReportMoney(-order.discountAmount)}',
    ],
    'Total: ${formatReportMoney(order.amount)}',
    if (order.paymentMethod.isNotEmpty) ...[
      'Paid by ${order.paymentMethod}: '
          '${formatReportMoney(order.amountReceived)}',
      if (order.changeAmount > 0)
        'Change: ${formatReportMoney(order.changeAmount)}',
    ],
    if (order.refundedAmount > 0)
      'Refunded: ${formatReportMoney(-order.refundedAmount)}',
  ];

  return lines.join('\n');
}
