import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/meetings_controller.dart';
import '../controllers/upload_controller.dart';
import '../models/meeting.dart';
import '../services/audio_player_service.dart';
import '../utils/calendar_utils.dart';
import '../widgets/primary_button.dart';

class RecordingDetailScreen extends StatefulWidget {
  final String meetingId;

  const RecordingDetailScreen({super.key, required this.meetingId});

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  final AudioPlayerService _audioPlayer = AudioPlayerService();
  final MeetingsController _meetingsController = Get.find<MeetingsController>();
  final UploadController _uploadController = Get.find<UploadController>();
  
  Meeting? _meeting;
  bool _isPlaying = false;
  bool _isLoading = true;
  StreamSubscription<bool>? _playingSubscription;

  @override
  void initState() {
    super.initState();
    _loadMeeting();
    // Listen to playback state changes
    _playingSubscription = _audioPlayer.playingStream.listen((isPlaying) {
      if (mounted) {
        setState(() => _isPlaying = isPlaying);
      }
    });
  }

  Future<void> _loadMeeting() async {
    await _meetingsController.loadMeetings();
    setState(() {
      _meeting = _meetingsController.meetings.firstWhereOrNull((m) => m.id == widget.meetingId);
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs}s';
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.playMeeting(widget.meetingId);
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _uploadRecording() async {
    final success = await _uploadController.uploadMeeting(widget.meetingId);
    if (success) {
      await _loadMeeting(); // Reload to get the summary
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload successful! Summary generated.')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${_uploadController.status.value}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Recording'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/recordings'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_meeting == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Recording'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/recordings'),
          ),
        ),
        body: const Center(child: Text('Recording not found')),
      );
    }

    final meeting = _meeting!;
    final isUploaded = meeting.status == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Text(meeting.clientName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/recordings'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recording Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isUploaded ? Icons.cloud_done : Icons.cloud_off,
                          color: isUploaded ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isUploaded ? 'Uploaded' : 'Not uploaded',
                          style: TextStyle(
                            color: isUploaded ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Date: ${_formatDate(meeting.date)}'),
                    const SizedBox(height: 4),
                    Text('Duration: ${_formatDuration(meeting.duration)}'),
                    const SizedBox(height: 4),
                    Text('Chunks recorded: ${meeting.totalChunks}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Audio Player Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Audio Recording',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filled(
                          iconSize: 48,
                          onPressed: _togglePlayback,
                          icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_isPlaying ? 'Playing...' : 'Tap to play'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Upload Button (only if not uploaded)
            if (!isUploaded) ...[
              Obx(() {
                final isUploading = _uploadController.isUploading.value;
                final progress = _uploadController.progress.value;

                return Column(
                  children: [
                    if (isUploading) ...[
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 8),
                      Text('Uploading... ${(progress * 100).toInt()}%'),
                      const SizedBox(height: 16),
                    ],
                    PrimaryButton(
                      text: isUploading ? 'Uploading...' : 'Upload & Process',
                      onPressed: isUploading ? null : _uploadRecording,
                    ),
                  ],
                );
              }),
              const SizedBox(height: 24),
            ],

            // Summary Section (only if uploaded)
            if (isUploaded && meeting.summary.isNotEmpty) ...[
              const Text(
                'Meeting Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              ...meeting.summary.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, size: 20, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s)),
                      ],
                    ),
                  )),
              const SizedBox(height: 24),
            ],

            // Action Items (only if uploaded)
            if (isUploaded && meeting.actionItems.isNotEmpty) ...[
              const Text(
                'Action Items',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              ...meeting.actionItems.map((a) => CheckboxListTile(
                    value: a.completed,
                    onChanged: (_) {},
                    title: Text(a.text),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  )),
              const SizedBox(height: 24),
            ],

            // Follow-ups (only if uploaded)
            if (isUploaded && meeting.followUps.isNotEmpty) ...[
              const Text(
                'Follow-ups',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              ...meeting.followUps.map((f) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: Text(f.text),
                      subtitle: Text(f.dueDate ?? 'No date'),
                      trailing: TextButton(
                        onPressed: () => openCalendar(f.dueDate),
                        child: const Text('Add to Calendar'),
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
