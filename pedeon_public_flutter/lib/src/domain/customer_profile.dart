import 'catalog_models.dart';

class CustomerProfile {
  const CustomerProfile({this.document, this.deliveryAddress});

  final String? document;
  final DeliveryAddress? deliveryAddress;

  Map<String, dynamic> toJson() => {
        if (document?.trim().isNotEmpty ?? false) 'document': document!.trim(),
        if (deliveryAddress != null)
          'delivery_address': deliveryAddress!.toJson(),
      };

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    final address = json['delivery_address'];
    return CustomerProfile(
      document: json['document'] as String?,
      deliveryAddress: address is Map
          ? DeliveryAddress.fromJson(Map<String, dynamic>.from(address))
          : null,
    );
  }
}
