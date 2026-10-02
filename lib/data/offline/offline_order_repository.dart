import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../domain/repositories/offline_sales_queue.dart';
import '../../domain/repositories/order_repository.dart';
import '../../models/offline_sale.dart';
import '../../models/order_item.dart';
import '../../models/order_record.dart';
import '../../models/pos_checkout.dart';
import '../../models/pos_discount.dart';
import '../../models/pos_menu_item.dart';
import '../../models/pos_modifier.dart';
import '../../models/pos_payment_method.dart';
import '../../models/refund_preview.dart';
import '../../models/request_id.dart';
import '../../models/shift_cash_snapshot.dart';
import 'key_value_store.dart';

/// Who is using the till. The queue is kept per user because the server
/// records each sale under the account that sends it.
class OfflineIdentity {
  final String userId;
  final String displayName;

  const OfflineIdentity({required this.userId, required this.displayName});
}

/// Whether [error] means the server could not be reached or did not finish,
/// as opposed to the server answering "no". Only the first kind may be
/// retried or queued.
bool isConnectionFailure(Object error) {
  if (error is OfflineUnavailableException) return false;
  if (error is OfflineSalesPendingException) return false;
  if (error is CheckoutSavedException) return false;
  if (error is FormatException) return false;
  if (error is UnsupportedError) return false;

  if (error is PostgrestException) {
    final code = error.code;
    if (!isServerRejectionCode(code)) return true;

    // An expired sign-in is repaired by the client refreshing its token.
    if (code!.startsWith('PGRST3')) return true;

    // Connection, resource, operator and serialization classes are the
    // server being busy or restarting, not a decision about the request.
    const transientClasses = ['08', '40', '53', '57', '58'];
    return transientClasses.contains(code.substring(0, 2));
  }

  return true;
}

/// The till's order repository. It passes everything to the server while
/// there is a connection, keeps a copy of what the till needs to keep
/// selling, and when the server cannot be reached it stores the sale on the
/// device and sends it later under the same request ID.
///
/// Only taking a sale works offline. Voids, refunds, cash movements and
/// closing a shift need the server.
class OfflineOrderRepository extends ChangeNotifier
    implements OrderRepository, OfflineSalesQueue {
  static const _salesKey = 'offline.sales.v1';
  static const _menuKey = 'offline.cache.menu.v1';
  static const _paymentMethodsKey = 'offline.cache.payment_methods.v1';
  static const _discountsKey = 'offline.cache.discounts.v1';
  static const _modifiersKey = 'offline.cache.modifiers.v1';
  static const _shiftPrefix = 'offline.shift.v1.';
  static const _shiftStartPrefix = 'offline.shift_start.v1.';
  static const _localShiftPrefix = 'offline-shift-';

  final OrderRepository _remote;
  final OfflineSaleUploader _uploader;
  final KeyValueStore _store;
  final OfflineIdentity? Function() _identity;
  final DateTime Function() _now;

  /// How long a server call may take before it counts as unreachable.
  final Duration requestTimeout;

  /// How often waiting sales are sent again while the server is unreachable.
  final Duration retryInterval;

  List<OfflineSale> _sales = [];
  Map<String, List<PosModifierGroup>> _modifierCache = {};
  bool _offline = false;
  bool _syncing = false;
  bool _prefetchingModifiers = false;
  bool _disposed = false;
  Timer? _retryTimer;

  OfflineOrderRepository({
    required this._remote,
    required this._uploader,
    required this._store,
    required this._identity,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 15),
    this.retryInterval = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now {
    _sales = _readSales();
    _modifierCache = _readModifierCache();
    _scheduleRetry();
  }

  // ---------------------------------------------------------------- queue

  @override
  bool get isOffline => _offline;

  @override
  bool get isSyncing => _syncing;

  @override
  List<OfflineSale> get waitingSales =>
      _mySales.where((sale) => !sale.isRejected).toList();

  @override
  List<OfflineSale> get rejectedSales =>
      _mySales.where((sale) => sale.isRejected).toList();

  Iterable<OfflineSale> get _mySales {
    final userId = _identity()?.userId;
    if (userId == null) return const [];
    return _sales.where((sale) => sale.userId == userId);
  }

  bool get _hasWorkToSend {
    final userId = _identity()?.userId;
    if (userId == null) return false;
    return waitingSales.isNotEmpty || _pendingShiftStart(userId) != null;
  }

  @override
  Future<void> syncPending() async {
    if (_syncing || _disposed) return;

    final userId = _identity()?.userId;
    if (userId == null || !_hasWorkToSend) return;

    _syncing = true;
    notifyListeners();

    try {
      if (!await _sendPendingShiftStart(userId)) return;

      // Oldest first, so stock and the cash drawer move in the order the
      // sales were made.
      final queue = waitingSales
        ..sort((a, b) => a.soldAt.compareTo(b.soldAt));

      for (final sale in queue) {
        try {
          await _uploader.uploadOfflineSale(sale).timeout(requestTimeout);
          _sales.removeWhere((entry) => entry.requestId == sale.requestId);
          await _writeSales();
          _setOffline(false);
        } catch (error) {
          if (isConnectionFailure(error)) {
            _setOffline(true);
            return;
          }

          // The server answered and refused this sale. It stays on the
          // device for a manager; the rest of the queue carries on.
          await _replaceSale(sale.withRejection(_messageOf(error)));
        }
      }
    } finally {
      _syncing = false;
      _scheduleRetry();
      notifyListeners();
    }
  }

  @override
  Future<void> retrySale(String requestId) async {
    final index = _sales.indexWhere((sale) => sale.requestId == requestId);
    if (index < 0) return;

    await _replaceSale(_sales[index].withRejection(''));
    notifyListeners();
    await syncPending();
  }

  @override
  Future<void> discardSale(String requestId) async {
    _sales.removeWhere(
      (sale) => sale.requestId == requestId && sale.isRejected,
    );
    await _writeSales();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }

  /// A sync can still be finishing when the app is torn down.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_disposed || !_hasWorkToSend) return;

    _retryTimer = Timer(retryInterval, () {
      unawaited(syncPending());
    });
  }

  void _setOffline(bool value) {
    if (_offline == value) return;
    _offline = value;
    notifyListeners();
  }

  /// Runs a server call, noting whether the server could be reached.
  Future<T> _online<T>(Future<T> Function() call) async {
    try {
      final result = await call().timeout(requestTimeout);
      final wasOffline = _offline;
      _setOffline(false);
      if (wasOffline && _hasWorkToSend) unawaited(syncPending());
      return result;
    } catch (error) {
      if (isConnectionFailure(error)) _setOffline(true);
      rethrow;
    }
  }

  /// Runs a server read, keeps its answer, and falls back to the kept answer
  /// when the server cannot be reached.
  Future<T> _cached<T>({
    required Future<T> Function() fetch,
    required Future<void> Function(T value) save,
    required T? Function() load,
  }) async {
    try {
      final value = await _online(fetch);
      await save(value);
      return value;
    } catch (error) {
      if (!isConnectionFailure(error)) rethrow;
      final kept = load();
      if (kept == null) rethrow;
      return kept;
    }
  }

  // ---------------------------------------------------------- till reads

  @override
  Future<List<PosMenuItem>> getPosMenu() async {
    final menu = await _cached<List<PosMenuItem>>(
      fetch: _remote.getPosMenu,
      save: (items) => _store.write(
        _menuKey,
        jsonEncode(items.map((item) => item.toMap()).toList()),
      ),
      // Stock levels kept from an earlier visit are stale, so the cached
      // menu carries none and the till does not block on them.
      load: () => _readList(
        _menuKey,
        PosMenuItem.fromMap,
      )?.map((item) => item.withAvailableQuantity(null)).toList(),
    );

    if (!_offline) unawaited(_prefetchModifiers(menu));
    return menu;
  }

  @override
  Future<List<PosPaymentMethod>> getPaymentMethods() {
    return _cached<List<PosPaymentMethod>>(
      fetch: _remote.getPaymentMethods,
      save: (methods) => _store.write(
        _paymentMethodsKey,
        jsonEncode(methods.map((method) => method.toMap()).toList()),
      ),
      load: () => _readList(_paymentMethodsKey, PosPaymentMethod.fromMap),
    );
  }

  @override
  Future<List<PosDiscountType>> getPosDiscountTypes() {
    return _cached<List<PosDiscountType>>(
      fetch: _remote.getPosDiscountTypes,
      save: (types) => _store.write(
        _discountsKey,
        jsonEncode(types.map((type) => type.toMap()).toList()),
      ),
      load: () => _readList(_discountsKey, PosDiscountType.fromMap),
    );
  }

  @override
  Future<List<PosModifierGroup>> getModifierGroups(String menuItemId) {
    return _cached<List<PosModifierGroup>>(
      fetch: () => _remote.getModifierGroups(menuItemId),
      save: (groups) => _rememberModifiers(menuItemId, groups),
      load: () => _modifierCache[menuItemId],
    );
  }

  /// Loads the options of every product once the menu is known, so a
  /// product never opened before can still be sold offline.
  Future<void> _prefetchModifiers(List<PosMenuItem> menu) async {
    if (_prefetchingModifiers) return;
    _prefetchingModifiers = true;

    try {
      final menuItemIds = menu.map((item) => item.menuItemId).toSet();
      for (final menuItemId in menuItemIds) {
        if (_modifierCache.containsKey(menuItemId)) continue;
        final groups = await _remote
            .getModifierGroups(menuItemId)
            .timeout(requestTimeout);
        await _rememberModifiers(menuItemId, groups);
      }
    } catch (_) {
      // Best effort: whatever was loaded is kept and the rest is fetched
      // the next time the menu loads.
    } finally {
      _prefetchingModifiers = false;
    }
  }

  Future<void> _rememberModifiers(
    String menuItemId,
    List<PosModifierGroup> groups,
  ) async {
    _modifierCache[menuItemId] = groups;
    await _store.write(
      _modifiersKey,
      jsonEncode({
        for (final entry in _modifierCache.entries)
          entry.key: entry.value.map((group) => group.toMap()).toList(),
      }),
    );
  }

  // --------------------------------------------------------------- shift

  @override
  Future<String?> getOpenShiftId() async {
    final userId = _identity()?.userId;

    try {
      final shiftId = await _online(_remote.getOpenShiftId);
      if (userId != null) {
        if (shiftId == null && _pendingShiftStart(userId) != null) {
          // The shift opened offline has not reached the server yet.
          return _store.read('$_shiftPrefix$userId');
        }
        await _rememberShift(userId, shiftId);
      }
      return shiftId;
    } catch (error) {
      if (!isConnectionFailure(error) || userId == null) rethrow;
      return _store.read('$_shiftPrefix$userId');
    }
  }

  @override
  Future<String> startShift({
    double? openingCash,
    String? clientRequestId,
  }) async {
    final userId = _identity()?.userId;
    final requestId = clientRequestId ?? newRequestId();

    try {
      final shiftId = await _online(
        () => _remote.startShift(
          openingCash: openingCash,
          clientRequestId: requestId,
        ),
      );
      if (userId != null) await _rememberShift(userId, shiftId);
      return shiftId;
    } catch (error) {
      if (!isConnectionFailure(error) || userId == null) rethrow;

      // Opened on the device now and on the server when it is reachable,
      // under the same request ID so it cannot open twice.
      final localId = '$_localShiftPrefix$requestId';
      await _store.write(
        '$_shiftStartPrefix$userId',
        jsonEncode({'request_id': requestId, 'opening_cash': openingCash}),
      );
      await _store.write('$_shiftPrefix$userId', localId);
      _scheduleRetry();
      notifyListeners();
      return localId;
    }
  }

  @override
  Future<void> endShift({
    required String shiftId,
    double? closingCashCounted,
    String notes = '',
    String? clientRequestId,
  }) async {
    // A shift is counted against its sales, so every sale has to be on the
    // server before it can close.
    await syncPending();

    final unsent = _mySales.length;
    if (unsent > 0) throw OfflineSalesPendingException(unsent);

    final serverShiftId = _serverShiftId(shiftId);
    await _online(
      () => _remote.endShift(
        shiftId: serverShiftId,
        closingCashCounted: closingCashCounted,
        notes: notes,
        clientRequestId: clientRequestId,
      ),
    );

    final userId = _identity()?.userId;
    if (userId != null) await _rememberShift(userId, null);
  }

  @override
  Future<ShiftCashSnapshot> getShiftCashSnapshot(String shiftId) async {
    await syncPending();
    return _online(() => _remote.getShiftCashSnapshot(_serverShiftId(shiftId)));
  }

  @override
  Future<void> recordShiftCashMovement({
    required String shiftId,
    required String movementType,
    required double amount,
    required String reason,
    String? clientRequestId,
  }) async {
    await syncPending();
    await _online(
      () => _remote.recordShiftCashMovement(
        shiftId: _serverShiftId(shiftId),
        movementType: movementType,
        amount: amount,
        reason: reason,
        clientRequestId: clientRequestId,
      ),
    );
  }

  /// The server's ID for a shift, which for one opened offline is known
  /// only after it has been sent.
  String _serverShiftId(String shiftId) {
    if (!shiftId.startsWith(_localShiftPrefix)) return shiftId;

    final userId = _identity()?.userId;
    final current = userId == null ? null : _store.read('$_shiftPrefix$userId');
    if (current == null || current.startsWith(_localShiftPrefix)) {
      throw const OfflineUnavailableException(
        'This shift was opened offline and has not reached the server yet. '
        'Connect to the internet and try again.',
      );
    }
    return current;
  }

  Map<String, dynamic>? _pendingShiftStart(String userId) {
    final raw = _store.read('$_shiftStartPrefix$userId');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Returns false when the server could not be reached, so nothing after
  /// it should be attempted.
  Future<bool> _sendPendingShiftStart(String userId) async {
    final pending = _pendingShiftStart(userId);
    if (pending == null) return true;

    try {
      final shiftId = await _remote
          .startShift(
            openingCash: (pending['opening_cash'] as num?)?.toDouble(),
            clientRequestId: pending['request_id']?.toString(),
          )
          .timeout(requestTimeout);
      await _store.remove('$_shiftStartPrefix$userId');
      await _rememberShift(userId, shiftId);
      _setOffline(false);
      return true;
    } catch (error) {
      if (isConnectionFailure(error)) {
        _setOffline(true);
        return false;
      }

      // The server refused, usually because a shift is already open on
      // another device. The sales then belong to whatever shift is open.
      await _store.remove('$_shiftStartPrefix$userId');
      try {
        await _rememberShift(
          userId,
          await _remote.getOpenShiftId().timeout(requestTimeout),
        );
      } catch (_) {
        return false;
      }
      return true;
    }
  }

  Future<void> _rememberShift(String userId, String? shiftId) async {
    if (shiftId == null) {
      await _store.remove('$_shiftPrefix$userId');
    } else {
      await _store.write('$_shiftPrefix$userId', shiftId);
    }
  }

  // -------------------------------------------------------------- orders

  @override
  Future<OrderRecord> placeOrder({
    required String orderType,
    required List<PosCheckoutItem> items,
    required List<PosPaymentInput> payments,
    String tableNumber = '',
    String customerName = '',
    String deliveryReference = '',
    String notes = '',
    String discountTypeId = '',
    double? discountValue,
    String discountNotes = '',
    required String clientRequestId,
  }) async {
    final alreadyQueued = _sales
        .where((sale) => sale.requestId == clientRequestId)
        .firstOrNull;
    if (alreadyQueued != null) return alreadyQueued.toOrderRecord();

    final identity = _identity();

    // Anything still on the device goes first, so the server receives the
    // sales in the order they were made and a shift opened offline exists
    // before a sale is posted to it.
    if (_hasWorkToSend) await syncPending();
    final mustQueue = _hasWorkToSend;

    if (!mustQueue) {
      try {
        return await _online(
          () => _remote.placeOrder(
            orderType: orderType,
            items: items,
            payments: payments,
            tableNumber: tableNumber,
            customerName: customerName,
            deliveryReference: deliveryReference,
            notes: notes,
            discountTypeId: discountTypeId,
            discountValue: discountValue,
            discountNotes: discountNotes,
            clientRequestId: clientRequestId,
          ),
        );
      } catch (error) {
        if (!isConnectionFailure(error)) rethrow;
        if (identity == null || payments.length != 1) rethrow;
      }
    }

    if (identity == null) {
      throw const OfflineUnavailableException(
        'Sign in again before taking a sale.',
      );
    }

    // Not confirmed by the server. The sale may or may not have been
    // saved; either way sending it again under the same request ID gives
    // exactly one order.
    final sale = _buildSale(
      identity: identity,
      requestId: clientRequestId,
      orderType: orderType,
      items: items,
      payment: payments.first,
      tableNumber: tableNumber,
      customerName: customerName,
      deliveryReference: deliveryReference,
      notes: notes,
      discountTypeId: discountTypeId,
      discountValue: discountValue,
      discountNotes: discountNotes,
    );

    _sales.add(sale);
    await _writeSales();
    _scheduleRetry();
    notifyListeners();

    return sale.toOrderRecord();
  }

  OfflineSale _buildSale({
    required OfflineIdentity identity,
    required String requestId,
    required String orderType,
    required List<PosCheckoutItem> items,
    required PosPaymentInput payment,
    required String tableNumber,
    required String customerName,
    required String deliveryReference,
    required String notes,
    required String discountTypeId,
    required double? discountValue,
    required String discountNotes,
  }) {
    final menu = _readList(_menuKey, PosMenuItem.fromMap) ?? const [];
    final lines = <OrderItem>[];
    var subtotal = 0.0;

    for (final item in items) {
      final product = menu
          .where((entry) => entry.variantId == item.menuVariantId)
          .firstOrNull;

      var unitPrice = product?.price ?? 0;
      final optionNames = <String>[];

      if (product != null) {
        final options = (_modifierCache[product.menuItemId] ?? const [])
            .expand((group) => group.options);
        for (final option in options) {
          if (!item.modifierIds.contains(option.id)) continue;
          unitPrice += option.priceDelta;
          optionNames.add(option.name);
        }
      }

      final name = product == null
          ? 'Item'
          : product.variantName.trim().isEmpty ||
                product.variantName == product.name
          ? product.name
          : '${product.name} (${product.variantName})';

      lines.add(
        OrderItem(
          productId: item.menuVariantId,
          productName: optionNames.isEmpty
              ? name
              : '$name + ${optionNames.join(', ')}',
          unitPrice: unitPrice,
          quantity: item.quantity,
        ),
      );
      subtotal += unitPrice * item.quantity;
    }

    final method = (_readList(_paymentMethodsKey, PosPaymentMethod.fromMap) ??
            const <PosPaymentMethod>[])
        .where((entry) => entry.id == payment.paymentMethodId)
        .firstOrNull;
    final discount = (_readList(_discountsKey, PosDiscountType.fromMap) ??
            const <PosDiscountType>[])
        .where((entry) => entry.id == discountTypeId)
        .firstOrNull;

    return OfflineSale(
      requestId: requestId,
      userId: identity.userId,
      soldAt: _now(),
      orderType: orderType,
      items: items,
      payment: payment,
      // What the till charged is the amount the customer actually paid.
      subtotal: subtotal < payment.amount ? payment.amount : subtotal,
      total: payment.amount,
      lines: lines,
      tableNumber: tableNumber,
      customerName: customerName,
      deliveryReference: deliveryReference,
      notes: notes,
      discountTypeId: discountTypeId,
      discountValue: discountValue,
      discountNotes: discountNotes,
      employeeName: identity.displayName,
      paymentMethodName: method?.name ?? '',
      discountName: discount?.name ?? '',
    );
  }

  @override
  Future<List<OrderRecord>> getOrders() async {
    final local = _mySales.toList()
      ..sort((a, b) => b.soldAt.compareTo(a.soldAt));
    final localRecords = local.map((sale) => sale.toOrderRecord()).toList();

    try {
      final orders = await _online(_remote.getOrders);
      return [...localRecords, ...orders];
    } catch (error) {
      // Offline, the sales kept on this device are all that can be shown.
      if (!isConnectionFailure(error) || localRecords.isEmpty) rethrow;
      return localRecords;
    }
  }

  @override
  Future<OrderRecord?> getOrderById(String id) async {
    final local = _localSale(id);
    if (local != null) return local.toOrderRecord();
    return _online(() => _remote.getOrderById(id));
  }

  @override
  Future<OrderRecord?> findOrderByRequestId(String clientRequestId) async {
    final local = _sales
        .where((sale) => sale.requestId == clientRequestId)
        .firstOrNull;
    if (local != null) return local.toOrderRecord();
    return _online(() => _remote.findOrderByRequestId(clientRequestId));
  }

  OfflineSale? _localSale(String id) {
    return _sales.where((sale) => sale.reference == id).firstOrNull;
  }

  void _requireSynced(String id) {
    if (_localSale(id) == null) return;
    throw const OfflineUnavailableException(
      'This sale has not reached the server yet. It can be voided or '
      'refunded once it has synced and has an order number.',
    );
  }

  @override
  Future<void> createOrder(OrderRecord order) => _remote.createOrder(order);

  @override
  Future<void> updateOrder(OrderRecord order) => _remote.updateOrder(order);

  @override
  Future<void> voidOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
  }) {
    _requireSynced(id);
    return _online(
      () => _remote.voidOrder(id, reason: reason, authorizedBy: authorizedBy),
    );
  }

  @override
  Future<void> refundOrder(
    String id, {
    String reason = '',
    String authorizedBy = '',
    String? clientRequestId,
  }) {
    _requireSynced(id);
    return _online(
      () => _remote.refundOrder(
        id,
        reason: reason,
        authorizedBy: authorizedBy,
        clientRequestId: clientRequestId,
      ),
    );
  }

  @override
  Future<RefundPreview> getRefundPreview(String id) {
    _requireSynced(id);
    return _online(() => _remote.getRefundPreview(id));
  }

  @override
  Future<List<RefundRestockCandidate>> getRefundRestockCandidates(String id) {
    _requireSynced(id);
    return _online(() => _remote.getRefundRestockCandidates(id));
  }

  @override
  Future<void> approveRefundItemRestock(
    String refundItemId, {
    String notes = '',
  }) {
    return _online(
      () => _remote.approveRefundItemRestock(refundItemId, notes: notes),
    );
  }

  @override
  Future<void> refundOrderItems(
    String id, {
    required Map<String, double> quantities,
    required String reason,
    String externalReference = '',
    String? clientRequestId,
  }) {
    _requireSynced(id);
    return _online(
      () => _remote.refundOrderItems(
        id,
        quantities: quantities,
        reason: reason,
        externalReference: externalReference,
        clientRequestId: clientRequestId,
      ),
    );
  }

  // ------------------------------------------------------------- storage

  List<OfflineSale> _readSales() {
    final raw = _store.read(_salesKey);
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .map(
            (entry) =>
                OfflineSale.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
    } catch (_) {
      // Unreadable data is left in place rather than overwritten, so it can
      // still be recovered by hand.
      return [];
    }
  }

  Future<void> _writeSales() {
    return _store.write(
      _salesKey,
      jsonEncode(_sales.map((sale) => sale.toJson()).toList()),
    );
  }

  Future<void> _replaceSale(OfflineSale sale) async {
    final index = _sales.indexWhere(
      (entry) => entry.requestId == sale.requestId,
    );
    if (index < 0) return;
    _sales[index] = sale;
    await _writeSales();
  }

  Map<String, List<PosModifierGroup>> _readModifierCache() {
    final raw = _store.read(_modifiersKey);
    if (raw == null) return {};

    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return decoded.map(
        (menuItemId, groups) => MapEntry(
          menuItemId,
          (groups as List)
              .map(
                (group) => PosModifierGroup.fromMap(
                  Map<String, dynamic>.from(group as Map),
                ),
              )
              .toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  List<T>? _readList<T>(
    String key,
    T Function(Map<String, dynamic> map) fromMap,
  ) {
    final raw = _store.read(key);
    if (raw == null) return null;

    try {
      return (jsonDecode(raw) as List)
          .map((entry) => fromMap(Map<String, dynamic>.from(entry as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  String _messageOf(Object error) {
    if (error is PostgrestException) return error.message;
    return error.toString();
  }
}
