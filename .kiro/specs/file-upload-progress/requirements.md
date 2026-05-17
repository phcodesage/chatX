# Requirements Document

## Introduction

This feature adds real-time, byte-level upload progress tracking to the 1-on-1 chat file sending flow. Currently, the `MediaUploadService` uses the standard `http` package which only reports 0% and 100% — no intermediate progress. The existing `MediaUploadState` (ChangeNotifier) and `UploadProgressIndicator` widget are already wired to display progress bars, but they never receive values between 0 and 1. This causes the UI to appear frozen during large file uploads. The solution is to replace the upload mechanism with one that streams byte-level progress (using the already-included `dio` package) so users see a smooth, real-time progress bar during file uploads in 1-on-1 chat.

## Glossary

- **Upload_Service**: The `MediaUploadService` class responsible for sending compressed media files to the backend via multipart POST requests.
- **Upload_State**: The `MediaUploadState` ChangeNotifier that tracks per-file upload progress and notifies UI listeners.
- **Progress_Indicator**: The `UploadProgressIndicator` widget that renders progress bars in the chat message list.
- **Dio_Client**: The Dio HTTP client library (already in pubspec.yaml) that provides `onSendProgress` callbacks for byte-level upload tracking.
- **Progress_Callback**: A function invoked by the upload mechanism reporting bytes sent vs total bytes as a fraction (0.0 to 1.0).
- **Byte_Stream_Progress**: Granular upload progress derived from the ratio of bytes transmitted to total file size.
- **Backoff_Strategy**: Exponential delay between retry attempts (1s, 2s, 4s) applied on retryable failures.

## Requirements

### Requirement 1: Byte-Level Upload Progress Reporting

**User Story:** As a user sending files in 1-on-1 chat, I want to see real-time upload progress, so that I know my file is actively being sent and can estimate how long it will take.

#### Acceptance Criteria

1. WHEN the Upload_Service begins transmitting file bytes, THE Upload_Service SHALL report progress as the ratio of bytes sent to total bytes via the Progress_Callback
2. WHILE a file upload is in progress, THE Upload_Service SHALL invoke the Progress_Callback at least once for every 5% of total bytes transmitted
3. WHEN the Upload_Service completes a file upload successfully, THE Upload_Service SHALL report a final progress value of 1.0 via the Progress_Callback
4. WHEN the Upload_Service starts a new upload attempt (including retries), THE Upload_Service SHALL report an initial progress value of 0.0 via the Progress_Callback

### Requirement 2: Dio-Based Upload Mechanism

**User Story:** As a developer, I want the upload service to use Dio's multipart upload with `onSendProgress`, so that byte-level progress is available without custom stream wrappers.

#### Acceptance Criteria

1. THE Upload_Service SHALL use the Dio_Client to perform multipart POST uploads instead of the standard http package MultipartRequest
2. THE Upload_Service SHALL configure the Dio_Client with the same timeout (120 seconds per attempt) as the existing implementation
3. THE Upload_Service SHALL include the Authorization header, recipient_id field, optional caption field, and file attachment in the Dio multipart request
4. THE Upload_Service SHALL parse successful responses (HTTP 200 or 201) into Message objects identical to the current implementation

### Requirement 3: Retry Logic Preservation

**User Story:** As a user, I want failed uploads to automatically retry with the same reliability as before, so that transient network issues do not lose my files.

#### Acceptance Criteria

1. WHEN a retryable error occurs (server 5xx, timeout, or network error), THE Upload_Service SHALL retry up to 3 times using the Backoff_Strategy
2. WHEN a non-retryable error occurs (client 4xx), THE Upload_Service SHALL return a failure result without retrying
3. WHEN a retry attempt begins, THE Upload_Service SHALL reset the reported progress to 0.0 and update the upload status to retrying
4. THE Upload_Service SHALL preserve the existing batch upload strategy (parallel for 5 or fewer files, sequential for more than 5 files)

### Requirement 4: State Management Integration

**User Story:** As a user, I want the progress bar in my chat to update smoothly in real time, so that I have continuous visual feedback during file uploads.

#### Acceptance Criteria

1. WHEN the Upload_Service reports Byte_Stream_Progress, THE Upload_State SHALL update the corresponding file entry and notify listeners
2. WHILE an upload is active, THE Progress_Indicator SHALL display the current progress value as a linear progress bar filling from 0% to 100%
3. WHEN multiple files are uploading, THE Upload_State SHALL track each file independently and compute an overall progress as the average of all active file progress values
4. IF the Upload_State receives a progress value that is less than the previously reported value for the same file (excluding retry resets), THEN THE Upload_State SHALL ignore the stale value and retain the higher progress

### Requirement 5: Error and Edge Case Handling

**User Story:** As a user, I want clear feedback when an upload fails after all retries, so that I know to take action.

#### Acceptance Criteria

1. IF all retry attempts are exhausted, THEN THE Upload_Service SHALL return an UploadResult with success set to false and a descriptive error message
2. IF no authentication token is available, THEN THE Upload_Service SHALL return a failure result immediately without attempting the upload
3. WHEN an upload is cancelled or the screen is disposed, THE Upload_State SHALL stop processing progress updates for that file
4. IF the file size is zero bytes, THEN THE Upload_Service SHALL report progress as 0.0 then 1.0 immediately without intermediate callbacks
