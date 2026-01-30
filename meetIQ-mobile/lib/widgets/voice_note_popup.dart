import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/recording_controller.dart';

/// Shows a WhatsApp-style voice note recording popup
/// Returns true if a recording was saved, false otherwise
Future<bool> showVoiceNotePopup(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) => const VoiceNotePopup(),
  );
  return result ?? false;
}

class VoiceNotePopup extends StatefulWidget {
  const VoiceNotePopup({super.key});

  @override
  State<VoiceNotePopup> createState() => _VoiceNotePopupState();
}

class _VoiceNotePopupState extends State<VoiceNotePopup>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  final List<double> _waveHeights = [];
  Timer? _waveTimer;
  bool _isRecording = false;
  int _elapsedSeconds = 0;
  Timer? _timerUpdater;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    
    // Initialize wave heights
    for (int i = 0; i < 30; i++) {
      _waveHeights.add(0.3 + Random().nextDouble() * 0.4);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _waveTimer?.cancel();
    _timerUpdater?.cancel();
    super.dispose();
  }

  void _startWaveAnimation() {
    _waveTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _isRecording) {
        setState(() {
          for (int i = 0; i < _waveHeights.length; i++) {
            _waveHeights[i] = 0.2 + Random().nextDouble() * 0.6;
          }
        });
      }
    });
    
    // Update elapsed time
    _timerUpdater = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _stopWaveAnimation() {
    _waveTimer?.cancel();
    _waveTimer = null;
    _timerUpdater?.cancel();
    _timerUpdater = null;
  }

  Future<void> _startRecording() async {
    final controller = Get.find<RecordingController>();
    
    // Haptic feedback
    HapticFeedback.mediumImpact();
    
    final ok = await controller.startRecording('Voice Note');
    if (ok) {
      setState(() {
        _isRecording = true;
        _elapsedSeconds = 0;
      });
      _startWaveAnimation();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    final controller = Get.find<RecordingController>();
    
    // Haptic feedback
    HapticFeedback.lightImpact();
    
    _stopWaveAnimation();
    
    if (controller.isRecording.value) {
      await controller.stopRecording();
      
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate recording was saved
      }
    } else {
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _cancelRecording() async {
    if (_isRecording) {
      final controller = Get.find<RecordingController>();
      _stopWaveAnimation();
      
      // Cancel the recording without saving
      if (controller.isRecording.value) {
        await controller.cancelRecording();
      }
    }
    
    if (mounted) {
      Navigator.pop(context, false);
    }
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isRecording ? 'Recording...' : 'Voice Note',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A5F),
                      ),
                    ),
                    // Close button
                    GestureDetector(
                      onTap: _cancelRecording,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          color: Colors.grey.shade600,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Waveform visualization
                if (_isRecording) ...[
                  SizedBox(
                    height: 60,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _waveHeights.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: 3,
                          height: 60 * _waveHeights[index],
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B6B),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Timer
                  Text(
                    _formatTime(_elapsedSeconds),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFFFF6B6B),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  // Pulsing instruction
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.5 + (_pulseController.value * 0.5),
                        child: const Icon(
                          Icons.keyboard_double_arrow_down,
                          color: Color(0xFF00BFA5),
                          size: 40,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Record button with Listener for immediate response
                Listener(
                  onPointerDown: (_) {
                    if (!_isRecording) {
                      _startRecording();
                    }
                  },
                  onPointerUp: (_) {
                    if (_isRecording) {
                      _stopRecording();
                    }
                  },
                  onPointerCancel: (_) {
                    if (_isRecording) {
                      _stopRecording();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _isRecording ? 100 : 80,
                    height: _isRecording ? 100 : 80,
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFF00BFA5),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _isRecording
                              ? const Color(0xFFFF6B6B).withValues(alpha: 0.4)
                              : const Color(0xFF00BFA5).withValues(alpha: 0.3),
                          blurRadius: _isRecording ? 30 : 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: _isRecording ? 48 : 36,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Instructions
                Text(
                  _isRecording
                      ? 'Release to save'
                      : 'Hold to record',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _isRecording
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFF1E3A5F),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  _isRecording
                      ? 'Lift your finger to stop and save the recording'
                      : 'Press and hold the mic button to start recording',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
