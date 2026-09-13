import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/ai_service.dart';
import '../services/location_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage(this.text, this.isUser);
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final _aiService = AiService();
  final _locationService = LocationService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    _ChatMessage("Hi! Ask me about local hospitals, weather, emergency numbers, or anything travel-related.", false),
  ];
  bool _isTyping = false;
  String? _currentAddress;
  double? _currentLat;
  double? _currentLng;

  final _quickQuestions = [
    'Nearest hospital?',
    'Weather today?',
    'Emergency numbers',
    'Local emergency phrases',
  ];

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _locationService.getAddressFromCoordinates(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _currentAddress = address;
        });
      }
    } catch (_) {}
  }

  bool _isHospitalQuestion(String text) {
    final lower = text.toLowerCase();
    return lower.contains('hospital') || lower.contains('medical') || lower.contains('clinic');
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isTyping = true;
      _controller.clear();
    });
    _scrollToBottom();

    String reply;

    if (_isHospitalQuestion(text) && _currentLat != null && _currentLng != null) {
      final hospitals = await _locationService.findNearbyHospitals(_currentLat!, _currentLng!);
      if (hospitals.isNotEmpty) {
        final lines = hospitals.map((h) {
          final km = (h['distanceMeters'] as double) / 1000;
          return '• ${h['name']} — ${km.toStringAsFixed(1)} km away';
        }).join('\n');
        reply = "Here are the nearest hospitals to your current location:\n\n$lines";
      } else {
        reply = "I couldn't find hospital data for your exact area right now. For immediate help, open Google Maps and search \"hospital near me\", or call your local emergency number.";
      }
    } else {
      final locationContext = _currentAddress != null
          ? " The user's current location is approximately: $_currentAddress."
          : '';
      reply = await _aiService.askAssistant('$text$locationContext');
    }

    if (mounted) {
      setState(() {
        _messages.add(_ChatMessage(reply, false));
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.auto_awesome, color: AppColors.gold, size: 20),
          SizedBox(width: 8),
          Text('Travel Assistant'),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Align(alignment: Alignment.centerLeft, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold))),
                  );
                }
                final msg = _messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: msg.isUser ? AppColors.gold : AppColors.navyCard,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(msg.isUser ? 14 : 4),
                        bottomRight: Radius.circular(msg.isUser ? 4 : 14),
                      ),
                    ),
                    child: Text(msg.text, style: TextStyle(color: msg.isUser ? AppColors.navyDark : Colors.white, fontSize: 14)),
                  ),
                );
              },
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _quickQuestions.map((q) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _send(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.navyBorder)),
                    child: Text(q, style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                  ),
                ),
              )).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(hintText: 'Ask something...', hintStyle: TextStyle(color: AppColors.textOnNavyMuted)),
                  onSubmitted: _send,
                ),
              ),
              IconButton(icon: const Icon(Icons.send, color: AppColors.gold), onPressed: () => _send(_controller.text)),
            ]),
          ),
        ],
      ),
    );
  }
}