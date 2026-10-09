import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/business_repository.dart';
import '../../models/business_profile.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/layout/app_page.dart';
import '../../core/theme/app_spacing.dart';

/// Where management sets what receipts say about the business and whether
/// shifts must count their cash.
class BusinessDetailsScreen extends StatefulWidget {
  final BusinessRepository businessRepository;

  /// Called with the saved details so receipts and the header update.
  final ValueChanged<BusinessProfile>? onSaved;

  const BusinessDetailsScreen({
    super.key,
    required this.businessRepository,
    this.onSaved,
  });

  @override
  State<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends State<BusinessDetailsScreen> {
  final _tradeName = TextEditingController();
  final _registeredName = TextEditingController();
  final _tin = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();
  final _postalCode = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  bool _requireOpeningCash = false;
  bool _requireClosingCash = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _tradeName,
      _registeredName,
      _tin,
      _address,
      _city,
      _province,
      _postalCode,
      _phone,
      _email,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final profile = await widget.businessRepository.getBusinessProfile();
      if (!mounted) return;

      _tradeName.text = profile.tradeName;
      _registeredName.text = profile.registeredName;
      _tin.text = profile.tin;
      _address.text = profile.addressLine;
      _city.text = profile.city;
      _province.text = profile.province;
      _postalCode.text = profile.postalCode;
      _phone.text = profile.phone;
      _email.text = profile.email;

      setState(() {
        _requireOpeningCash = profile.requireOpeningCash;
        _requireClosingCash = profile.requireClosingCash;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = errorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_tradeName.text.trim().isEmpty) {
      setState(() => _saveError = 'The business name is required.');
      return;
    }

    final profile = BusinessProfile(
      tradeName: _tradeName.text.trim(),
      registeredName: _registeredName.text.trim(),
      tin: _tin.text.trim(),
      addressLine: _address.text.trim(),
      city: _city.text.trim(),
      province: _province.text.trim(),
      postalCode: _postalCode.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      requireOpeningCash: _requireOpeningCash,
      requireClosingCash: _requireClosingCash,
    );

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      await widget.businessRepository.saveBusinessProfile(profile);
      if (!mounted) return;

      widget.onSaved?.call(profile);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Business details saved.')));
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _saveError = error.message);
    } catch (error) {
      if (mounted) setState(() => _saveError = errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Business details',
      subtitle: 'What receipts say about the business, and shift cash rules.',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unable to load the business details.\n$_loadError',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('On receipts', style: AppTextStyles.h3),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Shown at the top of every receipt. Leave a '
                            'field empty to leave it off.',
                            style: AppTextStyles.caption,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _field(_tradeName, 'Business Name *'),
                          _field(
                            _registeredName,
                            'Registered Name',
                            helper:
                                'The name on the business registration, if '
                                'different.',
                          ),
                          _field(_tin, 'TIN'),
                          _field(_address, 'Street Address'),
                          _pair(
                            _field(_city, 'City'),
                            _field(_province, 'Province'),
                          ),
                          _pair(
                            _field(_postalCode, 'Postal Code'),
                            _field(_phone, 'Phone'),
                          ),
                          _field(
                            _email,
                            'Email',
                            keyboardType: TextInputType.emailAddress,
                            helper: 'Not printed on receipts.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Shift cash', style: AppTextStyles.h3),
                          const SizedBox(height: AppSpacing.sm),
                          // The card paints its own background, so the
                          // switches need a surface of their own to draw
                          // their touch feedback on.
                          Material(
                            type: MaterialType.transparency,
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _requireOpeningCash,
                                  onChanged: (value) => setState(
                                    () => _requireOpeningCash = value,
                                  ),
                                  title: const Text('Count the drawer to open'),
                                  subtitle: const Text(
                                    'A shift cannot start until the opening cash '
                                    'is entered.',
                                  ),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _requireClosingCash,
                                  onChanged: (value) => setState(
                                    () => _requireClosingCash = value,
                                  ),
                                  title: const Text(
                                    'Count the drawer to close',
                                  ),
                                  subtitle: const Text(
                                    'A shift cannot end until the cash is counted, '
                                    'so every shift report shows a difference.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_saveError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _saveError!,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save changes'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, helperText: helper),
      ),
    );
  }

  /// Two fields side by side, or stacked where there is no room.
  Widget _pair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(children: [first, second]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
