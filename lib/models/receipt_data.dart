class ReceiptData {
  final String saleNumber;
  final String date;
  final String cashier;
  final String? customerName;
  final String? customerPhone;
  final List<ReceiptItem> items;
  final String subtotalUzs;
  final String discountUzs;
  final String totalUzs;
  final List<ReceiptPayment> payments;
  final String changeDueUzs;
  final String balanceAppliedUzs;
  final String balanceCreditedUzs;
  final String? receiptFormat;
  final CustomerBalance? customerBalance;

  const ReceiptData({
    required this.saleNumber,
    required this.date,
    required this.cashier,
    this.customerName,
    this.customerPhone,
    required this.items,
    required this.subtotalUzs,
    required this.discountUzs,
    required this.totalUzs,
    required this.payments,
    required this.changeDueUzs,
    required this.balanceAppliedUzs,
    required this.balanceCreditedUzs,
    this.receiptFormat,
    this.customerBalance,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) => ReceiptData(
        saleNumber: json['sale_number']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        cashier: json['cashier']?.toString() ?? 'System',
        customerName: json['customer_name']?.toString(),
        customerPhone: json['customer_phone']?.toString(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        subtotalUzs: _toStr(json['subtotal_uzs']),
        discountUzs: _toStr(json['discount_uzs']),
        totalUzs: _toStr(json['total_uzs']),
        payments: (json['payments'] as List<dynamic>?)
                ?.map(
                    (e) => ReceiptPayment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        changeDueUzs: _toStr(json['change_due_uzs']),
        balanceAppliedUzs: _toStr(json['balance_applied_uzs']),
        balanceCreditedUzs: _toStr(json['balance_credited_uzs']),
        receiptFormat: json['receipt_format']?.toString(),
        customerBalance: json['customer_balance'] != null
            ? CustomerBalance.fromJson(
                json['customer_balance'] as Map<String, dynamic>)
            : null,
      );

  static String _toStr(dynamic v) => v?.toString() ?? '0';
}

class ReceiptItem {
  final String name;
  final String code;
  final String quantity;
  final String price;
  final String total;
  final bool isPart;

  const ReceiptItem({
    required this.name,
    required this.code,
    required this.quantity,
    required this.price,
    required this.total,
    this.isPart = false,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
        name: json['name']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        quantity: json['quantity']?.toString() ?? '0',
        price: json['price']?.toString() ?? '0',
        total: json['total']?.toString() ?? '0',
        isPart: json['is_part'] == true,
      );
}

class ReceiptPayment {
  final String method;
  final String amount;

  const ReceiptPayment({required this.method, required this.amount});

  factory ReceiptPayment.fromJson(Map<String, dynamic> json) => ReceiptPayment(
        method: json['method']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '0',
      );
}

class CustomerBalance {
  final String debtUzs;
  final String debtUsd;

  const CustomerBalance({required this.debtUzs, required this.debtUsd});

  factory CustomerBalance.fromJson(Map<String, dynamic> json) =>
      CustomerBalance(
        debtUzs: json['debt_uzs']?.toString() ?? '0',
        debtUsd: json['debt_usd']?.toString() ?? '0',
      );
}
