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

  // Colors
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color lightBlue = Color(0xFF3B82F6);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _loadMeeting();
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
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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
      await _loadMeeting();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Processing complete!'),
              ],
            ),
            backgroundColor: successGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(_uploadController.statusMessage.value)),
              ],
            ),
            backgroundColor: errorRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: _buildAppBar('Recording'),
        body: const Center(child: CircularProgressIndicator(color: primaryBlue)),
      );
    }

    if (_meeting == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: _buildAppBar('Recording'),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text('Recording not found', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final meeting = _meeting!;
    final isUploaded = meeting.status == 'completed';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: CustomScrollView(
        slivers: [
          // Custom App Bar with gradient
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.go('/recordings'),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [primaryBlue, lightBlue],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 16, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          meeting.clientName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, color: Colors.white.withAlpha(179), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(meeting.date),
                              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 14),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.timer_outlined, color: Colors.white.withAlpha(179), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(meeting.duration),
                              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 14),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Status Badge
                _buildStatusBadge(meeting),
                const SizedBox(height: 16),

                // Audio Player Card
                _buildAudioPlayerCard(),
                const SizedBox(height: 16),

                // Upload Section (if not uploaded)
                if (!isUploaded) ...[
                  _buildUploadCard(),
                  const SizedBox(height: 16),
                ],

                // Financial Meeting Badge (if uploaded)
                if (isUploaded) ...[
                  _buildFinancialMeetingBadge(meeting),
                  const SizedBox(height: 16),

                  // Financial Products (if any)
                  if (meeting.financialProducts.isNotEmpty) ...[
                    _buildFinancialProductsCard(meeting),
                    const SizedBox(height: 16),
                  ],

                  // Client Intent
                  if (meeting.clientIntent.isNotEmpty) ...[
                    _buildClientIntentCard(meeting),
                    const SizedBox(height: 16),
                  ],

                  // Meeting Summary
                  if (meeting.summary.isNotEmpty) ...[
                    _buildSummaryCard(meeting),
                    const SizedBox(height: 16),
                  ],

                  // Action Items
                  if (meeting.actionItems.isNotEmpty) ...[
                    _buildActionItemsCard(meeting),
                    const SizedBox(height: 16),
                  ],

                  // Follow-ups
                  if (meeting.followUps.isNotEmpty) ...[
                    _buildFollowUpsCard(meeting),
                    const SizedBox(height: 16),
                  ],

                  // Confidence Level
                  _buildConfidenceCard(meeting),
                ],

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String title) {
    return AppBar(
      backgroundColor: primaryBlue,
      foregroundColor: Colors.white,
      title: Text(title),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/recordings'),
      ),
    );
  }

  Widget _buildStatusBadge(Meeting meeting) {
    final isUploaded = meeting.status == 'completed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isUploaded ? successGreen.withAlpha(26) : warningOrange.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUploaded ? successGreen.withAlpha(51) : warningOrange.withAlpha(51),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUploaded ? Icons.cloud_done : Icons.cloud_off,
            size: 18,
            color: isUploaded ? successGreen : warningOrange,
          ),
          const SizedBox(width: 8),
          Text(
            isUploaded ? 'Processed & Ready' : 'Pending Upload',
            style: TextStyle(
              color: isUploaded ? successGreen : warningOrange,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            '${meeting.totalChunks} chunks',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryBlue.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.headphones, color: primaryBlue, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audio Recording',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Tap play to listen to the recording',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryBlue, lightBlue],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: primaryBlue.withAlpha(77),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isPlaying ? Icons.stop : Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          if (_isPlaying) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                20,
                (i) => Container(
                  width: 3,
                  height: 8 + (i % 4) * 8.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: lightBlue.withAlpha(179),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return Obx(() {
      final isUploading = _uploadController.isUploading.value;
      final isProcessing = _uploadController.isProcessing.value;
      final progress = _uploadController.progress.value;
      final statusMsg = _uploadController.statusMessage.value;

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: lightBlue.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_upload, color: lightBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Upload & Process',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isUploading || isProcessing) ...[
              // Progress indicator
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isProcessing ? successGreen : lightBlue,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (isProcessing)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(successGreen),
                      ),
                    ),
                  if (isProcessing) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusMsg,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const Text(
                'Upload your recording to get AI-powered insights including meeting summary, action items, and financial product recommendations.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: 'Upload & Process',
                  onPressed: _uploadRecording,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildFinancialMeetingBadge(Meeting meeting) {
    final isFinancial = meeting.isFinancialMeeting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isFinancial ? primaryBlue.withAlpha(26) : Colors.grey.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFinancial ? primaryBlue.withAlpha(51) : Colors.grey.withAlpha(51),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFinancial ? Icons.account_balance : Icons.chat_bubble_outline,
            color: isFinancial ? primaryBlue : Colors.grey[600],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFinancial ? 'Financial Meeting' : 'General Meeting',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isFinancial ? primaryBlue : Colors.grey[700],
                    fontSize: 16,
                  ),
                ),
                Text(
                  isFinancial
                      ? 'This meeting discussed financial products or services'
                      : 'No specific financial topics detected',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialProductsCard(Meeting meeting) {
    return _buildSectionCard(
      icon: Icons.trending_up,
      iconColor: successGreen,
      title: 'Financial Products Discussed',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: meeting.financialProducts.map((product) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryBlue.withAlpha(26), lightBlue.withAlpha(26)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primaryBlue.withAlpha(51)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on, size: 16, color: primaryBlue),
                const SizedBox(width: 6),
                Text(
                  product,
                  style: const TextStyle(
                    color: primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildClientIntentCard(Meeting meeting) {
    return _buildSectionCard(
      icon: Icons.psychology,
      iconColor: const Color(0xFF8B5CF6),
      title: 'Client Intent',
      child: Text(
        meeting.clientIntent,
        style: const TextStyle(fontSize: 15, height: 1.5),
      ),
    );
  }

  Widget _buildSummaryCard(Meeting meeting) {
    return _buildSectionCard(
      icon: Icons.summarize,
      iconColor: lightBlue,
      title: 'Meeting Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: meeting.summary.map((point) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: lightBlue,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(point, style: const TextStyle(fontSize: 15, height: 1.4)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionItemsCard(Meeting meeting) {
    return _buildSectionCard(
      icon: Icons.checklist,
      iconColor: warningOrange,
      title: 'Action Items',
      child: Column(
        children: meeting.actionItems.map((item) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: item.completed ? successGreen.withAlpha(26) : warningOrange.withAlpha(26),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    item.completed ? Icons.check : Icons.radio_button_unchecked,
                    size: 16,
                    color: item.completed ? successGreen : warningOrange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.text,
                    style: TextStyle(
                      fontSize: 14,
                      decoration: item.completed ? TextDecoration.lineThrough : null,
                      color: item.completed ? Colors.grey : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFollowUpsCard(Meeting meeting) {
    return _buildSectionCard(
      icon: Icons.event,
      iconColor: const Color(0xFFEC4899),
      title: 'Follow-up Reminders',
      child: Column(
        children: meeting.followUps.map((followUp) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFFEC4899).withAlpha(13), const Color(0xFFEC4899).withAlpha(26)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEC4899).withAlpha(51)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 20, color: Color(0xFFEC4899)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        followUp.text,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (followUp.dueDate != null)
                        Text(
                          followUp.dueDate!,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => openCalendar(followUp.dueDate),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEC4899),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildConfidenceCard(Meeting meeting) {
    final confidence = meeting.confidenceLevel;
    final Color confidenceColor;
    final String confidenceLabel;
    
    if (confidence >= 0.8) {
      confidenceColor = successGreen;
      confidenceLabel = 'High Confidence';
    } else if (confidence >= 0.5) {
      confidenceColor = warningOrange;
      confidenceLabel = 'Medium Confidence';
    } else {
      confidenceColor = errorRed;
      confidenceLabel = 'Low Confidence';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: confidenceColor.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.analytics, color: confidenceColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analysis Confidence',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  confidenceLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: confidenceColor,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${(confidence * 100).toInt()}%',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: confidenceColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
