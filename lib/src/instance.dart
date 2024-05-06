import 'dart:developer';

import 'package:fn_http/src/typedefs.dart';

class FnHttpInstance {
  final String instanceLogName;
  final FnHttpCallback? defaultRequestModifier;
  final FnHttpCallback? defaultOnFailedConnection;
  final FnHttpAssessor? defaultAssessor;
  final FnHttpCallback? defaultOnFailure;

  const FnHttpInstance({
    required this.instanceLogName,
    this.defaultRequestModifier,
    this.defaultOnFailedConnection,
    this.defaultAssessor,
    this.defaultOnFailure,
  });

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
