import 'package:flutter/material.dart';

import 'package:linkless/features/recording/presentation/views/conversation_list_screen.dart';

/// Entry point for the Conversations tab.
///
/// Delegates to [ConversationListScreen] which displays the real conversation
/// list backed by the Drift database with reactive stream updates.
class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ConversationListScreen();
  }
}
