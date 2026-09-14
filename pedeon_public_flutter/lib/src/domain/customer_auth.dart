class CustomerSession {
  const CustomerSession({
    required this.token,
    required this.id,
    required this.name,
    required this.email,
    this.phone,
  });

  factory CustomerSession.fromJson(Map<String, dynamic> json) {
    final customer = (json['customer'] as Map).cast<String, dynamic>();
    return CustomerSession(
      token: json['access_token'] as String,
      id: customer['id'] as int,
      name: customer['name'] as String,
      email: customer['email'] as String,
      phone: customer['phone'] as String?,
    );
  }

  final String token;
  final int id;
  final String name;
  final String email;
  final String? phone;
}
