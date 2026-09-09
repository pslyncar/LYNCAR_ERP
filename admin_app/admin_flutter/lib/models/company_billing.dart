class CompanyBilling {
  const CompanyBilling({
    required this.id,
    required this.companyId,
    required this.companyCode,
    required this.companyName,
    required this.referenceMonth,
    required this.dueDate,
    required this.amount,
    this.interestAmount = 0,
    this.lateFeeAmount = 0,
    this.monetaryCorrectionAmount = 0,
    this.waivedAmount = 0,
    this.totalDue,
    this.paymentMethod,
    required this.status,
    this.paidAt,
    this.paidAmount,
    this.mercadoPagoPaymentId,
    this.mercadoPagoStatus,
    this.mercadoPagoPayerName,
    this.mercadoPagoPayerEmail,
    this.mercadoPagoPayerDocument,
    this.pixQrCode,
    this.pixQrCodeBase64,
    this.pixTicketUrl,
    this.notes,
  });

  final int id;
  final int companyId;
  final String companyCode;
  final String companyName;
  final String referenceMonth;
  final DateTime dueDate;
  final double amount;
  final double interestAmount;
  final double lateFeeAmount;
  final double monetaryCorrectionAmount;
  final double waivedAmount;
  final double? totalDue;
  final String? paymentMethod;
  final String status;
  final DateTime? paidAt;
  final double? paidAmount;
  final String? mercadoPagoPaymentId;
  final String? mercadoPagoStatus;
  final String? mercadoPagoPayerName;
  final String? mercadoPagoPayerEmail;
  final String? mercadoPagoPayerDocument;
  final String? pixQrCode;
  final String? pixQrCodeBase64;
  final String? pixTicketUrl;
  final String? notes;

  bool get isOverdue =>
      status == 'pending' &&
      DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );

  factory CompanyBilling.fromJson(Map<String, dynamic> json) {
    return CompanyBilling(
      id: json['id'] as int,
      companyId: json['company_id'] as int,
      companyCode: json['company_code'] as String,
      companyName: json['company_name'] as String,
      referenceMonth: json['reference_month'] as String,
      dueDate: DateTime.parse(json['due_date'] as String),
      amount: double.parse(json['amount'].toString()),
      interestAmount: double.tryParse('${json['interest_amount'] ?? 0}') ?? 0,
      lateFeeAmount: double.tryParse('${json['late_fee_amount'] ?? 0}') ?? 0,
      monetaryCorrectionAmount:
          double.tryParse('${json['monetary_correction_amount'] ?? 0}') ?? 0,
      waivedAmount: double.tryParse('${json['waived_amount'] ?? 0}') ?? 0,
      totalDue: json['total_due'] == null
          ? null
          : double.tryParse('${json['total_due']}'),
      paymentMethod: json['payment_method']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      paidAt: json['paid_at'] == null
          ? null
          : DateTime.parse(json['paid_at'] as String),
      paidAmount: json['paid_amount'] == null
          ? null
          : double.parse(json['paid_amount'].toString()),
      mercadoPagoPaymentId: json['mercado_pago_payment_id']?.toString(),
      mercadoPagoStatus: json['mercado_pago_status']?.toString(),
      mercadoPagoPayerName: json['mercado_pago_payer_name']?.toString(),
      mercadoPagoPayerEmail: json['mercado_pago_payer_email']?.toString(),
      mercadoPagoPayerDocument: json['mercado_pago_payer_document']?.toString(),
      pixQrCode: json['pix_qr_code']?.toString(),
      pixQrCodeBase64: json['pix_qr_code_base64']?.toString(),
      pixTicketUrl: json['pix_ticket_url']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

class CompanyBillingCreate {
  const CompanyBillingCreate({
    required this.companyId,
    required this.referenceMonth,
    required this.dueDate,
    required this.amount,
    this.paymentMethod,
    this.notes,
  });

  final int companyId;
  final String referenceMonth;
  final DateTime dueDate;
  final double amount;
  final String? paymentMethod;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'company_id': companyId,
      'reference_month': referenceMonth,
      'due_date': _dateOnly(dueDate),
      'amount': amount,
      'payment_method': paymentMethod,
      'notes': notes,
    };
  }
}

class CompanyBillingUpdate {
  const CompanyBillingUpdate({
    this.dueDate,
    this.amount,
    this.paymentMethod,
    this.status,
    this.notes,
  });

  final DateTime? dueDate;
  final double? amount;
  final String? paymentMethod;
  final String? status;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      if (dueDate != null) 'due_date': _dateOnly(dueDate!),
      if (amount != null) 'amount': amount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
    };
  }
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
