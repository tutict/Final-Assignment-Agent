import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:final_assignment_front/features/dashboard/controllers/chat_controller.dart';
import 'package:final_assignment_front/features/model/agent_context_info.dart';
import 'package:final_assignment_front/features/model/chat_action.dart';

class AiChat extends StatefulWidget {
  const AiChat({super.key});

  @override
  State<AiChat> createState() => _AiChatState();
}

class _AiChatState extends State<AiChat> {
  final ScrollController _scrollController = ScrollController();

  static const _background = Color(0xFF0E1116);
  static const _surface = Color(0xFF151A22);
  static const _surfaceRaised = Color(0xFF1C2430);
  static const _outline = Color(0xFF2A3444);
  static const _muted = Color(0xFF91A0B4);
  static const _text = Color(0xFFE6EDF6);
  static const _accent = Color(0xFF63B3ED);
  static const _accentSoft = Color(0xFF1C3146);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ChatController>();

    return DecoratedBox(
      decoration: const BoxDecoration(color: _background),
      child: SafeArea(
        child: Column(
          children: [
            _Header(controller: controller),
            Expanded(
              child: Obx(() {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                });

                if (controller.messages.isEmpty) {
                  return _EmptyState(
                    suggestions: controller.suggestions,
                    onSuggestionTap: controller.sendMessage,
                  );
                }

                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  children: [
                    if (controller.agentContext.value != null)
                      _ContextPanel(
                          contextInfo: controller.agentContext.value!),
                    if (controller.searchResults.isNotEmpty)
                      _SearchPanel(results: controller.searchResults),
                    ...controller.messages.map(
                      (message) => _MessageBlock(
                        message: message,
                        onActionTap: controller.executeAction,
                      ),
                    ),
                  ],
                );
              }),
            ),
            _Composer(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _ContextPanel extends StatelessWidget {
  const _ContextPanel({required this.contextInfo});

  final AgentContextInfo contextInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: contextInfo.privilegedOperator
            ? const Color(0xFF183124)
            : _AiChatState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: contextInfo.privilegedOperator
              ? const Color(0xFF2E7D57)
              : _AiChatState._outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Agent Context',
            style: TextStyle(
              color: _AiChatState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _ContextLine(
            label: '当前身份',
            value: contextInfo.operatorLabel ?? '未知',
          ),
          const SizedBox(height: 8),
          _ContextLine(
            label: '访问范围',
            value: contextInfo.accessScopeLabel ?? '未知',
          ),
        ],
      ),
    );
  }
}

class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: _AiChatState._muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: _AiChatState._text,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _AiChatState._outline)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _AiChatState._accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _AiChatState._outline),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  size: 18,
                  color: _AiChatState._accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'traffic-agent',
                      style: TextStyle(
                        color: _AiChatState._text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'chat.subtitle'.tr,
                      style: TextStyle(
                        color: _AiChatState._muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Obx(
                () => InkWell(
                  onTap: () => controller.toggleWebSearch(
                    !controller.webSearchEnabled.value,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: controller.webSearchEnabled.value
                          ? _AiChatState._accentSoft
                          : _AiChatState._surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AiChatState._outline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          controller.webSearchEnabled.value
                              ? Icons.language
                              : Icons.language_outlined,
                          size: 14,
                          color: controller.webSearchEnabled.value
                              ? _AiChatState._accent
                              : _AiChatState._muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          controller.webSearchEnabled.value
                              ? 'chat.webOn'.tr
                              : 'chat.webOff'.tr,
                          style: TextStyle(
                            color: controller.webSearchEnabled.value
                                ? _AiChatState._text
                                : _AiChatState._muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Obx(
            () => Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: controller.availableSkills.isEmpty
                    ? [
                        _TinyPill(
                          label: 'chat.loadingSkills'.tr,
                          icon: Icons.sync_rounded,
                        ),
                      ]
                    : controller.availableSkills
                        .map(
                          (skill) => _TinyPill(
                            label: skill.name,
                            tooltip: skill.description,
                            icon: Icons.hub_outlined,
                          ),
                        )
                        .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyPill extends StatelessWidget {
  const _TinyPill({
    required this.label,
    required this.icon,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _AiChatState._surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _AiChatState._outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _AiChatState._muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _AiChatState._muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return child;
    return Tooltip(message: tooltip, child: child);
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({required this.results});

  final List<String> results;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AiChatState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AiChatState._outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'chat.webResults'.tr,
            style: TextStyle(
              color: _AiChatState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...results.take(4).map(
                (result) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '> $result',
                    style: const TextStyle(
                      color: _AiChatState._text,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.message,
    required this.onActionTap,
  });

  final ChatMessage message;
  final ValueChanged<ChatAction> onActionTap;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final background = message.isStatus
        ? _AiChatState._surface
        : isUser
            ? _AiChatState._accentSoft
            : _AiChatState._surfaceRaised;

    final label = message.isStatus
        ? 'chat.status'
        : isUser
            ? 'chat.you'
            : 'chat.agent';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AiChatState._outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.tr,
            style: const TextStyle(
              color: _AiChatState._muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message.text,
            style: TextStyle(
              color:
                  message.isStatus ? _AiChatState._muted : _AiChatState._text,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          if (message.actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.actions
                  .map(
                    (action) => OutlinedButton.icon(
                      onPressed: () => onActionTap(action),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _AiChatState._text,
                        side: const BorderSide(color: _AiChatState._outline),
                        backgroundColor: _AiChatState._background,
                      ),
                      icon: const Icon(
                        Icons.subdirectory_arrow_right_rounded,
                        size: 16,
                      ),
                      label: Text(
                        action.label ?? action.target ?? 'chat.runAction'.tr,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.suggestions,
    required this.onSuggestionTap,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _AiChatState._surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _AiChatState._outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'chat.emptyTitle'.tr,
                style: TextStyle(
                  color: _AiChatState._text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'chat.emptyBody'.tr,
                style: TextStyle(
                  color: _AiChatState._muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: suggestions
                    .map(
                      (item) => ActionChip(
                        onPressed: () => onSuggestionTap(item),
                        backgroundColor: _AiChatState._accentSoft,
                        side: const BorderSide(color: _AiChatState._outline),
                        label: Text(
                          item,
                          style: const TextStyle(color: _AiChatState._text),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: _AiChatState._background,
        border: Border(top: BorderSide(color: _AiChatState._outline)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: _AiChatState._surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _AiChatState._outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.textController,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(
                      color: _AiChatState._text,
                      fontSize: 14,
                    ),
                    onSubmitted: (_) => controller.sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'chat.inputHint'.tr,
                      hintStyle: const TextStyle(color: _AiChatState._muted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    ),
                  ),
                ),
                Obx(
                  () => Padding(
                    padding: const EdgeInsets.only(right: 10, bottom: 10),
                    child: IconButton.filled(
                      onPressed: controller.isSending.value
                          ? null
                          : () => controller.sendMessage(),
                      style: IconButton.styleFrom(
                        backgroundColor: _AiChatState._accent,
                        foregroundColor: _AiChatState._background,
                      ),
                      icon: controller.isSending.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'chat.footer'.tr,
              style: TextStyle(color: _AiChatState._muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
