import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class PdvUpdateInfo {
  const PdvUpdateInfo({
    required this.version,
    required this.url,
    required this.sha256,
    required this.required,
    required this.mandatory,
    required this.installWhen,
    this.buildNumber,
    this.size,
    this.message,
    this.releaseNotes,
  });

  final String version;
  final int? buildNumber;
  final String url;
  final String sha256;
  final int? size;
  final bool required;
  final bool mandatory;
  final String installWhen;
  final String? message;
  final String? releaseNotes;

  factory PdvUpdateInfo.fromJson(Map<String, dynamic> json) {
    return PdvUpdateInfo(
      version: json['version']?.toString() ?? '',
      buildNumber: (json['build_number'] as num?)?.toInt(),
      url: json['url']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt(),
      required: json['required'] == true,
      mandatory: json['mandatory'] == true,
      installWhen: json['install_when']?.toString() ?? 'cashier_closed',
      message: json['message']?.toString(),
      releaseNotes: json['release_notes']?.toString(),
    );
  }

  bool get isValid {
    return version.trim().isNotEmpty &&
        url.trim().isNotEmpty &&
        sha256.trim().isNotEmpty;
  }
}

class PdvAutoUpdateService {
  PdvAutoUpdateService({
    required this.apiBaseUrl,
    required this.token,
    required this.currentVersion,
    required this.channel,
    this.terminalId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiBaseUrl;
  final String token;
  final String currentVersion;
  final String channel;
  final String? terminalId;
  final http.Client _client;

  static const _updatesDirName = 'LyncarPDV\\updates';

  Future<PdvUpdateInfo?> check() async {
    if (!Platform.isWindows) return null;
    final uri = Uri.parse('$apiBaseUrl/master/pdv/update/check').replace(
      queryParameters: {
        'current_version': currentVersion,
        'platform': 'windows',
        'channel': channel,
        if (terminalId != null && terminalId!.trim().isNotEmpty)
          'terminal_id': terminalId!.trim(),
      },
    );
    final response = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404 || response.statusCode == 405) {
      return null;
    }
    if (response.statusCode >= 400) {
      throw PdvUpdateException('Servidor de atualização retornou erro.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['update_available'] != true) return null;
    final info = PdvUpdateInfo.fromJson(decoded);
    if (!info.isValid) {
      throw PdvUpdateException('Dados de atualização incompletos.');
    }
    return info;
  }

  Future<File> downloadAndValidate(
    PdvUpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = await _ensureUpdatesDir();
    final fileName = _safeFileName(info.url, info.version);
    final file = File('${dir.path}\\$fileName');
    if (await file.exists()) {
      final hash = await sha256Of(file);
      if (_sameHash(hash, info.sha256)) {
        final length = await file.length();
        onProgress?.call(length, length);
        return file;
      }
      await file.delete();
    }

    final request = http.Request('GET', Uri.parse(info.url));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400) {
      throw PdvUpdateException('Não foi possível baixar a atualização.');
    }

    final contentLength = response.contentLength;
    final total =
        contentLength != null && contentLength >= 0 ? contentLength : null;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }

    final hash = await sha256Of(file);
    if (!_sameHash(hash, info.sha256)) {
      await file.delete();
      throw PdvUpdateException(
        'O arquivo baixado não passou na validação de segurança.',
      );
    }
    return file;
  }

  Future<void> installAfterExit(File installer) async {
    if (!Platform.isWindows) return;
    if (installer.path.toLowerCase().endsWith('.zip')) {
      await _installZipAfterExit(installer);
      return;
    }
    final dir = await _ensureUpdatesDir();
    final script = File('${dir.path}\\instalar_atualizacao_pdv.ps1');
    final currentExe = Platform.resolvedExecutable;
    final currentPid = pid;
    final scriptContent =
        r'''
$ErrorActionPreference = "SilentlyContinue"
$installer = "__INSTALLER__"
$currentExe = "__CURRENT_EXE__"
$currentPid = __PID__
      Start-Sleep -Seconds 1
while (Get-Process -Id $currentPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 500
}
Start-Process -FilePath $installer -ArgumentList "/VERYSILENT /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS" -Wait
Start-Sleep -Seconds 1
if (Test-Path $currentExe) {
  Start-Process -FilePath $currentExe
}
'''
            .replaceAll('__INSTALLER__', _psEscape(installer.path))
            .replaceAll('__CURRENT_EXE__', _psEscape(currentExe))
            .replaceAll('__PID__', currentPid.toString());
    await script.writeAsString(scriptContent, encoding: utf8);
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _installZipAfterExit(File package) async {
    final currentExe = File(Platform.resolvedExecutable);
    final appDir = currentExe.parent;
    final updater = File('${appDir.path}\\LyncarUpdater.exe');
    if (!await updater.exists()) {
      throw const PdvUpdateException(
        'Atualizador do PDV nao encontrado. Reinstale o PDV Lyncar.',
      );
    }
    await Process.start(updater.path, [
      '--package',
      package.path,
      '--target',
      appDir.path,
      '--restart',
      currentExe.path,
      '--pid',
      pid.toString(),
    ], mode: ProcessStartMode.detached);
  }

  Future<Directory> _ensureUpdatesDir() async {
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    final dir = Directory('$localAppData\\$_updatesDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> sha256Of(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toUpperCase();
  }

  static bool _sameHash(String a, String b) {
    return a.replaceAll(RegExp(r'\s'), '').toUpperCase() ==
        b.replaceAll(RegExp(r'\s'), '').toUpperCase();
  }

  static String _safeFileName(String url, String version) {
    final pathSegments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final last = pathSegments.isEmpty ? '' : pathSegments.last;
    if (last.toLowerCase().endsWith('.exe') ||
        last.toLowerCase().endsWith('.zip')) {
      return last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    }
    return 'PDV_Lyncar_Setup_$version.exe'.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
  }

  static String _psEscape(String value) {
    return value.replaceAll("'", "''");
  }
}

class PdvUpdateException implements Exception {
  const PdvUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
