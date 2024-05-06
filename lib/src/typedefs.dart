import 'package:fn_http/src/fn_http_base.dart';

typedef FnHttpCallback = Future<void> Function(FnHttp fnHttp);
typedef FnHttpAssessor = Future<bool> Function(FnHttp fnHttp);
