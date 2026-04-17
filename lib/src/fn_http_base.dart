import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fn_http/src/assessment_result.dart';
import 'package:fn_http/src/instance.dart';
import 'package:fn_http/src/typedefs.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

class FnHttp {
  final FnHttpInstance instance;
  final String method;
  final Uri uri;
  late final Map<String, String> headers;
  final Map<String, String>? bodyFields;
  final Map<String, dynamic>? bodyJson;
  final Map<String, List<File>> files;
  final Map<String, List<XFile>> xFiles;
  final List<http.MultipartFile> multipartFiles;

  /// Determine whether the request can be proceeded.
  /// If return false, then this request is canceled and [onAborted] is called.
  /// Will replace [instance.preRequest] if defined.
  final FnHttpPreRequest? preRequest;

  /// Called when [preRequest] return false.
  /// Will replace [instance.defaultOnAborted] if defined.
  final FnHttpCallback? onAborted;

  /// Usually used for calling [injectToBody] and [injectToHeader].
  /// Will replace [instance.defaultRequestModifier] if defined.
  final FnHttpCallback? requestModifier;

  final Duration? timeout;

  /// Called when [timeout] finish first in race againts request.
  /// Will replace [instance.defaultOnTimeout] if defined.
  final FnHttpCallback? onTimeout;

  /// Called when connection failed.
  /// Will replace [instance.defaultOnFailedConnection] if defined.
  final FnHttpCallback? onFailedConnection;

  /// Used to determine whether the request success or not.
  /// Returning true will make the request considered as succeeded.
  /// Will replace [instance.defaultAssessor] if defined.
  /// If neither [assessor] and [instance.defaultAssessor] defined, the request
  /// always be considered as succeeded.
  final FnHttpAssessor? assessor;

  /// Will be called when the result state of the request is determined,
  /// right before each callback of failed connection, success or failure result.
  /// Useful for canceling loading state, for example.
  final FnHttpCallback? onRequestFinish;

  final FnHttpCallback? onSuccess;
  final FnHttpCallback? onFailure;

  late http.BaseRequest request;
  http.StreamedResponse? result;
  http.Response? response;
  Map<String, dynamic>? jsonDecodedResponse;

  /// The order of execution:
  /// 1. [preRequest].
  /// 1. When [preRequest] return false, [onRequestFinish] then [onAborted] are called and send is finished.
  /// 1. [requestModifier].
  /// 2. Insertion of ([bodyFields] and [files]) or [bodyJson]. [request] initialized on this step.
  /// 3. Doing the actual request.
  /// 4. Request will race againts [timeout] if not omited.
  /// 5. When [timeout] won, [onRequestFinish] then [onTimeout].
  /// 6. On failed connection: [onRequestFinish] then [onFailedConnection].
  /// 7. [response] should be available now.
  /// 8. Trying to fill [jsonDecodedResponse].
  /// 9. [assessor].
  /// 10. [onRequestFinish].
  /// 11. [onSuccess] or [onFailure] or calling [retry].
  FnHttp({
    required this.instance,
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    this.bodyFields,
    this.bodyJson,
    this.files = const {},
    this.xFiles = const {},
    this.multipartFiles = const [],
    this.preRequest,
    this.onAborted,
    this.requestModifier,
    this.timeout,
    this.onTimeout,
    this.onFailedConnection,
    this.assessor,
    this.onRequestFinish,
    this.onSuccess,
    this.onFailure,
  }) : headers = headers ?? {} {
    // Validate body configuration: only one of bodyFields or bodyJson can be set
    if (bodyFields != null && bodyJson != null) {
      throw ArgumentError('Cannot specify both bodyFields and bodyJson');
    }

    // Validate body/file configuration: files not allowed with bodyJson
    if (bodyJson != null && (files.isNotEmpty || xFiles.isNotEmpty)) {
      throw ArgumentError('Cannot specify files with bodyJson');
    }
  }

  void _logRequest() {
    instance.sendLog(
      request.headers.toString(),
      '$method $uri (Request Headers)',
    );
    if (request is http.MultipartRequest) {
      instance.sendLog(
        (request as http.MultipartRequest).fields.toString(),
        '$method $uri (Request Body)',
      );
      instance.sendLog(
        (request as http.MultipartRequest).files
            .map((e) => '${e.field}: ${e.filename} (${e.length})')
            .toString(),
        '$method $uri (Request Body Files)',
      );
    }
    if (request is http.Request) {
      instance.sendLog(
        bodyFields != null
            ? (request as http.Request).bodyFields.toString()
            : (request as http.Request).body.toString(),
        '$method $uri (Request Body)',
      );
    }
  }

  void _logResponse() {
    instance.sendLog(
      response?.headers.toString() ?? '<no response headers>',
      '$method $uri (Response Headers)',
    );
    String bodyLog = response?.body.toString() ?? '<no response body>';
    if (bodyLog.length > 64 * 1024) bodyLog = '<${bodyLog.length}B body>';
    instance.sendLog(bodyLog, '$method $uri (Response Body)');
  }

  void _logError(String message) {
    instance.sendLog(message, '$method $uri: error');
  }

  void injectToBody(Map<String, String> additionalBody) {
    if (bodyFields != null) {
      bodyFields!.addAll(additionalBody);
    } else if (bodyJson != null) {
      bodyJson!.addAll(additionalBody);
    }
  }

  void injectToHeader(Map<String, String> additionalHeaders) {
    headers.addAll(additionalHeaders);
  }

  /// Parse MIME type string into MediaType object.
  /// Returns null if mimeType is null or cannot be parsed.
  MediaType? _parseMediaType(String? mimeType) {
    if (mimeType == null) return null;
    final split = mimeType.split('/');
    if (split.length != 2) return null;
    return MediaType(split[0], split[1]);
  }

  /// Execute a callback, preferring local override over instance default.
  /// Returns future that completes when callback finishes, or immediately if none.
  Future<void> _executeCallback(
    FnHttpCallback? localCallback,
    FnHttpCallback? Function() instanceCallbackGetter,
  ) async {
    if (localCallback != null) {
      await localCallback(this);
    } else {
      final instanceCallback = instanceCallbackGetter();
      if (instanceCallback != null) {
        await instanceCallback(this);
      }
    }
  }

  late Duration? _lastTimeout;
  late FnHttpCallback? _lastOnTimeout;
  late FnHttpCallback? _lastOnFailedConnection;
  late FnHttpCallback? _lastOnRequestFinish;
  late FnHttpCallback? _lastOnSuccess;
  late FnHttpCallback? _lastOnFailure;

  Future<void> retry([FnHttpCallback? modifier]) {
    if (modifier != null) modifier(this);
    return send(
      timeout: _lastTimeout,
      onTimeout: _lastOnTimeout,
      onFailedConnection: _lastOnFailedConnection,
      onRequestFinish: _lastOnRequestFinish,
      onSuccess: _lastOnSuccess,
      onFailure: _lastOnFailure,
    );
  }

  Future<void> send({
    Duration? timeout,
    FnHttpCallback? onTimeout,
    FnHttpCallback? onFailedConnection,
    FnHttpCallback? onRequestFinish,
    FnHttpCallback? onSuccess,
    FnHttpCallback? onFailure,
  }) async {
    _lastTimeout = timeout;
    _lastOnTimeout = onTimeout;
    _lastOnFailedConnection = onFailedConnection;
    _lastOnRequestFinish = onRequestFinish;
    _lastOnSuccess = onSuccess;
    _lastOnFailure = onFailure;

    bool preRequestResult = true;
    if (preRequest != null) {
      preRequestResult = await preRequest!(this);
    } else if (instance.defaultPreRequest != null) {
      preRequestResult = await instance.defaultPreRequest!(this);
    }

    if (preRequestResult == false) {
      await _executeCallback(onRequestFinish, () => this.onRequestFinish);
      await _executeCallback(onAborted, () => instance.defaultOnAborted);
      return;
    }

    if (requestModifier != null) {
      await requestModifier!(this);
    } else if (instance.defaultRequestModifier != null) {
      await instance.defaultRequestModifier!(this);
    }

    if (files.isNotEmpty || xFiles.isNotEmpty || multipartFiles.isNotEmpty) {
      request = http.MultipartRequest(method, uri);
      (request as http.MultipartRequest).fields.addAll(bodyFields ?? {});

      // Add files from File entries
      for (final key in files.keys) {
        final filesPerKey = files[key]!;
        for (final file in filesPerKey) {
          final data = await file.readAsBytes();
          final mimeType = lookupMimeType(file.path, headerBytes: data);
          final contentType = _parseMediaType(mimeType);
          (request as http.MultipartRequest).files.add(
            http.MultipartFile.fromBytes(
              key,
              data,
              filename: file.path,
              contentType: contentType,
            ),
          );
        }
      }

      // Add files from XFile entries
      for (final key in xFiles.keys) {
        final filesPerKey = xFiles[key]!;
        for (final file in filesPerKey) {
          final data = await file.readAsBytes();
          final mimeType = lookupMimeType(file.path, headerBytes: data);
          final contentType = _parseMediaType(mimeType);
          (request as http.MultipartRequest).files.add(
            http.MultipartFile.fromBytes(
              key,
              data,
              filename: file.name,
              contentType: contentType,
            ),
          );
        }
      }

      // Add pre-built multipart files
      for (final multipartFile in multipartFiles) {
        (request as http.MultipartRequest).files.add(multipartFile);
      }
    } else {
      request = http.Request(method, uri);
      if (bodyFields != null) {
        (request as http.Request).bodyFields = bodyFields!;
      } else if (bodyJson != null) {
        (request as http.Request).body = jsonEncode(bodyJson);
      }
    }

    request.headers.addAll({
      if (bodyJson != null) 'content-type': 'application/json',
    });
    request.headers.addAll(headers);

    _logRequest();

    try {
      final effectiveTimeout = timeout ?? this.timeout;
      if (effectiveTimeout != null) {
        result = await request.send().timeout(effectiveTimeout);
      } else {
        result = await request.send();
      }
    } on TimeoutException {
      await _executeCallback(onRequestFinish, () => this.onRequestFinish);

      _logError('Timeout');
      await _executeCallback(
        onTimeout,
        () => this.onTimeout ?? instance.defaultOnTimeout,
      );
      return;
    } catch (e) {
      await _executeCallback(onRequestFinish, () => this.onRequestFinish);

      _logError('Failed Connection');
      await _executeCallback(
        onFailedConnection,
        () => this.onFailedConnection ?? instance.defaultOnFailedConnection,
      );
      return;
    }

    response = await http.Response.fromStream(result!);
    _logResponse();

    try {
      jsonDecodedResponse =
          jsonDecode(utf8.decode(response!.bodyBytes)) as Map<String, dynamic>?;
    } catch (e) {
      jsonDecodedResponse = null;
      _logError('Failed JSON Decoding');
    }

    await _executeCallback(onRequestFinish, () => this.onRequestFinish);

    AssessmentResult assessmentResult = AssessmentResult.success;
    if (assessor != null) {
      assessmentResult = await assessor!(this);
    } else if (instance.defaultAssessor != null) {
      assessmentResult = await instance.defaultAssessor!(this);
    }

    if (assessmentResult == AssessmentResult.success) {
      await _executeCallback(onSuccess, () => this.onSuccess);
    } else if (assessmentResult == AssessmentResult.retry) {
      _logError('Retry recommended by assessor');
      await retry();
    } else {
      _logError('Not pass assessor');
      await _executeCallback(
        onFailure,
        () => this.onFailure ?? instance.defaultOnFailure,
      );
    }
  }
}
