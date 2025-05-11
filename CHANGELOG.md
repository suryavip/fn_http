## 4.0.0

- Dart SDK requirement to `^3.7.0`
- Add `retry()` method for easy retry.
- **BREAKING CHANGE**: now assessor returns `AssessmentResult` instead of `bool`. Returning `AssessmentResult.retry` will automatically call `retry()`.

## 3.3.2

- Can accept `XFile`.

## 3.2.0

- Allow manually add `multipartFiles` when usage of `File` is not possible.

## 3.1.0

- Use `utf8.decode` before `jsonDecode`.

## 3.0.0

- Wait for `defaultRequestModifier` and `requestModifier` to finish.
- Add `defaultPreRequest` and `preRequest` callback.
- Add `defaultOnAborted` and `onAborted` callback.

## 2.2.2

- Update packages
- Add basic documentation on `README.md`

## 1.0.0

- Initial version.
