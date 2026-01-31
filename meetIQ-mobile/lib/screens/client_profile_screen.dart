import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/client_memory.dart';
import '../models/client_overview.dart';
import '../services/graphql_service.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';
import '../services/user_service.dart';
import '../widgets/voice_note_popup.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final GraphQLService _graphQLService = GraphQLService();
  final StorageService _storageService = StorageService();
  final UploadService _uploadService = UploadService(baseUrl: 'http://192.168.1.73:8004/v2');
  UserService get _userService => Get.find<UserService>();

  UserProfile? _profile;
  ClientMemory? _clientMemory;
  bool _isLoading = true;
  bool _isMemoryLoading = true;
  int _recordingsCount = 0;
  
  // Accordion expansion states
  bool _isOverviewExpanded = true;
  bool _isPendingActionsExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Get user credentials
    final partnerToken = await _userService.getPartnerToken();
    final clientId = await _userService.getCurrentUserId();

    // Load recordings count
    final recordings = await _storageService.listMeetingsMetadata();
    _recordingsCount = recordings.length;

    // Load client memory
    if (clientId != null) {
      _loadClientMemory(clientId);
    }

    if (partnerToken != null && clientId != null && partnerToken.isNotEmpty) {
      // Try to fetch from API
      final profile = await _graphQLService.fetchUserProfile(
        partnerToken: partnerToken,
        clientId: clientId,
      );
      if (profile != null) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
        return;
      }
    }

    // Use demo profile if API fails or no credentials
    setState(() {
      _profile = UserProfile.demo();
      _isLoading = false;
    });
  }

  Future<void> _loadClientMemory(String clientId) async {
    setState(() => _isMemoryLoading = true);
    try {
      final memory = await _uploadService.fetchClientMemory(clientId);
      if (mounted) {
        setState(() {
          _clientMemory = memory;
          _isMemoryLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading client memory: $e');
      if (mounted) {
        setState(() => _isMemoryLoading = false);
      }
    }
  }

  String _formatCurrency(double value) {
    if (value >= 10000000) {
      return '₹${(value / 10000000).toStringAsFixed(2)} Cr';
    } else if (value >= 100000) {
      return '₹${(value / 100000).toStringAsFixed(2)} L';
    } else {
      final formatter = NumberFormat('#,##,###', 'en_IN');
      return '₹${formatter.format(value.toInt())}';
    }
  }

  void _logout() async {
    await _userService.logout();
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Blue header section
                  _buildHeader(),
                  // Content below header
                  Transform.translate(
                    offset: const Offset(0, -40),
                    child: _buildContent(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final profile = _profile!;
    final initial = profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'U';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3A5F), Color(0xFF2D4A6F)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar with logo and logout
          Row(
            children: [
              // Logo
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A6FA5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    'W',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Partner App',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    'admin',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Logout button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                  onPressed: _logout,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Client info
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 32,
                backgroundColor: const Color(0xFF00BFA5),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Name and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            profile.accountType ?? 'Moderate Risk',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Since Jan 2024',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Phone number
          Row(
            children: [
              Icon(Icons.phone, color: Colors.white.withValues(alpha: 0.7), size: 18),
              const SizedBox(width: 8),
              Text(
                profile.phoneNumber ?? '+91 98765 43210',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final profile = _profile!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Portfolio Summary Card
          _buildPortfolioCard(profile),
          const SizedBox(height: 24),

          // Meeting Recorder section
          const Text(
            'Meeting Recorder',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(height: 12),

          // Start Meeting button
          _buildStartMeetingCard(),
          const SizedBox(height: 12),

          // Voice Note and Past Meetings row
          Row(
            children: [
              Expanded(child: _buildQuickActionCard(
                icon: Icons.chat_bubble_outline,
                iconColor: const Color(0xFF00BFA5),
                title: 'Voice Note',
                subtitle: 'Quick note',
                onTap: () async {
                  final saved = await showVoiceNotePopup(context);
                  if (saved && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Voice note saved!'),
                        backgroundColor: Color(0xFF00BFA5),
                      ),
                    );
                    // Refresh recordings count
                    _loadData();
                  }
                },
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildQuickActionCard(
                icon: Icons.history,
                iconColor: const Color(0xFF78909C),
                title: 'Past Meetings',
                subtitle: '$_recordingsCount recorded',
                onTap: () => context.go('/recordings'),
              )),
            ],
          ),
          const SizedBox(height: 12),

          // About Client button - Risk Assessment for meeting preparation
          _buildAboutClientButton(),
          const SizedBox(height: 16),

          // Client Overview card
          _buildClientOverviewCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPortfolioCard(UserProfile profile) {
    final gain = profile.currentValue - profile.investedValue;
    final gainPercent = profile.investedValue > 0
        ? (gain / profile.investedValue * 100)
        : profile.absoluteReturnPercent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Portfolio Summary',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up, color: Color(0xFF00BFA5), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${gainPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00BFA5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Values row
          Row(
            children: [
              // Invested Value
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invested Value',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatCurrency(profile.investedValue),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Current Value
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFA5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Value',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatCurrency(profile.currentValue),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Total Gain row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Gain',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E3A5F),
                  ),
                ),
                Text(
                  '+${_formatCurrency(gain > 0 ? gain : profile.absoluteReturn)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00BFA5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartMeetingCard() {
    return GestureDetector(
      onTap: () => context.go('/record'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E3A5F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.mic_none,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start Meeting',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Record & generate summary',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutClientButton() {
    return GestureDetector(
      onTap: () => _showAboutClientModal(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
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
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.psychology,
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
                    'About Client',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Risk assessment & meeting prep',
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

  Future<void> _showAboutClientModal() async {
    final clientId = await _userService.getCurrentUserId();
    if (clientId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get client ID'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClientOverviewModal(
        uploadService: _uploadService,
        clientId: clientId,
        clientName: _profile?.name ?? 'Client',
      ),
    );
  }

  Widget _buildClientOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Client Overview',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () async {
                  final clientId = await _userService.getCurrentUserId();
                  if (clientId != null) {
                    _loadClientMemory(clientId);
                  }
                },
                child: Row(
                  children: [
                    if (_clientMemory?.lastUpdatedFromMeetingId != null) ...[
                      Text(
                        'Last update: ${_clientMemory!.lastUpdatedFromMeetingId}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      Icons.refresh, 
                      size: 16, 
                      color: _isMemoryLoading ? Colors.grey.shade300 : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content based on API response
          if (_isMemoryLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_clientMemory == null || !_clientMemory!.hasData)
            _buildEmptyMemoryState()
          else
            _buildMemoryContent(),
        ],
      ),
    );
  }

  Widget _buildEmptyMemoryState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'Start conversation to get client overview',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => context.go('/record'),
            icon: const Icon(Icons.mic, size: 18),
            label: const Text('Start Meeting'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryContent() {
    final memory = _clientMemory!;
    final pendingItems = memory.pendingActionItems;
    final hasOverview = memory.clientOverview != null && memory.clientOverview!.isNotEmpty;
    final hasPendingItems = pendingItems.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Client Overview Accordion
        if (hasOverview) ...[
          _buildAccordion(
            title: 'Client Overview',
            icon: Icons.person_outline,
            iconColor: const Color(0xFF1E3A5F),
            isExpanded: _isOverviewExpanded,
            onTap: () => setState(() => _isOverviewExpanded = !_isOverviewExpanded),
            child: Text(
              memory.clientOverview!,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF37474F),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Pending Action Items Accordion
        if (hasPendingItems)
          _buildAccordion(
            title: 'Pending Actions (${pendingItems.length})',
            icon: Icons.checklist,
            iconColor: Colors.amber.shade700,
            isExpanded: _isPendingActionsExpanded,
            onTap: () => setState(() => _isPendingActionsExpanded = !_isPendingActionsExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: pendingItems.map((item) => _buildBulletPoint(item)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildAccordion({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool isExpanded,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E3A5F),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Content
          AnimatedCrossFade(
            firstChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: child,
            ),
            secondChild: const SizedBox(width: double.infinity),
            crossFadeState: isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF00BFA5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF37474F),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal widget to display client overview/risk assessment
class _ClientOverviewModal extends StatefulWidget {
  final UploadService uploadService;
  final String clientId;
  final String clientName;

  const _ClientOverviewModal({
    required this.uploadService,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<_ClientOverviewModal> createState() => _ClientOverviewModalState();
}

class _ClientOverviewModalState extends State<_ClientOverviewModal> {
  ClientOverview? _overview;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchClientOverview();
  }

  Future<void> _fetchClientOverview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final overview = await widget.uploadService.fetchClientOverview(widget.clientId);
      if (mounted) {
        setState(() {
          _overview = overview;
          _isLoading = false;
          if (overview == null) {
            _error = 'Unable to fetch client overview. Please try again.';
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

  Color _getRiskColor(String riskAssessment) {
    final lower = riskAssessment.toLowerCase();
    if (lower.contains('aggressive')) {
      return const Color(0xFFEF4444);
    } else if (lower.contains('moderate')) {
      return const Color(0xFFF59E0B);
    } else if (lower.contains('conservative')) {
      return const Color(0xFF10B981);
    }
    return const Color(0xFF6366F1);
  }

  IconData _getRiskIcon(String riskAssessment) {
    final lower = riskAssessment.toLowerCase();
    if (lower.contains('aggressive')) {
      return Icons.trending_up;
    } else if (lower.contains('moderate')) {
      return Icons.swap_horiz;
    } else if (lower.contains('conservative')) {
      return Icons.shield;
    }
    return Icons.analytics;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.psychology, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About ${widget.clientName}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A5F),
                            ),
                          ),
                          const Text(
                            'Risk Assessment & Meeting Prep',
                            style: TextStyle(
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
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
          const SizedBox(height: 20),
          Text(
            'Analyzing client profile...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This may take a moment',
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
              onPressed: _fetchClientOverview,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
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
    final overview = _overview!;
    final riskColor = _getRiskColor(overview.riskAssessment);
    final riskIcon = _getRiskIcon(overview.riskAssessment);

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Risk Assessment Badge
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: riskColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(riskIcon, color: riskColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Risk Profile',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overview.riskAssessment.split('.').first,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: riskColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Summary Narrative
          _buildSection(
            icon: Icons.person_outline,
            iconColor: const Color(0xFF1E3A5F),
            title: 'Client Summary',
            content: overview.summaryNarrative,
          ),
          const SizedBox(height: 16),

          // Risk Assessment Details
          _buildSection(
            icon: Icons.analytics_outlined,
            iconColor: riskColor,
            title: 'Risk Assessment',
            content: overview.riskAssessment,
          ),
          const SizedBox(height: 16),

          // Pitch Preparation
          _buildSection(
            icon: Icons.lightbulb_outline,
            iconColor: const Color(0xFFF59E0B),
            title: 'Pitch Preparation',
            content: overview.pitchPreparation,
          ),
          const SizedBox(height: 16),

          // Discussion Topics
          if (overview.discussionTopics.isNotEmpty) ...[
            _buildSectionHeader(
              icon: Icons.chat_bubble_outline,
              iconColor: const Color(0xFF00BFA5),
              title: 'Discussion Topics',
            ),
            const SizedBox(height: 12),
            ...overview.discussionTopics.asMap().entries.map((entry) {
              final index = entry.key;
              final topic = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFA5).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00BFA5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        topic,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF37474F),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 24),

          // Last Meeting Date (if available)
          if (overview.lastMeetingDate != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.grey.shade600, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Last Meeting: ${overview.lastMeetingDate}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(icon: icon, iconColor: iconColor, title: title),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF37474F),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E3A5F),
          ),
        ),
      ],
    );
  }
}
