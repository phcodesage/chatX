# Implementation Plan: File Upload Progress

## Overview

Replace the `http.MultipartRequest` upload in `MediaUploadService.uploadSingleFile` with Dio's multipart upload + `onSendProgress` callback, and add a monotonic progress guard to `MediaUploadState`. The UI layer requires no changes.

## Tasks

- [x] 1. Refactor MediaUploadService.uploadSingleFile to use Dio
  - [x] 1.1 Replace http-based upload with Dio multipart POST
    - Remove `http.MultipartRequest` and `http.Response.fromStream` usage
    - Add `import 'package:dio/dio.dart'`
    - Create Dio instance with `BaseOptions(connectTimeout: timeout, receiveTimeout: timeout, validateStatus: (_) => true)`
    - Build `FormData` with recipient_id, optional caption, and `MultipartFile.fromBytes`
    - Set Authorization header via `Options(headers: {'Authorization': 'Bearer $token'})`
    - Wire `onSendProgress: (sent, total) => onProgress?.call(total > 0 ? sent / total : 0.0)`
    - Parse `response.data` (Dio auto-decodes JSON) instead of `jsonDecode(response.body)`
    - Map `response.statusCode` through existing `_isRetryableStatusCode` logic unchanged
    - Handle `DioException` types: connectionTimeout/receiveTimeout/connectionError → retryable, cancel → non-retryable
    - Keep `_backoff`, `_parseMediaType`, `_isRetryableStatusCode` helpers unchanged
    - Keep `uploadBatch`, `_uploadParallel`, `_uploadSequential` methods unchanged
    - Remove `import 'package:http/http.dart' as http'` if no longer used elsewhere in this file
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 5.4_

  - [ ]* 1.2 Write property tests for upload logic
    - **Property 3: Retry behavior determined by status code**
    - **Property 4: Batch strategy selection**
    - **Validates: Requirements 3.1, 3.2, 3.4**

- [ ] 2. Add monotonic progress guard to MediaUploadState
  - [ ] 2.1 Implement monotonic guard in updateProgress method
    - In `MediaUploadState.updateProgress`, check if incoming `progress.fileProgress` is less than the existing entry's `fileProgress`
    - Allow the update if it's a retry reset (status transitions to retrying/uploading from a different status)
    - Reject (return early without notifying) if progress decreased without a retry reset
    - _Requirements: 4.4_

  - [ ]* 2.2 Write property tests for MediaUploadState
    - **Property 5: Overall progress is average of file progress values**
    - **Property 6: Monotonic progress invariant**
    - **Validates: Requirements 4.3, 4.4**

- [ ] 3. Checkpoint - Verify integration
  - Ensure all tests pass, ask the user if questions arise.
  - Run `flutter analyze` to confirm no lint errors
  - Run `flutter build apk --debug` to confirm compilation succeeds
  - Verify the `http` package import is removed from `media_upload_service.dart` (it may still be needed elsewhere in the project — only remove from this file if unused)

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- The UI layer (`UploadProgressIndicator`) requires zero changes — it already handles intermediate progress values
- Dio is already in `pubspec.yaml` (`dio: ^5.7.0`) — no dependency changes needed
- The `http` and `http_parser` packages may still be used by other services — only remove the import from `media_upload_service.dart`
