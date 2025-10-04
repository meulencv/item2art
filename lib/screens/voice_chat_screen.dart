import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_chat_provider.dart';

class VoiceChatScreen extends StatelessWidget {
  final String initialMemoryText;
  const VoiceChatScreen({super.key, required this.initialMemoryText});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          VoiceChatProvider()..addSystemIntro(_buildIntro(initialMemoryText)),
      child: const _VoiceChatView(),
    );
  }

  String _buildIntro(String text) {
    return 'This is the memory read from the NFC tag. I will start by telling you a little about it, and you can ask me anything you want.\n\n$text';
  }
}

class _VoiceChatView extends StatefulWidget {
  const _VoiceChatView();

  @override
  State<_VoiceChatView> createState() => _VoiceChatViewState();
}

class _VoiceChatViewState extends State<_VoiceChatView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VoiceChatProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0f0c29),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Voice Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: provider.messages.length,
              itemBuilder: (context, index) {
                final msg = provider.messages[index];
                final isAI = msg.role == VoiceChatMessageRole.ai;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  alignment: isAI
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isAI
                            ? [
                                const Color(0xFF667EEA).withOpacity(0.4),
                                const Color(0xFF764BA2).withOpacity(0.4),
                              ]
                            : [
                                const Color(0xFFFF6B9D),
                                const Color(0xFFFEC163),
                              ],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isAI ? 0 : 18),
                        bottomRight: Radius.circular(isAI ? 18 : 0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      msg.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _buildBottomBar(context, provider),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, VoiceChatProvider provider) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: provider.isProcessing
                    ? Row(
                        key: const ValueKey('loading'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Processing...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      )
                    : Text(
                        provider.isRecording
                            ? 'Recording... release to send'
                            : 'Hold to speak',
                        key: ValueKey(provider.isRecording ? 'rec' : 'idle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: provider.isRecording
                              ? Colors.redAccent
                              : Colors.white70,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onLongPressStart: (_) => provider.startRecording(),
              onLongPressEnd: (_) => provider.stopRecordingAndProcess(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: provider.isRecording
                        ? [Colors.redAccent, Colors.redAccent.withOpacity(0.7)]
                        : [const Color(0xFF667EEA), const Color(0xFF764BA2)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (provider.isRecording
                                  ? Colors.redAccent
                                  : const Color(0xFF667EEA))
                              .withOpacity(0.6),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  provider.isRecording ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
