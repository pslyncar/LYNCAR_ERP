import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/client.dart';
import '../models/cash_closing.dart';
import '../models/company.dart';
import '../models/business_segment.dart';
import '../models/company_billing.dart';
import '../models/dashboard_summary.dart';
import '../models/equipment.dart';
import '../models/equipment_current_status.dart';
import '../models/fiscal.dart';
import '../models/fiscal_assistant.dart';
import '../models/master_access_status.dart';
import '../models/master_staff.dart';
import '../models/monitoring_snapshot.dart';
import '../models/payable.dart';
import '../models/payment_setting.dart';
import '../models/pdv_operator.dart';
import '../models/pdv_terminal.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/product_composition.dart';
import '../models/production_order.dart';
import '../models/receivable.dart';
import '../models/sale.dart';
import '../models/service_order.dart';
import '../models/service_contract.dart';
import '../models/session.dart';
import '../models/master_support.dart';
import '../models/stock_movement.dart';
import '../models/stock_entry.dart';
import '../models/subscription_plan.dart';
import '../models/supplier.dart';
import '../models/system_user.dart';
import '../models/website_contact_request.dart';

class ApiClient {
  ApiClient(String baseUrl) : baseUrl = _normalizeBaseUrl(baseUrl);

  final String baseUrl;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    final withoutTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final uri = Uri.tryParse(withoutTrailingSlash);
    if (uri != null &&
        (uri.host == '127.0.0.1' || uri.host == 'localhost') &&
        uri.port == 5000) {
      return uri.replace(port: 8000).toString();
    }
    return withoutTrailingSlash;
  }

  Future<Session> login({
    required String companyCode,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'company_code': companyCode,
        'email': email,
        'password': password,
      }),
    );
    final data = _decodeResponse(response);
    return Session.fromJson(data, baseUrl);
  }

  Future<Session> loginAutomatically({
    required String email,
    required String password,
    String? clientType,
  }) async {
    final payload = {'email': email, 'password': password};
    if (clientType != null && clientType.trim().isNotEmpty) {
      payload['client_type'] = clientType.trim();
    }
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/automatic'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    final data = _decodeResponse(response);
    return Session.fromJson(data, baseUrl);
  }

  Future<CurrentSystemUser> getCurrentUser(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: _authHeaders(token),
    );
    return CurrentSystemUser.fromJson(_decodeResponse(response));
  }

  Future<Session> refreshSession(Session session) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: _authHeaders(session.token),
    );
    final data = _decodeResponse(response);
    return Session.fromJson(data, session.apiBaseUrl);
  }

  Future<Session> refreshPdvSession(Session session) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/pdv/refresh'),
      headers: _authHeaders(session.token),
    );
    final data = _decodeResponse(response);
    return Session.fromJson(data, session.apiBaseUrl);
  }

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    _decodeResponse(response);
  }

  Future<void> heartbeat(String token, {String clientType = 'web'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/heartbeat?client_type=$clientType'),
      headers: _authHeaders(token),
    );
    _decodeResponse(response);
  }

  Future<List<MasterSupportTicket>> listSupportTickets(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/support/tickets'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => MasterSupportTicket.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<MasterSupportTicket> createSupportTicket(
    String token,
    MasterSupportTicketInput input,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/support/tickets'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toJson()),
    );
    return MasterSupportTicket.fromJson(_decodeResponse(response));
  }

  Future<MasterSupportTicket> addSupportMessage(
    String token,
    int ticketId,
    String body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/support/tickets/$ticketId/messages'),
      headers: _authHeaders(token),
      body: jsonEncode({'body': body}),
    );
    return MasterSupportTicket.fromJson(_decodeResponse(response));
  }

  Future<List<MasterSupportTicket>> listMasterSupportTickets(
    String token,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/support/tickets'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => MasterSupportTicket.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<MasterSupportTicket> updateMasterSupportTicket(
    String token,
    int ticketId, {
    String? status,
    String? priority,
    bool? customerAttachmentsEnabled,
    int? assignedMasterUserId,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (priority != null) body['priority'] = priority;
    if (customerAttachmentsEnabled != null) {
      body['customer_attachments_enabled'] = customerAttachmentsEnabled;
    }
    if (assignedMasterUserId != null) {
      body['assigned_master_user_id'] = assignedMasterUserId;
    }
    final response = await http.put(
      Uri.parse('$baseUrl/master/support/tickets/$ticketId'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    );
    return MasterSupportTicket.fromJson(_decodeResponse(response));
  }

  Future<MasterSupportTicket> uploadSupportAttachment(
    String token,
    int ticketId, {
    required String filename,
    required Uint8List bytes,
    String body = '',
    bool master = false,
  }) async {
    final endpoint = master
        ? '$baseUrl/master/support/tickets/$ticketId/attachments'
        : '$baseUrl/support/tickets/$ticketId/attachments';
    final request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers.addAll(_authHeaders(token)..remove('Content-Type'));
    request.fields['body'] = body;
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return MasterSupportTicket.fromJson(_decodeResponse(response));
  }

  Future<MasterSupportTicket> addMasterSupportMessage(
    String token,
    int ticketId,
    String body, {
    String? status,
  }) async {
    final payload = <String, dynamic>{'body': body};
    if (status != null) payload['status'] = status;
    final response = await http.post(
      Uri.parse('$baseUrl/master/support/tickets/$ticketId/messages'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    return MasterSupportTicket.fromJson(_decodeResponse(response));
  }

  Future<List<Company>> listCompanies(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/companies'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => Company.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MasterAccessStatus> getMasterAccessStatus(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/access-status'),
      headers: _authHeaders(token),
    );
    return MasterAccessStatus.fromJson(_decodeResponse(response));
  }

  Future<List<MasterPermission>> listMasterPermissions(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/permissions'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => MasterPermission.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<MasterStaff>> listMasterStaff(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/staff'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => MasterStaff.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MasterStaff> createMasterStaff(
    String token,
    MasterStaffInput input,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/staff'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toCreateJson()),
    );
    return MasterStaff.fromJson(_decodeResponse(response));
  }

  Future<MasterStaff> updateMasterStaff(
    String token,
    int userId,
    MasterStaffInput input,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/staff/$userId'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toUpdateJson()),
    );
    return MasterStaff.fromJson(_decodeResponse(response));
  }

  Future<Company> createCompany(String token, CompanyInput input) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/companies'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toCreateJson()),
    );
    return Company.fromJson(_decodeResponse(response));
  }

  Future<Company> updateCompany(
    String token,
    int companyId,
    CompanyInput input,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/companies/$companyId'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toUpdateJson()),
    );
    return Company.fromJson(_decodeResponse(response));
  }

  Future<CompanyTaxProfileLookup> lookupCompanyTaxProfile(
    String token,
    String cnpj,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/companies/cnpj-lookup/$cnpj'),
      headers: _authHeaders(token),
    );
    return CompanyTaxProfileLookup.fromJson(_decodeResponse(response));
  }

  Future<List<CompanyContract>> listCompanyContracts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/companies/contracts'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => CompanyContract.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<SubscriptionPlan>> listMasterPlans(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/plans'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => SubscriptionPlan.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<BusinessSegment>> listMasterSegments(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/segments'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => BusinessSegment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<WebsiteContactRequest>> listMasterContactRequests(
    String token, {
    String? status,
    String? search,
  }) async {
    final query = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final uri = Uri.parse(
      '$baseUrl/master/contact-requests',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: _authHeaders(token));
    return _decodeListResponse(response)
        .map(
          (item) =>
              WebsiteContactRequest.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<WebsiteContactRequest> updateMasterContactRequestStatus(
    String token,
    int requestId,
    String status,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/master/contact-requests/$requestId'),
      headers: _authHeaders(token),
      body: jsonEncode({'status': status}),
    );
    return WebsiteContactRequest.fromJson(_decodeResponse(response));
  }

  Future<SubscriptionPlan> updateMasterPlan(
    String token,
    String code,
    SubscriptionPlan plan,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/plans/$code'),
      headers: _authHeaders(token),
      body: jsonEncode(plan.toUpdateJson()),
    );
    return SubscriptionPlan.fromJson(_decodeResponse(response));
  }

  Future<SubscriptionPlan> createMasterPlan(
    String token,
    SubscriptionPlan plan,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/plans'),
      headers: _authHeaders(token),
      body: jsonEncode(plan.toCreateJson()),
    );
    return SubscriptionPlan.fromJson(_decodeResponse(response));
  }

  Future<void> deleteMasterPlan(
    String token,
    String code, {
    String? migrateToPlan,
  }) async {
    final uri = Uri.parse('$baseUrl/master/plans/$code');
    final response = await http.delete(
      migrateToPlan == null
          ? uri
          : uri.replace(queryParameters: {'migrate_to_plan': migrateToPlan}),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<BusinessSegment> createMasterSegment(
    String token,
    BusinessSegment segment,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/segments'),
      headers: _authHeaders(token),
      body: jsonEncode(segment.toCreateJson()),
    );
    return BusinessSegment.fromJson(_decodeResponse(response));
  }

  Future<BusinessSegment> updateMasterSegment(
    String token,
    String code,
    BusinessSegment segment,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/segments/$code'),
      headers: _authHeaders(token),
      body: jsonEncode(segment.toUpdateJson()),
    );
    return BusinessSegment.fromJson(_decodeResponse(response));
  }

  Future<void> deleteMasterSegment(
    String token,
    String code, {
    String? migrateToSegment,
  }) async {
    final uri = Uri.parse('$baseUrl/master/segments/$code');
    final response = await http.delete(
      migrateToSegment == null
          ? uri
          : uri.replace(
              queryParameters: {'migrate_to_segment': migrateToSegment},
            ),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<List<CompanyBilling>> listMasterBillings(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/billings'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => CompanyBilling.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CompanyBilling> createMasterBilling(
    String token,
    CompanyBillingCreate input,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/billings'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toJson()),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<CompanyBilling> updateMasterBilling(
    String token,
    int billingId,
    CompanyBillingUpdate input,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/billings/$billingId'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toJson()),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<List<CompanyBilling>> generateCurrentMasterBillings(
    String token,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/billings/generate-current'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => CompanyBilling.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CompanyBilling> generateMasterBillingPix(
    String token,
    int billingId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/billings/$billingId/pix'),
      headers: _authHeaders(token),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<CompanyBilling> syncMasterBillingPayment(
    String token,
    int billingId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/billings/$billingId/sync'),
      headers: _authHeaders(token),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<CompanyBilling> payMasterBilling(String token, int billingId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/billings/$billingId/pay'),
      headers: _authHeaders(token),
      body: jsonEncode({}),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<CompanyBilling> cancelMasterBilling(
    String token,
    int billingId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/billings/$billingId/cancel'),
      headers: _authHeaders(token),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<PaymentSetting> getMercadoPagoSetting(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/payment-settings/mercado-pago'),
      headers: _authHeaders(token),
    );
    return PaymentSetting.fromJson(_decodeResponse(response));
  }

  Future<PaymentSetting> updateMercadoPagoSetting(
    String token,
    PaymentSettingInput input,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/payment-settings/mercado-pago'),
      headers: _authHeaders(token),
      body: jsonEncode(input.toJson()),
    );
    return PaymentSetting.fromJson(_decodeResponse(response));
  }

  Future<DashboardSummary> getDashboardSummary(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/dashboard/summary'),
      headers: _authHeaders(token),
    );
    final data = _decodeResponse(response);
    return DashboardSummary.fromJson(data);
  }

  Future<CompanyBilling> getDashboardBillingPayment(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/dashboard/billing-payment'),
      headers: _authHeaders(token),
    );
    return CompanyBilling.fromJson(_decodeResponse(response));
  }

  Future<List<DashboardContent>> listMasterDashboardContents(
    String token,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/master/dashboard-contents'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => DashboardContent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DashboardContent> createMasterDashboardContent(
    String token,
    DashboardContentPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/dashboard-contents'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return DashboardContent.fromJson(_decodeResponse(response));
  }

  Future<DashboardContent> updateMasterDashboardContent(
    String token,
    int contentId,
    DashboardContentPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/master/dashboard-contents/$contentId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return DashboardContent.fromJson(_decodeResponse(response));
  }

  Future<void> deleteMasterDashboardContent(String token, int contentId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/master/dashboard-contents/$contentId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<String> uploadImage(
    String token, {
    required Uint8List bytes,
    required String filename,
    bool master = false,
  }) async {
    final path = master ? 'master-image' : 'image';
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/uploads/$path'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    final lowerName = filename.toLowerCase();
    final contentType = lowerName.endsWith('.png')
        ? MediaType('image', 'png')
        : lowerName.endsWith('.webp')
        ? MediaType('image', 'webp')
        : lowerName.endsWith('.gif')
        ? MediaType('image', 'gif')
        : MediaType('image', 'jpeg');
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decodeResponse(response);
    return data['url']?.toString() ?? '';
  }

  Future<Map<String, String>> uploadContract(
    String token, {
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/uploads/master-contract'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    final lowerName = filename.toLowerCase();
    final contentType = lowerName.endsWith('.pdf')
        ? MediaType('application', 'pdf')
        : lowerName.endsWith('.docx')
        ? MediaType(
            'application',
            'vnd.openxmlformats-officedocument.wordprocessingml.document',
          )
        : lowerName.endsWith('.doc')
        ? MediaType('application', 'msword')
        : lowerName.endsWith('.png')
        ? MediaType('image', 'png')
        : lowerName.endsWith('.webp')
        ? MediaType('image', 'webp')
        : lowerName.endsWith('.gif')
        ? MediaType('image', 'gif')
        : MediaType('image', 'jpeg');
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decodeResponse(response);
    return {
      'url': data['url']?.toString() ?? '',
      'name': data['name']?.toString() ?? filename,
    };
  }

  Future<List<Client>> listClients(
    String token, {
    String? query,
    int limit = 500,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    final trimmed = query?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      params['q'] = trimmed;
    }
    final response = await http.get(
      Uri.parse('$baseUrl/clients').replace(queryParameters: params),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => Client.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Client> createClient(String token, ClientCreate client) async {
    final response = await http.post(
      Uri.parse('$baseUrl/clients'),
      headers: _authHeaders(token),
      body: jsonEncode(client.toJson()),
    );
    final data = _decodeResponse(response);
    return Client.fromJson(data);
  }

  Future<Client> updateClient(
    String token,
    int clientId,
    ClientUpdate client,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/clients/$clientId'),
      headers: _authHeaders(token),
      body: jsonEncode(client.toJson()),
    );
    final data = _decodeResponse(response);
    return Client.fromJson(data);
  }

  Future<void> deleteClient(String token, int clientId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/clients/$clientId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<List<Equipment>> listEquipments(String token, {int? clientId}) async {
    final uri = clientId == null
        ? Uri.parse('$baseUrl/equipments')
        : Uri.parse('$baseUrl/equipments?client_id=$clientId');
    final response = await http.get(uri, headers: _authHeaders(token));
    final data = _decodeListResponse(response);
    return data
        .map((item) => Equipment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Equipment> createEquipment(
    String token,
    EquipmentCreate equipment,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/equipments'),
      headers: _authHeaders(token),
      body: jsonEncode(equipment.toJson()),
    );
    final data = _decodeResponse(response);
    return Equipment.fromJson(data);
  }

  Future<EquipmentAgentToken> generateEquipmentAgentToken(
    String token,
    int equipmentId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/equipments/$equipmentId/agent-token'),
      headers: _authHeaders(token),
    );
    final data = _decodeResponse(response);
    return EquipmentAgentToken.fromJson(data);
  }

  Future<List<MonitoringSnapshot>> listMonitoringSnapshots(
    String token,
    int equipmentId,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/monitoring/snapshots?equipment_id=$equipmentId&limit=5',
      ),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => MonitoringSnapshot.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<EquipmentCurrentStatus?> getEquipmentCurrentStatus(
    String token,
    int equipmentId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/monitoring/current-status?equipment_id=$equipmentId'),
      headers: _authHeaders(token),
    );
    if (response.body == 'null') {
      return null;
    }
    final data = _decodeResponse(response);
    return EquipmentCurrentStatus.fromJson(data);
  }

  Future<List<EquipmentAlert>> listEquipmentAlerts(
    String token,
    int equipmentId,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/monitoring/alerts?equipment_id=$equipmentId&limit=20',
      ),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => EquipmentAlert.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Product>> listProducts(
    String token, {
    bool? active,
    String? query,
    int limit = 500,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (active != null) {
      params['active'] = '$active';
    }
    final trimmed = query?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      params['q'] = trimmed;
    }
    final uri = Uri.parse('$baseUrl/products').replace(queryParameters: params);
    final response = await http.get(uri, headers: _authHeaders(token));
    final data = _decodeListResponse(response);
    return data
        .map((item) => Product.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Product> createProduct(String token, ProductPayload payload) async {
    final response = await http.post(
      Uri.parse('$baseUrl/products'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Product.fromJson(_decodeResponse(response));
  }

  Future<Product> updateProduct(
    String token,
    int productId,
    ProductPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/products/$productId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Product.fromJson(_decodeResponse(response));
  }

  Future<FiscalAssistantResponse> getFiscalAssistantProductSuggestions(
    String token, {
    int? productId,
    String? description,
    String? barcode,
  }) async {
    final query = <String, String>{};
    if (productId != null) query['product_id'] = productId.toString();
    if (description != null && description.trim().isNotEmpty) {
      query['description'] = description.trim();
    }
    if (barcode != null && barcode.trim().isNotEmpty) {
      query['barcode'] = barcode.trim();
    }
    final uri = Uri.parse(
      '$baseUrl/fiscal-assistant/product-suggestions',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: _authHeaders(token));
    return FiscalAssistantResponse.fromJson(_decodeResponse(response));
  }

  Future<Product> lookupProductByCode(String token, String code) async {
    final uri = Uri.parse(
      '$baseUrl/products/lookup/by-code',
    ).replace(queryParameters: {'code': code});
    final response = await http.get(uri, headers: _authHeaders(token));
    return Product.fromJson(_decodeResponse(response));
  }

  Future<List<StockMovement>> listProductStockMovements(
    String token,
    int productId, {
    int limit = 100,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/products/$productId/stock-movements?limit=$limit'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => StockMovement.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<StockMovement>> listRecentStockWithdrawals(
    String token, {
    DateTime? dateFrom,
    DateTime? dateTo,
    int? productId,
    String? reason,
    int? userId,
    int limit = 1000,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (dateFrom != null) query['date_from'] = _dateParameter(dateFrom);
    if (dateTo != null) query['date_to'] = _dateParameter(dateTo);
    if (productId != null) query['product_id'] = '$productId';
    if (reason != null && reason.isNotEmpty) query['reason'] = reason;
    if (userId != null) query['user_id'] = '$userId';
    final response = await http.get(
      Uri.parse(
        '$baseUrl/products/stock-withdrawals/recent',
      ).replace(queryParameters: query),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => StockMovement.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  String _dateParameter(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  Future<StockMovement> createStockWithdrawal(
    String token, {
    required int productId,
    required double quantity,
    required String reasonCode,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/products/$productId/stock-withdrawals'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'quantity': quantity,
        'reason_code': reasonCode,
        'notes': notes,
      }),
    );
    return StockMovement.fromJson(_decodeResponse(response));
  }

  Future<List<ProductBatch>> listProductBatches(
    String token,
    int productId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/products/$productId/batches'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => ProductBatch.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProductCompositionItem>> listProductComposition(
    String token,
    int productId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/products/$productId/composition'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) =>
              ProductCompositionItem.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ProductCompositionItem> createProductCompositionItem(
    String token,
    int productId,
    ProductCompositionPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/products/$productId/composition'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ProductCompositionItem.fromJson(_decodeResponse(response));
  }

  Future<ProductCompositionItem> updateProductCompositionItem(
    String token,
    int productId,
    int itemId,
    ProductCompositionPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/products/$productId/composition/$itemId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ProductCompositionItem.fromJson(_decodeResponse(response));
  }

  Future<void> deleteProductCompositionItem(
    String token,
    int productId,
    int itemId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/products/$productId/composition/$itemId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<List<Supplier>> listSuppliers(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/stock/suppliers'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => Supplier.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Supplier> createSupplier(String token, SupplierPayload payload) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/suppliers'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Supplier.fromJson(_decodeResponse(response));
  }

  Future<Supplier> updateSupplier(
    String token,
    int supplierId,
    SupplierPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stock/suppliers/$supplierId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Supplier.fromJson(_decodeResponse(response));
  }

  Future<void> deleteSupplier(String token, int supplierId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/stock/suppliers/$supplierId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<List<StockEntry>> listStockEntries(
    String token, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/stock/entries?limit=$limit'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => StockEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<XmlInboxSettings> getXmlInboxSettings(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/xml-inbox/settings'),
      headers: _authHeaders(token),
    );
    return XmlInboxSettings.fromJson(_decodeResponse(response));
  }

  Future<List<XmlInboxMessage>> listXmlInboxMessages(
    String token, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/xml-inbox/messages?limit=$limit'),
      headers: _authHeaders(token),
    );
    return _decodeListResponse(response)
        .map((item) => XmlInboxMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<StockEntry> createReceiptFromXmlInbox(
    String token,
    int messageId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/xml-inbox/messages/$messageId/receipt'),
      headers: _authHeaders(token),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<StockEntry> getStockEntry(String token, int entryId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/stock/entries/$entryId'),
      headers: _authHeaders(token),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<StockEntry> createStockEntry(
    String token,
    StockEntryPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/entries'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<StockEntry> createOpenStockEntry(
    String token,
    StockEntryPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/entries/open'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<StockEntry> updateOpenStockEntry(
    String token,
    int entryId,
    StockEntryPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/stock/entries/$entryId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<StockEntry> receiveStockEntryMobileItem(
    String token,
    int entryId,
    StockEntryMobileItemPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/entries/$entryId/mobile-items'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<StockEntry> confirmOpenStockEntry(String token, int entryId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/entries/$entryId/confirm'),
      headers: _authHeaders(token),
    );
    return StockEntry.fromJson(_decodeResponse(response));
  }

  Future<NfeXmlPreview> previewNfeXml(String token, String xmlContent) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/nfe/xml/preview'),
      headers: _authHeaders(token),
      body: jsonEncode({'xml_content': xmlContent}),
    );
    return NfeXmlPreview.fromJson(_decodeResponse(response));
  }

  Future<Map<String, dynamic>> downloadNfeByKey(
    String token,
    String accessKey,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock/nfe/key/download'),
      headers: _authHeaders(token),
      body: jsonEncode({'access_key': accessKey}),
    );
    return _decodeResponse(response);
  }

  Future<List<ProductionOrder>> listProductionOrders(
    String token, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/production-orders?limit=$limit'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => ProductionOrder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ProductionOrderPreview> previewProductionOrder(
    String token, {
    required int productId,
    required double quantity,
  }) async {
    final uri = Uri.parse('$baseUrl/production-orders/preview').replace(
      queryParameters: {
        'product_id': productId.toString(),
        'quantity': quantity.toString(),
      },
    );
    final response = await http.get(uri, headers: _authHeaders(token));
    return ProductionOrderPreview.fromJson(_decodeResponse(response));
  }

  Future<ProductionOrder> createProductionOrder(
    String token,
    ProductionOrderPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production-orders'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ProductionOrder.fromJson(_decodeResponse(response));
  }

  Future<ProductionOrder> startProductionOrder(
    String token,
    int orderId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production-orders/$orderId/start'),
      headers: _authHeaders(token),
    );
    return ProductionOrder.fromJson(_decodeResponse(response));
  }

  Future<ProductionOrder> completeProductionOrder(
    String token,
    int orderId,
    ProductionOrderCompletePayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production-orders/$orderId/complete'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ProductionOrder.fromJson(_decodeResponse(response));
  }

  Future<ProductionOrder> cancelProductionOrder(
    String token,
    int orderId,
    String reason,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production-orders/$orderId/cancel'),
      headers: _authHeaders(token),
      body: jsonEncode({'reason': reason}),
    );
    return ProductionOrder.fromJson(_decodeResponse(response));
  }

  Future<List<Sale>> listSales(
    String token, {
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (dateFrom != null) query['date_from'] = _dateParameter(dateFrom);
    if (dateTo != null) query['date_to'] = _dateParameter(dateTo);
    final response = await http.get(
      Uri.parse('$baseUrl/sales').replace(queryParameters: query),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => Sale.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Sale> createSale(String token, SalePayload payload) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sales'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Sale.fromJson(_decodeResponse(response));
  }

  Future<Sale> cancelSale(String token, int saleId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/sales/$saleId/cancel'),
      headers: _authHeaders(token),
    );
    return Sale.fromJson(_decodeResponse(response));
  }

  Future<Sale> updateSalePayments(
    String token,
    int saleId,
    List<SalePaymentPayload> payments,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/sales/$saleId/payments'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'payments': payments.map((payment) => payment.toJson()).toList(),
      }),
    );
    return Sale.fromJson(_decodeResponse(response));
  }

  Future<List<SaleSeller>> listSaleSellers(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/sales/sellers'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => SaleSeller.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PdvTerminal> registerPdvTerminal(
    String token,
    PdvTerminalRegisterPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pdv/terminals/register'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return PdvTerminal.fromJson(_decodeResponse(response));
  }

  Future<PdvTerminalActivationCode> createPdvTerminalActivationCode(
    String token,
    PdvTerminalActivationCreatePayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pdv/terminals/activation-code'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return PdvTerminalActivationCode.fromJson(_decodeResponse(response));
  }

  Future<PdvTerminalActivationCode> createMasterPdvTerminalActivationCode(
    String token,
    MasterPdvTerminalActivationCreatePayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/master/pdv/terminals/activation-code'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return PdvTerminalActivationCode.fromJson(_decodeResponse(response));
  }

  Future<List<PdvTerminal>> listMasterPdvTerminals(
    String token,
    String companyCode,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/master/pdv/terminals',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => PdvTerminal.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PdvBusinessDaySettings> getMasterPdvBusinessDaySettings(
    String token,
    String companyCode,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/master/pdv/business-day-settings',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
    );
    return PdvBusinessDaySettings.fromJson(_decodeResponse(response));
  }

  Future<PdvBusinessDaySettings> updateMasterPdvBusinessDaySettings(
    String token,
    String companyCode,
    int cutoffMinutes,
  ) async {
    final response = await http.put(
      Uri.parse(
        '$baseUrl/master/pdv/business-day-settings',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
      body: jsonEncode({'cutoff_minutes': cutoffMinutes}),
    );
    return PdvBusinessDaySettings.fromJson(_decodeResponse(response));
  }

  Future<PdvTerminal> updateMasterPdvTerminalNumber(
    String token,
    String companyCode,
    int terminalId,
    String cashRegisterNumber,
  ) async {
    final response = await http.put(
      Uri.parse(
        '$baseUrl/master/pdv/terminals/$terminalId/number',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
      body: jsonEncode({'cash_register_number': cashRegisterNumber}),
    );
    return PdvTerminal.fromJson(_decodeResponse(response));
  }

  Future<void> deleteMasterPdvTerminal(
    String token,
    String companyCode,
    int terminalId,
  ) async {
    final response = await http.delete(
      Uri.parse(
        '$baseUrl/master/pdv/terminals/$terminalId',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 204) {
      _decodeResponse(response);
    }
  }

  Future<List<PdvTerminalCommand>> listMasterPdvTerminalCommands(
    String token,
    String companyCode,
    int terminalId,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/master/pdv/terminals/$terminalId/commands',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => PdvTerminalCommand.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<PdvTerminalCommand> createMasterPdvTerminalCommand(
    String token,
    String companyCode,
    int terminalId,
    String action, {
    String? message,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/master/pdv/terminals/$terminalId/commands',
      ).replace(queryParameters: {'company_code': companyCode}),
      headers: _authHeaders(token),
      body: jsonEncode({'action': action, 'message': message}),
    );
    return PdvTerminalCommand.fromJson(_decodeResponse(response));
  }

  Future<PdvTerminal> sendPdvTerminalHeartbeat(
    String token,
    PdvTerminalHeartbeatPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pdv/terminals/heartbeat'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return PdvTerminal.fromJson(_decodeResponse(response));
  }

  Future<List<PdvTerminal>> listPdvTerminals(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pdv/terminals'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => PdvTerminal.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PdvBusinessDaySettings> getPdvBusinessDaySettings(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pdv/business-day-settings'),
      headers: _authHeaders(token),
    );
    return PdvBusinessDaySettings.fromJson(_decodeResponse(response));
  }

  Future<PdvBusinessDaySettings> updatePdvBusinessDaySettings(
    String token,
    int cutoffMinutes,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/pdv/business-day-settings'),
      headers: _authHeaders(token),
      body: jsonEncode({'cutoff_minutes': cutoffMinutes}),
    );
    return PdvBusinessDaySettings.fromJson(_decodeResponse(response));
  }

  Future<PdvTerminal> updatePdvTerminalNumber(
    String token,
    int terminalId,
    String cashRegisterNumber,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/pdv/terminals/$terminalId/number'),
      headers: _authHeaders(token),
      body: jsonEncode({'cash_register_number': cashRegisterNumber}),
    );
    return PdvTerminal.fromJson(_decodeResponse(response));
  }

  Future<void> deletePdvTerminal(String token, int terminalId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/pdv/terminals/$terminalId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 204) {
      _decodeResponse(response);
    }
  }

  Future<List<Receivable>> listReceivables(
    String token, {
    String? status,
    int? clientId,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (clientId != null) params['client_id'] = '$clientId';
    final uri = Uri.parse(
      '$baseUrl/receivables',
    ).replace(queryParameters: params);
    final response = await http.get(uri, headers: _authHeaders(token));
    final data = _decodeListResponse(response);
    return data
        .map((item) => Receivable.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Receivable> createManualReceivable(
    String token,
    ReceivableManualPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/receivables'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Receivable.fromJson(_decodeResponse(response));
  }

  Future<Receivable> payReceivable(
    String token,
    int receivableId,
    ReceivablePaymentPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/receivables/$receivableId/payments'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Receivable.fromJson(_decodeResponse(response));
  }

  Future<Receivable> cancelReceivable(String token, int receivableId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/receivables/$receivableId/cancel'),
      headers: _authHeaders(token),
    );
    return Receivable.fromJson(_decodeResponse(response));
  }

  Future<List<Receivable>> payClientReceivables(
    String token,
    int clientId,
    ReceivablePaymentPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/receivables/clients/$clientId/payments'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => Receivable.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Payable>> listPayables(
    String token, {
    String? status,
    int? supplierId,
    int limit = 100,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (supplierId != null) params['supplier_id'] = '$supplierId';
    final uri = Uri.parse('$baseUrl/payables').replace(queryParameters: params);
    final response = await http.get(uri, headers: _authHeaders(token));
    final data = _decodeListResponse(response);
    return data
        .map((item) => Payable.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Payable> createPayable(String token, PayablePayload payload) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payables'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Payable.fromJson(_decodeResponse(response));
  }

  Future<void> deletePayable(String token, int payableId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/payables/$payableId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<Payable> payPayable(
    String token,
    int payableId,
    PayablePaymentPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payables/$payableId/payments'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return Payable.fromJson(_decodeResponse(response));
  }

  Future<CompanyFiscalSetting> getFiscalSettings(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/settings'),
      headers: _authHeaders(token),
    );
    return CompanyFiscalSetting.fromJson(_decodeResponse(response));
  }

  Future<CompanyFiscalSetting> getPdvLogoSettings(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/settings/pdv-logo'),
      headers: _authHeaders(token),
    );
    return CompanyFiscalSetting.fromJson(_decodeResponse(response));
  }

  Future<FiscalSetupChecklist> getFiscalSetupChecklist(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/settings/checklist'),
      headers: _authHeaders(token),
    );
    return FiscalSetupChecklist.fromJson(_decodeResponse(response));
  }

  Future<RtcCompliance> getRtcCompliance(
    String token, {
    String model = '65',
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/rtc-compliance?model=$model'),
      headers: _authHeaders(token),
    );
    return RtcCompliance.fromJson(_decodeResponse(response));
  }

  Future<List<FiscalDocument>> listFiscalDocuments(
    String token, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/documents?limit=$limit'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => FiscalDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CompanyFiscalSetting> updateFiscalSettings(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/fiscal/settings'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    return CompanyFiscalSetting.fromJson(_decodeResponse(response));
  }

  Future<CompanyFiscalSetting> updatePdvLogoSettings(
    String token,
    String? logoUrl,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/fiscal/settings/pdv-logo'),
      headers: _authHeaders(token),
      body: jsonEncode({'logo_url': logoUrl}),
    );
    return CompanyFiscalSetting.fromJson(_decodeResponse(response));
  }

  Future<NfceNumberingSyncResult> syncNfceNumbering(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/settings/sync-nfce-numbering'),
      headers: _authHeaders(token),
    );
    return NfceNumberingSyncResult.fromJson(_decodeResponse(response));
  }

  Future<Map<String, dynamic>> recoverFiscalDocumentsFromSefaz(
    String token,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/recover-from-sefaz'),
      headers: _authHeaders(token),
    );
    return _decodeResponse(response);
  }

  Future<List<FiscalOutputRule>> listFiscalOutputRules(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/output-rules'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => FiscalOutputRule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<FiscalOutputRule> createFiscalOutputRule(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/output-rules'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    return FiscalOutputRule.fromJson(_decodeResponse(response));
  }

  Future<FiscalOutputRule> updateFiscalOutputRule(
    String token,
    int ruleId,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/fiscal/output-rules/$ruleId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    return FiscalOutputRule.fromJson(_decodeResponse(response));
  }

  Future<void> deleteFiscalOutputRule(String token, int ruleId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/fiscal/output-rules/$ruleId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<FiscalOutputRulePreview> previewFiscalOutputRule(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/output-rules/preview'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    return FiscalOutputRulePreview.fromJson(_decodeResponse(response));
  }

  Future<Map<String, dynamic>> uploadFiscalCertificate(
    String token, {
    required Uint8List bytes,
    required String filename,
    required String password,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/fiscal/certificate'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('certificate', bytes, filename: filename),
    );
    request.fields['password'] = password;
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _decodeResponse(response);
  }

  Future<void> deleteFiscalCertificate(String token) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/fiscal/certificate'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<FiscalDocument> prepareFiscalDocument(
    String token, {
    required int saleId,
    String documentType = 'nfce',
    int? fiscalClientId,
    String? consumerCpf,
    String? operationNature,
    String paymentCondition = 'vista',
    String? fiscalNotes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/prepare'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'sale_id': saleId,
        'fiscal_client_id': fiscalClientId,
        'document_type': documentType,
        'consumer_cpf': consumerCpf,
        'operation_nature': operationNature,
        'payment_condition': paymentCondition,
        'fiscal_notes': fiscalNotes,
      }),
    );
    return FiscalDocument.fromJson(_decodeResponse(response));
  }

  Future<FiscalSaleDraft> getFiscalSaleDraft(
    String token,
    String saleNumber,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/fiscal/sales/${Uri.encodeComponent(saleNumber)}/draft',
      ),
      headers: _authHeaders(token),
    );
    return FiscalSaleDraft.fromJson(_decodeResponse(response));
  }

  Future<List<FiscalProductLookup>> lookupFiscalProducts(
    String token,
    String query,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/fiscal/products/lookup?q=${Uri.encodeQueryComponent(query)}&limit=200',
      ),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => FiscalProductLookup.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<FiscalDocument> prepareFiscalDocumentWithItems(
    String token, {
    required int saleId,
    required List<FiscalDraftItem> items,
    String documentType = 'nfce',
    int? fiscalClientId,
    String? consumerCpf,
    String? operationNature,
    String paymentCondition = 'vista',
    String? fiscalNotes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/prepare-with-items'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'sale_id': saleId,
        'fiscal_client_id': fiscalClientId,
        'document_type': documentType,
        'consumer_cpf': consumerCpf,
        'operation_nature': operationNature,
        'payment_condition': paymentCondition,
        'fiscal_notes': fiscalNotes,
        'items': items.map((item) => item.toOverrideJson()).toList(),
      }),
    );
    return FiscalDocument.fromJson(_decodeResponse(response));
  }

  Future<FiscalDocument> prepareManualFiscalDocument(
    String token, {
    required List<FiscalDraftItem> items,
    String documentType = 'nfce',
    int? fiscalClientId,
    String? consumerCpf,
    String? operationNature,
    String paymentCondition = 'vista',
    String? fiscalNotes,
    bool stockDeductionOnAuthorize = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/prepare-manual'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'fiscal_client_id': fiscalClientId,
        'document_type': documentType,
        'consumer_cpf': consumerCpf,
        'operation_nature': operationNature,
        'payment_condition': paymentCondition,
        'fiscal_notes': fiscalNotes,
        'stock_deduction_on_authorize': stockDeductionOnAuthorize,
        'items': items.map((item) => item.toOverrideJson()).toList(),
      }),
    );
    return FiscalDocument.fromJson(_decodeResponse(response));
  }

  Future<FiscalDocument> authorizeFiscalDocument(
    String token,
    int documentId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/$documentId/authorize'),
      headers: _authHeaders(token),
    );
    return FiscalDocument.fromJson(_decodeResponse(response));
  }

  Future<FiscalDocument> transmitFiscalContingencyDocument(
    String token,
    int documentId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/$documentId/transmit-contingency'),
      headers: _authHeaders(token),
    );
    return FiscalDocument.fromJson(_decodeResponse(response));
  }

  Future<FiscalDocument> cancelFiscalDocument(
    String token,
    int documentId,
    String reason,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/fiscal/documents/$documentId/cancel'),
      headers: _authHeaders(token),
      body: jsonEncode({'reason': reason}),
    );
    return FiscalDocument.fromJson(_decodeResponse(response));
  }

  Future<Uint8List> getFiscalDanfe(String token, int documentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/fiscal/documents/$documentId/danfe'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
    return response.bodyBytes;
  }

  Future<List<SystemUser>> listSystemUsers(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => SystemUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<PdvOperator>> listPdvOperators(
    String token, {
    bool activeOnly = true,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pdv/operators?active_only=$activeOnly'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => PdvOperator.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PdvOperator> createPdvOperator(
    String token,
    PdvOperatorPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pdv/operators'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toCreateJson()),
    );
    return PdvOperator.fromJson(_decodeResponse(response));
  }

  Future<PdvOperator> updatePdvOperator(
    String token,
    int operatorId,
    PdvOperatorPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/pdv/operators/$operatorId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toUpdateJson()),
    );
    return PdvOperator.fromJson(_decodeResponse(response));
  }

  Future<void> deletePdvOperator(String token, int operatorId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/pdv/operators/$operatorId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<PdvAuthorization> authorizePdvAction(
    String token, {
    required String code,
    required String pin,
    required String action,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pdv/authorize'),
      headers: _authHeaders(token),
      body: jsonEncode({'code': code, 'pin': pin, 'action': action}),
    );
    return PdvAuthorization.fromJson(_decodeResponse(response));
  }

  Future<CashClosing> createCashClosing(
    String token,
    CashClosingPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/pdv/closings'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return CashClosing.fromJson(_decodeResponse(response));
  }

  Future<List<CashClosing>> listCashClosings(
    String token, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/pdv/closings?limit=$limit'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => CashClosing.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CashClosing> reviewCashClosing(
    String token,
    int closingId,
    CashClosingReviewPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/pdv/closings/$closingId/treasury-review'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return CashClosing.fromJson(_decodeResponse(response));
  }

  Future<SystemUser> createSystemUser(
    String token,
    SystemUserPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toCreateJson()),
    );
    return SystemUser.fromJson(_decodeResponse(response));
  }

  Future<SystemUser> updateSystemUser(
    String token,
    int userId,
    SystemUserPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/users/$userId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toUpdateJson()),
    );
    return SystemUser.fromJson(_decodeResponse(response));
  }

  Future<void> deleteSystemUser(String token, int userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/users/$userId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<List<SystemRole>> listSystemRoles(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/roles'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => SystemRole.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SystemRole> createSystemRole(
    String token,
    SystemRolePayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/roles'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return SystemRole.fromJson(_decodeResponse(response));
  }

  Future<SystemRole> updateSystemRole(
    String token,
    int roleId,
    SystemRolePayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/roles/$roleId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return SystemRole.fromJson(_decodeResponse(response));
  }

  Future<void> deleteSystemRole(String token, int roleId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/roles/$roleId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        throw ApiException(_detailMessage(decoded), data: decoded);
      }
      throw ApiException('Erro na API.');
    }
  }

  Future<List<SystemPermission>> listSystemPermissions(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/permissions'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => SystemPermission.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<SystemUser> setSystemUserPermission(
    String token,
    int userId, {
    required String permissionCode,
    required bool allowed,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/admin/users/$userId/permissions'),
      headers: _authHeaders(token),
      body: jsonEncode({'permission_code': permissionCode, 'allowed': allowed}),
    );
    return SystemUser.fromJson(_decodeResponse(response));
  }

  Future<List<ServiceOrder>> listServiceOrders(
    String token, {
    String? status,
    int? clientId,
  }) async {
    final query = <String, String>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (clientId != null) query['client_id'] = '$clientId';
    final uri = Uri.parse(
      '$baseUrl/service-orders',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: _authHeaders(token));
    final data = _decodeListResponse(response);
    return data
        .map((item) => ServiceOrder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ServiceContract>> listServiceContracts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/service-contracts'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => ServiceContract.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceContract> createServiceContract(
    String token,
    ServiceContractPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/service-contracts'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ServiceContract.fromJson(_decodeResponse(response));
  }

  Future<ServiceContract> updateServiceContract(
    String token,
    int contractId,
    ServiceContractPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/service-contracts/$contractId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ServiceContract.fromJson(_decodeResponse(response));
  }

  Future<List<ServiceAppointment>> generateServiceAppointments(
    String token,
    int contractId, {
    required String periodStart,
    required String periodEnd,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/service-contracts/$contractId/appointments/generate'),
      headers: _authHeaders(token),
      body: jsonEncode({'period_start': periodStart, 'period_end': periodEnd}),
    );
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => ServiceAppointment.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<ServiceAppointment>> listServiceAppointments(
    String token,
    int contractId, {
    String? periodStart,
    String? periodEnd,
  }) async {
    final query = <String, String>{};
    if (periodStart != null && periodStart.isNotEmpty) {
      query['period_start'] = periodStart;
    }
    if (periodEnd != null && periodEnd.isNotEmpty) {
      query['period_end'] = periodEnd;
    }
    final uri = Uri.parse(
      '$baseUrl/service-contracts/$contractId/appointments',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: _authHeaders(token));
    final data = _decodeListResponse(response);
    return data
        .map(
          (item) => ServiceAppointment.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ServiceAppointment> updateServiceAppointment(
    String token,
    int appointmentId,
    Map<String, dynamic> payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/service-contracts/appointments/$appointmentId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    );
    return ServiceAppointment.fromJson(_decodeResponse(response));
  }

  Future<ServiceAppointment> confirmServiceAppointment(
    String token,
    int appointmentId,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/service-contracts/appointments/$appointmentId/confirm',
      ),
      headers: _authHeaders(token),
    );
    return ServiceAppointment.fromJson(_decodeResponse(response));
  }

  Future<ServiceAppointment> cancelServiceAppointment(
    String token,
    int appointmentId, {
    String reason = 'Cancelamento do apontamento',
  }) async {
    final uri = Uri.parse(
      '$baseUrl/service-contracts/appointments/$appointmentId/cancel',
    ).replace(queryParameters: {'reason': reason});
    final response = await http.post(uri, headers: _authHeaders(token));
    return ServiceAppointment.fromJson(_decodeResponse(response));
  }

  Future<ServiceBilling> createServiceBilling(
    String token,
    int contractId, {
    required String periodStart,
    required String periodEnd,
    String? dueDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/service-contracts/$contractId/billings'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'period_start': periodStart,
        'period_end': periodEnd,
        'due_date': dueDate,
      }),
    );
    return ServiceBilling.fromJson(_decodeResponse(response));
  }

  Future<List<ServiceBilling>> listServiceBillings(
    String token,
    int contractId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/service-contracts/$contractId/billings'),
      headers: _authHeaders(token),
    );
    final data = _decodeListResponse(response);
    return data
        .map((item) => ServiceBilling.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceBilling> cancelServiceBilling(
    String token,
    int contractId,
    int billingId,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/service-contracts/$contractId/billings/$billingId/cancel',
      ),
      headers: _authHeaders(token),
    );
    return ServiceBilling.fromJson(_decodeResponse(response));
  }

  Future<void> reopenCanceledServiceBilling(
    String token,
    int contractId,
    int billingId,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/service-contracts/$contractId/billings/$billingId/reopen',
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      _decodeResponse(response);
    }
  }

  Future<ServiceOrder> createServiceOrder(
    String token,
    ServiceOrderPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/service-orders'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ServiceOrder.fromJson(_decodeResponse(response));
  }

  Future<ServiceOrder> updateServiceOrder(
    String token,
    int serviceOrderId,
    ServiceOrderPayload payload,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/service-orders/$serviceOrderId'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ServiceOrder.fromJson(_decodeResponse(response));
  }

  Future<ServiceOrderItem> addServiceOrderItem(
    String token,
    int serviceOrderId,
    ServiceOrderItemPayload payload,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/service-orders/$serviceOrderId/items'),
      headers: _authHeaders(token),
      body: jsonEncode(payload.toJson()),
    );
    return ServiceOrderItem.fromJson(_decodeResponse(response));
  }

  Future<ServiceOrder> deleteServiceOrderItem(
    String token,
    int serviceOrderId,
    int itemId,
  ) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/service-orders/$serviceOrderId/items/$itemId'),
      headers: _authHeaders(token),
    );
    return ServiceOrder.fromJson(_decodeResponse(response));
  }

  Future<String> printServiceOrderThermal(
    String token,
    int serviceOrderId, {
    required String printerHost,
    int printerPort = 9100,
    int paperWidth = 80,
    int copies = 1,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/service-orders/$serviceOrderId/thermal-print'),
      headers: _authHeaders(token),
      body: jsonEncode({
        'printer_host': printerHost,
        'printer_port': printerPort,
        'paper_width': paperWidth,
        'copies': copies,
      }),
    );
    final data = _decodeResponse(response);
    return data['message']?.toString() ?? 'Cupom enviado para a impressora.';
  }

  Future<void> deleteServiceOrder(String token, int serviceOrderId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/service-orders/$serviceOrderId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode >= 400) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        throw ApiException(_detailMessage(decoded));
      }
      throw ApiException('Erro na API.');
    }
  }

  Map<String, String> _authHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'detail': 'Resposta inesperada da API.'};
    if (response.statusCode >= 400) {
      throw ApiException(
        _detailMessage(data),
        data: data,
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  List<dynamic> _decodeListResponse(http.Response response) {
    if (response.statusCode >= 400) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        throw ApiException(
          _detailMessage(decoded),
          data: decoded,
          statusCode: response.statusCode,
        );
      }
      throw ApiException('Erro na API.', statusCode: response.statusCode);
    }
    final data = jsonDecode(response.body);
    if (data is! List<dynamic>) {
      throw ApiException('Resposta inesperada da API.');
    }
    return data;
  }

  String _detailMessage(Map<String, dynamic> data) {
    final detail = data['detail'];
    if (detail is String) {
      return detail;
    }
    if (detail is Map<String, dynamic>) {
      return detail['message']?.toString() ?? 'Erro na API.';
    }
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map<String, dynamic>) {
        return first['msg']?.toString() ?? 'Erro de validacao.';
      }
    }
    return 'Erro na API.';
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.data, this.statusCode});

  final String message;
  final Map<String, dynamic>? data;
  final int? statusCode;

  @override
  String toString() => message;
}
