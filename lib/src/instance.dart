import 'dart:developer';

import 'package:fn_http/src/typedefs.dart';

class FnHttpInstance {
  final String instanceLogName;
  final FnHttpPreRequest? defaultPreRequest;
  final FnHttpCallback? defaultOnAborted;
  final FnHttpCallback? defaultRequestModifier;
  final Duration? defaultTimeout;
  final FnHttpCallback? defaultOnTimeout;
  final FnHttpCallback? defaultOnFailedConnection;
  final FnHttpAssessor? defaultAssessor;
  final FnHttpCallback? defaultOnFailure;

  FnHttpInstance({
    required this.instanceLogName,
    this.defaultPreRequest,
    this.defaultOnAborted,
    this.defaultRequestModifier,
    this.defaultTimeout,
    this.defaultOnTimeout,
    this.defaultOnFailedConnection,
    this.defaultAssessor,
    this.defaultOnFailure,
  }) {
    if (instanceLogName.isEmpty || instanceLogName.trim().isEmpty) {
      throw ArgumentError.value(
        instanceLogName,
        'instanceLogName',
        'must not be empty or whitespace',
      );
    }
  }

  void sendLog(String message, [String? additionalName]) {
    log(
      message,
      name: [
        instanceLogName,
        if (additionalName != null) additionalName,
      ].join('::'),
    );
  }
}
