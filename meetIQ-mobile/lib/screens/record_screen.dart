import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/recording_controller.dart';
import '../services/alert_sound_service.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> with TickerProviderStateMixin {
  late AnimationController _waveController;
  final List<double> _waveHeights = [];
  Timer? _waveTimer;
  Timer? _silenceCheckTimer;
  bool _muteDialogShown = false;
  bool _silenceDialogShown = false;
  final AlertSoundService _alertSoundService = AlertSoundService();

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    // Initialize wave heights
    for (int i = 0; i < 20; i++) {
      _waveHeights.add(0.3 + Random().nextDouble() * 0.4);
    }
    // Initialize alert sound service
    _alertSoundService.init();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _waveTimer?.cancel();
    _silenceCheckTimer?.cancel();
    super.dispose();
  }

  void _startWaveAnimation() {
    _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        final controller = Get.find<RecordingController>();
        setState(() {
          // When paused or muted, show flat lines
          if (controller.isPaused.value || controller.isMuted.value) {
            for (int i = 0; i < _waveHeights.length; i++) {
              _waveHeights[i] = 0.1;
            }
          } else {
            for (int i = 0; i < _waveHeights.length; i++) {
              _waveHeights[i] = 0.2 + Random().nextDouble() * 0.6;
            }
          }
        });
      }
    });
    
    // Start silence detection timer
    _startSilenceDetection();
  }

  void _stopWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = null;
    _silenceCheckTimer?.cancel();
    _silenceCheckTimer = null;
  }

  void _startSilenceDetection() {
    _silenceCheckTimer?.cancel();
    _silenceCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final controller = Get.find<RecordingController>();
      
      // Check if we should show the mute warning (muted for 10+ seconds)
      if (controller.shouldShowMuteWarning && !_muteDialogShown) {
        _muteDialogShown = true;
        _showMuteWarningDialog(controller);
      }
      // Check if we should show the silence warning (NOT muted but no audio for 10+ seconds)
      else if (controller.shouldShowSilenceWarning && !_silenceDialogShown) {
        _silenceDialogShown = true;
        _showSilenceWarningDialog(controller);
      }
    });
  }

  /// Play alert sound using AlertSoundService
  Future<void> _playAlertSound() async {
    // Use haptic feedback
    HapticFeedback.heavyImpact();
    // Play audio alert
    await _alertSoundService.playAlert();
  }

  /// Show dialog when microphone is muted for too long
  Future<void> _showMuteWarningDialog(RecordingController controller) async {
    await _playAlertSound();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.mic_off,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'Microphone is Muted',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                'Your microphone has been muted for over 10 seconds. Are you sure you want to continue recording with mute on?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        controller.toggleMute();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.mic),
                      label: const Text('Unmute'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        controller.acknowledgeMuteWarning();
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Keep Muted',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    // Reset the dialog flag after dismissal
    _muteDialogShown = false;
  }

  /// Show dialog when no audio is detected (silence)
  Future<void> _showSilenceWarningDialog(RecordingController controller) async {
    await _playAlertSound();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.volume_off,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'No Audio Detected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                'We haven\'t detected any audio for over 10 seconds. Is anyone speaking?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        controller.acknowledgeSilenceWarning();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continue Recording'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        controller.acknowledgeSilenceWarning();
                        await controller.pauseRecording();
                        if (mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause Recording'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF9800),
                        side: const BorderSide(color: Color(0xFFFF9800)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    // Reset the dialog flag after dismissal
    _silenceDialogShown = false;
  }

  Future<void> _showConsentDialog(BuildContext context, RecordingController controller) async {
    final consent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shield icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFA5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              // Title
              const Text(
                'Client Consent Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F),
                ),
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                'Please inform your client that this meeting is being recorded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              // Quote box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '"This meeting is being recorded for notes & follow-ups. Is that okay?"',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF37474F),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Client Agreed',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (consent != true) return;

    final ok = await controller.startRecording('Client');
    if (ok) {
      _startWaveAnimation();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
    }
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<RecordingController>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E3A5F)),
          onPressed: () => context.go('/client'),
        ),
        title: Obx(() => Text(
              controller.isRecording.value ? 'Recording...' : 'Record Meeting',
              style: const TextStyle(
                color: Color(0xFF1E3A5F),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            )),
        centerTitle: false,
      ),
      body: Obx(() {
        if (controller.isRecording.value) {
          return _buildRecordingView(controller);
        }
        return _buildIdleView(controller);
      }),
    );
  }

  Widget _buildIdleView(RecordingController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mic button
          GestureDetector(
            onTap: () => _showConsentDialog(context, controller),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic_none,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Title
          const Text(
            'Tap to Start Recording',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(height: 8),
          // Subtitle
          Text(
            "We'll ask for client consent first",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingView(RecordingController controller) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Waveform
          SizedBox(
            height: 60,
            child: Obx(() {
              final isPaused = controller.isPaused.value;
              final isMuted = controller.isMuted.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _waveHeights.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: 4,
                    height: 60 * _waveHeights[index],
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isPaused 
                          ? Colors.grey.shade400 
                          : isMuted 
                              ? Colors.orange.shade300 
                              : const Color(0xFFFF6B6B),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 32),
          // Timer
          Obx(() => Text(
                _formatTime(controller.elapsedSeconds.value),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w300,
                  color: controller.isPaused.value 
                      ? Colors.grey.shade500 
                      : const Color(0xFFFF6B6B),
                  letterSpacing: 4,
                ),
              )),
          const SizedBox(height: 8),
          // Status
          Obx(() {
            String statusText = 'Recording in progress';
            Color statusColor = Colors.grey.shade500;
            
            if (controller.isPaused.value) {
              statusText = 'Recording paused';
              statusColor = Colors.orange;
            } else if (controller.isMuted.value) {
              statusText = 'Microphone muted';
              statusColor = Colors.orange;
            }
            
            return Text(
              statusText,
              style: TextStyle(
                fontSize: 14,
                color: statusColor,
              ),
            );
          }),
          const SizedBox(height: 48),
          // Control buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mute button
              Obx(() => _buildControlButton(
                icon: controller.isMuted.value ? Icons.mic_off : Icons.mic,
                label: controller.isMuted.value ? 'Unmute' : 'Mute',
                color: controller.isMuted.value ? Colors.orange : Colors.grey.shade600,
                onTap: controller.toggleMute,
              )),
              const SizedBox(width: 24),
              // Stop button (center, larger)
              GestureDetector(
                onTap: () async {
                  _stopWaveAnimation();
                  await controller.stopRecording();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Recording saved!')),
                    );
                    context.go('/recordings');
                  }
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE5E5),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF6B6B),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stop_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Pause/Resume button
              Obx(() => _buildControlButton(
                icon: controller.isPaused.value ? Icons.play_arrow : Icons.pause,
                label: controller.isPaused.value ? 'Resume' : 'Pause',
                color: controller.isPaused.value ? const Color(0xFF00BFA5) : Colors.grey.shade600,
                onTap: () async {
                  if (controller.isPaused.value) {
                    await controller.resumeRecording();
                  } else {
                    await controller.pauseRecording();
                  }
                },
              )),
            ],
          ),
          const SizedBox(height: 24),
          // Instruction
          Text(
            'Tap the center button to stop and save',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
