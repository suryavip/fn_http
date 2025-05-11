import 'package:fn_http/src/assessment_result.dart';
import 'package:fn_http/src/fn_http_base.dart';

typedef FnHttpCallback = Future<void> Function(FnHttp fnHttp);
typedef FnHttpPreRequest = Future<bool> Function(FnHttp fnHttp);
typedef FnHttpAssessor = Future<AssessmentResult> Function(FnHttp fnHttp);
