# ThoughtLoom

Weave clarity into your decisions.

## Running

The app runs with no configuration at all. Without Supabase credentials it
persists to on-device storage, so the whole flow — register, sign in, chats,
messages, memory — works offline:

```bash
flutter run
```

Watch the console on launch; it prints which backend it selected.

## Pointing it at Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Open the SQL editor and run [`supabase/schema.sql`](supabase/schema.sql).
   It is idempotent, so re-running it after an edit is safe — and **if your
   project predates the AI flow you must re-run it**, which adds the
   `awaiting_follow_up` and `assistant_reply` enum values those endpoints write.
3. Copy the project URL and public API key from **Project Settings → API**.
   Newer projects show a `sb_publishable_...` key where older ones show a JWT
   "anon" key — either goes in the same place.
4. Pass both at build time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-key-here
```

`SUPABASE_PUBLISHABLE_KEY` is accepted as an alias if you prefer the newer name.

Never pass the `service_role` key. The publishable key is meant to ship inside
clients; Row Level Security is what protects the data, and `schema.sql` sets up
those policies. Without it every table would be world-readable.

### Email confirmation

Supabase confirms email addresses by default, which means registration creates
the account but does not sign the user in — they get a "check your inbox"
notice. To sign in immediately during development, turn off
**Authentication → Providers → Email → Confirm email**.

## Architecture

```
Flutter ──auth + CRUD──> Supabase (Row Level Security)
   │
   └──────AI───────────> thoughtloom_backend (FastAPI on Render) ──> Cohere
                                  │                              └──> web search
                                  └──> Supabase (service-role: reads context,
                                                 writes the model's turns)
```

Auth and the user's own data go straight from the app to Supabase, protected by
Row Level Security. Anything involving the model goes through the FastAPI
service, which reads the chat's context and writes the model's turns back itself
— so the app never has write logic for AI-generated turns.

That service holds the service-role key, which bypasses RLS, so it does the
authorisation the database no longer can: every request carries the caller's
Supabase token and the chat must be theirs. See `../thoughtloom_backend/README.md`.

Everything the app persists goes through two interfaces, `AuthService` and
`DataService` (`lib/services/`). Each has a Supabase implementation and an
on-device one, chosen once at startup by `Backend.init()`. Screens depend only
on the interfaces, so swapping providers does not reach the UI.

```
lib/
  config/       build-time configuration
  models/       plain data classes, one per table
  data/         question sets
  services/
    auth_service.dart   interface
    data_service.dart   interface
    speech_service.dart dictation, with a null implementation
    backend.dart        picks an implementation at startup
    session.dart        signed-in user + profile, via InheritedWidget
    supabase/           Supabase implementations
    local/              on-device implementations
  screens/
    auth_gate.dart          signed-in vs signed-out, onboarding vs dashboard
    onboarding_screen.dart  the one-time basic profile
    dashboard_screen.dart   home: the four categories, and history
    intake_flow_screen.dart the per-category scripted opening
    describe_problem_screen.dart  free text, typed or dictated
    adaptive_flow_screen.dart     the model's own follow-up questions
    recommendation_screen.dart    the answer
    continued_chat_screen.dart    the back-and-forth after it
    history_screen.dart     past chats, and search across them
    chat_transcript_screen.dart   one past chat, read back whole
    profile_screen.dart     everything we know about you, editable
    memory_screen.dart      what the app has concluded about you, verbatim
  widgets/      the design system — buttons, cards, fields, the markdown renderer
supabase/
  schema.sql    tables, triggers, and RLS policies
```

`SessionScope` lives inside `AuthGate`, which is the `home` route — so **pushed
routes cannot read it**; they stack beside it in the navigator rather than
underneath. Screens below the dashboard take what they need through their
constructors instead.

## Onboarding

A first registration lands on a one-time basic profile — fourteen questions, one
per screen, defined in `lib/data/onboarding_questions.dart`. Answers are written
to `user_profiles` as the user goes, so a dropped connection costs one answer
rather than all of them. They are editable afterwards in `profile_screen.dart`.

What a signed-in user sees is decided in one place, by `AuthGate._needsOnboarding`
— the completed flag *and* whether the question list has anything unanswered
left in it. That second half is what lets a question be added later: a returning
user is asked only the ones that did not exist when they signed up, because
`firstUnansweredIndex` tests for a key's presence and a skip is stored as an
explicit null. On the flag alone, a new question would reach new users and
nobody else, forever.

- **false** → the questions, resumed from the first unanswered one
- **true** → straight to the dashboard, never asked again

Every answer lands in the `onboarding_answers` blob; `location`, `age_range`, and
`occupation` are mirrored into their own columns for later queries to filter on.
A skipped optional question is stored as an explicit `null` — that is what stops
resume from asking it again.

Adding a question does not re-prompt users who already finished; the flag
short-circuits before the list is consulted.

## Starting a chat

The dashboard offers the four categories. Picking one creates a `chats` row and
opens that category's scripted questions — four or five, one per screen, defined
in `lib/data/intake_questions.dart`. Each answer is a `messages` row of type
`intake`; the free-text description that ends the flow is one `free_text` row.

The questions are a pure function of `(category, profile)`. Nothing onboarding
already captured is asked again — it is used instead, to word a question, fill an
option list, or drop a question the profile already answers. The coarse reads
that drive this (`educationStageOf`, `partnerStatusOf`, `householdOf`) live in
`lib/data/onboarding_questions.dart`, next to the option strings they match, and
the test suite fails if an option is reworded out from under one.

The scripted part ends there, and the generated part begins.

## The AI half

After the description, the model takes over. It writes its own follow-up
questions with options built for what that person actually said, decides for
itself when it has enough (usually 3-6 questions; 8 is a hard cap), then takes a
position — researching first if the answer turns on real-world facts — and keeps
talking afterwards.

None of that lives in this app. It is `../thoughtloom_backend`, which reads the
chat's context from Supabase with the service-role key and writes the model's
turns back itself. So `AdaptiveFlowScreen`, `RecommendationScreen`, and
`ContinuedChatScreen` make no `DataService` calls at all — they display what the
API returns and send the answer back.

```
describe → adaptive_flow_screen → recommendation_screen → continued_chat_screen
             POST /adaptive-question   POST /recommendation   POST /follow-up
                                            ↓ leaving, from either screen
                                       POST /complete-chat
```

## History, and what carries between chats

Leaving a chat closes it — see `lib/services/chat_completion.dart`. The status
write is direct Flutter → Supabase; naming the chat and folding what it taught
us into `user_memory` are the API's, and are *not waited for*: the user pressed
Back, and the work happens server-side once the request lands, whether or not
this app is still running.

Everything after that is a direct read under RLS. `HistoryScreen` lists chats
newest-first and searches them — by title, and by what was actually said in them,
across every message type. There is no endpoint for it: the policies already
scope every row to its owner, so routing the user's own chats through a service
holding a key that *bypasses* those policies would add an authorisation problem
in order to solve nothing.

What a tap does follows from `status`, and the question it answers is "did this
chat ever produce advice?" — `awaiting_follow_up` and `completed` both did, so
both carry on the conversation (`ContinuedChatScreen` reopens a completed one
properly, and links to the full transcript); `in_progress` never did, so there is
nothing to continue and it opens read-only.

It used to be `awaiting_follow_up` resumes and *anything else* opens read-only,
which made `completed` — the status of every chat anyone ever finished properly —
a dead end.

The memory those chats build reaches the next one through the backend's context
assembly, not through this app. **A first-time user is unaffected by all of it**
— see `tests/test_context.py` there.

`AiService` (`lib/services/ai_service.dart`) is the only thing that talks to it.
`AiFailure` carries `retryable`, which is what decides whether a screen offers a
retry: a cold Render dyno is worth another go, being signed out is not.

**This needs Supabase.** The API reads its context from there and authorises by
the Supabase token, so the on-device backend cannot support it — the screens
check `Backend.usingSupabase` and say so plainly rather than letting a call fail
with a network error.

**A chat is only `completed` when the user leaves it.** The API sets
`awaiting_follow_up` when the recommendation lands, because they can still push
back. Leaving writes `completed` directly from Flutter — it is a status flag on
a row the user owns, so RLS covers it and the API is not involved.

### Voice

Every text input in the AI flow takes dictation, via `DictationController`
(`lib/widgets/dictation.dart`). Same failure rule as the describe screen: no
recogniser means no mic button, never a broken one.

### Dictation

The describe-your-problem screen takes typing or speech, via `speech_to_text`.
Speech writes into the same field as the keyboard, so the two mix freely.

Dictation fails soft: no recogniser, a denied microphone, or a platform without
the plugin means the mic button is never offered, and the text field works as
normal. The microphone permission is requested on reaching that screen, not at
launch. Android needs `RECORD_AUDIO` plus the `RecognitionService` queries entry;
iOS needs `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`.
All four are already in the manifests.

## Tests

```bash
flutter test
```

`local_backend_test.dart` asserts the contract both backends share — sequence
numbering, activity ordering, the memory split, cascade-on-delete — so the same
expectations hold whichever one is selected.

`onboarding_test.dart` drives the basic profile end to end: that answers reach
the database one at a time rather than in a batch at the end, that an
interrupted run resumes where it stopped, and that a finished profile is never
asked again.

`intake_flow_test.dart` drives a category flow end to end and then asserts the
database rather than the UI — row count, `seq` order, message types — because
that is the contract the adaptive questioning reads back.

`render_test.dart` is the layout pass: profile, memory, and a fully-marked-up
recommendation at 360×780 and 320×568, scrolled to the bottom, asserting the
render raised nothing.

Note: Inter ships in the bundle now, but `flutter test` does not register a
pubspec font without a `FontLoader`, so text under test is still measured in a
fallback whose glyphs are wider than the real thing. That cuts one way — anything
that fits under test fits on a device — but it also means a tap whose offset
misses only *warns* and then dispatches anyway, pressing whatever is really
there. Always `ensureVisible` before tapping an option.
