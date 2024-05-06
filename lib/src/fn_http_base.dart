import 'dart:convert';
import 'dart:io';

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

  /// Usually used for calling [injectToBody] and [injectToHeader].
  /// Will replace [instance.defaultRequestModifier] if defined.
  final FnHttpCallback? requestModifier;

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
    required this.instance,
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
        (request as http.MultipartRequest)
            .files
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
    instance.sendLog(
      response?.body.toString() ?? '<no response body>',
      '$method $uri (Response Body)',
    );
  }

  void _logError(String message) {
    instance.sendLog(
      message,
      '$method $uri: error',
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
    } else if (instance.defaultRequestModifier != null) {
      instance.defaultRequestModifier!(this);
    }

    if (files.isNotEmpty) {
      request = http.MultipartRequest(method, uri);
      (request as http.MultipartRequest).fields.addAll(bodyFields ?? {});
      for (final key in files.keys) {
        final filesPerKey = files[key]!;
        for (final file in filesPerKey) {
          final data = await file.readAsBytes();
          final mimeType = lookupMimeType(
            file.path,
            headerBytes: data,
          );
          MediaType? contentType;
          if (mimeType != null) {
            final split = mimeType.split('/');
            contentType = MediaType(split[0], split[1]);
          }
          (request as http.MultipartRequest)
              .files
              .add(http.MultipartFile.fromBytes(
                key,
                data,
                filename: file.path,
                contentType: contentType,
              ));
        }
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
      result = await request.send();
    } catch (e) {
      if (onRequestFinish != null) {
        await onRequestFinish(this);
      } else if (this.onRequestFinish != null) {
        await this.onRequestFinish!(this);
      }

      _logError('Failed Connection');
      if (onFailedConnection != null) {
        await onFailedConnection(this);
      } else if (this.onFailedConnection != null) {
        await this.onFailedConnection!(this);
      } else if (instance.defaultOnFailedConnection != null) {
        await instance.defaultOnFailedConnection!(this);
      }
      return;
    }

    response = await http.Response.fromStream(result!);
    _logResponse();

    try {
      jsonDecodedResponse = jsonDecode(response!.body);
    } catch (e) {
      jsonDecodedResponse = {};
      _logError('Failed JSON Decoding');
    }

    if (onRequestFinish != null) {
      await onRequestFinish(this);
    } else if (this.onRequestFinish != null) {
      await this.onRequestFinish!(this);
    }

    bool isSuccess = true;
    if (assessor != null) {
      isSuccess = await assessor!(this);
    } else if (instance.defaultAssessor != null) {
      isSuccess = await instance.defaultAssessor!(this);
    }

    if (isSuccess) {
      if (onSuccess != null) {
        await onSuccess(this);
      } else if (this.onSuccess != null) {
        await this.onSuccess!(this);
      }
    } else {
      _logError('Not pass assessor');
      if (onFailure != null) {
        await onFailure(this);
      } else if (this.onFailure != null) {
        await this.onFailure!(this);
      } else if (instance.defaultOnFailure != null) {
        await instance.defaultOnFailure!(this);
      }
    }
  }
}
