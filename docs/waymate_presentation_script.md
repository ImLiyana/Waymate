# WayMate: running-app presentation script

Based on the current project source reviewed on 8 October 2026. The script describes implemented code paths; it does not claim that every feature has passed a live-device test.

Allow about 15–20 minutes, including tapping through the application. Speak the paragraphs marked **Say**. Use **Show** as stage directions and **Code explanation** when the examiner asks how the feature works.

## Before the demonstration

- Use two Android devices, or an Android device and an emulator with location configured: one guide and one tourist. A second tourist helps demonstrate the nearest-tourist profile feature.
- Use demonstration accounts, phone numbers, and emergency contacts. Registration currently accepts Gmail addresses, requires ten-digit phone numbers and emergency contacts, and requires a password of at least six characters.
- Enable GPS, connect to the internet, and grant the required location, camera, and notification permissions. Check the Firebase configuration and Gemini configuration before presenting.
- Keep the guide dashboard visible when demonstrating incoming alerts. The current receiver uses a Firestore listener in the guide dashboard and local notifications; Firebase Cloud Messaging is not implemented.
- Check the map, QR scanner, route request, hospital search, and AI response beforehand. Do not change the code during the presentation.
- Demonstrate leaving, removing members, transferring leadership, and ending the trip only after the other features. These actions change the group used by the demonstration.
- You can show an SMS draft without sending it. Explain that the user must send the message in the phone's messaging application.

## 1. Introduction

**Show:** Open the application and display the WayMate name.

**Say:** “Good morning. My project is WayMate, a travel coordination and assistance application for tourists, pilgrims, and their guides. During a group trip, members can become separated, miss instructions, or need help without being able to describe their location. WayMate brings group location sharing, communication, meeting points, and assistance requests into one application.

“There are two roles: guide and tourist. I will demonstrate both roles and explain the main technologies behind each feature.”

**Code explanation:** Flutter and Dart implement the application. `MaterialApp` applies the shared theme. Firebase Authentication manages sign-in; Cloud Firestore stores profiles and group data. Services separate data operations from the screen widgets.

## 2. Application startup and login

**Show:** Display the login screen. Point to the email, password, visibility button, and Register link. Sign in with a prepared account.

**Say:** “This is the login page. An existing user enters their email and password. The eye icon shows or hides the password, and the loading indicator shows that sign-in is in progress. If sign-in fails, the application displays an error message.

“I use Firebase Authentication for email and password sign-in. After authentication, the application watches the login state and opens the home screen automatically. The home screen reads the profile to determine whether to display the guide or tourist interface.”

**Code explanation:** `main()` initializes Flutter, loads environment configuration, initializes Firebase, and configures notifications and background tracking. `AuthService.login()` calls `signInWithEmailAndPassword()`. `AuthGate` uses `StreamBuilder<User?>` with `authStateChanges`. The role comes from the Firestore user profile, not from the authentication record.

## 3. Registration and user roles

**Show:** Open Register. Switch between Tourist and Guide. Demonstrate a validation message without submitting an incomplete form.

**Say:** “New users register with their name, phone number, emergency contact, email, password, and role. The form checks required information before submitting. In this version, registration accepts Gmail addresses, ten-digit contact numbers, and passwords containing at least six characters.

“When a guide registers, the application creates a group automatically. A tourist can provide a group code or scan the guide's QR code during registration. The group code is optional, so a tourist can register first and join a group later.”

**Code explanation:** A `Form`, `GlobalKey<FormState>`, and `TextFormField` validators check the inputs. `AuthService.register()` creates the Firebase account and stores an `AppUser` profile under `users/{uid}`. `AppUser.toMap()` and `AppUser.fromMap()` convert between Dart objects and database fields. Registration then calls `createGroupForGuide()` or `joinGroup()` according to the selected role.

## 4. Group code and QR code page

**Show:** On the guide dashboard, tap the QR icon. On the tourist registration page, open the scanner and scan it. Alternatively, demonstrate joining with the displayed code.

**Say:** “This page shows the guide's group code and its QR representation. The QR code contains the same group code, so tourists can avoid typing it manually. The scanner reads the code and fills the group-code field during registration.

“The application checks whether the group exists. It then adds the tourist to the group's member list and saves the group ID in the tourist's profile.”

**Code explanation:** `_generateGroupCode()` creates a six-character code. `qr_flutter` renders it using `QrImageView`, and `mobile_scanner` reads it using `MobileScanner`. `joinGroup()` checks `groups/{code}`, uses `FieldValue.arrayUnion()` for `memberIds`, and updates `users/{uid}.groupId`. The home-screen Join dialog currently supports typed codes; the implemented camera scanner is on registration.

## 5. Guide home page and map

**Show:** Return to the guide dashboard. Point out the group code, member count, map markers, zoom controls, and draggable member panel. Tap a member or map marker.

**Say:** “This is the guide dashboard. It shows the group's shared locations on a map, the group code, and the number of tourists represented by location records. I can zoom, return to my location, and expand the member panel. Selecting a member centers the map on their shared location.

“The map is built with flutter_map and OpenStreetMap tiles. The device gets its coordinates through Geolocator. The application stores latitude, longitude, group ID, role, battery level, and update time in Firestore. A live database listener rebuilds the markers when those records change.”

**Code explanation:** `_startLocation()` starts the GPS stream. `LocationService.pushLocation()` writes `locations/{uid}`. `groupLocationsStream()` filters location records by group ID and uses `.snapshots()`. `_buildGuideMap()` combines `TileLayer` and `MarkerLayer`. `MapController` handles zooming and centering. The list and count are based on location documents, so a registered member without a location record may not appear yet.

## 6. Tourist home page and routes

**Show:** Switch to the tourist device. Point out the tourist's own location, guide marker, other group members, route button, and any destination banner.

**Say:** “This is the tourist view. A tourist can see their own position, the guide, and other group members with shared location records. This helps the tourist find the group if they become separated.

“The route button requests a route from the tourist's position to the guide. When a meeting point has been set, the Navigate button requests a route to that destination. The application receives route coordinates and draws a line on the map.”

**Code explanation:** `_buildTouristView()` displays group markers. `_fetchRoute()` makes an HTTP request to the configured OSRM endpoint, parses the returned GeoJSON coordinates, converts them into `LatLng` objects, and renders a `PolylineLayer`. Describe this as route display; the code does not implement spoken turn-by-turn navigation or verify the routing server's walking profile.

## 7. Distance warning and location status

**Show:** Expand the guide's member panel. Show a distant tourist if available, or explain the threshold without claiming a live event occurred.

**Say:** “The guide can identify a tourist who is more than 500 metres from the guide's shared location. The application calculates the distance between the two sets of coordinates and displays ‘Straying too far’ in the guide's member panel.

“The panel also uses the location timestamp to classify recently updated records as active. On logout, the app attempts to retain the last location with an offline flag, which the home map can display as a last known location.”

**Code explanation:** `Geolocator.distanceBetween()` calculates coordinate distance. `isStrayingTooFar()` compares it with `geofenceRadiusMeters`, which is 500. The dashboard uses a ten-minute timestamp threshold for activity. This is a distance comparison in the UI, not an operating-system geofence or a separate background separation alarm. A recent timestamp is not proof of continuous connectivity.

## 8. Group Members page and contact actions

**Show:** Open the drawer and choose Group Members. Tap a member to display their details. Point to the phone button without placing an unnecessary call.

**Say:** “The Group Members page provides a list of members who have shared location records. It shows their name, activity status, guide indicator, and a warning icon when battery is low. Opening a member displays contact information, battery level, and an address when it can be obtained.

“The address is obtained by reverse geocoding: converting latitude and longitude into a readable place description. The call button opens the phone application with the selected number.”

**Code explanation:** `MembersScreen` listens to `groupLocationsStream()` and loads names from user profiles. `getAddressFromCoordinates()` uses the `geocoding` package. `url_launcher` opens a `tel:` URI. The separate members page uses timestamp-based activity; the home dashboard additionally checks the offline flag.

## 9. Trip Destination and Set Destination pages

**Show:** As guide, open Trip Destination, choose Set Destination, tap the map, name the point “Main Entrance,” add a meeting time and instruction, and save. Show the tourist's banner and map pin. Point out Change and Clear.

**Say:** “The guide uses this page to choose a meeting point. I tap the map to drop a pin, enter a destination name, and optionally provide an arrival time and instructions. After saving, the destination appears on the tourist's home page without requiring a manual refresh.

“The tourist can use Navigate to request a route. The guide can change the destination or clear it when the meeting point is no longer needed.”

**Code explanation:** `SetDestinationScreen` handles the map tap through `MapOptions.onTap`. `showTimePicker()` collects the optional time. `GroupService.setDestination()` stores a nested `destination` object in the group document. `destinationStream()` reads it through a Firestore snapshot listener. `clearDestination()` removes the field with `FieldValue.delete()`. One current destination is stored; there is no itinerary history or automatic arrival detection.

## 10. Announcements page

**Show:** As guide, open Announcements, enter “Please meet at the main entrance in ten minutes,” and tap Send to Group. Show the banner on the tourist device. Demonstrate Clear Announcement if needed.

**Say:** “Announcements let the guide publish a current instruction to the group. This is useful for meeting reminders or changes to a trip plan. The announcement appears as a banner on the tourist's home screen.

“The current version stores one announcement at a time. Sending another replaces the previous one, and the guide can clear it.”

**Code explanation:** `postAnnouncement()` writes the text and server timestamp to the group document. `announcementStream()` supplies live updates to `StreamBuilder`. `clearAnnouncement()` deletes the field. This feature is a live in-app banner, not a separately implemented remote push-notification system.

## 11. Group Chat page

**Show:** Open Group Chat on both devices. Send a message and show it on the other device. Long-press to pin it. Demonstrate Unsend on a message belonging to the current user. Point out the unread badge in the drawer.

**Say:** “Group Chat supports conversation between guides and tourists. Each message is stored with its sender information and timestamp, and the other device displays it through a live listener.

“A message can be pinned so the group can find important information quickly. A sender can unsend their own message; the interface then displays ‘This message was deleted.’ The drawer also shows a count of unread messages from other users.”

**Code explanation:** Messages are stored under `groups/{groupId}/messages/{messageId}`. `messagesStream()` orders them by timestamp. `pinMessage()` uses a write batch to unpin previous messages and pin the selected one. `deleteMessage()` clears the text and sets `deleted: true`. `markGroupRead()` stores a timestamp under `groups/{groupId}/reads/{uid}`. `unreadCountStream()` counts messages from other users after that timestamp. The current UI offers pinning to group chat users; it does not limit it to guides. The Unsend restriction is implemented in the UI; do not claim verified database-level enforcement without examining deployed rules.

## 12. SOS and confirmation dialogs

**Show:** Keep the guide dashboard open. On the tourist device, tap TAP FOR SOS and confirm. Show the SMS draft with its map link, then return to WayMate. On the guide device, open the alert banner and show Mark as Resolved. Alternatively, cancel an accidental alert using “This was a mistake — Cancel.”

**Say:** “The SOS button provides a quick way to request help. A confirmation dialog reduces accidental activation. After confirmation, the app creates an alert containing the user's identity, group ID, coordinates, timestamp, type, and active status.

“The application looks up the guide's phone number, the emergency contact, and the nearest other group member using the available shared locations. It opens an SMS draft containing the person's name and a Google Maps link. The user still has to send this message in the messaging application.

“While the guide dashboard is listening, it displays the active alert and requests a local notification. The guide can open the details, contact the tourist, and mark the alert as resolved. An accidental alert can also be cancelled by the tourist.”

**Code explanation:** `SosButton` opens the first confirmation. `_handleSos()` calls `SosService.triggerSos()`. `_findNearestMember()` selects the minimum coordinate distance from available location records. `_openSmsComposer()` launches an `sms:` URI. The dashboard listens for `sos_alerts` matching the group and `status: active`; `NotificationService.showSosAlert()` uses `flutter_local_notifications`. `resolveAlert()` changes status to `resolved`. The stored `nearestMemberUid` has no separate tourist-side alert receiver in the current source. Do not claim automatic SMS delivery, guaranteed emergency response, or alert delivery when the guide app is closed.

## 13. Medical Aid

**Show:** Tap “Feeling unwell? Tap for medical aid” on the tourist device and show its confirmation. If demonstrated fully, show the guide's medical alert and resolve it.

**Say:** “Medical Aid is a separate assistance request for a tourist who feels unwell. It creates an alert with type ‘medical’ and opens an SMS draft addressed to the guide and nearest group member. The emergency contact is not included in this medical-request flow.

“The guide sees a medical alert and can open the location and resolve the request.”

**Code explanation:** `MedicalAidButton` confirms the action. `_handleMedicalAid()` calls `triggerMedicalAid()`, which writes the alert to the same collection with a different type. The guide dashboard changes the label and colour according to that type. This coordinates an assistance request; it does not provide a medical diagnosis or dispatch an ambulance.

## 14. Battery monitoring

**Show:** Show a member's battery percentage in their details. If a prepared tourist device is at 15% or lower, show the resulting alert; otherwise explain the threshold.

**Say:** “WayMate includes battery information with location updates. When a tourist's battery reaches 15 percent or lower, the app can create a low-battery alert with their location. This helps the guide recognize that the tourist's phone may soon become unavailable.

“A flag reduces repeated alerts within each tracking path until the battery rises above the threshold. Battery is checked when position updates arrive.”

**Code explanation:** `battery_plus` reads the percentage. `checkLowBatteryOnce()` applies the foreground threshold, and `sendLowBatteryAlert()` writes the alert and opens a guide SMS draft. The background service has its own threshold check and writes the Firestore alert without opening messaging. Foreground and background tracking use separate flags, so the code does not guarantee a single alert across both paths or across restarts.

## 15. Travel Assistant page

**Show:** Tap the gold assistant button. Ask “What should I carry for a group trip?” Then show the quick-question buttons for weather, emergency numbers, and emergency phrases.

**Say:** “The Travel Assistant provides a chat interface for travel questions. It can send a user's question, together with an approximate address when available, to the configured Gemini API. The response appears as an assistant message, and a loading indicator shows that the request is being processed.

“The quick-question buttons provide convenient starting questions. The app currently sends the weather question to the AI; it does not connect to a dedicated live weather service.”

**Code explanation:** `AiAssistantScreen._send()` adds the question to an in-memory message list. `AiService.askAssistant()` builds JSON, sends it through `http.post()`, and extracts response text. The configured model identifier is `gemini-3.1-flash-lite`. The API key is read through `flutter_dotenv`. The service includes a request timeout, retries for some failures, and messages for rate limits and permission errors. This is an external pretrained model integration, not a model trained by this project. The visible conversation is not saved to Firestore, and previous conversation messages are not included in subsequent requests.

## 16. Hospital search inside the assistant

**Show:** Ask “Hospitals near me” after the assistant has obtained location. Show the returned names and distances if the service responds.

**Say:** “Hospital questions use a different data path. The screen detects a question containing ‘hospital’ or ‘clinic’ and searches OpenStreetMap through the Overpass API using the device's coordinates.

“The code searches for hospital-tagged places within 20 kilometres, calculates their coordinate distances, sorts them, and displays up to five results. These results come from mapped place records. The displayed distance is a direct coordinate distance rather than road travel distance.”

**Code explanation:** `_isHospitalQuestion()` selects this path. `findNearbyHospitals()` posts an Overpass query for `amenity=hospital` on nodes, ways, and relations. It obtains coordinates directly or from the returned centre, uses `distanceBetween()`, sorts the list, and takes five. Although ‘clinic’ triggers this path, the query searches hospital tags only. The current empty-results message says 1 km, but the actual query uses 20 km; explain the query accurately if asked.

## 17. My Profile page

**Show:** Open My Profile from the drawer. Point to name, role, phone, email, emergency contact, group code, and Nearest Tourist when available.

**Say:** “My Profile brings the user's account information into one page. It shows the name, role, phone number, email, emergency contact, and group code.

“When another tourist in the group has shared location, the page can also show the nearest tourist and their approximate distance. It compares the current user's coordinates with the other tourist location records and selects the smallest distance.”

**Code explanation:** `AuthService.getUserProfile()` reads the Firestore profile, and Firebase Authentication supplies the email. `_findNearestTourist()` excludes the current user and guide-role records. This calculation happens when the profile page loads; it is not a continuously refreshing nearest-person stream. The current page displays information and does not include a profile-edit form.

## 18. Background location sharing

**Show:** Display the Android location-sharing notification. Briefly minimize the tourist app and check whether the guide receives a later location update on the prepared device.

**Say:** “The project includes an Android foreground service intended to keep sharing location while the application is minimized. Android displays a persistent notification so the user can see that sharing is running.

“The service runs in a separate Dart isolate, initializes Firebase there, listens for the user's role and group, and writes GPS updates to Firestore. Tracking requests high accuracy with a 15-metre distance filter. Its behaviour still depends on permissions, connectivity, and the device's background restrictions.”

**Code explanation:** `setupBackgroundLocationService()` configures `flutter_background_service` without starting it automatically. The home screen starts it after location permission succeeds. `_onBackgroundStart()` initializes plugins and Firebase in the service isolate, subscribes to profile and position streams, and handles the stop event. A distance filter is not a fixed refresh interval. Do not promise uninterrupted tracking after force-stop or claim equivalent iOS background behaviour; the implementation demonstrated here is Android-focused.

## 19. Group management and trip lifecycle

**Show:** As guide, open a tourist's member details and show Remove and Make Guide. Explain both before changing the group. Near the end, show Leave Group on the tourist account and End Trip on the guide account. A guide without a group can then use Start New Trip; a tourist without a group can use Join a Group.

**Say:** “The guide can remove a tourist or transfer leadership to another member. Removal clears the member's group association and removes their location record. Leadership transfer makes the selected member the guide and changes the previous guide to a tourist.

“A tourist can leave voluntarily. The guide can end the trip after confirming the action. This clears the group associations and location records for its members, attempts to delete the group's chat messages, and deletes the group document. The users keep their accounts and can start or join another trip.”

**Code explanation:** The drawer displays different actions according to `user.role` and `groupId`. `removeMember()` updates `memberIds`, clears the user's group ID, and deletes the location document. `transferGuideRole()` updates the guide ID and user/location roles. `endTrip()` uses a Firestore batch, selecting at most 400 chat messages for deletion. It does not provide unlimited history cleanup, and background tracking may recreate an ungrouped location document. `createGroupForGuide()` supports Start New Trip. Describe role-based UI controls without claiming verified server-side authorization rules.

## 20. Logout and closing

**Show:** Tap Log Out, return to the login page, and finish.

**Say:** “Logging out sends a stop request to the background service, attempts to mark the last location offline, and signs out through Firebase Authentication. The authentication listener then returns the application to the login page.

“WayMate demonstrates how mobile location services, a real-time database, group communication, and external APIs can work together in an academic application. The main contribution is connecting these features around the needs of a guide and travelling group. Future improvements include stronger automated testing, server-side access validation, remote push notifications, and more reliable external-service handling. Thank you.”

**Code explanation:** `AuthService.logout()` invokes `stopBackgroundLocationService()`, updates `online` and `lastSeen` when possible, and calls Firebase `signOut()`. The UI transition follows from `AuthGate` listening to authentication state.

## Technologies and where to show the code

| Feature | Technology | Code to open |
|---|---|---|
| Startup and authentication routing | Flutter, Firebase Core, Firebase Authentication, StreamBuilder | [main.dart](C:/Users/liyal/Documents/waymate/lib/main.dart) |
| Login and registration | Firebase Authentication, form validators | [login_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/auth/login_screen.dart), [register_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/auth/register_screen.dart), [auth_service.dart](C:/Users/liyal/Documents/waymate/lib/services/auth_service.dart) |
| Profile data conversion | AppUser, toMap, fromMap | [user_model.dart](C:/Users/liyal/Documents/waymate/lib/models/user_model.dart) |
| Guide and tourist dashboards; route display | flutter_map, OpenStreetMap, Geolocator, OSRM, http, latlong2 | [home_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/home_screen.dart), [location_service.dart](C:/Users/liyal/Documents/waymate/lib/services/location_service.dart) |
| Group creation and joining | Cloud Firestore, arrayUnion | [group_service.dart](C:/Users/liyal/Documents/waymate/lib/services/group_service.dart) |
| QR display and scanning | qr_flutter, mobile_scanner | [qr_display_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/qr_display_screen.dart), registration screen above |
| Member details and phone dialler | geocoding, url_launcher | [members_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/members_screen.dart) |
| Meeting points | map tap, time picker, Firestore streams | [trip_destination_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/trip_destination_screen.dart) |
| Announcements | Cloud Firestore, StreamBuilder | [announcements_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/announcements_screen.dart) |
| Chat, pins, deletion, unread count | Cloud Firestore streams and write batch | [chat_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/chat_screen.dart), [chat_service.dart](C:/Users/liyal/Documents/waymate/lib/services/chat_service.dart) |
| SOS, medical aid, SMS drafts | Cloud Firestore, url_launcher | [sos_service.dart](C:/Users/liyal/Documents/waymate/lib/services/sos_service.dart), [widgets.dart](C:/Users/liyal/Documents/waymate/lib/core/widgets.dart) |
| Local alert notifications | flutter_local_notifications, permission_handler | [notification_service.dart](C:/Users/liyal/Documents/waymate/lib/services/notification_service.dart) |
| AI questions and hospital search | Gemini API, http, flutter_dotenv, Overpass API | [ai_assistant_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/ai_assistant_screen.dart), [ai_service.dart](C:/Users/liyal/Documents/waymate/lib/services/ai_service.dart), location service above |
| Profile and nearest tourist | Firebase Authentication, Firestore, Geolocator | [profile_screen.dart](C:/Users/liyal/Documents/waymate/lib/screens/profile_screen.dart) |
| Background location and battery | flutter_background_service, Geolocator, battery_plus | [background_location_service.dart](C:/Users/liyal/Documents/waymate/lib/services/background_location_service.dart) |
| Drawer and trip actions | Navigator, role conditions, confirmation dialogs | [app_drawer.dart](C:/Users/liyal/Documents/waymate/lib/screens/app_drawer.dart) |
| Shared styling | Material 3, ThemeData, reusable widgets | [theme.dart](C:/Users/liyal/Documents/waymate/lib/core/theme.dart), shared widgets above |
| Package declarations | pubspec dependencies | [pubspec.yaml](C:/Users/liyal/Documents/waymate/pubspec.yaml) |

## Database explanation for the viva

| Data location | What the current code stores |
|---|---|
| Firebase Authentication | Account identity and authentication credentials, managed by Firebase |
| `users/{uid}` | Name, phone, role, group ID, emergency-contact phone |
| `groups/{groupId}` | Guide ID, group name, member IDs, creation time, current destination, current announcement |
| `locations/{uid}` | Coordinates, update time, group ID, role, battery percentage; logout can add offline/last-seen fields |
| `sos_alerts/{alertId}` | User ID, group ID, coordinates, timestamp, status, alert type; SOS can add nearestMemberUid |
| `groups/{groupId}/messages/{messageId}` | Sender ID/name, text, timestamp, pinned flag, deleted flag |
| `groups/{groupId}/reads/{uid}` | Last-read timestamp for unread counts |

Explain the main flow as: device GPS → Firestore location document → group snapshot listener → updated map marker. For chat: text input → Firestore message → snapshot listener → message bubble. For AI: question plus optional address → HTTP request → Gemini response → assistant bubble.

## Short viva answers

**Why Flutter?** “It lets me build the UI and application logic in Dart and use plugins for maps, Firebase, camera scanning, notifications, and device location. This project currently focuses on demonstrating the Android implementation.”

**Why Firebase?** “Authentication provides account sign-in, while Firestore provides cloud documents and live snapshot listeners for shared locations, messages, and group instructions.”

**How does real-time updating work?** “The screen subscribes to Firestore snapshots. When subscribed data changes, the stream emits new data and StreamBuilder rebuilds that part of the interface.”

**What is the difference between setState and StreamBuilder?** “setState refreshes local widget state, such as typing indicators or a selected map pin. StreamBuilder rebuilds from asynchronous stream events, such as new Firestore messages.”

**What is the difference between Authentication and Firestore?** “Authentication manages who is signed in. Firestore stores application-specific information, such as their role, group, and shared coordinates.”

**How is the nearest person selected?** “The app checks other available group location records, calculates the distance to each coordinate pair, and keeps the member with the minimum distance. This is coordinate proximity, not estimated travel time.”

**Did you train the AI?** “No. I integrated an external pretrained Gemini model through its API. My code builds the travel prompt, adds available location context, sends the request, and displays the response.”

**Does hospital search use Gemini?** “No. The screen directs hospital-related questions to an Overpass query for mapped hospital data, then calculates and sorts the distances.”

**Does it work offline?** “The app depends on connectivity for cloud synchronization and external requests. It has some location fallbacks, but I have not implemented or validated a complete offline workflow.”

**Are alerts push notifications?** “The guide dashboard receives Firestore changes and requests local notifications. Remote push notifications through Firebase Cloud Messaging are a future improvement.”

**Is SMS automatic?** “No. The app opens a prepared SMS draft. The user sends it in the messaging app.”

**How are guide permissions enforced?** “The UI displays management controls according to the stored role. Firestore rules must also enforce authorization independently. I should only claim database-level enforcement after checking and testing the deployed rules.”

**What are the important limitations?** “Background behaviour varies by Android permissions and device restrictions. Alert receiving currently depends on the guide dashboard listener. Weather is an AI question rather than a live weather integration. The AI configuration should move behind a backend before a public release, and the project needs more automated tests.”

**What if a service fails during the demo?** “I would explain the error shown and the code path involved. I would not present a failed request as a successful result. I can still show the local interaction and describe which external response was unavailable.”
