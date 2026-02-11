import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/connections/presentation/providers/connection_provider.dart';
import 'package:linkless/features/connections/presentation/widgets/connect_prompt_dialog.dart';
import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/presentation/providers/peer_profile_provider.dart';
import 'package:linkless/features/recording/presentation/providers/conversation_detail_provider.dart';
import 'package:linkless/features/recording/presentation/widgets/summary_widget.dart';
import 'package:linkless/features/recording/presentation/widgets/transcript_widget.dart';

/// Tinder-style encounter card for viewing another user's profile.
///
/// Displays the peer's photo (or a large fallback avatar) in the top half,
/// with a navy header bar showing name and platform chips, and a white
/// body card with social links below.
///
/// When [conversationId] is provided (e.g. navigating from a map pin),
/// the conversation transcript/summary and connection actions are shown
/// below the social links section.
class EncounterCardScreen extends ConsumerWidget {
  final String userId;
  final String? conversationId;

  const EncounterCardScreen({
    super.key,
    required this.userId,
    this.conversationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerAsync = ref.watch(peerProfileProvider(userId));

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: peerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Could not load profile',
                style: TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(peerProfileProvider(userId)),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
        data: (profile) => _buildCard(context, ref, profile),
      ),
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref, dynamic profile) {
    final screenHeight = MediaQuery.of(context).size.height;
    final photoHeight = screenHeight * 0.5;

    return Stack(
      children: [
        // Top photo section
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: photoHeight,
          child: profile.photoUrl != null
              ? CachedNetworkImage(
                  imageUrl: profile.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: AppColors.backgroundCard,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) =>
                      _buildFallbackAvatar(profile),
                )
              : _buildFallbackAvatar(profile),
        ),

        // Back button overlay
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: AppColors.textPrimary,
                size: 28,
              ),
              onPressed: () => context.pop(),
            ),
          ),
        ),

        // Card overlay from 45% down
        Positioned(
          top: photoHeight - 40,
          left: 0,
          right: 0,
          bottom: 0,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Navy header bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.encounterHeader,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName ?? 'Anonymous',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (profile.socialLinks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: profile.socialLinks
                              .map<Widget>(
                                (SocialLink link) => Chip(
                                  backgroundColor: AppColors.chipBackground,
                                  label: Text(
                                    link.platform.displayName,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // White body card with social links
                Container(
                  color: AppColors.backgroundDark,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile.socialLinks.isNotEmpty) ...[
                        const Text(
                          'Social Links',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...profile.socialLinks.map<Widget>(
                          (SocialLink link) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                link.platform.iconData,
                                color: AppColors.textSecondary,
                              ),
                              title: Text(
                                link.platform.displayName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '@${link.handle}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              tileColor: AppColors.backgroundCard,
                            ),
                          ),
                        ),
                      ] else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No social links shared',
                              style: TextStyle(color: AppColors.textTertiary),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Conversation section (only when navigated with a conversationId)
                if (conversationId != null)
                  _buildConversationSection(context, ref),

                // Clearance for dismiss button
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),

        // Bottom action buttons
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: _buildBottomButtons(context, ref),
        ),
      ],
    );
  }

  /// Builds the conversation transcript, summary, and connection section.
  Widget _buildConversationSection(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(conversationDetailProvider(conversationId!));

    return Container(
      color: AppColors.backgroundDark,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              const Text(
                'Could not load conversation',
                style: TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.invalidate(conversationDetailProvider(conversationId!)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) {
          if (data == null) return const SizedBox.shrink();

          final hasTranscript = data['transcript'] != null;
          final hasSummary = data['summary'] != null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 32),
              const Text(
                'Conversation',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (hasSummary)
                SummaryWidget(
                  summaryData: data['summary'] as Map<String, dynamic>,
                ),
              if (hasSummary && hasTranscript) const SizedBox(height: 16),
              if (hasTranscript)
                TranscriptWidget(
                  transcriptData:
                      data['transcript'] as Map<String, dynamic>,
                ),
              if (!hasSummary && !hasTranscript)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Transcript not yet available',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ),
              const SizedBox(height: 16),
              _buildConnectionSection(context, ref, data),
            ],
          );
        },
      ),
    );
  }

  /// Builds connection UI based on conversation detail data.
  Widget _buildConnectionSection(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
  ) {
    final peerUserId = data['peer_user_id'] as String?;
    final hasTranscript = data['transcript'] != null;
    if (peerUserId == null || !hasTranscript) return const SizedBox.shrink();

    final peerDisplayName = data['peer_display_name'] as String?;
    final peerInitials = data['peer_initials'] as String?;
    final peerPhotoUrl = data['peer_photo_url'] as String?;
    final currentUserId = data['user_id'] as String?;

    final connectionStatus =
        ref.watch(connectionStatusProvider(conversationId!));

    return connectionStatus.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (request) {
        // No request exists: show connect prompt banner
        if (request == null) {
          return _buildConnectBanner(
            context,
            ref,
            peerDisplayName: peerDisplayName,
            peerInitials: peerInitials,
            peerPhotoUrl: peerPhotoUrl,
          );
        }

        // Accepted: show connected chip
        if (request.isAccepted) {
          return _buildStatusChip(
            context,
            icon: Icons.check_circle,
            label: 'Connected',
            color: AppColors.success,
          );
        }

        // Declined: show nothing
        if (request.isDeclined) return const SizedBox.shrink();

        // Pending and current user is the requester: show sent chip
        if (request.isPending && currentUserId == request.requesterId) {
          return _buildStatusChip(
            context,
            icon: Icons.send,
            label: 'Connection request sent',
            color: AppColors.accentBlue,
          );
        }

        // Pending and current user is the recipient: show accept/decline
        if (request.isPending && currentUserId == request.recipientId) {
          return _buildIncomingRequestCard(
            context,
            ref,
            request.id,
            peerDisplayName: peerDisplayName,
            peerInitials: peerInitials,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  /// Banner card inviting the user to connect with the peer.
  Widget _buildConnectBanner(
    BuildContext context,
    WidgetRef ref, {
    String? peerDisplayName,
    String? peerInitials,
    String? peerPhotoUrl,
  }) {
    final name = peerDisplayName ?? peerInitials ?? 'this person';
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.person_add,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect with $name',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Exchange social links',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

  /// Card for incoming connection request with accept/decline buttons.
  Widget _buildIncomingRequestCard(
    BuildContext context,
    WidgetRef ref,
    String requestId, {
    String? peerDisplayName,
    String? peerInitials,
  }) {
    final name = peerDisplayName ?? peerInitials ?? 'Someone';
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_add,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$name wants to connect',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Accept to exchange social links',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small status chip for connection state indication.
  Widget _buildStatusChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Chip(
          avatar: Icon(icon, size: 18, color: color),
          label: Text(label),
          backgroundColor: color.withValues(alpha: 0.1),
          side: BorderSide.none,
        ),
      ),
    );
  }

  /// Builds the bottom floating action buttons (reject left, accept right).
  Widget _buildBottomButtons(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Left button — dismiss
        GestureDetector(
          onTap: () => context.pop(),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/Reject - No BG.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        // Right button — connect / accept (conditionally visible)
        if (conversationId != null)
          _buildAcceptButton(context, ref),
      ],
    );
  }

  /// Builds the right-side accept/connect button based on connection state.
  Widget _buildAcceptButton(BuildContext context, WidgetRef ref) {
    final connectionStatus =
        ref.watch(connectionStatusProvider(conversationId!));
    final detail = ref.watch(conversationDetailProvider(conversationId!));

    return connectionStatus.when(
      loading: () => const SizedBox(width: 64),
      error: (_, __) => const SizedBox(width: 64),
      data: (request) {
        final currentUserId = detail.valueOrNull?['user_id'] as String?;
        final peerDisplayName =
            detail.valueOrNull?['peer_display_name'] as String?;
        final peerInitials =
            detail.valueOrNull?['peer_initials'] as String?;
        final peerPhotoUrl =
            detail.valueOrNull?['peer_photo_url'] as String?;

        // Already connected or outgoing pending — hide button
        if (request != null &&
            (request.isAccepted ||
                (request.isPending &&
                    currentUserId == request.requesterId))) {
          return const SizedBox(width: 64);
        }

        // Declined — hide button
        if (request != null && request.isDeclined) {
          return const SizedBox(width: 64);
        }

        // Determine action
        VoidCallback onTap;
        if (request != null &&
            request.isPending &&
            currentUserId == request.recipientId) {
          // Incoming pending — accept
          onTap = () async {
            await acceptConnection(
              ref,
              request.id,
              conversationId: conversationId,
            );
          };
        } else {
          // No request — open connect prompt
          onTap = () {
            ConnectPromptDialog.show(
              context,
              peerDisplayName: peerDisplayName,
              peerInitials: peerInitials,
              peerPhotoUrl: peerPhotoUrl,
              conversationId: conversationId!,
              onAccept: () async {
                await sendConnectionRequest(ref, conversationId!);
              },
              onDecline: () {},
            );
          };
        }

        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/Favicon - No BG.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackAvatar(dynamic profile) {
    return Container(
      color: AppColors.backgroundCard,
      child: Center(
        child: CircleAvatar(
          radius: 60,
          backgroundColor: AppColors.accentBlue,
          child: Text(
            profile.initials ?? '?',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
