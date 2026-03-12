import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_octet_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/signers/rsa_signer.dart';

/// Service account credentials parsed from JSON key file.
class ServiceAccountCredentials {
  final String clientEmail;
  final String privateKey;
  final String tokenUri;
  final String? projectId;

  ServiceAccountCredentials({
    required this.clientEmail,
    required this.privateKey,
    required this.tokenUri,
    this.projectId,
  });

  /// Parse from service account JSON file content.
  factory ServiceAccountCredentials.fromJson(String jsonContent) {
    final map = json.decode(jsonContent) as Map<String, dynamic>;

    final type = map['type'] as String?;
    if (type != 'service_account') {
      throw FormatException(
        'Invalid credentials file: expected type "service_account", got "$type"',
      );
    }

    return ServiceAccountCredentials(
      clientEmail: map['client_email'] as String,
      privateKey: map['private_key'] as String,
      tokenUri: (map['token_uri'] as String?) ??
          'https://oauth2.googleapis.com/token',
      projectId: map['project_id'] as String?,
    );
  }

  /// Load from a file path.
  static Future<ServiceAccountCredentials> fromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException(
        'Service account credentials file not found',
        filePath,
      );
    }
    final content = await file.readAsString();
    return ServiceAccountCredentials.fromJson(content);
  }
}

/// Manages OAuth2 access tokens obtained via service account JWT assertion.
class FirebaseAuth {
  final ServiceAccountCredentials credentials;
  final http.Client _httpClient;

  String? _cachedToken;
  DateTime? _tokenExpiry;

  static const _scope = 'https://www.googleapis.com/auth/cloud-platform';

  FirebaseAuth({
    required this.credentials,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Load FirebaseAuth from a credentials file path.
  ///
  /// Resolves the credentials file in this order:
  /// 1. [credentialsFile] parameter (from build.yaml)
  /// 2. `GOOGLE_APPLICATION_CREDENTIALS` environment variable
  /// 3. `.firebase-credentials.json` in [projectPath]
  static Future<FirebaseAuth> fromConfig({
    String? credentialsFile,
    String? projectPath,
    http.Client? httpClient,
  }) async {
    final basePath = projectPath ?? Directory.current.path;

    // 1. Explicit path from build.yaml
    if (credentialsFile != null && credentialsFile.isNotEmpty) {
      final resolvedPath = _resolvePath(credentialsFile, basePath);
      final creds = await ServiceAccountCredentials.fromFile(resolvedPath);
      return FirebaseAuth(credentials: creds, httpClient: httpClient);
    }

    // 2. Environment variable
    final envPath = Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
    if (envPath != null && envPath.isNotEmpty) {
      final creds = await ServiceAccountCredentials.fromFile(envPath);
      return FirebaseAuth(credentials: creds, httpClient: httpClient);
    }

    // 3. Default file in project root
    final defaultPath = '$basePath/.firebase-credentials.json';
    final defaultFile = File(defaultPath);
    if (await defaultFile.exists()) {
      final creds = await ServiceAccountCredentials.fromFile(defaultPath);
      return FirebaseAuth(credentials: creds, httpClient: httpClient);
    }

    throw FileSystemException(
      'No service account credentials found. Provide one of:\n'
      '  1. Set "credentials_file" in build.yaml under firebase section\n'
      '  2. Set GOOGLE_APPLICATION_CREDENTIALS environment variable\n'
      '  3. Place .firebase-credentials.json in project root',
    );
  }

  /// Get a valid access token, refreshing if needed.
  Future<String> getAccessToken() async {
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return _cachedToken!;
    }

    final jwt = _createSignedJwt();
    final response = await _httpClient.post(
      Uri.parse(credentials.tokenUri),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer'
          '&assertion=$jwt',
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to obtain access token (${response.statusCode}): ${response.body}',
      );
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    _cachedToken = data['access_token'] as String;
    final expiresIn = data['expires_in'] as int;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    return _cachedToken!;
  }

  /// Close the underlying HTTP client.
  void close() {
    _httpClient.close();
  }

  /// Create a signed JWT for the service account assertion grant.
  String _createSignedJwt() {
    final now = DateTime.now().toUtc();
    final expiry = now.add(const Duration(hours: 1));

    final header = {'alg': 'RS256', 'typ': 'JWT'};
    final claims = {
      'iss': credentials.clientEmail,
      'scope': _scope,
      'aud': credentials.tokenUri,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': expiry.millisecondsSinceEpoch ~/ 1000,
    };

    final headerB64 = _base64UrlEncode(json.encode(header));
    final claimsB64 = _base64UrlEncode(json.encode(claims));
    final signingInput = '$headerB64.$claimsB64';

    final signature = _rsaSign(signingInput);
    final signatureB64 = _base64UrlEncodeBytes(signature);

    return '$signingInput.$signatureB64';
  }

  /// Sign data with RSA-SHA256 using the service account private key.
  Uint8List _rsaSign(String data) {
    final privateKey = _parseRsaPrivateKey(credentials.privateKey);

    final signer = RSASigner(Digest('SHA-256'), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    final dataBytes = Uint8List.fromList(utf8.encode(data));
    final signature = signer.generateSignature(dataBytes);

    return signature.bytes;
  }

  /// Parse a PEM-encoded RSA private key into a [RSAPrivateKey].
  RSAPrivateKey _parseRsaPrivateKey(String pem) {
    final lines = pem
        .split('\n')
        .where((line) =>
            line.trim().isNotEmpty &&
            !line.startsWith('-----BEGIN') &&
            !line.startsWith('-----END'))
        .join();

    final keyBytes = base64.decode(lines);
    final asn1Parser = ASN1Parser(Uint8List.fromList(keyBytes));
    final topSequence = asn1Parser.nextObject() as ASN1Sequence;

    // PKCS#8 format: PrivateKeyInfo wrapping RSAPrivateKey
    // We need to unwrap to get the actual RSA key
    final privateKeyOctet = topSequence.elements![2] as ASN1OctetString;
    final pkParser = ASN1Parser(privateKeyOctet.octets!);
    final pkSequence = pkParser.nextObject() as ASN1Sequence;

    final modulus = (pkSequence.elements![1] as ASN1Integer).integer!;
    final privateExponent = (pkSequence.elements![3] as ASN1Integer).integer!;
    final p = (pkSequence.elements![4] as ASN1Integer).integer!;
    final q = (pkSequence.elements![5] as ASN1Integer).integer!;

    return RSAPrivateKey(modulus, privateExponent, p, q);
  }

  static String _base64UrlEncode(String input) {
    return _base64UrlEncodeBytes(utf8.encode(input));
  }

  static String _base64UrlEncodeBytes(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _resolvePath(String filePath, String basePath) {
    if (filePath.startsWith('/') || filePath.startsWith('~')) {
      return filePath;
    }
    return '$basePath/$filePath';
  }
}
