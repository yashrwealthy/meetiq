import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/meetings_controller.dart';
import '../controllers/upload_controller.dart';
import '../models/action_item.dart';
import '../models/email_draft.dart';
import '../models/follow_up.dart';
import '../models/meeting.dart';
import '../services/audio_player_service.dart';
import '../services/graphql_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../services/user_service.dart';
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
  final StorageService _storageService = StorageService();
  
  Meeting? _meeting;
  UserProfile? _profile;
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isSaving = false;
  StreamSubscription<bool>? _playingSubscription;
  
  // Edit mode states
  bool _isEditingClientIntent = false;
  bool _isEditingSummary = false;
  bool _isEditingActionItems = false;
  bool _isEditingFollowUps = false;
  
  // Editable data
  String _editedClientIntent = '';
  List<String> _editedSummary = [];
  List<ActionItem> _editedActionItems = [];
  List<FollowUp> _editedFollowUps = [];

  // Colors
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color lightBlue = Color(0xFF3B82F6);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadMeeting();
    _playingSubscription = _audioPlayer.playingStream.listen((isPlaying) {
      if (mounted) {
        setState(() => _isPlaying = isPlaying);
      }
    });
  }

  Future<void> _loadProfile() async {
    final userService = Get.find<UserService>();
    final partnerToken = await userService.getPartnerToken();
    final clientId = await userService.getCurrentUserId();

    if (partnerToken != null && clientId != null && partnerToken.isNotEmpty) {
      final profile = await GraphQLService().fetchUserProfile(
        partnerToken: partnerToken,
        clientId: clientId,
      );
      if (profile != null && mounted) {
        setState(() => _profile = profile);
        return;
      }
    }
    if (mounted) {
      setState(() => _profile = UserProfile.demo());
    }
  }

  Future<void> _loadMeeting() async {
    await _meetingsController.loadMeetings();
    final meeting = _meetingsController.meetings.firstWhereOrNull((m) => m.id == widget.meetingId);
    setState(() {
      _meeting = meeting;
      _isLoading = false;
      
      // Initialize editable data
      if (meeting != null) {
        _editedClientIntent = meeting.clientIntent;
        _editedSummary = List.from(meeting.summary);
        _editedActionItems = meeting.actionItems.map((a) => ActionItem(id: a.id, text: a.text, completed: a.completed)).toList();
        _editedFollowUps = meeting.followUps.map((f) => FollowUp(id: f.id, text: f.text, dueDate: f.dueDate)).toList();
      }
    });
  }

  @override
  void dispose() {
    // Stop polling when user navigates away
    _uploadController.stopPolling();
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
  
  Future<void> _saveClientIntent() async {
    setState(() => _isSaving = true);
    try {
      await _storageService.updateClientIntent(widget.meetingId, _editedClientIntent);
      await _loadMeeting();
      setState(() => _isEditingClientIntent = false);
      _showSuccessSnackBar('Client intent saved');
    } catch (e) {
      _showErrorSnackBar('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }
  
  Future<void> _saveSummary() async {
    setState(() => _isSaving = true);
    try {
      await _storageService.updateMeetingSummary(widget.meetingId, _editedSummary);
      await _loadMeeting();
      setState(() => _isEditingSummary = false);
      _showSuccessSnackBar('Meeting summary saved');
    } catch (e) {
      _showErrorSnackBar('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }
  
  Future<void> _saveActionItems() async {
    setState(() => _isSaving = true);
    try {
      await _storageService.updateActionItems(widget.meetingId, _editedActionItems);
      await _loadMeeting();
      setState(() => _isEditingActionItems = false);
      _showSuccessSnackBar('Action items saved');
    } catch (e) {
      _showErrorSnackBar('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }
  
  Future<void> _saveFollowUps() async {
    setState(() => _isSaving = true);
    try {
      await _storageService.updateFollowUps(widget.meetingId, _editedFollowUps);
      await _loadMeeting();
      setState(() => _isEditingFollowUps = false);
      _showSuccessSnackBar('Follow-ups saved');
    } catch (e) {
      _showErrorSnackBar('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }
  
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
  
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: errorRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
                          meeting.clientName.isEmpty || meeting.clientName == 'Client' 
                              ? (_profile?.name ?? 'Default Client')
                              : meeting.clientName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.tag, color: Colors.white.withAlpha(179), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              meeting.id,
                              style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 12),
                            ),
                          ],
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

                // Upload Section (if not uploaded and not processing)
                if (!isUploaded && meeting.status != 'processing') ...[
                  _buildUploadCard(meeting),
                  const SizedBox(height: 16),
                ],
                
                // Processing Section (if processing)
                if (meeting.status == 'processing') ...[
                  _buildProcessingCard(meeting),
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
                  const SizedBox(height: 16),

                  // Email Draft Button
                  _buildEmailDraftButton(meeting),
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
    final isProcessing = meeting.status == 'processing';
    
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;
    
    if (isUploaded) {
      badgeColor = successGreen;
      badgeIcon = Icons.cloud_done;
      badgeText = 'Processed & Ready';
    } else if (isProcessing) {
      badgeColor = lightBlue;
      badgeIcon = Icons.hourglass_top;
      badgeText = 'Processing...';
    } else {
      badgeColor = warningOrange;
      badgeIcon = Icons.cloud_off;
      badgeText = 'Pending Upload';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: badgeColor.withAlpha(51),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badgeIcon,
            size: 18,
            color: badgeColor,
          ),
          const SizedBox(width: 8),
          Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
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

  Widget _buildUploadCard(Meeting meeting) {
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
  
  Widget _buildProcessingCard(Meeting meeting) {
    return Obx(() {
      final isCheckingStatus = _uploadController.isCheckingStatus.value;
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
                  child: const Icon(Icons.hourglass_top, color: lightBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Processing Status',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isCheckingStatus || isProcessing) ...[
              // Progress indicator
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(lightBlue),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(lightBlue),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusMsg.isNotEmpty ? statusMsg : 'Checking status...',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                  if (progress > 0)
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
              Text(
                'Your recording was uploaded and is being processed by our AI. Tap the button below to check if processing is complete.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: 'Check Processing Status',
                  onPressed: () => _checkStatus(meeting),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
  
  Future<void> _checkStatus(Meeting meeting) async {
    final jobId = meeting.jobId;
    if (jobId == null || jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('No job ID found for this recording'),
            ],
          ),
          backgroundColor: errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final success = await _uploadController.checkMeetingStatus(widget.meetingId, jobId);
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
      if (mounted && _uploadController.status.value == 'failed') {
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
    if (_isEditingClientIntent) {
      return _buildEditableCard(
        icon: Icons.psychology,
        iconColor: const Color(0xFF8B5CF6),
        title: 'Client Intent',
        onSave: _saveClientIntent,
        onCancel: () {
          setState(() {
            _editedClientIntent = meeting.clientIntent;
            _isEditingClientIntent = false;
          });
        },
        child: TextField(
          controller: TextEditingController(text: _editedClientIntent),
          onChanged: (value) => _editedClientIntent = value,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Enter client intent...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
      );
    }
    
    return _buildSectionCard(
      icon: Icons.psychology,
      iconColor: const Color(0xFF8B5CF6),
      title: 'Client Intent',
      onEdit: () => setState(() => _isEditingClientIntent = true),
      child: Text(
        meeting.clientIntent,
        style: const TextStyle(fontSize: 15, height: 1.5),
      ),
    );
  }

  Widget _buildSummaryCard(Meeting meeting) {
    if (_isEditingSummary) {
      return _buildEditableCard(
        icon: Icons.summarize,
        iconColor: lightBlue,
        title: 'Meeting Summary',
        onSave: _saveSummary,
        onCancel: () {
          setState(() {
            _editedSummary = List.from(meeting.summary);
            _isEditingSummary = false;
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...List.generate(_editedSummary.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: lightBlue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _editedSummary[index]),
                        onChanged: (value) => _editedSummary[index] = value,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Summary point...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: lightBlue),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.remove_circle, color: errorRed, size: 20),
                      onPressed: () {
                        setState(() {
                          _editedSummary.removeAt(index);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _editedSummary.add('');
                });
              },
              icon: const Icon(Icons.add_circle, size: 18),
              label: const Text('Add point'),
              style: TextButton.styleFrom(foregroundColor: lightBlue),
            ),
          ],
        ),
      );
    }
    
    return _buildSectionCard(
      icon: Icons.summarize,
      iconColor: lightBlue,
      title: 'Meeting Summary',
      onEdit: () => setState(() => _isEditingSummary = true),
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
    if (_isEditingActionItems) {
      return _buildEditableCard(
        icon: Icons.checklist,
        iconColor: warningOrange,
        title: 'Action Items',
        onSave: _saveActionItems,
        onCancel: () {
          setState(() {
            _editedActionItems = meeting.actionItems.map((a) => ActionItem(id: a.id, text: a.text, completed: a.completed)).toList();
            _isEditingActionItems = false;
          });
        },
        child: Column(
          children: [
            ...List.generate(_editedActionItems.length, (index) {
              final item = _editedActionItems[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: item.completed,
                      onChanged: (value) {
                        setState(() {
                          _editedActionItems[index] = ActionItem(
                            id: item.id,
                            text: item.text,
                            completed: value ?? false,
                          );
                        });
                      },
                      activeColor: successGreen,
                    ),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: item.text),
                        onChanged: (value) {
                          _editedActionItems[index] = ActionItem(
                            id: item.id,
                            text: value,
                            completed: item.completed,
                          );
                        },
                        decoration: InputDecoration(
                          hintText: 'Action item...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: warningOrange),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.remove_circle, color: errorRed, size: 20),
                      onPressed: () {
                        setState(() {
                          _editedActionItems.removeAt(index);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _editedActionItems.add(ActionItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    text: '',
                    completed: false,
                  ));
                });
              },
              icon: const Icon(Icons.add_circle, size: 18),
              label: const Text('Add action item'),
              style: TextButton.styleFrom(foregroundColor: warningOrange),
            ),
          ],
        ),
      );
    }
    
    return _buildSectionCard(
      icon: Icons.checklist,
      iconColor: warningOrange,
      title: 'Action Items',
      onEdit: () => setState(() => _isEditingActionItems = true),
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
    if (_isEditingFollowUps) {
      return _buildEditableCard(
        icon: Icons.event,
        iconColor: const Color(0xFFEC4899),
        title: 'Follow-up Items',
        onSave: _saveFollowUps,
        onCancel: () {
          setState(() {
            _editedFollowUps = meeting.followUps.map((f) => FollowUp(id: f.id, text: f.text, dueDate: f.dueDate)).toList();
            _isEditingFollowUps = false;
          });
        },
        child: Column(
          children: [
            ...List.generate(_editedFollowUps.length, (index) {
              final followUp = _editedFollowUps[index];
              final dueDate = followUp.dueDate != null ? DateTime.tryParse(followUp.dueDate!) : null;
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
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(text: followUp.text),
                            onChanged: (value) {
                              _editedFollowUps[index] = FollowUp(
                                id: followUp.id,
                                text: value,
                                dueDate: followUp.dueDate,
                              );
                            },
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: 'Follow-up item...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFEC4899)),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.remove_circle, color: errorRed, size: 20),
                          onPressed: () {
                            setState(() {
                              _editedFollowUps.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: Color(0xFFEC4899)),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            final selectedDate = await showDatePicker(
                              context: context,
                              initialDate: dueDate ?? DateTime.now().add(const Duration(days: 1)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (selectedDate != null) {
                              setState(() {
                                _editedFollowUps[index] = FollowUp(
                                  id: followUp.id,
                                  text: followUp.text,
                                  dueDate: selectedDate.toIso8601String(),
                                );
                              });
                            }
                          },
                          child: Text(
                            dueDate != null
                                ? '${dueDate.day}/${dueDate.month}/${dueDate.year}'
                                : 'Set due date',
                            style: const TextStyle(color: Color(0xFFEC4899)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _editedFollowUps.add(FollowUp(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    text: '',
                    dueDate: DateTime.now().add(const Duration(days: 1)).toIso8601String(),
                  ));
                });
              },
              icon: const Icon(Icons.add_circle, size: 18),
              label: const Text('Add follow-up'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFEC4899)),
            ),
          ],
        ),
      );
    }
    
    return _buildSectionCard(
      icon: Icons.event,
      iconColor: const Color(0xFFEC4899),
      title: 'Follow-up Items',
      onEdit: () => setState(() => _isEditingFollowUps = true),
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
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEC4899).withAlpha(26),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.flag_outlined, size: 18, color: Color(0xFFEC4899)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    followUp.text,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => openCalendarWithFollowUp(followUp.text, date: followUp.dueDate),
                  icon: const Icon(Icons.calendar_today, size: 14),
                  label: const Text('Add to Calendar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEC4899),
                    side: const BorderSide(color: Color(0xFFEC4899)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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
    VoidCallback? onEdit,
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit, color: iconColor, size: 20),
                  tooltip: 'Edit $title',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
  
  Widget _buildEditableCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
    required VoidCallback onSave,
    required VoidCallback onCancel,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withAlpha(128), width: 2),
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Editing',
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : onSave,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: iconColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmailDraftButton(Meeting meeting) {
    return GestureDetector(
      onTap: () => _showEmailDraftModal(meeting),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF059669), Color(0xFF10B981)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withAlpha(77),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(51),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.mail_outline,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prepare Email Draft',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'AI-generated follow-up email',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white70,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  void _showEmailDraftModal(Meeting meeting) {
    final jobId = meeting.jobId;
    if (jobId == null || jobId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('No job ID found for this meeting'),
            ],
          ),
          backgroundColor: errorRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // Get the client name from the meeting or profile
    final clientName = meeting.clientName.isEmpty || meeting.clientName == 'Client'
        ? (_profile?.name ?? 'Client')
        : meeting.clientName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EmailDraftModal(
        jobId: jobId,
        clientName: clientName,
      ),
    );
  }
}

/// Modal widget to display and manage email draft
class _EmailDraftModal extends StatefulWidget {
  final String jobId;
  final String clientName;

  const _EmailDraftModal({
    required this.jobId,
    required this.clientName,
  });

  @override
  State<_EmailDraftModal> createState() => _EmailDraftModalState();
}

class _EmailDraftModalState extends State<_EmailDraftModal> {
  final UploadService _uploadService = UploadService(baseUrl: 'http://192.168.1.73:8004/v2');
  
  EmailDraft? _emailDraft;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateEmailDraft();
  }

  Future<void> _generateEmailDraft() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final draft = await _uploadService.generateEmailDraft(
        jobId: widget.jobId,
        clientName: widget.clientName,
        partnerName: 'Wealthy-Partner',
      );
      
      if (mounted) {
        setState(() {
          _emailDraft = draft;
          _isLoading = false;
          if (draft == null) {
            _error = 'Unable to generate email draft. Please try again.';
          } else if (!draft.isSuccess) {
            _error = draft.error ?? 'Failed to generate email draft.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  Future<void> _sendEmail() async {
    if (_emailDraft == null || !_emailDraft!.isSuccess) return;
    
    final subject = Uri.encodeComponent(_emailDraft!.subject ?? '');
    final body = Uri.encodeComponent(_emailDraft!.body ?? '');
    final mailtoUrl = Uri.parse('mailto:?subject=$subject&body=$body');
    
    try {
      if (await canLaunchUrl(mailtoUrl)) {
        await launchUrl(mailtoUrl);
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        // Fallback: copy to clipboard if email client not available
        _copyToClipboard();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('No email app found. Email copied to clipboard!')),
                ],
              ),
              backgroundColor: const Color(0xFFF59E0B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      // Error handling - copy to clipboard as fallback
      _copyToClipboard();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Could not open email app. Copied to clipboard!')),
              ],
            ),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _copyToClipboard() {
    if (_emailDraft == null || !_emailDraft!.isSuccess) return;
    
    final text = 'Subject: ${_emailDraft!.subject}\n\n${_emailDraft!.body}';
    Clipboard.setData(ClipboardData(text: text));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.copy, color: Colors.white),
            SizedBox(width: 8),
            Text('Email copied to clipboard'),
          ],
        ),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.mail_outline, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email Draft',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A5F),
                            ),
                          ),
                          Text(
                            'For ${widget.clientName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Content
              Expanded(
                child: _isLoading
                    ? _buildLoadingState()
                    : _error != null
                        ? _buildErrorState()
                        : _buildContent(scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
          ),
          const SizedBox(height: 20),
          Text(
            'Generating email draft...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a few seconds',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generateEmailDraft,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    final draft = _emailDraft!;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tone Badge
                if (draft.tone != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withAlpha(26),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.style,
                          size: 16,
                          color: const Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tone: ${draft.tone!.substring(0, 1).toUpperCase()}${draft.tone!.substring(1)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Subject
                _buildEmailSection(
                  icon: Icons.subject,
                  iconColor: const Color(0xFF1E3A5F),
                  title: 'Subject',
                  content: draft.subject ?? '',
                  isSubject: true,
                ),
                const SizedBox(height: 16),

                // Body
                _buildEmailSection(
                  icon: Icons.article_outlined,
                  iconColor: const Color(0xFF059669),
                  title: 'Body',
                  content: draft.body ?? '',
                ),
                const SizedBox(height: 16),

                // Suggested Attachments
                if (draft.suggestedAttachments.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(26),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.attach_file, color: Color(0xFFF59E0B), size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Suggested Attachments',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A5F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...draft.suggestedAttachments.map((attachment) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  attachment,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Bottom Action Buttons
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E3A5F),
                    side: const BorderSide(color: Color(0xFF1E3A5F)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _sendEmail,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Send Email'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    bool isSubject = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 8,
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: isSubject ? 16 : 14,
              fontWeight: isSubject ? FontWeight.w600 : FontWeight.normal,
              color: const Color(0xFF37474F),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
