import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:http/http.dart' as http;

typedef FnHttpCallback = void Function(FnHttp fnHttp);
typedef FnHttpAssessor = Future<bool> Function(FnHttp fnHttp);

class FnHttp {
  static FnHttpCallback? defaultRequestModifier;
  static FnHttpCallback? defaultOnFailedConnection;
  static FnHttpAssessor? defaultAssessor;
  static FnHttpCallback? defaultOnFailure;

  final String method;
  final Uri uri;
  late final Map<String, String> headers;
  final Map<String, String>? bodyFields;
  final Map<String, dynamic>? bodyJson;
  final Map<String, File> files;

  /// Usually used for calling [injectToBody] and [injectToHeader].
  /// Will replace [defaultRequestModifier] if defined.
  final FnHttpCallback? requestModifier;

  /// Called when connection failed.
  /// Will replace [defaultOnFailedConnection] if defined.
  final FnHttpCallback? onFailedConnection;

  /// Used to determine whether the request success or not.
  /// Returning true will make the request considered as succeeded.
  /// Will replace [defaultAssessor] if defined.
  /// If neither [assessor] and [defaultAssessor] defined, the request
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
  dynamic jsonDecodedResponse;

  /// The order of execution:
  /// 1. [requestModifier].
  /// 2. Insertion of ([bodyFields] and [files]) or [bodyJson]. [request] initialized on this step.
  /// 3. Doing the actual request.
  /// 4. On failed connection: [onRequestFinish] then [onFailedConnection].
  /// 5. [response] should be available now.
  /// 6. Trying to fill [jsonDecodedResponse].
  /// 7. [assessor].
  /// 8. [onRequestFinish].
  /// 9. [onSuccess] or [onFailure].
  FnHttp({
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    this.bodyFields,
    this.bodyJson,
    this.files = const {},
    this.requestModifier,
    this.onFailedConnection,
    this.assessor,
    this.onRequestFinish,
    this.onSuccess,
    this.onFailure,
  })  : headers = headers ?? {},
        assert((bodyFields == null && bodyJson == null) ||
            (bodyFields != null && bodyJson == null) ||
            (bodyJson != null && bodyFields == null && files.isEmpty));

  void _logRequest() {
    log(
      request.headers.toString(),
      name: '$method $uri (Request Headers)',
    );
    if (request is http.MultipartRequest) {
      log(
        (request as http.MultipartRequest).fields.toString(),
        name: '$method $uri (Request Body)',
      );
      log(
        (request as http.MultipartRequest)
            .files
            .map((e) => '${e.field}: ${e.filename} (${e.length})')
            .toString(),
        name: '$method $uri (Request Body Files)',
      );
    }
    if (request is http.Request) {
      log(
        bodyFields != null
            ? (request as http.Request).bodyFields.toString()
            : (request as http.Request).body.toString(),
        name: '$method $uri (Request Body)',
      );
    }
  }

  void _logResponse() {
    log(
      response?.headers.toString() ?? '<no response headers>',
      name: '$method $uri (Response Headers)',
    );
    log(
      response?.body.toString() ?? '<no response body>',
      name: '$method $uri (Response Body)',
    );
  }

  void _logError(String message) {
    log(
      message,
      name: '$method $uri: error',
    );
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

  Future<void> send({
    FnHttpCallback? onFailedConnection,
    FnHttpCallback? onRequestFinish,
    FnHttpCallback? onSuccess,
    FnHttpCallback? onFailure,
  }) async {
    if (requestModifier != null) {
      requestModifier!(this);
    } else if (defaultRequestModifier != null) {
      defaultRequestModifier!(this);
    }

    if (files.isNotEmpty) {
      request = http.MultipartRequest(method, uri);
      (request as http.MultipartRequest).fields.addAll(bodyFields!);
      for (final key in files.keys) {
        (request as http.MultipartRequest)
            .files
            .add(http.MultipartFile.fromBytes(
              key,
              await files[key]!.readAsBytes(),
              filename: files[key]!.path,
            ));
      }
    } else {
      request = http.Request(method, uri);
      if (bodyFields != null) {
        (request as http.Request).bodyFields = bodyFields!;
      } else {
        (request as http.Request).body = jsonEncode(bodyJson);
      }
    }

    request.headers.addAll({
      if (bodyJson != null) 'content-type': 'application/json',
    });
    request.headers.addAll(headers);

    _logRequest();

    try {
      result = await request.send();
    } catch (e) {
      if (onRequestFinish != null) {
        onRequestFinish(this);
      } else if (this.onRequestFinish != null) {
        this.onRequestFinish!(this);
      }

      _logError('Failed Connection');
      if (onFailedConnection != null) {
        onFailedConnection(this);
      } else if (this.onFailedConnection != null) {
        this.onFailedConnection!(this);
      } else if (defaultOnFailedConnection != null) {
        defaultOnFailedConnection!(this);
      }
      return;
    }

    response = await http.Response.fromStream(result!);
    _logResponse();

    try {
      jsonDecodedResponse = jsonDecode(response!.body);
    } catch (e) {
      _logError('Failed JSON Decoding');
    }

    if (onRequestFinish != null) {
      onRequestFinish(this);
    } else if (this.onRequestFinish != null) {
      this.onRequestFinish!(this);
    }

    bool isSuccess = true;
    if (assessor != null) {
      isSuccess = await assessor!(this);
    } else if (defaultAssessor != null) {
      isSuccess = await defaultAssessor!(this);
    }

    if (isSuccess) {
      if (this.onSuccess != null) this.onSuccess!(this);
    } else {
      _logError('Not pass assessor');
      if (onFailure != null) {
        onFailure(this);
      } else if (this.onFailure != null) {
        this.onFailure!(this);
      } else if (defaultOnFailure != null) {
        defaultOnFailure!(this);
      }
    }
  }
}
