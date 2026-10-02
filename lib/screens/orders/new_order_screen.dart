import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/order_repository.dart';
import '../../models/order_record.dart';
import '../../models/pos_checkout.dart';
import '../../models/pos_discount.dart';
import '../../models/pos_menu_item.dart';
import '../../models/pos_modifier.dart';
import '../../models/pos_payment_method.dart';
import '../../models/request_id.dart';
import '../../widgets/common/app_dialog.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/layout/header_brand_motif.dart';

class NewOrderScreen extends StatefulWidget {
  final OrderRepository orderRepository;

  const NewOrderScreen({super.key, required this.orderRepository});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final _searchController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _tableNumberController = TextEditingController();
  final _deliveryReferenceController = TextEditingController();

  final List<_PosCartLine> _cart = [];

  late Future<List<PosMenuItem>> _menuFuture;
  late Future<List<PosPaymentMethod>> _paymentMethodsFuture;
  late Future<List<PosDiscountType>> _discountTypesFuture;

  String _selectedCategory = 'All';
  String _orderType = 'Dine In';
  String _searchQuery = '';
  String? _openShiftId;
  bool _loadingShift = true;
  bool _startingShift = false;
  bool _endingShift = false;
  bool _submittingOrder = false;
  final CheckoutAttempt _checkoutAttempt = CheckoutAttempt();
  String? _startShiftRequestId;

  @override
  void initState() {
    super.initState();
    _reloadPosData();
    _loadShift();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerNameController.dispose();
    _tableNumberController.dispose();
    _deliveryReferenceController.dispose();
    super.dispose();
  }

  void _reloadPosData() {
    _menuFuture = widget.orderRepository.getPosMenu();
    _paymentMethodsFuture = widget.orderRepository.getPaymentMethods();
    _discountTypesFuture = widget.orderRepository.getPosDiscountTypes();
  }

  Future<void> _loadShift() async {
    try {
      final id = await widget.orderRepository.getOpenShiftId();
      if (!mounted) return;
      setState(() {
        _openShiftId = id;
        _loadingShift = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingShift = false);
      _showError(error.toString());
    }
  }

  Future<void> _startShift() async {
    if (_startingShift) return;
    setState(() => _startingShift = true);

    try {
      final id = await widget.orderRepository.startShift(
        clientRequestId: _startShiftRequestId ??= newRequestId(),
      );
      _startShiftRequestId = null;
      if (!mounted) return;
      setState(() => _openShiftId = id);
      _showMessage('Shift started successfully.');
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _startingShift = false);
    }
  }

  Future<void> _showEndShiftDialog() async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final shiftId = _openShiftId;
    if (shiftId == null || _endingShift) return;

    final cashController = TextEditingController();
    final notesController = TextEditingController();
    String? errorMessage;
    StateSetter? dialogSetState;

    try {
      final snapshot = await widget.orderRepository.getShiftCashSnapshot(
        shiftId,
      );

      if (!mounted) return;

      await showPrototypeDialog(
        context: context,
        title: 'End Shift',
        width: 560,
        content: StatefulBuilder(
          builder: (_, setDialogState) {
            dialogSetState = setDialogState;

            final rawCash = cashController.text.trim();
            final countedCash = rawCash.isEmpty
                ? null
                : double.tryParse(rawCash);
            final variance = countedCash == null
                ? null
                : countedCash - snapshot.expectedCash;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.gray200),
                    ),
                    child: Column(
                      children: [
                        _paymentInfoRow(
                          'Opening Cash',
                          _money(snapshot.openingCash),
                        ),
                        _paymentInfoRow(
                          'Cash Sales',
                          _money(snapshot.cashSales),
                        ),
                        _paymentInfoRow(
                          'Cash Refunds',
                          _money(snapshot.cashRefunds),
                        ),
                        _paymentInfoRow(
                          'Pay-ins / Corrections',
                          _money(snapshot.cashIn),
                        ),
                        _paymentInfoRow(
                          'Pay-outs / Cash Drops',
                          _money(snapshot.cashOut),
                        ),
                        const Divider(),
                        _paymentInfoRow(
                          'Expected Closing Cash',
                          _money(snapshot.expectedCash),
                          emphasized: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cashController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      setDialogState(() => errorMessage = null);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Counted Closing Cash',
                      prefixText: '₱',
                      helperText: 'Optional for now, but entering it records the cash variance.',
                    ),
                  ),
                  if (variance != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: variance.abs() < 0.01
                            ? const Color(0xFFEAF7EE)
                            : AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _paymentInfoRow(
                        'Cash Variance',
                        _signedMoney(variance),
                        emphasized: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Closing Notes',
                      hintText: 'Optional explanation for cash differences or handover notes...',
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: _endingShift ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _endingShift
                ? null
                : () async {
                    final rawCash = cashController.text.trim();
                    final cash = rawCash.isEmpty
                        ? null
                        : double.tryParse(rawCash);

                    if (rawCash.isNotEmpty && cash == null) {
                      dialogSetState?.call(() {
                        errorMessage = 'Enter a valid closing cash amount.';
                      });
                      return;
                    }

                    if (cash != null && cash < 0) {
                      dialogSetState?.call(() {
                        errorMessage = 'Closing cash cannot be negative.';
                      });
                      return;
                    }

                    setState(() => _endingShift = true);

                    try {
                      await widget.orderRepository.endShift(
                        clientRequestId: requestId,
                        shiftId: shiftId,
                        closingCashCounted: cash,
                        notes: notesController.text.trim(),
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                      setState(() {
                        _openShiftId = null;
                        _cart.clear();
                      });

                      if (cash == null) {
                        _showMessage('Shift ended successfully.');
                      } else {
                        final variance = cash - snapshot.expectedCash;
                        _showMessage(
                          'Shift ended. Cash variance: ${_signedMoney(variance)}',
                        );
                      }
                    } on PostgrestException catch (error) {
                      dialogSetState?.call(() {
                        errorMessage = error.message;
                      });
                    } catch (error) {
                      dialogSetState?.call(() {
                        errorMessage = error.toString();
                      });
                    } finally {
                      if (mounted) setState(() => _endingShift = false);
                    }
                  },
            child: _endingShift
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('End Shift'),
          ),
        ],
      );
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      cashController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showCashMovementDialog() async {
    // One ID per form, so saving it again after a lost response
    // returns the stored result instead of posting twice.
    final requestId = newRequestId();

    final shiftId = _openShiftId;
    if (shiftId == null) return;

    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    var movementType = 'PAY_IN';
    String? errorMessage;
    StateSetter? dialogSetState;

    try {
      final snapshot = await widget.orderRepository.getShiftCashSnapshot(
        shiftId,
      );

      if (!mounted) return;

      await showPrototypeDialog(
        context: context,
        title: 'Cash Movement',
        width: 560,
        content: StatefulBuilder(
          builder: (_, setDialogState) {
            dialogSetState = setDialogState;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _paymentInfoRow(
                          'Opening Cash',
                          _money(snapshot.openingCash),
                        ),
                        _paymentInfoRow(
                          'Cash Sales',
                          _money(snapshot.cashSales),
                        ),
                        _paymentInfoRow(
                          'Cash Refunds',
                          _money(snapshot.cashRefunds),
                        ),
                        _paymentInfoRow(
                          'Pay-ins / Corrections',
                          _money(snapshot.cashIn),
                        ),
                        _paymentInfoRow(
                          'Pay-outs / Cash Drops',
                          _money(snapshot.cashOut),
                        ),
                        const Divider(),
                        _paymentInfoRow(
                          'Expected Cash',
                          _money(snapshot.expectedCash),
                          emphasized: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: movementType,
                    decoration: const InputDecoration(
                      labelText: 'Movement Type',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'PAY_IN', child: Text('Pay In')),
                      DropdownMenuItem(
                        value: 'PAY_OUT',
                        child: Text('Pay Out'),
                      ),
                      DropdownMenuItem(
                        value: 'CASH_DROP',
                        child: Text('Cash Drop'),
                      ),
                      DropdownMenuItem(
                        value: 'CORRECTION',
                        child: Text('Positive Correction'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        movementType = value;
                        errorMessage = null;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount *',
                      prefixText: '₱',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Reason *'),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim());
              final reason = reasonController.text.trim();

              if (amount == null || amount <= 0 || reason.isEmpty) {
                dialogSetState?.call(() {
                  errorMessage =
                      'Enter an amount greater than zero and a reason.';
                });
                return;
              }

              try {
                await widget.orderRepository.recordShiftCashMovement(
                  clientRequestId: requestId,
                  shiftId: shiftId,
                  movementType: movementType,
                  amount: amount,
                  reason: reason,
                );

                if (!mounted) return;
                Navigator.pop(context);
                _showMessage('Cash movement recorded.');
              } on PostgrestException catch (error) {
                dialogSetState?.call(() {
                  errorMessage = error.message;
                });
              } catch (error) {
                dialogSetState?.call(() {
                  errorMessage = error.toString();
                });
              }
            },
            child: const Text('Record Movement'),
          ),
        ],
      );
    } on PostgrestException catch (error) {
      if (mounted) _showError(error.message);
    } catch (error) {
      if (mounted) _showError(error.toString());
    }

    amountController.dispose();
    reasonController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_checkoutAttempt.hasUnresolved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _showError(
            'The last payment is not confirmed yet. Open payment and tap '
            'Complete Payment again before leaving this screen.',
          );
        }
      },
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray100,
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: HeaderBrandMotif(),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 16 : AppSpacing.page,
              ),
              child: FutureBuilder<List<PosMenuItem>>(
                future: _menuFuture,
                builder: (context, snapshot) {
                  final menu = snapshot.data ?? const <PosMenuItem>[];

                  return Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final title = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => Navigator.maybePop(context),
                                icon: const Icon(Icons.arrow_back),
                              ),
                              const SizedBox(width: 8),
                              const Text('New Order', style: AppTextStyles.h1),
                            ],
                          );

                          if (constraints.maxWidth < 760) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                title,
                                const SizedBox(height: 10),
                                _buildShiftStatus(),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              title,
                              const Spacer(),
                              _buildShiftStatus(),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError)
                        Expanded(child: _buildLoadError(snapshot.error))
                      else if (menu.isEmpty)
                        Expanded(
                          child: _buildLoadError(
                            'No active menu items are available.',
                          ),
                        )
                      else
                        Expanded(child: _buildOrderWorkspace(menu)),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftStatus() {
    if (_loadingShift) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_openShiftId != null) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7EE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Shift Active',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.success,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _showCashMovementDialog,
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Cash'),
          ),
          OutlinedButton.icon(
            onPressed: _endingShift ? null : _showEndShiftDialog,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('End Shift'),
          ),
        ],
      );
    }

    return ElevatedButton.icon(
      onPressed: _startingShift ? null : _startShift,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text(_startingShift ? 'Starting...' : 'Start Shift'),
    );
  }

  Widget _buildOrderWorkspace(List<PosMenuItem> menu) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Products'),
                    Tab(text: 'Current Order'),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildProductsPanel(menu),
                      _buildCurrentOrderPanel(),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildProductsPanel(menu)),
            const SizedBox(width: 20),
            SizedBox(width: 410, child: _buildCurrentOrderPanel()),
          ],
        );
      },
    );
  }

  Widget _buildLoadError(Object? error) {
    return Center(
      child: SizedBox(
        width: 500,
        child: SectionCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.primary,
                size: 40,
              ),
              const SizedBox(height: 12),
              const Text('Unable to load POS data', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'Unknown error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(_reloadPosData);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsPanel(List<PosMenuItem> menu) {
    final categories = <String>[
      'All',
      ...(menu.map((item) => item.category).toSet().toList()..sort()),
    ];

    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final query = _searchQuery.trim().toLowerCase();
    final products = menu.where((item) {
      final categoryMatches =
          _selectedCategory == 'All' || item.category == _selectedCategory;
      final searchMatches =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.variantName.toLowerCase().contains(query) ||
          item.sku.toLowerCase().contains(query);
      return categoryMatches && searchMatches;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Products', style: AppTextStyles.h3),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search products...',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final category = categories[index];
              return ChoiceChip(
                label: Text(category),
                selected: category == _selectedCategory,
                onSelected: (_) {
                  setState(() => _selectedCategory = category);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: products.isEmpty
              ? const Center(child: Text('No products found.'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 420
                        ? 1
                        : constraints.maxWidth < 720
                        ? 2
                        : 3;

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        mainAxisExtent: 200,
                      ),
                      itemCount: products.length,
                      itemBuilder: (_, index) =>
                          _buildProductCard(products[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductCard(PosMenuItem product) {
    final variantLabel = product.variantName.trim().isEmpty
        ? product.category
        : '${product.category} • ${product.variantName}';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconForCategory(product.category),
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            product.name,
            style: AppTextStyles.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            variantLabel,
            style: AppTextStyles.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (product.tracksInventory) ...[
            const SizedBox(height: 4),
            Text(
              product.isOutOfStock
                  ? 'Out of stock'
                  : '${_quantity(product.availableQuantity ?? 0)} available',
              style: AppTextStyles.caption.copyWith(
                color: product.isOutOfStock
                    ? AppColors.primary
                    : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              Text(
                _money(product.price),
                style: AppTextStyles.h3.copyWith(color: AppColors.primary),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: product.isOutOfStock
                    ? null
                    : () => _addProduct(product),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOrderPanel() {
    final total = _cart.fold<double>(0, (sum, line) => sum + line.lineTotal);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current Order', style: AppTextStyles.h2),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _orderType,
            decoration: const InputDecoration(labelText: 'Order Type'),
            items: const [
              DropdownMenuItem(value: 'Dine In', child: Text('Dine In')),
              DropdownMenuItem(value: 'Take Out', child: Text('Take Out')),
              DropdownMenuItem(value: 'Delivery', child: Text('Delivery')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _orderType = value);
            },
          ),
          const SizedBox(height: 12),
          _buildOrderIdentityFields(),
          const SizedBox(height: 14),
          const Divider(),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Text(
                      'No items added yet.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.gray500,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (_, index) =>
                        _buildCartItem(_cart[index], index),
                  ),
          ),
          const Divider(),
          _summaryRow('Subtotal', _money(total)),
          const SizedBox(height: 7),
          _summaryRow('Total', _money(total), emphasized: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _cart.isEmpty || _openShiftId == null
                  ? null
                  : _showPaymentDialog,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: Text(
                _openShiftId == null
                    ? 'Start Shift to Continue'
                    : 'Proceed to Payment',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderIdentityFields() {
    if (_orderType == 'Dine In') {
      return Column(
        children: [
          TextField(
            controller: _tableNumberController,
            decoration: const InputDecoration(labelText: 'Table Number *'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customerNameController,
            decoration: const InputDecoration(
              labelText: 'Customer Name',
              hintText: 'Optional',
            ),
          ),
        ],
      );
    }

    if (_orderType == 'Delivery') {
      return Column(
        children: [
          TextField(
            controller: _customerNameController,
            decoration: const InputDecoration(
              labelText: 'Customer / Recipient Name *',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _deliveryReferenceController,
            decoration: const InputDecoration(
              labelText: 'Delivery Reference / Platform',
            ),
          ),
        ],
      );
    }

    return TextField(
      controller: _customerNameController,
      decoration: const InputDecoration(labelText: 'Customer Name *'),
    );
  }

  Widget _buildCartItem(_PosCartLine line, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name, style: AppTextStyles.bodyMedium),
                Text(
                  '${line.product.variantName} • '
                  '${_money(line.unitPriceWithModifiers)} each • '
                  '${_money(line.lineTotal)}',
                  style: AppTextStyles.caption,
                ),
                if (line.modifiers.isNotEmpty)
                  Text(
                    line.modifiers.map((item) => item.name).join(', '),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
                if (line.specialInstructions.isNotEmpty)
                  Text(
                    'Note: ${line.specialInstructions}',
                    style: AppTextStyles.caption,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _decreaseLine(index),
            icon: const Icon(Icons.remove_circle_outline, size: 20),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '${line.quantity}',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ),
          IconButton(
            onPressed: () => _increaseLine(index),
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
          IconButton(
            onPressed: () => _removeLine(index),
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.primary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(PosMenuItem product) async {
    if (!_hasStockForAdditional(product, 1)) {
      _showError(
        '${product.name} only has '
        '${_quantity(product.availableQuantity ?? 0)} available.',
      );
      return;
    }

    List<PosModifierGroup> groups;
    try {
      groups = await widget.orderRepository.getModifierGroups(
        product.menuItemId,
      );
    } on PostgrestException catch (error) {
      _showError(error.message);
      return;
    }

    if (!mounted) return;

    if (groups.isEmpty) {
      _addOrMergeLine(
        _PosCartLine(
          product: product,
          quantity: 1,
          modifiers: const [],
          specialInstructions: '',
        ),
      );
      return;
    }

    final configured = await _showModifierDialog(product, groups);
    if (configured == null || !mounted) return;

    _addOrMergeLine(configured);
  }

  Future<_PosCartLine?> _showModifierDialog(
    PosMenuItem product,
    List<PosModifierGroup> groups,
  ) async {
    final selectedIds = <String>{};
    final instructionsController = TextEditingController();
    String? errorMessage;

    final result = await showSettledDialog<_PosCartLine>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              '${product.name} — ${product.variantName}',
              style: AppTextStyles.h2,
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final group in groups) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                          Text(
                            group.isRequired ? 'Required' : 'Optional',
                            style: AppTextStyles.caption.copyWith(
                              color: group.isRequired
                                  ? AppColors.primary
                                  : AppColors.gray500,
                            ),
                          ),
                        ],
                      ),
                      Text(_groupRule(group), style: AppTextStyles.caption),
                      const SizedBox(height: 6),
                      for (final option in group.options)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedIds.contains(option.id),
                          title: Text(option.name),
                          secondary: Text(
                            option.priceDelta == 0
                                ? 'Included'
                                : '+${_money(option.priceDelta)}',
                            style: AppTextStyles.caption,
                          ),
                          onChanged: (checked) {
                            setDialogState(() {
                              errorMessage = null;
                              if (checked == true) {
                                final selectedInGroup = group.options
                                    .where(
                                      (item) => selectedIds.contains(item.id),
                                    )
                                    .length;
                                final max = group.maxSelections;
                                if (max != null && selectedInGroup >= max) {
                                  errorMessage =
                                      '${group.name} allows up to $max selection(s).';
                                  return;
                                }
                                selectedIds.add(option.id);
                              } else {
                                selectedIds.remove(option.id);
                              }
                            });
                          },
                        ),
                      const Divider(height: 24),
                    ],
                    TextField(
                      controller: instructionsController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Special Instructions',
                        hintText: 'Optional',
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  for (final group in groups) {
                    final selectedCount = group.options
                        .where((item) => selectedIds.contains(item.id))
                        .length;

                    if (selectedCount < group.minSelections) {
                      setDialogState(() {
                        errorMessage =
                            'Select at least ${group.minSelections} option(s) from ${group.name}.';
                      });
                      return;
                    }

                    final max = group.maxSelections;
                    if (max != null && selectedCount > max) {
                      setDialogState(() {
                        errorMessage =
                            'Select at most $max option(s) from ${group.name}.';
                      });
                      return;
                    }
                  }

                  final selected = <PosModifierOption>[];
                  for (final group in groups) {
                    selected.addAll(
                      group.options.where(
                        (item) => selectedIds.contains(item.id),
                      ),
                    );
                  }

                  Navigator.pop(
                    dialogContext,
                    _PosCartLine(
                      product: product,
                      quantity: 1,
                      modifiers: selected,
                      specialInstructions: instructionsController.text.trim(),
                    ),
                  );
                },
                child: const Text('Add to Order'),
              ),
            ],
          );
        },
      ),
    );

    instructionsController.dispose();
    return result;
  }

  void _addOrMergeLine(_PosCartLine incoming) {
    final existingIndex = _cart.indexWhere(
      (line) =>
          line.product.variantId == incoming.product.variantId &&
          line.modifierSignature == incoming.modifierSignature &&
          line.specialInstructions == incoming.specialInstructions,
    );

    setState(() {
      if (existingIndex == -1) {
        _cart.add(incoming);
      } else {
        final existing = _cart[existingIndex];
        _cart[existingIndex] = existing.copyWith(
          quantity: existing.quantity + incoming.quantity,
        );
      }
    });
  }

  void _increaseLine(int index) {
    final line = _cart[index];

    if (!_hasStockForAdditional(line.product, 1)) {
      _showError(
        '${line.product.name} only has '
        '${_quantity(line.product.availableQuantity ?? 0)} available.',
      );
      return;
    }

    setState(() {
      _cart[index] = line.copyWith(quantity: line.quantity + 1);
    });
  }

  void _decreaseLine(int index) {
    final line = _cart[index];
    setState(() {
      if (line.quantity <= 1) {
        _cart.removeAt(index);
      } else {
        _cart[index] = line.copyWith(quantity: line.quantity - 1);
      }
    });
  }

  void _removeLine(int index) {
    setState(() => _cart.removeAt(index));
  }

  bool _hasStockForAdditional(PosMenuItem product, int additional) {
    if (!product.tracksInventory || product.availableQuantity == null) {
      return true;
    }

    final alreadyInCart = _cart
        .where((line) => line.product.variantId == product.variantId)
        .fold<int>(0, (sum, line) => sum + line.quantity);

    return alreadyInCart + additional <= product.availableQuantity!;
  }

  Future<void> _showPaymentDialog() async {
    final validation = _validateOrderDetails();
    if (validation != null) {
      _showError(validation);
      return;
    }

    final results = await Future.wait([
      _paymentMethodsFuture,
      _discountTypesFuture,
    ]);

    if (!mounted) return;

    final methods = results[0] as List<PosPaymentMethod>;
    final discounts = results[1] as List<PosDiscountType>;

    if (methods.isEmpty) {
      _showError('No active payment methods are configured.');
      return;
    }

    final subtotal = _cart.fold<double>(0, (sum, line) => sum + line.lineTotal);

    var selectedMethod = methods.first;
    PosDiscountType? selectedDiscount;

    final amountController = TextEditingController(
      text: subtotal.toStringAsFixed(2),
    );
    final referenceController = TextEditingController();
    final discountValueController = TextEditingController();
    final discountNotesController = TextEditingController();

    String? errorMessage;
    StateSetter? dialogSetState;

    double discountValue() {
      return double.tryParse(discountValueController.text.trim()) ?? 0;
    }

    double discountAmount() {
      final discount = selectedDiscount;
      if (discount == null) return 0;
      return discount.calculateDiscount(subtotal, discountValue());
    }

    double finalTotal() {
      return (subtotal - discountAmount()).clamp(0, double.infinity).toDouble();
    }

    await showPrototypeDialog(
      context: context,
      title: 'Proceed to Payment',
      width: 700,
      content: StatefulBuilder(
        builder: (_, setDialogState) {
          dialogSetState = setDialogState;

          final discountedTotal = finalTotal();
          final received = double.tryParse(amountController.text.trim()) ?? 0;
          final change = selectedMethod.isCash
              ? (received - discountedTotal)
                    .clamp(0, double.infinity)
                    .toDouble()
              : 0.0;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paymentInfoRow('Order Type', _orderType),
                _paymentInfoRow('Subtotal', _money(subtotal)),
                if (selectedDiscount != null)
                  _paymentInfoRow('Discount', '-${_money(discountAmount())}'),
                _paymentInfoRow(
                  'Total',
                  _money(discountedTotal),
                  emphasized: true,
                ),
                if (discounts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDiscount?.id ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Promotional Discount',
                      helperText: 'Senior/PWD rules are not enabled until the café tax setup is confirmed.',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('No Discount'),
                      ),
                      for (final discount in discounts)
                        DropdownMenuItem(
                          value: discount.id,
                          child: Text(discount.name),
                        ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedDiscount = value == null || value.isEmpty
                            ? null
                            : discounts.firstWhere((item) => item.id == value);

                        final defaultValue = selectedDiscount?.defaultValue;
                        discountValueController.text = defaultValue == null
                            ? ''
                            : defaultValue.toStringAsFixed(
                                defaultValue == defaultValue.roundToDouble()
                                    ? 0
                                    : 2,
                              );

                        amountController.text = finalTotal().toStringAsFixed(2);
                        errorMessage = null;
                      });
                    },
                  ),
                  if (selectedDiscount != null) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: discountValueController,
                      enabled: selectedDiscount!.allowCustomValue,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        helperText: selectedDiscount!.allowCustomValue
                            ? null
                            : 'Set by management for this promotion.',
                        labelText:
                            selectedDiscount!.calculationMethod == 'PERCENTAGE'
                            ? 'Discount Percentage *'
                            : 'Discount Amount *',
                        suffixText:
                            selectedDiscount!.calculationMethod == 'PERCENTAGE'
                            ? '%'
                            : null,
                        prefixText:
                            selectedDiscount!.calculationMethod == 'PERCENTAGE'
                            ? null
                            : '₱',
                      ),
                      onChanged: (_) {
                        setDialogState(() {
                          errorMessage = null;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: discountNotesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Discount Notes',
                        hintText: 'Optional promo/reference notes',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedMethod.id,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                  ),
                  items: methods
                      .map(
                        (method) => DropdownMenuItem(
                          value: method.id,
                          child: Text(method.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      selectedMethod = methods.firstWhere(
                        (method) => method.id == value,
                      );
                      errorMessage = null;
                      if (!selectedMethod.isCash) {
                        amountController.text = finalTotal().toStringAsFixed(2);
                      }
                    });
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  enabled: selectedMethod.isCash,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount Received',
                    prefixText: '₱',
                  ),
                  onChanged: (_) {
                    dialogSetState?.call(() {
                      errorMessage = null;
                    });
                  },
                ),
                if (selectedMethod.requiresReference) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: referenceController,
                    decoration: InputDecoration(
                      labelText: '${selectedMethod.name} Reference *',
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _paymentInfoRow('Change', _money(change)),
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorMessage!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _submittingOrder ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submittingOrder
              ? null
              : () async {
                  final discountedTotal = finalTotal();
                  final received =
                      double.tryParse(amountController.text.trim()) ?? 0;

                  final discount = selectedDiscount;
                  final enteredDiscountValue = discountValue();

                  if (discount != null) {
                    if (enteredDiscountValue <= 0) {
                      dialogSetState?.call(() {
                        errorMessage =
                            'Enter a discount value greater than zero.';
                      });
                      return;
                    }

                    if (discount.calculationMethod == 'PERCENTAGE' &&
                        enteredDiscountValue > 100) {
                      dialogSetState?.call(() {
                        errorMessage =
                            'Discount percentage cannot exceed 100%.';
                      });
                      return;
                    }

                    if (discountAmount() <= 0 || discountAmount() > subtotal) {
                      dialogSetState?.call(() {
                        errorMessage = 'Invalid discount amount.';
                      });
                      return;
                    }
                  }

                  if (discountedTotal <= 0) {
                    dialogSetState?.call(() {
                      errorMessage =
                          'The payable total must be greater than zero.';
                    });
                    return;
                  }

                  if (selectedMethod.isCash && received < discountedTotal) {
                    dialogSetState?.call(() {
                      errorMessage = 'Amount received cannot be less than the discounted total.';
                    });
                    return;
                  }

                  if (selectedMethod.requiresReference &&
                      referenceController.text.trim().isEmpty) {
                    dialogSetState?.call(() {
                      errorMessage = 'A transaction reference is required.';
                    });
                    return;
                  }

                  final fingerprint = _checkoutFingerprint(
                    paymentMethodId: selectedMethod.id,
                    discountTypeId: discount?.id ?? '',
                    discountValue: discount == null ? 0 : enteredDiscountValue,
                  );

                  if (_checkoutAttempt.conflictsWith(fingerprint)) {
                    // A different sale is being paid while an earlier
                    // payment is unconfirmed. Settle that one first.
                    setState(() => _submittingOrder = true);
                    try {
                      final earlier = await widget.orderRepository
                          .findOrderByRequestId(
                            _checkoutAttempt.unresolvedRequestId!,
                          );
                      _checkoutAttempt.resolve();
                      if (earlier != null) {
                        dialogSetState?.call(() {
                          errorMessage =
                              'The earlier payment was saved as order '
                              '${earlier.id}. Check it in Orders before '
                              'charging again.';
                        });
                        return;
                      }
                    } catch (_) {
                      dialogSetState?.call(() {
                        errorMessage =
                            'The earlier payment could not be confirmed yet. '
                            'Check the connection and try again.';
                      });
                      return;
                    } finally {
                      if (mounted) {
                        setState(() => _submittingOrder = false);
                      }
                    }
                  }

                  final requestId = _checkoutAttempt.requestIdFor(fingerprint);

                  setState(() => _submittingOrder = true);

                  try {
                    final order = await widget.orderRepository.placeOrder(
                      clientRequestId: requestId,
                      orderType: _orderType,
                      items: _cart
                          .map(
                            (line) => PosCheckoutItem(
                              menuVariantId: line.product.variantId,
                              quantity: line.quantity,
                              modifierIds: line.modifiers
                                  .map((modifier) => modifier.id)
                                  .toList(),
                              specialInstructions: line.specialInstructions,
                            ),
                          )
                          .toList(),
                      payments: [
                        PosPaymentInput(
                          paymentMethodId: selectedMethod.id,
                          amount: discountedTotal,
                          amountTendered: selectedMethod.isCash
                              ? received
                              : null,
                          changeAmount: selectedMethod.isCash
                              ? received - discountedTotal
                              : 0,
                          externalReference: selectedMethod.requiresReference
                              ? referenceController.text.trim()
                              : null,
                        ),
                      ],
                      tableNumber: _tableNumberController.text.trim(),
                      customerName: _customerNameController.text.trim(),
                      deliveryReference: _deliveryReferenceController.text
                          .trim(),
                      discountTypeId: discount?.id ?? '',
                      discountValue: discount == null
                          ? null
                          : enteredDiscountValue,
                      discountNotes: discountNotesController.text.trim(),
                    );

                    _checkoutAttempt.resolve();
                    if (!mounted) return;
                    Navigator.pop(context);
                    await _showReceiptDialog(order);
                  } on CheckoutSavedException catch (error) {
                    _checkoutAttempt.resolve();
                    if (!mounted) return;
                    Navigator.pop(context);
                    await _showSavedWithoutReceipt(error.orderNumber);
                  } on PostgrestException catch (error) {
                    if (isServerRejectionCode(error.code)) {
                      // The server answered and rolled back: nothing saved.
                      _checkoutAttempt.resolve();
                      dialogSetState?.call(() {
                        errorMessage = error.message;
                      });
                    } else {
                      dialogSetState?.call(() {
                        errorMessage = _unknownOutcomeMessage;
                      });
                    }
                  } catch (_) {
                    dialogSetState?.call(() {
                      errorMessage = _unknownOutcomeMessage;
                    });
                  } finally {
                    if (mounted) {
                      setState(() => _submittingOrder = false);
                    }
                  }
                },
          child: _submittingOrder
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Complete Payment'),
        ),
      ],
    );

    amountController.dispose();
    referenceController.dispose();
    discountValueController.dispose();
    discountNotesController.dispose();
  }

  static const _unknownOutcomeMessage =
      'The connection dropped before this sale was confirmed, so it may '
      'already be saved. Tap Complete Payment again to check. The customer '
      'will not be charged twice.';

  /// Identifies the sale being paid, so a retry can be told apart from a
  /// different sale. The amount tendered and reference are left out: changing
  /// them does not make it a different sale.
  String _checkoutFingerprint({
    required String paymentMethodId,
    required String discountTypeId,
    required double discountValue,
  }) {
    final lines = _cart
        .map(
          (line) => [
            line.product.variantId,
            line.quantity,
            line.modifiers.map((modifier) => modifier.id).join(','),
            line.specialInstructions.trim(),
          ].join(':'),
        )
        .join('|');

    return [
      _orderType,
      _tableNumberController.text.trim(),
      _customerNameController.text.trim(),
      _deliveryReferenceController.text.trim(),
      lines,
      discountTypeId,
      discountValue,
      paymentMethodId,
    ].join('\n');
  }

  Future<void> _showSavedWithoutReceipt(String orderNumber) async {
    await showPrototypeDialog(
      context: context,
      title: 'Payment saved',
      content: Text(
        'Order #$orderNumber was saved, but its receipt could not be loaded. '
        'Do not charge the customer again. Open the order from Orders to '
        'view the receipt.',
        style: AppTextStyles.body,
      ),
    );

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _showReceiptDialog(OrderRecord order) async {
    await showPrototypeDialog(
      context: context,
      title: 'Receipt',
      width: 560,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text('Street Bowl Café', style: AppTextStyles.h2),
            ),
            const SizedBox(height: 4),
            Center(child: Text(order.id, style: AppTextStyles.caption)),
            if (order.invoiceNumber.isNotEmpty) ...[
              const SizedBox(height: 3),
              Center(
                child: Text(
                  'Invoice ${order.invoiceNumber}',
                  style: AppTextStyles.caption,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _paymentInfoRow('Customer / Table', order.customerOrTable),
            _paymentInfoRow('Order Type', order.type),
            _paymentInfoRow('Handled by', order.employee),
            const Divider(height: 28),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.quantity} × ${item.productName}',
                        style: AppTextStyles.body,
                      ),
                    ),
                    Text(
                      _money(item.lineTotal),
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 28),
            if (order.discountAmount > 0) ...[
              _paymentInfoRow('Subtotal', _money(order.subtotal)),
              _paymentInfoRow(
                order.discountName.isEmpty
                    ? 'Discount'
                    : 'Discount (${order.discountName})',
                '-${_money(order.discountAmount)}',
              ),
            ],
            _paymentInfoRow('Total', _money(order.amount), emphasized: true),
            _paymentInfoRow('Payment', order.paymentMethod),
            _paymentInfoRow('Amount Received', _money(order.amountReceived)),
            _paymentInfoRow('Change', _money(order.changeAmount)),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.pop(context, true);
          },
          child: const Text('Done'),
        ),
      ],
    );
  }

  String? _validateOrderDetails() {
    if (_cart.isEmpty) return 'Add at least one item to the order.';
    if (_openShiftId == null) {
      return 'Start a shift before creating an order.';
    }

    if (_orderType == 'Dine In' && _tableNumberController.text.trim().isEmpty) {
      return 'Enter the table number for this dine-in order.';
    }

    if ((_orderType == 'Take Out' || _orderType == 'Delivery') &&
        _customerNameController.text.trim().isEmpty) {
      return 'Enter the customer name for this order.';
    }

    return null;
  }

  String _groupRule(PosModifierGroup group) {
    if (group.maxSelections == null) {
      return 'Select at least ${group.minSelections}';
    }
    if (group.minSelections == group.maxSelections) {
      return 'Select exactly ${group.minSelections}';
    }
    return 'Select ${group.minSelections}–${group.maxSelections}';
  }

  Widget _summaryRow(String label, String value, {bool emphasized = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: emphasized ? AppTextStyles.bodyMedium : AppTextStyles.body,
        ),
        Text(
          value,
          style: emphasized ? AppTextStyles.h2 : AppTextStyles.bodyMedium,
        ),
      ],
    );
  }

  Widget _paymentInfoRow(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized ? AppTextStyles.bodyMedium : AppTextStyles.body,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: emphasized ? AppTextStyles.h3 : AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }

  IconData _iconForCategory(String category) {
    final value = category.toLowerCase();
    if (value.contains('coffee')) return Icons.coffee_outlined;
    if (value.contains('baked')) return Icons.cake_outlined;
    if (value.contains('rice') || value.contains('meal')) {
      return Icons.rice_bowl_outlined;
    }
    if (value.contains('beverage')) return Icons.local_drink_outlined;
    if (value.contains('snack')) return Icons.cookie_outlined;
    return Icons.fastfood_outlined;
  }

  String _signedMoney(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${_money(value)}';
  }

  String _money(double value) {
    final whole = value == value.roundToDouble();
    return whole ? '₱${value.toInt()}' : '₱${value.toStringAsFixed(2)}';
  }

  String _quantity(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) => _showMessage(message);
}

class _PosCartLine {
  final PosMenuItem product;
  final int quantity;
  final List<PosModifierOption> modifiers;
  final String specialInstructions;

  const _PosCartLine({
    required this.product,
    required this.quantity,
    required this.modifiers,
    required this.specialInstructions,
  });

  double get modifierTotal =>
      modifiers.fold<double>(0, (sum, modifier) => sum + modifier.priceDelta);

  double get unitPriceWithModifiers => product.price + modifierTotal;

  double get lineTotal => unitPriceWithModifiers * quantity;

  String get modifierSignature {
    final ids = modifiers.map((item) => item.id).toList()..sort();
    return ids.join('|');
  }

  _PosCartLine copyWith({int? quantity}) {
    return _PosCartLine(
      product: product,
      quantity: quantity ?? this.quantity,
      modifiers: modifiers,
      specialInstructions: specialInstructions,
    );
  }
}
