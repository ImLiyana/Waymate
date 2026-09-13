import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AiService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent';

  Future<String> askAssistant(String userMessage) async {
    if (_apiKey.isEmpty) {
      return "AI Assistant isn't configured yet. Please add your Gemini API key.";
    }

    final url = Uri.parse(_endpoint);

    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "text":
                  "You are WayMate's travel assistant, helping tourists and pilgrims. "
                  "Keep answers short, practical, and safety-focused when relevant. "
                  "User question: $userMessage"
            }
          ]
        }
      ]
    });

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _apiKey,
          },
          body: body,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
          return text ?? "Sorry, I didn't understand that. Could you rephrase?";
        }

        if (response.statusCode == 503 && attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        return "The assistant is a bit busy right now — please try asking again in a moment.";
      } catch (e) {
        if (attempt == 1) {
          return "Something went wrong reaching the assistant. Check your internet connection.";
        }
      }
    }
    return "Something went wrong. Please try again.";
  }
}