# HORIZON connection widgets

Home Screen: add the small HORIZON VPN widget. Control Center: Edit → Add a Control → HORIZON VPN. iOS manages placement; the app does not add controls automatically. Existing Live Activity remains in the same WidgetBundle.

Both surfaces use SetVPNConnectionIntent with an explicit desired Boolean. iOS 26 dynamic foreground continuation supports ordinary background actions and bringing the app forward when setup/consent is required. Device authentication is required. No new subscription or permission is silently approved.

The host service reuses TunnelController's configuration validation, certificate consent, profile reactivation and startup recovery. It serializes widget actions, checks real system status, and waits for completion within a bounded interval. Disconnect reloads only HORIZON's manager and remains possible when subscription parsing fails. Other providers are never selected by this action.

App Group `group.Kenote.Clash.widgets` is needed for app, PacketTunnel and widget extension distribution profiles. Shared presentation data contains only phase, subscription display name and timestamp. No source URL, credentials or configuration payload is copied. The subscription label is privacySensitive.

App status changes and provider start/stop publish state and request WidgetKit/ControlCenter reloads. System scheduling can delay presentation; these are not continuous real-time displays. An abrupt provider termination or system-level change may leave the cached presentation stale until the next app refresh. Each action checks actual state before execution and does not blindly invert the live connection.

Validation: simulator state/setup-boundary tests and VPNProfileActivation regressions; signed device build. Still requires device acceptance: add each surface, connect/disconnect with app in background/terminated, reject locked-device authentication, missing configuration/profile, unapproved certificates, use another VPN then reconnect, and state/error appearance. Do not interpret a successful build as background execution or animation acceptance.

Rollback snapshot of previously existing files: build/rollback/before-connection-widgets/. New widget, intent/service, catalog, entitlement, shared state, tests and this document are additions. Preserve later edits if rolling back.

Widget actions also conform to LiveActivityIntent, allowing ActivityKit creation from the user-triggered background invocation. Successful connect (including an already-connected request) explicitly synchronizes the shared VPNLiveActivityController with current settings; confirmed disconnect/no profile explicitly ends live activities. Foreground and intent synchronization are serialized, with an end-generation guard against creating an activity after a concurrent stop. ActivityKit authorization and the user's Live Activity setting still apply. Device validation is required for background activity creation.
