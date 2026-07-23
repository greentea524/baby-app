import 'package:flutter/material.dart';

/// Daily event timeline. Populated by the Timeline & History epic (KAN-132).
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: const Center(child: Text('No events yet')),
    );
  }
}
