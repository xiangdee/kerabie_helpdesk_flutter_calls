import 'dart:async';

/// Shows a screen the AI agent asked for and returns the customer's answer, which the agent reads back:
///
/// - `show_items` returns the tapped item id, or `none`
/// - `pick_saved_address` returns the chosen address id, or `none` to type a new one
/// - `request_address_input` returns the typed address
/// - `confirm_action` returns `yes` or `no`
/// - `pick_schedule` returns an ISO 8601 date and time with the timezone
/// - `open_screen` returns `opened`
///
/// Throw when the customer closes it: the agent is then told the customer did not answer.
typedef KerabieScreenHandler = Future<String> Function(Map<String, dynamic> payload);

/// Something the app does for the agent on the device, such as adding to the app's own cart or starting its checkout.
/// The agent sees it as a tool named `action_<name>`, calls it with the arguments you describe, and tells the customer
/// what [run] returned.
class KerabieAgentAction {
  const KerabieAgentAction({required this.description, this.parameters, required this.run});

  /// When the agent should use it (10 characters or more).
  final String description;

  /// The inputs as JSON Schema (`{'type': 'object', 'properties': {...}, 'required': [...]}`). Null for an action that takes none.
  final Map<String, dynamic>? parameters;

  /// Runs it in the app and returns a short result the agent can say ("Added 2 x Ofada rice"). Throw to tell the agent it failed.
  final Future<String> Function(Map<String, dynamic> args) run;
}

/// What the AI agent needs from the app: who the customer is, and the screens the app can show.
class KerabieAgentOptions {
  const KerabieAgentOptions({this.getUserToken, this.screens = const {}, this.actions = const {}});

  /// Returns the signed-in customer's token (the one your own API accepts), or null when nobody is signed in.
  /// Sent to your tools as `X-Kerabie-User-Token`; kept encrypted for the call and never shown to the AI.
  final FutureOr<String?> Function()? getUserToken;

  /// The screens the agent may ask for, by name. The agent only uses the ones listed here.
  final Map<String, KerabieScreenHandler> screens;

  /// What the app can do for the agent on the device, by snake_case name (for example `add_to_cart`).
  final Map<String, KerabieAgentAction> actions;

  /// The actions described for the server: name, description and parameters.
  List<Map<String, dynamic>> describeActions() => [
        for (final e in actions.entries)
          {'name': e.key, 'description': e.value.description, if (e.value.parameters != null) 'parameters': e.value.parameters},
      ];

  /// The token, or null. A token that cannot be read means nobody is signed in, never a failed call.
  Future<String?> readUserToken() async {
    try {
      final token = await getUserToken?.call();
      return token == null || token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }
}
