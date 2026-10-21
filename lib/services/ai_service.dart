import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AiService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent';

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
                  "Keep answers short, practical, and safety-focused when relevant.\n\n"
                  "User question: $userMessage"
            }
          ]
        }
      ]
    });

    // Try Gemini up to 3 times if it is temporarily busy.
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': _apiKey,
              },
              body: body,
            )
            .timeout(const Duration(seconds: 30));

        print('Gemini status: ${response.statusCode}');
        print('Gemini response: ${response.body}');

        // SUCCESS
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          final text =
              data['candidates']?[0]?['content']?['parts']?[0]?['text'];

          return text ??
              "Sorry, I didn't understand that. Could you rephrase?";
        }

        // GEMINI IS BUSY
        if (response.statusCode == 503) {
          if (attempt < 2) {
            // Wait 5 seconds, then 10 seconds
            final waitSeconds = 5 * (attempt + 1);

            print(
              'Gemini is busy. Retrying in $waitSeconds seconds...',
            );

            await Future.delayed(
              Duration(seconds: waitSeconds),
            );

            continue;
          }

          return "Gemini is temporarily busy. Please try again in a moment.";
        }

        // RATE LIMIT
        if (response.statusCode == 429) {
          return "The AI usage limit has been reached. Please try again later.";
        }

        // BAD REQUEST
        if (response.statusCode == 400) {
          return "There was a problem with the AI request.";
        }

        // API KEY / PERMISSION
        if (response.statusCode == 401 ||
            response.statusCode == 403) {
          return "The Gemini API key is invalid or doesn't have permission to use this model.";
        }

        // OTHER SERVER ERROR
        if (response.statusCode >= 500) {
          return "Gemini is temporarily unavailable. Please try again shortly.";
        }

        return "Gemini returned an error (${response.statusCode}).";
      } catch (e) {
        print('Gemini exception: $e');

        if (attempt < 2) {
          await Future.delayed(
            const Duration(seconds: 3),
          );
          continue;
        }

        return "Unable to connect to the AI assistant right now.";
      }
    }

    return "The AI assistant is temporarily unavailable.";
  }
}