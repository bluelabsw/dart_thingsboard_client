import 'id/ota_package_id.dart';

mixin HasOtaPackage {
  OtaPackageId? getFirmwareId();

  OtaPackageId? getSoftwareId();
}
