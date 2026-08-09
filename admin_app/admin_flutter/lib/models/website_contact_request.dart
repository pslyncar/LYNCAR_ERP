class WebsiteContactRequest {
  const WebsiteContactRequest({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.companyName,
    this.message,
  });

  final int id;
  final String name;
  final String phone;
  final String? email;
  final String? companyName;
  final String? message;
  final String status;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WebsiteContactRequest.fromJson(Map<String, dynamic> json) {
    return WebsiteContactRequest(
      id: json['id'] as int,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      companyName: json['company_name'] as String?,
      message: json['message'] as String?,
      status: json['status'] as String,
      source: json['source'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
