class MasterSupportMessage {
  const MasterSupportMessage({
    required this.id,
    required this.ticketId,
    required this.authorType,
    required this.body,
    required this.createdAt,
    this.authorName,
    this.authorEmail,
    this.attachmentUrl,
    this.attachmentName,
  });

  final int id;
  final int ticketId;
  final String authorType;
  final String? authorName;
  final String? authorEmail;
  final String body;
  final String? attachmentUrl;
  final String? attachmentName;
  final DateTime createdAt;

  factory MasterSupportMessage.fromJson(Map<String, dynamic> json) {
    return MasterSupportMessage(
      id: json['id'] as int,
      ticketId: json['ticket_id'] as int,
      authorType: json['author_type'].toString(),
      authorName: json['author_name']?.toString(),
      authorEmail: json['author_email']?.toString(),
      body: json['body'].toString(),
      attachmentUrl: json['attachment_url']?.toString(),
      attachmentName: json['attachment_name']?.toString(),
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }
}

class MasterSupportTicket {
  const MasterSupportTicket({
    required this.id,
    required this.companyId,
    required this.companyCode,
    required this.companyName,
    required this.module,
    required this.priority,
    required this.status,
    required this.subject,
    required this.description,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.customerAttachmentsEnabled = false,
    this.requesterName,
    this.requesterEmail,
    this.assignedMasterUserName,
    this.assignedMasterUserEmail,
  });

  final int id;
  final int companyId;
  final String companyCode;
  final String companyName;
  final String module;
  final String priority;
  final String status;
  final String subject;
  final String description;
  final bool customerAttachmentsEnabled;
  final String? requesterName;
  final String? requesterEmail;
  final String? assignedMasterUserName;
  final String? assignedMasterUserEmail;
  final DateTime lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MasterSupportMessage> messages;

  factory MasterSupportTicket.fromJson(Map<String, dynamic> json) {
    return MasterSupportTicket(
      id: json['id'] as int,
      companyId: json['company_id'] as int,
      companyCode: json['company_code'].toString(),
      companyName: json['company_name'].toString(),
      module: json['module'].toString(),
      priority: json['priority'].toString(),
      status: json['status'].toString(),
      subject: json['subject'].toString(),
      description: json['description'].toString(),
      customerAttachmentsEnabled:
          json['customer_attachments_enabled'] as bool? ?? false,
      requesterName: json['requester_name']?.toString(),
      requesterEmail: json['requester_email']?.toString(),
      assignedMasterUserName: json['assigned_master_user_name']?.toString(),
      assignedMasterUserEmail: json['assigned_master_user_email']?.toString(),
      lastMessageAt: DateTime.parse(json['last_message_at'].toString()),
      createdAt: DateTime.parse(json['created_at'].toString()),
      updatedAt: DateTime.parse(json['updated_at'].toString()),
      messages: ((json['messages'] as List<dynamic>?) ?? const [])
          .map((item) => MasterSupportMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MasterSupportTicketInput {
  const MasterSupportTicketInput({
    required this.module,
    required this.priority,
    required this.subject,
    required this.description,
    this.attachmentUrl,
    this.attachmentName,
  });

  final String module;
  final String priority;
  final String subject;
  final String description;
  final String? attachmentUrl;
  final String? attachmentName;

  Map<String, dynamic> toJson() => {
        'module': module,
        'priority': priority,
        'subject': subject,
        'description': description,
        if (attachmentUrl != null) 'attachment_url': attachmentUrl,
        if (attachmentName != null) 'attachment_name': attachmentName,
      };
}
