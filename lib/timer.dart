import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:typed_data';
class AlarmSchedule {
  final int id;
  final TimeOfDay time;
  final List<bool> days;
  bool isEnabled;

  AlarmSchedule({
    required this.id,
    required this.time,
    required this.days,
    this.isEnabled = true,
  });

  // JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': {'hour': time.hour, 'minute': time.minute},
      'days': days,
      'isEnabled': isEnabled,
    };
  }

  // JSON에서 객체로 변환
  factory AlarmSchedule.fromJson(Map<String, dynamic> json) {
    final time = json['time'];
    return AlarmSchedule(
      id: json['id'],
      time: TimeOfDay(hour: time['hour'], minute: time['minute']),
      days: List<bool>.from(json['days']),
      isEnabled: json['isEnabled'],
    );
  }
}

class TimerScreen extends StatefulWidget {
  @override
  TimerScreenState createState() => TimerScreenState();
}

class TimerScreenState extends State<TimerScreen> {
  List<AlarmSchedule> alarms = [];
  List<bool> selectedDays = List.generate(7, (index) => false);
  TimeOfDay selectedTime = TimeOfDay.now();

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadAlarms();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    var androidInitialize = AndroidInitializationSettings('app_icon');
    var initializationSettings = InitializationSettings(
      android: androidInitialize,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  // TimeOfDay를 TZDateTime으로 변환하는 함수
  tz.TZDateTime _convertToTZDateTime(TimeOfDay timeOfDay) {
    final now = tz.TZDateTime.now(tz.local);
    return tz.TZDateTime(tz.local, now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
  }

  // 알람을 예약하는 함수
  Future<void> _scheduleNotification(AlarmSchedule alarm) async {
    var androidDetails = AndroidNotificationDetails(
      'alarm_channel_id',
      'Alarm Notifications',
      channelDescription: 'Channel for alarm notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: '알람이 울립니다!',
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 1000]), // 진동 패턴 설정
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    // 알림에 BigText 스타일 적용
    var bigTextStyleInformation = BigTextStyleInformation(
      '지금은 지하철이 도착하는 시간입니다! \n설정된 시간과 요일에 맞춰 알림을 받습니다.',
      contentTitle: '알람: ${alarm.time.format(context)}',
      htmlFormatContent: true,
    );

    // 새로 AndroidNotificationDetails를 생성하여 styleInformation을 적용
    var notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'alarm_channel_id',
        'Alarm Notifications',
        channelDescription: 'Channel for alarm notifications',
        importance: Importance.max,
        priority: Priority.high,
        ticker: '알람이 울립니다!',
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 1000]), // 진동 패턴 설정
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: bigTextStyleInformation, // 스타일 적용
      ),
    );

    // 정확한 시간에 알림을 예약
    await flutterLocalNotificationsPlugin.zonedSchedule(
      alarm.id,
      '알림 제목',
      '알림 내용',
      _convertToTZDateTime(alarm.time), // 예약 시간
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exact, // 정확한 시간에 알림 예약
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.wallClockTime,
    );
  }

  // 알람을 취소하는 함수
  Future<void> _cancelNotification(int alarmId) async {
    await flutterLocalNotificationsPlugin.cancel(alarmId);
  }

  // 알람을 SharedPreferences에 저장
  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final String alarmsJson = jsonEncode(alarms.map((a) => a.toJson()).toList());
    await prefs.setString('alarms', alarmsJson);
  }

  // SharedPreferences에서 알람 불러오기
  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final String? alarmsJson = prefs.getString('alarms');
    if (alarmsJson != null) {
      final List<dynamic> decoded = jsonDecode(alarmsJson);
      setState(() {
        alarms = decoded.map((item) => AlarmSchedule.fromJson(item)).toList();
      });
    }
  }

  // 알람을 추가하는 함수
  Future<void> _addAlarm() async {
    if (selectedDays.every((day) => !day)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('최소 하나의 요일을 선택해주세요')),
      );
      return;
    }

    final newAlarm = AlarmSchedule(
      id: DateTime.now().microsecondsSinceEpoch,
      time: selectedTime,
      days: List.from(selectedDays),
      isEnabled: true,
    );

    setState(() {
      alarms.add(newAlarm);
      selectedDays = List.generate(7, (index) => false);
    });

    await _scheduleNotification(newAlarm);
    await _saveAlarms();
  }

  // 알람을 삭제하는 함수
  Future<void> _deleteAlarm(int index) async {
    _cancelNotification(alarms[index].id);
    setState(() {
      alarms.removeAt(index);
    });
    await _saveAlarms();
  }

  // 알람을 활성화/비활성화하는 함수
  Future<void> _toggleAlarm(int index, bool value) async {
    setState(() {
      alarms[index].isEnabled = value;
    });

    if (value) {
      await _scheduleNotification(alarms[index]);
    } else {
      _cancelNotification(alarms[index].id);
    }
    await _saveAlarms();
  }

  // 알람의 요일 텍스트 반환
  String _getDaysText(List<bool> days) {
    final List<String> dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final List<String> selectedDays = [];

    for (int i = 0; i < days.length; i++) {
      if (days[i]) selectedDays.add(dayNames[i]);
    }

    return selectedDays.join(', ');
  }

  // 알람 추가 다이얼로그
  void _showAddAlarmDialog() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time != null) {
      selectedTime = time;
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text('요일 선택'),
              content: Container(
                width: double.maxFinite,
                child: Wrap(
                  spacing: 5,
                  children: [
                    for (int i = 0; i < 7; i++)
                      FilterChip(
                        label: Text(['월', '화', '수', '목', '금', '토', '일'][i]),
                        selected: selectedDays[i],
                        onSelected: (bool selected) {
                          setState(() {
                            selectedDays[i] = selected;
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: Text('취소'),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: Text('저장'),
                  onPressed: () {
                    Navigator.pop(context);
                    _addAlarm();
                  },
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black;
    final Color cardColor = isDarkMode ? Colors.grey[800]! : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text('알림 설정'),
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Expanded(
            child: alarms.isEmpty
                ? Center(
              child: Text(
                '설정된 알림이 없습니다.\n+ 버튼을 눌러 알림을 추가하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            )
                : ListView.builder(
              itemCount: alarms.length,
              itemBuilder: (context, index) {
                final alarm = alarms[index];
                return Card(
                  color: cardColor,
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 2,
                  child: ListTile(
                    title: Text(
                      '${alarm.time.format(context)} (${_getDaysText(alarm.days)})',
                      style: TextStyle(color: textColor),
                    ),
                    subtitle: Text(
                      alarm.isEnabled ? '활성화됨' : '비활성화됨',
                      style: TextStyle(color: textColor),
                    ),
                    trailing: Switch(
                      value: alarm.isEnabled,
                      onChanged: (value) => _toggleAlarm(index, value),
                    ),
                    onLongPress: () => _deleteAlarm(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddAlarmDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}
