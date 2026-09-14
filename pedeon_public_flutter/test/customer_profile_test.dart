import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_public/src/domain/catalog_models.dart';
import 'package:pedeon_public/src/domain/customer_profile.dart';

void main() {
  test('round trips customer document and delivery address', () {
    const profile = CustomerProfile(
      document: '12345678900',
      deliveryAddress: DeliveryAddress(
        postalCode: '12345678',
        street: 'Rua A',
        number: '10',
        neighborhood: 'Centro',
        city: 'Leme',
        state: 'SP',
      ),
    );

    final restored = CustomerProfile.fromJson(profile.toJson());

    expect(restored.document, '12345678900');
    expect(restored.deliveryAddress?.city, 'Leme');
  });
}
