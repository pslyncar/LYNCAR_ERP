import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_operations/domain/models/operation_order.dart';

void main() {
  test('aceita total numerico ou serializado como texto pela API local', () {
    expect(OperationOrder.fromJson(_orderJson(12.34)).total, 12.34);
    expect(OperationOrder.fromJson(_orderJson('12.34')).total, 12.34);
    expect(OperationOrder.fromJson(_orderJson('12,34')).total, 12.34);
  });
}

Map<String, dynamic> _orderJson(Object total) => {
  'public_id': 'PED-1',
  'status': 'ready',
  'total': total,
  'items': <Map<String, dynamic>>[],
};
