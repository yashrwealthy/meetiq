# MeetIQ Mobile

Flutter mobile app for MeetIQ with offline-first chunk-based recording and upload.

## Flow

1. Record meeting in 5-minute chunks (AAC/M4A)
2. Store chunks offline under /meetiq/{meeting_id}
3. Upload chunks sequentially when online
4. Finalize and view meeting intelligence