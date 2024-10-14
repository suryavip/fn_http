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

  /// Determine whether the request can be proceeded.
  /// If return false, then this request is canceled and [onAborted] is called.
  /// Will replace [instance.preRequest] if defined.
  final FnHttpAssessor? preRequest;

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
  dynamic jsonDecodedResponse;

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
  /// 11. [onSuccess] or [onFailure].
  FnHttp({
    required this.instance,
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    this.bodyFields,
    this.bodyJson,
    this.files = const {},
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
    String bodyLog = response?.body.toString() ?? '<no response body>';
    if (bodyLog.length > 64 * 1024) bodyLog = '<${bodyLog.length}B body>';
    instance.sendLog(
      bodyLog,
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
    Duration? timeout,
    FnHttpCallback? onTimeout,
    FnHttpCallback? onFailedConnection,
    FnHttpCallback? onRequestFinish,
    FnHttpCallback? onSuccess,
    FnHttpCallback? onFailure,
  }) async {
    bool preRequestResult = true;
    if (preRequest != null) {
      preRequestResult = await preRequest!(this);
    } else if (instance.defaultPreRequest != null) {
      preRequestResult = await instance.defaultPreRequest!(this);
    }

    if (preRequestResult == false) {
      if (onRequestFinish != null) {
        await onRequestFinish(this);
      } else if (this.onRequestFinish != null) {
        await this.onRequestFinish!(this);
      }

      if (onAborted != null) {
        await onAborted!(this);
      } else if (instance.defaultOnAborted != null) {
        await instance.defaultOnAborted!(this);
      }
      return;
    }

    if (requestModifier != null) {
      await requestModifier!(this);
    } else if (instance.defaultRequestModifier != null) {
      await instance.defaultRequestModifier!(this);
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
      result = await Future.any([
        request.send(),
        if (timeout != null)
          Future.delayed(timeout)
        else if (this.timeout != null)
          Future.delayed(this.timeout!),
      ]);
      if (result == null) {
        throw 'timeout';
      }
    } catch (e) {
      if (onRequestFinish != null) {
        await onRequestFinish(this);
      } else if (this.onRequestFinish != null) {
        await this.onRequestFinish!(this);
      }

      if (e == 'timeout') {
        _logError('Timeout');
        if (onTimeout != null) {
          await onTimeout(this);
        } else if (this.onTimeout != null) {
          await this.onTimeout!(this);
        } else if (instance.defaultOnTimeout != null) {
          await instance.defaultOnTimeout!(this);
        }
      } else {
        _logError('Failed Connection');
        if (onFailedConnection != null) {
          await onFailedConnection(this);
        } else if (this.onFailedConnection != null) {
          await this.onFailedConnection!(this);
        } else if (instance.defaultOnFailedConnection != null) {
          await instance.defaultOnFailedConnection!(this);
        }
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
