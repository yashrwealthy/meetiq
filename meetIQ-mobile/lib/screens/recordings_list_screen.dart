import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/meetings_controller.dart';
import '../models/meeting.dart';
import '../services/graphql_service.dart';
import '../services/user_service.dart';

class RecordingsListScreen extends StatefulWidget {
  const RecordingsListScreen({super.key});

  @override
  State<RecordingsListScreen> createState() => _RecordingsListScreenState();
}

class _RecordingsListScreenState extends State<RecordingsListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '00:${seconds.toString().padLeft(2, '0')}';
    }
    final minutes = seconds ~/ 60;
    return '$minutes min';
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final recordDate = DateTime(date.year, date.month, date.day);

      if (recordDate == today) {
        return 'Today';
      } else if (recordDate == yesterday) {
        return 'Yesterday';
      } else {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${months[date.month - 1]} ${date.day}, ${date.year}';
      }
    } catch (_) {
      return isoDate;
    }
  }

  int _getTotalActionItems(List<Meeting> meetings) {
    return meetings.fold(0, (sum, m) => sum + m.actionItems.length);
  }

  int _getCompletedCount(List<Meeting> meetings) {
    return meetings.where((m) => m.status == 'completed').length;
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MeetingsController>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: FutureBuilder(
        future: controller.loadMeetings(),
        builder: (context, snapshot) {
          return Obx(() {
            final allMeetings = controller.meetings;
            final filteredMeetings = _searchQuery.isEmpty
                ? allMeetings
                : allMeetings.where((m) =>
                    m.clientName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                    m.summary.any((s) => s.toLowerCase().contains(_searchQuery.toLowerCase()))).toList();

            return Column(
              children: [
                // Blue header
                _buildHeader(allMeetings),
                // Content
                Expanded(
                  child: allMeetings.isEmpty
                      ? _buildEmptyState()
                      : _buildRecordingsList(filteredMeetings),
                ),
              ],
            );
          });
        },
      ),
    );
  }

  Widget _buildHeader(List<Meeting> meetings) {
    final clientName = _profile?.name ?? 'Client';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A5F), Color(0xFF2D4A6F)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button and title
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.go('/client'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Meeting Recordings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        clientName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Stats row
              Row(
                children: [
                  _buildStatBox('${meetings.length}', 'Recordings'),
                  const SizedBox(width: 12),
                  _buildStatBox('${_getTotalActionItems(meetings)}', 'Action Items'),
                  const SizedBox(width: 12),
                  _buildStatBox('${_getCompletedCount(meetings)}', 'Completed'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No recordings yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a new recording to get started',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.go('/record'),
            icon: const Icon(Icons.mic),
            label: const Text('New Recording'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsList(List<Meeting> meetings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Search bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search recordings...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Recording cards
        ...meetings.map((meeting) => _buildRecordingCard(meeting)),
      ],
    );
  }

  Widget _buildRecordingCard(Meeting meeting) {
    final isUploaded = meeting.status == 'completed';
    final hasPartialUpload = meeting.uploadedChunks > 0 && meeting.uploadedChunks < meeting.totalChunks;
    final progress = meeting.totalChunks > 0 ? meeting.uploadedChunks / meeting.totalChunks : 0.0;

    // Get first summary line or default text
    String summaryText = 'Recording saved locally';
    if (meeting.summary.isNotEmpty) {
      summaryText = meeting.summary.first;
    }

    return GestureDetector(
      onTap: () => context.go('/recording/${meeting.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isUploaded
                    ? const Color(0xFFE0F7F4)
                    : const Color(0xFFEEF2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isUploaded ? Icons.chat_bubble_outline : Icons.mic_none,
                color: isUploaded
                    ? const Color(0xFF00BFA5)
                    : const Color(0xFF1E3A5F),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date and duration row
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(meeting.date),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDuration(meeting.duration),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.edit_outlined, size: 18, color: Colors.grey.shade400),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Summary text
                  Text(
                    summaryText,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Progress bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              hasPartialUpload || isUploaded
                                  ? const Color(0xFF00BFA5)
                                  : Colors.grey.shade300,
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${meeting.uploadedChunks}/${meeting.totalChunks}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
