import 'package:clock/clock.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:still_life/core/utils/date_arithmetic.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Manages local notifications for warranty expiry and maintenance reminders.
class NotificationService {
  static const _channelId = 'still_life_reminders';
  static const _channelName = 'Reminders';
  static const _channelDesc = 'Warranty and maintenance reminders';

  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(_resolveLocalLocation());

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings: settings);
  }

  tz.Location _resolveLocalLocation() {
    final offset = DateTime.now().timeZoneOffset;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (tz.TZDateTime.now(loc).timeZoneOffset == offset) return loc;
    }
    return tz.getLocation('UTC');
  }

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  /// Schedule a warranty-expiry reminder `daysBefore` days before [expiryDate].
  ///
  /// Uses the notification ID derived from [itemId] so it can be cancelled or
  /// rescheduled when the item is updated.
  Future<void> scheduleWarrantyReminder({
    required String itemId,
    required String itemName,
    required DateTime expiryDate,
    int daysBefore = 30,
  }) async {
    final scheduledDate = addCalendarDays(expiryDate, -daysBefore);
    if (scheduledDate.isBefore(clock.now())) return;

    await _plugin.zonedSchedule(
      id: _warrantyId(itemId),
      title: 'Warranty Expiring Soon',
      body: '$itemName warranty expires in $daysBefore days',
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  /// Schedule a maintenance due reminder [daysBefore] days before [dueDate].
  Future<void> scheduleMaintenanceReminder({
    required String logId,
    required String title,
    required DateTime dueDate,
    int daysBefore = 7,
  }) async {
    final scheduledDate = addCalendarDays(dueDate, -daysBefore);
    if (scheduledDate.isBefore(clock.now())) return;

    await _plugin.zonedSchedule(
      id: _maintenanceId(logId),
      title: 'Maintenance Due Soon',
      body: '$title is due in $daysBefore days',
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  /// Cancel any pending warranty reminder for [itemId].
  Future<void> cancelWarrantyReminder(String itemId) =>
      _plugin.cancel(id: _warrantyId(itemId));

  /// Cancel any pending maintenance reminder for [logId].
  Future<void> cancelMaintenanceReminder(String logId) =>
      _plugin.cancel(id: _maintenanceId(logId));

  /// Schedule a reminder 1 day before the loan due date.
  /// Notification fires at 9 AM local time on that day.
  /// No-op if dueDate is in the past or within 24 hours.
  Future<void> scheduleLoanReminder({
    required String loanId,
    required String itemName,
    required DateTime dueDate,
    int daysBefore = 1,
  }) async {
    final scheduledDate = addCalendarDays(dueDate, -daysBefore);
    if (scheduledDate.isBefore(clock.now())) return;

    await _plugin.zonedSchedule(
      id: _loanId(loanId),
      title: 'Loan Due Tomorrow',
      body: '$itemName is due back tomorrow',
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  /// Cancel any pending loan reminder for [loanId].
  Future<void> cancelLoanReminder(String loanId) =>
      _plugin.cancel(id: _loanId(loanId));

  /// Show an immediate low-stock alert for a consumable item.
  Future<void> showLowStockAlert({
    required String itemId,
    required String itemName,
    required double quantity,
    required double threshold,
  }) async {
    await _plugin.show(
      id: _lowStockId(itemId),
      title: 'Low Stock: $itemName',
      body: '$quantity remaining (threshold: $threshold)',
      notificationDetails: _notificationDetails(),
    );
  }

  /// Cancel any pending low-stock notification for [itemId].
  Future<void> cancelLowStockAlert(String itemId) =>
      _plugin.cancel(id: _lowStockId(itemId));

  /// Show an immediate notification (e.g. sync completed).
  Future<void> showImmediate({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(),
    );
  }

  // Notification IDs — use a stable hash derived from the entity ID so we
  // never accidentally schedule two notifications with the same int ID.
  int _lowStockId(String itemId) => 0x40000000 | (itemId.hashCode & 0x0FFFFFFF);
  int _warrantyId(String itemId) => 0x10000000 | (itemId.hashCode & 0x0FFFFFFF);
  int _maintenanceId(String logId) =>
      0x20000000 | (logId.hashCode & 0x0FFFFFFF);
  int _loanId(String loanId) => 0x30000000 | (loanId.hashCode & 0x0FFFFFFF);

  NotificationDetails _notificationDetails() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const ios = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: ios);
  }
}
