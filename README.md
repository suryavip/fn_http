This is just a wrapper for using http package with purpose of minimum boilerplate per project and clear outcomes (including error handling) directed through callbacks.

Common setup:
``` dart
abstract class FnHttpSetup {
  static late final FnHttpInstance instance;

  static Future<void> init() async {
    instance = const FnHttpInstance(
      instanceLogName: 'Project Name',
      defaultAssessor: _defaultAssessor,
      defaultOnFailedConnection: _defaultOnFailedConnection,
      defaultOnFailure: _defaultOnFailure,
      defaultRequestModifier: _defaultRequestModifier,
    );
  }

  static Future<bool> _defaultAssessor(fnHttp) async =>
  	// check if the response is as expected
      fnHttp.response?.statusCode == 200 &&
      fnHttp.jsonDecodedResponse?['status'] == 'success';

  static Future<void> _defaultOnFailedConnection(fnHttp) async {
	// show the problem to user
    showError(msg: 'Please check your internet connection');
  }

  static Future<void> _defaultOnFailure(fnHttp) async {
    if (fnHttp.jsonDecodedResponse?['message'] != null) {
		// show user the error from 'message' object on response body
      showError(msg: fnHttp.jsonDecodedResponse?['message']);
    } else {
		// show user the error status code
      showUnexpectedError('${fnHttp.response?.statusCode ?? 'UNKNOWN'}');
    }

	// do something else... maybe report to crashlytics
  }

  static Future<void> _defaultRequestModifier(fnHttp) async {
	// inject something common to body, maybe a token
    fnHttp.injectToBody({'token': '........'});

	// inject something common to header, maybe client identifier
    fnHttp.injectToHeader({'client': 'client A'});
  }
```

Common usage:
``` dart
abstract class AuthApi {
  static FnHttp login({
    required String username,
    required String password,
  }) {
    return FnHttp(
      instance: FnHttpSetup.instance,
      method: 'POST',
      uri: 'https://fn.http/login',
      bodyFields: {
        'username': username,
        'password': password,
      },
    );
  }
}

// to call login:
AuthApi.login(
	username: usernameController.text,
	password: passwordController.text,
).send(
	onRequestFinish: (fnHttp) async {
		// handle what to do after request finished, no matter if it's success or failed.
	},
	onSuccess: (fnHttp) async {
		// handle what to do after request declared success by assessor
		final response = fnHttp.jsonDecodedResponse['data'];
		// ...
	},
	onFailure: (fnHttp) async {
		// handle what to do after request declared failed by assessor
		if (fnHttp.jsonDecodedResponse['code'] == 'invalid_username_password') {
			// show invalid password
			return;
		}

		// you can pass through the default handler
		fnHttp.instance.defaultOnFailure!(fnHttp);
	},
);
```