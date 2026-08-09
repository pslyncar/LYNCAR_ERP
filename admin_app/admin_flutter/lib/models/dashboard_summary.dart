class DashboardSummary {
  const DashboardSummary({
    required this.dashboardKind,
    required this.businessType,
    required this.hasFiscalCertificate,
    required this.totalClients,
    required this.totalEquipments,
    required this.onlineEquipments,
    required this.offlineEquipments,
    required this.openTickets,
    required this.inProgressTickets,
    required this.completedTickets,
    required this.canceledTickets,
    required this.alerts,
    required this.contents,
  });

  final String dashboardKind;
  final String? businessType;
  final bool hasFiscalCertificate;
  final int totalClients;
  final int totalEquipments;
  final int onlineEquipments;
  final int offlineEquipments;
  final int openTickets;
  final int inProgressTickets;
  final int completedTickets;
  final int canceledTickets;
  final List<DashboardAlert> alerts;
  final List<DashboardContent> contents;

  bool get isTechnical => dashboardKind == 'technical';

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      dashboardKind: json['dashboard_kind']?.toString() ?? 'technical',
      businessType: json['business_type']?.toString(),
      hasFiscalCertificate: json['has_fiscal_certificate'] as bool? ?? false,
      totalClients: json['total_clients'] as int,
      totalEquipments: json['total_equipments'] as int,
      onlineEquipments: json['online_equipments'] as int,
      offlineEquipments: json['offline_equipments'] as int,
      openTickets: json['open_tickets'] as int,
      inProgressTickets: json['in_progress_tickets'] as int,
      completedTickets: json['completed_tickets'] as int,
      canceledTickets: json['canceled_tickets'] as int,
      alerts: (json['alerts'] as List<dynamic>)
          .map(
            (alert) => DashboardAlert.fromJson(alert as Map<String, dynamic>),
          )
          .toList(),
      contents: (json['contents'] as List<dynamic>? ?? [])
          .map(
            (content) =>
                DashboardContent.fromJson(content as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class DashboardContent {
  const DashboardContent({
    required this.id,
    required this.contentType,
    required this.title,
    required this.sortOrder,
    this.active = true,
    this.description,
    this.badge,
    this.priceLabel,
    this.imageUrl,
    this.targetUrl,
    this.buttonLabel,
    this.segment,
  });

  final int id;
  final String contentType;
  final String title;
  final String? description;
  final String? badge;
  final String? priceLabel;
  final String? imageUrl;
  final String? targetUrl;
  final String? buttonLabel;
  final String? segment;
  final int sortOrder;
  final bool active;

  factory DashboardContent.fromJson(Map<String, dynamic> json) {
    return DashboardContent(
      id: json['id'] as int,
      contentType: json['content_type']?.toString() ?? 'notice',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      badge: json['badge']?.toString(),
      priceLabel: json['price_label']?.toString(),
      imageUrl: json['image_url']?.toString(),
      targetUrl: json['target_url']?.toString(),
      buttonLabel: json['button_label']?.toString(),
      segment: json['segment']?.toString(),
      sortOrder: json['sort_order'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
    );
  }
}

class DashboardContentPayload {
  const DashboardContentPayload({
    required this.contentType,
    required this.title,
    required this.active,
    this.description,
    this.badge,
    this.priceLabel,
    this.imageUrl,
    this.targetUrl,
    this.buttonLabel,
    this.segment,
    this.sortOrder = 0,
  });

  final String contentType;
  final String title;
  final String? description;
  final String? badge;
  final String? priceLabel;
  final String? imageUrl;
  final String? targetUrl;
  final String? buttonLabel;
  final String? segment;
  final int sortOrder;
  final bool active;

  Map<String, dynamic> toJson() {
    return {
      'content_type': contentType,
      'title': title,
      'description': description,
      'badge': badge,
      'price_label': priceLabel,
      'image_url': imageUrl,
      'target_url': targetUrl,
      'button_label': buttonLabel,
      'segment': segment,
      'sort_order': sortOrder,
      'active': active,
    };
  }
}

class DashboardAlert {
  const DashboardAlert({
    required this.equipmentId,
    required this.hostname,
    required this.clientId,
    required this.clientName,
    required this.type,
    required this.severity,
    required this.message,
  });

  final int equipmentId;
  final String hostname;
  final int clientId;
  final String clientName;
  final String type;
  final String severity;
  final String message;

  factory DashboardAlert.fromJson(Map<String, dynamic> json) {
    return DashboardAlert(
      equipmentId: json['equipment_id'] as int,
      hostname: json['hostname'] as String,
      clientId: json['client_id'] as int,
      clientName: json['client_name'] as String,
      type: json['type'] as String,
      severity: json['severity'] as String,
      message: json['message'] as String,
    );
  }
}
