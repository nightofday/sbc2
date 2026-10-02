/// One field that changed, with its value before and after.
class AuditChange {
  final String field;
  final String before;
  final String after;

  const AuditChange({
    required this.field,
    required this.before,
    required this.after,
  });
}

/// One row of the audit trail: who did what, to which record, and when.
class AuditEntry {
  final String id;
  final DateTime createdAt;
  final String actorName;
  final String actionCode;
  final String entityType;
  final String label;
  final Map<String, dynamic> oldData;
  final Map<String, dynamic> newData;

  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.actorName,
    required this.actionCode,
    required this.entityType,
    required this.label,
    required this.oldData,
    required this.newData,
  });

  factory AuditEntry.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> data(String key) =>
        map[key] is Map ? Map<String, dynamic>.from(map[key] as Map) : const {};

    return AuditEntry(
      id: map['id']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      actorName: map['actor_name']?.toString() ?? 'Unknown',
      actionCode: map['action_code']?.toString() ?? '',
      entityType: map['entity_type']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      oldData: data('old_data'),
      newData: data('new_data'),
    );
  }

  static const _things = {
    'menu_items': 'Product',
    'menu_variants': 'Product size',
    'modifier_groups': 'Option group',
    'modifiers': 'Option',
    'discount_types': 'Discount',
    'payment_methods': 'Payment method',
    'suppliers': 'Supplier',
    'inventory_items': 'Stock item',
    'profiles': 'Staff account',
    'system_settings': 'Setting',
    'business_profile': 'Business details',
  };

  static const _actions = {
    'ORDER_CHECKOUT': 'Sale completed',
    'ORDER_REFUND': 'Refund made',
    'ORDER_VOIDED': 'Order voided',
    'SHIFT_STARTED': 'Shift opened',
    'SHIFT_ENDED': 'Shift closed',
    'SHIFT_CASH_MOVEMENT': 'Cash moved in or out of the drawer',
    'GOODS_RECEIPT_POSTED': 'Stock received',
    'GOODS_RECEIPT_VOIDED': 'Stock receipt voided',
    'STOCK_OUT_POSTED': 'Supplies released',
    'STOCK_OUT_VOIDED': 'Supply release voided',
    'STOCK_COUNT_POSTED': 'Stock count posted',
    'STOCK_COUNT_VOIDED': 'Stock count voided',
    'EXPENSE_UPDATED': 'Expense edited',
    'EXPENSE_VOIDED': 'Expense voided',
    'OFFLINE_SALE_SYNCED': 'Offline sale received',
    'OFFLINE_SALE_TOTAL_DIFFERENCE':
        'Offline sale total differed from the till',
    'CATEGORY_CREATED': 'Category added',
    'CATEGORY_UPDATED': 'Category changed',
    'CATEGORIES_REORDERED': 'Categories reordered',
    'SUPPLIER_PAYMENT_REVERSED': 'Supplier payment reversed',
    'LOT_DISPOSAL_VOIDED': 'Stock write-off reversed',
    'FIRST_ADMIN_BOOTSTRAPPED': 'First administrator set up',
  };

  /// What happened, in plain words.
  String get title {
    final known = _actions[actionCode];
    if (known != null) return known;

    final thing = _things[entityType];
    if (thing != null && actionCode.endsWith('_CREATED')) return '$thing added';
    if (thing != null && actionCode.endsWith('_UPDATED')) {
      return '$thing changed';
    }

    return _words(actionCode);
  }

  /// The fields that changed. For other events, the details recorded.
  List<AuditChange> get changes {
    if (actionCode.endsWith('_CREATED') && oldData.isEmpty) return const [];

    final keys = oldData.isNotEmpty ? oldData.keys : newData.keys;
    return [
      for (final key in keys)
        if (!_hidden(key))
          AuditChange(
            field: _words(key),
            before: oldData.isEmpty ? '' : _value(oldData[key]),
            after: _value(newData[key]),
          ),
    ];
  }

  // Internal identifiers mean nothing to a reader.
  static bool _hidden(String key) =>
      key == 'id' || key == 'updated_by' || key.endsWith('_id');

  static String _words(String code) {
    final text = code.replaceAll('_', ' ').toLowerCase().trim();
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  static String _value(dynamic value) {
    if (value == null) return 'empty';
    if (value is bool) return value ? 'yes' : 'no';
    if (value is Map || value is List) return value.toString();
    final text = value.toString();
    return text.isEmpty ? 'empty' : text;
  }
}
