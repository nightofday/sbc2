/// The business details printed on receipts, and the shift cash rules.
class BusinessProfile {
  final String tradeName;
  final String registeredName;
  final String tin;
  final String addressLine;
  final String city;
  final String province;
  final String postalCode;
  final String phone;
  final String email;

  /// A shift cannot open without a cash count.
  final bool requireOpeningCash;

  /// A shift cannot close without a cash count.
  final bool requireClosingCash;

  const BusinessProfile({
    required this.tradeName,
    this.registeredName = '',
    this.tin = '',
    this.addressLine = '',
    this.city = '',
    this.province = '',
    this.postalCode = '',
    this.phone = '',
    this.email = '',
    this.requireOpeningCash = false,
    this.requireClosingCash = false,
  });

  /// Used until the details have been loaded, and when they cannot be.
  static const fallback = BusinessProfile(tradeName: 'Street Bowl Café');

  /// Address, phone and TIN as they appear under the name on a receipt.
  /// Lines with nothing to show are left out.
  List<String> get receiptLines {
    final place = [
      addressLine,
      city,
      [province, postalCode].where((part) => part.isNotEmpty).join(' '),
    ].where((part) => part.isNotEmpty).join(', ');

    return [
      if (registeredName.isNotEmpty && registeredName != tradeName)
        registeredName,
      if (place.isNotEmpty) place,
      if (phone.isNotEmpty) phone,
      if (tin.isNotEmpty) 'TIN $tin',
    ];
  }

  Map<String, dynamic> toMap() => {
    'trade_name': tradeName,
    'registered_name': registeredName,
    'tin': tin,
    'address_line': addressLine,
    'city': city,
    'province': province,
    'postal_code': postalCode,
    'phone': phone,
    'email': email,
    'require_opening_cash': requireOpeningCash,
    'require_closing_cash': requireClosingCash,
  };

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    String text(String key) => map[key]?.toString().trim() ?? '';
    final name = text('trade_name');

    return BusinessProfile(
      tradeName: name.isEmpty ? fallback.tradeName : name,
      registeredName: text('registered_name'),
      tin: text('tin'),
      addressLine: text('address_line'),
      city: text('city'),
      province: text('province'),
      postalCode: text('postal_code'),
      phone: text('phone'),
      email: text('email'),
      requireOpeningCash: map['require_opening_cash'] == true,
      requireClosingCash: map['require_closing_cash'] == true,
    );
  }
}
