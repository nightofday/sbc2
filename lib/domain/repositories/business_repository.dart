import '../../models/business_profile.dart';

/// The business details and shift cash rules management can change.
abstract class BusinessRepository {
  Future<BusinessProfile> getBusinessProfile();

  /// Saves both the details and the cash rules of [profile].
  Future<void> saveBusinessProfile(BusinessProfile profile);
}
