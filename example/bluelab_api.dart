import 'package:thingsboard_client/thingsboard_client.dart';

void main() async {
  try {
    var tbClient = BluelabThingsboardClient(
        'endpoint',
        () =>
            'token',
        () => Future.value(true));
    // await tbClient.initWithTokenOverrides();
    // await tbClient.login(LoginRequest(username, password));

    var test = await tbClient.getAttributeService().saveEntityAttributesV2(
        DeviceId('c0fff860-b155-11ec-bb71-7bfb4862d40c'),
        AttributeScope.SHARED_SCOPE.toShortString(),
        {'phTarget': 5.2});
    print(test);
    // await deviceApiExample();
  } catch (e, s) {
    print('Error: $e');
    print('Stack: $s');
  }
}
