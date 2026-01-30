import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class PulsingMic extends StatelessWidget {
  const PulsingMic({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.mic, size: 48, color: Theme.of(context).colorScheme.primary),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .scale(duration: 1200.ms, begin: const Offset(1, 1), end: const Offset(1.1, 1.1))
        .fade(duration: 1200.ms, begin: 0.6, end: 1.0);
  }
}
