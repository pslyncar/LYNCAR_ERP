import 'catalog_models.dart';

class CustomerSession {
  const CustomerSession({
    required this.token,
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.document,
    this.deliveryAddress,
  });

  factory CustomerSession.fromJson(Map<String, dynamic> json) {
    final customer = (json['customer'] as Map).cast<String, dynamic>();
    return CustomerSession(
      token: json['access_token'] as String,
      id: customer['id'] as int,
      name: customer['name'] as String,
      email: customer['email'] as String,
      phone: customer['phone'] as String?,
      document: customer['document'] as String?,
      deliveryAddress: customer['delivery_address'] is Map
          ? DeliveryAddress.fromJson(
              Map<String, dynamic>.from(customer['delivery_address'] as Map),
            )
          : null,
    );
  }

  final String token;
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? document;
  final DeliveryAddress? deliveryAddress;
}
