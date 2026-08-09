class MasterAccessStatus {
  const MasterAccessStatus({
    required this.generatedAt,
    required this.onlineWindowSeconds,
    required this.totalCompanies,
    required this.onlineCompanies,
    required this.onlineUsers,
    required this.firstAccessCompletedCompanies,
    required this.pendingFirstAccessCompanies,
    required this.items,
  });

  final DateTime? generatedAt;
  final int onlineWindowSeconds;
  final int totalCompanies;
  final int onlineCompanies;
  final int onlineUsers;
  final int firstAccessCompletedCompanies;
  final int pendingFirstAccessCompanies;
  final List<MasterCompanyAccessStatus> items;

  factory MasterAccessStatus.fromJson(Map<String, dynamic> json) {
    return MasterAccessStatus(
      generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? ''),
      onlineWindowSeconds: _toInt(json['online_window_seconds']),
      totalCompanies: _toInt(json['total_companies']),
      onlineCompanies: _toInt(json['online_companies']),
      onlineUsers: _toInt(json['online_users']),
      firstAccessCompletedCompanies: _toInt(
        json['first_access_completed_companies'],
      ),
      pendingFirstAccessCompanies: _toInt(
        json['pending_first_access_companies'],
      ),
      items: (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MasterCompanyAccessStatus.fromJson)
          .toList(),
    );
  }
}

class MasterCompanyAccessStatus {
  const MasterCompanyAccessStatus({
    required this.companyId,
    required this.companyCode,
    required this.companyName,
    required this.plan,
    required this.status,
    required this.online,
    required this.onlineUsers,
    this.lastSeenAt,
    required this.activeUsers,
    required this.totalUsers,
    required this.pendingFirstAccessUsers,
    required this.changedPasswordUsers,
    required this.firstAccessCompleted,
    this.lastPasswordChangedAt,
    this.accessError,
    required this.usersOnlineDetails,
  });

  final int companyId;
  final String companyCode;
  final String companyName;
  final String plan;
  final String status;
  final bool online;
  final int onlineUsers;
  final DateTime? lastSeenAt;
  final int activeUsers;
  final int totalUsers;
  final int pendingFirstAccessUsers;
  final int changedPasswordUsers;
  final bool firstAccessCompleted;
  final DateTime? lastPasswordChangedAt;
  final String? accessError;
  final List<MasterOnlineUserDetail> usersOnlineDetails;

  factory MasterCompanyAccessStatus.fromJson(Map<String, dynamic> json) {
    return MasterCompanyAccessStatus(
      companyId: _toInt(json['company_id']),
      companyCode: json['company_code']?.toString() ?? '',
      companyName: json['company_name']?.toString() ?? '',
      plan: json['plan']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      online: json['online'] == true,
      onlineUsers: _toInt(json['online_users']),
      lastSeenAt: DateTime.tryParse(json['last_seen_at']?.toString() ?? ''),
      activeUsers: _toInt(json['active_users']),
      totalUsers: _toInt(json['total_users']),
      pendingFirstAccessUsers: _toInt(json['pending_first_access_users']),
      changedPasswordUsers: _toInt(json['changed_password_users']),
      firstAccessCompleted: json['first_access_completed'] == true,
      lastPasswordChangedAt: DateTime.tryParse(
        json['last_password_changed_at']?.toString() ?? '',
      ),
      accessError: json['access_error']?.toString(),
      usersOnlineDetails: (json['users_online_details'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MasterOnlineUserDetail.fromJson)
          .toList(),
    );
  }
}

class MasterOnlineUserDetail {
  const MasterOnlineUserDetail({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.clientType,
    this.lastSeenAt,
  });

  final int userId;
  final String name;
  final String email;
  final String role;
  final String clientType;
  final DateTime? lastSeenAt;

  factory MasterOnlineUserDetail.fromJson(Map<String, dynamic> json) {
    return MasterOnlineUserDetail(
      userId: _toInt(json['user_id']),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      clientType: json['client_type']?.toString() ?? '',
      lastSeenAt: DateTime.tryParse(json['last_seen_at']?.toString() ?? ''),
    );
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
