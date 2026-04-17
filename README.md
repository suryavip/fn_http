# fn_http - Simple HTTP Wrapper with Clear Callback Outcomes

[![Pub Version](https://img.shields.io/pub/v/fn_http)](https://pub.dev/packages/fn_http)
[![Pub Likes](https://img.shields.io/pub/likes/fn_http)](https://pub.dev/packages/fn_http)
[![Pub Popularity](https://img.shields.io/pub/popularity/fn_http)](https://pub.dev/packages/fn_http)
[![Dart SDK Version](https://img.shields.io/badge/dart-%3E%3D3.11.4-blue.svg)](https://dart.dev)

A lightweight HTTP wrapper for Dart/Flutter that minimizes boilerplate while providing clear, callback-driven request outcomes including comprehensive error handling.

## Features

- 🚀 **Minimal Boilerplate** - Simple API with sensible defaults
- 🎯 **Clear Outcomes** - Success/failure/retry states via callbacks
- 🔄 **Automatic Retry** - Built-in retry mechanism with custom logic
- 📁 **File Uploads** - Support for File, XFile, and custom MultipartFile
- ⏱️ **Timeout Handling** - Configurable timeouts with callback support
- 🎨 **Request Modification** - Pre-flight checks and request transformation
- 📊 **Response Assessment** - Custom success/failure determination
- 🛡️ **Type Safety** - Full null safety with proper error handling

## Quick Start

### 1. Setup Instance

```dart
import 'package:fn_http/fn_http.dart';

abstract class ApiSetup {
  static late final FnHttpInstance instance;

  static Future<void> init() async {
    instance = FnHttpInstance(
      instanceLogName: 'MyApp',
      defaultAssessor: _defaultAssessor,
      defaultOnFailedConnection: _defaultOnFailedConnection,
      defaultOnFailure: _defaultOnFailure,
    );
  }

  static Future<AssessmentResult> _defaultAssessor(FnHttp fnHttp) async {
    return fnHttp.response?.statusCode == 200 ? AssessmentResult.success : AssessmentResult.failed;
  }

  static Future<void> _defaultOnFailedConnection(FnHttp fnHttp) async {
    print('Network error: Please check your connection');
  }

  static Future<void> _defaultOnFailure(FnHttp fnHttp) async {
    final message = fnHttp.jsonDecodedResponse?['message'] ?? 'Request failed';
    print('Error: $message');
  }
}
```

### 2. Basic Usage

```dart
abstract class AuthApi {
  static FnHttp login(String username, String password) {
    return FnHttp(
      instance: ApiSetup.instance,
      method: 'POST',
      uri: Uri.parse('https://api.example.com/login'),
      bodyFields: {
        'username': username,
        'password': password,
      },
    );
  }
}

// Usage
await AuthApi.login('user@example.com', 'password').send(
  onSuccess: (fnHttp) async {
    final userData = fnHttp.jsonDecodedResponse?['data'];
    // Handle successful login
  },
  onFailure: (fnHttp) async {
    // Handle login failure
  },
);
```

## Advanced Examples

### JSON Request Body

```dart
FnHttp createPost(String title, String content, List<String> tags) {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'POST',
    uri: Uri.parse('https://api.example.com/posts'),
    headers: {'Authorization': 'Bearer $token'},
    bodyJson: {
      'title': title,
      'content': content,
      'tags': tags,
      'published': true,
    },
  );
}
```

### File Upload

```dart
import 'dart:io';
import 'package:cross_file/cross_file.dart';

FnHttp uploadAvatar(File imageFile) {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'POST',
    uri: Uri.parse('https://api.example.com/avatar'),
    files: {
      'avatar': [imageFile],
    },
  );
}

FnHttp uploadDocuments(List<XFile> documents) {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'POST',
    uri: Uri.parse('https://api.example.com/documents'),
    xFiles: {
      'documents': documents,
    },
  );
}
```

### Custom Multipart Files

```dart
import 'package:http/http.dart' as http;

FnHttp uploadWithMetadata(File file, Map<String, String> metadata) {
  final multipartFile = http.MultipartFile.fromBytes(
    'file',
    file.readAsBytesSync(),
    filename: file.path.split('/').last,
  );

  return FnHttp(
    instance: ApiSetup.instance,
    method: 'POST',
    uri: Uri.parse('https://api.example.com/upload'),
    bodyFields: metadata,
    multipartFiles: [multipartFile],
  );
}
```

### Timeout Handling

```dart
FnHttp fetchDataWithTimeout() {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'GET',
    uri: Uri.parse('https://api.example.com/data'),
    timeout: Duration(seconds: 10),
    onTimeout: (fnHttp) async {
      print('Request timed out after 10 seconds');
      // Show timeout UI or retry
    },
  );
}
```

### Request Modification

```dart
FnHttp authenticatedRequest() {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'GET',
    uri: Uri.parse('https://api.example.com/profile'),
    requestModifier: (fnHttp) async {
      // Add authentication token
      fnHttp.injectToHeader({
        'Authorization': 'Bearer ${await getAuthToken()}',
        'X-Client-Version': '1.0.0',
      });

      // Add common parameters
      fnHttp.injectToBody({
        'app_version': '1.0.0',
        'platform': Platform.operatingSystem,
      });
    },
  );
}
```

### Custom Assessment

```dart
FnHttp paymentRequest(double amount) {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'POST',
    uri: Uri.parse('https://api.example.com/pay'),
    bodyJson: {'amount': amount},
    assessor: (fnHttp) async {
      final response = fnHttp.jsonDecodedResponse;
      if (response == null) return AssessmentResult.failed;

      final status = response['status'];
      if (status == 'success') return AssessmentResult.success;
      if (status == 'pending') return AssessmentResult.retry;
      return AssessmentResult.failed;
    },
  );
}
```

### Pre-flight Checks

```dart
FnHttp conditionalRequest() {
  return FnHttp(
    instance: ApiSetup.instance,
    method: 'POST',
    uri: Uri.parse('https://api.example.com/action'),
    preRequest: (fnHttp) async {
      // Check if user is logged in
      if (!await isUserLoggedIn()) {
        return false; // Cancel request
      }

      // Check network connectivity
      if (!await hasInternetConnection()) {
        return false; // Cancel request
      }

      return true; // Proceed with request
    },
    onAborted: (fnHttp) async {
      // Handle cancelled request
      showMessage('Request cancelled - please check your connection');
    },
  );
}
```

### Retry Logic

```dart
// Automatic retry with custom logic
await FnHttp(
  instance: ApiSetup.instance,
  method: 'GET',
  uri: Uri.parse('https://api.example.com/unstable-endpoint'),
  assessor: (fnHttp) async {
    final response = fnHttp.jsonDecodedResponse;
    if (response?['status'] == 'success') {
      return AssessmentResult.success;
    }
    if (fnHttp.response?.statusCode == 503) {
	  await Future.delayed(Duration(seconds: 1)); // Delay before retrying
      return AssessmentResult.retry; // Will trigger auto retry
    }
    return AssessmentResult.failed;
  },
).send(
  onFailure: (fnHttp) async {
    // Manual retry with different parameters
    await fnHttp.retry((fnHttp) {
      fnHttp.injectToBody({'retry_attempt': 'manual'});
    });
  },
);
```

## Best Practices

1. **Use Instance Defaults** - Configure common behavior in `FnHttpInstance`
2. **Handle Timeouts** - Always set appropriate timeouts for your use case
3. **Validate Responses** - Use custom assessors for API response validation
5. **Type Safety** - Use `jsonDecodedResponse` with null checks

## Error Handling

The library provides comprehensive error handling through callbacks:

- **Network Errors**: `onFailedConnection` - Connection failures, DNS issues, etc.
- **Timeouts**: `onTimeout` - Request exceeded timeout duration
- **Response Errors**: `onFailure` - Handle when `assessor` returns `AssessmentResult.failed`
- **JSON Parsing**: Automatic fallback to `null` for invalid JSON