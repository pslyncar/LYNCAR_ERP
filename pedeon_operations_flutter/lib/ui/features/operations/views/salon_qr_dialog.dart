import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SalonQrDialog extends StatefulWidget {
  const SalonQrDialog({super.key, required this.slug});

  final String slug;

  @override
  State<SalonQrDialog> createState() => _SalonQrDialogState();
}

class _SalonQrDialogState extends State<SalonQrDialog> {
  late final Future<String?> _lanAddress = _findLanAddress();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('QR do salão'),
      content: SizedBox(
        width: 430,
        child: FutureBuilder<String?>(
          future: _lanAddress,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final address = snapshot.data;
            if (address == null) {
              return const Text(
                'Não foi possível localizar o IP desta rede. Conecte este computador e o celular ao mesmo Wi-Fi.',
              );
            }
            final salonUrl = Uri(
              scheme: 'http',
              host: address,
              port: 5001,
              path: '/${widget.slug}/salao',
            ).toString();
            return LayoutBuilder(
              builder: (context, constraints) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Aponte a câmera do celular conectado à mesma rede.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  QrImageView(
                    data: salonUrl,
                    size: math.min(260.0, constraints.maxWidth),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(salonUrl, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: salonUrl));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Endereço copiado.')),
                      );
                    },
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('Copiar endereço'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

Future<String?> _findLanAddress() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final addresses = interfaces
      .expand((interface) => interface.addresses)
      .map((entry) => entry.address)
      .where(_isPrivateIpv4)
      .toList(growable: false);
  if (addresses.isEmpty) return null;
  return addresses.firstWhere(
    (address) => address.startsWith('192.168.'),
    orElse: () => addresses.first,
  );
}

bool _isPrivateIpv4(String address) =>
    address.startsWith('10.') ||
    address.startsWith('192.168.') ||
    RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(address);
