import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/features/pedeon/domain/pedeon_order.dart';

void main() {
  test('preserva adicionais e observação do item no pedido', () {
    final order = PedeOnOrderDetail.fromJson({
      'id': 7,
      'public_id': 'pedido-7',
      'display_number': 'P0007',
      'source_channel': 'ifood',
      'external_order_id': 'IFOOD-123',
      'status': 'received',
      'payment_status': 'pending',
      'fulfillment_type': 'pickup',
      'customer_name': 'Cliente',
      'customer_phone': '11999999999',
      'total': '28.00',
      'created_at': '2026-08-22T20:00:00Z',
      'subtotal': '28.00',
      'discount': '0.00',
      'delivery_fee': '0.00',
      'items': [
        {
          'description': 'Hambúrguer',
          'quantity': '1.000',
          'unit': 'un',
          'unit_price': '20.00',
          'total': '28.00',
          'customer_notes': 'Sem cebola',
          'modifiers': [
            {
              'group_name': 'Bebida',
              'option_name': 'Coca-Cola',
              'quantity': '1.000',
              'unit_price': '8.00',
              'total': '8.00',
            },
          ],
        },
      ],
    });

    expect(order.items.single.customerNotes, 'Sem cebola');
    expect(order.sourceChannel, 'ifood');
    expect(order.externalOrderId, 'IFOOD-123');
    expect(order.items.single.modifiers.single.groupName, 'Bebida');
    expect(order.items.single.modifiers.single.optionName, 'Coca-Cola');
    expect(order.items.single.modifiers.single.total, 8);
  });
}
